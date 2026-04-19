extends Node2D

var capture

var volume = 0.0
var smooth_volume = 0.0
var prev_volume = 0.0

var threshold = 0.1
var was_loud = false

# Peak detection settings
var peak_threshold = 0.25
var flash_strength = 0.0

@onready var sprite = $Sprite2D
@onready var bg = $ColorRect


func _ready():
	var idx = AudioServer.get_bus_index("MicBus")

	if idx == -1:
		print("MicBus not found")
		return

	# Find AudioEffectCapture in the bus
	for i in range(AudioServer.get_bus_effect_count(idx)):
		var e = AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectCapture:
			capture = e
			print("Capture found")

	if capture == null:
		print("Capture not found")
	else:
		print("Microphone ready")


func _process(delta):
	if capture == null:
		return

	var frames = capture.get_frames_available()

	if frames > 0:
		var buffer = capture.get_buffer(frames)

		var max_val = 0.0

		# Calculate max amplitude from buffer
		for frame in buffer:
			max_val = max(max_val, abs(frame.x))

		# Amplify and clamp the signal
		volume = clamp(max_val * 10.0, 0.0, 1.0)

	# Smooth the signal to reduce jitter
	smooth_volume = lerp(smooth_volume, volume, 0.1)

	# Detect speaking state
	var is_loud = smooth_volume > threshold

	if is_loud and not was_loud:
		print("Started speaking")

	if not is_loud and was_loud:
		print("Silence")

	# Peak detection (sudden increase in volume)
	var delta_volume = smooth_volume - prev_volume

	if delta_volume > peak_threshold:
		flash_strength = 1.0

	prev_volume = smooth_volume
	was_loud = is_loud

	# Fade out flash effect over time
	flash_strength = lerp(flash_strength, 0.0, 0.1)

	# Background color reacts to peaks
	if bg:
		bg.color = Color.from_hsv(
			0.6 - smooth_volume * 0.6,  # hue
			0.7,
			0.5 + smooth_volume
		)

	# Scale visual element based on volume and peaks
	if sprite:
		var scale_value = 1.0 + smooth_volume * 2.0 + flash_strength
		sprite.scale = Vector2.ONE * scale_value

	# Debug output
	print("Volume:", smooth_volume)
