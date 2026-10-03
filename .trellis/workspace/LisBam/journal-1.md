# Journal - LisBam (Part 1)

> AI development session journal
> Started: 2026-09-22

---



## Session 1: 重建 Trellis 项目规范分层
<!-- trellis-session: v=2 fp=691555545ec52b4a -->

**Date**: 2026-09-23
**Task**: 重建 Trellis 项目规范分层
**Branch**: `master`

### Summary

确认本项目文档需要同步至 Trellis，并按其要求完成 spec 重建：删除不适用的 backend/frontend Web 模板，按 Godot/GDScript 项目真实分层重建为 project/content/core/ui/adapters + guides 共 22 个规范文件；同步归档引导任务。

### Main Changes

- 删除 .trellis/spec/backend 与 frontend 两套 Web 模板
- 新增 spec 总导航与五个分层规范（project/content/core/ui/adapters）
- 按 Trellis 契约在各层 index.md 加入 Pre-Development Checklist 与 Quality Check
- 本地化 guides 共享思维指南，移除与本项目无关的模板内容
- 归档 00-bootstrap-guidelines 引导任务

### Git Commits

| Hash | Message |
|------|---------|
| `e5fdb33` | 1. 移除不适用的 Trellis 前后端规范模板 2. 新增 Trellis 项目分层开发规范 3. 新增项目级协作与注释规范 4. 新增文档同步与验证规范 5. 新增内容源码层制作规范 6. 新增权威规则层与事件运行时规范 7. 新增界面表现层开发规范 8. 新增适配层 AI 与网络规范 9. 新增自动加载与平台适配规范 10. 本地化 Trellis 共享思维指南 |

### Testing

- [OK] get_context.py --mode packages 输出 Spec layers: adapters, content, core, project, ui
- [OK] spec 内 56 条相对链接全部有效，零断链
- [OK] spec 内无 To fill / TODO / placeholder 占位符残留

### Status

[OK] **Completed**

### Next Steps

- 后续编码任务按 trellis-before-dev 读取对应分层规范


## Session 2: 新增星际和平公司势力、武将真珠、真实轮末时机与牌面复制视为
<!-- trellis-session: v=2 fp=f81ebc9fe992b86b -->

**Date**: 2026-09-30
**Task**: 新增星际和平公司势力、武将真珠、真实轮末时机与牌面复制视为
**Branch**: `master`

### Summary

登记星际和平公司势力（铜色、简称“司”）与武将真珠（女性、3点体力），新增【补缀】（欢愉技104，轮末扣盾）与【鉴映】（出牌阶段限一次，连花色点数一起视为）；为此新增真实轮末时机 roundEnd 与可暂停的轮末步骤序列、手牌牌面复制视为端口，并修正固有技能持有者死亡后收不到维护时机的核心缺陷。36 项广域回归与新增专项全部通过，文档与 .trellis/spec 已同步。

### Main Changes

- 新增 game_data/factions.json 的星际和平公司（xingjihepinggongsi/司/b87333）
- 新增武将 zhenzhu.gd（女性、3点基础体力、技能顺序【补缀】【鉴映】）
- 新增技能 buzhui.gd：欢愉技104，可选0至3名目标各获得1点护盾，roundEnd 逐条失去1点护盾
- 新增技能 jianying.gd：出牌阶段限一次的三段展示与连花色点数视为流程
- 新增 roundEnd 时机（目录236）与轮末步骤序列，并区分 round_end_restore / round_end_after_restore 两种续接
- 新增 CardInstance.set_hand_view_as_with_face 与控制器端口，表现为横幅显示花色点数加视为牌名
- 修正 skill_definition.gd 的获得技能额度检查误拦截固有技能死亡后清理的问题
- 新增 tests/zhenzhu_mechanics_test（10个场景），同步 rule_timing、smoke、conquest_coop、gameplay_regression 断言
- 同步内容制作指南、游戏机制与玩法内容、战斗框架回归说明、README 与五份 .trellis/spec 规范

### Git Commits

| Hash | Message |
|------|---------|
| `9deeb35` | 新增星际和平公司势力、武将真珠、真实轮末时机与牌面复制视为机制 |
| `8faaf4f` | 同步真珠机制、轮末时机与视为牌复制的文档与项目规范 |

### Testing

- [OK] [OK] zhenzhu_mechanics PASS faction=xingjihepinggongsi hp=3 buzhui=104 jianying=face_view_as round_end=sequential
- [OK] [OK] 35项广域回归加 zhenzhu_mechanics 共 36/36 退出码 0，日志无 ERROR/SCRIPT ERROR/FAIL
- [OK] [OK] 补充复跑 ui_layout、virtual_card_color、phase_sequence、card_back_overlay 全部 PASS

### Status

[OK] **Completed**

### Next Steps

- 换将替换真珠时未到期记录会随实例卸载丢失，仍属已知边界；需要跨换将保留时改用 character_form_state
- 欢愉技参演编号与视为牌复制口径已写入 spec，后续新增内容按同一口径实现


## Session 3: 新增主演机制与白露、刃两名武将
<!-- trellis-session: v=2 fp=12af57958e813fc5 -->

**Date**: 2026-09-30
**Task**: 新增主演机制与白露、刃两名武将
**Branch**: `master`

### Summary

实现「主演」全局唯一状态与座次相邻查询，新增白露（悬壶/生息）、刃（万死/支离）两名武将与四条技能的规则及完整 AI，星核猎手改为黑紫配色，并补齐专项回归与文档。

### Main Changes

- 新增 StarringRoleService 保证主演全局唯一并复用酩酊同款角标
- 新增 GameState 座次相邻查询与三个技能纯查询钩子
- 新增白露【悬壶】【生息】与刃【万死】【支离】及配套 AI
- 调整星核猎手势力主题色为黑紫色
- 新增专项回归用例覆盖设计文档全部 23 条验收断言
- 同步内容制作指南、游戏机制与玩法内容、AI 模块等文档

### Git Commits

| Hash | Message |
|------|---------|
| `97c87fc` | 新增主演机制与白露、刃两名武将 |

### Testing

- [OK] 全量 71 个 headless 测试场景 0 失败
- [OK] smoke_test / ai_policy_test / new_character_mechanics_test / phase_progression_test / corner_badge_test / zhuyan_zhili_test 全部通过
- [OK] 四条技能 description 与需求原文逐字比对一致

### Status

[OK] **Completed**


## Session 4: 调整【好活】弃置逻辑与防具无效攻击的AI收益口径
<!-- trellis-session: v=2 fp=41691c179edbba86 -->

**Date**: 2026-09-30
**Task**: 调整【好活】弃置逻辑与防具无效攻击的AI收益口径
**Branch**: `master`

### Summary

【好活】改为先选场上（判定区或装备区）有牌的角色、再弃置其场上的一张牌；被【藤甲】与【仁王盾】完全无效的攻击目标收益由0改为明确负值。

### Main Changes

- 【好活】弃置场上牌改为两步交互：第一步选择场上有牌的角色，第二步弃置该角色场上的一张牌
- 新增场上可弃置角色与单角色场上候选两个核心端口，并抽取共用候选构建入口
- 新增 ARMOR_VOID_TARGET_PENALTY 负收益常量并替换防具完全无效目标的0收益
- 同步内容制作指南、AI模块、游戏机制与玩法内容、卡牌系统、界面与交互与README

### Git Commits

| Hash | Message |
|------|---------|
| `0a7e33e` | 调整【好活】弃置逻辑与防具无效攻击的AI收益口径 |

### Testing

- [OK] AI_POLICY_PASS cards=46；HUANYU_YAOGUANG_XING_QIONG_PASS
- [OK] 40余项相关回归场景（战斗、伤害、时机、技能结算、机会系统、欢愉与阿哈时刻）全部通过
- [OK] git diff --check 通过

### Status

[OK] **Completed**


## Session 5: 重构【凶星】为角色持续效果并新增【桃】留桃AI
<!-- trellis-session: v=2 fp=4ad0360720bfa2b9 -->

**Date**: 2026-10-01
**Task**: 重构【凶星】为角色持续效果并新增【桃】留桃AI
**Branch**: `master`

### Summary

新增角色持续效果基类、托管服务与目录扫描，把【凶星】伤害结算从技能实例迁移到挂在目标身上的效果，使层数在爻光阵亡、换将与非锁定技失效下都继续生效；新增【桃】参考无名杀的留桃AI；归档记录牌名表现形式任务。

### Git Commits

| Hash | Message |
|------|---------|
| `4275829` | ﻿重构【凶星】伤害结算为角色持续效果并新增【桃】留桃AI |

### Status

[OK] **Completed**


## Session 6: 新增回合操控机制（本回合由xx操控）与局域网代理提交协议
<!-- trellis-session: v=2 fp=8c41d7a02e93b5f6 -->

**Date**: 2026-07-26
**Task**: `.trellis/tasks/10-02-turn-control-mechanism/`（父任务 `10-02-kafuka-new-mechanics` 的子任务）
**Branch**: `master`

### Summary

实现《崩铁杀》卡芙卡需求的三个新机制中的第一个——**「本回合由xx操控」**：操控者接管被操控者的本回合操作权，被操控者只能旁观，操控结束后操控者回到原来的角色。按需求方改判，局域网一并交付**完整代理提交协议**（不做基础 AI 降级）。

**规则事实**：新增 `PlayerState.turn_input_delegate_id`（`-1` = 本人；`>= 0` = 由该 `player_id` 操控）。它是唯一权威、公开可序列化，因此观察者快照、AI 快照、权威存档与回放四条通道自动往返，沿用「主演」的既有口径。

**端口与判定**：`begin/end_turn_input_delegation()` 与两个只读查询；五条前置校验（存在且在场地、禁止自环、被操控者必须是当前回合角色、禁止链式操控、幂等/顶替）任一失败零副作用。**唯一代理解析入口** `_resolve_turn_input_submitter()` 被输入锁定、可作答判定与房主授权复核三处共用。

**到期与清理**：被操控者回合结束（`phaseAfter` 派发前）自动到期，用「回合角色 + 回合号」双重匹配保证无关角色回合结束不误清除；翻面被跳过的回合没有回合结束语义，改由下一个真实回合清除；死亡/离场在与 `clear_starring` 同处清理。

**第一视角**：离线复用 `_set_offline_manual_control_player()`（不新增第二套实现），优先级高于「控制所有角色」；新增离线影子值 `_offline_human_identity_id` 承载「本机真人是谁」，与会被改写的 `local_human_player_id` 分离。

**局域网协议**：新增按观察者裁剪的 `turn_input_controlled_actor_ids`、控制器单向下发给网关的代理授权表（网关零规则语义）、以被操控者为观察者的定向权重快照、掉线即清登记与授权、重连只重发授权表、授权不可用时显式降级（`lan_turn_control_degraded`）。`PROTOCOL_VERSION` 不提升（纯增量，旧客户端安全退化）。

**验证过程中修复的七个真实缺陷**（详见 `临时反馈文档.md`）：输入锁定作用域过宽、接管擦除本机真人身份、`_bound_local_player_id()` 离线误用 LAN 绑定值、锁定函数漏接提交入口、房主复核误拒内部 AI 提交、过期发送者上下文被本机动作继承、被操控座位重复注册 AI 抢占真人输入通道。

### Git Commits

| Hash | Message |
|------|---------|
| `14e110c` | 新增回合操控机制、局域网代理提交协议与专项回归测试 |

### Testing

- [OK] `TURN_CONTROL_PASS begin_guard+idempotence+proxy_submit+input_lock+answerable+expiry+cleanup+snapshot+view_takeover`
- [OK] `LAN_TURN_CONTROL_PASS proxy_submit+outsider_rejected+self_rejected+authorization_scope+disconnect+reconnect+degradation`
- [OK] `SMOKE_PASS game_over winner=renegade actions=267`
- [OK] `CONTROL_ALL_CHARACTERS_PASS` / `ZHUYAN_ZHILI_PASS` / `PHASE_PROGRESSION_PASS` / `GAMEPLAY_REGRESSION_PASS`
- [OK] `LAN_NETWORK_PASS` / `LAN_MATCH_FLOW_PASS` / `LAN_RECONNECT_PASS` / `LAN_KICK_REJOIN_PASS` / `MATCH_REPLAY_PASS`
- [OK] `UI_LAYOUT_PASS` / `AI_POLICY_PASS` / `PERFORMANCE_AND_PACING_PASS` / `STALL_WATCHDOG_PASS` / `AUTO_MANAGEMENT_PASS` / `EVENT_RUNTIME_PASS` / `SKILL_SETTLEMENT_RUNTIME_PASS`
- [OK] 内容侧 `NEW_CHARACTER_MECHANICS_PASS` / `TINGYUN_MECHANICS_PASS` / `ZHENZHU_MECHANICS_PASS`
- [OK] 合计 22 个测试场景全部 PASS，`GameDatabase.validation_errors` 为空

### Status

[OK] **Completed**（已提交并归档至 `.trellis/tasks/archive/2026-10/10-02-turn-control-mechanism/`）


## Session 7: 新增专属锦囊牌与不可知置牌机制
<!-- trellis-session: v=2 fp=kafuka-exclusive-card-private-placement -->

**Date**: 2026-10-03
**Task**: `.trellis/tasks/10-02-exclusive-card-and-private-placement/`（父任务 `10-02-kafuka-new-mechanics` 的子任务）
**Branch**: `master`

### Summary

交付卡芙卡需求的另两个机制底座（**不含任何卡牌、技能或武将**）：①**专属锦囊牌**——「正常情况不加入游戏中，只有被其他角色的技能或其他情况触发时才会按要求加入游戏」；②**「其他角色不可知」与牌堆位次置牌**——「只有使用者知道，不出现在对局记录中，其他角色不知道」，含「把一张手牌置于牌堆顶第一张或第二张」的权威端口与三选项交互。

### Main Changes

- 新增 `CardDefinition.is_exclusive()`：只读 `_metadata["exclusive"]` 的纯查询，缺省 `false`，既有 46 张牌行为逐字节不变
- 新增 `MatchController.create_and_insert_card_into_draw_pile()`：按定义造实体牌并按位次入堆，返回新 UID，五类非法输入零副作用；牌面缺省时用权威随机源并写 `random_history`
- 新增 `CardMovementService.insert_new_card_into_draw_pile()` 与 `@N` 位次解析（`_parse_draw_pile_position`），默认路径仍是原 `append()`，既有 5 处 `draw_pile` 写入点行为不变
- 新增 `PlayerState.private_pile_placement` 私有事实字段 + `from_authoritative_dict` 恢复 + 可见性裁剪
- 新增 `set/get/clear_private_pile_placement()` 唯一写点端口与 `place_hand_card_on_draw_pile_top()` 秘密置牌端口（不写日志、不产生公开表现、清空牌面知识残留）
- 新增 `card_position` 选择类型、三个稳定选项与 UI 位次询问窗口（恰好三个按钮，未选牌时位次按钮不可用）
- 新增 `_build_card_choice_actions()` 的 `card_position` 分支（合法动作数 = 候选牌数 × 2 + 1）
- 新增图鉴与牌面的专属牌标识，并在内容规范中补专属牌例外
- 新增 `tests/exclusive_card_and_private_placement_test`（7 个阶段标记，覆盖 AC1–AC17）
- 同步内容制作指南、游戏机制与玩法内容、卡牌系统、界面与交互、AI 模块、README

### Key Decisions

- **可见性条件收紧为 `reveal_private and viewer_id == player_id`**：只用 `reveal_private` 会让每个 AI 读到别人的置牌事实（AI 快照是 `to_dict(该AI, true)`）；只用 `viewer_id == player_id` 会把事实写进回放（本地广播快照 `to_dict(本机真人, false)` 被整体录制）。两个条件缺一不可。
- **不新增 `type` 取值表达专属**：核心多处按 `type == "trick"` 分支，新增 `type` 会让专属牌整体漏掉；改用可选元数据键，零分支改动。
- **不新增第二套选择框架**：位次询问复用 `ChoiceRequest`，取消角色由请求上下文键 `control_cancel_option_id` 声明，界面不硬编码选项 ID。
- **不回用 `_move_card_with_timings()`**：避免把「手牌离区 + reason」派发给所有技能而泄露秘密放置。

### Git Commits

| Hash | Message |
|------|---------|
| `a0b68f1` | 新增专属锦囊牌机制与不可知置牌机制（23 项，含端口、交互、图鉴标识、专项测试与六份文档同步） |

### Testing

- [OK] `EXCLUSIVE_CARD_PRIVATE_PLACEMENT_PASS card_field+validation+insert_pile+private_fact+broadcast_boundary+position_protocol+panel_usability`
- [OK] `SMOKE_PASS` / `GAMEPLAY_REGRESSION_PASS wuxie=1 aoe=1 dying=1 taoyuan=2 zhuque=1 yinyue=1 zhangba=2 judge=2`
- [OK] `EVENT_RUNTIME_PASS` / `SKILL_SETTLEMENT_RUNTIME_PASS faults=1` / `PHASE_PROGRESSION_PASS` / `TURN_CONTROL_PASS`
- [OK] `LAN_TURN_CONTROL_PASS` / `LAN_NETWORK_PASS` / `LAN_MATCH_FLOW_PASS` / `MATCH_REPLAY_PASS`
- [OK] `CARD_ACTION_SEMANTICS_PASS` / `INLINE_HAND_CHOICE_PASS` / `ZONE_ABOLITION_PASS` / `DAHEITA_MECHANICS_PASS`
- [OK] `UI_LAYOUT_PASS viewport=(1152.0, 648.0)` / `FONT_COLOR_AUDIT_PASS` / `CORNER_BADGE_PASS` / `CARD_BACK_OVERLAY_PASS` / `VIRTUAL_CARD_COLOR_PASS` / `MAIN_MENU_PASS`
- [OK] `AI_POLICY_PASS cards=46` / `ZHUYAN_ZHILI_PASS` / `NEW_CHARACTER_MECHANICS_PASS` / `PERFORMANCE_AND_PACING_PASS` / `GAME_SETTINGS_PERSISTENCE_PASS`
- [OK] `GameDatabase.validation_errors` 为空；脚本零 WARNING

### Status

[OK] **Completed**（已提交并归档至 `.trellis/tasks/archive/2026-10/10-02-exclusive-card-and-private-placement/`）

### Next Steps

- 剩余内容子任务（尚未创建）：卡牌【言灵】（梅花K 延时锦囊·专属）、武将卡芙卡、技能【言灵】与【游丝】及其配套 AI
- 技能【言灵】开场布三张牌 = 调用 `create_and_insert_card_into_draw_pile("yanling", "", 0, 1)` 三次；技能【游丝】直接调用 `request_hand_card_pile_position()` 与 `place_hand_card_on_draw_pile_top()`
- 后续 AI 必须按 `项目专属AGENTS.md` 2.3 扩展**通用**决策逻辑并写明扩展范围，不能只写需求提示里的那一条分支


## Session 8: 新增卡牌【言灵】、武将卡芙卡与技能【言灵】【游丝】
<!-- trellis-session: v=2 fp=kafuka-yanling-card-character-skills -->

**Date**: 2026-10-04
**Task**: `.trellis/tasks/archive/2026-10/10-02-yanling-card/` 与 `.trellis/tasks/archive/2026-10/10-02-kafuka-character-and-skills/`（父任务 `10-02-kafuka-new-mechanics` 的最后两个子任务）
**Branch**: `master`

### Summary

交付卡芙卡需求链的**最后三段内容**，父任务的四个子任务至此全部归档：①专属卡牌【言灵】（梅花K 延时锦囊，判定为梅花且场上有「主演」时本回合由主演操控）；②武将卡芙卡（星核猎手/女/体力上限 3）与技能【言灵】（锁定技：`gameStart` 随机布三张牌、任意角色使用延时锦囊牌时摸 1 张并成为主演）；③技能【游丝】（其他角色回合开始秘密置牌、该回合结束按其手牌判定二段收益）与两段配套 AI。

### Main Changes

- 新增 `game_data/cards/yanling.gd`：`trick`/`delayed`/`exclusive`、自带牌面梅花K、判定三条件、AI 硬门槛（队友 `6.0` / 拒绝 `-100.0` / 非最近敌人 `-100.0`）
- 新增 `game_data/characters/kafuka.gd`：星核猎手、女、体力上限 `3`、技能顺序【言灵】【游丝】
- 新增 `game_data/skills/yanling.gd`：`subscribe_timing("gameStart"|"useCard", …, "global")`；入堆 3 次且位次为 `DRAW_PILE_POSITION_RANDOM`；延时锦囊识别用 `type=="trick" and delayed==true`
- 新增 `game_data/skills/yousi.gd`：`phaseBefore`/`phaseAfter` 均 `role="global"`；置牌 → 私有事实 → 压力效果；二段按 `turn_player_id + turn_number` 双重匹配、**先无条件清事实**、候选为明示手牌 + 装备区（不含判定区）
- 新增 `game_data/effects/yousi_pressure.gd`：`get_ai_hand_pressure() = 3.0`，随承载角色本回合结束自行移除；持久状态写在**承载角色自己**的 `character_form_state`（`yousi_pressure_active`）
- 新增通用 AI 压力通道：`PlayerEffect.get_ai_hand_pressure()`（基类 `0.0`）→ `PlayerEffectService` 求和 → `MatchController.get_ai_hand_pressure()` → `AICoordinator.request_action(..., hand_pressure)` → `BasicAIPolicy.set_hand_pressure()/`_get_hand_pressure_bonus()`（只给消耗自己手牌的动作加分，一次决策后清零）
- 新增 `NonameAIEvaluator.get_starring_player_id()` 与 `should_dump_hand_against_starring()`：只用公开角标与态度，不读隐藏信息
- 新增 `tests/kafuka_mechanics_test.gd/.tscn`（7 个阶段标记、看门狗 20 秒）
- 修复 `tests/conquest_coop_test.gd` 的座位敏感性：新增 `_settle_pending_resolution_choice()` 在机缘解析期间结算无人驱动的窗口；超时诊断补充 `pending_kind/pending_chooser/lineup/hp`
- 同步 `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/卡牌系统.md`、`docs/AI模块.md`、`docs/界面与交互.md`、`README.md`、`.trellis/spec/content/`（index/skill-authoring/content-ai）与 `临时反馈文档.md`

### Key Decisions

- **延时锦囊不写牌名白名单**：判定口径为 `type == "trick"` 且 `delayed == true`，未来新增的延时锦囊自动纳入，符合内容自包含规范。
- **两种时机都必须 `role="global"`**：`gameStart` 的 `player_id` 恒为 `-1`（`role="player"` 静默收不到）；「一名角色」「其他角色」原文本就跨角色。
- **【游丝】的私有事实不复用 `character_form_state`**：其序列化条件是 `reveal_private`，而 AI 快照是 `to_dict(该AI, true)`，复用会让每个 AI 读到秘密。
- **「其他AI」提示降级为公开门槛下的标量倾向**：字面实现要求 AI 知道牌堆顶两张，与同一需求里的「其他角色不可知」直接冲突，且 AI 评估器是纯快照函数；改为「消耗自己手牌加分」并由公开主演角标 + 态度设门槛。
- **两个位次在常规分支同分**：AI 评分必须确定性（否则回放不可复现），随机性交给既有枚举顺序。
- **压力效果的持久状态必须写在承载角色自己身上**：宿主重建探测用的是**未绑定 host** 的实例（`GameDatabase.create_player_effect()` 不 `bind()`），因此 `has_persisted_state(player)` 只能读传进来的那个角色的状态。初版依赖 `host` 读取**卡芙卡**的置牌事实，导致该函数在真实调用路径上恒为 `false`（读档后压力静默消失），已修复并补断言。

### Git Commits

| Hash | Message |
|------|---------|
| `585c8f6` | 新增卡牌【言灵】、武将卡芙卡与技能【言灵】【游丝】（24 项，含两段技能与 AI、压力通道、专项测试、文档同步、子任务归档与协作测试修复） |
| （本次） | 修复游丝压力效果读档探测恒判无状态、持久状态改写到承载角色自身、补充可重建与清除断言 |

### Testing

- [OK] `KAFUKA_MECHANICS_PASS metadata+gameStart+delayedTrick+placement+privateFact+gain+aiPressure`
- [OK] `SMOKE_PASS`（卡牌 47 / 技能 102 / 武将 48）/ `AI_POLICY_PASS cards=47`
- [OK] `EXCLUSIVE_CARD_PRIVATE_PLACEMENT_PASS` / `ZHUYAN_ZHILI_PASS` / `TURN_CONTROL_PASS` / `LAN_TURN_CONTROL_PASS`
- [OK] `GAMEPLAY_REGRESSION_PASS` / `NEW_CHARACTER_MECHANICS_PASS` / `CARD_ACTION_SEMANTICS_PASS` / `MAIN_MENU_PASS`
- [OK] `PHASE_PROGRESSION_PASS` / `RULE_TIMING_PASS catalog=236` / `DRAW_SEQUENCE_PASS` / `OPPORTUNITY_SYSTEM_PASS`
- [OK] `MATCH_REPLAY_PASS` / `PERFORMANCE_AND_PACING_PASS` / `STALL_WATCHDOG_PASS`
- [OK] `CONQUEST_COOP_PASS`（修复前因新增第 48 名武将改变固定种子座位而超时；已在未改动的 HEAD 基线工作树确认基线通过）
- [OK] 六个新增/改动脚本 `--check-only` 全部零错误
- [OK] 反事实验证：把 `yousi_pressure.has_persisted_state()` 改成恒 `false` → `KAFUKA_FAIL yousi_pressure_not_restorable`（改动已还原并重跑通过）
- [OK] `CONQUEST_SAVE_PASS` / `CONQUEST_MODE_PASS` / `WHEEL_DUEL_MODE_PASS` / `CONQUEST_SINGLE_PLAYER_PASS`
- [KNOWN] `audio_system_test` → `AUDIO_SYSTEM_FAIL card_voice_auto_respond_missing=87`：**既有缺陷**，在未改动的 HEAD 基线工作树同样复现同一数字

### Status

[OK] **Completed**（已提交并归档至 `.trellis/tasks/archive/2026-10/10-02-yanling-card/` 与 `…/10-02-kafuka-character-and-skills/`）

### Next Steps

- 父任务 `10-02-kafuka-new-mechanics` 的四个子任务全部归档，跨子任务验收标准全部勾选
- 可选后续：卡芙卡插画与技能/阵亡语音素材；`tests/audio_system_test.gd` 的既有失败（`card_voice_auto_respond_missing`）


## Session 9: 更正游戏开始时时机、位次询问内联交互与按技能ID名单清算永久失去
<!-- trellis-session: v=2 fp=055ab2cc48d324e7 -->

**Date**: 2026-10-04
**Task**: `.trellis/tasks/archive/2026-10/10-04-kafuka-followup-fixes/`（父任务 `10-02-kafuka-new-mechanics` 的三个收口修正）
**Branch**: `master`

### Summary

处理卡芙卡内容交付后的三条收口意见：把牌堆位次询问从独立窗口改为操作区内联交互；把【留白】的「失去所有技能」从整体开关改为按技能ID名单清算，使清算后新获得的技能不受影响；把「游戏开始时」更正为手气卡之后、第一轮之前的正式开局时刻并补上发动记录与提示。

### Main Changes

本批次处理需求方在卡芙卡内容交付后提出的三条收口意见，任务记录见 `.trellis/tasks/archive/2026-10/10-04-kafuka-followup-fixes/`。

#### 需求一 · 位次询问改用操作区内联交互

- `choice_type = "card_position"` 不再打开 `CardSelectionPanel` 独立窗口，改由 `_is_inline_control_choice()` 接管，与【咬它】同形态：手牌候选在牌手区点亮，三个选项渲染为操作行按钮
- 前两项复用 `%UseButton` / `%CancelButton`，第三项由 `_append_inline_control_option_button()` 追加；请求已声明取消选项（上下文键 `control_cancel_option_id`）时不再追加 `InlineControlCancelButton`，可见按钮恰好三个
- 新增 `_is_inline_control_card_selection_ready()` / `_get_inline_control_cancel_option_id()` / `_is_inline_control_option_submittable()`：取消选项恒可提交，其余选项需同时满足手牌维度与目标维度，界面不硬编码任何选项 ID
- 移除 `CardSelectionPanel` 的 `position_submitted` 信号、位次按钮集合、`_show_card_position_request()`／`_add_position_options()`／两个位次回调与 `card_position` 渲染分支（净删 106 行）
- 重写 `tests/exclusive_card_and_private_placement_test.gd` 的界面阶段为内联断言（面板不可见、操作行恰好三个按钮、未选牌时位次按钮禁用、取消不写入任何状态、确认携带手牌与位次）

#### 需求二 · 永久失去改为按技能ID名单清算

- `PlayerState` 新增 `permanently_removed_skill_ids` 与 `mark_skill_permanently_removed()` / `has_permanently_removed_skill()` 两个薄端口并进入 `to_dict`；旧布尔 `skills_permanently_removed` 保留为迁移与旧版本降级标记，规则判定不再读取
- `remove_all_skills_permanently()` 先在卸载与清空前快照「此刻确实拥有的技能ID」（技能实例表 ∪ 获得技能 ∪ 临时技能，稳定ID去重），逐个记名单；无技能可失去时返回 `false`，不重复写日志与广播；清算时一并清空 `recorded_card_names`
- 五条装配路径逐项拦截：批量安装、换将重装、局内获得、存档补装、复原武将牌技能；两个重置端口不再整体拦截（名单内固有技能由复原路径逐项过滤，名单外新技能仍正常归零额度）
- 旧存档迁移：读档后首次装配时若「布尔为真且名单为空」，把该角色此刻本应安装的技能补记进名单
- 界面按名单逐项剔除：`MatchTable._get_visible_skill_ids()` 与 `PlayerTargetView._request_character_information()` 改为读名单；武将牌角标不再按整体标记清空（角标不携带技能归属，主演／凶星条目与技能无关）
- `game_data/skills/shengbian.gd` 的军功触发评分改为读名单逐项过滤

#### 需求三 · 「游戏开始时」更正为正式开局时刻

- `MatchController._complete_pre_game_start()` 成为 `gameStart` 的唯一派发点：起始手牌与手气卡全部结束之后、第一轮之前，派发期间阶段回到 `game_start`，完成后切到 `round_start`
- `game_data/skills/yanling.gd` 改为**先** `announce_activation({"insert_count":3, "insert_position":0})`（写技能历史、公开提示与 `skillAfter` 时机）**再**逐张插牌；`insert_position` 是位次口径（`0` = 权威随机位次），公开字段不泄露真实落点
- `RuleTimingCatalog` 的开局时机顺序调整为 `enterGame → gameDrawBefore → gameDrawBegin → gameDrawAfter → gameStart → roundEnd → roundStart`
- `tests/kafuka_mechanics_test.gd` 新增 `gameStartTimingAfterMulligan` 阶段：断言游戏开始时机的派发在起始手牌与手气卡之后，且手气卡刷新不可能刷到三张专属牌

#### 关键决策

- **位次询问复用内联分流而不是新写交互**：该询问的选项是纯文字，正好落在「文字选项 + 操作行按钮」分支的适用条件内；改一个 `in [...]` 列表与三个小判定函数，比新增一套交互组件更符合低耦合
- **「失去技能」的状态用名单而非开关**：开关只能表达「这个角色以后不能再有技能」，与需求「这些技能回不来、以后新得的照常」不符；名单同时解决界面整体清空技能栏与角标的连带损伤
- **旧布尔量双写不双读**：新存档同时写出名单与布尔量，旧版本读到新存档时按「全部失去」降级；新代码只按名单判定，避免两套真相
- **时机名字与派发位置互为定义**：把顺序常量、技能注释、玩法文档与回归断言一起对齐，防止「文档说发牌前、代码已到发牌后」的漂移

#### 追加 · 【言灵】开局张数由三张改为五张

- 需求方在本轮末尾把 `INSERT_COUNT` 改为 `5` 并同步玩家可见描述「随机加入五张【言灵】」，因此把全链路口径统一为五张：技能源码（含六处注释）、武将简介、专项回归（`EXPECTED_INSERT_COUNT` 与描述原文）、控制器两处注释、玩法文档 7 处、制作指南 2 处、README 测试说明
- `.trellis/tasks/archive/2026-10/10-02-*` 的历史 PRD／design 保留当时的需求原文「三张」，作为归档记录不回改
- 规范补充两条可复用规则：界面规范写清「文字选项询问走操作区内联、只有需要看牌面或牌名候选才开独立窗口」的分流条件与「选项可用性由选项自身决定、界面不硬编码选项ID」；核心规范写清 `gameStart` 在开局顺序中的位置（起始手牌与手气卡之后）与「必须走 `announce_activation()`、`context` 不放隐藏信息」的约束


### Git Commits

| Hash | Message |
|------|---------|
| `c3e567a` | 1. 修正「游戏开始时」的派发位置为起始手牌与手气卡之后、第一轮之前的正式开局时刻 2. 调整公开时机目录中开始时机与开局时机的排列顺序 3. 新增【言灵】开局布牌的发动公告与发动记录 4. 新增开局布牌先宣告发动再逐张插牌的顺序约束说明 5. 新增开局时机排在手气卡之后与手气卡无法刷到专属牌的回归断言 |
| `27922e6` | 1. 调整牌堆位次询问的分流判定为操作区内联询问 2. 新增内联文字选项的手牌维度可用性判定 3. 新增请求声明的取消选项识别与取消提交语义 4. 新增内联分支的额外选项按钮与取消按钮去重规则 5. 移除选牌面板的位次询问分支、位次按钮集合与提交信号 6. 调整位次询问技能端口的注释为内联交互口径 7. 重写位次询问的界面回归为内联形态断言 |
| `631f149` | 1. 新增玩家状态的永久失去技能ID名单字段与读写端口 2. 调整永久失去清算为逐项快照并逐个记入技能ID名单 3. 调整五条技能装配路径为按名单逐项拦截 4. 移除两个重置端口对永久失去角色的整体拦截 5. 新增旧存档布尔标记到技能ID名单的迁移 6. 调整界面技能栏与武将信息为按名单逐项剔除技能 7. 调整武将牌角标不再按整体标记清空 8. 调整升变军功评分按名单逐项过滤技能 9. 新增技能清算时一并清空技能产生的记录牌名 10. 新增永久失去名单的清算、新获得技能不受影响、存档往返与五条装配守卫断言 |
| `6db5420` | 1. 同步界面文档的位次询问内联交互与技能失去后的界面收敛口径 2. 同步玩法内容文档的开局顺序、言灵发动记录与留白永久失去名单口径 3. 同步内容制作指南的位次询问界面用法、言灵与游丝条目与时机目录顺序 4. 同步架构说明的永久失去名单状态位置与界面收敛责任划分 5. 同步内容规范的游戏开始时时机位置与发动公告约束 6. 同步复用指南的逐项移除与整体开关反例 7. 同步 README 的那刻夏回归测试说明 |
| `89bbe80` | 1. 补充武将卡芙卡的立绘与缩略图资源 2. 补充卡芙卡立绘资源的导入配置 |
| `017fd8a` | 1. 记录卡芙卡交付后三项收口修正的任务记录与会话日志 2. 补记第6至第8次会话的历史索引行 |
| `9596c11` | 1. 调整【言灵】开局加入牌堆的张数为五张 2. 调整【言灵】技能玩家可见描述为随机加入五张 3. 调整卡芙卡武将简介的专属锦囊张数 4. 调整卡芙卡专项回归的张数期望与描述断言 5. 同步造牌入堆端口与游戏开始派发点的张数注释 6. 同步玩法内容文档的五张口径与发动记录 7. 同步内容制作指南的言灵条目与端口随机口径 8. 同步 README 的卡芙卡专项测试说明 |
| `a01cdd6` | 1. 补记言灵开局张数调整的任务实施记录与会话日志 |
| `4adcdc0` | 1. 补充界面规范的文字选项询问内联分流与独立窗口适用条件 2. 补充核心规范的游戏开始时时机位置与发动公告约束 |

### Testing

- [OK] 全量 82 个测试场景连跑：仅 audio_system_test 在整批连跑中偶发失败，其余全部 PASS
- [OK] NAKEXIA_MECHANICS_PASS sections=2 phase_limit=2 jiezhi_per_game=2 jiezhi_self_reset=1 reset_keep_self=1 permanent_loss=2 permanent_new_skill=1 nested_trigger_entry=1
- [OK] EXCLUSIVE_CARD_PRIVATE_PLACEMENT_PASS card_field+validation+insert_pile+private_fact+broadcast_boundary+position_protocol+inline_usability
- [OK] KAFUKA_MECHANICS_PASS metadata+gameStart+delayedTrick+placement+privateFact+gain+aiPressure+gameStartTimingAfterMulligan
- [OK] RULE_TIMING_PASS catalog=236 active=4 roles=4 / PRE_GAME_CUSTOMIZATION_PASS / SMOKE_PASS / AI_POLICY_PASS cards=47
- [OK] 反事实验证：把 grant_acquired_skill() 的守卫改回整体布尔量 → NAKEXIA_FAIL permanent_new_skill_blocked（已还原并重跑通过）
- [KNOWN] audio_system_test 在整批连跑中偶发 AUDIO_SYSTEM_FAIL card_voice_auto_respond_missing=128；随后单独连跑 2 次均为 AUDIO_SYSTEM_PASS，且本批次未改动任何音频文件，属既有时序敏感用例
- [OK] 张数改为五张后复跑 KAFUKA_MECHANICS_PASS metadata+gameStart+delayedTrick+placement+privateFact+gain+aiPressure+gameStartTimingAfterMulligan

### Status

[OK] **Completed**

### Next Steps

- 可选后续：卡芙卡技能与阵亡语音素材；为 card_position 之外的文字选项询问补充内联可用性断言


## Session 10: 留白改为一次性失去当前技能并新增通用失去技能端口
<!-- trellis-session: v=2 fp=liubai-one-shot-skill-loss -->

**Date**: 2026-10-04
**Task**: `.trellis/tasks/archive/2026-10/10-05-liubai-one-shot-skill-loss/`（父任务 `10-04-kafuka-followup-fixes`）
**Branch**: `master`

### Summary

按需求方复审意见，把 `10-04` 交付的「按技能ID名单永久失去」**整体替换**为「只失去当前持有的技能、一次性生效、不做后期维护」：状态层不再保存任何“已失去技能”的字段，规则层新增通用端口 `remove_skill()`（失去某个技能）与 `remove_all_skills()`（失去所有技能），界面改为按公开快照的**实际安装集合** `installed_skill_ids` 收敛，使失去的技能立即从技能栏、悬停武将资料与右键武将详情三处消失，而重新获得的技能立即恢复显示。

### Main Changes

- `scripts/data/player_state.gd`：删除 `permanently_removed_skill_ids` 与 `skills_permanently_removed` 两个字段、它们的 `to_dict`／`from_authoritative_dict` 往返，以及 `mark_skill_permanently_removed()`／`has_permanently_removed_skill()` 两个端口
- `scripts/core/match_controller.gd`：`remove_all_skills_permanently()` → 通用 `remove_skill(player_id, skill_id, reason)` + 批量 `remove_all_skills(player_id, reason)`；五条装配路径（批量安装、换将重装、局内获得、存档补装、复原武将牌技能）删除全部按技能ID的拦截与旧布尔迁移；`_install_all_character_skills()` 改为接收 `saved_installed_skill_ids_by_player`；`_append_limited_skill_usage_to_snapshot()` 补充 `installed_skill_ids`；`_build_conquest_save_data()` 写出该字段、读档循环组装参数
- `game_data/skills/liubai.gd`：结束阶段改调 `remove_all_skills()`；`game_data/skills/shengbian.gd`：军功估值改读 `installed_skill_ids`
- `scripts/ui/match_table.gd` 与 `scripts/ui/player_target_view.gd`：技能栏、悬停资料与右键详情改为按 `installed_skill_ids` 裁剪；缺字段时不裁剪，缺失定义的技能保留占位
- `tests/nakexia_mechanics_test.gd`：三个阶段重写为一次性失去／装配路径不受影响／存档按实际集合装配，并新增界面收敛用例（真实 `PlayerTargetView` 场景 + `description_sections` 断言）与 `_get_snapshot_player()` 辅助
- 文档六篇（玩法内容、架构说明、界面与交互、内容制作指南、AI 模块、README）与规范两篇（复用指南模式 5、核心规范快照字段）同步

### Key Decisions

- **移除之后不需要“记得它曾经存在”**：既然失去后重新获得同一技能完全合法，就不该引入名单——凡是需要长期维护、且“漏查一次就出错”的派生状态都是未来的 bug 来源。原先的名单把「五条装配路径都要记得查」这一义务散布到核心层五处，现在这五处全部回归“按来源正常装配”。
- **界面收敛改读派生视图而不是“谁被拉黑过”**：`installed_skill_ids` 由 `get_installed_skill_ids()` 从技能实例表派生，随每次广播下发；东西没了列表自然变短，新东西进来列表自然变长，方向性错误从结构上不可能发生。
- **存档落的是当前状态，不是历史禁令**：存档写 `installed_skill_ids`、读档只装集合内技能，因此读档不会撤销【留白】的代价；缺该字段的旧存档读作“无记录 → 完整装配”，与改动前逐字节一致。
- **端口命名去掉 `_permanently`**：原 `remove_all_skills_permanently()` 的名字与新契约（可重新获得）直接矛盾，改名 `remove_all_skills()` 并在文档中写明“失去是一次性事实”。
- **不合并 `remove_acquired_skill()`**：后者只清“获得记录”，当固有/模式/临时来源仍提供同一技能时**保留实例**（用于次数额度到期），职责与“把技能拿走”不同，因此保留两个端口并在规范中写明分工。

### Git Commits

| Hash | Message |
|------|---------|
| `4aca7ce` | 1. 移除玩家状态的永久失去技能ID名单字段与两个名单读写端口 2. 新增失去技能的通用端口与失去全部技能的批量端口 3. 移除五条技能装配路径的永久失去名单拦截与旧布尔标记迁移 4. 新增公开快照的实际安装技能ID字段 5. 新增过关斩将存档的实际安装技能集合并按集合装配 6. 调整留白第二段为调用失去全部技能的批量端口 7. 调整升变的军功估值改为按实际安装技能集合统计 8. 调整本地技能栏按实际安装技能集合裁剪 9. 调整其他玩家悬停资料与右键详情按实际安装技能集合裁剪 10. 重写那刻夏留白专项回归为一次性失去与重新获得语义 11. 移除永久失去名单的快照、存档与迁移断言，新增实际安装集合断言 |
| `cb7ceb9` | 1. 同步玩法内容文档的留白一次性失去技能口径与通用失去技能接口 2. 同步玩法内容文档的界面收敛依据与存档实际技能集合说明 3. 同步架构说明的失去技能端口、装配路径与快照派生字段 4. 同步界面文档的按实际安装技能集合收敛口径 5. 同步内容制作指南的失去技能通用端口与批量端口说明 6. 同步 AI 模块文档的军功估值按实际安装技能集合统计 7. 同步 README 的那刻夏回归测试说明 |
| `509fb39` | 1. 重写复用指南的一次性移除反例为不引入持久名单 2. 补充核心规范的实际安装技能派生字段与失去技能端口约束 |
| `59862ec` | 1. 新增技能栏按实际安装集合裁剪的回归断言 2. 新增悬停武将资料与右键详情不显示已失去技能的回归断言 3. 新增缺少实际安装集合字段时保持完整列表的兼容断言 |
| （本次） | 1. 记录留白一次性失去技能修正的任务记录与会话日志 |

### Testing

- [OK] 定向子集 17 个场景全部 PASS（`.godot_test_logs/skill_loss_subset.txt`）：omphalos_transform / tingyun / daheita / kafuka / reincarnation / conquest_save（含 `resume_skills`）/ conquest_single_player / corner_badge / leader_skill / skill_target_ui / ui_layout / match_replay / new_character_mechanics / rule_timing / lan_match_flow / ai_policy / smoke
- [OK] `NAKEXIA_MECHANICS_PASS sections=2 phase_limit=2 jiezhi_per_game=2 jiezhi_self_reset=1 reset_keep_self=1 one_shot_loss=2 regrant_new_skill=1 regrant_lost_skill=1 ui_filter=3 nested_trigger_entry=1`
- [OK] 全量 82 个场景连跑（`.godot_test_logs/full_regression_one_shot.txt`）
- [OK] 界面断言覆盖需求第四条：真实 `PlayerTargetView` 实例在 `installed_skill_ids` 不含某技能时不再输出该技能分段，重新获得后立即恢复

### Status

[OK] **Completed**

### Next Steps

- 后续任何“失去技能”类效果直接调用 `remove_skill()` / `remove_all_skills()`，不要各自实现卸载流程
- 旧存档中的 `permanently_removed_skill_ids` 字段被静默忽略（需求方明确不做后期维护），如需回溯历史表现请查本任务记录

