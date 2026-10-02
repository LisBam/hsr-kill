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
| (pending) | 见本批次回复中的 Git 提交描述 |

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

[OK] **In Progress**（实现与验证完成；待提交与归档）
