# make script globally usable as Spiral
class_name Spiral
extends Node2D

# emitted when player clicks on a prime number dot
signal prime_clicked(prime: int)
# emitted when mouse moves over a prime number dot
signal prime_hovered(prime: int)

# keeps track of every prime the player has played, along with color/age data
var played_primes : Dictionary = {}
# short-lived glowing trail blobs left behind after a prime plays
var trails        : Array      = []
# individual floating sparkles that shoot out on prime click
var particles     : Array      = []
# decorative background star field, generated once on startup
var stars         : Array      = []

# which prime is currently selected/active (-1 means none)
var current_prime := -1
# which visual/audio mode is active (0-6, each changes behaviour and look)
var current_mode  := 0
# 0.0 to 1.0 oscillating value used to animate rings and glow on the active prime
var pulse         := 0.0
# whether to highlight twin prime pairs and draw lines between them
var show_twins    := true
# tiny random offset applied to everything so the screen wobbles after a click
var screen_shake  := Vector2.ZERO
# slowly drifting hue for the deep background colour
var bg_hue        := 0.0

# how zoomed in or out the spiral is (1.0 = normal)
var zoom_scale := 1.0
# how far the view has been panned from centre
var pan_offset := Vector2.ZERO
# true while the player holds right-mouse to drag the view
var _is_panning  := false
# where the mouse was when right-click drag started
var _pan_start   := Vector2.ZERO
# what pan_offset was at the start of the current drag
var _pan_origin  := Vector2.ZERO
# which prime (if any) the mouse is currently hovering over
var _hovered_prime := -1

# how many background stars to scatter across the screen
const STAR_COUNT = 180
# highest number we bother to check and draw (performance ceiling)
const REVEAL_MAX = 1500


func _ready() -> void:
	# first thing on scene load: scatter the background star field
	_generate_stars()


func _generate_stars() -> void:
	var vp = get_viewport_rect().size  # grab current window dimensions
	for i in range(STAR_COUNT):
		var tint_roll = randf()  # random roll to decide this star's colour temperature
		var tint : Color
		if tint_roll < 0.5:
			tint = Color(0.85, 0.9, 1.0)   # cool blue-white, most common
		elif tint_roll < 0.8:
			tint = Color(1.0, 1.0, 1.0)    # pure white, less common
		else:
			tint = Color(1.0, 0.9, 0.7)    # warm yellow-white, rarest
		stars.append({
			"pos":    Vector2(randf() * vp.x, randf() * vp.y),  # random screen position
			"size":   randf_range(0.4, 2.8),   # tiny dot to small circle
			"bright": randf_range(0.25, 1.0),  # base brightness before twinkle
			"speed":  randf_range(0.6, 2.2),   # how fast this star pulses
			"offset": randf() * TAU,           # phase offset so stars don't all pulse together
			"tint":   tint                     # the colour temperature we rolled above
		})


# returns true if n has no divisors other than 1 and itself
static func is_prime(n: int) -> bool:
	if n < 2:      return false       # 0 and 1 are not prime by definition
	if n == 2:     return true        # 2 is the only even prime
	if n % 2 == 0: return false       # skip all other even numbers fast
	for i in range(3, int(sqrt(float(n))) + 1, 2):  # only need to check up to sqrt(n)
		if n % i == 0: return false   # found a divisor, not prime
	return true


# a twin prime sits exactly 2 apart from another prime (e.g. 11 and 13)
static func is_twin_prime(n: int) -> bool:
	return is_prime(n) and (is_prime(n - 2) or is_prime(n + 2))


# the spacing between grid cells changes depending on the active visual mode
func cell_size() -> float:
	match current_mode:
		1: return 10.0   # tighter grid for mode 1
		3: return 14.0   # wider grid for mode 3
		4: return 12.0   # medium grid for constellation mode
		_: return 11.0   # default for everything else


# walks the Ulam spiral path and records the screen position of every visible prime
func build_prime_positions() -> Dictionary:
	var viewport  = get_viewport_rect().size
	var center    = viewport / 2.0 + pan_offset   # centre shifts when panned
	var cell      = cell_size() * zoom_scale       # scale cell size by current zoom
	var pos       = center    # start at the centre of the spiral
	var dir       = Vector2.RIGHT   # first step goes right (classic Ulam spiral)
	var steps_t   = 0    # how many steps taken in the current straight run
	var step_size = 1    # how long the current straight run is
	var turns     = 0    # total number of 90-degree turns made so far
	var number    = 1    # current integer being placed on the grid
	var result    : Dictionary = {}
	var margin    = 20.0   # don't draw primes right at the screen edge
	var bounds    = Rect2(margin, margin, viewport.x - margin * 2, viewport.y - margin * 2)

	while number <= REVEAL_MAX:
		if is_prime(number) and bounds.has_point(pos):
			result[number] = pos   # store this prime's screen coords
		pos     += dir * cell   # advance one step along the spiral
		number  += 1
		steps_t += 1
		if steps_t >= step_size:   # finished a straight segment, time to turn
			steps_t = 0
			dir     = Vector2(-dir.y, dir.x)   # rotate 90 degrees counter-clockwise
			turns   += 1
			if turns % 2 == 0:   # every two turns the segment length grows by 1
				step_size += 1

	return result


# routes raw input events to whatever the spiral needs to do with them
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_panning = event.pressed   # start or stop right-drag panning
			if event.pressed:
				_pan_start  = event.position   # remember where the drag began
				_pan_origin = pan_offset       # remember the offset at drag start
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_check_click(event.position)   # left click: see if a prime was hit
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_scale = clamp(zoom_scale * 1.1, 0.3, 4.0)   # zoom in, cap at 4×
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_scale = clamp(zoom_scale * 0.9, 0.3, 4.0)   # zoom out, cap at 0.3×
	elif event is InputEventMouseMotion:
		if _is_panning:
			pan_offset = _pan_origin + (event.position - _pan_start)   # drag the view
		else:
			_check_hover(event.position)   # not dragging: update which prime is hovered


# checks if the click landed close enough to any prime dot
func _check_click(mouse_pos: Vector2) -> void:
	var positions = build_prime_positions()
	var threshold = cell_size() * zoom_scale * 0.65   # hit radius scales with zoom
	for prime in positions.keys():
		if mouse_pos.distance_to(positions[prime]) < threshold:
			emit_signal("prime_clicked", prime)   # tell the parent a prime was clicked
			return   # only trigger one prime per click


# updates _hovered_prime as the mouse moves around
func _check_hover(mouse_pos: Vector2) -> void:
	var positions  = build_prime_positions()
	var threshold  = cell_size() * zoom_scale * 0.65
	var prev       = _hovered_prime   # remember old value so we can detect changes
	_hovered_prime = -1               # assume nothing is hovered until proven otherwise
	for prime in positions.keys():
		if mouse_pos.distance_to(positions[prime]) < threshold:
			_hovered_prime = prime
			break   # stop after finding the first match
	if _hovered_prime != prev:
		emit_signal("prime_hovered", _hovered_prime)   # notify only when it actually changed


func _draw() -> void:
	var viewport = get_viewport_rect().size
	var t        = Time.get_ticks_msec() * 0.001   # time in seconds, for animations

	# deep space background: very dark, slowly shifting hue
	draw_rect(Rect2(Vector2.ZERO, viewport),
		Color.from_hsv(bg_hue, 0.18, 0.04))

	# soft dark circles in each corner to vignette the edges
	draw_circle(Vector2.ZERO,           viewport.length() * 0.55, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(viewport.x, 0), viewport.length() * 0.55, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(0, viewport.y), viewport.length() * 0.55, Color(0, 0, 0, 0.18))
	draw_circle(viewport,               viewport.length() * 0.55, Color(0, 0, 0, 0.18))

	# draw each background star with a gentle sine-wave twinkle
	for star in stars:
		var twinkle = 0.5 + 0.5 * sin(t * star["speed"] + star["offset"])   # 0..1 pulse
		var alpha   = star["bright"] * (0.3 + 0.7 * twinkle)
		var c       = star["tint"]
		if star["size"] > 1.8:   # bigger stars get a faint soft glow halo
			draw_circle(star["pos"], star["size"] * 2.2, Color(c.r, c.g, c.b, alpha * 0.12))
		draw_circle(star["pos"], star["size"], Color(c.r, c.g, c.b, alpha))

	var prime_positions = build_prime_positions()
	var shifted : Dictionary = {}
	for k in prime_positions.keys():
		shifted[k] = prime_positions[k] + screen_shake   # apply shake offset to every dot

	# thin lines connecting twin prime pairs, brighter if either has been played
	if show_twins:
		for prime in shifted.keys():
			if is_twin_prime(prime) and shifted.has(prime + 2):
				var either_active = played_primes.has(prime) or played_primes.has(prime + 2)
				var alpha = 0.65 if either_active else 0.12   # pop when played, subtle otherwise
				var width = 1.2  if either_active else 0.6
				draw_line(shifted[prime], shifted[prime + 2],
					Color(0.5, 0.85, 1.0, alpha), width)

	# mode 4 draws a line connecting played primes in the order they were played
	if current_mode == 4:
		var pkeys = played_primes.keys()
		pkeys.sort()   # sort numerically so lines travel in ascending prime order
		for i in range(pkeys.size() - 1):
			var pa = pkeys[i]; var pb = pkeys[i + 1]
			if shifted.has(pa) and shifted.has(pb):
				var alpha = clamp(1.0 - played_primes[pa]["age"] * 0.07, 0.1, 0.7)   # fades with age
				draw_line(shifted[pa], shifted[pb], Color(0.4, 0.7, 1.0, alpha), 1.2)

	# mode 5 draws a spinning polygon centred on the active prime
	if current_mode == 5 and current_prime > 0 and shifted.has(current_prime):
		var fp    = shifted[current_prime]
		var sides = (current_prime % 5) + 3   # 3 to 7 sides depending on the prime value
		var rad   = 16.0 + pulse * 28.0       # polygon grows and shrinks with the pulse
		for i in range(sides):
			var a1 = TAU * float(i) / float(sides)
			var a2 = TAU * float((i + 1) % sides) / float(sides)
			draw_line(
				fp + Vector2(cos(a1), sin(a1)) * rad,
				fp + Vector2(cos(a2), sin(a2)) * rad,
				Color.from_hsv(float(i) / float(sides), 0.9, 1.0, pulse * 0.9), 1.4)  # rainbow edges

	# draw every prime dot on the spiral
	for prime in shifted.keys():
		var ppos   = shifted[prime]
		var is_cur = (prime == current_prime)    # this dot is currently playing
		var is_hov = (prime == _hovered_prime)   # mouse is hovering over this dot
		var played = played_primes.has(prime)    # this prime has been played before
		var twin   = show_twins and is_twin_prime(prime)

		if is_cur:
			# big expanding glow for the active prime
			draw_circle(ppos, 22.0 * pulse, Color(1.0, 0.4, 0.05, 0.08 * pulse))
			# three concentric pulsing rings
			for ring in range(3):
				var rr = (7.0 + ring * 9.0) + pulse * 12.0   # each ring is bigger than the last
				var ra = (0.6 - ring * 0.18) * pulse          # outer rings are more transparent
				draw_arc(ppos, rr, 0, TAU, 48, Color(1.0, 0.55, 0.1, ra), 1.5)
			draw_circle(ppos, 5.5 + pulse * 3.0, Color(1.0, 0.6, 0.15, 0.9 * pulse))  # bright core
		elif played:
			var pcol = played_primes[prime]["color"]
			var age  = played_primes[prime]["age"]
			var fade = clamp(1.0 - age * 0.008, 0.0, 1.0)   # fades to nothing over time
			draw_circle(ppos, 9.0 * fade, Color(pcol.r, pcol.g, pcol.b, 0.12 * fade))  # soft glow
			draw_arc(ppos, 5.0, 0, TAU, 24, Color(pcol.r, pcol.g, pcol.b, 0.5 * fade), 1.0)  # ring
		elif twin:
			# subtle blue hint on twin primes that haven't been played yet
			draw_circle(ppos, 4.5, Color(0.4, 0.85, 1.0, 0.09))

		if is_hov and not is_cur:
			# white highlight ring when hovering (don't override the active prime's look)
			draw_circle(ppos, 8.0, Color(1, 1, 1, 0.08))
			draw_arc(ppos, 8.0, 0, TAU, 24, Color(1, 1, 1, 0.55), 1.2)

		var col   : Color
		var fsize : int
		if is_cur:
			col   = Color(1.0, 0.75, 0.2, 1.0)         
			fsize = int(10.0 + pulse * 5.0)          # size breathes with the pulse
		elif played:
			var age  = played_primes[prime]["age"]
			var fade = clamp(1.0 - age * 0.008, 0.35, 1.0)   # never fully invisible
			var pc   = played_primes[prime]["color"]
			col      = Color(pc.r, pc.g, pc.b, fade)
			fsize    = 9
		elif is_hov:
			col   = Color(1.0, 1.0, 1.0, 1.0)   # bright white on hover
			fsize = 10
		elif twin:
			col   = Color(0.5, 0.88, 1.0, 0.65)   # soft cyan for twin primes
			fsize = 8
		else:
			col   = Color(0.3, 0.42, 0.62, 0.5)   # dim blue-grey for unplayed primes
			fsize = 7

		# draw the prime number as text, centred on its dot
		var txt   = str(prime)
		var txt_w = fsize * len(txt) * 0.52   # rough pixel width estimate for centering
		draw_string(ThemeDB.fallback_font,
			ppos + Vector2(-txt_w * 0.5, fsize * 0.38),   # nudge up so text sits on the dot
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

	# draw every active trail blob (left by recently played primes)
	# draw every active trail blob left behind when a prime was played
	for trail in trails:
		var tc = trail["color"]
		var tl = trail["life"]   # 1.0 = just spawned, 0.0 = fully faded
		draw_circle(trail["pos"] + screen_shake, 7.0 * tl, Color(tc.r, tc.g, tc.b, tl * 0.15))  # wide soft glow
		draw_circle(trail["pos"] + screen_shake, 3.5 * tl, Color(tc.r, tc.g, tc.b, tl * 0.55))  # brighter core

	# draw each floating particle sparkle
	for p in particles:
		var pc = p.color
		var pl = p.life
		draw_circle(p.pos, p.size * pl * 2.2, Color(pc.r, pc.g, pc.b, pl * 0.12))  # soft halo
		draw_circle(p.pos, p.size * pl,        Color(pc.r, pc.g, pc.b, pl * 0.9))  # solid dot

	# mode 6 shows a red bar at the bottom that pulses to the beat like a drum hit indicator
	if current_mode == 6:
		var bw = 200.0
		var bh = 36.0 * pulse   # height driven by pulse so it slams and decays
		var bx = viewport.x / 2.0 - bw / 2.0   # centred horizontally
		var by = viewport.y - 70.0              # near the bottom of the screen
		draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 0.15, 0.15, 0.8))           # filled red bar
		draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 0.4, 0.4, 0.4), false, 1.0) # lighter outline

	# floating tooltip that appears above whichever prime the mouse is over
	if _hovered_prime > 0 and shifted.has(_hovered_prime):
		var hp  = shifted[_hovered_prime]
		var tip = "prime " + str(_hovered_prime)
		if is_twin_prime(_hovered_prime):
			tip += "  [twin pair]"   # extra badge if it's a twin prime
		var tw = tip.length() * 6.5 + 16.0   # estimate tooltip box width from text length
		draw_rect(Rect2(hp.x + 10, hp.y - 18, tw, 18), Color(0.05, 0.05, 0.1, 0.75))  # dark bg pill
		draw_string(ThemeDB.fallback_font,
			hp + Vector2(14, -5),
			tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.95, 1.0, 0.95))

	# keyboard shortcut reminder along the bottom, barely visible so it doesn't distract
	var hint = "Q-M: play notes   scroll: zoom   RMB: pan   ESC: clear   F11: fullscreen"
	draw_string(ThemeDB.fallback_font,
		Vector2(viewport.x / 2.0 - 260, viewport.y - 10),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.65, 0.9, 0.28))
