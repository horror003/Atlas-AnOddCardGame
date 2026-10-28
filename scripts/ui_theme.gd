class_name UITheme
extends RefCounted

## 全局 UI 样式工具：统一深色主题、配色与按钮/卡牌风格。
## 所有界面（启动器/对战/编辑器）共用，保证视觉一致。

# ---- 基础配色 ----
const BG_DEEP := Color(0.055, 0.065, 0.095)      # 深空底色
const BG_PANEL := Color(0.105, 0.12, 0.165)      # 面板底
const BG_CARD := Color(0.15, 0.17, 0.23)         # 卡片/按钮底
const BG_INPUT := Color(0.075, 0.085, 0.115)     # 输入区底
const BORDER := Color(0.30, 0.33, 0.40)          # 常规描边
const ACCENT := Color(0.87, 0.71, 0.38)          # 天光金
const TEXT_MAIN := Color(0.93, 0.92, 0.88)
const TEXT_DIM := Color(0.60, 0.63, 0.68)
const DANGER := Color(0.88, 0.34, 0.32)
const OK := Color(0.42, 0.85, 0.50)

# ---------------- 移动端适配 ----------------

## 是否移动端（触屏设备）。ATLAS_MOBILE 环境变量用于在桌面模拟移动端布局调试。
static func is_mobile() -> bool:
	return OS.get_name() == "Android" or OS.get_name() == "iOS" or OS.has_environment("ATLAS_MOBILE")

## 触屏点击目标放大系数：可点元素短边 ≥ 44dp ≈ 56+ 逻辑像素
static func touch_scale() -> float:
	return 1.6 if is_mobile() else 1.0

## 移动端字号整体放大一档
static func fs(base: int) -> int:
	return base + 3 if is_mobile() else base

# ---------------- 基础构造 ----------------

static func flat(bg: Color, border: Color, radius: int = 8, bw: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb

static func button_styles(bg: Color, border: Color) -> Dictionary:
	return {
		"normal": flat(bg, border, 6, 1),
		"hover": flat(bg.lightened(0.12), border.lightened(0.25), 6, 1),
		"pressed": flat(bg.darkened(0.25), border, 6, 1),
		"disabled": flat(Color(bg.r, bg.g, bg.b, 0.45), border.darkened(0.4), 6, 1),
		"focus": StyleBoxEmpty.new(),
	}

static func accent_button_styles() -> Dictionary:
	return button_styles(Color(0.30, 0.235, 0.10), ACCENT)

static func danger_button_styles() -> Dictionary:
	return button_styles(Color(0.32, 0.12, 0.11), DANGER)

static func skill_button_styles() -> Dictionary:
	return button_styles(Color(0.185, 0.13, 0.26), Color(0.62, 0.44, 0.85))

static func style_button(btn: Button, styles: Dictionary) -> void:
	for k in styles.keys():
		btn.add_theme_stylebox_override(k, styles[k])

# ---------------- 卡牌着色 ----------------

static func damage_type_color(dt: String) -> Color:
	match dt:
		"physical": return Color(0.82, 0.36, 0.33)   # 物理：红
		"magical": return Color(0.38, 0.60, 0.88)    # 法术：蓝
		"soul": return Color(0.64, 0.45, 0.87)       # 灵魂：紫
		"hp_loss": return Color(0.62, 0.62, 0.64)    # 生命流失：灰
	return Color(0.55, 0.60, 0.68)

static func card_color(card: Dictionary) -> Color:
	var t := String(card.get("type", ""))
	var sub := String(card.get("subtype", ""))
	match t:
		"basic":
			match sub:
				"attack": return damage_type_color("physical")
				"defense": return Color(0.40, 0.68, 0.74)    # 防御：青
				"control": return Color(0.68, 0.54, 0.80)
				"support": return Color(0.44, 0.74, 0.62)
				"event": return Color(0.74, 0.64, 0.44)
			return Color(0.55, 0.60, 0.68)
		"special_attack":
			var dt := card_damage_type(card)
			return damage_type_color(dt if dt != "" else "physical")
		"food": return Color(0.44, 0.76, 0.44)               # 食物：绿
		"equipment": return ACCENT                            # 装备：金
		"trap": return Color(0.88, 0.56, 0.28)               # 陷阱：橙
		"delayed_judge": return Color(0.62, 0.50, 0.87)      # 判定：紫
	return Color(0.55, 0.60, 0.68)

static func card_damage_type(card: Dictionary) -> String:
	for eff in card.get("effects", []):
		for act in eff.get("actions", []):
			if String(act.get("type", "")) == "deal_damage":
				return String(act.get("damage_type", "physical"))
	return ""

static func card_styles(c: Color) -> Dictionary:
	return {
		"normal": flat(c.darkened(0.74).lerp(BG_CARD, 0.25), c, 8, 2),
		"hover": flat(c.darkened(0.58), c.lightened(0.3), 8, 2),
		"pressed": flat(c.darkened(0.85), c, 8, 2),
		"disabled": flat(Color(0.09, 0.10, 0.12), c.darkened(0.55), 8, 2),
		"focus": StyleBoxEmpty.new(),
	}

# ---------------- 整体主题 ----------------

static func add_background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)

static func make_theme(font_size: int = 16) -> Theme:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Microsoft YaHei", "SimHei", "PingFang SC", "sans-serif"])
	var th := Theme.new()
	th.default_font = sys
	th.default_font_size = font_size
	# 伪斜体：中文字体没有斜体变体，BBCode [i] 默认无效；
	# 用 FontVariation 的剪切变换合成斜体，供 RichTextLabel 的 [i]/[bi] 使用
	var italic := FontVariation.new()
	italic.base_font = sys
	italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.22, 1), Vector2.ZERO)
	th.set_font("italics_font", "RichTextLabel", italic)
	th.set_font("bold_italics_font", "RichTextLabel", italic)

	# 文字颜色
	th.set_color("font_color", "Label", TEXT_MAIN)
	th.set_color("default_color", "RichTextLabel", TEXT_MAIN)
	th.set_color("font_color", "Button", TEXT_MAIN)
	th.set_color("font_hover_color", "Button", TEXT_MAIN)
	th.set_color("font_pressed_color", "Button", ACCENT)
	th.set_color("font_disabled_color", "Button", TEXT_DIM)
	th.set_color("font_color", "LineEdit", TEXT_MAIN)
	th.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	th.set_color("font_color", "TextEdit", TEXT_MAIN)
	th.set_color("font_color", "ItemList", TEXT_MAIN)
	th.set_color("font_hovered_color", "ItemList", ACCENT)
	th.set_color("font_color", "CheckBox", TEXT_MAIN)
	th.set_color("font_color", "OptionButton", TEXT_MAIN)

	# 按钮
	var bs := button_styles(BG_CARD, BORDER)
	th.set_stylebox("normal", "Button", bs["normal"])
	th.set_stylebox("hover", "Button", bs["hover"])
	th.set_stylebox("pressed", "Button", bs["pressed"])
	th.set_stylebox("disabled", "Button", bs["disabled"])
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# 面板
	th.set_stylebox("panel", "PanelContainer", flat(BG_PANEL, BORDER, 8, 1))
	th.set_stylebox("panel", "Panel", flat(BG_PANEL, BORDER, 8, 1))

	# 输入控件
	th.set_stylebox("normal", "LineEdit", flat(BG_INPUT, BORDER, 6, 1))
	th.set_stylebox("focus", "LineEdit", flat(BG_INPUT, ACCENT, 6, 1))
	th.set_stylebox("normal", "TextEdit", flat(BG_INPUT, BORDER, 6, 1))
	th.set_stylebox("focus", "TextEdit", flat(BG_INPUT, ACCENT, 6, 1))

	# 列表
	th.set_stylebox("panel", "ItemList", flat(BG_INPUT, BORDER, 6, 1))
	th.set_stylebox("selected", "ItemList", flat(Color(0.24, 0.20, 0.10), ACCENT, 4, 1))
	th.set_stylebox("selected_focus", "ItemList", flat(Color(0.24, 0.20, 0.10), ACCENT, 4, 1))

	# 下拉框及其弹层
	th.set_stylebox("normal", "OptionButton", bs["normal"])
	th.set_stylebox("hover", "OptionButton", bs["hover"])
	th.set_stylebox("pressed", "OptionButton", bs["pressed"])
	th.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	th.set_stylebox("panel", "PopupMenu", flat(BG_PANEL, BORDER, 6, 1))
	th.set_stylebox("hover", "PopupMenu", flat(Color(0.24, 0.20, 0.10), ACCENT, 4, 1))
	th.set_color("font_color", "PopupMenu", TEXT_MAIN)
	th.set_color("font_hover_color", "PopupMenu", ACCENT)

	# 分隔线
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	th.set_stylebox("separator", "HSeparator", sep)
	th.set_stylebox("separator", "VSeparator", sep)

	# 滚动条
	var grab := flat(Color(0.30, 0.33, 0.40), Color(0.30, 0.33, 0.40), 4, 0)
	var grab_hi := flat(Color(0.42, 0.45, 0.53), Color(0.42, 0.45, 0.53), 4, 0)
	var trough := flat(Color(0.07, 0.08, 0.10), Color(0.07, 0.08, 0.10), 4, 0)
	for cls in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("grabber", cls, grab)
		th.set_stylebox("grabber_highlight", cls, grab_hi)
		th.set_stylebox("grabber_pressed", cls, grab_hi)
		th.set_stylebox("scroll", cls, trough)
		th.set_stylebox("scroll_focus", cls, trough)

	# 悬浮提示
	th.set_stylebox("panel", "TooltipPanel", flat(BG_PANEL, BORDER, 6, 1))
	th.set_color("font_color", "TooltipLabel", TEXT_MAIN)

	return th
