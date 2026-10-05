# 执行计划：操控者同时操作本体与被操控者

对应需求：[`prd.md`](./prd.md) ｜ 技术设计：[`design.md`](./design.md)

> 权威代码文件：`scripts/core/match_controller.gd`
> 权威测试文件：`tests/turn_control_mechanism_test.gd`、`tests/lan_turn_control_test.gd`

---

## 阶段 A：核心解析函数（无行为变化，先落地）

- [ ] **A1** 新增私有纯查询 `_resolve_pending_operator_hint(explicit_player_id := -1) -> int`。
      内容 = 现 `_prepare_offline_controlled_view()` 内 `:18066-18084` 的排序链，逐条搬迁，**不改变任何比较顺序**。
      注释必须写明：优先级链、返回值语义、无待办时回落 `state.current_player_id`、本函数不做归属过滤。
- [ ] **A2** 新增私有纯查询 `_is_viewable_actor(player_id) -> bool`：角色存在、`alive`、非 `out_of_game`。
- [ ] **A3** 新增私有纯查询 `_is_delegated_to_local_human(player_id) -> bool`：
      `get_turn_input_delegate_id(player_id)` 等于本机真人影子身份（`_offline_human_identity_id`，缺失时回落 `_bound_local_player_id()`）。
- [ ] **A4** 新增私有纯查询 `_resolve_delegated_operator_id(controller_player_id, explicit_player_id := -1) -> int`：
      取 `_get_controlled_actor_ids_for_controller(controller_player_id)`；空 → `-1`；
      提示命中操控者且可显示 → 操控者；提示命中某个被操控者且可显示 → 该被操控者；否则首个可显示的被操控者；都不可显示 → `-1`。

**验证**：`--headless` 跑 `tests/turn_control_mechanism_test.tscn` 仍 PASS（此时无任何调用方，属纯增量）。

---

## 阶段 B：离线第一视角（核心修复）

- [ ] **B1** `_resolve_delegated_viewer_id()` 增加 `explicit_player_id := -1` 参数；主体改为：
      非离线 → `-1`；当前回合角色无登记或其操控者 ≠ 本机真人影子身份 → `-1`；
      否则 `return _resolve_delegated_operator_id(本机真人影子身份, explicit_player_id)`。
      **必须新增注释**说明「本机真人在操控期间同时操作自己与被操控者，因此返回值不再恒为被操控者」。
- [ ] **B2** `_prepare_offline_controlled_view()`：
      ① 在回合操控分支之前先算 `requested_operator_id = _resolve_pending_operator_hint(explicit_player_id)`；
      ② 把 `requested_operator_id` 传给 `_resolve_delegated_viewer_id()`；
      ③ 「控制所有角色」分支删除已搬迁的排序代码，改为直接使用 `requested_operator_id`；
      ④ 保留既有的接管影子值记录与 `_set_offline_manual_control_player()` 唯一落点。
- [ ] **B3** `_set_offline_manual_control_player()`：把「切走的非主角色无条件注册基础 AI」改为
      `if not _is_delegated_to_local_human(旧目标): ai_coordinator.register_basic_ai(旧目标)`，并写明理由注释。
- [ ] **B4** `_sync_controlled_player_input_source()`：删去 `and not _control_all_characters_enabled`，
      并更新该函数注释，说明「登记表明由本机真人操控 ⇒ 必须注销基础 AI，与该设置无关」。

**验证**：`tests/turn_control_mechanism_test.tscn`、`tests/control_all_characters_test.tscn` 仍 PASS。

---

## 阶段 C：局域网代理快照

- [ ] **C1** `_emit_state()` 逐 peer 循环：在发送普通快照后计算 `delegated_view_target_id = _resolve_delegated_operator_id(viewer_id)`；
      代理快照循环增加 `if controlled_actor_id != delegated_view_target_id: continue`。
- [ ] **C2** 更新该处注释：说明「目标是操控者本人时普通快照已表达同一视角，不再下发代理快照；授权列表仍照常下发」。

**验证**：`tests/lan_turn_control_test.tscn` 仍 PASS。

---

## 阶段 D：专项测试

- [ ] **D1** `tests/turn_control_mechanism_test.gd` 新增 `_test_delegated_view_follows_pending_operator()`（AC1/AC2/AC3/AC4/AC7）：
      建立登记 → 断言视角 = 被操控者 → 直接调用 `_controller.request_card_choice(操控者, ...)` 造出一条属于操控者的待办
      → 断言 `local_human_player_id == 操控者` 且 `is_ai_controlled(被操控者) == false`
      → 结算该请求 → 断言视角回到被操控者。
      设置开启时重复一次断言（AC7）。断言信息必须带实际观测值。
- [ ] **D2** `tests/turn_control_mechanism_test.gd` 新增 `_test_controller_responds_as_self_during_delegation()`（AC5）：
      照抄 `tests/response_choice_test.gd:83-124`：清空双方手牌，给被操控者一张【杀】、给操控者一张【闪】，
      `_start_turn(被操控者)` → `begin_turn_input_delegation(被操控者, 操控者)` → 提交【杀】指向操控者
      → 断言 `_pending_card_choice.chooser_id == 操控者` 且 `local_human_player_id == 操控者`
      → 提交【闪】→ 断言视角回到被操控者、阶段仍为 `play`。
      连接 `card_choice_requested` 捕获时**必须**按 `chooser_id == local_human_player_id` 判定（与界面同口径）。
- [ ] **D3** 把两个新用例登记进 `_run()` 的阶段列表（沿用既有 `TURN_CONTROL_STAGE` / `TURN_CONTROL_PASS` 输出格式）。
- [ ] **D4** `tests/lan_turn_control_test.gd` 新增 `_test_delegated_snapshot_view_target()`（AC8/AC9）：
      断言 `_resolve_delegated_operator_id(操控者)` 在无操控者待办时 = 被操控者；
      造出一条 `chooser_id == 操控者` 的待办后 = 操控者；
      并断言 `_get_controlled_actor_ids_for_controller(操控者)` 在两种情形下都仍为 `[被操控者]`（授权不随视角变化）。

---

## 阶段 E：文档同步

- [ ] **E1** `docs/游戏机制与玩法内容.md`：在「本回合由 xx 操控」条目补充「操控者同时操作自己与被操控者；第一视角在两人之间跟随当前待办请求（含响应窗口）」。
- [ ] **E2** `docs/内容制作指南.md`：更新 `:4229-4231` 的回合操控段落（离线视角解析入口、局域网代理快照取值语义）。
- [ ] **E3** `docs/架构说明.md`：更新回合操控与「控制所有角色」的关系说明（视角归属解析共用同一入口）。
- [ ] **E4** `docs/界面与交互.md`：更新第一视角与询问窗口的对应关系（`chooser_id == local_human_player_id` 的前提在操控期间同样成立）。
- [ ] **E5** `docs/网络通信.md`：更新 `turn_input_delegated_viewer_id` 的取值语义（= 当前操作者，可能等于操控者本人；此时不下发代理快照）。
- [ ] **E6** `README.md`：如新增测试场景则补充说明（本任务扩展既有场景，不需要新增条目；如确需说明则同步）。

---

## 验证命令

```powershell
$GODOT = "E:\Godot\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe"
& $GODOT --headless --path . res://tests/turn_control_mechanism_test.tscn
& $GODOT --headless --path . res://tests/lan_turn_control_test.tscn
& $GODOT --headless --path . res://tests/control_all_characters_test.tscn
& $GODOT --headless --path . res://tests/response_choice_test.tscn
& $GODOT --headless --path . res://tests/kafuka_mechanics_test.tscn
& $GODOT --headless --path . res://tests/smoke_test.tscn
& $GODOT --headless --path . res://tests/gameplay_regression_test.tscn
& $GODOT --headless --path . res://tests/phase_progression_test.tscn
```

判定标准：退出码 0 + 输出自身 PASS 标记 + 日志无 `ERROR` / `SCRIPT ERROR` / `FAIL`。

---

## 评审门与回滚点

| 门 | 位置 | 判据 |
|---|---|---|
| RG1 | 阶段 A 后 | 既有专项仍 PASS（纯增量，无行为变化） |
| RG2 | 阶段 B 后 | `turn_control_mechanism_test` + `control_all_characters_test` PASS（视角链路未被破坏） |
| RG3 | 阶段 C 后 | `lan_turn_control_test` PASS（代理协议未被破坏） |
| RG4 | 阶段 D 后 | 两个新增用例 PASS，且**在回滚核心修复后必须失败**（证明用例真的覆盖缺陷） |
| RG5 | 阶段 E 后 | 六份文档与代码逐字一致 |

回滚点：任一门失败即 revert 对应阶段的改动；阶段 A/B/C 相互独立，可分级回滚。
