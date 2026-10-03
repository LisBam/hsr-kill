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

