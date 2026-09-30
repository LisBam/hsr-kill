# 执行计划：修复额外出牌节点下堪杀触发奇袭导致的对局卡死

## 步骤

1. **保留复现证据**：跑 `tests/_repro_kancha_qixi.tscn`（六组场景），确认“让出12帧后 `_deferred_skill_settlements` 仍为1、手工调用一次 `_resume_settlement_pipeline()` 立刻排空”。
2. **通用层修复**（`scripts/core/match_controller.gd`）：
   - 新增私有判定 `_has_unresolved_settlement_work()`（详见 `design.md` 第3节）；
   - 在 `_resume_settlement_pipeline()` 的同步排空结束处补登记唯一延后唤醒；
   - 修正 `defer_skill_settlement()` 第11571-11573行的注释，说明活跃性责任归属，不改变其调度条件以外的最小行为。
3. **重跑复现**：确认六组场景的 `deferred` 在自然让帧后归零，且奇袭的轮回节推进真实生效（不需要手工调用管线）。
4. **正式回归**：把复现收敛成正式用例（建议落在 `tests/new_character_mechanics_test.gd` 的秘策相关区段，或复用 `tests/skill_settlement_runtime_test.gd` 的管线断言风格）：
   - 秘策额外出牌阶段 + 堪杀①/②/③ + 奇袭达到重置阈值；
   - 断言让帧后 `_deferred_skill_settlements` 为空、轮回节按规则变化、额外出牌阶段正常收尾、控制权回到秘策持有者结束阶段。
5. **清理**：删除 `tests/_repro_kancha_qixi.gd` / `.tscn`。
6. **文档同步**：`docs/内容制作指南.md`（统一结算管线与延后唤醒的活跃性约定）、`docs/游戏机制与玩法内容.md`（额外出牌阶段条目）、`docs/架构说明.md`（若涉及管线说明段落）、`README.md`（测试清单）。

## 验证命令

```powershell
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/skill_settlement_runtime_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/stall_watchdog_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/new_character_mechanics_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/omphalos_transform_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/phase_progression_test.tscn
```

通过标准：退出码 0 且打印对应 `*_PASS` 行。

## 完成条件

- PRD 中 4 条验收标准全部满足；
- 上述五个既有场景不回归（尤其是管线/停滞看门狗相关场景）；
- 文档同步完成，`临时反馈文档.md` 追加本次学习反馈与分点提交描述。
