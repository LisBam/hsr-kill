# 卡牌【言灵】· 设计

父任务：[`10-02-kafuka-new-mechanics`](../../../10-02-kafuka-new-mechanics/prd.md) ｜ PRD：[`prd.md`](./prd.md)

---

## 1. 落点

| 关注点 | 落点 |
|---|---|
| 静态元数据 | `game_data/cards/yanling.gd` 的 `_init()` |
| 出牌结算 | `resolve(resolver, card, actor_id, target_ids)` → `resolver.host.place_delayed_trick(target, card)` → 返回 `"judgment"` |
| 判定结算 | `resolve_delayed_judgment(match_host, player_id, card, negated)` |
| 配套 AI | `modify_ai_action_score(authoritative_snapshot, action, current_score, evaluator)` |

卡牌不新增任何核心分支：入堆走前置子任务交付的端口，操控走前置子任务交付的回合操控端口，主演读取走既有的 `get_starring_role_player_id()`。

## 2. 判定流程

```text
目标判定阶段翻牌
  ├─ 被【无懈可击】抵消 → discard_delayed_card(card)，不判定
  └─ 未被抵消
       ├─ 花色 != club → 无事发生
       ├─ get_starring_role_player_id() == -1 → 无事发生
       └─ 成立 → begin_turn_input_delegation(被操控者 = 当前回合角色, 操控者 = 主演)
```

- 三个条件**同时**成立才登记；任一不成立是「合法但无效果」，不是错误。
- 判定结果读取的是实体牌的 `suit`，因此【言灵】自带的梅花K 与「被技能放到牌堆顶的牌」都会被正确读出。

## 3. AI 口径

| 分支 | 条件 | 分数 |
|---|---|---|
| 主演是队友 | `get_starring_player_id() >= 0` 且态度为正 | `AI_ALLY_STARRING_VALUE = 6.0` 作基础分 |
| 主演是敌人 / 不存在 | 主演为敌方，或场上没有主演 | `AI_REFUSE_SCORE = -100.0` |
| 目标不是最近的敌人 | 目标 != 「距离主演回合最近的敌人」 | `AI_NON_NEAREST_TARGET_SCORE = -100.0` |
| 判定安全结果 | 供通用改判定 AI 比较 | `AI_TARGET_SAFE_RESULT_VALUE = 4.0` |

- 「距离其回合最近的敌人」按**行动顺序**求主演之后的第一个敌人，而不是座次距离。
- 评分是硬门槛而非偏好：否决值远低于任何正常出牌分，等价于「不使用此牌」。

## 4. 与前置机制的关系

| 前置机制 | 本卡牌的使用方式 |
|---|---|
| 专属锦囊牌（`exclusive`） | 声明 `exclusive = true` 且不写入任何牌堆；自身声明牌面 |
| 本回合由xx操控 | 判定成立时调用 `begin_turn_input_delegation()`；卡牌本身不实现视角切换与输入锁定 |
| 「主演」 | 只读 `get_starring_role_player_id()`，不改动其唯一性与清理口径 |
