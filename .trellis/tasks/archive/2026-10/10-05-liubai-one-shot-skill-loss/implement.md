# 实施记录 · 留白改为一次性失去当前技能并新增通用失去技能端口

任务目录：`.trellis/tasks/archive/2026-10/10-05-liubai-one-shot-skill-loss/`
父任务：`10-04-kafuka-followup-fixes`
提交：`4aca7ce`（状态层+核心层+内容层+界面层+专项回归）、`cb7ceb9`（五篇文档）、`509fb39`（两篇规范）、`59862ec`（界面收敛断言）

## 一、核心改动 · 用「一次性移除」替换「技能ID名单」

| 文件 | 改动 |
|---|---|
| `scripts/data/player_state.gd` | 删除 `permanently_removed_skill_ids`、`skills_permanently_removed` 两个字段与其 `to_dict` / `from_authoritative_dict` 往返；删除 `mark_skill_permanently_removed()` 与 `has_permanently_removed_skill()` 两个端口 |
| `scripts/core/match_controller.gd` | `remove_all_skills_permanently()` 删除，替换为通用 `remove_skill(player_id, skill_id, reason)` 与批量 `remove_all_skills(player_id, reason)`；`_install_all_character_skills()` 改为接收 `saved_installed_skill_ids_by_player`（缺键=完整装配）并删除旧布尔迁移；`_reinstall_character_skills_for_player()`、`grant_acquired_skill()`、`_reinstall_saved_runtime_skills()`、`restore_character_card_skills()` 四处按技能ID的拦截全部删除；`_append_limited_skill_usage_to_snapshot()` 补充 `installed_skill_ids`；`_build_conquest_save_data()` 写出 `installed_skill_ids`，读档循环组装 `saved_installed_skill_ids_by_player` |
| `game_data/skills/liubai.gd` | 结束阶段改调 `remove_all_skills(owner_player_id, CLEAR_REASON)`，注释口径由“永久失去”改为“一次性失去” |
| `game_data/skills/shengbian.gd` | 军功估值的技能来源改读快照 `installed_skill_ids`（缺字段时不裁剪） |
| `scripts/ui/match_table.gd` | `_get_visible_skill_ids()` 按 `installed_skill_ids` 裁剪固有与模式技能；缺失定义的技能保留占位不裁剪；缺少该字段时整体不裁剪 |
| `scripts/ui/player_target_view.gd` | 变更检测列表与 `_request_character_information()` 的技能集合均改读 `installed_skill_ids` |
| `tests/nakexia_mechanics_test.gd` | 三个阶段重写为 `_test_liubai_one_shot_skill_loss()` / `_test_skill_loss_leaves_install_paths_intact()` / `_test_save_roundtrip_skill_loss()`，新增 `_test_ui_filter_follows_installed_skills()` 与快照查询辅助 `_get_snapshot_player()` |

**接口契约**：

- `remove_skill(player_id, skill_id, reason)` 是「失去某个技能」的唯一通用入口。执行顺序为「定位玩家 → 取实例表 → 卸载实例（释放时机订阅、持续标记与查询修正器）→ 从实例表移除 → 清空 `acquired_skills` / `temporary_skills` 记录 → 经 `ReincarnationSkillService.clear_skill_state()` 清理轮回公开状态 → 写日志 → 广播」。既无实例也无记录时返回 `false` 且不写日志不广播，因此调用方不需要前置判空。
- `remove_all_skills(player_id, reason)` 是批量入口：先快照当前技能ID（实例表键 ∪ 获得记录键 ∪ 临时记录键，按稳定ID去重）再逐个走同一通用接口，最后清空 `reincarnation_skills` 与 `recorded_card_names`；快照为空时返回 `false`。
- **不写任何持久状态**：失去是一次性事实，装配路径不再做任何按技能ID的拦截，之后同一技能可由机缘卡、军功、复原武将牌或换将重新获得并照常安装与发动。
- 与既有 `remove_acquired_skill()` 的分工：后者只清除“获得记录”，在固有/模式/临时来源仍提供同一技能时**保留实例**（用于次数额度到期），不适用于“把技能拿走”。

## 二、存档口径

| 场景 | 行为 |
|---|---|
| 新存档 | 为每名玩家写出 `installed_skill_ids`（存档那一刻实际安装的技能集合） |
| 读档（含该字段） | `_install_all_character_skills(saved_installed_skill_ids_by_player)` 只装配记录内技能，因此失去的技能不会因一次存读档而复活 |
| 读档（缺该字段） | 该玩家无条目 → 按武将固有技能 + 模式技能完整装配，与改动前完全一致（新开局同样无条目） |

## 三、界面收敛

- 收敛依据从“谁被拉黑过”改为“现在实际装着什么”：`installed_skill_ids` 由 `get_installed_skill_ids()` 从技能实例表派生，随每次广播下发；失去技能会卸载实例，列表随之收缩，界面自动不再显示。
- 三处消费点：技能栏按钮（`MatchTable._get_visible_skill_ids()`）、悬停武将资料与右键武将详情（`PlayerTargetView._request_character_information()`，两者共用同一份 `description_sections`）。
- 兼容：快照缺少该字段时不做裁剪；技能声明中缺失定义的条目保留占位，便于发现配置错误。
- 角标不受影响：`character_corner_text_entries` 不携带技能归属，技能声明的角标仍由各技能 `uninstall()` 自行移除，记录牌名由 `remove_all_skills()` 清空。

## 四、验证

- 定向子集 17 个场景全部 PASS（`.godot_test_logs/skill_loss_subset.txt`）：`omphalos_transform`、`tingyun_mechanics`、`daheita_mechanics`、`kafuka_mechanics`、`reincarnation_mechanics`、`conquest_save`（含 `resume_skills`）、`conquest_single_player`、`corner_badge`、`leader_skill`、`skill_target_ui`、`ui_layout`、`match_replay`、`new_character_mechanics`、`rule_timing`、`lan_match_flow`、`ai_policy`、`smoke`
- 专项复跑：`NAKEXIA_MECHANICS_PASS … one_shot_loss=2 regrant_new_skill=1 regrant_lost_skill=1 ui_filter=3`
- 界面断言直接覆盖需求第四条：`PlayerTargetView` 实例化真实场景后，`installed_skill_ids` 不含的技能不出现在 `description_sections` 中，重新获得后立即恢复
- 全量 82 个测试场景连跑（`.godot_test_logs/full_regression_one_shot.txt`）：**82/82 全部通过、零 `_FAIL`**，81 条 `_PASS` 标记 + 1 条 `ANDROID_ADAPTATION_TEST_OK`，其中包含整批连跑中偶发失败的 `audio_system_test`（本次 `AUDIO_SYSTEM_PASS`）
- 文档同步：`docs/游戏机制与玩法内容.md`、`docs/架构说明.md`、`docs/界面与交互.md`、`docs/内容制作指南.md`、`docs/AI模块.md`、`README.md`；规范同步：`.trellis/spec/guides/code-reuse-thinking-guide.md`（模式 5 重写为“不要把一次性移除写成需要长期维护的持久状态”）、`.trellis/spec/core/layering-and-state.md`

## 五、遗留

- 旧存档中已写入的 `permanently_removed_skill_ids` 字段被读档逻辑静默忽略（`from_authoritative_dict` 不再读取），表现为“这些技能随读档重新装配”；这是需求方明确要求“不做后期维护”的必然结果，未再加迁移代码。
- 其他“失去技能”类效果的接入点尚未出现，`remove_skill()` 目前只有【留白】经 `remove_all_skills()` 间接使用。
