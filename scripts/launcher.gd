extends Control

## 启动器：选择板子进入对战，或进入数据编辑器。

const MAIN_SCENE := "res://scenes/main.tscn"

var _db: CardDB = null
var _picker: ColorRect = null

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
	box.add_child(editor_btn)

	var quit_btn := _menu_button("退出", false)
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

func _menu_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 62)
	b.add_theme_font_size_override("font_size", 20)
	if primary:
		UITheme.style_button(b, UITheme.accent_button_styles())
	return b

# ---------------- 板子选择（多人对战入口） ----------------

func _show_board_picker() -> void:
	if _picker == null:
		_build_board_picker()
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
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "选择对战板子"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "座位与先手将在选人结束后随机分配"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(hint)

	box.add_child(HSeparator.new())

	if _db.boards.is_empty():
		var fallback := _menu_button("双人对决　·　2 人 / 2 队", true)
		fallback.pressed.connect(func(): _start_board("board_1v1"))
		box.add_child(fallback)
	else:
		for b in _db.boards:
			var count := int(b.get("player_count", 2))
			var teams: Array = b.get("teams", [])
			var btn := _menu_button("%s　·　%d 人 / %d 队" % [String(b.get("name", "对局")), count, teams.size()], count == 2)
			var bid := String(b.get("id", ""))
			btn.pressed.connect(func(): _start_board(bid))
			box.add_child(btn)

	var back := _menu_button("返回", false)
	back.pressed.connect(func(): _picker.visible = false)
	box.add_child(back)

func _start_board(board_id: String) -> void:
	GameSession.board_id = board_id
	get_tree().change_scene_to_file(MAIN_SCENE)
