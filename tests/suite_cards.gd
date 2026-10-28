extends RefCounted

## 卡牌 / 数据层回归：卡牌加载、访问器副本隔离、牌堆引用完整性。

func run(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var db: CardDB = g.db

	var atk: Dictionary = db.get_card("basic_attack")
	t.check(not atk.is_empty(), "卡牌【普通攻击】可加载")
	t.check_eq(String(atk.get("type", "")), "basic", "【普通攻击】类型为 basic")
	t.check(atk.has("effects"), "【普通攻击】带有效果定义")
	t.check(db.get_card("no_such_card").is_empty(), "未知卡牌返回空字典")
	t.check(db.get_skill("no_such_skill").is_empty(), "未知技能返回空字典")
	t.check(db.get_status("no_such_status").is_empty(), "未知状态返回空字典")

	# 访问器返回副本：外部修改不应污染内部数据
	atk["name"] = "被篡改"
	t.check_eq(String(db.get_card("basic_attack").get("name", "")), "【普通攻击】", "访问器返回副本，外部修改不污染数据")

	# 其他数据表可正常加载
	t.check(not db.get_skill("skill_fractal").is_empty(), "技能〖分形几何〗可加载")
	t.check(not db.get_event("event_first_aid").is_empty(), "事件『急救箱』可加载")
	t.check(not db.get_attribute("time").is_empty(), "属性〈时间〉可加载")
	t.check(not db.get_character("char_wuling").is_empty(), "角色伍灵可加载")
	t.check_eq(db.get_character("char_wuling").get("skill_ids", []), ["skill_perceive"], "角色技能列表正确")

	# 牌堆引用完整性：每个构成项都必须存在，总数必须为正
	var total := 0
	for cid in db.deck_composition.keys():
		t.check(not db.get_card(String(cid)).is_empty(), "抽牌堆卡牌存在：" + String(cid))
		total += int(db.deck_composition[cid])
	t.check(total > 0, "抽牌堆总数 > 0（实际 %d）" % total)
	for eid in db.event_deck_list:
		t.check(not db.get_event(String(eid)).is_empty(), "事件牌堆条目存在：" + String(eid))
