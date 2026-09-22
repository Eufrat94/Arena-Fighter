extends SceneTree

const ArenaMatch = preload("res://scripts/arena_match.gd")

var passed := 0
var failed := 0


func _init() -> void:
	_run()
	print("Tests: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _run() -> void:
	_test_start_positions()
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
	# Punch (slow, range 1), then N+S so the round nets no movement when both steps are free.
	return prog("P N,M N,M S")


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


func _test_wall_blocks_move() -> void:
	var m := match_with(filled("M N,M N,M N"))
	# P1 A5: N three times -> A4, A3, A2
	expect(m.positions[0] == Vector2i(0, 1), "P1 walked north to A2")
	m = ArenaMatch.new()
	m.positions[1] = Vector2i(1, 0)
	m.play_programmed_round(filled("S N,M S,M E", "M N,M N,M N"))
	expect(m.positions[1] == Vector2i(1, 0), "P2 north from B1 is wall, stays")


func _test_simple_move() -> void:
	var m := match_with(filled("M E,S N,P N"))
	expect(m.positions[0] == Vector2i(1, 4), "P1 A5 east to B5")


func _test_push() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E,S N,P N", "S N,M N,M S"))
	expect(m.positions[0] == Vector2i(2, 2), "mover takes C3")
	expect(m.positions[1] == Vector2i(3, 2), "occupant pushed to D3")


func _test_chain_push() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(1, 2) # B3
	m.positions[2] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E,S N,P N", "S N,M N,M S", "S N,M N,M S"))
	expect(m.positions[0] == Vector2i(1, 2), "P1 to B3")
	expect(m.positions[1] == Vector2i(2, 2), "P2 to C3")
	expect(m.positions[2] == Vector2i(3, 2), "P3 to D3")


func _test_push_wall_fails_entire_chain() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(3, 2) # D3
	m.positions[1] = Vector2i(4, 2) # E3
	m.positions[2] = Vector2i(5, 2) # F3 against east wall
	m.play_programmed_round(filled("M E,S N,P N", "S N,M N,M S", "S N,M N,M S"))
	expect(m.positions[0] == Vector2i(3, 2), "chain fail mover stays")
	expect(m.positions[1] == Vector2i(4, 2), "chain fail mid stays")
	expect(m.positions[2] == Vector2i(5, 2), "chain fail end stays")


func _test_shuriken_hit_and_whiff() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.play_programmed_round(filled("S E,P N,M S", "S W,P N,M N"))
	expect(m.hp[1] == 18, "P2 took shuriken 2")
	expect(m.hp[0] == 18, "P1 took return shuriken 2")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 5)
	m.play_programmed_round(filled("S N,M N,M E"))
	expect(m.hp[1] == 20 and m.hp[2] == 20 and m.hp[3] == 20, "north from A6 whiffs others")


func _test_diagonal_shuriken() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(2, 3) # C4
	m.positions[1] = Vector2i(3, 2) # D3  (NE of C4)
	m.play_programmed_round(filled("S NE,M N,M S", "S N,M N,M E"))
	expect(m.hp[1] == 18, "diagonal NE from C4 hits D3")


func _test_punch_range() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(2, 2) # two tiles east — punch should whiff
	m.play_programmed_round(filled("P E,S N,M S", "S N,M N,M E"))
	expect(m.hp[1] == 20, "punch range 1 whiffs at distance 2")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E,S N,M S", "S N,M N,M E"))
	expect(m.hp[1] == 16, "adjacent punch deals 4")


func _test_speed_order() -> void:
	# Same slot: P1 steps north off the rank, P2 throws west along that rank.
	# Instant must resolve first so the shuriken whiffs.
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(3, 2) # D3
	m.play_programmed_round(filled("M N,S N,P N", "S W,M N,M S"))
	expect(m.positions[0] == Vector2i(1, 1), "P1 moved to B2")
	expect(m.hp[0] == 20, "shuriken resolved after move and missed")


func _test_lower_priority_can_push_after() -> void:
	# P1 (higher) moves east into empty. P2 later moves west onto P1 and pushes.
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(4, 2) # E3
	m.priority = [0, 1, 2, 3]
	m.play_programmed_round(filled("M E,S N,P N", "M W,S N,P N"))
	# P1 first: C3 -> D3 empty.
	# P2: E3 west onto D3, push P1 west to C3, P2 takes D3.
	expect(m.positions[0] == Vector2i(2, 2), "P1 pushed back to C3")
	expect(m.positions[1] == Vector2i(3, 2), "P2 occupies D3")


func _test_priority_rotates_after_round() -> void:
	var m := match_with(filled("S N,M N,M E"))
	expect(m.priority[0] == 1, "priority rotated to P2 first")
	expect(m.priority[3] == 0, "P1 now last")


func _test_mutual_ko_same_tier() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 4
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E,S N,M S", "P W,S N,M S"))
	expect(not m.alive[0] and not m.alive[1], "both KO in same punch step")
	expect(m.alive[2] and m.alive[3], "others still up")


func _test_dead_skip_later_slots() -> void:
	var m := ArenaMatch.new()
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E,S E,M S", "S W,M N,P W"))
	expect(not m.alive[1], "P2 died in slot 1")
	expect(m.hp[0] == 18, "P2 slot-1 shuriken hit; later punch skipped")


func _test_win_last_player() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 4
	m.hp[1] = 4
	m.hp[2] = 4
	m.positions[0] = Vector2i(2, 2)
	m.positions[1] = Vector2i(3, 2)
	m.positions[2] = Vector2i(2, 3)
	# P4 punches nobody; P1 punches P2, P2 punches P1, P3 punches north into P1's tile...
	# Simpler: three players at 4 HP, P4 punches P3 from F2 is far.
	# KO P1 P2 P3 with P4 punching nothing and others punching each other isn't enough.
	# Direct: P1 punches P2, P2 punches P3, P3 punches P1, all adjacent triangle + P4 idle.
	m.positions[3] = Vector2i(5, 5)
	m.play_programmed_round(filled("P E,S N,M S", "P W,S N,M S", "P N,S N,M S", "S N,M N,M E"))
	# P1 C3 punch E hits P2 D3; P2 punch W hits P1; P3 C4 punch N hits P1 (same tile).
	# P1 takes 4+4=8 but only had 4, dies; P2 takes 4, dies; P3 alive.
	# Wait P3 punch N from C4 hits C3 which is P1. P3 survives. P4 alive too. Not a win.
	expect(m.alive[2] and m.alive[3], "P3 and P4 remain")
	expect(m.phase != ArenaMatch.Phase.MATCH_OVER, "match continues with 2+")
	# Finish them: next round P3 punches... we only needed continue vs over.
	m.hp[2] = 4
	m.hp[3] = 4
	m.positions[2] = Vector2i(4, 5)
	m.positions[3] = Vector2i(5, 5)
	m.play_programmed_round({2: prog("P E,S N,M S"), 3: prog("P W,S N,M S")})
	expect(m.phase == ArenaMatch.Phase.MATCH_OVER, "match over after last two KO")
	expect(m.winners.is_empty(), "shared final KO is a draw")


func _test_step_through_matches_batch() -> void:
	var programs := filled("M E,S E,P N", "M W,S W,P S", "M N,S N,P E", "M S,S S,P W")
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
	expect(n > 3, "stepped one action at a time")


func _test_declare_preview_chains_moves() -> void:
	var m := ArenaMatch.new()
	var slots: Array = [
		ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_E),
		{},
		ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_N),
	]
	var preview: Dictionary = m.declare_preview(0, slots)
	# P1 starts A5; slot1 East -> B5; empty slot2; slot3 North from B5 -> B4.
	expect(preview.plan_origin == Vector2i(1, 4), "next-slot origin is after slot 1 only (B5)")
	expect(preview.steps.size() == 2, "empty slot is skipped in ghost list")
	expect(preview.steps[1].to == Vector2i(1, 3), "slot 3 ghost is B4 after chained move")
	slots[0] = {}
	preview = m.declare_preview(0, slots)
	expect(preview.plan_origin == Vector2i(0, 4), "clearing slot 1 resets origin to A5")
	expect(preview.steps[0].to == Vector2i(0, 3), "slot 3 recast from A5 north to A4")


func _test_declare_follows_priority() -> void:
	var m := match_with(filled("M N,M S,M E"))
	expect(m.priority[0] == 1, "P2 is top priority after round 1")
	var order: Array[int] = []
	for id in m.priority:
		if m.alive[id]:
			order.append(id)
	expect(order[0] == 1, "first declarer in pass-and-play is top priority")


func _test_once_per_round_limit() -> void:
	var m := ArenaMatch.new()
	var err := m.submit_program(0, prog("S N,S E,M S"))
	expect(err != "", "duplicate Shuriken rejected")
	err = m.submit_program(0, prog("M N,M S,M E"))
	expect(err == "", "Move may fill all 3 slots")
	err = m.submit_program(0, prog("P N,S E,P S"))
	expect(err != "", "duplicate Punch rejected")


func _test_xp_and_level_up() -> void:
	var m := match_with(filled("M N,M S,M E"))
	expect(m.xp[0] == 1, "alive-only round is 1 XP")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E,S N,M S", "M N,M S,M E"))
	expect(m.xp[1] == 2, "damage bonus stacks on base XP")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E,M W,M E"))
	# C3 east D3 (center), west C3, east D3 — ends D3 center
	expect(m.xp[0] == 2, "center occupancy bonus stacks on base XP")
	m = ArenaMatch.new()
	m.xp[0] = 4
	m.rng.seed = 1
	m.play_programmed_round(filled("M N,M S,M E"))
	expect(m.xp[0] == 5, "XP is cumulative through the 5 threshold")
	expect(m.owned[0].size() == 4, "crossing 5 XP grants one acquired ability")
	expect(m.phase == ArenaMatch.Phase.DECLARE, "tests auto-resolve the level-up pick")


func _test_heal() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 10
	m.play_programmed_round(filled("H,S N,P N"))
	expect(m.hp[0] == 12, "Heal restores 2")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 19
	m.play_programmed_round(filled("H,S N,P N"))
	expect(m.hp[0] == 20, "Heal cannot exceed 20")


func _test_flying_kick() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("K E,S N,P N"))
	expect(m.positions[0] == Vector2i(1, 2), "kick steps to B3")
	expect(m.hp[1] == 18, "kick deals 2 to the tile beyond the landing")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(0, 0) # A1
	m.positions[1] = Vector2i(0, 1) # A2 south of wall-fail north
	m.play_programmed_round(filled("K N,S N,P N"))
	expect(m.positions[0] == Vector2i(0, 0), "wall-fail kick does not move")
	expect(m.hp[1] == 20, "nothing north of A1 to hit")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(4, 2) # E3
	m.positions[1] = Vector2i(5, 2) # F3 against east wall
	m.play_programmed_round(filled("K E,S N,P N"))
	expect(m.positions[0] == Vector2i(4, 2), "blocked push-kick stays put")
	expect(m.hp[1] == 18, "wall-fail kick still hits the adjacent occupant")


func _test_frost_ring() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(2, 3) # C4
	m.positions[2] = Vector2i(3, 2) # D3
	m.positions[3] = Vector2i(5, 5) # F6 out of ring
	m.play_programmed_round(filled("R,S N,P N"))
	expect(m.hp[1] == 19, "frost hits adjacent C4")
	expect(m.hp[2] == 19, "frost hits adjacent D3")
	expect(m.hp[3] == 20, "frost does not hit F6")


func _test_fireball_splash() -> void:
	var m := ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FIREBALL)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.positions[2] = Vector2i(4, 1) # E2 adjacent to stop
	m.play_programmed_round(filled("F E,S N,P N", "P S,M N,M S"))
	expect(m.hp[1] == 17, "fireball direct hit 3")
	expect(m.hp[2] == 19, "fireball splash 1 on neighbor of impact")
	m = ArenaMatch.new()
	m.owned[0].append(ArenaMatch.ActionKind.FIREBALL)
	m.positions[0] = Vector2i(5, 2) # F3
	m.positions[1] = Vector2i(5, 1) # F2
	m.play_programmed_round(filled("F E,S N,P N"))
	expect(m.hp[1] == 19, "wall-whiff still splashes tiles adjacent to the wall")


func _test_windwall_reflects_projectile() -> void:
	var m := ArenaMatch.new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.play_programmed_round(filled("S E,P N,M N", "W W,S N,P N"))
	expect(m.hp[1] == 20, "Windwall blocks the incoming Shuriken")
	expect(m.hp[0] == 18, "reflected Shuriken travels west and hits the thrower")
	m = ArenaMatch.new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2)
	m.positions[1] = Vector2i(2, 3)
	m.play_programmed_round(filled("R,S N,P N", "W N,S N,P N"))
	expect(m.hp[1] == 19, "Windwall does not block Frost Ring")

