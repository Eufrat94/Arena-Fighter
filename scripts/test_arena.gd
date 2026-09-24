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
	_test_same_tier_snapshot_combat()
	_test_normal_mutual_shuriken()
	_test_win_last_player()
	_test_step_through_matches_batch()
	_test_declare_preview_chains_moves()
	_test_declare_follows_priority()
	_test_once_per_round_limit()
	_test_xp_and_level_up()
	_test_starting_ability()
	_test_heal()
	_test_flying_kick()
	_test_frost_ring()
	_test_spear_strike()
	_test_fireball_splash()
	_test_windwall_reflects_projectile()
	_test_windwall_reflect_playback_legs()
	_test_windwall_lasts_until_cleanup()
	_test_uncontested_moves_all_apply()
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
	_test_legal_move_highlights()
	_test_aim_neighbor_highlights()
	_test_diagonal_ray_exits_true_45()


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
			"T":
				kind = ArenaMatch.ActionKind.SPEAR_STRIKE
			_:
				push_error("bad kind")
		var dir := Vector2i.ZERO
		if bits.size() > 1:
			dir = ArenaMatch.parse_dir(bits[1])
		actions.append(ArenaMatch.make_action(kind, dir))
	return actions


func idle() -> Array:
	return [ArenaMatch.make_pass()]


func match_new() -> ArenaMatch:
	var m := ArenaMatch.new()
	for i in ArenaMatch.PLAYER_COUNT:
		m.owned[i] = [ArenaMatch.ActionKind.MOVE, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.ActionKind.PUNCH]
	return m


func match_with(programs: Dictionary) -> ArenaMatch:
	var m := match_new()
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
	var m := match_new()
	expect(m.positions[0] == Vector2i(1, 5), "P1 starts B6")
	expect(m.positions[1] == Vector2i(0, 1), "P2 starts A2")
	expect(m.positions[2] == Vector2i(4, 0), "P3 starts E1")
	expect(m.positions[3] == Vector2i(5, 4), "P4 starts F5")
	expect(ArenaMatch.tile_name(m.positions[0]) == "B6", "tile name B6")


func _test_pass_stays_put() -> void:
	var m := match_new()
	var start: Vector2i = m.positions[0]
	m.play_programmed_round(filled("M"))
	expect(m.positions[0] == start, "pass / stay does not move")
	expect(m.round_index == 2, "cleanup runs after a single-action turn")


func _test_wall_blocks_move() -> void:
	var m := match_new()
	for _i in 3:
		m.play_programmed_round(filled("M N"))
	# P1 B6: N three turns -> B5, B4, B3
	expect(m.positions[0] == Vector2i(1, 2), "P1 walked north to B3")
	m = match_new()
	m.positions[1] = Vector2i(1, 0)
	m.play_programmed_round(filled("M", "M N"))
	expect(m.positions[1] == Vector2i(1, 0), "P2 north from B1 is wall, stays")


func _test_simple_move() -> void:
	var m := match_with(filled("M E"))
	expect(m.positions[0] == Vector2i(2, 5), "P1 B6 east to C6")


func _test_push() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E"))
	expect(m.positions[0] == Vector2i(2, 2), "mover takes C3")
	expect(m.positions[1] == Vector2i(3, 2), "occupant pushed to D3")


func _test_chain_push() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(1, 2) # B3
	m.positions[2] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E"))
	expect(m.positions[0] == Vector2i(1, 2), "P1 to B3")
	expect(m.positions[1] == Vector2i(2, 2), "P2 to C3")
	expect(m.positions[2] == Vector2i(3, 2), "P3 to D3")


func _test_push_wall_fails_entire_chain() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(3, 2) # D3
	m.positions[1] = Vector2i(4, 2) # E3
	m.positions[2] = Vector2i(5, 2) # F3 against east wall
	m.play_programmed_round(filled("M E"))
	expect(m.positions[0] == Vector2i(3, 2), "chain fail mover stays")
	expect(m.positions[1] == Vector2i(4, 2), "chain fail mid stays")
	expect(m.positions[2] == Vector2i(5, 2), "chain fail end stays")


func _test_shuriken_hit_and_whiff() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.play_programmed_round(filled("S E", "S W"))
	expect(m.hp[1] == 18, "P2 took shuriken 2")
	expect(m.hp[0] == 18, "P1 took return shuriken 2")
	m = match_new()
	m.positions[0] = Vector2i(0, 5)
	m.positions[1] = Vector2i(1, 0)
	m.play_programmed_round(filled("S N"))
	expect(m.hp[1] == 20 and m.hp[2] == 20 and m.hp[3] == 20, "north from A6 whiffs others")


func _test_diagonal_shuriken() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(2, 3) # C4
	m.positions[1] = Vector2i(3, 2) # D3  (NE of C4)
	m.play_programmed_round(filled("S NE"))
	expect(m.hp[1] == 18, "diagonal NE from C4 hits D3")


func _test_punch_range() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(2, 2) # two tiles east — punch should whiff
	m.play_programmed_round(filled("P E"))
	expect(m.hp[1] == 20, "punch range 1 whiffs at distance 2")
	m = match_new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E"))
	expect(m.hp[1] == 16, "adjacent punch deals 4")


func _test_speed_order() -> void:
	# Same slot: P1 steps north off the rank, P2 throws west along that rank.
	# Instant must resolve first so the shuriken whiffs.
	var m := match_new()
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(3, 2) # D3
	m.play_programmed_round(filled("M N", "S W"))
	expect(m.positions[0] == Vector2i(1, 1), "P1 moved to B2")
	expect(m.hp[0] == 20, "shuriken resolved after move and missed")


func _test_lower_priority_can_push_after() -> void:
	# P1 (higher) moves east into empty. P2 later moves west onto P1 and pushes.
	var m := match_new()
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
	var m := match_new()
	m.hp[0] = 4
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E", "P W"))
	expect(not m.alive[0] and not m.alive[1], "both KO in same punch step")
	expect(m.alive[2] and m.alive[3], "others still up")


func _test_dead_skip_later_slots() -> void:
	var m := match_new()
	m.hp[1] = 4
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E", "S W"))
	expect(not m.alive[1], "P2 died this turn")
	expect(m.hp[0] == 18, "P2 Shuriken (Normal) hit before the Punch (Slow)")


func _test_same_tier_snapshot_combat() -> void:
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.owned[1].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(2, 3) # C4
	m.play_programmed_round(filled("K N", "R"))
	expect(m.positions[0] == Vector2i(2, 1), "kick still steps north to C2")
	expect(m.hp[0] == 18, "Frost uses the pre-Slow snapshot, so it still hits the kicker")


func _test_normal_mutual_shuriken() -> void:
	var m := match_new()
	m.hp[0] = 2
	m.hp[1] = 2
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(4, 2)
	m.play_programmed_round(filled("S E", "S W"))
	expect(not m.alive[0] and not m.alive[1], "same-tier shots both apply; mutual KO is allowed")


func _test_win_last_player() -> void:
	var m := match_new()
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
	var batch := match_new()
	batch.play_programmed_round(programs)
	var stepped := match_new()
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
	var m := match_new()
	var slots: Array = [ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_E)]
	var preview: Dictionary = m.declare_preview(0, slots)
	expect(preview.plan_origin == Vector2i(2, 5), "single Move east ghosts to C6")
	expect(preview.steps.size() == 1, "one declared action, one ghost")
	expect(preview.steps[0].to == Vector2i(2, 5), "ghost lands on C6")
	slots[0] = {}
	preview = m.declare_preview(0, slots)
	expect(preview.plan_origin == Vector2i(1, 5), "clearing the action resets origin to B6")


func _test_declare_follows_priority() -> void:
	var m := match_with(filled("M N"))
	expect(m.priority[0] == 1, "P2 is top priority after turn 1")
	var order: Array[int] = []
	for id in m.priority:
		if m.alive[id]:
			order.append(id)
	expect(order[0] == 1, "first declarer in pass-and-play is top priority")


func _test_once_per_round_limit() -> void:
	var m := match_new()
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
	m = match_new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(1, 2)
	m.play_programmed_round(filled("P E"))
	expect(m.xp[1] == 2, "damage bonus stacks on base XP")
	m = match_new()
	m.positions[0] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("M E"))
	expect(m.xp[0] == 2, "center occupancy bonus stacks on base XP")
	m = match_new()
	m.xp[0] = 14
	m.rng.seed = 1
	m.play_programmed_round(filled("M N"))
	expect(m.xp[0] == 15, "XP is cumulative through the 15 threshold")
	expect(m.owned[0].size() == 4, "crossing 15 XP grants one acquired ability")
	expect(m.phase == ArenaMatch.Phase.DECLARE, "tests auto-resolve the level-up pick")


func _test_starting_ability() -> void:
	var m := ArenaMatch.new()
	for i in ArenaMatch.PLAYER_COUNT:
		expect(m.owned[i].size() == 4, "each player starts with one granted ability")
		expect(m.owned[i][0] == ArenaMatch.ActionKind.MOVE, "Move is still first")
		expect(m.owned[i][1] == ArenaMatch.ActionKind.SHURIKEN, "Shuriken stays in the base kit")
		expect(m.owned[i][2] == ArenaMatch.ActionKind.PUNCH, "Punch stays in the base kit")
		var extra: ArenaMatch.ActionKind = m.owned[i][3]
		expect(extra in ArenaMatch.STARTING_POOL, "starter is from the opening pool")
		expect(extra != ArenaMatch.ActionKind.HEAL, "Heal is not granted at match start")
		expect(m.ability_ready(i, extra), "starting ability is available on turn 1")
		expect(m.cooldown_left(i, extra) == 0, "starting ability is not on cooldown")
		expect(not m.unowned_acquirable(i).has(extra), "starter is not still on the level-up pool")
	m.rng.seed = 77
	for i in ArenaMatch.PLAYER_COUNT:
		m.owned[i] = [ArenaMatch.ActionKind.MOVE, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.ActionKind.PUNCH]
	m._grant_starting_abilities()
	var first: Array = m.owned[0].duplicate()
	m.rng.seed = 77
	for i in ArenaMatch.PLAYER_COUNT:
		m.owned[i] = [ArenaMatch.ActionKind.MOVE, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.ActionKind.PUNCH]
	m._grant_starting_abilities()
	expect(m.owned[0] == first, "the same seed grants the same starting abilities")


func _test_heal() -> void:
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 10
	m.play_programmed_round(filled("H"))
	expect(m.hp[0] == 12, "Heal restores 2")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 19
	m.play_programmed_round(filled("H"))
	expect(m.hp[0] == 20, "Heal cannot exceed 20")


func _test_flying_kick() -> void:
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(2, 2) # C3
	m.play_programmed_round(filled("K E"))
	expect(m.positions[0] == Vector2i(1, 2), "kick steps to B3")
	expect(m.hp[1] == 18, "kick deals 2 to the tile beyond the landing")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(0, 0) # A1
	m.positions[1] = Vector2i(0, 1) # A2 south of wall-fail north
	m.play_programmed_round(filled("K N"))
	expect(m.positions[0] == Vector2i(0, 0), "wall-fail kick does not move")
	expect(m.hp[1] == 20, "nothing north of A1 to hit")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(4, 2) # E3
	m.positions[1] = Vector2i(5, 2) # F3 against east wall
	m.play_programmed_round(filled("K E"))
	expect(m.positions[0] == Vector2i(4, 2), "blocked push-kick stays put")
	expect(m.positions[1] == Vector2i(5, 2), "wall-fail kick does not push")
	expect(m.hp[1] == 18, "wall-fail kick still hits the adjacent target")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FLYING_KICK)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(1, 2) # B3 adjacent
	m.play_programmed_round(filled("K E"))
	expect(m.positions[0] == Vector2i(1, 2), "kicker takes the vacated tile")
	expect(m.positions[1] == Vector2i(2, 2), "adjacent target is pushed like a Move")
	expect(m.hp[1] == 18, "damage lands on whoever is adjacent after the push")


func _test_frost_ring() -> void:
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(2, 3) # C4
	m.positions[2] = Vector2i(3, 2) # D3
	m.positions[3] = Vector2i(5, 5) # F6 out of ring
	m.play_programmed_round(filled("R"))
	expect(m.hp[1] == 18, "frost hits adjacent C4")
	expect(m.hp[2] == 18, "frost hits adjacent D3")
	expect(m.hp[3] == 20, "frost does not hit F6")


func _test_spear_strike() -> void:
	var tiles := ArenaMatch.spear_tiles(Vector2i(2, 2), ArenaMatch.DIR_E)
	expect(tiles.size() == 2, "interior east spear checks two tiles")
	expect(tiles[0] == Vector2i(3, 2) and tiles[1] == Vector2i(4, 2), "east spear is +1 then +2")
	expect(ArenaMatch.spear_tiles(Vector2i(0, 2), ArenaMatch.DIR_W).is_empty(), "off-grid first tile yields no strike")
	var edge := ArenaMatch.spear_tiles(Vector2i(4, 2), ArenaMatch.DIR_E)
	expect(edge.size() == 1 and edge[0] == Vector2i(5, 2), "near-edge spear still checks the on-grid first tile")
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.SPEAR_STRIKE)
	m.positions[0] = Vector2i(1, 2) # B3
	m.positions[1] = Vector2i(2, 2) # C3 range 1
	m.positions[2] = Vector2i(3, 2) # D3 range 2
	m.positions[3] = Vector2i(4, 2) # E3 beyond
	m.play_programmed_round(filled("T E"))
	expect(m.hp[1] == 17, "spear deals 3 at range 1")
	expect(m.hp[2] == 17, "spear deals 3 at range 2 independently")
	expect(m.hp[3] == 20, "spear does not continue past range 2")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.SPEAR_STRIKE)
	m.positions[0] = Vector2i(1, 2)
	m.positions[1] = Vector2i(3, 2) # only range 2 occupied
	m.play_programmed_round(filled("T E"))
	expect(m.hp[1] == 17, "empty range-1 still hits range 2")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.SPEAR_STRIKE)
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.positions[0] = Vector2i(1, 2)
	m.positions[1] = Vector2i(3, 2)
	m.play_programmed_round(filled("T E", "W W"))
	expect(m.hp[1] == 17, "Windwall does not block Spear Strike")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.SPEAR_STRIKE)
	m.positions[0] = Vector2i(0, 2)
	m.play_programmed_round(filled("T W"))
	expect(m.hp[0] == 20, "off-grid first tile is a full whiff, not a self-hit")
	expect(m.alive[0], "west-from-A-file spear is legal but empty")
	var offers_ok := ArenaMatch.ActionKind.SPEAR_STRIKE in ArenaMatch.ACQUIRABLE
	expect(offers_ok, "Spear Strike is in the level-up pool")
	expect(ArenaMatch.speed_of(ArenaMatch.ActionKind.SPEAR_STRIKE) == ArenaMatch.SpeedTier.SLOW, "Spear Strike is Slow")
	expect(not ArenaMatch.is_projectile(ArenaMatch.ActionKind.SPEAR_STRIKE), "Spear Strike is not a projectile")


func _test_fireball_splash() -> void:
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FIREBALL)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.positions[2] = Vector2i(4, 1) # E2 adjacent to stop
	m.play_programmed_round(filled("F E"))
	expect(m.hp[1] == 17, "fireball direct hit 3")
	expect(m.hp[2] == 19, "fireball splash 1 on neighbor of impact")
	m = match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FIREBALL)
	m.positions[0] = Vector2i(5, 2) # F3
	m.positions[1] = Vector2i(5, 1) # F2
	m.play_programmed_round(filled("F E"))
	expect(m.hp[1] == 19, "wall-whiff still splashes tiles adjacent to the wall")


func _test_windwall_reflects_projectile() -> void:
	var m := match_new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3
	m.play_programmed_round(filled("S E", "W W"))
	expect(m.hp[1] == 20, "Windwall blocks the incoming Shuriken")
	expect(m.hp[0] == 18, "reflected Shuriken travels west and hits the thrower")
	m = match_new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2)
	m.positions[1] = Vector2i(2, 3)
	m.play_programmed_round(filled("R", "W N"))
	expect(m.hp[1] == 18, "Windwall does not block Frost Ring")


func _test_windwall_reflect_playback_legs() -> void:
	var m := match_new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(4, 2)
	m.phase = ArenaMatch.Phase.DECLARE
	m.programs.clear()
	expect(m.submit_program(0, prog("S E")) == "", "p1 shuriken")
	expect(m.submit_program(1, prog("W W")) == "", "p2 windwall")
	expect(m.submit_program(2, idle()) == "", "p3 idle")
	expect(m.submit_program(3, idle()) == "", "p4 idle")
	m.begin_reveal()
	var inbound: Dictionary = {}
	var bounce: Dictionary = {}
	var n := 0
	while m.phase == ArenaMatch.Phase.REVEAL or m.phase == ArenaMatch.Phase.RESOLVING:
		var fx := m.resolve_next_action()
		n += 1
		if str(fx.get("kind", "")) == "shuriken" and bool(fx.get("blocked", false)):
			inbound = fx
		elif str(fx.get("kind", "")) == "shuriken" and not inbound.is_empty() and bounce.is_empty():
			bounce = fx
			break
		if n > 80:
			expect(false, "reflect playback step-through stuck")
			return
	expect(not inbound.is_empty(), "inbound blocked leg is played")
	expect(inbound.get("dir") == ArenaMatch.DIR_E, "inbound travels the original east throw")
	expect(inbound.get("origin") == Vector2i(0, 2), "inbound starts at the thrower")
	expect(int(inbound.get("wall_player", -1)) == 1, "impact is on the Windwall holder")
	expect(not bounce.is_empty(), "reflected travel is a separate playback leg")
	expect(bounce.get("dir") == ArenaMatch.DIR_W, "reflect fires opposite the inbound travel")
	expect(bounce.get("origin") == Vector2i(4, 2), "reflect starts at the wall tile, not hardcoded to the thrower")
	expect(int(bounce.get("hit_player", -1)) == 0, "this setup's reverse path does hit the thrower")
	var bounce_tiles: Array = bounce.get("tiles", [])
	expect(bounce_tiles.size() > 0, "reflected ray has a real path")
	expect(bounce_tiles[bounce_tiles.size() - 1] == Vector2i(0, 2), "bounce stops on the occupant of the reverse line")


func _test_windwall_lasts_until_cleanup() -> void:
	var m := match_new()
	m.owned[1].append(ArenaMatch.ActionKind.WINDWALL)
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(4, 2)
	m.phase = ArenaMatch.Phase.DECLARE
	m.programs.clear()
	expect(m.submit_program(0, prog("S E")) == "", "p1 shuriken")
	expect(m.submit_program(1, prog("W W")) == "", "p2 windwall")
	expect(m.submit_program(2, idle()) == "", "p3 idle")
	expect(m.submit_program(3, idle()) == "", "p4 idle")
	m.begin_reveal()
	var n := 0
	var saw_cover := false
	while m.phase == ArenaMatch.Phase.REVEAL or m.phase == ArenaMatch.Phase.RESOLVING:
		m.resolve_next_action()
		n += 1
		if m.windwall_incoming[1].size() == 3:
			saw_cover = true
			expect(ArenaMatch.DIR_W in m.windwall_incoming[1], "west cover")
			expect(ArenaMatch.DIR_NW in m.windwall_incoming[1], "nw cover")
			expect(ArenaMatch.DIR_SW in m.windwall_incoming[1], "sw cover")
		if m.awaiting_cleanup:
			expect(m.windwall_incoming[1].size() == 3, "windwall still up at end of resolution")
			m.resolve_next_action()
			break
		if n > 80:
			expect(false, "windwall duration step-through stuck")
			return
	expect(saw_cover, "windwall cover was applied during Instant")
	expect(m.windwall_incoming[1].is_empty(), "windwall clears at cleanup")


func _test_uncontested_moves_all_apply() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(5, 2)
	m.positions[2] = Vector2i(2, 0)
	m.positions[3] = Vector2i(2, 5)
	m.play_programmed_round(filled("M E", "M W", "M S", "M N"))
	expect(m.positions[0] == Vector2i(1, 2), "p1 uncontested east")
	expect(m.positions[1] == Vector2i(4, 2), "p2 uncontested west")
	expect(m.positions[2] == Vector2i(2, 1), "p3 uncontested south")
	expect(m.positions[3] == Vector2i(2, 4), "p4 uncontested north")


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
	var m := match_new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(4, 2) # E3 in a straight east line
	# Hidden bait: P2's unrevealed plan leaves the line. A cheating CPU would not throw east.
	m.programs[1] = prog("M N")
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.DIR_E), "CPU throws at the visible line, not at P2's hidden north moves")
	expect(m.programs[1][0].kind == ArenaMatch.ActionKind.MOVE, "planner must not rewrite other programs")


func _test_cpu_pokes_when_low_and_safe() -> void:
	var m := match_new()
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
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.HEAL)
	m.hp[0] = 5
	m.positions[0] = Vector2i(2, 2)
	m.positions[1] = Vector2i(3, 2)
	m.alive[2] = false
	m.alive[3] = false
	var plan: Array = _cpu_plan(m, 0)
	expect(plan[0].kind == ArenaMatch.ActionKind.HEAL, "low HP in melee with no kill shot prefers Heal")


func _test_cpu_retreats_when_adjacent_and_low() -> void:
	var m := match_new()
	m.hp[0] = 5
	m.positions[0] = Vector2i(2, 2) # C3 — room to step west
	m.positions[1] = Vector2i(3, 2) # D3
	m.alive[2] = false
	m.alive[3] = false
	var plan: Array = _cpu_plan(m, 0)
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "low HP next to a foe with no Heal: move away")
	expect(plan[0].dir == ArenaMatch.DIR_W, "retreat steps off the threat, not onto it")


func _test_cpu_takes_clear_shuriken() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(0, 2)
	m.positions[1] = Vector2i(4, 2)
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.DIR_E), "clear east line is a Shuriken")


func _test_cpu_frost_on_cluster() -> void:
	var m := match_new()
	m.owned[0].append(ArenaMatch.ActionKind.FROST_RING)
	m.positions[0] = Vector2i(2, 2) # C3
	m.positions[1] = Vector2i(2, 3) # C4
	m.positions[2] = Vector2i(3, 2) # D3
	m.positions[3] = Vector2i(5, 5)
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.FROST_RING), "two adjacent foes prefer Frost Ring")


func _test_cpu_closes_distance() -> void:
	var m := match_new()
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
	var m := match_new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(3, 1) # D2 — not currently on a ray
	m.last_step_dir[1] = ArenaMatch.DIR_S # would step to D3, on the east line
	var plan: Array = _cpu_plan(m, 0)
	expect(_plan_has(plan, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.DIR_E), "one-tile last-move extrapolation aims the throw")


func _test_cpu_projects_own_moves() -> void:
	var m := match_new()
	m.positions[0] = Vector2i(0, 2) # A3
	m.positions[1] = Vector2i(2, 3) # C4 — not on a cardinal/diagonal ray
	var plan: Array = _cpu_plan(m, 0)
	expect(plan.size() == 1, "CPU commits one action per turn")
	expect(plan[0].kind == ArenaMatch.ActionKind.MOVE, "no current attack line: step in")
	expect(plan[0].dir == ArenaMatch.DIR_E, "closes east toward C4")


func _test_cpu_stand_when_retreat_loops() -> void:
	var m := match_new()
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
	var m := match_new()
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
	var m := match_new()
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
	m = match_new()
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


func _has_tile(tiles: Array[Vector2i], pos: Vector2i) -> bool:
	return pos in tiles


func _test_legal_move_highlights() -> void:
	var edge := ArenaMatch.move_destinations(Vector2i(0, 4))
	expect(edge.size() == 3, "A5 Move has three on-board orthogonal tiles")
	expect(_has_tile(edge, Vector2i(0, 3)), "A5 can step north")
	expect(_has_tile(edge, Vector2i(0, 5)), "A5 can step south")
	expect(_has_tile(edge, Vector2i(1, 4)), "A5 can step east")
	expect(not _has_tile(edge, Vector2i(-1, 4)), "A5 cannot step off the west edge")
	var corner := ArenaMatch.move_destinations(Vector2i(0, 0))
	expect(corner.size() == 2, "A1 Move has only east and south")
	expect(_has_tile(corner, Vector2i(1, 0)), "A1 east")
	expect(_has_tile(corner, Vector2i(0, 1)), "A1 south")
	var mid := ArenaMatch.move_destinations(Vector2i(2, 2))
	expect(mid.size() == 4, "interior Move has four orthogonal tiles")


func _test_aim_neighbor_highlights() -> void:
	var mid := ArenaMatch.aim_neighbors(Vector2i(2, 2))
	expect(mid.size() == 8, "interior aim shows all eight neighbors")
	var corner := ArenaMatch.aim_neighbors(Vector2i(0, 0))
	expect(corner.size() == 3, "A1 aim only highlights on-board neighbors")
	expect(_has_tile(corner, Vector2i(1, 0)), "A1 east")
	expect(_has_tile(corner, Vector2i(1, 1)), "A1 southeast")
	expect(_has_tile(corner, Vector2i(0, 1)), "A1 south")
	var edge := ArenaMatch.aim_neighbors(Vector2i(0, 4))
	expect(edge.size() == 5, "A5 aim has five on-board neighbors")


func _test_diagonal_ray_exits_true_45() -> void:
	var board0 := Vector2.ZERO
	var board1 := Vector2(6, 6)
	# A5 center (0.5, 4.5) SW: true exit is left edge at y=5, not A6's left midpoint (0, 5.5).
	var sw := ArenaMatch.ray_rect_exit(Vector2(0.5, 4.5), Vector2i(-1, 1), board0, board1)
	expect(is_equal_approx(sw.x, 0.0), "A5 SW exits at the left edge")
	expect(is_equal_approx(sw.y, 5.0), "A5 SW stays on the 45° line (y=5), not A6 midpoint")
	# B1 center (1.5, 0.5) NW: true exit is top edge at x=1, not A1's top midpoint (0.5, 0).
	var nw := ArenaMatch.ray_rect_exit(Vector2(1.5, 0.5), Vector2i(-1, -1), board0, board1)
	expect(is_equal_approx(nw.x, 1.0), "B1 NW exits between A and B")
	expect(is_equal_approx(nw.y, 0.0), "B1 NW exits at the top edge")
	# Interior NE from C4 (2.5, 3.5) runs to the north or east edge on 45°.
	var ne := ArenaMatch.ray_rect_exit(Vector2(2.5, 3.5), Vector2i(1, -1), board0, board1)
	expect(is_equal_approx(ne.x - 2.5, 3.5 - ne.y), "C4 NE remains 45° to the boundary")
	expect(ne.x <= 6.0 and ne.y >= 0.0, "C4 NE exit is on the board rectangle")
	# Orthogonal north from B1 must still hit the top of column B.
	var n := ArenaMatch.ray_rect_exit(Vector2(1.5, 0.5), Vector2i(0, -1), board0, board1)
	expect(is_equal_approx(n.x, 1.5) and is_equal_approx(n.y, 0.0), "orthogonal N is unchanged")





