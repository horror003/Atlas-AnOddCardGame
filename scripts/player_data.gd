class_name PlayerData
extends RefCounted

## 玩家/角色数据：生命、存牌数值、手牌、状态、技能次数、各区域。
## 对应规则文档第 2 章（角色系统）与第 3.4 节（角色区域）。

var name: String = ""
var char_id: String = ""               # 所选角色 id
var team_id: String = ""               # 所属队伍 id（由板子配置决定）
var seat_index: int = 0                # 座位序号（等于 players 数组下标，一局内固定）
var attribute_ids: Array[String] = []  # 属性 id 列表（两派系各 1 个）
var max_hp: int = 20
var hp: int = 20
var hand_limit: int = 3                # 存牌数值（弃牌阶段手牌上限，默认 3）
var draw_limit: int = 5                # 摸牌数值（摸牌阶段手牌补足目标，默认 5）
var base_hand_limit: int = 3           # 角色基础存牌数值（技能动态改写前的原值）
var base_draw_limit: int = 5           # 角色基础摸牌数值
var hand: Array[String] = []           # 手牌（卡牌 id 列表）
var reserve: Array[String] = []        # 预备区：延时判定牌、提前布置的防御牌（对手可见，规则 3.4）
var equipment: Array[String] = []      # 装备栏（3 个栏位，规则 3.4）
var traps: Array[String] = []          # 陷阱区（对手仅见数量，规则 3.4）
var skill_ids: Array[String] = []      # 角色技能列表（规则 2.3：大部分角色 2 个技能）
var skill_uses_left: Dictionary = {}   # 主动技 id -> 本回合剩余使用次数

var statuses: Dictionary = {}          # 状态效果集合：状态 id -> 剩余回合数（-1 表示永久）
var status_layers: Dictionary = {}     # 状态 id -> 层数
var dying: bool = false                # 是否处于「濒死」
var dead: bool = false                 # 是否已宣布死亡
var attacks_used_this_turn: int = 0    # 本回合已打出【普通攻击】数量（被动条件判定用）
var attribute_uses_left: Dictionary = {}  # 属性被动 hook -> 本回合剩余触发次数
var scab: int = 0                      # 「痂」记录值（〖结痂〗）
var sage_mode: int = 0                 # 〖贤者之书〗当前形态 0/1/2
var limited_used: Dictionary = {}      # 限定技 id -> 是否已使用
var caged_beast_used: bool = false     # 本回合是否已触发〖困兽〗
var rhythm_used: bool = false          # 本回合出牌阶段是否已触发〖韵动〗
var guardian_seen_seq: int = -1        # 〖守御〗已触发过的卡牌实例序号
var oscillation_mode: int = 0          # 〖振荡〗当前形态 0=①弃2视作跳过 / 1=②摸2自加跳过
var star_brilliance_awakened: bool = false  # 〖星辉〗是否已觉醒（解锁沙葬）
var damage_reduction: int = 0          # 伤害减免：每次受到非生命流失伤害时等额削减（〖时钟悖论〗等）
var paradox_reduction: bool = false    # 〖时钟悖论〗减免标记：在其下个出牌阶段开始时清除
var machine_draw_used: bool = false    # 〖演算机器〗①本回合是否已选（每回合限一次）
var machine_heal_used: bool = false    # 〖演算机器〗②本回合是否已选（每回合限一次）
var saint_used: int = 0                # 〖圣徒〗本回合已触发次数（每回合限两次）
var funerary_this_turn: int = 0        # 〖开膛手〗本回合已掠夺的【陪葬品】数（每回合至多2张）
var millennium_marks: Dictionary = {}  # 〖千载幽咽〗本回合指定目标：玩家下标 -> true
var dawn_awakened: bool = false        # 溯〖黎明〗是否已觉醒（生命上限改写为100，解锁〖信仰之跃〗）
var scab_evolved: bool = false         # 溯〖蚀痕〗是否已觉醒：〖结痂〗进化（每8层痂+1/+1）并解锁〖食痂〗
var damage_immune: bool = false        # 溯〖余孽〗免疫任何伤害：在其下个出牌阶段开始时清除
var rhythm_next_boost: bool = false    # 溯〖韵动〗已消耗「镣铐」：下一张打出的牌伤害提升100%
var attack_minus_this_turn: int = 0    # 溯〖守御〗减益：本回合内使用【普通攻击】造成的伤害降低值
var guardian_rt_used: bool = false     # 溯〖守御〗本回合是否已触发（每名其他玩家的回合限一次，每回合重置）
var leap_reserve: Array[String] = []   # 溯〖跃迁〗扣置于预备区的牌（可当作手牌打出）
var own_turn_discards: Array[String] = []  # 本回合内自己弃掉的牌（溯〖嬉闹〗可选范围）

func has_status(id: String) -> bool:
	return statuses.has(id)

func add_status(id: String, duration: int = -1, layers: int = 1) -> void:
	if statuses.has(id):
		status_layers[id] = int(status_layers.get(id, 1)) + layers
		if duration >= 0:
			statuses[id] = duration
	else:
		statuses[id] = duration
		status_layers[id] = layers

func remove_status(id: String) -> void:
	statuses.erase(id)
	status_layers.erase(id)

func status_layer(id: String) -> int:
	if not statuses.has(id):
		return 0
	return int(status_layers.get(id, 1))

func consume_layer(id: String) -> void:
	## 消耗一层状态，层数归零时移除整个状态
	if not statuses.has(id):
		return
	var left := int(status_layers.get(id, 1)) - 1
	if left <= 0:
		remove_status(id)
	else:
		status_layers[id] = left

func tick_status(id: String) -> bool:
	## 回合开始时调用，剩余回合数 -1，返回是否仍需保留
	if not statuses.has(id):
		return false
	var remaining := int(statuses[id])
	if remaining < 0:
		return true  # 永久状态
	remaining -= 1
	if remaining <= 0:
		remove_status(id)
		return false
	statuses[id] = remaining
	return true

func status_ids() -> Array[String]:
	var out: Array[String] = []
	for k in statuses.keys():
		out.append(String(k))
	return out
