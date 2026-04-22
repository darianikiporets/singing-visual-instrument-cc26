extends Node2D

# -------- STAR --------
class Star:
	var angle = 0.0
	var radius = 0.0
	var speed = 0.0
	var size = 1.0
	var layer = 1.0

var stars = []
var capture

# -------- AUDIO --------
var volume = 0.0
var smooth_volume = 0.0
var prev_volume = 0.0

# -------- PITCH --------
var note_class = -1
var stable_note = -1
var note_timer = 0

# -------- DYNAMICS --------
var impulse = 0.0

# -------- STATE --------
var paused = false
var mode_id = 0

# -------- SCENE LINK --------
@export var menu_scene: PackedScene

@onready var bg = $ColorRect
@onready var back_btn = $CanvasLayer/HBoxContainer/back
@onready var pause_btn = $CanvasLayer/HBoxContainer/pause
@onready var mode_btn = $CanvasLayer/HBoxContainer/mode

var current_color = Color(0.4, 0.6, 1.0)


# -------- READY --------
func _ready():
	randomize()

	bg.color = Color.BLACK
	bg.z_index = -1

	for i in range(600):
		stars.append(create_star())

	var idx = AudioServer.get_bus_index("MicBus")
	if idx != -1:
		for i in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectCapture:
				capture = e

	# UI
	back_btn.pressed.connect(_on_back)
	pause_btn.pressed.connect(_on_pause)
	mode_btn.pressed.connect(_on_mode)


# -------- INPUT --------
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_on_back()


# -------- UI --------
func _on_back():
	var err = get_tree().change_scene_to_file("res://control.tscn")
	print("BACK:", err)

func _on_pause():
	paused = !paused
	pause_btn.text = "Resume" if paused else "Pause"

func _on_mode():
	mode_id = (mode_id + 1) % 3
	mode_btn.text = ["Galaxy", "Wave", "Explosion"][mode_id]


# -------- STAR CREATE --------
func create_star():
	var s = Star.new()

	var r = pow(randf(), 1.8) * 800.0
	var arm = randi() % 4

	s.radius = r
	s.angle = arm * TAU / 4 + r * 0.02
	s.speed = randf_range(0.4, 1.0)
	s.size = randf_range(1.0, 2.0)
	s.layer = randf_range(0.6, 1.4)

	return s


# -------- PROCESS --------
func _process(delta):
	if paused:
		return

	update_audio()
	update_galaxy(delta)
	update_color()
	queue_redraw()


# -------- GALAXY --------
func update_galaxy(delta):
	var rot = 0.02 + smooth_volume * 1.5 + impulse

	for s in stars:
		s.angle += rot * s.speed * delta


# -------- DRAW --------
func _draw():
	match mode_id:
		0:
			draw_galaxy()
		1:
			draw_wave()
		2:
			draw_explosion()


# -------- GALAXY --------
func draw_galaxy():
	var center = get_viewport_rect().size / 2
	var boost = 1.0 + smooth_volume * 2.5 + impulse * 2.0

	for s in stars:
		var pos = center + Vector2(
			cos(s.angle) * s.radius,
			sin(s.angle) * s.radius
		)

		var d = s.radius / 800.0
		var core = pow(1.0 - d, 2.0)

		var size = s.size * s.layer * boost * (0.5 + core)

		var c = current_color
		c.a = 1.0

		draw_circle(pos, size, c)


# -------- WAVE --------
func draw_wave():
	var size = get_viewport_rect().size
	var center_y = size.y / 2

	var points = []

	for i in range(120):
		var t = float(i) / 120.0
		var x = t * size.x

		var y = center_y + sin(t * TAU * 4 + Time.get_ticks_msec() * 0.005) * 120 * smooth_volume

		points.append(Vector2(x, y))

	draw_polyline(points, current_color, 3.0)


# -------- EXPLOSION --------
func draw_explosion():
	var center = get_viewport_rect().size / 2

	for i in range(100):
		var a = randf() * TAU
		var r = randf() * (200 + impulse * 400)

		var pos = center + Vector2(cos(a), sin(a)) * r

		var c = current_color
		c.a = 0.7

		draw_circle(pos, randf_range(1, 4), c)


# -------- COLOR --------
func update_color():
	if stable_note == -1:
		return

	var hue_map = [
		0.0, 0.08, 0.16, 0.25,
		0.33, 0.42, 0.5, 0.58,
		0.66, 0.75, 0.83, 0.92
	]

	var hue = hue_map[stable_note]

	current_color = Color.from_hsv(hue, 1.0, 0.9)


# -------- AUDIO --------
func update_audio():
	if capture == null:
		return

	var frames = capture.get_frames_available()
	if frames == 0:
		return

	var buffer = capture.get_buffer(frames)

	var sum = 0.0
	var crossings = 0
	var prev = 0.0

	var size = buffer.size()

	for i in range(size):
		var v = buffer[i].x

		sum += v * v

		if sign(v) != sign(prev):
			crossings += 1

		prev = v

	var rms = sqrt(sum / size)
	volume = clamp(rms * 50.0, 0.0, 1.0)

	var sample_rate = AudioServer.get_mix_rate()
	var freq = (crossings * sample_rate) / (2.0 * size)

	if freq > 80 and freq < 1000:
		var midi = int(round(69 + 12 * log(freq / 440.0) / log(2.0)))
		note_class = midi % 12

	if note_class != stable_note:
		note_timer += 1
		if note_timer > 4:
			stable_note = note_class
			note_timer = 0
	else:
		note_timer = 0

	smooth_volume = lerp(smooth_volume, volume, 0.3)

	var diff = volume - prev_volume
	if diff > 0.04:
		impulse = 1.0

	impulse = lerp(impulse, 0.0, 0.2)
	prev_volume = volume
