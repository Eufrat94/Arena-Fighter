extends Control

const PlanBar = preload("res://scripts/plan_bar.gd")
const CpuPlanner = preload("res://scripts/cpu_planner.gd")
const ACTION_STAGGER := 0.45

const PLAYER_COLORS := [
	Color("e85d4c"),
	Color("2ec4b6"),
	Color("f4a261"),
	Color("9b72cf"),
]

var game := ArenaMatch.new()
var declaring_player: int = 0
var draft: Array[Dictionary] = []
var draft_owner: int = -1

var board: BoardView
var phase_label: Label
var status_box: VBoxContainer
var log_label: RichTextLabel
var declare_panel: VBoxContainer
var resolve_panel: VBoxContainer
var over_panel: VBoxContainer
var draft_label: Label
var handoff_label: Label
var hover_label: Label
var priority_label: RichTextLabel
var stage_label: Label
var plan_bar: PlanBar
var level_panel: VBoxContainer
var level_header: Label
var level_title: Label
var level_choices: VBoxContainer
var right_help: Label
var anim_lock := false
var autoplaying := false
var fx_timer: Timer
var is_cpu: Array[bool] = [false, true, true, true]
var cpu_pending := false
var control_checks: Array[CheckBox] = []
var timer_label: Label
var pause_btn: Button
var declare_started_msec: int = 0
var timer_armed_for: int = -1
var timer_paused := false
var paused_left := 0.0
var left_panel: VBoxContainer
var right_panel: VBoxContainer

const LAYOUT_EDGE := 16.0
const LAYOUT_GAP := 16.0
const PRIORITY_H := 56.0
const DECLARE_HINT := "Keys 1–N or click an icon, then click a highlighted tile. Empty lock-in or timeout is Pass."


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	set_process(true)
	_build_ui()
	_reset_draft()
	_refresh()
	_kick_cpu()


func _process(_delta: float) -> void:
	if game.phase != ArenaMatch.Phase.DECLARE:
		return
	if declaring_player < 0 or is_cpu[declaring_player]:
		if timer_label:
			timer_label.text = ""
		if pause_btn:
			pause_btn.visible = false
		return
	if pause_btn:
		pause_btn.visible = true
	var left := _declare_time_left()
	if timer_label:
		timer_label.text = "Decide in %d s" % ceili(maxf(0.0, left))
		timer_label.add_theme_color_override("font_color", Color("f4a261") if left > 4.0 or timer_paused else Color("e85d4c"))
	if not timer_paused and left <= 0.0 and not anim_lock:
		_on_submit()


func _declare_time_left() -> float:
	if timer_paused:
		return paused_left
	var elapsed := float(Time.get_ticks_msec() - declare_started_msec) / 1000.0
	return ArenaMatch.DECLARE_SECONDS - elapsed


func _arm_declare_timer() -> void:
	timer_paused = false
	paused_left = ArenaMatch.DECLARE_SECONDS
	declare_started_msec = Time.get_ticks_msec()
	if pause_btn:
		pause_btn.text = "Pause"


func _on_toggle_timer_pause() -> void:
	if game.phase != ArenaMatch.Phase.DECLARE:
		return
	if declaring_player < 0 or is_cpu[declaring_player]:
		return
	if timer_paused:
		declare_started_msec = Time.get_ticks_msec() - int((ArenaMatch.DECLARE_SECONDS - paused_left) * 1000.0)
		timer_paused = false
		if pause_btn:
			pause_btn.text = "Pause"
	else:
		paused_left = maxf(0.0, _declare_time_left())
		timer_paused = true
		if pause_btn:
			pause_btn.text = "Resume"


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if game.phase != ArenaMatch.Phase.DECLARE or autoplaying or anim_lock:
		return
	if declaring_player < 0 or is_cpu[declaring_player]:
		return
	if event.keycode == KEY_ESCAPE:
		if board:
			board.clear_arm()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	var hot := _hotkey_index(event.keycode)
	if hot >= 0:
		_try_arm_hotkey(hot)
		get_viewport().set_input_as_handled()
		return
	if event.keycode != KEY_SPACE:
		return
	_on_submit()
	get_viewport().set_input_as_handled()


func _hotkey_index(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_9:
		return keycode - KEY_KP_1
	return -1


func _try_arm_hotkey(index: int) -> void:
	if declaring_player < 0 or game == null:
		return
	var kinds: Array = game.owned[declaring_player]
	if index < 0 or index >= kinds.size():
		return
	var kind: ArenaMatch.ActionKind = kinds[index]
	if not game.ability_ready(declaring_player, kind):
		draft_label.text = "That ability is on cooldown."
		return
	if board and board.arm_ability(int(kind)):
		draft_label.text = DECLARE_HINT


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("12141a")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	left_panel = VBoxContainer.new()
	left_panel.add_theme_constant_override("separation", 8)
	add_child(left_panel)

	var title := Label.new()
	title.text = "ARENA FIGHTER"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("e8dcc4"))
	left_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "v3.0 experiment  ·  1 action / turn  ·  15s declare"
	subtitle.add_theme_color_override("font_color", Color("8b93a7"))
	left_panel.add_child(subtitle)

	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 18)
	phase_label.add_theme_color_override("font_color", Color("f4a261"))
	left_panel.add_child(phase_label)

	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 14)
	left_panel.add_child(control_row)
	var control_caption := Label.new()
	control_caption.text = "Seats:"
	control_caption.add_theme_color_override("font_color", Color("8b93a7"))
	control_row.add_child(control_caption)
	control_checks.clear()
	for i in ArenaMatch.PLAYER_COUNT:
		var cb := CheckBox.new()
		cb.text = "%s CPU" % ArenaMatch.PLAYER_NAMES[i]
		cb.button_pressed = is_cpu[i]
		cb.add_theme_color_override("font_color", PLAYER_COLORS[i])
		cb.toggled.connect(_on_cpu_toggled.bind(i))
		control_row.add_child(cb)
		control_checks.append(cb)

	hover_label = Label.new()
	hover_label.add_theme_color_override("font_color", Color("6b7385"))
	left_panel.add_child(hover_label)

	status_box = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	left_panel.add_child(status_box)

	var log_title := Label.new()
	log_title.text = "Resolution log"
	log_title.add_theme_color_override("font_color", Color("d6c7a1"))
	left_panel.add_child(log_title)

	log_label = RichTextLabel.new()
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.custom_minimum_size.y = 140
	left_panel.add_child(log_label)

	priority_label = RichTextLabel.new()
	priority_label.bbcode_enabled = true
	priority_label.fit_content = true
	priority_label.scroll_active = false
	priority_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	priority_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	priority_label.custom_minimum_size.y = PRIORITY_H
	priority_label.add_theme_font_size_override("normal_font_size", 24)
	priority_label.add_theme_font_size_override("bold_font_size", 26)
	priority_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(priority_label)

	board = BoardView.new()
	board.match_ref = game
	board.tile_hovered.connect(_on_tile_hovered)
	board.move_dropped.connect(_on_move_dropped)
	board.ability_dropped.connect(_on_ability_dropped)
	board.ability_clicked.connect(_on_ability_clicked)
	board.drag_cancelled.connect(_on_drag_cancelled)
	board.plan_slot_clicked.connect(_clear_slot)
	board.armed_changed.connect(_on_armed_changed)
	add_child(board)

	right_panel = VBoxContainer.new()
	right_panel.add_theme_constant_override("separation", 10)
	right_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(right_panel)

	right_help = Label.new()
	right_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_help.add_theme_color_override("font_color", Color("8b93a7"))
	right_help.text = "Pass-and-play, one action each turn. Keys 1–N arm the rail (Move is 1). Click a highlighted tile to commit, or drag as before. Spacebar locks in. Empty lock-in or a timeout is Pass. Click the plan circle to clear. Escape cancels an armed ability."
	right_panel.add_child(right_help)

	declare_panel = VBoxContainer.new()
	declare_panel.add_theme_constant_override("separation", 8)
	right_panel.add_child(declare_panel)
	_fill_declare_panel()

	resolve_panel = VBoxContainer.new()
	resolve_panel.add_theme_constant_override("separation", 8)
	right_panel.add_child(resolve_panel)
	_fill_resolve_panel()

	over_panel = VBoxContainer.new()
	over_panel.add_theme_constant_override("separation", 8)
	right_panel.add_child(over_panel)
	var over_label := Label.new()
	over_label.name = "OverLabel"
	over_label.add_theme_font_size_override("font_size", 22)
	over_label.add_theme_color_override("font_color", Color("e8dcc4"))
	over_panel.add_child(over_label)
	over_panel.add_child(_btn("New match", _on_new_match))

	level_panel = VBoxContainer.new()
	level_panel.add_theme_constant_override("separation", 8)
	level_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(level_panel)
	level_header = Label.new()
	level_header.text = "LEVEL UP"
	level_header.add_theme_font_size_override("font_size", 28)
	level_header.add_theme_color_override("font_color", Color("e8dcc4"))
	level_panel.add_child(level_header)
	level_title = Label.new()
	level_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_title.add_theme_font_size_override("font_size", 15)
	level_title.add_theme_color_override("font_color", Color("f4a261"))
	level_panel.add_child(level_title)
	level_choices = VBoxContainer.new()
	level_choices.add_theme_constant_override("separation", 8)
	level_choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_panel.add_child(level_choices)

	pause_btn = Button.new()
	pause_btn.text = "Pause"
	pause_btn.tooltip_text = "Testing: freeze this player's declare countdown"
	pause_btn.pressed.connect(_on_toggle_timer_pause)
	pause_btn.custom_minimum_size = Vector2(0, 32)
	pause_btn.size_flags_horizontal = Control.SIZE_FILL
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	right_panel.add_child(pause_btn)

	plan_bar = PlanBar.new()
	plan_bar.slot_clicked.connect(_clear_slot)
	plan_bar.submit_pressed.connect(_on_submit)
	plan_bar.size_flags_horizontal = Control.SIZE_FILL
	plan_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	right_panel.add_child(plan_bar)

	fx_timer = Timer.new()
	fx_timer.one_shot = true
	fx_timer.wait_time = ACTION_STAGGER
	fx_timer.timeout.connect(_on_fx_done)
	add_child(fx_timer)

	resized.connect(_layout_playfield)
	call_deferred("_layout_playfield")


func _layout_playfield() -> void:
	if board == null or left_panel == null or right_panel == null or plan_bar == null:
		return
	var vw := size.x
	var vh := size.y
	if vw < 2.0 or vh < 2.0:
		return
	var left_w := 236.0
	var right_w := maxf(220.0, PlanBar.SUBMIT_W + 20.0)
	if priority_label:
		priority_label.position = Vector2(LAYOUT_EDGE, LAYOUT_EDGE)
		priority_label.size = Vector2(vw - LAYOUT_EDGE * 2.0, PRIORITY_H)
	var right_x := vw - LAYOUT_EDGE - right_w
	var right_y := LAYOUT_EDGE + PRIORITY_H + LAYOUT_GAP
	right_panel.position = Vector2(right_x, right_y)
	right_panel.size = Vector2(right_w, maxf(72.0, vh - LAYOUT_EDGE - right_y))
	left_panel.position = Vector2(LAYOUT_EDGE, LAYOUT_EDGE + PRIORITY_H + LAYOUT_GAP)
	left_panel.size = Vector2(left_w, vh - left_panel.position.y - LAYOUT_EDGE)
	var avail_x0 := LAYOUT_EDGE + left_w + LAYOUT_GAP
	var avail_y0 := LAYOUT_EDGE + PRIORITY_H + LAYOUT_GAP
	var avail_x1 := right_x - LAYOUT_GAP
	var avail_y1 := vh - LAYOUT_EDGE
	var max_board_w := maxf(120.0, avail_x1 - avail_x0)
	var max_board_h := maxf(120.0, avail_y1 - avail_y0)
	var max_cell_w := (max_board_w - BoardView.PAD_LEFT - BoardView.PAD_RIGHT) / float(ArenaMatch.COLS)
	var max_cell_h := (max_board_h - BoardView.PAD_TOP - BoardView.PAD_BOTTOM) / float(ArenaMatch.ROWS)
	var cell := clampf(minf(BoardView.CELL_MAX, minf(max_cell_w, max_cell_h)), BoardView.CELL_MIN, BoardView.CELL_MAX)
	var board_w := BoardView.PAD_LEFT + cell * float(ArenaMatch.COLS) + BoardView.PAD_RIGHT
	var board_h := BoardView.PAD_TOP + cell * float(ArenaMatch.ROWS) + BoardView.PAD_BOTTOM
	var board_x := avail_x0 + (max_board_w - board_w) * 0.5
	var board_y := avail_y0 + (max_board_h - board_h) * 0.5
	board.position = Vector2(board_x, board_y)
	board.size = Vector2(board_w, board_h)


func _fill_declare_panel() -> void:
	handoff_label = Label.new()
	handoff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	handoff_label.add_theme_font_size_override("font_size", 18)
	declare_panel.add_child(handoff_label)

	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 22)
	timer_label.add_theme_color_override("font_color", Color("f4a261"))
	timer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	declare_panel.add_child(timer_label)

	draft_label = Label.new()
	draft_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draft_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draft_label.custom_minimum_size.y = 44
	declare_panel.add_child(draft_label)


func _fill_resolve_panel() -> void:
	var reveal := Label.new()
	reveal.name = "RevealLabel"
	reveal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resolve_panel.add_child(reveal)
	stage_label = Label.new()
	stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage_label.add_theme_color_override("font_color", Color("d6c7a1"))
	resolve_panel.add_child(stage_label)


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _on_tile_hovered(pos: Vector2i) -> void:
	if pos.x < 0:
		hover_label.text = ""
		return
	var extra := "  ·  center" if ArenaMatch.is_center(pos) else ""
	var who := game.player_at(pos)
	if who >= 0:
		hover_label.text = "%s  ·  %s (%d HP)%s" % [ArenaMatch.tile_name(pos), ArenaMatch.PLAYER_NAMES[who], game.hp[who], extra]
	else:
		hover_label.text = "%s  ·  empty%s" % [ArenaMatch.tile_name(pos), extra]


func _on_armed_changed(_kind: int) -> void:
	pass


func _on_move_dropped(dir: Vector2i) -> void:
	_queue_action(ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, dir))


func _on_ability_dropped(kind: int, dir: Vector2i) -> void:
	_queue_action(ArenaMatch.make_action(kind as ArenaMatch.ActionKind, dir))


func _on_ability_clicked(kind: int) -> void:
	_queue_action(ArenaMatch.make_action(kind as ArenaMatch.ActionKind))


func _on_drag_cancelled(reason: String) -> void:
	if reason == "cooldown":
		draft_label.text = "That ability is still on cooldown."
	elif reason == "full":
		draft_label.text = "Replace your queued action, or lock it in."


func _slot_filled(slot: Dictionary) -> bool:
	return slot.has("kind")


func _next_open_slot() -> int:
	for i in draft.size():
		if not _slot_filled(draft[i]):
			return i
	return -1


func _queue_action(action: Dictionary) -> void:
	if game.phase != ArenaMatch.Phase.DECLARE:
		return
	var kind: ArenaMatch.ActionKind = action.kind
	if not game.owns(declaring_player, kind):
		draft_label.text = "You don't have %s yet." % ArenaMatch.kind_name(kind)
		return
	if not game.ability_ready(declaring_player, kind):
		draft_label.text = "That ability is on cooldown."
		return
	var err := game.validate_action(action)
	if err != "":
		draft_label.text = err
		return
	if draft.is_empty():
		_reset_draft()
	draft[0] = action
	if board:
		board.clear_arm()
	_refresh()


func _clear_slot(index: int) -> void:
	if index < 0 or index >= draft.size():
		return
	if not _slot_filled(draft[index]):
		return
	for i in range(index, draft.size()):
		draft[i] = {}
	_refresh()


func _on_submit() -> void:
	if game.phase != ArenaMatch.Phase.DECLARE:
		return
	if declaring_player < 0 or game.programs.has(declaring_player):
		return
	var chosen: Dictionary = ArenaMatch.make_pass()
	if not draft.is_empty() and _slot_filled(draft[0]):
		chosen = draft[0]
	var err := game.submit_program(declaring_player, [chosen])
	if err != "":
		draft_label.text = err
		return
	_advance_declare()


func _advance_declare() -> void:
	timer_armed_for = -1
	if game.all_living_have_programs():
		draft_owner = -1
		_reset_draft()
		game.begin_reveal()
		_start_autoplay()
		return
	declaring_player = _next_undeclared()
	_reset_draft()
	draft_owner = declaring_player
	_refresh()


func _next_undeclared() -> int:
	for id in game.priority:
		if game.alive[id] and not game.programs.has(id):
			return id
	var living := game.living_ids()
	return living[0] if living.size() > 0 else 0


func _start_autoplay() -> void:
	if autoplaying or anim_lock:
		return
	if game.phase != ArenaMatch.Phase.REVEAL and game.phase != ArenaMatch.Phase.RESOLVING:
		return
	autoplaying = true
	_auto_step()


func _fx_is_watchable(fx: Dictionary) -> bool:
	var kind := str(fx.get("kind", ""))
	return kind != "" and kind != "cleanup" and kind != "slot_end" and kind != "skip"


func _fx_wait(fx: Dictionary) -> float:
	if bool(fx.get("blocked", false)):
		return ACTION_STAGGER + 0.12
	return ACTION_STAGGER


func _auto_step() -> void:
	if not autoplaying:
		return
	var guard := 0
	while autoplaying and guard < 40:
		guard += 1
		if game.phase == ArenaMatch.Phase.DECLARE or game.phase == ArenaMatch.Phase.LEVEL_UP or game.phase == ArenaMatch.Phase.MATCH_OVER:
			_stop_autoplay()
			_refresh()
			_kick_cpu()
			return
		var fx := game.resolve_next_action()
		_refresh()
		if _fx_is_watchable(fx):
			board.play_fx(fx)
			anim_lock = true
			if fx_timer:
				fx_timer.wait_time = _fx_wait(fx)
				fx_timer.start()
			return
	_stop_autoplay()
	_refresh()
	_kick_cpu()


func _stop_autoplay() -> void:
	autoplaying = false
	anim_lock = false
	if fx_timer:
		fx_timer.stop()


func _on_fx_done() -> void:
	anim_lock = false
	if autoplaying:
		_auto_step()
	else:
		_refresh()


func _on_new_match() -> void:
	_stop_autoplay()
	timer_armed_for = -1
	game.reset_match()
	draft_owner = -1
	declaring_player = _next_undeclared()
	if board:
		board.clear_fx()
	_reset_draft()
	draft_owner = declaring_player
	_refresh()


func _reset_draft() -> void:
	draft.clear()
	for _i in ArenaMatch.SLOTS:
		draft.append({})


func _sync_declare_turn() -> void:
	if game.phase != ArenaMatch.Phase.DECLARE:
		return
	var living := game.living_ids()
	if living.is_empty():
		return
	var who := _next_undeclared()
	if declaring_player != who or draft_owner != who:
		declaring_player = who
		_reset_draft()
		draft_owner = who
	elif draft.size() != ArenaMatch.SLOTS:
		_reset_draft()
		draft_owner = who
	if who != timer_armed_for:
		timer_armed_for = who
		_arm_declare_timer()


func _refresh() -> void:
	board.match_ref = game
	board.queue_redraw()
	phase_label.text = "Turn %d" % game.round_index
	if game.phase == ArenaMatch.Phase.LEVEL_UP:
		phase_label.text = "Turn %d  ·  Level up — %s" % [game.round_index, ArenaMatch.PLAYER_NAMES[game.leveling_player]]
	elif game.phase == ArenaMatch.Phase.MATCH_OVER:
		phase_label.text = "Turn %d  ·  Match over" % game.round_index
	priority_label.text = _priority_bbcode()
	_rebuild_status()
	_rebuild_log()

	var declaring := game.phase == ArenaMatch.Phase.DECLARE
	var resolving := game.phase == ArenaMatch.Phase.REVEAL or game.phase == ArenaMatch.Phase.RESOLVING
	var leveling := game.phase == ArenaMatch.Phase.LEVEL_UP
	declare_panel.visible = declaring
	resolve_panel.visible = resolving
	over_panel.visible = game.phase == ArenaMatch.Phase.MATCH_OVER
	if level_panel:
		level_panel.visible = leveling
	if leveling:
		_rebuild_level_choices()
	if leveling or declaring:
		_kick_cpu()

	if right_help:
		if leveling:
			right_help.text = "Pick one ability. It is added permanently to your action set."
		elif declaring:
			right_help.text = "Pass-and-play, one action each turn. Your rail is the live one; the other three sides show everyone’s kits and cooldowns. Keys 1–N arm your rail (Move is 1). Click a highlighted tile to commit, or drag as before. Spacebar locks in. Empty lock-in or a timeout is Pass. Click the plan circle to clear. Escape cancels an armed ability."
		elif resolving:
			right_help.text = "Watch each action play in priority order. Combat in a speed tier is simultaneous underneath."
		elif game.phase == ArenaMatch.Phase.MATCH_OVER:
			right_help.text = "This match is over. Start a new one when you are ready."
		else:
			right_help.text = ""

	if declaring:
		_sync_declare_turn()
		handoff_label.add_theme_color_override("font_color", PLAYER_COLORS[declaring_player])
		var cpu_turn := declaring_player >= 0 and is_cpu[declaring_player]
		if cpu_turn:
			handoff_label.text = "%s (CPU) is picking one action from public board info only." % ArenaMatch.PLAYER_NAMES[declaring_player]
			draft_label.text = "No peeking — the CPU cannot see unrevealed programs, including yours."
			if pause_btn:
				pause_btn.visible = false
			if plan_bar:
				plan_bar.visible = false
				plan_bar.set_engaged(false)
			if board:
				board.set_declare_context(false, -1, false)
		else:
			handoff_label.text = ""
			draft_label.text = DECLARE_HINT
			if pause_btn:
				pause_btn.visible = true
				pause_btn.text = "Resume" if timer_paused else "Pause"
			if plan_bar:
				plan_bar.visible = true
				plan_bar.set_engaged(true)
				plan_bar.set_plan(declaring_player, draft, true)
			if board:
				var preview: Dictionary = game.declare_preview(declaring_player, draft)
				board.set_declare_context(
					true,
					declaring_player,
					false,
					preview.get("steps", []),
					preview.get("plan_origin", game.positions[declaring_player]),
					_dimmed_kinds()
				)
	else:
		if pause_btn:
			pause_btn.visible = false
		if plan_bar:
			plan_bar.visible = false
			plan_bar.set_engaged(false)
		if board:
			board.set_declare_context(false, -1, false)

	if resolving:
		var reveal: Label = resolve_panel.get_node("RevealLabel")
		var lines: PackedStringArray = PackedStringArray()
		match game.resolve_stage():
			"reveal":
				lines.append("Actions revealed — playing this turn.")
			"mid_slot":
				lines.append("Playing this turn — Instant, then Normal, then Slow.")
			"slot_boundary":
				lines.append("Turn actions finished.")
			"end_of_round":
				lines.append("Cleanup: XP, eliminations, priority.")
			_:
				lines.append("Resolving…")
		for id in game.living_ids():
			if game.programs.has(id):
				lines.append("%s  %s" % [ArenaMatch.PLAYER_NAMES[id], _program_with_active_slot(game.programs[id])])
		reveal.text = "\n".join(lines)
		stage_label.text = _stage_caption()

	if game.phase == ArenaMatch.Phase.MATCH_OVER:
		var over: Label = over_panel.get_node("OverLabel")
		if game.winners.is_empty():
			over.text = "Draw — no survivors."
		elif game.winners.size() == 1:
			over.text = "%s wins." % ArenaMatch.PLAYER_NAMES[game.winners[0]]
		else:
			var names: PackedStringArray = PackedStringArray()
			for id in game.winners:
				names.append(ArenaMatch.PLAYER_NAMES[id])
			over.text = "Shared victory: %s" % ", ".join(names)


func _priority_bbcode() -> String:
	var bits: PackedStringArray = PackedStringArray()
	for id in game.priority:
		var hex: String = PLAYER_COLORS[id].to_html(false)
		bits.append("[color=#%s][b]%s[/b][/color]" % [hex, ArenaMatch.PLAYER_NAMES[id]])
	return "[center][color=#8b93a7]Priority[/color]\n%s[/center]" % "  [color=#6b7385]›[/color]  ".join(bits)


func _phase_text() -> String:
	match game.phase:
		ArenaMatch.Phase.DECLARE:
			return "Declare"
		ArenaMatch.Phase.REVEAL:
			return "Reveal"
		ArenaMatch.Phase.RESOLVING:
			match game.resolve_stage():
				"end_of_round":
					return "Cleanup"
				"slot_boundary":
					return "Turn complete"
				_:
					return "Resolve"
		ArenaMatch.Phase.LEVEL_UP:
			return "Level up — %s" % ArenaMatch.PLAYER_NAMES[game.leveling_player]
		ArenaMatch.Phase.MATCH_OVER:
			return "Match over"
		_:
			return ""


func _program_with_active_slot(actions: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var mark := -1
	if game.phase == ArenaMatch.Phase.RESOLVING and not game.at_slot_boundary and not game.awaiting_cleanup:
		mark = game.current_slot
	for i in actions.size():
		var a: Dictionary = actions[i]
		var bit := "Pass" if ArenaMatch.is_pass(a) else "%s %s" % [ArenaMatch.kind_name(a.kind), ArenaMatch.dir_name(a.dir)]
		if i == mark:
			parts.append("[%s]" % bit)
		else:
			parts.append(bit)
	return " / ".join(parts)


func _stage_caption() -> String:
	match game.resolve_stage():
		"reveal":
			return "Playing turn"
		"mid_slot":
			return "Playing actions"
		"slot_boundary":
			return "Turn complete"
		"end_of_round":
			return "Cleanup"
		_:
			return ""


func _rebuild_log() -> void:
	var active_slot := -1
	if game.phase == ArenaMatch.Phase.RESOLVING:
		active_slot = game.current_slot
	const SLOT_HEX := ["#d6b25e", "#6cb6c9", "#c986b8"]
	var bb := ""
	for i in game.log_entries.size():
		var e: Dictionary = game.log_entries[i]
		var slot: int = int(e.get("slot", -1))
		var text: String = str(e.get("text", ""))
		var escaped := text.replace("[", "[lb]").replace("]", "[rb]")
		if slot >= 0 and slot <= 2:
			var hex: String = SLOT_HEX[slot]
			var is_active := game.phase == ArenaMatch.Phase.RESOLVING and slot == active_slot
			if bool(e.get("header", false)):
				if is_active:
					bb += "[bgcolor=#2a2618][color=%s][b]▸ %s[/b][/color][/bgcolor]\n" % [hex, escaped]
				else:
					bb += "[color=#6b7385]%s[/color]\n" % escaped
			elif is_active:
				bb += "[color=%s]|[/color] %s\n" % [hex, escaped]
			else:
				bb += "[color=#6b7385]%s[/color]\n" % escaped
		else:
			bb += "[color=#8b93a7]%s[/color]\n" % escaped
	log_label.text = bb


func _rebuild_status() -> void:
	for child in status_box.get_children():
		child.queue_free()
	for i in ArenaMatch.PLAYER_COUNT:
		var line := Label.new()
		line.add_theme_color_override("font_color", PLAYER_COLORS[i])
		if game.alive[i]:
			var seat := "CPU" if is_cpu[i] else "human"
			line.text = "%s  HP %d  XP %d  ·  %s%s" % [
				ArenaMatch.PLAYER_NAMES[i],
				game.hp[i],
				game.xp[i],
				seat,
				_cooldown_status(i),
			]
		else:
			line.text = "%s  eliminated" % ArenaMatch.PLAYER_NAMES[i]
			line.add_theme_color_override("font_color", Color("6b7385"))
		status_box.add_child(line)


func _draft_used_kinds() -> Array:
	var kinds: Array = []
	for slot in draft:
		if slot.has("kind"):
			kinds.append(slot.kind)
	return kinds


func _dimmed_kinds() -> Array:
	var kinds: Array = []
	if declaring_player < 0:
		return kinds
	for kind in [
		ArenaMatch.ActionKind.SHURIKEN,
		ArenaMatch.ActionKind.PUNCH,
		ArenaMatch.ActionKind.HEAL,
		ArenaMatch.ActionKind.FLYING_KICK,
		ArenaMatch.ActionKind.FROST_RING,
		ArenaMatch.ActionKind.FIREBALL,
		ArenaMatch.ActionKind.WINDWALL,
		ArenaMatch.ActionKind.SPEAR_STRIKE,
	]:
		if not game.ability_ready(declaring_player, kind):
			kinds.append(kind)
	return kinds


func _cooldown_status(player_id: int) -> String:
	var bits: PackedStringArray = PackedStringArray()
	for kind in game.owned[player_id]:
		var left := game.cooldown_left(player_id, kind)
		if left > 0:
			bits.append("%s %d" % [ArenaMatch.kind_name(kind), left])
	if bits.is_empty():
		return ""
	return "  ·  CD " + ", ".join(bits)


func _rebuild_level_choices() -> void:
	if level_title:
		var seat := "CPU" if (game.leveling_player >= 0 and is_cpu[game.leveling_player]) else "you"
		level_title.text = "%s (%s) — choose an ability" % [ArenaMatch.PLAYER_NAMES[game.leveling_player], seat]
	if level_choices == null:
		return
	for child in level_choices.get_children():
		child.queue_free()
	if game.leveling_player >= 0 and is_cpu[game.leveling_player]:
		return
	for kind in game.level_offers:
		var k: ArenaMatch.ActionKind = kind
		var b := Button.new()
		b.text = "%s\n%s" % [ArenaMatch.kind_name(k), _ability_blurb(k)]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = false
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size = Vector2(0, 56.0)
		var icon := _kind_icon(k)
		if icon:
			b.icon = icon
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 28)
		b.pressed.connect(_on_pick_level.bind(k))
		level_choices.add_child(b)
	# Keep the three rows compact so they stay on-screen under the help text.
	level_choices.add_theme_constant_override("separation", 8)


func _kind_icon(kind: ArenaMatch.ActionKind) -> Texture2D:
	match kind:
		ArenaMatch.ActionKind.HEAL:
			return preload("res://icons/heal.png")
		ArenaMatch.ActionKind.FLYING_KICK:
			return preload("res://icons/kick.png")
		ArenaMatch.ActionKind.FROST_RING:
			return preload("res://icons/circle.png")
		ArenaMatch.ActionKind.FIREBALL:
			return preload("res://icons/fireball.png")
		ArenaMatch.ActionKind.WINDWALL:
			return preload("res://icons/windwall.png")
		ArenaMatch.ActionKind.SPEAR_STRIKE:
			return preload("res://icons/spear.png")
		_:
			return null


func _ability_blurb(kind: ArenaMatch.ActionKind) -> String:
	match kind:
		ArenaMatch.ActionKind.HEAL:
			return "Normal · restore 2 HP (cap 20)"
		ArenaMatch.ActionKind.FLYING_KICK:
			return "Slow · step 1, then 2 dmg beyond"
		ArenaMatch.ActionKind.FROST_RING:
			return "Slow · 2 dmg to all 8 adjacent"
		ArenaMatch.ActionKind.FIREBALL:
			return "Slow · ray 3 dmg + 1 splash"
		ArenaMatch.ActionKind.WINDWALL:
			return "Instant · reflect projectiles"
		ArenaMatch.ActionKind.SPEAR_STRIKE:
			return "Slow · 3 dmg at range 1 and 2"
		_:
			return ""


func _on_pick_level(kind: ArenaMatch.ActionKind) -> void:
	var err := game.choose_level_up(kind)
	if err != "":
		return
	if game.phase == ArenaMatch.Phase.DECLARE:
		draft_owner = -1
		declaring_player = _next_undeclared()
		_reset_draft()
		draft_owner = declaring_player
	_refresh()
	_kick_cpu()


func _on_cpu_toggled(index: int, on: bool) -> void:
	is_cpu[index] = on
	_kick_cpu()


func _kick_cpu() -> void:
	if cpu_pending:
		return
	cpu_pending = true
	call_deferred("_cpu_step")


func _cpu_step() -> void:
	cpu_pending = false
	if game.phase == ArenaMatch.Phase.LEVEL_UP and game.leveling_player >= 0 and is_cpu[game.leveling_player]:
		if game.level_offers.is_empty():
			return
		_on_pick_level(CpuPlanner.preferred_level_up(game.level_offers))
		return
	if game.phase != ArenaMatch.Phase.DECLARE:
		return
	if declaring_player < 0 or not is_cpu[declaring_player]:
		return
	if game.programs.has(declaring_player):
		return
	var planner := CpuPlanner.new()
	var plan: Array = planner.plan_program(game, declaring_player)
	var err := game.submit_program(declaring_player, plan)
	if err != "":
		err = game.submit_program(declaring_player, _cpu_fallback())
		if err != "":
			push_error("CPU could not submit a plan: %s" % err)
			return
	_advance_declare()


func _cpu_fallback() -> Array:
	return [ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_N)]
