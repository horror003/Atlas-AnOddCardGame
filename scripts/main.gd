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
		# 触屏上拖拽与滚动互相争抢，移动端只保留「点牌→点面板」两段式（桌面保留拖拽）
		if main_scene.is_mobile():
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
				main_scene._drag_targets = main_scene.game._target_candidates_for(main_scene.game.current, ttype, "")
				main_scene.call_deferred("_refresh")
		var preview := Label.new()
		preview.text = String(card.get("name", ""))
		preview.add_theme_font_size_override("font_size", UITheme.fs(14))
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

## 玩家面板顶部的说明文本：状态/预备区词条可点击查阅，同时保留拖放接收
class StatusLabel extends RichTextLabel:
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

## 技能按钮：移动端长按 450ms 查看技能说明（桌面仍用悬停 tooltip）
class SkillButton extends Button:
	var skill_name := ""
	var skill_desc := ""
	var main_scene: Control
	var _press_msec := -1
	func _gui_input(event: InputEvent) -> void:
		if not main_scene.is_mobile():
			return
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_msec = Time.get_ticks_msec()
		else:
			_press_msec = -1
	func _process(_delta: float) -> void:
		if _press_msec < 0:
			return
		if Time.get_ticks_msec() - _press_msec >= 450:
			_press_msec = -1
			main_scene._skill_long_press = true
			main_scene._show_info(skill_name, skill_desc)

## 外层滚动容器：布局已保证内容不超窗口，接管 _gui_input 吞掉滚轮，
## 防止在手牌区/玩家面板滚动时误触发整页滚动（滚动条拖拽不受影响）
class NoWheelScroll extends ScrollContainer:
	func _gui_input(_event: InputEvent) -> void:
		pass

var game: AtlasGame
var _dragging_card_index := -1
var _drag_targets: Array[int] = []
var _skill_long_press := false  # 长按查看技能说明后置位，用于吞掉本次抬起触发的发动

static func is_mobile() -> bool:
	return UITheme.is_mobile()

## 底部操作按钮高度：触屏 ≥56 逻辑像素
static func _abtn_h() -> int:
	return 56 if UITheme.is_mobile() else ACTION_BTN_HEIGHT

## 顶栏菜单按钮尺寸
static func _menu_btn_size() -> Vector2:
	return Vector2(130, 52) if UITheme.is_mobile() else MENU_BTN_SIZE

## 玩家面板高度：移动端要容纳放大的字号与信息行
static func _panel_h(compact: bool) -> int:
	if UITheme.is_mobile():
		return 150 if compact else 180
	return PLAYER_PANEL_HEIGHT_COMPACT if compact else PLAYER_PANEL_HEIGHT

## 面板内属性/装备/技能小按钮；compact（移动端 4 人局）时更矮，节省纵向空间
static func _mini_btn_size(compact: bool = false) -> Vector2:
	if UITheme.is_mobile():
		return Vector2(64, 26) if compact else Vector2(70, 32)
	return Vector2(50, 20)

## 弹层按钮尺寸：移动端短边 ≥56
static func _overlay_btn_size(w: float, h: float) -> Vector2:
	if UITheme.is_mobile():
		return Vector2(maxf(w, 200.0), maxf(h, 56.0))
	return Vector2(w, h)

# ---------------- 布局常量（集中管理，避免散落的魔法数字） ----------------
const ROOT_MIN_HEIGHT := 760          # 根容器逻辑高度（视口固定 800）
const PLAYER_PANEL_HEIGHT := 156      # 2/3 人局面板高度
const PLAYER_PANEL_HEIGHT_COMPACT := 132  # 4 人局（2×2 布局）面板高度
const MIDDLE_MIN_HEIGHT := 60         # 日志 + 侧栏区域最小高度
const LOG_MIN_HEIGHT := 110           # 日志框最小高度
const HAND_SCROLL_HEIGHT := 60        # 手牌滚动区最小高度
const HAND_CARD_WIDTH := 170.0        # 手牌卡宽度（高度按手牌区高度动态均分）
const HAND_CARD_SEP := 8.0            # 手牌卡横/纵间距
const SIDEBAR_WIDTH := 262            # 右侧信息栏宽度
const MENU_BTN_SIZE := Vector2(110, 32)
const ACTION_BTN_HEIGHT := 36         # 底部操作按钮统一高度
const ACTION_BTN_WIDTH := 160

# ---- UI 引用 ----
var log_label: RichTextLabel
var dev_menu: DevMenu = null
var _meta_click_frame: int = -10      # 最近一次点击富文本链接的帧号
var info_label: Label
var discard_info_label: Label
var turn_label: Label
var phase_side_label: Label
var prompt_label: Label
var hand_title: Label
var hand_scroll: ScrollContainer
var hand_box: HFlowContainer
var reserve_title: Label
var reserve_box: HBoxContainer
var player_panels: Array[Button] = []
var player_labels: Array[RichTextLabel] = []
var player_skill_rows: Array[HBoxContainer] = []
var player_info_rows: Array[HBoxContainer] = []
var players_bar: GridContainer

var skill_bar: HBoxContainer
var end_play_btn: Button
var end_response_btn: Button
var cancel_target_btn: Button
var discard_hint_btn: Button

var char_pick_layer: Control
var char_pick_box: VBoxContainer
var char_pick_scroll: ScrollContainer
var char_pick_title: Label
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
var _root_margin: MarginContainer

var highlight_sb: StyleBoxFlat
var dying_sb: StyleBoxFlat
var panel_base_sb: StyleBoxFlat
var panel_active_sb: StyleBoxFlat

func _ready() -> void:
	_apply_theme()
	_build_ui()
	game = AtlasGame.new()
	game.message.connect(_on_log)
	game.start_game(GameSession.board_id, GameSession.pool_id)
	if OS.is_debug_build():
		dev_menu = DevMenu.new()
		dev_menu.game = game
		dev_menu.main_scene = self
		dev_menu.on_refresh = _refresh
		add_child(dev_menu)
		dev_menu.visible = false
	_refresh()
	# 首帧布局完成后手牌区才有实际尺寸，再排一次让卡牌高度精确撑满
	call_deferred("_refresh")

func _apply_theme() -> void:
	theme = UITheme.make_theme(UITheme.fs(16))
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
	_root_margin = margin

	# 外层滚动容器：内容超高时可滚动，保证底部按钮始终可访问
	var outer_scroll := NoWheelScroll.new()
	outer_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(outer_scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 固定逻辑高度，避免进入场景瞬间读到物理窗口尺寸而把根容器撑高导致多余滚动条。
	# 桌面视口高 800 → 760；移动端基准 720 → 660（有余量时由弹性容器吸收）
	root.custom_minimum_size = Vector2(0, 660 if UITheme.is_mobile() else ROOT_MIN_HEIGHT)
	outer_scroll.add_child(root)

	# 顶栏：标题 + 当前回合
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "天光墟纪事"
	title.add_theme_font_size_override("font_size", UITheme.fs(22))
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	top.add_child(title)
	var subtitle := Label.new()
	subtitle.text = " ATLAS"
	subtitle.add_theme_font_size_override("font_size", UITheme.fs(14))
	subtitle.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	turn_label = Label.new()
	turn_label.add_theme_font_size_override("font_size", UITheme.fs(18))
	turn_label.add_theme_color_override("font_color", UITheme.ACCENT)
	top.add_child(turn_label)
	var dev_btn := Button.new()
	dev_btn.text = "开发"
	dev_btn.custom_minimum_size = _menu_btn_size()
	dev_btn.visible = OS.is_debug_build()
	dev_btn.pressed.connect(_toggle_dev_menu)
	top.add_child(dev_btn)
	var menu_btn := Button.new()
	menu_btn.text = "主菜单"
	menu_btn.custom_minimum_size = _menu_btn_size()
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/launcher.tscn"))
	top.add_child(menu_btn)

	# 玩家面板（2 人 1×2 / 3 人 1×3 / 4 人 2×2），兼作目标选择按钮与拖放目标
	players_bar = GridContainer.new()
	players_bar.add_theme_constant_override("h_separation", 10)
	players_bar.add_theme_constant_override("v_separation", 6)
	root.add_child(players_bar)
	# 先建 2 个占位面板；_refresh 会按实际板子人数重建
	_rebuild_player_panels(2)

	# 中部：日志 + 侧栏信息
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 压缩中间说明区最小高度，保证内容较多时整体不出垂直滚动（其余空间仍会自动分给本区）
	middle.custom_minimum_size = Vector2(0, MIDDLE_MIN_HEIGHT)
	middle.add_theme_constant_override("separation", 10)
	root.add_child(middle)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size = Vector2(0, LOG_MIN_HEIGHT)
	log_label.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG_INPUT, UITheme.BORDER, 8, 1))
	# 日志区外包 DropLog，接受手牌拖放（自动对自己使用）
	var drop_log := DropLog.new()
	drop_log.main_scene = self
	drop_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# drop_log 是普通 Control，最小高度不会向上传播；显式给最小高度，
	# 否则 4 人局面板内容多时日志区会被压扁到只剩两三行
	drop_log.custom_minimum_size = Vector2(0, 90 if UITheme.is_mobile() else LOG_MIN_HEIGHT)
	drop_log.mouse_filter = Control.MOUSE_FILTER_PASS
	middle.add_child(drop_log)
	drop_log.add_child(log_label)
	# drop_log 是普通 Control（非 Container），不会布局子控件，
	# 必须用锚点让日志随父容器拉伸，否则宽度停留在 0 导致文字竖排
	log_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	# 侧栏包一层滚动容器：信息多时侧栏内部滚动，不撑大主界面导致整体滚动
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(SIDEBAR_WIDTH, 0)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(side_scroll)
	var side_panel := PanelContainer.new()
	# 横向填满滚动容器，否则右侧会留出一条背景空档
	side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 长文本偶发不换行时裁剪在面板内，避免画出屏幕右缘
	side_panel.clip_contents = true
	side_scroll.add_child(side_panel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side_panel.add_child(side)
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info_label)
	phase_side_label = Label.new()
	phase_side_label.add_theme_color_override("font_color", UITheme.ACCENT)
	phase_side_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(phase_side_label)
	var prompt_panel := PanelContainer.new()
	var prompt_sb := UITheme.flat(Color(0.16, 0.13, 0.07), UITheme.ACCENT.darkened(0.35), 6, 1)
	prompt_panel.add_theme_stylebox_override("panel", prompt_sb)
	# 提示框紧跟在阶段行之后：4 人局侧栏高度紧张时，先保证操作提示完整可见
	side.add_child(prompt_panel)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_panel.add_child(prompt_label)
	# 上一回合弃牌信息放在最下方，内容超长时可由侧栏独立滚动查看
	side.add_child(HSeparator.new())
	discard_info_label = Label.new()
	discard_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	discard_info_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	side.add_child(discard_info_label)

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
	scroll.custom_minimum_size = Vector2(0, 84 if UITheme.is_mobile() else HAND_SCROLL_HEIGHT)
	# 参与纵向弹性分配：窗口高时手牌区变大，卡牌高度随之撑满该区域
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.6
	# 手牌改为自动换行排布：横向不再滚动，纵向仅在行数过多时滚动
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)
	hand_scroll = scroll
	# 手牌区尺寸变化（首帧布局、窗口缩放）时重新分配卡牌高度
	scroll.item_rect_changed.connect(_fit_hand_cards)
	hand_box = HFlowContainer.new()
	hand_box.add_theme_constant_override("h_separation", int(HAND_CARD_SEP))
	hand_box.add_theme_constant_override("v_separation", int(HAND_CARD_SEP))
	hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	end_play_btn.custom_minimum_size = Vector2(ACTION_BTN_WIDTH, _abtn_h())
	UITheme.style_button(end_play_btn, UITheme.accent_button_styles())
	end_play_btn.pressed.connect(_on_end_play)
	bar.add_child(end_play_btn)
	end_response_btn = Button.new()
	end_response_btn.custom_minimum_size = Vector2(240, _abtn_h())
	UITheme.style_button(end_response_btn, UITheme.danger_button_styles())
	end_response_btn.pressed.connect(_on_end_response)
	bar.add_child(end_response_btn)
	cancel_target_btn = Button.new()
	cancel_target_btn.text = "取消操作"
	cancel_target_btn.custom_minimum_size = Vector2(140, _abtn_h())
	cancel_target_btn.pressed.connect(_on_cancel_target)
	bar.add_child(cancel_target_btn)
	discard_hint_btn = Button.new()
	discard_hint_btn.text = "弃牌中…"
	discard_hint_btn.custom_minimum_size = Vector2(ACTION_BTN_WIDTH, _abtn_h())
	discard_hint_btn.disabled = true
	discard_hint_btn.visible = false
	UITheme.style_button(discard_hint_btn, UITheme.accent_button_styles())
	bar.add_child(discard_hint_btn)

	# 覆盖层：选人 / 回合交接 / 技能选牌 / 游戏结束（最后添加，显示在最上层）
	var ov0 := _make_overlay(true)
	char_pick_layer = ov0["layer"]
	char_pick_box = ov0["box"]
	char_pick_scroll = ov0["scroll"] as ScrollContainer
	# 标题吸顶：放在滚动区外，滚动角色列表时「已选 N/M」始终可见
	char_pick_title = Label.new()
	char_pick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_pick_title.add_theme_font_size_override("font_size", UITheme.fs(22))
	char_pick_title.add_theme_color_override("font_color", UITheme.ACCENT)
	var cp_outer: VBoxContainer = ov0["outer"]
	cp_outer.add_child(char_pick_title)
	cp_outer.move_child(char_pick_title, 0)
	get_viewport().size_changed.connect(_fit_char_pick)
	get_viewport().size_changed.connect(_fit_hand_cards)
	get_viewport().size_changed.connect(_apply_safe_area)
	_fit_char_pick()
	call_deferred("_apply_safe_area")

	var ov1 := _make_overlay()
	interstitial = ov1["layer"]
	interstitial_label = Label.new()
	interstitial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interstitial_label.add_theme_font_size_override("font_size", UITheme.fs(22))
	ov1["box"].add_child(interstitial_label)
	var ibtn := Button.new()
	ibtn.text = "开始回合"
	ibtn.custom_minimum_size = _overlay_btn_size(220, 52)
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
	game_over_label.add_theme_font_size_override("font_size", UITheme.fs(30))
	game_over_label.add_theme_color_override("font_color", UITheme.ACCENT)
	ov3["box"].add_child(game_over_label)
	var rbtn := Button.new()
	rbtn.text = "再来一局"
	rbtn.custom_minimum_size = _overlay_btn_size(220, 52)
	UITheme.style_button(rbtn, UITheme.accent_button_styles())
	rbtn.pressed.connect(func(): get_tree().reload_current_scene())
	ov3["box"].add_child(rbtn)

	# 事件说明窗口
	var ov4 := _make_overlay()
	event_show_layer = ov4["layer"]
	event_show_label = Label.new()
	event_show_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_show_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_show_label.add_theme_font_size_override("font_size", UITheme.fs(18))
	ov4["box"].add_child(event_show_label)
	var ebtn := Button.new()
	ebtn.text = "确认"
	ebtn.custom_minimum_size = _overlay_btn_size(200, 48)
	UITheme.style_button(ebtn, UITheme.accent_button_styles())
	ebtn.pressed.connect(_on_event_show_confirm)
	ov4["box"].add_child(ebtn)

	# 信息弹窗（装备/技能/属性/状态详细描述）
	var ov5 := _make_overlay()
	info_popup = ov5["layer"]
	info_popup_title = Label.new()
	info_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_popup_title.add_theme_font_size_override("font_size", UITheme.fs(20))
	info_popup_title.add_theme_color_override("font_color", UITheme.ACCENT)
	ov5["box"].add_child(info_popup_title)
	info_popup_desc = Label.new()
	info_popup_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_popup_desc.add_theme_font_size_override("font_size", UITheme.fs(14))
	ov5["box"].add_child(info_popup_desc)
	var cbtn := Button.new()
	cbtn.text = "关闭"
	cbtn.custom_minimum_size = _overlay_btn_size(160, 40)
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
		# 内容超高时纵向滚动（选人列表），高度由 _fit_char_pick 按视口动态限制。
		# PanelContainer 会把所有子控件铺满同一块区域，因此用 VBox 承载「吸顶标题 + 滚动区」
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 8)
		panel.add_child(outer)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(sc)
		sc.add_child(box)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return {"layer": layer, "box": box, "scroll": sc, "panel": panel, "outer": outer}
	panel.add_child(box)
	return {"layer": layer, "box": box, "scroll": null, "panel": panel}

func _fit_char_pick() -> void:
	## 选人列表滚动区高度跟随窗口，避免面板超出屏幕导致角色看不全
	if char_pick_scroll == null:
		return
	var vh := get_viewport_rect().size.y
	char_pick_scroll.custom_minimum_size = Vector2(472, maxf(300.0, vh * 0.80))

## 安全区（刘海/挖孔/手势条）：把 DisplayServer 报告的安全区换算成逻辑坐标后加到根边距。
## 桌面或无安全区差异时保持基础边距，绝不硬编码具体机型数值。
func _apply_safe_area() -> void:
	if _root_margin == null:
		return
	if not UITheme.is_mobile():
		return
	var win: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return
	var scale := minf(win.x / 1280.0, win.y / 720.0)
	if scale <= 0.0:
		return
	var ml := maxi(14, int(safe.position.x / scale))
	var mt := maxi(8, int(safe.position.y / scale))
	var mr := maxi(14, int((win.x - safe.position.x - safe.size.x) / scale))
	var mb := maxi(8, int((win.y - safe.position.y - safe.size.y) / scale))
	_root_margin.add_theme_constant_override("margin_left", ml)
	_root_margin.add_theme_constant_override("margin_right", mr)
	_root_margin.add_theme_constant_override("margin_top", mt)
	_root_margin.add_theme_constant_override("margin_bottom", mb)

# ---------------- 状态刷新 ----------------

func _rebuild_player_panels(count: int) -> void:
	## 按人数重建玩家面板：2 人 1×2、3 人 1×3、4 人 2×2
	for c in players_bar.get_children():
		players_bar.remove_child(c)
		c.queue_free()
	player_panels.clear()
	player_labels.clear()
	player_skill_rows.clear()
	player_info_rows.clear()
	players_bar.columns = 2 if count <= 2 or count == 4 else 3
	var panel_h := _panel_h(count >= 4)
	for i in count:
		var pb := DropPanel.new()
		pb.player_index = i
		pb.main_scene = self
		pb.custom_minimum_size = Vector2(0, panel_h)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vbox := VBoxContainer.new()
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.add_theme_constant_override("separation", 1)
		pb.add_child(vbox)
		var rl := StatusLabel.new()
		rl.player_index = i
		rl.main_scene = self
		rl.bbcode_enabled = true
		rl.scroll_active = false
		# fit_content=true：按文本内容自动计算高度，不撑满面板也不被压扁
		rl.fit_content = true
		# 需要接收点击才能触发 meta_clicked；拖放由 StatusLabel 自行转发给面板。
		# 用 PASS 让「非链接区域」的点击继续冒泡到玩家面板，避免状态文字右侧空白吞掉选目标点击。
		rl.mouse_filter = Control.MOUSE_FILTER_PASS
		rl.meta_underlined = false
		rl.meta_clicked.connect(_on_player_meta)
		vbox.add_child(rl)
		# 信息行：属性 + 装备（可点击查看描述）
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

func _refresh() -> void:
	var g := game
	# 选人阶段
	char_pick_layer.visible = (g.mode == AtlasGame.Mode.SELECT_CHAR)
	if char_pick_layer.visible:
		_rebuild_char_pick()
	# 面板数量跟随实际人数；选人前按板子人数预建
	var want := g.players.size()
	if want == 0:
		want = g.board_player_count()
	if players_bar.get_child_count() != want:
		_rebuild_player_panels(want)
	if g.players.is_empty():
		return
	var cur := g.players[g.current]
	var cur_team := g._team_name(cur.team_id) if g.board_player_count() > 2 else ""
	if cur_team.is_empty():
		turn_label.text = "当前回合：%s" % cur.name
	else:
		turn_label.text = "当前回合：%s（%s）" % [cur.name, cur_team]
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
		# 移动端 4 人局：面板纵向空间紧张， chips 合并为一行、名片字号收小
		var compact := g.players.size() >= 4 and UITheme.is_mobile()
		var name_line := p.name
		if g.board_player_count() > 2:
			var tname := g._team_name(p.team_id)
			if not tname.is_empty():
				name_line = "%s　[lb]%s[rb]" % [p.name, tname]
		var bb := "[center][b][font_size=%d]%s[/font_size][/b][/center]\n" % [UITheme.fs(16) if compact else UITheme.fs(18), name_line]
		bb += "[center][color=lightgray]生命 %d / %d　手牌 %d[/color][/center]\n" % [p.hp, p.max_hp, p.hand.size()]
		var st_parts: Array[String] = []
		for s in p.status_ids():
			var n := p.status_layer(s)
			var s_label := _status_display_name(s)
			if n > 1:
				s_label += "×%d" % n
			st_parts.append("[url=st:%s]%s[/url]" % [s, s_label])
		if p.scab > 0:
			st_parts.append("[url=scab]「痂」%d[/url]" % p.scab)
		if p.dying:
			st_parts.append("[url=dying]「濒死」[/url]")
		if p.dead:
			st_parts.append("[url=dead]「死亡」[/url]")
		if not st_parts.is_empty():
			var st_joined := ""
			for part in st_parts:
				if st_joined != "":
					st_joined += " "
				st_joined += part
			bb += "[center][color=gold]%s[/color][/center]\n" % st_joined
		# 预备区（对手可见全部内容）与陷阱（对手仅见数量），卡名可点击查阅
		var rv_names: Array[String] = []
		for rv in p.reserve:
			rv_names.append("[url=card:%s]%s[/url]" % [rv, String(g.db.get_card(rv).get("name", rv))])
		var rv_joined := ""
		for nm in rv_names:
			if rv_joined != "":
				rv_joined += "、"
			rv_joined += nm
		bb += "[center][color=plum]预备区：%s[/color]　[color=orange]陷阱 ×%d[/color][/center]" % [(rv_joined if rv_joined != "" else "无"), p.traps.size()]
		player_labels[i].text = bb
		# 信息行：属性 + 装备（状态已移动到上方状态栏，点击可查阅）
		# compact 时技能 chips 也并入本行，省掉一整行高度
		var info_row: HBoxContainer = player_info_rows[i]
		var skill_row: HBoxContainer = player_skill_rows[i]
		var chip_row: HBoxContainer = info_row if compact else skill_row
		var chip_size := _mini_btn_size(compact)
		for c in info_row.get_children():
			c.queue_free()
		for c in skill_row.get_children():
			c.queue_free()
		for aid in p.attribute_ids:
			var attr := g.db.get_attribute(aid)
			var attr_btn := Button.new()
			attr_btn.text = String(attr.get("name", aid))
			attr_btn.add_theme_font_size_override("font_size", UITheme.fs(10))
			attr_btn.custom_minimum_size = chip_size
			attr_btn.tooltip_text = String(attr.get("name", "属性"))
			var attr_desc := String(attr.get("description", ""))
			var attr_name := String(attr.get("name", "属性"))
			attr_btn.pressed.connect(func(): _show_info(attr_name, attr_desc))
			info_row.add_child(attr_btn)
		if not p.equipment.is_empty():
			var eq_label := Label.new()
			eq_label.text = "装备:"
			eq_label.add_theme_font_size_override("font_size", UITheme.fs(10))
			eq_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			info_row.add_child(eq_label)
			for eq in p.equipment:
				var eq_card := g.db.get_card(eq)
				var eb := Button.new()
				eb.text = String(eq_card.get("name", eq))
				eb.add_theme_font_size_override("font_size", UITheme.fs(10))
				eb.custom_minimum_size = chip_size
				eb.tooltip_text = String(eq_card.get("name", eq))
				var eq_desc := String(eq_card.get("description", ""))
				var eq_name := String(eq_card.get("name", eq))
				eb.pressed.connect(func(): _show_info(eq_name, eq_desc))
				info_row.add_child(eb)
		# 技能行（compact 时并入信息行）
		for sid in p.skill_ids:
			var sk := g.db.get_skill(sid)
			var sb := Button.new()
			sb.text = String(sk.get("name", sid))
			sb.add_theme_font_size_override("font_size", UITheme.fs(10))
			sb.custom_minimum_size = chip_size
			sb.tooltip_text = String(sk.get("name", sid))
			var sk_desc := String(sk.get("description", ""))
			var sk_name := String(sk.get("name", sid))
			sb.pressed.connect(func(): _show_info(sk_name, sk_desc))
			chip_row.add_child(sb)
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
		if String(g.pending.get("kind", "")) == AtlasGame.PENDING_DYING_SAVE:
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
	var reserve_clickable := g.mode == AtlasGame.Mode.RESPONSE and String(g.pending.get("kind", "")) == AtlasGame.PENDING_DAMAGE
	var leap_playable := g.mode == AtlasGame.Mode.PLAY and view == g.players[g.current] and not view.leap_reserve.is_empty()
	var reserve_hint := ""
	if reserve_clickable:
		reserve_hint = "—— 响应中，可点击防御牌直接使用"
	elif leap_playable:
		reserve_hint = "—— 〖跃迁〗扣置牌可点击打出"
	reserve_title.text = "%s 的预备区（%d）%s" % [view.name, view.reserve.size(), reserve_hint]
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
		var first_cid := view.reserve[first_idx]
		var first_card := g.db.get_card(first_cid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(160, 52) if UITheme.is_mobile() else Vector2(140, 40)
		var stack_name := String(first_card.get("name", ""))
		if view.leap_reserve.has(first_cid):
			stack_name += "［跃迁］"
		b.text = "%s x%d" % [stack_name, indices.size()]
		b.add_theme_font_size_override("font_size", UITheme.fs(13))
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(first_card)))
		b.disabled = not ((reserve_clickable and bool(first_card.get("is_defense", false))) or (leap_playable and view.leap_reserve.has(first_cid)))
		var idx := first_idx
		b.pressed.connect(func(): _on_reserve(idx))
		reserve_box.add_child(b)
	# 非防御牌单独显示
	for i in other_cards:
		var cid := view.reserve[i]
		var card := g.db.get_card(cid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(160, 52) if UITheme.is_mobile() else Vector2(140, 40)
		var cname := String(card.get("name", cid))
		if view.leap_reserve.has(cid):
			cname += "［跃迁］"
		b.text = cname
		b.add_theme_font_size_override("font_size", UITheme.fs(13))
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(card)))
		b.disabled = not (leap_playable and view.leap_reserve.has(cid))
		var ri: int = i
		b.pressed.connect(func(): _on_reserve(ri))
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
			if kind == AtlasGame.PENDING_SKIP_RESPONSE:
				hand_title.text = "[响应中] %s 的手牌（只能打出【跳过】抵消）" % view.name
			elif kind == AtlasGame.PENDING_DYING_SAVE:
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
	# 手牌排版：按可用宽度算出每行张数（自动换行），再把可用高度均分给每行，
	# 让卡牌撑满手牌区；行数变多时高度自动收缩，下限 72px。
	var lay := _hand_layout(view.hand.size())
	var card_h: float = lay["card_h"]
	for i in view.hand.size():
		var cid := view.hand[i]
		var card := g.db.get_card(cid)
		var b := DraggableCard.new()
		b.hand_index = i
		b.main_scene = self
		b.custom_minimum_size = Vector2(HAND_CARD_WIDTH, card_h)
		b.text = "%s\n%s" % [String(card.get("name", cid)), String(card.get("description", ""))]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", UITheme.fs(12))
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(card)))
		b.disabled = not clickable
		var idx := i
		b.pressed.connect(func(): _on_card(idx))
		hand_box.add_child(b)
	# 手牌区的实际尺寸要等布局完成才稳定，下一帧按真实高度再校正一次
	call_deferred("_fit_hand_cards")

	# 提示与操作按钮
	match g.mode:
		AtlasGame.Mode.PLAY:
			prompt_label.text = "出牌阶段：点击手牌打出；可使用技能；完毕后点「结束出牌阶段」。"
		AtlasGame.Mode.SELECT_TARGET:
			prompt_label.text = "请点击上方高亮的玩家面板选择目标。"
		AtlasGame.Mode.RESPONSE:
			var kind := String(g.pending.get("kind", ""))
			if kind == AtlasGame.PENDING_SKIP_RESPONSE:
				prompt_label.text = "响应窗口：%s 即将获得「跳过」。打出另一张【跳过】抵消，或点「结束响应」。" % view.name
			elif kind == AtlasGame.PENDING_DYING_SAVE:
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
			var spk := String(g.pending.get("kind", ""))
			match spk:
				AtlasGame.PENDING_PLUNDER:
					prompt_label.text = "掠夺：请在弹层中选择要夺取的牌（手牌为盲选）。"
				AtlasGame.PENDING_RIPPER_ASK:
					prompt_label.text = "〖开膛手〗：请在弹层中选择是否掠夺。"
				AtlasGame.PENDING_MACHINE:
					prompt_label.text = "〖演算机器〗：请在弹层中选择一项。"
				AtlasGame.PENDING_MILLENNIUM_ASK:
					prompt_label.text = "〖千载幽咽〗：请在弹层中选择是否再指定一名目标。"
				AtlasGame.PENDING_PRISM:
					prompt_label.text = "〖电离棱体〗：请在弹层中选择要弃掉的牌。"
				AtlasGame.PENDING_PRAYER_MODE, AtlasGame.PENDING_PRAYER_DISCARD:
					prompt_label.text = "〖祝祷〗：请在弹层中操作。"
				AtlasGame.PENDING_SHACKLE_ASK:
					prompt_label.text = "〖困兽〗：请在弹层中选择是否消耗「镣铐」。"
				AtlasGame.PENDING_FROLIC_CARD:
					prompt_label.text = "〖嬉闹〗：请在弹层中选择本回合弃掉的一张牌。"
				AtlasGame.PENDING_LEAP_TRANSITION:
					prompt_label.text = "〖跃迁〗：请在弹层中选择摸牌数量。"
				AtlasGame.PENDING_EXILE_RT_ASK:
					prompt_label.text = "〖放逐〗：请在弹层中选择是否发动。"
				AtlasGame.PENDING_SCAB_EAT:
					prompt_label.text = "〖食痂〗：请在弹层中选择是否清空「痂」。"
				AtlasGame.PENDING_REORDER_OWN, AtlasGame.PENDING_REORDER_HAND:
					prompt_label.text = "〖调序〗：请在弹层中操作。"
				_:
					prompt_label.text = "技能：请在弹层中选择。"
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
			if stype != "active" and stype != "switch" and stype != "limited":
				continue
			var b := SkillButton.new()
			b.main_scene = self
			b.skill_name = String(sk.get("name", sid))
			b.skill_desc = String(sk.get("description", ""))
			var left := int(cur.skill_uses_left.get(sid, 0))
			if stype == "limited":
				var used := bool(cur.limited_used.get(sid, false))
				b.text = "%s（%s）" % [String(sk.get("name", sid)), "已用" if used else "未用"]
				b.disabled = used
			else:
				# 次数上限 ≥99 视为不限次数（如〖聚合〗〖开棺〗），不显示剩余次数
				var max_uses := int(sk.get("max_uses_per_turn", 1))
				if max_uses >= 99:
					b.text = String(sk.get("name", sid))
					b.disabled = false
				else:
					b.text = "%s（剩%d）" % [String(sk.get("name", sid)), left]
					b.disabled = left <= 0
			b.custom_minimum_size = Vector2(0, _abtn_h())
			# 狄瑟〖沙葬〗：未觉醒时置灰不可用
			if sid == "skill_sand_burial" and not cur.star_brilliance_awakened:
				b.disabled = true
				b.text = "%s（未觉醒）" % String(sk.get("name", sid))
			if is_mobile():
				# 移动端无悬停，说明靠长按弹出；tooltip 留着只会在桌面生效
				b.tooltip_text = ""
			else:
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
		var team_name := g.winner_team_name
		# 只有「队伍数少于人数」的板子才算组队局；混战局不显示队伍名
		var board_teams: Array = g.board.get("teams", [])
		var is_team_board := board_teams.size() < g.board_player_count()
		# 组队局仅剩一名存活者时引擎不写队伍名，这里按存活者的队伍补齐
		if team_name.is_empty() and is_team_board:
			for p in g.players:
				if not p.dead:
					team_name = g._team_name(p.team_id)
					break
		if not team_name.is_empty() and is_team_board:
			game_over_label.text = "%s 获胜！\n%s" % [team_name, "、".join(g.winner_members)]
		else:
			game_over_label.text = "%s 获胜！" % g.winner

# 选人界面（规则 4.1-1）
func _rebuild_char_pick() -> void:
	for c in char_pick_box.get_children():
		c.visible = false
		c.queue_free()
	var g := game
	var picked := g.picked_char_ids.size()
	var total := g.board_player_count()
	char_pick_title.text = "请第 %d 位选择角色（已选 %d / %d）" % [picked + 1, picked, total]
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", UITheme.fs(13))
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	hint.text = "选人结束后随机分配座位与先手"
	char_pick_box.add_child(hint)
	for c in g.db.characters:
		# 牌池过滤：仅显示本局板子对应角色池中的角色
		if not g.db.entry_in_pool(c, g.pool_id):
			continue
		var cid := String(c.get("id", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(460, 76)
		b.add_theme_font_size_override("font_size", UITheme.fs(14))
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
	title.add_theme_font_size_override("font_size", UITheme.fs(20))
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	if kind == AtlasGame.PENDING_EXILE_ASK:
		title.text = "是否发动限定技〖放逐〗？"
	elif kind == AtlasGame.PENDING_SAGE:
		title.text = "〖贤者之书〗：选择一张要丢弃的牌"
	elif kind == AtlasGame.PENDING_FRACTAL:
		title.text = "〖分形几何〗：选择一张【普通攻击】转化为【防御2】"
	elif kind == AtlasGame.PENDING_LEAP:
		title.text = "〖信仰之跃〗：选择摸牌数量"
	elif kind == AtlasGame.PENDING_MERCY:
		title.text = "〖仁慈〗：请选择一项"
	elif kind == AtlasGame.PENDING_OSC_FORM:
		title.text = "〖振荡〗：请选择形态"
	elif kind == AtlasGame.PENDING_PEEP_HAND:
		title.text = "〖窥伺之眼〗：请选择一张手牌视作【窥视】"
	elif kind == AtlasGame.PENDING_SAND_BURY_HAND:
		var sub := String(game.pending.get("sub_kind", ""))
		var step := int(game.pending.get("step", 1))
		if sub == "tip_discharge":
			title.text = "〖尖端放电〗：请选择一张手牌弃置"
		elif sub == "osc_discard":
			title.text = "〖振荡〗形态①：请选择第 %d 张手牌弃置（共需 2 张）" % step
		else:
			title.text = "〖沙葬〗：请选择第 %d 张要弃置的牌（从手牌/装备/预备区中选）" % step
	elif kind == AtlasGame.PENDING_PLUNDER:
		var purpose := String(game.pending.get("purpose", ""))
		var tgt_idx := int(game.pending.get("target", game.current))
		if purpose == "ripper":
			title.text = "〖开膛手〗：选择 %s 的一张手牌（盲选）或预备区牌扣置为【陪葬品】" % game.players[tgt_idx].name
		elif purpose == "converge":
			title.text = "〖聚合〗：盲选 %s 的一张手牌" % game.players[tgt_idx].name
		else:
			title.text = "【掠夺】：盲选 %s 的一张手牌" % game.players[tgt_idx].name
	elif kind == AtlasGame.PENDING_MACHINE:
		var midx := int(game.pending.get("source", game.current))
		title.text = "%s 触发〖演算机器〗：请选择一项" % game.players[midx].name
	elif kind == AtlasGame.PENDING_RIPPER_ASK:
		var src_idx := int(game.pending.get("source", game.current))
		var tgt2 := int(game.pending.get("defender", game.current))
		title.text = "%s 是否触发〖开膛手〗掠夺 %s 的一张手牌？" % [game.players[src_idx].name, game.players[tgt2].name]
	elif kind == AtlasGame.PENDING_MILLENNIUM_ASK:
		title.text = "〖千载幽咽〗：是否再指定一名目标？"
	elif kind == AtlasGame.PENDING_PRISM:
		title.text = "〖电离棱体〗：选择你区域中要弃掉的 1 张牌"
	elif kind == AtlasGame.PENDING_PRAYER_MODE:
		title.text = "〖祝祷〗：请选择回复对象"
	elif kind == AtlasGame.PENDING_PRAYER_DISCARD:
		var step2 := int(game.pending.get("step", 1))
		title.text = "〖祝祷〗：请选择第 %d 张要弃掉的牌（共需 2 张）" % step2
	elif kind == AtlasGame.PENDING_SHACKLE_ASK:
		title.text = "〖困兽〗：是否消耗一层「镣铐」防止本次伤害？"
	elif kind == AtlasGame.PENDING_FROLIC_CARD:
		title.text = "〖嬉闹〗：选择一张本回合弃掉的牌"
	elif kind == AtlasGame.PENDING_LEAP_TRANSITION:
		title.text = "〖跃迁〗：选择摸牌数量（扣置于预备区）"
	elif kind == AtlasGame.PENDING_EXILE_RT_ASK:
		title.text = "是否发动限定技〖放逐〗？"
	elif kind == AtlasGame.PENDING_SCAB_EAT:
		title.text = "〖食痂〗：是否清空所有「痂」回复等量生命？"
	elif kind == AtlasGame.PENDING_REORDER_OWN:
		title.text = "〖调序〗：选择你的一张牌弃置"
	elif kind == AtlasGame.PENDING_REORDER_HAND:
		var tgt3 := int(game.pending.get("target", game.current))
		title.text = "〖调序〗：盲选 %s 的一张手牌弃置" % game.players[tgt3].name
	elif kind == "judge_prompt":
		title.text = "%s：请选择一项" % String(game.pending.get("source_name", "判定失败"))
	else:
		title.text = "%s：选择一张加入手牌" % String(sk.get("name", "技能"))
	skill_pick_box.add_child(title)
	if kind == AtlasGame.PENDING_EXILE_ASK:
		var yes := Button.new()
		yes.text = "发动〖放逐〗"
		yes.custom_minimum_size = _overlay_btn_size(280, 48)
		yes.pressed.connect(func(): _on_skill_pick("yes"))
		skill_pick_box.add_child(yes)
		var no := Button.new()
		no.text = "放弃"
		no.custom_minimum_size = _overlay_btn_size(280, 44)
		no.pressed.connect(func(): _on_skill_pick("no"))
		skill_pick_box.add_child(no)
		return
	for opt in game.pending.get("options", []):
		var token := String(opt)
		var tok := token
		var b := Button.new()
		var card: Dictionary = {"type": "basic"}
		var label := token
		if kind == "skill_retrieve":
			card = game.db.get_card(token)
			label = String(card.get("name", token))
		elif kind == "leap":
			label = "摸 %s 张（失去 %d 点生命）" % [token, int(token) * 2]
		elif kind == AtlasGame.PENDING_MERCY:
			if token == "lose_hp":
				label = "① 失去 2 点生命"
			else:
				label = "② 对自己施加一层「止戈」"
			card = {}
		elif kind == AtlasGame.PENDING_OSC_FORM:
			if token == "form_1":
				label = "① 弃掉两张手牌，视作对一名其他玩家使用【跳过】"
			else:
				label = "② 摸两张牌，并对自己施加「跳过」"
			card = {}
		elif kind == "judge_prompt":
			# 来自判定 prompt_choice 的选项，token 直接作为 label
			var choices: Array = game.pending.get("choices", [])
			var idx := int(token) if token.is_valid_int() else -1
			if idx >= 0 and idx < choices.size():
				var choice: Dictionary = choices[idx]
				label = String(choice.get("label", token))
			card = {}
		elif kind == AtlasGame.PENDING_PLUNDER:
			# 掠夺：手牌盲选（只显示序号与背面），公开区域显示目标玩家的实际牌名
			var parts_p := token.split(":")
			var tgt_idx := int(game.pending.get("target", game.current))
			var tp: PlayerData = game.players[tgt_idx]
			var zi := int(parts_p[1]) if parts_p.size() > 1 else -1
			if parts_p[0] == "hand":
				label = "手牌 #%d（背面朝上）" % (zi + 1)
				card = {"type": "basic"}
			else:
				var cid_p := ""
				if parts_p[0] == "equip" and zi >= 0 and zi < tp.equipment.size():
					cid_p = tp.equipment[zi]
				elif parts_p[0] == "reserve" and zi >= 0 and zi < tp.reserve.size():
					cid_p = tp.reserve[zi]
				elif parts_p[0] == "trap" and zi >= 0 and zi < tp.traps.size():
					cid_p = tp.traps[zi]
				card = game.db.get_card(cid_p)
				var zn := "装备区"
				if parts_p[0] == "reserve":
					zn = "预备区"
				elif parts_p[0] == "trap":
					zn = "陷阱区"
				label = "%s：%s" % [zn, String(card.get("name", cid_p))]
		elif kind == AtlasGame.PENDING_MACHINE:
			if token == "draw":
				label = "① 摸一张牌"
			elif token == "heal":
				label = "② 回复 2 点生命"
			else:
				label = "放弃"
			card = {}
		elif kind == AtlasGame.PENDING_RIPPER_ASK:
			label = "掠夺其一张手牌" if token == "yes" else "放弃"
			card = {}
		elif kind == AtlasGame.PENDING_MILLENNIUM_ASK:
			label = "再指定一名目标" if token == "more" else "完成指定"
			card = {}
		elif kind == AtlasGame.PENDING_PRAYER_MODE:
			label = "为自己回复 3 点生命" if token == "self" else "为一名其他玩家回复生命"
			card = {}
		elif kind == AtlasGame.PENDING_SHACKLE_ASK:
			label = "消耗一层「镣铐」防止本次伤害" if token == "yes" else "不防止，正常结算"
			card = {}
		elif kind == AtlasGame.PENDING_EXILE_RT_ASK:
			label = "发动〖放逐〗：清空一名其他玩家的所有区域" if token == "yes" else "放弃"
			card = {}
		elif kind == AtlasGame.PENDING_SCAB_EAT:
			label = "清空「痂」并回复等量生命" if token == "yes" else "保留「痂」"
			card = {}
		elif kind == AtlasGame.PENDING_LEAP_TRANSITION:
			label = "摸 %s 张扣置预备区（失去 %d 点生命）" % [token, int(token) * 2]
			card = {}
		elif kind == AtlasGame.PENDING_FROLIC_CARD:
			# 嬉闹：token 形如 "frolic:N"，指向本回合弃牌记录
			var fidx := int(token.split(":")[1])
			var fcid := ""
			var fdisc: Array = game.players[game.current].own_turn_discards
			if fidx >= 0 and fidx < fdisc.size():
				fcid = String(fdisc[fidx])
			card = game.db.get_card(fcid)
			label = "本回合弃掉：%s" % String(card.get("name", fcid))
		elif kind == AtlasGame.PENDING_REORDER_OWN:
			# 调序：操作者是触发玩家（pending.source），通常并非当前回合玩家，牌名要按其区域解析
			var ridx2 := int(game.pending.get("source", game.current))
			var rp2 := game.players[ridx2]
			var parts2 := token.split(":")
			var zidx := int(parts2[1]) if parts2.size() > 1 else -1
			var rcid := ""
			var zname := "手牌"
			if parts2[0] == "reserve":
				zname = "预备区·跃迁扣置"
				if zidx >= 0 and zidx < rp2.reserve.size():
					rcid = rp2.reserve[zidx]
			elif zidx >= 0 and zidx < rp2.hand.size():
				rcid = rp2.hand[zidx]
			card = game.db.get_card(rcid)
			label = "%s：%s" % [zname, String(card.get("name", rcid))]
		elif kind == AtlasGame.PENDING_REORDER_HAND:
			label = "手牌 #%d（背面朝上）" % (int(token.split(":")[1]) + 1)
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
			label = "%s：%s" % [zone_name, String(card.get("name", cid))]
		b.text = label
		b.custom_minimum_size = _overlay_btn_size(320, 48)
		UITheme.style_button(b, UITheme.card_styles(UITheme.card_color(card)))
		b.pressed.connect(func(): _on_skill_pick(tok))
		skill_pick_box.add_child(b)
	# 掠夺/开膛手询问（含明确「放弃」项）及溯形态强制询问不显示取消按钮
	var hide_cancel := kind == AtlasGame.PENDING_PLUNDER or kind == AtlasGame.PENDING_RIPPER_ASK \
		or kind == AtlasGame.PENDING_SHACKLE_ASK or kind == AtlasGame.PENDING_EXILE_RT_ASK \
		or kind == AtlasGame.PENDING_SCAB_EAT
	if not hide_cancel:
		var cancel := Button.new()
		cancel.text = "取消"
		cancel.custom_minimum_size = _overlay_btn_size(280, 44)
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
	title.add_theme_font_size_override("font_size", UITheme.fs(20))
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
		cancel.custom_minimum_size = _overlay_btn_size(320, 44)
		cancel.pressed.connect(_on_cancel_discard_pick)
		discard_pick_box.add_child(cancel)

# ---------------- 事件回调 ----------------

func _on_log(text: String) -> void:
	log_label.append_text(text + "\n")

func _on_panel(i: int) -> void:
	# 富文本链接与面板点击来自同一次鼠标释放：延迟到本帧末再判断，
	# 若同一次点击刚触发过链接（meta_clicked）就忽略面板选目标。
	call_deferred("_apply_panel_click", i)

func _apply_panel_click(i: int) -> void:
	# 同一次鼠标释放既命中链接又命中面板按钮时，只保留链接（查看说明）的行为
	if Engine.get_process_frames() == _meta_click_frame:
		return
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
	if game.mode == AtlasGame.Mode.PLAY:
		game.ui_play_reserve_card(i)
	else:
		game.ui_play_reserve(i)
	_refresh()

# ---------------- 手牌排版 ----------------

func _hand_layout(count: int) -> Dictionary:
	## 按手牌区实际尺寸计算每行张数与卡牌高度，让卡牌撑满可用空间
	var avail_w := 1252.0
	if hand_scroll != null and hand_scroll.size.x > HAND_CARD_WIDTH:
		avail_w = hand_scroll.size.x - 8.0
	var per_row := maxi(1, int((avail_w + HAND_CARD_SEP) / (HAND_CARD_WIDTH + HAND_CARD_SEP)))
	var rows := maxi(1, int(ceil(float(maxi(1, count)) / float(per_row))))
	var avail_h := 150.0
	if hand_scroll != null and hand_scroll.size.y > 0.0:
		avail_h = hand_scroll.size.y - 8.0
	var card_h := clampf((avail_h - float(rows - 1) * HAND_CARD_SEP) / float(rows), 72.0, 260.0)
	return {"per_row": per_row, "card_h": card_h}

func _fit_hand_cards() -> void:
	## 布局稳定后校正卡牌高度（首帧尺寸未定、窗口尺寸变化时调用）
	if hand_box == null:
		return
	var count := 0
	for c in hand_box.get_children():
		if not c.is_queued_for_deletion():
			count += 1
	if count == 0:
		return
	var card_h: float = _hand_layout(count)["card_h"]
	for c in hand_box.get_children():
		if c.is_queued_for_deletion():
			continue
		var ctl := c as Control
		if absf(ctl.custom_minimum_size.y - card_h) > 0.5:
			ctl.custom_minimum_size.y = card_h

func _on_skill(id: String) -> void:
	# 长按查看说明后抬起会触发 pressed，本次不发动技能
	if _skill_long_press:
		_skill_long_press = false
		return
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
	# F12：开关开发者菜单（仅调试构建）
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F12:
		if OS.is_debug_build():
			_toggle_dev_menu()
			get_viewport().set_input_as_handled()
		return
	# Esc：与移动端返回键同语义——取消当前瞬态，绝不退出应用
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if _on_back_pressed():
			get_viewport().set_input_as_handled()
		return
	# 右键取消当前选目标操作（用 _input 而非 _unhandled_input，避免被面板等控件吞掉事件）
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if game != null and game.mode == AtlasGame.Mode.SELECT_TARGET:
		_on_cancel_target()
		get_viewport().set_input_as_handled()

## 返回键 / Esc 统一入口：按优先级取消当前瞬态。返回 true 表示已消费。
## 说明弹层 > 技能选择 > 选目标 > 事件确认；对局主界面与选人/终局层不响应，防止误退。
func _on_back_pressed() -> bool:
	if info_popup != null and info_popup.visible:
		info_popup.visible = false
		return true
	if skill_pick_layer != null and skill_pick_layer.visible:
		_on_cancel_skill_pick()
		return true
	if game != null and game.mode == AtlasGame.Mode.SELECT_TARGET:
		_on_cancel_target()
		return true
	if event_show_layer != null and event_show_layer.visible:
		_on_event_show_confirm()
		return true
	return false

func _toggle_dev_menu() -> void:
	if dev_menu == null:
		return
	if dev_menu.visible:
		dev_menu.visible = false
	else:
		dev_menu.visible = true
		dev_menu.rebuild()

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

# 玩家面板富文本词条点击：状态 / 痂 / 濒死 / 死亡 / 预备区卡牌
func _on_player_meta(meta: String) -> void:
	_meta_click_frame = Engine.get_process_frames()
	if meta.begins_with("st:"):
		var sid := meta.substr(3)
		_show_info(_status_display_name(sid), _status_desc(sid))
	elif meta == "scab":
		_show_info("「痂」", "你的回合外受到伤害时，将其中 40%（向上取整）记录为「痂」。你的回合开始时，回复与「痂」记录值相等的生命并清空记录。")
	elif meta == "dying":
		_show_info("「濒死」", "生命值为 0，进入濒死状态。按座位顺序询问救援，任意玩家可打出食物牌（视为濒死角色使用）；未被救活则宣布死亡。")
	elif meta == "dead":
		_show_info("「死亡」", "该玩家已死亡，退出本局对战。")
	elif meta.begins_with("card:"):
		var cid := meta.substr(5)
		var c := game.db.get_card(cid)
		_show_info(String(c.get("name", cid)), String(c.get("description", "")))

func _status_display_name(status_id: String) -> String:
	# 优先取 statuses.json 中的名称，回退到硬编码表，最后显示 id
	var st: Dictionary = game.db.get_status(status_id)
	if st.has("name"):
		return String(st["name"])
	return String(AtlasGame.STATUS_NAMES.get(status_id, status_id))

func _status_desc(status_id: String) -> String:
	# 优先取 statuses.json 中的描述
	var st: Dictionary = game.db.get_status(status_id)
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
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android 返回键：只用于取消当前瞬态，绝不退出应用
		_on_back_pressed()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		# 切后台再回来：pending 上下文在引擎内存中不丢，重绘一次 UI 即可
		if game != null:
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
	return game._target_candidates_for(game.current, ttype, "").has(p_idx)

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
