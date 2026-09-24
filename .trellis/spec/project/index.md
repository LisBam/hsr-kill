# 项目级开发规范（跨层）

> 适用于**任何**改动，无论落在哪一层。开工前先读完本页，再进入目标层的 `index.md`。

---

## 层职责与边界

本层不绑定具体目录，约束的是「在本项目工作的人与 AI 如何协作、如何交付」。它把 `AGENTS.md`（开发者记忆档案）与 `项目专属AGENTS.md`（项目专属铁律）中可执行的条目提炼为规范，两者仍是最终依据。

---

## Pre-Development Checklist（开工前必读）

- [ ] 确认本次改动属于哪一层（`content` / `core` / `ui` / `adapters`），去读该层 `index.md` 的清单。
- [ ] 确认是否涉及「需求钦定的原文」——若涉及，原文一字不得改（见 [collaboration-rules.md](./collaboration-rules.md)）。
- [ ] 搜一遍既有实现再动手：同功能可能已有标准端口或共享组件（见 [`../guides/code-reuse-thinking-guide.md`](../guides/code-reuse-thinking-guide.md)）。
- [ ] 确认本次改动需要同步哪些 `docs/` 文档（见 [documentation-sync.md](./documentation-sync.md) 的同步矩阵）。
- [ ] 确认验证方式：至少要跑一个相关的 `res://tests/*.tscn`（见 [verification.md](./verification.md)）。
- [ ] 避开禁读/禁改路径（见 [`../index.md`](../index.md) 第五节）。
- [ ] 核对是否触碰硬编码：可调参数一律提取为 `@export` 变量或顶部常量。

---

## 指南索引

| 指南 | 内容 |
|---|---|
| [collaboration-rules.md](./collaboration-rules.md) | 汇报口吻、原文不可变铁律、注释规范、架构原则、交付物要求 |
| [documentation-sync.md](./documentation-sync.md) | 改动类型 → 必须同步的 `docs/` 文档矩阵；数值记录要求 |
| [verification.md](./verification.md) | 引擎版本、运行方式、测试场景清单、数据校验边界 |

---

## Quality Check（完成前自检）

- [ ] 所有变量**独占一行注释**，说明用途、取值范围、默认值原因与修改影响。
- [ ] `@export` 参数集中在脚本最顶部，检查器中可直接调试。
- [ ] 未硬编码魔法数字；未引入跨模块强依赖；组件保持单一职责。
- [ ] 修改既有代码时，**未擅自改变量名、未删除或篡改原有注释**。
- [ ] 新机制/新函数/接口变更已完整写入 `docs/内容制作指南.md`。
- [ ] 涉及机制、玩法规则、数值体系时，《游戏机制与玩法内容》已记录**全部具体数值**。
- [ ] 已运行至少一个相关测试场景，并在输出中给出实际结果。
- [ ] 已产出「学习反馈摘要」与「Git 提交描述」，并追加到 `临时反馈文档.md`。

---

## 交付物（每次改动必须一并给出）

1. **学习反馈摘要** —— 修改思路、架构与设计、Bug 原因与修复方法（如涉及）、关键代码解析、学习要点提炼（1~3 条）。
2. **Git 提交描述** —— 数字序号分行，每行以动词开头（新增/修复/重构/移除/调整/优化/完善），一个核心动作一行，不糅合。
3. **追加写入 `临时反馈文档.md`** —— 开头带时间戳 `YYYY-MM-DD HH:MM`，追加在文件末尾，保留历史。

汇报口吻遵循 [`collaboration-rules.md`](./collaboration-rules.md)。
