class_name Synth
extends Node

# sgnals 
# fired every time a prime is turned into a sound, so the UI can react
signal note_triggered(prime: int, note_name: String, freq: float)

#constants
# standard CD-quality sample rate, how many audio samples we push per second
const SAMPLE_RATE := 44100.0

#public state 
var wave_mode    := 0          # which waveform shape: 0 sine  1 square  2 saw
var drone_on     := false      # whether the continuous low bass drone is active
var volume       := 0.5        # master output level, driven by the UI slider
var current_note := ""         # human-readable note name e.g. "C#4", set when a prime plays

# scales
var current_scale := 0   # index into SCALE_NAMES, cycles when the player presses Scale
const SCALE_NAMES  = ["MAJOR", "MINOR", "PENTATONIC", "CHROMATIC", "RANDOM"]
# each entry lists the semitone intervals that form that scale
const SCALES = {
	"MAJOR":      [0, 2, 4, 5, 7, 9, 11],
	"MINOR":      [0, 2, 3, 5, 7, 8, 10],
	"PENTATONIC": [0, 2, 4, 7, 9],
	"CHROMATIC":  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
	"RANDOM":     []   # filled procedurally in _prime_to_freq
}

#private audio state
var _player   : AudioStreamPlayer
var _playback   # the stream playback object we push raw samples into

# phase accumulators, each one tracks where we are in a 0..1 cycle for its oscillator
var _phase       := 0.0   # main oscillator
var _phase2      := 0.0   # harmony oscillator (fifth)
var _phase3      := 0.0   # harmony oscillator (third)
var _drone_phase := 0.0   # the low continuous drone oscillator

# frequencies for each active oscillator (0.0 means silent)
var _freq  := 220.0
var _freq2 := 0.0
var _freq3 := 0.0
var _drone_freq := 55.0   # drone is always two octaves below the main note

#controls how the sound fades in and out after each prime plays
var _env_attack  := 0.01   # seconds to ramp from silence to full volume
var _env_release := 0.3    # seconds to fade back to silence
var _env_time    := 0.0    # how long we've been in the current envelope stage
var _env_state   := "off"  # current stage: "attack", "sustain", "release", "off"
var _env_val     := 0.0    # current envelope amplitude 0.0..1.0

# circular delay buffer, stores recent samples and feeds them back for echo
var _delay_buffer : Array = []
var _delay_index  := 0       # current write head position
var _delay_samples := 0      # buffer length in samples (set from delay time in seconds)
var _delay_mix     := 0.25   # how loud the echo repeat is relative to the dry signal

# whether to add the fifth and third on top of the root note
var chord_mode := false


#setup
func setup(parent: Node) -> void:
	# create the audio generator stream with our sample rate and a short buffer
	var stream = AudioStreamGenerator.new()
	stream.mix_rate     = SAMPLE_RATE
	stream.buffer_length = 0.15   # 150 ms, short enough for low latency

	_player = AudioStreamPlayer.new()
	_player.stream = stream
	parent.add_child(_player)   # must be in the scene tree before we can play
	_player.play()
	_playback = _player.get_stream_playback()   # this is what pushes raw samples into

	# pre-allocate the delay buffer so we're not resizing it every frame
	_delay_samples = int(SAMPLE_RATE * 0.22)   # 220 ms delay time
	_delay_buffer.resize(_delay_samples)
	_delay_buffer.fill(0.0)


# Play a prime number as a musical note.
func play_prime(prime: int, mode: int) -> void:
	_freq = _prime_to_freq(prime)   # map the prime's value to a musical frequency

	match mode:
		2, 7:                        # harmonic / duet is stack a fifth and a major third on top
			_freq2 = _freq * 1.5
			_freq3 = _freq * 1.25
		6:                           # drum mode, replace pitch with a short thuddy low tone
			_freq  = 80.0 + float(prime % 8) * 20.0   # prime gives slight pitch variation
			_freq2 = 0.0
			_freq3 = 0.0
		_:
			_freq2 = 0.0   # all other modes play a single note
			_freq3 = 0.0

	if mode == 1:
		_freq *= randf_range(0.98, 1.02)   # chaos mode: tiny random detune for a wobbly feel

	_drone_freq = _freq * 0.25   # drone sits two octaves below whatever we just set
	_trigger_note()              # restart the envelope from the top
	_delay_mix = 0.0 if mode == 1 else 0.25   # chaos gets no echo, it's already messy enough

	emit_signal("note_triggered", prime, current_note, _freq)


func apply_mode(mode: int) -> void:
	# each mode has its own sonic character: attack/release times shape whether it
	# sounds punchy, smooth, plucked, or swelling
	match mode:
		0: wave_mode = 0; _env_attack = 0.01;  _env_release = 0.3    # default: warm sine, medium decay
		1: wave_mode = 2; _env_attack = 0.005; _env_release = 0.1    # chaos: sharp saw, very short
		2: wave_mode = 0; _env_attack = 0.02;  _env_release = 0.5    # harmonic: sine, longer tail
		3: wave_mode = 0; _env_attack = 0.05;  _env_release = 0.9    # ambient: slow swell, long fade
		4: wave_mode = 0; _env_attack = 0.01;  _env_release = 0.4    # constellation: snappy, medium
		5: wave_mode = 2; _env_attack = 0.01;  _env_release = 0.2    # fractal: saw, punchy
		6: wave_mode = 1; _env_attack = 0.003; _env_release = 0.08   # drum: square, very snappy thud
		7: wave_mode = 0; _env_attack = 0.02;  _env_release = 0.6    # duet: sine, slightly longer

func update(delta: float, is_active: bool) -> void:
	if _playback == null:
		return
	# if nothing is playing and the envelope is off, output silence rather than skipping
	var vol    = volume if (is_active or _env_state != "off") else 0.0
	var frames = _playback.get_frames_available()   # how many samples the audio driver needs right now
	var dt     = delta / float(max(frames, 1))       # time step per sample

	for _i in range(frames):
		var ev = _update_envelope(dt)                    # get current amplitude from envelope
		var s  = _osc(_phase, wave_mode) * ev * vol     # main oscillator sample

		if chord_mode and _freq2 > 0.0:
			# mix the fifth and third in at lower volumes so they support without overwhelming
			s += _osc(_phase2, 0) * ev * vol * 0.4   # fifth is fairly prominent
			s += _osc(_phase3, 0) * ev * vol * 0.2   # third is quieter, just adds colour
			_phase2 += _freq2 / SAMPLE_RATE
			_phase3 += _freq3 / SAMPLE_RATE
			if _phase2 >= 1.0: _phase2 -= 1.0   # keep phase in 0 1 range
			if _phase3 >= 1.0: _phase3 -= 1.0

		if drone_on:
			# add a constant low sine wave underneath everything, always a pure sine regardless of wave_mode
			_drone_phase += _drone_freq / SAMPLE_RATE
			if _drone_phase >= 1.0: _drone_phase -= 1.0
			s += sin(TAU * _drone_phase) * vol * 0.15   # quiet enough to be felt rather than heard

		_phase += _freq / SAMPLE_RATE
		if _phase >= 1.0: _phase -= 1.0   # wrap phase so it never grows forever

		# read from the delay buffer, mix the echo in, then write the current sample
		var delayed = _delay_buffer[_delay_index] * _delay_mix
		_delay_buffer[_delay_index] = s
		_delay_index = (_delay_index + 1) % _delay_samples
		s = clamp(s + delayed, -1.0, 1.0)   # clamp so we never clip the audio output
		_playback.push_frame(Vector2(s, s))  # stereo: same sample on both channels


# Release the envelope (call when note should fade out).
func release() -> void:
	if _env_state == "sustain":
		_env_state = "release"
		_env_time  = 0.0


# Returns true while the envelope hasn't gone silent yet.
func is_sounding() -> bool:
	return _env_state != "off"


func _trigger_note() -> void:
	# jump straight to attack  resets any previous envelope in progress
	_env_state = "attack"
	_env_time  = 0.0


func _update_envelope(dt: float) -> float:
	_env_time += dt
	match _env_state:
		"attack":
			# ramp linearly from 0 to 1 over the attack duration
			_env_val = clamp(_env_time / _env_attack, 0.0, 1.0)
			if _env_time >= _env_attack:
				_env_state = "sustain"
				_env_time  = 0.0
		"sustain":
			_env_val = 1.0   # hold at full volume until release() is called
		"release":
			# ramp linearly from 1 down to 0 over the release duration
			_env_val = clamp(1.0 - _env_time / _env_release, 0.0, 1.0)
			if _env_time >= _env_release:
				_env_state = "off"
				_env_val   = 0.0
		"off":
			_env_val = 0.0   # completely silent
	return _env_val


func _osc(p: float, wm: int) -> float:
	# generate one sample from the chosen waveform shape, given phase 0..1
	match wm:
		0: return sin(TAU * p)               # sine: smooth, warm
		1: return 1.0 if p < 0.5 else -1.0  # square: harsh, buzzy, great for drums
		2: return p * 2.0 - 1.0             # sawtooth: bright, aggressive
	return 0.0   # fallback silence if wm is somehow out of range


func _prime_to_freq(n: int) -> float:
	var scale_key = SCALE_NAMES[current_scale]
	var intervals : Array

	if scale_key == "RANDOM":
		# build a fresh random-ish scale each time, still vaguely musical
		intervals = [0, randi_range(1,2), randi_range(3,4),
					 randi_range(5,6), randi_range(7,8), randi_range(9,10), 11]
	else:
		intervals = SCALES[scale_key]

	# use modulo to pick which scale degree this prime maps to
	var idx      = n % intervals.size()
	var semitone = intervals[idx]
	# use modulo again to pick the octave,primes cycle through octaves 3, 4, 5
	var octave   = 3 + (n % 3)

	# build the human-readable note name e.g. "F#4"
	var names    = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
	current_note = names[semitone] + str(octave)

	# convert to MIDI note number then to Hz using the standard equal temperament formula
	var midi = 12 + octave * 12 + semitone
	return 440.0 * pow(2.0, (midi - 69) / 12.0)
