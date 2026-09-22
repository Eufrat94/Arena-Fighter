class_name BoardView
extends Control

signal tile_hovered(pos: Vector2i)
signal move_dropped(dir: Vector2i)
signal ability_dropped(kind: int, dir: Vector2i)
signal drag_cancelled(reason: String)
signal plan_slot_clicked(slot: int)

const PAD_LEFT := 36.0
const PAD_TOP := 48.0
const PAD_RIGHT := 108.0
const PAD_BOTTOM := 24.0
const FX_LIFE := 0.85
const ABILITY_DRAG_MIN := 36.0
const ICON_R := 26.0
const TEX_FIST := preload("res://icons/fist.png")
const TEX_SHURIKEN := preload("res://icons/shuriken.png")
const CELL_MAX := 72.0
const CELL_MIN := 40.0

enum DragKind { NONE, TOKEN, SHURIKEN, PUNCH }

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
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
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
const ABILITY_ARROW := 70.0


func set_declare_context(active: bool, player_id: int, is_full: bool, steps: Array = [], origin_tile: Vector2i = Vector2i(-1, -1)) -> void:
	declare_active = active
	declare_player = player_id
	slots_full = is_full
	plan_steps = steps.duplicate(true) if active else []
	plan_origin = origin_tile if active else Vector2i(-1, -1)
	if not active and drag != DragKind.NONE:
		_cancel_drag("off")
	queue_redraw()


func _ghost_slot_at(local: Vector2) -> int:
	for step in plan_steps:
		var slot: int = int(step.slot)
		var kind: ArenaMatch.ActionKind = step.kind
		match kind:
			ArenaMatch.ActionKind.MOVE:
				if local.distance_to(cell_center(step.to)) <= 22.0:
					return slot
			ArenaMatch.ActionKind.PUNCH:
				var mid := cell_center(step.from).lerp(_clamped_point(step.from + step.dir), 0.5)
				if local.distance_to(mid) <= 18.0:
					return slot
			ArenaMatch.ActionKind.SHURIKEN:
				if local.distance_to(cell_center(step.from)) <= 16.0:
					return slot
				for t in step.tiles:
					if local.distance_to(cell_center(t)) <= 14.0:
						return slot
	return -1


func _plan_origin_tile() -> Vector2i:
	if plan_origin.x >= 0:
		return plan_origin
	if declare_player >= 0 and match_ref != null:
		return match_ref.positions[declare_player]
	return Vector2i(-1, -1)
	if plan_origin.x >= 0:
		return plan_origin
	if declare_player >= 0 and match_ref != null:
		return match_ref.positions[declare_player]
	return Vector2i(-1, -1)


func _shuriken_pos() -> Vector2:
	return Vector2(PAD_LEFT + cell * ArenaMatch.COLS + 54.0, PAD_TOP + 48.0)


func _punch_pos() -> Vector2:
	return Vector2(PAD_LEFT + cell * ArenaMatch.COLS + 54.0, PAD_TOP + cell * ArenaMatch.ROWS - 28.0)


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
	if on_origin:
		drag = DragKind.TOKEN
		ghost_tile = origin_tile
		drag_start = local
		set_process_input(true)
		queue_redraw()
		return
	if slots_full:
		full_t = 0.7
		drag_cancelled.emit("full")
		queue_redraw()
		return
	if local.distance_to(_shuriken_pos()) <= ICON_R + 8.0:
		drag = DragKind.SHURIKEN
		ability_from = _shuriken_pos()
		ability_dir = Vector2i.ZERO
		drag_pointer = local
		set_process_input(true)
		queue_redraw()
		return
	if local.distance_to(_punch_pos()) <= ICON_R + 8.0:
		drag = DragKind.PUNCH
		ability_from = _punch_pos()
		ability_dir = Vector2i.ZERO
		drag_pointer = local
		set_process_input(true)
		queue_redraw()


func _update_drag(local: Vector2) -> void:
	drag_pointer = local
	if drag == DragKind.TOKEN:
		ghost_tile = _cell_at(local)
	elif drag == DragKind.SHURIKEN or drag == DragKind.PUNCH:
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
	elif mode == DragKind.SHURIKEN or mode == DragKind.PUNCH:
		if ability_dir == Vector2i.ZERO:
			invalid_t = 0.35
			drag_cancelled.emit("short")
		else:
			var kind := ArenaMatch.ActionKind.SHURIKEN if mode == DragKind.SHURIKEN else ArenaMatch.ActionKind.PUNCH
			ability_dropped.emit(kind, ability_dir)
		ability_dir = Vector2i.ZERO
	queue_redraw()


func _cancel_drag(_reason: String) -> void:
	drag = DragKind.NONE
	ghost_tile = Vector2i(-1, -1)
	ability_dir = Vector2i.ZERO
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


func _clamped_point(pos: Vector2i) -> Vector2:
	var p := cell_center(pos)
	var grid := Rect2(origin(), Vector2(cell * ArenaMatch.COLS, cell * ArenaMatch.ROWS))
	return Vector2(
		clampf(p.x, grid.position.x + 8.0, grid.end.x - 8.0),
		clampf(p.y, grid.position.y + 8.0, grid.end.y - 8.0)
	)


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
	for x in ArenaMatch.COLS:
		draw_string(
			ThemeDB.fallback_font,
			orig + Vector2(x * cell + cell * 0.38, -22),
			ArenaMatch.COL_LETTERS[x],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color("d6c7a1")
		)
	for y in ArenaMatch.ROWS:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(8, orig.y + y * cell + cell * 0.55),
			str(y + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color("d6c7a1")
		)
	_draw_fx_under()
	for i in ArenaMatch.PLAYER_COUNT:
		if not match_ref.alive[i]:
			continue
		var p: Vector2i = match_ref.positions[i]
		var center := cell_center(p)
		if _should_shake(i):
			center += Vector2(sin(fx_time * 48.0) * 4.0, 0)
		var col: Color = PLAYER_COLORS[i]
		if drag == DragKind.TOKEN and i == declare_player:
			col.a = 0.45
		draw_circle(center, 22.0, col)
		draw_circle(center, 22.0, Color(0, 0, 0, 0.55), false, 2.0)
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
	_draw_plan_ghosts()
	_draw_ghost()
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
		var kind: ArenaMatch.ActionKind = step.kind
		match kind:
			ArenaMatch.ActionKind.MOVE:
				_draw_arrow(cell_center(step.from), cell_center(step.to), col, 2.4)
				var c := cell_center(step.to)
				draw_circle(c, 20.0, col)
				draw_circle(c, 20.0, Color(1, 1, 1, a), false, 1.6)
				_draw_slot_badge(c + Vector2(14, -18), slot + 1, col_base, a)
			ArenaMatch.ActionKind.SHURIKEN:
				var pts: Array[Vector2] = [cell_center(step.from)]
				for t in step.tiles:
					pts.append(cell_center(t))
				if pts.size() == 1:
					pts.append(_clamped_point(step.from + step.dir))
				for i in range(pts.size() - 1):
					_draw_dashed(pts[i], pts[i + 1], col, 6.0, 5.0, 1.8)
				_draw_slot_badge(pts[mini(1, pts.size() - 1)] + Vector2(8, -16), slot + 1, col_base, a)
			ArenaMatch.ActionKind.PUNCH:
				var a_pt := cell_center(step.from)
				var b_pt := _clamped_point(step.from + step.dir)
				var mid := a_pt.lerp(b_pt, 0.5)
				_draw_impact(mid, col)
				_draw_slot_badge(mid + Vector2(10, -16), slot + 1, col_base, a)
	if plan_origin.x >= 0 and plan_origin != match_ref.positions[declare_player] and drag != DragKind.TOKEN:
		var ring: Color = col_base
		ring.a = 0.85
		draw_circle(cell_center(plan_origin), 24.0, ring, false, 2.0)


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
	draw_circle(c, 22.0, col)
	draw_circle(c, 22.0, Color(1, 1, 1, 0.35), false, 2.0)


func _draw_ability_rail() -> void:
	var s := _shuriken_pos()
	var p := _punch_pos()
	var accent: Color = PLAYER_COLORS[declare_player] if declare_active and declare_player >= 0 else Color("8b93a7")
	var shuriken_mod := Color.WHITE if drag != DragKind.SHURIKEN else Color(1.15, 1.15, 1.15)
	var punch_mod := Color.WHITE if drag != DragKind.PUNCH else Color(1.15, 1.15, 1.15)
	draw_circle(s, ICON_R + 4.0, Color(0.12, 0.14, 0.18, 0.92))
	draw_circle(s, ICON_R + 4.0, accent, false, 2.0)
	_draw_icon_tex(TEX_SHURIKEN, s, 40.0, shuriken_mod)
	draw_string(ThemeDB.fallback_font, s + Vector2(-28, 44), "Shuriken", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c5c9d4"))
	draw_circle(p, ICON_R + 4.0, Color(0.12, 0.14, 0.18, 0.92))
	draw_circle(p, ICON_R + 4.0, accent, false, 2.0)
	_draw_icon_tex(TEX_FIST, p, 40.0, punch_mod)
	draw_string(ThemeDB.fallback_font, p + Vector2(-18, 44), "Punch", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c5c9d4"))


func _draw_icon_tex(tex: Texture2D, center: Vector2, px: float, modulate: Color = Color.WHITE) -> void:
	var r := Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px))
	draw_texture_rect(tex, r, false, modulate)


func _draw_ability_drag() -> void:
	if drag != DragKind.SHURIKEN and drag != DragKind.PUNCH:
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
		"move":
			_draw_move_fx(a)
		"shuriken":
			_draw_shuriken_fx(a)
		"punch":
			_draw_punch_fx(a)


func _draw_fx_over() -> void:
	var a := _fx_alpha()
	if a <= 0.0 or fx.is_empty():
		return
	var kind := str(fx.get("kind", ""))
	if kind == "shuriken" or kind == "punch":
		_draw_float_text(a)


func _draw_move_fx(a: float) -> void:
	var segs: Array = fx.get("segments", [])
	var ok: bool = fx.get("success", false)
	for seg in segs:
		var pid: int = int(seg.player)
		var col: Color = PLAYER_COLORS[pid]
		col.a = a
		var p0 := _clamped_point(seg.from)
		var p1 := _clamped_point(seg.to)
		if not ok:
			p1 = p0.lerp(p1, 0.55)
		_draw_arrow(p0, p1, col, 3.2)
		if not ok:
			_draw_block_mark(p1, col)


func _draw_shuriken_fx(a: float) -> void:
	var actor: int = int(fx.get("actor", 0))
	var col: Color = PLAYER_COLORS[actor]
	col.a = a
	var origin_pos: Vector2i = fx.get("origin", Vector2i.ZERO)
	var tiles: Array = fx.get("tiles", [])
	var pts: Array[Vector2] = [cell_center(origin_pos)]
	for t in tiles:
		pts.append(cell_center(t))
	if pts.size() == 1:
		var dir: Vector2i = fx.get("dir", Vector2i.ZERO)
		pts.append(_clamped_point(origin_pos + dir))
	for i in range(pts.size() - 1):
		_draw_dashed(pts[i], pts[i + 1], col, 7.0, 5.0, 2.0)
	var hit: int = int(fx.get("hit_player", -1))
	if hit >= 0 and tiles.size() > 0:
		_draw_shuriken_icon(cell_center(tiles[tiles.size() - 1]), col)
	else:
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
	_draw_impact(mid, col)
	if int(fx.get("hit_player", -1)) < 0:
		_draw_whiff_mark(mid + Vector2(0, -14), col)


func _draw_float_text(a: float) -> void:
	var hit: int = int(fx.get("hit_player", -1))
	if hit < 0:
		return
	var rise := -8.0 - fx_time * 18.0
	var pos: Vector2
	if match_ref.alive[hit]:
		pos = cell_center(match_ref.positions[hit]) + Vector2(18, -10 + rise)
	else:
		var tiles: Array = fx.get("tiles", [])
		if tiles.size() > 0:
			pos = cell_center(tiles[tiles.size() - 1]) + Vector2(16, rise)
		else:
			pos = cell_center(match_ref.positions[hit]) + Vector2(16, rise)
	var dmg: int = int(fx.get("damage", 0))
	draw_string(
		ThemeDB.fallback_font,
		pos,
		"-%d" % dmg,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(1.0, 0.83, 0.66, a)
	)


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


func _draw_shuriken_icon(at: Vector2, color: Color) -> void:
	var s := 11.0
	var pts := PackedVector2Array([
		at + Vector2(0, -s),
		at + Vector2(s * 0.35, -s * 0.35),
		at + Vector2(s, 0),
		at + Vector2(s * 0.35, s * 0.35),
		at + Vector2(0, s),
		at + Vector2(-s * 0.35, s * 0.35),
		at + Vector2(-s, 0),
		at + Vector2(-s * 0.35, -s * 0.35),
	])
	draw_colored_polygon(pts, color)
	draw_circle(at, 2.4, Color(0.08, 0.08, 0.1, color.a))


func _draw_impact(at: Vector2, color: Color) -> void:
	for i in 6:
		var ang := TAU * float(i) / 6.0 + 0.2
		var p1 := at + Vector2.from_angle(ang) * 5.0
		var p2 := at + Vector2.from_angle(ang) * 12.0
		draw_line(p1, p2, color, 2.4, true)
	draw_circle(at, 5.0, color)


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
