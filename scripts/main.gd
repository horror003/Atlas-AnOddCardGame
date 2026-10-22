extends Control

## 主场景：本地热座 1v1 对战界面。
## 所有 UI 由代码构建，逻辑全部在 AtlasGame 中。

## 手牌按钮：支持拖拽到玩家面板快速指定目标
class DraggableCard extends Button:
	var hand_index := -1
	var main_scene: Control
	func _get_drag_data(_at_position: Vector2) -> Variant:
		if disabled:
			return null
		var g: AtlasGame = main_scene.game
		if g.mode != AtlasGame.Mode.PLAY:
			return null
		var p := g.players[g.current]
		if hand_index < 0 or hand_index >= p.hand.size():
			return null
		var card := g.db.get_card(p.hand[hand_index])
		main_scene._dragging_card_index = hand_index
		# 需要选目标的牌：预计算合法目标并高亮
		var ctype := String(card.get("type", ""))
		if not (bool(card.get("is_defense", false)) or ctype == "trap" or ctype == "equipment"):
			var ttype := String(card.get("target_type", "none"))
			if ttype != "none":
				main_scene._drag_targets = main_scene._drag_target_candidates(ttype)
				main_scene.call_deferred("_refresh")
		var preview := Label.new()
		preview.text = String(card.get("name", ""))
		preview.add_theme_font_size_override("font_size", 14)
		preview.add_theme_stylebox_override("normal", UITheme.card_styles(UITheme.card_color(card))["normal"])
		set_drag_preview(preview)
		return {"hand_index": hand_index}

## 玩家面板：接受手牌拖放
class DropPanel extends Button:
	var player_index := -1
	var main_scene: Control
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return main_scene._can_drop_on_player(player_index, data)
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		main_scene._drop_on_player(player_index, data)

## 日志区容器：接受手牌拖放（自动对自己使用）
class DropLog extends Control:
	var main_scene: Control
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return main_scene._can_drop_on_log(data)
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		main_scene._drop_on_log(data)

## 外层滚动容器：布局已保证内容不超窗口，接管 _gui_input 吞掉滚轮，
## 防止在手牌区/玩家面板滚动时误触发整页滚动（滚动条拖拽不受影响）
class NoWheelScroll extends ScrollContainer:
	func _gui_input(_event: InputEvent) -> void:
		pass

var game: AtlasGame
var _dragging_card_index := -1
var _drag_targets: Array[int] = []

# ---- UI 引用 ----
var log_label: RichTextLabel
var info_label: Label
var discard_info_label: Label
var turn_label: Label
var phase_side_label: Label
var prompt_label: Label
var hand_title: Label
var hand_box: HBoxContainer
var reserve_title: Label
var reserve_box: HBoxContainer
var player_panels: Array[Button] = []
var player_labels: Array[RichTextLabel] = []
var player_skill_rows: Array[HBoxContainer] = []
var player_info_rows: Array[HBoxContainer] = []

var skill_bar: HBoxContainer
var end_play_btn: Button
var end_response_btn: Button
var cancel_target_btn: Button
var discard_hint_btn: Button

var char_pick_layer: Control
var char_pick_box: VBoxContainer
var char_pick_scroll: ScrollContainer
var interstitial: Control
var interstitial_label: Label
var skill_pick_layer: Control
var skill_pick_box: VBoxContainer
var discard_pick_layer: Control
var discard_pick_box: VBoxContainer
var game_over_layer: Control
var game_over_label: Label
var event_show_layer: Control
var event_show_label: Label
var info_popup: Control
var info_popup_title: Label
var info_popup_desc: Label

var highlight_sb: StyleBoxFlat
var dying_sb: StyleBoxFlat
var panel_base_sb: StyleBoxFlat
var panel_active_sb: StyleBoxFlat

func _ready() -> void:
	_apply_theme()
	_build_ui()
	game = AtlasGame.new()
	game.message.connect(_on_log)
	game.start_game()
	_refresh()

func _apply_theme() -> void:
	theme = UITheme.make_theme(16)
	UITheme.add_background(self)

# ---------------- UI 构建 ----------------

func _build_ui() -> void:
	highlight_sb = UITheme.flat(Color(0.10, 0.26, 0.14, 0.95), UITheme.OK, 8, 3)
	dying_sb = UITheme.flat(Color(0.30, 0.10, 0.10, 0.95), UITheme.DANGER, 8, 2)
	panel_base_sb = UITheme.flat(UITheme.BG_PANEL, UITheme.BORDER, 8, 1)
	panel_active_sb = UITheme.flat(Color(0.17, 0.145, 0.08), UITheme.ACCENT, 8, 2)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	# 外层滚动容器：内容超高时可滚动，保证底部按钮始终可访问
	var outer_scroll := NoWheelScroll.new()
	outer_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(outer_scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 固定逻辑高度（stretch 已设为 keep_height，视口高度恒为 800），避免进入场景瞬间
	# 读到物理窗口尺寸而把根容器撑高，导致外层出现多余的纵向滚动条
	root.custom_minimum_size = Vector2(0, 760)
	outer_scroll.add_child(root)

	# 顶栏：标题 + 当前回合
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "天光墟纪事"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	top.add_child(title)
	var subtitle := Label.new()
	subtitle.text = " ATLAS"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.add_theme_color_override("font_color", UITheme.ACCENT)
	top.add_child(turn_label)
	var menu_btn := Button.new()
	menu_btn.text = "主菜单"
	menu_btn.custom_minimum_size = Vector2(110, 32)
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/launcher.tscn"))
	top.add_child(menu_btn)

	# 双方玩家面板（兼作目标选择按钮，接受手牌拖放）
	var players_bar := HBoxContainer.new()
	players_bar.add_theme_constant_override("separation", 10)
	root.add_child(players_bar)
	for i in 2:
		var pb := DropPanel.new()
		pb.player_index = i
		pb.main_scene = self
		pb.custom_minimum_size = Vector2(0, 156)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.add_theme_constant_override("separation", 1)
		pb.add_child(vbox)
		var rl := RichTextLabel.new()
		rl.bbcode_enabled = true
		rl.scroll_active = false
		# fit_content=true：按文本内容自动计算高度，不撑满面板也不被压扁
		rl.fit_content = true
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(rl)
		# 信息行：属性 + 状态 + 装备（可点击查看描述）
		var info_row := HBoxContainer.new()
		info_row.add_theme_constant_override("separation", 2)
		info_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(info_row)
		# 技能行（可点击查看描述）
		var skill_row := HBoxContainer.new()
		skill_row.add_theme_constant_override("separation", 2)
		skill_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(skill_row)
		var idx := i
		pb.pressed.connect(func(): _on_panel(idx))
		players_bar.add_child(pb)
		player_panels.append(pb)
		player_labels.append(rl)
		player_skill_rows.append(skill_row)
		player_info_rows.append(info_row)

	# 中部：日志 + 侧栏信息
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 压缩中间说明区最小高度，保证内容较多时整体不出垂直滚动（其余空间仍会自动分给本区）
	middle.custom_minimum_size = Vector2(0, 60)
	middle.add_theme_constant_override("separation", 10)
	root.add_child(middle)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, 110)
	log_label.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG_INPUT, UITheme.BORDER, 8, 1))
	# 日志区外包 DropLog，接受手牌拖放（自动对自己使用）
	var drop_log := DropLog.new()
	drop_log.main_scene = self
	drop_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drop_log.mouse_filter = Control.MOUSE_FILTER_PASS
	middle.add_child(drop_log)
	drop_log.add_child(log_label)
	# drop_log 是普通 Control（非 Container），不会布局子控件，
	# 必须用锚点让日志随父容器拉伸，否则宽度停留在 0 导致文字竖排
	log_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	# 侧栏包一层滚动容器：信息多时侧栏内部滚动，不撑大主界面导致整体滚动
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(262, 0)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(side_scroll)
	var side_panel := PanelContainer.new()
	side_scroll.add_child(side_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side_panel.add_child(side)
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	side.add_child(info_label)
	phase_side_label = Label.new()
	phase_side_label.add_theme_color_override("font_color", UITheme.ACCENT)
	side.add_child(phase_side_label)
	discard_info_label = Label.new()
	discard_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discard_info_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	side.add_child(discard_info_label)
	side.add_child(HSeparator.new())
	# 提示区：金色描边的提示框
	var prompt_panel := PanelContainer.new()
	var prompt_sb := UITheme.flat(Color(0.16, 0.13, 0.07), UITheme.ACCENT.darkened(0.35), 6, 1)
	prompt_panel.add_theme_stylebox_override("panel", prompt_sb)
	side.add_child(prompt_panel)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_panel.add_child(prompt_label)

	# 预备区（规则 3.4：对手可见全部内容）——标题与按钮合并一行，节省纵向空间
	var reserve_row := HBoxContainer.new()
	reserve_row.add_theme_constant_override("separation", 8)
	root.add_child(reserve_row)
	reserve_title = Label.new()
	reserve_title.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	reserve_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reserve_row.add_child(reserve_title)
	reserve_box = HBoxContainer.new()
	reserve_box.add_theme_constant_override("separation", 8)
	reserve_row.add_child(reserve_box)

	# 手牌区
	hand_title = Label.new()
	hand_title.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	root.add_child(hand_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 60)
	# 参与纵向弹性分配：窗口高时手牌区变大，卡牌描述不被裁切
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.6
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 8)
	scroll.add_child(hand_box)

	# 操作按钮栏：技能按钮动态生成 + 固定操作按钮
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	skill_bar = HBoxContainer.new()
	skill_bar.add_theme_constant_override("separation", 8)
	bar.add_child(skill_bar)
	end_play_btn = Button.new()
	end_play_btn.text = "结束出牌阶段"
	end_play_btn.custom_minimum_size = Vector2(160, 36)
	UITheme.style_button(end_play_btn, UITheme.accent_button_styles())
	end_play_btn.pressed.connect(_on_end_play)
	bar.add_child(end_play_btn)
	end_response_btn = Button.new()
	end_response_btn.custom_minimum_size = Vector2(220, 36)
	UITheme.style_button(end_response_btn, UITheme.danger_button_styles())
	end_response_btn.pressed.connect(_on_end_response)
	bar.add_child(end_response_btn)
	cancel_target_btn = Button.new()
	cancel_target_btn.text = "取消操作（右键）"
	cancel_target_btn.custom_minimum_size = Vector2(120, 36)
	cancel_target_btn.pressed.connect(_on_cancel_target)
	bar.add_child(cancel_target_btn)
	discard_hint_btn = Button.new()
	discard_hint_btn.text = "弃牌中…"
	discard_hint_btn.custom_minimum_size = Vector2(160, 36)
	discard_hint_btn.disabled = true
	discard_hint_btn.visible = false
	UITheme.style_button(discard_hint_btn, UITheme.accent_button_styles())
	bar.add_child(discard_hint_btn)

	# 覆盖层：选人 / 回合交接 / 技能选牌 / 游戏结束（最后添加，显示在最上层）
	var ov0 := _make_overlay(true)
	char_pick_layer = ov0["layer"]
	char_pick_box = ov0["box"]
	char_pick_scroll = ov0["scroll"] as ScrollContainer
	get_viewport().size_changed.connect(_fit_char_pick)
	_fit_char_pick()

	var ov1 := _make_overlay()
	interstitial = ov1["layer"]
	interstitial_label = Label.new()
	interstitial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interstitial_label.add_theme_font_size_override("font_size", 22)
	ov1["box"].add_child(interstitial_label)
	var ibtn := Button.new()
	ibtn.text = "开始回合"
	ibtn.custom_minimum_size = Vector2(220, 52)
	UITheme.style_button(ibtn, UITheme.accent_button_styles())
	ibtn.pressed.connect(_on_interstitial)
	ov1["box"].add_child(ibtn)

	var ov2 := _make_overlay()
	skill_pick_layer = ov2["layer"]
	skill_pick_box = ov2["box"]

	var ov2b := _make_overlay()
	discard_pick_layer = ov2b["layer"]
	discard_pick_box = ov2b["box"]

	var ov3 := _make_overlay()
	game_over_layer = ov3["layer"]
	game_over_label = Label.new()
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.add_theme_font_size_override("font_size", 30)
	game_over_label.add_theme_color_override("font_color", UITheme.ACCENT)
	ov3["box"].add_child(game_over_label)
	var rbtn := Button.new()
	rbtn.text = "再来一局"
	rbtn.custom_minimum_size = Vector2(220, 52)
	UITheme.style_button(rbtn, UITheme.accent_button_styles())
	rbtn.pressed.connect(func(): get_tree().reload_current_scene())
	ov3["box"].add_child(rbtn)

	# 事件说明窗口
	var ov4 := _make_overlay()
	event_show_layer = ov4["layer"]
	event_show_label = Label.new()
	event_show_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_show_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_show_label.add_theme_font_size_override("font_size", 18)
	ov4["box"].add_child(event_show_label)
	var ebtn := Button.new()
	ebtn.text = "确认"
	ebtn.custom_minimum_size = Vector2(200, 48)
	UITheme.style_button(ebtn, UITheme.accent_button_styles())
	ebtn.pressed.connect(_on_event_show_confirm)
	ov4["box"].add_child(ebtn)

	# 信息弹窗（装备/技能/属性/状态详细描述）
	var ov5 := _make_overlay()
	info_popup = ov5["layer"]
	info_popup_title = Label.new()
	info_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_popup_title.add_theme_font_size_override("font_size", 20)
	info_popup_title.add_theme_color_override("font_color", UITheme.ACCENT)
	ov5["box"].add_child(info_popup_title)
	info_popup_desc = Label.new()
	info_popup_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_popup_desc.add_theme_font_size_override("font_size", 14)
	ov5["box"].add_child(info_popup_desc)
	var cbtn := Button.new()
	cbtn.text = "关闭"
	cbtn.custom_minimum_size = Vector2(160, 40)
	cbtn.pressed.connect(func(): info_popup.visible = false)
	ov5["box"].add_child(cbtn)

func _make_overlay(scroll: bool = false) -> Dictionary:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	add_child(layer)
	# 背景压暗
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var sb := UITheme.flat(Color(0.09, 0.10, 0.13, 0.98), UITheme.ACCENT.darkened(0.3), 12, 2)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	if scroll:
		# 内容超高时纵向滚动（选人列表），高度由 _fit_char_pick 按视口动态限制
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		panel.add_child(sc)
		sc.add_child(box)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return {"layer": layer, "box": box, "scroll": sc}
	panel.add_child(box)
	return {"layer": layer, "box": box, "scroll": null}

func _fit_char_pick() -> void:
	## 选人列表滚动区高度跟随窗口，避免面板超出屏幕导致角色看不全
	if char_pick_scroll == null:
		return
	var vh := get_viewport_rect().size.y
	char_pick_scroll.custom_minimum_size = Vector2(472, maxf(300.0, vh * 0.80))

# ---------------- 状态刷新 ----------------

func _refresh() -> void:
	var g := game
	# 选人阶段
	char_pick_layer.visible = (g.mode == AtlasGame.Mode.SELECT_CHAR)
	if char_pick_layer.visible:
		_rebuild_char_pick()
	if g.players.is_empty():
		return
	var cur := g.players[g.current]
	turn_label.text = "当前回合：%s" % cur.name
	info_label.text = "抽牌堆：%d\n弃牌堆：%d\n事件堆：%d" % [g.draw_pile.size(), g.discard_pile.size(), g.event_deck.size()]
	phase_side_label.text = "阶段：%s" % AtlasGame.PHASE_NAMES[g.phase]
	# 信息公开：上一回合进入弃牌堆的牌（规则 6.1）
	var last_names := g.last_turn_discard_names()
	if last_names.is_empty():
		discard_info_label.text = "上回合弃牌：无"
	else:
		discard_info_label.text = "上回合弃牌：%s" % "、".join(last_names)

	# 玩家面板：生命/状态/预备区/陷阱（规则 3.4 / 6.1）
	for i in g.players.size():
		var p := g.players[i]
		var bb := "[center][b][font_size=18]%s[/font_size][/b][/center]\n" % p.name
		bb += "[center][color=lightgray]生命 %d / %d　手牌 %d[/color][/center]\n" % [p.hp, p.max_hp, p.hand.size()]
		var st := ""
		for s in p.status_ids():
			var n := p.status_layer(s)
			st += "%s" % _status_display_name(s)
			if n > 1:
				st += "×%d" % n
			st += " "
		if p.scab > 0:
			st += "「痂」%d " % p.scab
		if p.dying:
			st += "「濒死」"
		if p.dead:
			st += "「死亡」"
		if st != "":
			bb += "[center][color=gold]%s[/color][/center]\n" % st
		# 预备区（对手可见全部内容）与陷阱（对手仅见数量）
		var rv_names: Array[String] = []
		for rv in p.reserve:
			rv_names.append(String(g.db.get_card(rv).get("name", rv)))
		bb += "[center][color=plum]预备区：%s[/color]　[color=orange]陷阱 ×%d[/color][/center]" % [("、".join(rv_names) if not rv_names.is_empty() else "无"), p.traps.size()]
		player_labels[i].text = bb
		# 信息行：属性 + 状态 + 装备（全部可点击查看描述）
		var info_row: HBoxContainer = player_info_rows[i]
		for c in info_row.get_children():
			c.queue_free()
		for aid in p.attribute_ids:
			var attr := g.db.get_attribute(aid)
			var attr_btn := Button.new()
			attr_btn.text = String(attr.get("name", aid))
			attr_btn.add_theme_font_size_override("font_size", 10)
			attr_btn.custom_minimum_size = Vector2(50, 20)
			attr_btn.tooltip_text = String(attr.get("name", "属性"))
			var attr_desc := String(attr.get("description", ""))
			var attr_name := String(attr.get("name", "属性"))
			attr_btn.pressed.connect(func(): _show_info(attr_name, attr_desc))
			info_row.add_child(attr_btn)
		for s in p.status_ids():
			var sname := _status_display_name(s)
			var sbtn := Button.new()
			sbtn.text = sname
			sbtn.add_theme_font_size_override("font_size", 10)
			sbtn.custom_minimum_size = Vector2(50, 20)
			sbtn.tooltip_text = sname
			var sid := s
			sbtn.pressed.connect(func(): _show_info(sname, _status_desc(sid)))
			info_row.add_child(sbtn)
		if p.dying:
			var dbtn := Button.new()
			dbtn.text = "「濒死」"
			dbtn.add_theme_font_size_override("font_size", 10)
			dbtn.custom_minimum_size = Vector2(50, 20)
			dbtn.tooltip_text = "濒死"
			dbtn.pressed.connect(func(): _show_info("濒死", "生命值为 0，进入濒死状态。需要其他玩家使用食物牌救援，否则回合结束时死亡。"))
			info_row.add_child(dbtn)
		if not p.equipment.is_empty():
			var eq_label := Label.new()
			eq_label.text = "装备:"
			eq_label.add_theme_font_size_override("font_size", 10)
			eq_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			info_row.add_child(eq_label)
			for eq in p.equipment:
				var eq_card := g.db.get_card(eq)
				var eb := Button.new()
				eb.text = String(eq_card.get("name", eq))
				eb.add_theme_font_size_override("font_size", 10)
				eb.custom_minimum_size = Vector2(50, 20)
				eb.tooltip_text = String(eq_card.get("name", eq))
				var eq_desc := String(eq_card.get("description", ""))
				var eq_name := String(eq_card.get("name", eq))
				eb.pressed.connect(func(): _show_info(eq_name, eq_desc))
				info_row.add_child(eb)
		# 技能行
		var skill_row: HBoxContainer = player_skill_rows[i]
		for c in skill_row.get_children():
			c.queue_free()
		for sid in p.skill_ids:
			var sk := g.db.get_skill(sid)
			var sb := Button.new()
			sb.text = String(sk.get("name", sid))
			sb.add_theme_font_size_override("font_size", 10)
			sb.custom_minimum_size = Vector2(50, 20)
			sb.tooltip_text = String(sk.get("name", sid))
			var sk_desc := String(sk.get("description", ""))
			var sk_name := String(sk.get("name", sid))
			sb.pressed.connect(func(): _show_info(sk_name, sk_desc))
			skill_row.add_child(sb)
		# 面板样式优先级：濒死红色 > 目标候选/拖拽目标绿色 > 当前回合金色 > 普通
		player_panels[i].disabled = true
		var sb: StyleBoxFlat
		if p.dying or p.dead:
			sb = dying_sb
		elif g.mode == AtlasGame.Mode.SELECT_TARGET and g.target_candidates_now().has(i):
			player_panels[i].disabled = false
			sb = highlight_sb
		elif _drag_targets.has(i):
			sb = highlight_sb
		elif i == g.current:
			sb = panel_active_sb
		else:
			sb = panel_base_sb
		player_panels[i].add_theme_stylebox_override("normal", sb)

	# 当前视图玩家（响应窗口时切换为防御方 / 被询问救援的玩家 / 弃牌选择的目标）
	var view := cur
	if g.mode == AtlasGame.Mode.RESPONSE:
		if String(g.pending.get("kind", "")) == "dying_save":
			var rescuers: Array = g.pending.get("rescuers", [])
			if not rescuers.is_empty():
				view = g.players[int(rescuers[0])]
		else:
			view = g.players[int(g.pending["defender"])]
	elif g.mode == AtlasGame.Mode.DISCARD_PICK:
		view = g.players[int(g.pending.get("target", g.current))]

	# 预备区行：防御牌按防御数值堆叠，非防御牌单独显示
	for c in reserve_box.get_children():
		c.visible = false
		c.queue_free()
	var reserve_clickable := g.mode == AtlasGame.Mode.RESPONSE and String(g.pending.get("kind", "")) == "damage"
	reserve_title.text = "%s 的预备区（%d）%s" % [view.name, view.reserve.size(), "—— 响应中，可点击防御牌直接使用" if reserve_clickable else ""]
	reserve_title.visible = not view.reserve.is_empty() or reserve_clickable
	# 分组：防御牌按防御数值堆叠，其他牌单独列出
	var defense_groups := {}  # defense_value -> Array[int] reserve 索引
	var other_cards := []     # 非防御牌（如延时判定）
	for i in view.reserve.size():
		var cid := view.reserve[i]
		var card := g.db.get_card(cid)
		if bool(card.get("is_defense", false)):
			var dv := int(card.get("defense_value", 0))
			if not defense_groups.has(dv):
				defense_groups[dv] = []
			defense_groups[dv].append(i)
		else:
			other_cards.append(i)
	# 防御牌堆叠按钮
	var dv_keys := defense_groups.keys()
	dv_keys.sort()
	for dv in dv_keys:
		var indices: Array = defense_groups[dv]
		var first_idx := int(indices[0])
		var first_card := g.db.get_card(view.reserve[first_idx])
		var b := Button.new()
		b.custom_minimum_size = Vector2(140, 40)
		b.text = "%s x%d" % [String(first_card.get("name", "")), indices.size()]
		b.add_theme_font_size_override("font_size", 13)
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(first_card)))
		b.disabled = not (reserve_clickable and bool(first_card.get("is_defense", false)))
		var idx := first_idx
		b.pressed.connect(func(): _on_reserve(idx))
		reserve_box.add_child(b)
	# 非防御牌单独显示
	for i in other_cards:
		var cid := view.reserve[i]
		var card := g.db.get_card(cid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(140, 40)
		b.text = String(card.get("name", cid))
		b.add_theme_font_size_override("font_size", 13)
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(card)))
		b.disabled = true
		reserve_box.add_child(b)

	# 手牌区
	for c in hand_box.get_children():
		c.visible = false
		c.queue_free()
	match g.mode:
		AtlasGame.Mode.PLAY:
			hand_title.text = "%s 的手牌（点击打出；防御牌点击=布置到预备区）" % view.name
		AtlasGame.Mode.RESPONSE:
			var kind := String(g.pending.get("kind", ""))
			if kind == "skip_response":
				hand_title.text = "[响应中] %s 的手牌（只能打出【跳过】抵消）" % view.name
			elif kind == "dying_save":
				hand_title.text = "[濒死救援] %s 的手牌（只能打出食物牌救人，或放弃）" % view.name
			else:
				hand_title.text = "[响应中] %s 的手牌（只能打出【防御】类牌）" % view.name
		AtlasGame.Mode.DISCARD:
			hand_title.text = "%s 的手牌（点击弃置）" % view.name
		AtlasGame.Mode.SELECT_TARGET:
			hand_title.text = "%s 的手牌（选择目标中……）" % view.name
		AtlasGame.Mode.DISCARD_PICK:
			hand_title.text = "%s %s 的手牌（请选择 %d 张弃置）" % [String(g.db.get_skill("skill_perceive").get("name", "洞悉")), view.name, int(g.pending.get("count", 0))]
		_:
			hand_title.text = "%s 的手牌" % view.name
	var clickable := g.mode == AtlasGame.Mode.PLAY or g.mode == AtlasGame.Mode.RESPONSE or g.mode == AtlasGame.Mode.DISCARD or g.mode == AtlasGame.Mode.DISCARD_PICK
	for i in view.hand.size():
		var cid := view.hand[i]
		var card := g.db.get_card(cid)
		var b := DraggableCard.new()
		b.hand_index = i
		b.main_scene = self
		b.custom_minimum_size = Vector2(150, 60)
		b.text = "%s\n%s" % [String(card.get("name", cid)), String(card.get("description", ""))]
		b.add_theme_font_size_override("font_size", 12)
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(card)))
		b.disabled = not clickable
		var idx := i
		b.pressed.connect(func(): _on_card(idx))
		hand_box.add_child(b)

	# 提示与操作按钮
	match g.mode:
		AtlasGame.Mode.PLAY:
			prompt_label.text = "出牌阶段：点击手牌打出；可使用技能；完毕后点「结束出牌阶段」。"
		AtlasGame.Mode.SELECT_TARGET:
			prompt_label.text = "请点击上方高亮的玩家面板选择目标。"
		AtlasGame.Mode.RESPONSE:
			var kind := String(g.pending.get("kind", ""))
			if kind == "skip_response":
				prompt_label.text = "响应窗口：%s 即将获得「跳过」。打出另一张【跳过】抵消，或点「结束响应」。" % view.name
			elif kind == "dying_save":
				var dying_p := g.players[int(g.pending["dying_player"])]
				prompt_label.text = "濒死救援：%s 处于「濒死」！%s 可打出食物牌救人（视为其使用），或点「放弃救援」。" % [dying_p.name, view.name]
			else:
				var amount := int(g.pending["amount"])
				var blocked := int(g.pending["blocked"])
				var dtype := String(AtlasGame.DAMAGE_TYPE_NAMES.get(String(g.pending.get("damage_type", "physical")), ""))
				prompt_label.text = "响应窗口：%s 即将受到 %d 点%s伤害（已格挡 %d）。点击【防御】牌格挡，或点「结束响应」结算。" % [view.name, amount, dtype, blocked]
		AtlasGame.Mode.DISCARD:
			prompt_label.text = "弃牌阶段：点击手牌弃置，还需弃 %d 张。" % (cur.hand.size() - cur.hand_limit)
		AtlasGame.Mode.SKILL_PICK:
			prompt_label.text = "技能：请选择一张防御牌加入手牌。"
		AtlasGame.Mode.DISCARD_PICK:
			prompt_label.text = "%s 请点击下方手牌选择 %d 张弃置。" % [String(g.db.get_skill("skill_perceive").get("name", "洞悉")), int(g.pending.get("count", 0))]
		_:
			prompt_label.text = ""

	# 技能按钮：角色可拥有多个主动技（规则 2.3）
	for c in skill_bar.get_children():
		c.visible = false
		c.queue_free()
	if g.mode == AtlasGame.Mode.PLAY:
		for sid in cur.skill_ids:
			var sk := g.db.get_skill(sid)
			var stype := String(sk.get("skill_type", ""))
			if stype != "active" and stype != "switch":
				continue
			var b := Button.new()
			var left := int(cur.skill_uses_left.get(sid, 0))
			b.text = "%s（剩%d）" % [String(sk.get("name", sid)), left]
			b.custom_minimum_size = Vector2(0, 36)
			b.disabled = left <= 0
			b.tooltip_text = String(sk.get("description", ""))
			UITheme.style_button(b, UITheme.skill_button_styles())
			var id := sid
			b.pressed.connect(func(): _on_skill(id))
			skill_bar.add_child(b)
	end_play_btn.visible = (g.mode == AtlasGame.Mode.PLAY)
	end_response_btn.visible = (g.mode == AtlasGame.Mode.RESPONSE)
	if end_response_btn.visible:
		var kind := String(g.pending.get("kind", ""))
		if kind == "skip_response":
			end_response_btn.text = "结束响应（将获得「跳过」）"
		elif kind == "dying_save":
			end_response_btn.text = "放弃救援"
		else:
			var remain: int = maxi(0, int(g.pending["amount"]) - int(g.pending["blocked"]))
			end_response_btn.text = "结束响应（将受到 %d 点伤害）" % remain
	cancel_target_btn.visible = (g.mode == AtlasGame.Mode.SELECT_TARGET)
	# 弃牌/自选弃牌时显示占位按钮，保持底部操作行可见且行高稳定
	discard_hint_btn.visible = (g.mode == AtlasGame.Mode.DISCARD or g.mode == AtlasGame.Mode.DISCARD_PICK)
	if discard_hint_btn.visible:
		if g.mode == AtlasGame.Mode.DISCARD_PICK and g.pending.has("count"):
			discard_hint_btn.text = "弃牌中：还需选择 %d 张" % int(g.pending["count"])
		else:
			discard_hint_btn.text = "弃牌阶段进行中…"

	# 覆盖层
	interstitial.visible = (g.mode == AtlasGame.Mode.INTERSTITIAL)
	if interstitial.visible:
		interstitial_label.text = g.interstitial_text()
	skill_pick_layer.visible = (g.mode == AtlasGame.Mode.SKILL_PICK)
	if skill_pick_layer.visible:
		_rebuild_skill_pick()
	# 弃牌选择直接在手牌区进行，不再弹窗
	discard_pick_layer.visible = false
	event_show_layer.visible = (g.mode == AtlasGame.Mode.EVENT_SHOW)
	if event_show_layer.visible:
		var event := g.db.get_event(String(g.pending.get("event_id", "")))
		event_show_label.text = "%s\n\n%s" % [String(event.get("name", "")), String(event.get("description", ""))]
	game_over_layer.visible = (g.mode == AtlasGame.Mode.GAME_OVER)
	if game_over_layer.visible:
		game_over_label.text = "%s 获胜！" % g.winner

# 选人界面（规则 4.1-1）
func _rebuild_char_pick() -> void:
	for c in char_pick_box.get_children():
		c.visible = false
		c.queue_free()
	var g := game
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.text = "请 玩家%d 选择角色" % (g.picked_char_ids.size() + 1)
	char_pick_box.add_child(title)
	for c in g.db.characters:
		var cid := String(c.get("id", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(460, 76)
		b.add_theme_font_size_override("font_size", 14)
		var skill_names: Array[String] = []
		for sid in c.get("skill_ids", []):
			skill_names.append(String(g.db.get_skill(String(sid)).get("name", String(sid))))
		var attr_names: Array[String] = []
		var attr_descs: Array[String] = []
		for aid in c.get("attribute_ids", []):
			var attr := g.db.get_attribute(String(aid))
			attr_names.append(String(attr.get("name", String(aid))))
			var d := String(attr.get("description", ""))
			if d != "":
				attr_descs.append("%s：%s" % [String(attr.get("name", String(aid))), d])
		b.text = "%s（%s）\n生命 %d　摸牌 %d　存牌 %d　技能：%s\n%s" % [
			String(c.get("name", cid)),
			" × ".join(attr_names),
			int(c.get("max_hp", 20)),
			int(c.get("draw_limit", 5)),
			int(c.get("hand_limit", 3)),
			"、".join(skill_names),
			"；".join(attr_descs),
		]
		b.disabled = g.picked_char_ids.has(cid)
		var id := cid
		b.pressed.connect(func(): _on_char_pick(id))
		char_pick_box.add_child(b)

func _rebuild_skill_pick() -> void:
	for c in skill_pick_box.get_children():
		c.visible = false
		c.queue_free()
	var kind := String(game.pending.get("kind", ""))
	var sk := game.db.get_skill(String(game.pending.get("skill_id", "")))
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	if kind == "exile_ask":
		title.text = "是否发动限定技〖放逐〗？"
	elif kind == "sage":
		title.text = "〖贤者之书〗：选择一张要丢弃的牌"
	elif kind == "fractal":
		title.text = "〖分形几何〗：选择一张【普通攻击】转化为【防御2】"
	elif kind == "leap":
		title.text = "〖信仰之跃〗：选择摸牌数量"
	else:
		title.text = "%s：选择一张加入手牌" % String(sk.get("name", "技能"))
	skill_pick_box.add_child(title)
	if kind == "exile_ask":
		var yes := Button.new()
		yes.text = "发动〖放逐〗"
		yes.custom_minimum_size = Vector2(280, 48)
		yes.pressed.connect(func(): _on_skill_pick("yes"))
		skill_pick_box.add_child(yes)
		var no := Button.new()
		no.text = "放弃"
		no.custom_minimum_size = Vector2(280, 44)
		no.pressed.connect(func(): _on_skill_pick("no"))
		skill_pick_box.add_child(no)
		return
	for opt in game.pending.get("options", []):
		var token := String(opt)
		var tok := token
		var b := Button.new()
		var card: Dictionary = {}
		if kind == "skill_retrieve":
			card = game.db.get_card(token)
			b.text = String(card.get("name", token))
		elif kind == "leap":
			b.text = "摸 %s 张（失去 %d 点生命）" % [token, int(token) * 2]
			card = {"type": "basic"}
		else:
			var parts := token.split(":")
			var zone_name := "手牌"
			match parts[0]:
				"equip":
					zone_name = "装备区"
				"reserve":
					zone_name = "预备区"
				"trap":
					zone_name = "陷阱区"
			var cid := ""
			var zone_idx := int(parts[1]) if parts.size() > 1 else -1
			if parts[0] == "hand" and zone_idx >= 0 and zone_idx < game.players[game.current].hand.size():
				cid = game.players[game.current].hand[zone_idx]
			elif parts[0] == "equip" and zone_idx >= 0 and zone_idx < game.players[game.current].equipment.size():
				cid = game.players[game.current].equipment[zone_idx]
			elif parts[0] == "reserve" and zone_idx >= 0 and zone_idx < game.players[game.current].reserve.size():
				cid = game.players[game.current].reserve[zone_idx]
			elif parts[0] == "trap" and zone_idx >= 0 and zone_idx < game.players[game.current].traps.size():
				cid = game.players[game.current].traps[zone_idx]
			card = game.db.get_card(cid)
			b.text = "%s：%s" % [zone_name, String(card.get("name", cid))]
		b.custom_minimum_size = Vector2(320, 48)
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(card)))
		b.pressed.connect(func(): _on_skill_pick(tok))
		skill_pick_box.add_child(b)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(280, 44)
	cancel.pressed.connect(_on_cancel_skill_pick)
	skill_pick_box.add_child(cancel)

func _rebuild_discard_pick() -> void:
	for c in discard_pick_box.get_children():
		c.visible = false
		c.queue_free()
	var g := game
	var target_idx := int(g.pending.get("target", g.current))
	var p := g.players[target_idx]
	var count := int(g.pending.get("count", 1))
	var picker := String(g.pending.get("picker", "self"))
	var title := Label.new()
	if picker == "self":
		title.text = "%s：请选择 %d 张手牌弃置" % [p.name, count]
	else:
		title.text = "请选择 %s 的 %d 张手牌弃置" % [p.name, count]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	discard_pick_box.add_child(title)
	for i in p.hand.size():
		var cid := String(p.hand[i])
		var card := g.db.get_card(cid)
		var b := Button.new()
		b.text = "%s\n%s" % [String(card.get("name", cid)), String(card.get("description", ""))]
		b.custom_minimum_size = Vector2(320, 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(card)))
		var id := cid
		b.pressed.connect(func(): _on_discard_picked(id))
		discard_pick_box.add_child(b)
	if picker != "self":
		var cancel := Button.new()
		cancel.text = "取消"
		cancel.custom_minimum_size = Vector2(320, 44)
		cancel.pressed.connect(_on_cancel_discard_pick)
		discard_pick_box.add_child(cancel)

# ---------------- 事件回调 ----------------

func _on_log(text: String) -> void:
	log_label.append_text(text + "\n")

func _on_panel(i: int) -> void:
	game.ui_select_target(i)
	_refresh()

func _on_card(i: int) -> void:
	if game.mode == AtlasGame.Mode.DISCARD_PICK:
		var p: PlayerData = game.players[int(game.pending.get("target", game.current))]
		if i >= 0 and i < p.hand.size():
			game.ui_discard_picked(p.hand[i])
			_refresh()
		return
	game.ui_play_card(i)
	_refresh()

func _on_reserve(i: int) -> void:
	game.ui_play_reserve(i)
	_refresh()

func _on_skill(id: String) -> void:
	game.ui_use_skill(id)
	_refresh()

func _on_end_play() -> void:
	game.ui_end_play_phase()
	_refresh()

func _on_end_response() -> void:
	game.ui_end_response()
	_refresh()

func _on_cancel_target() -> void:
	game.ui_cancel_target()
	_refresh()

func _input(event: InputEvent) -> void:
	# 右键取消当前选目标操作（用 _input 而非 _unhandled_input，避免被面板等控件吞掉事件）
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if game != null and game.mode == AtlasGame.Mode.SELECT_TARGET:
		_on_cancel_target()
		get_viewport().set_input_as_handled()

func _on_interstitial() -> void:
	game.ui_confirm_interstitial()
	_refresh()

func _on_skill_pick(id: String) -> void:
	game.ui_skill_pick(id)
	_refresh()

func _on_cancel_skill_pick() -> void:
	game.ui_cancel_skill_pick()
	_refresh()

func _on_discard_picked(id: String) -> void:
	game.ui_discard_picked(id)
	_refresh()

func _on_cancel_discard_pick() -> void:
	game.ui_cancel_discard_pick()
	_refresh()

func _on_char_pick(id: String) -> void:
	game.ui_pick_character(id)
	_refresh()

func _on_event_show_confirm() -> void:
	game.ui_confirm_event_show()
	_refresh()

func _show_info(title: String, desc: String) -> void:
	info_popup_title.text = title
	info_popup_desc.text = desc
	info_popup.visible = true

func _status_display_name(status_id: String) -> String:
	# 优先取 statuses.json 中的名称，回退到硬编码表，最后显示 id
	var st: Dictionary = game.db.statuses.get(status_id, {})
	if st.has("name"):
		return String(st["name"])
	return String(AtlasGame.STATUS_NAMES.get(status_id, status_id))

func _status_desc(status_id: String) -> String:
	# 优先取 statuses.json 中的描述
	var st: Dictionary = game.db.statuses.get(status_id, {})
	if st.has("description") and not String(st["description"]).is_empty():
		return String(st["description"])
	match status_id:
		"skip":
			return "跳过该玩家的下一个完整回合。"
		"attack_up_1":
			return "下一次【普通攻击】造成的伤害 +1。"
		"dying":
			return "生命值为 0，进入濒死状态。需要其他玩家使用食物牌救援，否则回合结束时死亡。"
		"burn":
			return "接下来两个回合开始时失去2点生命。"
		_:
			return "一种持续状态效果。"

# ---------------- 拖放：手牌 → 玩家面板 ----------------

# 拖拽结束时清理状态（无论是否落到有效目标）
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if _dragging_card_index != -1 or not _drag_targets.is_empty():
			_dragging_card_index = -1
			_drag_targets.clear()
			_refresh()

# 判断手牌能否拖放到指定玩家面板（仅出牌阶段、需选目标的牌）
func _can_drop_on_player(p_idx: int, data: Variant) -> bool:
	if not (data is Dictionary and data.has("hand_index")):
		return false
	if game.mode != AtlasGame.Mode.PLAY:
		return false
	var hi := int(data["hand_index"])
	var p := game.players[game.current]
	if hi < 0 or hi >= p.hand.size():
		return false
	var card := game.db.get_card(p.hand[hi])
	var ctype := String(card.get("type", ""))
	# 防御牌进预备区、陷阱进陷阱区、装备自动上身，均无需拖放选目标
	if bool(card.get("is_defense", false)) or ctype == "trap" or ctype == "equipment":
		return false
	var ttype := String(card.get("target_type", "none"))
	return _drag_target_candidates(ttype).has(p_idx)

func _drop_on_player(p_idx: int, data: Variant) -> void:
	_dragging_card_index = -1
	_drag_targets.clear()
	var hi := int(data["hand_index"])
	game.ui_play_card(hi)
	# 需要选目标的牌此时处于 SELECT_TARGET，直接以拖放目标结算
	if game.mode == AtlasGame.Mode.SELECT_TARGET:
		if game.target_candidates_now().has(p_idx):
			game.ui_select_target(p_idx)
		else:
			game.ui_cancel_target()
	_refresh()

# 判断手牌能否拖放到日志区（仅出牌阶段，任意手牌）
func _can_drop_on_log(data: Variant) -> bool:
	if not (data is Dictionary and data.has("hand_index")):
		return false
	if game.mode != AtlasGame.Mode.PLAY:
		return false
	var hi := int(data["hand_index"])
	var p := game.players[game.current]
	return hi >= 0 and hi < p.hand.size()

# 拖到日志区 = 自动对自己使用（无目标牌直接结算，需选目标的牌以当前玩家为目标）
func _drop_on_log(data: Variant) -> void:
	_dragging_card_index = -1
	_drag_targets.clear()
	var hi := int(data["hand_index"])
	game.ui_play_card(hi)
	if game.mode == AtlasGame.Mode.SELECT_TARGET:
		# 自动以当前玩家为目标
		if game.target_candidates_now().has(game.current):
			game.ui_select_target(game.current)
		else:
			game.ui_cancel_target()
	_refresh()

# 与 game.gd 的 _target_candidates 同规则：「濒死」角色不能成为伤害/效果目标，食物除外
func _drag_target_candidates(target_type: String) -> Array[int]:
	var result: Array[int] = []
	for i in game.players.size():
		var p := game.players[i]
		match target_type:
			"single_any":
				if p.dead or p.dying:
					continue
				result.append(i)
			"single_enemy":
				if p.dead or p.dying or i == game.current:
					continue
				result.append(i)
			"self_or_dying":
				if i == game.current and not p.dead and not p.dying:
					result.append(i)
				elif p.dying and not p.dead:
					result.append(i)
	return result
