# 技术设计：重构记录牌名的表现形式

## 1. 范围与不变量

### 1.1 本次改动触及的层

```text
内容层  game_data/skills/jiegou.gd          声明一个“可查看按钮”角标条目
   ↓
状态层  scripts/data/player_state.gd        角标条目结构向后兼容扩展（新增 view_kind）
   ↓
权威层  scripts/core/match_controller.gd    角标端口增加可选参数；合成逻辑保持不变
   ↓
表现层  scripts/ui/                         角标区多元素容器 + 按钮组件 + 面板牌名模式
```

### 1.2 明确不变量（不得被本次改动破坏）

| 不变量 | 原因 |
|---|---|
| `character_corner_text` 的生成规则与取值完全不变 | 被 `noname_ai_evaluator` 与至少 5 个既有测试直接断言 |
| `character_corner_text_entries` 的既有条目结构与语义不变 | `noname_ai_evaluator.gd:381` 直接遍历它读取 `text` / `order` |
| `recorded_card_names` 的数据结构与观察者可见性不变 | 已在公开快照，所有角色可见的需求因此天然满足 |
| 【灵感】全部规则行为不变 | 上一轮刚修复的取消语义、目标模式展开、次数消费时机 |
| 技能 `description` 原文不变 | 项目铁律 |

### 1.3 核心设计取舍：按钮条目**不参与**文本合成

`_refresh_character_corner_text()` 目前把所有条目按 `order` 排序、按 `text` 去重后 `"\n".join()` 成单个字符串。

**设计决定**：带按钮语义的条目**根本不进入**这个合成过程。

由此得到两个直接好处：
1. `character_corner_text` 的取值集合不会因为新增按钮而多出一行文本，**既有断言全部原样通过**（回退风险归零）。
2. 表现层不再需要「把字符串拆回多行再猜哪行是按钮」这种脆弱解析——它改读**条目字典**，拿到的是结构化数据。

因此数据流变成两条并行通道：

```text
条目字典 ──┬─→ 仅有 text 的条目 ─→ 按 order 排序去重 ─→ character_corner_text（旧通道，不变）
           └─→ 全部条目 ────────→ 表现层按 order 渲染 ─→ 文本角标 + 按钮（新通道）
```

---

## 2. 数据契约：角标条目扩展

### 2.1 条目结构

```gdscript
# 既有条目（不变）
{"text": "酩酊", "order": 50}

# 新增按钮条目（view_kind 非空即为按钮）
{"text": "解构", "order": 60, "view_kind": "recorded_card_names"}
```

`view_kind` 的语义是**中立的查看类型标识**，核心层只做字符串透传，**不解释其含义、不校验取值**。表现层按下表映射到具体只读界面：

| `view_kind` | 表现层行为 | 数据来源（全部来自公开快照） |
|---|---|---|
| `""`（缺省） | 渲染为既有文本角标 | — |
| `"recorded_card_names"` | 渲染为按钮；点击打开记录牌名只读界面 | `recorded_card_names` |

> 为什么用中立的 `view_kind` 而不是 UI 里判断技能 ID：`component-patterns.md` 的「常见错误」明确禁止「为特定卡牌/技能在 UI 里写名称分支」。新增第二种查看类型时只需在表现层加一个映射，内容层与核心层都不用动。

### 2.2 端口签名（向后兼容）

```gdscript
# match_controller.gd —— 新增可选参数，默认值保持既有行为
func set_character_corner_text_entry(player_id: int, entry_id: String, display_text: String, order: int = 0, view_kind: String = "") -> bool
```

- 已有 5 个调用点（`mingding` / `zhuijian` / `anke` / `zhufeng` / `reincarnation_skill_service`）**全部不传 `view_kind`**，行为与改动前逐字节一致。
- `_refresh_character_corner_text()` 增加一行跳过条件：`view_kind` 非空的条目不加入 `text_lines`。

### 2.3 快照

`character_corner_text_entries` **已经在** `to_dict` 的公开部分（`player_state.gd:527`），本次**不新增任何快照字段**，也不改观察者裁剪规则。

---

## 3. UI 契约：角标区多元素容器

### 3.1 既有实现的硬约束

| 事实 | 位置 | 影响 |
|---|---|---|
| 角标节点位于 `(26, 20)`，零尺寸锚点，`z_index = 5` | `player_target_view.tscn:279-284` | 按钮沿用同一坐标 |
| 角标 `mouse_filter = 2`（IGNORE） | `character_corner_text_badge.tscn:18` | 所以它从不与输入区冲突 |
| **`InputArea` 的 `z_index = 30`** | `player_target_view.tscn:451-452` | **按钮必须 > 30，否则点击被输入区吞掉** |

`z_index = 30` 这一条是本次最容易踩的坑：既有角标因为完全不接收鼠标所以毫无问题，一旦变成可点击按钮，**低于 30 就会被武将牌的选目标输入区拦截**，表现为「按钮点了没反应」。因此新容器取 `z_index = 31`。

### 3.2 节点改造

**移除**场景中的单个 `CharacterCornerTextBadge` 实例，替换为一个纵向容器：

```text
PlayerTargetView (Node2D)
├── ...
├── CharacterCornerStack (VBoxContainer)   ← 新增，position (26,20)，z_index 31
│     ├── CharacterCornerTextBadge         ← 动态创建，每个文本条目一个
│     ├── CharacterCornerActionBadge       ← 动态创建，每个按钮条目一个
│     └── ...（按 order 混排）
└── InputArea (z_index 30)
```

**为什么可以安全移除原节点**：全项目检索确认，**没有任何测试或脚本引用场景中的 `CharacterCornerTextBadge` 节点路径**——测试断言的都是快照字段 `character_corner_text` 字符串与 `character_corner_text_entries` 字典。因此把「一个固定节点」换成「按条目动态创建」不会打破任何既有契约。

### 3.3 排序与去重

表现层排序规则必须与核心层合成逻辑**完全一致**，否则文本角标与按钮的相对顺序会出现两条通道不一致的观感：

- 主键 `order` 升序。
- 次键 `entry_id` 字典序升序。
- **文本条目**参与「同 `text` 只渲染一次」去重（与核心层一致）。
- **按钮条目不去重**：是否显示由内容层写入/移除决定，同一武将牌上出现两个同名按钮属于内容层错误，不应由表现层静默合并。

### 3.4 按钮组件 `CharacterCornerActionBadge`

```
extends Button
signal action_pressed(entry_id: String, view_kind: String)
```

- 视觉规格与 `CharacterCornerTextBadge` 对齐：同一 `StyleBoxFlat` 来源（深褐 0.94 不透明、圆角 3、内边距 4/2）、字号 10、白色字、2 像素黑色描边。
- `mouse_filter` 必须为 `STOP`（接收点击并阻止穿透到 `InputArea`）。
- **禁止**在组件内判断 `view_kind` 的具体取值或读取 `recorded_card_names`：它只发出「某个条目被按下」的信号，由 `match_table.gd` 决定打开哪个只读界面。

---

## 4. 查看界面：记录牌名只读展示

### 4.1 交互语义

- 打开者：**任意角色**（含非持有者、旁观者）。数据来自公开快照，无需额外权限判断。
- 纯只读：无确定/取消按钮、牌面不可选中、不产生 `PlayerAction`、不进入 `EventScheduler` 的请求 ID 命名空间。
- 因此它**不是**一次选择请求，而是表现层自持的只读模态。

### 4.2 与选目标交互的并存

按钮在 `z_index = 31` 之上，选目标期间点击按钮会打开只读窗口并**吃掉**这次点击（不会把该武将加入目标集合）。关闭后选目标流程照常继续——因为只读窗口从未提交响应、未修改任何规则状态，所以不存在「打断请求」的问题。

这一点需要在测试里显式覆盖：打开再关闭前后，`recorded_card_names`、手牌、牌区与事件记录必须完全不变（AC5）。

### 4.3 复用 `CardSelectionPanel`

不新写面板。复用「公共展示」已有的渲染能力，新增一个只读入口：

```gdscript
# card_selection_panel.gd
func show_recorded_names(view_data: Dictionary) -> void
# view_data = {"title": String, "card_names": Array[String], "empty_hint": String}
```

内部对每个 `definition_id` 构造一个候选字典，复用既有的 `_add_card_slot()` 单牌位渲染：

```gdscript
{
  "uid": 伪UID,                       # 负数，见 §5.3
  "visible": true,
  "definition_id": definition_id,
  "card_data": {                       # 仅用于 CardView 渲染
      "definition_id": definition_id,
      "suit": "none",
      "rank": 0,
      "hide_suit_rank": true,
  },
}
```

**关键**：显示名必须经 `GameSettings.resolve_card_name(definition_id)` 解析，以跟随玩家当前的「原文名 / 自定义名」名称模式——这与记录容器本身的既有约定一致（`docs/架构说明.md:308`）。**解析结果只用于渲染，绝不写回记录**。

### 4.4 `CardView` 的「隐藏花色点数」

现状：`_refresh_card_content()`（`card_view.gd:437`）无条件执行 `_corner_label.text = _suit_rank_text`，而 `_suit_symbol()` 对未知花色回退为 `"?"`——因此**传 `suit="none", rank=0` 会渲染出 `?0`**，不满足「隐藏花色与点数」的需求。

改造（最小侵入，向后兼容）：

```gdscript
func configure(card: Dictionary, definition: Dictionary, wooden_ox_card: bool, interactable: bool, dim_when_disabled: bool = true, hide_suit_rank: bool = false) -> void
```

具体改动四处，缺一不可：

1. `configure()` 缓存到 `_hide_suit_rank`。
2. `_refresh_card_content()` 中改为 `_corner_label.visible = not _hide_suit_rank`（**隐藏而非清空文本**：保留 `_suit_rank_text` 的取值，使红色花色配色判断等既有逻辑无需分支）。
3. 悬停副标题（`card_view.gd:598`）同样写死了花色点数，需一并跳过。
4. **必须把新参数并入 `card_view.gd:223` 的配置签名 `hash([...])`**——该实例用签名做增量跳过，若签名不含新参数，同一个 `CardView` 在「正常牌面 ↔ 牌名牌面」之间切换时会命中旧缓存而**保留上一次的花色点数显示**。这是一个不会报错、只在复用场景下出现的隐蔽缺陷。

默认 `false`，全部既有调用点行为不变。

---

## 5. 选择界面：牌名候选通道

### 5.1 现状与落差

【灵感】当前用 `request_control_selection_for_player()` 提交 `control_options`（`{id, label}` 文字按钮），按 `docs/界面与交互.md:121` 的既有规则，`control/bool` 请求**直接复用手牌上方操作区、不进入 `CardSelectionPanel`**。

需求要的是「展开类似五谷丰登的界面，点击牌面选择」——即需要让**文字选项以牌面形式呈现**。`docs/界面与交互.md:282` 的【勘测】已有近似先例（只读牌面 + 文字按钮并存），但它是「牌只读、点按钮」，与本次「**直接点牌面**」不同。

### 5.2 契约扩展（实测后的方案）

新增**选择类型** `card_name` 与请求**顶层字段** `name_candidates`，元素为 `{"definition_id": String, "uid": int}`：

```gdscript
# show_request() 分流顺序：arrange(:254) → card_name(新增) → control(:259)
if choice_type == "card_name":
    _show_name_candidate_request()
```

- **`choice_type` 不是 `control`**：这一点很重要。若沿用 `control`，`match_table.gd:3700 _is_inline_control_choice()` 会在「`control_options` 非空且 `display_candidates` 为空」时把请求判定为「复用手牌上方操作区」，**根本不打开面板**——功能会表现为「点什么都没反应」。
- **提交复用既有 control 通道**：确定时发出 `control_submitted(request_id, definition_id)`，由 `match_table.gd:3542` 转成 `selected_control_id`。这样**无需新增信号、无需新增响应类型**，且天然复用 `ChoiceRequest` 的 `control_ids` 白名单校验（`choice_request.gd:296-297`、`:215-216`）——规则层看到的仍是一个合法的 `control_id`。

> **协议层其实已经就绪**：`linggan.gd:238-249` 现在的文字选项就是 `{"id": definition_id, "label": resolve_card_name(...)}`，恢复时 `response.control_id` 直接当 definition_id 用。也就是说「牌名 ID 走 control 通道」这条约定早已存在并被权威校验支持，本次只是换一种**呈现方式**。

### 5.3 伪 UID 方案与边界

`CardSelectionPanel` 的候选链路以 **int UID** 为单位，最硬的一处是：

```gdscript
698: _card_views[card_uid] = card_view      # UID 为键
671: var card_uid: int = int(candidate.get("uid", -1))   # 无 UID 统一塌缩为 -1
```

若多个牌名候选都不带 UID，它们会在 `_card_views` 里**全部塌缩到同一个 `-1` 键并互相覆盖**，随后 `set_selected_state` 等按 UID 查找的操作会作用到错误的牌面上。

因此为每个牌名候选分配**唯一的负整数伪 UID**：

- 真实实体牌 UID 恒为正，负数不可能与任何真实牌碰撞（面板自身也有 `candidate_uid >= 0` 的既有判定，负值天然不会进入`_selectable_card_uids`）。
- 面板内维护 `伪UID → definition_id` 反查表（新增状态字段 `_name_candidates`）。
- **提交路径上立即转回 `definition_id`**，伪 UID 绝不进入 `PlayerAction`、`ChoiceResponse` 或任何规则状态。
- 面板关闭时清空反查表。

这是本次唯一「借道既有机制」的地方，因此列为**实现阶段的重点复核项**：任何让伪 UID 逃出面板的路径都是缺陷。

### 5.4 取消语义保持

选择界面保留确定/取消。取消必须与现状等价：

- 不消耗【灵感】出牌阶段次数（`_used_this_play_phase` 只在 `execute_cardless_virtual_card_use` 返回 `true` 之后自增——这条刚修复的规则不能被 UI 改造破坏）。
- 不移除任何记录。
- 取消后仍可重新发动，且 `can_activate()` 在存在待处理选择时返回 `false` 的守卫继续有效。

---

### 5.5 下发侧的两个内联判定必须同步排除

新增 `card_name` 类型后，`match_table.gd` 有两处「该请求是否内联到牌桌操作区」的判定必须把它排除，否则请求根本到不了面板：

| 函数 | 行号 | 不加排除的后果 |
|---|---|---|
| `_is_inline_hand_choice()` | `:3676` | `name_candidates` 未必填入 `candidates`；一旦 `candidates` 为空数组，`for` 循环不执行，函数在 `:3687` 直接返回 `true`，请求被误判为「可在本地手牌区完成」，面板不显示 |
| `_is_inline_control_choice()` | `:3700` | 若沿用 `control` 类型且 `display_candidates` 为空，在 `:3705` 返回 `true`，同样不进面板 |

修正：在 `_is_inline_hand_choice()` 的 `:3678` 排除列表中加入 `"card_name"`。`_is_inline_control_choice()` 因为新类型不等于 `control` 而天然不受影响，但实现时仍需复核确认。

> 这两处是「按类型字符串分流」的典型位置，也是本次改造中最容易漏掉、且症状会表现为「点击后毫无反应」的地方——没有报错、没有日志，只有功能静默失效。

## 6. 内容层：由技能声明按钮

`jiegou.gd` 在**记录首次变为非空**时写入按钮条目，在**记录被清空**时移除：

```gdscript
const CORNER_BUTTON_ENTRY_ID: String = "jiegou:recorded_names"
const CORNER_BUTTON_ORDER: int = 60                      # 排在酩酊/永劫(50) 之后、安可(100) 之前
const CORNER_BUTTON_VIEW_KIND: String = "recorded_card_names"
```

- 条目**常驻**：只在首次记录时写入一次，之后不再重复写（避免无谓的状态广播），也**不**在记录清空时移除。
  - 原因：移除记录的【看破】不应该知道【解构】的存在；而 `SkillDefinition` 并没有 `on_skill_loaded` / `on_skill_unloaded` 钩子可以让【解构】在别处被动清理（已用 grep 确认全项目不存在这两个钩子）。
  - 因此「按钮是否显示」交给表现层判断：公开快照的 `recorded_card_names` 为空时角标不渲染。这样【解构】与【看破】彻底解耦。
- 入口判断沿用既有端口存在性检查（`host.has_method("set_character_corner_text_entry")`），与 `mingding` / `anke` / `zhufeng` 的写法保持一致。

---

## 7. 风险与取舍

| 风险 | 影响 | 应对 |
|---|---|---|
| 按钮 `z_index` 低于输入区 | 点击无反应，功能完全不可用 | 取 31，并在测试中断言容器 `z_index > InputArea` |
| 按钮拦截选目标点击 | 玩家想选该角色却打开了记录界面 | 按钮尺寸严格等于角标尺寸（内容撑开，非全牌覆盖），且点按钮不产生任何目标选择副作用 |
| 伪 UID 泄漏到规则层 | 规则层收到不存在的牌 UID，可能误移动/误弃置 | 提交前强制转换；面板关闭清空映射；实现阶段列为复核项 |
| `CardView` 增参破坏既有调用 | 全项目牌面渲染回退 | 新参数带默认值 `false`，且既有调用点不传 |
| 别名校验：名称模式切换后界面不同步 | 与记录容器既有行为不一致 | 统一走 `GameSettings.resolve_card_name` |
| 频繁重建角标节点 | 高频刷新时帧率下降 | 按「条目结构签名」跳过重建，与项目既有做法一致（`decade_hand_container` 的结构签名模式） |

## 8. 回滚形态

改动是**纯增量**的，回滚不需要数据迁移：

1. 内容层不再写 `view_kind` 条目 → 按钮消失，退化为纯文本角标。
2. `set_character_corner_text_entry` 的新参数带默认值 → 核心层可原样保留。
3. `context.card_name_candidates` 缺省 → 【灵感】退回文字按钮选择。
4. `CardView.configure` 的新参数带默认值 → 牌面渲染可原样保留。

即四个改动点**各自独立可退**，没有「必须整批回滚」的耦合。
