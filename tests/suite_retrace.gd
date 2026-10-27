extends RefCounted

## 溯洄之境回归：掠夺机制、电棱/时钟悖论/演算机器/祝祷/圣徒/卫道/开膛手/开棺/千载幽咽、牌池过滤。

func run(t) -> void:
	_test_pool_filter(t)
	_test_plunder_card(t)
	_test_plunder_any_zone(t)
	_test_ion_prism_flow(t)
	_test_electro_turn_end(t)
	_test_electro_damage_reduction(t)
	_test_converge(t)
	_test_converge_blocked(t)
	_test_clock_paradox_skip_discard(t)
	_test_clock_paradox_attack_used(t)
	_test_clock_paradox_expires(t)
	_test_damage_reduction_settle(t)
	_test_machine_on_plunder(t)
	_test_machine_defense_excluded(t)
	_test_prayer_self(t)
	_test_prayer_other(t)
	_test_guardian_way(t)
	_test_ripper_attack_and_plunder(t)
	_test_ripper_plunder_reserve(t)
	_test_ripper_turn_cap(t)
	_test_millennium_and_coffin(t)
	_test_millennium_two_marks(t)

# ---------------- 牌池过滤 ----------------

func _test_pool_filter(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var classic_chars := g.db.characters_for_pool("classic")
	var retrace_chars := g.db.characters_for_pool("retrace")
	t.check(not classic_chars.is_empty(), "经典池角色非空")
	t.check_eq(classic_chars.size(), 15, "经典池 15 名角色（6 通用 + 9 经典专属）")
	t.check_eq(retrace_chars.size(), 19, "溯洄之境池 19 名角色（6 通用 + 4 新 + 9 溯形态）")
	var classic_deck := g.db.deck_composition_for_pool("classic")
	var retrace_deck := g.db.deck_composition_for_pool("retrace")
	t.check(not classic_deck.has("plunder"), "经典池牌堆不含【掠夺】")
	t.check_eq(int(retrace_deck.get("plunder", 0)), 4, "溯洄之境牌堆含 4 张【掠夺】")

# ---------------- 掠夺基础牌 ----------------

func _test_plunder_card(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.hand.append("plunder")
	g.players[1].hand.append("defend1")
	g.ui_play_card(0)
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "【掠夺】进入选目标")
	g.ui_select_target(1)
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "确认目标后进入盲选")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_PLUNDER, "pending kind 为 plunder")
	g.ui_skill_pick("hand:0")
	t.check_eq(String(p.hand[0]), "defend1", "掠夺的牌加入自己手牌")
	t.check(g.players[1].hand.is_empty(), "目标失去该手牌")
	t.check(g.discard_pile.has("plunder"), "【掠夺】本身进入弃牌堆")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "结算后回到出牌阶段")

func _test_plunder_any_zone(t) -> void:
	# 【掠夺】扩展：可掠夺手牌/装备/预备/陷阱任意区域，得手后加入来源对应区域
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.hand.append("plunder")
	var tp := g.players[1]
	tp.equipment.append("eq_sword")
	tp.reserve.append("defend2")
	tp.traps.append("trap_ambush")
	g.ui_play_card(0)
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "掠夺全区域：进入选目标")
	g.ui_select_target(1)
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "掠夺全区域：目标无手牌也可掠夺（进入选牌）")
	var opts: Array = g.pending.get("options", [])
	t.check(opts.has("equip:0") and opts.has("reserve:0") and opts.has("trap:0"), "掠夺全区域：选项覆盖装备/预备/陷阱")
	g.ui_skill_pick("reserve:0")
	t.check(p.reserve.has("defend2"), "掠夺全区域：预备区牌加入自己预备区")
	t.check(tp.reserve.is_empty(), "掠夺全区域：目标失去预备区牌")
	# 掠夺装备区 → 加入自己装备区
	p.hand.append("plunder")
	g.ui_play_card(p.hand.size() - 1)
	g.ui_select_target(1)
	g.ui_skill_pick("equip:0")
	t.check(p.equipment.has("eq_sword"), "掠夺全区域：装备牌加入自己装备区")

# ---------------- 元明：电离棱体 / 电棱 / 聚合 ----------------

func _test_ion_prism_flow(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_ion_prism")
	p.skill_uses_left["skill_ion_prism"] = 1
	p.hand.append("basic_attack")
	g.ui_use_skill("skill_ion_prism")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "〖电离棱体〗进入选牌")
	g.ui_skill_pick("hand:0")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "选牌后进入选目标")
	t.check_eq(p.hand.size(), 1, "确认目标前手牌未移除")
	g.ui_select_target(1)
	t.check_eq(p.hand.size(), 0, "确认后弃牌生效")
	t.check_eq(g.players[1].status_layer("electro_prism"), 1, "目标获得 1 层「电棱」")
	t.check_eq(int(p.skill_uses_left["skill_ion_prism"]), 0, "发动后次数 -1")

func _test_electro_turn_end(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.add_status("electro_prism", -1, 2)
	tp.hp = 20
	g.current = 1
	g._end_turn()
	t.check_eq(tp.hp, 18, "「电棱」回合结束造成层数点物理伤害")
	t.check_eq(tp.status_layer("electro_prism"), 2, "「电棱」层数保留")
	t.check_eq(g.mode, AtlasGame.Mode.INTERSTITIAL, "回合交替到下一玩家")

func _test_electro_damage_reduction(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.add_status("electro_prism", -1, 2)
	tp.damage_reduction = 1
	tp.hp = 20
	g.current = 1
	g._end_turn()
	t.check_eq(tp.hp, 19, "「电棱」伤害可被伤害减免削减")

func _test_converge(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_converge")
	p.skill_uses_left["skill_converge"] = 99
	var tp := g.players[1]
	tp.add_status("electro_prism", -1, 2)
	tp.hand.append("basic_attack")
	g.ui_use_skill("skill_converge")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "〖聚合〗进入选目标")
	g.ui_select_target(1)
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "〖聚合〗进入掠夺盲选")
	g.ui_skill_pick("hand:0")
	t.check_eq(p.hand.size(), 1, "掠夺的手牌加入自己手牌")
	t.check(tp.hand.is_empty(), "目标失去手牌")
	t.check_eq(tp.status_layer("electro_prism"), 0, "目标所有「电棱」被清除")

func _test_converge_blocked(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_converge")
	p.skill_uses_left["skill_converge"] = 99
	g.players[1].add_status("electro_prism", -1, 1)  # 仅 1 层，不满足 ≥2
	g.ui_use_skill("skill_converge")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "无 ≥2 层「电棱」目标时〖聚合〗发动失败")
	t.check_eq(int(p.skill_uses_left["skill_converge"]), 99, "失败时不消耗次数")

# ---------------- 派克：时钟悖论 / 演算机器 ----------------

func _test_clock_paradox_skip_discard(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_clock_paradox")
	p.attacks_used_this_turn = 0
	for i in 5:
		p.hand.append("basic_attack")  # 手牌 5 > 上限 3
	g.ui_end_play_phase()
	t.check_eq(p.damage_reduction, 1, "未用普攻 → 获得 1 点伤害减免")
	t.check(p.paradox_reduction, "减免标记已设置")
	t.check_eq(g.mode, AtlasGame.Mode.INTERSTITIAL, "跳过弃牌阶段直接结束回合")
	t.check_eq(p.hand.size(), 5, "跳过弃牌阶段，手牌不弃")

func _test_clock_paradox_attack_used(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_clock_paradox")
	p.attacks_used_this_turn = 1
	for i in 5:
		p.hand.append("basic_attack")
	g.ui_end_play_phase()
	t.check_eq(p.damage_reduction, 0, "用过普攻 → 不获得减免")
	t.check_eq(g.mode, AtlasGame.Mode.DISCARD, "正常进入弃牌阶段")

func _test_clock_paradox_expires(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.paradox_reduction = true
	p.damage_reduction = 1
	g._enter_play_phase(p)
	t.check_eq(p.damage_reduction, 0, "进入下个出牌阶段时减免失效")
	t.check(not p.paradox_reduction, "减免标记已清除")

func _test_damage_reduction_settle(t) -> void:
	var g: AtlasGame = t.make_game(2)
	g.players[1].damage_reduction = 2
	g._settle_damage({"source": 0, "defender": 1, "amount": 3, "damage_type": "soul", "source_name": "测试", "card_id": "", "card_type": "", "instance": -1}, 0)
	t.check_eq(g.players[1].hp, 19, "伤害减免每次受伤等额削减")
	g._settle_damage({"source": 0, "defender": 1, "amount": 3, "damage_type": "hp_loss", "source_name": "测试", "card_id": "", "card_type": "", "instance": -1}, 0)
	t.check_eq(g.players[1].hp, 16, "生命流失不受伤害减免影响")

func _test_machine_on_plunder(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var mp := g.players[1]
	mp.skill_ids.append("skill_computing_machine")
	mp.hp = 10
	mp.hand.append("basic_attack")
	g._start_plunder(0, 1, "card")
	g.ui_skill_pick("hand:0")
	t.check_eq(mp.hp, 11, "回合外失去 1 张非【防御】牌 → 回复 1 点")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_MACHINE, "弹出〖演算机器〗二选一")
	g.ui_skill_pick("heal")
	t.check_eq(mp.hp, 13, "选择②回复 2 点")
	t.check(mp.machine_heal_used, "②本回合已用")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "结算后回到出牌阶段")

func _test_machine_defense_excluded(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var mp := g.players[1]
	mp.skill_ids.append("skill_computing_machine")
	mp.hp = 10
	mp.hand.append("defend1")  # 【防御】牌不触发
	g._start_plunder(0, 1, "card")
	g.ui_skill_pick("hand:0")
	t.check_eq(mp.hp, 10, "失去【防御】牌不触发〖演算机器〗")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "无弹窗直接回到出牌阶段")

# ---------------- 十修：祝祷 / 圣徒 / 卫道 ----------------

func _test_prayer_self(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_prayer")
	p.skill_ids.append("skill_saint")
	p.skill_uses_left["skill_prayer"] = 1
	p.hp = 10
	p.hand.append("basic_attack")
	p.hand.append("basic_attack")
	g.ui_use_skill("skill_prayer")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "〖祝祷〗先选回复对象")
	g.ui_skill_pick("self")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "进入两步弃牌")
	g.ui_skill_pick("hand:0")
	g.ui_skill_pick("hand:0")
	t.check_eq(p.hp, 13, "〖祝祷〗自己回复 3 点")
	t.check_eq(p.saint_used, 1, "〖圣徒〗触发一次")
	t.check_eq(p.hand.size(), 1, "弃 2 张后〖圣徒〗摸 1 张")
	t.check_eq(int(p.skill_uses_left["skill_prayer"]), 0, "发动后次数 -1")

func _test_prayer_other(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_prayer")
	p.skill_uses_left["skill_prayer"] = 1
	p.hand.append("basic_attack")
	p.hand.append("basic_attack")
	var tp := g.players[1]
	tp.hp = 10  # 已损 10 → ceil(20%)=2，+3 = 回复 5
	g.ui_use_skill("skill_prayer")
	g.ui_skill_pick("other")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "为他人回复需先选目标")
	g.ui_select_target(1)
	g.ui_skill_pick("hand:0")
	g.ui_skill_pick("hand:0")
	t.check_eq(tp.hp, 15, "〖祝祷〗为他人回复 ceil(20%% 已损)+3")

func _test_guardian_way(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_guardian_way")
	p.skill_uses_left["skill_guardian_way"] = 1
	g.ui_use_skill("skill_guardian_way")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "〖卫道〗进入选目标")
	g.ui_select_target(1)
	t.check_eq(g.players[1].hp, 17, "〖卫道〗造成 3 点灵魂伤害")
	t.check_eq(p.hp, 18, "〖卫道〗自己失去 2 点生命")

# ---------------- 瑞普：开膛手 / 开棺 / 千载幽咽 ----------------

func _test_ripper_attack_and_plunder(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_ripper")
	p.hand.append("basic_attack")
	g.players[1].hand.append("basic_attack")
	g.ui_play_card(0)
	g.ui_select_target(1)
	t.check_eq(g.players[1].hp, 18, "〖开膛手〗普攻默认 2 点灵魂伤害")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_RIPPER_ASK, "弹出〖开膛手〗掠夺询问")
	g.ui_skill_pick("yes")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "进入掠夺盲选")
	g.ui_skill_pick("hand:0")
	t.check_eq(g._funerary_count(p), 1, "预备区扣置 1 张【陪葬品】")
	t.check(g.players[1].hand.is_empty(), "目标手牌被掠夺")
	t.check_eq(p.hand.size(), 0, "原牌未进入手牌（入弃牌堆）")
	t.check_eq(p.funerary_this_turn, 1, "本回合掠夺计数 +1")

func _test_ripper_plunder_reserve(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_ripper")
	p.hand.append("basic_attack")
	g.players[1].reserve.append("defend1")  # 目标手牌为空，仅预备区有牌
	g.ui_play_card(0)
	g.ui_select_target(1)
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_RIPPER_ASK, "开膛手：目标仅预备区有牌也弹出询问")
	g.ui_skill_pick("yes")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "开膛手：进入掠夺选牌")
	t.check(g.pending.get("options", []).has("reserve:0"), "开膛手：选项含预备区牌")
	g.ui_skill_pick("reserve:0")
	t.check_eq(g._funerary_count(p), 1, "开膛手：掠夺预备区牌扣置【陪葬品】")
	t.check(g.players[1].reserve.is_empty(), "开膛手：目标预备区牌被掠夺")
	t.check(g.discard_pile.has("defend1"), "开膛手：原牌视作丢弃")

func _test_ripper_turn_cap(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_ripper")
	p.funerary_this_turn = 2  # 已达每回合上限
	p.hand.append("basic_attack")
	g.players[1].hand.append("basic_attack")
	g.ui_play_card(0)
	g.ui_select_target(1)
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "每回合至多掠夺 2 张，超出后不再询问")

func _test_millennium_and_coffin(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_ripper")
	p.skill_ids.append("skill_open_coffin")
	p.skill_ids.append("skill_millennium")
	p.skill_uses_left["skill_open_coffin"] = 99
	p.reserve.append("token_funerary")
	p.reserve.append("token_funerary")
	g.ui_use_skill("skill_millennium")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "〖千载幽咽〗进入选目标")
	g.ui_select_target(1)
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "仅一名可选目标时直接完成指定")
	t.check(p.millennium_marks.has(1), "目标已被指定")
	g.ui_use_skill("skill_open_coffin")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "〖开棺〗进入选目标")
	g.ui_select_target(1)
	t.check_eq(g.players[1].hp, 17, "〖千载幽咽〗指定目标：普攻默认 3 点灵魂伤害")
	t.check_eq(g._funerary_count(p), 0, "〖开棺〗消耗 2 张【陪葬品】")
	t.check_eq(p.attacks_used_this_turn, 1, "视作打出一张【普通攻击】")

func _test_millennium_two_marks(t) -> void:
	var g: AtlasGame = t.make_game(3)
	var p := g.players[0]
	p.skill_ids.append("skill_ripper")
	p.skill_ids.append("skill_millennium")
	g.ui_use_skill("skill_millennium")
	g.ui_select_target(1)
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_MILLENNIUM_ASK, "3 人局弹出再指定询问")
	g.ui_skill_pick("more")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "再选第 2 名目标")
	var cands := g.target_candidates_now()
	t.check(not cands.has(1), "已指定目标不再出现在候选中")
	g.ui_select_target(2)
	t.check_eq(p.millennium_marks.size(), 2, "至多指定 2 名目标")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "指定完成回到出牌阶段")
