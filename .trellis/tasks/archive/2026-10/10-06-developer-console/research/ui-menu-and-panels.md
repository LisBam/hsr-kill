# 调研：局内菜单结构、模态窗口惯例与主题辅助

> 来源：只读代码检索，未修改任何文件。
> 注意：`Get-Content` 的行数在本项目不可靠（CRLF 混用）；本文所有行号取自 read 工具 / grep，二者一致。

---

## TL;DR — 需要动的 3 个地方

1. **`scenes/main.tscn`**（约 597–615 行，`MatchMenu/MenuPanel/MenuVBox` 内）新增按钮行。
2. **`scripts/ui/match_menu.gd`** — `@onready` 引用 + `_ready()` 连接 + `refresh_ui_style()` 上色 + 离线显隐。
3. **新组件** `scripts/ui/developer_console_panel.gd`（可配一个约 15 行的空 `.tscn`），由 `match_table.gd` 按 `CardSelectionPanel` / `MatchChatPanel` 的惯例创建并接线。

**关键事实：`match_menu.gd` 没有自己的 `.tscn`。** 整个 `MatchMenu` 节点树写在 `scenes/main.tscn` 226–615 行，脚本通过 `ExtResource("13_menu")` 挂载（`main.tscn:13` 与 `:236`）。`main.tscn` 根节点是 `Main`（`Control`），其脚本就是 `match_table.gd`（`main.tscn:3`、`:94–102`）——**是**，`main.tscn` 就是包含牌桌（`MatchTable`）的场景。

---

## 1. 局内菜单结构与设置行写法

`match_menu.gd` 结构（约 697 逻辑行 / 844 行）：
`class_name MatchMenu extends Control`（1–2）→ 5 个 `signal`（7–19）→ 2 个 `@export_range`（22–25）→ 约 40 个 `@onready var _x: Type = %UniqueName`（28–148）→ 4 个私有状态 `var`（151–160）→ `_ready()`（164–251）→ 公共 API（255–402）→ `refresh_ui_style()`（406–454）→ 各类 `_populate_*` / `_refresh_*` / `_on_*`（457–844）。

**设置行不是在代码里建的，是在 `main.tscn` 里手工搭的。** 三种既有行型：

### (a) 标签 + 控件的 HBoxContainer 行（最常用）

`main.tscn:293–306`（卡牌名称下拉）：
```
[node name="CardNameRow" type="HBoxContainer" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=741267067]
layout_mode = 2
theme_override_constants/separation = 10

[node name="CardNameLabel" type="Label" parent="MatchMenu/MenuPanel/MenuVBox/CardNameRow" unique_id=1580925356]
layout_mode = 2
size_flags_horizontal = 3
text = "卡牌名称"
vertical_alignment = 1

[node name="MenuCardNameOption" type="OptionButton" parent="MatchMenu/MenuPanel/MenuVBox/CardNameRow" unique_id=1005214864]
unique_name_in_owner = true
custom_minimum_size = Vector2(132, 30)
layout_mode = 2
```

脚本侧取「整行」容器的惯用法是**从控件反查父节点**（`match_menu.gd:106–148`）：
```gdscript
@onready var _player_count_row: Control = _player_count_input.get_parent() as Control
@onready var _mulligan_limit_row: Control = _mulligan_limit_option.get_parent() as Control
@onready var _custom_character_assignment_row: Control = _custom_character_assignment_checkbox
```

### (b) 纯复选框行

`main.tscn:348–362`（「控制所有角色」）。注意每个复选框都挂了一个**同尺寸子指示器 `Control`**（`scripts/ui/identity_marking_indicator.gd`），因为 Godot 默认勾选图标在深色主题下不可见：
```
[node name="ControlAllCharactersCheckBox" type="CheckBox" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=1796864808]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 24)
layout_mode = 2
mouse_default_cursor_shape = 2
text = "控制所有角色"

[node name="SettingsCheckBoxIndicator" type="Control" parent="MatchMenu/MenuPanel/MenuVBox/ControlAllCharactersCheckBox" unique_id=1406219382]
anchors_preset = 0
offset_left = 2.0
offset_top = 5.0
offset_right = 22.0
offset_bottom = 25.0
mouse_filter = 2
script = ExtResource("23_identity_indicator")
```

### (c) 按钮行（要复制的就是这个）

`main.tscn:597–615`。三个按钮直接是 `MenuVBox` 的子节点，**没有包 `HBoxContainer`**：
```
[node name="MenuRestartButton" type="Button" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=1272565438]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 34)
layout_mode = 2
theme_override_styles/normal = SubResource("StyleButtonPrimary")
text = "按设置重新开局"

[node name="MenuConquestExitButton" type="Button" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=2026072620]
unique_name_in_owner = true
visible = false
custom_minimum_size = Vector2(0, 32)
layout_mode = 2
text = "临时退出"

[node name="MenuReturnToMainButton" type="Button" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=1771219610]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 32)
layout_mode = 2
text = "返回主菜单"
```

### ⚠️ 局内菜单「按钮」不是配置行，而是配置行的**兄弟节点**

按钮按 VBox 顺序排在所有设置行之后，面板 `MenuVBox` 的 `theme_override_constants/separation = 1`（`main.tscn:284`）。`MenuPanel` 是右上角锚定的竖长条（`main.tscn:266–280`）：`anchors_preset = 11`、`offset_left = -286.0`、`offset_top = 65.0`、`offset_right = -18.0`、`offset_bottom = -27.0`，宽 268px。

### 要复制的确切模式（「开发者设置」按钮）

在 `MenuReturnToMainButton`（611–615）**之前**插入：
```
[node name="MenuDeveloperSettingsButton" type="Button" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=<新的唯一整数>]
unique_name_in_owner = true
visible = false
custom_minimum_size = Vector2(0, 32)
layout_mode = 2
text = "开发者设置"
```

`unique_id=` 是 Godot 4.6 新增的场景内唯一标识，`main.tscn` 中**每个**节点行都有；新增节点必须给一个当前场景未用过的整数。**不要手写 `%` 名字**——是 `unique_name_in_owner = true` 把节点名注册进 `%` 表。

`match_menu.gd` 侧（放在 `_main_menu_button` 声明之后，即 `:103` 后）：
```gdscript
## 开发者设置入口按钮；仅在纯离线对局显示，局域网房主与客户端一律隐藏。
@onready var _developer_settings_button: Button = %MenuDeveloperSettingsButton
```

`_ready()`（`:172` `_main_menu_button.pressed.connect(_request_main_menu)` 之后）加：
```gdscript
_developer_settings_button.pressed.connect(_request_developer_settings)
```

`refresh_ui_style()`（`:415` `_main_menu_button` 上色之后）加：
```gdscript
BattleUIStyle.apply_interaction_button(_developer_settings_button, BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false)
```

新增出口（模仿 `:765–767` 的 `_request_chat_toggle`，**菜单只发信号、不自己管窗口**）：
```gdscript
## 发出开发者控制台打开请求；菜单不创建窗口，由桌面统一创建与持有。
signal developer_settings_requested

func _request_developer_settings() -> void:
	_menu_panel.visible = false
	developer_settings_requested.emit()
```

新 signal 要加进文件顶部 7–19 行的 signal 区，并保持「组件只发请求、桌面执行」的既有约定（文件头注释明说：*「该组件只管理菜单显隐和下一局人数输入，通过信号请求桌面执行名称切换或重新开局。」*）。

---

## 2. 打开/关闭与层级

### z_index / 图层（硬约束，文档已固化）

- `MatchMenu` 根：**`z_index = 500`**（`main.tscn:228`）。
- 文档 `docs/界面与交互.md:204` 给出完整固定层级表：
  > 牌桌与手牌 `0`、托管滤镜 `5`、本地技能栏 `6`、飞牌与卡牌动画 `30`、技能发动名 `31`、「记录」面板 `35`、对手聊天气泡 `38`、选将遮罩 `40`、局内聊天窗口 `45`、统一信息框 `100`、阿哈时刻过场动画 `120`、卡牌选择窗口 `150`、机缘选择弹窗 `180`、结算面板 `220`、局内菜单 `500`、回放重演覆盖层 `620`。**新增界面必须落在上表已定义的层级之间，不得插队改变既有遮挡关系。**
- → 开发者控制台应取 **`z_index = 520`**（菜单 500 之上、回放覆盖层 620 之下）。
  **不要**照抄 `CardSelectionPanel.MODAL_Z_INDEX = 150`：150 低于菜单 500，从菜单弹出的窗口会被菜单面板盖住。
- 文档 `docs/界面与交互.md:105` 再次确认：*「菜单根层级固定为 `z_index=500`，高于选将遮罩及候选武将牌」*。
- `MatchMenu` 根 `mouse_filter = 2`（IGNORE），`MenuPanel` 未设（默认 STOP）。
- `_move_to_input_front()`（`match_menu.gd:255–259`）在 `call_deferred` 里把面板与按钮 `move_to_front()`，因为「展开面板的输入优先于运行时创建的武将牌和选将遮罩」。

### 显隐

- 菜单面板显隐只有两个入口：`_toggle_menu()`（`:760–761`，直接翻 `_menu_panel.visible`）与 `set_menu_open(open)`（`:309–317`，带焦点规则）。对外只读接口 `is_menu_open()`（`:304–305`）。
- 按钮按下 `_menu_button.pressed.connect(_toggle_menu)`（`:167`）。
- `set_menu_open` 的焦点约定（`:311–317`）：打开时若 `_authority_controls_visible` 则 `_restart_button.grab_focus()`，否则 `_main_menu_button.grab_focus()`；关闭时 `_menu_button.grab_focus()`。**新增按钮若要参与键盘导航，必须考虑这里。**

### Esc / 空白点击

- **Esc 不在 `match_menu` 里处理。** 桌面 `match_table.gd:3450 _unhandled_input()` 统一处理 `KEY_ESCAPE`（`:3457–3472`，按优先级：装备动作 → 振旗费用 → 内联 control → 内联选牌 → 已选牌取消）。安卓返回键走 `_on_unhandled_android_back_requested()`（`:3521–3533`），末行 `match_menu.set_menu_open(not match_menu.is_menu_open())`。**`MatchMenu` 自己没有任何 Esc 处理。**
- **空白点击**在 `match_table.gd:3503 _close_open_match_overlays_from_blank_click()`（由 `:3482` 的左键未消费分支和 `:662` 的 `match_log_panel.blank_area_pressed` 调用）：
```gdscript
	if match_menu != null and match_menu.is_menu_open():
		match_menu.set_menu_open(false)
		closed_any_overlay = true
```
**模态必须在 `_unhandled_input` 里抢在菜单之前消费 Esc/左键**，否则空白点击会穿透到牌桌。参考 `CardSelectionPanel`：它不实现 `_unhandled_input`，而是用一个全屏 `ColorRect` 遮罩 `MOUSE_FILTER_STOP` 把点击全部吃掉。

### 从菜单打开的模态 — 是否已有先例？

**没有「从局内菜单打开的模态窗口」先例。** 从菜单出发的只有「聊天」按钮，它打开的是**非模态**的 `MatchChatPanel`（`match_table.gd:1297–1302` 创建，`chat_toggle_requested` 信号触发 `_on_match_chat_toggle_requested()` `:1577`）。

真正的**模态**先例有三个，全在牌桌层：

| 组件 | 层级 | 遮罩实现 | 关掉方式 |
|---|---|---|---|
| `CardSelectionPanel` | `MODAL_Z_INDEX = 150`（`card_selection_panel.gd:31`） | 代码建的 `_shade: ColorRect`，`mouse_filter = MOUSE_FILTER_STOP`（`:159–163`） | 取消按钮 / 规则层 `close()` |
| `CharacterSelectionPanel` | `z_index = 40`（`main.tscn:923`） | 场景内 `SelectionShade` ColorRect，`mouse_filter = 1`（`main.tscn:932–940`） | `close()` |
| `AllCardsPanel` 的资料弹窗 | 子节点 `AllCardsInfoBackdrop`，`z_index = 30`（`all_cards_panel.tscn:282–292`） | `mouse_filter = 0`（STOP），点击遮罩 → `_on_information_backdrop_gui_input` 关闭（`all_cards_panel.gd:565–572`） | 遮罩左键 / 关闭按钮 / Esc |

**遮罩阻断输入的标准做法**（三种都用）：一个全屏 `ColorRect`，`mouse_filter = Control.MOUSE_FILTER_STOP`，颜色取 `BattleUIStyle.get_color("shade")` 或 `Color(shade, opacity)`。主菜单设置遮罩是同款：`MainMenuSettingsBackdrop`（`main.tscn:1768–1778`），`color = Color(0,0,0,0.86)`（ColorRect 默认 `mouse_filter = STOP`，所以没写）。

**Esc 关闭模态的标准做法**（`all_cards_panel.gd:968–976`）：
```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _information_backdrop.visible:
		_close_information()
	else:
		MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())
		close_requested.emit()
	get_viewport().set_input_as_handled()
```
（`main_menu.gd:1638–1644` 是同一形态。`MobileKeyboardGuard.release_text_focus_and_hide(get_viewport())` 是打开/关闭任何带输入框的模态前的必备调用，见 `main_menu.gd:1262`、`:1274`、`:1291`。）

**暂停期间可操作性**：`MatchMenu` 本身**没有**声明 `process_mode`，但运行时创建的模态组件普遍声明了 `process_mode = Node.PROCESS_MODE_ALWAYS`（`match_chat_panel.gd:51`、`opportunity_choice_panel.gd:39`、`game_settlement_panel.gd:75`、`information_box_layer.gd:189`、`match_log_panel.gd:43`、`match_replay_overlay.gd:58`）。若开发者控制台需在阿哈时刻过场暂停期间保持可操作，在 `_ready()` 里加 `process_mode = Node.PROCESS_MODE_ALWAYS`。

---

## 3. 离线 vs LAN 门控

**唯一权威判定点在 `match_table.gd:4187–4198`：**
```gdscript
## 按当前网络权威身份刷新局内菜单；离线玩家与房主保留权威设置，局域网客户端只显示本地可生效选项。
func _refresh_match_menu_authority_controls() -> void:
	if match_menu == null or not is_instance_valid(match_menu) or match_controller == null or match_controller.network_gateway == null:
		return
	match_menu.set_authority_controls_visible(not match_controller.network_gateway.is_lan_client())
	# 控制全部角色只属于纯离线对局；局域网房主虽然拥有其他权威设置，也必须隐藏该项。
	var is_offline_mode: bool = match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE
	match_menu.set_offline_controls_visible(is_offline_mode)
	if main_menu != null and is_instance_valid(main_menu):
		main_menu.set_control_all_characters_visible(is_offline_mode)
	# 只有标准身份局需要推测隐藏身份；斗地主、2v2与车轮战身份全明置时隐藏该开关。
	var current_match_mode: String = str(_snapshot.get("match_mode", GameSettings.next_match_mode if GameSettings != null else "identity"))
	match_menu.set_auto_identity_marking_visible(current_match_mode == "identity")
```
调用点：`match_table.gd` **669, 1038, 1052, 1091, 1102, 1730**。

**确切的字段/信号：**
- 字段：`match_controller.network_gateway.mode == NetworkGateway.Mode.OFFLINE`。`NetworkGateway` 枚举在 `scripts/network/network_gateway.gd:42–44`，`var mode: Mode = Mode.OFFLINE`（`:127`）。**没有 `is_offline()` 辅助函数**（只有 `is_lan_host()` `:357`、`is_lan_client()` `:362`、`is_lan_match_active()` `:367`）——必须写全 `mode == NetworkGateway.Mode.OFFLINE`。
- 菜单侧字段（`match_menu.gd:154`）：`## 当前是否处于纯离线模式；false时控制全部角色选项无条件隐藏。` `var _offline_controls_visible: bool = true`（默认 true 兼容离线/单机启动）。
- 菜单侧 setter（`match_menu.gd:357–362`）——**「控制所有角色」就是离线门控的范式**：
```gdscript
## 设置离线专属控件是否可见；联机房主虽然拥有权威设置权限，也不能启用控制全部角色。
func set_offline_controls_visible(controls_visible: bool) -> void:
	_offline_controls_visible = controls_visible
	_control_all_characters_checkbox.visible = _authority_controls_visible and _offline_controls_visible
	if not _control_all_characters_checkbox.visible and _control_all_characters_checkbox.has_focus():
		_control_all_characters_checkbox.release_focus()
```
**要加的（完全同构）：**
```gdscript
	_developer_settings_button.visible = _authority_controls_visible and _offline_controls_visible
	if not _developer_settings_button.visible and _developer_settings_button.has_focus():
		_developer_settings_button.release_focus()
```
⚠️ **不要**加进 `set_authority_controls_visible()`（`:333–348`）。那个入口的注释是硬规则：*「统一控制所有依赖房主权威的局内设置；后续新增同类功能必须加入本入口，避免非房主看到无法生效的控件。」* 文档 `docs/界面与交互.md:139` 也写：*「后续新增以房主为准的功能必须加入同一权威控件组，不得单独出现在非房主 UI。」* 但「开发者设置」按需求是**仅单机**，语义上属于 `_offline_controls_visible` 组（和「控制所有角色」同组），**局域网房主也应隐藏**。
另注：`set_authority_controls_visible` 与 `set_offline_controls_visible` 都会重算 `_control_all_characters_checkbox.visible`；按钮若只在后者重算，前者被调用时不会重算——**稳妥做法是把按钮显隐抽成一个 `_refresh_offline_only_controls()` 私有函数，从两个 setter 调用**。

`_ready()` 里的初始态（`:240`）：`_menu_panel.visible = false`。按钮在 `.tscn` 里 `visible = false`，与 `MenuConquestExitButton` 一致。

---

## 4. 面板实例化惯用法

`main.tscn` **同时**用两种方式，按「是否属于牌桌固定框架」区分：

### (a) 场景内已实例化的（静态框架）

`main.tscn:917`：
```
[node name="CardSelectionPanel" parent="." unique_id=2124335258 instance=ExtResource("16_card_selection")]
layout_mode = 1
```
⚠️ 这个节点**没有** `unique_name_in_owner = true`，所以 `match_table.gd` 用 `$` 而不是 `%`（`match_table.gd:242`）：
```gdscript
@onready var card_selection_panel: CardSelectionPanel = $CardSelectionPanel
@onready var match_menu: MatchMenu = %MatchMenu                    # :224，场景里标了 unique_name_in_owner
@onready var main_menu: MainMenu = %MainMenu                        # :230
@onready var character_selection_panel: CharacterSelectionPanel = %CharacterSelectionPanel  # :239
```

### (b) 运行时代码创建的（`preload` + `instantiate` + `add_child`）

顶部常量区 `match_table.gd:6–25`：
```gdscript
const PLAYER_SEAT_SLOT_SCENE: PackedScene = preload("res://scenes/components/player_seat_slot.tscn")
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")
const INFORMATION_BOX_LAYER_SCENE: PackedScene = preload("res://scenes/components/information_box_layer.tscn")
const OPPORTUNITY_CHOICE_PANEL_SCENE: PackedScene = preload("res://scenes/components/opportunity_choice_panel.tscn")
const GAME_SETTLEMENT_PANEL_SCENE: PackedScene = preload("res://scenes/components/game_settlement_panel.tscn")
```

创建函数的标准形态（`match_table.gd:1287–1302`）：
```gdscript
func _create_game_settlement_panel() -> void:
	game_settlement_panel = GAME_SETTLEMENT_PANEL_SCENE.instantiate() as GameSettlementPanel
	game_settlement_panel.name = "GameSettlementPanel"
	add_child(game_settlement_panel)
	game_settlement_panel.close_requested.connect(_on_game_settlement_close_requested)
	game_settlement_panel.save_replay_requested.connect(_on_save_replay_requested)

func _create_match_chat_panel() -> void:
	match_chat_panel = MatchChatPanel.new()
	match_chat_panel.name = "MatchChatPanel"
	add_child(match_chat_panel)
	match_chat_panel.chat_submitted.connect(_on_match_chat_submitted)
	match_chat_panel.close_requested.connect(_on_match_chat_close_requested)
```
**父节点一律是 `self`（即 `Main` 根），`name` 显式设置。** z-order **不在创建处设置**，而在组件自己的 `_ready()` 里：
- `card_selection_panel.gd:157` → `z_index = MODAL_Z_INDEX`（150）
- `match_chat_panel.gd:52` → `z_index = PANEL_Z_INDEX`（45）
- 唯一例外是 `information_box`（`match_table.gd:1125–1129`），就地设 `z_index = 100` 再 `add_child`：
```gdscript
	information_box = INFORMATION_BOX_LAYER_SCENE.instantiate() as InformationBoxLayer
	information_box.name = "InformationBoxLayer"
	information_box.z_index = 100
	add_child(information_box)
	information_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
```

**推荐给开发者控制台**：照 `MatchChatPanel` 走纯代码创建（无 `.tscn`），或照 `CardSelectionPanel` 走「约 15 行空 `.tscn` + 全代码构建」。`card_selection_panel.tscn` 全文只有 15 行，可作模板：
```
[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/ui/card_selection_panel.gd" id="1_script"]

[node name="CardSelectionPanel" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_script")
panel_max_width = 820.0
panel_max_height = 460.0
shade_color = Color(0.01, 0.008, 0.006, 0.42)
```

**接线位置**：`match_table.gd` 的 `_ready()` 中 620–664 是一大段信号连接；菜单信号在 635–639：
```gdscript
	match_menu.card_name_toggle_requested.connect(_on_name_mode_pressed)
	match_menu.restart_requested.connect(_on_restart_requested)
	match_menu.main_menu_requested.connect(_on_main_menu_requested)
	match_menu.conquest_temporary_exit_toggle_requested.connect(_on_conquest_temporary_exit_toggle_requested)
	match_menu.chat_toggle_requested.connect(_on_match_chat_toggle_requested)
```
`match_menu.developer_settings_requested.connect(_on_developer_settings_requested)` 加在这里。`_create_*` 的调用点在 `_ready()` 靠前区域（约 600 行之前），需找到 `_create_match_chat_panel()` 的调用处并仿照添加。

**`refresh_ui_style()` 也要挂**：`match_table.gd:3637` `match_menu.refresh_ui_style()`，`:3664–3665` `card_selection_panel.refresh_ui_style()` / `character_selection_panel.refresh_ui_style()` —— 新组件若实现 `refresh_ui_style()`，要在这里调用。

---

## 5. `all_cards_panel.gd` 复用评估

**它是什么**：`class_name AllCardsPanel extends Control`（976 行），主菜单「所有卡牌」**图鉴页**（不是局内弹窗）。三个子分页 `characters` / `game_cards` / `opportunities`（常量 19–28），左侧分页列表 + 右侧搜索框 + 自适应网格 + 空结果提示 + 一个**嵌套资料弹窗**。

**信号**：**只有一个** —— `signal close_requested()`（`:7`）。**没有多选、没有选择提交信号。**

**数据源**：**纯静态定义**，不读 `GameState`：
- `GameDatabase.cards` / `GameDatabase.get_card(card_id)`（`_build_game_card_entries()` `:388–395`）
- `GameDatabase.characters` / `get_character`（`_build_character_entries()` `:343`）
- `OpportunityCatalog.get_all_cards()`（`_build_opportunity_entries()` `:412`）
- 代表牌面：`_build_representative_card_cache()` 从牌堆配置取每种定义的首个花色点数，然后**伪造一个负 UID**（`:398–399`）：
```gdscript
		representative_card["uid"] = -(card_index + 1)
		representative_card["definition_id"] = card_id
```
注释明说（`:394`）：*「当前游戏牌静态定义；来自数据库深拷贝，不写回任何展示字段。」*

**耦合程度（决定复用难度）：高。** 硬耦合点：
1. `_current_category` / `CATEGORY_ORDER` / `_search_queries_by_category` 三分页状态机（`:183–196`）。
2. `_entries: Array[Dictionary]` 存的是 `{id, search_text, slot, size}`（`:438–443`），**不是牌数据**；`_add_entry_slot()` 只负责槽位布局。
3. 搜索/布局整条链（`_queue_filter_and_layout` `:455`、`_apply_filter_and_layout` `:463–519`）与 `_grid_scroll.resized` 绑定。
4. 点击行为固定为 `_open_information`（`:403` `card_view.pressed.connect(_open_information.bind(CATEGORY_GAME_CARDS, card_id))`），**没有选中态**。

**真正可复用的资产**是它内嵌的**资料弹窗结构**（`AllCardsInfoBackdrop` + `InfoCenter/CenterContainer` + `AllCardsInfoPanel`，`all_cards_panel.tscn:282–307`），以及它的关闭逻辑：
```gdscript
## 点击完整资料面板外的遮罩时关闭资料；仅响应鼠标左键按下，滚轮与右键不会误关闭。
func _on_information_backdrop_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
		_close_information()
		accept_event()
```
以及 `_close_information(restore_focus: bool = true)`（`:555–561`）与 `_unhandled_input` 的 Esc 优先级（`:968–976`）。

### ✅ 结论：做「从牌堆任选任意张牌」应抄 `card_selection_panel.gd`，不是 `all_cards_panel.gd`

`card_selection_panel.gd`（1000 行）**已经就是**一个多选牌面选择器，机制完全命中需求：
- `signal choice_submitted(request_id: int, selected_card_uids: Array[int])`（`:7`）
- `_selected_card_uids: Array[int]`（`:79`）+ `_selectable_card_uids: Array[int]`（`:85`）
- 多选逻辑（`_on_card_pressed` `:821–836`）：
```gdscript
	if _selected_card_uids.has(card_uid):
		_selected_card_uids.erase(card_uid)
	else:
		# 最大选择数；单选请求点击新牌时直接替换旧选择，减少额外取消步骤。
		var max_select: int = int(_choice_request.get("max_select", 1))
		if max_select == 1:
			_selected_card_uids.clear()
		if _selected_card_uids.size() < max_select:
			_selected_card_uids.append(card_uid)
	_refresh_selection_state()
```
- 确定按钮按 `min_select` / `max_select` 启用（`:840–856`）：`_confirm_button.disabled = _selected_card_uids.size() < min_select or _selected_card_uids.size() > max_select`
- 牌面创建 `_add_card_slot()`（`:749–805`）用 `CardView`，`card_view.configure(card_data, definition, false, selectable, dim_when_disabled, hide_suit_rank)`，`definition = GameDatabase.get_card(str(card_data.get("definition_id", "")))`（`:762`）——**即「实时牌实例字典 `card_data` + 静态定义 `definition`」两份数据**，正是牌堆选牌需要的形态。
- **无 `max_select` 上限的「任意张」**：只需传一个很大的 `max_select`（当前实现 `int(_choice_request.get("max_select", 0))`，**没有「无上限」哨兵值**）。
- 数据源是**规则层下发的 `choice_request` 字典**（`show_request(choice_request)` `:245`），不是自己读 `GameState`。
- ⚠️ **快照里只有 `draw_pile_count`，没有牌堆牌面数组**（`game_state.gd:249`：`"draw_pile_count": draw_pile.size()`；`to_dict(viewer_id, reveal_private)` `:183` 是唯一的观察者快照出口）。所以在局域网/客户端视角下拿不到牌堆明细——这也印证了「仅单机」的门控是对的。离线/权威侧需走 `match_controller.state.draw_pile` 并自行 `to_dict()`，或复用 `get_top_draw_card_candidates()`。
- 现成的相关控制器 API：`match_controller.gd:9051 gain_draw_pile_card_by_uid(...)`、`:9072 arrange_draw_pile_cards(...)`、`:9126 create_and_insert_card_into_draw_pile(...)`、`:7183` / `:7490` 处有遍历 `state.draw_pile` 的取牌实现。

---

## 6. 样式/主题辅助函数

**`scripts/ui/battle_ui_style.gd`**（`class_name BattleUIStyle extends RefCounted`，201 行，全 `static`）—— **唯一应该调用的主题工厂**：
```gdscript
static func get_color(key: String, fallback: Color = Color.WHITE) -> Color          # :80  语义键取色
static func is_monochrome() -> bool                                                 # :85
static func make_panel(background_color := UNSET_COLOR, border_color := UNSET_COLOR, border_width := 1, corner_radius := 10) -> StyleBoxFlat   # :91
static func make_button(background_color := UNSET_COLOR, border_color := UNSET_COLOR, border_width := 1, corner_radius := 8) -> StyleBoxFlat    # :137
static func make_inset_panel(background_color := UNSET_COLOR, border_color := UNSET_COLOR, border_width := 2, corner_radius := 6) -> StyleBoxFlat  # :147  ← 弹窗主框用这个
static func make_decade_button(background_color := UNSET_COLOR, border_color := UNSET_COLOR, emphasized := false) -> StyleBoxFlat   # :167
static func apply_interaction_button(button: Button, background_color := UNSET_COLOR, border_color := UNSET_COLOR, emphasized := true) -> void   # :186  ← 按钮一律用这个
static func apply_main_menu_scroll_bar_style(scroll_bar: VScrollBar, scroll_bar_width := MAIN_MENU_SCROLL_BAR_WIDTH) -> void   # :113
static func make_main_menu_scroll_bar_style(background_color: Color, border_color: Color) -> StyleBoxFlat   # :124
static func set_active_style(style_id: String) -> void / get_active_style_id() -> String   # :70 / :75
```
`apply_interaction_button` 一次性覆盖 normal/hover/pressed/focus/disabled 与 4 个字体色（`:193–201`）。**任何新按钮都必须用它**，否则会回退 Godot 默认皮肤——文档 `docs/界面与交互.md:169` 明文禁止。

**常用语义键**（来自 `get_color(...)` 调用点）：`panel` `metal_panel` `jade_panel` `border` `accent` `action_button` `disabled_button` `disabled_button_border` `text_primary` `text_secondary` `text_muted` `button_font` `button_hover_font` `button_pressed_font` `disabled_button_font` `shade` `table_surface` `rail` `selection_panel` `selection_section` `legal_target` `danger` `outer_background`。

**`scripts/ui/ui_style_registry.gd`**（`class_name UIStyleRegistry extends RefCounted`，377 行，全 `static`）—— **只被 `BattleUIStyle` 和设置菜单的下拉框使用，新 UI 不要直接调它**：
```gdscript
static func get_style_ids() -> Array[String]                                    # :364
static func get_display_name(style_id: String) -> String                        # :369
static func normalize_style_id(style_id: String) -> String                      # :376
static func get_value(style_id: String, key: String, fallback = null) -> Variant # :381
static func get_color(style_id: String, key: String, fallback := Color.WHITE) -> Color  # :390
static func is_monochrome(style_id: String) -> bool                             # :397
```
常量：`STYLE_SPACE_MONO = "space_mono"`（默认）、`STYLE_DECADE_WOOD = "decade_wood"`、`STYLE_PREMIUM_BLACK_GOLD = "premium_black_gold"`（`:8` / `:12` / `:15` / `:19` / `:22`）。

**`all_cards_panel.gd` 里两个私有但值得照抄的辅助函数**：
```gdscript
## 创建没有重复阴影的内层面板；图鉴外框保留唯一强阴影，内部只用细边区分内容。
func _make_flat_inner_panel(background_color: Color, border_color: Color, border_width: int = 1, corner_radius: int = 5) -> StyleBoxFlat:  # :935
	var style: StyleBoxFlat = BattleUIStyle.make_panel(background_color, border_color, border_width, corner_radius)
	style.shadow_size = 0
	style.shadow_offset = Vector2.ZERO
	return style

## 为搜索输入框应用当前主题常态与焦点样式；文本选择区使用半透明强调色。
func _apply_line_edit_style(line_edit: LineEdit) -> void:  # :920
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("action_button"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_placeholder_color", BattleUIStyle.get_color("text_muted"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))
```
（`main_menu.gd:1738` 有一份完全相同的 `_make_flat_inner_panel`——说明这是「每个面板各持一份私有副本」的既定风格，不是共享工具。）

**`refresh_ui_style()` 契约**（所有面板组件都实现）：`if not is_node_ready(): return` 开头，然后重设 stylebox + 所有字体色 + 转发给子组件；订阅 `GameSettings.ui_style_changed`（如 `all_cards_panel.gd:225`、`online_settings_panel.gd:101`）。**新组件必须实现它。**

**复选框**：`CheckBox` 只设 `add_theme_color_override("font_color", BattleUIStyle.get_color("text_secondary"))`（`match_menu.gd:419–424`），勾选框靠子节点 `IdentityMarkingIndicator`（`scripts/ui/identity_marking_indicator.gd`，61 行，`_draw()` 自绘 2px 边框 + 2.5px 对勾）。文档 `docs/界面与交互.md:114` 规定所有复选框必须用它。

---

## 7. 命名约定

| 类别 | 约定 | 例 |
|---|---|---|
| 脚本 | `snake_case.gd`，`class_name PascalCase`，`extends Control` | `match_menu.gd` / `class_name MatchMenu` |
| 节点名 | `PascalCase`，**前缀标明所属组件**避免全局冲突 | `MatchMenu`, `MenuPanel`, `MenuVBox`, `MenuRestartButton`, `MenuConquestExitButton`, `MenuReturnToMainButton`, `MenuCardNameOption`, `NextPlayerCountInput`, `AiResponseDelaySlider`, `ControlAllCharactersCheckBox`, `MatchMenuWheelDuelFaceUpCandidateInput`, `AllCardsInfoBackdrop`, `OnlineSettingsFrame` |
| `%` 唯一名 | `.tscn` 里 `unique_name_in_owner = true`；脚本里 `@onready var _x: Type = %NodeName` | `@onready var _menu_panel: PanelContainer = %MenuPanel`（`match_menu.gd:35`） |
| 非唯一/非本组件节点 | 用 `$` 绝对路径 | `@onready var card_selection_panel: CardSelectionPanel = $CardSelectionPanel`（`match_table.gd:242`） |
| 旧场景兼容 | `get_node_or_null("%X") as T` + null 判断 | `@onready var _chat_button: Button = get_node_or_null("%MatchChatButton") as Button`（`match_menu.gd:32`） |
| 私有变量/函数 | 单下划线 `_snake_case` | `_menu_panel`, `_refresh_match_menu_authority_controls()` |
| 私有「整行容器」引用 | `<控件>_row` | `_ai_response_delay_row`, `_mulligan_limit_row`, `_player_count_row` |
| 信号 | 动词过去式 / `_requested` / `_changed` / `_submitted` / `_toggled`；**过去式表示「已发生」，`_requested` 表示「请求桌面执行」** | `card_name_toggle_requested(mode: int)`（`:7`）, `restart_requested(player_count: int)`（`:10`）, `main_menu_requested`（`:13`）, `conquest_temporary_exit_toggle_requested`（`:16`）, `chat_toggle_requested`（`:19`）, `choice_submitted(request_id, selected_card_uids)`（`card_selection_panel.gd:7`）, `close_requested()`（`all_cards_panel.gd:7`） |
| 信号处理函数 | `_on_<signal_name>()` / `_request_<action>()` | `_on_restart_requested(player_count)`（`:3715`）, `_request_chat_toggle()`（`:765`） |
| 常量 | `UPPER_SNAKE_CASE`，`const X: Type = value`，带类型 | `MODAL_Z_INDEX: int = 150`（`card_selection_panel.gd:31`）, `PANEL_Z_INDEX: int = 45`（`match_chat_panel.gd:15`）, `SETTINGS_FILE_PATH: String = "user://game_settings.cfg"` |
| `@export` | 一律 `@export_range(...)` + `##` 中文注释（说明作用/取值范围/默认值理由/运行时是否需改） | `@export_range(0.5, 1.0, 0.01) var character_card_scale: float = 0.72`（`all_cards_panel.gd:63`） |
| 文档注释 | 每个 `@onready` / `var` / `func` / `signal` 上方 `##` 中文说明 | **AGENTS.md 强制要求，且严禁改已有注释** |

---

## 8. 滑块 + 数字输入

**项目里没有任何「HSlider + SpinBox 双向绑定」的现成组合。** 两者分开使用：

### HSlider 唯一形态

`AiResponseDelayRow` 是 **VBoxContainer**（标签在上、滑条在下）—— `main.tscn:544–560`：
```
[node name="AiResponseDelayRow" type="VBoxContainer" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=467391300]
layout_mode = 2
theme_override_constants/separation = 2

[node name="AiResponseDelayLabel" type="Label" parent="MatchMenu/MenuPanel/MenuVBox/AiResponseDelayRow" unique_id=297365554]
unique_name_in_owner = true
layout_mode = 2
text = "AI响应速度：0.30秒"

[node name="AiResponseDelaySlider" type="HSlider" parent="MatchMenu/MenuPanel/MenuVBox/AiResponseDelayRow" unique_id=388650724]
unique_name_in_owner = true
custom_minimum_size = Vector2(0, 22)
layout_mode = 2
min_value = 0.1
max_value = 1.0
step = 0.05
value = 0.30000000000000004
```

范围/步长在 `_ready()` 里由**全局常量**覆盖（`match_menu.gd:178–189`）：
```gdscript
	_ai_response_delay_slider.min_value = GameSettings.MIN_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.max_value = GameSettings.MAX_AI_RESPONSE_DELAY_SECONDS
	_ai_response_delay_slider.step = GameSettings.AI_RESPONSE_DELAY_STEP_SECONDS
	_ai_response_delay_slider.value = GameSettings.ai_response_delay_seconds
	_ai_response_delay_slider.value_changed.connect(_on_ai_response_delay_changed)
	GameSettings.ai_response_delay_changed.connect(_refresh_ai_response_delay_text)
```

标签文本 + 无信号回写（`:734–743`）：
```gdscript
func _refresh_ai_response_delay_text(delay_seconds: float) -> void:
	if not is_node_ready():
		return
	_ai_response_delay_slider.set_value_no_signal(delay_seconds)
	_ai_response_delay_label.text = "AI响应速度：%.2f秒" % delay_seconds

func _on_ai_response_delay_changed(delay_seconds: float) -> void:
	GameSettings.set_ai_response_delay_seconds(delay_seconds)
```
**`set_value_no_signal()` 是全局惯例**（`match_menu.gd:231` / `:233` / `:269` / `:603` / `:737` / `:750`），用来切断「信号回写 → 又触发信号」的循环。

滑条主题（`main_menu.gd:1824–1835`；**局内菜单自己没有 `_apply_slider_style`**——它只刷新了两个 Label 的颜色，见 `match_menu.gd:417–418`。所以滑条样式应照抄 `main_menu.gd` 这份）：
```gdscript
func _apply_slider_style(slider: HSlider) -> void:
	# 未选择区域轨道；低对比度细边保持滑条在两套深色主题中都清晰可见。
	var track_style: StyleBoxFlat = _make_flat_inner_panel(BattleUIStyle.get_color("disabled_button"), BattleUIStyle.get_color("disabled_button_border"), 1, 4)
	track_style.content_margin_top = 3.0
	track_style.content_margin_bottom = 3.0
	# 已选择区域轨道；主题强调色半透明填充用于表达当前数值，不引入固定配色。
	var filled_style: StyleBoxFlat = _make_flat_inner_panel(Color(BattleUIStyle.get_color("accent"), 0.72), BattleUIStyle.get_color("accent"), 1, 4)
	filled_style.content_margin_top = 3.0
	filled_style.content_margin_bottom = 3.0
	slider.add_theme_stylebox_override("slider", track_style)
	slider.add_theme_stylebox_override("grabber_area", filled_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled_style)
```

### SpinBox 形态

`HBoxContainer` 行：标签 + SpinBox —— `main.tscn:579–595`：
```
[node name="PlayerCountRow" type="HBoxContainer" parent="MatchMenu/MenuPanel/MenuVBox" unique_id=1045087042]
layout_mode = 2
theme_override_constants/separation = 10
...
[node name="NextPlayerCountInput" type="SpinBox" parent="MatchMenu/MenuPanel/MenuVBox/PlayerCountRow" unique_id=2052189361]
unique_name_in_owner = true
custom_minimum_size = Vector2(90, 30)
layout_mode = 2
min_value = 2.0
max_value = 10.0
value = 8.0
```

SpinBox 主题（`match_menu.gd:458–470`，**局内菜单版本**——focus 态用 `panel`/`accent`）：
```gdscript
func _apply_spin_box_style(spin_box: SpinBox) -> void:
	if spin_box == null:
		return
	var line_edit: LineEdit = spin_box.get_line_edit()
	line_edit.add_theme_font_override("font", ThemeDB.fallback_font)
	line_edit.add_theme_stylebox_override("normal", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("border"), false))
	line_edit.add_theme_stylebox_override("focus", BattleUIStyle.make_decade_button(BattleUIStyle.get_color("panel"), BattleUIStyle.get_color("accent"), true))
	line_edit.add_theme_color_override("font_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_selected_color", BattleUIStyle.get_color("text_primary"))
	line_edit.add_theme_color_override("font_uneditable_color", BattleUIStyle.get_color("text_secondary"))
	line_edit.add_theme_color_override("caret_color", BattleUIStyle.get_color("accent"))
	line_edit.add_theme_color_override("selection_color", Color(BattleUIStyle.get_color("accent"), 0.42))
```
（`main_menu.gd:1839–1850` 是同一函数，唯一差异：focus 态用 `action_button`/`accent`。`online_lobby_panel.gd:672` 与 `lan_lobby_panel.gd:275` 也各有一份。**惯例是每个面板持私有副本**。）

### ⚠️ 两个必须知道的 SpinBox 陷阱（项目已踩过并写进注释）

1. `match_menu.gd:263–273` `_apply_player_count_value()`：**`SpinBox` 的静默写入不会刷新内部 `LineEdit` 文本** —— 程序化写值后必须手动对齐文本：
```gdscript
	var count_line_edit: LineEdit = _player_count_input.get_line_edit()
	if int(_player_count_input.value) != player_count:
		_player_count_input.set_value_no_signal(float(player_count))
	var expected_text: String = str(player_count)
	if count_line_edit != null and count_line_edit.text != expected_text:
		count_line_edit.set_text(expected_text)
```
2. `match_menu.gd:176`：`_player_count_input.update_on_text_changed = true` —— 让键入即时同步 `Range` 值，避免「输入后立刻点按钮仍读到旧值」。

### 对「滑条(1–10) + 无上限输入框」的建议

- **滑条(1–10)**：照抄 `AiResponseDelayRow`（`VBoxContainer` + `Label` + `HSlider`，`min_value = 1`、`max_value = 10`、`step = 1`），Label 用 `_refresh_xxx_text()` 更新文案。
- **无上限输入框**：项目里**没有**无界数值控件；`SpinBox` 必须有 `min_value` / `max_value`。最接近「无界/手输数值」的既有范式是 **`LineEdit` + `.text.to_int()` 优先**（`lan_lobby_panel.gd:157–163`）：
```gdscript
## 返回输入框当前端口；编辑中的文本优先，非法或空文本回退 SpinBox 已确认值。
func get_port() -> int:
	# 当前手动输入端口；0不属于允许范围，可作为空文本与非法文本回退标记。
	var typed_port: int = _port_input.get_line_edit().text.to_int()
	# 最终候选端口；空文本或非法文本回退 SpinBox 当前数值，返回前统一限制合法范围。
	var resolved_port: int = int(_port_input.value) if typed_port == 0 else typed_port
	return clampi(resolved_port, MINIMUM_PORT, MAXIMUM_PORT)
```
另见 `match_menu.gd:290–300` `get_next_player_count()`（同样的「文本优先 + 回退控件值 + clamp」三段式，注释 `:288–289` 解释了原因）。
→ 建议：滑条用 `HSlider`；输入框用 **`LineEdit`**（用 `_apply_line_edit_style()` 上色，`all_cards_panel.gd:920`）而不是 `SpinBox`，然后仿 `get_port()` 写一个 `get_xxx() -> int` 做「文本优先、回退滑条值、不 clamp 上限（或只 clamp 下限）」。若坚持用 `SpinBox`，把 `max_value` 设成一个很大的哨兵（如 `999999`）并同样写 `get_xxx()` 文本优先读取。

---

## 9. 交付前必须一起处理的 5 件事（否则会破坏既有契约）

1. **文档同步（AGENTS.md 强制）**：`docs/界面与交互.md` 需更新
   - `:204` 的图层表（新增层级，按「落在既有层级之间」的规则）；
   - `:257`「## 局内菜单」小节（新增「开发者设置」入口、仅离线可见、打开控制台）；
   - 若涉及玩法数值（1–10 的滑条、无上限输入的含义），还要同步《游戏机制与玩法内容》文档。
2. **`tests/` 里的硬编码路径**：多个测试直接按路径取菜单节点，例如 `tests/main_menu_test.gd:194` `main_instance.get_node("MatchMenu/MenuPanel/MenuVBox/WheelDuelFaceUpCandidateRow/WheelDuelFaceUpCandidateLabel")`、`:340` `.../CharacterReplacementCountRow`、`tests/wheel_duel_mode_test.gd:138`、`tests/pre_game_customization_test.gd:148`（`%MenuPanel`）、`tests/doudizhu_mode_test.gd:408`（`%MenuPanel`）。**在 VBox 末尾/按钮区插入新按钮不会破坏这些路径**（它们按名字取，不按索引），但若加在设置行中间则要重新核对 `ui_layout_test.gd:1878–1983` 的几何断言。
3. **`ui_layout_test.gd` 的层级断言**：`animation_layer.z_index != 30`（`:1088`）、`log_panel.z_index <= 30`（`:1940`）、`animation_layer.z_index + continuity_batch_view.z_index >= AhhaMomentCutscene.CUTSCENE_Z_INDEX`（`:1493`）。新模态只要 `z_index >= 500` 就不会碰到这些，但若 `> 620` 会与回放覆盖层冲突。
4. **`_move_to_input_front()`（`match_menu.gd:255–259`）**：只把 `_menu_panel` 和 `_menu_button` 提到最前。新按钮加在 `MenuVBox` 内会随面板一起被 `move_to_front()` 带上去，无需改；若做成 `MatchMenu` 的兄弟节点则必须在此处也 `move_to_front()`。
5. **焦点管理**：`set_menu_open()`（`:309–317`）与 `set_authority_controls_visible()`（`:345–348`）都有一段长 `if` 显式处理「焦点落在刚隐藏的控件上时转交 `_main_menu_button`」。新按钮隐藏时必须 `release_focus()`（照 `set_offline_controls_visible` `:361–362` 与 `set_auto_identity_marking_visible` `:326–329` 的写法）。

---

## 10. 最省事的最小实现路径（推荐）

1. `scenes/main.tscn`：在 `MenuReturnToMainButton` 前插入 `MenuDeveloperSettingsButton`（`visible = false`、`custom_minimum_size = Vector2(0, 32)`、`text = "开发者设置"`、`unique_name_in_owner = true`、新 `unique_id`）。
2. `scripts/ui/match_menu.gd`：加 signal `developer_settings_requested`、`@onready var _developer_settings_button: Button = %MenuDeveloperSettingsButton`、`_ready()` 里 `.pressed.connect(_request_developer_settings)`、`refresh_ui_style()` 里 `apply_interaction_button(..., panel, border, false)`、显隐 setter 里加两行显隐+释放焦点、加 `_request_developer_settings()`（关菜单 + emit）。
3. 新建 `scripts/ui/developer_console_panel.gd`（`class_name DeveloperConsolePanel extends Control`），照 `card_selection_panel.gd:156–213` 的 `_ready()` 全代码建 UI（全屏 `_shade` ColorRect `MOUSE_FILTER_STOP` + 居中 `_frame` PanelContainer `make_inset_panel` + VBox 内容 + 底部按钮行），`z_index` 取 520，实现 `open_console()` / `close()` / `refresh_ui_style()` / `_unhandled_input`（Esc → `close_requested.emit()`）。
4. `scripts/ui/match_table.gd`：顶部 `const DEVELOPER_CONSOLE_PANEL_SCENE: PackedScene = preload(...)`（或直接 `DeveloperConsolePanel.new()`），加 `_create_developer_console_panel()`（`name = "DeveloperConsolePanel"`，`add_child(self)`，接 `close_requested`），在 `_ready()` 的 635–639 区块接 `match_menu.developer_settings_requested.connect(_on_developer_settings_requested)`，在 `refresh_ui_style()`（3637 附近）调 `refresh_ui_style()`。
5. 同步文档 + 追加 `临时反馈文档.md`（AGENTS.md 规范三/四/五）。
