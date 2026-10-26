extends RefCounted

## 多人对战回归：板子 / 队伍目标解析 / 队伍胜负 / 随机落座 / 跳过收敛 / 陷阱归属。

func run(t) -> void:
	_test_targets_1v1_legacy(t)
	_test_targets_ffa_three(t)
	_test_targets_2v2(t)
	_test_source_not_current(t)
	_test_dead_excluded(t)
	_test_victory_team(t)
	_test_victory_ffa(t)
	_test_victory_all_dead(t)
	_test_trap_team_filter(t)
	_test_skip_chain(t)
	_test_setup_by_board(t)
	_test_dying_rescue_order(t)

## 构造指定板子的对局（不抽牌、不改模式）
func _make_board_game(t, board_id: String, count: int) -> AtlasGame:
	var g: AtlasGame = t.make_game(count)
	g.board = g.db.get_board(board_id)
	for i in count:
		g.players[i].seat_index = i
		g.players[i].team_id = g._team_for_seat(i)
	return g

func _test_targets_1v1_legacy(t) -> void:
	var g := _make_board_game(t, "board_1v1", 2)
	t.check_eq(g._target_candidates("all_allies", ""), [0] as Array[int], "1v1 友方仅自己")
	t.check_eq(g._target_candidates("all_enemies", ""), [1] as Array[int], "1v1 敌方为对手")
	t.check_eq(g._target_candidates("all_others", ""), [1] as Array[int], "1v1 其他玩家为对手")
	var g2: AtlasGame = t.make_game(2)
	t.check_eq(g2._target_candidates("all_allies", ""), [0] as Array[int], "无板子时友方语义不变")

func _test_targets_ffa_three(t) -> void:
	var g := _make_board_game(t, "board_1v1v1", 3)
	t.check_eq(g._target_candidates("all_enemies", ""), [1, 2] as Array[int], "1v1v1 敌方为其余两人")
	t.check_eq(g._target_candidates("all_allies", ""), [0] as Array[int], "1v1v1 友方仅自己")
	t.check_eq(g._target_candidates("all_others", ""), [1, 2] as Array[int], "1v1v1 其他玩家为其余两人")
	t.check_eq(g._target_candidates("single_enemy", ""), [1, 2] as Array[int], "1v1v1 单体敌对目标为其余两人")

func _test_targets_2v2(t) -> void:
	var g := _make_board_game(t, "board_2v2", 4)
	t.check_eq(g._target_candidates("all_enemies", ""), [1, 3] as Array[int], "2v2 敌方为另一队两人")
	t.check_eq(g._target_candidates("all_allies", ""), [0, 2] as Array[int], "2v2 友方为同队含自己")
	t.check_eq(g._target_candidates("all_others", ""), [1, 2, 3] as Array[int], "2v2 其他玩家含队友")
	t.check_eq(g._target_candidates("single_enemy", ""), [1, 2, 3] as Array[int], "2v2 单体目标含队友（描述未写敌人）")
	t.check(!g._target_candidates("all_enemies", "").has(2), "2v2 多目标敌方不含队友")

func _test_source_not_current(t) -> void:
	var g := _make_board_game(t, "board_2v2", 4)
	g.current = 0
	t.check_eq(g._target_candidates_for(2, "all_enemies", ""), [1, 3] as Array[int], "目标按行动来源计算，而非 current")
	t.check_eq(g._target_candidates_for(2, "all_allies", ""), [0, 2] as Array[int], "来源为队友时友方集合正确")

func _test_dead_excluded(t) -> void:
	var g := _make_board_game(t, "board_2v2", 4)
	g.players[1].dead = true
	t.check_eq(g._target_candidates("all_enemies", ""), [3] as Array[int], "死者不再成为目标")
	t.check_eq(g._target_candidates("all_allies", ""), [0, 2] as Array[int], "友方集合不含死者")

func _test_victory_team(t) -> void:
	var g := _make_board_game(t, "board_2v2", 4)
	g.players[1].dead = true
	g._check_deaths()
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "2v2 死一人不结束")
	g.players[3].dead = true
	g._check_deaths()
	t.check_eq(g.mode, AtlasGame.Mode.GAME_OVER, "2v2 全队阵亡结束")
	t.check_eq(g.winner_team_name, "队伍A", "获胜队伍为队伍A")
	t.check_eq(g.winner, "队伍A", "组队模式 winner 为队伍名")
	t.check_eq(g.winner_members.size(), 2, "获胜成员为 2 人")

func _test_victory_ffa(t) -> void:
	var g := _make_board_game(t, "board_1v1v1", 3)
	g.players[2].dead = true
	g._check_deaths()
	t.check_eq(g.mode, AtlasGame.Mode.PLAY, "1v1v1 死一人不结束")
	g.players[1].dead = true
	g._check_deaths()
	t.check_eq(g.mode, AtlasGame.Mode.GAME_OVER, "1v1v1 只剩一人结束")
	t.check_eq(g.winner, "P1", "最后存活者获胜")

func _test_victory_all_dead(t) -> void:
	var g := _make_board_game(t, "board_1v1v1", 3)
	for i in 3:
		g.players[i].dead = true
	g._check_deaths()
	t.check_eq(g.mode, AtlasGame.Mode.GAME_OVER, "全员死亡进入终局")
	t.check_eq(g.winner, "", "全员死亡无胜者")

func _test_trap_team_filter(t) -> void:
	var g := _make_board_game(t, "board_2v2", 4)
	g.players[1].traps.append("trap_ambush")   # 敌方（B 队）
	g.players[2].traps.append("trap_ambush")   # 队友（A 队）
	g._emit_behavior("play_card", 0, {"card_id": "basic_attack"})
	t.check_eq(g.players[1].traps.size(), 0, "敌方陷阱因本方攻击触发")
	t.check_eq(g.players[2].traps.size(), 1, "队友陷阱不因本方行为触发")

func _test_skip_chain(t) -> void:
	var g := _make_board_game(t, "board_2v2", 4)
	for p in g.players:
		p.add_status("skip", -1)
	g._prepare_turn()
	t.check_eq(g._skip_chain, 0, "连续跳过后计数归零")
	for i in 4:
		t.check(not g.players[i].has_status("skip"), "P%d 的「跳过」已被消耗" % (i + 1))
	t.check_eq(g.mode, AtlasGame.Mode.INTERSTITIAL, "跳过一圈后进入正常回合")

func _test_setup_by_board(t) -> void:
	var g := AtlasGame.new()
	g.start_game("board_2v2")
	for cid in ["char_areia", "char_limo", "char_ferrano", "char_shijia"]:
		g.ui_pick_character(cid)
	t.check_eq(g.players.size(), 4, "2v2 板子创建 4 名玩家")
	var seats_ok := true
	var teams_ok := true
	for i in g.players.size():
		if g.players[i].seat_index != i:
			seats_ok = false
		var expect_team := "team_a" if i % 2 == 0 else "team_b"
		if g.players[i].team_id != expect_team:
			teams_ok = false
	t.check(seats_ok, "座位序号与数组下标一致")
	t.check(teams_ok, "2v2 座位 0/2 为 A 队、1/3 为 B 队")
	var hand_ok := true
	for p in g.players:
		if p.hand.size() != p.draw_limit:
			hand_ok = false
	t.check(hand_ok, "初始手牌数量等于摸牌数值（默认 5）")

func _test_dying_rescue_order(t) -> void:
	var g := _make_board_game(t, "board_1v1v1", 3)
	g._open_dying_window(1)
	var rescuers := g.pending.get("rescuers", []) as Array
	t.check_eq(int(rescuers[0]), 1, "救援询问从濒死者本人座位开始")
	t.check_eq(int(rescuers[1]), 2, "救援询问按座位顺序推进")
	t.check_eq(int(rescuers[2]), 0, "救援询问绕回座位 0")
