extends Node2D
## Draws the map (as a baked pixel texture) and everything that moves on it.

const D = preload("res://scripts/data.gd")

var w
var img: Image
var tex: ImageTexture
var sprite: Sprite2D
var selected = null
var zoom = 1.0
var font: Font

func setup(world) -> void:
	w = world
	font = ThemeDB.fallback_font
	img = Image.create(D.W * D.TS, D.H * D.TS, false, Image.FORMAT_RGBA8)
	for y in D.H:
		for x in D.W:
			paint(Vector2i(x, y))
	tex = ImageTexture.create_from_image(img)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = false
		sprite.z_index = -1
		add_child(sprite)
	sprite.texture = tex

func _process(_dt: float) -> void:
	if w == null:
		return
	if w.dirty.size() > 0:
		for c in w.dirty:
			paint(c)
		w.dirty.clear()
		tex.update(img)
	queue_redraw()

# ---------------------------------------------------------------- tile painting
func _h(x: int, y: int, k: int) -> int:
	var v: int = (x * 73856093) ^ (y * 19349663) ^ (k * 83492791) ^ w.seed_val
	v = (v ^ (v >> 13)) * 1274126177
	return abs(v ^ (v >> 16))

func _px(x0: int, y0: int, dx: int, dy: int, c: Color) -> void:
	if dx >= 0 and dy >= 0 and dx < D.TS and dy < D.TS:
		img.set_pixel(x0 + dx, y0 + dy, c)

func _rect(x0: int, y0: int, x: int, y: int, ww: int, hh: int, c: Color) -> void:
	img.fill_rect(Rect2i(x0 + x, y0 + y, ww, hh), c)

func paint(c: Vector2i) -> void:
	var x = c.x
	var y = c.y
	var x0 = x * D.TS
	var y0 = y * D.TS
	var i = y * D.W + x
	var g: int = w.ground[i]
	var base: Color
	match g:
		D.G_ASH:
			base = Color8(62, 58, 64)
		D.G_DUST:
			base = Color8(78, 70, 64)
		D.G_FLOOR:
			base = Color8(84, 84, 94)
		_:
			base = Color8(22, 38, 50)
	var shade = (_h(x, y, 1) % 9 - 4) * 0.004
	base = base.lightened(shade) if shade > 0 else base.darkened(-shade)
	_rect(x0, y0, 0, 0, D.TS, D.TS, base)
	if g == D.G_FLOOR:
		var grout = base.darkened(0.25)
		_rect(x0, y0, 0, 15, 16, 1, grout)
		_rect(x0, y0, (8 if y % 2 == 0 else 0), 0, 1, 16, grout)
		_rect(x0, y0, 0, 7, 16, 1, grout)
	elif g == D.G_WATER:
		for k in 3:
			var h = _h(x, y, 10 + k)
			_rect(x0, y0, h % 12, (h >> 4) % 15, 4, 1, Color8(40, 64, 80))
	else:
		for k in 7:
			var h = _h(x, y, 20 + k)
			var sc = base.lightened(0.12) if h % 3 == 0 else base.darkened(0.15)
			_px(x0, y0, h % 16, (h >> 5) % 16, sc)
	var f: int = w.feat[i]
	match f:
		D.F_TREE:
			_tree(x0, y0, x, y)
		D.F_SAPLING:
			_rect(x0, y0, 7, 9, 2, 5, Color8(70, 52, 44))
			_rect(x0, y0, 5, 7, 6, 3, Color8(60, 74, 58))
		D.F_ROCK:
			_rock(x0, y0, x, y, Color8(112, 108, 104))
		D.F_RUIN:
			_rect(x0, y0, 1, 6, 9, 6, Color8(98, 96, 108))
			_rect(x0, y0, 7, 2, 7, 6, Color8(110, 108, 120))
			_rect(x0, y0, 1, 11, 9, 1, Color8(60, 58, 70))
			_rect(x0, y0, 7, 7, 7, 1, Color8(64, 62, 74))
			_rect(x0, y0, 10, 12, 3, 2, Color8(90, 88, 100))
		D.F_CWALL:
			_rect(x0, y0, 0, 0, 16, 16, Color8(46, 44, 56))
			var br = Color8(66, 64, 80)
			for row in 4:
				var off = 0 if row % 2 == 0 else 4
				for col in 3:
					_rect(x0, y0, off + col * 8 - (4 if off else 0) + 1, row * 4 + 1, 6, 2, br)
			_rect(x0, y0, 0, 0, 16, 1, Color8(90, 88, 104))
		D.F_PLANT:
			_plant(x0, y0, x, y, true)
		D.F_BARE:
			_plant(x0, y0, x, y, false)
		D.F_GATEWAY:
			_rect(x0, y0, 2, 2, 12, 12, Color8(40, 36, 56))
			_rect(x0, y0, 4, 4, 8, 8, Color8(28, 24, 40))

func _tree(x0: int, y0: int, x: int, y: int) -> void:
	var h = _h(x, y, 5)
	var trunk = Color8(54, 40, 40)
	_rect(x0, y0, 7, 8, 2, 7, trunk)
	_rect(x0, y0, 5, 13, 6, 2, trunk.darkened(0.2))
	var leaf = Color8(48, 58, 52) if h % 3 else Color8(64, 50, 70)
	_rect(x0, y0, 3, 2, 10, 7, leaf)
	_rect(x0, y0, 2, 4, 12, 4, leaf)
	_rect(x0, y0, 4, 1, 6, 2, leaf.lightened(0.12))
	_rect(x0, y0, 3, 7, 10, 2, leaf.darkened(0.25))
	_px(x0, y0, 5 + h % 5, 3 + (h >> 3) % 3, leaf.lightened(0.25))

func _rock(x0: int, y0: int, x: int, y: int, c: Color) -> void:
	var h = _h(x, y, 6)
	c = c.darkened((h % 5) * 0.04)
	_rect(x0, y0, 1, 4, 14, 11, c)
	_rect(x0, y0, 3, 2, 10, 3, c)
	_rect(x0, y0, 3, 3, 6, 3, c.lightened(0.15))
	_rect(x0, y0, 1, 13, 14, 2, c.darkened(0.3))
	_px(x0, y0, 10, 8, c.darkened(0.4))
	_px(x0, y0, 11, 9, c.darkened(0.4))

func _plant(x0: int, y0: int, x: int, y: int, ripe: bool) -> void:
	var h = _h(x, y, 7)
	var ox = h % 4
	if ripe:
		var leaf = Color8(150, 120, 170)
		_rect(x0, y0, 5 + ox, 9, 1, 5, Color8(90, 80, 70))
		_rect(x0, y0, 3 + ox, 7, 3, 2, leaf)
		_rect(x0, y0, 6 + ox, 6, 3, 2, leaf.lightened(0.1))
		_rect(x0, y0, 4 + ox, 4, 2, 3, leaf)
		_px(x0, y0, 5 + ox, 4, Color8(220, 200, 120))
	else:
		_rect(x0, y0, 5 + ox, 11, 2, 3, Color8(90, 78, 66))

# ---------------------------------------------------------------- dynamic drawing
func _draw() -> void:
	if w == null:
		return
	var ts = float(D.TS)
	var t: int = w.tick
	# stockpile
	var sp = Vector2(w.stock) * ts
	draw_rect(Rect2(sp - Vector2(ts, ts), Vector2(ts * 3, ts * 3)), Color(0.9, 0.8, 0.5, 0.08))
	draw_rect(Rect2(sp - Vector2(ts, ts), Vector2(ts * 3, ts * 3)), Color(0.9, 0.8, 0.5, 0.35), false, 1.0)
	_piles(sp - Vector2(ts, ts))
	# blueprints
	for c in w.blueprints:
		var r = Rect2(Vector2(c) * ts + Vector2(1, 1), Vector2(ts - 2, ts - 2))
		draw_rect(r, Color(0.4, 0.75, 1.0, 0.12))
		draw_rect(r, Color(0.4, 0.75, 1.0, 0.6), false, 1.0)
	# buildings
	for c in w.buildings:
		_building(c, w.buildings[c])
	# campfire
	_fire(Vector2(w.camp) * ts + Vector2(ts / 2, ts / 2), 1.0, t)
	# gateway
	var gp = Vector2(w.gateway) * ts + Vector2(ts / 2, ts / 2)
	if w.gate_open:
		var pulse = 0.6 + 0.4 * sin(t * 0.08)
		draw_circle(gp, ts * 0.9, Color(0.6, 0.45, 1.0, 0.35 * pulse))
		draw_arc(gp, ts * 0.65, PI, TAU, 16, Color(0.8, 0.7, 1.0, 0.9), 2.0)
		draw_rect(Rect2(gp + Vector2(-ts * 0.45, -ts * 0.1), Vector2(ts * 0.9, ts * 0.55)), Color(0.75, 0.6, 1.0, 0.7 * pulse))
	else:
		draw_arc(gp, ts * 0.65, PI, TAU, 16, Color(0.45, 0.42, 0.5), 2.0)
		draw_line(gp + Vector2(-ts * 0.65, 0), gp + Vector2(-ts * 0.65, ts * 0.45), Color(0.45, 0.42, 0.5), 2.0)
		draw_line(gp + Vector2(ts * 0.65, 0), gp + Vector2(ts * 0.65, ts * 0.45), Color(0.45, 0.42, 0.5), 2.0)
	# graves
	for g in w.graves:
		var p: Vector2 = g[0] * ts
		draw_rect(Rect2(p + Vector2(-3, -4), Vector2(6, 8)), Color(0.55, 0.53, 0.58))
		draw_rect(Rect2(p + Vector2(-3, -4), Vector2(6, 2)), Color(0.7, 0.68, 0.74))
	# creatures
	for c in w.creatures:
		if c.alive:
			_creature(c, t)
	# pawns
	for p in w.pawns:
		if p.alive and p.away_until <= 0 and p.realm == "dream":
			_pawn(p, t)
	# effects
	for f in w.fx:
		var age = float(t - f[2]) / 90.0
		var fp: Vector2 = f[1] * ts
		if f[0] == "die":
			draw_arc(fp, ts * (0.3 + age * 1.4), 0, TAU, 20, Color(0.75, 0.6, 1.0, 1.0 - age), 1.5)
		else:
			draw_circle(fp, ts * 0.3 * (1.0 - age), Color(1, 0.5, 0.3, 1.0 - age))
	_selection("dream")

func _selection(realm: String) -> void:
	if selected == null or not selected.alive:
		return
	var here: String
	if selected.has_method("at"):
		here = selected.realm
	else:
		here = "dream" if selected.w == w else "wake"
	if here != realm:
		return
	var sp2: Vector2 = (selected.at() if selected.has_method("at") else selected.pos) * float(D.TS)
	draw_arc(sp2, D.TS * 0.9, 0, TAU, 24, Color(1, 1, 1, 0.9), 1.5)

func _piles(o: Vector2) -> void:
	var ts = float(D.TS)
	var wood = mini(w.store.wood, 120)
	for k in int(ceil(wood / 20.0)):
		var p = o + Vector2(3 + (k % 3) * 5, 3 + int(k / 3) * 4)
		draw_rect(Rect2(p, Vector2(10, 3)), Color8(120, 84, 56))
		draw_rect(Rect2(p + Vector2(0, 0), Vector2(2, 3)), Color8(170, 130, 90))
	var stone = mini(w.store.stone, 120)
	for k in int(ceil(stone / 20.0)):
		var p = o + Vector2(ts * 2 + 2 + (k % 2) * 6, 3 + int(k / 2) * 5)
		draw_rect(Rect2(p, Vector2(5, 4)), Color8(140, 138, 134))
	var food: int = mini(w.store.raw + w.store.meal, 90)
	for k in int(ceil(food / 15.0)):
		var p = o + Vector2(3 + (k % 4) * 6, ts * 2 + 3 + int(k / 4) * 5)
		draw_circle(p + Vector2(2, 2), 2.5, Color8(160, 128, 180) if k * 15 < w.store.raw else Color8(214, 160, 90))
	for k in mini(w.store.shards, 12):
		var p = o + Vector2(ts * 2 + 3 + (k % 4) * 3, ts * 2 + 3 + int(k / 4) * 4)
		draw_rect(Rect2(p, Vector2(2, 3)), Color(0.75, 0.6, 1.0))

func _building(c: Vector2i, b: Dictionary) -> void:
	var ts = float(D.TS)
	var o = Vector2(c) * ts
	match b.type:
		"wall":
			draw_rect(Rect2(o + Vector2(1, 2), Vector2(ts - 2, ts - 3)), Color8(108, 76, 52))
			for k in 4:
				draw_rect(Rect2(o + Vector2(1 + k * 4, 1), Vector2(3, ts - 2)), Color8(128, 92, 62))
				draw_rect(Rect2(o + Vector2(1 + k * 4, 1), Vector2(3, 2)), Color8(150, 112, 78))
		"swall":
			draw_rect(Rect2(o, Vector2(ts, ts)), Color8(96, 94, 100))
			draw_rect(Rect2(o + Vector2(1, 1), Vector2(6, 6)), Color8(124, 122, 128))
			draw_rect(Rect2(o + Vector2(9, 1), Vector2(6, 6)), Color8(116, 114, 120))
			draw_rect(Rect2(o + Vector2(4, 9), Vector2(8, 6)), Color8(120, 118, 124))
		"bed":
			draw_rect(Rect2(o + Vector2(3, 2), Vector2(10, 13)), Color8(92, 66, 48))
			draw_rect(Rect2(o + Vector2(4, 3), Vector2(8, 3)), Color8(200, 196, 186))
			var owner_col = Color8(120, 110, 140)
			for p in w.pawns:
				if p.id == b.owner:
					owner_col = p.color().darkened(0.2)
			draw_rect(Rect2(o + Vector2(4, 7), Vector2(8, 7)), owner_col)
		"cook":
			draw_circle(o + Vector2(8, 9), 6, Color8(70, 66, 70))
			draw_circle(o + Vector2(8, 9), 4, Color8(40, 34, 34))
			_fire(o + Vector2(8, 8), 0.7, w.tick)
			draw_rect(Rect2(o + Vector2(2, 1), Vector2(12, 2)), Color8(80, 60, 44))
		"torch":
			draw_rect(Rect2(o + Vector2(6, 7), Vector2(4, 8)), Color8(80, 76, 84))
			_fire(o + Vector2(8, 6), 0.5, w.tick)
	if b.has("hp") and D.BUILD[b.type].has("hp") and b.hp < D.BUILD[b.type].hp:
		var f: float = b.hp / float(D.BUILD[b.type].hp)
		draw_rect(Rect2(o + Vector2(1, -3), Vector2((ts - 2) * f, 2)), Color(0.9, 0.3, 0.3))

func _fire(p: Vector2, s: float, t: int) -> void:
	var fl = 0.8 + 0.2 * sin(t * 0.3 + p.x)
	draw_circle(p + Vector2(0, 2) * s, 5.0 * s, Color8(60, 56, 60))
	draw_circle(p, 4.0 * s * fl, Color(1.0, 0.45, 0.1, 0.9))
	draw_circle(p + Vector2(0, -1.5) * s, 2.6 * s * fl, Color(1.0, 0.8, 0.3, 0.95))
	draw_circle(p, 11.0 * s, Color(1.0, 0.6, 0.2, 0.08))

func _creature(c, t: int) -> void:
	var ts = float(D.TS)
	var p: Vector2 = c.pos * ts
	var r: float = c.size * ts * 0.5
	var body: Color = c.col
	if c.hit_flash > 0:
		body = body.lerp(Color.WHITE, 0.6)
	var bob = sin(t * 0.25 + c.id) * 0.8
	if c.guardian:
		draw_circle(p, r * 1.4, Color(0.6, 0.1, 0.1, 0.12))
		draw_circle(p + Vector2(0, bob), r, body)
		for k in 5:
			var a = PI + (k + 0.5) * PI / 5.0
			var tip = p + Vector2(cos(a), sin(a)) * r * 1.35 + Vector2(0, bob)
			draw_line(p + Vector2(cos(a), sin(a)) * r * 0.8 + Vector2(0, bob), tip, Color8(90, 80, 70), 2.0)
		draw_circle(p + Vector2(-r * 0.35, -r * 0.15 + bob), 2.2, Color(1, 0.25, 0.2))
		draw_circle(p + Vector2(r * 0.35, -r * 0.15 + bob), 2.2, Color(1, 0.25, 0.2))
	else:
		draw_circle(p + Vector2(0, 2), r * 0.9, Color(0, 0, 0, 0.3))
		draw_circle(p + Vector2(0, bob), r, body)
		if c.kind == "chainback":
			for k in 3:
				draw_rect(Rect2(p + Vector2(-r * 0.7 + k * r * 0.5, -r * 0.6 + bob), Vector2(r * 0.35, r * 0.35)), Color8(130, 130, 140))
		if c.kind == "fiend":
			draw_circle(p + Vector2(0, bob), r * 0.55, Color(1.0, 0.4, 0.1, 0.6))
		var eye = Color(1.0, 0.2, 0.2) if (c.raider or c.aggro != null) else Color(0.9, 0.7, 0.3)
		draw_circle(p + Vector2(-r * 0.35, -r * 0.2 + bob), 1.4, eye)
		draw_circle(p + Vector2(r * 0.35, -r * 0.2 + bob), 1.4, eye)
	if c.hp < c.max_hp:
		var f: float = max(0.0, c.hp / c.max_hp)
		var wd = ts * (2.4 if c.guardian else 1.0)
		draw_rect(Rect2(p + Vector2(-wd / 2, -r - 6), Vector2(wd, 2)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p + Vector2(-wd / 2, -r - 6), Vector2(wd * f, 2)), Color(0.9, 0.25, 0.25))

func _pawn(p, t: int) -> void:
	var ts = float(D.TS)
	var c: Vector2 = p.at() * ts
	var wake: bool = p.realm == "wake"
	var skin = Color8(232, 200, 170).darkened((p.id % 5) * 0.09)
	var tunic: Color = Color8(170, 168, 160) if p.rank == 0 else p.color()
	if p.hit_flash > 0:
		tunic = tunic.lerp(Color(1, 0.3, 0.3), 0.6)
	if (p.wsleep if wake else p.sleeping):
		draw_rect(Rect2(c + Vector2(-6, -2), Vector2(9, 5)), tunic)
		draw_circle(c + Vector2(4, 0), 2.6, skin)
		var zt = float((t / 4) % 30) / 30.0
		draw_string(font, c + Vector2(4, -6 - zt * 6), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 1.0 - zt))
		return
	var moving: bool = not (p.wpath if wake else p.path).is_empty()
	var step = sin(t * 0.5 + p.id) * (1.2 if moving else 0.0)
	draw_circle(c + Vector2(0, 6), 4.0, Color(0, 0, 0, 0.3))
	draw_rect(Rect2(c + Vector2(-3, 2), Vector2(2, 4 + step)), Color8(60, 54, 58))
	draw_rect(Rect2(c + Vector2(1, 2), Vector2(2, 4 - step)), Color8(60, 54, 58))
	draw_rect(Rect2(c + Vector2(-4, -3), Vector2(8, 7)), tunic)
	if p.rank >= 1:
		draw_rect(Rect2(c + Vector2(-4, -3), Vector2(8, 1)), tunic.lightened(0.35))
	draw_circle(c + Vector2(0, -6), 3.0, skin)
	var hair = Color8(40, 30, 28).lightened((p.id % 4) * 0.15)
	draw_rect(Rect2(c + Vector2(-3, -9), Vector2(6, 2)), hair)
	if p.rank >= 2:
		draw_arc(c + Vector2(0, -2), 9, 0, TAU, 20, Color(1.0, 0.8, 0.4, 0.9), 1.2)
	if p.carry != "" and not wake:
		var cc: Color = {"wood": Color8(150, 110, 70), "stone": Color8(150, 148, 144), "raw": Color8(160, 128, 180), "meal": Color8(214, 160, 90)}.get(p.carry, Color.WHITE)
		draw_rect(Rect2(c + Vector2(3, -2), Vector2(4, 4)), cc)
	var jt: String = p.wjob.get("t", "") if wake else p.job.get("t", "")
	if jt in ["chop", "mine", "build"] and p.job.get("stage", 0) in [1, 2] and (jt != "build" or p.job.get("stage", 0) == 2):
		var sw = sin(t * 0.6 + p.id) * 0.8
		var hand = c + Vector2(4, -1)
		draw_line(hand, hand + Vector2(cos(-0.8 + sw), sin(-0.8 + sw)) * 6, Color8(190, 180, 170), 1.5)
	if p.hp < p.max_hp():
		var f: float = max(0.0, p.hp / p.max_hp())
		draw_rect(Rect2(c + Vector2(-6, -13), Vector2(12, 2)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(c + Vector2(-6, -13), Vector2(12 * f, 2)), Color(0.3, 0.9, 0.4))
	if zoom >= 2.2:
		var nm: String = p.name.split(" ")[0]
		draw_string(font, c + Vector2(-20, 16), nm, HORIZONTAL_ALIGNMENT_CENTER, 40, 7, Color(1, 1, 1, 0.85))
