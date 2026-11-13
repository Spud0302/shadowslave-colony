extends RefCounted
## A Nightmare Creature: a wandering beast, a raider, or the Citadel's Guardian.

const D = preload("res://scripts/data.gd")

var w
var id = 0
var kind = ""
var name = ""
var rank_name = ""
var hp = 0.0
var max_hp = 0.0
var dmg = 0.0
var speed = 0.1
var size = 0.6
var col = Color.WHITE
var pos = Vector2()
var path: Array = []
var raider = false
var guardian = false
var aggro = null          # pawn it is chasing
var cd = 0
var repath = 0
var alive = true
var wander_t = 0
var home = Vector2()
var hit_flash = 0

func setup(world, k: String, p: Vector2, is_raider: bool) -> void:
	w = world
	kind = k
	var d: Dictionary = D.CREATURES[k]
	name = d.name
	rank_name = d.rank
	max_hp = d.hp * world.creature_scale()
	hp = max_hp
	dmg = d.dmg * world.creature_scale()
	speed = d.speed
	size = d.size
	col = Color(d.col)
	pos = p
	home = p
	raider = is_raider
	guardian = k == "tyrant"
	if guardian:
		max_hp = d.hp
		hp = max_hp
		dmg = d.dmg

func tile() -> Vector2i:
	return Vector2i(int(pos.x), int(pos.y))

func step() -> void:
	if not alive:
		return
	if cd > 0:
		cd -= 1
	if hit_flash > 0:
		hit_flash -= 1
	if guardian:
		_guardian_step()
		return
	# pick a target
	if aggro != null and (not aggro.alive or aggro.away_until > 0 or aggro.pos.distance_to(pos) > 14.0):
		aggro = null
	if raider and aggro == null and w.tick % 10 == id % 10:
		aggro = w.nearest_pawn(pos, 9.0)
	if not raider and aggro == null and hp < max_hp * 0.3:
		_flee()
		return
	if aggro != null:
		var dd = pos.distance_to(aggro.pos)
		if dd < 1.4:
			if cd <= 0:
				aggro.take_hit(dmg * w.rng.randf_range(0.7, 1.3), self)
				cd = 34
			return
		repath -= 1
		if repath <= 0 or path.is_empty():
			var p = w.find_path(tile(), aggro.tile(), false)
			path = p if p != null else []
			repath = 18
		_move()
		return
	if raider:
		# march on the camp, breaking walls in the way
		repath -= 1
		if repath <= 0 or path.is_empty():
			var p = w.find_path(tile(), w.camp, false)
			repath = 40
			if p == null:
				path = []
				_bash_wall()
			else:
				path = p
		_move()
		return
	# wandering beast
	wander_t -= 1
	if path.is_empty() and wander_t <= 0:
		var t = Vector2i(int(home.x) + w.rng.randi_range(-8, 8), int(home.y) + w.rng.randi_range(-8, 8))
		if w.walkable(t) and t.distance_to(w.camp) > 12:
			var p = w.find_path(tile(), t, false)
			if p != null:
				path = p
		wander_t = w.rng.randi_range(60, 240)
	_move()

func _guardian_step() -> void:
	if hp < max_hp and w.tick % 6 == 0:
		hp = min(max_hp, hp + 1.0)
	var target = null
	var best = 99.0
	for p in w.pawns:
		if p.alive and p.away_until <= 0 and w.keep_rect.has_point(p.tile()):
			var d: float = p.pos.distance_to(pos)
			if d < best:
				best = d
				target = p
	if target == null:
		# drift back to the throne
		var hv = home - pos
		if hv.length() > 0.2:
			pos += hv.normalized() * speed
		return
	if best < 1.9:
		if cd <= 0:
			target.take_hit(dmg * w.rng.randf_range(0.8, 1.25), self)
			cd = 40
	else:
		var v: Vector2 = target.pos - pos
		pos += v.normalized() * speed

func _move() -> void:
	if path.is_empty():
		return
	var nxt: Vector2i = path[0]
	if w.is_solid(nxt):
		path = []
		return
	var target = Vector2(nxt.x + 0.5, nxt.y + 0.5)
	var v = target - pos
	var s = speed * (0.6 if w.is_night() == false and raider else 1.0)
	if v.length() <= s:
		pos = target
		path.pop_front()
	else:
		pos += v.normalized() * s

func _flee() -> void:
	if path.is_empty():
		var away = (pos - Vector2(w.camp)).normalized() * 10.0
		var t = Vector2i(clampi(int(pos.x + away.x), 1, D.W - 2), clampi(int(pos.y + away.y), 1, D.H - 2))
		if w.walkable(t):
			var p = w.find_path(tile(), t, false)
			if p != null:
				path = p
	_move()

func _bash_wall() -> void:
	# No way in: attack the nearest built wall.
	var best = null
	var bd = 99.0
	for c in w.buildings:
		var b = w.buildings[c]
		if b.type == "wall" or b.type == "swall":
			var d: float = Vector2(c).distance_to(pos)
			if d < bd:
				bd = d
				best = c
	if best == null:
		return
	if bd < 1.6:
		if cd <= 0:
			w.damage_building(best, dmg)
			cd = 34
	else:
		var p = w.find_path(tile(), best, true)
		if p != null:
			path = p

func take_hit(amount: float, attacker) -> void:
	if not alive:
		return
	hp -= amount
	hit_flash = 6
	if aggro == null and attacker != null:
		aggro = attacker
	if hp <= 0:
		alive = false
		w.creature_died(self, attacker)
