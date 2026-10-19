# 运行时造牌底座 · 技术设计

## D1 核心决策：实例级牌名覆盖 + 复用被复制牌定义

### 背景

需求要求造出一张「牌名不与已有牌相同」「效果与类别取自选定的一张牌」的实体牌。例如：
「自定义名称1」+ 红桃 + K + 乐不思蜀 → 一张名为「自定义名称1」、花色点数红桃K、类别为延时锦囊牌、效果同乐不思蜀的牌。

### 两个候选方案

| | 方案 A：注册运行时卡牌定义 | 方案 B（**采纳**）：实例级牌名覆盖 + 复用被复制牌定义 |
|---|---|---|
| 实现 | 造一个 `definition_id`（如 `yitai_1`），写进 `GameDatabase.cards` / `card_definitions` / `card_scripts` | 新牌 `definition_id` 直接等于被复制牌的 ID，牌名写在实例上 |
| 效果执行 | 需要实例化被复制牌的脚本子类再覆盖 `_metadata`，否则 `CardDefinition.new()` 只得到基类、`resolve()` 为空实现，效果静默失效 | 零改动，`CardEffectResolver` 走原路径 |
| 类别 / 目标模式 / 响应模式 / 使用次数 / AI 画像 | 需要逐项复制元数据，漏一项就出错 | 自动完全继承 |
| 存档 / 读档 | `CardInstance` 只序列化 `definition_id`，而 `GameDatabase.reload_all()` 会清空注册表 → 读档后新牌降级为「未知牌」、效果静默失败。必须额外保存「造牌配方」并在恢复时重放 | 无需任何额外持久化，天然往返 |
| 回放 | 同样需要重放配方 | 无需处理 |
| 图鉴污染 | `all_cards_panel.gd:388` 遍历 `GameDatabase.cards.keys()`，运行时牌会永久出现在图鉴；`smoke_test.gd:145` 的 `EXPECTED_CUSTOM_CARD_NAMES` 断言可能失败 | 无污染 |
| 牌名的规则身份 | 新 `definition_id` → 所有按 `definition_id` 判定的规则（【杀】族计数、`response_pattern`、`play_limit_group`、技能正文里的 `card_id == "sha"`）**都不再认识它** | 规则身份 = 被复制牌（复制【杀】得到的牌**仍然是一张【杀】**） |
| 改动面 | 新增注册表 + 持久化 + 图鉴过滤 + 测试适配 | 新增两个实例字段 + 名称解析路径改造 |

### 采纳理由

1. **存档与回放的持久化风险是决定性的**。方案 A 需要在「造牌配方」上建立一整套平行持久化，任何一处遗漏都会造成读档后卡牌效果静默失效——这是最难发现、后果最严重的一类缺陷。
2. **「复制效果和类别」在方案 B 下是字面意义上的复制**：同一个定义对象，不需要逐字段搬运元数据。
3. **AI 画像、响应模式、使用次数限制自动继承**，不需要为造出的牌单独补 AI 逻辑。
4. 需求原文的约束是「该牌牌名不可与已有牌相同」——约束的对象是**牌名**，方案 B 恰好把「牌名」定义为实例级属性并强制其唯一，语义吻合。

### 需要明确记录的解释（补全项）

- **牌名与规则身份分离**：造出的牌在**展示与牌名查询**层面是「自定义名称1」，在**效果结算**层面等同于被复制牌。因此复制【杀】得到的牌**仍计入【杀】的使用次数与相关技能判定**（例如「当你使用【杀】时」仍会触发）。
- 若将来希望「新牌名 = 新的规则身份」（例如复制【杀】得到的牌不再算【杀】），扩展路径是引入方案 A 的运行时定义注册表；本设计把该选择点显式记录下来，不做隐式承诺。
- **花色与点数由玩家指定**，不继承被复制牌。

## D2 数据契约

### D2.1 `CardInstance` 新增字段

| 字段 | 类型 | 默认 | 语义 |
|---|---|---|---|
| `custom_display_name` | `String` | `""` | 非空时本实例的牌名以此为准；空字符串表示沿用卡牌定义名称 |
| `minted_skill_id` | `String` | `""` | 创造本牌的技能 ID；普通牌为空。用于按来源识别「以太」牌 |

- 两者都进入 `to_dict()` / `from_dict()`，因此随权威存档、公开快照、回放与联机同步往返。
- 字段放在 `card_instance.gd` 顶部字段区，各自独占一行 `##` 注释（作用、取值、默认值原因、修改影响）。
- `definition_id` 的语义**不变**（仍是被复制牌的定义 ID），因此 `to_dict()` 的既有字段与既有存档完全兼容；新字段对旧存档缺省为空字符串。

### D2.2 名称解析顺序

统一规则（新增集中式解析入口，避免各处自行拼装）：

```
牌名 = custom_display_name（非空）
     否则 GameSettings.resolve_card_name(GameDatabase.get_card(definition_id))
```

集中入口：`GameSettings.resolve_card_name_for_instance(card_data: Dictionary) -> String`
- 入参为卡牌实例字典（含 `definition_id` 与可选的 `custom_display_name`）。
- 已有 `resolve_card_name(definition)` 保持不变，供纯定义场景使用。

### D2.3 唯一性判定

```
is_card_name_available(name) -> bool
  name 非空、去首尾空白后长度 1..12、不含 "|" 与换行
  且 name 不在 collect_existing_card_names() 中

collect_existing_card_names() -> Array[String]（去重排序）
  ∪ GameDatabase.cards 的 original_name
  ∪ GameDatabase.cards 的 custom_name
  ∪ 所有区域中 custom_display_name 非空的实体牌
```

「所有区域」= 摸牌堆、弃牌堆、每名玩家的手牌 / 装备区 / 判定区 / 处理区 / 木牛流马。遍历顺序固定（摸牌堆 → 弃牌堆 → 按 `player_id` 升序的玩家 → 每个玩家按手牌 → 装备区（按 `EQUIPMENT_SLOT_ORDER`）→ 判定区 → 处理区 → 木牛），保证日志与 AI 结果可复现。

## D3 造牌端口

```
func mint_card_for_player(player_id: int, source_definition_id: String, custom_name: String, suit: String, rank: int) -> int
```

执行顺序（**先校验、后写入**，保证失败零副作用）：

1. `GameDatabase.get_card(source_definition_id)` 非空；否则返回 `-1`。
2. `is_card_name_available(custom_name)`；否则返回 `-1`。
3. `CardInstance.is_valid_suit(suit)` 且 `is_valid_rank(rank)`；否则返回 `-1`。
4. `state.get_player(player_id)` 存在、`alive`、`not out_of_game`；否则返回 `-1`。
5. `CardInstance.new(source_definition_id, suit, rank)` → 写 `custom_display_name` / `minted_skill_id`（由调用方经参数传入技能 ID）。
6. 通过 `card_movement.insert_new_card_into_draw_pile` 的同类入口把新牌放进手牌：新增 `CardMovementService.insert_new_card_into_zone(card, zone, owner_id, slot, reason, event_id)` 或复用既有「新牌入区」通路（`insert_new_card_into_draw_pile` 是摸牌堆专用，需按同一模式补手牌版本）。
7. `_record_runtime_event("mintCard", ...)` + `add_log` + `_emit_state()`。
8. 返回 `card.uid`。

`minted_skill_id` 由调用方（技能）传入，因此端口签名为：

```
func mint_card_for_player(player_id, source_definition_id, custom_name, suit, rank, minted_skill_id := "") -> int
```

## D4 洗回摸牌堆端口

```
func shuffle_discard_card_into_draw_pile(card_uid: int) -> bool
```

1. 定位 `card_uid`：必须位于 `state.discard_pile`，否则返回 `false`。
2. 位次：`position = _rng.randi_range(0, state.draw_pile.size())`（0..size 含端点，表示可插入任意位置）。
3. `card_movement.move_card(card, "draw_pile", -1, SECRET_PILE_PLACEMENT_REASON, state.current_event_id, "@%d" % position)`。
4. 与整堆洗牌同口径：清空 `known_to` / `shown` / `private_owner_id` / 视为牌面残留。
5. 把随机结果写入 `state.random_history`（kind `"shuffle_discard_card"`，含 `card_uid` 与 `position`），保证回放与联机一致。
6. `_record_runtime_event("washCard", ...)`（沿用既有整堆洗牌的事件名，便于日志与 AI 识别）+ `_emit_state()`。
7. 返回 `true`。

**为什么位次必须记账**：`_reshuffle_discard_pile()` 是整堆操作、位次由 `_shuffle_array` 内部消耗权威随机源；本端口只移动一张牌，若不把位次写进 `random_history`，回放时无法复原同一牌序。

## D5 弃牌堆按来源查询

```
func get_discard_pile_card_uids_by_skill(skill_id: String) -> Array[int]
```

- 从弃牌堆**堆顶向下**（数组末尾向前）遍历，返回 `minted_skill_id == skill_id` 的牌 UID。
- 供「若『以太』牌在弃牌堆中」判定与洗回使用。

## D6 名称解析改造清单

调研结论：**无硬阻塞**（详见 `../10-19-yinlang-and-duplicate-skills/research/06-card-instance-name-plumbing.md`）。
改造原则：**只改「把实例渲染给用户」的路径**，不改按 `definition_id` 判定的规则路径。

### D6.1 三个必须注意的技术点

| # | 事实 | 后果 |
|---|---|---|
| 1 | `card_instance.gd:88 from_dict()` 是**逐键白名单**读取 | **必须同时**改 `to_dict()` 与 `from_dict()`，否则存档/网络/回放往返全部丢字段 |
| 2 | `card_view.gd:294` 是**牌面名称的唯一渲染点** | 不改它则手牌/装备/判定/弃牌/图鉴全都不显示自定义名 |
| 3 | `information_box_layer.gd:519` 会对信息框 title **再做一次** `resolve_card_names_in_text` | 自定义名若撞上已登记双名会被**改写**成那张牌的名字 → 查重必须用双名索引口径 |

### D6.2 数据层（必改）

| 文件:行 | 改动 |
|---|---|
| `scripts/data/card_instance.gd:13` 附近 | 新增 `custom_display_name` / `minted_skill_id`（各带独立注释） |
| `card_instance.gd:257-295 to_dict()` | 加两个键 |
| `card_instance.gd:88-115 from_dict()` | 加两行读取 |
| `card_instance.gd:137 set_hand_view_as()` / `:173 set_hand_view_as_with_face()` | **决策**：视为状态下保留 `custom_display_name`（显示实体原名 + 视为横条），`clear_hand_view_as()`（`:148`）不动 |

### D6.3 集中入口（新增 1 处）

`scripts/autoload/game_settings.gd:1079-1093` 新增 `resolve_instance_display_name(card_dict, definition) -> String`：非空 `custom_display_name` 优先，否则回落 `resolve_card_display_name(definition)`。**所有下游改调它**，避免 20+ 处各自判空。

### D6.4 必改的展示路径

| 文件:行 | 用途 |
|---|---|
| `scripts/ui/card_view.gd:294` / `:275` | ★牌面主名称 / 视为横条（`:662` 悬停 title 随之自动生效） |
| `scripts/ui/equipment_stack_view.gd:198` / `:297` | 装备横条名 / 悬停 title |
| `scripts/ui/player_target_view.gd:1349` / `:1459` / `:1504` | 装备摘要 / 装备悬停 / 判定牌悬停 |
| `scripts/ui/player_target_view.gd:1142` / `:1610` / `:1616` | 判定区 / 装备 / 判定标记名 |
| `scripts/ui/match_table.gd:3112` / `:3126` | 装备槽名 / 本地判定区名 |
| `scripts/ui/match_table.gd:3541` / `:5912` | 装备材料提示 / 装备操作条文本（`_get_active_equipment_definition()` 需同时拿到实例字典） |
| `scripts/ui/developer_console_panel.gd:732` / `:763` | 开发者菜单卡牌文本 |
| `scripts/core/match_controller.gd:4367-4380` | ★`format_card_log_name()` —— **改一处覆盖全部日志调用方**（`:4425`/`:5779`/`:6751`/`:13988`/`:16402`） |
| `scripts/core/match_controller.gd:4464-4473` | `describe_card()` |
| `scripts/core/match_controller.gd:14635` / `:5382` | 重铸日志 / 装备响应 `response_title`（已有实例，改用实例名） |

### D6.5 自动生效、无需改（验证即可）

- `CardView.configure` 的刷新判据（`card_view.gd:241`）已 hash **整个 card 字典** → 新字段自动触发重绘。
- 手牌/飞牌/摸牌：`match_table.gd:2601/4788/4901/5212`；候选牌：`card_selection_panel.gd:768`。
- 存档：`match_controller.gd:15838` + `player_state.gd:508/514/519/525`；读档：`match_controller.gd:16042/16108-16111` + `player_state.gd:359/363/365/367`。
- 回放：`match_replay_recorder.gd:113/137/186`（快照与表现深拷贝）、`match_replay_playback_driver.gd:121`。
- 网络：`match_controller.gd:18097/18117/18146`（快照）、`:6881`（候选）；两个隐私裁剪点只 `erase` 不重建（`:17299-17300`、`:17329-17330`）。
- `card_presentation_event.gd:39/53`、`converted_card_presentation.gd:43-51` 复用 `to_dict()`。
- `ConquestSaveStore.SAVE_FORMAT_VERSION`（`conquest_save_store.gd:12`）**不需要 bump**。

### D6.6 保持定义名的已知降级点（不改，需在文档说明）

`match_controller.gd:4429 format_card_definition_log_name()`、`:5515`（无材料技能响应）、`:5889`（转化响应）、`:10924`（防具发动提示）、`:11123`/`:11142`（记录/移除牌名，**按定义正确**）、`:15221`（濒死救援选项名）、`card_effect_resolver.gd:62`、`card_definition.gd:415`、`skill_definition.gd:1091`、`skills/linggan.gd:293`、`skills/zimo.gd:244`。

### D6.7 不得改动的路径（语义会被污染）

| 文件:行 | 原因 |
|---|---|
| `match_controller.gd:11112 record_card_name()` / `:11131 remove_recorded_card_name()` | `recorded_card_names` / `skill_used_card_names` 存的是 **definition_id**；改成自定义名会污染「是否使用过某牌名」的语义 |
| `card_rule_service.gd:495-498`（延时锦囊同名判定） | 按 `definition_id` 判同名 → 复制【乐不思蜀】得到的牌与真实【乐不思蜀】**在判定区互斥**。这是「规则身份 = 被复制牌」的直接推论，需在文档中明确记录，**不是 bug** |
| `card_rule_service.gd:507/520-521/555-556`（`play_limit_group` 计数） | 造牌副本仍计入被复制牌的出牌次数 |
| `match_controller.gd:7792 get_card_original_name_length()` | 读定义 `rule_name`/`custom_name`，实例自定义名**不参与**名字数结算 → 需在文档中记录该口径（补全项） |

### D6.8 查重口径（必做）

- 复用 `GameDatabase._card_definitions_by_display_name.has(name)`（**双名索引**，正是 `resolve_card_names_in_text` 的匹配口径，因此能同时防住 D6.1 的第 3 点）。
- 需在 `game_database.gd:176` 附近新增公开 API（如 `is_card_display_name_taken(name) -> bool`），避免 `game_data` 层直接触碰私有字段。
- 查重范围 = 全部已登记定义的 `original_name` ∪ `custom_name` ∪ 本局已造牌的 `custom_display_name`。

## D7 边界与不变式

| 不变式 | 保障方式 |
|---|---|
| 造牌失败零副作用 | 全部校验在创建 `CardInstance` 之前完成 |
| 唯一性由权威侧最终裁决 | 界面只做即时提示；端口再校验一次 |
| 牌名不影响规则判定 | 规则路径继续只读 `definition_id`；`custom_display_name` 只用于展示与牌名查询 |
| 存档向后兼容 | 新字段缺省空字符串；不改 `SAVE_FORMAT_VERSION` |
| 不污染图鉴与静态卡表 | 不写任何 `GameDatabase` 容器 |
| 洗回位次可复现 | 位次写入 `random_history` |

## D8 风险

| 风险 | 缓解 |
|---|---|
| 有名称解析路径拿不到实例（只有 `definition_id`），导致局部显示旧名 | D6 清单逐个覆盖；新增集中入口 `resolve_card_name_for_instance` 并在清单中把「只有定义 ID」的路径标记为已知降级点 |
| 自由文本牌名含特殊字符破坏日志或描述解析 | 格式校验拒绝 `|`、换行、超长；`【…】` 解析路径按调研结论处理 |
| 造牌与既有「未知牌」降级混淆 | `definition_id` 始终是被复制牌的真实 ID，因此永不会落入未知牌分支 |
| 洗回时摸牌堆为空 | 位次范围 `0..size` 含端点，空堆时位次为 0，合法 |
