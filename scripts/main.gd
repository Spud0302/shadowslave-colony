extends Node2D
## Wires the simulation, the map view, the camera, the lights and the HUD together.

const D = preload("res://scripts/data.gd")
const World = preload("res://scripts/world.gd")
const View = preload("res://scripts/view.gd")
const UI = preload("res://scripts/ui.gd")

var w
var view
var ui
var cam: Camera2D
var shade: CanvasModulate
var lights = {}
var fire_light: PointLight2D
var gate_light: PointLight2D
var light_tex: Texture2D
var speed = 1
var acc = 0.0
var follow = false
var dragging = false
var drag_moved = false
var drag_from = Vector2()
var ui_t = 0.0
const TICKS_PER_SEC := 30.0

func _ready() -> void:
	var args = OS.get_cmdline_user_args()
	var seed_val = 1302
	for a in args:
		if a.begins_with("--seed="):
			seed_val = int(a.substr(7))
	w = World.new()
	w.gen(seed_val)
	for a in args:
		if a.begins_with("--simtest="):
			_simtest(int(a.substr(10)))
			return
	view = View.new()
	add_child(view)
	view.setup(w)
	cam = Camera2D.new()
	add_child(cam)
	cam.position = Vector2(w.camp) * D.TS + Vector2(0, -60)
	cam.zoom = Vector2(1.6, 1.6)
	cam.make_current()
	shade = CanvasModulate.new()
	add_child(shade)
	var g = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt = GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	light_tex = gt
	fire_light = _light(Vector2(w.camp) * D.TS + Vector2(8, 8), Color(1.0, 0.65, 0.3), 2.4)
	gate_light = _light(Vector2(w.gateway) * D.TS + Vector2(8, 8), Color(0.65, 0.5, 1.0), 2.0)
	gate_light.enabled = false
	ui = UI.new()
	add_child(ui)
	ui.build(w)
	ui.speed_changed.connect(_set_speed)
	ui.follow_toggled.connect(func(): follow = not follow)
	ui.event_clicked.connect(func(p): _select(p); cam.position = p.pos * D.TS)
	_set_speed(1)
	for a in args:
		if a.begins_with("--autoshot="):
			_autoshot(a.substr(11))

func _light(p: Vector2, c: Color, s: float) -> PointLight2D:
	var l = PointLight2D.new()
	l.texture = light_tex
	l.color = c
	l.texture_scale = s
	l.energy = 1.0
	l.position = p
	add_child(l)
	return l

func _set_speed(s: int) -> void:
	speed = s
	if ui:
		ui.set_speed(s)

func _process(dt: float) -> void:
	if w == null or view == null:
		return
	if speed > 0:
		acc += dt * TICKS_PER_SEC * speed
		var n = 0
		while acc >= 1.0 and n < 400:
			w.step()
			acc -= 1.0
			n += 1
		if n >= 400:
			acc = 0.0
	_lighting()
	view.zoom = cam.zoom.x
	if follow and ui.selected != null and ui.selected.alive:
		cam.position = cam.position.lerp(ui.selected.pos * D.TS, 0.15)
	var mv = Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if mv != Vector2.ZERO:
		cam.position += mv * 600.0 * dt / cam.zoom.x
	_clamp_cam()
	ui_t += dt
	if ui_t > 0.2:
		ui_t = 0.0
		ui.refresh()

func _lighting() -> void:
	var h: float = w.hour()
	var dark = 0.0
	if h >= 19.0:
		dark = clamp((h - 19.0) / 2.5, 0.0, 1.0)
	elif h < 6.5:
		dark = clamp((6.5 - h) / 1.5, 0.0, 1.0)
	var day_c = Color(1.0, 0.97, 0.95)
	var night_c = Color(0.22, 0.24, 0.42)
	shade.color = day_c.lerp(night_c, dark)
	fire_light.energy = 0.25 + dark * 1.1 + sin(w.tick * 0.2) * 0.05
	gate_light.enabled = w.gate_open
	gate_light.energy = 0.6 + dark * 0.8
	for c in w.buildings:
		var b = w.buildings[c]
		if (b.type == "cook" or b.type == "torch") and not lights.has(c):
			lights[c] = _light(Vector2(c) * D.TS + Vector2(8, 8), Color(1.0, 0.6, 0.3), 1.4 if b.type == "cook" else 1.1)
	for c in lights.keys():
		if not w.buildings.has(c):
			lights[c].queue_free()
			lights.erase(c)
		else:
			lights[c].energy = 0.15 + dark * 0.9

func _clamp_cam() -> void:
	var half = get_viewport_rect().size / cam.zoom / 2.0
	var mx = Vector2(D.W, D.H) * D.TS
	cam.position.x = clamp(cam.position.x, min(half.x, mx.x / 2), max(mx.x - half.x, mx.x / 2))
	cam.position.y = clamp(cam.position.y, min(half.y - 60, mx.y / 2), max(mx.y - half.y, mx.y / 2))

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_at(1.12, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_at(1.0 / 1.12, e.position)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if e.pressed:
				dragging = true
				drag_moved = false
				drag_from = e.position
			else:
				dragging = false
				if not drag_moved and e.button_index == MOUSE_BUTTON_LEFT:
					_click(get_global_mouse_position())
	elif e is InputEventMouseMotion and dragging:
		if e.position.distance_to(drag_from) > 4:
			drag_moved = true
		if drag_moved:
			cam.position -= e.relative / cam.zoom.x
			follow = false
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE:
				_set_speed(0 if speed > 0 else 1)
			KEY_1:
				_set_speed(1)
			KEY_2:
				_set_speed(2)
			KEY_3:
				_set_speed(4)
			KEY_4:
				_set_speed(8)
			KEY_5:
				_set_speed(20)
			KEY_F:
				follow = not follow
			KEY_ESCAPE:
				_select(null)

func _zoom_at(f: float, at: Vector2) -> void:
	var before = get_global_mouse_position()
	var z: float = clamp(cam.zoom.x * f, 0.35, 5.0)
	cam.zoom = Vector2(z, z)
	var after = get_global_mouse_position()
	cam.position += before - after

func _click(wp: Vector2) -> void:
	var tp = wp / D.TS
	var best = null
	var bd = 1.2
	for p in w.pawns:
		if p.alive and p.away_until <= 0:
			var d: float = p.pos.distance_to(tp)
			if d < bd:
				bd = d
				best = p
	for c in w.creatures:
		if c.alive:
			var d: float = c.pos.distance_to(tp)
			if d < bd * (1.6 if c.guardian else 1.0):
				bd = d
				best = c
	_select(best)

func _select(o) -> void:
	view.selected = o
	ui.show_inspect(o)
	if o == null:
		follow = false

# ---------------------------------------------------------------- tests and screenshots
func _simtest(days: int) -> void:
	var last = -1
	while w.day() < days:
		w.step()
		if w.day() != last:
			last = w.day()
			var ranks = [0, 0, 0]
			for p in w.pawns:
				if p.alive:
					ranks[p.rank] += 1
			var pw = 0.0
			var cs = 0.0
			for p in w.pawns:
				if p.alive:
					pw += p.power()
					cs += p.core
			print("  power %d need %d core %.2f arms %d" % [pw, w.guardian.dmg * w.guardian.hp, cs / max(1, w.pawns.size()), w.arms])
			print("day %d pop %s wood %d stone %d raw %d meal %d shards %d bld %d bp %d raids %d deaths %d kills %d gate %s guard %d" % [w.day(), str(ranks), w.store.wood, w.store.stone, w.store.raw, w.store.meal, w.store.shards, w.buildings.size(), w.blueprints.size(), w.raids_survived, w.deaths, w.kills, str(w.gate_open), int(w.guardian.hp)])
	for e in w.events:
		print("  D%d %02d  [%s] %s" % [e.day + 1, int(e.hour), e.kind, e.text])
	get_tree().quit()

func _shot(dir: String, name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var im = get_viewport().get_texture().get_image()
	im.save_png(dir + "/" + name + ".png")
	print("shot ", name)

func _run_until(cond: Callable, max_ticks: int) -> void:
	var n = 0
	while not cond.call() and n < max_ticks:
		w.step()
		n += 1

func _autoshot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_set_speed(0)
	await get_tree().process_frame
	# 1. first afternoon
	_run_until(func(): return w.day() >= 1 and w.hour() >= 14.0, 100000)
	cam.position = Vector2(w.camp) * D.TS
	cam.zoom = Vector2(2.4, 2.4)
	_set_speed(1)
	await get_tree().create_timer(1.0).timeout
	_set_speed(0)
	await _shot(dir, "01-camp-first-afternoon")
	# 2. a night raid
	_run_until(func(): return w.raid_active and _raider_near(10.0), 200000)
	_set_speed(1)
	await get_tree().create_timer(1.2).timeout
	_set_speed(0)
	cam.position = Vector2(w.camp) * D.TS
	cam.zoom = Vector2(2.2, 2.2)
	await _shot(dir, "02-night-raid")
	# 3. overview at midday, a few days on
	_run_until(func(): return w.day() >= 6 and w.hour() >= 12.0, 200000)
	cam.zoom = Vector2(0.62, 0.62)
	cam.position = Vector2(D.W / 2, D.H / 2) * D.TS
	await _shot(dir, "03-overview")
	# 4. inspect someone
	var pick = null
	for p in w.pawns:
		if p.alive and (pick == null or p.history.size() > pick.history.size()):
			pick = p
	_select(pick)
	cam.zoom = Vector2(2.6, 2.6)
	cam.position = pick.pos * D.TS
	_set_speed(1)
	await get_tree().create_timer(0.8).timeout
	_set_speed(0)
	cam.position = pick.pos * D.TS
	await _shot(dir, "04-inspect-a-sleeper")
	_select(null)
	# 5. the assault on the keep
	_run_until(func(): return w.assault and _fighters_in_keep() >= 3, 400000)
	if w.assault:
		cam.position = Vector2(w.gateway.x, w.gateway.y + 3) * D.TS
		cam.zoom = Vector2(2.3, 2.3)
		_set_speed(1)
		await get_tree().create_timer(1.5).timeout
		_set_speed(0)
		await _shot(dir, "05-assault-on-the-keep")
	# 6. the Gateway open
	_run_until(func(): return w.gate_open and w.awakened_total >= 2, 300000)
	cam.position = Vector2(w.gateway.x, w.gateway.y + 4) * D.TS
	cam.zoom = Vector2(2.0, 2.0)
	_set_speed(1)
	await get_tree().create_timer(1.0).timeout
	_set_speed(0)
	await _shot(dir, "06-gateway-open")
	# 7. the walled camp later on
	_run_until(func(): return w.hour() >= 21.5, 10000)
	cam.position = Vector2(w.camp) * D.TS
	cam.zoom = Vector2(1.5, 1.5)
	await _shot(dir, "07-walled-camp-at-night")
	print("autoshot done day ", w.day())
	get_tree().quit()

func _raider_near(r: float) -> bool:
	for c in w.creatures:
		if c.alive and c.raider and c.pos.distance_to(Vector2(w.camp)) < r:
			return true
	return false

func _fighters_in_keep() -> int:
	var n = 0
	for p in w.pawns:
		if p.alive and p.job.get("t", "") == "assault" and w.keep_rect.has_point(p.tile()):
			n += 1
	return n
