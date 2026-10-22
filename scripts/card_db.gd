class_name CardDB
extends RefCounted

## 数据驱动核心：从 res://data/*.json 加载卡牌、技能、特殊事件、属性与角色定义。
## 对应规则文档：卡牌与技能数据全部数据驱动，不写死在代码里。

var cards: Dictionary = {}              # 卡牌 id -> 定义
var skills: Dictionary = {}             # 技能 id -> 定义
var events: Dictionary = {}             # 特殊事件 id -> 定义
var attributes: Dictionary = {}         # 属性 id -> 定义
var factions: Array = []                # 属性派系列表（两套派系，各含四项属性）
var characters: Array = []              # 角色定义列表（角色池，规则 4.1）
var statuses: Dictionary = {}           # 状态 id -> 定义
var combos: Array = []                  # 装备组合定义列表（同时装备指定装备时激活）
var deck_composition: Dictionary = {}   # 抽牌堆构成：卡牌 id -> 数量
var event_deck_list: Array[String] = [] # 特殊事件牌堆构成

func _init() -> void:
	var cards_raw = _load_json("res://data/cards.json")
	if cards_raw != null:
		for e in cards_raw.get("cards", []):
			cards[String(e["id"])] = e
		for k in cards_raw.get("deck_composition", {}).keys():
			deck_composition[String(k)] = int(cards_raw["deck_composition"][k])
	var events_raw = _load_json("res://data/events.json")
	if events_raw != null:
		for e in events_raw.get("events", []):
			events[String(e["id"])] = e
		for e in events_raw.get("event_deck", []):
			event_deck_list.append(String(e))
	var skills_raw = _load_json("res://data/skills.json")
	if skills_raw != null:
		for e in skills_raw.get("skills", []):
			skills[String(e["id"])] = e
	var attrs_raw = _load_json("res://data/attributes.json")
	if attrs_raw != null:
		for e in attrs_raw.get("factions", []):
			factions.append(e)
		for e in attrs_raw.get("attributes", []):
			attributes[String(e["id"])] = e
	var chars_raw = _load_json("res://data/characters.json")
	if chars_raw != null:
		for e in chars_raw.get("characters", []):
			characters.append(e)
	var statuses_raw = _load_json("res://data/statuses.json")
	if statuses_raw != null:
		for e in statuses_raw.get("statuses", []):
			statuses[String(e["id"])] = e
	var combos_raw = _load_json("res://data/combos.json")
	if combos_raw != null:
		for e in combos_raw.get("combos", []):
			combos.append(e)

func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法打开数据文件：" + path)
		return null
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null:
		push_error("JSON 解析失败：" + path)
	return data

func get_card(id: String) -> Dictionary:
	return cards.get(id, {})

func get_skill(id: String) -> Dictionary:
	return skills.get(id, {})

func get_event(id: String) -> Dictionary:
	return events.get(id, {})

func get_attribute(id: String) -> Dictionary:
	return attributes.get(id, {})

func get_faction(id: String) -> Dictionary:
	for f in factions:
		if String(f.get("id", "")) == id:
			return f
	return {}

func get_character(id: String) -> Dictionary:
	for c in characters:
		if String(c.get("id", "")) == id:
			return c
	return {}
