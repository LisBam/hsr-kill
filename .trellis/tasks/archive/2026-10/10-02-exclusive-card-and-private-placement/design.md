# 技术设计：专属锦囊牌与不可知置牌机制

对应需求：[`prd.md`](./prd.md)

---

## 一、设计目标与边界

**一句话**：在**不改动牌堆数据结构、不新增第二套选择框架、不新增公开信息通道**的前提下，让「专属牌」与「只有使用者知道的事实」成为两条正式机制，并给出「把一张手牌置于牌堆顶第 N 位」的权威端口。

三条硬约束：

1. **牌堆写入只经唯一移牌边界**。`CardMovementService` 是唯一的区域写入者；新增的「造牌入堆」端口最终也要落到它（或与它同一套 `card_moved` 增量语义）上，不能出现第二条写入路径。
2. **私有事实不得进入任何公开通道**。公开通道共四条：观察者快照、公共日志（`add_log`）、回放录制、公开表现事件。四条都必须逐一确认不泄露。
3. **不新增第二套选择框架**。位次询问必须是既有 `ChoiceRequest` 协议的一个新类型，而不是并行的一套窗口与归还逻辑。

---

## 二、命名与契约（实现后 `docs/` 必须与本节逐字对齐）

### 2.1 卡牌专属字段

| 项 | 值 |
|---|---|
| 落点 | `CardDefinition` 元数据字典（`_init()` 的 `super({...})`），**基类不需要改动**（`_metadata` 是自由字典） |
| 字段名 | `exclusive` |
| 类型 / 默认值 | `bool` / `false` |
| 语义 | `true` = 该牌**不属于任何牌堆**，只能由技能或效果在运行时按要求加入游戏；图鉴据此显示「专属」标识 |
| 读取入口 | 在 `CardDefinition` 新增纯查询 `is_exclusive() -> bool`，与既有 `requires_actor_choice()`（`card_definition.gd:181-182`）同形 |
| 不要新增 `type` 取值 | 核心多处按 `type == "trick"` 分支（`match_controller.gd:6960` 延时锦囊检索、`card_rule_service.gd:338-340`、`noname_ai_evaluator.gd:284/1413` 等），新增一个 `type` 会从这些分支漏掉 |

### 2.2 位次常量（唯一来源）

```gdscript
## 牌堆顶第一张：摸牌时最先被摸到。
const DRAW_PILE_POSITION_TOP: int = 1

## 牌堆顶第二张：摸牌时第二个被摸到。
const DRAW_PILE_POSITION_SECOND: int = 2
```

- 放在 `MatchController` 顶部常量区，**`R3` 与 `R6` 共用**，禁止在别处写字面量 `1`/`2`。
- **方向约定**：`state.draw_pile` **数组末尾为顶**（`game_state.gd:33-34`）。因此 `position == 1` → `append()`；`position == 2` → `insert(size - 1, card)`。

### 2.3 控制器端口

```gdscript
## 按卡牌定义创建一张实体牌并加入摸牌堆；返回新实体牌 UID，失败返回 -1。
## suit/rank 留空时使用本局权威随机源（_rng）取一组花色与点数，并把结果写入 random_history 以支持存档与回放复现。
func create_and_insert_card_into_draw_pile(definition_id: String, suit: String = "", rank: int = 0, position: int = DRAW_PILE_POSITION_TOP) -> int

## 把指定玩家的**手牌**置于摸牌堆顶第一张或第二张；成功返回 true。
func place_hand_card_on_draw_pile_top(player_id: int, card_uid: int, position: int) -> bool

## 主动技能侧封装好的位次询问：先选一张手牌，再选「牌堆顶第一张 / 第二张 / 取消」。
## 返回值供技能在恢复阶段读取，形状固定为 {confirmed, card_uid, position}。
func request_hand_card_pile_position(player_id: int, title: String, prompt: String, allow_cancel: bool = true, context: Dictionary = {}) -> Dictionary
```

> **`allow_cancel` / `context` 为可选补充参数**（实现期确认）：技能侧需要在恢复阶段按 `context.kind` 分流、并可能不允许取消，因此这两个参数必须可传入；它们是可选参数，`(player_id, title, prompt)` 三参数调用的名字与顺序与上表完全一致，既有调用方无需改动。

### 2.3.1 配套常量（`MatchController` 顶部常量区）

| 常量 | 值 | 用途 |
|---|---|---|
| `PILE_SLOT_OPTION_TOP` | `"pile_slot_1"` | 位次选项稳定 ID |
| `PILE_SLOT_OPTION_SECOND` | `"pile_slot_2"` | 位次选项稳定 ID |
| `PILE_SLOT_OPTION_CANCEL` | `"cancel"` | 取消选项稳定 ID（**不能**作为已确认位次提交） |
| `CARD_POSITION_CHOICE_TYPE` | `"card_position"` | 选择类型标识 |
| `CONTEXT_KEY_CONTROL_CANCEL_OPTION_ID` | `"control_cancel_option_id"` | 请求 `context` 中声明「哪个文字选项等同取消」的键。放在 `context` 而非选项字典里，是因为 `request_card_choice` 只保留 `control_options` 条目的 `id`/`label` 两个键 |
| `SECRET_PILE_PLACEMENT_REASON` | `"secret_pile_placement"` | 置牌移牌的 `reason`，仅进 `card_move_history`（不进快照、不进存档） |
| `EXCLUSIVE_CARD_INSERT_REASON` | `"exclusive_card_insert"` | 入堆端口的 `random_history` 记账 `kind` |
| `DRAW_PILE_INSERT_SUIT_POOL` | `["spade","heart","club","diamond"]` | 缺省牌面的花色池 |
| `DRAW_PILE_INSERT_RANK_MIN` / `_MAX` | `1` / `13` | 缺省牌面的点数区间 |

### 2.4 私有事实字段（`PlayerState`）

| 项 | 值 |
|---|---|
| 落点 | `scripts/data/player_state.gd`，新增独立字段（**不复用** `character_form_state`） |
| 字段名 | `private_pile_placement: Dictionary` |
| 类型 / 默认值 | `Dictionary` / `{}` |
| 键 | `card_uid: int`、`position: int`、`turn_player_id: int`、`turn_number: int` |
| 可见性 | `to_dict`：**仅当 `reveal_private` 为真且 `viewer_id == player_id` 时**写入 `private_pile_placement.duplicate(true)`；其他观察者、AI 快照、本地广播快照、局域网定向快照与权威公开观察快照（`viewer_id = -1`）一律不含该键 |
| 存档 | `from_authoritative_dict()` 补一行恢复，键缺失时按 `{}` |
| 写入 | 只允许经控制器端口 `set_private_pile_placement()` / `clear_private_pile_placement()` / `get_private_pile_placement()` |

> **可见性条件必须是 `reveal_private and viewer_id == player_id`**（实现期两次修正）：
> ①**不能只用 `reveal_private`**：全部 AI 快照都是 `state.to_dict(该AI的player_id, true)`（`match_controller.gd:3098/5941/7686/17536` 等），
> 用 `reveal_private` 判定会让**每一个 AI 都读到其他角色的置牌事实**，直接违背原文「其他角色不可知」。
> ②**也不能只用 `viewer_id == player_id`**：本地广播快照是 `state.to_dict(local_human_player_id, false)`（`match_controller.gd:17167`），
> 而该快照会被整体录制进回放（`match_table.gd::_record_replay_snapshot`），只用观察者判定会把置牌事实写进回放文件，违背原文「不出现在对局记录中」。
> 两个条件同时成立时：存档流程 `player.to_dict(player.player_id, true)`（`match_controller.gd:15042`）与技能侧权威读取都能拿到，
> 而本地广播、局域网定向快照（均为 `reveal_private=false`）与权威公开观察快照都拿不到。专项用例对全部通道分别断言。
> 权威端读取事实不依赖本方法，统一走 `get_private_pile_placement()` 直接读实体字段。

> **为什么必须新增字段而不是放进 `character_form_state`**：后者的序列化条件是 `if reveal_private else {}`（`player_state.gd:526`），因此它**既不发给持有者自己的普通快照**，又**全量发给 AI 快照**（`reveal_private=true`，`match_controller.gd:3046,3230,5867,15579…`）。用它承载「其他角色不可知」会同时违反两条：使用者看不到、AI 反而看得到。既有正确的口径先例是 `wheel_duel_lineup`（`player_state.gd:583-584`），但那个字段**不进存档**，所以本字段需要自己补 `from_authoritative_dict`。

### 2.5 新的选择类型 `card_position`

| 项 | 值 |
|---|---|
| `choice_type_override` | `"card_position"` |
| 语义 | 一个请求里**同时**选一张牌与一个文字选项（位次），两者都必须通过校验 |
| `control_options` | `[{"id":"pile_slot_1","label":"牌堆顶第一张"},{"id":"pile_slot_2","label":"牌堆顶第二张"},{"id":"cancel","label":"取消"}]` |
| 稳定选项 ID | `pile_slot_1` / `pile_slot_2` / `cancel`，集中定义为常量 |
| 卡片维度 | `min_card_select = max_card_select = 1` |
| 交互约束 | 未选牌时 `pile_slot_1` / `pile_slot_2` 不可确认；`cancel` 始终可用（提交 `confirmed = false` 时不做牌数下限校验，与既有可取消请求同口径） |

**必须同步改造的三处校验/渲染白名单**（否则表现为「点技能无反应」或「看不到按钮」）：

| # | 位置 | 改法 |
|---|---|---|
| 1 | `match_controller.gd::_submit_card_choice` 的文字选项校验 | 把 `card_position` 加入允许携带 `selected_control_id` 的白名单，并新增「位次选项必须命中 `control_options`」的校验 |
| 2 | `match_controller.gd::_submit_card_choice` 的确认分支 | `confirmed` 时：牌数必须为 1，且位次选项必须是 `pile_slot_1`/`pile_slot_2`（不接受 `cancel` 作为已确认的位次） |
| 3 | `scripts/ui/card_selection_panel.gd` | 新增 `card_position` 渲染分支 `_show_card_position_request()`：先按既有 `_add_zone_row()` 渲染手牌区，再调用新函数 `_add_position_options()` 渲染三个按钮 |

**第 3 处的实现口径（实现期确认）**：不复用 `_add_control_options()`，因为它把「点击 → `control_submitted`」写死；位次询问需要「点击位次 → `position_submitted`、点击取消 → `choice_cancelled`」两种语义。因此新增 `_add_position_options()`：它按请求 `context[CONTEXT_KEY_CONTROL_CANCEL_OPTION_ID]` 判定哪个选项是取消，**界面不硬编码任何选项 ID**。同时该分支下隐藏底部确定按钮与底部放弃按钮，使窗口上恰好只有三个按钮（与原文「询问时显示三个按钮」严格一致）；`_refresh_selection_state()` 在未恰好选中一张手牌时把两个位次按钮置为 `disabled`，取消按钮始终可用。

> 内联（inline）路径不做改造：该请求的面板形态要求同时展示手牌与按钮，交给正式的 `card_selection_panel` 更稳妥。因此**必须**把 `card_position` 加进 `match_table.gd::_is_inline_hand_choice()` 的排除列表（该列表已是 `["control","bool","target_control","card_name"]`）；`_is_inline_control_choice()` 只列 `["control","bool","target_control"]`，`card_position` 天然落空，无需改动。新增信号 `position_submitted(request_id, selected_card_uids, control_id)` 并由 `match_table.gd::_on_card_position_submitted()` 转换为标准 `choose_cards` 动作。

### 2.6 AI 侧合法动作

`_build_card_choice_actions()` 必须为 `card_position` 生成合法动作，否则 `request_card_choice()` 会因「无合法动作」直接拒绝请求，导致 AI 永远无法提交（表现为请求挂住）。实现形状：对**每张候选牌 × 每个位次选项**（`pile_slot_1` / `pile_slot_2`）各生成一个确认动作，取消动作由上方既有的 `allow_cancel` 分支统一生成。因此非可取消请求的合法动作数为 `候选牌数 × 2`，可取消请求为 `候选牌数 × 2 + 1`（专项用例按该公式断言）。

> 本任务**不实现**游丝的 AI 评分（属后续子任务），但**必须**让 AI 有可提交的合法动作，否则机制无法在纯 AI 对局中存活。

---

## 三、分层落点与依赖方向

```
scripts/data/player_state.gd          ← private_pile_placement（R4）        【状态层】
        ↑ 读写只能经控制器端口
scripts/core/match_controller.gd      ← 端口、位次语义、私有记忆、校验白名单（R3/R4/R6/R7）【规则/运行时层】
scripts/core/card_movement_service.gd ← 若需支持「指定位次」则扩展 _add_to_zone（R6）
game_data/card_definition.gd          ← is_exclusive() 纯查询（R1）
scripts/ui/card_selection_panel.gd    ← card_position 渲染分支（R7）
scripts/ui/all_cards_panel.gd         ← 专属牌标识（R1）
scripts/ui/card_view.gd               ← 牌面「专属」标签（R1）
```

- **不新增** `game_data/cards/*.gd`：本任务只提供机制，不做内容。
- **不改动** `data/decks.json`：专属牌不得进入任何牌堆（AC4）。
- **不改动** `add_log()` 签名：本机制**完全不写日志**（见 §4.3），因此不需要私密日志通道。

---

## 四、数据流

### 4.1 专属牌：定义 → 校验 → 图鉴 → 运行时入堆

```
game_data/cards/xxx.gd  super({..., "exclusive": true})
   │
   ├─ GameDatabase._load_cards()        登记（无需改注册表）
   ├─ GameDatabase._validate_decks()    只校验「牌堆→卡牌」单向；不在任何牌堆 **不报错**
   ├─ all_cards_panel._build_game_card_entries()  遍历 cards.keys() → 自动收录（无需改动即显示）
   └─ 运行时由技能调用 create_and_insert_card_into_draw_pile(definition_id, suit, rank, position)
          │
          ├─ 前置校验：对局存在且未终局 / definition_id 在卡牌表 / position ∈ {1,2}
          ├─ CardInstance.new(definition_id, suit, rank)   ← 花色点数由端口参数决定；缺省或非法时由权威随机源补全
          ├─ 经唯一移牌边界落到 draw_pile 指定位次（产生一条 card_moved 与一条移牌历史）
          ├─ random_history 记账（仅当动用了权威随机源；照 arrange_draw_pile_cards 的既有写法）
          └─ _emit_state()
```

**关键决策**：端口**不内置随机**（K5）。「随机加入三张」需花色点数随机，由调用方决定；端口接收显式的 `suit`/`rank`（或由端口内部用 `state` 的权威随机源，但必须在 `design` 中固定一处并说明复现口径）。**最终采用**：端口签名带可选 `suit`/`rank`，缺省时使用 `_rng`（权威随机源，随存档与回放复现），并把结果写入 `random_history` 以便复盘——这与既有随机内容（如判定牌）的口径一致。

### 4.2 置牌：询问 → 私有记忆 → 放置

```
技能（后续子任务）请求 request_hand_card_pile_position(player_id, ...)
   │  choice_type = "card_position"
   │  candidates = 本人的手牌
   │  control_options = [pile_slot_1, pile_slot_2, cancel]
   ▼
玩家选一张手牌 + 一个位次
   ▼
_submit_card_choice：牌 UID 命中 candidates（既有校验）+ 位次命中 control_options（新增校验）
   ▼
技能恢复阶段：
   ① set_private_pile_placement(player_id, card_uid, position, 本回合角色, 本回合号)
   ② place_hand_card_on_draw_pile_top(player_id, card_uid, position)
        ├─ 校验：该牌确实是该玩家手牌 / position ∈ {1,2} / 对局未终局
        ├─ 经唯一移牌边界：position==1 → append；position==2 → insert(size-1)
        ├─ **不写任何日志**
        └─ _emit_state()
   ▼
本回合结束时（后续子任务）：按「回合角色 + 回合号」双重匹配读私有记忆 → 检查该 UID 是否在其手牌中
```

### 4.3 「其他角色不可知」的四条通道逐一确认

| 通道 | 现状 | 本机制的口径 |
|---|---|---|
| 观察者快照 | `game_state.to_dict` 的牌堆字段只有 `draw_pile_count`（`:249`）；`player.private_pile_placement` 按 §2.4 的私有条件裁掉 | **不泄露**：他人拿到 `{}` |
| 公共日志 `add_log()` | 无 `viewer_id`，一 emit 即进局域网广播（`:16117-16119`）、界面与回放（`match_table.gd:4125`） | **完全不调用** `add_log`。既有同口径先例：`arrange_draw_pile_cards()`（`:8647-8674`）与 `get_top_draw_card_candidates()`（`:8609-8622`）全程不写日志；技能侧【洗伐】`xifa.gd:73-85` 走这两个端口也不写日志 |
| 回放录制 | `match_replay_recorder.record_log()` 不区分来源；`record_skill_activation` 会把 `context` 写进**公开快照字段** `player.skill_history`（`player_state.gd:587`）并写公开日志 | **不得**把牌 UID / 位次放进 `announce_activation` 的 `context`；放置动作既不写日志也不声明激活 |
| 公开表现事件 | `_on_card_moved`（`15404-15418`）在目标区域不是 `hand`/`discard_pile` 时**直接 return**，因此手牌→牌堆本来就不产生 `card_transfer` | **保持该早退分支**，并在实现时显式断言「放置不产生任何表现事件」 |

**残余泄露面（必须在实现中堵住，并写进文档）**：

| 面 | 风险 | 处理 |
|---|---|---|
| `_move_card_with_timings`（`15291-15385`） | 会把 `loseBefore/Begin/End/After` 派发给**所有**技能，且 `reason` 进入 `timing_data`——其他技能的触发代码可观察到「某人的手牌离区、原因是 X」 | 放置端口**直接调用 `card_movement.move_card`**，绕过时机系统；与 `_refresh_starting_hand`（`10849`）的既有做法一致 |
| `card_movement_service.card_move_history` | 记录含 `reason`/`source`/`to_zone` | 现状**不进快照**（`game_state.gd:261` 仅 count）、**不进存档**（`_build_conquest_save_data` 无该键）；在文档中明确「禁止新增可反查该历史的公开查询端口」 |
| `CardInstance.known_to` | `_update_knowledge` 对 `draw_pile` **不清理** `known_to`（只把 `private_owner_id` 置 -1） | 放置端口在移牌前显式重置该牌的 `known_to` 与展示残留（`hand_mark_tags` / 手牌视为），参照 `_prepare_hidden_pile_gain`（`7461-7468`）的反方向工具 |

---

## 五、兼容性与迁移

| 面 | 影响 | 处理 |
|---|---|---|
| 卡牌元数据 | 新增一个可选键 `exclusive` | 纯增量；缺省 `false`，既有 46 张牌行为不变 |
| `GameDatabase` 校验 | **无变化** | 已确认不做反向校验，「不在任何牌堆」现状合法 |
| `PlayerState` 序列化 | 新增一个私有字段 | 旧存档缺键 → `{}`；公开快照对他人的输出**逐字节不变**（条件为 false 时给 `{}`，与新增字段前该键不存在相比多了一个空字典键——为避免快照形状变化，**仅在非空时写入该键**） |
| `ChoiceRequest` 协议 | 新增一个 `choice_type` 取值 | 纯增量；其他类型的行为与校验路径不变 |
| 位次语义 | 复用「数组末尾为顶」 | 不改牌堆结构 |
| `CardMovementService` | 可能需要一个「按位次插入」的内部能力 | 只新增，不改既有 `append` 行为（`position == 1` 走原路径） |

### 回滚

- 代码回滚：单独 revert 本次提交即可；新字段对旧代码是未知键，新选择类型无调用方时完全静默。
- 分级回滚：只回滚 UI 分支 → 机制仍可用（AI 与规则层照常），只是人类看不到按钮。

---

## 六、权衡与已否决方案

| 方案 | 否决原因 |
|---|---|
| 在 `character_form_state` 里承载私有记忆 | 序列化条件是 `reveal_private`：持有者自己看不到，AI 反而全量看到——同时违反「使用者知道」与「其他角色不可知」 |
| 放进 `state.random_history` | 既不进快照也不进存档（`_build_conquest_save_data` 无该键），过关斩将读档后记忆丢失 |
| 放进 `skill_history` / `announce_activation` context | `skill_history` 是**公开快照字段**，直接泄露牌 UID 与位次 |
| 复用 `arrange` 选择类型表达位次 | 其 `control_id` 语义被写死为「顶行张数」，且候选必须是**牌堆中已有的牌**（`:8660-8661`），手牌会被 `return false`；表达不了第 2 张 |
| 为游丝单独做一套三按钮专用窗口 | 与既有选择/暂停/续接管线并行，必然出现两套归还逻辑与失同步 |
| 复用 `arrange_draw_pile_cards()` 实现置牌 | 硬前置「牌必须已在牌堆」，且 `top_count` 只能切顶行/底行，对单张牌只有「顶」与「底」两种结果，**表达不了第 2 位** |
| 新增 `type: "exclusive"` 而非布尔字段 | 核心多处按 `type == "trick"` 分支，新 `type` 会漏掉延时锦囊检索（`:6960`）等路径 |
| 新增私密日志通道（`add_log` 加 `viewer_id`） | 需同时改局域网逐 peer 裁剪、界面分发与回放录制三处，且本次需求完全可以「不写日志」满足；先用最严格的零日志口径，避免为一个用例扩大协议面 |
| 让 AI 读到被放置事实 | 直接违反原文「其他角色不可知」 |
| 入堆端口内置「随机 N 张」 | 规则层引入随机源会扩大存档与回放的复现口径；端口只做确定性插入，随机由调用方与权威 `_rng` 协作 |

---

## 七、验证策略

1. **专项**：新增 `tests/exclusive_card_and_private_placement_test.gd` + `.tscn`，逐条覆盖 AC1–AC17；按 `docs/界面与交互.md`「自动化测试设置隔离」保存并恢复 `GameSettings`。
2. **必须实际执行动态端口调用**（不能只查前置条件）：`create_and_insert_card_into_draw_pile()`、`place_hand_card_on_draw_pile_top()`、`request_hand_card_pile_position()` 都要真实调用一次；构造 `Array[int]` 强类型实参（见 `card-authoring.md` 4.5）。
3. **防泄露断言要全量**：执行一次秘密放置后，遍历**所有**玩家的 `to_dict(viewer, false)` 与 AI 快照，断言不含该牌 UID / 牌名 / 位次；断言 `add_log` 未被调用（可用日志条数快照对比）。
4. **位次方向断言用实际摸牌顺序**：放置两张牌到第 1/第 2 位，然后连续摸两张，断言顺序。
5. **回归**：`smoke_test`、`gameplay_regression_test`、`card_action_semantics_test`、`all_cards`（图鉴）、`ui_layout_test`、`font_color_audit_test`（若新增文本控件）、`lan_network_test` / `lan_match_flow_test`（快照形状变化敏感）。
6. **静态**：`GameDatabase.validation_errors` 必须为空。
