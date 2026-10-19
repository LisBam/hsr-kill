# 调研 02 · 定制弹窗（技能专用窗口）的实现范式

调研范围：项目里「技能自建弹窗」的完整做法 —— 场景结构、层级、暂停语义、样式契约、输入控件、与选择请求的对接方式。
目标：为 `yinlang_windows`（注入组合窗口 + 以太造牌窗口）提供可直接照抄的模板。

---

## 1. 层级（z_index）是规范性约束

`docs/界面与交互.md:206` 的层级表（**规范性**，新增窗口必须插表并补测试）：

| 层 | 内容 |
|---|---|
| 0 | 牌桌 / 手牌 |
| 5 | 托管滤镜（`match_table.gd:85 AUTO_MANAGED_HAND_OVERLAY_Z_INDEX`） |
| 6 | 本地技能栏（`match_table.gd:88 LOCAL_SKILL_BAR_Z_INDEX`） |
| 30 | 飞牌动画 |
| 31 | 技能发动名 |
| 34 | 技能发动（`match_table.gd:76 SKILL_ACTIVATION_Z_INDEX`） |
| 35 | 记录面板 |
| 38 | 聊天气泡（`match_table.gd:79 CHAT_BUBBLE_Z_INDEX`） |
| 40 | 选将遮罩 |
| 45 | 局内聊天 |
| 100 | 信息框 |
| 120 | 阿哈时刻 |
| 150 | 卡牌选择（`card_selection_panel.gd:31 MODAL_Z_INDEX`） |
| 180 | 机缘选择（`opportunity_choice_panel.gd:19 MODAL_Z_INDEX`） |
| **185** | **`yinlang_windows`（本任务新增，位于 180 与 220 之间）** |
| 220 | 结算（`game_settlement_panel.gd`） |
| 500 | 局内菜单 |
| 520 | 开发者菜单 |
| 620 | 回放重演 |

`tests/ui_layout_test.gd` 现有层级断言：`:249-250`（装备面板 150×148）、`:396-397`（托管滤镜 < 技能栏）、`:1088-1089`（`animation_layer.z_index != 30`）、`:1493-1494`（批量飞牌 vs `AhhaMomentCutscene.CUTSCENE_Z_INDEX`）、`:1940-1941`（记录面板 > 30）、`:2005-2007`（层级带上界）。**目前没有对 150/180/220 的数值断言** → 本任务补 `185` 的断言。

## 2. 场景骨架

模板 `scenes/components/opportunity_choice_panel.tscn`（复制它改名为 `scenes/components/yinlang_windows_layer.tscn`）：

```
YinlangWindowsLayer (Control, 全屏 anchor, visible=false, process_mode=PROCESS_MODE_ALWAYS)
├── Shade (ColorRect, 全屏, mouse_filter=MOUSE_FILTER_STOP)
└── Frame (PanelContainer, anchor_preset=PRESET_CENTER)
    └── ...（两栏 / 四行内容）
```

## 3. 弹窗脚本的四条硬约束

1. **`process_mode = PROCESS_MODE_ALWAYS`** —— 项目在弹窗期间暂停牌桌处理（`docs/界面与交互.md:320`）；不设该值则弹窗自身也停止响应。
2. **`z_index` 在 `_ready()` 里设置**（场景文件里设会被父节点覆盖）。
3. **`Shade` 必须 `MOUSE_FILTER_STOP`** —— 否则点击穿透到底层牌桌。
4. **`refresh_ui_style()` 是项目级契约** —— 所有颜色必须经 `BattleUIStyle` / `UIStyleRegistry`；`match_table._on_ui_style_changed`（`match_table.gd:645` 挂接）会重新调用它。

参考实现：`scripts/ui/opportunity_choice_panel.gd`（`MODAL_Z_INDEX = 180:19`、`_ready():38-43`、`refresh_ui_style():47-59`）。

## 4. 样式系统（**高科技黑蓝当前不可表达**）

- 颜色只允许经 `scripts/ui/battle_ui_style.gd`（`UNSET_COLOR:8`、`_active_style_id:66`、`set_active_style():70`、`get_color(key, fallback):80`、`is_monochrome():85`、`make_panel():91`、`make_button():137`、`make_inset_panel():147`、`make_decade_button():167`、`apply_interaction_button():186`）与 `scripts/ui/ui_style_registry.gd`（`STYLE_SPACE_MONO:8`、`STYLE_DECADE_WOOD:12`、`STYLE_PREMIUM_BLACK_GOLD:15`、`DEFAULT_STYLE_ID:19`、`STYLE_ORDER:22`、`STYLE_DISPLAY_NAMES:25`、`STYLE_PALETTES:32-360`、`get_value():381`、`get_color():390`、`is_monochrome():397`）。
- **三套调色板全部是金/铜色系** → **「高科技黑蓝」今天无法表达**，必须为三套调色板各新增语义键：`tech_panel`、`tech_border`、`tech_accent`、`tech_grid`。
- `tests/font_color_audit_test.gd:50-62` 要求每个 `Label` / `CheckBox` 都有 `font_color` 覆盖；`RichTextLabel` 用 `default_color`。
- **项目内没有字体资源**（只有 `ThemeDB.fallback_font`）→ `LineEdit` 必须显式 `add_theme_font_override("font", ThemeDB.fallback_font)`。
- 字号阶梯：28 / 26 / 24 / 22 / 18 / 17 / 16 / 14 / 13 / 12。
- 节点命名 PascalCase；需要 `%Name` 访问时设 `unique_name_in_owner`。

## 5. 自由文本输入的既有先例

`scripts/ui/game_settlement_panel.gd:185-246 _build_naming_modal()` —— **项目里唯一用 `LineEdit` 收自由文本的弹窗**（Esc 取消在 `:250-255`）。以太造牌窗口的牌名输入照抄它的控件与样式处理。

`scripts/ui/all_cards_panel.gd:921-926` 是 `LineEdit` 样式处理的另一处参考。

## 6. 技能窗口与选择请求的对接

项目里「技能自建弹窗」的统一形状是**不直接操作界面，而是发一个选择请求，由 `match_table` 把请求路由到对应面板**：

1. 技能侧：`request_control_selection(title, prompt, options, allow_cancel, context, card_name_view)`（`game_data/skill_definition.gd:992-1014`）。
2. 控制器侧：`request_card_choice()`（`match_controller.gd:3095`）→ `_publish_card_choice_request()`（`:3331-3347`）→ UI 收到 `card_choice_requested`。
3. UI 侧路由：`match_table._on_card_choice_requested()`（`:4080-4131`）判断请求类型 → 打开对应面板；提交走 `_on_card_choice_submitted()`（`:4135-4143`）/ `_on_control_choice_submitted()`（`:4213-4220`）。
4. 判定是否内联：`_is_inline_control_choice()`（`:4397`）、`_is_inline_hand_choice()`（`:4366`）、`_is_inline_zhenqi_cost_choice()`（`:4386`）。
5. 内联提交：`_submit_inline_control_choice()`（`:6175-6202`，`:6185` 构造响应、`:6193` 构造 payload）。

**因此 `yinlang_windows` 的接入方式**：在 `_is_inline_control_choice()` 对带 `context["yinlang_window"]` 的请求返回 `false`，并在 `_refresh_card_selection_panel()`（`:4224`）里分流到新窗口层。

## 7. 选择协议（必须扩协议，不能用既有通道）

- `ChoiceRequest`（`scripts/data/choice_request.gd`）：`choice_type:25`、`control_ids:40`、`base_context:82` / `active_context:85`（任意字典，**这是传递池数据与唯一性名单的合法通道**）。
- `ChoiceResponse`（`scripts/data/choice_response.gd`）：`control_id:28` 是**唯一的字符串通道**，没有自由文本字段。
- 权威校验 `choice_request.gd:178 validate_response()`，其中 `:215-216`：

```gdscript
if not response.control_id.is_empty() and not control_ids.has(response.control_id):
	return "选择结果包含无效候选。"
```

`validate_response` 只被 `scripts/core/event_scheduler.gd:550`（`submit_choice`）、`:583`（`timeout_choice`）与 `tests/event_runtime_test.gd:75,81` 调用（文档 `docs/内容制作指南.md:1398`）。

- 控制器侧还有第二道校验：`match_controller.gd:3917`

```gdscript
if not selected_control_id.is_empty() and (choice_type not in ["control","bool","target_control","arrange",CARD_POSITION_CHOICE_TYPE] or not candidate_control_ids.has(selected_control_id)):
	return _reject("选择中包含无效文字选项。")
```

### 结论：必须扩协议

注入的组合空间是 23 × 24 = 552 种（不可枚举）；以太的牌名是**自由文本**（不可枚举）。两者都塞不进 `control_ids` 白名单。方案（见 `../10-19-yinlang-character-and-windows/design.md` R7）：

- 新增两个 `choice_type`：`yinlang_compose`（`control_id = "yinlang|compose|<时机键>|<效果键>"`）、`yinlang_mint`（`control_id = "yinlang|mint|<牌名>|<花色>|<点数>|<被复制牌定义ID>"`）。
- `ChoiceRequest` 新增请求级开关 `allow_free_control_id: bool = false`（含 `to_dict`/`from_dict`）→ `choice_request.gd:215` 仅对该开关跳过 `control_ids.has()` 白名单，**并**要求已确认时 `control_id` 非空。**刻意不做「按 choice_type 硬编码豁免名单」**，避免新类型静默绕过校验。
- `match_controller.gd:3917` 的自由控制项集合加入两个新类型；`:3937`/`:3944` 旁新增结构校验分支。
- `_build_card_choice_actions()`（`:3571`）新增分支：自由控制项类型按 `context["ai_candidate_control_ids"]` 生成确认动作（去重、限长 8）。**否则 AI 侧枚举为空**（`:3197-3207` 的自检会强制取消或 `_reject`）。
- **不给 `ChoiceResponse` 加字段。**

## 8. AI 枚举与自检的硬约束

- `_build_card_choice_actions(choice_request) -> Array[Dictionary]`（`:3571`）是 AI 候选枚举唯一入口，按 `choice_type` 分支：`allow_cancel` `:3599-3602`、`arrange` `:3603-3616`、`target_control` `:3617-3634`、`control`/`bool` `:3635-3644`、`CARD_POSITION_CHOICE_TYPE` `:3645-3658`（`:3647-3648` 注释解释了空枚举被拒的机制）、`respond` `:3659-3671`、零材料确认 `:3672-3674`。调用方：`:3199`、`:3282`、`:3466`、`:3493`、`:3522`、`:6151`。
- 自检 `:3197-3207`：枚举为空时，`allow_cancel` → 强制取消并继续；否则 `_pending_card_choice.clear()` + `_reject("选择请求没有合法结果，已跳过以避免流程停滞：%s。")`。
- AI 响应构造：`scripts/ai/ai_coordinator.gd:68-69` `response.control_id = str(payload.get("selected_control_id", ""))`。
- 技能侧 AI 钩子：`score_ai_choice(authoritative_snapshot, choice_request, action, evaluator) -> float`（`skill_definition.gd:841`），按 `context.kind` 判别。范式 `gongku.gd:65-89`（`:82` 读 `payload.get("selected_control_id", payload.get("control_id",""))`）。
- **`ai_prefer_control_id`** 是既有约定键，仅出现在 `game_data/skills/gongku.gd:42` 与 `guangfu.gd:135`。

## 9. 参考实现（可直接照抄的控制项选择技能）

`game_data/skills/gongku.gd`（96 行）—— 完整模板：

```gdscript
func _init() -> void:      # :7-14  元数据
func install() -> void:    # :18-19 subscribe_timing("dieAfter", _on_die_after, "global")
func _on_die_after(event): # :23-42 末尾 request_control_selection("共苦", "...", options, true, {"kind":"gongku_choice", "victim_id":victim_id, "ai_prefer_control_id":_prefer_control_id(owner)})
func continue_selection(context, response) -> bool:  # :46-61 读 response.control_id
func score_ai_choice(authoritative_snapshot, choice_request, action, evaluator) -> float:  # :65-89
func _prefer_control_id(owner) -> String:            # :93-96
```

`scripts/ui/card_selection_panel.gd` 的 `_show_name_candidate_request():926-964`、`_add_control_options():695`、`card_name_candidates:279-283` 是「候选牌名 + 控制项」混合面板的参考。
