# Synth.gd
# Attach to an AudioStreamPlayer node named "Synth" in your scene.
# Handles all audio: oscillators, ADSR envelope, delay, drone.
# Communicates outward only through signals — no UI references here.

class_name Synth
extends Node

# ── signals ──────────────────────────────────────────────────────────────────
signal note_triggered(prime: int, note_name: String, freq: float)

# ── constants ────────────────────────────────────────────────────────────────
const SAMPLE_RATE := 44100.0

# ── public state (read by main.gd) ───────────────────────────────────────────
var wave_mode    := 0          # 0 sine  1 square  2 saw
var drone_on     := false
var volume       := 0.5
var current_note := ""

# ── scales ───────────────────────────────────────────────────────────────────
var current_scale := 0
const SCALE_NAMES  = ["MAJOR", "MINOR", "PENTATONIC", "CHROMATIC", "RANDOM"]
const SCALES = {
	"MAJOR":      [0, 2, 4, 5, 7, 9, 11],
	"MINOR":      [0, 2, 3, 5, 7, 8, 10],
	"PENTATONIC": [0, 2, 4, 7, 9],
	"CHROMATIC":  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
	"RANDOM":     []
}

# ── private audio state ───────────────────────────────────────────────────────
var _player   : AudioStreamPlayer
var _playback

var _phase       := 0.0
var _phase2      := 0.0
var _phase3      := 0.0
var _drone_phase := 0.0

var _freq  := 220.0
var _freq2 := 0.0
var _freq3 := 0.0
var _drone_freq := 55.0

# ADSR
var _env_attack  := 0.01
var _env_release := 0.3
var _env_time    := 0.0
var _env_state   := "off"
var _env_val     := 0.0

# delay ring buffer
var _delay_buffer : Array = []
var _delay_index  := 0
var _delay_samples := 0
var _delay_mix     := 0.25

# chord mode flag (set by caller)
var chord_mode := false

# ── setup ─────────────────────────────────────────────────────────────────────
func setup(parent: Node) -> void:
	var stream = AudioStreamGenerator.new()
	stream.mix_rate     = SAMPLE_RATE
	stream.buffer_length = 0.15

	_player = AudioStreamPlayer.new()
	_player.stream = stream
	parent.add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()

	_delay_samples = int(SAMPLE_RATE * 0.22)
	_delay_buffer.resize(_delay_samples)
	_delay_buffer.fill(0.0)


# ── public API ────────────────────────────────────────────────────────────────

## Play a prime number as a musical note.
func play_prime(prime: int, mode: int) -> void:
	_freq = _prime_to_freq(prime)

	match mode:
		2, 7:                        # harmonic / duet — add fifth and third
			_freq2 = _freq * 1.5
			_freq3 = _freq * 1.25
		6:                           # drum — low thud
			_freq  = 80.0 + float(prime % 8) * 20.0
			_freq2 = 0.0
			_freq3 = 0.0
		_:
			_freq2 = 0.0
			_freq3 = 0.0

	if mode == 1:
		_freq *= randf_range(0.98, 1.02)   # chaos detune

	_drone_freq = _freq * 0.25
	_trigger_note()
	_delay_mix = 0.0 if mode == 1 else 0.25

	emit_signal("note_triggered", prime, current_note, _freq)


## Set ADSR and wave shape for a given mode.
func apply_mode(mode: int) -> void:
	match mode:
		0: wave_mode = 0; _env_attack = 0.01;  _env_release = 0.3
		1: wave_mode = 2; _env_attack = 0.005; _env_release = 0.1
		2: wave_mode = 0; _env_attack = 0.02;  _env_release = 0.5
		3: wave_mode = 0; _env_attack = 0.05;  _env_release = 0.9
		4: wave_mode = 0; _env_attack = 0.01;  _env_release = 0.4
		5: wave_mode = 2; _env_attack = 0.01;  _env_release = 0.2
		6: wave_mode = 1; _env_attack = 0.003; _env_release = 0.08
		7: wave_mode = 0; _env_attack = 0.02;  _env_release = 0.6


## Call from _process every frame with current delta.
func update(delta: float, is_active: bool) -> void:
	if _playback == null:
		return
	var vol    = volume if (is_active or _env_state != "off") else 0.0
	var frames = _playback.get_frames_available()
	var dt     = delta / float(max(frames, 1))

	for _i in range(frames):
		var ev = _update_envelope(dt)
		var s  = _osc(_phase, wave_mode) * ev * vol

		if chord_mode and _freq2 > 0.0:
			s += _osc(_phase2, 0) * ev * vol * 0.4
			s += _osc(_phase3, 0) * ev * vol * 0.2
			_phase2 += _freq2 / SAMPLE_RATE
			_phase3 += _freq3 / SAMPLE_RATE
			if _phase2 >= 1.0: _phase2 -= 1.0
			if _phase3 >= 1.0: _phase3 -= 1.0

		if drone_on:
			_drone_phase += _drone_freq / SAMPLE_RATE
			if _drone_phase >= 1.0: _drone_phase -= 1.0
			s += sin(TAU * _drone_phase) * vol * 0.15

		_phase += _freq / SAMPLE_RATE
		if _phase >= 1.0: _phase -= 1.0

		var delayed = _delay_buffer[_delay_index] * _delay_mix
		_delay_buffer[_delay_index] = s
		_delay_index = (_delay_index + 1) % _delay_samples
		s = clamp(s + delayed, -1.0, 1.0)
		_playback.push_frame(Vector2(s, s))


## Release the envelope (call when note should fade out).
func release() -> void:
	if _env_state == "sustain":
		_env_state = "release"
		_env_time  = 0.0


## Returns true while the envelope hasn't gone silent yet.
func is_sounding() -> bool:
	return _env_state != "off"


# ── private helpers ───────────────────────────────────────────────────────────

func _trigger_note() -> void:
	_env_state = "attack"
	_env_time  = 0.0


func _update_envelope(dt: float) -> float:
	_env_time += dt
	match _env_state:
		"attack":
			_env_val = clamp(_env_time / _env_attack, 0.0, 1.0)
			if _env_time >= _env_attack:
				_env_state = "sustain"
				_env_time  = 0.0
		"sustain":
			_env_val = 1.0
		"release":
			_env_val = clamp(1.0 - _env_time / _env_release, 0.0, 1.0)
			if _env_time >= _env_release:
				_env_state = "off"
				_env_val   = 0.0
		"off":
			_env_val = 0.0
	return _env_val


func _osc(p: float, wm: int) -> float:
	match wm:
		0: return sin(TAU * p)
		1: return 1.0 if p < 0.5 else -1.0
		2: return p * 2.0 - 1.0
	return 0.0


func _prime_to_freq(n: int) -> float:
	var scale_key = SCALE_NAMES[current_scale]
	var intervals : Array

	if scale_key == "RANDOM":
		intervals = [0, randi_range(1,2), randi_range(3,4),
					 randi_range(5,6), randi_range(7,8), randi_range(9,10), 11]
	else:
		intervals = SCALES[scale_key]

	var idx      = n % intervals.size()
	var semitone = intervals[idx]
	var octave   = 3 + (n % 3)

	var names    = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
	current_note = names[semitone] + str(octave)

	var midi = 12 + octave * 12 + semitone
	return 440.0 * pow(2.0, (midi - 69) / 12.0)
