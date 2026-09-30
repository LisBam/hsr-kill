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
