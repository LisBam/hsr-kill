# 执行计划：中央区展示牌被获得时先入弃牌堆再飞向获得者

> 依赖顺序：步骤 1 → 2 → 3 →（4 与 5 可并行）→ 6 → 7 → 8。
> 每步完成后先自检再进入下一步；步骤 6 的测试必须先失败/先暴露旧口径，再按新口径改写。

## 步骤 0：基线确认（开工前）

- [ ] `git status` 干净、记录当前 HEAD，确认回退基准提交为 `5e07e96`。
- [ ] 跑一次 6 套基线回归，记录改动前的通过状态，作为回归对照。

## 步骤 1：动画层新增「中央牌面落位通知」（`scripts/ui/card_use_animation_layer.gd`）

- [ ] 顶部状态区新增 `_pending_active_card_landings`（UID → 回调），按项目规范逐行中文注释说明键的选择理由。
- [ ] 新增 `request_active_card_landing(card_uid, on_landed) -> Dictionary`，返回 `{accepted, position}`。
- [ ] 新增 `cancel_active_card_landing(card_uid) -> bool`。
- [ ] 新增私有 `_bind_active_card_landing(card_view)`、`_on_active_card_motion_finished(card_instance_id)`、`_complete_active_card_landing(card_instance_id)`。
- [ ] `_start_card_motion()` 末尾补一次 `_bind_active_card_landing()`：队列补位替换补间后，落位必须跟随最新那条补间。
- [ ] `_detach_presented_card()` 清掉该 UID 的等待登记。
- [ ] `clear_presentations()` 清空 `_pending_active_card_landings`。
- [ ] 自检：接口命名与既有 `take_over_active_card()` / `consume_discard_transfer_claim()` 风格一致；没有新增第二套飞行动画函数。

## 步骤 2：桌面本机获得路径改为「等待落位后取走」（`scripts/ui/match_table.gd`）

- [ ] `_play_local_hand_gain_flight()`：先申请落位通知；`accepted=true` 时登记等待门闸（`card=null`、`origin=` 该牌此刻中心、`awaiting_landing=true`）并返回，不再当帧取牌。
- [ ] `accepted=false` 时保持原有立即路径，并在门闸里写入 `awaiting_landing=false`。
- [ ] 新增 `_on_central_display_card_landed(card_uid)`：门闸缺失/已取消 → 直接返回；牌面取不到 → 解闸落位；取到 → 回写 `card`/`origin`、清等待标记、调用 `_start_pending_local_hand_gain_flights()`。
- [ ] 更新 `_play_local_hand_gain_flight()` 的文档注释：说明「先进入弃牌堆、再飞向获得者」的两段口径与等待期间的门闸状态。
- [ ] 自检：没有改动 `_try_take_card_origin()` 的解析优先级，没有改动 `_should_show_card_back()` 口径。

## 步骤 3：门闸机制适配等待状态（`scripts/ui/match_table.gd`）

- [ ] `_hold_gated_local_hand_entries()`：起点保持条件放宽为「已起飞或正在等待中央落位」。
- [ ] `_start_pending_local_hand_gain_flights()`：增加等待落位早退，且**不**释放等待中的门闸。
- [ ] `_cancel_pending_local_hand_gain_flight()`：等待落位时先撤销动画层的落位通知。
- [ ] `_render_local_hand()` 门闸对账：撤销过期门闸改为经 `_cancel_pending_local_hand_gain_flight()`，保证通知与门闸同批回收。
- [ ] `_clear_local_hand_gain_animations()`：遍历门闸键，逐个撤销仍在等待的落位通知。
- [ ] 自检：`_local_hand_gain_flight_gates` 的既有字段名与注释未被改名或删除，只新增 `awaiting_landing`。

## 步骤 4：桌面其他角色获得路径统一为两段（`scripts/ui/match_table.gd`）

- [ ] `_on_card_transfer_requested()` 非本机分支：解析完起点/终点/牌背后，在 `not show_card_back` 时申请落位通知，`accepted=true` 直接返回（当帧不新建牌面）。
- [ ] 新增 `_on_central_display_card_transfer_landed(card_uid, target_position)`：取走队列中同一牌面并 `play_transfer()` 飞向捕获的终点；取不到则放弃本次表现。
- [ ] 自检：`accepted=false` 时新建立即路径与改动前逐行等价（`draw_stack_key` 公式、`_forget_taken_over_hand_card()`、牌背配置都不变）。

## 步骤 5：回归测试改写与扩展（`tests/ui_layout_test.gd`）

- [ ] 改写 `continuity_takeover_*` 段落为两段断言（申请 → 等待期间快照 → 落位接管 → 落地），覆盖 AC1/AC2/AC3/AC5。
- [ ] 新增其他角色获得路径的两段断言（AC4）：起点为落位中心、终点为获得者武将牌锚点、同 UID 牌面只有一张。
- [ ] 新增等待期间取消路径断言（AC6）：落位通知被撤销、门闸被清空、牌仍留在中央队列。
- [ ] 保留 `accepted=false` 的原有行为断言（AC7）。
- [ ] 自检：新断言不依赖硬编码坐标，全部从既有公开入口（`_get_player_indicator_position()`、`_get_local_hand_card_slot_center()`、容器槽位）反推。

## 步骤 6：跑测试并修复

- [ ] `ui_layout_test`（先单跑，最快暴露断言问题）。
- [ ] `virtual_hand_choice_test`、`draw_sequence_test`、`match_replay_test`、`gameplay_regression_test`、`smoke_test`。
- [ ] 检查日志：不允许 `ERROR` / `SCRIPT ERROR` / `FAIL`；退出码必须为 0。
- [ ] 如出现与本改动无关的既有失败，记录证据后单独说明，不掩盖。

## 步骤 7：文档与规范同步

- [ ] `docs/界面与交互.md`：中央展示牌被获得的表现改为两段口径（含弃牌区落位、本机/他人终点、等待期间门闸保持）。
- [ ] `docs/卡牌系统.md`、`docs/游戏机制与玩法内容.md`：记录「进入弃牌堆后才被获得」的表现顺序与涉及的具体时长数值（0.42 秒飞行、0.18 秒队列补位、0.48 秒停留）。
- [ ] `docs/内容制作指南.md`：把「获得中央展示牌」的表现接口沉淀为可复用条目（哪些接口、什么时序保证）。
- [ ] `README.md`：核对测试场景清单是否需要补充（若新增测试场景则补）。
- [ ] `.trellis/spec/ui/component-patterns.md`：改写「中央展示牌被获得」条目为落位后取走口径，并在「常见错误」中补一条「在牌面飞抵中央队列之前就取走它」的预防条目。
- [ ] 自检：代码注释保持永久性口径，没有写入单次更新说明。

## 步骤 8：收尾

- [ ] 输出「学习反馈摘要」（修改思路 / 架构与设计 / Bug 原因与修复方法 / 关键代码解析 / 学习要点提炼）。
- [ ] 输出编号 Git 提交描述（每行一个独立动作）。
- [ ] 把两者以 `YYYY-MM-DD HH:MM` 时间戳追加到 `临时反馈文档.md` 末尾。
- [ ] 提交代码，并归档 Trellis 任务。
- [ ] 向用户汇报：回退了什么、新实现是什么、测试结果、自主决定的问题清单。
