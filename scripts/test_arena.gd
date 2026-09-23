extends SceneTree

const ArenaMatch = preload("res://scripts/arena_match.gd")
const CpuPlanner = preload("res://scripts/cpu_planner.gd")

var passed := 0
var failed := 0


func _init() -> void:
	_run()
	print("Tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _run() -> void:
	_test_start_positions()
	_test_pass_stays_put()
	_test_wall_blocks_move()
	_test_simple_move()
	_test_push()
	_test_chain_push()
	_test_push_wall_fails_entire_chain()
	_test_shuriken_hit_and_whiff()
	_test_diagonal_shuriken()
	_test_punch_range()
	_test_speed_order()
	_test_lower_priority_can_push_after()
	_test_priority_rotates_after_round()
	_test_mutual_ko_same_tier()
	_test_dead_skip_later_slots()
	_test_win_last_player()
	_test_step_through_matches_batch()
	_test_declare_preview_chains_moves()
	_test_declare_follows_priority()
	_test_once_per_round_limit()
	_test_xp_and_level_up()
	_test_heal()
	_test_flying_kick()
	_test_frost_ring()
	_test_fireball_splash()
	_test_windwall_reflects_projectile()
	_test_cpu_ignores_hidden_programs()
	_test_cpu_pokes_when_low_and_safe()
	_test_cpu_heals_when_threatened_and_low()
	_test_cpu_retreats_when_adjacent_and_low()
	_test_cpu_takes_clear_shuriken()
	_test_cpu_frost_on_cluster()
	_test_cpu_closes_distance()
	_test_cpu_edge_does_not_walk_into_wall()
	_test_cpu_predictive_aim()
	_test_cpu_projects_own_moves()
	_test_cpu_stand_when_retreat_loops()
	_test_cpu_never_idles()


func expect(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", msg)


func prog(spec: String) -> Array:
	var actions: Array = []
	for part in spec.split(","):
		var bits := part.strip_edges().split(" ")
		var kind := ArenaMatch.ActionKind.MOVE
		match bits[0]:
			"M":
				kind = ArenaMatch.ActionKind.MOVE
			"S":
				kind = ArenaMatch.ActionKind.SHURIKEN
			"P":
				kind = ArenaMatch.ActionKind.PUNCH
			"H":
				kind = ArenaMatch.ActionKind.HEAL
			"K":
				kind = ArenaMatch.ActionKind.FLYING_KICK
			"R":
				kind = ArenaMatch.ActionKind.FROST_RING
			"F":
				kind = ArenaMatch.ActionKind.FIREBALL
			"W":
				kind = ArenaMatch.ActionKind.WINDWALL
			_:
				push_error("bad kind")
		var dir := Vector2i.ZERO
		if bits.size() > 1:
			dir = ArenaMatch.parse_dir(bits[1])
		actions.append(ArenaMatch.make_action(kind, dir))
	return actions


func idle() -> Array:
	return [ArenaMatch.make_pass()]


func match_with(programs: Dictionary) -> ArenaMatch:
	var m := ArenaMatch.new()
	m.play_programmed_round(programs)
	return m


func filled(p0: String, p1: String = "", p2: String = "", p3: String = "") -> Dictionary:
	return {
		0: prog(p0) if p0 != "" else idle(),
		1: prog(p1) if p1 != "" else idle(),
		2: prog(p2) if p2 != "" else idle(),
		3: prog(p3) if p3 != "" else idle(),
	}


func _test_start_positions() -> void:
	var m := ArenaMatch.new()
	expect(m.positions[0] == Vector2i(0, 4), "P1 starts A5")
	expect(m.positions[1] == Vector2i(1, 0), "P2 starts B1")
	expect(m.positions[2] == Vector2i(4, 5), "P3 starts E6")
	expect(m.positions[3] == Vector2i(5, 1), "P4 starts F2")
	expect(ArenaMatch.tile_name(m.positions[0]) == "A5", "tile name A5")


func _test_pass_stays_put() -> void:
	var m := ArenaMatch.new()
	var start: Vector2i = m.positions[0]
	m.play_programmed_round(filled("M"))
	expect(m.positions[0] == start, "pass / stay does not move")
	expect(m.round_index == 2, "cleanup runs after a single-action turn")


func _test_wall_blocks_move() -> void:
	var m := ArenaMatch.new()
	for _i in 3:
		m.play_programmed_round(filled("M N"))
	# P1 A5: N three turns -> A4, A3, A2
	expect(m.positions[0] == Vector2i(0, 1), "P1 walked north to A2")
	m = ArenaMatch.new()
	m.positions[1] = Vector2i(1, 0)
	m.play_programmed_round(filled("M", "M N"))
	expect(m.positions[1] == Vector2i(1, 0), "P2 north from B1 is wall, stays")


func _test_simple_move() -> void:
	var m := match_with(filled("M E"))
	expect(m.positions[0] == Vector2i(1, 4), "P1 A5 east to B5")


func _test_push() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E"))
	expect(m.positions[0] == Vector2i(2, 2), "mover takes C3")
	expect(m.positions[1] == Vector2i(3, 2), "occupant pushed to D3")


func _test_chain_push() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(1, 2) # B3
	m.positions[2] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E"))
	expect(m.positions[0] == Vector2i(1, 2), "P1 to B3")
	expect(m.positions[1] == Vector2i(2, 2), "P2 to C3")
	expect(m.positions[2] == Vector2i(3, 2), "P3 to D3")


func _test_push_wall_fails_entire_chain() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(3, 2) # D3
	m.positions[1] = Vector2i(4, 2) # E3
	m.positions[2] = Vector2i(5, 2) # F3 against east wall
	m.play_programmed_round(filled("M E"))
	expect(m.positions[0] == Vector2i(3, 2), "chain fail mover stays")
	expect(m.positions[1] == Vector2i(4, 2), "chain fail mid stays")
	expect(m.positions[2] == Vector2i(5, 2), "chain fail end stays")


func _test_shuriken_hit_and_whiff() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.play_programmed_round(filled("S E", "S W"))
	expect(m.hp[1] == 18, "P2 took shuriken 2")
	expect(m.hp[0] == 18, "P1 took return shuriken 2")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 5)
	m.play_programmed_round(filled("S N"))
	expect(m.hp[1] == 20 and m.hp[2] == 20 and m.hp[3] == 20, "north from A6 whiffs others")


func _test_diagonal_shuriken() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(2, 3) # C4
	m.positions[1] = Vector2i(3, 2) # D3  (NE of C4)
	m.play_programmed_round(filled("S NE"))
	expect(m.hp[1] == 18, "diagonal NE from C4 hits D3")


func _test_punch_range() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(2, 2) # two tiles east — punch should whiff
	m.play_programmed_round(filled("P E"))
	expect(m.hp[1] == 20, "punch range 1 whiffs at distance 2")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E"))
	expect(m.hp[1] == 16, "adjacent punch deals 4")


func _test_speed_order() -> void:
	# Same slot: P1 steps north off the rank, P2 throws west along that rank.
	# Instant must resolve first so the shuriken whiffs.
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(3, 2) # D3
	m.play_programmed_round(filled("M N", "S W"))
	expect(m.positions[0] == Vector2i(1, 1), "P1 moved to B2")
	expect(m.hp[0] == 20, "shuriken resolved after move and missed")


func _test_lower_priority_can_push_after() -> void:
	# P1 (higher) moves east into empty. P2 later moves west onto P1 and pushes.
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(4, 2) # E3
	m.priority = [0, 1, 2, 3]
	m.play_programmed_round(filled("M E", "M W"))
	# P1 first: C3 -> D3 empty.
	# P2: E3 west onto D3, push P1 west to C3, P2 takes D3.
	expect(m.positions[0] == Vector2i(2, 2), "P1 pushed back to C3")
	expect(m.positions[1] == Vector2i(3, 2), "P2 occupies D3")


func _test_priority_rotates_after_round() -> void:
	var m := match_with(filled("S N"))
	expect(m.priority[0] == 1, "priority rotated to P2 first")
	expect(m.priority[3] == 0, "P1 now last")


func _test_mutual_ko_same_tier() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 4
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E", "P W"))
	expect(not m.alive[0] and not m.alive[1], "both KO in same punch step")
	expect(m.alive[2] and m.alive[3], "others still up")


func _test_dead_skip_later_slots() -> void:
	var m := ArenaMatch.new()
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E", "S W"))
	expect(not m.alive[1], "P2 died this turn")
	expect(m.hp[0] == 18, "P2 Shuriken (Normal) hit before the Punch (Slow)")


func _test_win_last_player() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 4
	m.hp[1] = 4
	m.hp[2] = 4
	m.positions[0] = Vector2i(2, 2)
	m.positions[1] = Vector2i(3, 2)
	m.positions[2] = Vector2i(2, 3)
	m.positions[3] = Vector2i(5, 5)
	m.play_programmed_round(filled("P E", "P W", "P N"))
	expect(m.alive[2] and m.alive[3], "P3 and P4 remain")
	expect(m.phase != ArenaMatch.Phase.MATCH_OVER, "match continues with 2+")
	m.play_programmed_round(filled("M"))
	m.play_programmed_round(filled("M"))
	m.hp[2] = 4
	m.hp[3] = 4
	m.positions[2] = Vector2i(4, 5)
	m.positions[3] = Vector2i(5, 5)
	m.play_programmed_round({2: prog("P E"), 3: prog("P W")})
	expect(m.phase == ArenaMatch.Phase.MATCH_OVER, "match over after last two KO")
	expect(m.winners.is_empty(), "shared final KO is a draw")


func _test_step_through_matches_batch() -> void:
	var programs := filled("M E", "M W", "M N", "M S")
	var batch := ArenaMatch.new()
	batch.play_programmed_round(programs)
	var stepped := ArenaMatch.new()
	stepped.programs.clear()
	stepped.phase = ArenaMatch.Phase.DECLARE
	for id in programs.keys():
		var err := stepped.submit_program(int(id), programs[id])
		expect(err == "", "submit %s" % str(id))
	stepped.begin_reveal()
	var n := 0
	while stepped.phase == ArenaMatch.Phase.REVEAL or stepped.phase == ArenaMatch.Phase.RESOLVING:
		stepped.resolve_next_action()
		n += 1
		if n > 200:
			expect(false, "step-through did not finish")
			return
	expect(stepped.hp == batch.hp, "step HP matches batch")
	expect(stepped.positions == batch.positions, "step positions match batch")
	expect(stepped.alive == batch.alive, "step alive matches batch")
	expect(stepped.priority == batch.priority, "step priority matches batch")
	expect(n > 1, "stepped one action at a time")


func _test_declare_preview_chains_moves() -> void:
	var m := ArenaMatch.new()
	var slots: Array = [ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_E)]
	var preview: Dictionary = m.declare_preview(0, slots)
	expect(preview.plan_origin == Vector2i(1, 4), "single Move east ghosts to B5")
	expect(preview.steps.size() == 1, "one declared action, one ghost")
	expect(preview.steps[0].to == Vector2i(1, 4), "ghost lands on B5")
	slots[0] = {}
	preview = m.declare_preview(0, slots)
	expect(preview.plan_origin == Vector2i(0, 4), "clearing the action resets origin to A5")


func _test_declare_follows_priority() -> void:
	var m := match_with(filled("M N"))
	expect(m.priority[0] == 1, "P2 is top priority after turn 1")
	var order: Array[int] = []
	for id in m.priority:
		if m.alive[id]:
			order.append(id)
	expect(order[0] == 1, "first declarer in pass-and-play is top priority")


func _test_once_per_round_limit() -> void:
	var m := ArenaMatch.new()
	var err := m.submit_program(0, prog("S N"))
	expect(err == "", "Shuriken is legal on turn 1")
	m.play_programmed_round({0: prog("S N"), 1: idle(), 2: idle(), 3: idle()})
	err = m.submit_program(0, prog("S N"))
	expect(err != "", "Shuriken rejected while still on cooldown")
	m.play_programmed_round(filled("M"))
	m.play_programmed_round(filled("M"))
	err = m.submit_program(0, prog("S N"))
	expect(err == "", "Shuriken available after 3 turns")
	err = m.submit_program(0, prog("M N"))
	expect(err == "", "Move is never on cooldown")


func _test_xp_and_level_up() -> void:
	var m := match_with(filled("M N"))
	expect(m.xp[0] == 1, "alive-only turn is 1 XP")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E"))
	expect(m.xp[1] == 2, "damage bonus stacks on base XP")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E"))
	expect(m.xp[0] == 2, "center occupancy bonus stacks on base XP")
	m = ArenaMatch.new()
	m.xp[0] = 14
	m.rng.seed = 1
	m.play_programmed_round(filled("M N"))
	expect(m.xp[0] == 15, "XP is cumulative through the 15 threshold")
	expect(m.owned[0].size() == 4, "crossing 15 XP grants one acquired ability")
	expect(m.phase == ArenaMatch.Phase.DECLARE, "tests auto-resolve the level-up pick")


func _test_heal() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 10
	m.play_programmed_round(filled("H"))
	expect(m.hp[0] == 12, "Heal restores 2")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 19
	m.play_programmed_round(filled("H"))
	expect(m.hp[0] == 20, "Heal cannot exceed 20")


func _test_flying_kick() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("K E"))
	expect(m.positions[0] == Vector2i(1, 2), "kick steps to B3")
	expect(m.hp[1] == 18, "kick deals 2 to the tile beyond the landing")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(0, 0) # A1
	m.positions[1] = Vector2i(0, 1) # A2 south of wall-fail north
	m.play_programmed_round(filled("K N"))
	expect(m.positions[0] == Vector2i(0, 0), "wall-fail kick does not move")
	expect(m.hp[1] == 20, "nothing north of A1 to hit")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(4, 2) # E3
	m.positions[1] = Vector2i(5, 2) # F3 against east wall
	m.play_programmed_round(filled("K E"))
	expect(m.positions[0] == Vector2i(4, 2), "blocked push-kick stays put")
	expect(m.hp[1] == 18, "wall-fail kick still hits the adjacent occupant")


func _test_frost_ring() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(2, 3) # C4
	m.positions[2] = Vector2i(3, 2) # D3
	m.positions[3] = Vector2i(5, 5) # F6 out of ring
	m.play_programmed_round(filled("R"))
	expect(m.hp[1] == 19, "frost hits adjacent C4")
	expect(m.hp[2] == 19, "frost hits adjacent D3")
	expect(m.hp[3] == 20, "frost does not hit F6")


func _test_fireball_splash() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FIREBALL)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.positions[2] = Vector2i(4, 1) # E2 adjacent to stop
	m.play_programmed_round(filled("F E"))
	expect(m.hp[1] == 17, "fireball direct hit 3")
	expect(m.hp[2] == 19, "fireball splash 1 on neighbor of impact")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FIREBALL)
	m.positions[0] = Vector2i(5, 2) # F3
	m.positions[1] = Vector2i(5, 1) # F2
	m.play_programmed_round(filled("F E"))
	expect(m.hp[1] == 19, "wall-whiff still splashes tiles adjacent to the wall")


func _test_windwall_reflects_projectile() -> void:
	var m := ArenaMatch.new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.play_programmed_round(filled("S E", "W W"))
	expect(m.hp[1] == 20, "Windwall blocks the incoming Shuriken")
	expect(m.hp[0] == 18, "reflected Shuriken travels west and hits the thrower")
	m = ArenaMatch.new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2)
	m.positions[1] = Vector2i(2, 3)
	m.play_programmed_round(filled("R", "W N"))
	expect(m.hp[1] == 19, "Windwall does not block Frost Ring")


func _cpu_plan(m: ArenaMatch, id: int) -> Array:
	return CpuPlanner.new().plan_program(m, id)


func _plan_has(plan: Array, kind: ArenaMatch.ActionKind, dir: Vector2i = Vector2i(-99, -99)) -> bool:
	for a in plan:
		if a.kind != kind:
			continue
		if dir.x == -99 or a.dir == dir:
			return true
	return false


func _test_cpu_ignores_hidden_programs() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3 in a straight east line
	# Hidden bait: P2's unrevealed plan leaves the line. A cheating CPU would not throw east.
	m.programs[1] = prog("M N")
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.DIR_E), "CPU throws at the visible line, not at P2's hidden north moves")
	expect(m.programs[1][0].kind == ArenaMatch.ActionKind.MOVE, "planner must not rewrite other programs")


func _test_cpu_pokes_when_low_and_safe() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 5
	m.positions[0] = Vector2i(0, 0)
	m.positions[1] = Vector2i(5, 5)
	m.positions[2] = Vector2i(5, 4)
	m.positions[3] = Vector2i(4, 5)
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.SHURIKEN), "low HP at safe range still takes a ranged poke")
	expect(not _plan_has(plan, ArenaMatch.ActionKind.HEAL), "Heal is for threatened slots, not a blanket low-HP mode")


func _test_cpu_heals_when_threatened_and_low() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 5
	m.positions[0] = Vector2i(2, 2)
	m.positions[1] = Vector2i(3, 2)
	m.alive[2] = false
	m.alive[3] = false
	var plan: Array = _cpu_plan(m, 0)
	expect(plan[0].kind == ArenaMatch.ActionKind.HEAL, "low HP in melee with no kill shot prefers Heal")


func _test_cpu_retreats_when_adjacent_and_low() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 5
	m.positions[0] = Vector2i(2, 2) # C3 — room to step west
	m.positions[1] = Vector2i(3, 2) # D3
	m.alive[2] = false
	m.alive[3] = false
	var plan: Array = _cpu_plan(m, 0)
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "low HP next to a foe with no Heal: move away")
	expect(plan[0].dir == ArenaMatch.DIR_W, "retreat steps off the threat, not onto it")


func _test_cpu_takes_clear_shuriken() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(4, 2)
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.DIR_E), "clear east line is a Shuriken")


func _test_cpu_frost_on_cluster() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(2, 3) # C4
	m.positions[2] = Vector2i(3, 2) # D3
	m.positions[3] = Vector2i(5, 5)
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.FROST_RING), "two adjacent foes prefer Frost Ring")


func _test_cpu_closes_distance() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 4) # A5
	m.positions[1] = Vector2i(5, 0) # F1 — not on a ray
	m.alive[2] = false
	m.alive[3] = false
	var plan: Array = _cpu_plan(m, 0)
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "no attack line defaults to a Move")
	var dest: Vector2i = m.positions[0] + plan[0].dir
	expect(
		ArenaMatch.chebyshev(dest, m.positions[1]) < ArenaMatch.chebyshev(m.positions[0], m.positions[1]),
		"approach Move closes on the nearest foe"
	)


func _test_cpu_predictive_aim() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(3, 1) # D2 — not currently on a ray
	m.last_step_dir[1] = ArenaMatch.DIR_S # would step to D3, on the east line
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.DIR_E), "one-tile last-move extrapolation aims the throw")


func _test_cpu_projects_own_moves() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(2, 3) # C4 — not on a cardinal/diagonal ray
	var plan: Array = _cpu_plan(m, 0)
	expect(plan.size() == 1, "CPU commits one action per turn")
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "no current attack line: step in")
	expect(plan[0].dir == ArenaMatch.DIR_E, "closes east toward C4")


func _test_cpu_stand_when_retreat_loops() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 5
	m.positions[0] = Vector2i(0, 0) # A1 corner
	m.positions[1] = Vector2i(1, 0) # B1
	m.alive[2] = false
	m.alive[3] = false
	m.pos_history[0] = [Vector2i(0, 1), Vector2i(0, 0)]
	m.last_step_dir[0] = ArenaMatch.DIR_N
	var plan: Array = _cpu_plan(m, 0)
	expect(not ArenaMatch.is_pass(plan[0]), "cornered CPU still declares an action")
	expect(
		plan[0].kind == ArenaMatch.ActionKind.PUNCH or plan[0].kind == ArenaMatch.ActionKind.SHURIKEN,
		"a valid attack from A1 into B1 beats passing or bouncing"
	)


func _test_cpu_never_idles() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 5
	m.positions[0] = Vector2i(0, 0) # A1 corner
	m.positions[1] = Vector2i(1, 0) # B1
	m.alive[2] = false
	m.alive[3] = false
	m.pos_history[0] = [Vector2i(0, 1), Vector2i(0, 0)]
	m.last_step_dir[0] = ArenaMatch.DIR_N
	m.last_used_turn[0][ArenaMatch.ActionKind.SHURIKEN] = m.round_index
	m.last_used_turn[0][ArenaMatch.ActionKind.PUNCH] = m.round_index
	var plan: Array = _cpu_plan(m, 0)
	expect(plan.size() == 1, "CPU always queues one action")
	expect(plan[0].has("kind"), "CPU action has a kind")
	expect(not ArenaMatch.is_pass(plan[0]), "CPU never submits a pass / empty turn")
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "with attacks on cooldown, CPU still Moves")
	expect(plan[0].dir != Vector2i.ZERO, "the Move has a direction even if it will fail into a wall")
	expect(
		ArenaMatch.in_bounds(m.positions[0] + plan[0].dir),
		"idle fallback still steps onto the board, not into a wall"
	)


func _test_cpu_edge_does_not_walk_into_wall() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(5, 2) # F3 — eastern wall
	m.positions[1] = Vector2i(2, 3) # C4, not on a ray from F3
	m.positions[2] = Vector2i(0, 0) # A1
	m.positions[3] = Vector2i(1, 5) # B6 — not on a ray from F3
	var plan: Array = _cpu_plan(m, 0)
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "no line from F3: CPU Moves")
	expect(plan[0].dir != ArenaMatch.DIR_E, "nothing is east of F; do not walk into the wall")
	expect(ArenaMatch.in_bounds(m.positions[0] + plan[0].dir), "approach stays on the board")
	var dest: Vector2i = m.positions[0] + plan[0].dir
	expect(dest.x <= m.positions[0].x, "horizontal sign toward C/D and western foes is west, not east")
	m = ArenaMatch.new()
	m.hp[0] = 5
	m.positions[0] = Vector2i(5, 2) # F3
	m.positions[1] = Vector2i(3, 2) # D3 — threat from the west
	m.alive[2] = false
	m.alive[3] = false
	m.last_used_turn[0][ArenaMatch.ActionKind.SHURIKEN] = m.round_index
	m.last_used_turn[0][ArenaMatch.ActionKind.PUNCH] = m.round_index
	plan = _cpu_plan(m, 0)
	expect(not ArenaMatch.is_pass(plan[0]), "low-HP edge CPU still acts")
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "attacks on cooldown: Move")
	expect(plan[0].dir != ArenaMatch.DIR_E, "flee/stand must not treat off-board east as farther")
	expect(ArenaMatch.in_bounds(m.positions[0] + plan[0].dir), "least-bad Move is still on the board")



