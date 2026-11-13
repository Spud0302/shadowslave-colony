extends RefCounted
## The simulation: map, colony, creatures, raids, the Citadel and its Guardian.

const D = preload("res://scripts/data.gd")
const Pawn = preload("res://scripts/pawn.gd")
const Creature = preload("res://scripts/creature.gd")
const Waking = preload("res://scripts/waking.gd")

var rng = RandomNumberGenerator.new()
var seed_val = 0
var ground = PackedByteArray()
var feat = PackedByteArray()
var astar = AStarGrid2D.new()
var trees = {}
var rocks = {}
var plants = {}
var regrow = {}          # Vector2i -> [tick, feature]
var unreachable = {}     # Vector2i -> tick until we stop trying
var buildings = {}       # Vector2i -> {type, hp, owner}
var blueprints = {}      # Vector2i -> {type, delivered}
var reserved = {}
var pawns: Array = []
var creatures: Array = []
var graves: Array = []    # [Vector2, name, day]
var store = {"wood": 30, "stone": 0, "raw": 36, "meal": 0, "shards": 0}
var tick = 0
var events: Array = []    # {day, hour, text, kind}
var camp = Vector2i()
var stock = Vector2i()
var cook = Vector2i(-1, -1)
var bed_slots: Array = []
var wall_ring: Array = []
var keep_rect = Rect2i()
var cit_rect = Rect2i()
var gateway = Vector2i()
var gate_open = false
var guardian = null
var assault = false
var assault_tries = 0
var raid_active = false
var next_raid = 0
var foreseen = false
var next_id = 1
var dirty: Array = []
var citadel_name = ""
var deaths = 0
var raids_survived = 0
var kills = 0
var awakened_total = 0
var masters_total = 0
var arrivals = 0
var shard_rr = 0
var fx: Array = []        # [kind, Vector2, tick]
var arms := 0
var wake                  # the waking world

# ---------------------------------------------------------------- generation
func gen(s: int) -> void:
	seed_val = s
	rng.seed = s
	ground.resize(D.W * D.H)
	feat.resize(D.W * D.H)
	var n1 = FastNoiseLite.new()
	n1.seed = s
	n1.frequency = 0.03
	var n2 = FastNoiseLite.new()
	n2.seed = s + 11
	n2.frequency = 0.055
	var n3 = FastNoiseLite.new()
	n3.seed = s + 23
	n3.frequency = 0.07
	for y in D.H:
		for x in D.W:
			var i = y * D.W + x
			var e = n1.get_noise_2d(x, y)
			feat[i] = D.F_NONE
			if e < -0.38:
				ground[i] = D.G_WATER
				continue
			ground[i] = D.G_DUST if n3.get_noise_2d(x * 1.9 + 50, y * 1.9) > 0.22 else D.G_ASH
			if n2.get_noise_2d(x, y) > 0.34:
				feat[i] = D.F_ROCK
			elif n3.get_noise_2d(x, y) > 0.2 and rng.randf() < 0.5:
				feat[i] = D.F_TREE
			elif rng.randf() < 0.03:
				feat[i] = D.F_PLANT
	# the ruined Citadel
	var cw = 34
	var chh = 24
	cit_rect = Rect2i(D.W / 2 - cw / 2, 6, cw, chh)
	var cx = D.W / 2
	for y in range(cit_rect.position.y, cit_rect.end.y):
		for x in range(cit_rect.position.x, cit_rect.end.x):
			var i = y * D.W + x
			ground[i] = D.G_FLOOR
			feat[i] = D.F_NONE
			var edge = x == cit_rect.position.x or x == cit_rect.end.x - 1 or y == cit_rect.position.y or y == cit_rect.end.y - 1
			if edge:
				feat[i] = D.F_RUIN if rng.randf() < 0.07 else D.F_CWALL
				if y == cit_rect.end.y - 1 and abs(x - cx) <= 1:
					feat[i] = D.F_NONE
			elif rng.randf() < 0.035:
				feat[i] = D.F_RUIN
	keep_rect = Rect2i(cx - 6, cit_rect.position.y + 1, 13, 10)
	for y in range(keep_rect.position.y, keep_rect.end.y):
		for x in range(keep_rect.position.x, keep_rect.end.x):
			var i = y * D.W + x
			feat[i] = D.F_NONE
			var edge = x == keep_rect.position.x or x == keep_rect.end.x - 1 or y == keep_rect.end.y - 1
			if edge and not (y == keep_rect.end.y - 1 and abs(x - cx) <= 1):
				feat[i] = D.F_CWALL
	gateway = Vector2i(cx, keep_rect.position.y + 2)
	feat[gateway.y * D.W + gateway.x] = D.F_GATEWAY
	citadel_name = D.CIT_A[rng.randi() % D.CIT_A.size()] + D.CIT_B[rng.randi() % D.CIT_B.size()]
	# the camp below the Citadel's broken gate
	camp = Vector2i(cx, cit_rect.end.y + 11)
	for y in range(camp.y - 11, camp.y + 12):
		for x in range(camp.x - 12, camp.x + 13):
			if not in_bounds(Vector2i(x, y)):
				continue
			var i = y * D.W + x
			if Vector2(x, y).distance_to(Vector2(camp)) < 11.5:
				feat[i] = D.F_PLANT if (rng.randf() < 0.025 and Vector2(x, y).distance_to(Vector2(camp)) > 7) else D.F_NONE
				if ground[i] == D.G_WATER:
					ground[i] = D.G_ASH
	# a road from the camp to the gate
	for y in range(cit_rect.end.y - 1, camp.y):
		for x in range(cx - 1, cx + 2):
			var i = y * D.W + x
			if ground[i] == D.G_WATER:
				ground[i] = D.G_DUST
			if feat[i] != D.F_CWALL:
				feat[i] = D.F_NONE
	stock = camp + Vector2i(3, 1)
	cook = Vector2i(-1, -1)
	# bed slots in rows west of the fire, wall ring around everything
	for r in range(3, 8):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				_try_slot(camp + Vector2i(dx, dy))
		for dy in range(-r + 1, r):
			for dx in [-r, r]:
				_try_slot(camp + Vector2i(dx, dy))
	var R = 9
	for dx in range(-R, R + 1):
		for dy in range(-R, R + 1):
			if max(abs(dx), abs(dy)) != R:
				continue
			if abs(dx) <= 1 and abs(dy) == R:
				continue   # gates north and south
			if abs(dy) <= 1 and abs(dx) == R:
				continue   # gates east and west
			wall_ring.append(camp + Vector2i(dx, dy))
	# index resources
	for y in D.H:
		for x in D.W:
			var c = Vector2i(x, y)
			match feat[y * D.W + x]:
				D.F_TREE:
					trees[c] = true
				D.F_ROCK, D.F_RUIN:
					rocks[c] = true
				D.F_PLANT:
					plants[c] = true
	astar.region = Rect2i(0, 0, D.W, D.H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in D.H:
		for x in D.W:
			var c = Vector2i(x, y)
			if is_solid(c):
				astar.set_point_solid(c, true)
	# the Guardian sleeps on the keep's throne
	guardian = Creature.new()
	guardian.id = _nid()
	guardian.setup(self, "tyrant", Vector2(gateway.x + 0.5, gateway.y + 2.5), false)
	creatures.append(guardian)
	# the first cohort
	for i in 6:
		var p = _new_pawn(Vector2(camp.x + rng.randf_range(-3, 3), camp.y + rng.randf_range(-2, 3)))
		p.remember("Woke on the ash beneath %s." % citadel_name)
	for i in 3:
		_spawn_beast()
	next_raid = int(D.TICKS_PER_DAY * 2.9)
	tick = D.TICKS_PER_HOUR * 8
	wake = Waking.new()
	wake.gen(self, s)
	for p in pawns:
		wake.bed_for(p)
	log_event("The winter solstice. Six Sleepers wake on the ash beneath the ruined Citadel of %s. Its Gateway is sealed, and something vast stirs in the keep." % citadel_name, "spell")

func _try_slot(c: Vector2i) -> void:
	if not in_bounds(c) or c in bed_slots:
		return
	if abs(c.x - stock.x) <= 2 and abs(c.y - stock.y) <= 2:
		return
	if abs(c.x - camp.x) <= 1 or abs(c.y - camp.y) <= 1:
		return   # keep lanes to the gates clear
	if c.x < camp.x - 3 and c.y > camp.y and c.y < camp.y + 4:
		return   # room for the cooking fire
	bed_slots.append(c)

func an(n: String) -> String:
	return ("an " if n[0] in "AEIOU" else "a ") + n

func _nid() -> int:
	next_id += 1
	return next_id

func _new_pawn(p: Vector2):
	var pw = Pawn.new()
	pw.id = _nid()
	pw.setup(self, p)
	pawns.append(pw)
	if wake != null:
		wake.bed_for(pw)
	return pw

# ---------------------------------------------------------------- map queries
func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < D.W and c.y < D.H

func f_at(c: Vector2i) -> int:
	return feat[c.y * D.W + c.x]

func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	var i = c.y * D.W + c.x
	if ground[i] == D.G_WATER:
		return true
	var f = feat[i]
	if f == D.F_TREE or f == D.F_ROCK or f == D.F_RUIN or f == D.F_CWALL:
		return true
	var b = buildings.get(c)
	if b != null and D.BUILD[b.type].solid:
		return true
	return false

func walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_solid(c)

func refresh_cell(c: Vector2i) -> void:
	astar.set_point_solid(c, is_solid(c))
	dirty.append(c)

const NB := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

func find_path(from: Vector2i, to: Vector2i, adj: bool):
	## Returns an Array of cells to walk (empty when already there) or null.
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
			var cands: Array = []
			for d in NB:
				var n: Vector2i = to + d
				if in_bounds(n) and not astar.is_point_solid(n):
					cands.append(n)
			cands.sort_custom(func(a, b): return Vector2(a).distance_squared_to(Vector2(from)) < Vector2(b).distance_squared_to(Vector2(from)))
			for n in cands.slice(0, 3):
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

# ---------------------------------------------------------------- time
func day() -> int:
	return tick / D.TICKS_PER_DAY

func year() -> int:
	return day() / D.DAYS_PER_YEAR

func hour() -> float:
	return float(tick % D.TICKS_PER_DAY) / D.TICKS_PER_HOUR

func is_night() -> bool:
	var h = hour()
	return h >= 21.0 or h < 5.0

func creature_scale() -> float:
	return 1.0 + day() * 0.012 + (0.35 if gate_open else 0.0) + awakened_total * 0.015

func log_event(text: String, kind: String, who = null) -> void:
	events.append({"day": day(), "hour": hour(), "text": text, "kind": kind, "who": who})
	if events.size() > 400:
		events.pop_front()

# ---------------------------------------------------------------- the tick
func step() -> void:
	tick += 1
	for p in pawns:
		p.step()
	for c in creatures:
		c.step()
	wake.step()
	if tick % 30 == 0:
		pawns = pawns.filter(func(p): return p.alive)
		creatures = creatures.filter(func(c): return c.alive)
	if tick % D.TICKS_PER_HOUR == 0:
		_hourly()
	if tick % D.TICKS_PER_DAY == 0:
		_daily()
	if fx.size() > 0 and tick % 10 == 0:
		fx = fx.filter(func(f): return tick - f[2] < 90)

func _hourly() -> void:
	for p in pawns:
		p.update_mood()
	_plan()
	# regrowth
	for c in regrow.keys():
		if tick >= regrow[c][0]:
			var f: int = regrow[c][1]
			if f_at(c) == D.F_BARE or f_at(c) == D.F_SAPLING:
				if f == D.F_TREE and (_anyone_on(c) or buildings.has(c) or blueprints.has(c)):
					continue
				feat[c.y * D.W + c.x] = f
				if f == D.F_TREE:
					trees[c] = true
				else:
					plants[c] = true
				refresh_cell(c)
			regrow.erase(c)
	# wandering beasts
	var beasts = 0
	for c in creatures:
		if c.alive and not c.raider and not c.guardian:
			beasts += 1
	if beasts < 7 and rng.randf() < 0.35:
		_spawn_beast()
	# raids
	var h = hour()
	if not raid_active and not foreseen and tick >= next_raid - D.TICKS_PER_HOUR * 3:
		for p in pawns:
			if p.alive and p.perk() == "foresee" and p.away_until <= 0 and p.realm == "dream":
				foreseen = true
				log_event("%s sees it in a dream within the dream: Nightmare Creatures are coming tonight." % p.name, "spell", p)
				break
	if not raid_active and tick >= next_raid:
		_start_raid()
	if raid_active and h >= 6.0 and h < 7.0:
		for c in creatures:
			if c.alive and c.raider:
				c.alive = false
		log_event("Dawn comes. The last of the raiders melt back into the ash.", "info")
	if raid_active:
		var left = 0
		for c in creatures:
			if c.alive and c.raider:
				left += 1
		if left == 0:
			raid_active = false
			raids_survived += 1
			log_event("The raid is over. The camp still stands.", "good")
			for p in pawns:
				if p.alive:
					p.think("Survived a raid", 5, 2.0)
			next_raid = tick + int(D.TICKS_PER_DAY * rng.randf_range(1.6, 3.2))
			# raids come at night
			var hh = float(next_raid % D.TICKS_PER_DAY) / D.TICKS_PER_HOUR
			next_raid += int(fposmod(22.0 - hh, 24.0) * D.TICKS_PER_HOUR)
			foreseen = false
	# assault on the keep
	if not gate_open and not assault and not raid_active and h >= 11.0 and h < 12.0:
		_consider_assault()
	if assault:
		var fighters = 0
		for p in pawns:
			if p.alive and p.job.get("t", "") == "assault":
				fighters += 1
		if fighters == 0 and tick > assault_tries:
			assault = false
			log_event("The assault on the keep breaks. The survivors fall back, and the %s settles on its throne again." % guardian.name, "bad")
			for p in pawns:
				if p.alive:
					p.think("The assault failed", -8, 2.0)

func _daily() -> void:
	var d = day()
	if d % D.DAYS_PER_YEAR == 0:
		var n = rng.randi_range(2, 5)
		_arrivals(n, "The winter solstice. %d new Sleepers descend into the Dream Realm and stumble toward the firelight." % n)
	elif rng.randf() < 0.12:
		_arrivals(1, "A lone Sleeper staggers out of the ash and finds the camp.")
	for c in unreachable.keys():
		if unreachable[c] < tick:
			unreachable.erase(c)

func _arrivals(n: int, text: String) -> void:
	var edge = _edge_cell()
	for i in n:
		var p = _new_pawn(Vector2(edge.x + 0.5 + rng.randf_range(-1, 1), edge.y + 0.5))
		p.job = {"t": "arrive"}
		p.remember("Found the camp beneath %s." % citadel_name)
		arrivals += 1
	log_event(text, "spell")

func _edge_cell() -> Vector2i:
	for i in 200:
		var side = rng.randi() % 3
		var c: Vector2i
		if side == 0:
			c = Vector2i(rng.randi_range(2, D.W - 3), D.H - 2)
		elif side == 1:
			c = Vector2i(1, rng.randi_range(cit_rect.end.y, D.H - 2))
		else:
			c = Vector2i(D.W - 2, rng.randi_range(cit_rect.end.y, D.H - 2))
		if walkable(c) and find_path(c, camp, false) != null:
			return c
	return camp + Vector2i(0, 8)

func _spawn_beast() -> void:
	for i in 40:
		var c = Vector2i(rng.randi_range(2, D.W - 3), rng.randi_range(cit_rect.end.y + 2, D.H - 3))
		if walkable(c) and Vector2(c).distance_to(Vector2(camp)) > 16:
			var b = Creature.new()
			b.id = _nid()
			b.setup(self, "burrower" if rng.randf() < 0.7 else "chainback", Vector2(c.x + 0.5, c.y + 0.5), false)
			creatures.append(b)
			return

func _start_raid() -> void:
	raid_active = true
	var d = day()
	var n = 1 + int(d / 4.0) + int(pawns.size() / 5.0)
	n = min(n, 14)
	var edge = _edge_cell()
	var kinds: Array = []
	for i in n:
		var r = rng.randf()
		if d >= 26 and r < 0.1:
			kinds.append("fiend")
		elif d >= 11 and r < 0.3:
			kinds.append("mimic")
		elif r < 0.6:
			kinds.append("chainback")
		else:
			kinds.append("burrower")
	for k in kinds:
		var c = Creature.new()
		c.id = _nid()
		c.setup(self, k, Vector2(edge.x + 0.5 + rng.randf_range(-1.5, 1.5), edge.y + 0.5 + rng.randf_range(-1.5, 1.5)), true)
		creatures.append(c)
	var worst = "fiend" if "fiend" in kinds else ("mimic" if "mimic" in kinds else "chainback")
	log_event("A raid! %d Nightmare Creatures come out of the dark, led by %s." % [n, an(D.CREATURES[worst].name)], "bad")

func _consider_assault() -> void:
	var total = 0.0
	var fit = 0
	for p in pawns:
		if p.alive and assault_fit(p):
			total += p.power()
			fit += 1
	var need: float = guardian.dmg * guardian.hp * 1.0
	if fit >= 4 and total > need:
		assault = true
		assault_tries = tick + 300
		log_event("The colony gathers its strongest. %d fighters march into the keep of %s to face the %s." % [fit, citadel_name, guardian.name], "spell")

func assault_fit(p) -> bool:
	return p.alive and p.realm == "dream" and p.away_until <= 0 and p.hp > p.max_hp() * 0.7 and p.mood > 25 and tick >= p.break_until

# ---------------------------------------------------------------- planning
func _plan() -> void:
	var pop = 0
	for p in pawns:
		if p.alive:
			pop += 1
	if blueprints.size() > 14:
		return
	# beds for everyone
	var beds = 0
	for c in buildings:
		if buildings[c].type == "bed":
			beds += 1
	for c in blueprints:
		if blueprints[c].type == "bed":
			beds += 1
	if beds < pop:
		for s in bed_slots:
			if not buildings.has(s) and not blueprints.has(s) and walkable(s) and f_at(s) == D.F_NONE:
				_bp(s, "bed")
				break
	# arms
	if arms == 0 and store.wood >= 40:
		store.wood -= 30
		arms = 1
		log_event("The colony carves fire-hardened spears from the dead trees.", "good")
	elif arms == 1 and day() >= 4 and store.stone >= 40 and store.wood >= 30:
		store.stone -= 30
		store.wood -= 20
		arms = 2
		log_event("Stone axes and stone-tipped spears for everyone. The colony can fight back now.", "good")
	elif arms == 2 and store.shards >= 10 and store.stone >= 60:
		store.shards -= 10
		store.stone -= 40
		arms = 3
		log_event("Soul shards are worked into blade edges. The weapons hum faintly in the dark.", "spell")
	# a cooking fire once the first day is done
	if cook.x < 0 and day() >= 1 and not _has_bp("cook"):
		_bp(camp + Vector2i(-4, 2), "cook")
	# braziers at the gates of the wall
	# the palisade
	if day() >= 2 and store.wood >= 12:
		var added = 0
		for c in wall_ring:
			if added >= 6:
				break
			if buildings.has(c) or blueprints.has(c):
				continue
			if is_solid(c) or f_at(c) != D.F_NONE:
				continue
			_bp(c, "wall")
			added += 1
	# stone walls replace palisades later
	if day() >= 9 and store.stone >= 30:
		var added = 0
		for c in wall_ring:
			if added >= 4:
				break
			var b = buildings.get(c)
			if b != null and b.type == "wall" and not blueprints.has(c):
				_bp(c, "swall")
				added += 1
	if day() >= 4 and store.stone >= 6 and store.wood >= 10:
		for c in [camp + Vector2i(-2, -9), camp + Vector2i(2, -9), camp + Vector2i(-2, 9), camp + Vector2i(2, 9)]:
			c = c + Vector2i(0, 1 if c.y > camp.y else -1)
			if walkable(c) and not buildings.has(c) and not blueprints.has(c) and f_at(c) == D.F_NONE:
				_bp(c, "torch")
				break

func _has_bp(t: String) -> bool:
	for c in blueprints:
		if blueprints[c].type == t:
			return true
	return false

func _bp(c: Vector2i, t: String) -> void:
	blueprints[c] = {"type": t, "delivered": false}

func finish_building(c: Vector2i, by) -> void:
	var bp = blueprints.get(c)
	if bp == null:
		return
	blueprints.erase(c)
	var t: String = bp.type
	if D.BUILD[t].solid:
		for p in pawns:
			if p.alive and p.realm == "dream" and p.tile() == c:
				# step aside before the wall goes up
				for d in NB:
					if walkable(c + d):
						p.pos = Vector2(c.x + d.x + 0.5, c.y + d.y + 0.5)
						break
	buildings[c] = {"type": t, "hp": D.BUILD[t].get("hp", 100), "owner": -1}
	if t == "cook":
		cook = c
		log_event("%s builds a cooking fire. Meals will be hot from now on." % by.name, "good", by)
	refresh_cell(c)

func damage_building(c: Vector2i, amount: float) -> void:
	var b = buildings.get(c)
	if b == null:
		return
	b.hp -= amount
	fx.append(["hit", Vector2(c.x + 0.5, c.y + 0.5), tick])
	if b.hp <= 0:
		buildings.erase(c)
		refresh_cell(c)
		log_event("Nightmare Creatures break through the %s." % D.BUILD[b.type].name.to_lower(), "bad")

# ---------------------------------------------------------------- work
func pick_work(p):
	var pop = pawns.size()
	var food: int = store.raw + store.meal
	var opts: Array = []
	# build
	var best_bp = null
	var best_d = 1e9
	for c in blueprints:
		var bp = blueprints[c]
		if bp.delivered or reserved.has(c) or unreachable.has(c):
			continue
		var cost: Dictionary = D.BUILD[bp.type]
		if store.wood < cost.wood or store.stone < cost.stone:
			continue
		var d: float = p.pos.distance_squared_to(Vector2(c))
		if bp.type == "bed" and p.bed == null:
			d *= 0.3
		if d < best_d:
			best_d = d
			best_bp = c
	if best_bp != null:
		opts.append([4.5 * p.skill_mult("build"), {"t": "build", "target": best_bp, "btype": blueprints[best_bp].type}])
	if cook.x >= 0 and store.raw >= 3 and store.meal < pop * 2 and not _someone_doing("cook", 2):
		opts.append([4.0 * p.skill_mult("cook") * (1.4 if p.perk() == "fire" else 1.0), {"t": "cook"}])
	var fneed = 4.2 if food < pop * 6 else (1.6 if food < pop * 14 else (0.3 if food < pop * 30 else 0.0))
	var t = _nearest(plants, p)
	if t != null:
		opts.append([fneed * p.skill_mult("forage"), {"t": "forage", "target": t}])
	var wneed = 3.2 if store.wood < 40 else (1.2 if store.wood < 120 else (0.3 if store.wood < 300 else 0.0))
	t = _nearest(trees, p)
	if t != null:
		opts.append([wneed * p.skill_mult("labor"), {"t": "chop", "target": t}])
	var sneed = (2.6 if store.stone < 40 else (1.0 if store.stone < 120 else 0.2)) * (0.4 if day() < 3 else 1.0)
	t = _nearest(rocks, p)
	if t != null:
		opts.append([sneed * p.skill_mult("labor"), {"t": "mine", "target": t}])
	if p.hp > p.max_hp() * 0.8 and p.trait_name != "Timid":
		var prey = null
		var pd = 30.0
		for c in creatures:
			if c.alive and not c.raider and not c.guardian and c.aggro == null:
				var dd: float = c.pos.distance_to(p.pos)
				if dd < pd and p.power() > c.dmg * c.hp * 0.6:
					pd = dd
					prey = c
		if prey != null and not _someone_hunting(prey):
			opts.append([(2.2 + (1.5 if food < pop * 6 else 0.0)) * p.skill_mult("combat"), {"t": "hunt", "e": prey}])
	opts.append([0.9, null])
	if opts.is_empty():
		return null
	var best = null
	var bs = -1.0
	for o in opts:
		var s: float = o[0] * rng.randf_range(0.7, 1.3)
		if s > bs:
			bs = s
			best = o[1]
	return best

func _someone_doing(t: String, n: int) -> bool:
	var k = 0
	for p in pawns:
		if p.alive and p.job.get("t", "") == t:
			k += 1
	return k >= n

func _someone_hunting(c) -> bool:
	for p in pawns:
		if p.alive and p.job.get("t", "") == "hunt" and p.job.e == c:
			return true
	return false

func _nearest(set: Dictionary, p):
	var best = null
	var bd = 1e9
	var pp: Vector2 = p.pos
	for c in set:
		if reserved.has(c) or unreachable.has(c):
			continue
		if cit_rect.has_point(c) and not gate_open and keep_rect.has_point(c):
			continue
		var d = pp.distance_squared_to(Vector2(c))
		if d < bd:
			bd = d
			best = c
	return best

func feature_ok(t: String, c: Vector2i) -> bool:
	match t:
		"chop":
			return trees.has(c)
		"mine":
			return rocks.has(c)
		"forage":
			return plants.has(c)
	return false

func harvest(t: String, c: Vector2i, p) -> Array:
	var i = c.y * D.W + c.x
	match t:
		"chop":
			trees.erase(c)
			feat[i] = D.F_SAPLING
			regrow[c] = [tick + D.TICKS_PER_DAY * 6, D.F_TREE]
			refresh_cell(c)
			return ["wood", 8]
		"mine":
			rocks.erase(c)
			feat[i] = D.F_NONE
			refresh_cell(c)
			return ["stone", 6]
		"forage":
			plants.erase(c)
			feat[i] = D.F_BARE
			var fast = false
			for q in pawns:
				if q.alive and q.realm == "dream" and q.perk() == "regrow" and q.pos.distance_to(Vector2(c)) < 15:
					fast = true
			regrow[c] = [tick + int(D.TICKS_PER_DAY * (0.7 if fast else 1.6)), D.F_PLANT]
			refresh_cell(c)
			return ["raw", 5]
	return ["", 0]

func _anyone_on(c: Vector2i) -> bool:
	for p in pawns:
		if p.alive and p.realm == "dream" and p.tile() == c:
			return true
	return false

func food_available() -> bool:
	return store.raw + store.meal > 0

func shard_turn(p) -> bool:
	# hand shards to the strongest fighters first, but let everyone grow
	shard_rr += 1
	if arms == 2 and day() >= 8 and store.shards < 10:
		return false
	return p.rank > 0 or shard_rr % 2 == 0 or p.skills.combat > 4

func bed_owner(c) -> int:
	var b = buildings.get(c)
	return -1 if b == null else b.owner

func claim_bed(p):
	for c in buildings:
		var b = buildings[c]
		if b.type == "bed" and (b.owner == -1 or b.owner == p.id or not _alive_id(b.owner)):
			b.owner = p.id
			return c
	return null

func _alive_id(id: int) -> bool:
	for p in pawns:
		if p.id == id and p.alive:
			return true
	return false

func ground_spot(p) -> Vector2i:
	var a = float(p.id) * 2.39
	var c = camp + Vector2i(int(cos(a) * 3.5), int(sin(a) * 3.0))
	return c if walkable(c) else camp + Vector2i(0, 2)

func healer_bonus(p) -> float:
	var b = 0.0
	for q in pawns:
		if q != p and q.alive and q.away_until <= 0 and q.realm == p.realm and q.perk() == "heal" and q.at().distance_to(p.at()) < 6:
			b += 0.8 + q.skills.heal * 0.15
	return b

func rally_near(p) -> bool:
	for q in pawns:
		if q != p and q.alive and q.realm == p.realm and q.perk() == "rally" and q.at().distance_to(p.at()) < 6:
			return true
	return false

func nearest_hostile(pos: Vector2, r: float):
	var best = null
	var bd = r
	for c in creatures:
		if c.alive and not c.guardian and (c.raider or c.aggro != null):
			var d = pos.distance_to(c.pos)
			if d < bd:
				bd = d
				best = c
	return best

func nearest_pawn(pos: Vector2, r: float):
	var best = null
	var bd = r
	for p in pawns:
		if p.alive and p.away_until <= 0 and p.realm == "dream":
			var d = pos.distance_to(p.pos)
			if d < bd:
				bd = d
				best = p
	return best

func chat(p) -> void:
	if rng.randf() < 0.04:
		var others: Array = []
		for q in pawns:
			if q != p and q.alive and q.job.get("t", "") == "social":
				others.append(q)
		if others.size() > 0:
			var q = others[rng.randi() % others.size()]
			var lines = ["%s and %s trade stories about the waking world." , "%s teaches %s a song from home.", "%s and %s argue about what lives in the keep.", "%s tells %s about the dream they keep having.", "%s and %s laugh by the fire for the first time in days."]
			log_event(lines[rng.randi() % lines.size()] % [p.name, q.name], "info", p)

# ---------------------------------------------------------------- death, kills, the Gateway
func creature_died(c, killer) -> void:
	kills += 1
	fx.append(["die", c.pos, tick])
	if killer != null and killer.has_method("remember"):
		killer.kills += 1
	if c.guardian:
		gate_open = true
		assault = false
		var who: String = killer.name if killer != null else "the colony"
		log_event("The %s falls, slain by %s! The Gateway of %s stands open. The Sleepers can Awaken." % [c.name, who, citadel_name], "spell", killer)
		store.shards += 6
		for p in pawns:
			if p.alive:
				p.think("The Gateway is open", 20, 6.0)
				p.remember("Saw the %s fall." % c.name)
		if killer != null and killer.has_method("remember"):
			killer.remember("Struck the killing blow on the %s." % c.name)
		return
	var chance: float = D.CREATURES[c.kind].shard
	if killer != null and killer.has_method("perk") and killer.perk() == "reaper":
		chance += 0.3
	var shards = 0
	while chance > 0.0:
		if rng.randf() < chance:
			shards += 1
		chance -= 1.0
	store.shards += shards
	if not c.raider:
		store.raw += 6
	if c.kind == "fiend" or c.kind == "mimic":
		var who2: String = killer.name if killer != null and killer.has_method("remember") else "the colony"
		log_event("%s kills %s." % [who2, an(c.name)], "good", killer if killer != null and killer.has_method("remember") else null)
		if killer != null and killer.has_method("remember"):
			killer.remember("Killed a %s." % c.name)

func pawn_died(p, killer, cause: String) -> void:
	deaths += 1
	if p.realm == "dream":
		graves.append([p.pos, p.name, day()])
	if p.job.has("target") and reserved.get(p.job.target, -1) == p.id:
		reserved.erase(p.job.target)
	var how = "starves" if cause == "starvation" else ("is killed by %s" % an(killer.name) if killer != null else "dies")
	if p.realm == "wake":
		how += " in the streets of %s" % wake.city_code
	log_event("%s %s. %s" % [p.name, how, ("A Sleeper of the %s Aspect, %d days in the Dream Realm." if p.rank == 0 else "An Awakened of the %s Aspect.") % ([p.nature, (tick - p.arrived) / D.TICKS_PER_DAY] if p.rank == 0 else [p.nature])], "bad", p)
	for q in pawns:
		if q != p and q.alive:
			q.think("%s died" % p.name, -10, 2.5)

func enter_gateway(p, kind: String) -> void:
	if kind == "awaken" or kind == "home":
		_cross_to_waking(p, kind)
		return
	p.away_kind = kind
	p.away_until = tick + int(D.TICKS_PER_DAY * (0.5 if kind == "awaken" else 1.5))
	p.sleeping = false
	p.path = []
	if kind == "awaken":
		log_event("%s steps through the Gateway and wakes in the real world." % p.name, "rise", p)
	else:
		log_event("%s walks into the Gateway to face the Second Nightmare alone." % p.name, "spell", p)

func _cross_to_waking(p, kind: String) -> void:
	p.cancel_job()
	p.sleeping = false
	p.path = []
	if kind == "awaken":
		p.rank = 1
		p.core = min(p.core, 1.0) * 0.5
		p.hp = p.max_hp()
		awakened_total += 1
		p.think("Awakened", 15, 4.0)
		p.remember("Awakened with a %s Aspect and opened their eyes in %s." % [p.nature, wake.city_code])
		log_event("%s crosses the Gateway and wakes in the Sleepers' ward of %s, Awakened with the %s Aspect." % [p.name, wake.city_code, p.nature], "rise", p)
	else:
		pass   # routine crossings stay out of the chronicle; the inspector shows where they are
	wake.arrive(p)
	p.wake_stay = rng.randf_range(0.6, 2.2)

func enter_dream(p) -> void:
	## An Awakened falls asleep in the waking world and appears beside the Citadel's Gateway.
	p.realm = "dream"
	p.wsleep = false
	p.wjob = {}
	p.wpath = []
	p.job = {}
	p.path = []
	p.pos = Vector2(gateway.x + 0.5, gateway.y + 1.5)
	p.rest = max(p.rest, 80.0)
	p.dream_since = tick
	p.dream_stay = rng.randf_range(2.0, 5.0)

func can_go_home(p) -> bool:
	## Awakened slip back to the waking world now and then, if the camp can spare them.
	if p.realm != "dream" or raid_active or assault or foreseen:
		return false
	if tick - p.dream_since < int(D.TICKS_PER_DAY * p.dream_stay):
		return false
	var h = hour()
	if h < 8.0 or h > 17.0 or p.hp < p.max_hp() * 0.6:
		return false
	var fighters = 0
	for q in pawns:
		if q != p and q.alive and q.realm == "dream" and q.away_until <= 0 and q.rank >= 1:
			fighters += 1
	return fighters >= 2 or (fighters >= 1 and rng.randf() < 0.05)

func return_from_gateway(p) -> void:
	var kind: String = p.away_kind
	p.away_until = -1
	p.away_kind = ""
	p.pos = Vector2(gateway.x + 0.5, gateway.y + 1.5)
	p.job = {}
	if kind == "awaken":
		p.rank = 1
		p.core = min(p.core, 1.0) * 0.5
		p.hp = p.max_hp()
		awakened_total += 1
		p.think("Awakened", 15, 4.0)
		p.remember("Awakened with a %s Aspect." % p.nature)
		log_event("%s returns through the Gateway, Awakened. Their %s Aspect is theirs now." % [p.name, p.nature], "rise", p)
	else:
		var odds: float = 0.35 + p.skills.combat * 0.03
		if rng.randf() < odds:
			p.rank = 2
			p.core = 0.0
			p.hp = p.max_hp()
			masters_total += 1
			p.remember("Conquered the Second Nightmare and Ascended.")
			log_event("%s returns from the Second Nightmare. They have Ascended and become a Master!" % p.name, "spell", p)
			for q in pawns:
				if q.alive and q != p:
					q.think("%s Ascended" % p.name, 6, 3.0)
		else:
			p.alive = false
			deaths += 1
			log_event("%s never returns from the Second Nightmare." % p.name, "bad", p)
			for q in pawns:
				if q.alive and q != p:
					q.think("%s was lost to a Nightmare" % p.name, -8, 3.0)
