extends Control

## 启动器：选择板子进入对战，或进入数据编辑器。

const MAIN_SCENE := "res://scenes/main.tscn"

var _db: CardDB = null
var _picker: ColorRect = null
var _picker_box: VBoxContainer = null
var _sel_board: String = ""       # 弹层内已选模式（板子人数配置）
var _sel_pool: String = "classic" # 弹层内已选牌池（经典 / 溯洄之境）

func _ready() -> void:
	theme = UITheme.make_theme(18)
	UITheme.add_background(self)
	_db = CardDB.new()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "天光墟纪事"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "A T L A S ・ 本 地 热 座 卡 牌 对 战"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(sub)

	var line := HSeparator.new()
	var lsb := StyleBoxLine.new()
	lsb.color = UITheme.ACCENT.darkened(0.25)
	lsb.thickness = 2
	line.add_theme_stylebox_override("separator", lsb)
	box.add_child(line)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	box.add_child(pad)

	var play_btn := _menu_button("开始对战", true)
	play_btn.pressed.connect(_show_board_picker)
	box.add_child(play_btn)

	var editor_btn := _menu_button("数据编辑器", false)
	editor_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/editor.tscn"))
	# 数据编辑器是桌面专属，移动端不移植、不显示入口
	editor_btn.visible = OS.get_name() != "Android" and OS.get_name() != "iOS"
	box.add_child(editor_btn)

	var quit_btn := _menu_button("退出", false)
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 62)
	b.add_theme_font_size_override("font_size", UITheme.fs(20))
	if primary:
		UITheme.style_button(b, UITheme.accent_button_styles())
	return b

func _input(event: InputEvent) -> void:
	# Esc / 返回键：板子选择弹层打开时仅关闭弹层
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if _picker != null and _picker.visible:
			_picker.visible = false
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _picker != null and _picker.visible:
			_picker.visible = false
		# 启动器主界面不拦截返回键，交给系统默认行为（退出应用）

# ---------------- 模式与板子选择（多人对战入口） ----------------

func _show_board_picker() -> void:
	if _picker == null:
		_build_board_picker()
	# 每次打开重置选择状态：先选模式，再切换板子，最后点开始游戏
	_sel_board = ""
	_sel_pool = "classic"
	_rebuild_picker()
	_picker.visible = true

func _build_board_picker() -> void:
	_picker = ColorRect.new()
	_picker.color = Color(0.03, 0.04, 0.06, 0.85)
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_picker)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(center)
	_picker_box = VBoxContainer.new()
	_picker_box.add_theme_constant_override("separation", 12)
	center.add_child(_picker_box)

func _rebuild_picker() -> void:
	for c in _picker_box.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "选择对战模式"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	_picker_box.add_child(title)

	var hint := Label.new()
	hint.text = "座位与先手将在选人结束后随机分配"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_picker_box.add_child(hint)

	_picker_box.add_child(HSeparator.new())

	# 1. 模式（原 1v1 / 1v1v1 / 2v2 板子）
	if _db.boards.is_empty():
		var fallback := _menu_button("双人对决　·　2 人 / 2 队", true)
		fallback.pressed.connect(func(): _select_board("board_1v1"))
		_picker_box.add_child(fallback)
	else:
		for b in _db.boards:
			var count := int(b.get("player_count", 2))
			var teams: Array = b.get("teams", [])
			var bid := String(b.get("id", ""))
			var btn := _menu_button("%s　·　%d 人 / %d 队" % [String(b.get("name", "对局")), count, teams.size()], bid == _sel_board)
			btn.pressed.connect(func(): _select_board(bid))
			_picker_box.add_child(btn)

	# 2. 选定模式后：板子切换入口（在开始游戏按钮上方）+ 开始游戏
	if not _sel_board.is_empty():
		var pool_label := Label.new()
		pool_label.text = "板子"
		pool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pool_label.add_theme_font_size_override("font_size", 15)
		pool_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_picker_box.add_child(pool_label)

		var pool_row := HBoxContainer.new()
		pool_row.alignment = BoxContainer.ALIGNMENT_CENTER
		pool_row.add_theme_constant_override("separation", 10)
		_picker_box.add_child(pool_row)
		for p in CardDB.POOLS:
			var pid := String(p.get("id", ""))
			var pb := Button.new()
			pb.text = String(p.get("name", pid))
			pb.custom_minimum_size = Vector2(155, 48)
			pb.add_theme_font_size_override("font_size", UITheme.fs(16))
			if pid == _sel_pool:
				UITheme.style_button(pb, UITheme.accent_button_styles())
			pool_row.add_child(pb)
			pb.pressed.connect(func(): _select_pool(pid))

		var start := _menu_button("开始游戏", true)
		start.pressed.connect(func(): _start_board(_sel_board))
		_picker_box.add_child(start)

	var back := _menu_button("返回", false)
	back.pressed.connect(func(): _picker.visible = false)
	_picker_box.add_child(back)

func _select_board(bid: String) -> void:
	_sel_board = bid
	_rebuild_picker()

func _select_pool(pid: String) -> void:
	_sel_pool = pid
	_rebuild_picker()

func _start_board(board_id: String) -> void:
	GameSession.board_id = board_id
	GameSession.pool_id = _sel_pool
	get_tree().change_scene_to_file(MAIN_SCENE)
