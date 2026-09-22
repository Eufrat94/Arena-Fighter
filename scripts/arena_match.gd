class_name ArenaMatch
extends RefCounted

## Pure v1 match rules: 6x6 board, Move / Shuriken / Punch, simultaneous 3-slot rounds.

const COLS := 6
const ROWS := 6
const START_HP := 20
const PLAYER_COUNT := 4
const SLOTS := 3
const SHURIKEN_DAMAGE := 2
const PUNCH_DAMAGE := 4

enum ActionKind { MOVE, SHURIKEN, PUNCH }
enum SpeedTier { INSTANT, NORMAL, SLOW }
enum Phase { DECLARE, REVEAL, RESOLVING, MATCH_OVER }

const COL_LETTERS := ["A", "B", "C", "D", "E", "F"]
const PLAYER_NAMES := ["P1", "P2", "P3", "P4"]

const DIR_N := Vector2i(0, -1)
const DIR_S := Vector2i(0, 1)
const DIR_E := Vector2i(1, 0)
const DIR_W := Vector2i(-1, 0)
const DIR_NE := Vector2i(1, -1)
const DIR_NW := Vector2i(-1, -1)
const DIR_SE := Vector2i(1, 1)
const DIR_SW := Vector2i(-1, 1)

const ORTHOGONAL := [DIR_N, DIR_S, DIR_E, DIR_W]
const ALL_DIRS := [DIR_N, DIR_NE, DIR_E, DIR_SE, DIR_S, DIR_SW, DIR_W, DIR_NW]

## A5, B1, E6, F2 — no shared row, column, or diagonal at start.
const START_POSITIONS := [
	Vector2i(0, 4),
	Vector2i(1, 0),
	Vector2i(4, 5),
	Vector2i(5, 1),
]

## C3, C4, D3, D4
const CENTER_TILES := [
	Vector2i(2, 2),
	Vector2i(2, 3),
	Vector2i(3, 2),
	Vector2i(3, 3),
]


static func tile_name(pos: Vector2i) -> String:
	if not in_bounds(pos):
		return "?"
	return COL_LETTERS[pos.x] + str(pos.y + 1)


static func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < COLS and pos.y >= 0 and pos.y < ROWS


static func is_center(pos: Vector2i) -> bool:
	return pos in CENTER_TILES


static func is_orthogonal(dir: Vector2i) -> bool:
	return dir in ORTHOGONAL


static func dir_name(dir: Vector2i) -> String:
	match dir:
		DIR_N:
			return "N"
		DIR_S:
			return "S"
		DIR_E:
			return "E"
		DIR_W:
			return "W"
		DIR_NE:
			return "NE"
		DIR_NW:
			return "NW"
		DIR_SE:
			return "SE"
		DIR_SW:
			return "SW"
		_:
			return "?"


static func parse_dir(name: String) -> Vector2i:
	match name.to_upper():
		"N":
			return DIR_N
		"S":
			return DIR_S
		"E":
			return DIR_E
		"W":
			return DIR_W
		"NE":
			return DIR_NE
		"NW":
			return DIR_NW
		"SE":
			return DIR_SE
		"SW":
			return DIR_SW
		_:
			push_error("Unknown direction: %s" % name)
			return Vector2i.ZERO


static func kind_name(kind: ActionKind) -> String:
	match kind:
		ActionKind.MOVE:
			return "Move"
		ActionKind.SHURIKEN:
			return "Shuriken"
		ActionKind.PUNCH:
			return "Punch"
		_:
			return "?"


static func speed_of(kind: ActionKind) -> SpeedTier:
	match kind:
		ActionKind.MOVE:
			return SpeedTier.INSTANT
		ActionKind.SHURIKEN:
			return SpeedTier.NORMAL
		ActionKind.PUNCH:
			return SpeedTier.SLOW
		_:
			return SpeedTier.SLOW


static func make_action(kind: ActionKind, dir: Vector2i) -> Dictionary:
	return {"kind": kind, "dir": dir}


var hp: Array[int] = []
var positions: Array[Vector2i] = []
var alive: Array[bool] = []
var priority: Array[int] = [] ## player ids, highest first
var round_index: int = 1
var phase: Phase = Phase.DECLARE
var current_slot: int = 0 ## 0..2 while resolving
var programs: Dictionary = {} ## player_id -> Array[Dictionary] of 3 actions
var log_lines: PackedStringArray = PackedStringArray()
var log_entries: Array[Dictionary] = []
var last_center_occupants: PackedStringArray = PackedStringArray()
var winners: Array[int] = [] ## empty while match running

var at_slot_boundary: bool = false
var awaiting_cleanup: bool = false
var tier_kind: int = -1 ## 0 Move, 1 Shuriken, 2 Punch, -1 none
var action_queue: Array[int] = []
var attack_plan: Array[Dictionary] = []
var last_fx: Dictionary = {}


func _init() -> void:
	reset_match()


func reset_match() -> void:
	hp.clear()
	positions.clear()
	alive.clear()
	priority.clear()
	programs.clear()
	winners.clear()
	log_lines.clear()
	log_entries.clear()
	last_center_occupants.clear()
	_reset_step_state()
	for i in PLAYER_COUNT:
		hp.append(START_HP)
		positions.append(START_POSITIONS[i])
		alive.append(true)
		priority.append(i)
	round_index = 1
	phase = Phase.DECLARE
	current_slot = 0
	_log("Match start. Priority %s." % _priority_text(), -1)


func _reset_step_state() -> void:
	at_slot_boundary = false
	awaiting_cleanup = false
	tier_kind = -1
	action_queue.clear()
	attack_plan.clear()
	last_fx = {}


func living_ids() -> Array[int]:
	var ids: Array[int] = []
	for i in PLAYER_COUNT:
		if alive[i]:
			ids.append(i)
	return ids


func player_at(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return -1
	for i in PLAYER_COUNT:
		if alive[i] and positions[i] == pos:
			return i
	return -1


func submit_program(player_id: int, actions: Array) -> String:
	if phase != Phase.DECLARE:
		return "Not in declare phase."
	if player_id < 0 or player_id >= PLAYER_COUNT or not alive[player_id]:
		return "That player cannot declare."
	if actions.size() != SLOTS:
		return "Program must have exactly 3 actions."
	for a in actions:
		var err := validate_action(a)
		if err != "":
			return err
	programs[player_id] = actions.duplicate(true)
	return ""


func all_living_have_programs() -> bool:
	for id in living_ids():
		if not programs.has(id):
			return false
	return true


func begin_reveal() -> void:
	if phase != Phase.DECLARE:
		return
	phase = Phase.REVEAL
	_reset_step_state()
	_log("--- Round %d reveal ---" % round_index, -1)
	for id in living_ids():
		_log("%s: %s" % [PLAYER_NAMES[id], _program_text(programs[id])], -1)


func resolve_stage() -> String:
	if phase == Phase.REVEAL:
		return "reveal"
	if phase != Phase.RESOLVING:
		return "idle"
	if awaiting_cleanup:
		return "end_of_round"
	if at_slot_boundary:
		return "slot_boundary"
	return "mid_slot"


func next_prompt() -> String:
	match resolve_stage():
		"reveal":
			return "Next — Slot 1"
		"end_of_round":
			return "Next — cleanup"
		"slot_boundary":
			return "Next — Slot %d" % (current_slot + 2)
		"mid_slot":
			var left := action_queue.size()
			if left > 0:
				return "Next — Slot %d  (%d more this slot)" % [current_slot + 1, left]
			return "Next — Slot %d" % (current_slot + 1)
		_:
			return "Next"


func resolve_next_action() -> Dictionary:
	if phase == Phase.DECLARE or phase == Phase.MATCH_OVER:
		return {}
	if phase == Phase.REVEAL:
		phase = Phase.RESOLVING
		current_slot = 0
		_open_slot(0)
		return _step_action()
	if awaiting_cleanup:
		_cleanup_round()
		last_fx = {"kind": "cleanup", "slot": 2}
		return last_fx
	if at_slot_boundary:
		at_slot_boundary = false
		current_slot += 1
		_open_slot(current_slot)
		return _step_action()
	return _step_action()


func resolve_remaining_slots() -> void:
	var guard := 0
	while phase == Phase.REVEAL or phase == Phase.RESOLVING:
		resolve_next_action()
		guard += 1
		if guard > 200:
			push_error("Resolution did not terminate.")
			break


## Test helper: load programs for living players and fully resolve one round.
func play_programmed_round(by_player: Dictionary) -> void:
	programs.clear()
	phase = Phase.DECLARE
	_reset_step_state()
	for id in by_player.keys():
		var err := submit_program(int(id), by_player[id])
		assert(err == "", err)
	begin_reveal()
	resolve_remaining_slots()


func _open_slot(slot: int) -> void:
	current_slot = slot
	tier_kind = -1
	action_queue.clear()
	attack_plan.clear()
	_log("Slot %d:" % (slot + 1), slot)
	for kind in [ActionKind.MOVE, ActionKind.SHURIKEN, ActionKind.PUNCH]:
		if _load_tier(kind):
			return


func _load_tier(kind: ActionKind) -> bool:
	var actors := _actors_for(current_slot, kind)
	if actors.is_empty():
		return false
	action_queue = actors
	attack_plan.clear()
	if kind == ActionKind.MOVE:
		tier_kind = 0
	elif kind == ActionKind.SHURIKEN:
		tier_kind = 1
		for id in actors:
			attack_plan.append(_plan_attack(id, kind, SHURIKEN_DAMAGE))
	else:
		tier_kind = 2
		for id in actors:
			attack_plan.append(_plan_attack(id, kind, PUNCH_DAMAGE))
	return true


func _step_action() -> Dictionary:
	if action_queue.is_empty():
		_close_current_tier_and_advance()
		if action_queue.is_empty():
			last_fx = _slot_pause_fx()
			return last_fx
	var fx: Dictionary
	if tier_kind == 0:
		var mover: int = action_queue.pop_front()
		fx = _try_move(mover, programs[mover][current_slot].dir)
	else:
		var plan: Dictionary = attack_plan.pop_front()
		action_queue.pop_front()
		fx = _apply_planned_attack(plan)
	fx["slot"] = current_slot
	fx["log_index"] = log_entries.size() - 1
	if action_queue.is_empty():
		_close_current_tier_and_advance()
	fx["more_in_slot"] = not action_queue.is_empty() and not at_slot_boundary and not awaiting_cleanup
	fx["at_slot_boundary"] = at_slot_boundary
	fx["awaiting_cleanup"] = awaiting_cleanup
	last_fx = fx
	return fx


func _close_current_tier_and_advance() -> void:
	if tier_kind == 1 or tier_kind == 2:
		_eliminate_downed()
	var start := tier_kind + 1
	tier_kind = -1
	action_queue.clear()
	attack_plan.clear()
	for k in range(maxi(start, 0), 3):
		var kind: ActionKind = [ActionKind.MOVE, ActionKind.SHURIKEN, ActionKind.PUNCH][k]
		if _load_tier(kind):
			return
	if current_slot >= SLOTS - 1:
		awaiting_cleanup = true
	else:
		at_slot_boundary = true


func _slot_pause_fx() -> Dictionary:
	return {
		"kind": "slot_end",
		"slot": current_slot,
		"at_slot_boundary": at_slot_boundary,
		"awaiting_cleanup": awaiting_cleanup,
	}


func _cleanup_round() -> void:
	_record_center()
	var living := living_ids()
	if living.size() <= 1:
		winners = living.duplicate()
		phase = Phase.MATCH_OVER
		if winners.is_empty():
			_log("Match over: no survivors.", -1)
		else:
			_log("Match over: %s wins." % PLAYER_NAMES[winners[0]], -1)
		_reset_step_state()
		return
	_rotate_priority()
	programs.clear()
	round_index += 1
	phase = Phase.DECLARE
	current_slot = 0
	_log("End of round. Center: %s. Next priority %s." % [_center_text(), _priority_text()], -1)
	_reset_step_state()


func _rotate_priority() -> void:
	if priority.is_empty():
		return
	var first: int = priority.pop_front()
	priority.append(first)


## Planning-only preview. Does not mutate match state.
func declare_preview(player_id: int, slots: Array) -> Dictionary:
	var pos: Vector2i = positions[player_id]
	var next_open := slots.size()
	for i in slots.size():
		if not slots[i].has("kind"):
			next_open = i
			break
	var plan_origin := pos
	var steps: Array = []
	for i in slots.size():
		if not slots[i].has("kind"):
			if i < next_open:
				plan_origin = pos
			continue
		var kind: ActionKind = slots[i].kind
		var dir: Vector2i = slots[i].dir
		var from := pos
		var to := pos
		var tiles: Array[Vector2i] = []
		var hit := -1
		if kind == ActionKind.MOVE:
			var dest := pos + dir
			if in_bounds(dest):
				to = dest
				pos = dest
		elif kind == ActionKind.SHURIKEN:
			var traced := _preview_ray(from, dir, COLS + ROWS, player_id)
			tiles = traced.tiles
			hit = traced.target
		else:
			var traced := _preview_ray(from, dir, 1, player_id)
			tiles = traced.tiles
			hit = traced.target
		steps.append({
			"slot": i,
			"kind": kind,
			"dir": dir,
			"from": from,
			"to": to,
			"tiles": tiles,
			"hit": hit,
		})
		if i < next_open:
			plan_origin = pos
	return {"plan_origin": plan_origin, "steps": steps}


func _preview_ray(start: Vector2i, dir: Vector2i, max_range: int, ignore_id: int) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var cursor := start
	var target := -1
	for _i in max_range:
		cursor += dir
		if not in_bounds(cursor):
			break
		tiles.append(cursor)
		var who := player_at(cursor)
		if who >= 0 and who != ignore_id:
			target = who
			break
	return {"target": target, "tiles": tiles}


func validate_action(action: Dictionary) -> String:
	if not action.has("kind") or not action.has("dir"):
		return "Action needs kind and dir."
	var kind: ActionKind = action.kind
	var dir: Vector2i = action.dir
	if dir == Vector2i.ZERO:
		return "Direction required."
	if kind == ActionKind.MOVE:
		if not is_orthogonal(dir):
			return "Move must be N/S/E/W."
	elif not dir in ALL_DIRS:
		return "Invalid aim direction."
	return ""


func _actors_for(slot: int, kind: ActionKind) -> Array[int]:
	var actors: Array[int] = []
	for id in priority:
		if not alive[id]:
			continue
		if not programs.has(id):
			continue
		var action: Dictionary = programs[id][slot]
		if action.kind == kind:
			actors.append(id)
	return actors


func _try_move(mover: int, dir: Vector2i) -> Dictionary:
	var from: Vector2i = positions[mover]
	var dest := from + dir
	var fx := {
		"kind": "move",
		"actor": mover,
		"dir": dir,
		"from": from,
		"success": false,
		"segments": [],
		"blocked_at": dest,
	}
	if not in_bounds(dest):
		fx["segments"] = [{"player": mover, "from": from, "to": dest}]
		_log("  %s Move %s into wall — fail." % [PLAYER_NAMES[mover], dir_name(dir)])
		return fx
	var occupant := player_at(dest)
	if occupant < 0:
		positions[mover] = dest
		fx["success"] = true
		fx["segments"] = [{"player": mover, "from": from, "to": dest}]
		_log("  %s Move %s to %s." % [PLAYER_NAMES[mover], dir_name(dir), tile_name(dest)])
		return fx
	var chain: Array[int] = [mover]
	var cursor := dest
	while true:
		var who := player_at(cursor)
		if who < 0:
			break
		chain.append(who)
		cursor = cursor + dir
		if not in_bounds(cursor):
			var segs: Array = []
			for pid in chain:
				segs.append({"player": pid, "from": positions[pid], "to": positions[pid] + dir})
			fx["segments"] = segs
			fx["blocked_at"] = cursor
			_log("  %s Move %s push chain hits wall — fail." % [PLAYER_NAMES[mover], dir_name(dir)])
			return fx
	var segs_ok: Array = []
	for pid in chain:
		segs_ok.append({"player": pid, "from": positions[pid], "to": positions[pid] + dir})
	for i in range(chain.size() - 1, -1, -1):
		positions[chain[i]] = positions[chain[i]] + dir
	fx["success"] = true
	fx["segments"] = segs_ok
	var names: PackedStringArray = PackedStringArray()
	for i in range(1, chain.size()):
		var pid: int = chain[i]
		names.append("%s→%s" % [PLAYER_NAMES[pid], tile_name(positions[pid])])
	_log(
		"  %s Move %s to %s, push %s."
		% [PLAYER_NAMES[mover], dir_name(dir), tile_name(positions[mover]), ", ".join(names)]
	)
	return fx


func _plan_attack(from_id: int, kind: ActionKind, damage: int) -> Dictionary:
	var dir: Vector2i = programs[from_id][current_slot].dir
	var max_range := COLS + ROWS if kind == ActionKind.SHURIKEN else 1
	var traced := _trace_ray(from_id, dir, max_range)
	return {
		"from": from_id,
		"kind": kind,
		"dir": dir,
		"damage": damage,
		"target": traced.target,
		"tiles": traced.tiles,
		"origin": positions[from_id],
	}


func _apply_planned_attack(plan: Dictionary) -> Dictionary:
	var kind: ActionKind = plan.kind
	var label := kind_name(kind)
	var fx := {
		"kind": "shuriken" if kind == ActionKind.SHURIKEN else "punch",
		"actor": plan.from,
		"dir": plan.dir,
		"origin": plan.origin,
		"tiles": plan.tiles,
		"hit_player": plan.target,
		"damage": plan.damage,
		"success": plan.target >= 0,
	}
	if plan.target < 0:
		_log("  %s %s %s — whiff." % [PLAYER_NAMES[plan.from], label, dir_name(plan.dir)])
		return fx
	var target: int = plan.target
	hp[target] -= plan.damage
	_log(
		"  %s %s %s hits %s for %d (%d HP)."
		% [
			PLAYER_NAMES[plan.from],
			label,
			dir_name(plan.dir),
			PLAYER_NAMES[target],
			plan.damage,
			hp[target],
		]
	)
	return fx


func _trace_ray(from_id: int, dir: Vector2i, max_range: int) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var cursor := positions[from_id]
	var target := -1
	for _i in max_range:
		cursor += dir
		if not in_bounds(cursor):
			break
		tiles.append(cursor)
		var who := player_at(cursor)
		if who >= 0:
			target = who
			break
	return {"target": target, "tiles": tiles}


func _eliminate_downed() -> void:
	var newly: Array[int] = []
	for i in PLAYER_COUNT:
		if alive[i] and hp[i] <= 0:
			newly.append(i)
	if newly.is_empty():
		return
	for i in newly:
		alive[i] = false
		hp[i] = mini(hp[i], 0)
	var names: PackedStringArray = PackedStringArray()
	for i in newly:
		names.append(PLAYER_NAMES[i])
	_log("  Eliminated: %s." % ", ".join(names))


func _record_center() -> void:
	last_center_occupants.clear()
	for id in living_ids():
		if is_center(positions[id]):
			last_center_occupants.append("%s@%s" % [PLAYER_NAMES[id], tile_name(positions[id])])


func _center_text() -> String:
	if last_center_occupants.is_empty():
		return "empty"
	return ", ".join(last_center_occupants)


func _priority_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id in priority:
		parts.append(PLAYER_NAMES[id])
	return " > ".join(parts)


func _program_text(actions: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for a in actions:
		parts.append("%s %s" % [kind_name(a.kind), dir_name(a.dir)])
	return " / ".join(parts)


func _log(line: String, slot: int = -999) -> void:
	var s := slot
	if s == -999:
		s = current_slot if phase == Phase.RESOLVING else -1
	log_lines.append(line)
	log_entries.append({
		"text": line,
		"slot": s,
		"round": round_index,
		"header": line.begins_with("Slot "),
	})


func clone_snapshot() -> Dictionary:
	return {
		"hp": hp.duplicate(),
		"positions": positions.duplicate(),
		"alive": alive.duplicate(),
		"priority": priority.duplicate(),
		"round_index": round_index,
		"phase": phase,
		"winners": winners.duplicate(),
	}
