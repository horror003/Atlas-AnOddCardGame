extends Control

## 数据编辑器：可视化编辑 data/*.json（卡牌/技能/事件/属性/角色/状态/装备组合），校验后保存回 JSON。
## 布局：左侧分类 + 条目列表，右侧字段表单。复杂字段（效果/被动/判定）以 JSON 片段编辑并即时校验。

# ---- 数据文件配置 ----
const FILES := {
	"cards": "res://data/cards.json",
	"events": "res://data/events.json",
	"skills": "res://data/skills.json",
	"attributes": "res://data/attributes.json",
	"characters": "res://data/characters.json",
	"statuses": "res://data/statuses.json",
	"combos": "res://data/combos.json",
}

# 分类配置：list_key = JSON 中条目数组的键
const CATEGORIES := [
	{"key": "cards", "title": "卡牌", "list_key": "cards"},
	{"key": "skills", "title": "技能", "list_key": "skills"},
	{"key": "events", "title": "事件", "list_key": "events"},
	{"key": "attributes", "title": "属性", "list_key": "attributes"},
	{"key": "characters", "title": "角色", "list_key": "characters"},
	{"key": "statuses", "title": "状态", "list_key": "statuses"},
	{"key": "combos", "title": "装备组合", "list_key": "combos"},
]

# 字段 schema：kind = string/int/bool/multiline/json/option/string_list
# options_ref：option 的选项动态取自某分类的 id 列表
const SCHEMAS := {
	"cards": [
		{"key": "id", "label": "ID（唯一标识）", "kind": "string"},
		{"key": "name", "label": "名称（用【】括起）", "kind": "string"},
		{"key": "type", "label": "类型", "kind": "option", "options": ["basic", "special_attack", "food", "equipment", "trap", "delayed_judge"]},
		{"key": "subtype", "label": "子类型（attack/defense/weapon/armor 等）", "kind": "string"},
		{"key": "description", "label": "描述", "kind": "multiline"},
		{"key": "target_type", "label": "目标类型", "kind": "option", "options": ["none", "self", "single_any", "single_enemy", "self_or_dying", "all_players", "all_enemies", "all_allies", "all_others"]},
		{"key": "effects", "label": "效果（JSON 数组）", "kind": "json"},
		{"key": "passive", "label": "被动（JSON 对象，装备用）", "kind": "json"},
		{"key": "judge", "label": "判定（JSON 对象，延时判定/事件用）", "kind": "json"},
		{"key": "trap_trigger", "label": "陷阱触发（JSON 对象，陷阱用）", "kind": "json"},
		{"key": "tags", "label": "标签（逗号分隔，如 attack,basic）", "kind": "string_list"},
		{"key": "is_defense", "label": "是防御牌", "kind": "bool"},
		{"key": "defense_value", "label": "防御点数", "kind": "int"},
		{"key": "_deck_count", "label": "※ 抽牌堆中数量", "kind": "int"},
	],
	"skills": [
		{"key": "id", "label": "ID（唯一标识）", "kind": "string"},
		{"key": "name", "label": "名称（用〖〗括起）", "kind": "string"},
		{"key": "skill_type", "label": "技能类型", "kind": "option", "options": ["active", "opening", "locked", "limited", "switch"]},
		{"key": "description", "label": "描述", "kind": "multiline"},
		{"key": "max_uses_per_turn", "label": "每回合次数上限", "kind": "int"},
		{"key": "target_type", "label": "目标类型", "kind": "option", "options": ["none", "self", "single_any", "single_enemy", "all_players", "all_enemies", "all_allies", "all_others"]},
		{"key": "effects", "label": "效果（JSON 数组）", "kind": "json"},
	],
	"events": [
		{"key": "id", "label": "ID（唯一标识）", "kind": "string"},
		{"key": "name", "label": "名称（用『』括起）", "kind": "string"},
		{"key": "description", "label": "描述", "kind": "multiline"},
		{"key": "target_type", "label": "目标类型", "kind": "option", "options": ["none", "self", "single_any", "single_enemy", "all_players", "all_enemies", "all_allies", "all_others"]},
		{"key": "effects", "label": "效果（JSON 数组）", "kind": "json"},
		{"key": "judge", "label": "判定（JSON 对象）", "kind": "json"},
		{"key": "_in_event_deck", "label": "※ 加入特殊事件牌堆", "kind": "bool"},
	],
	"attributes": [
		{"key": "id", "label": "ID（唯一标识）", "kind": "string"},
		{"key": "name", "label": "名称（用〈〉括起）", "kind": "string"},
		{"key": "faction", "label": "所属派系", "kind": "option", "options_ref": "factions"},
		{"key": "description", "label": "描述", "kind": "multiline"},
		{"key": "passive", "label": "被动（JSON 对象，属性效果用）", "kind": "json"},
	],
	"characters": [
		{"key": "id", "label": "ID（唯一标识）", "kind": "string"},
		{"key": "name", "label": "名称", "kind": "string"},
		{"key": "max_hp", "label": "生命上限", "kind": "int"},
		{"key": "draw_limit", "label": "摸牌数值（摸牌阶段补足目标）", "kind": "int"},
		{"key": "hand_limit", "label": "存牌数值（弃牌阶段手牌上限）", "kind": "int"},
		{"key": "attribute_ids", "label": "属性（逗号分隔，两派系各 1 个属性 ID）", "kind": "string_list"},
		{"key": "skill_ids", "label": "技能列表（逗号分隔技能 ID）", "kind": "string_list"},
	],
	"statuses": [
		{"key": "id", "label": "ID（唯一标识）", "kind": "string"},
		{"key": "name", "label": "名称（用「」括起）", "kind": "string"},
		{"key": "description", "label": "描述", "kind": "multiline"},
		{"key": "duration", "label": "持续回合数（-1 永久）", "kind": "int"},
		{"key": "max_layers", "label": "最大层数（可叠层状态）", "kind": "int"},
		{"key": "trigger", "label": "触发时机", "kind": "option", "options": ["on_turn_start", "on_damage_taken", "on_play_card", "on_deal_damage", "on_attack", "none"]},
		{"key": "effects", "label": "效果（JSON 数组）", "kind": "json"},
	],
	"combos": [
		{"key": "id", "label": "ID（唯一标识）", "kind": "string"},
		{"key": "name", "label": "名称（用《》括起）", "kind": "string"},
		{"key": "parts", "label": "组成装备（逗号分隔装备 ID，至少 2 件）", "kind": "string_list"},
		{"key": "description", "label": "描述", "kind": "multiline"},
		{"key": "passive", "label": "被动（JSON 对象，组合激活时生效）", "kind": "json"},
	],
}

# 新增条目的模板
const TEMPLATES := {
	"cards": {"id": "new_card", "name": "【新卡牌】", "type": "basic", "subtype": "", "description": "", "target_type": "none", "effects": [], "tags": [], "is_defense": false, "defense_value": 0},
	"skills": {"id": "new_skill", "name": "〖新技能〗", "skill_type": "active", "description": "", "max_uses_per_turn": 1, "target_type": "none", "effects": []},
	"events": {"id": "new_event", "name": "『新事件』", "description": "", "target_type": "none", "effects": []},
	"attributes": {"id": "new_attr", "name": "〈新属性〉", "faction": "faction_a", "description": "", "passive": {}},
	"characters": {"id": "new_char", "name": "新角色", "max_hp": 20, "draw_limit": 5, "hand_limit": 3, "attribute_ids": [], "skill_ids": []},
	"statuses": {"id": "new_status", "name": "「新状态」", "description": "", "duration": -1, "trigger": "on_turn_start", "effects": []},
	"combos": {"id": "new_combo", "name": "《新组合》", "parts": [], "description": "", "passive": {}},
}

var raw: Dictionary = {}          # 分类 key -> 整个 JSON 对象
var current_cat := "cards"
var current_index := -1
var field_widgets: Dictionary = {}  # 字段 key -> 控件

var cat_option: OptionButton
var entry_list: ItemList
var form_box: VBoxContainer
var status_label: Label
var help_label: RichTextLabel

# 帮助文本：按分类显示字段说明
const HELP_TEXTS := {
	"cards": """[b][color=gold]卡牌字段说明[/color][/b]

[b]ID[/b]　唯一标识，其他数据通过此 ID 引用卡牌
[b]名称[/b]　显示名称，建议用【】括起
[b]类型[/b]　卡牌大类：
　・basic　基础牌（攻击/防御/控制/支援）
　・special_attack　特殊攻击牌
　・food　食物牌（回复生命）
　・equipment　装备牌（武器/防具）
　・trap　陷阱牌
　・delayed_judge　延时判定牌
[b]子类型[/b]　细分类型，如 attack/defense/weapon/armor
[b]描述[/b]　卡牌效果描述文本，支持换行
[b]目标类型[/b]
　・none　无需目标
　・self　以自己为目标
　・single_any　任意单体（含自己）
　・single_enemy　敌方单体
　・self_or_dying　自己或濒死者
　・all_players　场上所有存活玩家
　・all_enemies　所有敌方玩家
　・all_allies　所有友方玩家
　・all_others　除自己外的所有人
[b]效果[/b]　JSON 数组，打出时依次执行的动作列表
[b]被动[/b]　JSON 对象，装备牌专用，格式：
　{"hook": "on_outgoing_damage(造成伤害时)/on_incoming_damage(受到伤害时)",
　 "conditions": {"card_id": "限定卡牌ID", "damage_type": "physical/magical/soul",
　   "first_attack_this_turn": true, "allow_hp_loss": false},
　 "effect": {"type": "damage_bonus(伤害加减)/heal(回血)", "value": 数值或"per_attack_used_this_turn", "max": 上限},
　 "max_uses_per_turn": 每回合次数(可省略)}
[b]判定[/b]　JSON 对象，延时判定/事件牌专用
[b]陷阱触发[/b]　JSON 对象，陷阱牌专用，定义触发条件
[b]标签[/b]　逗号分隔，如 attack,basic，供规则引擎判断
[b]是防御牌[/b]　勾选后可布置到预备区，响应时抵消伤害
[b]防御点数[/b]　响应时抵消的伤害数值
[b]※ 抽牌堆中数量[/b]　该卡牌在抽牌堆中出现的次数""",
	"skills": """[b][color=gold]技能字段说明[/color][/b]

[b]ID[/b]　唯一标识，角色通过此 ID 引用技能
[b]名称[/b]　显示名称，建议用〖〗括起
[b]技能类型[/b]
　・active　主动技能，出牌阶段点击发动
　・opening　开局技能，对局开始时自动生效
　・locked　锁定技能，常驻自动生效，无按钮
　・limited　限定技，每局一次，由特定时机触发（如〖放逐〗）
　・switch　转换技，主动发动，按形态顺序轮换（如〖贤者之书〗）
[b]描述[/b]　技能效果描述文本
[b]每回合次数上限[/b]　主动技能每回合可用次数
[b]目标类型[/b]　同卡牌目标类型说明
[b]效果[/b]　JSON 数组，技能发动时执行的动作列表""",
	"events": """[b][color=gold]事件字段说明[/color][/b]

[b]ID[/b]　唯一标识
[b]名称[/b]　显示名称，建议用『』括起
[b]描述[/b]　事件效果描述文本
[b]目标类型[/b]　同卡牌目标类型说明
[b]效果[/b]　JSON 数组，事件触发时执行的动作列表
[b]判定[/b]　JSON 对象，事件可携带判定逻辑
[b]※ 加入特殊事件牌堆[/b]　勾选后该事件会进入特殊事件牌堆，可被【特殊事件】牌抽出""",
	"attributes": """[b][color=gold]属性字段说明[/color][/b]

[b]ID[/b]　唯一标识，角色通过此 ID 关联属性
[b]名称[/b]　属性名称，建议用〈〉括起
[b]所属派系[/b]　两套派系之一：
　・faction_a　时间 · 生命 · 臆想 · 粒子
　・faction_b　空间 · 冥暗 · 混沌 · 信息
　派系定义在 attributes.json 的 factions 数组中
[b]描述[/b]　属性特性描述文本
[b]被动[/b]　JSON 对象，属性效果用，格式与装备被动一致：
　{"hook": "on_outgoing_damage/on_incoming_damage",
　 "conditions": {"card_id"/"damage_type"/"first_attack_this_turn"/"allow_hp_loss"},
　 "effect": {"type": "damage_bonus/heal", "value": 数值},
　 "max_uses_per_turn": 每回合次数}
　示例：{"hook":"on_outgoing_damage",
　 "conditions":{"damage_type":"magical"},
　 "effect":{"type":"heal","value":1},"max_uses_per_turn":1}""",
	"characters": """[b][color=gold]角色字段说明[/color][/b]

[b]ID[/b]　唯一标识
[b]名称[/b]　角色名称
[b]生命上限[/b]　基础生命上限
[b]摸牌数值[/b]　摸牌阶段手牌补足目标数量
[b]存牌数值[/b]　弃牌阶段手牌上限，超过需弃置
[b]属性[/b]　逗号分隔的两个属性 ID，两个派系各选 1 个；
　如 time,chaos（〈时间〉+〈混沌〉）
[b]技能列表[/b]　逗号分隔的技能 ID，如 skill_a,skill_b""",
	"statuses": """[b][color=gold]状态字段说明[/color][/b]

[b]ID[/b]　唯一标识，卡牌/技能通过此 ID 引用状态
[b]名称[/b]　显示名称，建议用「」括起
[b]描述[/b]　状态效果描述文本
[b]持续回合数[/b]　-1 表示永久，正数表示持续回合数
[b]触发时机[/b]
　・on_turn_start　回合开始时触发
　・on_damage_taken　受到一次伤害后触发（如「易伤1」）
　・on_play_card　打出一张手牌时触发（如「恶化1」）
　・on_deal_damage　造成伤害时触发，可减伤（如「寒冷1」）
　・on_attack　攻击时触发（预留）
　・none　无自动触发（如「猩红」「皎白」「玄暗」）
[b]最大层数[/b]　可叠层状态的上限；不填视为无限制
[b]效果[/b]　JSON 数组，触发时执行的动作列表""",
	"combos": """[b][color=gold]装备组合字段说明[/color][/b]

[b]ID[/b]　唯一标识
[b]名称[/b]　显示名称，建议用《》括起
[b]组成装备[/b]　逗号分隔的装备牌 ID，至少 2 件；
　玩家装备栏中同时拥有全部这些装备时，组合自动激活
[b]描述[/b]　组合效果描述文本
[b]被动[/b]　JSON 对象，组合激活时生效，格式与装备/属性被动一致：
　{"hook": "on_outgoing_damage/on_incoming_damage",
　 "conditions": {"card_id"/"damage_type"/"first_attack_this_turn"},
　 "effect": {"type": "damage_bonus/heal", "value": 数值},
　 "max_uses_per_turn": 每回合次数(可省略)}
[b]※ 引用校验[/b]　保存时会检查组成装备是否存在且为装备牌""",
}

func _ready() -> void:
	_apply_theme()
	_build_ui()
	_load_all()
	_rebuild_list()
	if _entries().size() > 0:
		_select_entry(0)

func _apply_theme() -> void:
	theme = UITheme.make_theme(15)
	UITheme.add_background(self)

# ---------------- UI 构建 ----------------

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# 左侧：分类 + 条目列表 + 新增/删除
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(262, 0)
	root.add_child(left_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left_panel.add_child(left)
	var lt := Label.new()
	lt.text = "数据编辑器"
	lt.add_theme_font_size_override("font_size", 20)
	lt.add_theme_color_override("font_color", UITheme.ACCENT)
	left.add_child(lt)
	cat_option = OptionButton.new()
	for c in CATEGORIES:
		cat_option.add_item(String(c["title"]))
	cat_option.item_selected.connect(_on_category_changed)
	left.add_child(cat_option)
	entry_list = ItemList.new()
	entry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entry_list.item_selected.connect(_on_entry_selected)
	left.add_child(entry_list)
	var lbtn := HBoxContainer.new()
	lbtn.add_theme_constant_override("separation", 8)
	left.add_child(lbtn)
	var add_btn := Button.new()
	add_btn.text = "＋ 新增"
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(_on_add_entry)
	lbtn.add_child(add_btn)
	var del_btn := Button.new()
	del_btn.text = "－ 删除"
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(del_btn, UITheme.danger_button_styles())
	del_btn.pressed.connect(_on_delete_entry)
	lbtn.add_child(del_btn)

	# 右侧：顶栏 + 表单
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right_panel.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	right.add_child(top)
	var save_btn := Button.new()
	save_btn.text = "保存全部"
	save_btn.custom_minimum_size = Vector2(130, 40)
	UITheme.style_button(save_btn, UITheme.accent_button_styles())
	save_btn.pressed.connect(_on_save)
	top.add_child(save_btn)
	var back_btn := Button.new()
	back_btn.text = "返回主菜单"
	back_btn.custom_minimum_size = Vector2(130, 40)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/launcher.tscn"))
	top.add_child(back_btn)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	form_box = VBoxContainer.new()
	form_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_box.add_theme_constant_override("separation", 10)
	scroll.add_child(form_box)

	# 最右侧：帮助面板（按分类显示字段说明）
	var help_panel := PanelContainer.new()
	help_panel.custom_minimum_size = Vector2(280, 0)
	root.add_child(help_panel)
	var help_scroll := ScrollContainer.new()
	help_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_panel.add_child(help_scroll)
	help_label = RichTextLabel.new()
	help_label.bbcode_enabled = true
	help_label.scroll_active = false
	help_label.fit_content = true
	help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_label.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG_INPUT, UITheme.BORDER, 8, 1))
	help_label.text = HELP_TEXTS[current_cat]
	help_scroll.add_child(help_label)

# ---------------- 数据加载 / 保存 ----------------

func _load_all() -> void:
	raw.clear()
	for key in FILES.keys():
		var f := FileAccess.open(String(FILES[key]), FileAccess.READ)
		if f == null:
			_set_status("无法打开：" + String(FILES[key]), true)
			raw[key] = {}
			continue
		var text := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(text)
		if parsed == null or not parsed is Dictionary:
			_set_status("JSON 解析失败：" + String(FILES[key]), true)
			raw[key] = {}
			continue
		raw[key] = parsed

func _entries() -> Array:
	var list_key := _cat_list_key(current_cat)
	if raw.is_empty() or not raw.has(current_cat):
		return []
	return raw[current_cat].get(list_key, [])

func _cat_list_key(cat: String) -> String:
	for c in CATEGORIES:
		if String(c["key"]) == cat:
			return String(c["list_key"])
	return ""

func _on_save() -> void:
	if not _commit_current():
		return
	var errors := _validate_all()
	if not errors.is_empty():
		_set_status("校验失败：\n" + "\n".join(errors), true)
		return
	for key in FILES.keys():
		var f := FileAccess.open(String(FILES[key]), FileAccess.WRITE)
		if f == null:
			_set_status("无法写入：" + String(FILES[key]), true)
			return
		f.store_string(JSON.stringify(raw[key], "  ") + "\n")
		f.close()
	_set_status("已保存全部数据文件。", false)

# ---------------- 列表与表单 ----------------

func _on_category_changed(index: int) -> void:
	if not _commit_current():
		# 表单有错误时回退选择
		for i in CATEGORIES.size():
			if String(CATEGORIES[i]["key"]) == current_cat:
				cat_option.selected = i
		return
	current_cat = String(CATEGORIES[index]["key"])
	current_index = -1
	help_label.text = HELP_TEXTS[current_cat]
	_rebuild_list()
	if _entries().size() > 0:
		_select_entry(0)
	else:
		_rebuild_form()

func _rebuild_list() -> void:
	entry_list.clear()
	for e in _entries():
		var label := "%s　%s" % [String(e.get("id", "?")), String(e.get("name", ""))]
		entry_list.add_item(label)

func _on_entry_selected(index: int) -> void:
	if index == current_index:
		return
	if not _commit_current():
		entry_list.deselect_all()
		if current_index >= 0:
			entry_list.select(current_index)
		return
	_select_entry(index)

func _select_entry(index: int) -> void:
	current_index = index
	if index >= 0 and index < entry_list.item_count:
		entry_list.select(index)
	_rebuild_form()

func _rebuild_form() -> void:
	for c in form_box.get_children():
		c.visible = false
		c.queue_free()
	field_widgets.clear()
	if current_index < 0 or current_index >= _entries().size():
		return
	var entry: Dictionary = _entries()[current_index]
	for fs in SCHEMAS[current_cat]:
		_add_field(fs, entry)

func _add_field(fs: Dictionary, entry: Dictionary) -> void:
	var key := String(fs["key"])
	var kind := String(fs["kind"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	form_box.add_child(box)
	var label := Label.new()
	label.text = String(fs["label"])
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(label)
	match kind:
		"string":
			var le := LineEdit.new()
			le.text = String(entry.get(key, ""))
			box.add_child(le)
			field_widgets[key] = le
		"int":
			var sp := SpinBox.new()
			sp.min_value = -99
			sp.max_value = 999
			if key == "_deck_count":
				var dc: Dictionary = raw["cards"].get("deck_composition", {})
				sp.value = int(dc.get(String(entry.get("id", "")), 0))
			else:
				sp.value = int(entry.get(key, 0))
			box.add_child(sp)
			field_widgets[key] = sp
		"bool":
			var cb := CheckBox.new()
			if key == "_in_event_deck":
				var deck: Array = raw["events"].get("event_deck", [])
				cb.button_pressed = deck.has(String(entry.get("id", "")))
			else:
				cb.button_pressed = bool(entry.get(key, false))
			box.add_child(cb)
			field_widgets[key] = cb
		"multiline":
			var te := TextEdit.new()
			te.custom_minimum_size = Vector2(0, 60)
			te.text = String(entry.get(key, ""))
			box.add_child(te)
			field_widgets[key] = te
		"json":
			var te := TextEdit.new()
			te.custom_minimum_size = Vector2(0, 110)
			te.scroll_fit_content_height = false
			if entry.has(key):
				te.text = JSON.stringify(entry[key], "  ")
			else:
				te.text = ""
			box.add_child(te)
			field_widgets[key] = te
		"option":
			var ob := OptionButton.new()
			var opts: Array = fs.get("options", [])
			if fs.has("options_ref"):
				var ref := String(fs["options_ref"])
				opts = []
				if ref == "factions":
					# 派系列表与属性同文件（attributes.json 的 factions 数组）
					for f in raw["attributes"].get("factions", []):
						opts.append(String(f.get("id", "")))
				else:
					for e in raw[ref].get(_cat_list_key(ref), []):
						opts.append(String(e.get("id", "")))
			var cur := String(entry.get(key, ""))
			for i in opts.size():
				ob.add_item(String(opts[i]))
				if String(opts[i]) == cur:
					ob.selected = i
			box.add_child(ob)
			field_widgets[key] = ob
		"string_list":
			var le := LineEdit.new()
			var arr: Array = entry.get(key, [])
			var strs: Array[String] = []
			for x in arr:
				strs.append(String(x))
			le.text = ",".join(strs)
			box.add_child(le)
			field_widgets[key] = le

# 把表单值写回内存数据；JSON 片段解析失败则拒绝并提示
func _commit_current() -> bool:
	if current_index < 0 or current_index >= _entries().size():
		return true
	var entry: Dictionary = _entries()[current_index]
	var old_id := String(entry.get("id", ""))
	for fs in SCHEMAS[current_cat]:
		var key := String(fs["key"])
		var kind := String(fs["kind"])
		if not field_widgets.has(key):
			continue
		var w: Control = field_widgets[key]
		match kind:
			"string":
				entry[key] = (w as LineEdit).text
			"int":
				if key == "_deck_count":
					var dc: Dictionary = raw["cards"].get("deck_composition", {})
					var n := int((w as SpinBox).value)
					if n > 0:
						dc[old_id] = n
					else:
						dc.erase(old_id)
					raw["cards"]["deck_composition"] = dc
				else:
					entry[key] = int((w as SpinBox).value)
			"bool":
				if key == "_in_event_deck":
					var deck: Array = raw["events"].get("event_deck", [])
					var on := (w as CheckBox).button_pressed
					if on and not deck.has(old_id):
						deck.append(old_id)
					elif not on:
						deck.erase(old_id)
					raw["events"]["event_deck"] = deck
				else:
					entry[key] = (w as CheckBox).button_pressed
			"multiline":
				entry[key] = (w as TextEdit).text
			"json":
				var t: String = (w as TextEdit).text.strip_edges()
				if t == "":
					entry.erase(key)
				else:
					var parsed = JSON.parse_string(t)
					if parsed == null:
						_set_status("字段「%s」JSON 解析失败，请修正后再切换/保存。" % String(fs["label"]), true)
						return false
					entry[key] = parsed
			"option":
				var ob := w as OptionButton
				if ob.selected >= 0:
					entry[key] = ob.get_item_text(ob.selected)
			"string_list":
				var t: String = (w as LineEdit).text
				var out: Array = []
				for part in t.split(",", false):
					var s := part.strip_edges()
					if s != "":
						out.append(s)
				entry[key] = out
	# id 变更同步：牌堆构成的键跟随新 id
	var new_id := String(entry.get("id", ""))
	if new_id != old_id and old_id != "":
		if current_cat == "cards":
			var dc: Dictionary = raw["cards"].get("deck_composition", {})
			if dc.has(old_id):
				dc[new_id] = dc[old_id]
				dc.erase(old_id)
		elif current_cat == "events":
			var deck: Array = raw["events"].get("event_deck", [])
			if deck.has(old_id):
				deck.erase(old_id)
				deck.append(new_id)
	return true

func _on_add_entry() -> void:
	if not _commit_current():
		return
	var tpl: Dictionary = TEMPLATES[current_cat].duplicate(true)
	# 保证新 id 唯一
	var base := String(tpl["id"])
	var nid := base
	var n := 1
	while _find_entry_index(nid) != -1:
		n += 1
		nid = "%s_%d" % [base, n]
	tpl["id"] = nid
	_entries().append(tpl)
	_rebuild_list()
	_select_entry(_entries().size() - 1)

func _on_delete_entry() -> void:
	if current_index < 0 or current_index >= _entries().size():
		return
	var entry: Dictionary = _entries()[current_index]
	var id := String(entry.get("id", ""))
	_entries().remove_at(current_index)
	# 清理关联数据
	if current_cat == "cards":
		raw["cards"].get("deck_composition", {}).erase(id)
	elif current_cat == "events":
		raw["events"].get("event_deck", []).erase(id)
	current_index = -1
	_rebuild_list()
	if _entries().size() > 0:
		_select_entry(0)
	else:
		_rebuild_form()

func _find_entry_index(id: String) -> int:
	for i in _entries().size():
		if String(_entries()[i].get("id", "")) == id:
			return i
	return -1

# ---------------- 校验 ----------------

func _validate_all() -> Array[String]:
	var errors: Array[String] = []
	# 1. 各分类 id 非空且唯一
	for c in CATEGORIES:
		var cat := String(c["key"])
		var seen := {}
		for e in raw[cat].get(String(c["list_key"]), []):
			var id := String(e.get("id", ""))
			if id == "":
				errors.append("%s存在空 ID 的条目。" % String(c["title"]))
			elif seen.has(id):
				errors.append("%s的 ID「%s」重复。" % [String(c["title"]), id])
			seen[id] = true
	# 2. 引用校验：牌堆构成 -> 卡牌
	for id in raw["cards"].get("deck_composition", {}).keys():
		if _find_in("cards", String(id)) == null:
			errors.append("抽牌堆构成引用了不存在的卡牌「%s」。" % String(id))
	# 3. 引用校验：事件牌堆 -> 事件
	for id in raw["events"].get("event_deck", []):
		if _find_in("events", String(id)) == null:
			errors.append("事件牌堆引用了不存在的事件「%s」。" % String(id))
	# 4. 引用校验：角色的属性与技能
	for e in raw["characters"].get("characters", []):
		var aids: Array = e.get("attribute_ids", [])
		var used_factions := {}
		for aid in aids:
			var attr: Variant = _find_in("attributes", String(aid))
			if attr == null:
				errors.append("角色「%s」引用了不存在的属性「%s」。" % [String(e.get("name", "")), String(aid)])
			else:
				used_factions[String(attr.get("faction", ""))] = true
		if aids.size() != 2:
			errors.append("角色「%s」必须配置 2 个属性（两个派系各 1 个）。" % String(e.get("name", "")))
		elif used_factions.size() != 2:
			errors.append("角色「%s」的两个属性必须分别来自两个不同派系。" % String(e.get("name", "")))
		for sid in e.get("skill_ids", []):
			if _find_in("skills", String(sid)) == null:
				errors.append("角色「%s」引用了不存在的技能「%s」。" % [String(e.get("name", "")), String(sid)])
	# 5. 引用校验：装备组合的组成装备
	for e in raw["combos"].get("combos", []):
		var parts: Array = e.get("parts", [])
		if parts.size() < 2:
			errors.append("装备组合「%s」至少需要 2 件装备。" % String(e.get("name", "")))
		for pid in parts:
			var card: Variant = _find_in("cards", String(pid))
			if card == null:
				errors.append("装备组合「%s」引用了不存在的装备「%s」。" % [String(e.get("name", "")), String(pid)])
			elif String(card.get("type", "")) != "equipment":
				errors.append("装备组合「%s」的组成「%s」不是装备牌。" % [String(e.get("name", "")), String(pid)])
	return errors

func _find_in(cat: String, id: String) -> Variant:
	for c in CATEGORIES:
		if String(c["key"]) == cat:
			for e in raw[cat].get(String(c["list_key"]), []):
				if String(e.get("id", "")) == id:
					return e
	return null

func _set_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", UITheme.DANGER if is_error else UITheme.OK)
