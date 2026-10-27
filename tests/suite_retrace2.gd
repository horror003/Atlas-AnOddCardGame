extends RefCounted

## 溯洄之境·溯形态角色回归：喧闹转化、洞悉、嬉闹、跃迁打牌、调序、
## 镣铐防止、韵动溯版、守御溯版、结痂/蚀痕/食痂、黎明、放逐溯版、余孽+方舟遗芯、全视之眼、再生溯版、失足之幸。

func run(t) -> void:
	_test_noise_convert(t)
	_test_perceive_draw(t)
	_test_frolic(t)
	_test_leap_transition_and_play(t)
	_test_reorder_chain(t)
	_test_shackle_prevent(t)
	_test_shackle_decline(t)
	_test_rhythm_boost(t)
	_test_guardian_rt_counter(t)
	_test_guardian_rt_weaken(t)
	_test_scab_record(t)
	_test_eclipse_awaken_and_eat(t)
	_test_dawn_awaken(t)
	_test_exile_rt(t)
	_test_exile_rt_decline(t)
	_test_remnant_ark_core(t)
	_test_all_seeing_peep(t)
	_test_regen_retrace(t)
	_test_false_step_retrace(t)

# ---------------- 溯李斯特：喧闹 ----------------

func _test_noise_convert(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_noise_retrace")
	g.draw_pile = ["skip", "basic_attack"]
	g._draw_raw(p, 2)
	t.check_eq(p.hand.size(), 2, "喧闹：摸到 2 张牌")
	t.check(not p.hand.has("skip"), "喧闹：手牌中的【跳过】被转化")
	t.check(p.hand.has("draw"), "喧闹：【跳过】转化为【抽牌】")

# ---------------- 溯伍灵：洞悉 / 嬉闹 ----------------

func _test_perceive_draw(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_perceive")
	g.draw_pile = ["basic_attack", "defend1", "skip", "plunder"]
	g._draw_cards(p, 2)
	t.check_eq(p.hand.size(), 4, "洞悉：摸 2 改为先摸 4 张")
	t.check_eq(g.mode, AtlasGame.Mode.DISCARD_PICK, "洞悉：进入自选弃牌")
	g.ui_discard_picked("skip")
	t.check_eq(g.mode, AtlasGame.Mode.DISCARD_PICK, "洞悉：还需再弃 1 张")
	g.ui_discard_picked("plunder")
	t.check_eq(p.hand.size(), 2, "洞悉：弃 2 张后剩 2 张")
	t.check(g.discard_pile.has("skip") and g.discard_pile.has("plunder"), "洞悉：弃置的牌进入弃牌堆")

func _test_frolic(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_frolic")
	p.skill_uses_left["skill_frolic"] = 1
	p.own_turn_discards.append("basic_attack")
	g.discard_pile.append("basic_attack")
	g.ui_use_skill("skill_frolic")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "嬉闹：进入选牌")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_FROLIC_CARD, "嬉闹：pending 为选牌")
	g.ui_skill_pick("frolic:0")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "嬉闹：选牌后进入选目标")
	g.ui_select_target(1)
	t.check(g.players[1].hand.has("basic_attack"), "嬉闹：牌加入目标手牌")
	t.check(not g.discard_pile.has("basic_attack"), "嬉闹：牌从弃牌堆取出")
	t.check(p.own_turn_discards.is_empty(), "嬉闹：可选记录已移除")
	t.check_eq(int(p.skill_uses_left["skill_frolic"]), 0, "嬉闹：次数 -1")

# ---------------- 溯序巫：跃迁 / 调序 ----------------

func _test_leap_transition_and_play(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_leap_transition")
	p.skill_uses_left["skill_leap_transition"] = 1
	g.draw_pile = ["basic_attack"]
	g.ui_use_skill("skill_leap_transition")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "跃迁：进入数量选择")
	g.ui_skill_pick("1")
	t.check_eq(p.hp, 18, "跃迁：失去 2X 点生命（X=1）")
	t.check_eq(p.reserve.size(), 1, "跃迁：牌扣置于预备区")
	t.check(p.leap_reserve.has("basic_attack"), "跃迁：记录为跃迁扣置牌")
	g.ui_play_reserve_card(0)
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "跃迁牌当作手牌打出：进入选目标")
	t.check(p.reserve.is_empty() and p.leap_reserve.is_empty(), "跃迁：打出后预备区与记录清空")
	g.ui_select_target(1)
	t.check_eq(int(g.pending.get("amount", 0)), 3, "跃迁打出的普攻造成 3 点伤害")
	g.ui_end_response()
	t.check_eq(g.players[1].hp, 17, "跃迁：目标受到 3 点伤害")

func _test_reorder_chain(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	var tp := g.players[1]
	tp.skill_ids.append("skill_reorder")
	tp.hand = ["basic_attack", "defend1"]
	p.hand.append("plunder")
	g.ui_play_card(0)
	g.ui_select_target(1)
	g.ui_skill_pick("hand:0")  # 掠夺 P2 的【普通攻击】
	t.check(p.hand.has("basic_attack"), "调序铺垫：掠夺得手")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "调序：回合外失去非防御牌触发询问")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_REORDER_OWN, "调序：先弃自己的牌")
	g.ui_skill_pick("hand:0")  # P2 弃掉自己的【防御1】
	t.check(g.discard_pile.has("defend1"), "调序：自己的牌被弃置")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "调序：进入选目标")
	g.ui_select_target(0)  # 选 P1
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "调序：进入盲选手牌")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_REORDER_HAND, "调序：pending 为盲选")
	g.ui_skill_pick("hand:0")  # 盲弃 P1 的【普通攻击】
	t.check(p.hand.is_empty(), "调序：目标手牌被盲弃")
	t.check(g.discard_pile.has("basic_attack"), "调序：盲弃的牌进入弃牌堆")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "调序：结算完毕回到出牌阶段")

# ---------------- 溯“魔王”：困兽 / 韵动 ----------------

func _test_shackle_prevent(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.skill_ids.append("skill_caged_beast_retrace")
	tp.add_status("shackle", -1, 2)
	g._deal_damage(0, 1, 3, "physical", "测试", "basic_attack")
	g._kick_damage()
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "困兽：受伤时询问是否消耗镣铐")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_SHACKLE_ASK, "困兽：pending 为镣铐询问")
	g.ui_skill_pick("yes")
	t.check_eq(tp.status_layer("shackle"), 1, "困兽：消耗一层镣铐")
	t.check_eq(tp.hp, 19, "困兽：伤害被防止，失去 1 点生命")
	t.check(g.damage_queue.is_empty(), "困兽：伤害队列已清空")

func _test_shackle_decline(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.skill_ids.append("skill_caged_beast_retrace")
	tp.add_status("shackle", -1, 2)
	g._deal_damage(0, 1, 3, "physical", "测试", "basic_attack")
	g._kick_damage()
	g.ui_skill_pick("no")
	t.check_eq(g.mode, AtlasGame.Mode.RESPONSE, "困兽：不防止则进入正常响应")
	g.ui_end_response()
	t.check_eq(tp.hp, 17, "困兽：正常受到 3 点伤害")
	t.check_eq(tp.status_layer("shackle"), 2, "困兽：未消耗镣铐")

func _test_rhythm_boost(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_rhythm_retrace")
	p.skill_uses_left["skill_rhythm_retrace"] = 1
	p.add_status("shackle", -1, 2)
	p.hand.append("basic_attack")
	g.ui_use_skill("skill_rhythm_retrace")
	t.check(p.rhythm_next_boost, "韵动：伤害提升标记已置")
	t.check_eq(p.status_layer("shackle"), 1, "韵动：消耗一层镣铐")
	g.ui_play_card(0)
	g.ui_select_target(1)
	t.check_eq(int(g.pending.get("amount", 0)), 6, "韵动：普攻伤害提升 100%（3→6）")
	t.check(not p.rhythm_next_boost, "韵动：打出后标记已消耗")
	g.ui_end_response()
	t.check_eq(g.players[1].hp, 14, "韵动：目标受到 6 点伤害")

# ---------------- 溯伊加尔塔：守御溯版 ----------------

func _test_guardian_rt_counter(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.skill_ids.append("skill_guardian_retrace")
	g.draw_pile = ["ark_core"]  # 非基础牌判定
	g._deal_damage(0, 1, 2, "physical", "测试", "")
	g._kick_damage()
	var guard := 0
	while g.mode == AtlasGame.Mode.RESPONSE and guard < 10:
		g.ui_end_response()
		guard += 1
	t.check(tp.guardian_rt_used, "守御：本回合已触发")
	t.check_eq(g.players[0].hp, 18, "守御：判定非基础牌，反击 2 点物理伤害")

func _test_guardian_rt_weaken(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.skill_ids.append("skill_guardian_retrace")
	g.draw_pile = ["basic_attack"]  # 基础牌判定
	g._deal_damage(0, 1, 2, "physical", "测试", "")
	g._kick_damage()
	var guard := 0
	while g.mode == AtlasGame.Mode.RESPONSE and guard < 10:
		g.ui_end_response()
		guard += 1
	t.check_eq(g.players[0].attack_minus_this_turn, 1, "守御：判定基础牌，来源本回合普攻伤害 -1")
	# 减益生效：普攻 3 → 2
	g._deal_damage(0, 1, 3, "physical", "测试", "basic_attack")
	g._kick_damage()
	t.check_eq(int(g.pending.get("amount", 0)), 2, "守御：减益后普攻伤害 3→2")
	g.ui_end_response()

# ---------------- 溯蚀痂：结痂 / 蚀痕 / 食痂 ----------------

func _test_scab_record(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.skill_ids.append("skill_scab_retrace")
	g._deal_damage(0, 1, 5, "physical", "测试", "")
	g._kick_damage()
	g.ui_end_response()
	t.check_eq(tp.scab, 2, "结痂溯版：回合外受伤记录 ceil(40%)（5→2）")

func _test_eclipse_awaken_and_eat(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_scab_retrace")
	p.skill_ids.append("skill_eclipse")
	# 未觉醒时食痂不可用：即使技能在列表中且有「痂」也不应询问
	p.skill_ids.append("skill_scab_eat")
	p.scab = 10
	g._enter_play_phase(p)
	t.check(not p.scab_evolved, "食痂门控铺垫：未觉醒")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "食痂：未觉醒不弹询问")
	t.check_eq(p.scab, 10, "食痂：未觉醒不清痂")
	p.scab = 21
	p.hp = 2
	g._enter_play_phase(p)
	t.check(p.scab_evolved, "蚀痕：痂 >20 触发觉醒")
	t.check_eq(p.scab, 0, "蚀痕：清空所有痂")
	t.check_eq(p.hp, 17, "蚀痕：回复 15 点生命（2→17）")
	t.check(p.skill_ids.has("skill_scab_eat"), "蚀痕：获得食痂")
	# 进化加成：每 8 层痂 +1/+1
	p.scab = 8
	g._refresh_limits(p)
	t.check_eq(p.hand_limit, 4, "结痂进化：8 层痂存牌 +1")
	t.check_eq(p.draw_limit, 6, "结痂进化：8 层痂摸牌 +1")
	# 食痂：出牌阶段开始询问
	p.hp = 5
	p.scab = 10
	g._enter_play_phase(p)
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "食痂：出牌阶段开始询问")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_SCAB_EAT, "食痂：pending 正确")
	g.ui_skill_pick("yes")
	t.check_eq(p.hp, 15, "食痂：清空痂回复等量生命（5→15）")
	t.check_eq(p.scab, 0, "食痂：痂已清空")
	t.check_eq(p.hand_limit, 3, "食痂：痂清空后进化加成消失")

# ---------------- 溯贾斯汀：黎明 / 再生 / 失足之幸 ----------------

func _test_dawn_awaken(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_dawn")
	p.skill_ids.append("skill_leap_faith")
	p.max_hp = 24
	p.hp = 24
	# 觉醒前信仰之跃被锁定
	g.ui_use_skill("skill_leap_faith")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "黎明：觉醒前信仰之跃不可使用")
	t.check(g.pending.is_empty(), "黎明：觉醒前无 pending")
	g._enter_play_phase(p)
	t.check(p.dawn_awakened, "黎明：生命 ≥20 触发觉醒")
	t.check_eq(p.max_hp, 100, "黎明：生命上限改写为 100")
	t.check_eq(p.hp, 16, "黎明：失去 8 点生命（24→16）")
	t.check_eq(int(p.skill_uses_left.get("skill_leap_faith", 0)), 1, "黎明：信仰之跃获得 1 次")
	# 觉醒后可发动信仰之跃
	g.draw_pile = ["basic_attack", "defend1"]
	g.ui_use_skill("skill_leap_faith")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "黎明：觉醒后信仰之跃可发动")
	g.ui_skill_pick("2")
	t.check_eq(p.hand.size(), 2, "信仰之跃：摸 2 张牌")
	t.check_eq(p.hp, 12, "信仰之跃：失去 2X 点生命（16→12）")

func _test_regen_retrace(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_regen_retrace")
	p.hp = 15
	g._prepare_turn()
	t.check_eq(p.hp, 17, "再生溯版：生命 >11 回复 2 点")
	var g2: AtlasGame = t.make_game(2)
	var p2 := g2.players[0]
	p2.skill_ids.append("skill_regen_retrace")
	p2.hp = 11
	g2._prepare_turn()
	t.check_eq(p2.hp, 14, "再生溯版：生命 ≤11 回复 3 点")
	var g3: AtlasGame = t.make_game(2)
	var p3 := g3.players[0]
	p3.skill_ids.append("skill_regen_retrace")
	p3.hp = 7
	g3._prepare_turn()
	t.check_eq(p3.hp, 11, "再生溯版：生命 ≤7 回复 4 点")

func _test_false_step_retrace(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_false_step_retrace")
	p.skill_uses_left["skill_false_step_retrace"] = 1
	g.players[1].hp = 10
	g.draw_pile = ["basic_attack"]
	g.ui_use_skill("skill_false_step_retrace")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "失足之幸：进入选目标")
	g.ui_select_target(1)
	t.check_eq(p.hp, 16, "失足之幸：自己失去 4 点生命")
	t.check_eq(g.players[1].hp, 13, "失足之幸：目标回复 3 点生命")
	t.check_eq(p.hand.size(), 1, "失足之幸：摸一张牌")

# ---------------- 溯阿瑞亚：放逐溯版 / 余孽 ----------------

func _test_exile_rt(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.skill_ids.append("skill_exile_retrace")
	g.players[0].hand = ["basic_attack"]
	g.players[0].reserve = ["defend1"]
	g._deal_damage(0, 1, 25, "physical", "测试", "")
	g._kick_damage()
	g.ui_end_response()
	t.check(tp.dying, "放逐溯版：目标进入濒死")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "放逐溯版：进入濒死时询问")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_EXILE_RT_ASK, "放逐溯版：pending 正确")
	g.ui_skill_pick("yes")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "放逐溯版：进入选目标")
	g.ui_select_target(0)
	t.check(g.players[0].hand.is_empty() and g.players[0].reserve.is_empty(), "放逐溯版：目标所有区域被清空")
	t.check(g.discard_pile.has("basic_attack") and g.discard_pile.has("defend1"), "放逐溯版：清空的牌视作丢弃")
	t.check(bool(tp.limited_used.get("skill_exile_retrace", false)), "放逐溯版：限定技已标记")
	# 放逐完毕后回归濒死救援窗口
	t.check_eq(g.mode, AtlasGame.Mode.RESPONSE, "放逐溯版：回归濒死救援窗口")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_DYING_SAVE, "放逐溯版：濒死者等待救援")

func _test_exile_rt_decline(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var tp := g.players[1]
	tp.skill_ids.append("skill_exile_retrace")
	g._deal_damage(0, 1, 25, "physical", "测试", "")
	g._kick_damage()
	g.ui_end_response()
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "放逐溯版：询问弹出")
	g.ui_skill_pick("no")
	t.check(not bool(tp.limited_used.get("skill_exile_retrace", false)), "放逐溯版：放弃则不消耗限定技")
	t.check_eq(g.mode, AtlasGame.Mode.RESPONSE, "放逐溯版：放弃后进入濒死救援窗口")

func _test_remnant_ark_core(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_remnant")
	g.ui_use_skill("skill_remnant")
	t.check(p.damage_immune, "余孽：免疫任何伤害")
	t.check_eq(p.hp, 10, "余孽：失去 30 点生命触发濒死，方舟遗芯复活 50%（20→10）")
	t.check(not p.dying, "余孽：方舟遗芯跳过救援直接复活")
	t.check(not p.reserve.has("ark_core"), "余孽：方舟遗芯已弃置")
	t.check(not g.discard_pile.has("ark_core"), "余孽：方舟遗芯为 token 牌，弃置后移出游戏而非进入弃牌堆")
	t.check(bool(p.limited_used.get("skill_remnant", false)), "余孽：限定技已标记")
	# 免疫验证：伤害无效
	g._deal_damage(1, 0, 5, "physical", "测试", "")
	t.check(g.damage_queue.is_empty(), "余孽：免疫期间伤害不入队")
	t.check_eq(p.hp, 10, "余孽：免疫期间生命不变")
	# 免疫验证：生命流失同样无效
	g._lose_hp_direct(p, 5, "测试生命流失")
	t.check_eq(p.hp, 10, "余孽：免疫期间生命流失无效")

# ---------------- 溯奥比亚：全视之眼 ----------------

func _test_all_seeing_peep(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_all_seeing")
	p.skill_uses_left["skill_all_seeing"] = 1
	g.ui_use_skill("skill_all_seeing")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "全视之眼：进入选目标")
	g.ui_select_target(1)
	var tp := g.players[1]
	t.check_eq(tp.status_layer("peep"), 1, "全视之眼：目标获得 1 层窥探")
	g._refresh_limits(tp)
	t.check_eq(tp.hand_limit, 2, "窥探：存牌数值 -1")
	t.check_eq(tp.draw_limit, 4, "窥探：摸牌数值 -1")
