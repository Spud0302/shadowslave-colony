extends RefCounted
## A colonist: a Sleeper or an Awakened, with needs, skills, an Aspect and a job.

const D = preload("res://scripts/data.gd")

var w
var id = 0
var name = ""
var nature = ""
var trait_name = ""
var rank = 0
var core = 0.0
var pos = Vector2()
var path: Array = []
var hp = 60.0
var hunger = 85.0
var rest = 85.0
var mood = 55.0
var skills = {}
var job = {}
var carry = ""
var carry_n = 0
var thoughts: Array = []   # [text, value, until_tick]
var cd = 0
var alive = true
var away_until = -1
var away_kind = ""
var kills = 0
var arrived = 0
var used_unbroken = false
var activity = "Idle"
var bed = null
var break_until = 0
var think_t = 0
var sleeping = false
var hit_flash = 0
var history: Array = []

func setup(world, p: Vector2) -> void:
	w = world
	var r = world.rng
	name = D.FIRST[r.randi() % D.FIRST.size()] + " " + D.LAST[r.randi() % D.LAST.size()]
	var keys = D.NATURES.keys()
	nature = keys[r.randi() % keys.size()]
	trait_name = D.TRAITS[r.randi() % D.TRAITS.size()]
	for s in D.SKILLS:
		skills[s] = r.randf_range(0.0, 3.0)
	var bonus: Dictionary = D.NATURES[nature][1]
	for s in bonus:
		skills[s] += bonus[s]
	pos = p
	hp = max_hp()
	arrived = world.tick

func perk() -> String:
	return D.NATURES[nature][2]

func color() -> Color:
	return Color(D.NATURES[nature][0])

func tile() -> Vector2i:
	return Vector2i(int(pos.x), int(pos.y))

func max_hp() -> float:
	return D.RANK_HP[rank] * (1.0 + core * 0.8)

func damage() -> float:
	var d: float = D.RANK_DMG[rank] * (1.0 + core * 0.9) * (1.0 + skills.combat * 0.07) * D.ARMS_MULT[w.arms]
	if perk() == "fire":
		d *= 1.25
	if perk() == "rage":
		d *= 1.0 + (1.0 - hp / max_hp()) * 1.2
	if trait_name == "Hot-headed":
		d *= 1.1
	if w.rally_near(self):
		d *= 1.2
	return d

func power() -> float:
	return damage() * max_hp()

func skill_mult(s: String) -> float:
	return 0.55 + skills[s] * 0.11

func spd() -> float:
	var s = 0.11
	if perk() == "speed":
		s *= 1.35
	if hunger < 15 or rest < 10:
		s *= 0.75
	if hp < max_hp() * 0.35:
		s *= 0.7
	return s

func think(text: String, value: float, days: float) -> void:
	for t in thoughts:
		if t[0] == text:
			t[2] = w.tick + int(days * D.TICKS_PER_DAY)
			return
	thoughts.append([text, value, w.tick + int(days * D.TICKS_PER_DAY)])

func remember(text: String) -> void:
	history.append("Day %d: %s" % [w.day() + 1, text])
	if history.size() > 12:
		history.pop_front()

# ---------------------------------------------------------------- tick
func step() -> void:
	if not alive:
		return
	if away_until > 0:
		if w.tick >= away_until:
			w.return_from_gateway(self)
		return
	if cd > 0:
		cd -= 1
	if hit_flash > 0:
		hit_flash -= 1
	var rest_rate = 100.0 / (D.TICKS_PER_DAY * 1.05)
	if perk() == "lull":
		rest_rate *= 0.5
	if trait_name == "Tireless":
		rest_rate *= 0.8
	var hunger_rate = 100.0 / (D.TICKS_PER_DAY * 1.25)
	if trait_name == "Glutton":
		hunger_rate *= 1.3
	hunger = max(0.0, hunger - hunger_rate)
	if not sleeping:
		rest = max(0.0, rest - rest_rate)
	if hunger <= 0.0 and w.tick % 60 == 0:
		take_hit(1.5, null, "starvation")
		if not alive:
			return
	# slow natural healing
	if hp < max_hp() and w.tick % 40 == 0:
		hp = min(max_hp(), hp + (0.6 if not sleeping else 2.0) + w.healer_bonus(self))
	think_t -= 1
	if think_t <= 0:
		think_t = 20
		_interrupts()
	if job.is_empty():
		_decide()
	_run_job()

func update_mood() -> void:
	var m = 50.0
	var keep: Array = []
	for t in thoughts:
		if t[2] > w.tick:
			keep.append(t)
			m += t[1]
	thoughts = keep
	if hunger < 20:
		m -= 10
	if rest < 20:
		m -= 8
	if hp < max_hp() * 0.5:
		m -= 6
	if trait_name == "Hopeful":
		m += 6
	if trait_name == "Grim":
		m -= 6
	mood = lerp(mood, clamp(m, 0.0, 100.0), 0.3)
	if mood < 16 and break_until < w.tick and w.rng.randf() < 0.08 and job.get("t", "") != "fight":
		break_until = w.tick + 500
		_set_job({"t": "break"})
		w.log_event("%s's spirit breaks. They wander off, lost in despair." % name, "bad", self)
		remember("Their spirit broke.")

func _interrupts() -> void:
	var t: String = job.get("t", "")
	if t == "break" or t == "assault" or t == "gateway":
		return
	var enemy = w.nearest_hostile(pos, 9.0 if w.raid_active else 5.0)
	var brave = hp > max_hp() * (0.5 if trait_name == "Timid" else 0.35)
	if enemy != null and brave and t != "fight":
		_set_job({"t": "fight", "e": enemy})
		return
	if hp < max_hp() * 0.3 and t != "recover" and (enemy == null or not brave):
		_set_job({"t": "recover"})
		return
	if w.assault and t != "assault" and w.assault_fit(self):
		_set_job({"t": "assault"})
		return
	if t == "sleep" and enemy != null:
		_set_job({})

func _decide() -> void:
	activity = "Idle"
	if w.tick < break_until:
		_set_job({"t": "break"})
		return
	if hunger < 32 and w.food_available():
		_set_job({"t": "eat"})
		return
	var night: bool = w.is_night()
	var want_sleep = rest < 22 or (night and rest < 75)
	if trait_name == "Night owl":
		want_sleep = rest < 22 or (not night and w.hour() > 6.0 and w.hour() < 12.0 and rest < 60)
	if want_sleep:
		_set_job({"t": "sleep"})
		return
	if hp < max_hp() * 0.6 and night:
		_set_job({"t": "recover"})
		return
	if w.gate_open and rank == 0:
		_set_job({"t": "gateway", "kind": "awaken"})
		return
	if w.gate_open and rank == 1 and core >= 0.999 and w.rng.randf() < 0.05:
		_set_job({"t": "gateway", "kind": "nightmare"})
		return
	if w.store.shards > 0 and core < 0.999 and w.shard_turn(self):
		_set_job({"t": "absorb"})
		return
	var work = w.pick_work(self)
	if work != null:
		_set_job(work)
		return
	if w.hour() > 18.0 and w.rng.randf() < 0.6:
		_set_job({"t": "social", "timer": w.rng.randi_range(120, 260)})
		return
	_set_job({"t": "wander"})

func _set_job(j: Dictionary) -> void:
	_release()
	if sleeping:
		sleeping = false
	job = j
	path = []
	if job.has("target"):
		w.reserved[job.target] = id

func _release() -> void:
	if job.has("target") and w.reserved.get(job.target, -1) == id:
		w.reserved.erase(job.target)
	if job.get("t", "") == "build" and job.get("taken", false) and not job.get("done", false):
		# put the materials back
		var bp = w.blueprints.get(job.target)
		if bp != null:
			bp.delivered = false
		var cost: Dictionary = D.BUILD[job.btype]
		w.store.wood += cost.wood
		w.store.stone += cost.stone

func cancel_job() -> void:
	_set_job({})

# ---------------------------------------------------------------- movement
func _go(to: Vector2i, adj: bool) -> int:
	## 1 = arrived, 0 = walking, -1 = unreachable
	var here = tile()
	if adj:
		if Vector2(here).distance_to(Vector2(to)) < 1.5 and path.is_empty():
			return 1
	elif here == to and path.is_empty():
		return 1
	if path.is_empty():
		var p = w.find_path(here, to, adj)
		if p == null:
			return -1
		if p.is_empty():
			return 1
		path = p
	var nxt: Vector2i = path[0]
	if w.is_solid(nxt):
		path = []
		return 0
	var target = Vector2(nxt.x + 0.5, nxt.y + 0.5)
	var v = target - pos
	var s = spd()
	if v.length() <= s:
		pos = target
		path.pop_front()
	else:
		pos += v.normalized() * s
	return 0

# ---------------------------------------------------------------- jobs
func _run_job() -> void:
	if job.is_empty():
		return
	match job.t:
		"chop", "mine", "forage":
			_gather()
		"build":
			_build()
		"cook":
			_cook()
		"eat":
			_eat()
		"sleep":
			_sleep(false)
		"recover":
			_sleep(true)
		"fight":
			_fight(job.e)
		"hunt":
			activity = "Hunting a " + job.e.name
			_fight(job.e)
		"assault":
			_assault()
		"gateway":
			_gateway()
		"absorb":
			_absorb()
		"social":
			_social()
		"wander":
			_wander()
		"break":
			_break()
		"arrive":
			activity = "Walking to the camp"
			if _go(w.camp + Vector2i(w.rng.randi_range(-2, 2), 2), false) != 0:
				_set_job({})
		_:
			_set_job({})

func _gather() -> void:
	var t: Vector2i = job.get("target", Vector2i(-1, -1))
	var label = {"chop": "Felling a dead tree", "mine": "Breaking stone", "forage": "Gathering ashroot"}[job.t]
	activity = label
	var stage: int = job.get("stage", 0)
	if stage == 0:
		if not w.feature_ok(job.t, t):
			_set_job({})
			return
		var r = _go(t, true)
		if r == -1:
			w.unreachable[t] = w.tick + 2000
			_set_job({})
		elif r == 1:
			job.stage = 1
			job.timer = int({"chop": 220, "mine": 280, "forage": 110}[job.t] / skill_mult("labor" if job.t != "forage" else "forage"))
	elif stage == 1:
		job.timer -= 1
		if job.timer <= 0:
			var res: Array = w.harvest(job.t, t, self)
			carry = res[0]
			carry_n = res[1]
			skills["labor" if job.t != "forage" else "forage"] += 0.04
			w.reserved.erase(t)
			job.erase("target")
			job.stage = 2
	else:
		activity = "Carrying %s to the stockpile" % carry
		if _go(w.stock, false) != 0:
			w.store[carry] += carry_n
			carry = ""
			carry_n = 0
			_set_job({})

func _build() -> void:
	var t: Vector2i = job.target
	var bp = w.blueprints.get(t)
	if bp == null:
		_set_job({})
		return
	activity = "Building a " + D.BUILD[job.btype].name.to_lower()
	var stage: int = job.get("stage", 0)
	if stage == 0:
		var r = _go(w.stock, false)
		if r == 1:
			var cost: Dictionary = D.BUILD[job.btype]
			if w.store.wood < cost.wood or w.store.stone < cost.stone:
				_set_job({})
				return
			w.store.wood -= cost.wood
			w.store.stone -= cost.stone
			job.taken = true
			bp.delivered = true
			carry = "wood" if cost.wood > 0 else "stone"
			carry_n = cost.wood + cost.stone
			job.stage = 1
		elif r == -1:
			_set_job({})
	elif stage == 1:
		var solid: bool = D.BUILD[job.btype].solid
		var r = _go(t, solid)
		if r == 1:
			job.stage = 2
			job.timer = int(D.BUILD[job.btype].work / skill_mult("build"))
		elif r == -1:
			w.unreachable[t] = w.tick + 1500
			_set_job({})
	else:
		job.timer -= 1
		if job.timer <= 0:
			carry = ""
			carry_n = 0
			job.done = true
			skills.build += 0.05
			w.finish_building(t, self)
			_set_job({})

func _cook() -> void:
	activity = "Cooking"
	var stage: int = job.get("stage", 0)
	if stage == 0:
		var r = _go(w.stock, false)
		if r == 1:
			if w.store.raw < 3:
				_set_job({})
				return
			w.store.raw -= 3
			carry = "raw"
			carry_n = 3
			job.stage = 1
		elif r == -1:
			_set_job({})
	elif stage == 1:
		var r = _go(w.cook, true)
		if r == 1:
			job.stage = 2
			job.timer = int(150 / skill_mult("cook") / (1.3 if perk() == "fire" else 1.0))
		elif r == -1:
			w.store.raw += 3
			carry = ""
			_set_job({})
	elif stage == 2:
		job.timer -= 1
		if job.timer <= 0:
			carry = "meal"
			carry_n = 3
			skills.cook += 0.05
			job.stage = 3
	else:
		activity = "Carrying meals to the stockpile"
		if _go(w.stock, false) != 0:
			w.store.meal += carry_n
			carry = ""
			carry_n = 0
			_set_job({})

func _eat() -> void:
	activity = "Going to eat"
	var stage: int = job.get("stage", 0)
	if stage == 0:
		var r = _go(w.stock + Vector2i(w.rng.randi_range(-1, 1), 1), false)
		if r != 0:
			job.stage = 1
			job.timer = 70
			if w.store.meal > 0:
				w.store.meal -= 1
				job.food = "meal"
			elif w.store.raw > 0:
				w.store.raw -= 1
				job.food = "raw"
			else:
				_set_job({})
	else:
		activity = "Eating"
		job.timer -= 1
		if job.timer <= 0:
			if job.food == "meal":
				hunger = min(100.0, hunger + 62)
				think("Ate a hot meal", 5, 1.0)
			else:
				hunger = min(100.0, hunger + 38)
				think("Ate raw ashroot", -4, 1.0)
			_set_job({})

func _sleep(recovering: bool) -> void:
	if bed == null or not w.buildings.has(bed) or w.bed_owner(bed) != id:
		bed = w.claim_bed(self)
	var spot: Vector2i = bed if bed != null else w.ground_spot(self)
	var stage: int = job.get("stage", 0)
	if stage == 0:
		activity = "Going to rest" if recovering else "Going to bed"
		var r = _go(spot, false)
		if r != 0:
			job.stage = 1
			sleeping = true
	else:
		sleeping = true
		activity = "Recovering in bed" if recovering else "Sleeping"
		var gain = 100.0 / (D.TICKS_PER_DAY * 0.3)
		rest = min(100.0, rest + gain)
		if recovering:
			if w.tick % 30 == 0:
				hp = min(max_hp(), hp + 2.5 + w.healer_bonus(self))
			if hp >= max_hp() * 0.85 and rest > 60:
				_wake(bed != null)
		elif rest >= 99.0 or (not w.is_night() and rest > 70):
			_wake(bed != null)

func _wake(in_bed: bool) -> void:
	sleeping = false
	if in_bed:
		think("Slept in a bed", 3, 1.0)
	else:
		think("Slept on the ash", -5, 1.0)
	_set_job({})

func _fight(e) -> void:
	if e == null or not e.alive:
		_set_job({})
		return
	if job.t == "fight":
		activity = "Fighting a " + e.name
	var d = pos.distance_to(e.pos)
	if d > 16.0:
		_set_job({})
		return
	if d < 1.5:
		path = []
		if cd <= 0:
			e.take_hit(damage() * w.rng.randf_range(0.75, 1.25), self)
			cd = 30
			skills.combat += 0.02
		return
	if path.is_empty() or w.tick % 15 == id % 15:
		var p = w.find_path(tile(), e.tile(), false)
		path = p if p != null else []
		if p == null:
			_set_job({})
			return
	_go(e.tile(), false)

func _assault() -> void:
	activity = "Storming the keep"
	if not w.assault:
		_set_job({})
		return
	var g = w.guardian
	if g == null or not g.alive:
		_set_job({})
		return
	if hp < max_hp() * 0.25:
		_set_job({"t": "recover"})
		return
	var d = pos.distance_to(g.pos)
	if d < 1.9:
		path = []
		if cd <= 0:
			g.take_hit(damage() * w.rng.randf_range(0.75, 1.25), self)
			cd = 30
			skills.combat += 0.03
		return
	if path.is_empty():
		var p = w.find_path(tile(), g.tile(), true)
		path = p if p != null else []
	_go(g.tile(), true)

func _gateway() -> void:
	activity = "Walking to the Gateway" if job.kind == "awaken" else "Going to face the Second Nightmare"
	var r = _go(w.gateway, false)
	if r == 1:
		w.enter_gateway(self, job.kind)
		job = {}
	elif r == -1:
		_set_job({})

func _absorb() -> void:
	activity = "Absorbing a soul shard"
	var stage: int = job.get("stage", 0)
	if stage == 0:
		var r = _go(w.stock, true)
		if r == 1:
			if w.store.shards <= 0:
				_set_job({})
				return
			w.store.shards -= 1
			job.stage = 1
			job.timer = 50
		elif r == -1:
			_set_job({})
	else:
		job.timer -= 1
		if job.timer <= 0:
			var before = core
			core = min(1.0, core + (0.14 if rank == 0 else 0.07 if rank == 1 else 0.025))
			hp = min(max_hp(), hp + 10)
			if before < 1.0 and core >= 1.0:
				w.log_event("%s's soul core is saturated." % name, "rise", self)
				remember("Saturated their soul core.")
			_set_job({})

func _social() -> void:
	activity = "Sitting by the fire"
	var spot: Vector2i = job.get("spot", Vector2i(-1, -1))
	if spot.x < 0:
		spot = w.camp + Vector2i(w.rng.randi_range(-2, 2), w.rng.randi_range(-2, 2))
		if not w.walkable(spot):
			spot = w.camp + Vector2i(0, 1)
		job.spot = spot
	if _go(spot, false) != 0:
		job.timer -= 1
		if job.timer % 90 == 0:
			w.chat(self)
		if job.timer <= 0:
			think("Talked by the fire", 3, 0.6)
			_set_job({})

func _wander() -> void:
	activity = "Wandering"
	if not job.has("dest"):
		var t = w.camp + Vector2i(w.rng.randi_range(-6, 6), w.rng.randi_range(-6, 6))
		job.dest = t if w.walkable(t) else w.camp + Vector2i(0, 1)
		job.timer = w.rng.randi_range(40, 140)
	if _go(job.dest, false) != 0:
		job.timer -= 1
		if job.timer <= 0:
			_set_job({})

func _break() -> void:
	activity = "Wandering in despair"
	if w.tick >= break_until:
		think("Recovered from a breakdown", 6, 1.0)
		_set_job({})
		return
	if not job.has("dest") or _go(job.dest, false) != 0:
		var t = tile() + Vector2i(w.rng.randi_range(-10, 10), w.rng.randi_range(-10, 10))
		job.dest = t if w.walkable(t) else w.camp
		path = []

# ---------------------------------------------------------------- damage
func take_hit(amount: float, attacker, cause := "") -> void:
	if not alive or away_until > 0:
		return
	if perk() == "ward":
		amount *= 0.75
	if perk() == "luck" and w.rng.randf() < 0.18:
		return
	hp -= amount
	hit_flash = 6
	if sleeping and attacker != null:
		sleeping = false
		_set_job({"t": "fight", "e": attacker})
	if hp <= 0:
		if perk() == "unbroken" and not used_unbroken:
			used_unbroken = true
			hp = 1.0
			w.log_event("%s refuses to fall. Their Unbroken Aspect holds them up." % name, "rise", self)
			remember("Refused to die.")
			return
		alive = false
		w.pawn_died(self, attacker, cause)
