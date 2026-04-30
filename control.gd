extends Node2D

@onready var start_btn = $CenterContainer/VBoxContainer/Start
@onready var quit_btn  = $CenterContainer/VBoxContainer/Quit

var anim_time  := 0.0    # total seconds elapsed since the screen appeared
var anim_count := 0      # how many numbers of the spiral to draw (grows from 0 on load)
var fade_in    := 0.0    # 0..1, drives the overall opacity of everything as it fades in

# audio, tiny self-contained synth just for the menu screen click sounds
var player      : AudioStreamPlayer
var playback
var audio_phase := 0.0    # oscillator phase 0..1
var audio_freq  := 0.0    # frequency to play (0 = silent)
var audio_env   := 0.0    # simple linear decay envelope, 1 = full, 0 = silent
const SAMPLE_RATE = 44100.0

# list of prime dot positions updated each draw, used for click detection
var dot_positions : Array = []

func _ready():
	start_btn.pressed.connect(_start)
	quit_btn.pressed.connect(_quit)
	start_btn.text = "PLAY"
	quit_btn.text  = "QUIT"

	# set the title if it exists in the scene tree
	if $CenterContainer/VBoxContainer.has_node("Title"):
		var t = $CenterContainer/VBoxContainer/Title
		t.text = "PRIME SPIRAL SYNTH"
		t.add_theme_font_size_override("font_size", 28)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# set the subtitle if it exists
	if $CenterContainer/VBoxContainer.has_node("Subtitle"):
		var s = $CenterContainer/VBoxContainer/Subtitle
		s.text = "Hearing Hidden Mathematics"
		s.add_theme_font_size_override("font_size", 13)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# make the buttons a consistent size regardless of text length
	start_btn.custom_minimum_size = Vector2(180, 48)
	quit_btn.custom_minimum_size  = Vector2(180, 40)

	_setup_audio()

func _setup_audio():
	# same generator setup as Synth.gd but much simpler, just one sine oscillator
	var stream = AudioStreamGenerator.new()
	stream.mix_rate     = SAMPLE_RATE
	stream.buffer_length = 0.1
	player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	playback = player.get_stream_playback()

func _play_tone(f: float):
	# start a new note, reset phase so there's no click from mid-cycle
	audio_freq  = f
	audio_env   = 1.0
	audio_phase = 0.0

func _update_audio(delta: float):
	if playback == null or audio_freq <= 0.0:
		return
	audio_env = max(0.0, audio_env - delta * 1.8)   # fast linear decay, notes are short
	var frames = playback.get_frames_available()
	for i in range(frames):
		var s = sin(TAU * audio_phase) * audio_env * 0.38   # 0.38 keeps it comfortably quiet
		audio_phase += audio_freq / SAMPLE_RATE
		if audio_phase >= 1.0: audio_phase -= 1.0
		playback.push_frame(Vector2(s, s))

func _start():
	get_tree().change_scene_to_file("res://main.tscn")

func _quit():
	get_tree().quit()

func _input(event):
	if event is InputEventKey and event.pressed:
		# Enter or Space on the keyboard also starts the game
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_start()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_check_dot_click(event.position)

func _check_dot_click(mouse_pos: Vector2):
	# if the player clicks near a prime dot on the decorative spiral, play its note
	for dot in dot_positions:
		if mouse_pos.distance_to(dot["pos"]) < 8.0:
			var n         = dot["prime"]
			# map prime to a scale degree and octave the same way Synth does
			var semitones = [0, 2, 4, 5, 7, 9, 11]   # major scale
			var semitone  = semitones[n % 7]
			var octave    = 3 + (n % 3)
			var midi      = 12 + octave * 12 + semitone
			_play_tone(440.0 * pow(2.0, (midi - 69) / 12.0))
			return   # only play one note per click

func _is_prime(n: int) -> bool:
	# local copy of the primality test, avoids a dependency on Spiral just for the menu
	if n < 2: return false
	if n == 2: return true
	if n % 2 == 0: return false
	for i in range(3, int(sqrt(float(n))) + 1, 2):
		if n % i == 0: return false
	return true

func _process(delta):
	anim_time  += delta
	fade_in     = clamp(fade_in + delta * 0.7, 0.0, 1.0)   # takes ~1.4 seconds to fully appear
	anim_count  = min(anim_count + 2, 400)   # reveal 2 more numbers per frame until 400
	_update_audio(delta)
	queue_redraw()   # animate every frame

func _draw():
	var vp     = get_viewport_rect().size
	var center = vp / 2.0   # spiral starts from screen centre

	# very dark blue background
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.03, 0.06))

	# walk the Ulam spiral exactly like the main game does
	var pos       = center
	var dir       = Vector2.RIGHT
	var steps_t   = 0
	var step_size = 1
	var turns     = 0
	var number    = 1
	var cell      = 16.0   # slightly larger cells than the main game for a bolder look

	dot_positions.clear()   # rebuild click targets every draw so they match what's on screen

	while number <= anim_count:
		if _is_prime(number):
			var hue     = float(number % 7) / 7.0
			var wobble  = sin(anim_time * 0.6 + number * 0.15) * 1.8   # gentle sway animation
			var dot_pos = pos + Vector2(wobble, wobble * 0.5)            # wobble more on X than Y
			var bright  = 0.45 + 0.25 * sin(anim_time * 1.2 + float(number) * 0.4)  # breathing brightness
			var col     = Color.from_hsv(hue, 0.7, bright, fade_in * 0.9)

			# soft outer glow ring
			draw_circle(dot_pos, 5.0, Color(col.r, col.g, col.b, col.a * 0.18))
			# main dot
			draw_circle(dot_pos, 2.5, col)

			# register this dot so _check_dot_click can detect it
			dot_positions.append({"pos": dot_pos, "prime": number})
		else:
			# composite numbers get a tiny dim dot so you can see the spiral grid
			draw_circle(pos, 1.0, Color(0.1, 0.1, 0.14, fade_in * 0.35))

		# advance along the spiral path, same algorithm as Spiral.gd
		pos     += dir * cell
		number  += 1
		steps_t += 1
		if steps_t >= step_size:
			steps_t = 0
			dir     = Vector2(-dir.y, dir.x)   # 90-degree left turn
			turns  += 1
			if turns % 2 == 0:
				step_size += 1   # every two turns the run length grows by one

	# two faint horizontal lines to frame the UI buttons in the centre
	var la = fade_in * 0.14   # very subtle so they don't distract
	draw_line(Vector2(vp.x * 0.18, vp.y * 0.38), Vector2(vp.x * 0.82, vp.y * 0.38),
		Color(0.4, 0.6, 1.0, la), 1.0)
	draw_line(Vector2(vp.x * 0.18, vp.y * 0.65), Vector2(vp.x * 0.82, vp.y * 0.65),
		Color(0.4, 0.6, 1.0, la), 1.0)

	# tagline fades in 1.5 seconds after everything else, so it feels like a reveal
	var ta = clamp((anim_time - 1.5) * 0.5, 0.0, 1.0) * 0.5
	draw_string(ThemeDB.fallback_font,
		Vector2(vp.x / 2.0 - 96, vp.y - 26),
		"Numbers are not silent.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.7, 1.0, ta))
	draw_string(ThemeDB.fallback_font,
		Vector2(vp.x / 2.0 - 96, vp.y - 10),
		"click the spiral to hear it  ·  ENTER to start",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, ta * 0.6))   # slightly dimmer than the tagline
