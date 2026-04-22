extends Node2D

# -------- STAR --------
class Star:
	var angle = 0.0
	var radius = 0.0
	var speed = 0.0
	var size = 1.0

var stars = []

var capture

var volume = 0.0
var smooth_volume = 0.0

var pitch = 0.0
var smooth_pitch = 0.0

@onready var bg = $ColorRect


# -------- READY --------
func _ready():
	randomize()
	bg.z_index = -1

	for i in range(900):
		stars.append(create_star())

	var idx = AudioServer.get_bus_index("MicBus")
	if idx != -1:
		for i in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectCapture:
				capture = e


# -------- CREATE STAR --------
func create_star():
	var s = Star.new()

	s.angle = randf() * TAU
	s.radius = pow(randf(), 2.0) * 900.0
	s.angle += s.radius * 0.04

	s.speed = randf_range(0.2, 0.8)
	s.size = randf_range(1.0, 2.5)

	return s


# -------- PROCESS --------
func _process(delta):
	update_audio()
	update_galaxy(delta)
	queue_redraw()


# -------- GALAXY --------
func update_galaxy(delta):
	var rot_speed = 0.2 + smooth_volume * 2.5

	for s in stars:
		s.angle += rot_speed * s.speed * delta
		s.radius += sin(s.angle * 2.0) * 0.2


# -------- DRAW --------
func _draw():
	if smooth_volume < 0.02:
		return

	var size = get_viewport().get_visible_rect().size
	var center = size / 2

	for s in stars:
		var pos = Vector2(
			center.x + cos(s.angle) * s.radius,
			center.y + sin(s.angle) * s.radius
		)

		var c = pick_color()
		c.a = smooth_volume

		draw_circle(pos, s.size, c)


# -------- PITCH (AUTOCORRELATION) --------
func estimate_pitch(buffer):
	var size = buffer.size()
	if size < 2:
		return 0.0

	var best_offset = 0
	var best_corr = 0.0

	for offset in range(20, 200):
		var corr = 0.0

		for i in range(size - offset):
			corr += buffer[i].x * buffer[i + offset].x

		if corr > best_corr:
			best_corr = corr
			best_offset = offset

	if best_offset == 0:
		return 0.0

	return 44100.0 / best_offset


# -------- NOTE --------
func freq_to_note(freq):
	if freq <= 0:
		return -1

	var note = int(round(12.0 * log(freq / 440.0) / log(2.0)))
	return (note % 12 + 12) % 12


func is_major_note(note):
	var major = [0, 2, 4, 5, 7, 9, 11]
	return note in major


# -------- COLOR --------
func pick_color():
	var note = freq_to_note(smooth_pitch)

	if note == -1:
		return Color(0.1, 0.1, 0.2)

	var is_major = is_major_note(note)

	if is_major:
		return Color.from_hsv(
			randf_range(0.02, 0.12), # тёплый
			0.9,
			randf_range(0.8, 1.0)
		)
	else:
		return Color.from_hsv(
			randf_range(0.55, 0.75), # холодный
			0.8,
			randf_range(0.8, 1.0)
		)


# -------- AUDIO --------
func update_audio():
	if capture == null:
		return

	var frames = capture.get_frames_available()

	if frames > 0:
		var buffer = capture.get_buffer(frames)

		var max_val = 0.0

		for frame in buffer:
			max_val = max(max_val, abs(frame.x))

		volume = clamp(max_val * 10.0, 0.0, 1.0)

		pitch = estimate_pitch(buffer)

	smooth_volume = lerp(smooth_volume, volume, 0.1)
	smooth_pitch = lerp(smooth_pitch, pitch, 0.1)

	if bg:
		bg.color = Color(0, 0, 0.05)
