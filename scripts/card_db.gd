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
var boards: Array = []                  # 板子定义列表（人数 / 队伍 / 座位映射）
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
	var boards_raw = _load_json("res://data/boards.json")
	if boards_raw != null:
		for e in boards_raw.get("boards", []):
			boards.append(e)
	_validate()

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

# ---------------- 引用完整性校验 ----------------
# 加载后统一检查数据之间的引用，缺失时输出错误，避免运行期静默失效。

func _validate() -> void:
	var issues: Array[String] = []
	for cid in deck_composition.keys():
		if not cards.has(String(cid)):
			issues.append("deck_composition 引用了不存在的卡牌：%s" % cid)
		elif int(deck_composition[cid]) <= 0:
			issues.append("deck_composition 中 %s 的数量无效（%d）" % [cid, int(deck_composition[cid])])
	for eid in event_deck_list:
		if not events.has(eid):
			issues.append("event_deck 引用了不存在的事件：%s" % eid)
	for c in characters:
		var who := "角色 %s" % String(c.get("id", "?"))
		for aid in c.get("attribute_ids", []):
			if not attributes.has(String(aid)):
				issues.append("%s 的 attribute_ids 引用了不存在的属性：%s" % [who, aid])
		for sid in c.get("skill_ids", []):
			if not skills.has(String(sid)):
				issues.append("%s 的 skill_ids 引用了不存在的技能：%s" % [who, sid])
	for combo in combos:
		var combo_id := String(combo.get("id", "?"))
		var parts: Array = combo.get("parts", [])
		if parts.size() < 2:
			issues.append("装备组合 %s 的 parts 少于 2 件" % combo_id)
		for pid in parts:
			var part: Dictionary = cards.get(String(pid), {})
			if part.is_empty():
				issues.append("装备组合 %s 的 parts 引用了不存在的卡牌：%s" % [combo_id, pid])
			elif String(part.get("type", "")) != "equipment":
				issues.append("装备组合 %s 的 parts 引用了非装备牌：%s" % [combo_id, pid])
	# 牌池字段合法性（缺省=通用；只允许 classic / retrace / all）
	for c in characters:
		var cpool := String(c.get("pool", ""))
		if not ["", "all", "classic", "retrace"].has(cpool):
			issues.append("角色 %s 的 pool 字段无效：%s" % [String(c.get("id", "?")), cpool])
	for cid in cards.keys():
		var kpool := String(cards[cid].get("pool", ""))
		if not ["", "all", "classic", "retrace"].has(kpool):
			issues.append("卡牌 %s 的 pool 字段无效：%s" % [cid, kpool])
	var seen: Dictionary = {}
	_check_refs("卡牌", cards.values(), issues, seen)
	_check_refs("技能", skills.values(), issues, seen)
	_check_refs("事件", events.values(), issues, seen)
	_check_refs("属性", attributes.values(), issues, seen)
	_check_refs("状态", statuses.values(), issues, seen)
	_check_refs("装备组合", combos, issues, seen)
	# 板子：座位必须恰好覆盖 0..player_count-1，队伍 id 唯一
	var board_ids_seen: Dictionary = {}
	for b in boards:
		var bid := String(b.get("id", "?"))
		if board_ids_seen.has(bid):
			issues.append("板子 id 重复：%s" % bid)
		board_ids_seen[bid] = true
		var pc := int(b.get("player_count", 0))
		if pc < 2:
			issues.append("板子 %s 的 player_count 必须 >= 2（当前 %d）" % [bid, pc])
		var team_ids_seen: Dictionary = {}
		var seat_seen: Dictionary = {}
		var seat_total := 0
		for t in b.get("teams", []):
			var tid := String(t.get("id", ""))
			if tid.is_empty():
				issues.append("板子 %s 存在空的队伍 id" % bid)
			elif team_ids_seen.has(tid):
				issues.append("板子 %s 的队伍 id 重复：%s" % [bid, tid])
			team_ids_seen[tid] = true
			var seats: Array = t.get("seats", [])
			if seats.is_empty():
				issues.append("板子 %s 的队伍 %s 没有任何座位" % [bid, tid])
			for s in seats:
				var si := int(s)
				seat_total += 1
				if si < 0 or si >= pc:
					issues.append("板子 %s 的座位 %d 越界（player_count=%d）" % [bid, si, pc])
				elif seat_seen.has(si):
					issues.append("板子 %s 的座位 %d 被多个队伍占用" % [bid, si])
				seat_seen[si] = true
		if seat_total != pc or seat_seen.size() != pc:
			issues.append("板子 %s 的座位未完整覆盖 0..%d" % [bid, pc - 1])
	if issues.is_empty():
		return
	for msg in issues:
		push_error("[CardDB] " + msg)
	print("[CardDB] 数据引用校验发现 %d 处问题。" % issues.size())

func _check_refs(label: String, entries: Array, issues: Array[String], seen: Dictionary) -> void:
	## 递归扫描条目中的 id 引用字段（status_id / skill_id / card_id / event_id / defense_ids）
	for entry in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			_walk_refs(label, entry, issues, seen)

func _walk_refs(label: String, node: Variant, issues: Array[String], seen: Dictionary) -> void:
	match typeof(node):
		TYPE_DICTIONARY:
			var d: Dictionary = node
			for k in d.keys():
				var key := String(k)
				var value: Variant = d[key]
				match key:
					"status_id":
						_require(label, "状态", String(value), statuses, issues, seen)
					"skill_id":
						_require(label, "技能", String(value), skills, issues, seen)
					"card_id":
						_require(label, "卡牌", String(value), cards, issues, seen)
					"event_id":
						_require(label, "事件", String(value), events, issues, seen)
					"defense_ids":
						for cid in value:
							_require(label, "卡牌", String(cid), cards, issues, seen)
					_:
						_walk_refs(label, value, issues, seen)
		TYPE_ARRAY:
			for item in node:
				_walk_refs(label, item, issues, seen)

func _require(label: String, kind: String, id: String, table: Dictionary, issues: Array[String], seen: Dictionary) -> void:
	if id.is_empty() or table.has(id):
		return
	var sig := label + "|" + kind + "|" + id
	if seen.has(sig):
		return
	seen[sig] = true
	issues.append("%s 的效果引用了不存在的%s：%s" % [label, kind, id])

# ---------------- 访问器（返回只读副本，防止外部改动污染数据字典） ----------------

func get_card(id: String) -> Dictionary:
	var c: Dictionary = cards.get(id, {})
	return c.duplicate(true)

func get_skill(id: String) -> Dictionary:
	var s: Dictionary = skills.get(id, {})
	return s.duplicate(true)

func get_event(id: String) -> Dictionary:
	var e: Dictionary = events.get(id, {})
	return e.duplicate(true)

func get_attribute(id: String) -> Dictionary:
	var a: Dictionary = attributes.get(id, {})
	return a.duplicate(true)

func get_status(id: String) -> Dictionary:
	var s: Dictionary = statuses.get(id, {})
	return s.duplicate(true)

func get_faction(id: String) -> Dictionary:
	for f in factions:
		if String(f.get("id", "")) == id:
			var cfg: Dictionary = f
			return cfg.duplicate(true)
	return {}

func get_character(id: String) -> Dictionary:
	for c in characters:
		if String(c.get("id", "")) == id:
			var cfg: Dictionary = c
			return cfg.duplicate(true)
	return {}

func get_board(id: String) -> Dictionary:
	for b in boards:
		if String(b.get("id", "")) == id:
			var cfg: Dictionary = b
			return cfg.duplicate(true)
	return {}

func default_board() -> Dictionary:
	## 缺省板子：优先 default=true，否则取第一个；均无则返回空字典
	for b in boards:
		if bool(b.get("default", false)):
			var cfg: Dictionary = b
			return cfg.duplicate(true)
	if boards.is_empty():
		return {}
	var first: Dictionary = boards[0]
	return first.duplicate(true)

func board_ids() -> Array[String]:
	var out: Array[String] = []
	for b in boards:
		out.append(String(b.get("id", "")))
	return out

# ---------------- 牌池（板子变体：经典 / 溯洄之境） ----------------
# 条目 pool 字段缺省 = 两个池通用；"classic" = 仅经典；"retrace" = 仅溯洄之境。

const POOLS := [
	{"id": "classic", "name": "经典"},
	{"id": "retrace", "name": "溯洄之境"},
]

func entry_in_pool(entry: Dictionary, pool: String) -> bool:
	var p := String(entry.get("pool", ""))
	return p.is_empty() or p == "all" or p == pool

func characters_for_pool(pool: String) -> Array:
	## 指定牌池可用的角色定义列表（引用，勿改）
	var out: Array = []
	for c in characters:
		if entry_in_pool(c, pool):
			out.append(c)
	return out

func deck_composition_for_pool(pool: String) -> Dictionary:
	## 指定牌池的抽牌堆构成：卡牌 id -> 数量（按卡牌 pool 字段过滤）
	var out: Dictionary = {}
	for cid in deck_composition.keys():
		var card: Dictionary = cards.get(String(cid), {})
		if entry_in_pool(card, pool):
			out[String(cid)] = int(deck_composition[cid])
	return out

func pool_name(pool: String) -> String:
	for p in POOLS:
		if String(p.get("id", "")) == pool:
			return String(p.get("name", pool))
	return pool
