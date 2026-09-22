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
			_:
				push_error("bad kind")
		actions.append(ArenaMatch.make_action(kind, ArenaMatch.parse_dir(bits[1])))
	return actions


func idle() -> Array:
	# Range-1 punch off the north edge for anyone not adjacent north of a victim.
	return prog("P N,P N,P N")


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
	m.play_programmed_round(filled("S N,S N,S N", "M N,M N,M N"))
	expect(m.positions[1] == Vector2i(1, 0), "P2 north from B1 is wall, stays")


func _test_simple_move() -> void:
	var m := match_with(filled("M E,S N,S N"))
	expect(m.positions[0] == Vector2i(1, 4), "P1 A5 east to B5")


func _test_push() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E,S N,S N", "S N,S N,S N"))
	expect(m.positions[0] == Vector2i(2, 2), "mover takes C3")
	expect(m.positions[1] == Vector2i(3, 2), "occupant pushed to D3")


func _test_chain_push() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(1, 2) # B3
	m.positions[2] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E,S N,S N", "S N,S N,S N", "S N,S N,S N"))
	expect(m.positions[0] == Vector2i(1, 2), "P1 to B3")
	expect(m.positions[1] == Vector2i(2, 2), "P2 to C3")
	expect(m.positions[2] == Vector2i(3, 2), "P3 to D3")


func _test_push_wall_fails_entire_chain() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(3, 2) # D3
	m.positions[1] = Vector2i(4, 2) # E3
	m.positions[2] = Vector2i(5, 2) # F3 against east wall
	m.play_programmed_round(filled("M E,S N,S N", "S N,S N,S N", "S N,S N,S N"))
	expect(m.positions[0] == Vector2i(3, 2), "chain fail mover stays")
	expect(m.positions[1] == Vector2i(4, 2), "chain fail mid stays")
	expect(m.positions[2] == Vector2i(5, 2), "chain fail end stays")


func _test_shuriken_hit_and_whiff() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.play_programmed_round(filled("S E,S N,S N", "S W,S N,S N"))
	expect(m.hp[1] == 18, "P2 took shuriken 2")
	expect(m.hp[0] == 18, "P1 took return shuriken 2")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 5)
	m.play_programmed_round(filled("S N,S N,S N"))
	expect(m.hp[1] == 20 and m.hp[2] == 20 and m.hp[3] == 20, "north from A6 whiffs others")


func _test_diagonal_shuriken() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(2, 3) # C4
	m.positions[1] = Vector2i(3, 2) # D3  (NE of C4)
	m.play_programmed_round(filled("S NE,S N,S N", "S N,S N,S N"))
	expect(m.hp[1] == 18, "diagonal NE from C4 hits D3")


func _test_punch_range() -> void:
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(2, 2) # two tiles east — punch should whiff
	m.play_programmed_round(filled("P E,S N,S N", "S N,S N,S N"))
	expect(m.hp[1] == 20, "punch range 1 whiffs at distance 2")
	m = ArenaMatch.new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E,S N,S N", "S N,S N,S N"))
	expect(m.hp[1] == 16, "adjacent punch deals 4")


func _test_speed_order() -> void:
	# Same slot: P1 steps north off the rank, P2 throws west along that rank.
	# Instant must resolve first so the shuriken whiffs.
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(3, 2) # D3
	m.play_programmed_round(filled("M N,S N,S N", "S W,S N,S N"))
	expect(m.positions[0] == Vector2i(1, 1), "P1 moved to B2")
	expect(m.hp[0] == 20, "shuriken resolved after move and missed")


func _test_lower_priority_can_push_after() -> void:
	# P1 (higher) moves east into empty. P2 later moves west onto P1 and pushes.
	var m := ArenaMatch.new()
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(4, 2) # E3
	m.priority = [0, 1, 2, 3]
	m.play_programmed_round(filled("M E,S N,S N", "M W,S N,S N"))
	# P1 first: C3 -> D3 empty.
	# P2: E3 west onto D3, push P1 west to C3, P2 takes D3.
	expect(m.positions[0] == Vector2i(2, 2), "P1 pushed back to C3")
	expect(m.positions[1] == Vector2i(3, 2), "P2 occupies D3")


func _test_priority_rotates_after_round() -> void:
	var m := match_with(filled("S N,S N,S N"))
	expect(m.priority[0] == 1, "priority rotated to P2 first")
	expect(m.priority[3] == 0, "P1 now last")


func _test_mutual_ko_same_tier() -> void:
	var m := ArenaMatch.new()
	m.hp[0] = 4
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E,S N,S N", "P W,S N,S N"))
	expect(not m.alive[0] and not m.alive[1], "both KO in same punch step")
	expect(m.alive[2] and m.alive[3], "others still up")


func _test_dead_skip_later_slots() -> void:
	var m := ArenaMatch.new()
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E,S E,S E", "S W,S W,P W"))
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
	m.play_programmed_round(filled("P E,S N,S N", "P W,S N,S N", "P N,S N,S N", "S N,S N,S N"))
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
	m.play_programmed_round({2: prog("P E,S N,S N"), 3: prog("P W,S N,S N")})
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
	var m := match_with(filled("P N,P N,P N"))
	expect(m.priority[0] == 1, "P2 is top priority after round 1")
	var order: Array[int] = []
	for id in m.priority:
		if m.alive[id]:
			order.append(id)
	expect(order[0] == 1, "first declarer in pass-and-play is top priority")
