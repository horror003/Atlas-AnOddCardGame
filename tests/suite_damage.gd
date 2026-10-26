extends RefCounted

## 伤害管线回归：伤害加算/乘算、格挡响应、不可响应伤害、直接失去生命。

func run(t) -> void:
	_test_status_bonus(t)
	_test_cold_penalty(t)
	_test_defense_response(t)
	_test_soul_unresponsive(t)
	_test_hp_loss(t)
	_test_self_death_ends_turn(t)

func _test_status_bonus(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[0].add_status("attack_up_1")
	g._deal_damage(0, 1, 3, "physical", "测试", "basic_attack")
	t.check_eq(g.damage_queue.size(), 1, "伤害入队一次")
	t.check_eq(int(g.damage_queue[0]["amount"]), 4, "「奋击」使普通攻击伤害 +1")
	t.check(not g.players[0].has_status("attack_up_1"), "「奋击」结算后移除")

func _test_cold_penalty(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[0].add_status("cold_1")
	g._deal_damage(0, 1, 3, "physical", "测试", "basic_attack")
	t.check_eq(int(g.damage_queue[0]["amount"]), 2, "「寒冷1」使本次伤害 -1")

func _test_defense_response(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[1].hand.append("defend1")
	g._deal_damage(0, 1, 3, "physical", "测试", "basic_attack")
	g._kick_damage()
	t.check_eq(g.mode, AtlasGame.Mode.RESPONSE, "物理伤害进入响应窗口")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_DAMAGE, "pending kind 为 damage")
	g._play_response_card(0)
	g.ui_end_response()
	t.check_eq(g.players[1].hp, 18, "【防御1】格挡 1 点，实际受到 2 点伤害")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "伤害结算后回到出牌阶段")

func _test_soul_unresponsive(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g._deal_damage(0, 1, 2, "soul", "测试", "")
	g._kick_damage()
	t.check_eq(g.players[1].hp, 18, "灵魂伤害直接结算")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "灵魂伤害不进入响应窗口")

func _test_hp_loss(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[0].hp = 15
	g._lose_hp_direct(g.players[0], 3, "测试")
	t.check_eq(g.players[0].hp, 12, "失去生命直接扣血")
	t.check(not g.players[0].dying, "生命未归零时不进入濒死")

func _test_self_death_ends_turn(t) -> void:
	var g: AtlasGame = t.make_game(3)
	# 三人各自为队，确保一人死亡不会直接终局，才能验证回合交接
	for i in g.players.size():
		g.players[i].team_id = "team_%d" % i
	g.players[0].hp = 5
	g._lose_hp_direct(g.players[0], 5, "测试自伤")
	t.check(g.players[0].dying, "自伤致死进入「濒死」")
	t.check(g._ensure_dying_window(), "先开启濒死救援窗口")
	var guard := 0
	while g.mode == AtlasGame.Mode.RESPONSE and guard < 10:
		g.ui_end_response()
		guard += 1
	t.check(g.players[0].dead, "无人救援后宣布死亡")
	t.check_eq(g.mode, AtlasGame.Mode.INTERSTITIAL, "死者回合立即结束并进入下一名玩家的回合交接")
	t.check_eq(g.current, 1, "行动权交给下一名存活玩家")
