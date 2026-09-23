extends Control

const PlanBar = preload("res://scripts/plan_bar.gd")
const CpuPlanner = preload("res://scripts/cpu_planner.gd")

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
var center_label: Label
var priority_label: Label
var next_btn: Button
var stage_label: Label
var plan_bar: PlanBar
var level_panel: VBoxContainer
var level_title: Label
var level_choices: VBoxContainer
var anim_lock := false
var fx_timer: Timer
var is_cpu: Array[bool] = [false, true, true, true]
var cpu_pending := false
var control_checks: Array[CheckBox] = []


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_build_ui()
	_reset_draft()
	_refresh()
	_kick_cpu()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("12141a")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(split)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)

	var title := Label.new()
	title.text = "ARENA FIGHTER"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("e8dcc4"))
	left.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "v2.1  ·  heuristic CPU  ·  same hidden information as a human"
	subtitle.add_theme_color_override("font_color", Color("8b93a7"))
	left.add_child(subtitle)

	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 18)
	phase_label.add_theme_color_override("font_color", Color("f4a261"))
	left.add_child(phase_label)

	priority_label = Label.new()
	priority_label.add_theme_color_override("font_color", Color("c5c9d4"))
	left.add_child(priority_label)

	center_label = Label.new()
	center_label.add_theme_color_override("font_color", Color("9b72cf"))
	left.add_child(center_label)

	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 14)
	left.add_child(control_row)
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

	var board_row := HBoxContainer.new()
	board_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_row.add_theme_constant_override("separation", 12)
	left.add_child(board_row)

	board = BoardView.new()
	board.match_ref = game
	board.tile_hovered.connect(_on_tile_hovered)
	board.move_dropped.connect(_on_move_dropped)
	board.ability_dropped.connect(_on_ability_dropped)
	board.ability_clicked.connect(_on_ability_clicked)
	board.drag_cancelled.connect(_on_drag_cancelled)
	board.plan_slot_clicked.connect(_clear_slot)
	board_row.add_child(board)

	plan_bar = PlanBar.new()
	plan_bar.slot_clicked.connect(_clear_slot)
	plan_bar.submit_pressed.connect(_on_submit)
	board_row.add_child(plan_bar)

	hover_label = Label.new()
	hover_label.add_theme_color_override("font_color", Color("6b7385"))
	left.add_child(hover_label)

	status_box = VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	left.add_child(status_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 360
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.72
	right.add_theme_constant_override("separation", 10)
	split.add_child(right)

	declare_panel = VBoxContainer.new()
	declare_panel.add_theme_constant_override("separation", 8)
	right.add_child(declare_panel)
	_fill_declare_panel()

	resolve_panel = VBoxContainer.new()
	resolve_panel.add_theme_constant_override("separation", 8)
	right.add_child(resolve_panel)
	_fill_resolve_panel()

	over_panel = VBoxContainer.new()
	over_panel.add_theme_constant_override("separation", 8)
	right.add_child(over_panel)
	var over_label := Label.new()
	over_label.name = "OverLabel"
	over_label.add_theme_font_size_override("font_size", 22)
	over_label.add_theme_color_override("font_color", Color("e8dcc4"))
	over_panel.add_child(over_label)
	over_panel.add_child(_btn("New match", _on_new_match))

	level_panel = VBoxContainer.new()
	level_panel.add_theme_constant_override("separation", 10)
	right.add_child(level_panel)
	level_title = Label.new()
	level_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_title.add_theme_font_size_override("font_size", 20)
	level_title.add_theme_color_override("font_color", Color("f4a261"))
	level_panel.add_child(level_title)
	var level_hint := Label.new()
	level_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_hint.add_theme_color_override("font_color", Color("8b93a7"))
	level_hint.text = "Pick one ability. It is added permanently to your action set."
	level_panel.add_child(level_hint)
	level_choices = VBoxContainer.new()
	level_choices.add_theme_constant_override("separation", 8)
	level_panel.add_child(level_choices)

	var log_title := Label.new()
	log_title.text = "Resolution log"
	log_title.add_theme_color_override("font_color", Color("d6c7a1"))
	right.add_child(log_title)

	log_label = RichTextLabel.new()
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.custom_minimum_size.y = 120
	right.add_child(log_label)

	fx_timer = Timer.new()
	fx_timer.one_shot = true
	fx_timer.wait_time = 0.45
	fx_timer.timeout.connect(_on_fx_done)
	add_child(fx_timer)


func _fill_declare_panel() -> void:
	handoff_label = Label.new()
	handoff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	handoff_label.add_theme_font_size_override("font_size", 18)
	declare_panel.add_child(handoff_label)

	draft_label = Label.new()
	draft_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	declare_panel.add_child(draft_label)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("8b93a7"))
	hint.text = "Pass-and-play follows this round's priority. Drag your token to Move (unlimited). Drag an aimed ability from the rail, or click Heal / Frost Ring. Shuriken, Punch, and every acquired ability are once per round. Click a plan circle to clear that slot and everything after it."
	declare_panel.add_child(hint)


func _fill_resolve_panel() -> void:
	var reveal := Label.new()
	reveal.name = "RevealLabel"
	reveal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resolve_panel.add_child(reveal)
	stage_label = Label.new()
	stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage_label.add_theme_color_override("font_color", Color("d6c7a1"))
	resolve_panel.add_child(stage_label)
	next_btn = _btn("Next — Slot 1", _on_next_action)
	resolve_panel.add_child(next_btn)


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


func _on_move_dropped(dir: Vector2i) -> void:
	_queue_action(ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, dir))


func _on_ability_dropped(kind: int, dir: Vector2i) -> void:
	_queue_action(ArenaMatch.make_action(kind as ArenaMatch.ActionKind, dir))


func _on_ability_clicked(kind: int) -> void:
	_queue_action(ArenaMatch.make_action(kind as ArenaMatch.ActionKind))


func _on_drag_cancelled(reason: String) -> void:
	if reason == "full":
		draft_label.text = "All 3 slots are set. Click a slot to clear it."


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
	var i := _next_open_slot()
	if i < 0:
		draft_label.text = "All 3 slots are set. Click a slot to clear it."
		_refresh()
		return
	var kind: ArenaMatch.ActionKind = action.kind
	if not game.owns(declaring_player, kind):
		draft_label.text = "You don't have %s yet." % ArenaMatch.kind_name(kind)
		return
	if not ArenaMatch.is_unlimited(kind):
		for slot in draft:
			if slot.has("kind") and slot.kind == kind:
				draft_label.text = "%s can only be used once per round." % ArenaMatch.kind_name(kind)
				return
	var err := game.validate_action(action)
	if err != "":
		draft_label.text = err
		return
	draft[i] = action
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
	var actions: Array = []
	for slot in draft:
		if not _slot_filled(slot):
			draft_label.text = "Fill all 3 slots before submitting."
			return
		actions.append(slot)
	var err := game.submit_program(declaring_player, actions)
	if err != "":
		draft_label.text = err
		return
	_advance_declare()


func _advance_declare() -> void:
	if game.all_living_have_programs():
		draft_owner = -1
		_reset_draft()
		game.begin_reveal()
		_refresh()
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


func _on_next_action() -> void:
	if anim_lock:
		return
	var fx := game.resolve_next_action()
	if not fx.is_empty() and str(fx.get("kind", "")) not in ["cleanup", "slot_end", ""]:
		board.play_fx(fx)
		anim_lock = true
		if next_btn:
			next_btn.disabled = true
		fx_timer.start()
	_refresh()


func _on_fx_done() -> void:
	anim_lock = false
	if next_btn:
		next_btn.disabled = false
	_refresh()


func _on_new_match() -> void:
	anim_lock = false
	if fx_timer:
		fx_timer.stop()
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


func _refresh() -> void:
	board.match_ref = game
	board.queue_redraw()
	phase_label.text = "Round %d  ·  %s" % [game.round_index, _phase_text()]
	priority_label.text = "Priority: " + game._priority_text()
	if game.last_center_occupants.is_empty() and game.round_index == 1 and game.phase == ArenaMatch.Phase.DECLARE and game.programs.is_empty():
		center_label.text = "Center tiles: C3 C4 D3 D4  ·  +1 XP if you end a round there"
	else:
		center_label.text = "Center at last cleanup: " + game._center_text()
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

	if declaring:
		_sync_declare_turn()
		handoff_label.add_theme_color_override("font_color", PLAYER_COLORS[declaring_player])
		var cpu_turn := declaring_player >= 0 and is_cpu[declaring_player]
		if cpu_turn:
			handoff_label.text = "%s (CPU) is writing a 3-action plan from public board info only." % ArenaMatch.PLAYER_NAMES[declaring_player]
			draft_label.text = "No peeking — the CPU cannot see unrevealed programs, including yours."
			if plan_bar:
				plan_bar.visible = false
			if board:
				board.set_declare_context(false, -1, false)
		else:
			handoff_label.text = "Hand the machine to %s — program 3 actions." % ArenaMatch.PLAYER_NAMES[declaring_player]
			var open := _next_open_slot()
			if open < 0:
				draft_label.text = "All 3 actions queued. Submit your plan under the board."
			else:
				draft_label.text = "Next empty slot: %d  ·  drag on the board to queue" % (open + 1)
			if plan_bar:
				plan_bar.visible = true
				plan_bar.set_plan(declaring_player, draft, open < 0)
			if board:
				var preview: Dictionary = game.declare_preview(declaring_player, draft)
				board.set_declare_context(
					true,
					declaring_player,
					open < 0,
					preview.get("steps", []),
					preview.get("plan_origin", game.positions[declaring_player]),
					_draft_used_kinds()
				)
	else:
		if plan_bar:
			plan_bar.visible = false
		if board:
			board.set_declare_context(false, -1, false)

	if resolving:
		var reveal: Label = resolve_panel.get_node("RevealLabel")
		var lines: PackedStringArray = PackedStringArray()
		match game.resolve_stage():
			"reveal":
				lines.append("Programs revealed. Step through each action with Next.")
			"mid_slot":
				lines.append("Resolving Slot %d — more actions remain in this slot." % (game.current_slot + 1))
			"slot_boundary":
				lines.append("Slot %d finished. Next begins Slot %d." % [game.current_slot + 1, game.current_slot + 2])
			"end_of_round":
				lines.append("Slot 3 finished. Next awards XP, then cleanup (center, eliminations, priority).")
			_:
				lines.append("Resolving…")
		for id in game.living_ids():
			if game.programs.has(id):
				lines.append("%s  %s" % [ArenaMatch.PLAYER_NAMES[id], _program_with_active_slot(game.programs[id])])
		reveal.text = "\n".join(lines)
		stage_label.text = _stage_caption()
		next_btn.text = game.next_prompt()
		next_btn.disabled = anim_lock

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
					return "Slot %d complete" % (game.current_slot + 1)
				_:
					return "Resolve slot %d" % (game.current_slot + 1)
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
		var bit := "%s %s" % [ArenaMatch.kind_name(a.kind), ArenaMatch.dir_name(a.dir)]
		if i == mark:
			parts.append("[%s]" % bit)
		else:
			parts.append(bit)
	return " / ".join(parts)


func _stage_caption() -> String:
	match game.resolve_stage():
		"reveal":
			return "Ready to resolve"
		"mid_slot":
			return "Mid-slot — more actions this slot"
		"slot_boundary":
			return "Slot boundary"
		"end_of_round":
			return "End of round"
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
			line.text = "%s  HP %d  XP %d  @ %s  ·  %s" % [ArenaMatch.PLAYER_NAMES[i], game.hp[i], game.xp[i], ArenaMatch.tile_name(game.positions[i]), seat]
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
		b.text = "%s  ·  %s" % [ArenaMatch.kind_name(k), _ability_blurb(k)]
		b.pressed.connect(_on_pick_level.bind(k))
		level_choices.add_child(b)


func _ability_blurb(kind: ArenaMatch.ActionKind) -> String:
	match kind:
		ArenaMatch.ActionKind.HEAL:
			return "Normal · restore 2 HP (cap 20)"
		ArenaMatch.ActionKind.FLYING_KICK:
			return "Slow · step 1, then 2 dmg beyond"
		ArenaMatch.ActionKind.FROST_RING:
			return "Slow · 1 dmg to all 8 adjacent"
		ArenaMatch.ActionKind.FIREBALL:
			return "Slow · ray 3 dmg + 1 splash"
		ArenaMatch.ActionKind.WINDWALL:
			return "Instant · reflect projectiles"
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
	return [
		ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_N),
		ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_S),
		ArenaMatch.make_action(ArenaMatch.ActionKind.MOVE, ArenaMatch.DIR_E),
	]

