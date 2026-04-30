# main.gd
# Orchestrator — owns the UI and wires Synth, Looper, Spiral together.
# All audio logic lives in Synth.gd.
# All loop/record logic lives in Looper.gd.
# All drawing logic lives in Spiral.gd.
#
# Scene tree expected:
#   Node2D  (this script)
#   ├── Spiral      (Spiral.gd)
#   ├── CanvasLayer
#   │   ├── NoteLabel   Label
#   │   ├── Wave        Button
#   │   ├── Back        Button
#   │   ├── Input       LineEdit
#   │   ├── Play        Button
#   │   ├── Stop        Button      ← NEW
#   │   ├── Random      Button
#   │   ├── Tempo       HSlider
#   │   └── Volume      HSlider

extends Node2D

# ── child references ──────────────────────────────────────────────────────────
@onready var spiral        : Spiral = $Spiral
@onready var note_label            = $CanvasLayer/NoteLabel
@onready var wave_btn              = $CanvasLayer/Wave
@onready var back_btn              = $CanvasLayer/Back
@onready var input_box             = $CanvasLayer/Input
@onready var play_btn              = $CanvasLayer/Play
@onready var stop_btn              = $CanvasLayer/Stop
@onready var random_btn            = $CanvasLayer/Random
@onready var tempo_slider          = $CanvasLayer/Tempo
@onready var volume_slider         = $CanvasLayer/Volume

# dynamically created buttons
var mode_btn   : Button
var scale_btn  : Button
var drone_btn  : Button
var stats_label : Label
var info_panel  : PanelContainer
var info_visible := false

# ── sub-systems ───────────────────────────────────────────────────────────────
var synth  : Synth
# ── sequence state ────────────────────────────────────────────────────────────
var sequence      : Array = []
var step          := 0
var seq_timer     := 0.0
var is_playing    := false
var current_prime := -1
var current_mode  := 0

const MODE_NAMES = [
	"PRIME MELODY", "CHAOS", "HARMONIC", "AMBIENT",
	"CONSTELLATION", "FRACTAL", "DRUM", "DUET"
]

# ── stats ─────────────────────────────────────────────────────────────────────
var primes_played   := 0
var highest_prime   := 0
var last_prime_stat := -1
var gap_sum         := 0
var gap_count       := 0

# ── visuals ───────────────────────────────────────────────────────────────────
var pulse        := 0.0
var screen_shake := Vector2.ZERO
var shake_amount := 0.0
var bg_hue       := 0.0

# particle / trail class (kept here, passed to Spiral each frame)
class Particle:
	var pos   : Vector2
	var vel   : Vector2
	var life  : float
	var color : Color
	var size  : float

var particles : Array = []
var trails    : Array = []

# ── idle screensaver ──────────────────────────────────────────────────────────
var idle_timer := 0.0
const IDLE_TIME = 12.0
var idle_mode  := false


func _ready() -> void:
	randomize()
	_setup_subsystems()
	_setup_sliders()
	_create_dynamic_nodes()
	_connect_signals()
	note_label.text = "press PLAY or SPACE"


# ── init ──────────────────────────────────────────────────────────────────────

func _setup_subsystems() -> void:
	synth  = Synth.new()
	add_child(synth)
	synth.setup(self)

	synth.note_triggered.connect(_on_note_triggered)
	spiral.prime_clicked.connect(_on_spiral_prime_clicked)
	spiral.prime_hovered.connect(_on_spiral_prime_hovered)


func _setup_sliders() -> void:
	tempo_slider.min_value  = 0.08
	tempo_slider.max_value  = 1.4
	tempo_slider.step       = 0.02
	tempo_slider.value      = 0.45
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step      = 0.01
	volume_slider.value     = 0.5


func _create_dynamic_nodes() -> void:
	var cl = $CanvasLayer
	_make_btn(cl, "Mode",  "PRIME MELODY", Vector2(12, 60),  Vector2(160, 36), _on_mode_pressed)
	_make_btn(cl, "Scale", "SCALE: MAJOR", Vector2(12, 100), Vector2(160, 36), _on_scale_pressed)
	_make_btn(cl, "DroneBtn", "DRONE: OFF",    Vector2(12, 140), Vector2(160, 36), _on_drone_pressed)
	_make_btn(cl, "TwinBtn",  "TWINS: ON",     Vector2(12, 180), Vector2(160, 36), _on_twins_pressed)
	_make_btn(cl, "InfoBtn",  "?",             Vector2(178, 100), Vector2(36, 36), _toggle_info)

	if not cl.has_node("StatsLabel"):
		stats_label = Label.new()
		stats_label.name = "StatsLabel"
		stats_label.position = Vector2(12, 420)
		stats_label.size = Vector2(200, 140)
		stats_label.add_theme_font_size_override("font_size", 11)
		cl.add_child(stats_label)
	else:
		stats_label = cl.get_node("StatsLabel")

	mode_btn  = cl.get_node("Mode")
	scale_btn = cl.get_node("Scale")
	drone_btn = cl.get_node("DroneBtn")

	_create_info_panel(cl)


func _make_btn(cl: Node, n: String, txt: String, pos: Vector2, sz: Vector2, cb: Callable) -> void:
	var b : Button
	if cl.has_node(n):
		b = cl.get_node(n)
		if b.pressed.is_connected(cb):
			b.pressed.disconnect(cb)
	else:
		b = Button.new()
		b.name = n
		b.position = pos
		b.size = sz
		cl.add_child(b)
	b.text = txt
	b.pressed.connect(cb)


func _create_info_panel(cl: Node) -> void:
	if cl.has_node("InfoPanel"):
		info_panel = cl.get_node("InfoPanel")
		return
	info_panel = PanelContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.position = Vector2(200, 120)
	info_panel.size = Vector2(360, 240)
	info_panel.visible = false
	cl.add_child(info_panel)

	var vbox  = VBoxContainer.new()
	info_panel.add_child(vbox)
	var title = Label.new()
	title.text = "What are prime numbers?"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	var body = Label.new()
	body.text = (
		"A prime number is divisible only by 1 and itself.\n\n"
		+ "Examples:   2   3   5   7   11   13   17   19\n\n"
		+ "Primes are infinite but unpredictable.\n\n"
		+ "The Ulam spiral reveals hidden diagonal\n"
		+ "patterns — no one fully understands why.\n\n"
		+ "This project turns those patterns into sound."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body)
	var close = Button.new()
	close.text = "CLOSE"
	close.pressed.connect(func(): info_panel.visible = false; info_visible = false)
	vbox.add_child(close)


func _connect_signals() -> void:
	wave_btn.pressed.connect(_on_wave_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	stop_btn.pressed.connect(_on_stop_pressed)
	random_btn.pressed.connect(_on_random_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	input_box.text_submitted.connect(_on_submit)


# ── signal handlers ───────────────────────────────────────────────────────────

func _on_note_triggered(_prime: int, _note: String, _freq: float) -> void:
	pass  # Synth already updated current_note; Spiral state updated in play_prime


func _on_layer_note(prime: int) -> void:
	# layer notes light up the spiral without resetting the main envelope
	if not spiral.played_primes.has(prime):
		spiral.played_primes[prime] = {"color": _note_color(prime), "age": 0.0}
	else:
		spiral.played_primes[prime]["age"] = 0.0
	_spawn_trail(prime)


func _on_spiral_prime_clicked(prime: int) -> void:
	_play_key_note(prime)


func _on_spiral_prime_hovered(_prime: int) -> void:
	pass  # Spiral handles its own hover drawing




# ── button handlers ───────────────────────────────────────────────────────────

func _on_wave_pressed() -> void:
	synth.wave_mode = (synth.wave_mode + 1) % 3

func _on_play_pressed() -> void:
	make_user_sequence()
	_start_playing()

func _on_stop_pressed() -> void:
	is_playing = false
	synth.release()
	note_label.text = "stopped  ·  SPACE to resume"

func _on_random_pressed() -> void:
	make_random_sequence()
	_start_playing()

func _on_submit(_text: String) -> void:
	make_user_sequence()
	_start_playing()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://control.tscn")

func _on_mode_pressed() -> void:
	current_mode = (current_mode + 1) % MODE_NAMES.size()
	synth.apply_mode(current_mode)
	synth.chord_mode = (current_mode == 2 or current_mode == 7)
	spiral.current_mode = current_mode
	if is_playing:
		make_random_sequence()

func _on_scale_pressed() -> void:
	synth.current_scale = (synth.current_scale + 1) % Synth.SCALE_NAMES.size()

func _on_drone_pressed() -> void:
	synth.drone_on = not synth.drone_on
	drone_btn.text = "DRONE: ON" if synth.drone_on else "DRONE: OFF"

func _on_twins_pressed() -> void:
	spiral.show_twins = not spiral.show_twins
	$CanvasLayer/TwinBtn.text = "TWINS: ON" if spiral.show_twins else "TWINS: OFF"


func _toggle_info() -> void:
	info_visible = not info_visible
	info_panel.visible = info_visible


# ── sequence helpers ──────────────────────────────────────────────────────────

func make_random_sequence() -> void:
	sequence.clear()
	var all_primes : Array = []
	var p = 2
	while all_primes.size() < 50:
		all_primes.append(p)
		p = _next_prime_after(p)
	all_primes.shuffle()
	var count = randi_range(10, 16)
	for i in range(min(count, all_primes.size())):
		sequence.append(all_primes[i])
	step = 0


func make_user_sequence() -> void:
	sequence.clear()
	for txt in input_box.text.split(","):
		var value = int(txt.strip_edges())
		if Spiral.is_prime(value):
			sequence.append(value)
	if sequence.size() == 0:
		make_random_sequence()
	step = 0


func _start_playing() -> void:
	is_playing = true
	seq_timer  = 0.0
	step       = 0
	idle_timer = 0.0
	idle_mode  = false


func _get_tempo() -> float:
	match current_mode:
		1: return max(0.08, tempo_slider.value * 0.45)
		3: return tempo_slider.value * 2.0
		_: return tempo_slider.value


func _next_prime_after(n: int) -> int:
	var x = n + 1
	while not Spiral.is_prime(x):
		x += 1
	return x


# ── note playing ──────────────────────────────────────────────────────────────

func play_prime(n: int) -> void:
	current_prime = n
	synth.volume  = volume_slider.value
	synth.play_prime(n, current_mode)

	pulse        = 1.0
	shake_amount = 3.5 if current_mode == 1 else 0.8

	spiral.played_primes[n] = {"color": _note_color(n), "age": 0.0}
	spiral.current_prime    = n

	primes_played += 1
	if n > highest_prime: highest_prime = n
	if last_prime_stat >= 0:
		gap_sum   += abs(n - last_prime_stat)
		gap_count += 1
	last_prime_stat = n

	_spawn_particles(n)
	_spawn_trail(n)
	idle_timer = 0.0
	idle_mode  = false


func _play_key_note(prime: int) -> void:
	is_playing = false
	play_prime(prime)


# ── visual helpers ────────────────────────────────────────────────────────────

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


func _spawn_particles(prime: int) -> void:
	var positions = spiral.build_prime_positions()
	if not positions.has(prime):
		return
	var sp    = positions[prime]
	var count = 14 if current_mode == 1 else 7
	for i in range(count):
		var p   = Particle.new()
		p.pos   = sp
		var a   = randf() * TAU
		p.vel   = Vector2(cos(a), sin(a)) * randf_range(30.0, 100.0)
		p.life  = 1.0
		p.size  = randf_range(2.0, 6.0)
		p.color = _note_color(prime)
		particles.append(p)


func _spawn_trail(prime: int) -> void:
	var positions = spiral.build_prime_positions()
	if not positions.has(prime):
		return
	trails.append({"pos": positions[prime], "color": _note_color(prime), "life": 1.0})


func _update_particles(delta: float) -> void:
	for p in particles:
		p.pos  += p.vel * delta
		p.vel  *= 0.91
		p.life -= delta * 1.8
	particles = particles.filter(func(p): return p.life > 0.0)


func _update_trails(delta: float) -> void:
	for t in trails:
		t["life"] -= delta * 0.4
	trails = trails.filter(func(t): return t["life"] > 0.0)
	for key in spiral.played_primes.keys():
		spiral.played_primes[key]["age"] += delta


# ── _process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# idle screensaver
	idle_timer += delta
	if idle_timer > IDLE_TIME and not idle_mode and not is_playing:
		idle_mode    = true
		current_mode = 3
		spiral.current_mode = current_mode
		make_random_sequence()
		_start_playing()

	# screen shake decay
	if shake_amount > 0.0:
		shake_amount = max(0.0, shake_amount - delta * 8.0)
		screen_shake = Vector2(randf_range(-shake_amount, shake_amount),
							   randf_range(-shake_amount, shake_amount))
	else:
		screen_shake = Vector2.ZERO

	bg_hue = fmod(bg_hue + delta * 0.03, 1.0)

	# advance sequencer
	if is_playing:
		seq_timer += delta
		if seq_timer >= _get_tempo():
			seq_timer = 0.0
			if step >= sequence.size(): step = 0
			if sequence.size() > 0:
				play_prime(sequence[step])
				step += 1

	# trigger envelope release before next note
	if synth.is_sounding() and seq_timer > _get_tempo() * 0.6:
		synth.release()

	pulse = max(0.0, pulse - delta * 2.5)

	_update_particles(delta)
	_update_trails(delta)

	synth.volume = volume_slider.value
	synth.update(delta, is_playing)

	# push state to Spiral for drawing
	spiral.current_prime = current_prime
	spiral.current_mode  = current_mode
	spiral.pulse         = pulse
	spiral.screen_shake  = screen_shake
	spiral.bg_hue        = bg_hue
	spiral.particles     = particles
	spiral.trails        = trails
	spiral.layers        = []
	spiral.queue_redraw()

	# update UI labels
	var waves = ["SINE", "SQUARE", "SAW"]
	wave_btn.text  = waves[synth.wave_mode]
	mode_btn.text  = MODE_NAMES[current_mode]
	scale_btn.text = "SCALE: " + Synth.SCALE_NAMES[synth.current_scale]

	if is_playing and current_prime >= 0:
		note_label.text = ">  PRIME " + str(current_prime) + "   NOTE " + synth.current_note
	elif not is_playing:
		note_label.text = "STOP  ·  click prime or SPACE"

	var avg_gap = float(gap_sum) / float(max(gap_count, 1))
	var bpm_val = int(60.0 / max(_get_tempo(), 0.01))
	if stats_label:
		stats_label.text = (
			"played:  " + str(primes_played) + "\n"
			+ "highest: " + str(highest_prime) + "\n"
			+ "avg gap: " + ("%.1f" % avg_gap) + "\n"
			+ "BPM:     " + str(bpm_val) + "\n"
			+ "scale:   " + Synth.SCALE_NAMES[synth.current_scale] + "\n"		)


# ── _input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if input_box.has_focus():
		return

	# forward mouse events to Spiral for click/hover/zoom/pan
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		spiral.handle_input(event)
		return

	if event is InputEventKey and event.pressed:
		idle_timer = 0.0
		match event.keycode:
			KEY_SPACE:
				if is_playing:
					_on_stop_pressed()
				else:
					make_random_sequence()
					_start_playing()
			KEY_1:       synth.wave_mode = 0
			KEY_2:       synth.wave_mode = 1
			KEY_3:       synth.wave_mode = 2
			KEY_F11:
				var wm = DisplayServer.window_get_mode()
				if wm == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			# QWERTY keyboard instrument — each key = one prime = one note
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
