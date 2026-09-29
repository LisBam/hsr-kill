# 阿哈时刻与欢愉技机制 — 技术设计

> 需求与验收见同目录 `prd.md`；公共架构决策见父任务 `09-30-huanyu-ahha-system/design.md`。

---

## 一、改动清单（精确落点）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `game_data/skill_definition.gd` | 新增 `joy_skill` / `performance_number` 元数据键与 5 个访问器/入口 |
| 2 | `scripts/core/ahha_moment_system.gd` | **新建**：阿哈时刻服务组件 |
| 3 | `scripts/core/match_controller.gd` | 成员与创建、回合开始前事件链收敛、完成回报、停滞自修复轻推 |
| 4 | `scripts/autoload/game_database.gd` | 新增「欢愉技」正文类型声明一致性校验 |
| 5 | `tests/ahha_moment_test.tscn` + `.gd` | **新建**：专项测试 |

---

## 二、`SkillDefinition` 扩展（改动 1）

### 新增常量

```gdscript
## “欢愉技”标签正文；只用于 GameDatabase 加载期校验正文类型声明与 joy_skill 标签是否一致，
## 运行期判定一律读取标签（与 REINCARNATION_TAG 同一口径）。
const JOY_SKILL_TAG: String = "欢愉技"
```

### 新增成员

```gdscript
## 当前技能是否为欢愉技；true 表示由阿哈时刻按参演编号依次执行，不生成主动发动按钮。
var joy_skill: bool = false

## 当前技能的参演编号；阿哈时刻按该值升序执行，编号相同时按当前回合位置起算的座次正序执行。
## 非欢愉技固定为 0，不参与任何排序。
var performance_number: int = 0
```

`_init()` 中在 `reincarnation` 之后追加（保持既有段落顺序，不插入已有逻辑中间）：

```gdscript
joy_skill = bool(_metadata.get("joy_skill", false))
_metadata["joy_skill"] = joy_skill
# 参演编号；非欢愉技强制归零，负值收敛到 0，避免内容笔误污染排序键。
performance_number = maxi(int(_metadata.get("performance_number", 0)), 0) if joy_skill else 0
_metadata["performance_number"] = performance_number
```

> `_metadata` 回写是必需的：元数据会经 `get_metadata()` 流入武将引用校验、技能栏展示、网络与回放。

### 新增访问器与执行入口

```gdscript
## 返回当前技能是否为欢愉技；阿哈时刻以此筛选参演技能。
func is_joy_skill() -> bool

## 返回参演编号；非欢愉技返回 0。
func get_performance_number() -> int

## 无副作用判断当前欢愉技能否在本轮阿哈时刻执行。
## 默认口径：是欢愉技、效果片段当前可用、且持有者存活且未离场。
func can_perform_joy_skill() -> bool

## 欢愉技在阿哈时刻的执行入口；默认空实现，具体内容文件覆盖。
## 实现者必须在本技能全部效果（含嵌套结算）结束后调用 finish_joy_skill_performance()，
## 否则阿哈时刻队列会停在当前项。
func perform_joy_skill(context: Dictionary) -> void

## 回报当前欢愉技已完整结束；由内容文件在效果成立后调用。
func finish_joy_skill_performance() -> void
```

`finish_joy_skill_performance()` 实现：

```gdscript
if host == null or not host.has_method("finish_joy_skill_performance"):
    return
host.call("finish_joy_skill_performance", owner_player_id, get_id())
```

### 正文类型声明识别（供校验使用）

新增静态方法（与 `description_declares_reincarnation_type` 同构）：

```gdscript
## 判断技能正文的类型段是否声明了“欢愉技”；只服务加载期校验，不参与运行期判定。
static func description_declares_joy_type(description: String) -> bool
```

识别口径沿用轮回技的实现方式：只看**类型段**（正文开头到第一个句号/逗号分隔的类型声明区），并排除引号内的「提及」。实现时直接复用 `DESCRIPTION_QUOTE_CHARS` 与既有辅助函数的思路，避免第二套解析规则。

**为什么加这条校验**：与 `reincarnation` 完全同构——正文写了「欢愉技」却没打标签，或打了标签正文没写，都会让「玩家看到的类型」与「运行期行为」不一致，属于必须在加载期拦住的错误。现有 144 个技能正文均不含「欢愉技」，因此该校验对存量内容零影响。

---

## 三、`AhhaMomentSystem`（改动 2）

`class_name AhhaMomentSystem extends Node`，由 `MatchController._ready()` 动态创建为子节点（照 `:680`-`:684` 的机缘模式），`process_mode = PROCESS_MODE_ALWAYS`。

### 生命周期

| 方法 | 时机 | 行为 |
|---|---|---|
| `configure(host, state, rng, enabled)` | 每局开局（`match_controller.gd:1339` 附近与机缘同批） | 先 `shutdown()`，再绑定端口、清空队列与轮状态 |
| `shutdown()` | 开局重配、放弃对局、退出对局（`:1410`、`:1525` 附近与机缘同批） | 清空全部运行时状态并把 `_enabled=false` |

### 状态字段

```gdscript
var _host: MatchController          # 权威控制器；只调用其公开端口
var _state: GameState               # 权威状态；只读
var _rng: RandomNumberGenerator     # 对局共享随机源
var _enabled: bool = false          # 本局是否启用
var _tracked_round_number: int = -1 # 已初始化概率的轮数
var _triggered_this_round: bool = false          # 本轮是否已触发
var _round_trigger_probability: float = 0.0      # 本轮锁定的触发概率
var _performance_queue: Array[Dictionary] = []   # 待执行序列，每项 {player_id, skill_id}
var _active_index: int = -1                      # 当前执行位置
var _waiting_for_barrier: bool = false           # 当前项是否只等嵌套结算屏障
var _resume_player_id: int = -1                  # 完成后要建立回合事实的角色
var _resume_starts_new_round: bool = false       # 该角色是否开启新轮
```

### 纯查询：执行序列构建

```gdscript
## 构建阿哈时刻的欢愉技执行序列；纯查询，不修改任何状态，供执行与测试共用。
func build_performance_order(trigger_player_id: int) -> Array[Dictionary]
```

算法：

```text
player_count = _state.players.size()
if player_count == 0: return []
trigger_index = _state.players.find(_state.get_player(trigger_player_id))
if trigger_index < 0: trigger_index = _state.players.find(_state.get_player(_state.current_player_id))
if trigger_index < 0: return []

entries = []
for seat_offset in range(player_count):
    seat_index = posmod(trigger_index + seat_offset, player_count)   # 正序环回
    player = _state.players[seat_index]
    if player == null or not player.alive or player.out_of_game: continue
    skills = _host.skill_instances_by_player.get(player.player_id, {})
    for skill_id in skills:
        skill = skills[skill_id]
        if skill == null or not skill.is_joy_skill() or not skill.can_perform_joy_skill(): continue
        entries.append({"player_id":player.player_id, "skill_id":skill_id,
                        "performance_number":skill.get_performance_number(),
                        "seat_order":seat_offset})

entries.sort_custom(编号升序，其次 seat_order 升序)
```

**排序稳定性**：`Array.sort_custom` 不是稳定排序，因此比较函数在「编号相同且 `seat_order` 相同」时（同一角色持有两个编号相同的欢愉技）追加第三键 `skill_id` 字典序，保证固定种子下结果可复现。

### 触发判定

```gdscript
func try_trigger_before_turn_start(turn_context: Dictionary, is_extra_turn: bool) -> bool
```

```text
if not _enabled or _state == null or _state.game_over or is_extra_turn: return false
round_number = _state.round_number
if _tracked_round_number != round_number: _initialize_round_probability(round_number)
if _triggered_this_round: return false

trigger_player_id = int(turn_context.get("player_id", -1))
queue = build_performance_order(trigger_player_id)
if queue.is_empty(): return false        # 决策：无可执行欢愉技直接跳过，且不消耗随机数

roll = _rng.randf()
_state.random_history.append({"kind":"ahha_moment_trigger_roll", "round_number":round_number,
        "player_id":trigger_player_id, "probability":_round_trigger_probability, "roll":roll})
if roll >= _round_trigger_probability: return false

_triggered_this_round = true
_performance_queue = queue
_active_index = -1
_resume_player_id = trigger_player_id
_resume_starts_new_round = bool(turn_context.get("starts_new_round", false))
_host.add_log("阿哈时刻：%d项欢愉技依次演出。" % _performance_queue.size())
_start_next_performance()
return true
```

`_initialize_round_probability(round_number)` 与机缘 `:833` **同构**（存活且未离场人数倒数），但使用自己的三个字段，不共享机缘的额度。

> **顺序要点**：`build_performance_order` 必须在 `randf()` **之前**调用，否则「候选为空」的提前返回就无法避免消耗随机数（会破坏固定种子下其他随机流程的一致性）。

### 执行与续接

```text
_start_next_performance()
  _waiting_for_barrier = false
  _active_index += 1
  while _active_index < queue.size():
      entry = queue[_active_index]
      player = _state.get_player(entry.player_id)
      if player == null or not player.alive or player.out_of_game: _active_index += 1; continue
      skill = _host.get_skill_instance(entry.player_id, entry.skill_id)
      if skill == null or not skill.can_perform_joy_skill(): _active_index += 1; continue
      skill.perform_joy_skill({"ahha_moment":true, "trigger_player_id":_resume_player_id,
                               "seat_order":entry.seat_order, "performance_number":entry.performance_number})
      return                       # 该技能可能挂起在选择上；完成时由其回调 finish_
  _complete_all()

finish_joy_skill_performance(player_id, skill_id) -> bool
  if not is_active(): return false
  entry = queue[_active_index]
  if entry.player_id != player_id or entry.skill_id != skill_id: return false
  _complete_current_performance(); return true

_complete_current_performance()
  if _host.has_nested_settlement_barrier():
      _waiting_for_barrier = true
      _host.defer_ahha_moment_resolution()      # 与 defer_opportunity_resolution 同构
      return
  _start_next_performance()

continue_after_barrier()     # 由控制器在结算栈清空 / 停滞自修复时调用
  if not is_active(): return
  if _waiting_for_barrier: _waiting_for_barrier = false
  _start_next_performance()

_complete_all()
  _performance_queue.clear(); _active_index = -1
  host.continue_after_ahha_moment(_resume_player_id, _resume_starts_new_round)
```

`is_active()` 判定：`_enabled and not _performance_queue.is_empty() and _active_index >= 0`。

**同步完成的技能**：`perform_joy_skill` 内部若没有任何选择，会在返回前同步调用 `finish_joy_skill_performance()`；此时 `_active_index` 仍指向当前项，`_start_next_performance()` 被重入。为避免递归加深，`_complete_current_performance()` 在无屏障时改为**登记下一帧/续接推进**而非直接递归（沿用机缘 `_schedule_next_effect_resolution()` 的思路），保证长队列不会形成深递归。

---

## 四、`MatchController` 改动（改动 3）

### 成员与创建

| 位置 | 改动 |
|---|---|
| `:404` 附近 | 新增 `var ahha_moment_system: AhhaMomentSystem` |
| `:680`-`:684` | `_ready()` 中照机缘模式创建子节点 |
| `:1339` 附近 | 开局配置处与机缘同批调用 `ahha_moment_system.configure(self, state, _rng, true)`（`enabled` 恒为 `true`：模式无关，「无可执行欢愉技则跳过」已保证零影响） |
| `:1410`、`:1525` | 与机缘同批调用 `shutdown()` |

### 回合开始前事件链收敛

新增私有入口：

```gdscript
## 回合开始前的统一事件链：机缘选择判定 → 阿哈时刻判定 → 建立回合事实。
## allow_opportunity / allow_ahha 用于区分“首次进入”与“某个环节结算后恢复”，避免重复判定。
func _continue_turn_start_prelude(player_id: int, starts_new_round: bool, allow_opportunity: bool, allow_ahha: bool) -> void
```

```text
if state == null or state.game_over: return
player = state.get_player(player_id)
if player == null or not player.alive or player.out_of_game: return
turn_start_context = {"stage":"round_start", "player_id":player_id, "starts_new_round":starts_new_round}
if allow_opportunity and opportunity_system != null \
   and opportunity_system.try_trigger_before_turn_start(turn_start_context, _current_turn_is_extra):
    return
if allow_ahha and ahha_moment_system != null \
   and ahha_moment_system.try_trigger_before_turn_start(turn_start_context, _current_turn_is_extra):
    return
_begin_turn_after_opportunity(player_id, starts_new_round)
```

三处调用点改为：

| 原位置 | 原内容 | 改为 |
|---|---|---|
| `:10602`-`:10607` | 组装 `turn_start_context` + 机缘判定 + `_begin_turn_after_opportunity` | `_continue_turn_start_prelude(player_id, starts_new_round, true, true)` |
| `:13086`-`:13088` | `_resume_pending_turn_after_extra_turns(...)` 之后直接 `_begin_turn_after_opportunity(...)` | `_continue_turn_start_prelude(pending_player_id, starts_new_round, false, true)` |
| `:13037` | 额外回合链结束后直接 `_begin_turn_after_opportunity(...)` | `_continue_turn_start_prelude(pending_player_id, bool(...), false, true)` |

`_begin_turn_after_opportunity` **函数名、签名、函数体均不变**；它只从「3 个直接调用方」变为「1 个调用方（prelude）」。

### 新增公开端口

```gdscript
## 阿哈时刻完成后恢复回合开始；角色可能在欢愉技中死亡或离场。
func continue_after_ahha_moment(player_id: int, starts_new_round: bool) -> void

## 登记阿哈时刻的通用续接；嵌套结算屏障清空后再推进下一项欢愉技。
func defer_ahha_moment_resolution() -> bool
```

`continue_after_ahha_moment` 与机缘 `continue_after_opportunity` 的 `before_turn_start` 分支**同构**：

```text
if state == null or state.game_over: return
player = state.get_player(player_id)
if player == null or not player.alive or player.out_of_game:
    _start_queued_or_normal_turn(state.current_player_id); return
if _resume_pending_turn_after_extra_turns(player_id, starts_new_round): return
_begin_turn_after_opportunity(player_id, starts_new_round)
```

> 阿哈时刻期间产生的额外回合同样必须立即执行（与机缘口径一致），因此沿用 `_resume_pending_turn_after_extra_turns`。

`defer_ahha_moment_resolution()` 复用既有 `_rule_continuations` 续接栈（与 `:11098` 的 `defer_opportunity_resolution` 同一机制），续接回调里调用 `ahha_moment_system.continue_after_barrier()`。

### 停滞自修复轻推

在 `:1003` 附近的软修复分支中，紧随机缘的 `continue_after_barrier()` 之后追加：

```gdscript
if ahha_moment_system != null and ahha_moment_system.is_active() \
   and event_scheduler != null and event_scheduler.get_pending_choice_requests().is_empty() \
   and not has_pending_card_choice():
    ahha_moment_system.continue_after_barrier()
    actions.append("nudge_ahha_moment_resolution")
```

---

## 五、数据流

```text
_start_turn(player_id)
   └─ _continue_turn_start_prelude(..., true, true)
        ├─ 机缘判定 ── true ─→ return ──(机缘结算完)─→ continue_after_opportunity
        │                                                  └─ prelude(..., false, true)
        └─ 阿哈时刻判定 ── true ─→ return ──(队列走完)─→ continue_after_ahha_moment
        │                                                  └─ prelude(..., false, false) 等价于直接 _begin_turn_after_opportunity
        └─ 都未触发 ─→ _begin_turn_after_opportunity
```

> 阿哈时刻结束后的恢复**不再经过 prelude**（两个 allow 都是 false），直接建立回合事实——这正是「阿哈时刻在机缘之后」的必然结果，避免了两者互相回跳。

---

## 六、测试设计（`tests/ahha_moment_test.tscn`）

沿用项目既有测试写法（自建 `MatchController`、固定种子、断言后打印 `AHHA_MOMENT_PASS`）。核心用例：

| 用例 | 断言 |
|---|---|
| 概率与每轮一次 | 锁定概率 1.0 时首名角色回合开始前触发；同一轮后续角色不再触发 |
| 与机缘独立 | 强制机缘已触发后，阿哈时刻仍可按自身概率触发；反之亦然 |
| 无可执行欢愉技跳过 | 无人持有欢愉技时 `try_trigger_before_turn_start` 返回 `false`，且 `random_history` 长度不变、`_triggered_this_round` 仍为 `false` |
| 编号升序 | 构造编号 144 与 100 的两名持有者，`build_performance_order` 首项为 100 |
| 同编号座次正序 | 两名编号相同的持有者，触发角色不同时执行顺序不同（正序断言） |
| 死亡/离场跳过 | 持有者在队列中途死亡后，其欢愉技不再出现在执行序列中 |
| 全流程贯通 | 阿哈时刻结束后该角色回合正常建立（`current_player_id` 与 `turn_number` 正确递增） |

测试需要一个**探针欢愉技**（测试内定义的最小 `SkillDefinition` 子类，声明 `joy_skill=true` 与编号），避免测试依赖真实武将内容。

---

## 七、兼容性与风险

- 所有改动都是增量；未声明 `joy_skill` 的技能行为不变。
- 因「无可执行欢愉技直接跳过」，现有全部对局中 `try_trigger_before_turn_start` 在第一行就返回 `false`，**不消耗随机数、不写状态**，因此 `opportunity_system_test` 的固定种子序列不受影响。
- 风险最高的是 `_start_turn` / `continue_after_opportunity` / `_start_queued_or_normal_turn` 三处的收敛；`phase_progression_test` 与 `event_runtime_test` 是这两处的守门测试。
- 递归风险：见「执行与续接」中「同步完成的技能」一节，必须用续接推进一步，不得直接递归。
