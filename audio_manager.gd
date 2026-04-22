extends Node

signal volume_changed(v)
signal pitch_changed(p)
signal peak_detected()

var capture

var volume = 0.0
var smooth_volume = 0.0
var prev_volume = 0.0

var pitch = 0.0
var smooth_pitch = 0.0


func _ready():
	var idx = AudioServer.get_bus_index("MicBus")

	if idx == -1:
		return

	for i in range(AudioServer.get_bus_effect_count(idx)):
		var e = AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectCapture:
			capture = e


func _process(delta):
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

		volume = clamp(max_val * 12.0, 0.0, 1.0)
		pitch = clamp(avg * 150.0, 0.0, 1.0)

	smooth_volume = lerp(smooth_volume, volume, 0.12)
	smooth_pitch = lerp(smooth_pitch, pitch, 0.08)

	emit_signal("volume_changed", smooth_volume)
	emit_signal("pitch_changed", smooth_pitch)

	var delta_v = smooth_volume - prev_volume

	if delta_v > 0.10:
		emit_signal("peak_detected")

	prev_volume = smooth_volume
