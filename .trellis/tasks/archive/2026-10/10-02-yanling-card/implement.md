# 卡牌【言灵】· 实施记录

父任务：[`10-02-kafuka-new-mechanics`](../../../10-02-kafuka-new-mechanics/prd.md) ｜ PRD：[`prd.md`](./prd.md) ｜ 设计：[`design.md`](./design.md)

---

## 改动清单

- [x] H1 新增 `game_data/cards/yanling.gd`（静态元数据 + `resolve()` + `resolve_delayed_judgment()` + `modify_ai_action_score()`）。
- [x] H2 卡牌固定牌面声明为梅花K（`DECLARED_SUIT = "club"` / `DECLARED_RANK = 13`），供入堆端口缺省牌面时使用。
- [x] H3 AI 硬门槛与判定安全结果值集中声明为常量。
- [x] H4 `docs/内容制作指南.md` 四张卡牌总表新增 `yanling.gd` 行。
- [x] H5 `docs/卡牌系统.md` 锦囊牌表新增【言灵】行，并补齐「专属牌自带牌面」的数据流差异。
- [x] H6 `docs/游戏机制与玩法内容.md` 新增专属卡牌【言灵】小节。
- [x] H7 `docs/AI模块.md` 新增【言灵】卡牌 AI 口径。
- [x] H8 `tests/kafuka_mechanics_test.gd` 覆盖静态元数据、牌面、判定三分支与 AI 门槛。
- [x] H9 `README.md` 新增专项测试入口说明。
- [x] H10 `临时反馈文档.md` 追加学习反馈摘要与 Git 提交描述。

## 验证

| 用例 | 结果 |
|---|---|
| `tests/kafuka_mechanics_test.tscn` | `KAFUKA_MECHANICS_PASS metadata+gameStart+delayedTrick+placement+privateFact+gain+aiPressure` |
| `tests/smoke_test.tscn` | `SMOKE_PASS`（卡牌定义数 46 → 47） |
| `tests/ai_policy_test.tscn` | `AI_POLICY_PASS cards=47` |
| `tests/exclusive_card_and_private_placement_test.tscn` | `EXCLUSIVE_CARD_PRIVATE_PLACEMENT_PASS` |

## 遗留

- 卡牌插画与音效素材未制作（缺失时静默跳过，属既有规范允许状态）。
- 判定结果点数（K）目前不参与任何规则分支，仅作为牌面事实保留。
