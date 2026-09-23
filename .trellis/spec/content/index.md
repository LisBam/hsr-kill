# 内容源码层开发规范

> 覆盖 `game_data/cards`、`game_data/skills`、`game_data/characters`、`game_data/factions.json`、`data/decks.json`。
> 权威手册：[`docs/内容制作指南.md`](../../../docs/内容制作指南.md)。

---

## 层职责与边界

内容源码层是**静态数据层**，只负责**声明内容**：一张牌是什么、一个技能怎么写、一名武将引用哪些技能。

- 三个基类位于 `game_data/card_definition.gd`、`game_data/skill_definition.gd`、`game_data/character_definition.gd`。
- 具体内容文件**只继承对应 `class_name`**，不得复制基类，也不得引用同目录下另一个具体内容文件形成强耦合。
- `GameDatabase`（自动加载）自动扫描目录并建立只读索引；**新增文件不需要修改任何集中注册表**。
- 内容代码只能通过 `resolver.host`、事件总线和统一选择请求修改规则状态；**不得读取或修改 UI 节点**。

```text
game_data/cards|skills|characters  →  GameDatabase  →  CardInstance / PlayerState / GameState
       （声明内容）                     （索引+校验）        （对局状态，内容层不得直接改写）
```

---

## Pre-Development Checklist（开工前必读）

- [ ] 打开 `docs/内容制作指南.md`，读对应章节（卡牌制作 / 技能制作 / 命名规范 / 参数总表）。
- [ ] **先在机制库中检索可复用接口**，确认没有现成函数可以复用；不要重新发明结算逻辑。
- [ ] 若涉及**未收录的新机制**，先完成机制开发与文档更新，再实现内容。
- [ ] 文件名与稳定 `id` 使用完整小写拼音（见 [naming-and-directory.md](./naming-and-directory.md)）。
- [ ] 卡牌：效果直接写在卡牌文件；技能：规则与配套 AI 都写在技能文件。
- [ ] 新增卡牌后确认已加入 `data/decks.json` 牌堆。
- [ ] 核对必填字段齐全（数据库强制 7 项 + 规则完整性字段）。
- [ ] 所有魔法数字提取为带注释的常量或 `@export` 变量。

---

## 指南索引

| 指南 | 内容 |
|---|---|
| [naming-and-directory.md](./naming-and-directory.md) | 目录职责、拼音命名与冲突序号、`GameDatabase` 校验边界 |
| [card-authoring.md](./card-authoring.md) | 卡牌模板、静态参数、类别语义、装备字段、效果入口 |
| [skill-authoring.md](./skill-authoring.md) | 技能生命周期、静态参数、时机订阅、暂停与续接、原文不可变 |
| [content-ai.md](./content-ai.md) | 内容文件必须自带配套 AI：卡牌 `ai` 字典与专属评分钩子 |

---

## Quality Check（完成前自检）

- [ ] 文件名与 `id` 均为小写拼音，冲突时从 `_2` 起递增，且两者主体一致。
- [ ] `id` 非空且全项目唯一；未擅自改动已投入使用的稳定 ID。
- [ ] 继承类型正确（卡牌 / 技能 / 武将分别继承对应基类）。
- [ ] 卡牌必填 7 项字段齐全：`original_name`、`custom_name`、`type`、`subtype`、`effect_id`、`target_mode`、`description`。
- [ ] `description` 完整写明发动时机、条件、次数、目标、费用与效果数值。
- [ ] 玩家可见的技能描述文本与主公原文**逐字一致**。
- [ ] 正式技能已补配套 AI；`sample_only` 占位技能**未**伪造 AI。
- [ ] 新卡已登记进 `data/decks.json`；新武将的技能引用有效。
- [ ] `GameDatabase.validation_errors` 为空，可正常开局。
- [ ] 已同步 `docs/内容制作指南.md`、`docs/卡牌系统.md`、`docs/游戏机制与玩法内容.md`（涉数值）。

---

## 禁止模式

| 禁止 | 原因 |
|---|---|
| 在 `CardEffectResolver` / `BasicAIPolicy` / `MatchController` 中新增具体牌名分支或 ID 白名单 | 内容层必须自包含，扩展不应触碰核心 |
| 把牌效写在卡牌文件之外 | 违反内容自包含与 `docs/内容制作指南.md` 命名规范第 5 条 |
| 内容代码读取/修改 UI 节点 | 内容层不得依赖表现层 |
| 依赖跨帧保留的运行时对象（节点、`PlayerState`、`CardInstance`、`Callable`）存放在 `context` | `context` 必须纯可序列化，否则存档、回放、网络全部失效 |
| 直接写 `GameState.current_phase` / `phase_index` / `current_player_id` | 阶段只能经 `MatchController` 标准端口推进 |
