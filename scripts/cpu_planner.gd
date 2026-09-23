class_name CpuPlanner
extends RefCounted

## Tier 2 heuristic. Plans from public board state + own draft projection only.
## Never reads other players' unrevealed programs.

const LOW_HP := 6

var game: ArenaMatch
var cpu_id: int = 0
var used: Dictionary = {}
var projected_hp: int = 0
var rng := RandomNumberGenerator.new()
var plan_visited: Array[Vector2i] = []


func plan_program(match_ref: ArenaMatch, player_id: int) -> Array:
	game = match_ref
	cpu_id = player_id
	used.clear()
	plan_visited.clear()
	projected_hp = game.hp[cpu_id]
	rng.seed = match_ref.rng.randi()
	var slots: Array = [{}, {}, {}]
	for i in ArenaMatch.SLOTS:
		var action := _pick_slot(slots)
		slots[i] = action
		_mark_used(action)
		if action.kind == ArenaMatch.ActionKind.HEAL:
			projected_hp = mini(ArenaMatch.START_HP, projected_hp + ArenaMatch.HEAL_AMOUNT)
	return slots


func _mark_used(action: Dictionary) -> void:
	var kind: ArenaMatch.ActionKind = action.kind
	if not ArenaMatch.is_unlimited(kind):
		used[kind] = true


func _can(kind: ArenaMatch.ActionKind) -> bool:
	if not game.owns(cpu_id, kind):
		return false
	if ArenaMatch.is_unlimited(kind):
		return true
	return not used.has(kind)


func _origin(slots: Array) -> Vector2i:
	return game.declare_preview(cpu_id, slots).plan_origin


func _pick_slot(slots: Array) -> Dictionary:
	var origin: Vector2i = _origin(slots)
	plan_visited.append(origin)
	var low := projected_hp <= LOW_HP
	var threatened := _immediate_threat(origin)
	if low and threatened:
		var kill := _finishing_attack(origin)
		if not kill.is_empty():
			return kill
		if _can(ArenaMatch.ActionKind.HEAL):
			return ArenaMatch.make_action(ArenaMatch.ActionKind.HEAL)
		var flee := _move_away(origin)
		if not flee.is_empty() and _retreat_is_productive(origin, origin + flee.dir):
			return flee
		var stand := _make_stand(origin)
		if not stand.is_empty():
			return stand
	if low and not threatened:
		var poke := _best_ranged_attack(origin)
		if poke.is_empty():
			poke = _best_predictive_shot(origin)
		if not poke.is_empty():
			return poke
		var shift := _reposition_safe(origin)
		if not shift.is_empty():
			return shift
		var stand_safe := _make_stand(origin)
		if not stand_safe.is_empty():
			return stand_safe
	var cluster := _best_cluster(origin)
	if not cluster.is_empty():
		return cluster
	var attack := _best_direct_attack(origin)
	if not attack.is_empty():
		return attack
	var pred := _best_predictive_shot(origin)
	if not pred.is_empty():
		return pred
	var close := _move_toward_fight(origin)
	if not close.is_empty():
		return close
	return _fallback_move(origin)


func _living_foes() -> Array[int]:
	var ids: Array[int] = []
	for id in game.living_ids():
		if id != cpu_id:
			ids.append(id)
	return ids


func _adjacent_threat(origin: Vector2i) -> bool:
	return _immediate_threat(origin)


func _immediate_threat(origin: Vector2i) -> bool:
	for id in _living_foes():
		var there: Vector2i = game.positions[id]
		if ArenaMatch.chebyshev(origin, there) == 1:
			return true
		for dir in ArenaMatch.ORTHOGONAL:
			var step: Vector2i = there + dir
			if ArenaMatch.in_bounds(step) and ArenaMatch.chebyshev(origin, step) == 1:
				return true
		var continued: Vector2i = there + game.last_step_dir[id]
		if game.last_step_dir[id] != Vector2i.ZERO and ArenaMatch.in_bounds(continued):
			if ArenaMatch.chebyshev(origin, continued) == 1:
				return true
	return false


func _foe_count_adjacent(origin: Vector2i) -> int:
	var n := 0
	for id in _living_foes():
		if ArenaMatch.chebyshev(origin, game.positions[id]) == 1:
			n += 1
	return n


func _splash_count(impact: Vector2i, skip_id: int = -1) -> int:
	var n := 0
	for id in _living_foes():
		if id == skip_id:
			continue
		if ArenaMatch.chebyshev(game.positions[id], impact) <= 1:
			n += 1
	return n


func _best_cluster(origin: Vector2i) -> Dictionary:
	var frost_hits := _foe_count_adjacent(origin)
	var frost_ok := _can(ArenaMatch.ActionKind.FROST_RING) and frost_hits >= 2
	var fire_ok := _can(ArenaMatch.ActionKind.FIREBALL)
	var best_dir := Vector2i.ZERO
	var best_score := 0
	if fire_ok:
		for dir in ArenaMatch.ALL_DIRS:
			var impact := _projectile_impact(origin, dir)
			var hit: int = impact.target
			var splash := _splash_count(impact.stop, hit)
			var total := splash + (1 if hit >= 0 and hit != cpu_id else 0)
			if total < 2:
				continue
			var score := 0
			if hit >= 0:
				score += ArenaMatch.FIREBALL_DAMAGE
			score += splash * ArenaMatch.FIREBALL_SPLASH
			if score > best_score or (score == best_score and score > 0 and rng.randf() < 0.5):
				best_score = score
				best_dir = dir
	if frost_ok:
		var frost_score := frost_hits * ArenaMatch.FROST_DAMAGE
		if frost_score > best_score or (best_dir == Vector2i.ZERO):
			return ArenaMatch.make_action(ArenaMatch.ActionKind.FROST_RING)
		if frost_score == best_score and rng.randf() < 0.35:
			return ArenaMatch.make_action(ArenaMatch.ActionKind.FROST_RING)
	if best_dir != Vector2i.ZERO and best_score > 0:
		return ArenaMatch.make_action(ArenaMatch.ActionKind.FIREBALL, best_dir)
	return {}


func _projectile_impact(origin: Vector2i, dir: Vector2i) -> Dictionary:
	var traced: Dictionary = game.preview_ray(origin, dir, ArenaMatch.COLS + ArenaMatch.ROWS, cpu_id)
	var tiles: Array = traced.tiles
	var target: int = traced.target
	var stop: Vector2i = origin
	if tiles.size() > 0:
		stop = tiles[tiles.size() - 1]
	if target < 0:
		var wall: Vector2i = stop + dir if tiles.size() > 0 else origin + dir
		if not ArenaMatch.in_bounds(wall) and tiles.size() > 0:
			stop = wall
	return {"target": target, "stop": stop, "tiles": tiles}


func _best_ranged_attack(origin: Vector2i) -> Dictionary:
	var options: Array = []
	for id in _living_foes():
		var there: Vector2i = game.positions[id]
		var d: Vector2i = ArenaMatch.line_dir(origin, there)
		if d == Vector2i.ZERO:
			continue
		var traced: Dictionary = game.preview_ray(origin, d, ArenaMatch.COLS + ArenaMatch.ROWS, cpu_id)
		if traced.target != id:
			continue
		if _can(ArenaMatch.ActionKind.FIREBALL):
			options.append({"action": ArenaMatch.make_action(ArenaMatch.ActionKind.FIREBALL, d), "rank": 4})
		if _can(ArenaMatch.ActionKind.SHURIKEN):
			options.append({"action": ArenaMatch.make_action(ArenaMatch.ActionKind.SHURIKEN, d), "rank": 1})
	return _pick_ranked(options)


func _finishing_attack(origin: Vector2i) -> Dictionary:
	for id in _living_foes():
		var there: Vector2i = game.positions[id]
		var d: Vector2i = ArenaMatch.line_dir(origin, there)
		if d == Vector2i.ZERO:
			continue
		var dist := ArenaMatch.chebyshev(origin, there)
		var hp_left: int = game.hp[id]
		if dist == 1:
			if _can(ArenaMatch.ActionKind.PUNCH) and ArenaMatch.PUNCH_DAMAGE >= hp_left:
				return ArenaMatch.make_action(ArenaMatch.ActionKind.PUNCH, d)
			if _can(ArenaMatch.ActionKind.FLYING_KICK) and ArenaMatch.FLYING_KICK_DAMAGE >= hp_left:
				return ArenaMatch.make_action(ArenaMatch.ActionKind.FLYING_KICK, d)
		var traced: Dictionary = game.preview_ray(origin, d, ArenaMatch.COLS + ArenaMatch.ROWS, cpu_id)
		if traced.target != id:
			continue
		if _can(ArenaMatch.ActionKind.FIREBALL) and ArenaMatch.FIREBALL_DAMAGE >= hp_left:
			return ArenaMatch.make_action(ArenaMatch.ActionKind.FIREBALL, d)
		if _can(ArenaMatch.ActionKind.SHURIKEN) and ArenaMatch.SHURIKEN_DAMAGE >= hp_left:
			return ArenaMatch.make_action(ArenaMatch.ActionKind.SHURIKEN, d)
	return {}


func _pick_ranked(options: Array) -> Dictionary:
	if options.is_empty():
		return {}
	options.sort_custom(func(a, b): return int(a.rank) > int(b.rank))
	var top: int = options[0].rank
	var tied: Array = []
	for o in options:
		if o.rank == top:
			tied.append(o.action)
	return tied[rng.randi_range(0, tied.size() - 1)]


func _best_direct_attack(origin: Vector2i) -> Dictionary:
	var options: Array = []
	for id in _living_foes():
		var there: Vector2i = game.positions[id]
		var d: Vector2i = ArenaMatch.line_dir(origin, there)
		if d == Vector2i.ZERO:
			continue
		var dist := ArenaMatch.chebyshev(origin, there)
		if dist == 1:
			if _can(ArenaMatch.ActionKind.FLYING_KICK):
				options.append({"action": ArenaMatch.make_action(ArenaMatch.ActionKind.FLYING_KICK, d), "rank": 3})
			if _can(ArenaMatch.ActionKind.PUNCH):
				options.append({"action": ArenaMatch.make_action(ArenaMatch.ActionKind.PUNCH, d), "rank": 2})
		if dist >= 1:
			var traced: Dictionary = game.preview_ray(origin, d, ArenaMatch.COLS + ArenaMatch.ROWS, cpu_id)
			if traced.target != id:
				continue
			if _can(ArenaMatch.ActionKind.FIREBALL):
				options.append({"action": ArenaMatch.make_action(ArenaMatch.ActionKind.FIREBALL, d), "rank": 4})
			if _can(ArenaMatch.ActionKind.SHURIKEN):
				options.append({"action": ArenaMatch.make_action(ArenaMatch.ActionKind.SHURIKEN, d), "rank": 1})
	return _pick_ranked(options)


func _best_predictive_shot(origin: Vector2i) -> Dictionary:
	var ranged: Array = []
	if _can(ArenaMatch.ActionKind.FIREBALL):
		ranged.append(ArenaMatch.ActionKind.FIREBALL)
	if _can(ArenaMatch.ActionKind.SHURIKEN):
		ranged.append(ArenaMatch.ActionKind.SHURIKEN)
	if ranged.is_empty():
		return {}
	var shots: Array = []
	for id in _living_foes():
		var step: Vector2i = game.last_step_dir[id]
		if step == Vector2i.ZERO:
			continue
		var here: Vector2i = game.positions[id]
		var pred: Vector2i = here + step
		if not ArenaMatch.in_bounds(pred):
			continue
		if ArenaMatch.line_dir(origin, here) != Vector2i.ZERO:
			continue
		var d: Vector2i = ArenaMatch.line_dir(origin, pred)
		if d == Vector2i.ZERO:
			continue
		if not _ray_clear_to(origin, d, pred):
			continue
		var kind: ArenaMatch.ActionKind = ranged[0]
		shots.append(ArenaMatch.make_action(kind, d))
	if shots.is_empty():
		return {}
	return shots[rng.randi_range(0, shots.size() - 1)]


func _ray_clear_to(origin: Vector2i, dir: Vector2i, dest: Vector2i) -> bool:
	var cursor := origin
	for _i in ArenaMatch.COLS + ArenaMatch.ROWS:
		cursor += dir
		if cursor == dest:
			return ArenaMatch.in_bounds(dest)
		if not ArenaMatch.in_bounds(cursor):
			return false
		if game.player_at(cursor) >= 0:
			return false
	return false


func _move_toward_fight(origin: Vector2i) -> Dictionary:
	var foe := _nearest_foe(origin)
	if foe >= 0:
		var toward := _best_step(origin, game.positions[foe], false)
		if not toward.is_empty():
			var dest: Vector2i = origin + toward.dir
			if ArenaMatch.chebyshev(dest, game.positions[foe]) < ArenaMatch.chebyshev(origin, game.positions[foe]):
				return toward
	return _best_step(origin, _nearest_center(origin), false)


func _move_away(origin: Vector2i) -> Dictionary:
	var choices: Array[Vector2i] = []
	var best := -99999
	for dir in ArenaMatch.ORTHOGONAL:
		var dest: Vector2i = origin + dir
		if not _retreat_is_productive(origin, dest):
			continue
		var score := _clearance(dest) * 10 + _sum_foe_dist(dest)
		if score > best:
			best = score
			choices = [dir]
		elif score == best:
			choices.append(dir)
	if choices.is_empty():
		return {}
	return ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, choices[rng.randi_range(0, choices.size() - 1)])


func _retreat_is_productive(origin: Vector2i, dest: Vector2i) -> bool:
	if not ArenaMatch.in_bounds(dest):
		return false
	if dest in plan_visited:
		return false
	var hist: Array = game.pos_history[cpu_id] if cpu_id < game.pos_history.size() else []
	if dest in hist:
		return false
	var came: Vector2i = game.last_step_dir[cpu_id]
	if came != Vector2i.ZERO and dest == origin - came:
		return false
	if _clearance(dest) < _clearance(origin):
		return false
	if _clearance(dest) == _clearance(origin) and _sum_foe_dist(dest) <= _sum_foe_dist(origin):
		return false
	return true


func _reposition_safe(origin: Vector2i) -> Dictionary:
	var min_clear := mini(2, _clearance(origin))
	var foe := _nearest_foe(origin)
	var goal: Vector2i = game.positions[foe] if foe >= 0 else _nearest_center(origin)
	var choices: Array[Vector2i] = []
	var best := -99999
	for dir in ArenaMatch.ORTHOGONAL:
		var dest: Vector2i = origin + dir
		if not ArenaMatch.in_bounds(dest):
			continue
		if dest in plan_visited:
			continue
		if _clearance(dest) < min_clear:
			continue
		var score := _clearance(dest) * 8
		if ArenaMatch.line_dir(dest, goal) != Vector2i.ZERO:
			score += 12
		score += (ArenaMatch.chebyshev(origin, goal) - ArenaMatch.chebyshev(dest, goal)) * 4
		if ArenaMatch.is_center(dest):
			score += 2
		if score > best:
			best = score
			choices = [dir]
		elif score == best:
			choices.append(dir)
	if choices.is_empty():
		return {}
	return ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, choices[rng.randi_range(0, choices.size() - 1)])


func _make_stand(origin: Vector2i) -> Dictionary:
	var foe := _nearest_foe(origin)
	if _can(ArenaMatch.ActionKind.WINDWALL) and foe >= 0:
		var face := ArenaMatch.line_dir(origin, game.positions[foe])
		if face == Vector2i.ZERO:
			var d: Vector2i = game.positions[foe] - origin
			if absi(d.x) >= absi(d.y):
				face = Vector2i(signi(d.x), 0)
			else:
				face = Vector2i(0, signi(d.y))
		if face != Vector2i.ZERO:
			return ArenaMatch.make_action(ArenaMatch.ActionKind.WINDWALL, face)
	var hit := _best_direct_attack(origin)
	if not hit.is_empty():
		return hit
	if _can(ArenaMatch.ActionKind.HEAL):
		return ArenaMatch.make_action(ArenaMatch.ActionKind.HEAL)
	return {}


func _fallback_move(origin: Vector2i) -> Dictionary:
	var step := _best_step(origin, _nearest_center(origin), false)
	if not step.is_empty():
		return step
	for dir in ArenaMatch.ORTHOGONAL:
		if ArenaMatch.in_bounds(origin + dir):
			return ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, dir)
	return ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_N)


func _nearest_foe(origin: Vector2i) -> int:
	var best := -1
	var best_d := 99
	var best_hp := 999
	for id in _living_foes():
		var d := ArenaMatch.chebyshev(origin, game.positions[id])
		var h: int = game.hp[id]
		if d < best_d or (d == best_d and h < best_hp) or (d == best_d and h == best_hp and rng.randf() < 0.5):
			best_d = d
			best_hp = h
			best = id
	return best


func _nearest_center(origin: Vector2i) -> Vector2i:
	var best: Vector2i = ArenaMatch.CENTER_TILES[0]
	var best_d := 99
	for c in ArenaMatch.CENTER_TILES:
		var d := ArenaMatch.chebyshev(origin, c)
		if d < best_d:
			best_d = d
			best = c
	return best


func _best_step(origin: Vector2i, goal: Vector2i, flee: bool) -> Dictionary:
	var choices: Array[Vector2i] = []
	var best_score := -99999
	for dir in ArenaMatch.ORTHOGONAL:
		var dest: Vector2i = origin + dir
		if not ArenaMatch.in_bounds(dest):
			continue
		var score := 0
		if flee:
			score = _clearance(dest) * 10 + _sum_foe_dist(dest)
		else:
			var before := ArenaMatch.chebyshev(origin, goal)
			var after := ArenaMatch.chebyshev(dest, goal)
			score = (before - after) * 20
			if ArenaMatch.is_center(dest):
				score += 3
			score += rng.randi_range(0, 1)
		if score > best_score:
			best_score = score
			choices = [dir]
		elif score == best_score:
			choices.append(dir)
	if choices.is_empty():
		return {}
	if flee and best_score < _clearance(origin) * 10 + _sum_foe_dist(origin):
		# No improvement, still step a random legal way rather than pass.
		pass
	var dir: Vector2i = choices[rng.randi_range(0, choices.size() - 1)]
	return ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, dir)


func _clearance(pos: Vector2i) -> int:
	var m := 99
	for id in _living_foes():
		m = mini(m, ArenaMatch.chebyshev(pos, game.positions[id]))
	return 0 if m == 99 else m


func _sum_foe_dist(pos: Vector2i) -> int:
	var s := 0
	for id in _living_foes():
		s += ArenaMatch.chebyshev(pos, game.positions[id])
	return s


static func preferred_level_up(offers: Array) -> ArenaMatch.ActionKind:
	var order := [
		ArenaMatch.ActionKind.FIREBALL,
		ArenaMatch.ActionKind.FLYING_KICK,
		ArenaMatch.ActionKind.FROST_RING,
		ArenaMatch.ActionKind.WINDWALL,
		ArenaMatch.ActionKind.HEAL,
	]
	for kind in order:
		if kind in offers:
			return kind
	return offers[0]
