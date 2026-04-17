extends Node2D

var capture
var volume = 0.0
var smooth_volume = 0.0

var threshold = 0.15
var was_loud = false



func _ready():
	var idx = AudioServer.get_bus_index("MicBus")

	if idx == -1:
		print("no micbus")
		return

	for i in range(AudioServer.get_bus_effect_count(idx)):
		var e = AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectCapture:
			capture = e
			print("Capture")

	if capture == null:
		print(" No Capture")
	else:
		print("Mic is ready")


func _process(delta):
	if capture == null:
		return

	var frames = capture.get_frames_available()

	if frames > 0:
		var buffer = capture.get_buffer(frames)

		var max_val = 0.0

		for frame in buffer:
			max_val = max(max_val, abs(frame.x))

		volume = clamp(max_val * 10.0, 0.0, 1.0)

	smooth_volume = lerp(smooth_volume, volume, 0.1)

	var is_loud = smooth_volume > threshold


	if is_loud and not was_loud:
		print("started talking")

	if not is_loud and was_loud:
		print("silence")

	was_loud = is_loud


	print("Volume:", smooth_volume)
