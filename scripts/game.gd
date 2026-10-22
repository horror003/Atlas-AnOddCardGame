class_name AtlasGame
extends RefCounted

## 游戏核心逻辑：回合状态机 + 规则结算。
## 对应规则文档第 2~6 章：角色/属性、卡牌与区域、战斗流程、伤害/防御/濒死、信息公开。
## 与 UI 完全解耦：UI 调用 ui_* 方法，通过 message 信号接收日志，读取公开状态刷新界面。

signal message(text: String)

# 回合阶段：规则文档 4.2（判定 → 摸牌 → 出牌 → 弃牌）
enum Phase { JUDGE, DRAW, PLAY, DISCARD }

# UI 交互模式（热座操作的状态机）
enum Mode { SELECT_CHAR, INTERSTITIAL, PLAY, SELECT_TARGET, RESPONSE, DISCARD, SKILL_PICK, DISCARD_PICK, EVENT_SHOW, GAME_OVER }

const PHASE_NAMES := ["判定阶段", "摸牌阶段", "出牌阶段", "弃牌阶段"]

# 状态 id -> 显示名（命名规范：状态效果用「」展示）
const STATUS_NAMES := {
	"skip": "「跳过」",
	"attack_up_1": "「奋击·攻击+1」",
}

# 伤害类型 id -> 显示名（规则 5.1）
const DAMAGE_TYPE_NAMES := {
	"physical": "物理",
	"magical": "法术",
	"soul": "灵魂",
	"hp_loss": "生命流失",
}

var db: CardDB
var players: Array[PlayerData] = []
var current: int = 0                  # 当前行动玩家下标
var phase: int = Phase.JUDGE
var mode: int = Mode.SELECT_CHAR
var first_turn: bool = true

var draw_pile: Array[String] = []     # 抽牌堆（全场共用，规则 3.1）
var discard_pile: Array[String] = []  # 弃牌堆（全场共用）
var event_deck: Array[String] = []    # 特殊事件牌堆（独立，规则 3.3）

var turn_discards: Array[String] = []      # 本回合进入弃牌堆的牌
var last_turn_discards: Array[String] = [] # 上一回合进入弃牌堆的牌（信息公开，规则 6.1）

var pending: Dictionary = {}          # 待结算动作上下文（选目标 / 伤害响应 / 技能选牌）
var damage_queue: Array[Dictionary] = []  # 伤害队列：一次攻击多类型=多次独立伤害（规则 5.1）
var damage_return_to: String = "play" # 伤害队列清空后的回归点："play" / "judge"
var winner: String = ""

var picked_char_ids: Array[String] = []  # 选人阶段已选角色 id（规则 4.1）
var _card_instance_seq: int = 0          # 卡牌实例序号（同一张牌多段伤害只算一次）
var _exile_done: Dictionary = {}         # 已处理过〖放逐〗询问的玩家下标

func _init() -> void:
	db = CardDB.new()

func _log(text: String) -> void:
	message.emit(text)

func _to_discard(card_id: String) -> void:
	# 进入弃牌堆，并记录本回合弃牌（信息公开，规则 6.1）
	discard_pile.append(card_id)
	turn_discards.append(card_id)

# ---------------- 游戏开始与选人（规则 4.1） ----------------

func start_game() -> void:
	# 选人阶段：玩家1先选，玩家2后选，不可重复
	mode = Mode.SELECT_CHAR
	_log("—— 选人阶段：请 玩家1 选择角色 ——")

func ui_pick_character(char_id: String) -> void:
	if mode != Mode.SELECT_CHAR:
		return
	if picked_char_ids.has(char_id):
		return
	var c := db.get_character(char_id)
	if c.is_empty():
		return
	picked_char_ids.append(char_id)
	if picked_char_ids.size() == 1:
		_log("玩家1 选择了 %s。请 玩家2 选择角色。" % String(c.get("name", char_id)))
		return
	_log("玩家2 选择了 %s。" % String(c.get("name", char_id)))
	_setup_players()

func _setup_players() -> void:
	# 1. 根据所选角色创建玩家
	for i in range(2):
		var c := db.get_character(picked_char_ids[i])
		var p := PlayerData.new()
		p.name = "玩家%d·%s" % [i + 1, String(c.get("name", "?"))]
		p.char_id = String(c.get("id", ""))
		p.attribute_ids.clear()
		for aid in c.get("attribute_ids", []):
			p.attribute_ids.append(String(aid))
		p.max_hp = int(c.get("max_hp", 20))
		p.hp = p.max_hp
		p.hand_limit = int(c.get("hand_limit", 3))
		p.draw_limit = int(c.get("draw_limit", 5))
		p.base_hand_limit = p.hand_limit
		p.base_draw_limit = p.draw_limit
		for sid in c.get("skill_ids", []):
			p.skill_ids.append(String(sid))
		players.append(p)
	for pl in players:
		_refresh_limits(pl)
	# 2. 组建抽牌堆并洗牌
	for id in db.deck_composition.keys():
		for i in range(int(db.deck_composition[id])):
			draw_pile.append(String(id))
	draw_pile.shuffle()
	# 特殊事件牌堆（独立牌堆，规则 3.3）
	for e in db.event_deck_list:
		event_deck.append(e)
	event_deck.shuffle()
	# 3. 抽取初始手牌：数量 = 存牌数值（规则 3.1）
	# 洞悉玩家需自选弃牌，改为队列式逐个处理
	_setup_draw_queue.clear()
	for i in players.size():
		_setup_draw_queue.append(i)
	# 标记「正在开局抽初始手牌」，供洞悉弃牌结束后正确恢复流程
	_setup_drawing = true
	_process_setup_draw()

var _setup_draw_queue: Array[int] = []
var _setup_drawing: bool = false

func _process_setup_draw() -> void:
	if _setup_draw_queue.is_empty():
		_finish_setup()
		return
	var idx := _setup_draw_queue[0]
	_setup_draw_queue.remove_at(0)
	var p := players[idx]
	_draw_cards(p, p.hand_limit)
	# 若触发洞悉进入弃牌选择，等待玩家操作后继续
	if mode == Mode.DISCARD_PICK:
		return
	_process_setup_draw()

func _finish_setup() -> void:
	# 开局初始手牌抽取结束，清除标记（此后摸牌均按正常回合流程处理）
	_setup_drawing = false
	# 4. 随机确定先手
	current = randi() % players.size()
	_log("游戏开始！%s 先手。" % players[current].name)
	# 5. 触发开场技能（规则 2.3：选人→抽初始手牌→定先手后，按座位顺序结算）
	for i in players.size():
		var p := players[i]
		for sid in p.skill_ids:
			var sk := db.get_skill(sid)
			if String(sk.get("skill_type", "")) == "opening":
				_log("%s 触发开场技能%s。" % [p.name, String(sk.get("name", sid))])
				_run_actions(i, sk.get("effects", []), i, {"source_name": String(sk.get("name", sid))})
	_prepare_turn()

# ---------------- 回合流程（规则 4.2） ----------------

func _prepare_turn() -> void:
	# 信息公开：每回合开始时快照上一回合进入弃牌堆的牌（规则 6.1）
	last_turn_discards = turn_discards.duplicate()
	turn_discards.clear()
	var p := players[current]
	# 规则 5.4：「跳过」令玩家跳过下一个完整回合，跳过后自动解除
	if p.has_status("skip"):
		p.remove_status("skip")
		_log("%s 带有「跳过」，跳过其整个回合。" % p.name)
		_advance_player()
		_prepare_turn()
		return
	# 每回合重置主动技使用次数与被动计数
	p.skill_uses_left.clear()
	for sid in p.skill_ids:
		var sk := db.get_skill(sid)
		var stype := String(sk.get("skill_type", ""))
		if stype == "active" or stype == "switch":
			p.skill_uses_left[sid] = int(sk.get("max_uses_per_turn", 1))
	p.attacks_used_this_turn = 0
	# 触发回合开始状态效果（如「燃烧」）
	_trigger_turn_start_statuses(p)
	# 新回合：重置〖困兽〗与〖韵动〗的每回合计数，并刷新动态摸牌/存牌数值
	for pl in players:
		pl.caged_beast_used = false
	_refresh_limits(p)
	# 〖结痂〗：回复「痂」记录值并清空
	if _has_skill(p, "skill_scab") and p.scab > 0:
		var scab_val := p.scab
		p.scab = 0
		var old_hp := p.hp
		p.hp = mini(p.max_hp, p.hp + scab_val)
		_log("%s 的「痂」结算：回复 %d 点生命（%d → %d）。" % [p.name, p.hp - old_hp, old_hp, p.hp])
	# 〖再生〗：回合开始时回复 2 点；生命 ≤7 时改为 4 点
	if _has_skill(p, "skill_regen") and not p.dead:
		var regen := 4 if p.hp <= 7 else 2
		var old2 := p.hp
		p.hp = mini(p.max_hp, p.hp + regen)
		_log("%s 触发〖再生〗，回复 %d 点生命（%d → %d）。" % [p.name, p.hp - old2, old2, p.hp])
	# 重置被动触发次数（属性 + 装备 + 装备组合共用，key 为 显示名_hook）
	p.attribute_uses_left.clear()
	var passive_sources: Array[Dictionary] = []
	for aid in p.attribute_ids:
		passive_sources.append(db.get_attribute(aid))
	for eq_id in p.equipment:
		passive_sources.append(db.get_card(eq_id))
	for combo in _active_combos(p):
		passive_sources.append(combo)
	for src_cfg in passive_sources:
		var passive: Dictionary = src_cfg.get("passive", {})
		if passive.is_empty():
			continue
		var max_uses := int(passive.get("max_uses_per_turn", 0))
		if max_uses > 0:
			var uses_key := String(src_cfg.get("name", "")) + "_" + String(passive.get("hook", ""))
			p.attribute_uses_left[uses_key] = max_uses
	pending = {}
	mode = Mode.INTERSTITIAL

# 热座交接确认，开始当前玩家的回合
func ui_confirm_interstitial() -> void:
	if mode != Mode.INTERSTITIAL:
		return
	var p := players[current]
	# 判定阶段（规则 4.2-1）：结算自己预备区中的延时判定牌
	phase = Phase.JUDGE
	_run_judge_phase(p)
	if mode == Mode.GAME_OVER:
		return
	# 判定可能产生伤害，先清空伤害队列再进入摸牌/出牌阶段
	if not damage_queue.is_empty():
		damage_return_to = "judge"
		_process_damage_queue()
		return
	_after_judge()

func _has_skill(p: PlayerData, skill_id: String) -> bool:
	return p.skill_ids.has(skill_id)

func _refresh_limits(p: PlayerData) -> void:
	## 动态计算存牌/摸牌数值（〖骗局〗〖疫医〗）
	var hand := p.base_hand_limit
	var draw := p.base_draw_limit
	if _has_skill(p, "skill_deception"):
		hand = maxi(hand, 4)
		draw = maxi(draw, 6)
	if _has_skill(p, "skill_plague_doctor"):
		var higher := false
		for other in players:
			if other != p and not other.dead and other.hp > p.hp:
				higher = true
				break
		if higher:
			hand = maxi(hand, 4)
			draw = maxi(draw, 6)
	p.hand_limit = hand
	p.draw_limit = draw

func _ceil_pct(value: int, pct: int) -> int:
	return int(ceil(float(value) * float(pct) / 100.0))

func _lose_hp_direct(p: PlayerData, val: int, reason: String) -> void:
	## 直接失去生命（不经过防御/装备），只标记濒死，由后续流程开救援窗口
	if val <= 0:
		return
	p.hp -= val
	_log("%s 失去 %d 点生命（%s），剩余生命 %d。" % [p.name, val, reason, maxi(0, p.hp)])
	if p.hp <= 0 and not p.dying and not p.dead:
		p.hp = 0
		p.dying = true
		_log("%s 生命归零，进入「濒死」！" % p.name)

func _add_status_capped(p: PlayerData, status_id: String, layers: int, duration: int) -> int:
	## 按 statuses.json 的 max_layers 限制叠层，返回实际叠加层数
	var cap := int(db.statuses.get(status_id, {}).get("max_layers", 99))
	var cur := p.status_layer(status_id)
	var add := clampi(layers, 0, cap - cur)
	if add <= 0:
		return 0
	p.add_status(status_id, duration, add)
	return add

func _on_card_played(p: PlayerData) -> void:
	## 打出手牌时触发「恶化1」
	var n := p.status_layer("worsen_1")
	if n > 0:
		p.consume_layer("worsen_1")
		_log("%s 因「恶化1」失去 1 点生命（剩余 %d 层）。" % [p.name, p.status_layer("worsen_1")])
		_lose_hp_direct(p, 1, "「恶化1」")

func _after_judge() -> void:
	if mode == Mode.GAME_OVER:
		return
	var p := players[current]
	if p.dead:
		return
	_refresh_limits(p)
	# 摸牌阶段：将手牌补至摸牌数值（规则 4.2-2）
	phase = Phase.DRAW
	var need := p.draw_limit - p.hand.size()
	if need > 0:
		_draw_cards(p, need)
		if mode == Mode.DISCARD_PICK:
			return  # 洞悉等待自选弃牌，ui_discard_picked 会在弃完后调用 _enter_play_phase 继续
		_log("%s 摸牌阶段：补 %d 张牌（现有 %d 张，目标 %d 张）。" % [p.name, need, p.hand.size(), p.draw_limit])
	else:
		_log("%s 摸牌阶段：手牌已达摸牌数值，无需补牌。" % p.name)
	_enter_play_phase(p)

func _enter_play_phase(p: PlayerData) -> void:
	# 进入出牌阶段（规则 4.2-3）
	phase = Phase.PLAY
	mode = Mode.PLAY
	first_turn = false
	p.rhythm_used = false
	_log("—— %s 的出牌阶段 ——" % p.name)

func ui_end_play_phase() -> void:
	if mode != Mode.PLAY:
		return
	var p := players[current]
	phase = Phase.DISCARD
	_refresh_limits(p)
	# 弃牌阶段：手牌超过存牌数值则弃至上限（规则 4.2-4）
	if p.hand.size() > p.hand_limit:
		mode = Mode.DISCARD
		_log("弃牌阶段：%s 需弃置 %d 张牌。" % [p.name, p.hand.size() - p.hand_limit])
	else:
		_end_turn()

func _trigger_turn_start_statuses(p: PlayerData) -> void:
	## 回合开始时触发所有 on_turn_start 状态效果，并减少持续时间
	var to_trigger: Array[String] = []
	for sid in p.status_ids():
		var st: Dictionary = db.statuses.get(sid, {})
		if String(st.get("trigger", "")) == "on_turn_start":
			to_trigger.append(sid)
	# 先触发效果，再减持续
	for sid in to_trigger:
		var st: Dictionary = db.statuses.get(sid, {})
		var sname := String(st.get("name", sid))
		var effects: Array = st.get("effects", [])
		if not effects.is_empty():
			_log("%s 触发%s效果！" % [p.name, sname])
		for action in effects:
			_execute_action(current, action, current, {})
	# 减少所有状态的剩余回合数
	var expired: Array[String] = []
	for sid in p.status_ids():
		if not p.tick_status(sid):
			var st: Dictionary = db.statuses.get(sid, {})
			var sname := String(st.get("name", sid))
			_log("%s 的%s已消失。" % [p.name, sname])

func _end_turn() -> void:
	var p := players[current]
	# 清理本回合临时状态（如「奋击·攻击+1」的增益，持续时间为"本回合"）
	if p.has_status("attack_up_1"):
		p.remove_status("attack_up_1")
	pending = {}
	_advance_player()
	_prepare_turn()

func _advance_player() -> void:
	current = (current + 1) % players.size()
	# 已死亡玩家不再行动
	var guard := 0
	while players[current].dead and guard < players.size():
		current = (current + 1) % players.size()
		guard += 1

# ---------------- 摸牌 / 牌堆（规则 3.1） ----------------

func _draw_cards(p: PlayerData, n: int) -> void:
	if n <= 0:
		return
	# 洞悉：锁定技，所有摸牌行为改为先摸 2n 张，再自选弃 n 张
	if "skill_perceive" in p.skill_ids:
		var sk_name := String(db.get_skill("skill_perceive").get("name", "skill_perceive"))
		_log("%s 生效：%s 本次摸牌改为先摸 %d 张，再自选弃 %d 张。" % [sk_name, p.name, n * 2, n])
		_draw_raw(p, n * 2)
		pending = {"kind": "discard_pick", "target": players.find(p), "count": n, "picker": "self", "setup": _setup_drawing}
		mode = Mode.DISCARD_PICK
		_log("请选择 %d 张手牌弃置。" % n)
		return
	_draw_raw(p, n)

func _draw_raw(p: PlayerData, n: int) -> void:
	for i in range(n):
		# 抽牌堆耗尽时，将弃牌堆洗牌后成为新的抽牌堆
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				_log("抽牌堆与弃牌堆均已空，无法摸牌。")
				return
			draw_pile = discard_pile
			discard_pile = []
			draw_pile.shuffle()
			_log("抽牌堆耗尽：弃牌堆洗牌后成为新的抽牌堆。")
		var top_card: String = draw_pile.pop_back()
		p.hand.append(top_card)

# ---------------- 出牌（UI 入口，按模式分发） ----------------

func ui_play_card(card_index: int) -> void:
	match mode:
		Mode.PLAY:
			_play_in_play_phase(card_index)
		Mode.RESPONSE:
			_play_response_card(card_index)
		Mode.DISCARD:
			_discard_one(card_index)

func _play_in_play_phase(card_index: int) -> void:
	var p := players[current]
	if card_index < 0 or card_index >= p.hand.size():
		return
	var card_id := p.hand[card_index]
	var card := db.get_card(card_id)
	var card_type := String(card.get("type", ""))
	var card_name := String(card.get("name", card_id))
	match card_type:
		"basic":
			# 【防御】类牌：提前布置到预备区（规则 3.4），响应时也可直接从手牌打出
			if bool(card.get("is_defense", false)):
				_play_card_from_hand(p, card_index)
				p.reserve.append(card_id)
				_log("%s 将%s布置到预备区。" % [p.name, card_name])
				return
			_play_targeted_or_direct(p, card_index, card_id, card)
		"food":
			# 食物牌（规则 3.3）：默认只能对自己使用；有角色「濒死」时可给该角色
			_play_targeted_or_direct(p, card_index, card_id, card)
		"equipment":
			_play_equipment(p, card_index, card_id, card)
		"trap":
			# 陷阱牌（规则 3.3）：必须先布置到陷阱区才能生效
			_play_card_from_hand(p, card_index)
			p.traps.append(card_id)
			_log("%s 布置了一道陷阱。" % p.name)
		"delayed_judge":
			# 延时判定牌：打出后进入目标预备区，其判定阶段结算
			_play_targeted_or_direct(p, card_index, card_id, card)
		_:
			_play_targeted_or_direct(p, card_index, card_id, card)

# 需要选目标的牌：进入 SELECT_TARGET；候选仅自己时直接结算
func _play_targeted_or_direct(p: PlayerData, card_index: int, card_id: String, card: Dictionary) -> void:
	var target_type := String(card.get("target_type", "none"))
	# 多目标类型：直接对所有目标结算，不进入选择
	if target_type in ["all_players", "all_enemies", "all_allies", "all_others"]:
		var candidates := _target_candidates(target_type, card_id)
		if candidates.is_empty():
			_log("没有合法目标，无法打出%s。" % String(card["name"]))
			return
		var card_name := String(card.get("name", card_id))
		_log("%s 打出了%s（目标：%s）。" % [p.name, card_name, _target_type_name(target_type)])
		_play_card_from_hand(p, card_index)
		_to_discard(card_id)
		var ctx := {"card_id": card_id, "source_name": card_name, "instance": _card_instance_seq}
		if _card_deals_damage(card) and _has_skill(p, "skill_rhythm") and not p.rhythm_used:
			p.rhythm_used = true
			ctx["rhythm"] = true
			_log("%s 触发〖韵动〗：%s 的每段伤害提升100%%。" % [p.name, card_name])
		for t_idx in candidates:
			_run_actions(current, card.get("effects", []), t_idx, ctx)
		_emit_behavior("play_card", current, {"card_id": card_id})
		_kick_damage()
		return
	if target_type == "single_any" or target_type == "single_enemy" or target_type == "self_or_dying":
		var candidates := _target_candidates(target_type, card_id)
		if candidates.is_empty():
			_log("没有合法目标，无法打出%s。" % String(card["name"]))
			return
		# 候选只有自己时直接结算（如食物牌场上无濒死者）
		if candidates.size() == 1 and candidates[0] == current:
			_resolve_played_card(p, card_index, card_id, card, current)
			return
		pending = {
			"kind": "card",
			"source": current,
			"card_id": card_id,
			"hand_index": card_index,
			"target_type": target_type,
		}
		mode = Mode.SELECT_TARGET
		_log("请选择%s的目标。" % String(card["name"]))
		return
	# 无需选目标的牌：直接结算
	_resolve_played_card(p, card_index, card_id, card, current)

# 装备牌：打出即放入装备栏（规则 3.3/3.4）
func _play_equipment(p: PlayerData, card_index: int, card_id: String, card: Dictionary) -> void:
	var card_name := String(card.get("name", card_id))
	# 装备栏共 3 个栏位
	if p.equipment.size() >= 3:
		_log("装备栏已满（3 件），无法装备%s。" % card_name)
		return
	# 规则 3.4：不可同时装备三件同类型装备
	var sub := String(card.get("subtype", ""))
	var same := 0
	for eq in p.equipment:
		if String(db.get_card(eq).get("subtype", "")) == sub:
			same += 1
	if p.equipment.size() == 2 and same == 2:
		_log("不可同时装备三件同类型装备（%s），%s 装备失败。" % [sub, card_name])
		return
	_play_card_from_hand(p, card_index)
	p.equipment.append(card_id)
	_log("%s 装备了%s。" % [p.name, card_name])
	# 装备后检查装备组合是否激活（组合定义中含本装备且此时已凑齐）
	for combo in _active_combos(p):
		if (combo.get("parts", []) as Array).has(card_id):
			_log("%s 激活装备组合%s：%s" % [p.name, String(combo.get("name", "")), String(combo.get("description", ""))])

# 结算一张已确定目标的牌：移除手牌、进弃牌堆、执行效果、触发陷阱钩子
func _play_card_from_hand(p: PlayerData, index: int) -> void:
	## 从手牌打出（非弃置）：触发「恶化1」并占用一个新的卡牌实例序号
	_remove_hand_card(p, index)
	_card_instance_seq += 1
	_on_card_played(p)

func _card_deals_damage(card: Dictionary) -> bool:
	for fx in card.get("effects", []):
		for action in fx.get("actions", []):
			if String(action.get("type", "")) == "deal_damage":
				return true
	return false

func _reserve_defense_total(p: PlayerData) -> int:
	var total := 0
	for cid in p.reserve:
		var c := db.get_card(cid)
		if bool(c.get("is_defense", false)):
			total += int(c.get("defense_value", 0))
	return total

func _apply_bloodline(p: PlayerData) -> void:
	## 〖血裔〗：失去 ceil(10% 当前生命)，至少1点，然后回复3点
	var cost := maxi(1, _ceil_pct(p.hp, 10))
	_lose_hp_direct(p, cost, "〖血裔〗")
	var old := p.hp
	p.hp = mini(p.max_hp, p.hp + 3)
	_log("%s 触发〖血裔〗，回复 %d 点生命（%d → %d）。" % [p.name, p.hp - old, old, p.hp])
	if p.hp > 0 and p.dying:
		p.dying = false
		_log("%s 脱离了「濒死」。" % p.name)

func _resolve_played_card(p: PlayerData, card_index: int, card_id: String, card: Dictionary, target_idx: int) -> void:
	_play_card_from_hand(p, card_index)
	_to_discard(card_id)
	var card_name := String(card.get("name", card_id))
	if target_idx == current:
		_log("%s 打出了%s。" % [p.name, card_name])
	else:
		_log("%s 对 %s 打出了%s。" % [p.name, players[target_idx].name, card_name])
	# 每回合首张【普通攻击】计数（被动条件判定用）
	if card_id == "basic_attack":
		p.attacks_used_this_turn += 1
		if _has_skill(p, "skill_bloodline"):
			_apply_bloodline(p)
	var card_type := String(card.get("type", ""))
	# 延时判定牌：进入目标预备区而非弃牌堆结算
	if card_type == "delayed_judge":
		discard_pile.erase(card_id)
		turn_discards.erase(card_id)
		players[target_idx].reserve.append(card_id)
		_log("%s 进入 %s 的预备区，将在其判定阶段结算。" % [card_name, players[target_idx].name])
		return
	# 【跳过】特殊结算：解除或进入抵消响应窗口
	if card_id == "skip":
		_resolve_skip(p, target_idx)
		return
	var ctx := {"card_id": card_id, "source_name": card_name, "instance": _card_instance_seq}
	# 〖韵动〗：每个出牌阶段第一张伤害类型牌的每段伤害 ×2
	if _card_deals_damage(card) and _has_skill(p, "skill_rhythm") and not p.rhythm_used:
		p.rhythm_used = true
		ctx["rhythm"] = true
		_log("%s 触发〖韵动〗：%s 的每段伤害提升100%%。" % [p.name, card_name])
	_run_actions(current, card.get("effects", []), target_idx, ctx)
	# 〖千钧之数〗：普攻附加一次预备区防御点数和×30%（向下取整）的灵魂伤害
	if card_id == "basic_attack" and _has_skill(p, "skill_thousand_weight"):
		var extra := int(floor(float(_reserve_defense_total(p)) * 0.3))
		if extra > 0:
			damage_queue.append({
				"source": current,
				"defender": target_idx,
				"amount": extra,
				"damage_type": "soul",
				"source_name": "〖千钧之数〗",
				"card_id": "",
				"card_type": "",
				"instance": _card_instance_seq,
			})
			_log("〖千钧之数〗追加 %d 点灵魂伤害。" % extra)
	# 陷阱钩子：对手打出牌时触发（规则 3.3）
	_emit_behavior("play_card", current, {"card_id": card_id})
	_kick_damage()

# 【跳过】结算（规则 3.3）：对已有「跳过」者使用=解除；否则其他玩家可打【跳过】抵消
func _resolve_skip(src_p: PlayerData, target_idx: int) -> void:
	var target := players[target_idx]
	if target.has_status("skip"):
		target.remove_status("skip")
		_log("%s 的「跳过」被%s解除了。" % [target.name, src_p.name])
		return
	# 进入抵消响应窗口：目标（或队友）可打出另一张【跳过】抵消
	pending = {
		"kind": "skip_response",
		"source": current,
		"defender": target_idx,
	}
	mode = Mode.RESPONSE
	_log("%s 即将获得「跳过」，可打出另一张【跳过】抵消。" % target.name)

func ui_select_target(target_idx: int) -> void:
	if mode != Mode.SELECT_TARGET or pending.is_empty():
		return
	if not target_candidates_now().has(target_idx):
		return
	var kind := String(pending.get("kind", ""))
	if kind == "card":
		var p := players[current]
		var card_id := String(pending["card_id"])
		var hand_index := int(pending["hand_index"])
		var card := db.get_card(card_id)
		pending = {}
		mode = Mode.PLAY
		_resolve_played_card(p, hand_index, card_id, card, target_idx)
	elif kind == "event":
		var event := db.get_event(String(pending["event_id"]))
		var src := int(pending["source"])
		pending = {}
		mode = Mode.PLAY
		_log("事件目标：%s。" % players[target_idx].name)
		_run_actions(src, event.get("effects", []), target_idx, {"source_name": String(event["name"])})
		_kick_damage()
	elif kind == "skill":
		var skill := db.get_skill(String(pending["skill_id"]))
		var src := int(pending["source"])
		pending = {}
		mode = Mode.PLAY
		players[src].skill_uses_left[String(skill["id"])] = int(players[src].skill_uses_left.get(String(skill["id"]), 1)) - 1
		_log("%s 发动了%s，目标：%s。" % [players[src].name, String(skill["name"]), players[target_idx].name])
		_run_actions(src, skill.get("effects", []), target_idx, {"source_name": String(skill["name"])})
		_kick_damage()
	elif kind == "sage_target":
		var src := int(pending["source"])
		var p := players[src]
		var sid := String(pending.get("sage_status", "vulnerable_1"))
		var form := int(pending.get("sage_form", 0))
		var sage_token := String(pending.get("sage_token", ""))
		pending = {}
		mode = Mode.PLAY
		var discarded := _take_zone_card(p, sage_token)
		if discarded.is_empty():
			_log("要丢弃的牌已不存在，〖贤者之书〗发动失败。")
			return
		_to_discard(discarded)
		_log("%s 发动〖贤者之书〗，丢弃了 %s。" % [p.name, String(db.get_card(discarded).get("name", discarded))])
		p.skill_uses_left["skill_sage_book"] = int(p.skill_uses_left.get("skill_sage_book", 1)) - 1
		var applied := _add_status_capped(players[target_idx], sid, 2, -1)
		var sname := String(db.statuses.get(sid, {}).get("name", sid))
		p.sage_mode = (form + 1) % 3
		_log("%s 对 %s 施加 %d 层%s，〖贤者之书〗转为形态 %s。" % [p.name, players[target_idx].name, applied, sname, ["①", "②", "③"][p.sage_mode]])
	elif kind == "mutual":
		var src := int(pending["source"])
		var p := players[src]
		if players[target_idx].status_layer("pale") <= 0:
			return
		var x := mini(2, p.status_layer("dark"))
		var y := p.status_layer("crimson")
		pending = {}
		mode = Mode.PLAY
		p.skill_uses_left["skill_mutual"] = int(p.skill_uses_left.get("skill_mutual", 1)) - 1
		for i in x:
			p.consume_layer("dark")
		for i in mini(x, players[target_idx].status_layer("pale")):
			players[target_idx].consume_layer("pale")
		_log("%s 发动〖相生相灭〗：移除 %d 层「玄暗」，对 %s 造成 %d 点灵魂伤害。" % [p.name, x, players[target_idx].name, x * 2])
		_deal_damage(src, target_idx, x * 2, "soul", "〖相生相灭〗")
		if y > 0:
			for i in y:
				p.consume_layer("crimson")
			_log("并移除 %d 层「猩红」，追加 %d 点灵魂伤害。" % [y, y])
			_deal_damage(src, target_idx, y, "soul", "〖相生相灭〗")
		_kick_damage()
	elif kind == "exile_target":
		var src := int(pending["source"])
		var tp := players[target_idx]
		pending = {}
		mode = Mode.PLAY
		var all_cards: Array[String] = []
		for cid in tp.hand:
			all_cards.append(cid)
		for cid in tp.equipment:
			all_cards.append(cid)
		for cid in tp.reserve:
			all_cards.append(cid)
		for cid in tp.traps:
			all_cards.append(cid)
		tp.hand.clear()
		tp.equipment.clear()
		tp.reserve.clear()
		tp.traps.clear()
		for cid in all_cards:
			_to_discard(cid)
		_log("%s 发动〖放逐〗，清空了 %s 的所有区域（共 %d 张牌进入弃牌堆）。" % [players[src].name, tp.name, all_cards.size()])
		_finalize_dying(src)

# 取消选目标（卡牌/技能/转换技/事件/放逐均可取消）
func ui_cancel_target() -> void:
	if mode != Mode.SELECT_TARGET:
		return
	var kind := String(pending.get("kind", ""))
	if kind == "card" or kind == "mutual" or kind == "sage_target" or kind == "skill":
		pending = {}
		mode = Mode.PLAY
		_log("取消了出牌。")
	elif kind == "event":
		pending = {}
		mode = Mode.PLAY
		_log("放弃了事件结算。")
	elif kind == "exile_target":
		var src := int(pending.get("source", current))
		pending = {}
		mode = Mode.PLAY
		_log("%s 放弃发动〖放逐〗。" % players[src].name)
		_finalize_dying(src)

# 供 UI 查询当前可选目标
func target_candidates_now() -> Array[int]:
	if mode != Mode.SELECT_TARGET:
		return []
	var kind := String(pending.get("kind", ""))
	if kind == "exile_target":
		var src := int(pending.get("source", current))
		var res: Array[int] = []
		for i in players.size():
			if i != src and not players[i].dead:
				res.append(i)
		return res
	if kind == "mutual":
		var src2 := int(pending.get("source", current))
		var res2: Array[int] = []
		for i in players.size():
			if i != src2 and not players[i].dead and players[i].status_layer("pale") > 0:
				res2.append(i)
		return res2
	return _target_candidates(String(pending.get("target_type", "none")), String(pending.get("card_id", "")))

# 目标候选（规则：「濒死」角色不能再成为伤害/效果目标，治疗与食物除外）
func _target_candidates(target_type: String, card_id: String) -> Array[int]:
	var result: Array[int] = []
	for i in players.size():
		var p := players[i]
		match target_type:
			"single_any":
				if p.dead or p.dying:
					continue
				result.append(i)
			"single_enemy":
				if p.dead or p.dying or i == current:
					continue
				result.append(i)
			"self_or_dying":
				# 食物牌：自己；或任意「濒死」角色（视为其使用，规则 3.3）
				if i == current and not p.dead and not p.dying:
					result.append(i)
				elif p.dying and not p.dead:
					result.append(i)
			"all_players":
				# 场上所有存活玩家（含自己）
				if not p.dead:
					result.append(i)
			"all_enemies":
				# 所有敌方玩家（不含自己）
				if not p.dead and i != current:
					result.append(i)
			"all_allies":
				# 所有友方玩家（当前仅含自己，预留组队扩展）
				if not p.dead and i == current:
					result.append(i)
			"all_others":
				# 除了自己之外的所有存活玩家
				if not p.dead and i != current:
					result.append(i)
	return result

func _remove_hand_card(p: PlayerData, index: int) -> void:
	if index >= 0 and index < p.hand.size():
		p.hand.remove_at(index)

# ---------------- 效果解释器（数据驱动结算） ----------------

func _run_actions(src_idx: int, effects: Array, target_idx: int, ctx: Dictionary = {}) -> void:
	for fx in effects:
		for action in fx.get("actions", []):
			_execute_action(src_idx, action, target_idx, ctx)

func _execute_action(src_idx: int, action: Dictionary, target_idx: int, ctx: Dictionary) -> void:
	var type := String(action.get("type", ""))
	# 解析动作目标："self" 为行动者自己，"selected" 为选中的目标
	var t := src_idx if String(action.get("target", "selected")) == "self" else target_idx
	match type:
		"deal_damage":
			var mult := 2.0 if bool(ctx.get("rhythm", false)) else 1.0
			_deal_damage(src_idx, t, int(action.get("value", 0)), String(action.get("damage_type", "physical")), String(ctx.get("source_name", "未知来源")), String(ctx.get("card_id", "")), mult)
		"add_status":
			var sid := String(action.get("status_id", ""))
			var dur := int(action.get("duration", -1))
			players[t].add_status(sid, dur, int(action.get("layers", 1)))
			var sname := String(db.statuses.get(sid, {}).get("name", sid))
			if dur > 0:
				_log("%s 获得%s（持续 %d 回合）。" % [players[t].name, sname, dur])
			else:
				_log("%s 获得%s。" % [players[t].name, sname])
		"draw_cards":
			_draw_cards(players[t], int(action.get("value", 1)))
			_log("%s 摸了 %d 张牌。" % [players[t].name, int(action.get("value", 1))])
		"draw_all":
			for p in players:
				if p.dead or p.dying:
					continue
				_draw_cards(p, int(action.get("value", 1)))
			_log("全体玩家各摸 %d 张牌。" % int(action.get("value", 1)))
		"heal":
			# 规则 5.5：治疗一般不可超过生命上限；治疗可作用于「濒死」角色
			var p := players[t]
			var old := p.hp
			p.hp = mini(p.max_hp, p.hp + int(action.get("value", 0)))
			if p.hp > 0 and p.dying:
				p.dying = false
				_log("%s 脱离了「濒死」。" % p.name)
			_log("%s 回复 %d 点生命（%d → %d）。" % [p.name, p.hp - old, old, p.hp])
		"random_discard":
			var p := players[t]
			if p.hand.is_empty():
				_log("%s 没有手牌可弃。" % p.name)
			else:
				var r := randi() % p.hand.size()
				var cid := p.hand[r]
				p.hand.remove_at(r)
				_to_discard(cid)
				_log("随机弃置了 %s 的 1 张手牌（%s）。" % [p.name, String(db.get_card(cid)["name"])])
		"discard_target_pick":
			var p := players[t]
			if p.hand.is_empty():
				_log("%s 没有手牌可弃。" % p.name)
			else:
				var count := int(action.get("value", 1))
				pending = {"kind": "discard_pick", "target": t, "count": count, "picker": "actor", "source": src_idx}
				mode = Mode.DISCARD_PICK
				_log("请选择 %s 的 %d 张手牌弃置。" % [p.name, count])
		"trigger_event":
			_trigger_event(src_idx)
		"lose_hp":
			# 失去生命：不受防御/装备影响，直接扣血
			var p := players[t]
			var val := int(action.get("value", 1))
			p.hp -= val
			_log("%s 失去 %d 点生命（剩余 %d）。" % [p.name, val, p.hp])
			if p.hp <= 0 and not p.dying and not p.dead:
				p.hp = 0
				p.dying = true
				_log("%s 进入「濒死」状态！" % p.name)
				_open_dying_window(t)
		_:
			push_warning("未实现的动作类型：" + type)

# ---------------- 伤害与防御响应（规则 5.1 / 5.2） ----------------

# 伤害统一入队：一次攻击多类型=多次独立伤害，分次响应（规则 5.1/5.2）
func _deal_damage(src_idx: int, target_idx: int, base_amount: int, damage_type: String, source_name: String, card_id: String = "", multiplier: float = 1.0) -> void:
	var target := players[target_idx]
	# 规则 5.3：「濒死」角色不能再被伤害
	if target.dying or target.dead:
		_log("%s 处于「濒死」或已死亡，无法成为伤害目标。" % target.name)
		return
	var src := players[src_idx]
	var card: Dictionary = db.get_card(card_id) if not card_id.is_empty() else {}
	var card_type := String(card.get("type", ""))
	var amount := base_amount
	# 1. 基础伤害改动（〖方舟之剑〗〖困兽〗）
	if card_id == "basic_attack":
		if _has_skill(src, "skill_ark_sword"):
			amount = 4
		if _has_skill(target, "skill_caged_beast") and not target.caged_beast_used:
			target.caged_beast_used = true
			amount = 1
			_log("%s 触发〖困兽〗：本回合受到的第一张【普通攻击】默认伤害改为 1 点。" % target.name)
	# 2. 加算
	# 「奋击·攻击+1」：你使用的下一张【普通攻击】伤害+1
	if card_id == "basic_attack" and src.has_status("attack_up_1"):
		amount += 1
		src.remove_status("attack_up_1")
		_log("%s 生效：本次【普通攻击】伤害 +1。" % String(db.statuses.get("attack_up_1", {}).get("name", "attack_up_1")))
	# 通用被动系统：装备/属性效果统一结算
	amount = _apply_passives_outgoing(src, target, card_id, damage_type, amount, src_idx)
	amount = _apply_passives_incoming(src, target, card_id, damage_type, amount, src_idx)
	# 「寒冷1」：造成伤害时本次伤害 -1，然后减少一层
	if src.has_status("cold_1"):
		src.consume_layer("cold_1")
		amount -= 1
		_log("%s 因「寒冷1」本次伤害 -1（剩余 %d 层）。" % [src.name, src.status_layer("cold_1")])
	# 3. 乘算
	if not is_equal_approx(multiplier, 1.0):
		amount = int(floor(float(amount) * multiplier))
	amount = maxi(0, amount)
	damage_queue.append({
		"source": src_idx,
		"defender": target_idx,
		"amount": amount,
		"damage_type": damage_type,
		"source_name": source_name,
		"card_id": card_id,
		"card_type": card_type,
		"instance": _card_instance_seq,
	})
	_log("%s 即将受到 %d 点%s伤害（来源：%s）。" % [target.name, amount, String(DAMAGE_TYPE_NAMES.get(damage_type, damage_type)), source_name])

# 通用被动系统：造成伤害时的装备/属性效果结算
func _apply_passives_outgoing(src: PlayerData, target: PlayerData, card_id: String, damage_type: String, amount: int, src_idx: int) -> int:
	var result := amount
	# 装备被动
	for eq_id in src.equipment:
		var eq := db.get_card(eq_id)
		var pas: Dictionary = eq.get("passive", {})
		result = _apply_single_passive(pas, src, target, card_id, damage_type, result, String(eq.get("name", eq_id)), src_idx, "outgoing")
	# 属性被动
	for aid in src.attribute_ids:
		var attr := db.get_attribute(aid)
		var attr_pas: Dictionary = attr.get("passive", {})
		result = _apply_single_passive(attr_pas, src, target, card_id, damage_type, result, String(attr.get("name", aid)), src_idx, "outgoing")
	# 装备组合被动（同时装备指定装备时激活）
	for combo in _active_combos(src):
		result = _apply_single_passive(combo.get("passive", {}), src, target, card_id, damage_type, result, String(combo.get("name", "")), src_idx, "outgoing")
	return result

# 通用被动系统：受到伤害时的装备效果结算
func _apply_passives_incoming(src: PlayerData, target: PlayerData, card_id: String, damage_type: String, amount: int, src_idx: int) -> int:
	var result := amount
	for eq_id in target.equipment:
		var eq := db.get_card(eq_id)
		var pas: Dictionary = eq.get("passive", {})
		result = _apply_single_passive(pas, src, target, card_id, damage_type, result, String(eq.get("name", eq_id)), src_idx, "incoming")
	# 装备组合被动（同时装备指定装备时激活）
	for combo in _active_combos(target):
		result = _apply_single_passive(combo.get("passive", {}), src, target, card_id, damage_type, result, String(combo.get("name", "")), src_idx, "incoming")
	return result

# 装备组合：当玩家同时装备组合指定的全部装备时激活（combos.json 数据驱动）
func _active_combos(p: PlayerData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for combo_v in db.combos:
		var combo: Dictionary = combo_v
		var parts: Array = combo.get("parts", [])
		if parts.size() < 2:
			continue
		var all_equipped := true
		for pid in parts:
			if not p.equipment.has(String(pid)):
				all_equipped = false
				break
		if all_equipped:
			out.append(combo)
	return out

# 结算单个被动效果
func _apply_single_passive(pas: Dictionary, src: PlayerData, target: PlayerData, card_id: String, damage_type: String, amount: int, display_name: String, src_idx: int, direction: String) -> int:
	if pas.is_empty():
		return amount
	var hook := String(pas.get("hook", ""))
	var cond: Dictionary = pas.get("conditions", {})
	var effect: Dictionary = pas.get("effect", {})
	# 检查触发时机
	if direction == "outgoing" and hook != "on_outgoing_damage":
		return amount
	if direction == "incoming" and hook != "on_incoming_damage":
		return amount
	# 检查条件
	if not _check_passive_conditions(cond, src, target, card_id, damage_type):
		return amount
	# 检查每回合使用次数（次数与效果归属：造成伤害时归来源，受到伤害时归受伤者）
	var owner: PlayerData = target if direction == "incoming" else src
	var max_uses := int(pas.get("max_uses_per_turn", 0))
	if max_uses > 0:
		var uses_key := display_name + "_" + hook
		var uses := int(owner.attribute_uses_left.get(uses_key, 0))
		if uses <= 0:
			return amount
		owner.attribute_uses_left[uses_key] = uses - 1
	# 执行效果
	var effect_type := String(effect.get("type", ""))
	match effect_type:
		"damage_bonus":
			var bonus := _resolve_effect_value(effect, src, target)
			if bonus != 0:
				amount += bonus
				_log("%s 生效：伤害 %+d。" % [display_name, bonus])
		"heal":
			var heal_val := _resolve_effect_value(effect, src, target)
			if heal_val > 0:
				var old_hp = owner.hp
				owner.hp = mini(owner.max_hp, owner.hp + heal_val)
				_log("%s 生效：%s 回复 %d 点生命（%d → %d）。" % [display_name, owner.name, owner.hp - old_hp, old_hp, owner.hp])
	return amount

# 检查被动条件是否满足
func _check_passive_conditions(cond: Dictionary, src: PlayerData, target: PlayerData, card_id: String, damage_type: String) -> bool:
	if cond.is_empty():
		return true
	# 卡牌 ID 条件
	var req_card_id := String(cond.get("card_id", ""))
	if req_card_id != "" and card_id != req_card_id:
		return false
	# 伤害类型条件
	var req_dmg_type := String(cond.get("damage_type", ""))
	if req_dmg_type != "" and req_dmg_type != "all" and damage_type != req_dmg_type:
		return false
	# 首次攻击条件（撰文人）
	if bool(cond.get("first_attack_this_turn", false)):
		if src.attacks_used_this_turn != 1:
			return false
	# 生命流失不触发（规则 5.1）
	if damage_type == "hp_loss" and not bool(cond.get("allow_hp_loss", false)):
		return false
	return true

# 解析效果数值
func _resolve_effect_value(effect: Dictionary, src: PlayerData, target: PlayerData) -> int:
	var val = effect.get("value", 0)
	if val is String:
		match val:
			"per_attack_used_this_turn":
				var max_stack = int(effect.get("max", 0))
				var stack = src.attacks_used_this_turn - 1
				if max_stack > 0:
					stack = min(stack, max_stack)
				return stack
			"per_status_on_target":
				return target.status_ids().size()
			_:
				return int(val)
	return int(val)

func _kick_damage() -> void:
	if damage_queue.is_empty():
		return
	if mode == Mode.RESPONSE:
		return
	damage_return_to = "play"
	_process_damage_queue()

func _process_damage_queue() -> void:
	while not damage_queue.is_empty():
		var d: Dictionary = damage_queue[0]
		var dtype := String(d["damage_type"])
		# 规则 5.1：物理与法术伤害可被【防御】响应；灵魂伤害与失去生命不能被响应
		if dtype == "physical" or dtype == "magical":
			pending = {
				"kind": "damage",
				"source": int(d["source"]),
				"defender": int(d["defender"]),
				"amount": int(d["amount"]),
				"blocked": 0,
				"damage_type": dtype,
				"source_name": String(d["source_name"]),
			}
			mode = Mode.RESPONSE
			_log("等待 %s 响应……" % players[int(d["defender"])].name)
			return
		# 灵魂伤害 / 失去生命：直接结算
		damage_queue.remove_at(0)
		_settle_damage(d, 0)
	_after_damage_queue()

func _after_damage_queue() -> void:
	# 规则 5.3：有「濒死」角色时先开救援窗口（可按座位顺序用食物救），结算完毕仍未脱离才宣布死亡
	for i in players.size():
		if players[i].dying and not players[i].dead:
			_open_dying_window(i)
			return
	_check_deaths()
	if mode == Mode.GAME_OVER:
		return
	if damage_return_to == "judge":
		_after_judge()
	else:
		mode = Mode.PLAY

# 濒死救援窗口：从濒死者开始按座位顺序，各玩家可打出食物（视为濒死角色使用，规则 3.3）
func _open_dying_window(dying_idx: int) -> void:
	var rescuers: Array[int] = []
	for k in players.size():
		var i := (dying_idx + k) % players.size()
		if not players[i].dead:
			rescuers.append(i)
	pending = {"kind": "dying_save", "dying_player": dying_idx, "rescuers": rescuers}
	mode = Mode.RESPONSE
	_log("%s 处于「濒死」！按座位顺序询问救援：可打出食物牌（视为濒死角色使用）。" % players[dying_idx].name)

# 救援结束仍濒死：宣布死亡（规则 5.3）
func _finalize_dying(idx: int) -> void:
	var p := players[idx]
	if not p.dying or p.dead:
		_check_deaths()
		if mode == Mode.GAME_OVER:
			return
		if damage_return_to == "judge":
			_after_judge()
		else:
			mode = Mode.PLAY
		return
	# 限定技〖放逐〗：宣布死亡时询问一次（可选择不发动）
	if _has_skill(p, "skill_exile") and not bool(p.limited_used.get("skill_exile", false)) and not _exile_done.has(idx):
		var has_other := false
		for i in players.size():
			if i != idx and not players[i].dead:
				has_other = true
		if has_other:
			pending = {"kind": "exile_ask", "dying": idx, "options": ["yes", "no"]}
			mode = Mode.SKILL_PICK
			_log("%s 可以发动限定技〖放逐〗：清空一名其他玩家的所有区域。" % p.name)
			return
	p.dead = true
	# 规则 5.3：死亡后，该角色区域内所有牌进入弃牌堆
	var all_cards: Array[String] = []
	for cid in p.hand:
		all_cards.append(cid)
	for cid in p.reserve:
		all_cards.append(cid)
	for cid in p.equipment:
		all_cards.append(cid)
	for cid in p.traps:
		all_cards.append(cid)
	for cid in all_cards:
		_to_discard(cid)
	p.hand.clear()
	p.reserve.clear()
	p.equipment.clear()
	p.traps.clear()
	_log("%s 宣布死亡！其区域内所有牌进入弃牌堆。" % p.name)
	_check_deaths()
	if mode == Mode.GAME_OVER:
		return
	if damage_return_to == "judge":
		_after_judge()
	else:
		mode = Mode.PLAY

# 结算单次伤害实例
func _settle_damage(d: Dictionary, blocked: int) -> void:
	var defender := players[int(d["defender"])]
	var dtype := String(d["damage_type"])
	var dmg: int = maxi(0, int(d["amount"]) - blocked)
	var type_name := String(DAMAGE_TYPE_NAMES.get(dtype, dtype))
	if dmg > 0:
		defender.hp -= dmg
		if dtype == "hp_loss":
			# 失去生命无视所有伤害格挡、抵消、减免效果（规则 5.1）
			_log("%s 失去 %d 点生命（%s），剩余生命 %d。" % [defender.name, dmg, String(d["source_name"]), maxi(0, defender.hp)])
		else:
			_log("%s 受到 %d 点%s伤害（%s），剩余生命 %d。" % [defender.name, dmg, type_name, String(d["source_name"]), maxi(0, defender.hp)])
		# 〖结痂〗：回合外受伤记录 ceil(40%) 为「痂」
		if _has_skill(defender, "skill_scab") and int(d["defender"]) != current:
			var rec := _ceil_pct(dmg, 40)
			if rec > 0:
				defender.scab += rec
				_log("%s 触发〖结痂〗，记录 %d 点「痂」（累计 %d）。" % [defender.name, rec, defender.scab])
		# 「易伤1」：受到一次伤害时失去1点生命并减少一层
		if defender.has_status("vulnerable_1"):
			defender.consume_layer("vulnerable_1")
			_log("%s 因「易伤1」失去 1 点生命（剩余 %d 层）。" % [defender.name, defender.status_layer("vulnerable_1")])
			_lose_hp_direct(defender, 1, "「易伤1」")
		# 〖三色无缘〗：受伤获得「猩红」、来源获得「皎白」；造成伤害者获得「玄暗」
		var src_p := players[int(d["source"])]
		var self_hit := int(d["source"]) == int(d["defender"])
		if not self_hit:
			if _has_skill(defender, "skill_trichroma"):
				var c1 := _add_status_capped(defender, "crimson", 1, -1)
				var c2 := _add_status_capped(src_p, "pale", 1, -1)
				if c1 > 0 or c2 > 0:
					_log("%s 获得「猩红」（%d 层），%s 获得「皎白」（%d 层）。" % [defender.name, defender.status_layer("crimson"), src_p.name, src_p.status_layer("pale")])
			if _has_skill(src_p, "skill_trichroma"):
				var c3 := _add_status_capped(src_p, "dark", 1, -1)
				if c3 > 0:
					_log("%s 获得「玄暗」（%d 层）。" % [src_p.name, src_p.status_layer("dark")])
		# 〖守御〗：受到特殊攻击伤害时进行一次摸牌判定，非基础牌则反击2点物理，单张牌只触发一次
		if _has_skill(defender, "skill_guardian") and String(d.get("card_type", "")) == "special_attack" and not self_hit:
			var inst := int(d.get("instance", -1))
			if inst >= 0 and defender.guardian_seen_seq != inst:
				defender.guardian_seen_seq = inst
				var judge_id := _judge_draw_card()
				if not judge_id.is_empty():
					var jcard := db.get_card(judge_id)
					_to_discard(judge_id)
					_log("%s 触发〖守御〗摸牌判定：%s。" % [defender.name, String(jcard.get("name", judge_id))])
					if String(jcard.get("type", "")) != "basic":
						_log("判定牌不为基础牌，%s 对 %s 造成 2 点物理伤害。" % [defender.name, src_p.name])
						_deal_damage(int(d["defender"]), int(d["source"]), 2, "physical", "〖守御〗", "")
	else:
		_log("%s 完全格挡了本次%s伤害。" % [defender.name, type_name])
	# 规则 5.3：生命值归零时进入「濒死」
	if defender.hp <= 0 and not defender.dying:
		defender.hp = 0
		defender.dying = true
		_log("%s 生命归零，进入「濒死」！" % defender.name)

# 响应窗口内使用手牌：防御牌格挡 / 【跳过】抵消 / 濒死救援出食物
func _play_response_card(card_index: int) -> void:
	if pending.is_empty():
		return
	var kind := String(pending.get("kind", ""))
	if kind == "damage" or kind == "skip_response":
		var defender := players[int(pending["defender"])]
		if card_index < 0 or card_index >= defender.hand.size():
			return
		var card_id := defender.hand[card_index]
		var card := db.get_card(card_id)
		if kind == "damage":
			# 规则 5.2：一张防御牌无论点数多少，只能格挡一次伤害实例
			if not bool(card.get("is_defense", false)):
				_log("响应窗口内只能打出【防御】类牌。")
				return
			var value := int(card.get("defense_value", 0))
			_play_card_from_hand(defender, card_index)
			_to_discard(card_id)
			pending["blocked"] = int(pending["blocked"]) + value
			_log("%s 打出%s，格挡 %d 点（已格挡 %d / %d）。" % [defender.name, String(card["name"]), value, int(pending["blocked"]), int(pending["amount"])])
		else:
			# 规则 3.3：场上其他玩家可打出另一张【跳过】来抵消「跳过」
			if card_id != "skip":
				_log("只能打出【跳过】来抵消「跳过」。")
				return
			_play_card_from_hand(defender, card_index)
			_to_discard(card_id)
			_log("%s 打出【跳过】，抵消了「跳过」效果。" % defender.name)
			pending = {}
			mode = Mode.PLAY
	elif kind == "dying_save":
		# 濒死救援：当前被询问的玩家打出食物牌，视为濒死角色使用（规则 3.3）
		var rescuers: Array = pending.get("rescuers", [])
		if rescuers.is_empty():
			return
		var rescuer_idx := int(rescuers[0])
		var rescuer := players[rescuer_idx]
		if card_index < 0 or card_index >= rescuer.hand.size():
			return
		var fcid := rescuer.hand[card_index]
		var fcard := db.get_card(fcid)
		if String(fcard.get("type", "")) != "food":
			_log("濒死救援中只能打出食物牌。")
			return
		var dying_idx := int(pending["dying_player"])
		_play_card_from_hand(rescuer, card_index)
		_to_discard(fcid)
		_log("%s 对 %s 使用%s（视为濒死角色使用）。" % [rescuer.name, players[dying_idx].name, String(fcard.get("name", fcid))])
		_run_actions(rescuer_idx, fcard.get("effects", []), dying_idx, {"card_id": fcid, "source_name": String(fcard.get("name", fcid))})
		# 救活则关闭窗口回归流程；未救活可继续出食物或放弃
		if not players[dying_idx].dying:
			pending = {}
			_after_damage_queue()

# 响应时使用预备区中的防御牌：不需要执行「打出」动作（规则 5.2）
func ui_play_reserve(reserve_index: int) -> void:
	if mode != Mode.RESPONSE or String(pending.get("kind", "")) != "damage":
		return
	var defender := players[int(pending["defender"])]
	if reserve_index < 0 or reserve_index >= defender.reserve.size():
		return
	var card_id := defender.reserve[reserve_index]
	var card := db.get_card(card_id)
	if not bool(card.get("is_defense", false)):
		_log("预备区中只有【防御】类牌可在响应时使用。")
		return
	var value := int(card.get("defense_value", 0))
	defender.reserve.remove_at(reserve_index)
	_to_discard(card_id)
	pending["blocked"] = int(pending["blocked"]) + value
	_log("%s 使用预备区的%s，格挡 %d 点（已格挡 %d / %d）。" % [defender.name, String(card["name"]), value, int(pending["blocked"]), int(pending["amount"])])

# 结束响应，结算本次伤害 / 附加「跳过」
func ui_end_response() -> void:
	if mode != Mode.RESPONSE:
		return
	var kind := String(pending.get("kind", ""))
	if kind == "damage":
		if damage_queue.is_empty():
			pending = {}
			mode = Mode.PLAY
			return
		var d: Dictionary = damage_queue[0]
		damage_queue.remove_at(0)
		var blocked := int(pending["blocked"])
		pending = {}
		_settle_damage(d, blocked)
		_process_damage_queue()
	elif kind == "skip_response":
		var t := players[int(pending["defender"])]
		t.add_status("skip")
		_log("%s 获得「跳过」。" % t.name)
		pending = {}
		mode = Mode.PLAY
	elif kind == "dying_save":
		# 当前被询问的玩家放弃救援 → 询问下一位；无人再救则宣布死亡（规则 5.3）
		var rescuers: Array = pending.get("rescuers", [])
		var dying_idx := int(pending["dying_player"])
		if not rescuers.is_empty():
			_log("%s 放弃救援。" % players[int(rescuers[0])].name)
			rescuers.remove_at(0)
		if rescuers.is_empty():
			pending = {}
			_finalize_dying(dying_idx)
		else:
			pending["rescuers"] = rescuers

# ---------------- 判定阶段与延时判定牌（规则 4.2-1 / 4.3） ----------------

func _run_judge_phase(p: PlayerData) -> void:
	# 结算预备区中所有延时判定牌
	var judges: Array[String] = []
	for cid in p.reserve:
		if String(db.get_card(cid).get("type", "")) == "delayed_judge":
			judges.append(cid)
	if judges.is_empty():
		return
	_log("—— %s 的判定阶段 ——" % p.name)
	for cid in judges:
		p.reserve.erase(cid)
		_to_discard(cid)
		var card := db.get_card(cid)
		_log("结算延时判定牌%s。" % String(card.get("name", cid)))
		var owner_idx := players.find(p)
		_run_judge(card.get("judge", {}), owner_idx, owner_idx, String(card.get("name", cid)))
		if mode == Mode.GAME_OVER:
			return

# 三种判定方式：摸牌判定 / 排中判定 / 骰子判定（规则 4.3）
func _run_judge(j: Dictionary, src_idx: int, target_idx: int, source_name: String) -> void:
	var method := String(j.get("method", "coin"))
	var success := false
	match method:
		"draw":
			# 摸牌判定：翻抽牌堆顶一张，按牌面属性判定
			var jid := _judge_draw_card()
			if jid == "":
				_log("摸牌判定失败：抽牌堆为空。")
			else:
				var jc := db.get_card(jid)
				var cond := String(j.get("condition", ""))
				success = _judge_card_match(jc, cond)
				_log("摸牌判定：翻开%s（条件：%s）→ %s。" % [String(jc.get("name", jid)), _judge_condition_name(cond), "成功" if success else "失败"])
				_to_discard(jid)
		"coin":
			# 排中判定：50% 概率结果 A 或结果 B
			success = randi() % 2 == 0
			_log("排中判定：%s。" % ("正面（成功）" if success else "反面（失败）"))
		"dice":
			# 骰子判定：掷骰子，按点数执行对应结果
			var roll := 1 + randi() % 6
			var need: Array = j.get("success_values", [])
			success = need.has(roll)
			_log("骰子判定：掷出 %d 点（成功点：%s）→ %s。" % [roll, str(need), "成功" if success else "失败"])
	var actions: Array = j.get("success_actions", []) if success else j.get("fail_actions", [])
	for action in actions:
		_execute_action(src_idx, action, target_idx, {"source_name": source_name})

func _judge_draw_card() -> String:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			return ""
		draw_pile = discard_pile
		discard_pile = []
		draw_pile.shuffle()
		_log("抽牌堆耗尽：弃牌堆洗牌后成为新的抽牌堆。")
	var top: String = draw_pile.pop_back()
	return top

func _judge_card_match(card: Dictionary, cond: String) -> bool:
	match cond:
		"is_basic":
			return String(card.get("type", "")) == "basic"
		"is_attack":
			return card.get("tags", []).has("attack")
		"is_defense":
			return bool(card.get("is_defense", false))
	return false

func _judge_condition_name(cond: String) -> String:
	match cond:
		"is_basic":
			return "基础牌"
		"is_attack":
			return "攻击牌"
		"is_defense":
			return "防御牌"
	return cond

func _target_type_name(t: String) -> String:
	match t:
		"all_players":
			return "所有玩家"
		"all_enemies":
			return "所有敌人"
		"all_allies":
			return "所有队友"
		"all_others":
			return "除自己外的所有人"
	return t

# ---------------- 陷阱系统（规则 3.3） ----------------

# 行为事件钩子：对手布置的陷阱在满足条件时触发
func _emit_behavior(event: String, actor_idx: int, ctx: Dictionary) -> void:
	for i in players.size():
		if i == actor_idx:
			continue
		var p := players[i]
		if p.dead:
			continue
		var triggered: Array[String] = []
		for tid in p.traps:
			var tc := db.get_card(tid)
			var tr: Dictionary = tc.get("trap_trigger", {})
			if String(tr.get("event", "")) != event:
				continue
			# 条件：如触发牌需带某标签（如攻击牌）
			var need_tag := String(tr.get("card_tag", ""))
			if need_tag != "":
				var cid := String(ctx.get("card_id", ""))
				if not db.get_card(cid).get("tags", []).has(need_tag):
					continue
			triggered.append(tid)
		for tid in triggered:
			p.traps.erase(tid)
			_to_discard(tid)
			var tc := db.get_card(tid)
			_log("%s 的陷阱%s触发！" % [p.name, String(tc.get("name", tid))])
			_run_actions(i, tc.get("effects", []), actor_idx, {"source_name": String(tc.get("name", tid))})

# ---------------- 技能系统（规则 2.3） ----------------

# 使用主动技：不视为「出牌」，有每回合次数限制
func _zone_card_options(p: PlayerData) -> Array[String]:
	## 己方所有区域的可选牌，token 形式：区域:下标
	var opts: Array[String] = []
	for i in p.hand.size():
		opts.append("hand:%d" % i)
	for i in p.equipment.size():
		opts.append("equip:%d" % i)
	for i in p.reserve.size():
		opts.append("reserve:%d" % i)
	for i in p.traps.size():
		opts.append("trap:%d" % i)
	return opts

func _take_zone_card(p: PlayerData, token: String, remove: bool = true) -> String:
	## 从 token 指定的区域取出一张牌并返回其 id，找不到返回空串
	## remove = false 时只读取不移除（供选目标取消后无副作用地回滚）
	var parts := token.split(":")
	if parts.size() != 2:
		return ""
	var zone := parts[0]
	var i := int(parts[1])
	var arr: Array[String]
	match zone:
		"hand":
			arr = p.hand
		"equip":
			arr = p.equipment
		"reserve":
			arr = p.reserve
		"trap":
			arr = p.traps
		_:
			return ""
	if i < 0 or i >= arr.size():
		return ""
	var cid := arr[i]
	if remove:
		arr.remove_at(i)
	return cid

func ui_use_skill(skill_id: String) -> void:
	if mode != Mode.PLAY:
		return
	var p := players[current]
	if not p.skill_ids.has(skill_id):
		return
	if int(p.skill_uses_left.get(skill_id, 0)) <= 0:
		_log("本回合该技能次数已用完。")
		return
	var skill := db.get_skill(skill_id)
	# 〖分形几何〗：将一张【普通攻击】视作【防御2】布置到预备区
	if skill_id == "skill_fractal":
		var fopts: Array[String] = []
		for i in p.hand.size():
			if p.hand[i] == "basic_attack":
				fopts.append("hand:%d" % i)
		if fopts.is_empty():
			_log("手牌中没有【普通攻击】，〖分形几何〗发动失败。")
			return
		pending = {"kind": "fractal", "skill_id": skill_id, "options": fopts}
		mode = Mode.SKILL_PICK
		_log("请选择一张【普通攻击】转化为【防御2】。")
		return
	# 〖贤者之书〗：选择区域内一张牌丢弃，再选择目标
	if skill_id == "skill_sage_book":
		var sopts := _zone_card_options(p)
		if sopts.is_empty():
			_log("你的区域内没有可丢弃的牌，〖贤者之书〗发动失败。")
			return
		if _target_candidates("single_enemy", "").is_empty():
			_log("没有其他合法玩家，〖贤者之书〗发动失败。")
			return
		pending = {"kind": "sage", "skill_id": skill_id, "options": sopts}
		mode = Mode.SKILL_PICK
		_log("〖贤者之书〗：请选择要丢弃的牌。")
		return
	# 〖相生相灭〗：需自身有「玄暗」且场上有其他带「皎白」的玩家
	if skill_id == "skill_mutual":
		if p.status_layer("dark") <= 0:
			_log("你没有「玄暗」，〖相生相灭〗发动失败。")
			return
		var has_pale := false
		for i in players.size():
			if i != current and not players[i].dead and players[i].status_layer("pale") > 0:
				has_pale = true
		if not has_pale:
			_log("场上没有携带「皎白」的其他玩家，〖相生相灭〗发动失败。")
			return
		pending = {"kind": "mutual", "source": current, "skill_id": skill_id, "target_type": "single_enemy"}
		mode = Mode.SELECT_TARGET
		_log("〖相生相灭〗：请选择一名携带「皎白」的玩家。")
		return
	# 〖信仰之跃〗：选择摸牌数量（1~3）
	if skill_id == "skill_leap_faith":
		pending = {"kind": "leap", "skill_id": skill_id, "options": ["1", "2", "3"]}
		mode = Mode.SKILL_PICK
		_log("〖信仰之跃〗：请选择要摸取的数量（摸 X 张，失去 2X 点生命）。")
		return
	# 〖失足之幸〗：生命值 ≥20 才能发动
	if skill_id == "skill_false_step" and p.hp < 20:
		_log("生命值不足 20，〖失足之幸〗发动失败。")
		return
	# 〖坚壁〗类：需从弃牌堆检索防御牌
	for fx in skill.get("effects", []):
		for action in fx.get("actions", []):
			if String(action.get("type", "")) == "retrieve_defense":
				var options: Array[String] = []
				var seen := {}
				for cid in discard_pile:
					if String(cid) in action.get("defense_ids", []) and not seen.has(cid):
						seen[cid] = true
						options.append(String(cid))
				if options.is_empty():
					# 弃牌堆没有目标牌则发动失败，不消耗次数
					_log("弃牌堆中没有【防御1】或【防御2】，%s 发动失败。" % String(skill["name"]))
					return
				pending = {"kind": "skill_retrieve", "skill_id": skill_id, "options": options}
				mode = Mode.SKILL_PICK
				_log("请选择一张防御牌加入手牌。")
				return
	# 需要选目标的主动技
	var tt := String(skill.get("target_type", "none"))
	if tt == "single_any" or tt == "single_enemy":
		var candidates := _target_candidates(tt, "")
		if candidates.is_empty():
			_log("没有合法目标，%s 发动失败。" % String(skill["name"]))
			return
		pending = {"kind": "skill", "source": current, "skill_id": skill_id, "target_type": tt}
		mode = Mode.SELECT_TARGET
		_log("请选择%s的目标。" % String(skill["name"]))
		return
	# 其他主动技：直接结算
	p.skill_uses_left[skill_id] = int(p.skill_uses_left[skill_id]) - 1
	_log("%s 发动了%s。" % [p.name, String(skill["name"])])
	_run_actions(current, skill.get("effects", []), current, {"source_name": String(skill["name"])})
	_kick_damage()

func ui_skill_pick(token: String) -> void:
	if mode != Mode.SKILL_PICK:
		return
	var kind := String(pending.get("kind", ""))
	var p := players[current]
	var skill_id := String(pending.get("skill_id", ""))
	if kind == "skill_retrieve":
		var idx := discard_pile.find(token)
		if idx == -1:
			return
		discard_pile.remove_at(idx)
		p.hand.append(token)
		p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
		var skill := db.get_skill(skill_id)
		_log("%s 发动%s，将%s加入手牌。" % [p.name, String(skill.get("name", skill_id)), String(db.get_card(token).get("name", token))])
		pending = {}
		mode = Mode.PLAY
		return
	if kind == "fractal":
		var cid := _take_zone_card(p, token)
		if cid != "basic_attack":
			if not cid.is_empty():
				p.hand.append(cid)
			return
		p.reserve.append("defend2")
		p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
		_log("%s 发动〖分形几何〗：一张【普通攻击】转化为【防御2】布置到预备区。" % p.name)
		pending = {}
		mode = Mode.PLAY
		return
	if kind == "sage":
		# 只记录要丢弃的牌，真正移除/进弃牌堆推迟到选定目标后，取消时无副作用
		var cid := _take_zone_card(p, token, false)
		if cid.is_empty():
			return
		var status_map := ["vulnerable_1", "worsen_1", "cold_1"]
		var form := clampi(p.sage_mode, 0, 2)
		pending = {
			"kind": "sage_target",
			"source": current,
			"skill_id": skill_id,
			"target_type": "single_enemy",
			"sage_form": form,
			"sage_status": status_map[form],
			"sage_token": token,
			"sage_card": cid,
		}
		mode = Mode.SELECT_TARGET
		_log("请选择〖贤者之书〗（形态 %s）的目标。" % ["①", "②", "③"][form])
		return
	if kind == "leap":
		var x := int(token)
		if x < 1 or x > 3:
			return
		p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
		_log("%s 发动〖信仰之跃〗：摸 %d 张牌，然后失去 %d 点生命。" % [p.name, x, x * 2])
		pending = {}
		mode = Mode.PLAY
		_draw_cards(p, x)
		_lose_hp_direct(p, x * 2, "〖信仰之跃〗")
		if mode != Mode.DISCARD_PICK:
			mode = Mode.PLAY
		if p.dying and not p.dead:
			_open_dying_window(current)
		return
	if kind == "exile_ask":
		var dying_idx := int(pending.get("dying", current))
		var dp := players[dying_idx]
		pending = {}
		if token == "no":
			_exile_done[dying_idx] = true
			_log("%s 放弃发动〖放逐〗。" % dp.name)
			_finalize_dying(dying_idx)
			return
		dp.limited_used["skill_exile"] = true
		_exile_done[dying_idx] = true
		pending = {"kind": "exile_target", "source": dying_idx, "target_type": "single_enemy"}
		mode = Mode.SELECT_TARGET
		_log("请选择〖放逐〗要清空的目标。")
		return

func ui_cancel_skill_pick() -> void:
	if mode != Mode.SKILL_PICK:
		return
	var kind := String(pending.get("kind", ""))
	if kind == "exile_ask":
		# 放弃放逐，继续死亡结算
		var dying_idx := int(pending.get("dying", current))
		pending = {}
		_exile_done[dying_idx] = true
		_log("%s 放弃发动〖放逐〗。" % players[dying_idx].name)
		_finalize_dying(dying_idx)
		return
	pending = {}
	mode = Mode.PLAY
	_log("取消了技能发动。")

# ---------------- 弃牌选择（洞悉/让别人选弃） ----------------

func ui_discard_picked(card_id: String) -> void:
	if mode != Mode.DISCARD_PICK:
		return
	var target_idx := int(pending.get("target", current))
	var p := players[target_idx]
	var idx := p.hand.find(card_id)
	if idx == -1:
		return
	p.hand.remove_at(idx)
	_to_discard(card_id)
	_log("%s 弃置了 %s。" % [p.name, String(db.get_card(card_id)["name"])])
	var remaining := int(pending.get("count", 1)) - 1
	if remaining > 0 and not p.hand.is_empty():
		pending["count"] = remaining
		_log("还需选择 %d 张手牌弃置。" % remaining)
	else:
		var was_setup := bool(pending.get("setup", false))
		var was_turn_draw := (not was_setup) and phase == Phase.DRAW and target_idx == current and not p.dead
		pending = {}
		mode = Mode.PLAY
		if was_setup:
			_process_setup_draw()
		elif was_turn_draw:
			# 己方回合摸牌阶段触发的洞悉弃牌：弃完后继续进入出牌阶段，而不是切给下一位玩家
			_enter_play_phase(p)

func ui_cancel_discard_pick() -> void:
	if mode != Mode.DISCARD_PICK:
		return
	# 自弃（洞悉）不可取消；让别人选弃可以取消
	if String(pending.get("picker", "")) == "self":
		return
	pending = {}
	mode = Mode.PLAY
	_log("取消了弃牌选择。")

# ---------------- 特殊事件（规则 3.3） ----------------

func _trigger_event(src_idx: int) -> void:
	# 特殊事件牌堆独立，抽完后重新洗牌
	if event_deck.is_empty():
		for e in db.event_deck_list:
			event_deck.append(e)
		event_deck.shuffle()
		_log("特殊事件牌堆已重新洗牌。")
	var event_id: String = event_deck.pop_back()
	var event := db.get_event(event_id)
	_log("%s 触发特殊事件：%s —— %s" % [players[src_idx].name, String(event.get("name", "")), String(event.get("description", ""))])
	# 先显示事件说明窗口，确认后再执行
	pending = {"kind": "event_show", "event_id": event_id, "source": src_idx}
	mode = Mode.EVENT_SHOW

func ui_confirm_event_show() -> void:
	if mode != Mode.EVENT_SHOW:
		return
	var event_id := String(pending.get("event_id", ""))
	var src := int(pending.get("source", 0))
	var event := db.get_event(event_id)
	pending = {}
	mode = Mode.PLAY
	# 事件带判定时直接判定（如骰子判定事件）
	if event.has("judge"):
		var tt := String(event.get("target_type", "none"))
		var t := src
		if tt == "single_any" or tt == "single_enemy":
			var candidates := _target_candidates(tt, "")
			if candidates.is_empty():
				_log("没有合法目标，事件无效。")
				return
			pending = {"kind": "event", "source": src, "event_id": event_id, "target_type": tt}
			mode = Mode.SELECT_TARGET
			_log("请选择事件目标。")
			return
		_run_judge(event.get("judge", {}), src, t, String(event.get("name", "")))
		_kick_damage()
		return
	var tt := String(event.get("target_type", "none"))
	if tt == "single_any" or tt == "single_enemy":
		var candidates := _target_candidates(tt, "")
		if candidates.is_empty():
			_log("没有合法目标，事件无效。")
			return
		pending = {"kind": "event", "source": src, "event_id": event_id, "target_type": tt}
		mode = Mode.SELECT_TARGET
		_log("请选择事件目标。")
		return
	var ctx := {"source_name": String(event.get("name", ""))}
	if tt in ["all_players", "all_enemies", "all_allies", "all_others"]:
		# 多目标事件：对全部合法目标依次结算
		var candidates := _target_candidates(tt, "")
		if candidates.is_empty():
			_log("没有合法目标，事件无效。")
			return
		_log("事件目标：%s。" % _target_type_name(tt))
		for t_idx in candidates:
			_run_actions(src, event.get("effects", []), t_idx, ctx)
	else:
		_run_actions(src, event.get("effects", []), src, ctx)
	# 事件抽到即结算，不能留在伤害队列等待下一次出牌
	_kick_damage()

# ---------------- 弃牌阶段 ----------------

func _discard_one(card_index: int) -> void:
	var p := players[current]
	if card_index < 0 or card_index >= p.hand.size():
		return
	var card_id := p.hand[card_index]
	_remove_hand_card(p, card_index)
	_to_discard(card_id)
	_log("%s 弃置了%s。" % [p.name, String(db.get_card(card_id)["name"])])
	if p.hand.size() <= p.hand_limit:
		_end_turn()

# ---------------- 濒死、死亡与胜负（规则 5.3 / 6.2） ----------------

func _check_deaths() -> void:
	# 死亡宣布在 _finalize_dying 完成；此处仅判定胜负（规则 6.2：所有敌人死亡）
	var alive: Array[int] = []
	for i in players.size():
		if not players[i].dead:
			alive.append(i)
	if alive.size() == 1:
		winner = players[alive[0]].name
		mode = Mode.GAME_OVER
		_log("游戏结束！%s 获胜！" % winner)

# ---------------- UI 辅助 ----------------

func interstitial_text() -> String:
	var p := players[current]
	if first_turn:
		return "游戏开始，%s 先手！\n\n请 %s 开始操作。" % [p.name, p.name]
	return "回合交接\n\n现在由 %s 操作。" % p.name

# 弃牌堆公开信息：上一回合进入弃牌堆的牌名（规则 6.1）
func last_turn_discard_names() -> Array[String]:
	var out: Array[String] = []
	for cid in last_turn_discards:
		out.append(String(db.get_card(cid).get("name", cid)))
	return out
