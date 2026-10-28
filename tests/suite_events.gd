extends RefCounted

## 随机事件回归：天罚/急救箱/洪水泛滥/失而复得/饥荒/猎巫运动/被遗弃者/救济粮/毕宿五的召唤。

func run(t) -> void:
	_test_thunder(t)
	_test_first_aid(t)
	_test_flood(t)
	_test_recover(t)
	_test_famine(t)
	_test_witch_hunt(t)
	_test_forsaken_path1(t)
	_test_forsaken_path2(t)
	_test_relief(t)
	_test_hastur(t)

## 强制触发指定事件并确认说明窗口
func _fire_event(g: AtlasGame, event_id: String, src: int = 0) -> void:
	g.event_deck.clear()
	g.event_deck.append(event_id)
	g._trigger_event(src)
	g.ui_confirm_event_show()

func _skip_responses(g: AtlasGame) -> void:
	var guard := 0
	while g.mode == AtlasGame.Mode.RESPONSE and guard < 10:
		g.ui_end_response()
		guard += 1

func _test_thunder(t) -> void:
	var g: AtlasGame = t.make_game(2)
	_fire_event(g, "event_thunder")
	t.check_eq(g.players[0].hp, 15, "天罚：自己失去 5 点生命")
	t.check_eq(g.players[1].hp, 15, "天罚：对方失去 5 点生命")

func _test_first_aid(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[0].hp = 10
	g.players[1].hp = 5
	_fire_event(g, "event_first_aid")
	t.check_eq(g.players[0].hp, 15, "急救箱：自己回复 5 点")
	t.check_eq(g.players[1].hp, 8, "急救箱：生命≤5 的玩家再回 3 点")

func _test_flood(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[0].reserve.append("defend1")
	g.players[0].reserve.append("basic_attack")
	g.players[1].reserve.append("defend2")
	var before := g.discard_pile.size()
	_fire_event(g, "event_flood")
	t.check(g.players[0].reserve.is_empty(), "洪水：自己预备区清空")
	t.check(g.players[1].reserve.is_empty(), "洪水：对方预备区清空")
	t.check_eq(g.discard_pile.size(), before + 3, "洪水：3 张牌进入弃牌堆")

func _test_recover(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.hand = ["basic_attack", "defend1", "skip"]
	g.draw_pile = ["plunder", "draw", "magic_bolt"]
	_fire_event(g, "event_recover")
	t.check_eq(p.hand.size(), 3, "失而复得：摸回等量手牌")
	# 摸牌堆从末尾摸取，只校验摸到的牌面集合
	t.check(p.hand.has("plunder") and p.hand.has("draw") and p.hand.has("magic_bolt"), "失而复得：摸到新牌")
	t.check(g.discard_pile.has("basic_attack") and g.discard_pile.has("skip"), "失而复得：原手牌进入弃牌堆")

func _test_famine(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p0 := g.players[0]
	var p1 := g.players[1]
	p0.hand = ["basic_attack"]
	p1.hand = ["basic_attack"]
	_fire_event(g, "event_famine")
	t.check(p0.has_status("famine") and p1.has_status("famine"), "饥荒：所有玩家获得「饥荒」")
	# 触发者本回合不受「回合结束弃牌」影响（持续 2 未 tick）
	g.ui_end_play_phase()
	t.check(not p0.hand.is_empty(), "饥荒：触发者本回合结束不弃牌")
	t.check_eq(g.current, 1, "饥荒：回合交替给下一名玩家")
	g.ui_confirm_interstitial()
	# 对方下回合：不能摸牌（手牌仍为 1 张，低于摸牌数值也不补）
	t.check_eq(p1.hand.size(), 1, "饥荒：下回合摸牌阶段不能摸牌")
	# 对方回合结束：弃掉所有手牌并解除
	g.ui_end_play_phase()
	t.check(p1.hand.is_empty(), "饥荒：回合结束弃掉所有手牌")
	t.check(not p1.has_status("famine"), "饥荒：结算后状态移除")

func _test_witch_hunt(t) -> void:
	var g: AtlasGame = t.make_game(2)
	_fire_event(g, "event_witch_hunt")
	t.check_eq(g.witch_hunt_owner, 0, "猎巫：记录触发者")
	# 交替到对方回合，打出特殊攻击【裂解】（原 2 点法术伤害）应转化为【普通攻击】
	g.ui_end_play_phase()
	t.check_eq(g.current, 1, "猎巫：进入对方回合")
	g.ui_confirm_interstitial()
	var p1 := g.players[1]
	p1.hand.append("magic_bolt")
	var hp0 := g.players[0].hp
	g.ui_play_card(p1.hand.size() - 1)
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "猎巫：转化牌进入选目标")
	g.ui_select_target(0)
	_skip_responses(g)
	t.check_eq(g.players[0].hp, hp0 - 3, "猎巫：【裂解】按【普通攻击】造成 3 点物理伤害")
	t.check_eq(p1.attacks_used_this_turn, 1, "猎巫：转化的牌计入普攻次数")
	# 触发者下个回合开始时解除
	g.ui_end_play_phase()
	t.check_eq(g.current, 0, "猎巫：回到触发者回合")
	t.check_eq(g.witch_hunt_owner, -1, "猎巫：触发者回合开始时解除")

func _test_forsaken_path1(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.hp = 20
	p.equipment.append("eq_sword")
	p.equipment.append("eq_armor")
	_fire_event(g, "event_forsaken")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "被遗弃者：弹出二选一")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_EVENT_CHOICE, "被遗弃者：pending kind")
	g.ui_skill_pick("path1")
	t.check_eq(p.hp, 10, "被遗弃者①：失去当前 50%（向上取整）生命")
	t.check(p.equipment.is_empty(), "被遗弃者①：装备区清空")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "被遗弃者①：结算后回到出牌阶段")

func _test_forsaken_path2(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.hand = ["basic_attack", "defend1"]
	p.reserve.append("defend2")
	_fire_event(g, "event_forsaken")
	g.ui_skill_pick("path2")
	t.check(p.hand.is_empty(), "被遗弃者②：手牌全弃")
	t.check(p.reserve.is_empty(), "被遗弃者②：预备区清空")

func _test_relief(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[0].hand = []
	g.players[1].hand = []
	g.draw_pile = ["basic_attack", "defend1", "skip", "plunder"]
	_fire_event(g, "event_relief")
	t.check_eq(g.players[0].hand.size(), 2, "救济粮：自己摸 2 张")
	t.check_eq(g.players[1].hand.size(), 2, "救济粮：对方摸 2 张")

func _test_hastur(t) -> void:
	var g: AtlasGame = t.make_game(2)
	_fire_event(g, "event_hastur")
	t.check_eq(g.players[0].hp, 19, "毕宿五：自己失去 1 点生命")
	t.check_eq(g.players[1].hp, 19, "毕宿五：对方失去 1 点生命")
	t.check(g.players[0].has_status("yellow_sign"), "毕宿五：自己获得「黄印」")
	t.check(g.players[1].has_status("yellow_sign"), "毕宿五：对方获得「黄印」")
	# 「黄印」：出牌阶段开始时失去 2 点生命，永久持续
	var p1 := g.players[1]
	var hp_before := p1.hp
	g._enter_play_phase(p1)
	t.check_eq(p1.hp, hp_before - 2, "黄印：出牌阶段开始失去 2 点生命")
	t.check(p1.has_status("yellow_sign"), "黄印：永久持续不消失")
