# 实施计划：重构记录牌名的表现形式

> 前置：`design.md` 的契约已定；本文件只安排**执行顺序、验证命令与复核门**。
> 全程遵守：Tab 缩进；每个变量独占一行注释；不修改任何既有注释与变量名；技能 `description` 原文不动。

## 0. 硬性前置认知（开工前读一遍）

| 事实 | 出处 | 为什么要记住 |
|---|---|---|
| `InputArea` 的 `z_index = 30` | `player_target_view.tscn:451` | 新按钮容器必须 `> 30`，否则点击被吞 |
| `_card_views[card_uid]` 以 UID 为键 | `card_selection_panel.gd:698` | 无 UID 候选会塌缩到 `-1` 互相覆盖 |
| `configure()` 有配置签名 `hash([...])` | `card_view.gd:223` | 新参数不入签名会导致复用实例保留旧花色点数 |
| `_is_inline_hand_choice()` 空候选返回 `true` | `match_table.gd:3676-3687` | `card_name` 不排除就进不了面板 |
| `_validate_selected_candidates` 只认 `card_ids`/`control_ids` | `choice_request.gd:322-331` | 提交值必须在权威白名单内 |
| `character_corner_text` 被 AI 与 5+ 测试断言 | `noname_ai_evaluator.gd:381` 等 | 生成规则**一个字都不能变** |
| 测试须 grep `_PASS` 行 | 项目既有约定 | `--quit-after` 会让中止的测试也退出 0 |

**统一验证命令**（下称「跑单个测试」）：

```powershell
$gd = 'E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe'
$out = & $gd --headless --path . res://tests/<名字>.tscn --quit-after 6000 2>&1
$out | Select-String -Pattern '_PASS|_FAIL|Parse Error|SCRIPT ERROR'
```

---

## U1 核心层：角标条目支持中性「按钮」标记

**改动**
- `scripts/core/match_controller.gd`
  - `set_character_corner_text_entry()` 增加可选形参 `view_kind: String = ""`，写入条目字典。
  - `_refresh_character_corner_text()` 增加一行跳过：`view_kind` 非空的条目**不参与** `text_lines` 合成。
- `scripts/data/player_state.gd`：**预期无需改动**（`character_corner_text_entries` 已是 `Dictionary` 且以 `duplicate(true)` 全量透传）。开工时先确认 `from_authoritative_dict` / `to_dict` 未做字段白名单裁剪。

**复核门**
- [ ] 5 个既有调用点（`mingding` / `zhuijian` / `anke` / `zhufeng` / `reincarnation_skill_service`）全部未传新参数。
- [ ] `character_corner_text` 的取值与改动前**逐字节一致**。

**验证**
- 跑单个测试：`omphalos_transform_test`（断言 `character_corner_text == "永劫"`）
- 跑单个测试：`new_character_mechanics_test`（断言「酩酊」「逐风 1」「安可：♠♥♣♦」「追歼\n安可：♠」等多条合并结果）
- 跑单个测试：`reincarnation_mechanics_test`

---

## U2 内容层：【解构】声明按钮条目

**改动**
- `game_data/skills/jiegou.gd`
  - 新增常量：`CORNER_BUTTON_ENTRY_ID`、`CORNER_BUTTON_ORDER`（`60`，排在 50 类状态提示之后、100 类数值提示之前）、`CORNER_BUTTON_VIEW_KIND = "recorded_card_names"`。
  - 在**首次记录后**写入按钮条目（幂等：已存在则直接返回）；条目常驻，记录清空时**不移除**。
  - 不处理技能卸载：基类没有 load/unload 钩子，且「是否显示」由表现层按公开记录是否为空决定，见 design.md §6。

**复核门**
- [ ] 按钮条目写入是**幂等**的，只在首次记录时生效，不在每次记录变化时重复写（避免无谓状态广播）。
- [ ] 沿用 `host.has_method(...)` 的既有防御写法。
- [ ] 未出现 UI 节点、未出现 `view_kind` 取值判断。

**验证**
- 跑单个测试：`daheita_mechanics_test`（本单元先只加「记录后 entries 含按钮条目 / 清空后条目仍在、由表现层隐藏」的断言）

---

## U3 表现层：角标区多元素容器与按钮组件

**改动**
- 新增 `scripts/ui/character_corner_action_badge.gd` + `scenes/components/character_corner_action_badge.tscn`
  - `extends Button`，信号 `action_pressed(entry_id, view_kind)`。
  - 视觉规格对齐 `character_corner_text_badge.tscn`（深褐 `(0.18,0.105,0.065,0.94)`、圆角 3、内边距 4/2、字号 10、白字 2 像素黑描边）。
  - `mouse_filter = STOP`。
- `scenes/components/player_target_view.tscn`
  - 移除单个 `CharacterCornerTextBadge` 实例，新增 `CharacterCornerStack`（`VBoxContainer`，`position (26,20)`，**`z_index = 31`**）。
- `scripts/ui/player_target_view.gd`
  - 删除 `_corner_text_badge` 的 `@onready` 与 `set_display_text` 调用，改为按 `character_corner_text_entries` 动态构建子项。
  - 排序：`order` 升序 → `entry_id` 字典序；文本条目按 `text` 去重；按钮条目不去重。
  - 按「条目结构签名」跳过重建（与 `decade_hand_container` 的既有做法一致）。
  - 新增信号 `corner_action_pressed(player_id, entry_id, view_kind)`。
  - `visual_data`（`:435-458`）需纳入按钮相关字段，否则记录变化不触发重绘。
- `scripts/ui/battle_ui_style.gd` / `ui_style_registry.gd`：按需补充按钮态样式读取入口（**不得新增主题专属颜色常量**）。

**复核门**
- [ ] `CharacterCornerStack.z_index` > `InputArea` 的 `30`。
- [ ] 按钮 `mouse_filter = STOP`；容器自身 `IGNORE`。
- [ ] 全项目无残留 `_corner_text_badge` 引用。
- [ ] 颜色全部经 `BattleUIStyle` 读取。
- [ ] 空闲不注册 `_process`。

**验证**
- 跑单个测试：`ui_layout_test`（1152×648）
- 跑单个测试：`font_color_audit_test`（新增 `Label` 必须带字体色覆盖）
- 跑单个测试：`new_character_mechanics_test`（回归文本角标断言——本次改的是表现层，规则断言应全部不受影响）

---

## U4 表现层：`CardView` 支持隐藏花色点数

**改动** `scripts/ui/card_view.gd`
1. `configure()` 增加可选形参 `hide_suit_rank: bool = false`，缓存到 `_hide_suit_rank`。
2. **把新参数并入 `:223` 的配置签名 `hash([...])`**（漏掉会导致复用实例保留旧花色点数，且不报错）。
3. `_refresh_card_content()`：`_corner_label.visible = not _hide_suit_rank`。
4. 悬停副标题（`:598`）跳过花色点数。
5. 红色花色判定（`:444`）在隐藏时回退普通牌色。

**复核门**
- [ ] 默认 `false` 时，牌面渲染与改动前完全一致。
- [ ] 新参数**在签名内**。
- [ ] 未删除 `_suit_rank_text` 的既有计算（保留供配色判断）。

**验证**
- 全量回归（牌面渲染影响面最大，必须整轮跑）：
```powershell
$files = Get-ChildItem 'tests\*.tscn' | Sort-Object Name
$ok = 0; $fail = @()
foreach ($f in $files) {
  $out = & $gd --headless --path . "res://tests/$($f.Name)" --quit-after 6000 2>&1
  if (($out | Select-String -Pattern '_PASS').Count -gt 0) { $ok++ } else { $fail += $f.BaseName }
}
Write-Output "TOTAL=$($files.Count) OK=$ok FAILED=$($fail.Count)"
```
- 期望：`TOTAL=65 OK=64 FAILED=1`（仅 `android_adaptation_test`）

---

## U5 表现层：面板牌名候选模式

**改动**
- `scripts/ui/card_selection_panel.gd`
  - `show_request()`（`:238`）在 `arrange`（`:254`）与 `control`（`:259`）之间插入 `card_name` 分支。
  - 新增 `_show_name_candidate_request()`：从 `name_candidates` 构造候选，复用既有牌位渲染；每项分配**唯一负整数伪 UID**。
  - 新增状态字段 `_name_candidates`（伪 UID → definition_id 反查表），`close()` 时清空。
  - `_on_card_pressed()`（`:733`）与提交路径加 `card_name` 分支：把伪 UID 转回 `definition_id`，经 `control_submitted` 提交。
- `scripts/ui/match_table.gd`
  - `_is_inline_hand_choice()`（`:3678`）排除列表加入 `"card_name"`。
  - 确认 `_is_inline_control_choice()` 不误判（新类型非 `control`）。

**复核门（重点）**
- [ ] **伪 UID 绝不逃出面板**：不进入 `PlayerAction`、`ChoiceResponse`、`selected_card_uids`。
- [ ] 每个牌名候选的伪 UID **唯一**（否则 `_card_views` 互相覆盖）。
- [ ] 提交值是 `definition_id`，且能被 `choice_request.gd` 的 `control_ids` 校验通过。
- [ ] 面板关闭后反查表已清空。

**验证**
- 跑单个测试：`daheita_mechanics_test`（【灵感】两段选牌名走新通道）

---

## U6 表现层：记录牌名只读查看界面

**改动**
- `scripts/ui/card_selection_panel.gd`：新增只读入口 `show_recorded_names(view_data)`，复用 4 列牌阵渲染，`hide_suit_rank = true`，无确定/取消。
- `scripts/ui/match_table.gd`：连接 `corner_action_pressed`，按 `view_kind` 映射到只读界面；数据取当前快照的 `recorded_card_names`，显示名经 `GameSettings.resolve_card_name`。
- `scripts/ui/player_target_view.gd`：只读窗口打开期间不改变武将牌的目标可选态。

**复核门**
- [ ] 打开/关闭**不产生任何规则动作**，不进入 `EventScheduler` 请求命名空间。
- [ ] 任何角色（含非持有者）都能打开，结果一致。
- [ ] 显示名走 `resolve_card_name`，**不写回记录**。
- [ ] 无确定/取消按钮，牌面不可选中。

**验证**
- 跑单个测试：`daheita_mechanics_test`（新增 AC5 断言：打开关闭前后权威状态不变）

---

## U7 内容层 + 技能基类：【灵感】改用牌名候选

**改动**
- `game_data/skill_definition.gd`：新增端口 `request_card_name_selection(title, prompt, definition_ids, allow_cancel, context)`，内部下发 `choice_type = "card_name"` + `name_candidates`。
- `game_data/skills/linggan.gd`：`CHOICE_PICK_EFFECT` 与 `CHOICE_PICK_TARGET_MODE` 两处由 `request_control_selection_for_player(...)` 改为新端口。

**复核门（不得回退，逐条对照）**
- [ ] 取消任一步骤：不消耗出牌阶段次数、不移除记录、仍可重新发动。
- [ ] `can_activate()` 在存在待处理选择时返回 `false`。
- [ ] 次数只在 `execute_cardless_virtual_card_use` 返回 `true` 后自增。
- [ ] `all_others` / `all_players` / `self` / `self_wounded` 仍由整牌逻辑展开。
- [ ] 记录中只有一张牌名时仍跳过重定向询问。
- [ ] 无懈可击仍不出现在候选中。

**验证**
- 跑单个测试：`daheita_mechanics_test`（全部子测试，含取消语义与目标模式用例）

---

## U8 测试补全、文档同步与提交

**测试补全**（`tests/daheita_mechanics_test.gd`）
- [ ] 记录非空→按钮条目存在；记录清空→按钮条目消失。
- [ ] 同一武将牌上「文本角标 + 按钮」共存时，两者都在 `character_corner_text_entries` 中且 `order` 排序正确。
- [ ] `character_corner_text` 不包含按钮文本（证明未参与合成）。
- [ ] 只读界面打开关闭后权威状态不变。
- [ ] 通过行扩展新标记。

**文档同步**（项目规范二）
- [ ] `docs/界面与交互.md`：角标区多元素容器、按钮交互、只读查看界面、牌名候选选择界面、`CardView` 隐藏花色点数。
- [ ] `docs/游戏机制与玩法内容.md`：记录牌名的表现与查看方式（不涉及数值时也需说明机制变更）。
- [ ] `docs/架构说明.md`：`character_corner_text_entries` 的 `view_kind` 扩展；`context.card_name_candidates` 呈现开关与伪 UID 边界。
- [ ] `docs/AI模块.md`：确认 AI 侧读取 `character_corner_text_entries` 的行为未受影响（`:381`）。
- [ ] `docs/内容制作指南.md`：技能声明角标按钮的写法。

**全量回归**
- [ ] `TOTAL=65 OK=64 FAILED=1`（仅 `android_adaptation_test`）
- [ ] `git checkout -- scenes/main.tscn`（headless 跑测会重写该文件，提交前必须还原）

**提交拆分**（每条单行、动词开头）
1. 新增角标条目的中性查看类型字段
2. 调整控制器角标端口写入查看类型
3. 新增【解构】记录按钮条目的声明与清理
4. 新增武将牌角标区的多元素容器
5. 新增角标按钮组件
6. 新增卡牌视图隐藏花色点数能力
7. 新增卡选择面板的牌名候选模式
8. 新增记录牌名的只读查看界面
9. 新增技能牌名选择端口并改造【灵感】选牌
10. 新增记录牌名表现的回归用例
11. 补充界面与交互文档中角标按钮与查看界面
12. 补充架构说明中查看类型与牌名候选通道
13. 补充内容制作指南中角标按钮声明写法

---

## AC 覆盖映射

| AC | 覆盖单元 |
|---|---|
| AC1 按钮出现/消失 | U2 + U3 + U8 |
| AC2 角标与按钮共存 | U3 + U8 |
| AC3 查看界面隐藏花色点数 | U4 + U6 |
| AC4 只读、任意角色可开 | U6 |
| AC5 不改权威状态 | U6 + U8 |
| AC6 两段选牌名走卡片界面 | U5 + U7 |
| AC7 取消语义不回退 | U7 |
| AC8 全体/自指模式展开正确 | U7 |
| AC9 既有角标不回退 | U1 验证 + U4 全量回归 |
| AC10 `daheita_mechanics_test` 通过 | U8 |
| AC11 字体色与布局测试通过 | U3 验证 + U8 |
| AC12 文档同步 | U8 |

## 回滚点

每个单元都是**独立可退**的（见 `design.md` §8）。若 U5/U6 的面板改造出现问题，可只回退 U5–U7，让【灵感】退回文字按钮选择，而 U1–U4 的按钮与查看界面仍然可用——两者之间只通过 `view_kind` 字符串和 `card_name` 类型解耦，没有共享可变状态。
