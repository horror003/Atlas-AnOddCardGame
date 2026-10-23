extends RefCounted

## 特殊事件回归：抽取 → 展示确认 → 结算效果。

func run(t) -> void:
	_test_heal_event(t)
	_test_draw_all_event(t)

func _test_heal_event(t) -> void:
	var g: AtlasGame = t.make_game(2)
	var p := g.players[0]
	p.hp = 15
	g.event_deck.append("event_heal_2")
	g._trigger_event(0)
	t.check_eq(g.mode, AtlasGame.Mode.EVENT_SHOW, "事件先进入展示确认")
	t.check_eq(String(g.pending.get("kind", "")), AtlasGame.PENDING_EVENT_SHOW, "pending kind 为 event_show")
	t.check_eq(String(g.pending.get("event_id", "")), "event_heal_2", "pending 记录事件 id")
	g.ui_confirm_event_show()
	t.check_eq(p.hp, 17, "『一息尚存』回复 2 点生命")

func _test_draw_all_event(t) -> void:
	var g: AtlasGame = t.make_game(2)
	for i in 4:
		g.draw_pile.append("basic_attack")
	g.event_deck.append("event_draw_all")
	g._trigger_event(0)
	g.ui_confirm_event_show()
	t.check_eq(g.players[0].hand.size(), 1, "『全员补给』P1 摸 1 张")
	t.check_eq(g.players[1].hand.size(), 1, "『全员补给』P2 摸 1 张")
