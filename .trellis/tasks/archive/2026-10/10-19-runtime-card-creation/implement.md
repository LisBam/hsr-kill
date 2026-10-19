# 运行时造牌底座 · 实施计划

阶段顺序：先数据契约（B1），再名称解析（B2，最易漏），再端口（B3-B4），最后持久化验证与文档（B5-B6）。

---

## B1 `CardInstance` 字段与序列化

- [x] B1.1 新增 `custom_display_name: String = ""`（独占 `##` 注释：作用、取值、默认值原因、修改影响）。
- [x] B1.2 新增 `minted_skill_id: String = ""`（同上注释）。
- [x] B1.3 `to_dict()` 写出两个字段。
- [x] B1.4 `static from_dict(data)` 读入两个字段，缺省为空字符串（旧存档兼容）。⚠️ `from_dict` 是**逐键白名单**读取，未显式 `data.get()` 的键会被丢弃 → 只改 `to_dict` 会导致存档/网络/回放全部丢字段。
- [x] B1.5 新增只读辅助 `get_display_name_override() -> String`（返回 `custom_display_name`，供解析入口使用）。
- [x] B1.6 **决策点**（`card_instance.gd:137 set_hand_view_as()` / `:173 set_hand_view_as_with_face()`）：视为状态下保留 `custom_display_name`（显示实体原名 + 视为横条）；`clear_hand_view_as()`（`:148`）不动该字段。实现时补注释说明该取舍。

**验证**：新增断言「构造 → `to_dict` → `from_dict` 往返一致」；「旧字典（无新字段）`from_dict` 得到空字符串」。
**回滚点**：纯字段增量，回滚即删除字段与两处读写。

---

## B2 名称解析集中入口与改造

改造清单见 `design.md` D6（已按调研逐文件逐行落定）。

- [x] B2.1 `game_settings.gd:1079-1093` 附近新增 `resolve_instance_display_name(card_dict, definition) -> String`：优先 `custom_display_name`，否则回退既有 `resolve_card_display_name(definition)`。
- [x] B2.2 **必改**（见 D6.4）：`card_view.gd:294`/`:275`（★牌面唯一渲染点）、`equipment_stack_view.gd:198`/`:297`、`player_target_view.gd:1349`/`:1459`/`:1504`/`:1142`/`:1610`/`:1616`、`match_table.gd:3112`/`:3126`/`:3541`/`:5912`、`developer_console_panel.gd:732`/`:763`、`match_controller.gd:4367-4380`（★`format_card_log_name`，**改一处覆盖全部日志调用方**）、`:4464-4473`、`:14635`、`:5382`。
- [x] B2.3 **自动生效、只需验证**（见 D6.5）：`CardView.configure` 的刷新判据已 hash 整个 card 字典（`card_view.gd:241`）；手牌/飞牌/摸牌 `match_table.gd:2601/4788/4901/5212`；候选牌 `card_selection_panel.gd:768`；存档/读档/回放/网络全部走 `card.to_dict()` / `CardInstance.from_dict()`。
- [x] B2.4 **保持定义名的已知降级点**（见 D6.6，需在文档中说明）：`format_card_definition_log_name`、`:5515`、`:5889`、`:10924`、`:11123`/`:11142`、`:15221`、`card_effect_resolver.gd:62` 等。
- [x] B2.5 **不得改动**（见 D6.7）：`record_card_name`/`remove_recorded_card_name`（`:11112`/`:11131`，存 definition_id）、`card_rule_service.gd:495-498`（延时锦囊同名按定义 ID）、`card_rule_service.gd:507/520-521/555-556`（`play_limit_group` 计数）。
- [x] B2.6 **记录口径而非修改**：`match_controller.gd:7792 get_card_original_name_length()` 读定义名，自定义名不参与名字数结算 → 写入 `docs/卡牌系统.md` 与 `docs/游戏机制与玩法内容.md`。
- [x] B2.7 **查重口径**（见 D6.8）：`game_database.gd:176` 附近新增公开 `is_card_display_name_taken(name) -> bool`，复用 `_card_definitions_by_display_name.has(name)`（双名索引，同时防住信息框 title 被改写）；查重范围 = 全部定义的 `original_name` ∪ `custom_name` ∪ 本局已造牌的 `custom_display_name`。

**验证**：新增断言「造牌后手牌面板、选牌窗口、日志三处都显示自定义牌名」；「自定义名与已登记牌名相同时被拒绝」；「存档/回放/网络往返后自定义名仍在」；`font_color_audit_test`、`gameplay_regression_test` 全绿。
**回滚点**：改造清单逐文件独立，可按文件回滚。

---

## B3 造牌端口

- [x] B3.1 `CardMovementService` 补「新牌直接进入指定区域」的通路（参照 `insert_new_card_into_draw_pile`），供入手使用。
- [x] B3.2 `match_controller.gd` 新增 `is_card_name_available(card_name) -> bool`（格式校验 + 唯一性）。
- [x] B3.3 新增 `collect_existing_card_names() -> Array[String]`（静态定义名 ∪ 在局造牌名，去重排序）。
- [x] B3.4 新增 `mint_card_for_player(player_id, source_definition_id, custom_name, suit, rank, minted_skill_id := "") -> int`，严格按 design D3 的顺序「先全部校验、再写入」。
- [x] B3.5 成功时写 `_record_runtime_event("mintCard", ...)` + `add_log` + `_emit_state()`。
- [x] B3.6 新增 `get_discard_pile_card_uids_by_skill(skill_id) -> Array[int]`（从堆顶向下扫描，返回 `minted_skill_id == skill_id` 的牌 UID）。
- [x] B3.7 新增 `get_draw_pile_card_uids_by_skill(skill_id) -> Array[int]`（同一口径，供「从牌堆中获得一张『以太』牌」使用）。
- [x] B3.8 新增 `gain_top_minted_card_from_draw_or_discard(player_id, skill_id, reason) -> bool`：先摸牌堆后弃牌堆，取第一张 `minted_skill_id == skill_id` 的牌并入手；无命中返回 `false` 且零副作用。

> **为什么用 `minted_skill_id` 而不是牌名**：「以太」造出的牌牌名由玩家自由指定（例如「自定义名称1」），因此「『以太』牌」的**唯一可靠标识是铸造来源**，不是牌名。`minted_skill_id == "yitai"` 即「由以太创造的牌」。该字段同时让存档/回放能在牌名未知时仍可判定。

**验证**：新增断言覆盖全部失败分支（定义缺失 / 重名 / 空名 / 超长 / 含 `|` / 非法花色 / 非法点数 / 玩家无效）都返回 `-1` 且状态零变化；成功分支字段正确。
**回滚点**：端口为纯新增函数。

---

## B4 洗回摸牌堆端口

- [x] B4.1 新增 `shuffle_discard_card_into_draw_pile(card_uid) -> bool`：定位弃牌堆 → 权威随机位次 → `move_card(..., "@%d" % position)` → 清可见性 → 写 `random_history`（kind `"shuffle_discard_card"`）→ `_record_runtime_event("washCard", ...)` → `_emit_state()`。
- [x] B4.2 不在弃牌堆时返回 `false` 且零副作用。
- [x] B4.3 确认不影响 `_reshuffle_discard_pile()` 的既有整堆行为。

**验证**：新增断言「弃牌堆 → 摸牌堆、位次写入 `random_history`、弃牌堆不再包含该牌」；「对不在弃牌堆的牌返回 false」；既有摸牌/洗牌测试全绿。
**回滚点**：端口为纯新增函数。

---

## B5 持久化验证

- [x] B5.1 确认权威存档写出/读入路径包含两个新字段（`to_dict` / `from_dict` 已覆盖），若有逐字段白名单则补上。
- [x] B5.2 确认公开快照与联机同步包含两个新字段。
- [x] B5.3 确认回放路径包含两个新字段（若回放只记录事件与定义 ID，则记录为已知限制并说明）。
- [x] B5.4 确认无需提升存档格式版本号（旧档缺省空字符串）。

**验证**：新增「存档 → 读档 → 造牌字段一致」断言；`requested_changes_test`、`pre_game_deal_gain_test` 全绿。
**回滚点**：若需补白名单，改动局部可回滚。

---

## B6 测试与文档

- [x] B6.1 新增 `tests/runtime_card_minting_test.gd` + `.tscn`，覆盖 PRD 的全部验收条目。
- [x] B6.2 运行并确认全绿：`exclusive_card_and_private_placement_test`、`smoke_test`、`card_timing_sequence_test`、`gameplay_regression_test`、`font_color_audit_test`、`ui_layout_test`、`runtime_card_minting_test`。
- [x] B6.3 `docs/内容制作指南.md`：新增「运行时造牌」小节（端口用法、牌名唯一性、`custom_display_name` 语义、AI 画像自动继承、注意事项）。
- [x] B6.4 `docs/游戏机制与玩法内容.md`：记录造牌规则与全部数值（牌名长度上限 12、点数 1-13、花色四选一）。
- [x] B6.5 `docs/卡牌系统.md`：记录 `CardInstance` 新字段与牌名解析顺序。
- [x] B6.6 `docs/架构说明.md`：记录造牌端口与洗回端口的职责与位置。
- [x] B6.7 `README.md`：测试场景清单补充 `runtime_card_minting_test`。
- [x] B6.8 `临时反馈文档.md`：追加学习反馈摘要 + Git 提交描述（带时间戳）。

---

## 依赖与顺序

```
B1 → B2
B1 → B3 → B4
B3 → B5
B2..B5 → B6
```

B2 与 B3/B4 可并行（B2 只依赖 B1 的字段）。
