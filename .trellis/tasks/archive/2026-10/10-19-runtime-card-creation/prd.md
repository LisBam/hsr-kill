# 运行时造牌底座（以太造牌与洗入牌堆）

## Goal

为「以太」提供造牌所需的全部底层能力：一张拥有**玩家自定义牌名**、指定花色点数、并**复制既有牌效果与类别**的卡牌，可以被创造并直接进入玩家手牌；一张位于弃牌堆的指定牌可以被洗入摸牌堆（位次由权威随机源决定并记账）；并提供「该牌名是否与所有已存在牌名都不同」的权威查询入口。

## Requirements

### R1 自定义牌名的卡牌实例

- **R1.1** `CardInstance` 新增 `custom_display_name: String`：非空时该实例的**牌名**以此为准，为空时沿用卡牌定义的名称。
- **R1.2** `CardInstance` 新增 `minted_skill_id: String`：记录创造该牌的技能 ID（普通牌为空）。用于「若『以太』牌在弃牌堆中」这类按来源识别牌名的判定。
- **R1.3** 两个字段进入 `to_dict()` / `from_dict()`，并随权威存档、公开快照、回放与网络同步一起往返，读档后不丢失。
- **R1.4** 效果与类别通过**复用被复制牌的卡牌定义**实现：造出的牌 `definition_id` 即被复制牌的定义 ID，因此其效果逻辑、类别、目标模式、AI 画像、响应模式、使用次数限制全部自动继承，无需运行时定义注册表。
- **R1.5** 该牌在牌名展示层面（手牌、选牌窗口、装备区、判定区、信息框、日志、AI 文本）显示 `custom_display_name`；在效果结算层面按其定义执行。

### R2 牌名唯一性

- **R2.1** 新增权威查询端口：`MatchController.is_card_name_available(card_name: String) -> bool`。
- **R2.2** 「已存在牌名」集合 = 全部静态卡牌定义的 `original_name` 与 `custom_name`（两种命名模式下都不得撞名） ∪ 本局所有区域中 `custom_display_name` 非空的实体牌。
- **R2.3** 新增 `MatchController.collect_existing_card_names() -> Array[String]`（去重、排序）供界面提示与 AI 使用。
- **R2.4** 空字符串、纯空白、超长（> 12 个字符）、包含换行或 `|` 分隔符的牌名一律视为不可用。
- **R2.5** 唯一性校验必须在**权威侧**再执行一次：即使界面已校验，服务端拒绝时不得产生任何副作用。

### R3 造牌入手端口

- **R3.1** 新增 `MatchController.mint_card_for_player(player_id, source_definition_id, custom_name, suit, rank) -> int`，返回新牌 `uid`，失败返回 `-1` 且**零副作用**。
- **R3.2** 失败条件：技能定义缺失、牌名不可用、花色或点数非法、玩家不存在/已死亡/已离场。
- **R3.3** 成功时：创建 `CardInstance`（`definition_id = source_definition_id`，`custom_display_name = custom_name`，`minted_skill_id = 发起技能 ID`，`suit`/`rank` 取入参）→ 通过 `CardMovementService` 放入该玩家手牌 → 记录来源日志 → `_emit_state()`。
- **R3.4** 花色与点数使用既有校验：`CardInstance.is_valid_suit()` / `is_valid_rank()`；点数范围 1-13。
- **R3.5** 必须使用既有的「新牌入区」通路（`insert_new_card_into_draw_pile` 的同类机制或等价的移动服务入口），不得绕过 `CardMovementService` 直接改写区域数组。

### R4 弃牌堆洗入摸牌堆端口

- **R4.1** 新增 `MatchController.shuffle_discard_card_into_draw_pile(card_uid: int) -> bool`。
- **R4.2** 行为：仅当该牌当前位于弃牌堆时生效；移动进摸牌堆的**随机位次**由权威随机源决定，并把该随机结果写入 `state.random_history`（保证回放与联机一致）；移动后清空该牌的 `known_to` / `shown` / `private_owner_id` 与视为牌面残留（与整堆洗牌口径一致）；`_emit_state()`。
- **R4.3** 新增 `MatchController.get_discard_pile_card_uids_by_skill(skill_id: String) -> Array[int]`（按技能来源筛选弃牌堆中的牌，从堆顶向下顺序）。
- **R4.4** 该端口不得影响 `_reshuffle_discard_pile()` 的既有整堆洗牌行为。

### R5 文档

- **R5.1** `docs/内容制作指南.md` 增补「运行时造牌」小节：`mint_card_for_player` 用法、牌名唯一性约束、`custom_display_name` 语义、AI 画像自动继承、注意事项。
- **R5.2** `docs/游戏机制与玩法内容.md` 记录造牌规则（牌名唯一、花色点数自选、效果类别复制、入手的牌为实体牌）。
- **R5.3** `docs/卡牌系统.md` 记录 `CardInstance` 新增字段与牌名解析顺序。
- **R5.4** `docs/架构说明.md` 记录造牌端口与洗回端口的位置与职责。

## Acceptance Criteria

- [ ] `CardInstance` 具备 `custom_display_name` / `minted_skill_id`，`to_dict()` / `from_dict()` 往返一致。
- [ ] `mint_card_for_player(pid, "lebusishu", "自定义名称1", "heart", 13)` 返回有效 `uid`；该牌位于 `pid` 手牌，`definition_id == "lebusishu"`，`suit == "heart"`，`rank == 13`，`custom_display_name == "自定义名称1"`。
- [ ] 造出的牌在界面与日志中显示「自定义名称1」，其效果按「乐不思蜀」结算（延时锦囊牌、判定流程一致）。
- [ ] 重名牌名（与任一静态定义名或另一张已造牌同名）被 `is_card_name_available` 判为不可用，且 `mint_card_for_player` 返回 `-1` 且不产生任何状态变化。
- [ ] 空白牌名、超长牌名、含 `|` 的牌名被拒绝。
- [ ] 非法花色/点数被拒绝。
- [ ] `shuffle_discard_card_into_draw_pile(uid)` 把该牌从弃牌堆移入摸牌堆，位次写入 `random_history`，且该牌不再出现在弃牌堆。
- [ ] 对不在弃牌堆的牌调用 `shuffle_discard_card_into_draw_pile` 返回 `false` 且无副作用。
- [ ] 存档 → 读档后造出的牌仍保留 `custom_display_name` / `minted_skill_id`，界面仍显示自定义牌名。
- [ ] 既有卡牌测试全绿（`exclusive_card_and_private_placement_test`、`smoke_test`、`card_timing_sequence_test`、`gameplay_regression_test`、`font_color_audit_test`）。
- [ ] 新增 `tests/runtime_card_minting_test.tscn` 覆盖上述断言。
- [ ] `docs/内容制作指南.md`、`docs/游戏机制与玩法内容.md`、`docs/卡牌系统.md`、`docs/架构说明.md` 已同步。

## Notes

- 关键设计决策见 `design.md` 的 **D1**：以「卡牌实例级牌名覆盖 + 复用被复制牌定义」实现造牌，而不是注册运行时卡牌定义。备选方案与风险对比一并记录。
- 本任务**不**包含 `yinlang_windows` 界面（属 `10-19-yinlang-character-and-windows`），只提供端口与数据契约。
- 本任务**不**负责自由文本输入的协议通路；该通路在 `10-19-yinlang-character-and-windows` 中实现，本任务只保证权威侧对入参的校验完整。
