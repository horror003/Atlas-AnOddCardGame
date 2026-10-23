extends RefCounted

## 伤害管线回归：伤害加算/乘算、格挡响应、不可响应伤害、直接失去生命。

func run(t) -> void:
	_test_status_bonus(t)
	_test_cold_penalty(t)
	_test_defense_response(t)
	_test_soul_unresponsive(t)
	_test_hp_loss(t)

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
