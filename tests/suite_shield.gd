extends RefCounted

## 护盾机制与溯洄之境新角色：PM10（启泵/气体交换/增压/兴奋）、狄斯托利（我即真理/我即武器/毁灭当量/烈性炸药）、卡丽茜（神经疗法/以毒攻毒/毒素）。

func run(t) -> void:
	_test_shield_blocks_soul(t)
	_test_shield_no_hp_loss(t)
	_test_shield_after_reduction(t)
	_test_pump_opening(t)
	_test_gas_exchange_judge(t)
	_test_boost_to_exhaust(t)
	_test_boost_to_intake(t)
	_test_excitement_double(t)
	_test_truth_gains_explosive(t)
	_test_explosive_extra_damage(t)
	_test_weapon_ask_flow(t)
	_test_destroy_damage(t)
	_test_destroy_locked(t)
	_test_neuro_applies_toxin(t)
	_test_antidote_extra(t)
	_test_toxin_play_phase(t)

# ---------------- 护盾机制 ----------------

func _test_shield_blocks_soul(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[1].shield = 3
	g._settle_damage({"source": 0, "defender": 1, "amount": 5, "damage_type": "soul", "source_name": "测试", "card_id": "", "card_type": "", "instance": -1}, 0)
	t.check_eq(g.players[1].hp, 18, "护盾抵挡 3 点灵魂伤害后承受剩余 2 点")
	t.check_eq(g.players[1].shield, 0, "护盾被消耗殆尽")

func _test_shield_no_hp_loss(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[1].shield = 5
	g._settle_damage({"source": 0, "defender": 1, "amount": 3, "damage_type": "hp_loss", "source_name": "测试", "card_id": "", "card_type": "", "instance": -1}, 0)
	t.check_eq(g.players[1].hp, 17, "生命流失不被护盾抵挡")
	t.check_eq(g.players[1].shield, 5, "护盾不消耗")

func _test_shield_after_reduction(t) -> void:
	# 先算伤害减免，再扣护盾
	var g: AtlasGame = t.make_game(2)
	g.players[1].damage_reduction = 2
	g.players[1].shield = 2
	g._settle_damage({"source": 0, "defender": 1, "amount": 5, "damage_type": "soul", "source_name": "测试", "card_id": "", "card_type": "", "instance": -1}, 0)
	t.check_eq(g.players[1].hp, 19, "5 - 减免2 - 护盾2 = 承受 1 点")
	t.check_eq(g.players[1].shield, 0, "护盾扣除 2 点")

# ---------------- PM10 ----------------

func _test_pump_opening(t) -> void:
	# 〔启泵〕开场技：获得「进气」与 2 点护盾（数据驱动 effects）
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	var sk := g.db.get_skill("skill_pump")
	for fx in sk.get("effects", []):
		for action in fx.get("actions", []):
			g._execute_action(0, action, 0, {"source_name": "〔启泵〕"})
	t.check(p.has_status("intake"), "〔启泵〕获得「进气」")
	t.check_eq(p.shield, 2, "〔启泵〕获得 2 点护盾")

func _test_gas_exchange_judge(t) -> void:
	# 〔气体交换〕：判定阶段开始时「进气」→「排气」并获得一层「兴奋」
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_gas_exchange")
	p.add_status("intake", -1, 1)
	g.mode = AtlasGame.Mode.INTERSTITIAL
	g.ui_confirm_interstitial()
	t.check(p.has_status("exhaust"), "判定阶段开始：「进气」切换为「排气」")
	t.check(not p.has_status("intake"), "「进气」已移除")
	t.check_eq(p.status_layer("excitement"), 1, "获得一层「兴奋」")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "判定/摸牌后进入出牌阶段")

func _test_boost_to_exhaust(t) -> void:
	# 〔增压〕：弃一张手牌额外切换；「进气」→「排气」则摸一张牌
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_boost")
	p.skill_uses_left["skill_boost"] = 1
	p.add_status("intake", -1, 1)
	p.hand.append("basic_attack")
	g.draw_pile.append("basic_attack")
	g.ui_use_skill("skill_boost")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "〔增压〕进入选牌")
	g.ui_skill_pick("hand:0")
	t.check(p.has_status("exhaust"), "〔增压〕切换为「排气」")
	t.check_eq(p.status_layer("excitement"), 1, "〔增压〕触发对应效果：获得一层「兴奋」")
	t.check_eq(p.hand.size(), 1, "切换为「排气」摸一张牌")
	t.check_eq(int(p.skill_uses_left["skill_boost"]), 0, "发动后次数 -1")

func _test_boost_to_intake(t) -> void:
	# 〔增压〕：「排气」→「进气」则我方全体额外 +2 护盾（切换本身再 +2）
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_boost")
	p.skill_uses_left["skill_boost"] = 1
	p.add_status("exhaust", -1, 1)
	p.hand.append("basic_attack")
	g.ui_use_skill("skill_boost")
	g.ui_skill_pick("hand:0")
	t.check(p.has_status("intake"), "〔增压〕切换为「进气」")
	t.check_eq(p.shield, 4, "切换 +2 护盾，〔增压〕额外 +2（自己也是我方）")
	t.check_eq(g.players[1].shield, 2, "我方全体（含队友）额外 +2 护盾")
	t.check_eq(p.hand.size(), 0, "弃牌后不再摸牌")

func _test_excitement_double(t) -> void:
	# 「兴奋」：造成伤害提升100%，然后减少一层
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.add_status("excitement", -1, 1)
	g._deal_damage(0, 1, 2, "physical", "测试", "")
	t.check_eq(int(g.damage_queue[0]["amount"]), 4, "「兴奋」伤害 ×2")
	t.check_eq(p.status_layer("excitement"), 0, "「兴奋」消耗一层")
	g._process_damage_queue()
	while g.mode == AtlasGame.Mode.RESPONSE:
		g.ui_end_response()
	t.check_eq(g.players[1].hp, 16, "结算后目标承受 4 点物理伤害")

# ---------------- 狄斯托利 ----------------

func _test_truth_gains_explosive(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_truth")
	p.skill_uses_left["skill_truth"] = 2
	p.hand.append("basic_attack")
	p.hand.append("defend1")
	g.ui_use_skill("skill_truth")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "〔我即真理〕进入选牌")
	g.ui_skill_pick("hand:0")
	t.check_eq(p.status_layer("explosive"), 1, "获得一层「烈性炸药」")
	t.check_eq(p.hand.size(), 1, "弃掉一张手牌")
	g.ui_use_skill("skill_truth")
	g.ui_skill_pick("hand:0")
	t.check_eq(p.status_layer("explosive"), 2, "第二次发动再获一层")
	t.check_eq(int(p.skill_uses_left["skill_truth"]), 0, "出牌阶段限两次，次数用完")
	g.ui_use_skill("skill_truth")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "次数用完不可再发动")

func _test_explosive_extra_damage(t) -> void:
	# 「烈性炸药」：使用【普通攻击】时额外造成 1 点物理伤害，然后减少一层
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.add_status("explosive", -1, 2)
	p.hand.append("basic_attack")
	g.ui_play_card(0)
	g.ui_select_target(1)
	while g.mode == AtlasGame.Mode.RESPONSE:
		g.ui_end_response()
	t.check_eq(g.players[1].hp, 16, "普攻 3 点 +「烈性炸药」额外 1 点")
	t.check_eq(p.status_layer("explosive"), 1, "「烈性炸药」减少一层")

func _test_weapon_ask_flow(t) -> void:
	# 〔我即武器〕：≥5 层时出牌阶段开始询问；拒绝后再次进入出牌阶段会再询问
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_weapon")
	p.add_status("explosive", -1, 5)
	p.hand.append("basic_attack")
	g._enter_play_phase(p)
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "≥5 层「烈性炸药」弹出觉醒询问")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_WEAPON_ASK, "pending kind 为 weapon_ask")
	g.ui_skill_pick("no")
	t.check(not p.weapon_awakened, "拒绝后未觉醒")
	t.check_eq(p.status_layer("explosive"), 5, "拒绝后保留「烈性炸药」")
	g._enter_play_phase(p)
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "下个出牌阶段开始再次询问")
	g.ui_skill_pick("yes")
	t.check(p.weapon_awakened, "确认后觉醒")
	t.check_eq(p.status_layer("explosive"), 0, "「烈性炸药」清空")
	t.check_eq(p.status_layer("high_explosive"), 5, "转化为等量「高爆炸药」")
	t.check_eq(p.hand.size(), 0, "弃掉所有手牌")
	t.check(p.skill_ids.has("skill_destroy"), "解锁〔毁灭当量〕")

func _test_destroy_damage(t) -> void:
	# 〔毁灭当量〕：5 点灵魂伤害 + X+2Y 点物理伤害，然后清空两种炸药
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_destroy")
	p.weapon_awakened = true
	p.add_status("explosive", -1, 2)
	p.add_status("high_explosive", -1, 3)
	g.ui_use_skill("skill_destroy")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "〔毁灭当量〕进入选目标")
	g.ui_select_target(1)
	while g.mode == AtlasGame.Mode.RESPONSE:
		g.ui_end_response()
	t.check_eq(g.players[1].hp, 7, "承受 5 灵魂 + (2+2×3)=8 物理")
	t.check_eq(p.status_layer("explosive"), 0, "「烈性炸药」清空")
	t.check_eq(p.status_layer("high_explosive"), 0, "「高爆炸药」清空")
	t.check(bool(p.limited_used.get("skill_destroy", false)), "限定技标记已用")
	g.ui_use_skill("skill_destroy")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "限定技每局仅一次")

func _test_destroy_locked(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_destroy")
	g.ui_use_skill("skill_destroy")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "未觉醒〔我即武器〕不可发动〔毁灭当量〕")
	t.check(not bool(p.limited_used.get("skill_destroy", false)), "未发动不消耗限定次数")

# ---------------- 卡丽茜 ----------------

func _test_neuro_applies_toxin(t) -> void:
	# 〔神经疗法〕：【普通攻击】对目标造成伤害后施加一层「毒素」
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_neuro")
	p.hand.append("basic_attack")
	g.ui_play_card(0)
	g.ui_select_target(1)
	while g.mode == AtlasGame.Mode.RESPONSE:
		g.ui_end_response()
	t.check_eq(g.players[1].hp, 17, "普攻造成 3 点伤害")
	t.check_eq(g.players[1].status_layer("toxin"), 1, "目标获得一层「毒素」")

func _test_antidote_extra(t) -> void:
	# 〔以毒攻毒〕：对带「毒素」的敌人造成伤害时额外附带 ceil(层数/2) 点法术伤害
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_antidote")
	g.players[1].add_status("toxin", 2, 3)
	g._deal_damage(0, 1, 2, "physical", "测试", "")
	g._process_damage_queue()
	while g.mode == AtlasGame.Mode.RESPONSE:
		g.ui_end_response()
	t.check_eq(g.players[1].hp, 16, "2 物理 + ceil(3/2)=2 法术")
	t.check(g.damage_queue.is_empty(), "附加伤害不再连锁触发〔以毒攻毒〕")

func _test_toxin_play_phase(t) -> void:
	# 「毒素」：出牌阶段开始时失去相当于层数的生命（每次至多 3 点），触发后清空
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.add_status("toxin", 2, 5)
	g._trigger_turn_start_statuses(p)  # 回合开始 tick：持续 2 → 1
	t.check_eq(p.status_layer("toxin"), 5, "tick 后「毒素」层数保留")
	g._enter_play_phase(p)
	t.check_eq(p.hp, 17, "5 层「毒素」单次至多失去 3 点生命")
	t.check_eq(p.status_layer("toxin"), 0, "触发后清空「毒素」")
	# 2 层时失去 2 点
	p.add_status("toxin", 2, 2)
	g._trigger_turn_start_statuses(p)
	g._enter_play_phase(p)
	t.check_eq(p.hp, 15, "2 层「毒素」失去 2 点生命")
