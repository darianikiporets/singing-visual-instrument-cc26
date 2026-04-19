extends Node2D

# -------- STAR --------
class Star:
	var angle = 0.0
	var radius = 0.0
	var speed = 0.0
	var size = 1.0
	var color = Color.WHITE

# -------- GAMMA BURST --------
class Burst:
	var pos = Vector2.ZERO
	var angle = 0.0
	var length = 0.0
	var speed = 0.0
	var life = 1.0
	var color = Color.WHITE


var stars = []
var bursts = []

var capture

var volume = 0.0
var smooth_volume = 0.0
var prev_volume = 0.0

var energy = 0.0
var smooth_energy = 0.0

# NEW: pitch
var pitch = 0.0
var smooth_pitch = 0.0

var flash = 0.0

@onready var bg = $ColorRect


func _ready():
	randomize()
	bg.z_index = -1

	for i in range(1200):
		stars.append(create_star())

	var idx = AudioServer.get_bus_index("MicBus")
	if idx != -1:
		for i in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectCapture:
				capture = e


# -------- STAR --------
func create_star():
	var s = Star.new()
	s.angle = randf() * TAU
	s.radius = randf_range(50, 900)
	s.angle += s.radius * 0.04
	s.speed = randf_range(0.1, 0.6)
	s.size = randf_range(1.0, 3.0)
	s.color = pick_color()
	return s


# -------- PROCESS --------
func _process(delta):
	update_audio()

	update_galaxy(delta)
	update_bursts(delta)

	var delta_v = volume - prev_volume

	if volume > 0.2 and delta_v > 0.05:
		flash = 1.0

		for i in range(50):
			spawn_burst()

	prev_volume = volume

	flash = lerp(flash, 0.0, 0.1)

	queue_redraw()


# -------- GALAXY --------
func update_galaxy(delta):
	var rot_speed = 0.2 + smooth_volume * 2.5

	for s in stars:
		s.angle += rot_speed * s.speed * delta
		s.radius += sin(s.angle * 2.0) * 0.3
		s.color = pick_color()


# -------- BURSTS --------
func spawn_burst():
	var b = Burst.new()

	var size = get_viewport().get_visible_rect().size
	var center = size / 2

	b.pos = center
	b.angle = randf() * TAU
	b.length = randf_range(20, 60)
	b.speed = randf_range(500, 1000)
	b.life = 1.0
	b.color = pick_color()

	bursts.append(b)


func update_bursts(delta):
	for b in bursts:
		b.length += b.speed * delta
		b.life -= delta * 1.5

	bursts = bursts.filter(func(b): return b.life > 0.0)


# -------- DRAW --------
func _draw():
	var size = get_viewport().get_visible_rect().size
	var center = size / 2

	draw_circle(center, 60 + smooth_volume * 120, Color(1,1,1,0.15 + flash * 0.3))

	for s in stars:
		var pos = Vector2(
			center.x + cos(s.angle) * s.radius,
			center.y + sin(s.angle) * s.radius
		)

		var c = s.color.lightened(flash)
		draw_circle(pos, s.size, c)

	for b in bursts:
		var dir = Vector2(cos(b.angle), sin(b.angle))
		var start = b.pos
		var end = b.pos + dir * b.length

		var c = b.color
		c.a = b.life

		draw_line(start, end, c, 2.0 + b.life * 3.0)
		draw_line(start, end, Color(c.r, c.g, c.b, c.a * 0.2), 6.0)


# -------- COLOR BASED ON PITCH --------
func pick_color():
	# LOW pitch → cold
	if smooth_pitch < 0.5:
		return Color.from_hsv(randf_range(0.55, 0.75), 0.8, 1.0)
	else:
	# HIGH pitch → warm
		return Color.from_hsv(randf_range(0.0, 0.15), 0.9, 1.0)


# -------- AUDIO --------
func update_audio():
	if capture == null:
		return

	var frames = capture.get_frames_available()

	if frames > 0:
		var buffer = capture.get_buffer(frames)

		var max_val = 0.0
		var avg = 0.0

		for frame in buffer:
			var v = abs(frame.x)
			max_val = max(max_val, v)
			avg += v

		avg /= buffer.size()

		volume = clamp(max_val * 20.0, 0.0, 1.0)
		energy = clamp(avg * 60.0, 0.0, 1.0)

		# APPROX pitch (very simple)
		pitch = clamp(avg * 10.0, 0.0, 1.0)

	smooth_volume = lerp(smooth_volume, volume, 0.1)
	smooth_energy = lerp(smooth_energy, energy, 0.05)
	smooth_pitch = lerp(smooth_pitch, pitch, 0.1)

	if bg:
		bg.color = Color(0, 0, 0.08)
