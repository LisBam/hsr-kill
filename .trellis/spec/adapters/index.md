# 适配层开发规范（AI / 网络 / 自动加载 / 平台）

> 覆盖 `scripts/ai/`、`scripts/network/`、`scripts/autoload/`、`scripts/platform/`。
> 权威文档：[`docs/AI模块.md`](../../../docs/AI模块.md)、[`docs/网络通信.md`](../../../docs/网络通信.md)、[`docs/架构说明.md`](../../../docs/架构说明.md)。

---

## 层职责与边界

适配层的共同定位：**它们提供"另一个操作来源"，但不拥有规则状态。**

| 子层 | 目录 | 边界 |
|---|---|---|
| AI | `scripts/ai/` | 只在核心已生成的**合法动作集合**中评分并返回可序列化动作 |
| 网络 | `scripts/network/` | 房主权威结算；客户端只上行 `PlayerAction`、下行只读裁剪快照 |
| 自动加载 | `scripts/autoload/` | `GameSettings` 管设置持久化，`GameDatabase` 管静态内容索引 |
| 平台 | `scripts/platform/` | 只做 Android 返回键、软键盘、显示稳定性适配 |

**共同铁律**：离线玩家、LAN 客户端与内置 AI **统一通过 `PlayerAction` 下发操作**；适配层不直接造成伤害、回复体力、移动牌、修改身份或推进阶段。

---

## Pre-Development Checklist（开工前必读）

- [ ] 确认改动属于 AI 评分、网络协议、设置持久化还是平台适配。
- [ ] AI：确认只在合法动作中评分，**没有**新增卡牌/技能 ID 白名单。
- [ ] AI：确认没有跨决策缓存权威快照或决策结果。
- [ ] 网络：确认新增数据是否应按观察者裁剪；是否泄露隐藏信息。
- [ ] 网络：确认新增上行是否经过权威校验（actor 防伪、序号去重）。
- [ ] 设置：确认新字段的写入是否需要合并计时与强制刷新边界。
- [ ] 平台：确认改动只影响平台适配，不侵入规则或表现层。

---

## 指南索引

| 指南 | 内容 |
|---|---|
| [ai-pipeline.md](./ai-pipeline.md) | AI 四层分工、缓存边界、动作协议、性能红线 |
| [network-layer.md](./network-layer.md) | 房主权威模型、快照裁剪、重连令牌、聊天、防伪 |
| [autoload-and-platform.md](./autoload-and-platform.md) | `GameSettings` 持久化、`GameDatabase` 索引、Android 适配 |

---

## Quality Check（完成前自检）

- [ ] 适配层未直接改写 `GameState` / `PlayerState` / 牌区。
- [ ] AI 返回的动作全部来自核心提供的合法动作集合，且可序列化。
- [ ] 网络新增字段已确认裁剪策略，未泄露身份/手牌/随机种子。
- [ ] 客户端任何输入都经房主权威复核（防 actor 伪造）。
- [ ] `GameSettings` 新字段遵循 0.25 秒合并写入与退出强制刷新。
- [ ] 未在 `GameDatabase` 之外维护第二份内容索引。
- [ ] 已跑相关测试（`ai_policy_test` / `lan_*` / `game_settings_persistence_test` / `android_adaptation_test`）。
- [ ] `docs/AI模块.md`、`docs/网络通信.md`、`README.md` 已同步。

---

## 常见错误

| 错误 | 后果 |
|---|---|
| AI 直接调用 `host.damage(...)` 造成伤害 | 绕过权威校验，AI 可产生非法结果 |
| AI 缓存跨决策的 `PlayerState` 引用 | 决策污染，性能与正确性双失 |
| 客户端上传状态而非动作 | 破坏房主权威，可被作弊 |
| 新快照字段未裁剪 | 泄露隐藏身份或他人手牌 |
| 在别处另存一份卡牌 ID 表 | 与 `GameDatabase` 索引不一致 |
