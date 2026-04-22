extends Node

var capture

var volume = 0.0
var smooth_volume = 0.0

var pitch = 0.0
var smooth_pitch = 0.0


func _ready():
	var idx = AudioServer.get_bus_index("MicBus")

	if idx != -1:
		for i in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, i)
			if e is AudioEffectCapture:
				capture = e


func _process(delta):
	update_audio()


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
		pitch = crossings * 20.0

	smooth_volume = lerp(smooth_volume, volume, 0.1)
	smooth_pitch = lerp(smooth_pitch, pitch, 0.03)


func get_note():
	if smooth_pitch <= 0:
		return -1

	var note = int(round(12.0 * log(smooth_pitch / 440.0) / log(2.0)))
	return (note % 12 + 12) % 12
