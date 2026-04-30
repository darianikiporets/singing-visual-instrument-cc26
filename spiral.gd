# Spiral.gd — visual polish update
# Changes from previous version:
#   - deeper space background, stars have colour tint (blue/white/warm)
#   - prime dots: unplayed = more visible, played = brighter glow ring
#   - active note: larger pulse rings, warm orange glow fill
#   - twin prime lines: thicker when either is active
#   - trail circles: larger, slower fade
#   - particles: drawn with additive-style brightness via alpha layers

class_name Spiral
extends Node2D

signal prime_clicked(prime: int)
signal prime_hovered(prime: int)

var played_primes : Dictionary = {}
var trails        : Array      = []
var particles     : Array      = []
var stars         : Array      = []

var current_prime := -1
var current_mode  := 0
var pulse         := 0.0
var show_twins    := true
var screen_shake  := Vector2.ZERO
var layers        : Array = []
var bg_hue        := 0.0

var zoom_scale := 1.0
var pan_offset := Vector2.ZERO
var _is_panning  := false
var _pan_start   := Vector2.ZERO
var _pan_origin  := Vector2.ZERO
var _hovered_prime := -1

const STAR_COUNT = 180
const REVEAL_MAX = 1500


func _ready() -> void:
	_generate_stars()


func _generate_stars() -> void:
	var vp = get_viewport_rect().size
	for i in range(STAR_COUNT):
		var tint_roll = randf()
		var tint : Color
		if tint_roll < 0.5:
			tint = Color(0.85, 0.9, 1.0)
		elif tint_roll < 0.8:
			tint = Color(1.0, 1.0, 1.0)
		else:
			tint = Color(1.0, 0.9, 0.7)
		stars.append({
			"pos":    Vector2(randf() * vp.x, randf() * vp.y),
			"size":   randf_range(0.4, 2.8),
			"bright": randf_range(0.25, 1.0),
			"speed":  randf_range(0.6, 2.2),
			"offset": randf() * TAU,
			"tint":   tint
		})


static func is_prime(n: int) -> bool:
	if n < 2:      return false
	if n == 2:     return true
	if n % 2 == 0: return false
	for i in range(3, int(sqrt(float(n))) + 1, 2):
		if n % i == 0: return false
	return true


static func is_twin_prime(n: int) -> bool:
	return is_prime(n) and (is_prime(n - 2) or is_prime(n + 2))


func cell_size() -> float:
	match current_mode:
		1: return 10.0
		3: return 14.0
		4: return 12.0
		_: return 11.0


func build_prime_positions() -> Dictionary:
	var viewport  = get_viewport_rect().size
	var center    = viewport / 2.0 + pan_offset
	var cell      = cell_size() * zoom_scale
	var pos       = center
	var dir       = Vector2.RIGHT
	var steps_t   = 0
	var step_size = 1
	var turns     = 0
	var number    = 1
	var result    : Dictionary = {}
	var margin    = 20.0
	var bounds    = Rect2(margin, margin, viewport.x - margin * 2, viewport.y - margin * 2)

	while number <= REVEAL_MAX:
		if is_prime(number) and bounds.has_point(pos):
			result[number] = pos
		pos     += dir * cell
		number  += 1
		steps_t += 1
		if steps_t >= step_size:
			steps_t = 0
			dir     = Vector2(-dir.y, dir.x)
			turns   += 1
			if turns % 2 == 0:
				step_size += 1

	return result


func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_panning = event.pressed
			if event.pressed:
				_pan_start  = event.position
				_pan_origin = pan_offset
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_check_click(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_scale = clamp(zoom_scale * 1.1, 0.3, 4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_scale = clamp(zoom_scale * 0.9, 0.3, 4.0)
	elif event is InputEventMouseMotion:
		if _is_panning:
			pan_offset = _pan_origin + (event.position - _pan_start)
		else:
			_check_hover(event.position)


func _check_click(mouse_pos: Vector2) -> void:
	var positions = build_prime_positions()
	var threshold = cell_size() * zoom_scale * 0.65
	for prime in positions.keys():
		if mouse_pos.distance_to(positions[prime]) < threshold:
			emit_signal("prime_clicked", prime)
			return


func _check_hover(mouse_pos: Vector2) -> void:
	var positions  = build_prime_positions()
	var threshold  = cell_size() * zoom_scale * 0.65
	var prev       = _hovered_prime
	_hovered_prime = -1
	for prime in positions.keys():
		if mouse_pos.distance_to(positions[prime]) < threshold:
			_hovered_prime = prime
			break
	if _hovered_prime != prev:
		emit_signal("prime_hovered", _hovered_prime)


func _draw() -> void:
	var viewport = get_viewport_rect().size
	var t        = Time.get_ticks_msec() * 0.001

	# background
	draw_rect(Rect2(Vector2.ZERO, viewport),
		Color.from_hsv(bg_hue, 0.18, 0.04))

	# corner vignette
	draw_circle(Vector2.ZERO,           viewport.length() * 0.55, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(viewport.x, 0), viewport.length() * 0.55, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(0, viewport.y), viewport.length() * 0.55, Color(0, 0, 0, 0.18))
	draw_circle(viewport,               viewport.length() * 0.55, Color(0, 0, 0, 0.18))

	# stars
	for star in stars:
		var twinkle = 0.5 + 0.5 * sin(t * star["speed"] + star["offset"])
		var alpha   = star["bright"] * (0.3 + 0.7 * twinkle)
		var c       = star["tint"]
		if star["size"] > 1.8:
			draw_circle(star["pos"], star["size"] * 2.2, Color(c.r, c.g, c.b, alpha * 0.12))
		draw_circle(star["pos"], star["size"], Color(c.r, c.g, c.b, alpha))

	var prime_positions = build_prime_positions()
	var shifted : Dictionary = {}
	for k in prime_positions.keys():
		shifted[k] = prime_positions[k] + screen_shake

	# twin prime lines
	if show_twins:
		for prime in shifted.keys():
			if is_twin_prime(prime) and shifted.has(prime + 2):
				var either_active = played_primes.has(prime) or played_primes.has(prime + 2)
				var alpha = 0.65 if either_active else 0.12
				var width = 1.2  if either_active else 0.6
				draw_line(shifted[prime], shifted[prime + 2],
					Color(0.5, 0.85, 1.0, alpha), width)

	# constellation lines
	if current_mode == 4:
		var pkeys = played_primes.keys()
		pkeys.sort()
		for i in range(pkeys.size() - 1):
			var pa = pkeys[i]; var pb = pkeys[i + 1]
			if shifted.has(pa) and shifted.has(pb):
				var alpha = clamp(1.0 - played_primes[pa]["age"] * 0.07, 0.1, 0.7)
				draw_line(shifted[pa], shifted[pb], Color(0.4, 0.7, 1.0, alpha), 1.2)

	# layer lines
	for i in range(layers.size()):
		var layer = layers[i]
		var lcol  = Color.from_hsv(float(i + 1) / float(max(layers.size(), 1)), 0.6, 0.8, 0.3)
		for j in range(layer.size() - 1):
			var pa = layer[j]; var pb = layer[j + 1]
			if shifted.has(pa) and shifted.has(pb):
				draw_line(shifted[pa], shifted[pb], lcol, 0.7)

	# fractal polygon
	if current_mode == 5 and current_prime > 0 and shifted.has(current_prime):
		var fp    = shifted[current_prime]
		var sides = (current_prime % 5) + 3
		var rad   = 16.0 + pulse * 28.0
		for i in range(sides):
			var a1 = TAU * float(i) / float(sides)
			var a2 = TAU * float((i + 1) % sides) / float(sides)
			draw_line(
				fp + Vector2(cos(a1), sin(a1)) * rad,
				fp + Vector2(cos(a2), sin(a2)) * rad,
				Color.from_hsv(float(i) / float(sides), 0.9, 1.0, pulse * 0.9), 1.4)

	# prime dots
	for prime in shifted.keys():
		var ppos   = shifted[prime]
		var is_cur = (prime == current_prime)
		var is_hov = (prime == _hovered_prime)
		var played = played_primes.has(prime)
		var twin   = show_twins and is_twin_prime(prime)

		var in_layer = false
		for layer in layers:
			if layer.has(prime):
				in_layer = true
				break

		if is_cur:
			draw_circle(ppos, 22.0 * pulse, Color(1.0, 0.4, 0.05, 0.08 * pulse))
			for ring in range(3):
				var rr = (7.0 + ring * 9.0) + pulse * 12.0
				var ra = (0.6 - ring * 0.18) * pulse
				draw_arc(ppos, rr, 0, TAU, 48, Color(1.0, 0.55, 0.1, ra), 1.5)
			draw_circle(ppos, 5.5 + pulse * 3.0, Color(1.0, 0.6, 0.15, 0.9 * pulse))
		elif played:
			var pcol = played_primes[prime]["color"]
			var age  = played_primes[prime]["age"]
			var fade = clamp(1.0 - age * 0.008, 0.0, 1.0)
			draw_circle(ppos, 9.0 * fade, Color(pcol.r, pcol.g, pcol.b, 0.12 * fade))
			draw_arc(ppos, 5.0, 0, TAU, 24, Color(pcol.r, pcol.g, pcol.b, 0.5 * fade), 1.0)
		elif twin:
			draw_circle(ppos, 4.5, Color(0.4, 0.85, 1.0, 0.09))

		if in_layer and not is_cur:
			draw_arc(ppos, 9.0, 0, TAU, 24, Color(0.75, 0.5, 1.0, 0.4), 1.1)
		if is_hov and not is_cur:
			draw_circle(ppos, 8.0, Color(1, 1, 1, 0.08))
			draw_arc(ppos, 8.0, 0, TAU, 24, Color(1, 1, 1, 0.55), 1.2)

		var col   : Color
		var fsize : int
		if is_cur:
			col   = Color(1.0, 0.75, 0.2, 1.0)
			fsize = int(10.0 + pulse * 5.0)
		elif played:
			var age  = played_primes[prime]["age"]
			var fade = clamp(1.0 - age * 0.008, 0.35, 1.0)
			var pc   = played_primes[prime]["color"]
			col      = Color(pc.r, pc.g, pc.b, fade)
			fsize    = 9
		elif is_hov:
			col   = Color(1.0, 1.0, 1.0, 1.0)
			fsize = 10
		elif twin:
			col   = Color(0.5, 0.88, 1.0, 0.65)
			fsize = 8
		else:
			col   = Color(0.3, 0.42, 0.62, 0.5)
			fsize = 7

		var txt   = str(prime)
		var txt_w = fsize * len(txt) * 0.52
		draw_string(ThemeDB.fallback_font,
			ppos + Vector2(-txt_w * 0.5, fsize * 0.38),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

	# trails
	for tr in trails:
		var tc = tr["color"]
		var tl = tr["life"]
		draw_circle(tr["pos"] + screen_shake, 7.0 * tl, Color(tc.r, tc.g, tc.b, tl * 0.15))
		draw_circle(tr["pos"] + screen_shake, 3.5 * tl, Color(tc.r, tc.g, tc.b, tl * 0.55))

	# particles
	for p in particles:
		var pc = p.color
		var pl = p.life
		draw_circle(p.pos, p.size * pl * 2.2, Color(pc.r, pc.g, pc.b, pl * 0.12))
		draw_circle(p.pos, p.size * pl,        Color(pc.r, pc.g, pc.b, pl * 0.9))

	# drum bar
	if current_mode == 6:
		var bw = 200.0
		var bh = 36.0 * pulse
		var bx = viewport.x / 2.0 - bw / 2.0
		var by = viewport.y - 70.0
		draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 0.15, 0.15, 0.8))
		draw_rect(Rect2(bx, by, bw, bh), Color(1.0, 0.4, 0.4, 0.4), false, 1.0)

	# hover tooltip
	if _hovered_prime > 0 and shifted.has(_hovered_prime):
		var hp  = shifted[_hovered_prime]
		var tip = "prime " + str(_hovered_prime)
		if is_twin_prime(_hovered_prime):
			tip += "  [twin pair]"
		var tw = tip.length() * 6.5 + 16.0
		draw_rect(Rect2(hp.x + 10, hp.y - 18, tw, 18), Color(0.05, 0.05, 0.1, 0.75))
		draw_string(ThemeDB.fallback_font,
			hp + Vector2(14, -5),
			tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.95, 1.0, 0.95))

	# keyboard hint
	var hint = "Q-M: play notes   scroll: zoom   RMB: pan   ESC: clear   F11: fullscreen"
	draw_string(ThemeDB.fallback_font,
		Vector2(viewport.x / 2.0 - 260, viewport.y - 10),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.65, 0.9, 0.28))
