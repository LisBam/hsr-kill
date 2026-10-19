# 银狼武将、注入/以太技能与 yinlang_windows 窗口

## Goal

新增星核猎手武将「银狼」（体力值 3，女），实现技能「注入」（`zhuru`）与「以太」（`yitai`）；实现由「注入」驱动的运行时组合技能「进程」（`jincheng`）与「缺陷」（`quexian`）；实现高科技黑蓝风格的窗口 `yinlang_windows`，承载注入的组合选择窗口与以太的造牌窗口。

## 依赖

- `10-19-skill-instance-multiplicity`：多实例技能（`allow_duplicate`、实例键、按实例的每回合额度、按实例的动态描述）。
- `10-19-runtime-card-creation`：`mint_card_for_player`、`shuffle_discard_card_into_draw_pile`、`is_card_name_available`、`get_discard_pile_card_uids_by_skill`、`CardInstance.custom_display_name` / `minted_skill_id`。

本任务在两项完成后开始。

## Requirements

### R1 银狼武将

- **R1.1** `game_data/characters/yinlang.gd`：`id = "yinlang"`、`display_name = "银狼"`、`gender = "female"`、`faction = "xinghelieshou"`（星核猎手，已存在于 `game_data/factions.json`）、`max_hp = 3`、技能 `[zhuru, yitai]`（按此顺序）。
- **R1.2** 武将 `description` 与两个技能 `description` **逐字**使用需求原文，不得改写、增删标点。
- **R1.3** 立绘：`game_data/characters/image/yinlang.png`（按脚本文件 basename 匹配）。缺失不阻塞功能，但需在交付说明中列出该待补资源。
- **R1.4** 阵亡语音路径约定同其他武将：`game_data/characters/audio/die/yinlang.{ogg,wav,mp3}`（可选，缺失不影响功能）。

### R2 注入（`zhuru`）

- **R2.1 游戏开始时**：订阅 `gameStart`（`role = "global"`，因为 `gameStart` 的三个 ID 均为 -1）。可选发动：发动则打开 `yinlang_windows` 的注入窗口，组合一项「进程」并令**银狼自己**获得；不发动则无任何效果。
- **R2.2 准备阶段**：订阅 `phaseZhunbeiBegin`（`role = "player"`，即银狼自己的准备阶段）。可选择一名角色（可含自己）；目标为「主演」时组合「进程」并令其获得，否则组合「缺陷」并令其获得。
- **R2.3 可选发动**：准备阶段的选择允许取消，取消则不获得任何技能。
- **R2.4 目标合法性**：存活且未离场的角色（含自己）。
- **R2.5 累积**：每轮准备阶段都可发动，因此同一角色会累积多个同名组合技能；每个实例独立计数（依赖多实例底座）。
- **R2.6 每回合限一次**：组合技能正文含「每回合限一次」，通过 `grant_acquired_skill(..., per_turn_limit = 1, allow_duplicate = true)` 实现，额度按实例分别计算。
- **R2.7 主演判定**：使用既有 `is_starring_role(player_id)` 端口；「主演」是公开角落文字条目，至多一名。

### R3 组合技能「进程」/「缺陷」

- **R3.1 静态脚本**：`game_data/skills/jincheng.gd`（名「进程」）与 `game_data/skills/quexian.gd`（名「缺陷」），均 `lock: true`。
- **R3.2 实例配置**：每个实例的「所选时机」「所选效果」「组合后正文」保存在 `PlayerState.runtime_skill_data[实例键]`（经 `set_runtime_skill_data` 写入），进入快照与存档。
- **R3.3 动态正文**：实例的描述通过 `set_skill_display_description(player_id, 实例键, 正文)` 写入，正文严格等于
  `"锁定技，" + 时机文本 + "，" + 效果文本 + "。每回合限一次。"`
- **R3.4 动态时机订阅**：`install()` 读取本实例配置中的时机，映射到 `RuleTimingCatalog` 的时机名与 `role` 后订阅；未配置时（异常）不订阅并写日志，不得崩溃。
- **R3.5 效果执行**：按配置中的效果 ID 分派到该效果的实现函数；每个效果必须完整实现（不允许只写提示分支）。
- **R3.6 失去本技能**：效果文本含「并失去本技能」时，执行效果后移除**本实例**（`remove_acquired_skill` 或 `remove_skill` 传实例键）。
- **R3.7 AI 段**：两个脚本必须自带 AI 段（`score_ai_choice` / `score_ai_action` 等），使 AI 在组合选择与触发时机上可决策。

### R4 时机池与效果池（逐字，顺序不得调整）

- **R4.1 时机池（进程与缺陷共用，23 项）**：

  当你受到伤害后 / 当你失去体力后 / 当你受到属性伤害后 / 当你造成伤害后 / 当你造成属性伤害后 / 当你回复体力后 / 当你的体力上限发生变化后 / 当你的体力值发生变化后 / 每轮开始时 / 每轮结束时 / 回合开始时 / 回合结束时 / 判定阶段开始时 / 出牌阶段开始时 / 摸牌阶段开始时 / 弃牌阶段开始时 / 当你使用【杀】时 / 当你成为【杀】的目标时 / 当你的武将牌翻面时 / 当你因弃置而失去牌时 / 当你于回合外失去牌时 / 当一名角色死亡后 / 当一名角色脱离濒死状态后

- **R4.2 进程效果池（24 项）**：

  你摸一张牌 / 你从牌堆中获得一张锦囊牌 / 你从牌堆中获得一张基本牌 / 你从牌堆中获得一张装备牌 / 你从牌堆中获得一张"以太"牌 / 从牌堆中获得一张【闪】/ 从牌堆中获得一张【杀】/ 你随机使用牌堆中的一张装备牌 / 你将武将牌重置 / 你弃置一名角色区域内的一张牌 / 你获得一名角色装备区内的一张牌 / 你获得不为你的当前回合角色的一张手牌 / 你的手牌上限+2直到回合结束 / 你的出牌阶段使用【杀】的次数上限+1直到回合结束 / 你使用攻击范围+2直到回合结束 / 你计算与其他角色距离-1直到回合结束 / 防止你受到伤害直到回合结束 / 你视为使用一张【杀】/ 你视为使用一张【决斗】/ 你视为使用一张【顺手牵羊】/ 你摸两张牌并失去本技能 / 你回复1点体力并失去本技能 / 你增加1点体力上限并失去本技能 / 你获得1点护盾并失去本技能

- **R4.3 缺陷效果池（18 项）**：

  你弃置一张手牌 / 你随机弃置一张牌 / 你随机弃置一张装备牌 / 你随机弃置一张基本牌 / 你随机弃置一张锦囊牌 / 你的手牌上限-1直到回合结束 / 你将武将牌调整至横置 / 你交给不为你的当前回合角色一张牌 / 你不可响应其他角色使用的牌直到回合结束 / 你计算与其他角色的距离+1直到回合结束 / 本回合内你下次受到的伤害+1 / 本回合内你下次受到的属性伤害+1 / 你下次回复的体力-1直到回合结束 / 你失去1点体力并失去本技能 / 你受到1点伤害并失去本技能 / 你受到1点雷电伤害并失去本技能 / 你受到1点火焰伤害并失去本技能 / 你减少1点体力上限并失去本技能

- **R4.4** 每条时机必须映射到一个真实可订阅的时机名与 `role`；每条效果必须映射到一个真实可执行的端口或机制。映射表见 `design.md`。
- **R4.5** 同一池中的条目在不同轮次可重复选择（允许重复组合出相同内容的不同实例）。
- **R4.6** 池文本不得出现在技能描述以外的位置造成重复维护：池数据集中在一个数据文件（`game_data/composed_skill_pools.gd`），技能脚本与界面均从该文件读取。

### R5 以太（`yitai`）

- **R5.1 限定技**：`description` 含「限定技」即由基类自动标记 `limited`；出牌阶段可发动（`ui_enabled = true`）。
- **R5.2 造牌**：发动时打开 `yinlang_windows` 的以太窗口；四项选择齐全并确认后，调用 `mint_card_for_player` 创造该牌并进入银狼手牌。
- **R5.3 牌名唯一**：牌名不得与任何已存在牌名相同；冲突时界面即时提示并阻止确认；权威侧二次校验。
- **R5.4 回合结束回流**：订阅 `phaseAfter`（`role = "global"`）——即「一名角色的回合结束时」。若弃牌堆中存在由「以太」创造的牌（`minted_skill_id == "yitai"`），银狼成为「主演」（`set_starring_role`）并把该牌洗入摸牌堆（`shuffle_discard_card_into_draw_pile`）。
- **R5.5 多张时的口径**（原文未明确，需补全并汇报）：对弃牌堆中**所有**由「以太」创造的牌依次洗入摸牌堆；只要至少洗入一张，银狼即成为「主演」。常规情形（限定技一局一次）下只有一张，行为与原文单数表述一致。
- **R5.6** 该时机必须支持嵌套结算屏障（技能在时机回调中创建选择/移动时使用 `defer_settlement` / `continue_settlement`）。

### R6 `yinlang_windows` 窗口

- **R6.1 命名**：窗口层节点与脚本统一命名为 `yinlang_windows`（`scripts/ui/yinlang_windows_layer.gd`，`scenes/components/yinlang_windows_layer.tscn`，节点名 `YinlangWindowsLayer`）。
- **R6.2 视觉**：高科技黑蓝风格——深色（近黑）面板底、蓝色描边与高光、等宽感排版。颜色与样式**一律**经 `BattleUIStyle` / `UIStyleRegistry` 读取；为此在三个调色板中新增语义键 `tech_panel` / `tech_border` / `tech_accent` / `tech_grid`，不在组件内硬编码主题色。
- **R6.3 层级**：层级取 `185`（介于机缘选择弹窗 `180` 与结算面板 `220` 之间），同步更新 `docs/界面与交互.md` 的层级表；并在 `tests/ui_layout_test.gd` 中新增该层级的契约断言（`yinlang_windows` 层级严格大于机缘弹窗、小于结算面板），使层级不再只靠文档约束。
- **R6.4 模态**：`process_mode = PROCESS_MODE_ALWAYS`、全屏遮罩 `MOUSE_FILTER_STOP`、`visible = false` 起步、`move_to_front()` 展示、实现 `refresh_ui_style()` 并由 `GameState`/设置变更重入。
- **R6.5 注入窗口**：两栏——左栏时机选择、右栏效果选择；每栏**默认只展示 2 个候选**（默认「两个时机中选一个、两个效果中选一个」），提供「展开全部」入口以访问完整池；两栏各选中一项后底部「确定」可点击，点击即提交组合结果。窗口内实时预览组合后的技能正文。
- **R6.6 以太窗口**：四行——(1) 自定义牌名文本输入（`LineEdit`，须设 `ThemeDB.fallback_font`）；(2) 花色选择（黑桃/红桃/梅花/方块）；(3) 点数选择（A、2-10、J、Q、K，对应 1-13）；(4) 效果与类别选择，列出**全部**牌名，按「基本牌 → 锦囊牌 → 装备牌」顺序分组。四项齐全后「确定」可点击。
- **R6.7 校验反馈**：牌名冲突/为空/超长时在窗口内显示可见提示并禁用「确定」。
- **R6.8 取消**：允许取消（`allow_cancel`），取消即关闭窗口且不产生任何效果。
- **R6.9 字体颜色**：窗口内每个 `Label`/`CheckBox` 必须有 `font_color` 覆盖，`RichTextLabel` 必须有 `default_color`（`tests/font_color_audit_test.gd` 强制）。
- **R6.10 层职责**：窗口只接收宿主传入的普通字典数据，只通过信号回报选择结果；不得读取 `GameState`、不得改写规则状态、不得持有 `MatchController` 引用做规则调用。

### R7 协议与分流

- **R7.1** 注入窗口与以太窗口的请求复用既有 `control_options` + `control_id` 通道，不新增 `ChoiceResponse` 字段。
- **R7.2** 请求 `context` 携带 `yinlang_window`（`"inject"` / `"aether"`）以及窗口所需的池数据；`match_table._is_inline_control_choice` 必须对这类请求返回 `false`（走模态），`_refresh_card_selection_panel` 需在分流处优先转交 `yinlang_windows`。
- **R7.3** 两个窗口的作答都无法用「预先枚举的合法选项」表达（以太是自由文本；注入是 23 × 24 组合，逐项枚举会造成 552 条选项的无效序列化），因此各引入**新的 `choice_type`**：
  - 注入：`yinlang_compose`，`control_id = "yinlang|compose|<时机键>|<效果键>"`；
  - 以太：`yinlang_mint`，`control_id = "yinlang|mint|<牌名>|<花色>|<点数>|<被复制牌定义ID>"`。
- **R7.4** 权威侧为两个新 `choice_type` 增加结构性校验分支（紧邻既有 `arrange` / `card_position` 分支）：时机键与效果键必须属于该窗口声明的池，且效果键必须属于本次组合类别（进程 / 缺陷）对应的池；牌名必须通过唯一性与格式校验，花色与点数合法，被复制牌定义必须存在。任一不合法即 `_reject`，不得产生副作用。
- **R7.5** 新 `choice_type` 必须被纳入「不按内联处理」的分流判定，并确认不会误入「选择的牌数不足」等卡牌维度校验分支。
- **R7.6** 既有 `ChoiceRequest.validate_response()` 会用 `control_ids.has(control_id)` 拒绝任何未预先登记的 `control_id`，这与「自由文本 / 组合枚举不可预登记」直接冲突。因此新增一个显式请求级开关 `allow_free_control_id: bool = false`：仅两个新 `choice_type` 的请求置为 `true`；开关为真时跳过白名单比对，但**必须**额外要求已确认时 `control_id` 非空。该开关进入 `to_dict()` / `from_dict()`，保证联机与回放一致。禁止用「按 choice_type 硬编码豁免列表」的方式绕过。
- **R7.7** 联机与回放：两种请求都只依赖 `control_id`，因此随既有 `choose_cards` 动作自然同步与回放，无需新增 `ChoiceResponse` 字段。
- **R7.8** AI：AI 作为选择方时必须能作答。`_build_card_choice_actions()` 目前只为 `control` / `bool` / `target_control` / `arrange` / `card_position` 枚举候选动作，新类型会得到空枚举（仅剩取消动作），AI 永远只能取消。因此新增通用分支：当请求声明自由控制项时，按 `context["ai_candidate_control_ids"]`（技能给出的短名单，去重并限长）逐个生成确认动作。银狼两个技能必须提供该短名单（注入：按 AI 价值排序的若干组合；以太：一个自动生成且唯一的牌名 + 预设花色点数 + 由 AI 选定的被复制牌）。

### R8 文档

- **R8.1** `docs/内容制作指南.md`：新增「运行时组合技能」「银狼与 yinlang_windows」「自由文本输入型选择请求」三节。
- **R8.2** `docs/游戏机制与玩法内容.md`：完整记录银狼、注入、以太、组合技能池（逐字列出 23 + 24 + 18 项）、造牌规则、回合结束回流规则与全部数值。
- **R8.3** `docs/界面与交互.md`：新增 `yinlang_windows` 章节（结构、交互、层级、视觉规格、键盘/取消行为）并更新层级表。
- **R8.4** `README.md`：测试场景清单补充新测试。
- **R8.5** `临时反馈文档.md`：追加学习反馈摘要与 Git 提交描述。

## Acceptance Criteria

- [ ] 选将界面出现「银狼」，星核猎手势力、体力值 3、女；技能栏显示「注入」「以太」。
- [ ] 游戏开始时弹出 `yinlang_windows` 注入窗口；选一项时机 + 一项效果并点「确定」后，银狼获得一个「进程」技能，其描述严格等于「锁定技，<时机>，<效果>。每回合限一次。」；取消则不获得。
- [ ] 银狼准备阶段弹出选择目标；目标为「主演」时获得「进程」，否则获得「缺陷」；连续两轮后银狼拥有两个同名组合技能，技能栏各占一项。
- [ ] 两个同名组合技能的「每回合限一次」分别计算：其一发动后其二仍可发动。
- [ ] 组合技能在其所选时机上真实触发并完整执行所选效果（逐条验收，见 `implement.md` 的效果验收表）。
- [ ] 含「并失去本技能」的效果执行后该实例消失，其余同名实例不受影响。
- [ ] 以太为限定技：一局只能发动一次；发动后弹出以太窗口，四项选择齐全后点「确定」创造新牌并进入手牌，牌名/花色/点数与输入一致，类别与效果与被复制牌一致。
- [ ] 以太窗口中输入与已有牌名相同的名称时显示提示且「确定」不可点击。
- [ ] 任意角色回合结束时，若弃牌堆中有「以太」创造的牌，银狼获得「主演」角落文字，该牌回到摸牌堆（且不再出现在弃牌堆）。
- [ ] `yinlang_windows` 为高科技黑蓝风格，颜色全部来自主题层；切换界面风格后窗口配色跟随变化。
- [ ] 窗口层级为 185，未遮挡也未低于既有窗口；`ui_layout_test` 通过。
- [ ] AI 使用银狼时能完成注入的组合选择与以太的四项选择，不会卡在选择界面。
- [ ] 测试全绿：新增 `tests/yinlang_mechanics_test.tscn`，并通过 `smoke_test`、`new_character_mechanics_test`、`gameplay_regression_test`、`ui_layout_test`、`font_color_audit_test`、`skill_ownership_test`、`skill_instance_multiplicity_test`、`runtime_card_minting_test`。
- [ ] `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/界面与交互.md`、`README.md` 已同步；`临时反馈文档.md` 已追加。

## Notes

- **原文不可变**：需求原文中的技能描述、池内文本、数值、顺序一律不得改动。
- 需要自行补全并单独汇报的配套逻辑：
  1. 注入窗口「默认 2 个候选 + 可展开完整池」的具体候选来源（随机 2 项 / 固定前 2 项 / 按 AI 价值推荐 2 项）——本任务采用「权威随机源抽取 2 项，可展开完整池」，保证联机一致且回放可复现；
  2. 多张「以太」牌同时在弃牌堆时的处理（见 R5.5）；
  3. 组合技能实例在目标角色死亡/离场/换将时的清理口径；
  4. 组合技能为锁定技，是否受「非锁定技失效」影响（按锁定技语义不受影响）；
  5. AI 对两个技能与组合效果的决策权重。
