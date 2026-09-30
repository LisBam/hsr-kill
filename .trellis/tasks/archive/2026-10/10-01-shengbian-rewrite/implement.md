# 执行计划：按新原文改写升变

## 步骤

1. **先改测试基线**：跑 `tests/omphalos_transform_test.tscn` 与 `tests/reincarnation_mechanics_test.tscn` 记录当前通过状态，避免把既有失败误判为本次引入。
2. **技能实现**（`game_data/skills/shengbian.gd`）：
   - 顶部新增 `MILITARY_MERIT_GAIN_PER_ACTIVATION`、`MILITARY_MERIT_TOTAL_CAP` 常量（注释含用途/取值范围/修改影响）；
   - `description` 逐字替换为新原文；
   - 移除轮回技相关元数据与轮回数逻辑（X、至多5枚）；
   - 结算改为“无军功→先清空全场军功；然后按 `clamp(8 − 当前, 0, 2)` 给予”；
   - 清场分支同步撤销军功来源动态授予的【奇袭】；
   - AI 目标评分补全：处理“已满8枚收益为0”“清场会损失我方其他角色军功”“全部目标无收益则取消”。
3. **关联技能核查**（`game_data/skills/qixi.gd`）：确认升变不再被判为轮回技，且奇袭不因升变产生任何登记；军功归零者的动态【奇袭】被撤销。
4. **加载期校验**：确认去掉轮回技标签后无双向校验报错（启动一次 `tests/smoke_test.tscn` 即可覆盖技能注册校验）。
5. **测试改写**：按 `design.md` 第4节重写 `_test_shengbian_qixi_and_kansha`，并检查 `tests/reincarnation_mechanics_test.gd` 中是否有依赖升变的断言。
6. **文档同步**：`docs/游戏机制与玩法内容.md`、`docs/内容制作指南.md`、`docs/AI模块.md`、`README.md` 中所有“升变=轮回技/按X截断/至多5枚/2→4→10”的表述改写为新规则，并记录数值（每次+2、总数封顶8）。

## 验证命令

```powershell
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/omphalos_transform_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/reincarnation_mechanics_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/smoke_test.tscn
& 'E:\Godot\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe' --headless --path . --scene res://tests/conquest_single_player_test.tscn
```

## 完成条件

- PRD 中 8 条验收标准全部满足；
- 上述四个场景通过；
- 文档同步完成，`临时反馈文档.md` 追加本次学习反馈与分点提交描述。
