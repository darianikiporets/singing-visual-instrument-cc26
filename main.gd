extends Node2D

# =====================================================
# UI NODES
# =====================================================

@onready var note_label    = $CanvasLayer/NoteLabel
@onready var wave_btn      = $CanvasLayer/Wave
@onready var back_btn      = $CanvasLayer/Back
@onready var input_box     = $CanvasLayer/Input
@onready var play_btn      = $CanvasLayer/Play
@onready var random_btn    = $CanvasLayer/Random
@onready var tempo_slider  = $CanvasLayer/Tempo
@onready var volume_slider = $CanvasLayer/Volume

var mode_btn            : Button
var scale_btn           : Button
var drone_btn           : Button
var save_btn            : Button
var rec_btn             : Button
var history_label       : Label
var prime_history_label : Label
var stats_label         : Label
var info_panel          : PanelContainer
var info_visible        := false

# =====================================================
# AUDIO
# =====================================================

var sample_rate  := 44100.0
var phase        := 0.0
var phase2       := 0.0
var phase3       := 0.0
var drone_phase  := 0.0
var freq         := 220.0
var freq2        := 0.0
var freq3        := 0.0
var drone_freq   := 55.0
var drone_on     := false

var player   : AudioStreamPlayer
var playback

var wave_mode := 0
var waves     = ["SINE", "SQUARE", "SAW"]

var env_attack  := 0.01
var env_release := 0.3
var env_time    := 0.0
var env_state   := "off"
var env_val     := 0.0

var delay_buffer  : Array = []
var delay_index   := 0
var DELAY_SAMPLES := 0

# =====================================================
# SCALE SYSTEM
# =====================================================

var current_scale := 0
var scale_names   = ["MAJOR", "MINOR", "PENTATONIC", "CHROMATIC", "RANDOM"]
var scales = {
	"MAJOR":      [0, 2, 4, 5, 7, 9, 11],
	"MINOR":      [0, 2, 3, 5, 7, 8, 10],
	"PENTATONIC": [0, 2, 4, 7, 9],
	"CHROMATIC":  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
	"RANDOM":     []
}

# =====================================================
# SEQUENCE
# =====================================================

var sequence      = []
var step          := 0
var seq_timer     := 0.0
var current_prime := -1
var current_note  := ""
var note_history  : Array = []
var prime_history : Array = []
const HISTORY_MAX = 8
var session_log   : Array = []

# =====================================================
# LOOP LAYERS
# =====================================================

var layers       : Array = []   # каждый элемент = Array of primes
var layer_steps  : Array = []   # текущий шаг каждого слоя
var layer_timers : Array = []   # таймер каждого слоя
var recording    := false
var current_rec  : Array = []   # что пишем прямо сейчас

# =====================================================
# MODES
# =====================================================

var current_mode := 0
var mode_names   = [
	"PRIME MELODY", "CHAOS", "HARMONIC", "AMBIENT",
	"CONSTELLATION", "FRACTAL", "DRUM", "DUET"
]

# =====================================================
# STATISTICS
# =====================================================

var primes_played   := 0
var highest_prime   := 0
var last_prime_stat := -1
var gap_sum         := 0
var gap_count       := 0

# =====================================================
# VISUALS
# =====================================================

var is_playing    := false
var pulse         := 0.0
var screen_shake  := Vector2.ZERO
var shake_amount  := 0.0
var bg_hue        := 0.0

var zoom_scale  := 1.0
var pan_offset  := Vector2.ZERO
var is_panning  := false
var pan_start   := Vector2.ZERO
var pan_origin  := Vector2.ZERO

var played_primes : Dictionary = {}
var trails        : Array = []
var stars         : Array = []
const STAR_COUNT  = 120
var show_twins    := true

# =====================================================
# PARTICLES
# =====================================================

class Particle:
	var pos   : Vector2
	var vel   : Vector2
	var life  : float
	var color : Color
	var size  : float

var particles : Array = []

# =====================================================
# MOUSE / IDLE
# =====================================================

var hovered_prime := -1
var idle_timer    := 0.0
const IDLE_TIME   = 12.0
var idle_mode     := false

const REVEAL_MAX  = 1500

# =====================================================
# READY
# =====================================================

func _ready():
	randomize()
	_setup_audio()
	_setup_sliders()
	_create_dynamic_nodes()
	_connect_signals()
	_generate_stars()
	note_label.text = "press PLAY or SPACE"

func _setup_sliders():
	tempo_slider.min_value  = 0.08
	tempo_slider.max_value  = 1.4
	tempo_slider.step       = 0.02
	tempo_slider.value      = 0.45
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step      = 0.01
	volume_slider.value     = 0.5

func _generate_stars():
	var vp = get_viewport_rect().size
	for i in range(STAR_COUNT):
		stars.append({
			"pos":    Vector2(randf() * vp.x, randf() * vp.y),
			"size":   randf_range(0.5, 2.2),
			"bright": randf_range(0.3, 1.0)
		})

# =====================================================
# SINGLE SOURCE OF TRUTH FOR SPIRAL POSITIONS
# =====================================================

func _build_prime_positions() -> Dictionary:
	var viewport  = get_viewport_rect().size
	var center    = viewport / 2.0 + pan_offset
	var cell      = _cell_size() * zoom_scale
	var pos       = center
	var dir       = Vector2.RIGHT
	var steps_t   = 0
	var step_size = 1
	var turns     = 0
	var number    = 1
	var result    : Dictionary = {}
	var margin    = 20.0
	var bounds    = Rect2(margin, margin, viewport.x - margin * 2, viewport.y - margin * 2)

	while number <= REVEAL_MAX:
		if is_prime(number) and bounds.has_point(pos):
			result[number] = pos
		pos     += dir * cell
		number  += 1
		steps_t += 1
		if steps_t >= step_size:
			steps_t = 0
			dir     = Vector2(-dir.y, dir.x)
			turns   += 1
			if turns % 2 == 0:
				step_size += 1

	return result

# =====================================================
# DYNAMIC NODE CREATION
# =====================================================

func _create_dynamic_nodes():
	var cl = $CanvasLayer

	_make_btn(cl, "Mode",  "PRIME MELODY", Vector2(12, 60),  Vector2(160, 36), _on_mode_pressed)
	_make_btn(cl, "Scale", "SCALE: MAJOR", Vector2(12, 100), Vector2(160, 36), _on_scale_pressed)

	if not cl.has_node("DroneBtn"):
		drone_btn = Button.new()
		drone_btn.name = "DroneBtn"
		drone_btn.text = "DRONE: OFF"
		drone_btn.position = Vector2(12, 140)
		drone_btn.size = Vector2(160, 36)
		drone_btn.pressed.connect(func():
			drone_on = not drone_on
			drone_btn.text = "DRONE: ON" if drone_on else "DRONE: OFF"
		)
		cl.add_child(drone_btn)
	else:
		drone_btn = cl.get_node("DroneBtn")

	if not cl.has_node("TwinBtn"):
		var tb = Button.new()
		tb.name = "TwinBtn"
		tb.text = "TWINS: ON"
		tb.position = Vector2(12, 180)
		tb.size = Vector2(160, 36)
		tb.pressed.connect(func():
			show_twins = not show_twins
			tb.text = "TWINS: ON" if show_twins else "TWINS: OFF"
		)
		cl.add_child(tb)

	if not cl.has_node("SaveBtn"):
		save_btn = Button.new()
		save_btn.name = "SaveBtn"
		save_btn.text = "SAVE MELODY"
		save_btn.position = Vector2(12, 220)
		save_btn.size = Vector2(160, 36)
		save_btn.pressed.connect(_save_melody)
		cl.add_child(save_btn)

	# REC button
	if not cl.has_node("RecBtn"):
		rec_btn = Button.new()
		rec_btn.name = "RecBtn"
		rec_btn.text = "REC"
		rec_btn.position = Vector2(12, 260)
		rec_btn.size = Vector2(160, 36)
		rec_btn.pressed.connect(_on_rec_pressed)
		cl.add_child(rec_btn)
	else:
		rec_btn = cl.get_node("RecBtn")

	if not cl.has_node("InfoBtn"):
		var ib = Button.new()
		ib.name = "InfoBtn"
		ib.text = "?"
		ib.position = Vector2(178, 100)
		ib.size = Vector2(36, 36)
		ib.pressed.connect(_toggle_info)
		cl.add_child(ib)

	_make_label(cl, "History",      Vector2(12, 565), Vector2(700, 22))
	_make_label(cl, "PrimeHistory", Vector2(12, 588), Vector2(700, 22))

	if not cl.has_node("StatsLabel"):
		stats_label = Label.new()
		stats_label.name = "StatsLabel"
		stats_label.position = Vector2(12, 420)
		stats_label.size = Vector2(200, 140)
		stats_label.add_theme_font_size_override("font_size", 11)
		cl.add_child(stats_label)
	else:
		stats_label = cl.get_node("StatsLabel")

	history_label       = cl.get_node("History")
	prime_history_label = cl.get_node("PrimeHistory")
	mode_btn            = cl.get_node("Mode")
	scale_btn           = cl.get_node("Scale")

	_create_info_panel(cl)

func _make_btn(cl: Node, n: String, txt: String, pos: Vector2, sz: Vector2, cb: Callable):
	if not cl.has_node(n):
		var b = Button.new()
		b.name = n; b.text = txt; b.position = pos; b.size = sz
		b.pressed.connect(cb)
		cl.add_child(b)

func _make_label(cl: Node, n: String, pos: Vector2, sz: Vector2):
	if not cl.has_node(n):
		var lb = Label.new()
		lb.name = n; lb.position = pos; lb.size = sz
		lb.add_theme_font_size_override("font_size", 11)
		cl.add_child(lb)

func _create_info_panel(cl: Node):
	if cl.has_node("InfoPanel"):
		info_panel = cl.get_node("InfoPanel")
		return
	info_panel = PanelContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.position = Vector2(200, 120)
	info_panel.size = Vector2(360, 240)
	info_panel.visible = false
	cl.add_child(info_panel)

	var vbox = VBoxContainer.new()
	info_panel.add_child(vbox)

	var title = Label.new()
	title.text = "What are prime numbers?"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var body = Label.new()
	body.text = (
		"A prime number is divisible only by 1 and itself.\n\n" +
		"Examples:   2   3   5   7   11   13   17   19\n\n" +
		"Primes are infinite but unpredictable.\n\n" +
		"The Ulam spiral reveals hidden diagonal\n" +
		"patterns — no one fully understands why.\n\n" +
		"This project turns those patterns into sound."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body)

	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.pressed.connect(func():
		info_panel.visible = false
		info_visible = false
	)
	vbox.add_child(close_btn)

# =====================================================
# AUDIO
# =====================================================

func _setup_audio():
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = sample_rate
	stream.buffer_length = 0.15
	player = AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	playback = player.get_stream_playback()
	DELAY_SAMPLES = int(sample_rate * 0.22)
	delay_buffer.resize(DELAY_SAMPLES)
	delay_buffer.fill(0.0)

func _osc(p: float, wm: int) -> float:
	match wm:
		0: return sin(TAU * p)
		1: return 1.0 if p < 0.5 else -1.0
		2: return p * 2.0 - 1.0
	return 0.0

func _trigger_note():
	env_state = "attack"
	env_time  = 0.0

func _update_envelope(dt: float) -> float:
	env_time += dt
	match env_state:
		"attack":
			env_val = clamp(env_time / env_attack, 0.0, 1.0)
			if env_time >= env_attack:
				env_state = "sustain"
				env_time  = 0.0
		"sustain":
			env_val = 1.0
		"release":
			env_val = clamp(1.0 - env_time / env_release, 0.0, 1.0)
			if env_time >= env_release:
				env_state = "off"
				env_val   = 0.0
		"off":
			env_val = 0.0
	return env_val

func _update_audio(delta: float):
	if playback == null:
		return
	var volume    = volume_slider.value if (is_playing or env_state != "off") else 0.0
	var frames    = playback.get_frames_available()
	var dt        = delta / float(max(frames, 1))
	var delay_mix = 0.0 if current_mode == 1 else 0.25

	for i in range(frames):
		var ev = _update_envelope(dt)
		var s  = _osc(phase, wave_mode) * ev * volume

		if (current_mode == 2 or current_mode == 7) and freq2 > 0.0:
			s += _osc(phase2, 0) * ev * volume * 0.4
			s += _osc(phase3, 0) * ev * volume * 0.2
			phase2 += freq2 / sample_rate
			phase3 += freq3 / sample_rate
			if phase2 >= 1.0: phase2 -= 1.0
			if phase3 >= 1.0: phase3 -= 1.0

		if drone_on:
			drone_phase += drone_freq / sample_rate
			if drone_phase >= 1.0: drone_phase -= 1.0
			s += sin(TAU * drone_phase) * volume * 0.15

		phase += freq / sample_rate
		if phase >= 1.0: phase -= 1.0

		var delayed = delay_buffer[delay_index] * delay_mix
		delay_buffer[delay_index] = s
		delay_index = (delay_index + 1) % DELAY_SAMPLES
		s = clamp(s + delayed, -1.0, 1.0)
		playback.push_frame(Vector2(s, s))

# =====================================================
# PRIME MATH
# =====================================================

func is_prime(n: int) -> bool:
	if n < 2: return false
	if n == 2: return true
	if n % 2 == 0: return false
	for i in range(3, int(sqrt(float(n))) + 1, 2):
		if n % i == 0: return false
	return true

func next_prime_after(n: int) -> int:
	var x = n + 1
	while not is_prime(x):
		x += 1
	return x

func is_twin_prime(n: int) -> bool:
	return is_prime(n) and (is_prime(n - 2) or is_prime(n + 2))

# =====================================================
# SCALE + NOTE MAPPING
# =====================================================

func _prime_to_freq(n: int) -> float:
	var scale_key = scale_names[current_scale]
	var intervals : Array
	if scale_key == "RANDOM":
		intervals = [0, randi_range(1,2), randi_range(3,4),
					 randi_range(5,6), randi_range(7,8), randi_range(9,10), 11]
	else:
		intervals = scales[scale_key]

	var scale_len = intervals.size()
	var idx       = n % scale_len
	var semitone  = intervals[idx]
	var octave    = 3 + (n % 3)

	var display = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
	current_note = display[semitone] + str(octave)

	var midi = 12 + octave * 12 + semitone
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

# =====================================================
# SEQUENCES
# =====================================================

func make_random_sequence():
	sequence.clear()
	var all_primes = []
	var p = 2
	while all_primes.size() < 50:
		all_primes.append(p)
		p = next_prime_after(p)
	all_primes.shuffle()
	var count = randi_range(10, 16)
	for i in range(min(count, all_primes.size())):
		sequence.append(all_primes[i])
	step = 0

func make_user_sequence():
	sequence.clear()
	for txt in input_box.text.split(","):
		var value = int(txt.strip_edges())
		if is_prime(value):
			sequence.append(value)
	if sequence.size() == 0:
		make_random_sequence()
	step = 0

# =====================================================
# PLAY NOTE
# =====================================================

func play_prime(n: int):
	current_prime = n
	freq = _prime_to_freq(n)

	match current_mode:
		2, 7:
			freq2 = freq * 1.5
			freq3 = freq * 1.25
		6:
			freq  = 80.0 + float(n % 8) * 20.0
			freq2 = 0.0; freq3 = 0.0
		_:
			freq2 = 0.0; freq3 = 0.0

	if current_mode == 1:
		freq *= randf_range(0.98, 1.02)

	drone_freq = freq * 0.25
	_trigger_note()
	pulse        = 1.0
	shake_amount = 3.5 if current_mode == 1 else 0.8

	var col = _note_color(n)
	played_primes[n] = {"color": col, "age": 0.0}

	primes_played += 1
	if n > highest_prime: highest_prime = n
	if last_prime_stat >= 0:
		gap_sum   += abs(n - last_prime_stat)
		gap_count += 1
	last_prime_stat = n

	note_history.push_front(current_note)
	prime_history.push_front(str(n))
	if note_history.size()  > HISTORY_MAX: note_history.pop_back()
	if prime_history.size() > HISTORY_MAX: prime_history.pop_back()

	session_log.append({"prime": n, "note": current_note})

	# запись в текущий слой
	if recording:
		current_rec.append(n)

	_spawn_particles(n)
	_spawn_trail(n)
	idle_timer = 0.0
	idle_mode  = false

# только визуал для слоёв — не сбивает основной envelope
func _play_layer_note(n: int):
	var col = _note_color(n)
	if not played_primes.has(n):
		played_primes[n] = {"color": col, "age": 0.0}
	else:
		played_primes[n]["age"] = 0.0
	_spawn_trail(n)

# =====================================================
# LOOP LAYERS
# =====================================================

func _on_rec_pressed():
	if not recording:
		recording   = true
		current_rec = []
		rec_btn.text = "STOP REC"
		if not is_playing:
			make_random_sequence()
			_start_playing()
	else:
		recording = false
		rec_btn.text = "REC"
		if current_rec.size() > 0:
			layers.append(current_rec.duplicate())
			layer_steps.append(0)
			layer_timers.append(0.0)
			note_label.text = (
				"layer " + str(layers.size()) +
				" saved  (" + str(current_rec.size()) + " notes)"
			)
		current_rec = []

func _clear_layers():
	layers.clear()
	layer_steps.clear()
	layer_timers.clear()
	note_label.text = "layers cleared"

# =====================================================
# SAVE MELODY
# =====================================================

func _save_melody():
	var lines : Array = []
	lines.append("PRIME SPIRAL SYNTH - Session Log")
	lines.append("Scale: " + scale_names[current_scale])
	lines.append("Mode:  " + mode_names[current_mode])
	lines.append("Layers: " + str(layers.size()))
	lines.append("")
	lines.append("Primes played: " + str(primes_played))
	lines.append("Highest prime: " + str(highest_prime))
	lines.append("")
	lines.append("Main sequence:")
	for entry in session_log:
		lines.append("  " + str(entry["prime"]) + "  ->  " + entry["note"])
	lines.append("")
	for i in range(layers.size()):
		lines.append("Layer " + str(i + 1) + ":")
		for p in layers[i]:
			lines.append("  " + str(p))

	var file = FileAccess.open("user://melody_session.txt", FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()
		note_label.text = "saved!  user://melody_session.txt"

# =====================================================
# PARTICLES + TRAILS
# =====================================================

func _spawn_particles(prime: int):
	var positions = _build_prime_positions()
	if not positions.has(prime):
		return
	var sp    = positions[prime]
	var count = 14 if current_mode == 1 else 7
	for i in range(count):
		var p   = Particle.new()
		p.pos   = sp
		var a   = randf() * TAU
		var spd = randf_range(30.0, 100.0)
		p.vel   = Vector2(cos(a), sin(a)) * spd
		p.life  = 1.0
		p.size  = randf_range(2.0, 6.0)
		p.color = _note_color(prime)
		particles.append(p)

func _spawn_trail(prime: int):
	var positions = _build_prime_positions()
	if not positions.has(prime):
		return
	trails.append({"pos": positions[prime], "color": _note_color(prime), "life": 1.0})

func _update_particles(delta: float):
	for p in particles:
		p.pos  += p.vel * delta
		p.vel  *= 0.91
		p.life -= delta * 1.8
	particles = particles.filter(func(p): return p.life > 0.0)

func _update_trails(delta: float):
	for t in trails:
		t["life"] -= delta * 0.4
	trails = trails.filter(func(t): return t["life"] > 0.0)
	for key in played_primes.keys():
		played_primes[key]["age"] += delta

# =====================================================
# HELPERS
# =====================================================

func _note_color(n: int) -> Color:
	var hue = float(n % 7) / 7.0
	match current_mode:
		0: return Color.from_hsv(hue, 0.7, 1.0)
		1: return Color.from_hsv(randf(), 1.0, 1.0)
		2: return Color.from_hsv(hue * 0.5 + 0.55, 0.6, 1.0)
		3: return Color.from_hsv(hue * 0.3 + 0.55, 0.4, 0.85)
		4: return Color.from_hsv(hue, 0.5, 1.0)
		5: return Color.from_hsv(hue * 0.8, 0.8, 1.0)
		6: return Color.from_hsv(0.0, 0.9, 1.0)
		7: return Color.from_hsv(hue * 0.6 + 0.3, 0.7, 1.0)
	return Color.WHITE

func _cell_size() -> float:
	match current_mode:
		1: return 10.0
		3: return 14.0
		4: return 12.0
		_: return 11.0

func _get_tempo() -> float:
	match current_mode:
		1: return max(0.08, tempo_slider.value * 0.45)
		3: return tempo_slider.value * 2.0
		_: return tempo_slider.value

# =====================================================
# START
# =====================================================

func _start_playing():
	is_playing = true
	seq_timer  = 0.0
	step       = 0
	env_state  = "off"
	idle_timer = 0.0
	idle_mode  = false

# =====================================================
# UI CALLBACKS
# =====================================================

func _on_wave_pressed():
	wave_mode = (wave_mode + 1) % waves.size()

func _on_play_pressed():
	make_user_sequence()
	_start_playing()

func _on_random_pressed():
	make_random_sequence()
	_start_playing()

func _on_submit(_text):
	make_user_sequence()
	_start_playing()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://control.tscn")

func _on_mode_pressed():
	current_mode = (current_mode + 1) % mode_names.size()
	match current_mode:
		0: wave_mode = 0; env_attack = 0.01;  env_release = 0.3
		1: wave_mode = 2; env_attack = 0.005; env_release = 0.1
		2: wave_mode = 0; env_attack = 0.02;  env_release = 0.5
		3: wave_mode = 0; env_attack = 0.05;  env_release = 0.9
		4: wave_mode = 0; env_attack = 0.01;  env_release = 0.4
		5: wave_mode = 2; env_attack = 0.01;  env_release = 0.2
		6: wave_mode = 1; env_attack = 0.003; env_release = 0.08
		7: wave_mode = 0; env_attack = 0.02;  env_release = 0.6
	if is_playing:
		make_random_sequence()

func _on_scale_pressed():
	current_scale = (current_scale + 1) % scale_names.size()

func _toggle_info():
	info_visible = not info_visible
	info_panel.visible = info_visible

func _connect_signals():
	wave_btn.pressed.connect(_on_wave_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	random_btn.pressed.connect(_on_random_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	mode_btn.pressed.connect(_on_mode_pressed)
	scale_btn.pressed.connect(_on_scale_pressed)
	input_box.text_submitted.connect(_on_submit)

# =====================================================
# KEYBOARD NOTE PLAYING
# =====================================================

func _play_key_note(prime: int):
	is_playing = false
	play_prime(prime)
	env_state = "attack"
	env_time  = 0.0

# =====================================================
# INPUT
# =====================================================

func _input(event):
	if input_box.has_focus():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_panning = event.pressed
			if event.pressed:
				pan_start  = event.position
				pan_origin = pan_offset
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_check_spiral_click(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_scale = clamp(zoom_scale * 1.1, 0.3, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_scale = clamp(zoom_scale * 0.9, 0.3, 4.0)
		return

	if event is InputEventMouseMotion:
		if is_panning:
			pan_offset = pan_origin + (event.position - pan_start)
		else:
			_check_spiral_hover(event.position)
		return

	if event is InputEventKey and event.pressed:
		idle_timer = 0.0
		match event.keycode:
			KEY_SPACE:
				make_random_sequence()
				_start_playing()
			KEY_ESCAPE:
				_clear_layers()
			KEY_1: wave_mode = 0
			KEY_2: wave_mode = 1
			KEY_3: wave_mode = 2
			KEY_F11:
				var wm = DisplayServer.window_get_mode()
				if wm == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_Q: _play_key_note(2)
			KEY_W: _play_key_note(3)
			KEY_E: _play_key_note(5)
			KEY_R: _play_key_note(7)
			KEY_T: _play_key_note(11)
			KEY_Y: _play_key_note(13)
			KEY_U: _play_key_note(17)
			KEY_I: _play_key_note(19)
			KEY_O: _play_key_note(23)
			KEY_P: _play_key_note(29)
			KEY_A: _play_key_note(31)
			KEY_S: _play_key_note(37)
			KEY_D: _play_key_note(41)
			KEY_F: _play_key_note(43)
			KEY_G: _play_key_note(47)
			KEY_H: _play_key_note(53)
			KEY_J: _play_key_note(59)
			KEY_K: _play_key_note(61)
			KEY_L: _play_key_note(67)
			KEY_Z: _play_key_note(71)
			KEY_X: _play_key_note(73)
			KEY_C: _play_key_note(79)
			KEY_V: _play_key_note(83)
			KEY_B: _play_key_note(89)
			KEY_N: _play_key_note(97)
			KEY_M: _play_key_note(101)

# =====================================================
# MOUSE
# =====================================================

func _check_spiral_click(mouse_pos: Vector2):
	var positions = _build_prime_positions()
	var threshold = _cell_size() * zoom_scale * 0.65
	for prime in positions.keys():
		if mouse_pos.distance_to(positions[prime]) < threshold:
			_play_key_note(prime)
			return

func _check_spiral_hover(mouse_pos: Vector2):
	var positions = _build_prime_positions()
	var threshold = _cell_size() * zoom_scale * 0.65
	hovered_prime = -1
	for prime in positions.keys():
		if mouse_pos.distance_to(positions[prime]) < threshold:
			hovered_prime = prime
			return

# =====================================================
# PROCESS
# =====================================================

func _process(delta):
	# idle screensaver
	idle_timer += delta
	if idle_timer > IDLE_TIME and not idle_mode and not is_playing:
		idle_mode    = true
		current_mode = 3
		make_random_sequence()
		_start_playing()

	# shake
	if shake_amount > 0.0:
		shake_amount = max(0.0, shake_amount - delta * 8.0)
		screen_shake = Vector2(randf_range(-shake_amount, shake_amount),
							   randf_range(-shake_amount, shake_amount))
	else:
		screen_shake = Vector2.ZERO

	bg_hue = fmod(bg_hue + delta * 0.03, 1.0)

	# main sequence
	if is_playing:
		seq_timer += delta
		if seq_timer >= _get_tempo():
			seq_timer = 0.0
			if step >= sequence.size(): step = 0
			if sequence.size() > 0:
				play_prime(sequence[step])
				step += 1

	# envelope release
	if env_state == "sustain" and seq_timer > _get_tempo() * 0.6:
		env_state = "release"
		env_time  = 0.0

	# loop layers — каждый слой тикает независимо
	for i in range(layers.size()):
		layer_timers[i] += delta
		if layer_timers[i] >= _get_tempo():
			layer_timers[i] = 0.0
			var layer = layers[i]
			if layer.size() > 0:
				var ls = layer_steps[i] % layer.size()
				_play_layer_note(layer[ls])
				layer_steps[i] += 1

	pulse = max(0.0, pulse - delta * 2.5)

	_update_particles(delta)
	_update_trails(delta)
	_update_audio(delta)

	# UI
	wave_btn.text  = waves[wave_mode]
	mode_btn.text  = mode_names[current_mode]
	scale_btn.text = "SCALE: " + scale_names[current_scale]

	# rec button pulse text
	if recording:
		var blink = int(Time.get_ticks_msec() / 500) % 2
		rec_btn.text = "STOP REC" if blink == 0 else "● STOP REC"
	else:
		rec_btn.text = "REC  [" + str(layers.size()) + " layers]" if layers.size() > 0 else "REC"

	if is_playing and current_prime >= 0:
		note_label.text = "▶  PRIME " + str(current_prime) + "   NOTE " + current_note
	else:
		note_label.text = "click a prime  ·  QWERTY plays notes  ·  SPACE = random"

	if history_label:
		history_label.text = "notes:   " + "  ".join(note_history)
	if prime_history_label:
		prime_history_label.text = "primes:  " + "  ".join(prime_history)

	var avg_gap = float(gap_sum) / float(max(gap_count, 1))
	var bpm_val = int(60.0 / max(_get_tempo(), 0.01))
	if stats_label:
		stats_label.text = (
			"played:  " + str(primes_played) + "\n" +
			"highest: " + str(highest_prime) + "\n" +
			"avg gap: " + ("%.1f" % avg_gap) + "\n" +
			"BPM:     " + str(bpm_val) + "\n" +
			"scale:   " + scale_names[current_scale] + "\n" +
			"layers:  " + str(layers.size())
		)

	queue_redraw()

# =====================================================
# DRAW
# =====================================================

func _draw():
	var viewport = get_viewport_rect().size

	draw_rect(Rect2(Vector2.ZERO, viewport),
		Color.from_hsv(bg_hue, 0.12, 0.05))

	for star in stars:
		var twinkle = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 + star["pos"].x)
		draw_circle(star["pos"], star["size"],
			Color(1, 1, 1, star["bright"] * twinkle * 0.5))

	# единые позиции для draw, click, hover
	var prime_positions = _build_prime_positions()

	# shake только визуальный
	var shake = screen_shake
	var shifted : Dictionary = {}
	for k in prime_positions.keys():
		shifted[k] = prime_positions[k] + shake

	# twin prime lines
	if show_twins:
		for prime in shifted.keys():
			if is_twin_prime(prime) and shifted.has(prime + 2):
				var alpha = 0.5 if (played_primes.has(prime) or played_primes.has(prime + 2)) else 0.1
				draw_line(shifted[prime], shifted[prime + 2],
					Color(0.6, 0.9, 1.0, alpha), 0.8)

	# constellation lines
	if current_mode == 4:
		var pkeys = played_primes.keys()
		pkeys.sort()
		for i in range(pkeys.size() - 1):
			var pa = pkeys[i]; var pb = pkeys[i + 1]
			if shifted.has(pa) and shifted.has(pb):
				var alpha = clamp(1.0 - played_primes[pa]["age"] * 0.07, 0.1, 0.7)
				draw_line(shifted[pa], shifted[pb], Color(0.4, 0.7, 1.0, alpha), 1.0)

	# layer connections — рисуем линии между нотами каждого слоя
	for i in range(layers.size()):
		var layer = layers[i]
		var hue   = float(i + 1) / float(max(layers.size(), 1))
		var lcol  = Color.from_hsv(hue, 0.6, 0.8, 0.3)
		for j in range(layer.size() - 1):
			var pa = layer[j]; var pb = layer[j + 1]
			if shifted.has(pa) and shifted.has(pb):
				draw_line(shifted[pa], shifted[pb], lcol, 0.6)

	# fractal
	if current_mode == 5 and current_prime > 0 and shifted.has(current_prime):
		var fp    = shifted[current_prime]
		var sides = (current_prime % 5) + 3
		var rad   = 14.0 + pulse * 22.0
		for i in range(sides):
			var a1 = TAU * float(i) / float(sides)
			var a2 = TAU * float((i + 1) % sides) / float(sides)
			draw_line(
				fp + Vector2(cos(a1), sin(a1)) * rad,
				fp + Vector2(cos(a2), sin(a2)) * rad,
				Color.from_hsv(float(i) / float(sides), 0.8, 1.0, pulse), 1.2)

	# draw primes
	for prime in shifted.keys():
		var ppos   = shifted[prime]
		var is_cur = (prime == current_prime and is_playing)
		var is_hov = (prime == hovered_prime)
		var played = played_primes.has(prime)
		var twin   = show_twins and is_twin_prime(prime)

		# check if this prime is in any layer
		var in_layer = false
		for layer in layers:
			if layer.has(prime):
				in_layer = true
				break

		if is_cur:
			for ring in range(3):
				var rr = (6.0 + ring * 8.0) + pulse * 10.0
				var ra = (0.5 - ring * 0.15) * pulse
				draw_arc(ppos, rr, 0, TAU, 32, Color(1.0, 0.5, 0.1, ra), 1.2)

		if is_cur:
			draw_circle(ppos, 12.0, Color(1.0, 0.5, 0.1, 0.18 * pulse))
		elif played:
			var pcol = played_primes[prime]["color"]
			draw_circle(ppos, 5.5, Color(pcol.r, pcol.g, pcol.b, 0.08))
		elif twin:
			draw_circle(ppos, 4.0, Color(0.5, 0.9, 1.0, 0.06))

		# layer glow ring
		if in_layer and not is_cur:
			draw_arc(ppos, 8.0, 0, TAU, 20, Color(0.8, 0.6, 1.0, 0.35), 1.0)

		if is_hov and not is_cur:
			draw_arc(ppos, 7.0, 0, TAU, 20, Color(1, 1, 1, 0.4), 1.0)

		var col   : Color
		var fsize : int
		if is_cur:
			col   = Color.from_hsv(0.08, 0.9, 1.0)
			fsize = int(9 + pulse * 5)
		elif played:
			var age  = played_primes[prime]["age"]
			var fade = clamp(1.0 - age * 0.01, 0.3, 1.0)
			var pc   = played_primes[prime]["color"]
			col      = Color(pc.r, pc.g, pc.b, fade)
			fsize    = 8
		elif is_hov:
			col   = Color(1.0, 1.0, 1.0, 0.95)
			fsize = 9
		elif twin:
			col   = Color(0.55, 0.88, 1.0, 0.55)
			fsize = 7
		else:
			col   = Color(0.25, 0.35, 0.5, 0.38)
			fsize = 7

		var txt   = str(prime)
		var txt_w = fsize * len(txt) * 0.52
		draw_string(ThemeDB.fallback_font,
			ppos + Vector2(-txt_w * 0.5, fsize * 0.38),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

	# trails
	for t in trails:
		draw_circle(t["pos"] + shake, 3.5 * t["life"],
			Color(t["color"].r, t["color"].g, t["color"].b, t["life"] * 0.4))

	# particles
	for p in particles:
		draw_circle(p.pos, p.size * p.life,
			Color(p.color.r, p.color.g, p.color.b, p.life * 0.85))

	# drum bar
	if current_mode == 6:
		draw_rect(Rect2(viewport.x/2 - 90, viewport.y - 65, 180, 32 * pulse),
			Color(1.0, 0.2, 0.2, 0.75))

	# REC indicator
	if recording:
		var blink = int(Time.get_ticks_msec() / 500) % 2
		if blink == 0:
			draw_circle(Vector2(viewport.x - 20, 20), 7.0, Color(1, 0.1, 0.1, 0.9))
		draw_string(ThemeDB.fallback_font,
			Vector2(viewport.x - 80, 26),
			"REC  " + str(current_rec.size()),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.3, 0.3, 0.9))

	# hover tooltip
	if hovered_prime > 0 and shifted.has(hovered_prime):
		var hp  = shifted[hovered_prime]
		var tip = "prime " + str(hovered_prime)
		if is_twin_prime(hovered_prime): tip += "  [twin]"
		draw_string(ThemeDB.fallback_font, hp + Vector2(10, -6),
			tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))

	# bottom hint
	draw_string(ThemeDB.fallback_font,
		Vector2(viewport.x - 340, viewport.y - 14),
		"Q-M: notes   scroll: zoom   RMB: pan   ESC: clear layers   F11: fullscreen",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.22))
