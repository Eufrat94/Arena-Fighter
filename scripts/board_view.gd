class_name BoardView
extends Control

signal tile_hovered(pos: Vector2i)
signal move_dropped(dir: Vector2i)
signal ability_dropped(kind: int, dir: Vector2i)
signal ability_clicked(kind: int)
signal drag_cancelled(reason: String)
signal plan_slot_clicked(slot: int)
signal armed_changed(kind: int)

const PAD_LEFT := 100.0
const PAD_TOP := 100.0
const PAD_RIGHT := 92.0
const PAD_BOTTOM := 100.0
const FX_LIFE := 0.85
const MOVE_TRAVEL := 0.45
const PUSH_IMPACT_AT := 0.62
const PUSH_IMPACT_LIFE := 0.14
const ABILITY_DRAG_MIN := 36.0
const ICON_R := 24.0
const RAIL_OFFSET := 56.0
const RAIL_SPACING := 58.0
const TEX_FIST := preload("res://icons/fist.png")
const TEX_SHURIKEN := preload("res://icons/shuriken.png")
const TEX_FOOT := preload("res://icons/foot.png")
const TEX_KICK := preload("res://icons/kick.png")
const TEX_FROST := preload("res://icons/circle.png")
const TEX_FIREBALL := preload("res://icons/fireball.png")
const TEX_WINDWALL := preload("res://icons/windwall.png")
const TEX_HEAL := preload("res://icons/heal.png")
const TEX_SPEAR := preload("res://icons/spear.png")
const CELL_MAX := 100.0
const CELL_MIN := 56.0

enum DragKind { NONE, TOKEN, ABILITY }

var cell := CELL_MAX
var match_ref: ArenaMatch
var hover := Vector2i(-1, -1)
var fx: Dictionary = {}
var fx_time := 0.0

var declare_active := false
var declare_player := -1
var slots_full := false

var drag := DragKind.NONE
var ghost_tile := Vector2i(-1, -1)
var ability_dir := Vector2i.ZERO
var ability_from := Vector2.ZERO
var drag_pointer := Vector2.ZERO
var invalid_t := 0.0
var full_t := 0.0
var drag_start := Vector2.ZERO

const PLAYER_COLORS := [
	Color("e85d4c"),
	Color("2ec4b6"),
	Color("f4a261"),
	Color("9b72cf"),
]


func _ready() -> void:
	custom_minimum_size = Vector2(
		PAD_LEFT + CELL_MIN * ArenaMatch.COLS + PAD_RIGHT,
		PAD_TOP + CELL_MIN * ArenaMatch.ROWS + PAD_BOTTOM
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	set_process(true)
	resized.connect(_on_resized)


func _on_resized() -> void:
	var avail_w := size.x - PAD_LEFT - PAD_RIGHT
	var avail_h := size.y - PAD_TOP - PAD_BOTTOM
	cell = clampf(minf(avail_w / float(ArenaMatch.COLS), avail_h / float(ArenaMatch.ROWS)), CELL_MIN, CELL_MAX)
	queue_redraw()


func play_fx(data: Dictionary) -> void:
	fx = data.duplicate(true)
	fx_time = 0.0
	queue_redraw()


func clear_fx() -> void:
	fx.clear()
	queue_redraw()


var plan_steps: Array = []
var plan_origin := Vector2i(-1, -1)
var used_kinds: Array = []
var drag_ability: int = -1
var armed_kind: int = -1
var hover_aim_dir := Vector2i.ZERO
const ABILITY_ARROW := 70.0


func set_declare_context(active: bool, player_id: int, is_full: bool, steps: Array = [], origin_tile: Vector2i = Vector2i(-1, -1), used: Array = []) -> void:
	var prev_player := declare_player
	declare_active = active
	declare_player = player_id
	slots_full = is_full
	plan_steps = steps.duplicate(true) if active else []
	plan_origin = origin_tile if active else Vector2i(-1, -1)
	used_kinds = used.duplicate() if active else []
	if not active:
		if drag != DragKind.NONE:
			_cancel_drag("off")
		clear_arm()
	elif prev_player != player_id:
		clear_arm()
	queue_redraw()


func arm_ability(kind: int) -> bool:
	if not declare_active or declare_player < 0:
		return false
	if used_kinds.has(kind) and not ArenaMatch.is_unlimited(kind as ArenaMatch.ActionKind):
		return false
	if drag != DragKind.NONE:
		_cancel_drag("rearm")
	if armed_kind != kind:
		armed_kind = kind
		armed_changed.emit(kind)
	hover_aim_dir = _snap_aim(get_local_mouse_position())
	queue_redraw()
	return true


func clear_arm() -> void:
	if armed_kind < 0:
		hover_aim_dir = Vector2i.ZERO
		return
	armed_kind = -1
	hover_aim_dir = Vector2i.ZERO
	armed_changed.emit(-1)
	queue_redraw()


func _current_armed() -> int:
	if drag == DragKind.TOKEN:
		return int(ArenaMatch.ActionKind.MOVE)
	if drag == DragKind.ABILITY:
		return drag_ability
	return armed_kind


func _set_armed(kind: int) -> void:
	if armed_kind != kind:
		armed_kind = kind
		armed_changed.emit(kind)
	hover_aim_dir = _snap_aim(get_local_mouse_position())


func _ghost_slot_at(local: Vector2) -> int:
	for step in plan_steps:
		var slot: int = int(step.slot)
		var kind: ArenaMatch.ActionKind = step.kind
		match kind:
			ArenaMatch.ActionKind.MOVE:
				if local.distance_to(cell_center(step.to)) <= 22.0:
					return slot
			ArenaMatch.ActionKind.PUNCH, ArenaMatch.ActionKind.FLYING_KICK, ArenaMatch.ActionKind.WINDWALL, ArenaMatch.ActionKind.SPEAR_STRIKE:
				var mid := cell_center(step.from).lerp(_clamped_point(step.from + step.dir), 0.5)
				if local.distance_to(mid) <= 18.0:
					return slot
			ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.ActionKind.FIREBALL:
				if local.distance_to(cell_center(step.from)) <= 16.0:
					return slot
				for t in step.tiles:
					if local.distance_to(cell_center(t)) <= 14.0:
						return slot
			ArenaMatch.ActionKind.FROST_RING, ArenaMatch.ActionKind.HEAL:
				if local.distance_to(cell_center(step.from)) <= 20.0:
					return slot
	return -1


func _plan_origin_tile() -> Vector2i:
	if plan_origin.x >= 0:
		return plan_origin
	if declare_player >= 0 and match_ref != null:
		return match_ref.positions[declare_player]
	return Vector2i(-1, -1)


func _rail_kinds() -> Array:
	return _rail_kinds_for(declare_player)


func _rail_kinds_for(player_id: int) -> Array:
	if match_ref == null or player_id < 0 or player_id >= match_ref.owned.size():
		return [ArenaMatch.ActionKind.MOVE, ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.ActionKind.PUNCH]
	return match_ref.owned[player_id].duplicate()


func _rail_pos(index: int) -> Vector2:
	return _rail_pos_for(declare_player, index)


func _rail_spacing_for(player_id: int) -> float:
	var n := maxi(_rail_kinds_for(player_id).size(), 1)
	var along := cell * float(ArenaMatch.COLS)
	if player_id == 1 or player_id == 3:
		along = cell * float(ArenaMatch.ROWS)
	if n <= 1:
		return RAIL_SPACING
	return minf(RAIL_SPACING, maxf(44.0, (along - 8.0) / float(n - 1)))


func _rail_pos_for(player_id: int, index: int) -> Vector2:
	var n := maxi(_rail_kinds_for(player_id).size(), 1)
	var spacing := _rail_spacing_for(player_id)
	var total := spacing * float(n - 1)
	var grid := Rect2(origin(), Vector2(cell * float(ArenaMatch.COLS), cell * float(ArenaMatch.ROWS)))
	match player_id:
		1:
			var x := grid.end.x + RAIL_OFFSET
			var start_y := grid.position.y + grid.size.y * 0.5 - total * 0.5
			return Vector2(x, start_y + float(index) * spacing)
		2:
			var start_x := grid.position.x + grid.size.x * 0.5 - total * 0.5
			var y := grid.position.y - RAIL_OFFSET
			return Vector2(start_x + float(index) * spacing, y)
		3:
			var x := grid.position.x - RAIL_OFFSET
			var start_y := grid.position.y + grid.size.y * 0.5 - total * 0.5
			return Vector2(x, start_y + float(index) * spacing)
		_:
			var start_x := grid.position.x + grid.size.x * 0.5 - total * 0.5
			var y := grid.end.y + RAIL_OFFSET
			return Vector2(start_x + float(index) * spacing, y)


func _shuriken_pos() -> Vector2:
	return _rail_pos(0)


func _punch_pos() -> Vector2:
	return _rail_pos(1)


func _process(delta: float) -> void:
	var dirty := false
	if not fx.is_empty():
		fx_time += delta
		dirty = true
	if invalid_t > 0.0:
		invalid_t = maxf(0.0, invalid_t - delta)
		dirty = true
	if full_t > 0.0:
		full_t = maxf(0.0, full_t - delta)
		dirty = true
	if drag != DragKind.NONE:
		dirty = true
	if dirty:
		queue_redraw()


func _fx_alpha() -> float:
	if fx.is_empty():
		return 0.0
	if fx_time < 0.45:
		return 1.0
	return clampf(1.0 - (fx_time - 0.45) / (FX_LIFE - 0.45), 0.0, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var pos := _cell_at(event.position)
		if pos != hover:
			hover = pos
			tile_hovered.emit(pos)
		if drag != DragKind.NONE:
			_update_drag(event.position)
		elif _current_armed() >= 0:
			hover_aim_dir = _snap_aim(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_begin_drag(event.position)
		elif drag != DragKind.NONE:
			_finish_drag(event.position)


func _input(event: InputEvent) -> void:
	if drag == DragKind.NONE:
		return
	if event is InputEventMouseMotion:
		_update_drag(get_local_mouse_position())
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_drag(get_local_mouse_position())
		get_viewport().set_input_as_handled()


func _try_begin_drag(local: Vector2) -> void:
	if not declare_active or declare_player < 0 or match_ref == null:
		return
	if not match_ref.alive[declare_player]:
		return
	var ghost_slot := _ghost_slot_at(local)
	var origin_tile := _plan_origin_tile()
	var origin_c := cell_center(origin_tile)
	var real_c := cell_center(match_ref.positions[declare_player])
	var on_origin := local.distance_to(origin_c) <= 24.0 or local.distance_to(real_c) <= 24.0
	if ghost_slot >= 0 and not on_origin:
		plan_slot_clicked.emit(ghost_slot)
		return
	var kinds := _rail_kinds_for(declare_player)
	for i in kinds.size():
		if local.distance_to(_rail_pos_for(declare_player, i)) <= ICON_R + 8.0:
			var kind: ArenaMatch.ActionKind = kinds[i]
			if used_kinds.has(kind) and not ArenaMatch.is_unlimited(kind):
				full_t = 0.4
				drag_cancelled.emit("cooldown")
				queue_redraw()
				return
			drag = DragKind.ABILITY
			drag_ability = int(kind)
			_set_armed(int(kind))
			ability_from = _rail_pos_for(declare_player, i)
			ability_dir = Vector2i.ZERO
			drag_pointer = local
			set_process_input(true)
			queue_redraw()
			return
	if _try_commit_armed(local):
		return
	if on_origin:
		if armed_kind >= 0 and armed_kind != int(ArenaMatch.ActionKind.MOVE):
			return
		drag = DragKind.TOKEN
		_set_armed(int(ArenaMatch.ActionKind.MOVE))
		ghost_tile = origin_tile
		drag_start = local
		set_process_input(true)
		queue_redraw()
		return
	if slots_full:
		full_t = 0.7
		drag_cancelled.emit("full")
		queue_redraw()


func _update_drag(local: Vector2) -> void:
	drag_pointer = local
	if drag == DragKind.TOKEN:
		ghost_tile = _cell_at(local)
	elif drag == DragKind.ABILITY:
		var delta := local - ability_from
		if delta.length() >= ABILITY_DRAG_MIN:
			ability_dir = _octant_dir(delta)
		else:
			ability_dir = Vector2i.ZERO


func _finish_drag(local: Vector2) -> void:
	_update_drag(local)
	var mode := drag
	drag = DragKind.NONE
	set_process_input(false)
	if mode == DragKind.TOKEN:
		var origin: Vector2i = _plan_origin_tile()
		var dest := ghost_tile
		ghost_tile = Vector2i(-1, -1)
		var delta := dest - origin
		if ArenaMatch.in_bounds(dest) and ArenaMatch.is_orthogonal(delta) and delta.length_squared() == 1:
			move_dropped.emit(delta)
		else:
			if local.distance_to(drag_start) < 10.0:
				var gs := _ghost_slot_at(drag_start)
				if gs >= 0:
					plan_slot_clicked.emit(gs)
					queue_redraw()
					return
			invalid_t = 0.4
			drag_cancelled.emit("invalid_move")
	elif mode == DragKind.ABILITY:
		var kind: ArenaMatch.ActionKind = drag_ability as ArenaMatch.ActionKind
		if not ArenaMatch.needs_aim(kind):
			ability_clicked.emit(kind)
		elif ability_dir == Vector2i.ZERO:
			invalid_t = 0.35
			drag_cancelled.emit("short")
		else:
			var dir := ability_dir
			if kind == ArenaMatch.ActionKind.MOVE:
				dir = _orthogonal_dir(dir)
				if dir == Vector2i.ZERO:
					invalid_t = 0.35
					drag_cancelled.emit("invalid_move")
				else:
					move_dropped.emit(dir)
			else:
				ability_dropped.emit(kind, dir)
		ability_dir = Vector2i.ZERO
		drag_ability = -1
	queue_redraw()


func _try_commit_armed(local: Vector2) -> bool:
	var kind := _current_armed()
	if kind < 0:
		return false
	var origin := _plan_origin_tile()
	if origin.x < 0:
		return false
	var tile := _cell_at(local)
	var akind: ArenaMatch.ActionKind = kind as ArenaMatch.ActionKind
	if not ArenaMatch.needs_aim(akind):
		if tile.x >= 0:
			ability_clicked.emit(akind)
			return true
		return false
	var origin_c := cell_center(origin)
	if local.distance_to(origin_c) <= 24.0:
		return false
	var dir := _snap_aim(local)
	if dir == Vector2i.ZERO:
		return false
	hover_aim_dir = dir
	if akind == ArenaMatch.ActionKind.MOVE:
		move_dropped.emit(dir)
	else:
		ability_dropped.emit(akind, dir)
	return true


func _cancel_drag(_reason: String) -> void:
	drag = DragKind.NONE
	ghost_tile = Vector2i(-1, -1)
	ability_dir = Vector2i.ZERO
	drag_ability = -1
	set_process_input(false)
	queue_redraw()


func _octant_dir(v: Vector2) -> Vector2i:
	var oct := wrapi(int(round(v.angle() / (PI * 0.25))), 0, 8)
	var table := [
		ArenaMatch.DIR_E,
		ArenaMatch.DIR_SE,
		ArenaMatch.DIR_S,
		ArenaMatch.DIR_SW,
		ArenaMatch.DIR_W,
		ArenaMatch.DIR_NW,
		ArenaMatch.DIR_N,
		ArenaMatch.DIR_NE,
	]
	return table[oct]


func _orthogonal_dir(dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(dir.x) >= absi(dir.y):
		return Vector2i(signi(dir.x), 0)
	return Vector2i(0, signi(dir.y))


func _current_aim_dir() -> Vector2i:
	if drag == DragKind.TOKEN:
		var origin := _plan_origin_tile()
		var delta := ghost_tile - origin
		if ArenaMatch.in_bounds(ghost_tile) and ArenaMatch.is_orthogonal(delta) and delta.length_squared() == 1:
			return delta
		return Vector2i.ZERO
	if drag == DragKind.ABILITY:
		var kind: ArenaMatch.ActionKind = drag_ability as ArenaMatch.ActionKind
		if kind == ArenaMatch.ActionKind.MOVE:
			var dir := _orthogonal_dir(ability_dir)
			var dest := _plan_origin_tile() + dir
			if dir != Vector2i.ZERO and ArenaMatch.in_bounds(dest):
				return dir
			return Vector2i.ZERO
		return ability_dir
	return hover_aim_dir


func _snap_aim(local: Vector2) -> Vector2i:
	var origin := _plan_origin_tile()
	if origin.x < 0:
		return Vector2i.ZERO
	var kind := _current_armed()
	if kind < 0:
		return Vector2i.ZERO
	var akind: ArenaMatch.ActionKind = kind as ArenaMatch.ActionKind
	if not ArenaMatch.needs_aim(akind):
		return Vector2i.ZERO
	var origin_c := cell_center(origin)
	var delta := local - origin_c
	if akind == ArenaMatch.ActionKind.MOVE:
		var tile := _cell_at(local)
		if tile in ArenaMatch.move_destinations(origin):
			return tile - origin
		if delta.length() >= 8.0:
			var dir := _orthogonal_dir(_octant_dir(delta))
			if dir != Vector2i.ZERO and ArenaMatch.in_bounds(origin + dir):
				return dir
		var best := Vector2i.ZERO
		var best_d := INF
		for t in ArenaMatch.move_destinations(origin):
			var d := local.distance_squared_to(cell_center(t))
			if d < best_d:
				best_d = d
				best = t - origin
		return best
	if delta.length() < cell * 0.22:
		return hover_aim_dir
	return _octant_dir(delta)


func _cell_at(local: Vector2) -> Vector2i:
	var x := int((local.x - PAD_LEFT) / cell)
	var y := int((local.y - PAD_TOP) / cell)
	var pos := Vector2i(x, y)
	if ArenaMatch.in_bounds(pos):
		return pos
	return Vector2i(-1, -1)


func origin() -> Vector2:
	return Vector2(PAD_LEFT, PAD_TOP)


func cell_center(pos: Vector2i) -> Vector2:
	return origin() + Vector2(pos) * cell + Vector2(cell, cell) * 0.5


func _token_r() -> float:
	return clampf(cell * 0.30, 20.0, 34.0)


func _clamped_point(pos: Vector2i) -> Vector2:
	var p := cell_center(pos)
	var grid := _grid_rect()
	return Vector2(
		clampf(p.x, grid.position.x + 8.0, grid.end.x - 8.0),
		clampf(p.y, grid.position.y + 8.0, grid.end.y - 8.0)
	)


func _grid_rect() -> Rect2:
	return Rect2(origin(), Vector2(cell * float(ArenaMatch.COLS), cell * float(ArenaMatch.ROWS)))


func _ray_exit(from: Vector2i, dir: Vector2i) -> Vector2:
	var grid := _grid_rect()
	return ArenaMatch.ray_rect_exit(cell_center(from), dir, grid.position, grid.end)


func _ray_points(from: Vector2i, dir: Vector2i, tiles: Array, hit_target: bool) -> Array[Vector2]:
	var pts: Array[Vector2] = [cell_center(from)]
	for t in tiles:
		pts.append(cell_center(t))
	if hit_target:
		return pts
	var exit_pt := _ray_exit(from, dir)
	if pts[pts.size() - 1].distance_to(exit_pt) > 1.5:
		pts.append(exit_pt)
	return pts


func _move_travel_t() -> float:
	return clampf(fx_time / MOVE_TRAVEL, 0.0, 1.0)


func _motion_seg_for(player_id: int) -> Dictionary:
	if fx.is_empty():
		return {}
	var kind := str(fx.get("kind", ""))
	if kind != "move" and kind != "kick" and kind != "instant_free":
		return {}
	var default_ok: bool = fx.get("success", false)
	for seg in fx.get("segments", []):
		if int(seg.player) != player_id:
			continue
		if not bool(seg.get("ok", default_ok)):
			return {}
		return seg
	return {}


func _pre_push_center(player_id: int) -> Vector2:
	var default_ok: bool = fx.get("success", true)
	for seg in fx.get("segments", []):
		if int(seg.player) != player_id:
			continue
		if bool(seg.get("ok", default_ok)):
			return _clamped_point(seg.to)
	for seg in fx.get("pending_push", []):
		if int(seg.player) != player_id:
			continue
		if bool(seg.get("ok", true)):
			return _clamped_point(seg.from)
	return cell_center(match_ref.positions[player_id])


func _token_visual(player_id: int) -> Dictionary:
	var rest := cell_center(match_ref.positions[player_id])
	var out := {"center": rest, "scale": Vector2.ONE}
	if bool(fx.get("pre_push_hold", false)) or str(fx.get("kind", "")) == "setup":
		out.center = _pre_push_center(player_id)
		return out
	var seg := _motion_seg_for(player_id)
	if seg.is_empty():
		return out
	var p0 := _clamped_point(seg.from)
	var p1 := _clamped_point(seg.to)
	var t := _move_travel_t()
	if bool(seg.get("pushed", false)):
		out.center = _pushed_center(p0, p1, t)
		out.scale = _pushed_scale(t)
	elif bool(fx.get("has_push", false)):
		if t <= PUSH_IMPACT_AT:
			var u := t / PUSH_IMPACT_AT
			u = 1.0 - (1.0 - u) * (1.0 - u)
			out.center = p0.lerp(p1, u)
		else:
			out.center = p1
	return out


func _pushed_center(p0: Vector2, p1: Vector2, t: float) -> Vector2:
	var v := p1 - p0
	var n := v.normalized() if v.length() > 0.5 else Vector2.ZERO
	if t <= PUSH_IMPACT_AT:
		var u := t / PUSH_IMPACT_AT
		u = 1.0 - (1.0 - u) * (1.0 - u)
		return p0.lerp(p1, u)
	var bounce_t := (t - PUSH_IMPACT_AT) / maxf(1.0 - PUSH_IMPACT_AT, 0.001)
	var overshoot := sin(bounce_t * PI) * 11.0
	return p1 + n * overshoot


func _pushed_scale(t: float) -> Vector2:
	if t < PUSH_IMPACT_AT or t >= 1.0:
		return Vector2.ONE
	var bounce_t := (t - PUSH_IMPACT_AT) / maxf(1.0 - PUSH_IMPACT_AT, 0.001)
	var squash := sin(bounce_t * PI)
	return Vector2(1.0 + squash * 0.22, 1.0 - squash * 0.18)


func _draw_push_impacts() -> void:
	if fx.is_empty() or not bool(fx.get("success", false)):
		return
	var t := _move_travel_t()
	if t < PUSH_IMPACT_AT:
		return
	var age := fx_time - MOVE_TRAVEL * PUSH_IMPACT_AT
	if age > PUSH_IMPACT_LIFE:
		return
	var fade := 1.0 - clampf(age / PUSH_IMPACT_LIFE, 0.0, 1.0)
	var default_ok: bool = fx.get("success", false)
	for seg in fx.get("segments", []):
		if not bool(seg.get("pushed", false)):
			continue
		if not bool(seg.get("ok", default_ok)):
			continue
		_draw_impact_burst(_clamped_point(seg.from), fade)


func _draw() -> void:
	if match_ref == null:
		return
	var orig := origin()
	var origin_tile := Vector2i(-1, -1)
	if declare_active and declare_player >= 0 and match_ref.alive[declare_player]:
		origin_tile = _plan_origin_tile()
	for y in ArenaMatch.ROWS:
		for x in ArenaMatch.COLS:
			var pos := Vector2i(x, y)
			var r := Rect2(orig + Vector2(x, y) * cell, Vector2(cell, cell))
			var bg := Color("1a1d24")
			if ArenaMatch.is_center(pos):
				bg = Color("2a2430")
			if (x + y) % 2 == 0:
				bg = bg.lightened(0.04)
			if drag == DragKind.TOKEN and origin_tile.x >= 0:
				var d := pos - origin_tile
				if ArenaMatch.is_orthogonal(d) and d.length_squared() == 1:
					bg = bg.lerp(PLAYER_COLORS[declare_player], 0.28)
			if pos == hover:
				bg = bg.lightened(0.08)
			draw_rect(r, bg)
			draw_rect(r, Color("3d4454"), false, 1.0)
			draw_string(
				ThemeDB.fallback_font,
				r.position + Vector2(6, 16),
				ArenaMatch.tile_name(pos),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				Color("6b7385")
			)
	_draw_fx_under()
	for i in ArenaMatch.PLAYER_COUNT:
		if not match_ref.alive[i]:
			continue
		var visual := _token_visual(i)
		var center: Vector2 = visual.center
		if _should_shake(i):
			center += Vector2(sin(fx_time * 48.0) * 4.0, 0)
		var col: Color = PLAYER_COLORS[i]
		if drag == DragKind.TOKEN and i == declare_player:
			col.a = 0.45
		var scale: Vector2 = visual.scale
		draw_set_transform(center, 0.0, scale)
		draw_circle(Vector2.ZERO, _token_r(), col)
		draw_circle(Vector2.ZERO, _token_r(), Color(0, 0, 0, 0.55), false, 2.0)
		draw_set_transform(Vector2.ZERO)
		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-12, 6),
			ArenaMatch.PLAYER_NAMES[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color.WHITE
		)
		_draw_hp_chip(i, center)
		_draw_windwall_cover(i, center)
	_draw_plan_ghosts()
	_draw_ghost()
	_draw_legal_shadows()
	_draw_hover_ghost()
	_draw_ability_rail()
	_draw_ability_drag()
	_draw_fx_over()
	if full_t > 0.0:
		var a := clampf(full_t / 0.7, 0.0, 1.0)
		draw_string(
			ThemeDB.fallback_font,
			origin() + Vector2(80, -8),
			"all actions set",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(1, 0.85, 0.55, a)
		)
	if invalid_t > 0.0 and drag == DragKind.NONE:
		var a2 := clampf(invalid_t / 0.4, 0.0, 1.0)
		draw_string(
			ThemeDB.fallback_font,
			origin() + Vector2(200, -8),
			"invalid drop",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(1.0, 0.45, 0.4, a2)
		)


func _draw_plan_ghosts() -> void:
	if not declare_active or declare_player < 0:
		return
	var col_base: Color = PLAYER_COLORS[declare_player]
	for step in plan_steps:
		var slot: int = int(step.slot)
		var a := 0.34 + float(slot) * 0.18
		var col: Color = col_base
		col.a = a
		_draw_plan_step(step, col, a, true)
	if plan_origin.x >= 0 and plan_origin != match_ref.positions[declare_player] and drag != DragKind.TOKEN:
		var ring: Color = col_base
		ring.a = 0.85
		draw_circle(cell_center(plan_origin), 24.0, ring, false, 2.0)


func _draw_hover_ghost() -> void:
	if not declare_active or declare_player < 0 or match_ref == null:
		return
	var kind := _current_armed()
	if kind < 0:
		return
	var akind: ArenaMatch.ActionKind = kind as ArenaMatch.ActionKind
	if not ArenaMatch.needs_aim(akind):
		return
	if drag == DragKind.TOKEN:
		return
	var dir := _current_aim_dir()
	if dir == Vector2i.ZERO:
		return
	var preview: Dictionary = match_ref.declare_preview(
		declare_player,
		[ArenaMatch.make_action(akind, dir)]
	)
	var steps: Array = preview.get("steps", [])
	if steps.is_empty():
		return
	var col: Color = PLAYER_COLORS[declare_player]
	col.a = 0.62
	_draw_plan_step(steps[0], col, 0.62, false)


func _draw_plan_step(step: Dictionary, col: Color, a: float, show_badge: bool) -> void:
	var kind: ArenaMatch.ActionKind = step.kind
	var col_base: Color = PLAYER_COLORS[declare_player] if declare_player >= 0 else col
	var slot: int = int(step.get("slot", 0))
	match kind:
		ArenaMatch.ActionKind.MOVE:
			_draw_arrow(cell_center(step.from), cell_center(step.to), col, 2.4)
			var c := cell_center(step.to)
			draw_circle(c, _token_r(), col)
			draw_circle(c, _token_r(), Color(1, 1, 1, a), false, 1.6)
			if show_badge:
				_draw_slot_badge(c + Vector2(14, -18), slot + 1, col_base, a)
		ArenaMatch.ActionKind.FLYING_KICK:
			_draw_arrow(cell_center(step.from), cell_center(step.to), col, 2.4)
			var land := cell_center(step.to)
			draw_circle(land, _token_r(), col)
			draw_circle(land, _token_r(), Color(1, 1, 1, a), false, 1.6)
			var beyond_tiles: Array = step.get("tiles", [])
			if not beyond_tiles.is_empty():
				var strike: Vector2i = beyond_tiles[0]
				_draw_icon_tex(TEX_KICK, cell_center(strike), 30.0, col)
			if show_badge:
				_draw_slot_badge(land + Vector2(14, -18), slot + 1, col_base, a)
		ArenaMatch.ActionKind.SHURIKEN, ArenaMatch.ActionKind.FIREBALL:
			var pts := _ray_points(step.from, step.dir, step.tiles, int(step.get("hit", -1)) >= 0)
			for i in range(pts.size() - 1):
				_draw_dashed(pts[i], pts[i + 1], col, 6.0, 5.0, 1.8)
			var tip := pts[pts.size() - 1]
			if kind == ArenaMatch.ActionKind.FIREBALL:
				_draw_icon_tex(TEX_FIREBALL, tip, 26.0, col)
			else:
				_draw_icon_tex(TEX_SHURIKEN, tip, 22.0, col)
			if show_badge:
				_draw_slot_badge(tip + Vector2(8, -16), slot + 1, col_base, a)
		ArenaMatch.ActionKind.PUNCH:
			var a_pt := cell_center(step.from)
			var dest: Vector2i = step.from + step.dir
			var b_pt := cell_center(dest) if ArenaMatch.in_bounds(dest) else _clamped_point(dest)
			var fist_at := a_pt.lerp(b_pt, 0.72)
			_draw_icon_tex_rotated(TEX_FIST, fist_at, 30.0, col, _fist_rotation(step.dir))
			if show_badge:
				_draw_slot_badge(fist_at + Vector2(10, -16), slot + 1, col_base, a)
		ArenaMatch.ActionKind.WINDWALL:
			_draw_windwall_aim(cell_center(step.from), step.dir, col)
			if show_badge:
				var mid := cell_center(step.from).lerp(_clamped_point(step.from + step.dir), 0.5)
				_draw_slot_badge(mid + Vector2(10, -16), slot + 1, col_base, a)
		ArenaMatch.ActionKind.SPEAR_STRIKE:
			var tiles: Array = step.get("tiles", [])
			var prev := cell_center(step.from)
			for t in tiles:
				var c := cell_center(t)
				_draw_dashed(prev, c, col, 6.0, 4.0, 1.8)
				prev = c
			if not tiles.is_empty():
				var tip: Vector2i = tiles[tiles.size() - 1]
				_draw_icon_tex_rotated(TEX_SPEAR, cell_center(tip), 30.0, col, _spear_rotation(step.dir))
				if show_badge:
					_draw_slot_badge(cell_center(tip) + Vector2(10, -16), slot + 1, col_base, a)
		ArenaMatch.ActionKind.FROST_RING:
			_draw_icon_tex(TEX_FROST, cell_center(step.from), 32.0, col)
			for t in step.tiles:
				draw_circle(cell_center(t), 10.0, col, false, 1.4)
			if show_badge:
				_draw_slot_badge(cell_center(step.from) + Vector2(16, -16), slot + 1, col_base, a)
		ArenaMatch.ActionKind.HEAL:
			_draw_icon_tex(TEX_HEAL, cell_center(step.from), 32.0, col)
			if show_badge:
				_draw_slot_badge(cell_center(step.from) + Vector2(16, -22), slot + 1, col_base, a)


func _draw_windwall_aim(token_center: Vector2, dir: Vector2i, col: Color) -> void:
	var cover: Array[Vector2i] = [dir]
	for adj in ArenaMatch.adjacent_dirs(dir):
		cover.append(adj)
	_draw_barrier_lines(token_center, cover, col)
	_draw_icon_tex(TEX_WINDWALL, token_center + Vector2(0, -_token_r() - 16.0), 20.0, col)


func _draw_slot_badge(at: Vector2, n: int, col: Color, a: float) -> void:
	var bg := Color(0.08, 0.09, 0.11, clampf(a + 0.25, 0.0, 0.9))
	draw_circle(at, 9.0, bg)
	var label_c := col
	label_c.a = 1.0
	draw_string(ThemeDB.fallback_font, at + Vector2(-4, 5), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_c)


func _draw_ghost() -> void:
	if drag != DragKind.TOKEN or declare_player < 0:
		return
	var origin_tile: Vector2i = _plan_origin_tile()
	var dest := ghost_tile
	var valid := ArenaMatch.in_bounds(dest) and ArenaMatch.is_orthogonal(dest - origin_tile) and (dest - origin_tile).length_squared() == 1
	if not ArenaMatch.in_bounds(dest):
		return
	var col: Color = PLAYER_COLORS[declare_player]
	if valid:
		col.a = 0.5
	else:
		col = Color(0.95, 0.25, 0.22, 0.4)
	var c := cell_center(dest)
	draw_circle(c, _token_r(), col)
	draw_circle(c, _token_r(), Color(1, 1, 1, 0.35), false, 2.0)


func _draw_ability_rail() -> void:
	if match_ref == null:
		return
	for pid in ArenaMatch.PLAYER_COUNT:
		_draw_player_rail(pid)


func _draw_player_rail(player_id: int) -> void:
	var accent: Color = PLAYER_COLORS[player_id]
	var kinds := _rail_kinds_for(player_id)
	if kinds.is_empty():
		return
	var interactive := declare_active and player_id == declare_player
	var armed := _current_armed() if interactive else -1
	var alive := match_ref.alive[player_id]
	var tag := _rail_pos_for(player_id, 0)
	_draw_rail_stats(player_id, tag, accent, alive)
	for i in kinds.size():
		var kind: ArenaMatch.ActionKind = kinds[i]
		var s := _rail_pos_for(player_id, i)
		var cd := 0
		if not ArenaMatch.is_unlimited(kind):
			cd = match_ref.cooldown_left(player_id, kind)
		var spent := cd > 0 or not alive
		var selected := interactive and armed == int(kind)
		var mod := Color(1.15, 1.15, 1.15) if selected else Color.WHITE
		if spent:
			mod = Color(0.55, 0.55, 0.58)
		if not alive:
			mod.a = 0.45
		draw_circle(s, ICON_R + 4.0, Color(0.12, 0.14, 0.18, 0.92))
		var ring := accent.darkened(0.25) if spent else accent
		var ring_w := 3.2 if selected and not spent else 2.0
		draw_circle(s, ICON_R + 4.0, ring, false, ring_w)
		_draw_kind_icon(kind, s, 36.0, mod)
		if interactive:
			var key_col := Color("8b93a7") if spent else Color("e8dcc4")
			draw_string(
				ThemeDB.fallback_font,
				s + Vector2(-8, -ICON_R - 8),
				str(i + 1),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				13,
				key_col
			)
		if player_id == 0 or player_id == 2:
			draw_string(
				ThemeDB.fallback_font,
				s + Vector2(-36, 40),
				ArenaMatch.kind_name(kind),
				HORIZONTAL_ALIGNMENT_CENTER,
				72,
				10,
				Color("8b93a7") if spent else Color("c5c9d4")
			)
		if cd > 0:
			_draw_cd_badge(s, cd)


func _draw_rail_stats(player_id: int, first_icon: Vector2, accent: Color, alive: bool) -> void:
	var name_col := accent if alive else Color("6b7385")
	var info_col := Color("c5c9d4") if alive else Color("6b7385")
	var rail_name: String = ArenaMatch.PLAYER_NAMES[player_id]
	var info := "eliminated"
	if alive and match_ref != null:
		info = "HP %d   XP %d" % [match_ref.hp[player_id], match_ref.xp[player_id]]
	var pos := first_icon + Vector2(-78, -8)
	if player_id == 1 or player_id == 3:
		pos = first_icon + Vector2(-16, -ICON_R - 34)
	draw_string(ThemeDB.fallback_font, pos, rail_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, name_col)
	draw_string(ThemeDB.fallback_font, pos + Vector2(0, 14), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, info_col)


func _draw_cd_badge(icon_center: Vector2, turns: int) -> void:
	var text := str(turns)
	var font := ThemeDB.fallback_font
	var font_px := 12
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var chip := Vector2(maxf(tw + 8.0, 16.0), 14.0)
	var pos := icon_center + Vector2(6.0, 8.0)
	draw_rect(Rect2(pos, chip), Color(0.05, 0.06, 0.08, 0.9), true, -1.0, true)
	draw_rect(Rect2(pos, chip), Color("f4a261"), false, 1.0, true)
	draw_string(
		font,
		pos + Vector2((chip.x - tw) * 0.5, 11),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_px,
		Color("f2efe8")
	)


func _draw_legal_shadows() -> void:
	if not declare_active or declare_player < 0:
		return
	var kind := _current_armed()
	if kind < 0:
		return
	var origin := _plan_origin_tile()
	if origin.x < 0:
		return
	var accent: Color = PLAYER_COLORS[declare_player]
	var akind: ArenaMatch.ActionKind = kind as ArenaMatch.ActionKind
	var aim := _current_aim_dir()
	if akind == ArenaMatch.ActionKind.MOVE:
		for t in ArenaMatch.move_destinations(origin):
			_draw_shadow_tile(t, accent, t - origin == aim)
		return
	if not ArenaMatch.needs_aim(akind):
		var c := cell_center(origin)
		var ring: Color = accent
		ring.a = 0.55
		draw_circle(c, _token_r() + 8.0, ring, false, 2.0)
		return
	for d in ArenaMatch.ALL_DIRS:
		var dest: Vector2i = origin + d
		if ArenaMatch.in_bounds(dest):
			_draw_shadow_tile(dest, accent, d == aim)
		else:
			var pt := _clamped_point(dest)
			var col: Color = accent
			col.a = 0.28 if d == aim else 0.12
			draw_circle(pt, 7.0, col, false, 1.2)


func _draw_shadow_tile(pos: Vector2i, accent: Color, active: bool) -> void:
	var r := Rect2(origin() + Vector2(pos) * cell + Vector2(6, 6), Vector2(cell - 12.0, cell - 12.0))
	var fill: Color = accent
	fill.a = 0.10 if active else 0.04
	var edge: Color = accent
	edge.a = 0.38 if active else 0.14
	draw_rect(r, fill, true, -1.0, true)
	draw_rect(r, edge, false, 1.0, true)


func _draw_kind_icon(kind: ArenaMatch.ActionKind, center: Vector2, px: float, modulate: Color = Color.WHITE) -> void:
	var tex := _tex_for_kind(kind)
	if tex:
		_draw_icon_tex(tex, center, px, modulate)
		return
	var col := modulate
	draw_circle(center, px * 0.38, Color(0.18, 0.2, 0.24, col.a))
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-6, 6),
		ArenaMatch.kind_letter(kind),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		col
	)


func _tex_for_kind(kind: ArenaMatch.ActionKind) -> Texture2D:
	match kind:
		ArenaMatch.ActionKind.MOVE:
			return TEX_FOOT
		ArenaMatch.ActionKind.SHURIKEN:
			return TEX_SHURIKEN
		ArenaMatch.ActionKind.PUNCH:
			return TEX_FIST
		ArenaMatch.ActionKind.FLYING_KICK:
			return TEX_KICK
		ArenaMatch.ActionKind.FROST_RING:
			return TEX_FROST
		ArenaMatch.ActionKind.FIREBALL:
			return TEX_FIREBALL
		ArenaMatch.ActionKind.WINDWALL:
			return TEX_WINDWALL
		ArenaMatch.ActionKind.HEAL:
			return TEX_HEAL
		ArenaMatch.ActionKind.SPEAR_STRIKE:
			return TEX_SPEAR
		_:
			return null


func _draw_icon_tex(tex: Texture2D, center: Vector2, px: float, modulate: Color = Color.WHITE) -> void:
	var r := Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px))
	draw_texture_rect(tex, r, false, modulate)


func _draw_icon_tex_rotated(tex: Texture2D, center: Vector2, px: float, modulate: Color, rot: float) -> void:
	draw_set_transform(center, rot, Vector2.ONE)
	var r := Rect2(Vector2(-px, -px) * 0.5, Vector2(px, px))
	draw_texture_rect(tex, r, false, modulate)
	draw_set_transform(Vector2.ZERO)


## fist.png points north (knuckles up, wrist down). Godot 2D angles are clockwise from +X.
func _fist_rotation(dir: Vector2i) -> float:
	if dir == Vector2i.ZERO:
		return 0.0
	return Vector2(dir).angle() + PI * 0.5


## spear.png points southeast by default.
func _spear_rotation(dir: Vector2i) -> float:
	if dir == Vector2i.ZERO:
		return 0.0
	return Vector2(dir).angle() - Vector2(1, 1).angle()


func _draw_ability_drag() -> void:
	if drag != DragKind.ABILITY:
		return
	var col: Color = PLAYER_COLORS[declare_player] if declare_player >= 0 else Color.WHITE
	if ability_dir == Vector2i.ZERO:
		col = Color(0.7, 0.72, 0.78, 0.7)
		draw_line(ability_from, drag_pointer, col, 2.0, true)
		return
	var tip := ability_from + Vector2(ability_dir) * ABILITY_ARROW
	_draw_arrow(ability_from, tip, col, 3.4)
	draw_string(
		ThemeDB.fallback_font,
		tip + Vector2(6, -6),
		ArenaMatch.dir_name(ability_dir),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		col
	)


func _should_shake(player_id: int) -> bool:
	if fx.is_empty() or fx_time > 0.4:
		return false
	if str(fx.get("kind", "")) != "move":
		return false
	if fx.get("success", true):
		return false
	return int(fx.get("actor", -1)) == player_id


func _draw_hp_chip(player_id: int, token_center: Vector2) -> void:
	var text := str(match_ref.hp[player_id])
	var font := ThemeDB.fallback_font
	var font_px := 13
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var chip := Vector2(maxf(tw + 12.0, 28.0), 16.0)
	var pos := token_center + Vector2(-chip.x * 0.5, -40.0)
	var bounds := Rect2(Vector2(2, 2), self.size - Vector2(4, 4))
	pos.x = clampf(pos.x, bounds.position.x, bounds.end.x - chip.x)
	pos.y = clampf(pos.y, bounds.position.y, bounds.end.y - chip.y)
	draw_rect(Rect2(pos, chip), Color(0.05, 0.06, 0.08, 0.88), true, -1.0, true)
	draw_rect(Rect2(pos, chip), PLAYER_COLORS[player_id], false, 1.0, true)
	draw_string(
		font,
		pos + Vector2((chip.x - tw) * 0.5, 13),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_px,
		Color("f2efe8")
	)


func _draw_fx_under() -> void:
	var a := _fx_alpha()
	if a <= 0.0 or fx.is_empty():
		return
	var kind := str(fx.get("kind", ""))
	match kind:
		"move", "kick":
			_draw_move_fx(a)
		"instant_free":
			_draw_move_fx(a)
		"shuriken":
			_draw_shuriken_fx(a)
		"fireball":
			_draw_fireball_fx(a)
		"punch":
			_draw_punch_fx(a)
		"spear":
			_draw_spear_fx(a)
		"frost":
			_draw_frost_fx(a)
		"heal":
			_draw_heal_fx(a)
		"windwall":
			_draw_windwall_fx(a)
		"setup":
			pass


func _draw_fx_over() -> void:
	var a := _fx_alpha()
	if a <= 0.0 or fx.is_empty():
		return
	var kind := str(fx.get("kind", ""))
	if kind == "shuriken" or kind == "punch" or kind == "fireball" or kind == "kick" or kind == "frost" or kind == "spear":
		_draw_float_text(a)
	if (kind == "move" or kind == "kick" or kind == "instant_free") and bool(fx.get("has_push", false)):
		_draw_push_impacts()


func _draw_move_fx(a: float) -> void:
	var segs: Array = fx.get("segments", [])
	var default_ok: bool = fx.get("success", false)
	for seg in segs:
		var pid: int = int(seg.player)
		var col: Color = PLAYER_COLORS[pid]
		var ok: bool = bool(seg.get("ok", default_ok))
		col.a = a * (0.28 if ok else 1.0)
		var p0 := _clamped_point(seg.from)
		var p1 := _clamped_point(seg.to)
		if not ok:
			p1 = p0.lerp(p1, 0.55)
		_draw_arrow(p0, p1, col, 2.4 if ok else 3.2)
		if not ok:
			_draw_block_mark(p1, col)
	if str(fx.get("kind", "")) == "kick":
		var origin_pos: Vector2i = fx.get("origin", Vector2i.ZERO)
		var tint: Color = PLAYER_COLORS[int(fx.get("actor", 0))]
		tint = tint.lerp(Color.WHITE, 0.18)
		tint.a = a
		_draw_icon_tex(TEX_KICK, cell_center(origin_pos), 32.0, tint)


func _projectile_path() -> Array[Vector2]:
	var origin_pos: Vector2i = fx.get("origin", Vector2i.ZERO)
	var dir: Vector2i = fx.get("dir", Vector2i.ZERO)
	var tiles: Array = fx.get("tiles", [])
	var hit := int(fx.get("hit_player", -1)) >= 0 or bool(fx.get("blocked", false))
	return _ray_points(origin_pos, dir, tiles, hit)


func _projectile_travel() -> float:
	var pts := _projectile_path()
	var path_len := 0.0
	for i in range(pts.size() - 1):
		path_len += pts[i].distance_to(pts[i + 1])
	var travel_dur := clampf(0.22 + path_len / maxf(cell, 1.0) * 0.05, 0.24, 0.38)
	return clampf(fx_time / travel_dur, 0.0, 1.0)


func _point_along(pts: Array[Vector2], t: float) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() == 1 or t <= 0.0:
		return pts[0]
	if t >= 1.0:
		return pts[pts.size() - 1]
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	if total <= 1.0:
		return pts[0].lerp(pts[pts.size() - 1], t)
	var remain := total * t
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if remain <= seg or i == pts.size() - 2:
			return pts[i].lerp(pts[i + 1], remain / maxf(seg, 0.001))
		remain -= seg
	return pts[pts.size() - 1]


func _draw_shuriken_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var col: Color = PLAYER_COLORS[actor]
	col.a = a
	var pts := _projectile_path()
	for i in range(pts.size() - 1):
		_draw_dashed(pts[i], pts[i + 1], col, 7.0, 5.0, 2.0)
	var travel := _projectile_travel()
	var at := _point_along(pts, travel)
	var spin := travel * TAU * 2.6
	var tint := col.lerp(Color.WHITE, 0.22)
	tint.a = a
	_draw_icon_tex_rotated(TEX_SHURIKEN, at, 30.0, tint, spin)
	if int(fx.get("hit_player", -1)) < 0 and not bool(fx.get("blocked", false)) and travel >= 1.0:
		_draw_whiff_mark(pts[pts.size() - 1], col)


func _draw_fireball_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var col: Color = PLAYER_COLORS[actor]
	col.a = a
	var pts := _projectile_path()
	for i in range(pts.size() - 1):
		_draw_dashed(pts[i], pts[i + 1], col, 7.0, 5.0, 2.0)
	var travel := _projectile_travel()
	var at := _point_along(pts, travel)
	var tint := col.lerp(Color.WHITE, 0.18)
	tint.a = a
	_draw_icon_tex(TEX_FIREBALL, at, 32.0, tint)
	if int(fx.get("hit_player", -1)) < 0 and not bool(fx.get("blocked", false)) and travel >= 1.0:
		_draw_whiff_mark(pts[pts.size() - 1], col)


func _draw_punch_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var col: Color = PLAYER_COLORS[actor]
	col.a = a
	var origin_pos: Vector2i = fx.get("origin", Vector2i.ZERO)
	var dir: Vector2i = fx.get("dir", Vector2i.ZERO)
	var a_pt := cell_center(origin_pos)
	var b_pt := _clamped_point(origin_pos + dir)
	var mid := a_pt.lerp(b_pt, 0.5)
	var tint := col.lerp(Color.WHITE, 0.18)
	tint.a = a
	var pop := clampf(fx_time / 0.12, 0.0, 1.0)
	_draw_icon_tex_rotated(TEX_FIST, mid, lerpf(22.0, 34.0, pop), tint, _fist_rotation(dir))
	if int(fx.get("hit_player", -1)) < 0:
		_draw_whiff_mark(mid + Vector2(0, -18), col)


func _draw_spear_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var col: Color = PLAYER_COLORS[actor]
	col.a = a
	var origin_pos: Vector2i = fx.get("origin", Vector2i.ZERO)
	var dir: Vector2i = fx.get("dir", Vector2i.ZERO)
	var tiles: Array = fx.get("tiles", [])
	var prev := cell_center(origin_pos)
	for t in tiles:
		var c := cell_center(t)
		_draw_dashed(prev, c, col, 7.0, 4.0, 2.0)
		prev = c
	var tint := col.lerp(Color.WHITE, 0.18)
	tint.a = a
	var pop := clampf(fx_time / 0.12, 0.0, 1.0)
	var tip := prev
	_draw_icon_tex_rotated(TEX_SPEAR, tip, lerpf(24.0, 36.0, pop), tint, _spear_rotation(dir))
	if fx.get("hits", []).is_empty() and int(fx.get("hit_player", -1)) < 0:
		_draw_whiff_mark(tip + Vector2(0, -18), col)


func _draw_heal_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var col: Color = PLAYER_COLORS[actor]
	var origin_pos: Vector2i = fx.get("origin", match_ref.positions[actor] if match_ref else Vector2i.ZERO)
	var tint: Color = col.lerp(Color.WHITE, 0.18)
	tint.a = a
	var pop := clampf(fx_time / 0.12, 0.0, 1.0)
	_draw_icon_tex(TEX_HEAL, cell_center(origin_pos), lerpf(24.0, 36.0, pop), tint)


func _draw_frost_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var col: Color = PLAYER_COLORS[actor]
	col.a = a
	var origin_pos: Vector2i = fx.get("origin", match_ref.positions[actor] if match_ref else Vector2i.ZERO)
	var tint: Color = col.lerp(Color.WHITE, 0.18)
	tint.a = a
	_draw_icon_tex(TEX_FROST, cell_center(origin_pos), 36.0, tint)
	draw_circle(cell_center(origin_pos), cell * 0.95, col, false, 2.0)
	for t in fx.get("tiles", []):
		draw_circle(cell_center(t), 8.0, col, false, 1.6)


func _draw_windwall_cover(player_id: int, token_center: Vector2) -> void:
	if match_ref == null or player_id < 0 or player_id >= match_ref.windwall_incoming.size():
		return
	var cover: Array = match_ref.windwall_incoming[player_id]
	if cover.is_empty():
		return
	var jitter := _wall_impact_jitter(player_id)
	var col := Color(1.0, 1.0, 1.0, 0.92)
	_draw_icon_tex(TEX_WINDWALL, token_center + Vector2(0, -_token_r() - 14.0) + jitter, 22.0, Color(1, 1, 1, 0.95))
	_draw_barrier_lines(token_center + jitter, cover, col)


func _draw_barrier_lines(token_center: Vector2, cover: Array, col: Color) -> void:
	var edge := _token_r() + 7.0
	var half := clampf(cell * 0.26, 13.0, 20.0)
	for d in cover:
		var n := Vector2(d).normalized()
		if n.length() < 0.1:
			continue
		var mid := token_center + n * edge
		var perp := Vector2(-n.y, n.x)
		draw_line(mid - perp * half, mid + perp * half, col, 2.8, true)


func _wall_impact_jitter(player_id: int) -> Vector2:
	if fx.is_empty() or not bool(fx.get("blocked", false)):
		return Vector2.ZERO
	if int(fx.get("wall_player", fx.get("hit_player", -1))) != player_id:
		return Vector2.ZERO
	if _projectile_travel() < 1.0:
		return Vector2.ZERO
	var t := fx_time
	return Vector2(sin(t * 92.0), cos(t * 78.0)) * 2.4


func _draw_windwall_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var origin_pos: Vector2i = fx.get("origin", Vector2i.ZERO)
	_draw_windwall_cover(actor, cell_center(origin_pos))
	var col := Color(1.0, 1.0, 1.0, a)
	draw_circle(cell_center(origin_pos), _token_r() + 20.0, col, false, 1.0)


func _draw_float_text(a: float) -> void:
	if bool(fx.get("blocked", false)):
		return
	var hits: Array = fx.get("hits", [])
	if hits.is_empty():
		var hit: int = int(fx.get("hit_player", -1))
		if hit >= 0:
			hits = [hit]
	if hits.is_empty():
		return
	var rise := -8.0 - fx_time * 18.0
	var dmg: int = int(fx.get("damage", 0))
	var i := 0
	for hid in hits:
		var who: int = int(hid)
		var pos: Vector2
		if who >= 0 and who < match_ref.alive.size() and match_ref.alive[who]:
			pos = cell_center(match_ref.positions[who]) + Vector2(18, -10 + rise)
		else:
			var tiles: Array = fx.get("tiles", [])
			if i < tiles.size():
				pos = cell_center(tiles[i]) + Vector2(16, rise)
			elif tiles.size() > 0:
				pos = cell_center(tiles[tiles.size() - 1]) + Vector2(16, rise)
			else:
				pos = Vector2.ZERO
		draw_string(
			ThemeDB.fallback_font,
			pos,
			"-%d" % dmg,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(1.0, 0.83, 0.66, a)
		)
		i += 1


func _draw_arrow(p0: Vector2, p1: Vector2, color: Color, width: float) -> void:
	draw_line(p0, p1, color, width, true)
	var v := p1 - p0
	if v.length() < 4.0:
		return
	var n := v.normalized()
	var left := p1 - n.rotated(0.7) * 10.0
	var right := p1 - n.rotated(-0.7) * 10.0
	draw_line(p1, left, color, width, true)
	draw_line(p1, right, color, width, true)


func _draw_dashed(p0: Vector2, p1: Vector2, color: Color, dash: float, gap: float, width: float) -> void:
	var v := p1 - p0
	var length := v.length()
	if length < 1.0:
		return
	var n := v / length
	var dist := 0.0
	var draw_on := true
	while dist < length:
		var step := dash if draw_on else gap
		var a := p0 + n * dist
		var b := p0 + n * minf(dist + step, length)
		if draw_on:
			draw_line(a, b, color, width, true)
		dist += step
		draw_on = not draw_on


func _draw_block_mark(at: Vector2, color: Color) -> void:
	var s := 7.0
	draw_line(at + Vector2(-s, -s), at + Vector2(s, s), color, 2.2, true)
	draw_line(at + Vector2(s, -s), at + Vector2(-s, s), color, 2.2, true)


func _draw_impact(at: Vector2, color: Color) -> void:
	for i in 6:
		var ang := TAU * float(i) / 6.0 + 0.2
		var p1 := at + Vector2.from_angle(ang) * 5.0
		var p2 := at + Vector2.from_angle(ang) * 12.0
		draw_line(p1, p2, color, 2.4, true)
	draw_circle(at, 5.0, color)


func _draw_impact_burst(at: Vector2, fade: float) -> void:
	var col := Color(1.0, 0.93, 0.72, fade)
	var pop := 1.0 + (1.0 - fade) * 0.45
	draw_circle(at, 5.0 * pop, Color(1.0, 1.0, 1.0, fade * 0.55))
	for i in 7:
		var ang := TAU * float(i) / 7.0 + fade * 0.4
		var p1 := at + Vector2.from_angle(ang) * 4.0 * pop
		var p2 := at + Vector2.from_angle(ang) * 13.0 * pop
		draw_line(p1, p2, col, 2.0, true)


func _draw_whiff_mark(at: Vector2, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font,
		at + Vector2(-18, -8),
		"whiff",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		color
	)
