# 《天光墟纪事》数据 JSON 编写说明

本文档说明 `data/` 目录下所有 JSON 文件的编写规范。共七类数据：卡牌、技能、状态、属性、角色、事件、装备组合。

---

## 一、卡牌（cards.json）

### 1.1 顶层结构

```json
{
  "cards": [
    { /* 卡牌1 */ },
    { /* 卡牌2 */ }
  ],
  "deck_composition": {
    "card_id_a": 5,
    "card_id_b": 3
  }
}
```

- `cards`：所有卡牌定义数组。
- `deck_composition`：抽牌堆构成，键为卡牌 ID，值为数量。

### 1.2 卡牌通用字段

| 字段              | 必填 | 类型                   | 说明                                                      |
| ----------------- | ---- | ---------------------- | --------------------------------------------------------- |
| `id`            | 是   | string                 | 唯一标识，不可重复                                        |
| `name`          | 是   | string                 | 显示名称，**用【】括起**，如 `"【普通攻击】"`     |
| `type`          | 是   | string                 | 卡牌大类，见 1.4                                          |
| `subtype`       | 否   | string                 | 子类型，如 `attack`、`defense`、`weapon`、`armor` |
| `description`   | 是   | string                 | 卡牌描述文本，支持 `\n` 换行                            |
| `target_type`   | 是   | string                 | 目标选择方式，见 1.3                                      |
| `effects`       | 是   | Array                  | 效果数组，打出时触发                                      |
| `tags`          | 否   | Array<string></string> | 标签数组，如 `["attack", "basic"]`                      |
| `is_defense`    | 否   | bool                   | 是否为防御牌                                              |
| `defense_value` | 否   | int                    | 防御点数                                                  |
| `_deck_count`   | 否   | int                    | ※ 抽牌堆中数量（编辑器辅助字段）                         |

### 1.3 目标类型（target_type）

| 值                | 说明                                   | 结算方式           |
| ----------------- | -------------------------------------- | ------------------ |
| `none`          | 无需目标                               | 直接执行 effects   |
| `self`          | 以自己为目标                           | 自动对自己结算     |
| `single_any`    | 任意单体（含自己）                     | 进入选择模式       |
| `single_enemy`  | 任一其他存活玩家（不含自己；**含队友**） | 进入选择模式       |
| `self_or_dying` | 自己或濒死者（食物牌）                 | 进入选择模式       |
| `all_players`   | **所有存活玩家（含自己）**       | 自动对所有目标结算 |
| `all_enemies`   | **所有非同队存活玩家（不含自己）** | 自动对所有目标结算 |
| `all_allies`    | **所有同队存活玩家（含自己）** | 自动对所有目标结算 |
| `all_others`    | **除自己外的所有存活玩家**       | 自动对所有目标结算 |

> `all_*` 多目标类型打出后**自动对所有合法目标结算**，不进入选择模式。

> 队伍由板子（boards.json）的 `seats` 决定，同一局内固定，见 7. 板子。1v1 板子中每名玩家各成一队，此时 `all_enemies` 与 `all_others` 等价、`all_allies` 只含自己。
>
> 口径：单体目标的 `single_enemy` 只排除自己和已死亡/濒死角色，**不会排除队友**；卡牌/技能描述没有写「敌方」时，选中队友是合法行为。

### 1.4 卡牌大类（type）

| 值                 | 结算方式                                                     |
| ------------------ | ------------------------------------------------------------ |
| `basic`          | 普通牌，打出后执行 effects。防御牌在出牌阶段点击直接进预备区 |
| `special_attack` | 特殊攻击，打出后执行 effects（一般含伤害动作）               |
| `food`           | 食物牌，仅在响应阶段打出，或用于濒死救援                     |
| `equipment`      | 装备牌，打出后直接装备到身上，触发 passive 效果              |
| `trap`           | 陷阱牌，打出后布置到陷阱区，按 `trap_trigger` 触发         |
| `delayed_judge`  | 延时判定牌，打出后进入目标预备区，判定阶段按 `judge` 判定  |

### 1.5 效果系统（effects）

```json
{
  "effects": [
    {
      "trigger": "on_play",
      "actions": [
        {
          "type": "deal_damage",
          "target": "selected",
          "value": 3,
          "damage_type": "physical"
        }
      ]
    }
  ]
}
```

- `trigger`：触发时机
  - `on_play`：打出时（卡牌）
  - `on_use`：使用时（主动技能）
  - `on_game_start`：游戏开始时（开场技能）
  - `on_trap`：陷阱触发时
- `actions`：动作数组，按顺序执行

**支持的动作类型：**

| 动作                    | 字段                                    | 说明                                                         |
| ----------------------- | --------------------------------------- | ------------------------------------------------------------ |
| `deal_damage`         | `value`, `damage_type`, `target`  | 对目标造成伤害                                               |
| `heal`                | `value`, `target`                   | 治疗目标（仅可加到满血）                                     |
| `draw_cards`          | `value`, `target`                   | 目标摸指定数量牌                                             |
| `add_status`          | `status_id`, `duration`, `target` | 给目标挂载状态效果，`duration` 为持续回合数（`-1` 永久） |
| `remove_status`       | `status_id`, `target`               | 移除目标身上的指定状态                                       |
| `discard_cards`       | `value`, `target`                   | 目标随机弃置指定数量手牌                                     |
| `discard_target_pick` | `value`, `target`                   | 让**目标（被弃牌者）自选**弃置手牌（弹出选择界面）     |
| `random_discard`      | `value`, `target`                   | 目标随机弃置手牌（由其他玩家发动）                           |
| `lose_hp`             | `value`, `target`                   | 目标直接失去生命（不受防御/装备影响，扣至 0 触发濒死）       |
| `trigger_event`       | `target`                              | 从特殊事件牌堆抽一张并执行                                   |
| `retrieve_defense`    | `target`                              | 从弃牌堆中选择一张防御牌加入手牌（无则不生效）               |

### 1.6 伤害类型（damage_type）

| 类型          | 说明                                                      |
| ------------- | --------------------------------------------------------- |
| `physical`  | 物理伤害，可被防御/装备减免                               |
| `magical`   | 法术伤害，可被防御/装备减免                               |
| `soul`      | 灵魂伤害，可被防御/装备减免                               |
| `hp_loss`   | **生命流失**，直接扣血，**不受防御/装备影响** |

> 灵魂伤害与生命流失的区别：灵魂伤害可被响应减免，生命流失直接扣血不可减免。

### 1.7 专属字段

**装备（equipment）** 需要 `passive` 字段（与属性被动共用同一套通用被动格式，详见 4.4 节）：

```json
"passive": {
  "hook": "on_outgoing_damage",
  "conditions": {"damage_type": "physical"},
  "effect": {"type": "damage_bonus", "value": 1}
}
```

**陷阱（trap）** 需要 `trap_trigger` 字段：

```json
"trap_trigger": {
  "card_tag": "attack",
  "event": "play_card"
}
```

**延时判定（delayed_judge）** 需要 `judge` 字段：

```json
"judge": {
  "method": "draw",
  "condition": "is_basic",
  "success_actions": [
    {"type": "deal_damage", "target": "selected", "value": 2, "damage_type": "physical"}
  ],
  "fail_actions": []
}
```

判定条件（`condition`）：

- `is_basic`：摸牌判定，若为基础牌则触发成功
- `is_attack`：摸牌判定，若为攻击牌则触发成功
- `is_defense`：摸牌判定，若为防御牌则触发成功

### 1.8 卡牌示例

**多目标伤害卡：**

```json
{
  "id": "firestorm",
  "name": "【烈焰风暴】",
  "type": "special_attack",
  "subtype": "attack",
  "description": "对所有敌人造成2点法术伤害。",
  "target_type": "all_enemies",
  "effects": [
    {
      "trigger": "on_play",
      "actions": [
        {
          "type": "deal_damage",
          "target": "selected",
          "value": 2,
          "damage_type": "magical"
        }
      ]
    }
  ],
  "tags": ["attack"],
  "is_defense": false,
  "defense_value": 0
}
```

**状态类特殊攻击：**

```json
{
  "id": "ignite",
  "name": "【点燃】",
  "type": "special_attack",
  "subtype": "attack",
  "description": "给目标挂上「燃烧」（接下来两个回合开始时失去2点生命）。",
  "target_type": "single_enemy",
  "effects": [
    {
      "trigger": "on_play",
      "actions": [
        {
          "type": "add_status",
          "target": "selected",
          "status_id": "burn",
          "duration": 2
        }
      ]
    }
  ],
  "tags": ["attack"],
  "is_defense": false,
  "defense_value": 0
}
```

**混合伤害卡（分次独立响应）：**

```json
{
  "id": "twin_edge",
  "name": "【双刃】",
  "type": "special_attack",
  "subtype": "attack",
  "description": "对目标造成2点物理伤害+1点法术伤害（分次独立响应）。",
  "target_type": "single_enemy",
  "effects": [
    {
      "trigger": "on_play",
      "actions": [
        {
          "type": "deal_damage",
          "target": "selected",
          "value": 2,
          "damage_type": "physical"
        },
        {
          "type": "deal_damage",
          "target": "selected",
          "value": 1,
          "damage_type": "magical"
        }
      ]
    }
  ],
  "tags": ["attack"],
  "is_defense": false,
  "defense_value": 0
}
```

---

## 二、技能（skills.json）

### 2.1 顶层结构

```json
{
  "skills": [
    { /* 技能1 */ },
    { /* 技能2 */ }
  ]
}
```

### 2.2 技能字段

| 字段                  | 必填 | 类型   | 说明                                            |
| --------------------- | ---- | ------ | ----------------------------------------------- |
| `id`                | 是   | string | 唯一标识                                        |
| `name`              | 是   | string | 显示名称，**用〖〗括起**                  |
| `skill_type`        | 是   | string | 技能类型：`active` / `opening` / `locked` / `limited` / `switch` |
| `description`       | 是   | string | 技能描述                                        |
| `max_uses_per_turn` | 否   | int    | 每回合使用次数上限（`0` 无限制）              |
| `target_type`       | 是   | string | 同卡牌目标类型，支持多目标                      |
| `effects`           | 否   | Array  | 主动/开场技能的效果数组                         |

### 2.3 技能类型说明

| 类型        | 说明                                                                                           |
| ----------- | ---------------------------------------------------------------------------------------------- |
| `active`  | 主动技能。出牌阶段显示为按钮，点击发动。效果在 `effects` 中定义                              |
| `opening` | 开场技能。游戏开始时自动触发。效果在 `effects` 中定义                                        |
| `locked`  | 锁定技（被动）。不出现在按钮栏，`effects` 通常为空。引擎按 `skill_id` 硬编码实现其被动效果 |

> 锁定技无触发次数限制（`max_uses_per_turn` 设为 `0`），属于被动技能。

### 2.4 技能示例

```json
{
  "id": "skill_false_step",
  "name": "〖失足之幸〗",
  "skill_type": "active",
  "description": "出牌阶段限1次。当你的生命值≥20时，你可以失去4点生命并选择一名其他玩家，令其回复3点生命。",
  "max_uses_per_turn": 1,
  "target_type": "single_enemy",
  "effects": [
    {
      "trigger": "on_use",
      "actions": [
        {
          "type": "lose_hp",
          "target": "self",
          "value": 4
        },
        {
          "type": "heal",
          "target": "selected",
          "value": 3
        }
      ]
    }
  ]
}
```

```json
{
  "id": "skill_hope",
  "name": "〖希冀〗",
  "skill_type": "opening",
  "description": "开场技。你失去8点生命，并摸2张牌。",
  "max_uses_per_turn": 0,
  "target_type": "none",
  "effects": [
    {
      "trigger": "on_game_start",
      "actions": [
        {
          "type": "lose_hp",
          "target": "self",
          "value": 8
        },
        {
          "type": "draw_cards",
          "target": "self",
          "value": 2
        }
      ]
    }
  ]
}
```

---

## 三、状态效果（statuses.json）

### 3.1 顶层结构

```json
{
  "statuses": [
    { /* 状态1 */ },
    { /* 状态2 */ }
  ]
}
```

### 3.2 状态字段

| 字段            | 必填 | 类型   | 说明                                              |
| --------------- | ---- | ------ | ------------------------------------------------- |
| `id`          | 是   | string | 唯一标识，卡牌/技能通过此 ID 引用状态             |
| `name`        | 是   | string | 显示名称，**用「」括起**，如 `"「燃烧」"` |
| `description` | 是   | string | 状态效果描述                                      |
| `duration`    | 是   | int    | 持续回合数，`-1` 表示永久                       |
| `trigger`     | 是   | string | 触发时机                                          |
| `effects`     | 是   | Array  | 触发时执行的动作数组，格式同卡牌 effects          |

### 3.3 触发时机（trigger）

| 值                  | 说明                   |
| ------------------- | ---------------------- |
| `on_turn_start`   | 回合开始时触发         |
| `on_damage_taken` | 受到一次伤害后触发（如「易伤1」） |
| `on_play_card`    | 打出一张手牌时触发（如「恶化1」） |
| `on_deal_damage`  | 造成伤害时触发，可减伤（如「寒冷1」） |
| `on_attack`       | 攻击时触发（预留）     |
| `none`            | 无自动触发（如「猩红」「皎白」「玄暗」） |

### 3.4 状态示例

```json
{
  "id": "burn",
  "name": "「燃烧」",
  "description": "接下来两个回合开始时失去2点生命。",
  "duration": 2,
  "trigger": "on_turn_start",
  "effects": [
    {
      "type": "lose_hp",
      "value": 2
    }
  ]
}
```

---

## 四、属性（attributes.json）

### 4.1 顶层结构

属性系统分为两套可互相自由组合的派系，每个角色从两派系中各选 1 个属性（共 2 个属性，16 种组合）。

```json
{
  "factions": [
    { "id": "faction_a", "name": "派系一（时间·生命·臆想·粒子）" },
    { "id": "faction_b", "name": "派系二（空间·冥暗·混沌·信息）" }
  ],
  "attributes": [
    { /* 属性1 */ },
    { /* 属性2 */ }
  ]
}
```

### 4.2 派系字段（factions）

| 字段   | 必填 | 类型   | 说明                     |
| ------ | ---- | ------ | ------------------------ |
| `id`   | 是   | string | 派系唯一标识             |
| `name` | 是   | string | 派系显示名称             |

### 4.3 属性字段（attributes）

| 字段          | 必填 | 类型   | 说明                                   |
| ------------- | ---- | ------ | -------------------------------------- |
| `id`          | 是   | string | 唯一标识                               |
| `name`        | 是   | string | 属性名称，**用〈〉括起**，如 `"〈时间〉"` |
| `faction`     | 是   | string | 所属派系 ID，必须是 `factions` 中的一项 |
| `description` | 是   | string | 属性效果描述                           |
| `passive`     | 否   | Object | 被动效果配置（数据驱动，格式见 4.4）   |

### 4.4 通用被动效果（passive）

装备牌（cards.json）、属性（attributes.json）与装备组合（combos.json）共用同一套通用被动格式，**新增类似机制只需配置 JSON，无需修改代码**。

```json
"passive": {
  "hook": "on_outgoing_damage",
  "conditions": {
    "card_id": "basic_attack",
    "damage_type": "physical",
    "first_attack_this_turn": true
  },
  "effect": {"type": "damage_bonus", "value": 1},
  "max_uses_per_turn": 1
}
```

| 字段                  | 必填 | 说明                                                                                                               |
| --------------------- | ---- | ------------------------------------------------------------------------------------------------------------------ |
| `hook`              | 是   | 触发时机：`on_outgoing_damage`（自己造成伤害时）、`on_incoming_damage`（自己受到伤害时，仅装备于防守方时生效） |
| `conditions`        | 否   | 触发条件，全部满足才生效，省略则无条件                                                                             |
| `effect`            | 是   | 效果配置                                                                                                           |
| `max_uses_per_turn` | 否   | 每回合最多触发次数，省略或 0 表示不限次数                                                                          |

**conditions 可用条件：**

| 条件                       | 说明                                                        |
| -------------------------- | ----------------------------------------------------------- |
| `card_id`                | 仅限指定卡牌触发（如 `"basic_attack"`）                   |
| `damage_type`            | 仅限指定伤害类型触发：`physical` / `magical` / `soul` |
| `first_attack_this_turn` | `true` 时仅限本回合打出的第一张【普通攻击】触发           |
| `allow_hp_loss`          | `true` 时生命流失也可触发（默认生命流失不触发任何被动）   |

**effect 可用效果：**

| type             | 说明                           | value 取值                                                                              |
| ---------------- | ------------------------------ | --------------------------------------------------------------------------------------- |
| `damage_bonus` | 伤害加减（正数加伤、负数减伤） | 固定数值，或 `"per_attack_used_this_turn"`（本回合已打出普攻数-1），可配 `max` 上限 |
| `heal`         | 伤害来源回复生命               | 固定数值                                                                                |

**示例 1：刻耳柏洛斯的怨恨（装备武器）** —— 每打出过一张【普通攻击】，接下来的【普通攻击】伤害+1，至多3层：

```json
"passive": {
  "hook": "on_outgoing_damage",
  "conditions": {"card_id": "basic_attack", "damage_type": "physical"},
  "effect": {"type": "damage_bonus", "value": "per_attack_used_this_turn", "max": 3}
}
```

**示例 2：〈生命〉（属性）** —— 造成魔法伤害时回复1点生命，每回合至多1次：

```json
"passive": {
  "hook": "on_outgoing_damage",
  "conditions": {"damage_type": "magical"},
  "effect": {"type": "heal", "value": 1},
  "max_uses_per_turn": 1
}
```

**示例 3：铁木甲（装备防具）** —— 受到的物理伤害-1：

```json
"passive": {
  "hook": "on_incoming_damage",
  "conditions": {"damage_type": "physical"},
  "effect": {"type": "damage_bonus", "value": -1}
}
```

### 4.5 属性示例

```json
{
  "id": "time",
  "name": "〈时间〉",
  "faction": "faction_a",
  "description": "派系一属性：时间。具体效果待补充。"
}
```

```json
{
  "id": "chaos",
  "name": "〈混沌〉",
  "faction": "faction_b",
  "description": "派系二属性：混沌。具体效果待补充。",
  "passive": {
    "hook": "on_outgoing_damage",
    "conditions": {"damage_type": "soul"},
    "effect": {"type": "damage_bonus", "value": 1},
    "max_uses_per_turn": 1
  }
}
```

---

## 五、角色（characters.json）

### 5.1 顶层结构

```json
{
  "characters": [
    { /* 角色1 */ },
    { /* 角色2 */ }
  ]
}
```

### 5.2 角色字段

| 字段            | 必填 | 类型                   | 说明                                               |
| --------------- | ---- | ---------------------- | -------------------------------------------------- |
| `id`            | 是   | string                 | 唯一标识                                           |
| `name`          | 是   | string                 | 角色名称                                           |
| `max_hp`        | 是   | int                    | 基础生命上限                                       |
| `draw_limit`    | 是   | int                    | **摸牌数值**。摸牌阶段手牌补足目标数量       |
| `hand_limit`    | 是   | int                    | **存牌数值**。弃牌阶段手牌上限，超过需弃置   |
| `attribute_ids` | 是   | Array<string></string> | 两个属性 ID，**两个派系各 1 个**，如 `["time", "chaos"]` |
| `skill_ids`     | 是   | Array<string></string> | 技能 ID 列表，如 `["skill_perceive", "skill_hope"]` |

### 5.3 角色示例

```json
{
  "id": "char_wuling",
  "name": "伍灵",
  "max_hp": 20,
  "draw_limit": 5,
  "hand_limit": 3,
  "attribute_ids": ["time", "chaos"],
  "skill_ids": ["skill_perceive"]
}
```

---

## 六、事件（events.json）

### 6.1 顶层结构

```json
{
  "events": [
    { /* 事件1 */ },
    { /* 事件2 */ }
  ],
  "event_deck": ["event_id_a", "event_id_b"]
}
```

- `events`：所有事件定义数组
- `event_deck`：特殊事件牌堆构成，列出事件 ID

### 6.2 事件字段

| 字段            | 必填 | 类型   | 说明                           |
| --------------- | ---- | ------ | ------------------------------ |
| `id`          | 是   | string | 唯一标识                       |
| `name`        | 是   | string | 显示名称，**用『』括起** |
| `description` | 是   | string | 事件描述                       |
| `target_type` | 是   | string | 同卡牌目标类型                 |
| `effects`     | 是   | Array  | 效果数组                       |
| `judge`       | 否   | Object | 判定配置（同延时判定卡）       |

### 6.3 事件示例

```json
{
  "id": "event_plague",
  "name": "『瘟疫』",
  "description": "对所有玩家造成1点生命流失。",
  "target_type": "all_players",
  "effects": [
    {
      "trigger": "on_play",
      "actions": [
        {
          "type": "lose_hp",
          "target": "selected",
          "value": 1
        }
      ]
    }
  ]
}
```

```json
{
  "id": "event_draw",
  "name": "『全员补给』",
  "description": "所有玩家各摸1张牌。",
  "target_type": "all_players",
  "effects": [
    {
      "trigger": "on_play",
      "actions": [
        {
          "type": "draw_cards",
          "target": "selected",
          "value": 1
        }
      ]
    }
  ]
}
```

---

## 七、板子（boards.json）

板子决定一局的人数与队伍划分。选人前由启动器展示板子列表，选中后写入 `GameSession.board_id`。新增板子只需追加配置，无需改代码。

### 7.1 顶层结构

```json
{
  "boards": [
    {
      "id": "board_2v2",
      "name": "双人组队",
      "player_count": 4,
      "default": false,
      "teams": [
        { "id": "team_a", "name": "队伍A", "seats": [0, 2] },
        { "id": "team_b", "name": "队伍B", "seats": [1, 3] }
      ]
    }
  ]
}
```

### 7.2 板子字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | string | 是 | 板子唯一标识，启动器与 `GameSession` 以此选择 |
| `name` | string | 是 | 显示名，启动器按钮与选人标题使用 |
| `player_count` | int | 是 | 本局人数，决定选人次数与玩家面板数量 |
| `default` | bool | 否 | 未指定板子时的回退项，建议只让一个板子为 `true` |
| `teams` | array | 是 | 队伍列表，至少一支 |
| `teams[].id` | string | 是 | 队伍唯一标识，同队玩家共享 |
| `teams[].name` | string | 是 | 队伍显示名（面板标题、当前回合、终局文案使用） |
| `teams[].seats` | array[int] | 是 | 该队占据的座位号，范围 `0 .. player_count-1` |

### 7.3 校验规则

加载 `boards.json` 时执行，任一失败视为数据错误：

- 每个座位必须恰好被一支队伍占用，不能缺座、重复占用或越界。
- 单个板子内队伍 `id` 唯一。
- `teams` 数量少于 `player_count` 表示组队局；等于人数表示混战局。

### 7.4 座位、队伍与规则的关系

- 开局时角色与座位的映射随机，座位决定回合顺序，队伍由 `seats` 反查，因此组队局中队友组合也是随机的。
- `all_enemies` / `all_allies` 等目标类型按队伍判定（见 1.3）。
- 组队局终局显示队伍名与成员；混战局只显示玩家名。
- 当前数据编辑器不含板子分类，需直接编辑本文件；保存后重启游戏生效。

## 八、装备组合（combos.json）

### 8.1 顶层结构

```json
{
  "combos": [
    { /* 组合1 */ },
    { /* 组合2 */ }
  ]
}
```

### 8.2 组合字段

| 字段            | 必填 | 类型   | 说明                                            |
| --------------- | ---- | ------ | ----------------------------------------------- |
| `id`          | 是   | string | 唯一标识                                        |
| `name`        | 是   | string | 组合名称，建议用《》括起                        |
| `parts`       | 是   | array  | 组成装备的卡牌 ID 列表，至少 2 件               |
| `description` | 否   | string | 组合效果描述                                    |
| `passive`     | 否   | Object | 组合激活时生效的被动效果，格式同 4.4 节通用被动 |

**激活规则**：玩家装备栏中**同时拥有** `parts` 中列出的全部装备时，组合自动激活；装备被移除（如死亡清空区域）后自动失效。组合被动与装备自身被动、属性被动**叠加结算**。

### 8.3 组合示例

**《利刃铁甲》** —— 同时装备【裂片短刃】与【铁木甲】时，每回合第一张【普通攻击】额外造成1点物理伤害：

```json
{
  "id": "combo_blade_iron",
  "name": "《利刃铁甲》",
  "parts": ["eq_sword", "eq_armor"],
  "description": "同时装备【裂片短刃】与【铁木甲】时激活：你每回合打出的第一张【普通攻击】额外造成1点物理伤害。",
  "passive": {
    "hook": "on_outgoing_damage",
    "conditions": {
      "card_id": "basic_attack",
      "damage_type": "physical",
      "first_attack_this_turn": true
    },
    "effect": {"type": "damage_bonus", "value": 1}
  }
}
```

> `parts` 的装备 ID 需存在于 cards.json 且 `type` 为 `equipment`，编辑器保存时会自动校验。

---

## 九、通用注意事项

### 9.1 跨文件引用

| 引用字段          | 目标文件                               | 说明                     |
| ----------------- | -------------------------------------- | ------------------------ |
| `attribute_ids` | attributes.json                        | 角色关联属性（两派系各 1 个） |
| `skill_ids`     | skills.json                            | 角色关联技能             |
| `status_id`     | statuses.json                          | 卡牌/技能引用状态        |
| `parts`         | cards.json                             | 装备组合引用装备牌       |
| 卡牌/事件/技能 ID | cards.json / events.json / skills.json | 编辑器自动校验引用合法性 |

### 9.2 命名规范

**每类词条使用唯一专属括号，不得混用。**

| 类型       | 括号 | 示例                 |
| ---------- | ---- | -------------------- |
| 卡牌名     | 【】 | `"【普通攻击】"`   |
| 技能名     | 〖〗 | `"〖技能名〗"`       |
| 状态名     | 「」 | `"「燃烧」"`       |
| 事件名     | 『』 | `"『瘟疫』"`       |
| 装备组合名 | 《》 | `"《利刃铁甲》"`   |
| 属性名     | 〈〉 | `"〈时间〉"`       |

### 9.3 特殊机制说明

**濒死保护**：任何将角色生命值降至 0 或以下的伤害/失去生命，都会使其进入濒死状态；随后按座位顺序询问**全部存活玩家（含敌方，允许救敌方）**是否使用食物牌救援，全部放弃则死亡。

**生命流失（`hp_loss`）**：不属于伤害，不受防御/装备影响，直接扣血。扣至 0 仍触发濒死。

**防御牌**：`is_defense: true` 的牌在出牌阶段点击会直接进预备区，不执行 effects。预备区中按防御数值堆叠显示。

**混合伤害**：一张卡的效果数组中包含多个 `deal_damage` 动作，每个伤害是独立实例，对手可分别响应。

**锁定技**：`skill_type: "locked"` 不出现在技能按钮栏。`effects` 通常为空，引擎按 `skill_id` 硬编码实现其被动效果。每回合无次数限制。

**洞悉（skill_perceive）**：锁定技。你所有的摸牌行为需执行：先摸 2x 张牌，然后自选弃掉 x 张牌。（x 为本次摸牌行为需要摸牌的数量）

**装备组合（combos.json）**：`parts` 中列出的装备全部在身时自动激活，其 `passive` 与装备自身被动、属性被动叠加。装备时日志会提示组合激活。

**板子与队伍（boards.json）**：队伍归属由板子的 `seats` 决定，同一局内固定；座位在选人后随机分配，先手随机。组队局需同队全员死亡才败北，混战局最后存活者获胜；目标类型中的敌我判定见 1.3。

### 9.4 编辑器使用

- 左侧分类切换：卡牌 / 技能 / 事件 / 属性 / 角色 / 状态 / 装备组合
- 右侧表单编辑，复杂字段（效果/被动/判定）以 JSON 片段编辑并即时校验
- 保存前自动校验 JSON 语法和跨文件 ID 引用合法性
- 点击属性名、装备名、技能名、状态标签可查看详细描述

---

## 附录：动作类型速查表

| 动作类型                | 用途         | 关键字段                                |
| ----------------------- | ------------ | --------------------------------------- |
| `deal_damage`         | 造成伤害     | `value`, `damage_type`, `target`  |
| `heal`                | 治疗         | `value`, `target`                   |
| `draw_cards`          | 摸牌         | `value`, `target`                   |
| `lose_hp`             | 直接失去生命 | `value`, `target`                   |
| `add_status`          | 挂载状态     | `status_id`, `duration`, `target` |
| `remove_status`       | 移除状态     | `status_id`, `target`               |
| `discard_cards`       | 随机弃牌     | `value`, `target`                   |
| `discard_target_pick` | 自选弃牌     | `value`, `target`                   |
| `random_discard`      | 随机弃牌     | `value`, `target`                   |
| `trigger_event`       | 触发事件     | `target`                              |
| `retrieve_defense`    | 回收防御牌   | `target`                              |
