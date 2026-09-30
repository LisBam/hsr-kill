# 技术设计：木牛流马两段式存牌/转移与5张容量上限

## 1. 现状

- `game_data/cards/muniuliuma.gd`：
  - 元数据 `play_phase_interaction:"store_attachment"`、`play_phase_action_type:"store_wooden_ox"`、`play_phase_material_count:1`、`play_phase_action_card_source:"material"`；
  - `validate_play_phase_action()` 已允许 `target_ids` 至多1名其他存活角色；
  - `execute_play_phase_action()` **在同一次调用内**完成存牌与可选转移；
  - `get_play_phase_action_preview()` 返回 `target_mode:"optional_single_other"`、`min_targets:0`、`max_targets:1`。
- `scripts/core/match_controller.gd`：
  - 装备主动动作预览在 `_build_play_phase_action_preview` 附近（约第15780-15815行），对 `store_wooden_ox` 有专门分支，从公开快照构造可选目标；
  - 无处理区父牌的装备选择恢复入口在第3835-3856行：按上下文 `equipment_definition_id` 调用 `continue_equipment_response()` 或 `continue_equipment_choice(match_host, context, selected_uids)`；
  - `CardDefinition` 目前只有 `continue_equipment_choice` 与 `continue_equipment_response`，**没有携带 `selected_target_ids` 的通用恢复钩子**；
  - 控制器已有 `request_card_choice(...)`、`request_target_choice(...)`、`request_card_target_choice(...)` 等请求创建入口。
- 容量：`PlayerState.wooden_ox_storage` 目前无数量上限。

## 2. 目标交互

```
点击木牛流马 → 选择1张普通手牌 → 确定
        ↓（本次发动已消耗，牌进入“粮”）
独立询问：“是否将此装备移动给其他角色？”
        ├─ 选择1名其他存活角色 → 确定 → 整体转移
        └─ 取消 → 结束本次发动，宝物留在原处
```

## 3. 设计

### 3.1 两段式流程

1. **第一段**（现有请求改造）：装备主动动作预览把 `target_mode` 从 `optional_single_other` 改回“不需要目标”（`min_targets:0, max_targets:0`），`get_play_phase_action_preview()` 不再暴露转移目标；`validate_play_phase_action()` 对第一段拒绝任何 `target_ids`。
2. `execute_play_phase_action()` 只做“把材料移入 `wooden_ox`”，随后**创建第二段请求**而不是直接结束：
   - 请求类型：需要“可选1名其他存活角色 + 可取消”的语义；
   - 提示文本：`是否将此装备移动给其他角色？`（提取为文件顶部 `const TRANSFER_PROMPT`）；
   - 上下文携带 `equipment_definition_id = get_id()`、`choice_kind`（例如 `"muniu_transfer"`）、`owner_id`、`equipment_uid`、以及原始材料信息，供恢复期复核。
3. **恢复**：在 `CardDefinition` 新增
   `continue_equipment_selection(match_host, context, response: ChoiceResponse) -> bool`
   并在控制器第3835-3856行的装备恢复分支中、`continue_equipment_choice(...)` 之后加入对它的调用（保持“先响应牌、后普通选择、最后通用选择”的既有顺序；具体顺序在实现时按现有分支结构确定）。
   - 语义与卡牌的 `continue_selection()` 对齐：读取 `response.selected_target_ids` 与 `response.confirmed`；返回 `true` 表示本次请求已由装备源码消化。
   - 取消（`confirmed == false` 或未选目标）→ 不移动任何实体，记录日志后结束；
   - 确认且目标合法 → `transfer_equipment_with_attachments(owner, target, "treasure", attachment_cards, "wooden_ox")`，然后清空 `wooden_ox_storage`。
4. **AI**：
   - 第一段保持 `append_play_phase_actions()` 的“每张普通手牌一个存粮动作”，不产生转移目标；
   - 第二段需在 `score_ai_choice()` 内补全决策：默认取消；当“宝物与粮交给队友的收益 > 留在自己处的收益”时确认并选最优队友。必须显式说明补全范围与未覆盖情形（符合项目 AI 补全规范）。
5. **UI**：第二段是带提示文本的目标选择请求，复用现有目标选择控件；需确认取消按钮可用（`allow_cancel = true`）且提示文本直接显示。同步 `docs/界面与交互.md`。

### 3.2 容量上限

- 常量：`WOODEN_OX_STORAGE_CAPACITY: int = 5`（`game_data/cards/muniuliuma.gd` 顶部，带用途/取值范围/修改影响注释）。
- 只读查询：`is_play_phase_action_available()` 增加 `owner.wooden_ox_storage.size() < WOODEN_OX_STORAGE_CAPACITY`。
- 枚举：`append_play_phase_actions()` 在容量已满时不追加任何动作。
- 规则校验：`validate_play_phase_action()` 在容量已满时返回明确拒绝原因（例如 `"木牛流马下的“粮”已达上限。"`）。
- 第二段转移不改变总量，不受容量影响。
- 公开数量显示沿用 `shows_attachment_count` 机制，达到上限时可选择在装备名后提示“已满”；是否新增提示在实现时与 `docs/界面与交互.md` 一并定稿。

## 4. 兼容性检查清单（实现时逐条核对）

- 粮牌可使用/打出（`PlayerState.find_usable_card` 等）、不参与弃牌上限、不可重铸（`match_controller.gd:2201-2202` 与 `match_table.gd:5112`）保持不变。
- 木牛离区弃置全部“粮”保持不变；整体转移走专用路径不触发离区清理。
- `tests/gameplay_regression_test.gd` 第836-930行的既有断言需要按新流程调整（原本可能依赖同一步完成转移）。
- `tests/inline_hand_choice_test.gd` 第477-500行关于出牌快照的断言需复核。
- 房主最终校验必须覆盖第二段请求的合法性与目标存活校验。
- 网络：第二段请求作为普通选择请求同步，不新增自定义消息类型。

## 5. 验证设计

新增/改写测试覆盖：

1. 第一段确定后**不移动装备**，且 `_pending_card_choice` 出现新请求，提示文本为“是否将此装备移动给其他角色？”。
2. 第二段取消 → 宝物与“粮”原地不动，`wooden_ox_used == true`。
3. 第二段确认并选目标 → 宝物与其下全部“粮”整体转移，目标装备区为木牛，“粮”数量一致，未触发离区弃置。
4. 容量：4张时可再存第5张；5张时 `is_play_phase_action_available()` 为假、AI 动作枚举为空、校验返回拒绝原因。
5. AI：容量已满时 AI 不提交存粮动作；第二段 AI 在“收益为负”时取消。
