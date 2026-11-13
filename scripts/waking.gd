extends RefCounted
## The waking world: a city district with the Academy, its Sleepers' ward, civilians and Gates.

const D = preload("res://scripts/data.gd")
const Creature = preload("res://scripts/creature.gd")

const W := 96
const H := 64

const G_ROAD := 0
const G_WALK := 1
const G_FLOOR := 2
const G_GRASS := 3
const G_SAND := 4
const F_NONE := 0
const F_BUILDING := 1
const F_WALL := 2
const F_TREE := 3
const F_RUBBLE := 4
const F_TABLE := 5

class Civ:
	var id = 0
	var pos = Vector2()
	var path: Array = []
	var alive = true
	var away_until = -1
	var name = "a civilian"
	var hp = 20.0
	var col = Color.WHITE
	var flee = 0
	var wait = 0
	var ww
	func tile() -> Vector2i:
		return Vector2i(int(pos.x), int(pos.y))
	func take_hit(a: float, _by, _cause := "") -> void:
		hp -= a
		if hp <= 0 and alive:
			alive = false
			ww.civ_died(self)

var dw                     # the dream world (the colony)
var rng := RandomNumberGenerator.new()
var ground := PackedByteArray()
var feat := PackedByteArray()
var roof := PackedInt32Array()   # building id per tile, -1 for none
var astar := AStarGrid2D.new()
var buildings := {}        # unused here, creatures look for walls to bash
var creatures: Array = []
var civs: Array = []
var gates: Array = []      # {pos, cat, opened, spawned, closed}
var dirty: Array = []
var fx: Array = []
var tick := 0
var camp := Vector2i()     # creatures head for the Academy
var academy := Rect2i()
var ward_beds: Array = []
var canteen := Vector2i()
var yard := Rect2i()
var door := Vector2i()
var lamps: Array = []
var windows: Array = []    # [Vector2, Color] lit at night
var blocks: Array = []     # building rects for roofs
var city_code := ""
var city_name := ""
var gates_closed := 0
var civ_deaths := 0
var next_gate := 0
var next_id := 1

func gen(dream_world, s: int) -> void:
	dw = dream_world
	rng.seed = s * 31 + 7
	ground.resize(W * H)
	feat.resize(W * H)
	roof.resize(W * H)
	for i in W * H:
		ground[i] = G_WALK
		feat[i] = F_NONE
		roof[i] = -1
	var quads = ["Northern", "Southern", "Eastern", "Western"]
	var ords = ["First", "Second", "Third"]
	var q: String = quads[rng.randi() % 4]
	var o: String = ords[rng.randi() % 3]
	city_name = "%s Quadrant %s City" % [q, o]
	city_code = q[0] + "Q" + o[0] + "C"
	# streets: a grid of two-wide roads
	var xs = []
	var x = 1
	while x < W:
		xs.append(x)
		x += 14
	var ys = []
	var y = 1
	while y < H:
		ys.append(y)
		y += 11
	for yy in H:
		for xx in W:
			for sx in xs:
				if xx >= sx and xx < sx + 2:
					ground[yy * W + xx] = G_ROAD
			for sy in ys:
				if yy >= sy and yy < sy + 2:
					ground[yy * W + xx] = G_ROAD
	# blocks between roads
	var bi = 0
	var mid_x = xs.size() / 2
	var mid_y = ys.size() / 2
	for a in xs.size():
		for b in ys.size():
			var bx: int = xs[a] + 3
			var by: int = ys[b] + 3
			var bw = 9
			var bh = 6
			if bx + bw >= W or by + bh >= H:
				continue
			var rect = Rect2i(bx, by, bw, bh)
			if a == mid_x - 1 and b == mid_y - 1:
				_academy(Rect2i(bx, by, bw + 14, bh + 11))
			elif (a == mid_x and b == mid_y - 1) or (a == mid_x - 1 and b == mid_y) or (a == mid_x and b == mid_y):
				continue   # covered by the Academy
			elif rng.randf() < 0.14:
				_park(rect)
			else:
				_building(rect, bi)
				bi += 1
	# street lamps at crossings
	for sx in xs:
		for sy in ys:
			if sx + 2 < W and sy + 2 < H:
				lamps.append(Vector2(sx + 2.5, sy + 2.5))
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for yy in H:
		for xx in W:
			if is_solid(Vector2i(xx, yy)):
				astar.set_point_solid(Vector2i(xx, yy), true)
	camp = door
	for i in 40:
		_spawn_civ()
	next_gate = D.TICKS_PER_DAY * 2 + D.TICKS_PER_HOUR * 14

func _academy(r: Rect2i) -> void:
	academy = r
	for yy in range(r.position.y, r.end.y):
		for xx in range(r.position.x, r.end.x):
			var i = yy * W + xx
			ground[i] = G_FLOOR
			feat[i] = F_NONE
			var edge = xx == r.position.x or xx == r.end.x - 1 or yy == r.position.y or yy == r.end.y - 1
			if edge:
				feat[i] = F_WALL
	# door at the bottom middle, and an inner wall splitting the ward from the hall
	door = Vector2i(r.position.x + r.size.x / 2, r.end.y - 1)
	feat[door.y * W + door.x] = F_NONE
	feat[door.y * W + door.x - 1] = F_NONE
	var split = r.position.y + 8
	for xx in range(r.position.x, r.end.x):
		if abs(xx - (r.position.x + r.size.x / 2)) > 1:
			feat[split * W + xx] = F_WALL
	# ward beds in two rows along the top
	for row in 3:
		for k in range((r.size.x - 4) / 2):
			ward_beds.append(Vector2i(r.position.x + 2 + k * 2, r.position.y + 2 + row * 2))
	# canteen tables, bottom left
	canteen = Vector2i(r.position.x + 4, r.end.y - 4)
	for k in 3:
		feat[(canteen.y) * W + canteen.x - 2 + k * 2] = F_TABLE
	# training yard, bottom right, sand floor
	yard = Rect2i(r.end.x - 9, split + 2, 7, r.end.y - split - 4)
	for yy in range(yard.position.y, yard.end.y):
		for xx in range(yard.position.x, yard.end.x):
			ground[yy * W + xx] = G_SAND

func _park(r: Rect2i) -> void:
	for yy in range(r.position.y - 1, r.end.y + 1):
		for xx in range(r.position.x - 1, r.end.x + 1):
			var i = yy * W + xx
			ground[i] = G_GRASS
			if rng.randf() < 0.16:
				feat[i] = F_TREE

func _building(r: Rect2i, id: int) -> void:
	var cols = [Color8(78, 84, 98), Color8(96, 88, 84), Color8(70, 78, 72), Color8(88, 80, 96), Color8(102, 100, 96)]
	var col: Color = cols[rng.randi() % cols.size()]
	# sometimes two buildings in one block
	var parts: Array = [r]
	if rng.randf() < 0.5:
		var cut = r.position.x + rng.randi_range(3, r.size.x - 4)
		parts = [Rect2i(r.position.x, r.position.y, cut - r.position.x, r.size.y), Rect2i(cut + 1, r.position.y, r.end.x - cut - 1, r.size.y)]
	for p in parts:
		blocks.append([p, col.lightened(rng.randf_range(-0.08, 0.08))])
		for yy in range(p.position.y, p.end.y):
			for xx in range(p.position.x, p.end.x):
				var i = yy * W + xx
				feat[i] = F_BUILDING
				roof[i] = blocks.size() - 1
		for k in int(p.size.x * p.size.y / 4):
			windows.append(Vector2(p.position.x + rng.randf_range(0.3, p.size.x - 0.6), p.position.y + rng.randf_range(0.5, p.size.y - 0.4)))

func _spawn_civ() -> void:
	for i in 30:
		var c = Vector2i(rng.randi_range(1, W - 2), rng.randi_range(1, H - 2))
		if walkable(c) and not academy.has_point(c):
			var v = Civ.new()
			v.ww = self
			v.id = next_id
			next_id += 1
			v.pos = Vector2(c.x + 0.5, c.y + 0.5)
			v.col = Color.from_hsv(rng.randf(), 0.35, 0.75)
			civs.append(v)
			return

# ---------------------------------------------------------------- queries (shared with Creature)
func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H

func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	var f = feat[c.y * W + c.x]
	return f == F_BUILDING or f == F_WALL or f == F_TREE or f == F_TABLE

func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_solid(c)

func is_night() -> bool:
	return dw.is_night()

func hour() -> float:
	return dw.hour()

func creature_scale() -> float:
	return 1.0 + dw.day() * 0.01

func find_path(from: Vector2i, to: Vector2i, adj: bool):
	if not in_bounds(to) or not in_bounds(from):
		return null
	var fs = astar.is_point_solid(from)
	if fs:
		astar.set_point_solid(from, false)
	var res = null
	if adj or astar.is_point_solid(to):
		if Vector2(from).distance_to(Vector2(to)) < 1.5:
			res = []
		else:
			for d in dw.NB:
				var n: Vector2i = to + d
				if in_bounds(n) and not astar.is_point_solid(n):
					var p = astar.get_id_path(from, n)
					if p.size() > 0:
						res = Array(p)
						res.pop_front()
						break
	elif from == to:
		res = []
	else:
		var p = astar.get_id_path(from, to)
		if p.size() > 0:
			res = Array(p)
			res.pop_front()
	if fs:
		astar.set_point_solid(from, true)
	return res

func nearest_pawn(pos: Vector2, r: float):
	var best = null
	var bd = r
	for p in dw.pawns:
		if p.alive and p.realm == "wake" and p.away_until <= 0:
			var d: float = pos.distance_to(p.wpos)
			if d < bd:
				bd = d
				best = WakeProxy.new(p)
	for v in civs:
		if v.alive:
			var d: float = pos.distance_to(v.pos)
			if d < bd:
				bd = d
				best = v
	return best

func damage_building(_c, _a) -> void:
	pass

func creature_died(c, killer) -> void:
	fx.append(["die", c.pos, tick])
	var who = killer.p if killer is WakeProxy else null
	if who != null:
		who.kills += 1
		dw.kills += 1
	var chance: float = D.CREATURES[c.kind].shard
	if rng.randf() < chance:
		dw.store.shards += 1
	for g in gates:
		if not g.closed and c in g.spawn:
			g.spawn.erase(c)
			if g.spawn.is_empty() and g.spawned:
				g.closed = true
				g.closed_at = tick
				gates_closed += 1
				var by: String = who.name if who != null else "the city's Awakened"
				dw.log_event("[%s] %s closes the Category %s Gate in the streets." % [city_code, by, ["One", "Two", "Three"][g.cat - 1]], "good", who)
				dw.store.shards += g.cat
				if who != null:
					who.remember("Closed a Category %d Gate in %s." % [g.cat, city_code])

func civ_died(v) -> void:
	civ_deaths += 1
	fx.append(["die", v.pos, tick])

## Lets a Creature chase and hit a pawn that lives in the waking world.
class WakeProxy:
	var p
	func _init(pp) -> void:
		p = pp
	var alive:
		get:
			return p.alive and p.realm == "wake"
	var pos:
		get:
			return p.wpos
	var away_until:
		get:
			return p.away_until
	var name:
		get:
			return p.name
	func tile() -> Vector2i:
		return Vector2i(int(p.wpos.x), int(p.wpos.y))
	func take_hit(a: float, by, cause := "") -> void:
		p.take_hit(a, by, cause)
	func remember(t: String) -> void:
		p.remember(t)

# ---------------------------------------------------------------- tick
func step() -> void:
	tick = dw.tick
	for v in civs:
		if v.alive:
			_civ_step(v)
	for c in creatures:
		c.step()
	if tick % 30 == 0:
		civs = civs.filter(func(v): return v.alive)
		creatures = creatures.filter(func(c): return c.alive)
		if civs.size() < 40 and rng.randf() < 0.05:
			_spawn_civ()
	if tick % D.TICKS_PER_HOUR == 0:
		_hourly()
	if fx.size() > 0 and tick % 10 == 0:
		fx = fx.filter(func(f): return tick - f[2] < 90)

func _hourly() -> void:
	if tick >= next_gate:
		_open_gate()
		next_gate = tick + int(D.TICKS_PER_DAY * rng.randf_range(1.2, 2.6) / (1.0 + dw.day() * 0.02))
	for g in gates:
		if g.closed:
			continue
		var age: int = tick - g.opened
		if not g.spawned and age > D.TICKS_PER_HOUR:
			g.spawned = true
			var n: int = 2 + g.cat * 2
			for i in n:
				var c = Creature.new()
				c.id = 100000 + next_id
				next_id += 1
				var k = "burrower"
				if g.cat >= 2:
					k = "chainback" if rng.randf() < 0.6 else "mimic"
				if g.cat >= 3:
					k = "mimic" if rng.randf() < 0.7 else "fiend"
				c.setup(self, k, g.pos + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)), true)
				creatures.append(c)
				g.spawn.append(c)
			dw.log_event("[%s] The Gate breaks open. %d Nightmare Creatures spill into the streets." % [city_code, n], "bad")
		elif g.spawned and age > D.TICKS_PER_HOUR * 7:
			# the army arrives and seals it, at a cost
			var lost = 0
			for c in g.spawn:
				if c.alive:
					c.alive = false
					lost += 1
			g.closed = true
			g.closed_at = tick
			var dead = rng.randi_range(1, 4) * g.cat
			civ_deaths += dead
			dw.log_event("[%s] The army finally seals the Gate. %d civilians are dead." % [city_code, dead], "bad")
	gates = gates.filter(func(g): return not g.closed or tick - g.opened < D.TICKS_PER_DAY)

func _open_gate() -> void:
	var cat = 1
	if dw.day() > 8 and rng.randf() < 0.35:
		cat = 2
	if dw.day() > 24 and rng.randf() < 0.2:
		cat = 3
	for i in 50:
		var c = Vector2i(rng.randi_range(2, W - 3), rng.randi_range(2, H - 3))
		if walkable(c) and ground[c.y * W + c.x] == G_ROAD and Vector2(c).distance_to(Vector2(door)) > 12:
			gates.append({"pos": Vector2(c.x + 0.5, c.y + 0.5), "cat": cat, "opened": tick, "spawned": false, "closed": false, "spawn": []})
			dw.log_event("[%s] The Spell's warning: a Category %s Gate is opening in the streets of %s." % [city_code, ["One", "Two", "Three"][cat - 1], city_code], "spell")
			return

func active_threat():
	for c in creatures:
		if c.alive:
			return c
	return null

func _civ_step(v) -> void:
	var danger = null
	for c in creatures:
		if c.alive and c.pos.distance_to(v.pos) < 7:
			danger = c
			break
	if danger != null and v.flee <= 0:
		var away: Vector2 = (v.pos - danger.pos).normalized() * 10.0
		var t = Vector2i(clampi(int(v.pos.x + away.x), 1, W - 2), clampi(int(v.pos.y + away.y), 1, H - 2))
		if walkable(t):
			var p = find_path(v.tile(), t, false)
			v.path = p if p != null else []
		v.flee = 40
	if v.flee > 0:
		v.flee -= 1
	if v.path.is_empty():
		v.wait -= 1
		if v.wait <= 0:
			var t = Vector2i(rng.randi_range(1, W - 2), rng.randi_range(1, H - 2))
			if walkable(t) and not academy.has_point(t):
				var p = find_path(v.tile(), t, false)
				if p != null:
					v.path = p
			v.wait = rng.randi_range(60, 400)
		return
	var nxt: Vector2i = v.path[0]
	var target = Vector2(nxt.x + 0.5, nxt.y + 0.5)
	var d = target - v.pos
	var s = 0.13 if v.flee > 0 else 0.06
	if dw.is_night() and v.flee <= 0 and rng.randf() < 0.5:
		return   # fewer people out at night
	if d.length() <= s:
		v.pos = target
		v.path.pop_front()
	else:
		v.pos += d.normalized() * s

# ---------------------------------------------------------------- Awakened living in the waking world
func bed_for(p) -> Vector2i:
	if p.ward_bed < 0:
		var used = {}
		for q in dw.pawns:
			if q.alive and q.ward_bed >= 0:
				used[q.ward_bed] = true
		for i in ward_beds.size():
			if not used.has(i):
				p.ward_bed = i
				break
	if p.ward_bed < 0:
		return ward_beds[p.id % ward_beds.size()]
	return ward_beds[p.ward_bed]

func arrive(p) -> void:
	## A pawn wakes up in their body in the ward.
	var b = bed_for(p)
	p.realm = "wake"
	p.wpos = Vector2(b.x + 0.5, b.y + 0.5)
	p.wpath = []
	p.wjob = {"t": "rise", "timer": 60}
	p.wake_since = dw.tick

func step_pawn(p) -> void:
	var j: Dictionary = p.wjob
	if j.is_empty():
		_decide(p)
		j = p.wjob
	var threat = null
	if j.get("t", "") != "fight" and p.hp > p.max_hp() * 0.4:
		for c in creatures:
			if c.alive and c.pos.distance_to(p.wpos) < 30:
				threat = c
				break
		if threat != null:
			p.wjob = {"t": "fight", "e": threat}
			p.wpath = []
			p.wsleep = false
			j = p.wjob
	match j.t:
		"rise":
			p.activity = "Waking up in the ward"
			j.timer -= 1
			if j.timer <= 0:
				p.wjob = {}
		"fight":
			var e = j.e
			if e == null or not e.alive:
				p.wjob = {}
				return
			p.activity = "Fighting %s in the streets" % dw.an(e.name)
			if p.wpos.distance_to(e.pos) < 1.5:
				p.wpath = []
				if p.cd <= 0:
					e.take_hit(p.damage() * rng.randf_range(0.75, 1.25), WakeProxy.new(p))
					p.cd = 30
					p.skills.combat += 0.02
				return
			if p.wpath.is_empty() or tick % 15 == p.id % 15:
				var pp = find_path(p.wtile(), Vector2i(int(e.pos.x), int(e.pos.y)), false)
				p.wpath = pp if pp != null else []
			_move(p)
		"eat":
			p.activity = "Eating in the canteen"
			if _go(p, canteen + Vector2i(0, 1)):
				j.timer -= 1
				if j.timer <= 0:
					p.hunger = min(100.0, p.hunger + 70)
					p.think("Ate real food in the waking world", 6, 1.0)
					p.wjob = {}
		"train":
			p.activity = "Training in the yard"
			if not j.has("spot"):
				j.spot = Vector2i(rng.randi_range(yard.position.x, yard.end.x - 1), rng.randi_range(yard.position.y, yard.end.y - 1))
			if _go(p, j.spot):
				j.timer -= 1
				if tick % 20 == 0:
					p.skills.combat += 0.006
				if j.timer <= 0:
					p.wjob = {}
		"patrol":
			p.activity = "Patrolling the streets of %s" % city_code
			if not j.has("dest"):
				for i in 20:
					var t = Vector2i(rng.randi_range(1, W - 2), rng.randi_range(1, H - 2))
					if walkable(t) and ground[t.y * W + t.x] == G_ROAD:
						j.dest = t
						break
				if not j.has("dest"):
					p.wjob = {}
					return
			if _go(p, j.dest):
				p.wjob = {}
		"home":
			p.activity = "Visiting family in the city"
			if not j.has("dest"):
				j.dest = door + Vector2i(rng.randi_range(-20, 20), rng.randi_range(-12, 12))
				if not walkable(j.dest):
					j.dest = door + Vector2i(0, 2)
			if _go(p, j.dest):
				j.timer -= 1
				if j.timer <= 0:
					p.think("Saw family in the waking world", 8, 2.0)
					p.wjob = {}
		"sleep":
			var b = bed_for(p)
			if not p.wsleep:
				p.activity = "Going to bed in the ward"
				if _go(p, b):
					p.wsleep = true
			else:
				p.activity = "Asleep in the ward"
				p.rest = min(100.0, p.rest + 100.0 / (D.TICKS_PER_DAY * 0.3))
				j.timer -= 1
				if j.timer <= 0:
					if j.get("dream", false):
						dw.enter_dream(p)
					else:
						p.wsleep = false
						p.wjob = {}
		_:
			p.wjob = {}

func _decide(p) -> void:
	var h: float = dw.hour()
	var in_wake: int = dw.tick - p.wake_since
	# An Awakened who falls asleep is pulled into the Dream Realm, so sleep is the way back.
	var tired: bool = p.rest < 15 or (dw.is_night() and p.rest < 45)
	if tired or (in_wake > D.TICKS_PER_DAY * p.wake_stay and (dw.is_night() or h > 22.0)):
		if p.hunger < 55:
			p.wjob = {"t": "eat", "timer": 60}
			return
		p.wjob = {"t": "sleep", "timer": 220, "dream": true}
		return
	if p.hunger < 45:
		p.wjob = {"t": "eat", "timer": 60}
		return
	var r = rng.randf()
	if r < 0.35:
		p.wjob = {"t": "train", "timer": rng.randi_range(200, 500)}
	elif r < 0.7:
		p.wjob = {"t": "patrol"}
	else:
		p.wjob = {"t": "home", "timer": rng.randi_range(200, 600)}

func _go(p, to: Vector2i) -> bool:
	if p.wtile() == to and p.wpath.is_empty():
		return true
	if p.wpath.is_empty():
		var pp = find_path(p.wtile(), to, false)
		if pp == null:
			p.wjob = {}
			return false
		if pp.is_empty():
			return true
		p.wpath = pp
	_move(p)
	return false

func _move(p) -> void:
	if p.wpath.is_empty():
		return
	var nxt: Vector2i = p.wpath[0]
	var target = Vector2(nxt.x + 0.5, nxt.y + 0.5)
	var v: Vector2 = target - p.wpos
	var s: float = p.spd()
	if v.length() <= s:
		p.wpos = target
		p.wpath.pop_front()
	else:
		p.wpos += v.normalized() * s
