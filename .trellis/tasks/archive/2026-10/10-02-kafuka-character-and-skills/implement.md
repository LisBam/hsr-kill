# 武将卡芙卡 + 技能【言灵】【游丝】· 实施记录

父任务：[`10-02-kafuka-new-mechanics`](../../../10-02-kafuka-new-mechanics/prd.md) ｜ PRD：[`prd.md`](./prd.md) ｜ 设计：[`design.md`](./design.md)

---

## 新增文件

| 文件 | 内容 |
|---|---|
| `game_data/characters/kafuka.gd` | 星核猎手 / 女 / 体力上限 3 / 技能顺序【言灵】【游丝】 |
| `game_data/skills/yanling.gd` | 锁定技：`gameStart` 随机布 3 张【言灵】；延时锦囊触发时摸 1 张并成为「主演」 |
| `game_data/skills/yousi.gd` | 非锁定技：其他角色回合开始秘密置牌；该回合结束观看并获得一张牌 |
| `game_data/effects/yousi_pressure.gd` | 被发动者的通用出牌压力（`get_ai_hand_pressure() = 3.0`，本回合结束自行移除） |
| `tests/kafuka_mechanics_test.gd` / `.tscn` | 专项回归测试（自带看门狗与阶段标记） |

## 被修改文件

| 文件 | 改动 |
|---|---|
| `scripts/core/match_controller.gd` | 入堆端口的随机位次、私有置牌事实端口、位次询问端口、`get_private_hand_and_equipment_candidates()`、`get_ai_hand_pressure()` 转发（均在前置子任务与本任务中落地） |
| `game_data/player_effect.gd` | 新增基类默认 `get_ai_hand_pressure() -> 0.0` |
| `scripts/core/player_effect_service.gd` | 新增按玩家求和 `get_ai_hand_pressure()` |
| `scripts/ai/basic_ai_policy.gd` | 新增 `hand_pressure`、`set_hand_pressure()`、`_get_hand_pressure_bonus()`，一次决策后清零 |
| `scripts/ai/noname_ai_evaluator.gd` | 新增 `get_starring_player_id()` 与 `should_dump_hand_against_starring()`（只读公开角标与态度） |
| `scripts/ai/ai_coordinator.gd` | `request_action(..., hand_pressure := 0.0)` |
| `tests/smoke_test.tscn` 相关断言 | 卡牌 47 / 技能 102 / 武将 48；图鉴新增 `"yanling": "言灵"` |
| `tests/conquest_coop_test.gd` | 修复座位敏感点：机缘解析期间结算真人座位的待处理窗口；超时诊断补充登场阵容与体力 |

## 验证

| 用例 | 结果 |
|---|---|
| `tests/kafuka_mechanics_test.tscn` | `KAFUKA_MECHANICS_PASS metadata+gameStart+delayedTrick+placement+privateFact+gain+aiPressure` |
| `tests/smoke_test.tscn` | `SMOKE_PASS` |
| `tests/ai_policy_test.tscn` | `AI_POLICY_PASS cards=47` |
| `tests/exclusive_card_and_private_placement_test.tscn` | `EXCLUSIVE_CARD_PRIVATE_PLACEMENT_PASS` |
| `tests/zhuyan_zhili_test.tscn` / `tests/turn_control_mechanism_test.tscn` / `tests/lan_turn_control_test.tscn` | 通过 |
| `tests/conquest_coop_test.tscn` | 修复后 `CONQUEST_COOP_PASS`（修复前因新武将改变固定种子座位而超时） |
| 全量 `tests/*.tscn` | 仅 `audio_system_test` 未通过；已在**未改动的 HEAD 基线工作树**上复现同样失败，属既有缺陷，与本任务无关 |

## 遗留

- 卡芙卡没有插画与技能/阵亡语音素材（缺失时静默跳过，属既有规范允许状态）。
- `tests/audio_system_test.gd` 的 `card_voice_auto_respond_missing` 是既有失败，未在本任务处理。
