# 技术设计：技能按钮在发动流程中失效

## 一、边界与分层归属

| 层 | 是否改动 | 说明 |
|---|---|---|
| `scripts/ui/match_table.gd` | **改** | 唯一的实现改动点：按钮可用性判定 + 点击分支 |
| `scripts/ui/skill_button_view.gd` | 不改 | 现有 `configure(available, ...)` + `set_selected_state(selected)` 已足以表达"禁用但选中" |
| `scripts/core/match_controller.gd` | 不改 | `allow_cancel` / 取消响应语义保持原样 |
| `game_data/skills/*.gd` | 不改 | 技能脚本继续按原文实现"取消 = 未支付费用" |
| `tests/` | 改 | 改写二次点击断言 + 新增多段技能不跳段断言 |
| `docs/`、`.trellis/spec/` | 改 | 交互契约描述同步 |

UI 层仍只做两件事（读快照 / 提交 `PlayerAction`）：本次改动是**移除一个 UI 自造的取消快捷方式**，不新增任何规则判断，因此不触碰单向依赖原则。

## 二、契约变更

### 变更前

```
内联请求进行中 && allow_cancel && context.skill_id 有按钮
  → 按钮 available = true, selected = true
  → 第二次点击 = 提交 confirmed=false（取消整次/当前段）
```

### 变更后

```
内联请求进行中 && context.skill_id 有按钮（不看 allow_cancel）
  → 按钮 available = false, selected = true   （灰色禁用底 + 金色选中描边）
  → 点击被静默忽略，不提交任何动作
取消出口：操作区“取消”按钮 / Esc / 右键 → confirmed=false（与变更前逐字一致）
```

### 新增/替换的函数

| 函数 | 职责 |
|---|---|
| `_get_in_flight_skill_release_id() -> String` | 返回"当前内联请求归属且有技能按钮"的技能 ID；空字符串表示没有技能正在发动中。**判定不看 `allow_cancel`**，与旧 `_get_selected_skill_release_id()` 的关键差别。 |
| `_active_response_skill_id`（既有成员） | 响应转化材料模式开关，继续单独驱动该技能的"选中 + 可点击退出"语义。 |

### 删除的函数

| 函数 | 删除理由 |
|---|---|
| `_get_selected_skill_release_id()` | 被 `_get_in_flight_skill_release_id()` 取代（旧实现把"发动中"和"响应材料模式"混在一个返回值里，正是缺陷来源）。 |
| `_is_originating_inline_skill_release()` | 只服务于旧二次点击取消分支。 |
| `_cancel_originating_inline_skill_release()` | 同上；其行为已由 `_on_cancel_pressed()`（`match_table.gd:3718-3721`）完整覆盖。 |

## 三、`_render_local_skills` 判定改造

`scripts/ui/match_table.gd` 的刷新分支（约 `:2192-2203`）与重建分支（约 `:2222-2233`）各有一份相同表达式，两处必须同改，否则首次进入技能栏与后续刷新会出现不一致。

改造后每处四个局部量：

```gdscript
# 当前响应转化技能是否处于材料筛选模式；该模式开关仍允许再次点击退出。
var skill_response_mode_active: bool = _active_response_skill_id == skill_id
# 当前技能是否正在发动中：它自己创建的统一选择请求仍未结束。
# 材料筛选模式优先：响应窗口的上下文可能携带 skill_id，不能因此把转化技能按钮判成“发动中”。
var skill_release_in_progress: bool = not skill_response_mode_active and _get_in_flight_skill_release_id() == skill_id
# 当前技能选中视觉；发动中与响应材料模式都使用金色选中描边。
var skill_selected: bool = skill_release_in_progress or skill_response_mode_active
# 当前技能可点击状态；发动中的技能按钮必须失效，其余仍由权威门禁决定。
var skill_available: bool = bool(skill_definition.get("ui_enabled", false)) \
	and not skill_release_in_progress \
	and (skill_response_mode_active or match_controller.can_activate_skill(match_controller.local_human_player_id, skill_id, _get_local_skill_activation_context()))
```

`skill_response_mode_active` 的优先级与改动前的 `_get_selected_skill_release_id()`（先返回 `_active_response_skill_id`）保持一致，确保响应阶段的材料模式切换行为零变化。

`skill_button_view.gd:158/160/185` 的取值组合会自动给出期望视觉：`is_skill_available=false` → 灰色禁用底、无悬停反馈；`is_skill_selected=true` → 3 像素金色描边。无需改组件。

## 四、`_on_skill_requested` 改造

```gdscript
func _on_skill_requested(skill_id: String) -> void:
	# 响应转化技能已处于选中状态时，第二次点击只退出材料转化模式（保持原语义）。
	if _active_response_skill_id == skill_id:
		...
		return
	# 技能发动中再次点击同一按钮不提交任何响应；取消只由操作区“取消”按钮表达。
	# 材料筛选模式期间不拦截，保留“点击另一个转化技能即可切换材料模式”的既有能力。
	if _active_response_skill_id.is_empty() and _get_in_flight_skill_release_id() == skill_id:
		return
	...
```

这道守卫与按钮 `disabled` 是**双保险**：即使某条路径（测试直接调用、未来新增入口）绕过了按钮禁用，也不会再产生"点一下就跳段"的提交。

## 五、时序与数据流（改造后）

```
玩家点技能按钮
  → _on_skill_requested → PlayerAction(use_skill)
  → MatchController.activate_skill → 技能 activate() 创建内联请求
  → _on_card_choice_requested → _render_local_skills
      → skill_release_in_progress = true → 该按钮 disabled + 金色描边
  → 玩家再次点该按钮：按钮 disabled 不触发 pressed；即便触发也被守卫拦下
  → 玩家点“取消”/Esc/右键 → _on_cancel_pressed → confirmed=false
  → 技能 continue_selection 走既有取消分支（技能脚本零改动）
  → 请求清空 → _render_local_skills 恢复按钮可用
```

## 六、兼容性与风险

| 风险 | 评估 | 处置 |
|---|---|---|
| 玩家失去"点按钮取消"的快捷方式 | 低：`_on_cancel_pressed()` 提交完全相同的 `confirmed=false` | 用例覆盖"取消按钮仍可取消" |
| 某些技能把 `allow_cancel=true` 但 `hide_cancel_button=true`（【自摸】`zimo.gd:222`） | 无影响：那里的取消语义就是"重开同一询问"，按钮失效后玩家按候选正常选择即可 | 不改该技能；`qingque_mechanics_test` 仍覆盖 |
| 响应阶段多技能切换（转化技能） | 不受影响：材料模式由 `_active_response_skill_id` 单独驱动，未被本判定合并 | 既有断言继续通过 |
| 两处 `_render_local_skills` 分支只改一处 | 中：首次进入与后续刷新行为不一致 | 实现清单显式列出两处 |
| 局域网客户端（按钮可用性来自房主下发的 `active_skill_ids`） | 低：发动中的请求仍是内联请求，判定同源 | 由 `_get_in_flight_skill_release_id()` 统一处理 |

## 七、回滚

改动集中在 `match_table.gd` 的三个函数 + 两个判定表达式，`git revert` 单个提交即可完全回滚；测试与文档同提交，无数据迁移、无存档格式变更、无网络协议变更。
