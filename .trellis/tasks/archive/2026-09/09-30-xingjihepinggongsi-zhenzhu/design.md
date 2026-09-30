# 技术设计：星际和平公司势力与武将真珠

## 1. 范围与分层

| 文件 | 层次 | 改动性质 | 职责 |
|---|---|---|---|
| `game_data/factions.json` | 内容 | 新增一项 | 登记星际和平公司（铜色） |
| `game_data/characters/zhenzhu.gd` | 内容 | 新增文件 | 真珠静态定义（女、3 体力、势力、两项技能） |
| `game_data/skills/buzhui.gd` | 内容 | 新增文件 | 欢愉技【补缀】：给盾 + 登记轮末扣盾 |
| `game_data/skills/jianying.gd` | 内容 | 新增文件 | 主动技【鉴映】：展示 A/B 并建立牌面视为 |
| `scripts/core/rule_timing_catalog.gd` | 核心 | 目录扩展 | 新增 `roundEnd` 时机（235→236） |
| `scripts/core/match_controller.gd` | 核心 | 流程扩展 + 新端口 | 轮末派发 `roundEnd`；新增牌面视为写入口 |
| `scripts/data/card_instance.gd` | 核心数据 | 字段与 API 扩展 | 视为时的花色点数覆写、快照与恢复 |
| `scripts/ui/card_view.gd` | 表现 | 展示扩展 | 视为横条带花色点数；角标保持实体牌面 |
| `tests/zhenzhu_mechanics_test.gd(.tscn)` | 测试 | 新增 | 势力/武将/两技能/轮末/牌面视为专项 |
| `tests/rule_timing_test.gd` | 测试 | 断言更新 | 目录数量 236、分类 `[58, ...]` |
| `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md` | 文档 | 同步 | 时机目录、势力登记、视为牌规则、数值 |

设计原则：**内容层零硬编码依赖核心新机制**——`buzhui.gd` 只依赖 `roundEnd` 这个已经登记进目录的标准时机；`jianying.gd` 只依赖 `MatchController` 上新增的公开端口。核心层不出现 `buzhui`/`jianying`/`zhenzhu` 任一字符串。

## 2. 内容层设计

### 2.1 势力登记

`game_data/factions.json` 末尾追加（与既有条目同构，字段顺序一致）：

```json
{"id":"xingjihepinggongsi","display_name":"星际和平公司","short_name":"司","color":"b87333"}
```

`GameDatabase._load_factions` 会校验 `display_name`、`short_name`、`color` 六位十六进制，缺一即写 `validation_errors`。铜色 `b87333` 满足校验。

`CardGallerySort.CHARACTER_FACTION_ORDER` 是「需求指定优先顺序」，未登记势力自动落入末尾分组并按势力名排序，**本次不需要修改该常量**（新增势力不是需求指定优先势力）。

### 2.2 武将真珠

`game_data/characters/zhenzhu.gd` 复用现有武将模板（`super({...}, [SKILL_SCRIPTS])`）：

- `id = "zhenzhu"`、`display_name = "真珠"`、`gender = "female"`、`faction = "xingjihepinggongsi"`、`max_hp = 3`。
- 技能脚本顺序为 `buzhui.gd`（欢愉技，显示在前）与 `jianying.gd`（主动技）。
- 无领袖技：真珠不进入领袖候选池，`smoke_test` 的 `leader_candidates.size() == 5` 断言不受影响。
- 插画/阵亡语音缺失走统一占位与静默路径，不写校验错误（内容制作指南「武将插画自动定位」段已约定），本任务不产出素材。

### 2.3 【补缀】技能设计（`game_data/skills/buzhui.gd`）

静态定义（`build_definition()` 返回的字典）：

| 字段 | 值 | 说明 |
|---|---|---|
| `id` | `buzhui` | 拼音小写稳定 ID |
| `display_name` | `补缀` | |
| `description` | 需求原文（逐字） | 含「欢愉技，参演编号104」 |
| `trigger` | `passive` | 欢愉技由阿哈时刻驱动，不生成主动按钮 |
| `joy_skill` | `true` | 欢愉技标记 |
| `performance_number` | `104` | 参演编号 |

顶部常量（全部带注释）：

- `PERFORMANCE_NUMBER: int = 104`（与静态定义共用同一常量，避免两处硬编码分叉）。
- `MIN_TARGET_COUNT: int = 0` / `MAX_TARGET_COUNT: int = 3`：原子牌「至多三名角色」→ 选择 0~3 名。
- `SHIELD_GRANT_AMOUNT: int = 1` / `SHIELD_LOSS_AMOUNT: int = 1`：正文「各获得1点护盾」「各失去1点护盾」。
- `TARGET_CHOICE_KIND: String = "buzhui_target"`：目标选择请求上下文 kind，供 AI 与自校验定位。
- `ALLOW_TARGET_CANCEL: bool = false`：欢愉技强制发动，窗口不提供取消按钮。
- `AI_FRIENDLY_SHIELD_VALUE: float = 1.6`：友方获得 1 点护盾的正收益基准。
- `AI_FRIENDLY_MISSING_HP_WEIGHT: float = 0.8`：每点已损失体力追加的优先级权重（对应「血量较少的友方」）。
- `AI_SELF_SHIELD_DISCOUNT: float = 0.85`：自己已经完整时略低于真实残血队友。
- `AI_HOSTILE_SHIELD_VALUE: float = -1.2`：给敌方护盾的负收益。

流程（`perform_joy_skill(context)`）：

1. 取 `target_ids`（阿哈时刻或测试直传）；缺失时按 `request_target_selection` 走标准目标选择（`resolver.host` 端口），候选为**存活且未离场的全部角色**（含自己）。
2. 目标去重、截断到 `MAX_TARGET_COUNT`，过滤越界/无效 ID。
3. 逐名 `get_skill_player(target_id).shield(SHIELD_GRANT_AMOUNT, get_owner_skill_player())`，实际增加量为 0 的目标不进入轮末记录（例如已经离场被端口拒绝）。
4. 仅当本次实际记录非空时，向 `_round_end_shield_records` 追加一条到期记录。
5. 调用基类 `finish_joy_skill_performance()` 回报演出结束。

轮末记录结构（纯基础值，可序列化）：

```gdscript
## 本轮各次演出登记的轮末扣盾记录；每项为 {"round_number":int,"target_ids":Array[int]}。
var _round_end_shield_records: Array = []
```

`install()` 中订阅一次轮末时机：

```gdscript
subscribe_timing("roundEnd", Callable(self, "_on_round_end"), "global", 0, false, false, Callable(), false, true)
```

- `role = "global"`：轮末不看角色匹配，只看技能持有者是否有效。
- `maintenance = true`：清理回调属于「持续效果到期」，不属于新增收益，绕过「非锁定技失效」检查（与基类注释约定的用途一致）。
- 另外覆盖 `can_trigger_while_owner_inactive(_event) -> bool: return true`：护盾的轮末到期是**已生效的持续效果清理**，不因真珠中途阵亡而失效（规则原文没有为「本轮结束时」附加持有者存活条件）。该覆盖只影响本技能订阅的 `roundEnd`，其他时机本技能不订阅。

`_on_round_end(event)`：

1. 读取结束轮数 `round_number`（`event.data` 优先，缺失回退 `host.state.round_number`）。
2. 依次取出 `round_number <= 结束轮数` 的全部记录，对每条记录中的每个目标 `get_skill_player(target_id).loseShield(SHIELD_LOSS_AMOUNT, get_owner_skill_player())`。
3. 移除已消费记录；保留轮数更大的记录（用于跨轮边界产生的极端记录）。
4. 逐条记录各扣 1 点，因此同轮两次演出命中同一角色时共扣 2 点。

死亡/离场目标不额外判断：`MatchController.change_hujia` 的扣减分支本就拒绝 `not alive / out_of_game / shield <= 0`，返回实际扣减 0，日志与事件都不产生，属于既有权威行为，技能层不重复实现。

### 2.4 【鉴映】技能设计（`game_data/skills/jianying.gd`）

静态定义：`id = jianying`、`display_name = 鉴映`、`description` 为需求原文（逐字）、`trigger = active`、`enable = phaseUse`、`ui_enabled = true`。

顶部常量：

- `CARD_CHOICE_KIND_A: String = "jianying_card_a"`、`TARGET_CHOICE_KIND: String = "jianying_target"`、`CARD_CHOICE_KIND_B: String = "jianying_card_b"`：三步请求各自的 AI 定位键。
- `CARD_SELECT_COUNT: int = 1`：A、B 各选一张。
- `TARGET_SELECT_COUNT: int = 1`：阶段 2 只选一名角色。
- `ALLOW_CANCEL_FIRST_STEP: bool = true` / `ALLOW_CANCEL_AFTER_REVEAL: bool = false`：A 未展示前可取消；展示后不可取消。
- `EQUIPMENT_CARD_TYPE: String = "equipment"`：B 为装备牌时不建立视为。
- `MIN_SHIELD_FOR_TARGET: int = 1`：目标必须「有护盾」。
- `AI_LOW_VALUE_GAP_THRESHOLD: float = 2.0`：判定「高低价值差较高」的阈值。
- `AI_SELF_UPGRADE_TARGET_VALUE: float = 3.0`、`AI_HOSTILE_TARGET_VALUE: float = 1.2`、`AI_FRIENDLY_TARGET_VALUE: float = 0.2`：三类目标的发动倾向。
- `AI_REVEAL_HOSTILE_TARGET_RESULT: float = -0.4`：向他人展示手牌属于信息外泄，身份行为观察取轻微负值。

运行时状态：

```gdscript
## 本阶段是否已发动【鉴映】；出牌阶段开始时复位，阶段内限一次。
var _used_this_play_phase: bool = false
## 本次发动已展示的手牌 A 的实体 UID；-1 表示尚未展示，用于禁止 A 之后取消。
var _revealed_material_uid: int = -1
## 本次发动已展示的手牌 A 的稳定牌名；仅用于日志与自校验。
var _revealed_material_definition_id: String = ""
```

流程（`activate(context)` → 依次 `continue_selection`，用 `context.kind` 分派）：

1. **阶段 0（前置校验）**：真珠存活在场、当前为真珠的出牌阶段、`_used_this_play_phase == false`、真珠普通手牌非空。任一不成立则返回未发动（不消耗次数）。
2. **阶段 1 选 A**：`request_card_selection`，候选为 `host.get_hand_candidates(owner_player_id, owner_player_id)`（本人视角，牌面可见），`1..1`、可取消。
   - 取消：`_used_this_play_phase` 保持 `false`，技能结束。
   - 确认：立即置 `_used_this_play_phase = true`（次数在此消费），`host.reveal_hand_card(owner_player_id, a_uid, get_id())` 公开展示 A，记录 A 的 UID 与牌名。
3. **阶段 2 选角色**：候选为「存活在场、`shield >= MIN_SHIELD_FOR_TARGET`、普通手牌非空」的角色（含真珠本人）。`request_target_selection`，`1..1`、不可取消。
   - 无合法候选：直接收尾（`announce_activation` + 结束），不建立视为效果。
   - 确认：校验所选角色仍合法，进入阶段 3。
4. **阶段 3 选 B**：`request_card_selection`，候选为 `host.get_hand_candidates(owner_player_id, chosen_target_id)`——**视角参数固定为真珠**：目标不是真珠时候选按观察者裁剪（不可见牌面，只能按位置选），目标是真珠时牌面可见。`1..1`、不可取消。
   - 无合法候选：直接收尾。
   - 确认：`host.reveal_hand_card(chosen_target_id, b_uid, get_id())` 公开展示 B。
5. **阶段 4 建立视为**：读取 B 的静态定义；若 `type != equipment`，调用
   `host.set_hand_card_view_as_with_face(owner_player_id, a_uid, b_definition_id, b_suit, b_rank, get_id())`；
   否则只写日志说明 B 为装备牌、不建立视为。
6. **收尾**：`announce_activation({"target_id":chosen_target_id, "card_uid":a_uid, "view_as_definition_id":...})`；对非本人目标调用 `observe_identity_behavior([target_id], {"target_result": AI_REVEAL_HOSTILE_TARGET_RESULT})`（只读观察，不改状态）。

次数复位：`install()` 订阅 `phaseUseBegin`（`role = "player"`），回调复位 `_used_this_play_phase`。普通出牌阶段与额外出牌阶段都会派发 `phaseUseBegin`，因此两者额度独立，与正文「出牌阶段限一次」一致。

自校验钩子：`can_activate_impl(context)` 复用阶段 0 的条件，供 UI 灰显与 AI 入参共用同一判定，避免两处逻辑分叉。

## 3. 核心机制一：真实轮末时机 `roundEnd`

### 3.1 目录扩展

`scripts/core/rule_timing_catalog.gd` 的 `GAME_PHASE_TIMINGS` 在 `enterGame` 之后、`roundStart` 之前插入 `"roundEnd"`：

```
gameStart, gameDrawBefore, gameDrawBegin, gameDrawAfter, enterGame, roundEnd, roundStart, phaseBefore, ...
```

- 语义顺序「轮末 → 轮开始」自然成立，`get_all_timing_names()` 总数 235 → **236**，分类数量 `[57,...]` → **`[58,...]`**。
- 该时机是**真实存在的独立时机**（不是别名），会被 `has_timing`/`has_active_entry`/目录校验全部识别。

### 3.2 派发点：复用既有轮末边界

现有轮末边界在 `MatchController._continue_after_phase_after`：`is_round_boundary`（回合结束且下家回到轮锚点、非额外回合）成立时，原顺序为

```
_restore_round_limited_out_of_game_players(round_number + 1) → [可选屏障延后] → _continue_round_end_after_restore → 轮末机缘 → 下一回合
```

新顺序把 `roundEnd` 插到最前：

```
[屏障则在恢复前延后] → roundEnd 派发（可暂停） → 限时离场恢复 → [屏障则延后] → 轮末机缘 → 下一回合
```

新增三个私有步骤函数与一个入口函数：

- `_begin_round_end_boundary(finished_player_id)`：以 `run_rule_sequence` 建立步骤序列，`context = {"finished_player_id": ...}`；入口先做「仍是同一结束角色且对局未结束」的守卫，避免刚结束回合的玩家已经不是当前玩家时误派发。
- `_emit_round_end_timing(sequence)`：`sequence.wait_for_timing(emit_sequence_timing(sequence, "roundEnd", finished, finished, finished, {"round_number": state.round_number, "finished_player_id": finished, "turn_number": state.turn_number}))`。
  - `state.round_number` 在此时**尚未递增**（递增发生在下一回合的 `_start_turn`），因此事件数据天然是「结束的那一轮」。
  - 用 `emit_sequence_timing` 而非 `_emit_rule_timing`：前者把事件交给序列持有，处理者创建选择会暂停序列，满足「暂停前无副作用、恢复后只执行一次」的既有验收口径。
- `_restore_round_limited_players(sequence)`：执行既有的 `_restore_round_limited_out_of_game_players(state.round_number + 1)`；若恢复后出现嵌套结算屏障，用**新续接类型** `round_end_after_restore` 延后，然后 `sequence.finish()`。
- `_complete_round_end_boundary(sequence)`：调用既有 `_continue_round_end_after_restore(finished_player_id)`，进入轮末机缘或直接安排下一回合。

续接类型表与分派表同步变更：

```gdscript
const RULE_CONTINUATION_TYPES: Array[String] = [..., "round_end_restore", "round_end_after_restore", ...]

"round_end_restore":
	_begin_round_end_boundary(int(context.get("finished_player_id", -1)))
"round_end_after_restore":
	_continue_round_end_after_restore(int(context.get("finished_player_id", -1)))
```

为什么拆成两个续接类型：屏障可能出现在 `roundEnd` **之前**（原代码已有该判断分支）或**恢复之后**。前者恢复后必须从 `roundEnd` 重新开始，后者必须跳过 `roundEnd` 直接进入机缘；共用一个类型会让 `roundEnd` 被跳过或被重复派发。

### 3.3 兼容性分析

- `roundStart` 语义、`turn_start_service` 步骤顺序、`state.round_number` 递增点全部未动。
- 「直到本轮结束」的离场恢复仍在同一位置、同一轮数入参（`round_number + 1`）。
- 轮末机缘的入口与 `resume_kind = "round_end"` 未动。
- 额外回合：`is_round_boundary` 已排除额外回合，`roundEnd` 因此不派发、轮数不递增，符合 R5.5。
- 事件父节点：`emit_sequence_timing` 默认 `parent_id = -2`，沿用当前事件栈；轮末不属于任何卡牌事件，不伪造父事件。

### 3.4 备选方案与取舍

| 方案 | 结论 |
|---|---|
| 内容层自行监听 `roundStart` 清理（不改目录） | 否决：语义是「下一轮开始」，会让护盾多持续一整个回合，且轮末机缘期间护盾仍在，改变规则结果 |
| 控制器内置「轮末护盾到期」专用机制 | 否决：为核心引入具体技能概念，违背内容自包含与解耦原则 |
| 新增 `roundEnd` 目录项 + 内容层订阅（采纳） | 通用、可复用、零硬编码；其他未来技能可直接监听同一时机 |

## 4. 核心机制二：手牌视为的牌面（花色+点数）复制

### 4.1 现状与目标

现有手牌视为（`CardInstance.set_hand_view_as`）只覆写 `definition_id`，花色点数沿用实体原值——这是【药理】【亲酿】的正确口径（只换牌名）。【鉴映】要求连花色点数一起视为，且必须**被所有既有规则读取路径自动看到**（颜色筛杀、花色判定、拼点、作为材料转化其他牌时的花色聚合、虚拟牌花色继承……）。因此选择**写时覆写**而非读时派生：覆写 `suit`/`rank` 本身，让全部既有读取点零改动地读到逻辑牌面。

### 4.2 `CardInstance` 字段与 API

新增字段（全部带独立注释，沿用现有命名风格）：

```gdscript
## 本次手牌视为同时覆写的花色；空字符串表示该视为不复制花色。
var hand_view_as_original_suit: String = ""
## 本次手牌视为同时覆写的点数；0表示该视为不复制点数。
var hand_view_as_original_rank: int = 0
## 离手后仅用于展示的最近一次视为花色；-1在语义上等价于「无」。
var last_hand_view_as_suit: String = ""
## 离手后仅用于展示的最近一次视为点数；0表示无。
var last_hand_view_as_rank: int = 0
```

新增/扩展方法：

- `set_hand_view_as_with_face(view_as_definition_id, view_as_suit, view_as_rank, source_skill_id) -> bool`：
  校验新牌名存在、花色属于四种合法花色、点数在 1..13；首次建立视为时**同时快照实体定义与实体花色点数**（沿用「保留最初实体」的既有口径），随后覆写 `definition_id`、`suit`、`rank`。
- `clear_hand_view_as()`：恢复 `definition_id`、`suit`、`rank`，并把本次视为的花色点数写入 `last_hand_view_as_suit/rank`，供离手后的公共展示继续显示逻辑牌面。
- `clear_hand_view_as_presentation()`：清空 `last_hand_view_as_*`（含新增两项）。
- `to_dict()` 新增四个展示字段：
  - `presentation_original_suit` / `presentation_original_rank`：**仅当牌面覆写生效时**非空，表示实体原花色点数，供表现层保留原实体角标。
  - `view_as_suit` / `view_as_rank`：本次视为的逻辑花色点数（离手后为最近一次），供表现层拼「花色＋点数＋视为牌名」。
- `from_dict()`/`_apply_dict`：同步还原四个新字段，保证存档、网络快照与回放一致。

### 4.3 恢复时机

既有恢复点已经覆盖「离开手牌区即恢复」，无需新增调用：

- `scripts/core/card_move_resolution_service.gd`：手牌 → 非手牌（或换主人）时 `card.clear_hand_view_as()`。
- `scripts/core/match_controller.gd`：`transfer_hand_card`/`move_card` 的直接移牌路径同样调用 `clear_hand_view_as()`。
- `scripts/core/match_controller.gd`：手牌视为的回合到期清理（既有 `_hand_view_as_*` 机制）走同一 `clear_hand_view_as()`。

因为花色点数的恢复写在 `clear_hand_view_as()` 内，上述三个入口自动一起恢复，不存在只恢复牌名、遗留逻辑花色点数的中间态。

### 4.4 新公开端口（`MatchController`）

```gdscript
## 把玩家手牌设为「视为某张牌」并在同一视为中复制花色与点数；仅允许作用于该玩家手牌区的实体牌。
func set_hand_card_view_as_with_face(player_id: int, card_uid: int, view_as_definition_id: String, suit: String, rank: int, source_skill_id: String) -> bool
```

职责：定位该玩家手牌中的实体牌 → 校验新牌名与花色点数合法 → 调用 `set_hand_view_as_with_face` → 失败时不改任何状态；写规则日志（`X的手牌视为♥A【桃】直到离开手牌区。`）→ `_emit_state()` 刷新快照。不做次数、时机或目标合法性判断（那是内容层的职责）。

### 4.5 表现层（`scripts/ui/card_view.gd`）

- 角标：`_suit_rank_text` 优先取 `presentation_original_suit/rank`（实体原值），缺失时用当前 `suit`/`rank`；因此 A 的插画、底部牌名与角标全部保持实体原样。
- 视为横条：`_view_as_display_name_text` 拼装时，若 `view_as_suit` 非空，则前缀 `"花色符号 + 点数文本 + 空格"`，形成 `♥A 桃`；否则维持现状（既有【药理】【亲酿】横条文本逐字不变）。
- 信息框副标题同理带上前缀，保证悬停说明与横条一致。
- 花色符号与点数文本复用类内既有 `_suit_symbol`/点数渲染逻辑，不新增独立映射，避免两套花色符号。

### 4.6 备选方案与取舍

| 方案 | 结论 |
|---|---|
| 读时派生逻辑花色（保留实体字段，新增 `get_effective_suit()`，改造全部读取点） | 否决：读取点分散在卡牌、判定、拼点、材料聚合、AI 等多处，漏改一处即静默错误；且违反「不为同一数据写第二套逻辑」 |
| 写时覆写 `suit`/`rank` + 快照原值仅供展示（采纳） | 全部既有读取路径零改动地读到逻辑牌面；表现层用快照字段保持实体牌面 |
| 用 `color_override` 之类的既有字段间接表达 | 否决：既有字段语义是颜色覆写，无法表达点数，且会影响无关牌 |

## 5. AI 设计

### 5.1 【补缀】`score_ai_choice`

请求 kind 为 `buzhui_target` 时，按 `selected_target_ids` 累加：

- 目标是自己：`AI_FRIENDLY_SHIELD_VALUE * AI_SELF_SHIELD_DISCOUNT + 已损失体力 * AI_FRIENDLY_MISSING_HP_WEIGHT`。
- 目标是友方（`evaluator.get_attitude > 0`）：`AI_FRIENDLY_SHIELD_VALUE + 已损失体力 * AI_FRIENDLY_MISSING_HP_WEIGHT`。已损失体力越多分数越高，天然实现「队友多时优先血量较少的友方」，并让前 3 名落在残血友方上。
- 目标是敌方：`AI_HOSTILE_SHIELD_VALUE`（负分）；因此全体候选都是敌方时，AI 提交 0 名目标（空选择得分 0 高于任何负分组合）。
- 未知态度按 0 处理，不给分也不扣分，避免身份未明时乱选。

### 5.2 【鉴映】

- `append_play_phase_actions(result)`：条件成立（`can_activate` 同级判定）时追加 `use_skill` 动作，基础分取 `AI_SELF_UPGRADE_TARGET_VALUE`（自身有护盾可确定升级）或 `AI_HOSTILE_TARGET_VALUE`（对手牌不可见，收益不确定），随后由步骤 1 的材料机会成本（`evaluator.get_owned_card_value_by_uid`）扣分——与既有转化技能（【药理】）的 AI 口径一致。
- `score_ai_choice` 按 `context.kind` 分派：
  - `jianying_card_a`：`-evaluator.get_choice_card_value(...)`（优先最低价值）；当自己持有 `shield >= 1` 且手牌最高价值与候选价值之差 ≥ `AI_LOW_VALUE_GAP_THRESHOLD` 时，额外追加负分，强化「低价值 A 配高价值 B」。
  - `jianying_target`：自己 `shield >= 1` → `+AI_SELF_UPGRADE_TARGET_VALUE`；敌方能作目标 → `+AI_HOSTILE_TARGET_VALUE`；友方 → `+AI_FRIENDLY_TARGET_VALUE`；无护盾或无手牌的目标不进入候选（规则层已过滤，AI 不重复判断）。
  - `jianying_card_b`：已选角色是自己时 `+evaluator.get_choice_card_value(...)`，并对 UID 等于 `_revealed_material_uid` 的候选追加负分（避免 A 视为自己、白发动）；已选角色是他人时所有候选价值相同（不可见牌按未知资源处理），保持候选顺序稳定即可，不猜测牌面。

## 6. 契约、兼容与边界

### 6.1 序列化与回放

- `CardInstance.to_dict/from_dict` 的新增字段随既有快照通道自动进入网络同步、存档、回放与选择请求候选，无额外改造成本。
- 【补缀】的轮末记录保存在技能实例内，与既有技能运行时状态同生命周期；重连快照按既有技能状态序列化通道处理，不新增独立存档字段。

### 6.2 既有行为不回退的断言点

- 【药理】【亲酿】等既有视为牌：`set_hand_view_as` 行为逐字不变；不调用新方法时 `presentation_original_*` 与 `view_as_suit/rank` 均为空，横条文本与角标输出与改动前完全一致。
- `roundEnd` 是新增目录项，既有内容不订阅它，因此既有回归场景的事件流只多出一条无人处理的派发记录（无副作用）。
- 真珠无领袖技、无额外势力排序需求，选将/图鉴/联机的候选池与排序规则不变（新势力落入末尾分组）。

### 6.3 已知边界（不在本任务范围）

- 真珠在轮末前被换将（技能实例卸载）时，该轮已登记的轮末扣盾记录随之丢失，护盾保留到当轮结束后的下一轮；属于换将这一极端组合，不在本任务验收范围。
- 【鉴映】不能指定「手牌为空的角色」，这与正文「展示一名有护盾的角色的一张手牌B」一致，非缺陷。
- 武将插画与阵亡语音素材不产出。
