extends "res://scripts/view.gd"
## Draws the waking world: the city district, the Academy and its Sleepers' ward, the Gates.

const K = preload("res://scripts/waking.gd")

var ww                 # the waking world
var dark = 0.0         # 0 by day, 1 at full night (set by main)
var glow_layer: CanvasLayer
var glow: Node2D
var soft_tex: Texture2D

class Glow extends Node2D:
	var v
	func _draw() -> void:
		v._draw_glow(self)

func setup(world) -> void:
	w = world
	ww = world.wake
	font = ThemeDB.fallback_font
	img = Image.create(K.W * D.TS, K.H * D.TS, false, Image.FORMAT_RGBA8)
	for y in K.H:
		for x in K.W:
			paint(Vector2i(x, y))
	tex = ImageTexture.create_from_image(img)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.z_index = -1
	add_child(sprite)
	sprite.texture = tex
	# lamplight and lit windows sit on their own layer, so the night tint doesn't swallow them
	var g = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var gt = GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	soft_tex = gt
	glow_layer = CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	glow = Glow.new()
	glow.v = self
	var m = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = m
	glow_layer.add_child(glow)

func set_shown(on: bool) -> void:
	visible = on
	glow_layer.visible = on

func _process(_dt: float) -> void:
	if ww == null:
		return
	if ww.dirty.size() > 0:
		for c in ww.dirty:
			paint(c)
		ww.dirty.clear()
		tex.update(img)
	if visible:
		queue_redraw()
		glow.queue_redraw()

# ---------------------------------------------------------------- tile painting
func paint(c: Vector2i) -> void:
	var x = c.x
	var y = c.y
	var x0 = x * D.TS
	var y0 = y * D.TS
	var i = y * K.W + x
	var g: int = ww.ground[i]
	var base: Color
	match g:
		K.G_ROAD:
			base = Color8(46, 48, 54)
		K.G_WALK:
			base = Color8(108, 106, 102)
		K.G_FLOOR:
			base = Color8(118, 100, 82)
		K.G_GRASS:
			base = Color8(64, 92, 60)
		_:
			base = Color8(152, 132, 98)
	var shade = (_h(x, y, 1) % 9 - 4) * 0.006
	base = base.lightened(shade) if shade > 0 else base.darkened(-shade)
	_rect(x0, y0, 0, 0, D.TS, D.TS, base)
	match g:
		K.G_ROAD:
			for k in 5:
				var h = _h(x, y, 30 + k)
				_px(x0, y0, h % 16, (h >> 5) % 16, base.lightened(0.1))
			# kerbs where the road meets the pavement
			if _g(x, y - 1) == K.G_WALK:
				_rect(x0, y0, 0, 0, 16, 1, Color8(140, 138, 132))
			if _g(x, y + 1) == K.G_WALK:
				_rect(x0, y0, 0, 15, 16, 1, Color8(140, 138, 132))
			if _g(x - 1, y) == K.G_WALK:
				_rect(x0, y0, 0, 0, 1, 16, Color8(140, 138, 132))
			if _g(x + 1, y) == K.G_WALK:
				_rect(x0, y0, 15, 0, 1, 16, Color8(140, 138, 132))
			# a dashed centre line between the two lanes
			var lane = Color8(196, 180, 110)
			if _g(x, y + 1) == K.G_ROAD and _g(x, y - 1) != K.G_ROAD and _g(x - 1, y) != K.G_WALK and _g(x + 1, y) != K.G_WALK and x % 2 == 0:
				_rect(x0, y0, 2, 15, 10, 1, lane)
			if _g(x + 1, y) == K.G_ROAD and _g(x - 1, y) != K.G_ROAD and _g(x, y - 1) != K.G_WALK and _g(x, y + 1) != K.G_WALK and y % 2 == 0:
				_rect(x0, y0, 15, 2, 1, 10, lane)
		K.G_WALK:
			var grout = base.darkened(0.14)
			_rect(x0, y0, 0, 15, 16, 1, grout)
			_rect(x0, y0, 15, 0, 1, 16, grout)
			_rect(x0, y0, 7, 0, 1, 8, grout)
			_rect(x0, y0, 0, 7, 16, 1, grout)
		K.G_FLOOR:
			for row in 4:
				_rect(x0, y0, 0, row * 4 + 3, 16, 1, base.darkened(0.18))
				_rect(x0, y0, (_h(x, y, 40 + row) % 14) + 1, row * 4, 1, 3, base.darkened(0.12))
		K.G_GRASS:
			for k in 8:
				var h = _h(x, y, 50 + k)
				var gc = base.lightened(0.15) if h % 2 == 0 else base.darkened(0.15)
				_rect(x0, y0, h % 15, (h >> 5) % 14, 1, 2, gc)
		_:
			for k in 6:
				var h = _h(x, y, 60 + k)
				_px(x0, y0, h % 16, (h >> 5) % 16, base.darkened(0.12))
	var f: int = ww.feat[i]
	match f:
		K.F_BUILDING:
			_roof(x0, y0, x, y)
		K.F_WALL:
			_rect(x0, y0, 0, 0, 16, 16, Color8(132, 118, 104))
			var br = Color8(150, 136, 120)
			for row in 4:
				var off = 0 if row % 2 == 0 else 4
				for col in 3:
					_rect(x0, y0, off + col * 8 - (4 if off else 0) + 1, row * 4 + 1, 6, 2, br)
			_rect(x0, y0, 0, 0, 16, 2, Color8(176, 164, 150))
		K.F_TREE:
			var h = _h(x, y, 5)
			_rect(x0, y0, 7, 9, 2, 6, Color8(84, 60, 44))
			var leaf = Color8(58, 112, 62) if h % 3 else Color8(72, 124, 70)
			draw_blob(x0, y0, leaf)
		K.F_TABLE:
			_rect(x0, y0, 0, 4, 16, 8, Color8(122, 88, 60))
			_rect(x0, y0, 0, 4, 16, 1, Color8(150, 112, 80))
			_rect(x0, y0, 2, 1, 3, 2, Color8(100, 90, 80))
			_rect(x0, y0, 11, 13, 3, 2, Color8(100, 90, 80))

func draw_blob(x0: int, y0: int, leaf: Color) -> void:
	_rect(x0, y0, 3, 2, 10, 8, leaf)
	_rect(x0, y0, 2, 4, 12, 4, leaf)
	_rect(x0, y0, 4, 1, 6, 2, leaf.lightened(0.15))
	_rect(x0, y0, 3, 8, 10, 2, leaf.darkened(0.25))

func _g(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= K.W or y >= K.H:
		return -1
	return ww.ground[y * K.W + x]

func _rid(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= K.W or y >= K.H:
		return -2
	return ww.roof[y * K.W + x]

func _roof(x0: int, y0: int, x: int, y: int) -> void:
	var id = _rid(x, y)
	var col: Color = ww.blocks[id][1]
	_rect(x0, y0, 0, 0, 16, 16, col)
	# gravel speckle
	for k in 4:
		var h = _h(x, y, 70 + k)
		_px(x0, y0, h % 16, (h >> 5) % 16, col.darkened(0.12))
	# parapet on the roof's edges, with a shadow on the street below
	var lip = col.lightened(0.22)
	var low = col.darkened(0.3)
	if _rid(x, y - 1) != id:
		_rect(x0, y0, 0, 0, 16, 2, lip)
	if _rid(x - 1, y) != id:
		_rect(x0, y0, 0, 0, 2, 16, lip)
	if _rid(x + 1, y) != id:
		_rect(x0, y0, 14, 0, 2, 16, low)
	if _rid(x, y + 1) != id:
		_rect(x0, y0, 0, 14, 16, 2, low)
	# rooftop clutter: vents, water tanks, skylights
	var hh = _h(x, y, 77)
	if hh % 11 == 0:
		_rect(x0, y0, 4, 4, 7, 6, Color8(150, 150, 156))
		_rect(x0, y0, 4, 9, 7, 1, Color8(90, 90, 96))
	elif hh % 13 == 0:
		_rect(x0, y0, 5, 5, 6, 6, Color8(86, 116, 140))
		_rect(x0, y0, 5, 5, 6, 1, Color8(150, 180, 200))

# ---------------------------------------------------------------- dynamic drawing
func _draw() -> void:
	if ww == null:
		return
	var ts = float(D.TS)
	var t: int = w.tick
	# the ward: a bed for every Sleeper, with their body asleep in it
	var who = {}
	for p in w.pawns:
		if p.alive and p.ward_bed >= 0:
			who[p.ward_bed] = p
	for i in ww.ward_beds.size():
		var b: Vector2i = ww.ward_beds[i]
		var o = Vector2(b) * ts
		draw_rect(Rect2(o + Vector2(2, 1), Vector2(12, 14)), Color8(86, 90, 104))
		draw_rect(Rect2(o + Vector2(3, 2), Vector2(10, 12)), Color8(214, 216, 222))
		draw_rect(Rect2(o + Vector2(4, 2), Vector2(8, 3)), Color8(240, 240, 244))
		var p = who.get(i)
		if p != null and p.realm == "dream":
			_body(p, o, t)
			if p == selected:
				draw_arc(o + Vector2(8, 8), ts * 0.9, 0, TAU, 24, Color(1, 1, 1, 0.9), 1.5)
	# the Academy's name over its door
	if zoom >= 1.0:
		var dp = Vector2(ww.door) * ts + Vector2(ts * 0.5, ts * 2.2)
		draw_string(font, dp - Vector2(60, 0), "THE ACADEMY", HORIZONTAL_ALIGNMENT_CENTER, 120, 9, Color(0.95, 0.9, 0.8, 0.8))
	# lamp posts
	for l in ww.lamps:
		var lp: Vector2 = l * ts
		draw_circle(lp + Vector2(0, 1), 2.5, Color(0, 0, 0, 0.35))
		draw_circle(lp, 2.2, Color8(60, 62, 70))
		draw_circle(lp, 1.2, Color(1.0, 0.85, 0.5) if dark > 0.2 else Color8(150, 150, 140))
	# Gates
	for g in ww.gates:
		_gate(g, t)
	# civilians
	for v in ww.civs:
		if v.alive:
			_civ(v, t)
	for c in ww.creatures:
		if c.alive:
			_creature(c, t)
	for p in w.pawns:
		if p.alive and p.realm == "wake":
			_pawn(p, t)
	for f in ww.fx:
		var age = max(0.0, float(t - f[2]) / 90.0)
		var fp: Vector2 = f[1] * ts
		draw_arc(fp, ts * (0.3 + age * 1.4), 0, TAU, 20, Color(0.75, 0.6, 1.0, 1.0 - age), 1.5)
	_selection("wake")

func _body(p, o: Vector2, t: int) -> void:
	var tunic: Color = Color8(150, 160, 190) if p.rank == 0 else p.color().darkened(0.1)
	var skin = Color8(232, 200, 170).darkened((p.id % 5) * 0.09)
	draw_rect(Rect2(o + Vector2(4, 6), Vector2(8, 8)), tunic)
	draw_circle(o + Vector2(8, 4.5), 2.4, skin)
	# a faint violet pulse: their mind is in the Dream Realm
	var pulse = 0.5 + 0.5 * sin(t * 0.05 + p.id)
	draw_circle(o + Vector2(8, 8), 7.0, Color(0.6, 0.45, 1.0, 0.08 + 0.08 * pulse))
	if p.away_until > 0:
		draw_arc(o + Vector2(8, 8), 7.5, 0, TAU, 16, Color(1.0, 0.4, 0.5, 0.5 + 0.3 * pulse), 1.0)
	if zoom >= 2.2:
		draw_string(font, o + Vector2(-12, 22), p.name.split(" ")[0], HORIZONTAL_ALIGNMENT_CENTER, 40, 7, Color(1, 1, 1, 0.75))

func _gate(g: Dictionary, t: int) -> void:
	var ts = float(D.TS)
	var p: Vector2 = g.pos * ts
	if g.closed:
		var fade = 1.0 - clamp(float(t - g.get("closed_at", t)) / D.TICKS_PER_DAY, 0.0, 1.0)
		draw_circle(p, ts * 0.8, Color(0.1, 0.08, 0.12, 0.5 * fade + 0.15))
		return
	var r = ts * (0.6 + 0.25 * g.cat)
	if not g.spawned:
		r *= 0.4 + 0.6 * clamp(float(t - g.opened) / D.TICKS_PER_HOUR, 0.0, 1.0)
	var pulse = 0.6 + 0.4 * sin(t * 0.12 + g.pos.x)
	draw_circle(p, r * 1.6, Color(0.55, 0.3, 0.9, 0.15 * pulse))
	_ellipse(p, r * 1.15, r * 0.75, Color(0.7, 0.5, 1.0, 0.8))
	_ellipse(p, r, r * 0.62, Color(0.05, 0.02, 0.08))
	for k in 5:
		var a = k * TAU / 5.0 + t * 0.01
		draw_line(p + Vector2(cos(a), sin(a) * 0.65) * r, p + Vector2(cos(a), sin(a) * 0.65) * r * (1.5 + 0.2 * sin(t * 0.2 + k)), Color(0.75, 0.55, 1.0, 0.6), 1.0)

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts = PackedVector2Array()
	for k in 20:
		var a = k * TAU / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func _civ(v, t: int) -> void:
	var c: Vector2 = v.pos * float(D.TS)
	var moving: bool = not v.path.is_empty()
	var step = sin(t * 0.5 + v.id) * (1.0 if moving else 0.0)
	draw_circle(c + Vector2(0, 5), 3.0, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(c + Vector2(-2, 2), Vector2(1.5, 3 + step)), Color8(50, 50, 60))
	draw_rect(Rect2(c + Vector2(0.5, 2), Vector2(1.5, 3 - step)), Color8(50, 50, 60))
	draw_rect(Rect2(c + Vector2(-3, -2), Vector2(6, 5)), v.col)
	draw_circle(c + Vector2(0, -4.5), 2.2, Color8(226, 196, 166).darkened((v.id % 4) * 0.1))
	if v.flee > 0:
		draw_string(font, c + Vector2(-2, -8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.8, 0.3))

# ---------------------------------------------------------------- the night glow layer
func _draw_glow(n: Node2D) -> void:
	var ts = float(D.TS)
	var t: int = w.tick
	if dark > 0.02:
		for l in ww.lamps:
			_soft(n, l * ts, ts * 3.4, Color(1.0, 0.78, 0.45), 0.45 * dark)
		var hhmm = int(w.hour() * 4)
		for i in ww.windows.size():
			# people turn their lights off as the night goes on
			var h = _h(i, hhmm / 6, 9)
			if h % 10 < 6:
				var wp: Vector2 = ww.windows[i] * ts
				n.draw_rect(Rect2(wp, Vector2(3, 2)), Color(1.0, 0.82, 0.45, 0.75 * dark))
				_soft(n, wp + Vector2(1.5, 1), ts * 0.8, Color(1.0, 0.7, 0.35), 0.35 * dark)
		# night lights over the ward beds
		for b in ww.ward_beds:
			_soft(n, Vector2(b) * ts + Vector2(8, 8), ts * 1.2, Color(0.75, 0.7, 1.0), 0.18 * dark)
	for g in ww.gates:
		if not g.closed:
			var pulse = 0.7 + 0.3 * sin(t * 0.12)
			_soft(n, g.pos * ts, ts * (2.5 + g.cat), Color(0.6, 0.35, 1.0), (0.12 + 0.25 * dark) * pulse)

func _soft(n: Node2D, p: Vector2, r: float, c: Color, a: float) -> void:
	n.draw_texture_rect(soft_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c.r, c.g, c.b, a))
