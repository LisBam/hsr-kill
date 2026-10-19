# 技能多实例底座 · 技术设计

## 0. 现状（调研结论，已核实）

| 关注点 | 现状 |
|---|---|
| 技能实例容器 | `match_controller.skill_instances_by_player: {player_id -> {技能ID -> SkillDefinition}}`（`match_controller.gd:496`） |
| 拥有权记录 | `PlayerState.acquired_skills` / `temporary_skills` / `reincarnation_skills` / `dynamic_skill_descriptions` / `skill_used_card_names` 全部按技能 ID 为键 |
| 事件分发 | `TriggerManager` / `RuleEventBus` / `RuleModifierPipeline` 全部按 **owner 对象身份**订阅与解绑 → 天然支持多实例 |
| 技能脚本安装 | `install()` / `uninstall()` 只调用 `subscribe_timing` 与三类 `unsubscribe_owner(self)` → 天然支持多实例 |
| 元数据来源 | `GameDatabase.get_skill(技能ID)` / `create_skill(技能ID)`，只认识 `res://game_data/skills/*.gd` 里登记过的 ID |
| 描述覆盖 | `PlayerState.dynamic_skill_descriptions`（按 ID）+ `MatchController.set_skill_display_description` |
| 名称覆盖 | **不存在**。所有名称路径都是 `GameDatabase.get_skill(技能ID).get("name", 技能ID)` |
| 授予去重 | `grant_acquired_skill` 显式 `if player_skills.has(skill_id): return false`（`match_controller.gd:10302`） |
| 额度 | 记录在 `player.acquired_skills[键]`；读取方 `can_use_acquired_skill` / `consume_acquired_skill_use`；`SkillDefinition.announce_activation` 与 `_can_receive_timing_event` 用 `get_id()` 取键 |

结论：**分发层不需要改动**；需要改动的是「容器键」「按 ID 的查找端口」「快照/存档」「UI/AI 消费者」。

## D1 设计决策：实例键编码

### 候选方案

| 方案 | 形态 | 评价 |
|---|---|---|
| (a) 复合字符串键 | `{技能ID -> SkillDefinition}`，重复实例用 `"zhuru#2"` | 首实例键 == 技能 ID，既有调用方与 35 个测试文件**零改动**；代价是所有 `GameDatabase.get_skill/create_skill` 调用点必须先还原技能 ID |
| (b) 每个 ID 一个数组 | `{技能ID -> Array[SkillDefinition]}` | `get_skill_instance(pid, id)` 语义不变，但**所有**读写点（约 20 处 core + 35 个测试文件）都从「取对象」变成「取数组」，破坏面更大；快照仍需要每实例唯一标识 |
| (c) 运行时技能 ID | 每个组合技能用唯一 ID（`jincheng_1`） | 需要运行时技能定义注册表；且 `GameDatabase.get_skill` 查不到 → 名称退化为 ID（按钮只显示 ID 前 2 字符）、AI 拿不到元数据。代价最高 |

### 决策

采用 **(a) 复合字符串键**，理由：

1. **首实例键 == 技能 ID**，因此单实例场景下容器键、快照、存档、界面、AI、既有测试**全部保持原语义**，这是本次改动最重要的安全边界（`tests/*.gd` 里 35 个文件直接写 `player_skills[skill_id] = skill`，无需修改）。
2. 技能 ID 的字符集是 `[a-z0-9_]+`（`game_database.gd:489-492` 强制），`#` 不会出现在任何合法技能 ID 中，分隔符无歧义。
3. 方案 (c) 被否决：`GameDatabase.create_skill` 只认静态脚本，运行时 ID 会让 `get_skill` 返回 `{}`，直接导致按钮名退化为 ID、AI 跳过该技能、限定技/轮回技标记全部失效。

### 编码规范

```
首实例（第 1 个）：实例键 = 技能 ID
后续实例（第 N 个，N ≥ 2）：实例键 = "<技能ID>#<N>"
```

- N 的取值：该角色容器内 `"<技能ID>#<k>"`（k ≥ 2）当前未被占用的最小整数。移除实例后允许复用空出的 N（保持「最小可用」规则，避免编号无限增长）。
- 解析入口：`SkillDefinition.base_skill_id_of(instance_key: String) -> String`（静态；取最后一个 `#` 之前的部分，无 `#` 时原样返回）。
  - 用 `rfind("#")` 而不是 `find`，保证即使未来技能 ID 里出现 `#` 也只切掉最后一段。

## 1. 端口契约（关键设计）

### 1.1 「键或 ID」双接受约定

所有以技能为参数的公开端口统一采用：

```
先按实例键精确匹配；未命中时按技能 ID 匹配该技能的第一个实例（键序最小者）。
```

这样：
- 既有调用方传技能 ID（单实例时键 == ID）→ 命中唯一实例，行为不变；
- 新调用方传实例键 → 命中指定实例。

适用端口：`get_skill_instance`、`get_skill_instance_key_of`、`has_skill`、`can_activate_skill`、`can_use_acquired_skill`、`consume_acquired_skill_use`、`remove_acquired_skill`、`remove_temporary_skill`、`set_skill_display_description`、`get_skill_used_card_names`、`record_skill_activation`、`repeat_skill_activation`。

### 1.2 `remove_skill` 的例外语义

`remove_skill(player_id, key_or_id)`：

- 传**实例键** → 只移除该实例；
- 传**技能 ID** → 移除该技能的**全部**实例（角色整体失去该技能）。

原因：`remove_skill` 的既有调用方（换将、`_replace_native_character_skills`、【留白】类失去技能）语义都是「这个技能没有了」，保留该语义才能保证既有行为不变。

### 1.3 新增端口

| 端口 | 作用 |
|---|---|
| `get_skill_instances(player_id, skill_id) -> Array[SkillDefinition]` | 取该技能的全部实例（按键序） |
| `get_installed_skill_keys(player_id) -> Array[String]` | 实例键列表（界面逐项展示用） |
| `get_installed_skill_ids(player_id) -> Array[String]` | **技能 ID** 去重列表（既有语义不变） |
| `get_active_skill_keys(player_id) -> Array[String]` | 当前可发动的实例键（取代 `get_active_skill_ids` 在 UI/AI 的使用） |
| `get_skill_instance_key(player_id, skill: SkillDefinition) -> String` | 反查实例键（保存/日志用） |
| `grant_acquired_skill(..., allow_duplicate := false)` | 允许安装第 2..N 个实例 |
| `grant_temporary_skill(..., allow_duplicate := false)` | 同上 |
| `get_runtime_skill_data(player_id, instance_key) -> Dictionary` | 读取实例运行时配置 |
| `set_runtime_skill_data(player_id, instance_key, data) -> void` | 写入实例运行时配置（内容层调用） |

`get_active_skill_ids` **保留**（返回技能 ID，供既有语义调用方使用），但 UI/AI 改走 `get_active_skill_keys`。

## 2. `SkillDefinition` 改动

```gdscript
## 本实例的实例键；未显式设置时等于技能 ID，保证单实例场景与改动前一致。
var _instance_key: String = ""

## 返回实例键；未设置时回落到技能 ID。
func get_instance_key() -> String:
	if _instance_key.is_empty():
		return get_id()
	return _instance_key

## 设置实例键；仅由 MatchController 在安装实例时调用。
func set_instance_key(instance_key: String) -> void:
	_instance_key = instance_key
```

内部 `get_id()` → `get_instance_key()` 的替换点（**这是本次最容易漏的地方**）：

| 位置 | 现状 | 改为 |
|---|---|---|
| `bind()` 轮回技登记 | `register_reincarnation_skill(owner_player_id, get_id(), _metadata)` | `get_instance_key()` |
| `announce_activation()` 记录发动 | `record_skill_activation(owner_player_id, get_id(), ctx)` | `get_instance_key()` |
| `announce_activation()` 消耗额度 | `consume_acquired_skill_use(owner_player_id, get_id())` | `get_instance_key()` |
| `_can_receive_timing_event()` 额度门禁 | `owner.acquired_skills.has(get_id())` + `can_use_acquired_skill(..., get_id())` | `get_instance_key()` |
| `SkillPlayer` 记录键（`skill_used_card_names`） | `get_id()` | `get_instance_key()` |
| 语音/日志名 | `get_id()` | **保持 `get_id()`**（语音按技能、日志显示技能名） |

`collect_snapshot_skill_ids` / `snapshot_has_skill` 的改造：

```gdscript
## 返回快照中的实例键列表（去重、保序）；界面按此逐项展示同名技能的每个实例。
static func collect_snapshot_skill_keys(player_snapshot: Dictionary, character_definition: Dictionary) -> Array[String]

## 返回去重后的技能 ID 列表；保持「角色拥有哪些技能」的既有语义。
static func collect_snapshot_skill_ids(player_snapshot: Dictionary, character_definition: Dictionary) -> Array[String]
	# 实现：collect_snapshot_skill_keys() → base_skill_id_of() → 去重
```

`installed_skill_ids` 过滤逻辑改为：把快照中的键还原成技能 ID 后与 native/mode ID 比较（原先直接比较字符串，单实例时等价）。

## 3. 数据层改动

`scripts/data/player_state.gd`：

```gdscript
## 实例键 → 该实例的运行时配置；组合技能用它保存所选时机/效果等实例级数据。
var runtime_skill_data: Dictionary = {}
```

- `acquired_skills[键]` 记录新增 `"skill_id"` 字段（技能 ID），供「按 ID 汇总」类查询使用。
- `temporary_skills[键]` 同样新增 `"skill_id"`。
- `reincarnation_skills[键]` 键改实例键（首实例 == ID）。
- `dynamic_skill_descriptions[键]` 键改实例键。
- `skill_used_card_names[键]` 键改实例键。
- `from_authoritative_dict` / `to_dict` 增加 `runtime_skill_data` 的读写；其余字段序列化代码不变（键本身就是字符串，序列化天然兼容）。

## 4. 快照与存档

| 字段 | 改动 |
|---|---|
| `installed_skill_ids` | 内容改为实例键列表（首实例 == 技能 ID）。字段名不变，避免破坏旧存档/旧回放解析 |
| `used_limited_skill_ids` | 同上 |
| `used_intrinsic_use_skill_ids` | 同上 |
| `dynamic_skill_descriptions` | 键改实例键 |
| `runtime_skill_data` | 新增 |
| `acquired_skill_remaining_uses` | 键改实例键（`match_table._get_acquired_skill_remaining_uses` 同步） |
| 征服模式 `skill_runtime_states` | 键改实例键 |
| 征服模式 `installed_skill_ids` | 内容改实例键 |

**读档兼容**：旧存档里全是纯技能 ID → `base_skill_id_of` 原样返回 → 安装为首实例 → 行为与改动前一致。因此**不需要**提升 `ConquestSaveStore.SAVE_FORMAT_VERSION`；仅在文档中注明「新存档的 `installed_skill_ids` 可能含 `#N` 后缀，旧版本客户端不保证可读」。

**读档安装顺序**（`_install_all_character_skills`）：

```
1. native 技能 ID 列表（来自 character.get("skills") + mode_skill_ids）→ 逐项安装为首实例
2. 存档中的实例键列表 → 跳过第 1 步已安装的首实例键；其余键：
   a. base_id = base_skill_id_of(key)
   b. skill = GameDatabase.create_skill(base_id)；为 null 则 push_error 并记录到「丢失技能」日志
   c. skill.set_instance_key(key)；skill.bind(...)；player_skills[key] = skill；skill.install()
3. 恢复 acquired/temporary/runtime_skill_data 记录
```

## 5. UI 改动

`CharacterSkillDisplay`（技能查看的唯一实现）：

- `collect_visible_skill_ids()` 保留（返回技能 ID，去重）→ 供既有调用方与测试。
- 新增 `collect_visible_skill_keys()`（返回实例键）→ `build_skill_entries()` 改用它迭代。
- `build_skill_entries()` 每个条目新增 `"instance_key"` 字段；名称/描述从 `GameDatabase.get_skill(base_skill_id_of(key))` 取，`dynamic_skill_descriptions[key]` 优先。
- `build_skill_title()` 同样先还原技能 ID。

`match_table`：

- `_skill_views` 改按实例键为键。
- `skill_list_signature` 用实例键拼接（同名技能产生不同键 → 签名变化 → 按钮重建）。
- 按钮 payload 的 `skill_id` 字段**保留字段名**（协议兼容），值改为实例键；规则侧端口按 1.1 约定解析。
- `_get_visible_skill_ids()` → 新增 `_get_visible_skill_keys()`。
- `_get_acquired_skill_remaining_uses()` 按实例键读。
- `_active_response_skill_id` 语义变为实例键。

`player_target_view`：

- 视觉签名与悬停条目改用实例键列表。

## 6. AI 改动

- `basic_ai_policy`：`_decision_skill_instances` 改按实例键为键；构造评分实例时 `GameDatabase.create_skill(base_skill_id_of(key))`，并把实例键写回 `skill.set_instance_key(key)`（保证评分实例的额度查询命中同一记录）。
- `noname_ai_evaluator` / `identity_strategy_evaluator`：迭代实例键，元数据查询先还原技能 ID；「对手是否拥有技能 X」保持技能 ID 语义（`snapshot_has_skill`）。
- 多个同名实例在 AI 决策列表中各自成为一项候选，AI 可分别评估；不做额外去重。

## 7. 边界

| 机制 | 处理 |
|---|---|
| 轮回技 | `register_reincarnation_skill` 按实例键登记；`ReincarnationSkillService` 内部用 `base_skill_id_of` 还原技能 ID 取元数据与文案；清理时按实例键移除，技能整体移除时按前缀清理全部实例 |
| 欢愉技 | 阿哈时刻参演队列改按实例键登记与匹配（`start_joy_skill_performance` / `finish_...`） |
| 限定技 | `_intrinsic_used_count` 在实例上，天然独立 |
| 领袖技 | 按实例判定；`_get_visible_skill_ids` 的领袖过滤改为按技能 ID 判定（同一技能的所有实例同进同出） |
| 过关斩将 | 「敌方技能机缘不重复」是模式规则，**保持不变**；文档注明 |
| 半锁定技 | `locked_segment` 门禁在实例上，天然独立 |
| 非锁定技失效 | `can_use_effect` 读实例的 `lock`，天然独立 |

## 8. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 漏改 `get_id()` → 额度被静默放开 | 单元测试直接断言「两实例分别计数」与「同一实例第二次被拒」；并在 `_can_receive_timing_event` 加注释说明为何必须用实例键 |
| 快照键含 `#` 导致旧 UI 崩溃 | 所有 UI 名称/描述读取都经过 `base_skill_id_of`；`font_color_audit_test` / `ui_layout_test` 覆盖 |
| 存档往返丢键 | 新增读档往返测试（存档 → 读档 → 断言键与额度） |
| 35 个既有测试文件受影响 | 首实例键 == 技能 ID，预期零改动；以全量测试结果验证 |

回滚点：改动集中在 `skill_definition.gd`、`match_controller.gd`、`player_state.gd`、`character_skill_display.gd`、`match_table.gd`、`player_target_view.gd`、`basic_ai_policy.gd`、`reincarnation_skill_service.gd`、`ahha_moment_system.gd`，按 `implement.md` 的分阶段提交逐段回滚。
