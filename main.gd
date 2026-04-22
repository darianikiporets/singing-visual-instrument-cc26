extends Node2D

# -------- STAR --------
class Star:
	var angle = 0.0
	var radius = 0.0
	var speed = 0.0
	var size = 1.0
	var layer = 1.0

var stars = []
var nebula_points = []

var capture

var volume = 0.0
var smooth_volume = 0.0

var note_class = -1

var peak = false
var flash_power = 0.0

@onready var bg = $ColorRect

var current_color = Color.from_hsv(0.65, 1.0, 0.9)


# -------- READY --------
func _ready():
	randomize()
	bg.z_index = -1

	# -------- STARS --------
	for i in range(600):
		stars.append(create_star())

	# -------- NEBULA (создаётся ОДИН раз) --------
	for i in range(80):
		var r = pow(randf(), 2.0) * 700.0
		var angle = randf() * TAU

		# лёгкая привязка к спирали
		angle += r * 0.02

		nebula_points.append({
			"angle": angle,
			"radius": r,
			"size": randf_range(20, 60)
		})

	# -------- MIC --------
	var idx = AudioServer.get_bus_index("MicBus")
	if idx != -1:
		for i in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectCapture:
				capture = e


# -------- CREATE STAR --------
func create_star():
	var s = Star.new()

	var r = pow(randf(), 1.8) * 900.0

	var arms = 4
	var arm = randi() % arms

	var arm_angle = arm * TAU / arms
	var twist = r * 0.025

	s.radius = r
	s.angle = arm_angle + twist + randf_range(-0.2, 0.2)

	s.speed = randf_range(0.3, 1.0)
	s.size = randf_range(1.0, 2.5)
	s.layer = randf_range(0.8, 1.4)

	return s


# -------- PROCESS --------
func _process(delta):
	update_audio()
	update_galaxy(delta)
	queue_redraw()

	# лёгкий след движения
	bg.color = Color(0, 0, 0, 0.08 + smooth_volume * 0.1)


# -------- GALAXY --------
func update_galaxy(delta):
	var rot_speed = 0.03 + smooth_volume * 0.8

	for s in stars:
		s.angle += rot_speed * s.speed * delta


# -------- DRAW --------
func _draw():
	var rect = get_viewport().get_visible_rect()
	var center = rect.size / 2

	var size_boost = 1.0 + smooth_volume * 1.2 + flash_power * 1.5

	# -------- NEBULA (СТАБИЛЬНАЯ) --------
	for n in nebula_points:
		var pos = center + Vector2(
			cos(n.angle),
			sin(n.angle)
		) * n.radius

		var c = current_color
		c.a = 0.06 + smooth_volume * 0.05

		draw_circle(pos, n.size, c)

	# -------- STARS --------
	for s in stars:
		var pos = Vector2(
			center.x + cos(s.angle) * s.radius,
			center.y + sin(s.angle) * s.radius
		)

		var dist = s.radius / 900.0
		var core = pow(1.0 - dist, 2.0)

		var c = current_color
		c.a = clamp(0.5 + core * 0.5, 0.5, 1.0)

		var final_size = s.size * s.layer * size_boost * (0.6 + core)

		draw_circle(pos, final_size, c)

		# лёгкий glow только у части звёзд
		if s.layer > 1.2:
			var glow = c
			glow.a = 0.15
			draw_circle(pos, final_size * 1.4, glow)

	# -------- CORE --------
	for i in range(20):
		var angle = randf() * TAU
		var r = randf() * 30

		var pos = center + Vector2(cos(angle), sin(angle)) * r

		var c = current_color
		c.a = 0.1

		draw_circle(pos, randf_range(2, 4), c)

	# -------- PEAK BURST --------
	if peak:
		for i in range(25):
			var angle = randf() * TAU
			var r = randf() * 200

			var pos = center + Vector2(cos(angle), sin(angle)) * r

			var c = current_color
			c.a = 0.15

			draw_circle(pos, randf_range(2, 6), c)


# -------- COLOR --------
func update_color():
	var minor_notes = [0, 2, 5, 9]
	var major_notes = [1, 4, 7, 11]

	if note_class in minor_notes:
		current_color = Color.from_hsv(0.65, 1.0, 0.9)

	elif note_class in major_notes:
		current_color = Color.from_hsv(0.08, 1.0, 0.9)

	else:
		current_color = Color.from_hsv(0.6, 1.0, 0.9)


# -------- AUDIO --------
func update_audio():
	if capture == null:
		return

	var frames = capture.get_frames_available()

	if frames > 0:
		var buffer = capture.get_buffer(frames)

		var max_val = 0.0
		var crossings = 0
		var prev = 0.0

		for frame in buffer:
			var v = frame.x

			max_val = max(max_val, abs(v))

			if sign(v) != sign(prev):
				crossings += 1

			prev = v

		volume = clamp(max_val * 10.0, 0.0, 1.0)

		var sample_rate = AudioServer.get_mix_rate()
		var freq = (crossings * sample_rate) / (2.0 * buffer.size())

		var old_note = note_class

		if freq > 50 and freq < 2000:
			var midi = int(round(69 + 12 * log(freq / 440.0) / log(2.0)))
			note_class = midi % 12

		if note_class != old_note:
			update_color()

	smooth_volume = lerp(smooth_volume, volume, 0.08)

	if smooth_volume > 0.6:
		flash_power = lerp(flash_power, 1.0, 0.2)
	else:
		flash_power = lerp(flash_power, 0.0, 0.05)

	peak = smooth_volume > 0.6
