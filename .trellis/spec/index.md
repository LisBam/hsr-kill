# 《崩铁杀》项目开发规范（Trellis Spec）

> 本目录是注入给 AI 编码代理的**工程约定**，不是项目百科。深度细节以 `docs/` 下的权威文档为准，本目录负责说明「在本项目写代码时必须遵守什么、在哪里写、如何验证、禁止什么」。

---

## 一、项目速览

| 项 | 内容 |
|---|---|
| 项目名 | 崩铁杀（**LisBam**） |
| 引擎 | Godot 4.6（`project.godot`，主场景 `res://scenes/main.tscn`） |
| 语言 | GDScript（唯一实现语言，缩进使用 **Tab**） |
| 玩法 | 标准身份制同人桌游；在三国杀规则骨架上套《崩坏：星穹铁道》题材 |
| 规则依据 | 本地「三国杀官方规则集 3.0」快照 |
| 架构参考 | 本地无名杀（noname）v1.10.16 源码快照（仅作参考，**不复制其 JavaScript**） |
| 规模 | `scripts/` 约 102 个 `.gd`；`game_data/cards` 92、`characters` 189、`skills` 144；`tests/` 48 个测试场景 |

---

## 二、分层地图（spec 层 ↔ 真实目录）

本 spec 树按项目**真实分层**组织，与 `scripts/`、`game_data/` 一一对应：

| Spec 层 | 覆盖的真实目录 | 何时读 |
|---|---|---|
| [`project/`](./project/index.md) | 跨层全局约定：协作口吻、注释规范、文档同步、验证方式 | **每次开工前必读** |
| [`content/`](./content/index.md) | `game_data/cards`、`game_data/skills`、`game_data/characters`、`data/decks.json`、`game_data/factions.json` | 新增/修改卡牌、技能、武将、牌堆 |
| [`core/`](./core/index.md) | `scripts/core/`、`scripts/data/`、`scripts/opportunity/` | 改动权威规则、状态、事件运行时、结算管线 |
| [`ui/`](./ui/index.md) | `scripts/ui/`、`scenes/` | 改动界面、表现、布局、主题 |
| [`adapters/`](./adapters/index.md) | `scripts/ai/`、`scripts/network/`、`scripts/autoload/`、`scripts/platform/` | 改动 AI、联机、自动加载、平台适配 |
| [`guides/`](./guides/index.md) | 跨层思维指南（Trellis 共享） | 跨层改动、疑似重复代码、动手前自检 |

查询分层清单：

```bash
python ./.trellis/scripts/get_context.py --mode packages
```

---

## 三、权威文档索引（`docs/`）

**规则冲突时以 `docs/` 为准，本 spec 只做提炼与索引。**

| 文档 | 权威范围 |
|---|---|
| [`docs/架构说明.md`](../../docs/架构说明.md) | 五层单向依赖、模块职责、各类边界（状态可见性 / 设计边界 / 平台适配 / 事件运行时 / 停滞自修复） |
| [`docs/内容制作指南.md`](../../docs/内容制作指南.md) | 卡牌 / 技能 / 武将制作的**唯一权威手册**（命名、字段总表、模板、生命周期、源码索引） |
| [`docs/游戏机制与玩法内容.md`](../../docs/游戏机制与玩法内容.md) | 玩法与数值的**唯一权威快照**（伤害、次数、距离、概率、资源、持续时间） |
| [`docs/卡牌系统.md`](../../docs/卡牌系统.md) | 卡牌数据流与结算语义 |
| [`docs/AI模块.md`](../../docs/AI模块.md) | AI 四层架构、评分模型与战略数值 |
| [`docs/网络通信.md`](../../docs/网络通信.md) | LAN 权威模型、快照裁剪、重连与聊天 |
| [`docs/界面与交互.md`](../../docs/界面与交互.md) | 界面结构、交互协议与视觉规格 |
| [`docs/无名杀运行逻辑重构分析.md`](../../docs/无名杀运行逻辑重构分析.md) | 与 noname 的对照分析（研究性质，非实现约束） |
| [`README.md`](../../README.md) | 项目总览、运行方式、**逐项测试说明** |
| [`AGENTS.md`](../../AGENTS.md) | 开发者记忆档案：架构原则、AI 协作规范 |
| [`项目专属AGENTS.md`](../../项目专属AGENTS.md) | 项目专属铁律：君臣口吻、主公原文不可变、机制/武将/AI 处理流程 |

---

## 四、总纲：五条不可违反的原则

1. **原文不可变** — 主公给出的技能/卡牌描述原文，字段、数值、文字、标点、语序一律不得改动。
2. **单向依赖** — 静态数据层 → 状态与规则层 → 事件运行时 → 动作协议层 → AI/网络/UI 适配层。任何 UI、AI、网络模块**不得直接改写 `GameState`**。
3. **单一权威** — 规则状态只有 `MatchController` + `GameState` 一份；UI/AI/网络只读快照、只提交 `PlayerAction`。
4. **内容自包含** — 卡牌效果写在卡牌文件、技能规则与配套 AI 写在技能文件；禁止中心化 ID 白名单。
5. **文档同步** — 改代码必须同步对应 `docs/` 文档与《游戏机制与玩法内容》的具体数值（见 [`project/documentation-sync.md`](./project/documentation-sync.md)）。

---

## 五、禁读 / 禁改清单

以下路径含作者私有内容或外部参考快照，AI **不得读取、不得修改**：

| 路径 | 约束 |
|---|---|
| `设计自用文档（AI禁改禁读）.md` | 禁读、禁改 |
| `游戏机制关键词（AI禁读禁改）/` | 禁读、禁改 |
| `【统帅三？军】（临时文件）（AI禁读）.txt` | 禁读 |
| `三国杀规则集/`、`无名杀参考代码/`、`参考图/` | 外部参考快照，只作规则/架构依据，**不得修改** |

`临时反馈文档.md` 由 AI 按规范追加，**不做维护、校验或引用**。
