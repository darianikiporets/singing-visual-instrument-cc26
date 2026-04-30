extends Node2D

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

# these buttons don't exist in the scene file so i created them in code
var mode_btn   : Button
var scale_btn  : Button
var drone_btn  : Button
var stats_label : Label
var info_panel  : PanelContainer
var info_visible := false   # tracks whether the info overlay is currently shown

var synth  : Synth

var sequence      : Array = []   # ordered list of primes to play through
var step          := 0           # which item in sequence is next
var seq_timer     := 0.0         # accumulates delta time between note triggers
var is_playing    := false       # false when stopped or paused
var current_prime := -1          # the prime that just played (-1 = none yet)
var current_mode  := 0           # active visual/sound mode index

const MODE_NAMES = [
	"PRIME MELODY", "CHAOS", "HARMONIC", "AMBIENT",
	"CONSTELLATION", "FRACTAL", "DRUM", "DUET"
]

var primes_played   := 0    # total count of prime triggers this session
var highest_prime   := 0    # largest prime that's been played
var last_prime_stat := -1   # previous prime, used to compute the gap
var gap_sum         := 0    # sum of all gaps between consecutive primes played
var gap_count       := 0    # number of gaps recorded, for averaging

var pulse        := 0.0          # 0..1 value that spikes on note hit then decays
var screen_shake := Vector2.ZERO # random offset applied to the spiral each frame
var shake_amount := 0.0          # how violent the shake currently is, decays over time
var bg_hue       := 0.0          # slowly drifts to shift the background colour

# particle and trail data is created here and handed to Spiral every frame for drawing
class Particle:
	var pos   : Vector2
	var vel   : Vector2
	var life  : float    # 1.0 = just born, 0.0 = dead
	var color : Color
	var size  : float

var particles : Array = []   # active sparkle particles
var trails    : Array = []   # glowing blobs left at prime positions after a note plays

var idle_timer := 0.0         # counts up when the player isn't doing anything
const IDLE_TIME = 12.0        # seconds of inactivity before screensaver kicks in
var idle_mode  := false       # true while the screensaver is running


func _ready() -> void:
	randomize()              # seed the RNG so particles and random sequences differ each run
	_setup_subsystems()      # create Synth and wire up all signals
	_setup_sliders()         # set sensible default ranges and values
	_create_dynamic_nodes()  # build buttons that aren't in the scene file
	_connect_signals()       # hook up UI button presses to our handler functions
	note_label.text = "press PLAY or SPACE"


func _setup_subsystems() -> void:
	synth  = Synth.new()
	add_child(synth)
	synth.setup(self)   # Synth creates its own AudioStreamPlayer under us

	# connect all cross-system signals in one place so it's easy to follow the data flow
	synth.note_triggered.connect(_on_note_triggered)
	spiral.prime_clicked.connect(_on_spiral_prime_clicked)
	spiral.prime_hovered.connect(_on_spiral_prime_hovered)


func _setup_sliders() -> void:
	# tempo: 0.08s between notes (very fast) up to 1.4s (slow and spacious)
	tempo_slider.min_value  = 0.08
	tempo_slider.max_value  = 1.4
	tempo_slider.step       = 0.02
	tempo_slider.value      = 0.45   # comfortable default feels musical without rushing
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step      = 0.01
	volume_slider.value     = 0.5


func _create_dynamic_nodes() -> void:
	var cl = $CanvasLayer
	# create the left-side control buttons in a column
	_make_btn(cl, "Mode",     "PRIME MELODY", Vector2(12, 60),  Vector2(160, 36), _on_mode_pressed)
	_make_btn(cl, "Scale",    "SCALE: MAJOR", Vector2(12, 100), Vector2(160, 36), _on_scale_pressed)
	_make_btn(cl, "DroneBtn", "DRONE: OFF",   Vector2(12, 140), Vector2(160, 36), _on_drone_pressed)
	_make_btn(cl, "TwinBtn",  "TWINS: ON",    Vector2(12, 180), Vector2(160, 36), _on_twins_pressed)
	_make_btn(cl, "InfoBtn",  "?",            Vector2(178, 100), Vector2(36, 36), _toggle_info)

	# stats label shows live session metrics in the bottom-left corner
	if not cl.has_node("StatsLabel"):
		stats_label = Label.new()
		stats_label.name = "StatsLabel"
		stats_label.position = Vector2(12, 420)
		stats_label.size = Vector2(200, 140)
		stats_label.add_theme_font_size_override("font_size", 11)
		cl.add_child(stats_label)
	else:
		stats_label = cl.get_node("StatsLabel")   # already exists if scene was reloaded

	# grab references to the buttons ,so i just created so other functions can update their text
	mode_btn  = cl.get_node("Mode")
	scale_btn = cl.get_node("Scale")
	drone_btn = cl.get_node("DroneBtn")

	_create_info_panel(cl)


func _make_btn(cl: Node, n: String, txt: String, pos: Vector2, sz: Vector2, cb: Callable) -> void:
	var b : Button
	if cl.has_node(n):
		# button already exists (e.g. after a scene reload),  reuse it but re-bind the callback
		b = cl.get_node(n)
		if b.pressed.is_connected(cb):
			b.pressed.disconnect(cb)   # disconnect first to avoid double-firing
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
		return   # already built, nothing to do
	info_panel = PanelContainer.new()
	info_panel.name = "InfoPanel"
	info_panel.position = Vector2(200, 120)
	info_panel.size = Vector2(360, 240)
	info_panel.visible = false   # hidden by default, shown when "?" is pressed
	cl.add_child(info_panel)

	# build a simple vertical layout inside the panel
	var vbox  = VBoxContainer.new()
	info_panel.add_child(vbox)
	var title = Label.new()
	title.text = "What are prime numbers?"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())   # thin horizontal rule under the title
	var body = Label.new()
	body.text = (
		"A prime number is divisible only by 1 and itself.\n\n"
		+ "Examples:   2   3   5   7   11   13   17   19\n\n"
		+ "Primes are infinite but unpredictable.\n\n"
		+ "The Ulam spiral reveals hidden diagonal\n"
		+ "patterns - no one fully understands why.\n\n"
		+ "This project turns those patterns into sound."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(body)
	var close = Button.new()
	close.text = "CLOSE"
	close.pressed.connect(func(): info_panel.visible = false; info_visible = false)
	vbox.add_child(close)


func _connect_signals() -> void:
	# wire up all the static buttons that exist in the scene file
	wave_btn.pressed.connect(_on_wave_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	stop_btn.pressed.connect(_on_stop_pressed)
	random_btn.pressed.connect(_on_random_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	input_box.text_submitted.connect(_on_submit)   # fires when player hits Enter in the text field

func _on_note_triggered(_prime: int, _note: String, _freq: float) -> void:
	pass  # Synth already updated current_note; Spiral state updated in play_prime


func _on_layer_note(prime: int) -> void:
	# light up a prime on the spiral without disturbing the main sequencer's envelope
	if not spiral.played_primes.has(prime):
		spiral.played_primes[prime] = {"color": _note_color(prime), "age": 0.0}
	else:
		spiral.played_primes[prime]["age"] = 0.0   # reset the fade timer so it glows fresh
	_spawn_trail(prime)


func _on_spiral_prime_clicked(prime: int) -> void:
	_play_key_note(prime)   # clicking a dot on the spiral plays it immediately


func _on_spiral_prime_hovered(_prime: int) -> void:
	pass  # Spiral handles its own hover drawing

func _on_wave_pressed() -> void:
	synth.wave_mode = (synth.wave_mode + 1) % 3   # cycle: sine → square → saw → sine

func _on_play_pressed() -> void:
	make_user_sequence()   # parse whatever's in the text box
	_start_playing()

func _on_stop_pressed() -> void:
	is_playing = false
	synth.release()
	note_label.text = "stopped  ·  SPACE to resume"

func _on_random_pressed() -> void:
	make_random_sequence()
	_start_playing()

func _on_submit(_text: String) -> void:
	make_user_sequence()   # same as pressing Play Enter key triggers it
	_start_playing()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://control.tscn")   # go back to the menu

func _on_mode_pressed() -> void:
	current_mode = (current_mode + 1) % MODE_NAMES.size()   # cycle through all 8 modes
	synth.apply_mode(current_mode)                           # update ADSR and waveform
	synth.chord_mode = (current_mode == 2 or current_mode == 7)  # only harmonic and duet stack chords
	spiral.current_mode = current_mode
	if is_playing:
		make_random_sequence()   # shuffle to a fresh sequence when the mode changes mid-play

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


func make_random_sequence() -> void:
	sequence.clear()
	var all_primes : Array = []
	var p = 2
	while all_primes.size() < 50:   # collect the first 50 primes
		all_primes.append(p)
		p = _next_prime_after(p)
	all_primes.shuffle()            # randomise order so every playthrough sounds different
	var count = randi_range(10, 16) # pick a random length so loops don't feel repetitive
	for i in range(min(count, all_primes.size())):
		sequence.append(all_primes[i])
	step = 0


func make_user_sequence() -> void:
	sequence.clear()
	# split the text box on commas, parse each chunk as a number, keep only valid primes
	for txt in input_box.text.split(","):
		var value = int(txt.strip_edges())
		if Spiral.is_prime(value):
			sequence.append(value)
	if sequence.size() == 0:
		make_random_sequence()   # if the input was empty or all invalid, fall back to random
	step = 0


func _start_playing() -> void:
	is_playing = true
	seq_timer  = 0.0
	step       = 0
	idle_timer = 0.0   # reset idle so screensaver doesn't kick in immediately
	idle_mode  = false


func _get_tempo() -> float:
	# each mode tweaks the tempo differently so the feel matches the aesthetic
	match current_mode:
		1: return max(0.08, tempo_slider.value * 0.45)  # chaos fires notes much faster
		3: return tempo_slider.value * 2.0              # ambient breathes slowly
		_: return tempo_slider.value                    # everything else respects the slider directly


func _next_prime_after(n: int) -> int:
	# brute-force upward search fine because we only call this 50 times at startup
	var x = n + 1
	while not Spiral.is_prime(x):
		x += 1
	return x


func play_prime(n: int) -> void:
	current_prime = n
	synth.volume  = volume_slider.value
	synth.play_prime(n, current_mode)   # hand off to Synth for audio

	pulse        = 1.0                                         # spike the pulse so the spiral animates
	shake_amount = 3.5 if current_mode == 1 else 0.8          # chaos mode shakes harder

	# mark this prime as played on the spiral so it gets colour and a glow ring
	spiral.played_primes[n] = {"color": _note_color(n), "age": 0.0}
	spiral.current_prime    = n

	# update session stats
	primes_played += 1
	if n > highest_prime: highest_prime = n
	if last_prime_stat >= 0:
		gap_sum   += abs(n - last_prime_stat)   # track how far apart consecutive primes are
		gap_count += 1
	last_prime_stat = n

	_spawn_particles(n)   # burst of sparkles at this prime's dot
	_spawn_trail(n)       # leave a glowing blob behind
	idle_timer = 0.0      # reset idle timer  something just happened
	idle_mode  = false


func _play_key_note(prime: int) -> void:
	is_playing = false   # stop the sequencer user is now playing manually
	play_prime(prime)

func _note_color(n: int) -> Color:
	# each prime gets a colour based on which of the 7 rainbow hues its value maps to
	var hue = float(n % 7) / 7.0
	match current_mode:
		0: return Color.from_hsv(hue, 0.7, 1.0)              # vivid full-spectrum colours
		1: return Color.from_hsv(randf(), 1.0, 1.0)           # chaos: fully random hue every time
		2: return Color.from_hsv(hue * 0.5 + 0.55, 0.6, 1.0) # harmonic: cooler blue/purple range
		3: return Color.from_hsv(hue * 0.3 + 0.55, 0.4, 0.85)# ambient: muted, desaturated
		4: return Color.from_hsv(hue, 0.5, 1.0)               # constellation: pastel full spectrum
		5: return Color.from_hsv(hue * 0.8, 0.8, 1.0)         # fractal: slightly compressed range
		6: return Color.from_hsv(0.0, 0.9, 1.0)               # drum: always red
		7: return Color.from_hsv(hue * 0.6 + 0.3, 0.7, 1.0)  # duet: warm mid-spectrum
	return Color.WHITE


func _spawn_particles(prime: int) -> void:
	var positions = spiral.build_prime_positions()
	if not positions.has(prime):
		return   # prime is off-screen, nothing to spawn at
	var sp    = positions[prime]
	var count = 14 if current_mode == 1 else 7   # chaos gets double the particles
	for i in range(count):
		var p   = Particle.new()
		p.pos   = sp
		var a   = randf() * TAU                               # random angle in all directions
		p.vel   = Vector2(cos(a), sin(a)) * randf_range(30.0, 100.0)  # random speed outward
		p.life  = 1.0
		p.size  = randf_range(2.0, 6.0)
		p.color = _note_color(prime)
		particles.append(p)


func _spawn_trail(prime: int) -> void:
	var positions = spiral.build_prime_positions()
	if not positions.has(prime):
		return
	# simple dict Spiral.gd draws these as fading blobs
	trails.append({"pos": positions[prime], "color": _note_color(prime), "life": 1.0})


func _update_particles(delta: float) -> void:
	for p in particles:
		p.pos  += p.vel * delta     # move outward
		p.vel  *= 0.91              # drag: slows down each frame so they don't fly forever
		p.life -= delta * 1.8       # fade out relatively quickly
	particles = particles.filter(func(p): return p.life > 0.0)   # remove dead ones


func _update_trails(delta: float) -> void:
	# decay each trail's life, so trails outlast particles so the glow lingers a bit
	for trail in trails:
		trail["life"] -= delta * 0.4   # fades to zero in ~2.5 seconds
	trails = trails.filter(func(trail): return trail["life"] > 0.0)  # remove dead ones
	# also tick the age of every prime that's been played so its glow fades in Spiral
	for key in spiral.played_primes.keys():
		spiral.played_primes[key]["age"] += delta


func _process(delta: float) -> void:
	# if nobody interacts for IDLE_TIME seconds, switch to ambient mode and auto-play
	idle_timer += delta
	if idle_timer > IDLE_TIME and not idle_mode and not is_playing:
		idle_mode    = true
		current_mode = 3   # ambient feels right for a screensaver
		spiral.current_mode = current_mode
		make_random_sequence()
		_start_playing()

	# screen shake: spikes when a note hits, then quickly damps to nothing
	if shake_amount > 0.0:
		shake_amount = max(0.0, shake_amount - delta * 8.0)   # decay 8 units per second
		screen_shake = Vector2(randf_range(-shake_amount, shake_amount),
							   randf_range(-shake_amount, shake_amount))
	else:
		screen_shake = Vector2.ZERO

	# slowly cycle the background hue so the colour never settles
	bg_hue = fmod(bg_hue + delta * 0.03, 1.0)

	# advance the sequencer, fire a note whenever enough time has passed
	if is_playing:
		seq_timer += delta
		if seq_timer >= _get_tempo():
			seq_timer = 0.0
			if step >= sequence.size(): step = 0   # loop back to the start
			if sequence.size() > 0:
				play_prime(sequence[step])
				step += 1

	# trigger the release a bit before the next note so notes don't blur into each other
	if synth.is_sounding() and seq_timer > _get_tempo() * 0.6:
		synth.release()

	# pulse decays smoothly back to 0 after each note spike
	pulse = max(0.0, pulse - delta * 2.5)

	_update_particles(delta)
	_update_trails(delta)

	# always read the volume slider live so the user can adjust mid-play
	synth.volume = volume_slider.value
	synth.update(delta, is_playing)

	# push our local state into Spiral every frame so it can draw correctly
	spiral.current_prime = current_prime
	spiral.current_mode  = current_mode
	spiral.pulse         = pulse
	spiral.screen_shake  = screen_shake
	spiral.bg_hue        = bg_hue
	spiral.particles     = particles
	spiral.trails        = trails
	spiral.queue_redraw()   

	# refresh button labels in case mode, scale, or wave changed
	var waves = ["SINE", "SQUARE", "SAW"]
	wave_btn.text  = waves[synth.wave_mode]
	mode_btn.text  = MODE_NAMES[current_mode]
	scale_btn.text = "SCALE: " + Synth.SCALE_NAMES[synth.current_scale]

	# update the big note display at the top of the screen
	if is_playing and current_prime >= 0:
		note_label.text = ">  PRIME " + str(current_prime) + "   NOTE " + synth.current_note
	elif not is_playing:
		note_label.text = "STOP  ·  click prime or SPACE"

	# update the stats sidebar
	var avg_gap = float(gap_sum) / float(max(gap_count, 1))
	var bpm_val = int(60.0 / max(_get_tempo(), 0.01))
	if stats_label:
		stats_label.text = (
			"played:  " + str(primes_played) + "\n"
			+ "highest: " + str(highest_prime) + "\n"
			+ "avg gap: " + ("%.1f" % avg_gap) + "\n"
			+ "BPM:     " + str(bpm_val) + "\n"
			+ "scale:   " + Synth.SCALE_NAMES[synth.current_scale] + "\n"
		)


func _input(event: InputEvent) -> void:
	if input_box.has_focus():
		return   # let the text box handle its own keypresses, so don't hijack them

	# mouse events go straight to Spiral so it can handle clicks, hover, zoom, and pan
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		spiral.handle_input(event)
		return

	if event is InputEventKey and event.pressed:
		idle_timer = 0.0   # any keypress resets the idle screensaver countdown
		match event.keycode:
			KEY_SPACE:
				if is_playing:
					_on_stop_pressed()
				else:
					make_random_sequence()
					_start_playing()
			KEY_1:       synth.wave_mode = 0   # switch to sine
			KEY_2:       synth.wave_mode = 1   # switch to square
			KEY_3:       synth.wave_mode = 2   # switch to saw
			KEY_F11:
				# toggle between fullscreen and windowed
				var wm = DisplayServer.window_get_mode()
				if wm == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			# QWERTY keyboard instrument, each key maps to one of the first 26 primes
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
