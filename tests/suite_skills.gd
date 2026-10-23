extends RefCounted

## 技能回归：特判拦截、选牌流程、目标选择。

func run(t) -> void:
	_test_false_step_blocked(t)
	_test_false_step_target(t)
	_test_fractal(t)
	_test_mutual_blocked(t)

func _test_false_step_blocked(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_false_step")
	p.skill_uses_left["skill_false_step"] = 1
	p.hp = 19
	g.ui_use_skill("skill_false_step")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "生命不足时〖失足之幸〗被拦截")
	t.check_eq(int(p.skill_uses_left["skill_false_step"]), 1, "拦截时不消耗次数")
	t.check(g.pending.is_empty(), "拦截时不写入 pending")

func _test_false_step_target(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_false_step")
	p.skill_uses_left["skill_false_step"] = 1
	g.ui_use_skill("skill_false_step")
	t.check_eq(g.mode, AtlasGame.Mode.SELECT_TARGET, "满足条件时进入选目标")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_SKILL, "pending kind 为 skill")

func _test_fractal(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_fractal")
	p.skill_uses_left["skill_fractal"] = 1
	p.hand.append("basic_attack")
	g.ui_use_skill("skill_fractal")
	t.check_eq(g.mode, AtlasGame.Mode.SKILL_PICK, "〖分形几何〗进入选牌")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_FRACTAL, "pending kind 为 fractal")
	g.ui_skill_pick("hand:0")
	t.check_eq(p.reserve.size(), 1, "生成一张预备区防御牌")
	t.check_eq(p.reserve[0], "defend2", "转化为【防御2】")
	t.check_eq(p.hand.size(), 0, "原【普通攻击】已离开手牌")
	t.check_eq(int(p.skill_uses_left["skill_fractal"]), 0, "发动后次数 -1")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "选牌后回到出牌阶段")

func _test_mutual_blocked(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.skill_ids.append("skill_mutual")
	p.skill_uses_left["skill_mutual"] = 1
	g.ui_use_skill("skill_mutual")
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "缺少「玄暗」时〖相生相灭〗发动失败")
	t.check_eq(int(p.skill_uses_left["skill_mutual"]), 1, "失败时不消耗次数")
