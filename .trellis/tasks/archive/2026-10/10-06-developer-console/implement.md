# 执行计划：开发者设置与开发者菜单（单机局内调试控制台）

> 需求见 `prd.md`，技术设计见 `design.md`。
> 平台：DeepSeek Harness（inline 工作流）——本会话由主 agent 直接改代码，**不派发子 agent**，因此不消费 `implement.jsonl` / `check.jsonl`。
> 纪律：每个阶段结束都要跑该阶段的验证命令；验证未过不得进入下一阶段。阶段末标出**回滚点**。

---

## 0. 前置条件与基线

- [ ] 0.1 确认工作区干净、当前分支 `master`，记录基线提交哈希。
- [ ] 0.2 确认 Godot 可执行文件路径（本机为 `E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe`）。
- [ ] 0.3 **跑基线测试**，记录改动前结果，作为回归对照：
  - `smoke_test`、`event_runtime_test`、`phase_progression_test`、`ui_layout_test`、`font_color_audit_test`
- [ ] 0.4 复读并确认 `docs/架构说明.md`「事件运行时边界」「停滞自修复边界」与 `.trellis/spec/core/event-runtime-phases.md` 的约束仍然成立（管线优先级链未在本任务期间被他人改动）。

**验证命令模板**（逐条顺序执行，不并发——项目规范要求逐进程顺序跑）：

```powershell
$godot = "E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
& $godot --headless --path . res://tests/<name>.tscn
```

判定：**退出码 0 + 输出自身 PASS 标记 + 日志无 `ERROR` / `SCRIPT ERROR` / `FAIL`**。

**回滚点 R0**：无改动。

---

## 1. core：开发者效果队列

- [ ] 1.1 新增 `scripts/core/developer_effect_service.gd`（`class_name DeveloperEffectService extends RefCounted`），实现 `design.md` §4.2 的公开契约：
  - `_init(host_controller: Node = null)`
  - `enqueue(effect_kind, target_player_id, amount, match_id, payload = {}) -> bool`
  - `has_pending() -> bool` / `pending_count() -> int`
  - `resume_next() -> bool`
  - `reset() -> void` / `drain_discarded() -> int`
  - `const MAX_PENDING_EFFECTS: int = 64`
- [ ] 1.2 服务内实现 §4.5 的 11 个 kind 分派；**只调宿主公开端口**，不写任何 `hp` / `max_hp` / `shield` 赋值。
- [ ] 1.3 实现「生效判定」：执行前后对比 `host.state.get_player(target)` 的公开字段，或直接使用端口返回的 `int` / `bool`。不复制规则公式。
- [ ] 1.4 实现过期条目处理：`match_id` 不符或目标玩家不存在时静默丢弃 + 写一条开发者日志。
- [ ] 1.5 每个 `var` 独占一行 `##` 注释，说明用途、取值范围、默认值原因与修改影响；`@export` / 常量集中在文件最顶部。
- [ ] 1.6 `scripts/core/match_controller.gd` 新增成员（紧邻 `_rule_continuations`，约 `:818`）：
  ```gdscript
  var _developer_effects: DeveloperEffectService = DeveloperEffectService.new()
  ```
  并在服务构造处传入 `self`（若采用 `_init(host)` 形态，则改为在 `_ready`/`_ensure_*` 中绑定宿主，与既有 `_ensure_card_movement()` 风格一致；实现时以最小侵入为准并保持注释说明）。
- [ ] 1.7 新增公开端口 `request_developer_effect()` / `get_developer_effect_pending_count()`（签名与骨架见 `design.md` §4.3）。
- [ ] 1.8 `request_developer_effect()` 内加**纵深防御**的离线门控：`network_gateway == null or network_gateway.mode == NetworkGateway.Mode.OFFLINE` 之外一律拒绝（`docs/内容制作指南.md:12`）。
- [ ] 1.9 插入**挂钩 1**（消费点）：`_run_settlement_pipeline_pass()` 的 `while` 内，`_deferred_skill_settlements` 分支之后、`break` 之前（当前 `:13139–13143`）。
- [ ] 1.10 插入**挂钩 2、3**：当前 `:13145` 与 `:13153` 的判据加入 `_developer_effects.has_pending()`。
- [ ] 1.11 插入**挂钩 4**：`_has_unresolved_settlement_work()`（当前 `:13032–13039`）加入 `_developer_effects.has_pending()`。
- [ ] 1.12 插入**挂钩 5**：在 `_rule_continuations.reset()` 出现的全部 5 处（当前 `:1694`、`:1767`、`:1854`、`:16131`、`:16160`）追加 `_developer_effects.reset()`。
- [ ] 1.13 效果执行后调用 `refresh_state_snapshot()`（在 `resume_next()` 成功消费后由控制器侧统一调用，避免服务反向依赖快照机制）。

### 阶段 1 验证

- [ ] 1.14 新建测试场景 `tests/developer_console_test.gd` + `.tscn`（照既有测试形态：自带断言、打印 `DEVELOPER_CONSOLE_PASS`），覆盖：
  - 队列登记后**不会立即生效**：在一次结算进行中登记，断言状态未变；结算结束后断言已生效。
  - 9 项数值效果各自的实际生效量与边界（满体力 `recover` 不生效、`lose_hp` 不消耗护盾、`damage` 先扣护盾、`change_max_hp` 减少时至少保留 1、`change_hujia` 最低为 0 且不产生伤害）。
  - **待办选择期间排队**：制造一个待办选择后登记效果，断言效果未执行；提交响应后断言执行。
  - **重开清理**：登记效果后 `start_match()` 重开，断言新一局无任何旧效果痕迹。
  - **活跃性**：登记效果后不调用任何额外入口，断言效果最终被执行（验证挂钩 4 有效）。
  - 局域网模式下 `request_developer_effect()` 被拒绝。
- [ ] 1.15 跑阶段 1 相关回归（必须全绿）：
  - `developer_console_test`（新）
  - `event_runtime_test`
  - `phase_progression_test`
  - `skill_settlement_runtime_test`（该用例专门覆盖管线唤醒活跃性保证）
  - `smoke_test`
- [ ] 1.16 在 `README.md`「自动校验」章节补充 `developer_console_test` 的说明（项目规范要求）。

**评审门 G1**：确认 `git diff scripts/core/match_controller.gd` 只有「1 个成员 + 2 个公开端口 + 4 处判据/分支 + 5 行 reset」，没有其它改动；确认消费点位置正确（在技能「然后」之后、阶段恢复之前）。

**回滚点 R1**：`git checkout -- scripts/core/match_controller.gd && rm scripts/core/developer_effect_service.gd`。

---

## 2. ui：局内菜单入口

- [ ] 2.1 `scenes/main.tscn`：在 `MenuReturnToMainButton`（当前 `:611`）之前插入：
  ```
  [node name="MenuDeveloperSettingsButton" type="Button" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=<未占用整数>]
  unique_name_in_owner = true
  visible = false
  custom_minimum_size = Vector2(0, 32)
  layout_mode = 2
  text = "开发者设置"
  ```
  `unique_id` 必须取当前场景未使用的整数（可 grep 现有最大值后递增）。
- [ ] 2.2 用 Godot 打开 `project.godot` 确认场景能正常加载、按钮出现在菜单底部按钮区、`%MenuDeveloperSettingsButton` 可被 `%` 引用（验证 `unique_id` 与 `unique_name_in_owner` 写法正确；若编辑器对 `unique_id` 有额外要求，以编辑器实际保存结果为准）。
- [ ] 2.2b **硬门：竖向余量实测（插入前必做）**
  `MenuPanel` 是固定锚定高度的 `PanelContainer`，`MenuVBox` 是普通 `VBoxContainer` 且无滚动容器，`clip_contents` 未开启；静态核算在身份模式下余量仅约 41px，而新按钮需 33px（详见 `design.md` §6.1）。
  写一个**一次性** headless 检查脚本（跑完即删，不入库）：加载 `main.tscn`、`start_match()`、打开菜单、等待若干帧，打印
  `MenuPanel.size`、`MenuVBox.get_combined_minimum_size()`、各可见子节点的 `get_rect()`、以及最后一个子节点的 `rect.end.y` 与视口高度。
  - 判定：`MenuVBox.get_combined_minimum_size().y + 33 <= MenuPanel.size.y` **且** 插入后最后一个子节点 `rect.end.y <= 视口高度`。
  - 通过 → 按 2.1 的堆叠按钮方案继续。
  - 不通过 → 采用 `design.md` §6.1 的**首选回退**：新增 `MenuBottomButtonRow`（`HBoxContainer`）承载 `MenuReturnToMainButton` + `MenuDeveloperSettingsButton` 并排，额外高度为 0。已 grep 确认这两个按钮仅经 `%` 引用（`match_menu.gd:100/103`），改父节点不影响解析。
  - **不得**给 `MenuVBox` 外套 `ScrollContainer`：会破坏 `match_menu.gd:416–445` 的 `MenuVBox/...` 绝对路径。
- [ ] 2.2c 实测开发者菜单窗口在 1152×648 下不溢出（内容全部置于 `ScrollContainer`，底部按钮行固定可见）。
- [ ] 2.3 `scripts/ui/match_menu.gd` 新增：
  - signal `developer_settings_requested`（加入文件顶部 signal 区）
  - `@onready var _developer_settings_button: Button = %MenuDeveloperSettingsButton`
  - `_ready()` 中 `.pressed.connect(_request_developer_settings)`
  - `_request_developer_settings()`：先 `_menu_panel.visible = false`，再 `emit`
  - `refresh_ui_style()` 中 `BattleUIStyle.apply_interaction_button(_developer_settings_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)`
- [ ] 2.4 新增私有 `_refresh_developer_entry_visibility()`，由 `set_offline_controls_visible()` 与 `set_authority_controls_visible()` **两边都调用**；内部：
  ```gdscript
  _developer_settings_button.visible = _authority_controls_visible and _offline_controls_visible
  if not _developer_settings_button.visible and _developer_settings_button.has_focus():
      _developer_settings_button.release_focus()
  ```
- [ ] 2.5 **不修改**任何既有变量名与既有注释；只新增。

### 阶段 2 验证

- [ ] 2.6 跑 `ui_layout_test`、`font_color_audit_test`、`main_menu_test`、`smoke_test`。
- [ ] 2.7 人工确认：单机对局菜单出现按钮；局域网房主与客户端不出现。

**评审门 G2**：`git diff scenes/main.tscn` 只有 1 个新增节点；`git diff scripts/ui/match_menu.gd` 只有新增行。

**回滚点 R2**：`git checkout -- scenes/main.tscn scripts/ui/match_menu.gd`。

---

## 3. ui：开发者菜单面板主体

- [ ] 3.1 新增 `scenes/components/developer_console_panel.tscn`（照 `card_selection_panel.tscn` 的极简形态：根 `Control` 全屏锚点 + 挂脚本 + `@export` 默认值）。
- [ ] 3.2 新增 `scripts/ui/developer_console_panel.gd`（`class_name DeveloperConsolePanel extends Control`）：
  - 顶部常量区：`CONSOLE_Z_INDEX = 520`、`MIN_EFFECT_VALUE = 1`、`SLIDER_MIN_VALUE = 1`、`SLIDER_MAX_VALUE = 10`、效果声明数组 `EFFECT_DECLARATIONS`（`{kind, label, uses_amount}`）
  - signal：`close_requested`、`effect_requested(kind, target_player_id, amount)`、`draw_pile_gain_requested(target_player_id, uids)`、`character_replace_requested(target_player_id, character_id)`
  - `@export` 参数集中在最顶部并逐行注释（面板宽度、最大高度、行高、按钮宽度等）
- [ ] 3.3 代码构建 UI：全屏遮罩 `ColorRect`（`MOUSE_FILTER_STOP`，色取 `BattleUIStyle.get_color("shade")`）+ 居中 `PanelContainer`（`make_inset_panel()`）+ `ScrollContainer`/`VBoxContainer`：
  - 标题行（标题 + 关闭按钮）
  - 目标选择行（`Label` + `OptionButton`）
  - 9 个效果行（遍历 `EFFECT_DECLARATIONS` 构建：`Button` + `HSlider` + 数值输入框）
  - 2 个纯按钮行
  - 状态行（`Label`，显示排队数与最近结果）
- [ ] 3.4 拖条与输入框双向同步，程序化写值一律 `set_value_no_signal()`；输入框按「文本优先」惯例取值（下限 `1`、无上限）。
- [ ] 3.5 实现 `open_console()` / `close_console()` / `set_target_candidates()` / `set_pending_count()` / `set_status_text()`；目标选择在刷新时保留，仅当目标已不存在时回退到 `preferred_player_id`。
- [ ] 3.6 实现 `_unhandled_input()`：Esc 优先关闭第二层子视图，否则 `close_requested.emit()`，两种情况都 `set_input_as_handled()`；安卓返回键同路径。
- [ ] 3.7 实现 `refresh_ui_style()`（`if not is_node_ready(): return` 开头），订阅 `GameSettings.ui_style_changed`；按钮一律 `BattleUIStyle.apply_interaction_button()`；滑条照 `main_menu.gd:1824 _apply_slider_style()`；输入框照 `all_cards_panel.gd:920 _apply_line_edit_style()`。
- [ ] 3.8 面板**不得**出现 `GameState` / `MatchController` 引用（`GameDatabase` 静态定义除外，符合既有惯例）。

### 阶段 3 验证

- [ ] 3.9 跑 `font_color_audit_test`（新增 `Label` / `Button` / 输入框必须全部纳入统一主题字体色）。
- [ ] 3.10 跑 `ui_layout_test`；并人工在 1152×648 下打开窗口确认内容可滚动、无溢出。

**评审门 G3**：面板脚本内 grep `GameState` / `match_controller` 无命中。

**回滚点 R3**：`rm scripts/ui/developer_console_panel.gd scenes/components/developer_console_panel.tscn`。

---

## 4. ui：第二层窗口（牌堆选牌 / 换将选将）

- [ ] 4.1 在 `DeveloperConsolePanel` 内实现两个子视图（同一遮罩内切换内容，不叠加第二层全屏遮罩）：
  - **牌堆选牌**：`set_draw_pile_candidates(candidates)` 注入候选；网格渲染 `CardView`（`card_data` + `GameDatabase.get_card(definition_id)`）；任意张多选；无选中时「确定」禁用；确定发 `draw_pile_gain_requested`，取消/Esc 返回主视图。
  - **换将选将**：自 `GameDatabase.characters` 构建列表，按势力分组，单选；确定发 `character_replace_requested`，取消/Esc 返回主视图。
- [ ] 4.2 两个子视图均需可滚动；换将列表需支持按名称/势力筛选（约 189 项）。
- [ ] 4.3 复用 `CardSelectionPanel` 的多选交互**形态**（选中态、`min_select`/`max_select` 判定），但**不实例化**该组件。

### 阶段 4 验证

- [ ] 4.4 人工确认：牌堆选牌窗口列出全部摸牌堆牌、多选可用、确定后牌进入目标手牌、取消不获得任何牌；换将窗口可滚动、可单选、确定后武将牌替换、取消无副作用。
- [ ] 4.5 跑 `font_color_audit_test`、`ui_layout_test`。

**回滚点 R4**：撤销 `developer_console_panel.gd` 中的子视图改动（保留阶段 3 成果）。

---

## 5. ui：桌面装配与转发

- [ ] 5.1 `scripts/ui/match_table.gd` 顶部常量区新增：
  ```gdscript
  const DEVELOPER_CONSOLE_PANEL_SCENE: PackedScene = preload("res://scenes/components/developer_console_panel.tscn")
  ```
- [ ] 5.2 新增 `_create_developer_console_panel()`（照 `_create_game_settlement_panel()` 形态：`instantiate() as DeveloperConsolePanel`、显式 `name`、`add_child(self)`、连接全部信号），并在 `_ready()` 中与其它 `_create_*` 同区调用。
- [ ] 5.3 `_ready()` 的菜单信号连接区（当前 `:635–639`）新增 `match_menu.developer_settings_requested.connect(_on_developer_settings_requested)`。
- [ ] 5.4 实现转发：
  - `_on_developer_settings_requested()`：注入目标候选（从 `_snapshot.players` 投影，默认 `match_controller.local_human_player_id`）→ 注入排队数 → `open_console()`
  - `_on_developer_console_effect_requested(kind, target_id, amount)`：`match_controller.request_developer_effect(...)` → 回写状态行
  - `_on_developer_console_draw_pile_requested()`：调 `match_controller.get_top_draw_card_candidates(match_controller.local_human_player_id, draw_pile_count)` → `set_draw_pile_candidates()`
  - `_on_developer_console_draw_pile_gain_requested(target_id, uids)`：`request_developer_effect("gain_draw_pile_card", target_id, 0, {"uids": uids})`
  - `_on_developer_console_character_replace_requested(target_id, character_id)`：`request_developer_effect("replace_character", target_id, 0, {"character_id": character_id})`
  - `_on_developer_console_close_requested()`：`close_console()` + 焦点归还
- [ ] 5.5 快照刷新路径（`state_changed` 处理处）追加：窗口可见时刷新目标候选与排队数。
- [ ] 5.6 主题刷新处（当前 `:3637` 一带，`match_menu.refresh_ui_style()` 附近）调用 `developer_console_panel.refresh_ui_style()`。
- [ ] 5.7 返回主菜单 / 局域网会话结束 / 重开局的清理路径追加 `close_console()`（与 `character_selection_panel.close()` / `game_settlement_panel` 的既有兜底同区）。

### 阶段 5 验证

- [ ] 5.8 跑 `ui_layout_test`、`font_color_audit_test`、`main_menu_test`、`smoke_test`。
- [ ] 5.9 人工走查 AC1–AC15 全流程（单机身份局 5 人）：
  - 打开菜单 → 开发者设置 → 默认目标本人
  - 逐项效果生效并观察体力/上限/护盾/手牌/牌堆变化与日志
  - 切换目标后效果作用到新目标
  - 在 AI 结算进行中点击效果 → 状态行显示排队 → 结算完成后生效
  - 制造本机待办选择后点击效果 → 排队 → 提交选择后生效
  - 获得牌堆指定牌（多选 + 取消）
  - 更换武将（含 special 武将 + 取消 + 对死亡目标操作）
  - 有待办效果时重开 → 新局无旧效果痕迹
  - Esc / 安卓返回键 / 关闭按钮三条关闭路径
  - 局域网房主与客户端：菜单无「开发者设置」

**评审门 G5**：AC1–AC15 全部实测通过；`git diff --stat` 与 `design.md` §3 的文件清单一致，无越界改动。

**回滚点 R5**：`git checkout -- scripts/ui/match_table.gd`。

---

## 6. 文档同步（AGENTS.md 强制）

- [ ] 6.1 `docs/界面与交互.md`：
  - `z_index` 表新增开发者菜单窗口 `520`（落在局内菜单 `500` 与回放覆盖层 `620` 之间）
  - 「局内菜单」小节新增「开发者设置」入口（仅离线可见）、窗口结构与第二层窗口规格、关闭路径
- [ ] 6.2 `docs/游戏机制与玩法内容.md`：新增「开发者菜单」章节，记录**全部数值**：
  - 拖条范围 `1..10`、默认 `1`、步长 `1`
  - 输入框最小值 `1`、无上限
  - 9 项效果的语义与作用对象（含「弃牌只作用于普通手牌」「伤害无来源且为普通属性」）
  - 空闲时间执行规则（结算边界、待办选择期间排队、重开清理、队列上限 `64`）
  - 明确标注这是**调试工具**，不属于正式玩法数值体系
- [ ] 6.3 `docs/架构说明.md`：补充开发者请求队列、空闲边界端口、离线特权表面边界（引用 `内容制作指南.md:12`）。
- [ ] 6.4 `docs/内容制作指南.md`：按 `documentation-sync.md` §一「新机制/新函数处理流程」第 3 条与 §四「接口沉淀」的强制要求，把新增的公开接口写入指南的端口/函数索引（与 `resolver.host.*` 端口清单同区）：
  - `request_developer_effect(effect_kind, target_player_id, amount, payload = {}) -> bool`
  - `get_developer_effect_pending_count() -> int`
  - 11 个 `effect_kind` 字符串常量及其语义
  - `DeveloperEffectService` 的职责与「纯数据队列 + 结算边界消费」约定
  - 明确标注这些是**离线调试特权端口**，内容文件（卡牌/技能）**不得**调用。
- [ ] 6.5 检查 `.trellis/spec/` 是否有条目需要更新（尤其 `ui/index.md` 的层级约定与 `core/event-runtime-phases.md` 的管线优先级链）。若有，用 `trellis-update-spec` 流程补充。
- [ ] 6.6 逐行核对 `documentation-sync.md` §一 同步矩阵与 §Quality Check 清单，确认无遗漏项。

---

## 7. 全量回归与收尾

- [ ] 7.1 逐条顺序执行全量相关回归：
  ```
  smoke_test, event_runtime_test, phase_progression_test, skill_settlement_runtime_test,
  gameplay_regression_test, developer_console_test, ui_layout_test, font_color_audit_test,
  main_menu_test, ai_policy_test, performance_and_pacing_test
  ```
- [ ] 7.2 确认 `GameDatabase.validation_errors` 为空、可正常开局（`smoke_test` 覆盖）。
- [ ] 7.3 产出「学习反馈摘要」（修改思路 / 架构与设计 / 关键代码解析 / 学习要点提炼）。
- [ ] 7.4 产出「Git 提交描述」（数字序号分行、每行一个核心动作、动词开头）。
- [ ] 7.5 把 7.3 + 7.4 以时间戳 `YYYY-MM-DD HH:MM` 追加写入 `临时反馈文档.md` 末尾（不覆盖历史）。
- [ ] 7.6 在 `README.md`「自动校验」补充新测试说明（若阶段 1.16 已完成则跳过）。
- [ ] 7.7 归档任务：`python ./.trellis/scripts/task.py archive <task-dir>`（在用户确认提交后执行）。

---

## 验证命令速查

```powershell
$godot = "E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
$tests = @("smoke_test","event_runtime_test","phase_progression_test","skill_settlement_runtime_test",
           "gameplay_regression_test","developer_console_test","ui_layout_test","font_color_audit_test",
           "main_menu_test","ai_policy_test","performance_and_pacing_test")
foreach ($t in $tests) {
  Write-Host "=== $t ==="
  & $godot --headless --path . "res://tests/$t.tscn"
  Write-Host "exit=$LASTEXITCODE"
}
```

> **不要并发跑多个 Godot 进程**：会争用本机用户设置与 `.godot` 缓存（`.trellis/spec/project/verification.md` 明确要求逐进程顺序执行）。
> 断言一律用**条件等待 + 兜底超时**，不用固定墙钟休眠。

---

## 风险与回滚总览

| 回滚点 | 范围 | 命令 |
|---|---|---|
| R0 | 无改动 | — |
| R1 | core 队列 | `git checkout -- scripts/core/match_controller.gd; rm scripts/core/developer_effect_service.gd tests/developer_console_test.*` |
| R2 | 菜单入口 | `git checkout -- scenes/main.tscn scripts/ui/match_menu.gd` |
| R3 | 面板主体 | `rm scripts/ui/developer_console_panel.gd scenes/components/developer_console_panel.tscn` |
| R4 | 第二层窗口 | 撤销面板内子视图改动（保留 R3 成果） |
| R5 | 桌面装配 | `git checkout -- scripts/ui/match_table.gd` |

改动全程为纯增量，无存档格式、网络协议或数据迁移变化；队列为空时管线行为与改动前逐位一致。
