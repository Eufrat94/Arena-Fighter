class_name PlanBar
extends Control

signal slot_clicked(index: int)
signal submit_pressed

const R := 32.0
const GAP := 14.0
const SUBMIT_W := 132.0
const SUBMIT_H := 48.0
const ICON_SIZE := 36.0

const TEX_FOOT := preload("res://icons/foot.png")
const TEX_FIST := preload("res://icons/fist.png")
const TEX_SHURIKEN := preload("res://icons/shuriken.png")

var player_id: int = 0
var draft: Array = []
var accent := Color("e85d4c")
var can_submit := false

const PLAYER_COLORS := [
	Color("e85d4c"),
	Color("2ec4b6"),
	Color("f4a261"),
	Color("9b72cf"),
]


func _ready() -> void:
	custom_minimum_size = Vector2(SUBMIT_W + 12.0, R * 6.0 + GAP * 4.0 + SUBMIT_H + 28.0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_plan(pid: int, slots: Array, submit_ok: bool) -> void:
	player_id = pid
	draft = slots.duplicate(true)
	can_submit = submit_ok
	if pid >= 0 and pid < PLAYER_COLORS.size():
		accent = PLAYER_COLORS[pid]
	queue_redraw()


func _circle_center(i: int) -> Vector2:
	return Vector2(size.x * 0.5, 22.0 + R + float(i) * (R * 2.0 + GAP))


func _submit_rect() -> Rect2:
	var y := _circle_center(2).y + R + GAP + 4.0
	return Rect2(Vector2((size.x - SUBMIT_W) * 0.5, y), Vector2(SUBMIT_W, SUBMIT_H))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var local: Vector2 = event.position
	for i in 3:
		if local.distance_to(_circle_center(i)) <= R + 2.0:
			slot_clicked.emit(i)
			accept_event()
			return
	if _submit_rect().has_point(local) and can_submit:
		submit_pressed.emit()
		accept_event()


func _draw() -> void:
	for i in 3:
		_draw_slot_circle(i)
	_draw_submit()


func _slot_filled(i: int) -> bool:
	return i < draft.size() and draft[i].has("kind")


func _draw_slot_circle(i: int) -> void:
	var c := _circle_center(i)
	var filled := _slot_filled(i)
	if filled:
		var fill := accent.darkened(0.25)
		fill.a = 0.92
		draw_circle(c, R, fill)
		draw_circle(c, R, accent, false, 3.0)
		var action: Dictionary = draft[i]
		var kind: ArenaMatch.ActionKind = action.kind
		var dir: Vector2i = action.dir
		match kind:
			ArenaMatch.ActionKind.MOVE:
				_draw_icon(TEX_FOOT, c, ICON_SIZE)
			ArenaMatch.ActionKind.SHURIKEN:
				_draw_icon(TEX_SHURIKEN, c, ICON_SIZE)
			ArenaMatch.ActionKind.PUNCH:
				_draw_icon(TEX_FIST, c, ICON_SIZE)
		_draw_dir_arrow(c, dir, Color.WHITE)
	else:
		draw_circle(c, R, Color(0.12, 0.14, 0.18, 0.9))
		draw_arc(c, R, 0.0, TAU, 28, Color(accent.r, accent.g, accent.b, 0.35), 2.0, true)
		draw_arc(c, R - 6.0, 0.2, TAU - 0.4, 20, Color(1, 1, 1, 0.08), 1.2, true)
	draw_string(
		ThemeDB.fallback_font,
		c + Vector2(-4, -R - 6),
		str(i + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		Color(accent.r, accent.g, accent.b, 0.95) if filled else Color(0.55, 0.58, 0.64, 0.9)
	)


func _draw_submit() -> void:
	var r := _submit_rect()
	var bg := accent if can_submit else Color(0.22, 0.24, 0.28)
	var edge := accent.lightened(0.15) if can_submit else Color(0.35, 0.38, 0.42)
	draw_rect(r, bg, true, -1.0, true)
	draw_rect(r, edge, false, 2.0, true)
	var label := "Submit plan" if can_submit else "Queue 3 first"
	var col := Color.WHITE if can_submit else Color(0.65, 0.67, 0.7)
	draw_string(
		ThemeDB.fallback_font,
		r.position + Vector2(14, r.size.y * 0.62),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		15,
		col
	)


func _draw_dir_arrow(c: Vector2, dir: Vector2i, col: Color) -> void:
	var n := Vector2(dir).normalized()
	if n == Vector2.ZERO:
		return
	var tip := c + n * (R - 7.0)
	var tail := c + n * 6.0
	draw_line(tail, tip, col, 2.4, true)
	var left := tip - n.rotated(0.7) * 7.0
	var right := tip - n.rotated(-0.7) * 7.0
	draw_line(tip, left, col, 2.4, true)
	draw_line(tip, right, col, 2.4, true)


func _draw_icon(tex: Texture2D, center: Vector2, px: float) -> void:
	var r := Rect2(center - Vector2(px, px) * 0.5, Vector2(px, px))
	draw_texture_rect(tex, r, false)
