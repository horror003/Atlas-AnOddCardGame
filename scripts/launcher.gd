extends Control

## 启动器：选择进入对战或数据编辑器。

func _ready() -> void:
	theme = UITheme.make_theme(18)
	UITheme.add_background(self)

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
	play_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
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
