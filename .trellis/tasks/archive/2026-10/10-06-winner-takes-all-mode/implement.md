# Implement：新游戏模式「胜者为王」

> **执行顺序不可调整。** 存在两个并列的 P0 阻断项，缺任何一个新模式都跑不起来：
> 1. **规则层未注册**：`normalize_mode`（`identity_rules.gd:59-70`）是白名单，未注册时新模式被静默当作身份模式，`_evaluate_identity_winner` 找不到主公，会在首次 `_check_game_over()` 立即判「反贼」结束对局。
> 2. **选将服务未接入**：`character_selection_service.gd:429-431` 在 `uses_leader_priority_selection()` 为真且找不到 `leader_player_id` 时直接返回 `"身份配置缺少领袖，无法开始选将。"`，**对局根本无法开始**。
>
> 因此 **T1 与 T1B 都必须在任何对局级验证（V3 / V4）之前完成**。T1B 未完成时，T3 / T4 的段内验证会全部失败且现象具有误导性。
>
> 每完成一个 T 段落，立即运行该段落的"段内验证"，再进入下一段。

## 0. 前置检查（Pre-flight）

- [ ] P1 读取工作规范：`.trellis/spec/` 下的 `project/`、`core/`、`ui/`、`adapters/` 索引与检查清单；确认本次涉及的分层规范已读。
- [ ] P2 确认禁止路径全程未被打开：`游戏机制关键词（AI禁读禁改）/`、`设计自用文档（AI禁改禁读）.md`、`【统帅三？军】（临时文件）（AI禁读）.txt`。
- [ ] P3 确认不修改：`三国杀规则集/`、`无名杀参考代码/`、`参考图/`。
- [ ] P4 记录基线：`git status` 干净、`git rev-parse HEAD` 记下起始提交；确认 `.trellis/tasks/10-06-winner-takes-all-mode/` 下已有 `prd.md` / `design.md` / `implement.md`。
- [ ] P5 基线跑一遍受影响的既有测试，确认"改前是绿的"，便于区分新引入的失败与既有失败：
  - `res://tests/doudizhu_mode_test.tscn`
  - `res://tests/team2v2_mode_test.tscn`
  - `res://tests/main_menu_test.tscn`
  - `res://tests/game_settings_persistence_test.tscn`
  - `res://tests/font_color_audit_test.tscn`
- [ ] P6 grep 出 `host_lan(` / `update_lan_lobby_settings(` 的**全部**调用点与相关测试（这两个是位置参数函数，T5 会改签名）：

  ```
  grep -n "host_lan(\|update_lan_lobby_settings(" --include=*.gd .
  ```

  把结果记下来；T5 必须逐点更新。

---

## T1 规则层注册与规则分支（`scripts/core/identity_rules.gd`）

**目标**：让 `MODE_WINNER_TAKES_ALL` 成为一等模式，并让 §4.2 的 5 个函数可用。

- [ ] T1.1 常量块（`:7-22`）新增 `MODE_WINNER_TAKES_ALL: String = "winner_takes_all"`，配逐行注释说明稳定 ID 与显示名对应关系。
- [ ] T1.2 `normalize_mode`（`:59-70`）白名单加入该 ID。
- [ ] T1.3 `get_distribution`（`:110-132`）新增分支：该模式且人数在 `get_supported_player_counts` 内时返回 n 个 `"renegade"`；人数不支持时返回空数组（沿用既有约定）。
- [ ] T1.4 `supports_lobby_custom_identity`（`:136-137`）改为「除过关斩将与胜者为王外为 true」，并更新函数上方的文档注释写明原因（只有一种身份，自选无意义）。
- [ ] T1.5 `get_first_player_identity`（`:173-178`）加入返回 `""` 的分支（本模式无主公），并更新注释。
- [ ] T1.6 `starts_from_first_seat`（`:182-184`）加入返回 true 的分支（一号位先手）。
- [ ] T1.7 `is_identity_public_at_start`（`:200-204`）加入返回 true 的分支（全员同身份，隐藏无意义）。
- [ ] T1.8 `are_identities_teammates`（`:235-256`）加入显式分支恒返回 false，注释说明「全员同为内奸，任意两人（含两个内奸之间）都不互为队友」。
- [ ] T1.9 `evaluate_winner`（`:278-291`）新增分支委托 `_evaluate_winner_takes_all_winner(state)`。
- [ ] T1.10 `get_death_reward`（`:299-315`）新增分支：本模式且 `killer != null` 时返回 `"draw_three"`；保留既有 `killer == null` 早退语义。注释说明**不改 `death_resolution_service`**，因为它已实现 `"draw_three"`。
- [ ] T1.11 文件末尾新增私有函数 `_evaluate_winner_takes_all_winner(state)`：存活 1 人 → 返回顶部常量 `WINNER_TAKES_ALL_WINNER_ID`；存活 0 人 → `"draw"`；否则 `""`。
- [ ] T1.12 顶部新增常量（均为脚本顶部、带逐行注释、说明取值含义与修改影响）：
  - `WINNER_TAKES_ALL_WINNER_ID: String = "last_survivor"`
  - `WINNER_TAKES_ALL_HAND_BONUS_SEAT_PAIR_SIZE: int = 2`
  - `WINNER_TAKES_ALL_HP_BONUS_FIRST_SEAT: int = 5`
  - `WINNER_TAKES_ALL_HP_BONUS_SECOND_SEAT: int = 9`
  - `WINNER_TAKES_ALL_HP_BONUS_LOW_TIER: int = 1`
  - `WINNER_TAKES_ALL_HP_BONUS_HIGH_TIER: int = 2`
- [ ] T1.13 新增 `get_seat_compensation_hand_bonus(mode_id, seat_number, enabled)`：非本模式 / `not enabled` / `seat_number < 1` → 0；否则 `(seat_number - 1) / WINNER_TAKES_ALL_HAND_BONUS_SEAT_PAIR_SIZE`（整数除法）。**必须写清"座次为 1 起始的规则座次"** 与各档位数值。
- [ ] T1.14 新增 `get_seat_compensation_max_hp_bonus(mode_id, seat_number, enabled)`：非本模式 / `not enabled` / `seat_number < 1` → 0；`seat_number >= 9` → 高档次；`seat_number >= 5` → 低档次；否则 0。
- [ ] T1.15 **不改** `get_opening_max_hp_bonus` 的签名与实现（3 参调用点保持兼容）。
- [ ] T1.16 **不改** `rule_timing_catalog.gd`：该文件的 `MODE_TIMINGS` 是**规则时机事件名**列表，与游戏模式 ID 无关（已核实零 `MODE_` / `match_mode` 命中）。

**段内验证 V1**（先写最小断言，或在本段完成后立即用 T7 的测试骨架跑）：
- `normalize_mode("winner_takes_all") == "winner_takes_all"`
- `get_supported_player_counts(MODE_WINNER_TAKES_ALL) == [2,3,4,5,6,7,8,9,10]`
- 对 2—10 每个人数，`get_distribution(n, ...)` 长度 n 且全为 `"renegade"`
- `get_seat_compensation_hand_bonus(MODE_WINNER_TAKES_ALL, s, true)` 对 s=1..10 等于 `[0,0,1,1,2,2,3,3,4,4]`
- `get_seat_compensation_max_hp_bonus(MODE_WINNER_TAKES_ALL, s, true)` 对 s=1..10 等于 `[0,0,0,0,1,1,1,1,2,2]`
- 上述两个函数的 `enabled=false` 时全部为 0，且 `mode_id = MODE_IDENTITY` 时全部为 0
- `get_death_reward(killer, victim, MODE_WINNER_TAKES_ALL) == "draw_three"`；killer 为 null 时为 `""`
- `are_identities_teammates("renegade", "renegade", MODE_WINNER_TAKES_ALL) == false`
- `starts_from_first_seat(MODE_WINNER_TAKES_ALL) == true`；`get_first_player_identity(...) == ""`

**回归检查**：`doudizhu_mode_test` / `team2v2_mode_test` 的纯规则段仍全绿（证明既有模式分支未被改动）。

---

## T1B 选将服务接入（P0 阻断项，`scripts/core/character_selection_service.gd`）

**为什么必须在 T3/T4 之前**：不接这一步，`start_match` 会在选将阶段直接返回错误串「身份配置缺少领袖，无法开始选将。」，所有对局级验证都拿不到开局。逐步追踪见 `design.md` D11。

- [ ] T1B.1 新增 `is_winner_takes_all_mode()` 判定：`return match_mode == "winner_takes_all"`。本文件使用裸字符串比较（与 `is_conquest_mode()` `:124-125` 一致），**不要**引入 `IdentityRules.MODE_*` 常量，保持文件内风格统一。
- [ ] T1B.2 `begin()` 的模式解析（`:400-407`）在 `elif requested_match_mode == "conquest":` 之后插入 `elif requested_match_mode == "winner_takes_all": match_mode = "winner_takes_all"`。
- [ ] T1B.3 **核实调用方**：读取 `match_controller.gd:1594` 附近 `character_selection.begin(...)` 的实际实参，确认传入的是 `str(state.match_mode)`（即含模式 ID）。若传入空串，则 T1B.1 的判据恒为 false，本步骤必须先把调用方改为传入模式 ID。
- [ ] T1B.4 `get_first_seat_identity()`（`:103-110`）在 `if is_team2v2_mode() or is_conquest_mode(): return ""` 处补上 `or is_winner_takes_all_mode()`，并更新函数上方注释说明本模式无主公。
- [ ] T1B.5 `leader_player_id` 回落分支（`:426`）的 `(is_team2v2_mode() or is_conquest_mode())` 补 `or is_winner_takes_all_mode()`，使 `:429-431` 的领袖校验通过（记录一号位玩家 ID，不表示领袖优先选将）。
- [ ] T1B.6 跳过领袖技候选注入：`:409` 的 `if uses_leader_priority_selection():` 与 `:439` 的 `_make_candidates(leader_player_id, "", true)` 各加 `and not is_winner_takes_all_mode()`，并加注释说明「本模式无人是主公，主公技武将前置为锁定候选属纯劣势」。
- [ ] T1B.7 **不改** `uses_simultaneous_selection()`（`:154-155`）与 `uses_leader_priority_selection()`（`:167-168`）：保持 true/false 原值，复用既有 PHASE_LEADER 状态机实现"一号位先选、再顺时针"。
- [ ] T1B.8 `character_selection_panel.gd`：`selection_mode` 推断（`:865-885`）加本模式分支；`_get_first_seat_identity_id()`（`:913-932`）加入返回 `""` 的分支（否则选将界面会把一号位标成主公）。
- [ ] T1B.9 核对并记录（**不改动**）：主公技在无 `leader` 身份时全程休眠（`match_controller.gd:4722/4761/10845/10891/16014`、`match_table.gd:2159`、`basic_ai_policy.gd:422`、`identity_strategy_evaluator.gd:292`）。这是 2v2 / 车轮战 / 过关斩将的既有共同行为，本模式与之一致（`design.md` D12 / D13）。

**段内验证 V1B**：
- `character_selection.begin(...)` 返回空串（不是错误串）；`match_mode == "winner_takes_all"`；`get_first_seat_identity() == ""`；`uses_leader_priority_selection() == true`。
- 本模式下 2 人开局：`start_match` 返回成功，`state.current_phase` 进入 `character_selection`（不出现 `push_error`、不出现「对局缺少首回合角色」）。
- **回归**：身份模式 5 人开局的 "主公优先选将" 行为与改动前逐字一致（`get_first_seat_identity() == "leader"`、领袖技候选仍被注入）。

---

## T2 设置层（`scripts/autoload/game_settings.gd`）

- [ ] T2.1 常量区（`:263-278`）新增 `MATCH_MODE_WINNER_TAKES_ALL: String = "winner_takes_all"`。
- [ ] T2.2 默认值区（`:280-316`）新增 `DEFAULT_WINNER_TAKES_ALL_PLAYER_COUNT: int = 8`、`DEFAULT_SEAT_COMPENSATION_ENABLED: bool = false`，注释说明"默认 8 人与其他 2—10 人模式一致""默认关闭保持对称开局"。
- [ ] T2.3 人数槽区（`:346-361`）新增 `next_match_player_count_winner_takes_all: int = DEFAULT_WINNER_TAKES_ALL_PLAYER_COUNT`，**逐行注释**（作用、含义、取值范围、默认值原因、修改影响）。绝不重命名既有槽。
- [ ] T2.4 开关变量区（`:371` 附近，紧邻 `custom_character_assignment_enabled` 同风格）新增 `seat_compensation_enabled: bool = DEFAULT_SEAT_COMPENSATION_ENABLED`，逐行注释说明"仅胜者为王模式读取；默认关闭；运行时可变并持久化"。
- [ ] T2.5 信号区（`:25-59`）新增 `signal seat_compensation_enabled_changed(enabled: bool)`，带注释。
- [ ] T2.6 `normalize_match_mode`（`:587-598`）加入该 ID。
- [ ] T2.7 `get_stored_player_count_for_mode`（`:621-633`）与 `_store_player_count_for_mode`（`:637-651`）加入该模式槽。
- [ ] T2.8 `set_next_match_player_count` / `normalize_player_count_for_mode` 无需改动（else 分支已按 2—10 收敛）——**核对后确认，不盲改**。
- [ ] T2.9 新增 `set_seat_compensation_enabled(enabled: bool)` setter：值未变则早退；否则赋值 + 发射信号 + `_queue_settings_save()`。形态照抄 `set_custom_character_assignment_enabled`（`:673-678`）。
- [ ] T2.10 存档写（`:993-1029`）新增 `gameplay/seat_compensation_enabled` 与 `gameplay/next_match_player_count_winner_takes_all`。
- [ ] T2.11 读档读（`:881-911`）新增两项读取，**缺字段时回落默认值**（`DEFAULT_SEAT_COMPENSATION_ENABLED` / `DEFAULT_WINNER_TAKES_ALL_PLAYER_COUNT`），保证旧存档不报错。
- [ ] T2.12 若 `set_value`（`:1002-1009`）是逐键列举式，同步补两个键。

**段内验证 V2**（并在 T7 里固化为断言）：
- 设置该模式人数 9 → 切到身份模式 → 切回 → 仍为 9；身份模式人数未变。
- `set_seat_compensation_enabled(true)` → 信号发射一次 → `_save_settings()` → 重新加载设置文件 → 仍为 true。
- 用一个**不含**新字段的旧配置文件路径加载 → 人数回落 8、开关回落 false，无 `ERROR` 输出。

---

## T3 开局锁定（`scripts/core/match_controller.gd`）

- [ ] T3.1 `state.match_options` 字典字面量（`:1537-1553`）追加 `"seat_compensation_enabled"`。取值按 `design.md` §4.1 的解析规则，写成与相邻 `lan_*` 键同风格的单行三元表达式，并带空值守卫；加注释说明"LAN 房主以房间状态为准，其余以本地持久化设置为准；本局锁定后不再变化"。
- [ ] T3.2 `_resolve_match_mode`（`:1454-1460`）核对：新模式经 `normalize_mode` 后即返回自身，**无需改动**（确认后不做无谓修改）。
- [ ] T3.3 `get_match_start_validation_error`（`:1421-1451`）核对人数校验走 `get_supported_player_counts`，2—10 已通过，**无需改动**。若需要，仅追加一句可选提示文案。
- [ ] T3.4 新增私有只读助手（放在 `_refresh_pre_game_character_stats` 附近，带注释）：
  ```
  ## 返回本局是否启用座次补偿；只读取开局锁定的模式选项，保证进行中不受设置改动影响。
  func _is_seat_compensation_enabled() -> bool
      # 返回 bool(state.match_options.get("seat_compensation_enabled", false))，state 为空时返回 false
  ```
- [ ] T3.5 新增私有只读助手（带注释）：
  ```
  ## 返回玩家当前的一号位起规则座次；座次由 players 数组顺序派生，找不到时返回 -1。
  func _get_player_seat_number(player: PlayerState) -> int
      # state.players.find(player) + 1；沿用 format_player_state_log_name（:4237-4246）的既有惯用法
  ```

**段内验证 V3**：以 3 人开局一次，打印/断言 `state.match_options["seat_compensation_enabled"]` 为 false（默认关闭）；`GameSettings.set_seat_compensation_enabled(true)` 后重新开局为 true。

---

## T4 座次补偿落点（`scripts/core/match_controller.gd`）

- [ ] T4.1 **初始手牌**：`:11418-11424` 的 `seat_hand_count` 表达式在既有「基础 + 2v2 四号位 + 机缘」累加串末尾追加：
  ```
  + identity_rules.get_seat_compensation_hand_bonus(str(state.match_mode), seat_index + 1, _is_seat_compensation_enabled())
  ```
  加注释说明 `seat_index + 1` 是 1 起始座次，且该下标在此时已是最终座次（`_create_players` 在创建后立即排序）。
- [ ] T4.2 **体力上限**：`_refresh_pre_game_character_stats`（`:9647-9669`）在既有 `opening_max_hp_bonus` 之后追加座次补偿：
  ```
  opening_max_hp_bonus += identity_rules.get_seat_compensation_max_hp_bonus(str(state.match_mode), _get_player_seat_number(player), _is_seat_compensation_enabled())
  ```
  注意 `player.max_hp` 的赋值表达式（`:9655`）本身不改（仍是 `maxi(基础,1) + opening_max_hp_bonus`），只改 bonus 的累加。加注释说明**不改 `get_opening_max_hp_bonus` 签名**的原因（既有 3 参调用点 + 身份驱动与座次驱动语义分离）。
- [ ] T4.3 **手气卡**：核对 `_refresh_starting_hand`（`:11651-11685`）使用 `returned_cards.size()` 作为重发张数 → **确认零改动**。写一条注释说明"重发张数取实际起始手牌数，因此座次补偿天然被沿用，无需在此重复计算"。
- [ ] T4.4 **开局日志**：在 `:11483` 附近的开局日志追加一句座次补偿摘要（仅在开关开启时输出），格式与既有模式日志一致。**不扩展** `gameDraw` 运行时事件结构（避免影响回放兼容性），并在注释中写明这一取舍。
- [ ] T4.5 `_refresh_player_starting_hand`（`:11650` 附近）核对：确认重发路径不重新计算座次补偿（由 T4.3 的语义保证）。

**段内验证 V4**：
- 开启补偿 + 9 人开局 → 逐座断言起始手牌追加为 `[0,0,1,1,2,2,3,3,4]`，`max_hp` 追加为 `[0,0,0,0,1,1,1,1,2]`。
- 关闭补偿 + 9 人开局 → 全部座次起始手牌与 `max_hp` 等于改动前的基准值。
- 身份模式 5 人开局 → 主公 `max_hp` 仍为基础 +1，其余角色 +0（回归）。

---

## T5 局域网注册与房间开关（`scripts/network/network_gateway.gd`）

- [ ] T5.1 `LOBBY_GAME_MODE_OPTIONS`（`:106-113`）追加 `{"id": "winner_takes_all", "display_name": "胜者为王"}` 项（保持既有字典键结构）。
- [ ] T5.2 `_is_lobby_game_mode_playable`（`:1682-1684`）字面量白名单加入该 ID。**此步不可省**：只做 T5.1 会让房间开局被拒（`match_table.gd:972` 分支）。
- [ ] T5.3 房间状态变量区（`:161-167` 附近）新增 `_lobby_seat_compensation_enabled: bool = false` + 逐行注释；`_set_offline_state`（`:1740-1743`）重置为 false。
- [ ] T5.4 `host_lan`（`:269`）追加位置参数 `seat_compensation_enabled: bool = false`，并在函数体（`:295-297` 附近）赋值。
- [ ] T5.5 `update_lan_lobby_settings`（`:437`）追加同名位置参数，函数体（`:451-453` 附近）赋值。
- [ ] T5.6 新增只读访问器 `is_lan_seat_compensation_enabled() -> bool`，形态照抄 `is_lan_fixed_seat_enabled()`（`:426-427`，注意 `mode == Mode.LAN and _lobby_seat_compensation_enabled`）。
- [ ] T5.7 `get_lan_lobby_snapshot()`（`:397-409`）新增 `"seat_compensation_enabled"` 字段。
- [ ] T5.8 `_apply_remote_lobby_state`（`:1377-1398`，写入点 `:1384-1389`）读取该字段。
- [ ] T5.9 `PROTOCOL_VERSION`（`:61`）10 → 11，并在变更说明注释块（`:56-60`）追加一行说明本次新增的房间字段。
- [ ] T5.10 **逐点更新 P6 记录的全部调用点**（`match_table.gd:946-950`、大厅面板信号、既有局域网测试）并同步修改相关函数签名与 `host_requested` / `settings_update_requested` 信号。

**段内验证 V5**：
- `_is_lobby_game_mode_playable("winner_takes_all") == true`
- 房主 `host_lan(..., seat_compensation_enabled = true)` → `get_lan_lobby_snapshot()["seat_compensation_enabled"] == true` 且 `is_lan_seat_compensation_enabled() == true`
- `update_lan_lobby_settings(..., seat_compensation_enabled = false)` → 快照与访问器同步为 false
- 用旧协议版本号构造握手包 → 被既有版本检查拒绝（证明版本提升生效）

---

## T6 AI 口径（`scripts/ai/identity_ai_model.gd`）

- [ ] T6.1 `get_real_attitude`（`:331-428`）**函数顶部**新增模式分支：当 `str(authoritative_snapshot.get("match_mode", "")) == IdentityRules.MODE_WINNER_TAKES_ALL` 时，`to_player_id == from_player_id` 返回自身态度常量，否则返回自由混战敌对态度常量（负值，量级与既有 `ENEMY`/`-8.0` 一致，提取为顶部常量）。
- [ ] T6.2 分支位置必须在既有的斗地主分支（`:345-348`）与 2v2 分支（`:350-353`）**之前**，并保证这三个分支互斥（模式不同）。
- [ ] T6.3 保留末尾既有 `if to_identity == "renegade": return 0.0`（`:426-427`）**逐字不动**——它是身份模式下的正确行为，本模式靠 T6.1 的分支提前返回。
- [ ] T6.4 新增顶部常量（带逐行注释说明取值与影响）：本模式对自身/对他人的态度值。
- [ ] T6.5 核对 `_update_identity_mark`（`:610-637`）：本模式 `identity_revealed` 恒为 true，`:617` 已提前返回 → **零改动**，加一条注释说明依赖关系。
- [ ] T6.6 `identity_strategy_evaluator.gd` **零改动**：在文件顶部相关函数处补充注释，说明内奸分支在无主公/忠臣/反贼时会安全退化（`_score_renegade_negative_effect` 落到"压制更强者"、`_score_renegade_positive_effect` 返回 0.0、`_is_confirmed_ally` 对同身份返回 false），因此本模式无需额外分支。

**段内验证 V6**：
- 本模式快照下 `get_real_attitude` 对任意其他玩家为负、对自身为正。
- 身份模式快照（同为 `renegade` 的两名玩家）下 `get_real_attitude` 的返回值与本改动前**逐字相同**（回归；可用改动前的固定期望值断言）。
- 斗地主 / 2v2 快照下态度不变（回归）。

---

## T7 界面接入

### T7.1 主菜单场景（`scenes/main.tscn`）

- [ ] T7.1.1 在 `ConquestModeButton` 块（`:1521-1563`）之后插入第 7 张模式卡，**完整复用 5 节点结构** + 全新 `unique_name_in_owner`：`WinnerTakesAllModeButton` / `WinnerTakesAllModeContent` / `WinnerTakesAllModeName` / `WinnerTakesAllModePlayerCount` / `WinnerTakesAllModeIndicator`。
- [ ] T7.1.2 硬性规格不得压缩：卡片 `custom_minimum_size.y = 100`、`Content` 上下内边距 14、标题字号 27、人数提示字号 16；卡片内部**不放任何 Button**。
- [ ] T7.1.3 人数提示文案：`2-10人`。
- [ ] T7.1.4 在 `SettingsVBox`（`:1737`）内 `MainMenuConquestOpportunityChoiceRow` 之后克隆新增 `MainMenuSeatCompensationRow` + `MainMenuSeatCompensationCheckBox`，标签文案「座次补偿」。

### T7.2 主菜单脚本（`scripts/ui/main_menu.gd`）

- [ ] T7.2.1 新增 `@onready`：新按钮、新指示灯、新设置行、新复选框（放在既有 `:275-279` 同区）。
- [ ] T7.2.2 `_ready()`（`:378-384`）连接新按钮的 `pressed` 与新复选框的 `toggled`。
- [ ] T7.2.3 新增 `STARTING_STATUS_TEXT_WINNER_TAKES_ALL`（`:45-60` 同区）。
- [ ] T7.2.4 `MODE_DETAILS_BY_MODE`（`:84-97`）新增该模式键，正文按 PRD R6.2 写全：2—10 人、全员内奸、击杀其余全部角色、最后存活者获胜、统一摸 3 张、一号位先手，以及 `1、2号位+0；3、4号位+1；5、6号位+2；7、8号位+3；9、10号位+4`、`5至8号位体力上限+1；9号位及以后体力上限+2`、默认关闭。**文案必须与 `docs/游戏机制与玩法内容.md` 的数值表逐字一致**（测试用 `contains()` 逐字断言）。
- [ ] T7.2.5 新增 `_select_winner_takes_all_mode()`，以 `_select_opportunity_brawl_mode()`（`:950-986`）为模板：设置 `_selected_match_mode`、把其他 7 个按钮/指示灯的选中态清掉、设置人数上下限为 2/10/步长 1、调用 `_set_wheel_duel_settings_visible(...)`、刷新状态文案、刷新 UI。
- [ ] T7.2.6 **在既有 6 个 `_select_*_mode()`（`:773`/`:818`/`:865`/`:912`/`:950`/`:990`）中各加一行关闭新按钮的选中态**（本文件无 `ButtonGroup`，互斥靠显式赋值；漏改会导致两个模式同时高亮）。
- [ ] T7.2.7 `refresh_ui_style()`：新指示灯的选中色加入 `:617-625` 段，新卡样式加入 `:629-634` 段，新卡两个标签的字体色覆盖加入 `:657-674` 段（**`font_color_audit_test` 会遍历全部静态 Label/CheckBox，漏掉即失败**）。
- [ ] T7.2.8 `_restore_selected_match_mode`（`:752-770`）新增该模式分支（按持久化模式恢复选中）。
- [ ] T7.2.9 `_set_wheel_duel_settings_visible`（`:1032-1056`）新增该模式判定：`_seat_compensation_row.visible = is_winner_takes_all`。
- [ ] T7.2.10 `_request_start_game`（`:1341-1351`）新增该模式的起始状态文案分支。
- [ ] T7.2.11 设置行/复选框初值同步：在 `_ready()` 的初始同步段读取 `GameSettings.seat_compensation_enabled`，`toggled` 回调写回 setter。
- [ ] T7.2.12 `_ensure_mode_button_visible`（`:1694-1699`）核对：新按钮已注册，**确认无需改动**。

### T7.3 局内菜单（`scenes/main.tscn` + `scripts/ui/match_menu.gd`）

- [ ] T7.3.1 在 `MatchConquestOpportunityChoiceRow`（`:472-484`）之后克隆新增 `MatchSeatCompensationRow` + `MatchSeatCompensationCheckBox`。
- [ ] T7.3.2 `match_menu.gd` 新增引用（`:66` / `:133-136` 同区）、`_ready()` 连接（`:216-221` 同区）、初值同步（`:240` 同区）。
- [ ] T7.3.3 `_apply_mode_specific_settings_visibility`（`:364-384`）新增该模式的行显隐。
- [ ] T7.3.4 **同步更新 3 处易漏的并行列表**：焦点交还链（`:338`）、标签色覆盖（`:416-417`）、控件样式（`:437-438`）。漏改表现为"隐藏后焦点丢失"或"标签颜色不对"。
- [ ] T7.3.5 `set_match_mode`（`:357-360`）核对：模式变更后触发显隐刷新，**确认无需改动**。
- [ ] T7.3.6 新复选框 `toggled` 写 `GameSettings.set_seat_compensation_enabled(...)`（只影响下一局，与自选武将同语义）。

### T7.4 联机大厅（`scenes/components/*.tscn` + 两个面板脚本）

- [ ] T7.4.1 `scenes/components/lan_lobby_panel.tscn`：在 `LanFixedSeatCheckBox`（`:188`）之后克隆新增 `LanSeatCompensationCheckBox` 行。
- [ ] T7.4.2 `lan_lobby_panel.gd`：新增引用（`:55` 同区）；在 `host_requested.emit(...)`（`:208`）中带上该勾选值；扩展信号签名（`:7`）。
- [ ] T7.4.3 `scenes/components/online_lobby_panel.tscn`：在 `FixedSeatCheckBox`（`:317`）之后克隆新增 `OnlineSeatCompensationCheckBox` 行。
- [ ] T7.4.4 `online_lobby_panel.gd`：新增引用（`:109` 同区）；`_open_settings`（`:360-380`）从房间快照回填显示值；`settings_update_requested`（`:16` / `:406`）带上该值；按 `_refresh_room_controls`（`:351-356`）的房主门禁决定可编辑性；非本模式时按既有 disable 机制（`:552-566`）处理。
- [ ] T7.4.5 `match_table.gd`：更新 `lan_lobby_changed` / `settings_update_requested` 的连接与转发（`:646-654`、`:946-950`、约 `:1004-1052`），把新参数透传到 `host_lan` / `update_lan_lobby_settings`。
- [ ] T7.4.6 核对 `_apply_player_count_limits_for_mode`（`online_lobby_panel.gd:584-608`）：else 分支已为 2—10，**确认无需改动**。

### T7.5 终局表现与身份表现（`scripts/ui/match_table.gd` + `scripts/ui/character_selection_*.gd`）

- [ ] T7.5.1 `_is_local_player_victory`（`:5635-5650`）新增分支：`winner == IdentityRules.WINNER_TAKES_ALL_WINNER_ID` 时以**本地玩家是否存活**为判定依据，并加注释说明"不能比对身份——全员身份相同"。
- [ ] T7.5.2 `_get_post_match_result_text`（`:5622-5632`）核对：由 `_is_local_player_victory` 驱动，**确认无需改动**。
- [ ] T7.5.3 `match_controller._winner_text`（`:18356-18365`）新增 `"last_survivor"` → 「最后的胜者」映射。
- [ ] T7.5.4 `set_auto_identity_marking_visible(current_match_mode == "identity")`（`:4194-4195`）核对：本模式已被排除，**确认无需改动**。
- [ ] T7.5.5 身份标记入口（`:847`、`:881`）**只做核对，不做修改**：本模式身份开局公开（T1.7）⇒ `:851` 的 `identity == "hidden"` 条件不成立 ⇒ 手动标注菜单不可达；`_update_identity_mark` 也因目标身份为 `renegade` 而权重为 0。确认二者均为死路径即可；**若实测发现可达再最小化扩展排除条件**，不要预防性改动。
- [ ] T7.5.6 选将服务与选将面板的接入已在 **T1B** 完成（P0 阻断项前置）。此处只做核对：`character_selection_panel` 在本模式下正常显示「内奸」身份、不显示主公标记、不注入主公技候选。

**段内验证 V7**：
- 主菜单：模式列表为 7 项且顺序为 身份模式、斗地主、2v2、1v1车轮战、机缘大乱斗、过关斩将、胜者为王。
- 逐一点选 7 张卡：任意时刻恰有 1 张处于 `button_pressed`，`GameSettings.next_match_mode` 与之一致。
- 选中本模式：人数 SpinBox 上下限为 2/10、步长 1；「座次补偿」行可见；「详情」按钮可见。
- 选中其他 6 个模式：「座次补偿」行隐藏；各自的既有设置行显隐与改动前一致。
- 详情弹窗标题与正文逐字符合 PRD R6.2；关闭后弹窗隐藏。
- 滚动到底部：最后一张卡（胜者为王）完整进入视口且可被真实点击。

---

## T8 测试与文档

### T8.1 新增模式测试

- [ ] T8.1.1 新建 `tests/winner_takes_all_mode_test.gd`（`extends Node`），结构照抄 `tests/team2v2_mode_test.gd`：`_ready()` → `call_deferred("_run")`；自带 `_create_controller()` / `_fail(reason)` / `_restore_settings()`；PASS 打印 `WINNER_TAKES_ALL_MODE_PASS <tags>` 后 `quit(0)`，FAIL 打印 `WINNER_TAKES_ALL_MODE_FAIL <reason>=<实际值>` 后 `quit(1)`。
- [ ] T8.1.2 测试开头保存并在结尾还原会干扰的全局设置（`customize_ai_characters_enabled`、`custom_character_assignment_enabled`、`next_match_mode`、本模式人数槽、`seat_compensation_enabled`）。
- [ ] T8.1.3 控制器组件树 = `MatchController` + `RuleEventBus` + `AICoordinator` + `NetworkGateway` 子节点；`randomize_local_human_seat = false`、`game_flow_interval_seconds = 0.0`、`ai_action_delay_seconds = 0.0`。
- [ ] T8.1.4 覆盖 PRD 的 AC-1、AC-2、AC-3、AC-4（纯规则段 + 对局段）。对局段用固定种子 `start_match(人数, 种子, IdentityRules.MODE_WINNER_TAKES_ALL)`。
- [ ] T8.1.5 选将收敛：按**条件等待 + 有界帧预算**（不固定墙钟等待）推进到离开 `character_selection`；提交候选时**挑"首位未被其他玩家占用且当前可提交"的候选**，不要盲目提交 `candidates[0]`（固定种子下候选阵容会随武将库增长变化）。
- [ ] T8.1.6 新建 `tests/winner_takes_all_mode_test.tscn`：6 行最小场景（`load_steps=2 format=3` + `ext_resource` + `[node name="WinnerTakesAllModeTest" type="Node"]`）。
- [ ] T8.1.7 `.gd.uid` 由 Godot 编辑器生成，不手写。

### T8.2 既有测试同步

- [ ] T8.2.1 `tests/main_menu_test.gd` 6 处必改：
  1. `:119-130` 节点声明区追加新按钮（与建议的新标题 Label）。
  2. `:236-241` 选中底色比较追加 `winner_takes_all_selected_style`。
  3. `:242-249` **`mode_list_buttons.size() != 6` → `!= 7`**，补 `mode_list_buttons[6] != winner_takes_all_mode_button`，注释「六项」→「七项」。
  4. `:262-266` 追加新卡的 `custom_minimum_size.y == 100` 断言。
  5. `:274-284` **把"滚到底部最后一张卡完整可见"的断言目标从 `conquest_mode_button` 改为新的最后一张卡**；并确认后续对 `conquest_mode_button` 的真实点击在滚到底部时仍可见（必要时先显式滚动到该卡）。
  6. `:355-397` 详情断言段追加本模式（按钮可见 + 标题 `"胜者为王模式详情"` + 正文包含座次补偿数值），并把"指定三种模式的详情按钮"的既有描述改为四种；`identity_mode_copy` 断言若加了新标题字号检查需同步。
- [ ] T8.2.2 `tests/game_settings_persistence_test.gd`：追加本模式人数槽与 `seat_compensation_enabled` 的写—存—重载断言。
- [ ] T8.2.3 核对 `tests/ui_layout_test.gd` 是否断言模式卡滚动范围/数量；若有断言，同步更新（7 张卡使内容高度 660 → 772）。
- [ ] T8.2.4 `tests/font_color_audit_test.gd` **不用改**，但新卡两个标签必须已应用主题字体色覆盖（T7.2.7）；跑一遍确认。
- [ ] T8.2.5 核对 `tests/character_selection_timing_test.gd`：本模式用 `uses_leader_priority_selection()`（非同时选将），**确认无需新增门禁用例**；如后续改为同时选将再补。

### T8.3 文档同步

- [ ] T8.3.1 `docs/游戏机制与玩法内容.md`
  - 文件头 blockquote（`:17` / `:23` / `:25`）：「六张模式卡片」→ 七张；模式列表与人数分存补本模式（2—10 人、默认 8）。
  - `## 一、模式边界`（`:47-56`）：正式模式枚举句与人数枚举句补本模式及其规则归属。
  - `## 二、身份配置`（`:89-103`）：补一句"胜者为王不使用本身份人数表，全员固定 `renegade`"。
  - `### 联机自选身份与固定座位`（`:105-123`）：位置身份表枚举补一条（胜者为王不放开自选身份）。
  - `### 队友与友方`（`:125-131`）：补"全员内奸，任意两人都不互为队友"。
  - **新增 `### 胜者为王模式` 章节**，插入点 = 机缘大乱斗正文 bullet 之后（`:311` 之后、`:313` `### 阿哈时刻与欢愉技` 之前）。**建议顺手补回缺失的 `### 机缘大乱斗模式` 标题**（`:300` 起的正文当前直接挂在过关斩将章节下）。子结构照抄 2v2 章节（`:158-180`）：稳定模式 ID → 人数与 per-mode 计数槽 → 身份表（全员 `renegade`）→ 身份开局是否明置 → 座次补偿开关与全部具体数值 → 选将模式 → 起始手牌 → 击杀奖惩（统一摸 3 张）→ 胜负（最后存活者胜）→ 终局表现 → 局域网大厅支持性。并附 `#### 相关数值（可追溯）` 两列表格。
  - `### 死亡奖惩`（`:507-513`）：补"胜者为王模式下任意角色互杀统一为 `draw_three`（摸 3 张），不经由领袖/反贼分支"。
  - `## 十五、本轮机制与玩法快照`（`:1141-1151`）：追加一条本轮变更 bullet。
- [ ] T8.3.2 `docs/架构说明.md`：`GameSettings` 段（`:40`）、`IdentityRules` 四入口取值（`:82`）、`## 对局模式`（`:266-276`）新增条目；`:115`「六种模式」与 `:127`「六张模式卡」改为七。
- [ ] T8.3.3 `docs/界面与交互.md`：`:106`（详情按钮的模式枚举，改为四种）、`:159`/`:161`/`:165`/`:166`/`:167`（六张卡 → 七张 + 本模式预览说明）、`:454`（终局 `winner` 文案映射补 `last_survivor`）、`:458`/`:460`（模式列表与人数范围）。
- [ ] T8.3.4 `docs/内容制作指南.md`：`:53` 之后、`## 通用制作规范` 之前新增 `## 胜者为王模式扩展规范`；`:3895-3900` 开局模式参数注册表补本模式 ID 与 per-mode 人数槽（顺带修正该处 `conquest` 漏项）；`:3921` 显式声明本模式不加入机缘集合；`:3617-3630` 的 `get_death_reward` 行补本模式口径。
- [ ] T8.3.5 `docs/AI模块.md`：新增「全员内奸模式（胜者为王）的 AI 口径」一节，并在 4.2 真实态度（`:69-71`）、4.4 身份局战略（`:101-114`）、4.5 目标与牌效（`:116-134`）三处加限定说明。
- [ ] T8.3.6 `docs/网络通信.md`：`:23`/`:24` 的"可实际开局模式"枚举与位置身份表枚举补本模式；`:95` 协议版本变更说明同步到 v11。
- [ ] T8.3.7 `README.md`「自动校验」（`:58-204`）：新增 `res://tests/winner_takes_all_mode_test.tscn` 一行；改写 `:122` 的 `main_menu_test` 描述（模式入口顺序改为七项、详情按钮模式改为四种）。

### T8.4 交付附加（AGENTS.md 强制）

- [ ] T8.4.1 输出「学习反馈摘要」：修改思路 / 架构与设计 / 关键代码解析 / 学习要点提炼（1—3 条）。
- [ ] T8.4.2 输出「Git 提交描述」：数字序号分行，每行一个独立动作。
- [ ] T8.4.3 把上述两份内容**追加**到 `临时反馈文档.md`，开头带 `YYYY-MM-DD HH:MM` 时间戳；文件不存在则新建；不覆盖历史内容。

---

## 验证清单（Verification）

### V1 自动化测试

逐进程顺序执行（不要并发，会争用用户设置与 `.godot` 缓存）。判定：退出码 0 + 输出自身 `*_PASS` 标记 + 日志无 `ERROR`/`SCRIPT ERROR`/`FAIL`。

```
godot --headless --path . res://tests/winner_takes_all_mode_test.tscn
godot --headless --path . res://tests/doudizhu_mode_test.tscn
godot --headless --path . res://tests/team2v2_mode_test.tscn
godot --headless --path . res://tests/conquest_coop_test.tscn
godot --headless --path . res://tests/game_settings_persistence_test.tscn
godot --headless --path . res://tests/lan_custom_identity_test.tscn
godot --headless --path . res://tests/lan_lobby_ui_test.tscn
godot --headless --path . res://tests/lan_match_flow_test.tscn
godot --headless --path . res://tests/seat_display_source_test.tscn
godot --headless --path . res://tests/pre_game_deal_gain_test.tscn
godot --headless --path . res://tests/character_selection_timing_test.tscn
```

需要真实 GUI 命中的用例（严格像素断言）在编辑器内运行：

```
res://tests/main_menu_test.tscn
res://tests/font_color_audit_test.tscn
res://tests/ui_layout_test.tscn
```

`godot` 替换为本机 Godot 可执行文件路径。

### V2 手工开局验证（编辑器）

- [ ] V2.1 单机 2 人 / 5 人 / 10 人各开局一次（座次补偿关闭）：7 项模式入口可见，全员身份显示「内奸」，一号位先手，全程无 `push_error`。
  - **专项**：确认对局**不会**在开局首回合结束或第一张牌结算后立刻判「反贼」获胜（回归防线；`_check_game_over()` 会在每次用牌结算、每次 phaseAfter、每次死亡后调用）。若出现"开局即终局"，即 T1 的 `evaluate_winner` 分支未生效。
  - **专项**：确认全场无「?」身份徽记、无自动身份标记开关（身份开局公开）。
- [ ] V2.2 开启座次补偿 + 10 人开局：选将界面逐一核对 10 个座次的起始手牌（应为 4/4/5/5/6/6/7/7/8/8，若基础为 4）与体力上限（座次 1—4 为基础值，5—8 为 +1，9—10 为 +2）。
- [ ] V2.3 击杀验证：座次 A 击杀座次 B 后 A 手牌 +3；控制台与对局日志无错误。
- [ ] V2.4 胜负验证：把局面推进到仅剩 1 名玩家存活 → 该玩家客户端显示「游戏胜利」，其余显示「游戏失败」；`add_log` 输出「对局结束，获胜方：最后的胜者。」。
  - 判定依据必须是**本地玩家的 `alive` 公开字段**（`state.winner` 是纯字符串，没有 `winner_player_id`；`alive` 在快照中公开，客户端可自行判断"我是否唯一存活"）。
  - **专项**：已出局的客户端也必须显示「游戏失败」（若错误地复用 `renegade` 作为获胜 ID，全员都会显示胜利）。
- [ ] V2.5 平局验证：构造/推演全员同时阵亡 → 判平局，不崩溃。
- [ ] V2.6 AI 验证：本模式下 AI 在若干回合内主动对其他角色出攻击牌（不得全员观望到牌堆耗尽）。
- [ ] V2.7 局域网验证：房主建房选「胜者为王」并设人数 5 → 房间可开局 → 房主改「座次补偿」为开 → 客户端只读显示与房主一致 → 开局后 `state.match_options` 中该键为 true，客户端实际拿到补偿。
- [ ] V2.8 局内菜单：本模式下「座次补偿」行可见；切换其他模式后隐藏；修改后只影响下一局。

### V3 分层与规范核对

- [ ] V3.1 `IdentityRules` 内**没有**任何 `GameSettings` / `NetworkGateway` 引用（单向分层未被破坏）。
- [ ] V3.2 新增的每个变量/常量都有独占一行的注释，且 `@export`（若有）在检查器中可直接理解用途。
- [ ] V3.3 **没有**修改任何既有变量名，**没有**删除或篡改任何既有注释（仅新增）。
- [ ] V3.4 守卫新模式的代码分支一律以 `normalize_mode(...) == MODE_WINNER_TAKES_ALL` 为判定，不比较裸字符串字面量（除 `character_selection_service.gd` 的既有裸字符串风格，需与该文件保持一致）。
- [ ] V3.5 所有新增数值都来自顶部常量，没有内联魔法数字。

### V4 边界与回归核对（V6 专项）

- [ ] V4.1 逐点核对 `_refresh_pre_game_character_stats` 的 4 个调用点（`:1891`、`:1904`、`:9644`、`:15343`）与 `_apply_character` 的 8 个调用点（`:1888`、`:1898`、`:1962`、`:11163`、`:11325`、`:11582`、`:15272`、`death_resolution_service.gd:258`），确认本模式下不存在"开局后重入并重复累加体力上限"的路径。
- [ ] V4.2 核对 `_clear_pre_game_character_preview`（`:11330-11337`）直接写 `max_hp = 4` 不会在最终选将之后覆盖已应用的体力上限补偿；若会，把补偿改为在 `_finish_character_selection` 之后统一应用。
- [ ] V4.3 核对 `_reorder_players_from_leader()`（`:11739-11764`）在 `:11431` 的第二次调用对本模式仍是空操作（`leader_index` 恒为 -1）；在手牌发放与体力上限设置完成前后各打一条临时日志确认数组顺序未变。
- [ ] V4.4 核对 `_starting_hand_count`（`:408`）与开局日志（`:11483`）不会因座次补偿而误报基础张数（T4.4 已追加摘要）。
- [ ] V4.5 旧存档兼容：用手工构造的、缺少两个新键的设置文件启动 → 回落默认值，无 `ERROR`。

---

## Review Gates

- [ ] **G1 规则层与选将接入完成门**（T1 + T1B 后）：纯规则断言全绿；`begin(...)` 不再返回「身份配置缺少领袖」；本模式 2 人 `start_match` 能进入 `character_selection`；斗地主 / 2v2 / 身份模式既有纯规则段与领袖优先选将行为无回归。**未过此门不得继续 T2**。
- [ ] **G2 数值正确性门**（T4 后）：AC-4.1—AC-4.8 全部可验证；关闭态的数值与改动前逐字一致。
- [ ] **G3 结算正确性门**（T3+T7.5 后）：AC-2.4 的胜负区分成立（本地胜利 / 本地失败），AC-3 的摸 3 张成立，平局不崩。
- [ ] **G4 网络门**（T5 后）：AC-5.3 / AC-5.4 / AC-5.6 成立，且所有 `host_lan` / `update_lan_lobby_settings` 调用点已同步（P6 清单清零）。
- [ ] **G5 界面门**（T7 后）：AC-8.1—AC-8.4 成立；`main_menu_test` / `font_color_audit_test` 在编辑器内全绿。
- [ ] **G6 文档门**（T8.3 后）：AC-9.1—AC-9.6 逐条可勾选；数值表与代码常量逐项对齐（模式「详情」文案、文档表格、代码常量三者必须一致）。
- [ ] **G7 交付门**：学习反馈摘要 + Git 提交描述已输出并追加到 `临时反馈文档.md`。

---

## 不可做的事（Hard Stops）

- 不得在 T1 完成前改动任何其他文件。
- 不得新增身份 ID（复用 `renegade`）。
- 不得用 `"renegade"` 作为获胜 ID。
- 不得修改 `get_opening_max_hp_bonus` 的签名。
- 不得改 `death_resolution_service.gd` 的 `"draw_three"` 分支（已实现）。
- 不得让 `IdentityRules` 依赖 `GameSettings` / `NetworkGateway`。
- 不得只改 `LOBBY_GAME_MODE_OPTIONS` 而漏改 `_is_lobby_game_mode_playable`。
- 不得压缩既有模式卡的尺寸、字号或间距来给第 7 张卡让位。
- 不得重命名既有变量或删除既有注释。
- 不得修改 `rule_timing_catalog.gd`（`MODE_TIMINGS` 与模式 ID 无关）。
- 不得进入 `游戏机制关键词（AI禁读禁改）/`、`设计自用文档（AI禁改禁读）.md`、`【统帅三？军】（临时文件）（AI禁读）.txt`。
- 不得修改 `三国杀规则集/`、`无名杀参考代码/`、`参考图/`。
