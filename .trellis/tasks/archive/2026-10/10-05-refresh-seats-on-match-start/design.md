# 技术设计：开局座位一致性（面板本地座次缓存的跨局残留）

父任务：`10-05-character-selection-timing-and-seat-refresh`
需求见同目录 `prd.md`。

## 一、结论先行

**核心层的「每局刷新座位」并不缺失**，本次不需要在 `MatchController` 里新增「开局刷新所有角色座位」的逻辑。真正的缺口在**选将面板的本地座次缓存跨局残留**，且只有「局内重开」这一条入口会漏清。

因此用户原话「请在每次开始游戏时刷新一下所有角色的座位」的落地含义是：**每次开局都必须把选将面板的座位/身份缓存清掉，并从本局权威快照重新取值**，而不是在核心层重算一遍（核心层已经在重算了）。

## 二、根因（含代码链）

### 2.1 主因链（已确认可达）

1. 局内重开入口：`scripts/ui/match_table.gd:3712-3761 _on_restart_requested()` → `:3747 _reset_presentation_for_new_match()` → `:3749 match_controller.start_match(player_count)`。
2. `_reset_presentation_for_new_match()`（`:3765-3814`，注释自称「普通重开与存档恢复开局共用本入口」）关闭了 `card_selection_panel`（`:3792`）、信息框、播报、动画、时钟、身份标注，**但全文没有 `character_selection_panel.close()`**。对比：返回主菜单路径会关（`:3891`、`:3913-3914`）。
3. 选将面板只在「真正离开选将阶段」时才关：`:1751-1754 if str(_snapshot.get("current_phase","")) not in ["character_selection","wheel_duel_selection"]: character_selection_panel.close()`。局内重开时旧局与新局的阶段都是 `character_selection` → **永不关闭**。
4. `scripts/ui/character_selection_panel.gd:357-397 bind_snapshot()`：

   ```gdscript
   var preserves_local_context: bool = visible \
       and str(_snapshot.get("phase","")) == str(snapshot.get("phase","")) \
       and int(_snapshot.get("target_player_id",-1)) == int(snapshot.get("target_player_id",-1))
   ```

   而核心 `CharacterSelectionService.to_dict()`（`character_selection_service.gd:882-918`）**从不输出 `target_player_id`**（只有 AI 调整与车轮战快照有：`match_controller.gd:18140`），两边取值恒为 `-1`。判据因此退化为「面板原本可见且阶段名字符串相同」——**没有 `match_id` 维度**。
5. 命中 `preserves_local_context` 时，`:367-375` 的复位分支（把 `_selected_seat_number`/`_selected_identity` 重置为本局 `preview_seat_number`/`initial_seat_number`）不执行；唯一的补救分支是 `:376-379 elif phase == PHASE_CUSTOM`。
6. **斗地主 / 2v2 / 过关斩将的首帧阶段就是 `PHASE_OTHERS`**（`character_selection_service.gd:433-436`、`:444`；过关斩将的 `_custom_character_assignment_enabled` 恒为 false，`:1524` 排除），因此这两个模式的 `_selected_seat_number`/`_selected_identity` 在整个对局中**只由本地点击更新，永不被权威快照纠正**。
7. 显示与提交都取这份缓存：
   - 显示：`_get_displayed_seat_number()`（`:470-472`）第一优先返回 `_selected_seat_number`；标题在 `:462`、`:500` 渲染。
   - 提交：`:1386-1387 "seat_number":_selected_seat_number, "identity":_selected_identity`。

**症状**：重开后标题与座次按钮高亮仍是上一局的「N号位 / 身份」，且确认时提交的也是这一对 → 最终落位沿用旧座次（新局随机结果被忽略）。若旧座次在新局已被他人占用，确认还会被拒（`character_selection_service.gd:511-515`「该座次已经被其他玩家选择。」；2v2/斗地主还可能在 `:310-324`、`:286-303` 因绑定表不符直接报「N号位必须选择X身份」）——此时标题显示的是权威拒绝的座次，重选后实际座次与最初显示不符。**完全对应「重开后显示座位与实际座位不相符」。**

### 2.2 间歇性（「有时候」）的四个条件

必须同时满足，缺一即自愈，这正是用户看到「有时候」的原因：

1. `GameSettings.custom_character_assignment_enabled = true`（默认 false，`scripts/autoload/game_settings.gd:371`，持久化到 `user://game_settings.cfg`）。
2. 在**选将阶段**用局内菜单重开（经主菜单返回的路径会 `close()` 面板，不中招）。
3. 新模式与旧模式的首帧阶段字符串相同（斗地主 / 2v2 的 `PHASE_OTHERS`；身份局重开时也落在同一个 `PHASE_LEADER`，见 §2.4）。
4. 旧座次在新局仍然合法（否则退化为「确认被拒」这一更明显的症状）。

> 自选关闭时为什么自愈：`:372` 在非延续分支把 `_selected_seat_number` 置为 `-1`（因为 `allow_custom_assignment` 为 false），于是 `_get_displayed_seat_number()` 落到权威快照字段（`:473-481`）。**这也正是既有测试漏测的原因**，见 §七。

### 2.3 使能缺陷（C2）与次因（C3）

- **C2**：`preserves_local_context` 无法区分「同一局」与「新一局」。快照里明明有 `local_player_id`（`character_selection_service.gd:896`）却没参与判断（注：`local_player_id` 在关闭随机座次时跨局不变，本身不是可靠的对局标识，见 §四的取舍）。
- **C3**（同一模式族，无需重开即可发生）：面板点击即发预览且不等待（`:1277-1281`）；权威侧被拒只发错误信号、不回滚面板本地值（`match_controller.gd:2028-2029`）；确认互斥只查「已确认」表、不查「预览」表（`character_selection_service.gd:511-522`），因此「预览的座次随后被他人确认」是允许的；此时投影会静默丢弃该玩家的预览（`match_controller.gd:11184-11185`），而面板在 `PHASE_OTHERS` 永不回读 → 标题与落位不一致。

### 2.4 对调研结论的一处修正：身份局并非必然自愈

调研认为「身份局因 `PHASE_LEADER → PHASE_CUSTOM` 的阶段变化而 preserves 必失败」。这只在**同一局内阶段推进**时成立。**重开会把阶段打回开头**：旧局停在 `PHASE_LEADER`、新局首帧也是 `PHASE_LEADER` → 阶段字符串相同 → `preserves_local_context` 仍为真 → 残留同样发生。

因此身份局（自选开启 + 在领袖阶段重开）**也属于中招范围**，测试必须覆盖它，不能只覆盖斗地主 / 2v2。

### 2.5 已证伪的候选（记录以免后人重走）

| 候选 | 结论 | 依据 |
|---|---|---|
| 自选座次 + 领袖轮转冲突 | **证伪**。身份局领袖身份全局唯一（`identity_rules.gd:24-35` 每种人数恰 1 个），座次 1 ⇔ 领袖被服务双绑（`character_selection_service.gd:336-351`），投影阶段也显式保住一号位领袖（`match_controller.gd:11191-11207`），故 `:11422 _reorder_players_from_leader()` 在任何投影之后都是幂等 no-op | 5 人斗地主的 2 名地主同理被投影兜底分支强制落在 1/3 号位（`:11218-11245`） |
| 重开入口漏调核心座次刷新 | **证伪**。`start_match()` 每局都执行 `:1510 _assign_local_human_player_seat(actual_player_count)`（`:1847-1850` 用 `_rng.randi_range` 重随机），身份局还会在 `:11422` 按领袖旋转数组 | `docs/游戏机制与玩法内容.md:54` 明确「0至7中独立随机分配本地人类玩家座次」 |
| 初始座次表与最终数组不一致 | **证伪**。两者是同一取模公式：服务 `character_selection_service.gd:426-429` 的 `(player_index - leader_index + n) % n + 1` 与 `match_controller.gd:11745-11750` 的旋转等价 | 已逐项代数验算 |
| 存档恢复漏刷 | **证伪**。`resume_conquest_match()`（`match_table.gd:3833` → `match_controller.gd:15857`）按存档座位恢复（`:15904-15921` 直接 append），**本就不该重刷** | 重刷会破坏存档语义 |

## 三、设计目标与不变量

- **不变量 I1（唯一权威来源）**：选将界面显示的座次与身份，必须来自**本局**的权威快照；面板不得保留跨局的座次/身份值。
- **不变量 I2（无共享脏状态）**：面板的本地选择状态（`_selected_seat_number`、`_selected_identity`、`_selected_character_id`、`_showing_all_characters`、`_snapshot`）在每一局开始时必须回到初始态。
- **不变量 I3（不改变表现层职责边界）**：面板仍然是**被动消费者**——它不做任何座次计算，只在「本局的权威值」与「本局内的乐观本地值」之间切换。修复不得让面板自己去算座次。

## 四、修复点

### 4.1 修复一（主修，落实「每次开局刷新」）：新对局复位面板

在 `scripts/ui/match_table.gd:3765-3814 _reset_presentation_for_new_match()` 中，与 `:3792 card_selection_panel.close()` **并列**补上 `character_selection_panel.close()`。

- **为什么是这个位置**：该函数是普通重开与存档恢复**共用**的唯一表现层复位入口（`:3764` 注释、调用点 `:3747`、`:3833`），语义正是「清空上一局残留的全部本地表现与临时交互状态」。
- **为什么复用 `close()` 而不是新写清理**：`close()`（`character_selection_panel.gd:406-423`）已经清 `_snapshot`、`_selected_character_id`、`_selected_seat_number`、`_selected_identity`、`_showing_all_characters` 并清空候选与座次身份按钮；语义完全吻合，且它已经被主菜单返回路径（`:3891`、`:3914`）与 `ui_layout_test.gd:1059` 使用，是**已被验证的复位端**。
- **不新增变量名、不删除既有注释**：只新增一行调用与说明性注释。
- **空值防护**：与 `:3913` 的写法保持一致，先判 `!= null and is_instance_valid(...)`。

### 4.2 修复二（不变量硬化）：面板的权威回读不再只认单一阶段

`character_selection_panel.gd:365-379` 目前是：

```
if not preserves_local_context:
    ... 从快照复位 ...
elif phase == PHASE_CUSTOM:
    ... 从权威预览回读 ...
```

问题在于「延续上下文时**只有** `PHASE_CUSTOM` 才回读」，使 `PHASE_OTHERS` 的权威值永不被采纳。

**改法**：把「延续上下文时的权威回读」从「仅 `PHASE_CUSTOM`」放宽为「**只要快照携带权威座次/身份字段就回读**」，即把 `elif` 的条件改为按字段存在性判断（`preview_seat_number` / `preview_identity` 存在且 ≥1 / 非空），而不是按阶段名判断。

- **为什么这样能同时消灭 C1 与 C3**：`get_preview_seat_number()`（`character_selection_service.gd:718-721`）的取值链是「已确认 → 预览 → 初始」，本局任意时刻都会返回一个**本局权威值**；因此无论 `preserves_local_context` 是否误判，面板显示的都会是本局权威值。C1 的「沿用上一局」与 C3 的「预览被抢占后不回读」被同一条改动覆盖。
- **为什么不能只靠修复一**：修复一解决「重开」这条入口，但 C3 不需要重开就能发生；且修复二让 `preserves_local_context` 的判据弱点**不再承重**，属于纵深防御。
- **取舍：不加 `match_id`**。把上下文判据改成按对局归属需要快照带对局标识，而 `to_dict()` 是服务层产出、同时服务局域网裁剪与回放路径，新增字段会牵动网络快照契约（需同步 `docs/网络通信.md`）。修复二已经让该判据对座次显示**不再承重**，因此本次**刻意不扩展快照契约**，只在 `design.md` 记录该判据的固有弱点。`local_player_id` 也不作为替代判据（关闭随机座次时它跨局不变）。
- **行为变化提示**：权威预览被拒时，面板现在会**回落到权威值**（此前保留被拒的本地值）。这是修复目标而非回退，但必须写进文档（§八）。

### 4.3 修复三（清掉模式无意义的残留）：自选关闭时无条件置空

`:372` 只在「非延续上下文」分支里做 `allow_custom_assignment == false → -1/""`。若命中延续上下文且模式未开启自选，座次/身份缓存仍是旧值（虽因修复二会被权威值覆盖，但「模式无意义字段应为空」这一不变量应当显式成立）。

**改法**：在 `bind_snapshot()` 开头按 `allow_custom_assignment` 无条件置 `_selected_seat_number = -1` / `_selected_identity = ""`（保留原有分支内的赋值与注释不动，只在其之前补一次显式归零，并在注释中说明「自选关闭时座次身份无意义，任何上下文都不得保留」）。

### 4.4 明确不做的事

- **不在核心层新增「开局刷新所有角色座位」**：§2.5 已证伪其必要性；`start_match()` 每局已经重随机本地座次并旋转数组，座次写入点也已收敛（数组变更仅 `match_controller.gd:9541`、`:11293`、`:11697`、`:11750`、`:15916`）。
- **不改存档恢复的座位**：读档必须保持存档中的座位。
- **不改各模式的座位规则**（PRD R2-5）。
- **不改 `_last_automatic_doudizhu_local_seat_index/_identity`**：其判据与 `_resolve_doudizhu_seat_order` 同源，未见错位，且属 §2.5 已核查范围。

## 五、跨局存活状态核查结果

| 状态 | 位置 | 每局是否重置 | 是否致错 |
|---|---|---|---|
| `local_human_player_id` | `match_controller.gd:278` | 是（`:1510` 每局重随机；`<0` 与局域网映射除外） | 否（本身即刷新机制） |
| `randomize_local_human_seat` | `:281` | 用户设置，跨局保持 | 否（关闭时座次固定属预期） |
| `_last_automatic_doudizhu_local_seat_index/_identity` | `:596`、`:599` | 否（跨局防重复键） | 否（只改「谁当地主」，用重排后座次索引，同源） |
| `character_selection` 的各座位/身份映射 | `character_selection_service.gd:67-110` | 是（每局新建 `:1560` + `begin()` 清空 `:363-370`） | 否 |
| `_custom_character_assignment_enabled` 等开关 | `:1523-1524` | 每局从 `GameSettings` 重读（值本身跨局保持） | 是（C1 前置条件） |
| **面板 `_selected_seat_number` / `_selected_identity`** | `character_selection_panel.gd:215`、`:218` | **否**（仅 `close()` 或非延续分支清） | **是（主因）** |
| **面板 `_selected_character_id` / `_showing_all_characters` / `_snapshot`** | `:366`、`:368-374`、`:389`、`:398` | **否**（同上） | 是（同类残留） |
| `_primary_offline_human_player_id` 等视角状态 | `:437`、`:459`、`:471`、`:477` | 是（`:1513`、`:1529`、`:1569-1573`） | 否 |
| `MatchTable._identity_marks*` | `:3810-3813` | 是（按 `match_id` 归零） | 否（可参照的正确写法） |

## 六、职责划分

| 组件 | 职责 | 本次改动 |
|---|---|---|
| `CharacterSelectionService` | 座次/身份的权威计算与快照产出 | **不动** |
| `MatchController` | 每局重随机本地座次、投射与旋转 | **不动** |
| `MatchTable` | 表现层生命周期：新对局复位 | 修复一（一行调用 + 注释） |
| `CharacterSelectionPanel` | 被动消费快照；本局乐观值与权威值的切换 | 修复二、修复三 |
| `CharacterSelectionService.to_dict()` 契约 | 快照字段 | **刻意不扩展**（§4.2 取舍） |

## 七、测试设计

### 7.1 为什么既有测试漏了这个缺陷（必须记录）

`tests/doudizhu_mode_test.gd:381-440 _test_selection_menu_restart_random_assignment()` **判据完全正确**：用真实 `main.tscn` 连续 8 次点 `%MenuButton` → `%MenuRestartButton`，每次断言 `_selection_title_matches_local_assignment()`（`:457-470`，比对标题「你的座次为N号位 / 你的身份为X」与 `state.players.find(local) + 1`），并断言相邻两局组合不同（`:430-435`）。

**但它在 `:39-41` 把 `GameSettings.set_custom_character_assignment_enabled(false)` 强制关掉后才跑**（调用序早于 `:51`）。自选关闭 ⇒ `allow_custom_assignment = false` ⇒ 面板初值 `-1`（`:372`）⇒ `_get_displayed_seat_number()` 落到权威字段（`:473-481`）⇒ **C1/C3 完全不进入断言路径**。

因此本子任务的核心测试增量就是**让这条已经正确的断言覆盖自选开启**。

### 7.2 用例清单

| 用例 | 断言 | 非空性（改动前必须失败） |
|---|---|---|
| 斗地主 · 自选关闭 · 局内菜单重开 | 复用 `_selection_title_matches_local_assignment()`；标题座次 == 数组座次 == 面板 `_selected_seat_number` | 该组合改动前已通过 → 属**回归保护**，用于证明修复未破坏行为 |
| 斗地主 · **自选开启** · 局内菜单重开 | 同上 | **改动前必须失败**（C1 主因验证） |
| 2v2 · **自选开启** · 局内菜单重开 | 同上 | **改动前必须失败** |
| **身份局 · 自选开启 · 在领袖阶段重开** | 同上（对应 §2.4 的修正，证明身份局也会中招） | **改动前必须失败** |
| 预览被他人确认后回读 | 预览座次被他人确认后，标题回落到权威值而非保留被拒预览 | 对应 C3；改动前必须失败 |

断言规范：失败信息必须同时打印**标题文本**、**面板缓存值**、**权威数组座次**与**队列中的座位/身份占用情况**（沿用既有 `_selection_title_matches_local_assignment()` 的输出风格）。

### 7.3 测试实现注意

- 必须走真实 `main.tscn` 与局内菜单按钮（既有 `doudizhu_mode_test.gd:381-440` 已是该模式，直接复用）。
- 该用例会**修改全局 `GameSettings`**，必须显式恢复（既有 `_restore_settings()` 直到 `:84` 才恢复，存在跨用例耦合——扩展时用 try/finally 式的成对恢复，避免污染后续用例）。
- 不使用固定墙钟等待；等待快照/阶段用条件循环 + 兜底上限。

## 八、文档同步

按 `.trellis/spec/project/documentation-sync.md` 的同步矩阵：

| 文档 | 必查原因 | 预期更新 |
|---|---|---|
| `docs/架构说明.md` | 权威规则 / 状态结构（座次投射与表现层复位边界） | 补「新对局复位选将面板」与「面板座次唯一来源为本局权威快照」 |
| `docs/游戏机制与玩法内容.md` | 座位规则与自选座次身份流程（`:43`、`:54`、`:61`、`:539`、`:546`） | 明确「每次开局重新随机并刷新显示」；记录「权威预览被拒时界面回落到权威值」这一行为 |
| `docs/界面与交互.md` | 界面 / 交互规格（标题座次取值来源） | 补面板座次/身份的取值来源与复位时机 |
| `README.md` | 仅当新增测试场景 | 本设计**只扩展现有测试场景**，预期无需改动；若最终新增了 `*_test.tscn` 则必须补「自动校验」 |

## 九、风险与未决

| 风险 | 处置 |
|---|---|
| 修复二改变「预览被拒后界面行为」 | 明确文档化（§八）；若用户期望保留本地值，则应改为「权威回读 + 错误提示」而非保留错误值——本设计选择回落权威值，因为它满足不变量 I1 |
| 局域网路径未深挖 | 调研未逐行核对 `prepare_lan_match_assignments`（`match_table.gd:3728`）与 `_build_lan_slot_identity_distribution()`（`match_controller.gd:9509-9510`）组合是否会让客户端本地视角座次与服务端不一致。**列为显式未决项**，实现阶段先跑既有 `lan_*` 用例确认无回归，不扩大改动 |
| 用户所指「座位」的界面渠道 | **已由用户确认：两者都要修**。本文档负责其中的「本局 vs 上一局的跨局缓存」部分；「标题用领袖旋转序、对手标签用创建序」这一**取值序**缺陷已拆为独立子任务 `10-05-align-seat-labels-with-authoritative-order`。若在实现本子任务时观察到失败原因是取值序而非跨局缓存，应把该现象交给子任务 C，不要在本文档范围内顺手改数组顺序 |
| 未实机复现 | 调研为只读推导。实现阶段第一步必须**先让新断言在改动前失败**，以实证取代推导 |

## 十、回滚

改动面为「一行调用 + 面板两处条件/归零」，无数据迁移、无存档格式变化、无协议变化。回滚即删除该行调用并还原面板两处逻辑。
