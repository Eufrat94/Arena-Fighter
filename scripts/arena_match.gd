class_name ArenaMatch
extends RefCounted

## 6x6 simultaneous 1-action turns. v3 experiment: 15s declare, ability cooldowns, XP 15.

const COLS := 6
const ROWS := 6
const START_HP := 20
const PLAYER_COUNT := 4
const SLOTS := 1
const SHURIKEN_DAMAGE := 2
const PUNCH_DAMAGE := 4
const HEAL_AMOUNT := 2
const FLYING_KICK_DAMAGE := 2
const FROST_DAMAGE := 1
const FIREBALL_DAMAGE := 3
const FIREBALL_SPLASH := 1
const XP_THRESHOLD := 15
const ABILITY_COOLDOWN := 3
const DECLARE_SECONDS := 15.0

enum ActionKind { MOVE, SHURIKEN, PUNCH, HEAL, FLYING_KICK, FROST_RING, FIREBALL, WINDWALL }
enum SpeedTier { INSTANT, NORMAL, SLOW }
enum Phase { DECLARE, REVEAL, RESOLVING, LEVEL_UP, MATCH_OVER }

const COL_LETTERS := ["A", "B", "C", "D", "E", "F"]
const PLAYER_NAMES := ["P1", "P2", "P3", "P4"]
const ACQUIRABLE := [ActionKind.HEAL, ActionKind.FLYING_KICK, ActionKind.FROST_RING, ActionKind.FIREBALL, ActionKind.WINDWALL]
const CLOCKWISE := [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

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
		ActionKind.HEAL:
			return "Heal"
		ActionKind.FLYING_KICK:
			return "Flying Kick"
		ActionKind.FROST_RING:
			return "Frost Ring"
		ActionKind.FIREBALL:
			return "Fireball"
		ActionKind.WINDWALL:
			return "Windwall"
		_:
			return "?"


static func kind_letter(kind: ActionKind) -> String:
	match kind:
		ActionKind.MOVE:
			return "M"
		ActionKind.SHURIKEN:
			return "S"
		ActionKind.PUNCH:
			return "P"
		ActionKind.HEAL:
			return "H"
		ActionKind.FLYING_KICK:
			return "K"
		ActionKind.FROST_RING:
			return "R"
		ActionKind.FIREBALL:
			return "F"
		ActionKind.WINDWALL:
			return "W"
		_:
			return "?"


static func speed_of(kind: ActionKind) -> SpeedTier:
	match kind:
		ActionKind.MOVE, ActionKind.WINDWALL:
			return SpeedTier.INSTANT
		ActionKind.SHURIKEN, ActionKind.HEAL:
			return SpeedTier.NORMAL
		_:
			return SpeedTier.SLOW


static func is_projectile(kind: ActionKind) -> bool:
	return kind == ActionKind.SHURIKEN or kind == ActionKind.FIREBALL


static func is_unlimited(kind: ActionKind) -> bool:
	return kind == ActionKind.MOVE


static func needs_aim(kind: ActionKind) -> bool:
	return kind != ActionKind.HEAL and kind != ActionKind.FROST_RING


static func projectile_damage(kind: ActionKind) -> int:
	match kind:
		ActionKind.FIREBALL:
			return FIREBALL_DAMAGE
		_:
			return SHURIKEN_DAMAGE


static func projectile_splash(kind: ActionKind) -> int:
	return FIREBALL_SPLASH if kind == ActionKind.FIREBALL else 0


static func adjacent_dirs(dir: Vector2i) -> Array[Vector2i]:
	var i := CLOCKWISE.find(dir)
	if i < 0:
		return []
	return [CLOCKWISE[(i + 7) % 8], CLOCKWISE[(i + 1) % 8]]


static func neighbors_8(pos: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in CLOCKWISE:
		var n: Vector2i = pos + d
		if in_bounds(n):
			out.append(n)
	return out


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func make_action(kind: ActionKind, dir: Vector2i = Vector2i.ZERO) -> Dictionary:
	return {"kind": kind, "dir": dir}


static func make_pass() -> Dictionary:
	return make_action(ActionKind.MOVE, Vector2i.ZERO)


static func is_pass(action: Dictionary) -> bool:
	return action.get("kind", -1) == ActionKind.MOVE and action.get("dir", Vector2i(-1, -1)) == Vector2i.ZERO


## Cardinal or diagonal step from `from` toward `to`, or ZERO if they are not on a ray.
static func line_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var d: Vector2i = to - from
	if d == Vector2i.ZERO:
		return Vector2i.ZERO
	var ax := absi(d.x)
	var ay := absi(d.y)
	if ax != 0 and ay != 0 and ax != ay:
		return Vector2i.ZERO
	return Vector2i(signi(d.x), signi(d.y))


var hp: Array[int] = []
var positions: Array[Vector2i] = []
var alive: Array[bool] = []
var priority: Array[int] = [] ## player ids, highest first
var round_index: int = 1
var phase: Phase = Phase.DECLARE
var current_slot: int = 0 ## 0..2 while resolving
var programs: Dictionary = {} ## player_id -> Array[Dictionary] of 1 action
var log_lines: PackedStringArray = PackedStringArray()
var log_entries: Array[Dictionary] = []
var last_center_occupants: PackedStringArray = PackedStringArray()
var winners: Array[int] = [] ## empty while match running
var xp: Array[int] = []
var owned: Array = [] ## player -> Array of ActionKind
var damaged_this_round: Array[bool] = []
var windwall_incoming: Array = [] ## player -> Array[Vector2i]
var rng := RandomNumberGenerator.new()
var level_queue: Array[int] = []
var level_offers: Array = []
var leveling_player: int = -1

var at_slot_boundary: bool = false
var awaiting_cleanup: bool = false
var current_speed: int = -1
var action_queue: Array[int] = []
var last_fx: Dictionary = {}
var auto_pick_level_ups := false
## Last successful one-tile step per player (move or push). Public, observed information.
var last_step_dir: Array[Vector2i] = []
## Last two round-end tiles per player. Public. Used to stop retreat oscillation.
var pos_history: Array = []
## player -> Dictionary ActionKind -> last turn index it was executed
var last_used_turn: Array = []


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
	xp.clear()
	owned.clear()
	damaged_this_round.clear()
	windwall_incoming.clear()
	level_queue.clear()
	level_offers.clear()
	leveling_player = -1
	last_step_dir.clear()
	pos_history.clear()
	last_used_turn.clear()
	_reset_step_state()
	rng.randomize()
	for i in PLAYER_COUNT:
		hp.append(START_HP)
		positions.append(START_POSITIONS[i])
		alive.append(true)
		priority.append(i)
		xp.append(0)
		owned.append([ActionKind.MOVE, ActionKind.SHURIKEN, ActionKind.PUNCH])
		damaged_this_round.append(false)
		windwall_incoming.append([])
		last_step_dir.append(Vector2i.ZERO)
		pos_history.append([])
		last_used_turn.append({})
	round_index = 1
	phase = Phase.DECLARE
	current_slot = 0
	_log("Match start. Priority %s." % _priority_text(), -1)


func _reset_step_state() -> void:
	at_slot_boundary = false
	awaiting_cleanup = false
	current_speed = -1
	action_queue.clear()
	last_fx = {}
	for i in PLAYER_COUNT:
		if i < windwall_incoming.size():
			windwall_incoming[i] = []


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


func owns(player_id: int, kind: ActionKind) -> bool:
	return owned[player_id].has(kind)


func unowned_acquirable(player_id: int) -> Array:
	var pool: Array = []
	for kind in ACQUIRABLE:
		if not owns(player_id, kind):
			pool.append(kind)
	return pool


func ability_ready(player_id: int, kind: ActionKind) -> bool:
	if is_unlimited(kind):
		return true
	if not owns(player_id, kind):
		return false
	var last: int = int(last_used_turn[player_id].get(kind, -ABILITY_COOLDOWN))
	return round_index - last >= ABILITY_COOLDOWN


func cooldown_left(player_id: int, kind: ActionKind) -> int:
	if ability_ready(player_id, kind):
		return 0
	var last: int = int(last_used_turn[player_id].get(kind, -ABILITY_COOLDOWN))
	return ABILITY_COOLDOWN - (round_index - last)


func submit_program(player_id: int, actions: Array) -> String:
	if phase != Phase.DECLARE:
		return "Not in declare phase."
	if player_id < 0 or player_id >= PLAYER_COUNT or not alive[player_id]:
		return "That player cannot declare."
	if actions.size() != SLOTS:
		return "Choose exactly 1 action."
	for a in actions:
		var err := validate_action(a)
		if err != "":
			return err
		var kind: ActionKind = a.kind
		if not owns(player_id, kind):
			return "You don't have %s yet." % kind_name(kind)
		if not ability_ready(player_id, kind):
			return "%s is on cooldown (%d turn(s) left)." % [kind_name(kind), cooldown_left(player_id, kind)]
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
	for i in PLAYER_COUNT:
		damaged_this_round[i] = false
	_log("--- Turn %d reveal ---" % round_index, -1)
	for id in living_ids():
		_log("%s: %s" % [PLAYER_NAMES[id], _program_text(programs[id])], -1)


func resolve_stage() -> String:
	if phase == Phase.REVEAL:
		return "reveal"
	if phase == Phase.LEVEL_UP:
		return "level_up"
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
			return "Playing turn"
		"end_of_round":
			return "Next — cleanup"
		"slot_boundary":
			return "Next"
		"mid_slot":
			var left := action_queue.size()
			if left > 0:
				return "Next — %d left this turn" % left
			return "Next"
		"level_up":
			return "Level up"
		_:
			return "Next"


func resolve_next_action() -> Dictionary:
	if phase == Phase.DECLARE or phase == Phase.MATCH_OVER or phase == Phase.LEVEL_UP:
		return {}
	if phase == Phase.REVEAL:
		phase = Phase.RESOLVING
		current_slot = 0
		_open_slot(0)
		return _step_action()
	if awaiting_cleanup:
		_cleanup_round()
		last_fx = {"kind": "cleanup", "slot": current_slot}
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
		if guard > 400:
			push_error("Resolution did not terminate.")
			break
	if auto_pick_level_ups:
		_auto_resolve_level_ups()


func _auto_resolve_level_ups() -> void:
	var guard := 0
	while phase == Phase.LEVEL_UP and not level_offers.is_empty():
		choose_level_up(level_offers[0])
		guard += 1
		if guard > 20:
			break


## Test helper: load programs for living players and fully resolve one round.
func play_programmed_round(by_player: Dictionary) -> void:
	programs.clear()
	phase = Phase.DECLARE
	_reset_step_state()
	auto_pick_level_ups = true
	for id in by_player.keys():
		if not alive[int(id)]:
			continue
		var err := submit_program(int(id), by_player[id])
		assert(err == "", err)
	begin_reveal()
	resolve_remaining_slots()
	auto_pick_level_ups = false


func _open_slot(slot: int) -> void:
	current_slot = slot
	current_speed = -1
	action_queue.clear()
	for i in PLAYER_COUNT:
		windwall_incoming[i] = []
	_log("Turn %d:" % round_index, slot)
	for speed in [SpeedTier.INSTANT, SpeedTier.NORMAL, SpeedTier.SLOW]:
		if _load_speed(speed):
			return


func _load_speed(speed: SpeedTier) -> bool:
	var actors: Array[int] = []
	for id in priority:
		if not alive[id] or not programs.has(id):
			continue
		var kind: ActionKind = programs[id][current_slot].kind
		if speed_of(kind) == speed:
			actors.append(id)
	if actors.is_empty():
		return false
	action_queue = actors
	current_speed = int(speed)
	return true


func _step_action() -> Dictionary:
	if action_queue.is_empty():
		_close_speed_and_advance()
		if action_queue.is_empty():
			last_fx = _slot_pause_fx()
			return last_fx
	var actor: int = action_queue.pop_front()
	var fx: Dictionary = _execute(actor, programs[actor][current_slot])
	fx["slot"] = current_slot
	fx["log_index"] = log_entries.size() - 1
	if action_queue.is_empty():
		_close_speed_and_advance()
	fx["more_in_slot"] = not action_queue.is_empty() and not at_slot_boundary and not awaiting_cleanup
	fx["at_slot_boundary"] = at_slot_boundary
	fx["awaiting_cleanup"] = awaiting_cleanup
	last_fx = fx
	return fx


func _close_speed_and_advance() -> void:
	_eliminate_downed()
	var start := current_speed + 1
	current_speed = -1
	action_queue.clear()
	for k in range(maxi(start, 0), 3):
		if _load_speed(k as SpeedTier):
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
	_record_position_history()
	_record_center()
	_award_xp()
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
	current_slot = 0
	_log("End of turn. Center: %s. Next priority %s." % [_center_text(), _priority_text()], -1)
	_reset_step_state()
	if not level_queue.is_empty():
		_present_next_level()
	else:
		phase = Phase.DECLARE


func _award_xp() -> void:
	level_queue.clear()
	for id in living_ids():
		var gained := 1
		var why: PackedStringArray = PackedStringArray(["alive"])
		if damaged_this_round[id]:
			gained += 1
			why.append("damaged")
		if is_center(positions[id]):
			gained += 1
			why.append("center")
		var before := xp[id]
		xp[id] += gained
		_log("  %s +%d XP (%s) → %d." % [PLAYER_NAMES[id], gained, ", ".join(why), xp[id]], -1)
		var before_lv := int(before / XP_THRESHOLD)
		var after_lv := int(xp[id] / XP_THRESHOLD)
		if after_lv > before_lv and not unowned_acquirable(id).is_empty():
			level_queue.append(id)


func _present_next_level() -> void:
	while not level_queue.is_empty():
		var id: int = level_queue.pop_front()
		if not alive[id]:
			continue
		var pool: Array = unowned_acquirable(id)
		if pool.is_empty():
			continue
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		leveling_player = id
		level_offers = pool.slice(0, mini(3, pool.size()))
		phase = Phase.LEVEL_UP
		_log("%s levels up — choose an ability." % PLAYER_NAMES[id], -1)
		return
	leveling_player = -1
	level_offers.clear()
	phase = Phase.DECLARE


func choose_level_up(kind: ActionKind) -> String:
	if phase != Phase.LEVEL_UP:
		return "Not leveling up."
	if not kind in level_offers:
		return "That ability is not on offer."
	if owns(leveling_player, kind):
		return "Already owned."
	owned[leveling_player].append(kind)
	_log("%s acquired %s." % [PLAYER_NAMES[leveling_player], kind_name(kind)], -1)
	_present_next_level()
	return ""


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
		match kind:
			ActionKind.MOVE, ActionKind.FLYING_KICK:
				var dest := pos + dir
				if in_bounds(dest):
					to = dest
					pos = dest
				if kind == ActionKind.FLYING_KICK:
					var beyond := pos + dir
					if in_bounds(beyond):
						tiles.append(beyond)
						hit = player_at(beyond)
						if hit == player_id:
							hit = -1
			ActionKind.SHURIKEN, ActionKind.FIREBALL:
				var traced := _preview_ray(from, dir, COLS + ROWS, player_id)
				tiles = traced.tiles
				hit = traced.target
			ActionKind.PUNCH, ActionKind.WINDWALL:
				var traced2 := _preview_ray(from, dir, 1, player_id)
				tiles = traced2.tiles
				hit = traced2.target
			ActionKind.FROST_RING:
				tiles = neighbors_8(from)
			ActionKind.HEAL:
				pass
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


func preview_ray(start: Vector2i, dir: Vector2i, max_range: int, ignore_id: int) -> Dictionary:
	return _preview_ray(start, dir, max_range, ignore_id)


func _note_step(player_id: int, dir: Vector2i) -> void:
	if player_id >= 0 and player_id < last_step_dir.size():
		last_step_dir[player_id] = dir


func _record_position_history() -> void:
	for i in PLAYER_COUNT:
		if i >= pos_history.size():
			continue
		var hist: Array = pos_history[i]
		hist.append(positions[i])
		while hist.size() > 2:
			hist.remove_at(0)
		pos_history[i] = hist


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
	if not action.has("kind"):
		return "Action needs kind."
	var kind: ActionKind = action.kind
	var dir: Vector2i = action.get("dir", Vector2i.ZERO)
	if kind == ActionKind.MOVE:
		if dir == Vector2i.ZERO:
			return ""
		if not is_orthogonal(dir):
			return "Move must be N/S/E/W."
		return ""
	if not needs_aim(kind):
		return ""
	if dir == Vector2i.ZERO:
		return "Direction required."
	if not dir in ALL_DIRS:
		return "Invalid aim direction."
	return ""


func _execute(actor: int, action: Dictionary) -> Dictionary:
	if not alive[actor]:
		return {"kind": "skip", "actor": actor}
	var kind: ActionKind = action.kind
	var dir: Vector2i = action.get("dir", Vector2i.ZERO)
	if not is_unlimited(kind):
		last_used_turn[actor][kind] = round_index
	match kind:
		ActionKind.MOVE:
			if dir == Vector2i.ZERO:
				return _apply_pass(actor)
			return _try_move(actor, dir, "Move")
		ActionKind.WINDWALL:
			return _apply_windwall(actor, dir)
		ActionKind.HEAL:
			return _apply_heal(actor)
		ActionKind.SHURIKEN, ActionKind.FIREBALL:
			return _fire_projectile(actor, positions[actor], dir, kind, 0)
		ActionKind.PUNCH:
			return _apply_melee(actor, dir, PUNCH_DAMAGE, "punch")
		ActionKind.FROST_RING:
			return _apply_frost(actor)
		ActionKind.FLYING_KICK:
			return _apply_flying_kick(actor, dir)
		_:
			return {"kind": "skip", "actor": actor}


func _apply_pass(actor: int) -> Dictionary:
	_log("  %s stays put." % PLAYER_NAMES[actor])
	return {
		"kind": "pass",
		"actor": actor,
		"origin": positions[actor],
		"success": true,
	}


func _try_move(mover: int, dir: Vector2i, verb: String = "Move") -> Dictionary:
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
		_log("  %s %s %s into wall — fail." % [PLAYER_NAMES[mover], verb, dir_name(dir)])
		return fx
	var occupant := player_at(dest)
	if occupant < 0:
		positions[mover] = dest
		fx["success"] = true
		fx["segments"] = [{"player": mover, "from": from, "to": dest}]
		_note_step(mover, dir)
		_log("  %s %s %s to %s." % [PLAYER_NAMES[mover], verb, dir_name(dir), tile_name(dest)])
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
			_log("  %s %s %s push chain hits wall — fail." % [PLAYER_NAMES[mover], verb, dir_name(dir)])
			return fx
	var segs_ok: Array = []
	for pid in chain:
		segs_ok.append({"player": pid, "from": positions[pid], "to": positions[pid] + dir})
	for i in range(chain.size() - 1, -1, -1):
		positions[chain[i]] = positions[chain[i]] + dir
	fx["success"] = true
	fx["segments"] = segs_ok
	for pid in chain:
		_note_step(pid, dir)
	var names: PackedStringArray = PackedStringArray()
	for i in range(1, chain.size()):
		var pid: int = chain[i]
		names.append("%s→%s" % [PLAYER_NAMES[pid], tile_name(positions[pid])])
	_log(
		"  %s %s %s to %s, push %s."
		% [PLAYER_NAMES[mover], verb, dir_name(dir), tile_name(positions[mover]), ", ".join(names)]
	)
	return fx


func _apply_windwall(actor: int, dir: Vector2i) -> Dictionary:
	var cover: Array[Vector2i] = [dir]
	for adj in adjacent_dirs(dir):
		cover.append(adj)
	windwall_incoming[actor] = cover
	var names: PackedStringArray = PackedStringArray()
	for d in cover:
		names.append(dir_name(d))
	_log("  %s Windwall covers incoming %s." % [PLAYER_NAMES[actor], ", ".join(names)])
	return {
		"kind": "windwall",
		"actor": actor,
		"dir": dir,
		"origin": positions[actor],
		"cover": cover,
		"success": true,
	}


func _apply_heal(actor: int) -> Dictionary:
	var before := hp[actor]
	hp[actor] = mini(START_HP, hp[actor] + HEAL_AMOUNT)
	var gained := hp[actor] - before
	_log("  %s Heal restores %d (%d HP)." % [PLAYER_NAMES[actor], gained, hp[actor]])
	return {
		"kind": "heal",
		"actor": actor,
		"origin": positions[actor],
		"healed": gained,
		"success": gained > 0,
	}


func _apply_frost(actor: int) -> Dictionary:
	var tiles := neighbors_8(positions[actor])
	var hits: Array[int] = []
	for t in tiles:
		var who := player_at(t)
		if who >= 0:
			_deal_damage(who, FROST_DAMAGE)
			hits.append(who)
	if hits.is_empty():
		_log("  %s Frost Ring — no one adjacent." % PLAYER_NAMES[actor])
	else:
		var names: PackedStringArray = PackedStringArray()
		for id in hits:
			names.append("%s (%d HP)" % [PLAYER_NAMES[id], hp[id]])
		_log("  %s Frost Ring hits %s." % [PLAYER_NAMES[actor], ", ".join(names)])
	return {
		"kind": "frost",
		"actor": actor,
		"origin": positions[actor],
		"tiles": tiles,
		"hits": hits,
		"damage": FROST_DAMAGE,
		"success": not hits.is_empty(),
	}


func _apply_melee(actor: int, dir: Vector2i, damage: int, fx_kind: String) -> Dictionary:
	var origin: Vector2i = positions[actor]
	var dest := origin + dir
	var target := player_at(dest) if in_bounds(dest) else -1
	var tiles: Array[Vector2i] = []
	if in_bounds(dest):
		tiles.append(dest)
	var fx := {
		"kind": fx_kind,
		"actor": actor,
		"dir": dir,
		"origin": origin,
		"tiles": tiles,
		"hit_player": target,
		"damage": damage,
		"success": target >= 0,
	}
	if target < 0:
		_log("  %s %s %s — whiff." % [PLAYER_NAMES[actor], kind_name(_kind_from_fx(fx_kind)), dir_name(dir)])
		return fx
	_deal_damage(target, damage)
	_log(
		"  %s %s %s hits %s for %d (%d HP)."
		% [PLAYER_NAMES[actor], kind_name(_kind_from_fx(fx_kind)), dir_name(dir), PLAYER_NAMES[target], damage, hp[target]]
	)
	return fx


func _kind_from_fx(fx_kind: String) -> ActionKind:
	match fx_kind:
		"punch":
			return ActionKind.PUNCH
		"kick":
			return ActionKind.FLYING_KICK
		_:
			return ActionKind.PUNCH


func _apply_flying_kick(actor: int, dir: Vector2i) -> Dictionary:
	var move_fx := _try_move(actor, dir, "Flying Kick")
	var origin: Vector2i = positions[actor]
	var dest := origin + dir
	var target := player_at(dest) if in_bounds(dest) else -1
	var tiles: Array[Vector2i] = []
	if in_bounds(dest):
		tiles.append(dest)
	if target >= 0:
		_deal_damage(target, FLYING_KICK_DAMAGE)
		_log(
			"  %s Flying Kick strikes %s for %d (%d HP)."
			% [PLAYER_NAMES[actor], PLAYER_NAMES[target], FLYING_KICK_DAMAGE, hp[target]]
		)
	move_fx["kind"] = "kick"
	move_fx["hit_player"] = target
	move_fx["damage"] = FLYING_KICK_DAMAGE
	move_fx["tiles"] = tiles
	move_fx["origin"] = origin
	return move_fx


func _blocks_projectile(player_id: int, travel: Vector2i) -> bool:
	var incoming: Vector2i = -travel
	var cover: Array = windwall_incoming[player_id]
	return incoming in cover


func _trace_ray_from(origin: Vector2i, dir: Vector2i, max_range: int = COLS + ROWS) -> Dictionary:
	var tiles: Array[Vector2i] = []
	var cursor := origin
	for _i in max_range:
		cursor += dir
		if not in_bounds(cursor):
			return {
				"target": -1,
				"tiles": tiles,
				"wall": true,
				"wall_tile": cursor,
				"stop": cursor - dir,
			}
		tiles.append(cursor)
		var who := player_at(cursor)
		if who >= 0:
			return {
				"target": who,
				"tiles": tiles,
				"wall": false,
				"wall_tile": cursor,
				"stop": cursor,
			}
	return {
		"target": -1,
		"tiles": tiles,
		"wall": false,
		"wall_tile": cursor,
		"stop": cursor,
	}


func _fire_projectile(actor: int, origin: Vector2i, dir: Vector2i, kind: ActionKind, bounce: int) -> Dictionary:
	var dmg := projectile_damage(kind)
	var splash := projectile_splash(kind)
	var traced := _trace_ray_from(origin, dir)
	var fx_name := "fireball" if kind == ActionKind.FIREBALL else "shuriken"
	if bounce > 12:
		_log("  Projectile fizzles after too many reflections.")
		return {
			"kind": fx_name,
			"actor": actor,
			"dir": dir,
			"origin": origin,
			"tiles": [],
			"hit_player": -1,
			"damage": dmg,
			"success": false,
		}
	var target: int = traced.target
	if target >= 0 and _blocks_projectile(target, dir):
		_log(
			"  %s %s blocked by %s Windwall — reflected %s."
			% [PLAYER_NAMES[actor], kind_name(kind), PLAYER_NAMES[target], dir_name(-dir)]
		)
		return _fire_projectile(target, positions[target], -dir, kind, bounce + 1)
	var splash_hits: Array[int] = []
	if target >= 0:
		_deal_damage(target, dmg)
		_log(
			"  %s %s %s hits %s for %d (%d HP)."
			% [PLAYER_NAMES[actor], kind_name(kind), dir_name(dir), PLAYER_NAMES[target], dmg, hp[target]]
		)
	else:
		_log("  %s %s %s — whiff." % [PLAYER_NAMES[actor], kind_name(kind), dir_name(dir)])
	if splash > 0:
		var center: Vector2i = traced.wall_tile if traced.wall else traced.stop
		for id in living_ids():
			if id == target:
				continue
			if chebyshev(positions[id], center) <= 1:
				_deal_damage(id, splash)
				splash_hits.append(id)
		if not splash_hits.is_empty():
			var names: PackedStringArray = PackedStringArray()
			for id in splash_hits:
				names.append("%s (%d HP)" % [PLAYER_NAMES[id], hp[id]])
			_log("  %s splash hits %s." % [kind_name(kind), ", ".join(names)])
	return {
		"kind": fx_name,
		"actor": actor,
		"dir": dir,
		"origin": origin,
		"tiles": traced.tiles,
		"hit_player": target,
		"damage": dmg,
		"splash_hits": splash_hits,
		"success": target >= 0 or not splash_hits.is_empty(),
	}


func _deal_damage(target: int, amount: int) -> void:
	if not alive[target] or amount <= 0:
		return
	hp[target] -= amount
	damaged_this_round[target] = true


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
		if is_pass(a):
			parts.append("Pass")
		elif needs_aim(a.kind) and a.dir != Vector2i.ZERO:
			parts.append("%s %s" % [kind_name(a.kind), dir_name(a.dir)])
		else:
			parts.append(kind_name(a.kind))
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
		"xp": xp.duplicate(),
	}
