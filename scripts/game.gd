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

# pending 上下文的 kind 取值（集中定义，避免字符串散落；写入时由 _set_pending 校验）
const PENDING_CARD := "card"
const PENDING_EVENT := "event"
const PENDING_EVENT_SHOW := "event_show"
const PENDING_SKILL := "skill"
const PENDING_SKIP_RESPONSE := "skip_response"
const PENDING_DAMAGE := "damage"
const PENDING_DYING_SAVE := "dying_save"
const PENDING_DISCARD_PICK := "discard_pick"
const PENDING_SKILL_RETRIEVE := "skill_retrieve"
const PENDING_FRACTAL := "fractal"
const PENDING_SAGE := "sage"
const PENDING_SAGE_TARGET := "sage_target"
const PENDING_MUTUAL := "mutual"
const PENDING_LEAP := "leap"
const PENDING_EXILE_ASK := "exile_ask"
const PENDING_EXILE_TARGET := "exile_target"
const PENDING_MERCY := "mercy"
const PENDING_OSC_FORM := "osc_form"
const PENDING_OSC_TARGET := "osc_target"
const PENDING_PEEP_HAND := "peep_hand"
const PENDING_PEEP_TARGET := "peep_target"
const PENDING_SAND_BURY_HAND := "sand_bury_hand"
const PENDING_SAND_BURY_TARGET := "sand_bury_target"
const PENDING_SAND_BURY_DISCARD := "sand_bury_discard"
const PENDING_PLUNDER := "plunder"
const PENDING_MACHINE := "machine_choice"
const PENDING_PRISM := "prism_card"
const PENDING_PRISM_TARGET := "prism_target"
const PENDING_CONVERGE_TARGET := "converge_target"
const PENDING_PRAYER_MODE := "prayer_mode"
const PENDING_PRAYER_TARGET := "prayer_target"
const PENDING_PRAYER_DISCARD := "prayer_discard"
const PENDING_COFFIN_TARGET := "coffin_target"
const PENDING_RIPPER_ASK := "ripper_ask"
const PENDING_MILLENNIUM_ASK := "millennium_ask"
const PENDING_MILLENNIUM_TARGET := "millennium_target"

const PENDING_KINDS := [
	PENDING_CARD, PENDING_EVENT, PENDING_EVENT_SHOW, PENDING_SKILL,
	PENDING_SKIP_RESPONSE, PENDING_DAMAGE, PENDING_DYING_SAVE, PENDING_DISCARD_PICK,
	PENDING_SKILL_RETRIEVE, PENDING_FRACTAL, PENDING_SAGE, PENDING_SAGE_TARGET,
	PENDING_MUTUAL, PENDING_LEAP, PENDING_EXILE_ASK, PENDING_EXILE_TARGET,
	PENDING_MERCY, PENDING_OSC_FORM, PENDING_OSC_TARGET,
	PENDING_PEEP_HAND, PENDING_PEEP_TARGET,
	PENDING_SAND_BURY_HAND, PENDING_SAND_BURY_TARGET, PENDING_SAND_BURY_DISCARD,
	PENDING_PLUNDER, PENDING_MACHINE, PENDING_PRISM, PENDING_PRISM_TARGET,
	PENDING_CONVERGE_TARGET, PENDING_PRAYER_MODE, PENDING_PRAYER_TARGET,
	PENDING_PRAYER_DISCARD, PENDING_COFFIN_TARGET, PENDING_RIPPER_ASK,
	PENDING_MILLENNIUM_ASK, PENDING_MILLENNIUM_TARGET,
	"judge_prompt",
]

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
var winner_team_id: String = ""       # 获胜队伍 id（单人队时同 winner）
var winner_team_name: String = ""     # 获胜队伍显示名（组队模式使用）
var winner_members: Array[String] = []  # 获胜队伍成员显示名
var board: Dictionary = {}             # 当前板子配置（人数 / 队伍 / 座位映射）
var pool_id: String = "classic"        # 本局牌池：classic 经典 / retrace 溯洄之境（角色池与牌堆过滤）
var _machine_pending: Array[int] = []  # 〖演算机器〗等待二选一询问的玩家下标队列
var _ripper_pending: Array[Dictionary] = []  # 〖开膛手〗等待掠夺询问的 {source, defender} 队列
var _skip_chain: int = 0               # 连续「跳过」计数，用于限制递归深度
var dev_forced_judge: String = ""     # 开发者菜单：强制下一次判定结果（""=不干预 / success / fail / roll:N）

var picked_char_ids: Array[String] = []  # 选人阶段已选角色 id（规则 4.1）
var _card_instance_seq: int = 0          # 卡牌实例序号（同一张牌多段伤害只算一次）
var _exile_done: Dictionary = {}         # 已处理过〖放逐〗询问的玩家下标
var _dying_window_open: bool = false      # 当前是否已有「濒死救援」窗口处于打开状态（防重复开窗）

func _init() -> void:
	db = CardDB.new()

func _log(text: String) -> void:
	message.emit(text)

func _set_pending(kind: String, data: Dictionary = {}) -> void:
	## 统一写入 pending 上下文，并校验 kind 已在 PENDING_KINDS 中声明
	if not PENDING_KINDS.has(kind):
		push_error("未声明的 pending kind：" + kind)
	pending = data.duplicate()
	pending["kind"] = kind

func _pending_kind() -> String:
	return String(pending.get("kind", ""))

func _to_discard(card_id: String) -> void:
	# 进入弃牌堆，并记录本回合弃牌（信息公开，规则 6.1）
	discard_pile.append(card_id)
	turn_discards.append(card_id)

func _resolve_card_after_play(card_id: String) -> void:
	## 出牌完成后的统一后置处理：根据卡牌类型决定进入弃牌堆还是直接移除
	var card := db.get_card(card_id)
	var ctype := String(card.get("type", ""))
	if ctype == "special":
		# 特殊牌打出后直接移除（不进入弃牌堆）
		_log("%s 作为特殊牌被直接移除。" % String(card.get("name", card_id)))
	else:
		_to_discard(card_id)

# ---------------- 板子与队伍（多人口径见 docs/多人对战交接文档.md） ----------------

func board_player_count() -> int:
	return int(board.get("player_count", 2))

func _team_for_seat(seat: int) -> String:
	for t in board.get("teams", []):
		for s in t.get("seats", []):
			if int(s) == seat:
				return String(t.get("id", ""))
	return ""

func _team_name(team_id: String) -> String:
	for t in board.get("teams", []):
		if String(t.get("id", "")) == team_id:
			return String(t.get("name", team_id))
	return ""

func is_same_team(a: int, b: int) -> bool:
	if a == b:
		return true
	if a < 0 or a >= players.size() or b < 0 or b >= players.size():
		return false
	var ta := players[a].team_id
	return not ta.is_empty() and ta == players[b].team_id

func _alive_teams() -> Array[String]:
	var out: Array[String] = []
	for i in players.size():
		if players[i].dead:
			continue
		var tid := players[i].team_id
		if tid.is_empty():
			tid = "solo_%d" % i
		if not out.has(tid):
			out.append(tid)
	return out

# ---------------- 游戏开始与选人（规则 4.1） ----------------

func start_game(board_id: String = "", new_pool_id: String = "classic") -> void:
	# 选人阶段：按板子人数依次选择角色，不可重复（规则 4.1）
	pool_id = new_pool_id
	board = db.get_board(board_id) if not board_id.is_empty() else db.default_board()
	if board.is_empty():
		board = {
			"id": "board_1v1", "name": "双人对决", "player_count": 2,
			"teams": [
				{"id": "team_a", "name": "队伍A", "seats": [0]},
				{"id": "team_b", "name": "队伍B", "seats": [1]},
			],
		}
	players.clear()
	picked_char_ids.clear()
	mode = Mode.SELECT_CHAR
	_dying_window_open = false
	_machine_pending.clear()
	_ripper_pending.clear()
	_log("—— 选人阶段：%s（%d 人）· 板子：%s ——" % [String(board.get("name", "对局")), board_player_count(), db.pool_name(pool_id)])
	_log("请 玩家1 选择角色。")

func ui_pick_character(char_id: String) -> void:
	if mode != Mode.SELECT_CHAR:
		return
	if picked_char_ids.has(char_id):
		return
	var c := db.get_character(char_id)
	if c.is_empty():
		return
	# 牌池过滤：只能选择本局板子对应角色池中的角色
	if not db.entry_in_pool(c, pool_id):
		_log("%s 不在当前板子的角色池中。" % String(c.get("name", char_id)))
		return
	picked_char_ids.append(char_id)
	var picked := picked_char_ids.size()
	var cname := String(c.get("name", char_id))
	if picked < board_player_count():
		_log("玩家%d 选择了 %s。请 玩家%d 选择角色。" % [picked, cname, picked + 1])
		return
	_log("玩家%d 选择了 %s。" % [picked, cname])
	_setup_players()

func _setup_players() -> void:
	# 1. 随机落座：所选角色打乱后依次填入座位（口径 2.5-5），队伍由座位映射决定
	var seat_chars := picked_char_ids.duplicate()
	seat_chars.shuffle()
	for i in seat_chars.size():
		var c := db.get_character(String(seat_chars[i]))
		var p := PlayerData.new()
		p.seat_index = i
		p.team_id = _team_for_seat(i)
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
	# 2. 组建抽牌堆并洗牌（按本局牌池过滤，如【掠夺】仅存在于溯洄之境）
	var deck := db.deck_composition_for_pool(pool_id)
	for id in deck.keys():
		for i in range(int(deck[id])):
			draw_pile.append(String(id))
	draw_pile.shuffle()
	# 特殊事件牌堆（独立牌堆，规则 3.3）
	for e in db.event_deck_list:
		event_deck.append(e)
	event_deck.shuffle()
	# 3. 抽取初始手牌：数量 = 摸牌数值（规则 3.1 / 口径 2.5-6）
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
	_draw_cards(p, p.draw_limit)
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
		_skip_chain += 1
		_advance_player()
		# 连续跳过最多一圈，避免多人连续跳过导致递归加深
		if _skip_chain >= players.size():
			_skip_chain = 0
		_prepare_turn()
		return
	_skip_chain = 0
	# 每回合重置主动技使用次数与被动计数
	p.skill_uses_left.clear()
	for sid in p.skill_ids:
		var sk := db.get_skill(sid)
		var stype := String(sk.get("skill_type", ""))
		if stype == "active" or stype == "switch":
			p.skill_uses_left[sid] = int(sk.get("max_uses_per_turn", 1))
	p.attacks_used_this_turn = 0
	p.caged_beast_used = false
	# 回合开始：先检查觉醒与喧闹（在状态触发之前）
	_check_noise_on_turn_start(p)
	_check_star_brilliance(p)
	# 触发回合开始状态效果（如「燃烧」）
	_trigger_turn_start_statuses(p)
	# 新回合：重置〖困兽〗与〖韵动〗的每回合计数，并刷新动态摸牌/存牌数值
	# 同时重置所有玩家的跨回合每回合计数（〖演算机器〗〖圣徒〗〖开膛手〗，回合外也可能触发）
	for pl in players:
		pl.caged_beast_used = false
		pl.machine_draw_used = false
		pl.machine_heal_used = false
		pl.saint_used = 0
		pl.funerary_this_turn = 0
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
	# 回合准备期间（如回合开始的「燃烧」）可能导致当前玩家死亡，需立刻结束其回合
	_end_turn_if_current_dead()

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
	## 直接失去生命（不经过防御/装备），只标记濒死；
	## 救援窗口统一由 _ensure_dying_window() 在流程收尾处开启，避免中途打断结算
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
	var cap := int(db.get_status(status_id).get("max_layers", 99))
	var cur := p.status_layer(status_id)
	var add := clampi(layers, 0, cap - cur)
	if add <= 0:
		return 0
	p.add_status(status_id, duration, add)
	return add

# ---------------- 开发者工具接口（仅调试构建的开发者菜单调用） ----------------

func dev_set_turn(idx: int, ph: int) -> void:
	## 强制设置当前回合玩家与阶段，并清空所有待结算上下文
	current = clampi(idx, 0, players.size() - 1)
	phase = clampi(ph, 0, Phase.DISCARD)
	pending = {}
	damage_queue.clear()
	mode = Mode.PLAY
	_log("【开发者】当前回合设为 %s，阶段设为 %s。" % [players[current].name, PHASE_NAMES[phase]])

func dev_draw(p: PlayerData, n: int) -> void:
	_draw_raw(p, n)
	_log("【开发者】%s 摸了 %d 张牌。" % [p.name, n])

func dev_grant_card(p: PlayerData, card_id: String, zone: String) -> void:
	match zone:
		"equipment":
			p.equipment.append(card_id)
		"reserve":
			p.reserve.append(card_id)
		"traps":
			p.traps.append(card_id)
		_:
			p.hand.append(card_id)
	_log("【开发者】将 %s 加入 %s 的%s。" % [String(db.get_card(card_id).get("name", card_id)), p.name, _dev_zone_name(zone)])

func dev_remove_card(p: PlayerData, zone: String, index: int) -> void:
	var arr := _dev_zone_array(p, zone)
	if index < 0 or index >= arr.size():
		return
	var card_id: String = arr[index]
	arr.remove_at(index)
	_log("【开发者】从 %s 的%s移除了 %s。" % [p.name, _dev_zone_name(zone), String(db.get_card(card_id).get("name", card_id))])

func dev_shuffle_draw() -> void:
	draw_pile.shuffle()
	_log("【开发者】抽牌堆已洗牌。")

func dev_push_draw(card_id: String) -> void:
	draw_pile.append(card_id)
	_log("【开发者】将 %s 置入抽牌堆顶。" % String(db.get_card(card_id).get("name", card_id)))

func dev_apply_stats(p: PlayerData, hp: int, max_hp: int, hand_limit: int, draw_limit: int, scab: int) -> void:
	p.max_hp = maxi(1, max_hp)
	p.hp = clampi(hp, 0, p.max_hp)
	p.hand_limit = maxi(0, hand_limit)
	p.draw_limit = maxi(1, draw_limit)
	p.scab = maxi(0, scab)
	_log("【开发者】写入 %s 数值：生命 %d/%d，存牌 %d，摸牌 %d，痂 %d。" % [p.name, p.hp, p.max_hp, p.hand_limit, p.draw_limit, p.scab])

func dev_kill(idx: int) -> void:
	var p := players[idx]
	p.hp = 0
	p.dying = false
	p.dead = true
	_log("【开发者】%s 被宣布死亡。" % p.name)
	_check_deaths()

func dev_win(idx: int) -> void:
	# 组队模式下按该玩家所属队伍宣布胜利
	var tid := players[idx].team_id
	winner_members.clear()
	for i in players.size():
		if not players[i].dead and is_same_team(i, idx):
			winner_members.append(players[i].name)
	winner_team_id = tid
	if winner_members.size() > 1:
		winner_team_name = _team_name(tid)
		winner = winner_team_name
	else:
		winner_team_name = ""
		winner = players[idx].name
		winner_members.clear()
		winner_members.append(players[idx].name)
	mode = Mode.GAME_OVER
	_log("【开发者】%s 被宣布胜利。" % winner)

func _dev_zone_array(p: PlayerData, zone: String) -> Array[String]:
	match zone:
		"equipment":
			return p.equipment
		"reserve":
			return p.reserve
		"traps":
			return p.traps
		_:
			return p.hand

func _dev_zone_name(zone: String) -> String:
	match zone:
		"equipment":
			return "装备栏"
		"reserve":
			return "预备区"
		"traps":
			return "陷阱区"
		_:
			return "手牌"

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
	# 〖时钟悖论〗的伤害减免持续至出牌阶段前，进入出牌阶段即失效
	if p.paradox_reduction:
		p.paradox_reduction = false
		p.damage_reduction = maxi(0, p.damage_reduction - 1)
		_log("%s 的〖时钟悖论〗伤害减免失效。" % p.name)
	_log("—— %s 的出牌阶段 ——" % p.name)
	# 先结算【窥视】等 play_start 触发的延时判定牌
	_run_play_start_judge(p)
	if mode != Mode.PLAY:
		return  # 可能被 prompt_choice 中断
	# 雷雨〖大气电压〗：出牌阶段开始时加一张【电击1】到手牌
	if _has_skill(p, "skill_voltage"):
		p.hand.append("special_electric_shock")
		_log("%s 触发〖大气电压〗：一张【电击1】加入手牌。" % p.name)
	# 古卢〖仁慈〗：出牌阶段开始时摸1张 + 二选一
	if _has_skill(p, "skill_mercy"):
		_draw_cards(p, 1)
		_log("%s 触发〖仁慈〗：摸了 1 张牌。请选择一项：" % p.name)
		_set_pending(PENDING_MERCY, {"options": ["lose_hp", "add_stop_sword"]})
		mode = Mode.SKILL_PICK
		return

func ui_end_play_phase() -> void:
	if mode != Mode.PLAY:
		return
	var p := players[current]
	# 出牌阶段结束钩子：结算所有 trigger=on_play_end 的状态效果
	_trigger_on_play_end_statuses(p)
	# 派克〖时钟悖论〗：出牌阶段内未使用过【普通攻击】→ 跳过弃牌阶段，获得 1 点伤害减免
	if _has_skill(p, "skill_clock_paradox") and p.attacks_used_this_turn == 0:
		p.damage_reduction += 1
		p.paradox_reduction = true
		_log("%s 触发〖时钟悖论〗：本回合未使用【普通攻击】，跳过弃牌阶段，获得 1 点伤害减免（持续至其下个出牌阶段前）。" % p.name)
		_end_turn()
		return
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
		var st: Dictionary = db.get_status(sid)
		if String(st.get("trigger", "")) == "on_turn_start":
			to_trigger.append(sid)
	# 先触发效果，再减持续
	for sid in to_trigger:
		var st: Dictionary = db.get_status(sid)
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
			var st: Dictionary = db.get_status(sid)
			var sname := String(st.get("name", sid))
			_log("%s 的%s已消失。" % [p.name, sname])

func _trigger_on_play_end_statuses(p: PlayerData) -> void:
	## 出牌阶段结束时触发所有 trigger=on_play_end 的状态（如「止戈」清空）
	var to_clear: Array[String] = []
	for sid in p.status_ids():
		var st: Dictionary = db.get_status(sid)
		if String(st.get("trigger", "")) == "on_play_end":
			to_clear.append(sid)
	for sid in to_clear:
		var sname := String(db.get_status(sid).get("name", sid))
		p.remove_status(sid)
		_log("%s 出牌阶段结束，清空自身所有%s。" % [p.name, sname])

func _end_turn() -> void:
	var p := players[current]
	# 清理本回合临时状态（如「奋击·攻击+1」的增益，持续时间为"本回合"）
	if p.has_status("attack_up_1"):
		p.remove_status("attack_up_1")
	# 〖千载幽咽〗的指定仅在本回合内有效
	if not p.millennium_marks.is_empty():
		p.millennium_marks.clear()
	# 回合结束状态结算（如「电棱」：可被伤害减免削减，不可被【防御】响应）
	_trigger_turn_end_statuses(p)
	# 回合结束结算可能导致濒死：先开救援窗口，救援/死亡处理完毕后再继续交替回合
	if p.dying and not p.dead:
		damage_return_to = "end_turn"
		if _ensure_dying_window():
			return
		damage_return_to = "play"
	_finish_end_turn()

func _finish_end_turn() -> void:
	## 回合结束收尾：濒死救援完毕（或无需救援）后交替到下一玩家
	damage_return_to = "play"
	pending = {}
	_advance_player()
	_prepare_turn()

func _trigger_turn_end_statuses(p: PlayerData) -> void:
	## 回合结束时触发所有 trigger=on_turn_end 的状态（如「电棱」按层数受到物理伤害）
	if p.dead:
		return
	for sid in p.status_ids():
		var st: Dictionary = db.get_status(sid)
		if String(st.get("trigger", "")) != "on_turn_end":
			continue
		if sid == "electro_prism":
			var layers := p.status_layer(sid)
			if layers <= 0:
				continue
			_log("%s 的「电棱」结算：%d 层 → 受到 %d 点物理伤害。" % [p.name, layers, layers])
			_deal_status_damage(players.find(p), layers, "physical", "「电棱」")

func _deal_status_damage(target_idx: int, amount: int, dtype: String, source_name: String) -> void:
	## 状态造成的伤害：跳过【防御】响应窗口直接结算，但伤害减免与装备减伤正常生效
	var target := players[target_idx]
	var amt := _apply_passives_incoming(target, target, "", dtype, amount, target_idx)
	amt = maxi(0, amt)
	_settle_damage({
		"source": target_idx,
		"defender": target_idx,
		"amount": amt,
		"damage_type": dtype,
		"source_name": source_name,
		"card_id": "",
		"card_type": "",
		"instance": -1,
	}, 0)

# 当前行动玩家死亡后必须立刻结束其回合，否则死者会继续拥有出牌/技能操作
func _end_turn_if_current_dead() -> bool:
	if mode == Mode.GAME_OVER or players.is_empty():
		return false
	if current < 0 or current >= players.size() or not players[current].dead:
		return false
	damage_return_to = "play"
	_end_turn()
	return true

func _advance_player() -> void:
	current = (current + 1) % players.size()
	# 已死亡玩家不再行动
	var guard := 0
	while players[current].dead and guard < players.size():
		current = (current + 1) % players.size()
		guard += 1
	# 全员死亡：立即判定终局，避免在死者之间循环
	if guard >= players.size():
		_check_deaths()

# ---------------- 摸牌 / 牌堆（规则 3.1） ----------------

func _draw_cards(p: PlayerData, n: int) -> void:
	if n <= 0:
		return
	# 洞悉：锁定技，所有摸牌行为改为先摸 2n 张，再自选弃 n 张
	if "skill_perceive" in p.skill_ids:
		var sk_name := String(db.get_skill("skill_perceive").get("name", "skill_perceive"))
		_log("%s 生效：%s 本次摸牌改为先摸 %d 张，再自选弃 %d 张。" % [sk_name, p.name, n * 2, n])
		_draw_raw(p, n * 2)
		_set_pending(PENDING_DISCARD_PICK, {"target": players.find(p), "count": n, "picker": "self", "setup": _setup_drawing})
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
	# 李斯特〖喧闹〗：不能使用手牌中的【跳过】（锁定技强制触发）
	if card_id == "skip" and _has_skill(p, "skill_noise"):
		_log("〖喧闹〗：你不能使用手牌中的【跳过】，它会在回合开始被自动替换。")
		return
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
		_resolve_card_after_play(card_id)
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
		_set_pending(PENDING_CARD, {
			"source": current,
			"card_id": card_id,
			"hand_index": card_index,
			"target_type": target_type,
		})
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
	var card_type := String(card.get("type", ""))
	var has_zone := card.has("zone") and not String(card.get("zone", "")).is_empty()
	# 进预备区的延时类牌（delayed_judge 或 special 带 zone）：不进弃牌堆，直接进目标预备区
	if card_type == "delayed_judge" or has_zone:
		players[target_idx].reserve.append(card_id)
		_log("%s 进入 %s 的预备区，将在其判定/出牌阶段结算。" % [String(card.get("name", card_id)), players[target_idx].name])
		_ensure_dying_window()  # 打出牌触发「恶化1」等自伤致死时仍需开救援窗口
		return
	_resolve_card_after_play(card_id)
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
	# 【跳过】特殊结算：解除或进入抵消响应窗口
	if card_id == "skip":
		_resolve_skip(p, target_idx)
		_ensure_dying_window()  # 「恶化1」等自伤致死时优先开救援窗口
		return
	# 【掠夺】特殊结算：不触发响应/防御窗口，直接盲选目标一张手牌
	if card_id == "plunder":
		_emit_behavior("play_card", current, {"card_id": card_id})
		if players[target_idx].hand.is_empty():
			_log("%s 没有手牌，掠夺落空。" % players[target_idx].name)
			_ensure_dying_window()
			return
		_start_plunder(current, target_idx, "card")
		return
	if card_id == "basic_attack":
		_resolve_basic_attack(p, target_idx)
	else:
		var ctx := {"card_id": card_id, "source_name": card_name, "instance": _card_instance_seq}
		# 〖韵动〗：每个出牌阶段第一张伤害类型牌的每段伤害 ×2
		if _card_deals_damage(card) and _has_skill(p, "skill_rhythm") and not p.rhythm_used:
			p.rhythm_used = true
			ctx["rhythm"] = true
			_log("%s 触发〖韵动〗：%s 的每段伤害提升100%%。" % [p.name, card_name])
		_run_actions(current, card.get("effects", []), target_idx, ctx)
	# 陷阱钩子：对手打出牌时触发（规则 3.3）
	_emit_behavior("play_card", current, {"card_id": card_id})
	_kick_damage()

# 【普通攻击】统一结算：〖开膛手〗灵魂伤害 / 〖扬沙〗双段 / 默认数据驱动 + 光明之眼/千钧之数钩子
# 调用方需先完成 attacks_used_this_turn 计数与〖血裔〗结算
func _resolve_basic_attack(p: PlayerData, target_idx: int) -> void:
	var target := players[target_idx]
	var ctx := {"card_id": "basic_attack", "source_name": "【普通攻击】", "instance": _card_instance_seq}
	if _has_skill(p, "skill_rhythm") and not p.rhythm_used:
		p.rhythm_used = true
		ctx["rhythm"] = true
		_log("%s 触发〖韵动〗：【普通攻击】的每段伤害提升100%%。" % p.name)
	if _has_skill(p, "skill_ripper"):
		# 〖开膛手〗：普攻默认造成 2 点灵魂伤害；〖千载幽咽〗指定目标则为 3 点
		var soul_val := 3 if p.millennium_marks.has(target_idx) else 2
		if ctx.has("rhythm"):
			soul_val *= 2
		_deal_damage(current, target_idx, soul_val, "soul", "【普通攻击】", "basic_attack")
		_log("%s 触发〖开膛手〗：【普通攻击】造成 %d 点灵魂伤害。" % [p.name, soul_val])
	elif _has_skill(p, "skill_sand_wind"):
		# 〖扬沙〗：普攻默认改成 2 次 2 点物理伤害（必须走 _deal_damage 让困兽/奋击/韵动/止戈/失明等正常生效）
		var dmg_val := 2
		if ctx.has("rhythm"):
			dmg_val *= 2
		_deal_damage(current, target_idx, dmg_val, "physical", "【普通攻击】（扬沙）", "basic_attack")
		_deal_damage(current, target_idx, dmg_val, "physical", "【普通攻击】（扬沙）", "basic_attack")
		_log("%s 触发〖扬沙〗：【普通攻击】改为 2×%d 点物理伤害。" % [p.name, dmg_val])
	else:
		_run_actions(current, db.get_card("basic_attack").get("effects", []), target_idx, ctx)
	# 〖光明之眼〗：每回合第一张普攻 → 目标失明
	if _has_skill(p, "skill_light_eye") and p.attacks_used_this_turn == 1:
		var c := _add_status_capped(target, "blind", 1, -1)
		if c > 0:
			_log("%s 触发〖光明之眼〗：%s 获得一层「失明」。" % [p.name, target.name])
	# 〖千钧之数〗：普攻附加一次预备区防御点数和×30%（向下取整）的灵魂伤害
	if _has_skill(p, "skill_thousand_weight"):
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

# 【跳过】结算（规则 3.3）：对已有「跳过」者使用=解除；否则其他玩家可打【跳过】抵消
func _resolve_skip(src_p: PlayerData, target_idx: int) -> void:
	var target := players[target_idx]
	if target.has_status("skip"):
		target.remove_status("skip")
		_log("%s 的「跳过」被%s解除了。" % [target.name, src_p.name])
		return
	# 进入抵消响应窗口：目标（或队友）可打出另一张【跳过】抵消
	_set_pending(PENDING_SKIP_RESPONSE, {
		"source": current,
		"defender": target_idx,
	})
	mode = Mode.RESPONSE
	_log("%s 即将获得「跳过」，可打出另一张【跳过】抵消。" % target.name)

func ui_select_target(target_idx: int) -> void:
	if mode != Mode.SELECT_TARGET or pending.is_empty():
		return
	if not target_candidates_now().has(target_idx):
		return
	var kind := String(pending.get("kind", ""))
	if kind == PENDING_CARD:
		var p := players[current]
		var card_id := String(pending["card_id"])
		var hand_index := int(pending["hand_index"])
		var card := db.get_card(card_id)
		pending = {}
		mode = Mode.PLAY
		_resolve_played_card(p, hand_index, card_id, card, target_idx)
	elif kind == PENDING_EVENT:
		var event := db.get_event(String(pending["event_id"]))
		var src := int(pending["source"])
		pending = {}
		mode = Mode.PLAY
		_log("事件目标：%s。" % players[target_idx].name)
		_run_actions(src, event.get("effects", []), target_idx, {"source_name": String(event["name"])})
		_kick_damage()
	elif kind == PENDING_SKILL:
		var skill := db.get_skill(String(pending["skill_id"]))
		var src := int(pending["source"])
		pending = {}
		mode = Mode.PLAY
		players[src].skill_uses_left[String(skill["id"])] = int(players[src].skill_uses_left.get(String(skill["id"]), 1)) - 1
		_log("%s 发动了%s，目标：%s。" % [players[src].name, String(skill["name"]), players[target_idx].name])
		_run_actions(src, skill.get("effects", []), target_idx, {"source_name": String(skill["name"])})
		_kick_damage()
	elif kind == PENDING_OSC_TARGET:
		# 振荡①：pick 层已把要弃的牌从区域移除暂存进 pending，这里确认后才执行副作用
		var src := int(pending.get("source", current))
		var skill_id := String(pending.get("skill_id", "skill_oscillation"))
		var first_cid := String(pending.get("first_card", ""))
		var second_cid := String(pending.get("second_card", ""))
		var p := players[src]
		pending = {}
		mode = Mode.PLAY
		p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
		p.oscillation_mode = 1  # 下次强制形态②
		if not first_cid.is_empty():
			_to_discard(first_cid)
		if not second_cid.is_empty():
			_to_discard(second_cid)
		var card_names: Array[String] = []
		for cid in [first_cid, second_cid]:
			if not cid.is_empty():
				card_names.append(String(db.get_card(cid).get("name", cid)))
		var _joined := ""
		for _n in card_names:
			if _joined != "": _joined += "、"
			_joined += _n
		_log("%s 发动〖振荡〗形态①：弃 [%s] → 对%s视作使用【跳过】。下次必形态②。" % [p.name, _joined, players[target_idx].name])
		_resolve_skip(p, target_idx)
		_kick_damage()
	elif kind == PENDING_PEEP_TARGET:
		# 窥伺之眼：把手牌视作【窥视】置入目标预备区（所有副作用在确认后执行）
		var p := players[current]
		var cid := String(pending.get("peep_card", ""))
		var skill_id := String(pending.get("skill_id", "skill_peep_eye"))
		pending = {}
		mode = Mode.PLAY
		p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
		if cid != "":
			_to_discard(cid)
		players[target_idx].reserve.append("special_peek")
		_log("%s 发动〖窥伺之眼〗：弃 %s → 【窥视】进入%s的预备区。" % [p.name, String(db.get_card(cid).get("name", cid)), players[target_idx].name])
		_kick_damage()
	elif kind == PENDING_SAGE_TARGET:
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
		var sname := String(db.get_status(sid).get("name", sid))
		p.sage_mode = (form + 1) % 3
		_log("%s 对 %s 施加 %d 层%s，〖贤者之书〗转为形态 %s。" % [p.name, players[target_idx].name, applied, sname, ["①", "②", "③"][p.sage_mode]])
	elif kind == PENDING_MUTUAL:
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
	elif kind == PENDING_EXILE_TARGET:
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
		_notify_cards_lost(tp, all_cards, "〖放逐〗")
		_finalize_dying(src)
	elif kind == PENDING_PRISM_TARGET:
		# 电离棱体：pick 层只是暂存（未移除），确认目标后才真正弃牌并施加「电棱」
		var src := int(pending.get("source", current))
		var p := players[src]
		var skill_id := String(pending.get("skill_id", "skill_ion_prism"))
		var prism_token := String(pending.get("prism_token", ""))
		pending = {}
		mode = Mode.PLAY
		var discarded := _take_zone_card(p, prism_token)
		if discarded.is_empty():
			_log("要丢弃的牌已不存在，〖电离棱体〗发动失败。")
			return
		_to_discard(discarded)
		p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
		_add_status_capped(players[target_idx], "electro_prism", 1, -1)
		_log("%s 发动〖电离棱体〗：弃 %s → %s 获得一层「电棱」（共 %d 层）。" % [p.name, String(db.get_card(discarded).get("name", discarded)), players[target_idx].name, players[target_idx].status_layer("electro_prism")])
	elif kind == PENDING_CONVERGE_TARGET:
		# 聚合：掠夺带 ≥2 层「电棱」者的一张手牌，并清除其所有「电棱」
		var src2 := int(pending.get("source", current))
		pending = {}
		mode = Mode.PLAY
		var sp2 := players[src2]
		var tp2 := players[target_idx]
		sp2.skill_uses_left["skill_converge"] = int(sp2.skill_uses_left.get("skill_converge", 1)) - 1
		if tp2.hand.is_empty():
			tp2.remove_status("electro_prism")
			_log("%s 发动〖聚合〗：%s 没有手牌，掠夺落空，其所有「电棱」已被清除。" % [sp2.name, tp2.name])
			return
		_log("%s 发动〖聚合〗：掠夺 %s 的一张手牌。" % [sp2.name, tp2.name])
		_start_plunder(src2, target_idx, "converge")
	elif kind == PENDING_PRAYER_TARGET:
		# 祝祷（为他人回复）：确认目标后进入两步弃牌
		var skill_id2 := String(pending.get("skill_id", "skill_prayer"))
		pending = {}
		_begin_prayer_discards(players[current], skill_id2, target_idx)
	elif kind == PENDING_COFFIN_TARGET:
		# 开棺：移除预备区 2 张【陪葬品】，视作打出一张【普通攻击】
		var src3 := int(pending.get("source", current))
		var p3 := players[src3]
		var skill_id3 := String(pending.get("skill_id", "skill_open_coffin"))
		pending = {}
		mode = Mode.PLAY
		var removed := 0
		for i in range(p3.reserve.size() - 1, -1, -1):
			if removed >= 2:
				break
			if p3.reserve[i] == "token_funerary":
				p3.reserve.remove_at(i)
				removed += 1
		p3.skill_uses_left[skill_id3] = int(p3.skill_uses_left.get(skill_id3, 1)) - 1
		_log("%s 发动〖开棺〗：将 2 张【陪葬品】视作【普通攻击】打出，目标：%s。" % [p3.name, players[target_idx].name])
		p3.attacks_used_this_turn += 1
		if _has_skill(p3, "skill_bloodline"):
			_apply_bloodline(p3)
		_card_instance_seq += 1
		_resolve_basic_attack(p3, target_idx)
		_emit_behavior("play_card", src3, {"card_id": "basic_attack"})
		_kick_damage()
	elif kind == PENDING_MILLENNIUM_TARGET:
		# 千载幽咽：指定第 1/2 名目标
		var src4 := int(pending.get("source", current))
		var p4 := players[src4]
		pending = {}
		mode = Mode.PLAY
		p4.millennium_marks[target_idx] = true
		_log("%s 将 %s 指定为〖千载幽咽〗的目标。" % [p4.name, players[target_idx].name])
		if p4.millennium_marks.size() < 2:
			var more_left := false
			for i in players.size():
				if i != src4 and not players[i].dead and not players[i].dying and not p4.millennium_marks.has(i):
					more_left = true
			if more_left:
				_set_pending(PENDING_MILLENNIUM_ASK, {"source": src4, "options": ["more", "done"]})
				mode = Mode.SKILL_PICK
				_log("〖千载幽咽〗：是否再指定一名目标？")
				return
		_log("〖千载幽咽〗指定完成：本回合 %s 对被指定者的【普通攻击】默认造成 3 点灵魂伤害。" % p4.name)

# 取消选目标（卡牌/技能/转换技/事件/放逐均可取消）
func ui_cancel_target() -> void:
	if mode != Mode.SELECT_TARGET:
		return
	var kind := String(pending.get("kind", ""))
	if kind == PENDING_CARD or kind == PENDING_MUTUAL or kind == PENDING_SAGE_TARGET or kind == PENDING_SKILL:
		pending = {}
		mode = Mode.PLAY
		_log("取消了出牌。")
	elif kind == PENDING_PEEP_TARGET:
		# 恢复被 take_zone_card 移除的手牌
		var peep_cid := String(pending.get("peep_card", ""))
		var p := players[current]
		pending = {}
		mode = Mode.PLAY
		if not peep_cid.is_empty():
			p.hand.append(peep_cid)
		_log("取消了〖窥伺之眼〗，手牌已恢复。")
	elif kind == PENDING_OSC_TARGET:
		# 恢复两张被 take_zone_card 从手牌移除的牌（副作用未执行所以不需要回滚次数）
		var first_cid := String(pending.get("first_card", ""))
		var second_cid := String(pending.get("second_card", ""))
		var p2 := players[current]
		pending = {}
		mode = Mode.PLAY
		if not first_cid.is_empty():
			p2.hand.append(first_cid)
		if not second_cid.is_empty():
			p2.hand.append(second_cid)
		_log("取消了〖振荡〗形态①选目标，手牌已恢复，不消耗次数。")
	elif kind == PENDING_EVENT:
		pending = {}
		mode = Mode.PLAY
		_log("放弃了事件结算。")
	elif kind == PENDING_EXILE_TARGET:
		var src := int(pending.get("source", current))
		pending = {}
		mode = Mode.PLAY
		_log("%s 放弃发动〖放逐〗。" % players[src].name)
		_finalize_dying(src)
	elif kind == PENDING_PRISM_TARGET or kind == PENDING_CONVERGE_TARGET or kind == PENDING_PRAYER_TARGET or kind == PENDING_COFFIN_TARGET:
		# 这些流程在确认目标前均未产生副作用（牌未移除/次数未扣），直接取消即可
		pending = {}
		mode = Mode.PLAY
		_log("取消了技能发动。")
	elif kind == PENDING_MILLENNIUM_TARGET:
		# 千载幽咽：取消视为完成指定（至少已指定 1 名时）；一名未指定则视为放弃发动
		var src2 := int(pending.get("source", current))
		var p2 := players[src2]
		pending = {}
		mode = Mode.PLAY
		if p2.millennium_marks.is_empty():
			p2.limited_used.erase("skill_millennium")
			_log("%s 放弃了〖千载幽咽〗的发动。" % p2.name)
		else:
			_log("〖千载幽咽〗指定完成：本回合 %s 对被指定者的【普通攻击】默认造成 3 点灵魂伤害。" % p2.name)

# 供 UI 查询当前可选目标
func target_candidates_now() -> Array[int]:
	if mode != Mode.SELECT_TARGET:
		return []
	var kind := String(pending.get("kind", ""))
	var src_idx := int(pending.get("source", current))
	if kind == PENDING_EXILE_TARGET:
		var res: Array[int] = []
		for i in players.size():
			if i != src_idx and not players[i].dead:
				res.append(i)
		return res
	if kind == PENDING_MUTUAL:
		var src2 := int(pending.get("source", current))
		var res2: Array[int] = []
		for i in players.size():
			if i != src2 and not players[i].dead and players[i].status_layer("pale") > 0:
				res2.append(i)
		return res2
	if kind == PENDING_CONVERGE_TARGET:
		var res3: Array[int] = []
		for i in players.size():
			if i != src_idx and not players[i].dead and players[i].status_layer("electro_prism") >= 2:
				res3.append(i)
		return res3
	if kind == PENDING_PRAYER_TARGET:
		# 祝祷可为其他存活或「濒死」玩家回复生命
		var res4: Array[int] = []
		for i in players.size():
			if i != src_idx and not players[i].dead:
				res4.append(i)
		return res4
	if kind == PENDING_MILLENNIUM_TARGET:
		var p2 := players[src_idx]
		var res5: Array[int] = []
		for i in players.size():
			if i != src_idx and not players[i].dead and not players[i].dying and not p2.millennium_marks.has(i):
				res5.append(i)
		return res5
	return _target_candidates_for(src_idx, String(pending.get("target_type", "none")), String(pending.get("card_id", "")))

# 目标候选（规则：「濒死」角色不能再成为伤害/效果目标，治疗与食物除外）
func _target_candidates(target_type: String, card_id: String) -> Array[int]:
	# 兼容旧签名：默认以当前行动玩家为行动来源
	return _target_candidates_for(current, target_type, card_id)

func _target_candidates_for(source_idx: int, target_type: String, card_id: String) -> Array[int]:
	var result: Array[int] = []
	for i in players.size():
		var p := players[i]
		match target_type:
			"single_any":
				if p.dead or p.dying:
					continue
				result.append(i)
			"single_enemy":
				# 单体目标：任一其他存活玩家（口径 2.5-7：描述未写「敌人」即含队友）
				if p.dead or p.dying or i == source_idx:
					continue
				result.append(i)
			"self_or_dying":
				# 食物牌：自己；或任意「濒死」角色（视为其使用，规则 3.3）
				if i == source_idx and not p.dead and not p.dying:
					result.append(i)
				elif p.dying and not p.dead:
					result.append(i)
			"all_players":
				# 场上所有存活玩家（含自己）
				if not p.dead:
					result.append(i)
			"all_enemies":
				# 所有敌方玩家：非同队且不含自己
				if not p.dead and i != source_idx and not is_same_team(source_idx, i):
					result.append(i)
			"all_allies":
				# 所有友方玩家：同队含自己（1v1 与 1v1v1 下等价于仅自己）
				if not p.dead and (i == source_idx or is_same_team(source_idx, i)):
					result.append(i)
			"all_others":
				# 除了自己之外的所有存活玩家（含队友）
				if not p.dead and i != source_idx:
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
			var sname := String(db.get_status(sid).get("name", sid))
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
			_heal_with_saint(p, int(action.get("value", 0)))
			_log("%s 回复 %d 点生命（%d → %d）。" % [p.name, p.hp - old, old, p.hp])
		"random_discard":
			var p := players[t]
			if p.hand.is_empty():
				_log("%s 没有手牌可弃。" % p.name)
			else:
				var count := int(action.get("value", 1))
				var actual := mini(count, p.hand.size())
				var names: Array[String] = []
				var lost: Array[String] = []
				for _i in actual:
					var r := randi() % p.hand.size()
					var cid := p.hand[r]
					p.hand.remove_at(r)
					_to_discard(cid)
					names.append(String(db.get_card(cid)["name"]))
					lost.append(cid)
				var joined := ""
				for _n in names:
					if joined != "":
						joined += "、"
					joined += _n
				_log("随机弃置了 %s 的 %d 张手牌（%s）。" % [p.name, actual, joined])
				_notify_cards_lost(p, lost, "随机弃置")
		"discard_target_pick":
			var p := players[t]
			if p.hand.is_empty():
				_log("%s 没有手牌可弃。" % p.name)
			else:
				var count := int(action.get("value", 1))
				_set_pending(PENDING_DISCARD_PICK, {"target": t, "count": count, "picker": "actor", "source": src_idx})
				mode = Mode.DISCARD_PICK
				_log("请选择 %s 的 %d 张手牌弃置。" % [p.name, count])
		"trigger_event":
			_trigger_event(src_idx)
		"lose_hp":
			# 失去生命：不受防御/装备影响，直接扣血（濒死窗口由流程收尾统一开启）
			_lose_hp_direct(players[t], int(action.get("value", 1)), "失去生命")
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
		_log("%s 生效：本次【普通攻击】伤害 +1。" % String(db.get_status("attack_up_1").get("name", "attack_up_1")))
	# 通用被动系统：装备/属性效果统一结算
	amount = _apply_passives_outgoing(src, target, card_id, damage_type, amount, src_idx)
	amount = _apply_passives_incoming(src, target, card_id, damage_type, amount, src_idx)
	# 「寒冷1」：造成伤害时本次伤害 -1，然后减少一层
	if src.has_status("cold_1"):
		src.consume_layer("cold_1")
		amount -= 1
		_log("%s 因「寒冷1」本次伤害 -1（剩余 %d 层）。" % [src.name, src.status_layer("cold_1")])
	# 「失明」：造成伤害时 -100%，触发后移除一层
	if src.has_status("blind"):
		src.consume_layer("blind")
		amount = 0
		_log("%s 因「失明」本次伤害归零（剩余 %d 层）。" % [src.name, src.status_layer("blind")])
	# 「止戈」：造成伤害时 -1（加算），触发后不移除（出牌阶段结束统一清）
	if src.has_status("stop_sword"):
		var n := src.status_layer("stop_sword")
		amount -= n
		_log("%s 因「止戈」本次伤害 -%d。" % [src.name, n])
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
		# 无伤害待结算，但仍可能有技能/状态自伤导致的濒死，需要开救援窗口
		_ensure_dying_window()
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
			_set_pending(PENDING_DAMAGE, {
				"source": int(d["source"]),
				"defender": int(d["defender"]),
				"amount": int(d["amount"]),
				"blocked": 0,
				"damage_type": dtype,
				"source_name": String(d["source_name"]),
			})
			mode = Mode.RESPONSE
			_log("等待 %s 响应……" % players[int(d["defender"])].name)
			return
		# 灵魂伤害 / 失去生命：直接结算
		damage_queue.remove_at(0)
		_settle_damage(d, 0)
	_after_damage_queue()

func _after_damage_queue() -> void:
	# 规则 5.3：有「濒死」角色时先开救援窗口（可按座位顺序用食物救），结算完毕仍未脱离才宣布死亡
	if _ensure_dying_window():
		return
	_check_deaths()
	if mode == Mode.GAME_OVER:
		return
	if damage_return_to == "judge":
		_after_judge()
	else:
		mode = Mode.PLAY
		# 伤害结算完毕后的安全点：弹出延迟询问（〖开膛手〗掠夺 / 〖演算机器〗二选一）
		_run_deferred_prompts()

# 存在濒死角色且当前没有已打开的救援窗口时开窗；返回是否新开窗
func _ensure_dying_window() -> bool:
	if _dying_window_open or mode == Mode.GAME_OVER:
		return false
	for i in players.size():
		if players[i].dying and not players[i].dead:
			_open_dying_window(i)
			return true
	return false

# 濒死救援窗口：从濒死者开始按座位顺序，各玩家可打出食物（视为濒死角色使用，规则 3.3）
func _open_dying_window(dying_idx: int) -> void:
	var rescuers: Array[int] = []
	for k in players.size():
		var i := (dying_idx + k) % players.size()
		if not players[i].dead:
			rescuers.append(i)
	_dying_window_open = true
	_set_pending(PENDING_DYING_SAVE, {"dying_player": dying_idx, "rescuers": rescuers})
	mode = Mode.RESPONSE
	_log("%s 处于「濒死」！按座位顺序询问救援：可打出食物牌（视为濒死角色使用）。" % players[dying_idx].name)

# 救援结束仍濒死：宣布死亡（规则 5.3）
func _finalize_dying(idx: int) -> void:
	_dying_window_open = false
	var p := players[idx]
	if not p.dying or p.dead:
		_check_deaths()
		if mode == Mode.GAME_OVER:
			return
		if damage_return_to == "end_turn":
			_finish_end_turn()
			return
		if damage_return_to == "judge":
			_after_judge()
		else:
			mode = Mode.PLAY
			_run_deferred_prompts()
		return
	# 限定技〖放逐〗：宣布死亡时询问一次（可选择不发动）
	if _has_skill(p, "skill_exile") and not bool(p.limited_used.get("skill_exile", false)) and not _exile_done.has(idx):
		var has_other := false
		for i in players.size():
			if i != idx and not players[i].dead:
				has_other = true
		if has_other:
			_set_pending(PENDING_EXILE_ASK, {"dying": idx, "options": ["yes", "no"]})
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
	# 濒死者就是当前行动玩家时，其回合必须就地结束（自伤/状态致死）
	if _end_turn_if_current_dead():
		return
	if damage_return_to == "end_turn":
		_finish_end_turn()
		return
	if damage_return_to == "judge":
		_after_judge()
	else:
		mode = Mode.PLAY
		_run_deferred_prompts()

# 结算单次伤害实例
func _settle_damage(d: Dictionary, blocked: int) -> void:
	var defender := players[int(d["defender"])]
	var dtype := String(d["damage_type"])
	var dmg: int = maxi(0, int(d["amount"]) - blocked)
	var type_name := String(DAMAGE_TYPE_NAMES.get(dtype, dtype))
	# 伤害减免（〖时钟悖论〗等）：每次受到非生命流失伤害时等额削减
	if dtype != "hp_loss" and dmg > 0 and defender.damage_reduction > 0:
		var reduced := mini(dmg, defender.damage_reduction)
		dmg -= reduced
		_log("%s 的伤害减免生效：本次%s伤害 -%d。" % [defender.name, type_name, reduced])
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
			# 古卢〖止戈〗：受到其他玩家造成的【普通攻击】伤害后，对来源施加一层「止戈」
			if _has_skill(defender, "skill_stop_sword_skill") and String(d.get("card_id", "")) == "basic_attack":
				var c4 := _add_status_capped(src_p, "stop_sword", 1, -1)
				if c4 > 0:
					_log("%s 触发〖止戈〗：%s 获得一层「止戈」（%d 层）。" % [defender.name, src_p.name, src_p.status_layer("stop_sword")])
			# 瑞普〖开膛手〗：普攻对其他玩家造成伤害后，延迟询问是否掠夺其手牌扣置为【陪葬品】
			if _has_skill(src_p, "skill_ripper") and String(d.get("card_id", "")) == "basic_attack":
				_ripper_pending.append({"source": int(d["source"]), "defender": int(d["defender"])})
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
	if kind == PENDING_DAMAGE or kind == PENDING_SKIP_RESPONSE:
		var defender := players[int(pending["defender"])]
		if card_index < 0 or card_index >= defender.hand.size():
			return
		var card_id := defender.hand[card_index]
		var card := db.get_card(card_id)
		if kind == PENDING_DAMAGE:
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
	elif kind == PENDING_DYING_SAVE:
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
			_dying_window_open = false
			pending = {}
			_after_damage_queue()

# 响应时使用预备区中的防御牌：不需要执行「打出」动作（规则 5.2）
func ui_play_reserve(reserve_index: int) -> void:
	if mode != Mode.RESPONSE or String(pending.get("kind", "")) != PENDING_DAMAGE:
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
	if kind == PENDING_DAMAGE:
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
	elif kind == PENDING_SKIP_RESPONSE:
		var t := players[int(pending["defender"])]
		t.add_status("skip")
		_log("%s 获得「跳过」。" % t.name)
		pending = {}
		mode = Mode.PLAY
	elif kind == PENDING_DYING_SAVE:
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
	# 结算预备区中所有在「判定阶段」触发的延时判定牌
	var judges: Array[String] = []
	for cid in p.reserve:
		var card := db.get_card(cid)
		var ct := String(card.get("type", ""))
		if ct == "delayed_judge":
			judges.append(cid)
		elif ct == "special":
			var jdict: Dictionary = card.get("judge", {})
			if String(jdict.get("trigger_phase", "")) != "play_start":
				# 普通判定阶段触发的 special 延时牌（如富兰克林之钥：回合开始）
				judges.append(cid)
	if judges.is_empty():
		return
	_log("—— %s 的判定阶段 ——" % p.name)
	for cid in judges:
		p.reserve.erase(cid)
		_resolve_card_after_play(cid)
		var card := db.get_card(cid)
		_log("结算延时判定牌%s。" % String(card.get("name", cid)))
		var owner_idx := players.find(p)
		_run_judge(card.get("judge", {}), owner_idx, owner_idx, String(card.get("name", cid)))
		if mode == Mode.GAME_OVER:
			return

# 结算预备区中「出牌阶段开始」触发的 special 延时牌（如【窥视】）
func _run_play_start_judge(p: PlayerData) -> void:
	var judges: Array[String] = []
	for cid in p.reserve:
		var card := db.get_card(cid)
		if String(card.get("type", "")) == "special":
			var jdict: Dictionary = card.get("judge", {})
			if String(jdict.get("trigger_phase", "")) == "play_start":
				judges.append(cid)
	if judges.is_empty():
		return
	for cid in judges:
		p.reserve.erase(cid)
		_resolve_card_after_play(cid)
		var card := db.get_card(cid)
		_log("出牌阶段开始，结算%s。" % String(card.get("name", cid)))
		var owner_idx := players.find(p)
		_run_judge(card.get("judge", {}), owner_idx, owner_idx, String(card.get("name", cid)))
		if mode == Mode.GAME_OVER:
			return

# 三种判定方式：摸牌判定 / 排中判定 / 骰子判定（规则 4.3）+ multi_judge 多段
func _run_judge(j: Dictionary, src_idx: int, target_idx: int, source_name: String) -> void:
	var method := String(j.get("method", "coin"))
	var multi: Dictionary = j.get("multi_judge", {}) if j.has("multi_judge") else {}
	if not multi.is_empty():
		# 多段判定：翻 count 次，success 即中断
		var count := int(multi.get("count", 2))
		var interrupt := bool(multi.get("interrupt_on_success", false))
		var all_failed := true
		for step in range(count):
			var success := _run_single_judge_roll(method, j)
			if success:
				all_failed = false
				if interrupt:
					break
		if all_failed:
			_log("%s 两次判定均失败，执行失败效果。" % source_name)
			_execute_judge_actions(j.get("fail_actions", []), src_idx, target_idx, source_name)
		else:
			_log("%s 判定过程中有一次成功，效果不触发。" % source_name)
		return
	var success := _run_single_judge_roll(method, j)
	var actions: Array = j.get("success_actions", []) if success else j.get("fail_actions", [])
	_execute_judge_actions(actions, src_idx, target_idx, source_name)

func _run_single_judge_roll(method: String, j: Dictionary) -> bool:
	# 开发者菜单：强制本次判定结果
	if dev_forced_judge != "":
		var forced := dev_forced_judge
		dev_forced_judge = ""
		if forced == "success":
			_log("【开发者】本次判定被强制为成功。")
			return true
		if forced == "fail":
			_log("【开发者】本次判定被强制为失败。")
			return false
		if forced.begins_with("roll:"):
			var roll := clampi(int(forced.substr(5)), 1, 6)
			var need: Array = j.get("success_values", [])
			var ok := need.has(roll)
			_log("【开发者】骰子判定被强制掷出 %d 点 → %s。" % [roll, "成功" if ok else "失败"])
			return ok
	match method:
		"draw":
			var jid := _judge_draw_card()
			if jid == "":
				_log("摸牌判定失败：抽牌堆为空。")
				return false
			var jc := db.get_card(jid)
			var cond := String(j.get("condition", ""))
			var s := _judge_card_match(jc, cond)
			_log("摸牌判定：翻开%s（条件：%s）→ %s。" % [String(jc.get("name", jid)), _judge_condition_name(cond), "成功" if s else "失败"])
			_to_discard(jid)
			return s
		"coin":
			var s := randi() % 2 == 0
			_log("排中判定：%s。" % ("正面（成功）" if s else "反面（失败）"))
			return s
		"dice":
			var roll := 1 + randi() % 6
			var need: Array = j.get("success_values", [])
			var s := need.has(roll)
			_log("骰子判定：掷出 %d 点（成功点：%s）→ %s。" % [roll, str(need), "成功" if s else "失败"])
			return s
	return false

func _execute_judge_actions(actions: Array, src_idx: int, target_idx: int, source_name: String) -> void:
	for action in actions:
		var atype := String(action.get("type", ""))
		if atype == "conditional_deal_damage":
			# 条件扣血：目标带有指定状态才生效
			var cond_status := String(action.get("condition_status", ""))
			var t := players[target_idx]
			if not t.has_status(cond_status):
				_log("条件未满足（%s 不带「%s」），跳过。" % [t.name, cond_status])
				continue
		if atype == "prompt_choice":
			# 选择式判定失败：让玩家在多个动作里选一个
			var choices: Array = action.get("prompt_choice", [])
			if choices.size() >= 2:
				var idx_options: Array = []
				for i in choices.size():
					idx_options.append(str(i))
				_set_pending("judge_prompt", {"source": src_idx, "target": target_idx, "choices": choices, "options": idx_options, "source_name": source_name})
				mode = Mode.SKILL_PICK
				_log("%s 判定失败，请选择一项。" % source_name)
				return  # 等 pick
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

# 行为事件钩子：敌对玩家布置的陷阱在满足条件时触发（队友陷阱不触发，口径 2.5-2）
func _emit_behavior(event: String, actor_idx: int, ctx: Dictionary) -> void:
	for i in players.size():
		if i == actor_idx:
			continue
		var p := players[i]
		if p.dead:
			continue
		# 2v2 中队友的陷阱不会因本方行为触发
		if is_same_team(i, actor_idx):
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

# 主动技能特判：技能 id -> 处理函数（返回 true 表示已处理；false 继续走通用流程）
const SKILL_SPECIAL_HANDLERS := {
	"skill_fractal": "_skill_fractal",
	"skill_sage_book": "_skill_sage_book",
	"skill_mutual": "_skill_mutual",
	"skill_leap_faith": "_skill_leap_faith",
	"skill_false_step": "_skill_false_step",
	"skill_lightning_rod": "_skill_lightning_rod",
	"skill_tip_discharge": "_skill_tip_discharge",
	"skill_peep_eye": "_skill_peep_eye",
	"skill_oscillation": "_skill_oscillation",
	"skill_sand_burial": "_skill_sand_burial",
	"skill_ion_prism": "_skill_ion_prism",
	"skill_converge": "_skill_converge",
	"skill_prayer": "_skill_prayer",
	"skill_open_coffin": "_skill_open_coffin",
	"skill_millennium": "_skill_millennium",
}

# 技能选牌处理：pending kind -> 处理函数
const SKILL_PICK_HANDLERS := {
	PENDING_SKILL_RETRIEVE: "_pick_retrieve",
	PENDING_FRACTAL: "_pick_fractal",
	PENDING_SAGE: "_pick_sage",
	PENDING_LEAP: "_pick_leap",
	PENDING_EXILE_ASK: "_pick_exile_ask",
	PENDING_MERCY: "_pick_mercy",
	PENDING_OSC_FORM: "_pick_osc_form",
	PENDING_PEEP_HAND: "_pick_peep_hand",
	PENDING_SAND_BURY_HAND: "_pick_sand_bury_hand",
	PENDING_PLUNDER: "_pick_plunder",
	PENDING_MACHINE: "_pick_machine",
	PENDING_PRISM: "_pick_prism",
	PENDING_PRAYER_MODE: "_pick_prayer_mode",
	PENDING_PRAYER_DISCARD: "_pick_prayer_discard",
	PENDING_RIPPER_ASK: "_pick_ripper_ask",
	PENDING_MILLENNIUM_ASK: "_pick_millennium_ask",
	"judge_prompt": "_pick_judge_prompt",
}

func ui_use_skill(skill_id: String) -> void:
	if mode != Mode.PLAY:
		return
	var p := players[current]
	if not p.skill_ids.has(skill_id):
		return
	var skill := db.get_skill(skill_id)
	var stype := String(skill.get("skill_type", ""))
	# 限定技：每局一次，检查 limited_used
	if stype == "limited":
		if bool(p.limited_used.get(skill_id, false)):
			_log("%s 已在本局发动过。" % String(skill.get("name", skill_id)))
			return
	# 觉醒技能（沙葬）：未觉醒时不可用
	if skill_id == "skill_sand_burial" and not p.star_brilliance_awakened:
		_log("〖沙葬〗需觉醒〖星辉〗后才能发动。")
		return
	# 主动/转换技：检查本回合剩余次数
	if stype == "active" or stype == "switch":
		if int(p.skill_uses_left.get(skill_id, 0)) <= 0:
			_log("本回合该技能次数已用完。")
			return
	# 1. 技能特判（数据无法表达的前置检查与选择）
	var handler := String(SKILL_SPECIAL_HANDLERS.get(skill_id, ""))
	if handler != "" and bool(call(handler, p, skill, skill_id)):
		return
	# 2. 数据驱动的弃牌堆检索（如〖坚壁〗）
	if _try_retrieve_defense(skill, skill_id):
		return
	# 3. 需要选目标的主动技
	var tt := String(skill.get("target_type", "none"))
	if tt == "single_any" or tt == "single_enemy":
		var candidates := _target_candidates(tt, "")
		if candidates.is_empty():
			_log("没有合法目标，%s 发动失败。" % String(skill["name"]))
			return
		_set_pending(PENDING_SKILL, {"source": current, "skill_id": skill_id, "target_type": tt})
		mode = Mode.SELECT_TARGET
		_log("请选择%s的目标。" % String(skill["name"]))
		return
	# switch / limited 不应该走通用路径，已在特判里拦截
	if stype == "switch" or stype == "limited":
		_log("%s 无法通过通用路径结算。" % String(skill.get("name", "")))
		return
	# 4. 其他主动技：直接结算
	p.skill_uses_left[skill_id] = int(p.skill_uses_left[skill_id]) - 1
	_log("%s 发动了%s。" % [p.name, String(skill["name"])])
	_run_actions(current, skill.get("effects", []), current, {"source_name": String(skill["name"])})
	_kick_damage()

# 〖分形几何〗：将一张【普通攻击】视作【防御2】布置到预备区
func _skill_fractal(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	var fopts: Array[String] = []
	for i in p.hand.size():
		if p.hand[i] == "basic_attack":
			fopts.append("hand:%d" % i)
	if fopts.is_empty():
		_log("手牌中没有【普通攻击】，〖分形几何〗发动失败。")
		return true
	_set_pending(PENDING_FRACTAL, {"skill_id": skill_id, "options": fopts})
	mode = Mode.SKILL_PICK
	_log("请选择一张【普通攻击】转化为【防御2】。")
	return true

# 〖贤者之书〗：选择区域内一张牌丢弃，再选择目标
func _skill_sage_book(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	var sopts := _zone_card_options(p)
	if sopts.is_empty():
		_log("你的区域内没有可丢弃的牌，〖贤者之书〗发动失败。")
		return true
	if _target_candidates("single_enemy", "").is_empty():
		_log("没有其他合法玩家，〖贤者之书〗发动失败。")
		return true
	_set_pending(PENDING_SAGE, {"skill_id": skill_id, "options": sopts})
	mode = Mode.SKILL_PICK
	_log("〖贤者之书〗：请选择要丢弃的牌。")
	return true

# 〖相生相灭〗：需自身有「玄暗」且场上有其他带「皎白」的玩家
func _skill_mutual(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	if p.status_layer("dark") <= 0:
		_log("你没有「玄暗」，〖相生相灭〗发动失败。")
		return true
	var has_pale := false
	for i in players.size():
		if i != current and not players[i].dead and players[i].status_layer("pale") > 0:
			has_pale = true
	if not has_pale:
		_log("场上没有携带「皎白」的其他玩家，〖相生相灭〗发动失败。")
		return true
	_set_pending(PENDING_MUTUAL, {"source": current, "skill_id": skill_id, "target_type": "single_enemy"})
	mode = Mode.SELECT_TARGET
	_log("〖相生相灭〗：请选择一名携带「皎白」的玩家。")
	return true

# 〖信仰之跃〗：选择摸牌数量（1~3）
func _skill_leap_faith(_p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	_set_pending(PENDING_LEAP, {"skill_id": skill_id, "options": ["1", "2", "3"]})
	mode = Mode.SKILL_PICK
	_log("〖信仰之跃〗：请选择要摸取的数量（摸 X 张，失去 2X 点生命）。")
	return true

# 〖失足之幸〗：生命值 ≥20 才能发动（不满足时拦截；满足则继续通用流程）
func _skill_false_step(p: PlayerData, _skill: Dictionary, _skill_id: String) -> bool:
	if p.hp < 20:
		_log("生命值不足 20，〖失足之幸〗发动失败。")
		return true
	return false

# 雷雨〖引雷〗（限定技）：将【富兰克林之钥】加入手牌
func _skill_lightning_rod(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	p.limited_used[skill_id] = true
	p.hand.append("special_franklin_key")
	_log("%s 发动〖引雷〗：一张【富兰克林之钥】加入手牌。" % p.name)
	return true

# 雷雨〖尖端放电〗：弃一张手牌 → 对场上所有带「触电」的玩家造成2点灵魂伤害
func _skill_tip_discharge(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	# 前置检查：场上必须存在带「触电」标记的玩家
	var has_electrified := false
	for other in players:
		if not other.dead and other.has_status("electrified"):
			has_electrified = true
			break
	if not has_electrified:
		_log("场上没有带「触电」标记的玩家，〖尖端放电〗无法发动。")
		return true
	if p.hand.is_empty():
		_log("手牌为空，〖尖端放电〗发动失败。")
		return true
	# 选择一张手牌
	var opts: Array[String] = []
	for i in p.hand.size():
		opts.append("hand:%d" % i)
	_set_pending(PENDING_SAND_BURY_HAND, {"skill_id": skill_id, "sub_kind": "tip_discharge", "step": 1, "options": opts})
	mode = Mode.SKILL_PICK
	_log("〖尖端放电〗：请选择一张手牌弃置。")
	return true

# 奥比亚〖窥伺之眼〗：选一张手牌视作【窥视】置入敌方判定区
func _skill_peep_eye(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	if p.hand.is_empty():
		_log("手牌为空，〖窥伺之眼〗发动失败。")
		return true
	var opts: Array[String] = []
	for i in p.hand.size():
		opts.append("hand:%d" % i)
	_set_pending(PENDING_PEEP_HAND, {"skill_id": skill_id, "options": opts})
	mode = Mode.SKILL_PICK
	_log("〖窥伺之眼〗：请选择一张手牌作为【窥视】使用。")
	return true

# 李斯特〖振荡〗（转换技）：强制按 oscillation_mode 轮换 —— 第一次必①、用后切②、再下次必①
func _skill_oscillation(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	var form := int(p.oscillation_mode)
	if form == 0:
		# ① 自选弃2手牌 → 选敌方目标 → 视作使用【跳过】
		if p.hand.size() < 2:
			_log("手牌不足 2 张，〖振荡〗形态①发动失败。")
			return true
		var opts: Array[String] = []
		for i in p.hand.size():
			opts.append("hand:%d" % i)
		_set_pending(PENDING_SAND_BURY_HAND, {"skill_id": skill_id, "sub_kind": "osc_discard", "step": 1, "options": opts})
		mode = Mode.SKILL_PICK
		_log("〖振荡〗形态①：请选择第 1 张要弃置的手牌（共需弃 2 张）。")
	else:
		# ② 摸2牌 + 自加跳过（无目标，直接结算）
		p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
		p.oscillation_mode = 0  # 下次切换形态①
		_draw_cards(p, 2)
		p.add_status("skip", -1, 1)
		mode = Mode.PLAY
		_log("%s 发动〖振荡〗形态②：摸 2 张牌，对自己施加「跳过」。下次必形态①。" % p.name)
		_kick_damage()
	return true

# 狄瑟〖沙葬〗（觉醒技）：弃两张牌 → 骰子 → AoE 点数/2 物理伤害
func _skill_sand_burial(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	var opts: Array[String] = []
	for i in p.hand.size():
		opts.append("hand:%d" % i)
	for i in p.equipment.size():
		opts.append("equip:%d" % i)
	for i in p.reserve.size():
		opts.append("reserve:%d" % i)
	if opts.size() < 2:
		_log("可用牌不足 2 张，〖沙葬〗发动失败。")
		return true
	_set_pending(PENDING_SAND_BURY_HAND, {"skill_id": skill_id, "sub_kind": "sand_bury", "step": 1, "options": opts})
	mode = Mode.SKILL_PICK
	_log("〖沙葬〗：请选择第一张要弃置的牌。")
	return true

# ---------------- 溯洄之境：掠夺 / 演算机器 / 新角色技能 ----------------

# 掠夺入口：从目标区域拿一张牌入来源对应区域。
# 手牌=盲选（UI 只显示数量与背面）；装备/预备/陷阱=明牌自选。目标全空→落空记日志。
func _start_plunder(src_idx: int, target_idx: int, purpose: String, hand_only: bool = true) -> bool:
	var sp := players[src_idx]
	var tp := players[target_idx]
	var opts: Array[String] = []
	for i in tp.hand.size():
		opts.append("hand:%d" % i)
	if not hand_only:
		for i in tp.equipment.size():
			opts.append("equip:%d" % i)
		for i in tp.reserve.size():
			opts.append("reserve:%d" % i)
		for i in tp.traps.size():
			opts.append("trap:%d" % i)
	if opts.is_empty():
		_log("%s 尝试掠夺 %s，但其区域内没有可掠夺的牌，掠夺落空。" % [sp.name, tp.name])
		return false
	_set_pending(PENDING_PLUNDER, {"source": src_idx, "target": target_idx, "purpose": purpose, "options": opts})
	mode = Mode.SKILL_PICK
	_log("%s 正在掠夺 %s：请选择要夺取的牌。" % [sp.name, tp.name])
	return true

func _pick_plunder(_p: PlayerData, _skill_id: String, token: String) -> void:
	var src := int(pending.get("source", current))
	var tgt := int(pending.get("target", -1))
	var purpose := String(pending.get("purpose", "card"))
	if tgt < 0:
		pending = {}
		mode = Mode.PLAY
		return
	var sp := players[src]
	var tp := players[tgt]
	var cid := _take_zone_card(tp, token)
	if cid.is_empty():
		pending = {}
		mode = Mode.PLAY
		return
	pending = {}
	mode = Mode.PLAY
	var cname := String(db.get_card(cid).get("name", cid))
	if purpose == "ripper":
		# 〖开膛手〗：原牌进入弃牌堆，预备区扣置一张白板【陪葬品】
		_to_discard(cid)
		sp.reserve.append("token_funerary")
		sp.funerary_this_turn += 1
		_log("%s 掠夺了 %s 的一张手牌（%s 入弃牌堆），扣置一张【陪葬品】于预备区（本回合 %d/2，储存 %d/6）。" % [sp.name, tp.name, cname, sp.funerary_this_turn, _funerary_count(sp)])
	else:
		# 加入来源对应区域（当前用途均为手牌 → 手牌）
		var zone := String(token.split(":")[0])
		match zone:
			"hand":
				sp.hand.append(cid)
			"equip":
				sp.equipment.append(cid)
			"reserve":
				sp.reserve.append(cid)
			"trap":
				sp.traps.append(cid)
			_:
				sp.hand.append(cid)
		_log("%s 掠夺了 %s 的一张牌：%s 加入自己的%s。" % [sp.name, tp.name, cname, {"hand": "手牌", "equip": "装备栏", "reserve": "预备区", "trap": "陷阱区"}.get(zone, "手牌")])
		if purpose == "converge":
			tp.remove_status("electro_prism")
			_log("%s 的所有「电棱」标记被清除。" % tp.name)
	# 〖演算机器〗：目标回合外失去非【防御】牌时触发
	_notify_cards_lost(tp, [cid], "被掠夺")
	_run_deferred_prompts()

func _funerary_count(p: PlayerData) -> int:
	var n := 0
	for cid in p.reserve:
		if cid == "token_funerary":
			n += 1
	return n

# 〖演算机器〗：回合外失去区域内非【防御】的牌时，回复等量生命，并延迟弹出二选一
func _notify_cards_lost(p: PlayerData, lost_cards: Array[String], reason: String) -> void:
	if lost_cards.is_empty() or p.dead:
		return
	if not _has_skill(p, "skill_computing_machine"):
		return
	var idx := players.find(p)
	if idx == current or idx < 0:
		return  # 仅回合外触发
	var count := 0
	for cid in lost_cards:
		if not bool(db.get_card(cid).get("is_defense", false)):
			count += 1
	if count <= 0:
		return
	var old := p.hp
	_heal_with_saint(p, count)
	_log("%s 触发〖演算机器〗：回合外因%s失去 %d 张非【防御】牌，回复 %d 点生命（%d → %d）。" % [p.name, reason, count, p.hp - old, old, p.hp])
	_machine_pending.append(idx)

# 统一回复入口（带〖圣徒〗钩子）：回复生命值时摸一张牌（每回合限两次），返回实际回复量
func _heal_with_saint(p: PlayerData, amount: int) -> int:
	var old := p.hp
	p.hp = mini(p.max_hp, p.hp + amount)
	if p.hp > 0 and p.dying:
		p.dying = false
		_log("%s 脱离了「濒死」。" % p.name)
	var healed := p.hp - old
	if healed > 0 and _has_skill(p, "skill_saint") and p.saint_used < 2:
		p.saint_used += 1
		_draw_cards(p, 1)
		_log("%s 触发〖圣徒〗：回复生命值后摸一张牌（本回合 %d/2）。" % [p.name, p.saint_used])
	return healed

# 安全点（mode==PLAY 且伤害队列已空）弹出延迟询问：先〖开膛手〗掠夺，再〖演算机器〗二选一
func _run_deferred_prompts() -> void:
	if players.is_empty() or mode != Mode.PLAY or not damage_queue.is_empty():
		return
	while not _ripper_pending.is_empty():
		var item: Dictionary = _ripper_pending[0]
		_ripper_pending.remove_at(0)
		var src := int(item.get("source", -1))
		var tgt := int(item.get("defender", -1))
		if src < 0 or tgt < 0:
			continue
		var sp := players[src]
		var tp := players[tgt]
		# 弹出时校验：双方存活、目标有手牌、本回合掠夺 <2 张、储存 <6 张
		if sp.dead or tp.dead or tp.hand.is_empty():
			continue
		if sp.funerary_this_turn >= 2 or _funerary_count(sp) >= 6:
			continue
		_set_pending(PENDING_RIPPER_ASK, {"source": src, "defender": tgt, "options": ["yes", "no"]})
		mode = Mode.SKILL_PICK
		_log("%s 的【普通攻击】对 %s 造成了伤害：是否触发〖开膛手〗掠夺其一张手牌？" % [sp.name, tp.name])
		return
	while not _machine_pending.is_empty():
		var midx := _machine_pending[0]
		_machine_pending.remove_at(0)
		var mp := players[midx]
		if mp.dead:
			continue
		var opts: Array[String] = []
		if not mp.machine_draw_used:
			opts.append("draw")
		if not mp.machine_heal_used:
			opts.append("heal")
		opts.append("skip")
		if opts.size() == 1:
			continue  # 两项均已用完，不再询问
		_set_pending(PENDING_MACHINE, {"source": midx, "options": opts})
		mode = Mode.SKILL_PICK
		_log("%s 触发〖演算机器〗：请选择一项（每回合各限一次）。" % mp.name)
		return

# 〖开膛手〗询问：yes → 掠夺；no → 放弃
func _pick_ripper_ask(_p: PlayerData, _skill_id: String, token: String) -> void:
	var src := int(pending.get("source", current))
	var tgt := int(pending.get("defender", -1))
	pending = {}
	mode = Mode.PLAY
	if token != "yes" or tgt < 0:
		_log("%s 放弃〖开膛手〗的掠夺。" % players[src].name)
		_run_deferred_prompts()
		return
	_start_plunder(src, tgt, "ripper")

# 〖演算机器〗二选一：①摸一张牌；②回复 2 点生命；skip 放弃
func _pick_machine(_p: PlayerData, _skill_id: String, token: String) -> void:
	var midx := int(pending.get("source", current))
	var mp := players[midx]
	pending = {}
	mode = Mode.PLAY
	if token == "draw":
		mp.machine_draw_used = true
		_log("%s 选择〖演算机器〗①：摸一张牌。" % mp.name)
		_draw_cards(mp, 1)
	elif token == "heal":
		mp.machine_heal_used = true
		var old := mp.hp
		_heal_with_saint(mp, 2)
		_log("%s 选择〖演算机器〗②：回复 2 点生命（%d → %d）。" % [mp.name, old, mp.hp])
	else:
		_log("%s 放弃〖演算机器〗的选择。" % mp.name)
	if mode != Mode.DISCARD_PICK:
		_run_deferred_prompts()

# 元明〖电离棱体〗：弃自己区域 1 张牌 → 对一名其他玩家施加 1 层「电棱」
func _skill_ion_prism(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	var opts := _zone_card_options(p)
	if opts.is_empty():
		_log("你的区域内没有可弃掉的牌，〖电离棱体〗发动失败。")
		return true
	if _target_candidates("single_enemy", "").is_empty():
		_log("没有其他合法玩家，〖电离棱体〗发动失败。")
		return true
	_set_pending(PENDING_PRISM, {"skill_id": skill_id, "options": opts})
	mode = Mode.SKILL_PICK
	_log("〖电离棱体〗：请选择你区域中要弃掉的 1 张牌（确认目标后才真正弃置）。")
	return true

func _pick_prism(p: PlayerData, skill_id: String, token: String) -> void:
	# 参照贤者之书：pick 层只暂存不移除，目标确认后才真弃
	var cid := _take_zone_card(p, token, false)
	if cid.is_empty():
		return
	_set_pending(PENDING_PRISM_TARGET, {
		"source": current,
		"skill_id": skill_id,
		"target_type": "single_enemy",
		"prism_token": token,
	})
	mode = Mode.SELECT_TARGET
	_log("〖电离棱体〗：请选择要施加「电棱」的目标。")

# 元明〖聚合〗：掠夺带 ≥2 层「电棱」者的一张手牌并清除其所有「电棱」
func _skill_converge(_p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	var has_target := false
	for i in players.size():
		if i != current and not players[i].dead and players[i].status_layer("electro_prism") >= 2:
			has_target = true
			break
	if not has_target:
		_log("场上没有携带 ≥2 层「电棱」的玩家，〖聚合〗发动失败。")
		return true
	_set_pending(PENDING_CONVERGE_TARGET, {"source": current, "skill_id": skill_id, "target_type": "single_enemy"})
	mode = Mode.SELECT_TARGET
	_log("〖聚合〗：请选择一名携带 ≥2 层「电棱」的玩家。")
	return true

# 十修〖祝祷〗：弃 2 张牌 → 自己回 3，或为他人回复 ceil(20% 已损)+3
func _skill_prayer(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	if _zone_card_options(p).size() < 2:
		_log("你区域中的牌不足 2 张，〖祝祷〗发动失败。")
		return true
	_set_pending(PENDING_PRAYER_MODE, {"skill_id": skill_id, "options": ["self", "other"]})
	mode = Mode.SKILL_PICK
	_log("〖祝祷〗：请选择回复对象。")
	return true

func _pick_prayer_mode(p: PlayerData, skill_id: String, token: String) -> void:
	if token == "self":
		_begin_prayer_discards(p, skill_id, -1)
		return
	var candidates := _target_candidates("single_enemy", "")
	var has_other := not candidates.is_empty()
	var has_dying := false
	if not has_other:
		for i in players.size():
			if i != current and players[i].dying and not players[i].dead:
				has_dying = true
	if not has_other and not has_dying:
		_log("没有其他合法玩家，〖祝祷〗发动失败。")
		pending = {}
		mode = Mode.PLAY
		return
	_set_pending(PENDING_PRAYER_TARGET, {"skill_id": skill_id, "target_type": "single_enemy"})
	mode = Mode.SELECT_TARGET
	_log("请选择〖祝祷〗的目标（可为「濒死」角色回复）。")

func _begin_prayer_discards(p: PlayerData, skill_id: String, target_idx: int) -> void:
	var opts := _zone_card_options(p)
	if opts.size() < 2:
		_log("你区域中的牌不足 2 张，〖祝祷〗发动失败。")
		mode = Mode.PLAY
		return
	_set_pending(PENDING_PRAYER_DISCARD, {"skill_id": skill_id, "prayer_target": target_idx, "step": 1, "options": opts})
	mode = Mode.SKILL_PICK
	_log("〖祝祷〗：请选择第 1 张要弃掉的牌（共需弃 2 张）。")

func _pick_prayer_discard(p: PlayerData, skill_id: String, token: String) -> void:
	var step := int(pending.get("step", 1))
	if step == 1:
		var cid := _take_zone_card(p, token)
		if cid.is_empty():
			pending = {}
			mode = Mode.PLAY
			return
		pending["first_card"] = cid
		pending["first_zone_token"] = token  # 记录原始位置，取消时恢复
		pending["step"] = 2
		pending["options"] = _zone_card_options(p)
		_rebuild_skill_pick_immediate()
		_log("〖祝祷〗：请选择第 2 张要弃掉的牌。")
		return
	var cid2 := _take_zone_card(p, token)
	if cid2.is_empty():
		return
	var cid1 := String(pending.get("first_card", ""))
	var target_idx := int(pending.get("prayer_target", -1))
	pending = {}
	mode = Mode.PLAY
	_to_discard(cid1)
	_to_discard(cid2)
	_finalize_prayer(p, skill_id, target_idx, cid1, cid2)
	_kick_damage()

func _finalize_prayer(p: PlayerData, skill_id: String, target_idx: int, cid1: String, cid2: String) -> void:
	p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
	var n1 := String(db.get_card(cid1).get("name", cid1))
	var n2 := String(db.get_card(cid2).get("name", cid2))
	if target_idx < 0:
		var old := p.hp
		_heal_with_saint(p, 3)
		_log("%s 发动〖祝祷〗：弃 %s、%s → 自己回复 %d 点生命（%d → %d）。" % [p.name, n1, n2, p.hp - old, old, p.hp])
		return
	var t := players[target_idx]
	var amount := _ceil_pct(t.max_hp - t.hp, 20) + 3
	var old2 := t.hp
	_heal_with_saint(t, amount)
	_log("%s 发动〖祝祷〗：弃 %s、%s → %s 回复 %d 点生命（%d → %d）。" % [p.name, n1, n2, t.name, t.hp - old2, old2, t.hp])

# 瑞普〖开棺〗：将预备区 2 张【陪葬品】视作 1 张【普通攻击】打出
func _skill_open_coffin(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	if _funerary_count(p) < 2:
		_log("预备区中的【陪葬品】不足 2 张，〖开棺〗发动失败。")
		return true
	if _target_candidates("single_enemy", "").is_empty():
		_log("没有合法目标，〖开棺〗发动失败。")
		return true
	_set_pending(PENDING_COFFIN_TARGET, {"source": current, "skill_id": skill_id, "target_type": "single_enemy"})
	mode = Mode.SELECT_TARGET
	_log("〖开棺〗：将 2 张【陪葬品】视作【普通攻击】，请选择目标。")
	return true

# 瑞普〖千载幽咽〗（限定技）：指定至多 2 名其他玩家，本回合对其普攻默认 3 点灵魂伤害
func _skill_millennium(p: PlayerData, _skill: Dictionary, skill_id: String) -> bool:
	if _target_candidates("single_enemy", "").is_empty():
		_log("没有其他合法玩家，〖千载幽咽〗发动失败。")
		return true
	p.limited_used[skill_id] = true
	p.millennium_marks.clear()
	_set_pending(PENDING_MILLENNIUM_TARGET, {"source": current, "skill_id": skill_id, "target_type": "single_enemy"})
	mode = Mode.SELECT_TARGET
	_log("〖千载幽咽〗：请选择第 1 名指定目标（本回合你对其的【普通攻击】默认造成 3 点灵魂伤害）。")
	return true

func _pick_millennium_ask(_p: PlayerData, _skill_id: String, token: String) -> void:
	if token == "more":
		_set_pending(PENDING_MILLENNIUM_TARGET, {"source": current, "target_type": "single_enemy"})
		mode = Mode.SELECT_TARGET
		_log("〖千载幽咽〗：请选择第 2 名指定目标。")
		return
	pending = {}
	mode = Mode.PLAY
	_log("〖千载幽咽〗指定完成。")

# 数据驱动的弃牌堆检索：技能效果含 retrieve_defense 时先选牌
func _try_retrieve_defense(skill: Dictionary, skill_id: String) -> bool:
	for fx in skill.get("effects", []):
		for action in fx.get("actions", []):
			if String(action.get("type", "")) != "retrieve_defense":
				continue
			var options: Array[String] = []
			var seen := {}
			for cid in discard_pile:
				if String(cid) in action.get("defense_ids", []) and not seen.has(cid):
					seen[cid] = true
					options.append(String(cid))
			if options.is_empty():
				# 弃牌堆没有目标牌则发动失败，不消耗次数
				_log("弃牌堆中没有【防御1】或【防御2】，%s 发动失败。" % String(skill["name"]))
				return true
			_set_pending(PENDING_SKILL_RETRIEVE, {"skill_id": skill_id, "options": options})
			mode = Mode.SKILL_PICK
			_log("请选择一张防御牌加入手牌。")
			return true
	return false

func ui_skill_pick(token: String) -> void:
	if mode != Mode.SKILL_PICK:
		return
	var handler := String(SKILL_PICK_HANDLERS.get(_pending_kind(), ""))
	if handler == "":
		return
	var p := players[current]
	var skill_id := String(pending.get("skill_id", ""))
	call(handler, p, skill_id, token)

func _pick_retrieve(p: PlayerData, skill_id: String, token: String) -> void:
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

func _pick_fractal(p: PlayerData, skill_id: String, token: String) -> void:
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

func _pick_sage(p: PlayerData, skill_id: String, token: String) -> void:
	# 只记录要丢弃的牌，真正移除/进弃牌堆推迟到选定目标后，取消时无副作用
	var cid := _take_zone_card(p, token, false)
	if cid.is_empty():
		return
	var status_map := ["vulnerable_1", "worsen_1", "cold_1"]
	var form := clampi(p.sage_mode, 0, 2)
	_set_pending(PENDING_SAGE_TARGET, {
		"source": current,
		"skill_id": skill_id,
		"target_type": "single_enemy",
		"sage_form": form,
		"sage_status": status_map[form],
		"sage_token": token,
		"sage_card": cid,
	})
	mode = Mode.SELECT_TARGET
	_log("请选择〖贤者之书〗（形态 %s）的目标。" % ["①", "②", "③"][form])

func _pick_leap(p: PlayerData, skill_id: String, token: String) -> void:
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
	_ensure_dying_window()

func _pick_exile_ask(_p: PlayerData, _skill_id: String, token: String) -> void:
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
	_set_pending(PENDING_EXILE_TARGET, {"source": dying_idx, "target_type": "single_enemy"})
	mode = Mode.SELECT_TARGET
	_log("请选择〖放逐〗要清空的目标。")

# 古卢〖仁慈〗：lose_hp = 直接扣血；add_stop_sword = 自加止戈
func _pick_mercy(p: PlayerData, _skill_id: String, token: String) -> void:
	pending = {}
	if token == "lose_hp":
		_lose_hp_direct(p, 2, "〖仁慈〗选择①")
		_log("%s 选择〖仁慈〗①：失去 2 点生命。" % p.name)
	else:
		_add_status_capped(p, "stop_sword", 1, -1)
		_log("%s 选择〖仁慈〗②：对自己施加一层「止戈」。" % p.name)
	mode = Mode.PLAY
	_kick_damage()

# 判定 prompt_choice 选择器：按 choices 数组索引执行对应动作
func _pick_judge_prompt(p: PlayerData, _skill_id: String, token: String) -> void:
	var idx := int(token) if token.is_valid_int() else -1
	if idx < 0:
		pending = {}; mode = Mode.PLAY; return
	var choices: Array = pending.get("choices", [])
	if idx >= choices.size():
		pending = {}; mode = Mode.PLAY; return
	var choice: Dictionary = choices[idx]
	var src := int(pending.get("source", current))
	var tgt := int(pending.get("target", current))
	var src_name := String(pending.get("source_name", "判定"))
	pending = {}
	mode = Mode.PLAY
	_log("%s 选择：%s。" % [players[tgt].name, String(choice.get("label", token))])
	for action in choice.get("actions", []):
		_execute_action(src, action, tgt, {"source_name": src_name})
	_kick_damage()

# 奥比亚〖窥伺之眼〗：选手牌 → 选敌方目标 → 视作【窥视】进判定区
func _pick_peep_hand(p: PlayerData, skill_id: String, token: String) -> void:
	var cid := _take_zone_card(p, token)
	if cid.is_empty():
		mode = Mode.PLAY
		return
	pending = {}
	var candidates := _target_candidates("single_enemy", "")
	if candidates.is_empty():
		_log("没有合法目标，〖窥伺之眼〗发动失败。")
		p.hand.append(cid); mode = Mode.PLAY
		return
	# 注意：次数扣除推迟到 PENDING_PEEP_TARGET 确认后（避免取消浪费次数）
	_set_pending(PENDING_PEEP_TARGET, {"source": current, "target_type": "single_enemy"})
	mode = Mode.SELECT_TARGET
	pending["peep_card"] = cid
	pending["skill_id"] = skill_id
	_log("〖窥伺之眼〗：请选择要放置【窥视】的目标（确认后才消耗次数）。")

# 选牌处理器：tip_discharge 一步 / sand_bury 两步 / osc_discard 两步（副作用全部后置）
func _pick_sand_bury_hand(p: PlayerData, skill_id: String, token: String) -> void:
	var sub_kind := String(pending.get("sub_kind", ""))
	var step := int(pending.get("step", 1))

	# 尖端放电：一步选完一张手牌就走 finalize（不走两步）
	if sub_kind == "tip_discharge":
		var cid := _take_zone_card(p, token)
		if cid.is_empty():
			pending = {}; mode = Mode.PLAY; return
		pending = {}
		_to_discard(cid)  # 弃牌（仅这一次，finalize 不再弃）
		_finalize_tip_discharge(p, skill_id, cid)
		mode = Mode.PLAY; _kick_damage()
		return

	# 沙葬 / 振荡①：两步选牌（pick 层只选不做副作用）
	if step == 1:
		var cid := _take_zone_card(p, token)
		if cid.is_empty():
			pending = {}; mode = Mode.PLAY; return
		pending["first_card"] = cid
		pending["first_zone_token"] = token  # 记录原始位置，用于取消时恢复
		# 振荡①只能选手牌；沙葬可以选任何区域
		var rest: Array[String] = []
		if sub_kind == "osc_discard":
			for i in p.hand.size():
				rest.append("hand:%d" % i)
		else:
			for i in p.hand.size():
				rest.append("hand:%d" % i)
			for i in p.equipment.size():
				rest.append("equip:%d" % i)
			for i in p.reserve.size():
				rest.append("reserve:%d" % i)
		if rest.is_empty():
			# 只有一张可选牌——理论上沙葬会有更多（装备/预备），振荡①会提前 hand<2 return
			var cid1 := String(pending.get("first_card", ""))
			pending = {}
			if sub_kind == "sand_bury":
				_to_discard(cid1)
				_finalize_sand_bury(p, skill_id, cid1, "")
				mode = Mode.PLAY
				_kick_damage()
			else:
				# 振荡①：弃牌/扣次数/形态轮换全部等目标确认后再执行
				var candidates := _target_candidates("single_enemy", "")
				if candidates.is_empty():
					p.hand.append(cid1)
					_log("%s 发动〖振荡〗形态①：没有合法目标，手牌已恢复。" % p.name)
					mode = Mode.PLAY
					return
				_set_pending(PENDING_OSC_TARGET, {"source": current, "skill_id": skill_id, "first_card": cid1, "second_card": "", "target_type": "single_enemy"})
				mode = Mode.SELECT_TARGET
				_log("%s 发动〖振荡〗形态①：请选择要施加【跳过】的目标（确认后才弃牌）。" % p.name)
			return
		pending["step"] = 2
		pending["options"] = rest
		_rebuild_skill_pick_immediate()
		return

	# 步骤2：选第二张
	if step == 2:
		var cid2 := _take_zone_card(p, token)
		var cid1 := String(pending.get("first_card", ""))
		pending = {}
		if sub_kind == "osc_discard":
			# 振荡①：副作用全部在 PENDING_OSC_TARGET 确认后才执行（避免取消丢牌/次数）
			_set_pending(PENDING_OSC_TARGET, {"source": current, "skill_id": skill_id, "first_card": cid1, "second_card": cid2, "target_type": "single_enemy"})
			mode = Mode.SELECT_TARGET
			_log("%s 发动〖振荡〗形态①：已选 2 张手牌 → 请选择要施加【跳过】的目标（确认后才弃牌）。" % p.name)
			return
		# 沙葬：副作用在 pick 层就做（因为不需要选目标）
		_to_discard(cid1); _to_discard(cid2)
		_log("%s 发动〖沙葬〗：弃置了 %s 与 %s。" % [p.name, String(db.get_card(cid1).get("name", cid1)), String(db.get_card(cid2).get("name", cid2))])
		_finalize_sand_bury(p, skill_id, cid1, cid2)
		mode = Mode.PLAY; _kick_damage()

# 尖端放电最终结算（_to_discard 已在 pick 层完成）
func _finalize_tip_discharge(p: PlayerData, skill_id: String, _cid: String) -> void:
	p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
	var hit: Array[String] = []
	for other in players:
		if other.dead or other.dying:
			continue
		if other.has_status("electrified"):
			hit.append(other.name)
			_deal_damage(current, players.find(other), 2, "soul", "〖尖端放电〗")
	if hit.is_empty():
		_log("场上已无带「触电」标记的玩家，〖尖端放电〗无伤害结算。")
	else:
		var _joined_hit := ""
		for _n in hit:
			if _joined_hit != "": _joined_hit += "、"
			_joined_hit += _n
		_log("%s 发动〖尖端放电〗：对 [%s] 各造成 2 点灵魂伤害。" % [p.name, _joined_hit])
	_kick_damage()

# 沙葬最终结算：掷骰子 → AoE ceil(roll/2) 物理伤害，自己受50%
func _finalize_sand_bury(p: PlayerData, skill_id: String, _cid1: String, _cid2: String) -> void:
	p.skill_uses_left[skill_id] = int(p.skill_uses_left.get(skill_id, 1)) - 1
	var roll := randi() % 6 + 1
	var dmg := int(ceil(float(roll) * 0.5))
	_log("%s 发动〖沙葬〗：骰子掷出 %d 点 → 对全场造成 %d 点物理伤害（自身减半）。" % [p.name, roll, dmg])
	for i in players.size():
		if players[i].dead:
			continue
		var amt := dmg
		if i == current:
			amt = maxi(0, int(floor(float(dmg) * 0.5)))
		_deal_damage(current, i, amt, "physical", "〖沙葬〗")

# 辅助：选完第一张牌后立即刷新 SKILL_PICK 层
func _rebuild_skill_pick_immediate() -> void:
	mode = Mode.SKILL_PICK
	pass

# 「喧闹」：回合开始检查手牌中是否有【跳过】→ 弃所有【跳过】并摸等量
func _check_noise_on_turn_start(p: PlayerData) -> void:
	if not _has_skill(p, "skill_noise"):
		return
	var skip_count := p.hand.filter(func(c): return c == "skip").size()
	if skip_count > 0:
		var new_hand: Array[String] = []
		for c in p.hand:
			if c != "skip":
				new_hand.append(c)
			else:
				_to_discard(c)
		p.hand = new_hand
		_log("%s 触发〖喧闹〗：弃掉 %d 张【跳过】。" % [p.name, skip_count])
		_draw_cards(p, skip_count)
		_log("%s 摸了 %d 张牌（等量替代）。" % [p.name, skip_count])

# 〖星辉〗觉醒：每回合开始检查 HP≤6
func _check_star_brilliance(p: PlayerData) -> void:
	if not _has_skill(p, "skill_star_brilliance"):
		return
	if p.star_brilliance_awakened:
		return
	if p.hp <= 6:
		var old_max := p.max_hp
		p.max_hp -= 6
		p.max_hp = maxi(1, p.max_hp)
		p.hp = mini(p.max_hp, p.hp + 6)
		p.star_brilliance_awakened = true
		if not p.skill_ids.has("skill_sand_burial"):
			p.skill_ids.append("skill_sand_burial")
		_log("%s 触发〖星辉〗觉醒！生命上限 %d→%d，回复至 %d 点生命，获得〖沙葬〗。" % [p.name, old_max, p.max_hp, p.hp])

func ui_cancel_skill_pick() -> void:
	if mode != Mode.SKILL_PICK:
		return
	var kind := String(pending.get("kind", ""))
	if kind == PENDING_EXILE_ASK:
		var dying_idx := int(pending.get("dying", current))
		pending = {}
		_exile_done[dying_idx] = true
		_log("%s 放弃发动〖放逐〗。" % players[dying_idx].name)
		_finalize_dying(dying_idx)
		return
	if kind == PENDING_RIPPER_ASK:
		var src_r := int(pending.get("source", current))
		pending = {}
		mode = Mode.PLAY
		_log("%s 放弃〖开膛手〗的掠夺。" % players[src_r].name)
		_run_deferred_prompts()
		return
	if kind == PENDING_MACHINE:
		var midx := int(pending.get("source", current))
		pending = {}
		mode = Mode.PLAY
		_log("%s 放弃〖演算机器〗的选择。" % players[midx].name)
		_run_deferred_prompts()
		return
	if kind == PENDING_MILLENNIUM_ASK:
		pending = {}
		mode = Mode.PLAY
		_log("〖千载幽咽〗指定完成。")
		return
	var p := players[current]
	# 恢复被 _take_zone_card 从 hand/equip/reserve 移走的牌（避免凭空消失）
	# 流程提示：
	#   tip_discharge:   step=1 选完 1 张直接结算，无法中途取消 → 不需要恢复
	#   osc_discard:     step=1 可取消（first_card 在 SKILL_PICK）→ 需要恢复到 hand
	#                    step=2 后进入 SELECT_TARGET → 取消走 ui_cancel_target（已修）
	#   sand_bury:       step=1 可取消（first_card 在 SKILL_PICK）→ 按 zone_token 恢复
	#                    step=2 选完直接结算，无法中途取消 → 不需要恢复
	#   prayer_discard:  step=2 可取消（first_card 在 SKILL_PICK）→ 按 zone_token 恢复
	var sub_kind := String(pending.get("sub_kind", ""))
	# 只要 pending 里还存着 first_card，就说明这张牌已被 _take_zone_card 从区域移走、
	# 但副作用尚未执行（无论当前处于 step 1 还是 step 2），取消时都必须按原始区域归还。
	if pending.has("first_card") and (sub_kind == "osc_discard" or sub_kind == "sand_bury" or kind == PENDING_PRAYER_DISCARD):
		var cid_r := String(pending.get("first_card", ""))
		var zt := String(pending.get("first_zone_token", ""))
		if not cid_r.is_empty():
			if zt.begins_with("equip:"):
				p.equipment.append(cid_r)
			elif zt.begins_with("reserve:"):
				p.reserve.append(cid_r)
			else:
				p.hand.append(cid_r)
			_log("已恢复被暂存的牌 %s 到 %s。" % [String(db.get_card(cid_r).get("name", cid_r)), zt.split(":")[0] if zt != "" else "hand"])
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
	# 累计本次被弃的牌（供〖演算机器〗结算）
	var lost: Array = pending.get("lost_cards", [])
	lost.append(card_id)
	pending["lost_cards"] = lost
	var remaining := int(pending.get("count", 1)) - 1
	if remaining > 0 and not p.hand.is_empty():
		pending["count"] = remaining
		_log("还需选择 %d 张手牌弃置。" % remaining)
	else:
		var was_setup := bool(pending.get("setup", false))
		var was_turn_draw := (not was_setup) and phase == Phase.DRAW and target_idx == current and not p.dead
		var picker := String(pending.get("picker", ""))
		var lost_cards: Array[String] = []
		for c in lost:
			lost_cards.append(String(c))
		pending = {}
		mode = Mode.PLAY
		# 〖演算机器〗：回合外被他人选弃（picker=="actor"）时触发
		if picker == "actor":
			_notify_cards_lost(p, lost_cards, "被弃置")
		if was_setup:
			_process_setup_draw()
		elif was_turn_draw:
			# 己方回合摸牌阶段触发的洞悉弃牌：弃完后继续进入出牌阶段，而不是切给下一位玩家
			_enter_play_phase(p)
		else:
			_run_deferred_prompts()

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
	_set_pending(PENDING_EVENT_SHOW, {"event_id": event_id, "source": src_idx})
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
			var candidates := _target_candidates_for(src, tt, "")
			if candidates.is_empty():
				_log("没有合法目标，事件无效。")
				return
			_set_pending(PENDING_EVENT, {"source": src, "event_id": event_id, "target_type": tt})
			mode = Mode.SELECT_TARGET
			_log("请选择事件目标。")
			return
		_run_judge(event.get("judge", {}), src, t, String(event.get("name", "")))
		_kick_damage()
		return
	var tt := String(event.get("target_type", "none"))
	if tt == "single_any" or tt == "single_enemy":
		var candidates := _target_candidates_for(src, tt, "")
		if candidates.is_empty():
			_log("没有合法目标，事件无效。")
			return
		_set_pending(PENDING_EVENT, {"source": src, "event_id": event_id, "target_type": tt})
		mode = Mode.SELECT_TARGET
		_log("请选择事件目标。")
		return
	var ctx := {"source_name": String(event.get("name", ""))}
	if tt in ["all_players", "all_enemies", "all_allies", "all_others"]:
		# 多目标事件：对全部合法目标依次结算
		var candidates := _target_candidates_for(src, tt, "")
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
	# 死亡宣布在 _finalize_dying 完成；此处按队伍判定胜负（规则 6.2 / 口径 2.2）
	if mode == Mode.GAME_OVER:
		return
	var alive_teams := _alive_teams()
	winner = ""
	winner_team_id = ""
	winner_team_name = ""
	winner_members.clear()
	if alive_teams.size() == 1:
		var tid := String(alive_teams[0])
		winner_team_id = tid
		for i in players.size():
			if not players[i].dead:
				winner_members.append(players[i].name)
		if winner_members.size() == 1:
			winner = winner_members[0]
		else:
			winner_team_name = _team_name(tid)
			winner = winner_team_name
			_log("游戏结束！%s 获胜（%s）！" % [winner_team_name, "、".join(winner_members)])
			mode = Mode.GAME_OVER
			return
		mode = Mode.GAME_OVER
		_log("游戏结束！%s 获胜！" % winner)
	elif alive_teams.is_empty():
		mode = Mode.GAME_OVER
		_log("游戏结束！同归于尽。")

# ---------------- UI 辅助 ----------------

func interstitial_text() -> String:
	var p := players[current]
	var team := _team_name(p.team_id)
	var label := p.name if team.is_empty() else "%s（%s）" % [p.name, team]
	if first_turn:
		return "游戏开始，%s 先手！\n\n请 %s 开始操作。" % [label, p.name]
	return "回合交接\n\n现在由 %s 操作。" % label

# 弃牌堆公开信息：上一回合进入弃牌堆的牌名（规则 6.1）
func last_turn_discard_names() -> Array[String]:
	var out: Array[String] = []
	for cid in last_turn_discards:
		out.append(String(db.get_card(cid).get("name", cid)))
	return out
