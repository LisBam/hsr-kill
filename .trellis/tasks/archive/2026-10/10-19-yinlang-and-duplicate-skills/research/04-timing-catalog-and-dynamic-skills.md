# 调研 04 · 时机目录、动态技能与准备阶段

调研范围：运行时组合技能所需的「时机系统」「技能动态描述/名称」「准备阶段与游戏开始时」「锁定技语义」「每回合限一次」「武将注册」。
结论均为只读调研，含可复核的文件与行号。

---

## 1. 是否存在运行时定义/组合技能的机制？

**不存在。**

`GameDatabase.create_skill(skill_id)`（`scripts/autoload/game_database.gd:248-253`）只在 `skill_scripts` 字典里查脚本：

```gdscript
func create_skill(skill_id: String) -> SkillDefinition:
	var skill_script: Script = skill_scripts.get(skill_id) as Script
	if skill_script == null:
		return null
	return skill_script.new() as SkillDefinition
```

- `skill_scripts`（`game_database.gd:66`）只由 `_load_skills()`（`:345-391`）填充：扫描 `res://game_data/skills`（`SKILLS_DIRECTORY`，`:19`），逐个 `.gd` 实例化后按 `definition.get_id()` 建键（`:391`）。**文件名不影响 ID**，只要求符合 `[a-z0-9_]+`（`_list_gd_scripts`，`:470-494`，错误在 `:492`）。
- **没有 `GameDatabase.register_skill()`**。全项目唯一在运行时写 `GameDatabase` 字典的地方是测试（`tests/reincarnation_mechanics_test.gd:132,137` 写 `GameDatabase.characters["wandi"]` 后还原）。
- `GameDatabase.get_skill(id)`（`:168-169`）对未知 ID 返回 `{}`。

### 唯一存在的运行时组合钩子（仅元数据）

`game_data/skill_definition.gd:99` —— 基类构造函数接受完整元数据字典：

```gdscript
func _init(metadata: Dictionary = {}) -> void:
	_metadata = metadata.duplicate(true)
```

因此 `SkillDefinition.new({"id":"x","name":"Y","description":"Z","lock":true})` 能得到一个可用实例。**但** `install()` 是 `pass`（`:673-674`），没有按实例的回调表，这种实例订阅不了任何时机、也反应不了任何事件。

17 处 `SkillDefinition.new(...)` 全部在测试中：`tests/haiseyin_mechanics_test.gd:244,264`、`tests/reincarnation_mechanics_test.gd:146,160,171,299`、`tests/ahha_moment_test.gd:168,172,176,180,184,269`、`tests/rule_timing_test.gd:147,149,193`、`tests/health_mechanics_test.gd:80`、`tests/skill_choice_test.gd:71`。

### 存在的运行时能力（都按静态 ID 工作）

- **授予技能**：`match_controller.gd:10295-10327` `grant_acquired_skill(...)` → `GameDatabase.create_skill`（`:10306`）→ **拒绝重复 ID**（`:10302-10304`，日志「已经拥有【%s】，本次获得未重复安装」）→ 写 `player.acquired_skills[skill_id]`（`:10313-10323`）→ `skill.install()`（`:10324`）。
- `grant_temporary_skill`（`:10408-10425`）、`remove_acquired_skill`（`:10382-10404`）、`get_installed_skill_ids`（`:10563-10570`）、`has_skill`（`:10582-10595`）。
- **给其他角色授予技能的先例**：`game_data/skills/lingfu.gd:246` `host.call("grant_acquired_skill", target_id, MEIZHAN_SKILL_ID, 0, 0, GRANT_SOURCE)`；另见 `shengbian.gd:134`。
- 机缘系统只授予**静态** ID：`scripts/opportunity/opportunity_catalog.gd:43-59` → `opportunity_effect_resolver.gd:78-80`。
- **描述覆盖存在**：`PlayerState.dynamic_skill_descriptions`（`player_state.gd:78`，公开，序列化于 `:559`、恢复于 `:336`）+ `match_controller.gd:17768-17778` `set_skill_display_description(player_id, skill_id, description)`。使用先例：`duanjie.gd:280-286`。

### 每局运行时元数据注册表的先例（不是定义注册表）

`scripts/core/reincarnation_skill_service.gd:58-93` `register_skill(player_id, skill_id, metadata)` —— 按技能 ID 写入 `player.reincarnation_skills`。最接近「运行时元数据存储」的架构先例，但存的是**进度**，且技能 ID 必须已存在。

**结论**：项目有「运行时授予静态技能」与「运行时覆盖描述」，但**没有运行时组合技能定义**。

---

## 2. 描述 / 名称解析

### `SkillDefinition`
- **没有 `get_description()`**。文本在 `_metadata["description"]`，经 `get_metadata()`（`:142-143`，返回深拷贝）与 `get_id()`（`:147-148`）暴露。
- `lock` / `limited` / `half_locked` / `awakening` / `reincarnation` / `joy_skill` 在 `_init`（`:99-138`）归一化后写回 `_metadata`。
- `_metadata` 是普通 `var`（`:32`），可直接写，但运行时无人这么做。

### UI 链 —— 名称**永远**读静态库

| 位置 | 表达式 |
|---|---|
| `scripts/ui/character_skill_display.gd:80` | `var skill_definition: Dictionary = GameDatabase.get_skill(skill_id)` |
| `character_skill_display.gd:82` | `str(skill_definition.get("name", skill_id))` ← **名称** |
| `character_skill_display.gd:99-102` | `resolve_skill_description()`：`dynamic_descriptions.get(skill_id, skill_definition.get("description", FALLBACK))` ← 唯一的动态路径 |
| `character_skill_display.gd:109` | `build_skill_title()` 名称再次读库 |
| `scripts/ui/skill_button_view.gd:84/94/95` | `skill_id`；`str(definition.get("name", skill_id))`；短名 = 前 2 字 |
| `scripts/ui/match_table.gd:2191/2226-2228/2244` | `GameDatabase.get_skill(skill_id)`；未知 ID → `{"id":skill_id,"name":skill_id,"description":"技能元数据尚未登记。"}`；`skill_button.configure(...)` |
| `match_table.gd:2257-2260` | `_resolve_skill_dynamic_description()` → `dynamic_skill_descriptions.get(skill_id, "")` |
| `match_table.gd:2314-2331` | `_get_visible_skill_ids()`，`:2328` 用库查 `leader_skill` 过滤 |

`collect_visible_skill_ids()`（`character_skill_display.gd:30-58`）→ `SkillDefinition.collect_snapshot_skill_ids`（`skill_definition.gd:305-342`）：native（`character.skills`）+ `mode_skill_ids` + `temporary_skills` 键 + `acquired_skills` 键。

**结论**：运行时实例**可以**自定义描述（`set_skill_display_description`，支持 `[s]…[/s]`），**不能**自定义名称——合成 ID 会显示为原始 ID（按钮上是前 2 字、标题是【原始ID】）。

> **本任务的应对**：不引入合成技能 ID。把「进程」「缺陷」做成**静态脚本**，名称来自静态元数据，正文由实例级描述覆盖，行为由静态脚本读实例配置分派。

---

## 3. 时机系统

`scripts/core/rule_timing_catalog.gd` 全部标识符分组：

| 组 | 行 | 内容 |
|---|---|---|
| `GAME_PHASE_TIMINGS` | 10-19 | `enterGame, gameDrawBefore, gameDrawBegin, gameDrawAfter, gameStart, roundEnd, roundStart, phaseBefore, phaseBeforeStart, phaseBeforeEnd, phaseBeginStart, phaseBegin, phaseChange, phaseEnd, phaseAfter, phaseOver, phaseCancelled`，以及 `phaseZhunbei/phaseJudge/phaseDraw/phaseUse/phaseDiscard/phaseJieshu` 各自的 `…Before, …Begin, (…), …End, …After, …Cancelled, …Skipped`；摸牌额外有 `phaseDrawBegin1/phaseDrawBegin2` |
| `CARD_RESPONSE_TIMINGS` | 22-31 | `chooseToUse*`、`chooseToRespond*`、`useCardBefore/Begin/0/1/2/useCard/End/After/Cancelled`、`useCardTo*`、`useCardToPlayer/Playered/Target/Targeted`、`respond*`、`eventNeutralized`、`yingbian*`、`shaBefore/Begin/Hit/Miss/Damage/End/After/Cancelled`、`juedou*`、`huogongBegin`、`taoBegin`、`wuguRemained` |
| `DAMAGE_TIMINGS` | 34-37 | `damageBefore, damageBegin, damageBegin1..4, damage, damageZero, damageSource, damageEnd, damageAfter, damagePoint*, damageCancelled` |
| `HEALTH_STATE_TIMINGS` | 40-51 | `changeHp`、`recover*`、`loseHp*`、`gainMaxHp*`、`loseMaxHp*`、`changeHujia*`、`dying*`、`die*`、`link*`、`turnOverBefore/End/After` |
| `CARD_MOVE_TIMINGS` | 54-68 | `gain*`、`lose*`、`loseAsyncEnd/After`、`discard*`、`cardsDiscardEnd/After`、`loseToDiscardpileAfter`、`cardsDiscardedBatchAfter`、`cardsGainedBatchAfter`、`draw*`、`equip*`、`disableEquip*`、`enableEquipAfter`、`addJudge*`、`disableJudge*`、`enableJudgeAfter`、`addToExpansionEnd/After` |
| `JUDGE_COMPARE_TIMINGS` | 71-74 | `judge*`、`chooseToCompareBegin/After`、`compare`、`compareMultipleAfter` |
| `CHOICE_TIMINGS` | 77-81 | `chooseBoolBegin`、`chooseButtonBegin`、`chooseCardBegin`、`chooseCardTargetBegin`、`chooseControlBegin`、`choosePlayerCardBegin`、`chooseTargetBegin`、`chooseToDiscardBegin`、`chooseToGiveBegin`、`chooseToMoveBegin`、`gainPlayerCardBegin`、`discardPlayerCardBegin`、`rewriteDiscardResult`、`rewriteGainResult` |
| `SKILL_TIMINGS` | 84-86 | `logSkillBegin`、`logSkill`、`useSkillBegin`、`useSkill`、`useSkillAfter`、`skillAfter`、`triggerInvisible`、`triggerAfter` |
| `REINCARNATION_TIMINGS` | 89-91 | `reincarnationStart/End`、`reincarnationSectionStart/End` |
| `MODE_TIMINGS` | 94-96 | `changeSkillsAfter`、`removeCharacterBefore/End`、`hideShownCardsAfter`、`zhuUpdate`、**`washCard`** |

- `ACTIVE_ENTRIES`（`:99`）= `["phaseUse","chooseToUse","chooseToRespond","chooseCard"]`
- `MAIN_PHASES`（`:102`）= `["judgment","draw","play","discard"]`（**准备阶段不在其中**）
- `MAIN_PHASE_TIMING_PREFIXES`（`:105-110`）；`get_main_phase_timing_name("zhunbei", …)` 返回 `""`
- `has_timing()`（`:131-132`）、`has_active_entry()`（`:136-137`）、`is_main_phase()`（`:141-142`）

### ⚠️ `washCard` 是陷阱

`washCard` 在目录里（`:95`），但 `match_controller.gd:16654` 只调用 `_record_runtime_event("washCard", ...)`，**从不 `_emit_rule_timing`** → **不可订阅**。不要为它写订阅。

### role 语义

`scripts/core/trigger_manager.gd:10` `VALID_ROLES = ["player","source","target","global"]`

`_matches_role()`（`:358-373`）：

```gdscript
if role == "global": return true
var owner_player_id: int = int(entry.get("owner_player_id", -1))
if owner_player_id < 0: return false
if role == "player": return owner_player_id == event.player_id
if role == "source": return owner_player_id == event.source_id
if role == "target": return owner_player_id == event.target_id
```

排序（`:85-114`）：firstDo/lastDo 分组 → priority 降序 → 距 `start_player_id` 的座次距离 → 注册序号。`subscribe()` 在 `:45-65`。

### 订阅入口

`skill_definition.gd:622-631`：

```gdscript
func subscribe_timing(event_name: String, callback: Callable, role: String = "player", priority: int = 0, first_do: bool = false, last_do: bool = false, condition: Callable = Callable(), locked_segment: bool = false, maintenance: bool = false) -> int:
	if host == null or host.get("trigger_manager") == null or not RuleTimingCatalog.has_timing(event_name):
		return -1
	var manager: TriggerManager = host.get("trigger_manager") as TriggerManager
	var guarded_condition: Callable = Callable(self, "_can_receive_timing_event").bind(condition, _bound_character_generation, locked_segment, maintenance)
	var guarded_callback: Callable = Callable(self, "_dispatch_timing_callback").bind(callback)
	return manager.subscribe(event_name, self, guarded_callback, priority, owner_player_id, role, first_do, last_do, guarded_condition)
```

守卫 `_can_receive_timing_event`（`:640-669`）：代次匹配 → 持有者存活/离场 → `can_use_effect(locked_segment)` → **获得技能额度** → 自定义条件。

> ⚠️ `:665` 的额度门禁读 `owner.acquired_skills.has(get_id())`。多实例改造后必须改用 `get_instance_key()`，否则重复实例会绕过额度。

### 最小「当你受到伤害后」技能全文范例

`game_data/skills/huanying.gd`（64 行）—— 见文件本体；要点：`_init` 写 `lock:true` + 逐字 `description`；`install()` 里 `subscribe_timing("damageAfter", _on_owner_damaged, "target")` 与 `subscribe_timing("phaseAfter", …, "global")`；回调里 `announce_activation({...})` 后直接执行效果。

---

## 4. 准备阶段

**存在**，即标准六阶段中的 `phaseZhunbei`。

- 时机 ID：`rule_timing_catalog.gd:13` → `phaseZhunbeiBefore, phaseZhunbeiBegin, phaseZhunbei, phaseZhunbeiEnd, phaseZhunbeiAfter, phaseZhunbeiCancelled, phaseZhunbeiSkipped`
- **不在 `MAIN_PHASES`**（`:102`），也没有 `MAIN_PHASE_TIMING_PREFIXES` 条目 → `get_main_phase_timing_name("zhunbei", …)` 返回 `""`；它是手写路径。
- 入口：`scripts/core/turn_start_service.gd:153-154`

```gdscript
_host._record_runtime_event("phaseZhunbei", "phase", {"player_id":player_id}, {}, turn_event_id)
_host._begin_phase_lifecycle("phaseZhunbei", player_id, {"turn_number":_host.state.turn_number}, turn_event_id, Callable(_host, "_run_preparation_phase_body").bind(player_id), Callable(_host, "_continue_turn_after_preparation_phase").bind(player_id))
```

- 显示名：`match_controller.gd:360` `"phaseZhunbei": "准备阶段"`
- 主体：`match_controller.gd:12408-12426`

### 准备阶段先例

`game_data/skills/bahu.gd:19-26`：

```gdscript
func install() -> void:
	subscribe_timing("phaseZhunbeiBegin", _on_phase_zhunbei_begin, "player")

func _on_phase_zhunbei_begin(_event: RuleEvent) -> void:
	announce_activation({})
	host.call("draw", owner_player_id, 1)
```

其他：`jiahu.gd:28`、`feiyan.gd:56`、`xingqi.gd:29`、`zhuijian.gd:37`。

测试驱动方式：`_controller._emit_rule_timing("phaseZhunbeiBegin", 0, 0, -1)`（`tests/card_timing_sequence_test.gd:127`）或 `_begin_phase_lifecycle("phaseZhunbei", ...)`（`tests/new_character_mechanics_test.gd:1501`）。

---

## 5. 游戏开始时

- 时机 ID `gameStart`（`rule_timing_catalog.gd:11`）；位置见 `:8-9` 注释：起始手牌 + 手气卡之后、第 1 轮之前。
- **权威派发点**：`match_controller.gd:11593-11601` `_complete_pre_game_start()`

```gdscript
state.current_phase = "game_start"
_record_runtime_event("gameStart", "mode", {"player_count":state.players.size()})
_emit_rule_timing("gameStart", -1, -1, -1, {"player_count":state.players.size()})
```

三个 ID 全为 `-1` → **只有 `role="global"` 能收到**。

- `_emit_rule_timing(...)` 定义在 `match_controller.gd:17887-17890`。
- 技能安装更早（`_install_all_character_skills`，`:10952-10987`），所以 `gameStart` 一定在安装之后。

### 范例

`game_data/skills/chouma.gd`（68 行）—— `lock:true` + `subscribe_timing("gameStart", _on_game_start, "global")`（`:40`，带注释说明为何必须 global）+ `_applied` 幂等标记（`:24`、`:45`、`:51`）。
另一例：`game_data/skills/yanling.gd`（卡芙卡【言灵】，往摸牌堆插入 5 张牌）。

---

## 6. 锁定技

**声明**：`super({... "lock": true ...})`。范例 `bahu.gd:13`、`huanying.gd:16`、`chouma.gd:32`。刻律德菈【征服】因「锁定技」出现在正文中间而显式写 `"lock": true`（`docs/内容制作指南.md:4473`）。

**归一化**：`skill_definition.gd:103-113`

```gdscript
awakening = bool(_metadata.get("awakening", false)) or description.contains("觉醒技")
limited = bool(_metadata.get("limited", false)) or description.contains("限定技") or awakening
lock = bool(_metadata.get("lock", false)) or awakening
_metadata["lock"] = lock
var locked_label_index: int = description.find("锁定技")
half_locked = bool(_metadata.get("half_locked", not lock and locked_label_index > 0))
```

**语义只有两条**：

1. **免疫「非锁定技失效」** —— `skill_definition.gd:575-580`

```gdscript
func can_use_effect(locked_segment: bool = false) -> bool:
	var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.get("state") != null else null
	if owner == null or not owner.non_locked_skills_disabled:
		return true
	return lock or (half_locked and locked_segment)
```

状态由 `match_controller.gd:10201-10218` `set_non_locked_skills_disabled(...)` 写入（多来源）；`PlayerState.non_locked_skills_disabled` 在 `player_state.gd:64`，来源表在 `:67`。门禁出现在 `_can_receive_timing_event`（`:660-661`）与每个主动入口（`:10509`、`:10602`、`:12684`）。**`lock=true` 完全免疫。**

2. **引擎层没有「强制发动」**。核心从不读 `lock` 来创建或抑制选择。锁定技语义**由技能文件自己实现**：跳过 `request_*`，直接 `announce_activation()` + 执行效果（`bahu.gd:24-26`、`huanying.gd:35-44`、`chouma.gd:44-59`）。约定见 `docs/内容制作指南.md:1919`。移除主动按钮的是 `ui_enabled=false`（不是 `lock`）。

---

## 7. 「每回合限一次」的两种实现

### (a) 通用 `acquired_skills.per_turn_limit`（技能内零代码）

- 写入：`match_controller.gd:10313-10323`（`grant_acquired_skill` 内）

```gdscript
player.acquired_skills[skill_id] = {
	"source":source, "per_turn_limit":maxi(per_turn_limit,0), "per_round_limit":..., "total_limit":...,
	"tracked_turn_number":state.turn_number, "tracked_round_number":state.round_number,
	"uses_this_turn":0, "uses_this_round":0, "total_uses":0,
}
```

- 门禁：`match_controller.gd:10331-10350` `can_use_acquired_skill()`（回合/轮/总额度，按 `tracked_turn_number` 与 `state.turn_number` 比较做惰性重置）
- 触发门禁：`skill_definition.gd:665-668`（**只对存在于 `acquired_skills` 的 ID 生效**；固有技能跳过）
- 消耗：`skill_definition.gd:216-217`（在 `announce_activation()` 内）→ `consume_acquired_skill_use`（`match_controller.gd:10354+`）
- **范例：`game_data/skills/huanyang.gd`（91 行）—— 文件内没有任何回合记账**；「每回合限一次」完全来自授予。授予点：`opportunity_catalog.gd:56` `{"id":"blue_skill_huanyang", ..., "effect":"grant_skill", "skill_id":"huanyang", "per_turn_limit":3}`
- 测试：`tests/opportunity_system_test.gd:240-241`、`:1027`；UI 显示 `match_table.gd:2264+`

### (b) 技能自记回合号

- `anda.gd:14-15` `var _used_turn_number: int = -1`；检查于 `:32`、`:98`、`:153`；写于 `:110`、`:163`
- `wansi.gd:26-29` + `:139-145` —— 完整惰性重置，最接近组合技能（「每回合限一次，当你受到伤害后…」）的形态：

```gdscript
var _tracked_turn_number: int = -1
var _used_this_turn: bool = false

func _sync_turn_state() -> void:
	var turn_number: int = _get_turn_number()
	if _tracked_turn_number != turn_number:
		_tracked_turn_number = turn_number
		_used_this_turn = false
```

调用点：触发顶部 `:62`、`continue_selection` `:85`；消耗于 `:91`。

其他：`yongyi.gd:5,66,95`、`fuhuo.gd:24,90-96`、`buzhui.gd:50-51,137-157`、`bingfeng.gd:17-18,45,81,91`。

---

## 8. 武将注册

### 规范文件 `game_data/characters/yinzhi.gd`（22 行，全文见文件）

```gdscript
extends CharacterDefinition

const XUNLI_SKILL: Script = preload("res://game_data/skills/xunli.gd")
const LIJIE_SKILL: Script = preload("res://game_data/skills/lijie.gd")

func _init() -> void:
	super({
		"id":"yinzhi",
		"display_name":"银枝",
		"gender":"male",
		"faction":"xingjianhuanyv",
		"max_hp":4,
		"description":"…",
	}, [XUNLI_SKILL, LIJIE_SKILL])
```

### `game_data/character_definition.gd`（43 行）
- `_metadata:7`、`_skill_scripts: Array[Script]:10`、`_init(metadata, skill_scripts):14-16`
- `get_metadata():20-33` —— **`skills` ID 数组由逐个实例化脚本读 `get_id()` 推导**（`:29-31`）；武将文件从不写字符串 ID
- `get_id():37-38`、`get_skill_scripts():42-43`

### 枚举与校验
- `GameDatabase._load_characters()`（`game_database.gd:395+`）；立绘路径在 `:419` 注入，由 `_find_character_art_path()`（`:434`）查找
- `_validate_characters()`（`:609-624`）：`display_name` 非空（`:614-615`）、`faction` 必须存在（`:617-619`）、**每个 `skills` 条目必须是已注册技能 ID**（`:620-624`）
- 势力：`game_data/factions.json`（10 个）。**星核猎手 = `xinghelieshou` / 猎 / `5b3a7d`**

### 新武将字段要求（`docs/内容制作指南.md:3403-3500`）

| 字段 | 必需 | 说明 |
|---|---|---|
| `id` | ✔ | 唯一，`[a-z0-9_]+` |
| `display_name` | ✔ | 中文 |
| `gender` | ✔ | `male`/`female`/`unknown`（影响雌雄双股剑） |
| `faction` | ✔ | 必须存在于 `factions.json` |
| `max_hp` | ✔ | ≥1；<1 会被钳到 1 |
| `description` | ✔ | 定位文案 |
| skills | ✔ | `Array[Script]`，`preload` 的技能脚本，按显示顺序 |

### 立绘与语音路径（**不在 `assets/` 下**）
- `CHARACTER_IMAGE_DIRECTORY = "res://game_data/characters/image"`（`game_database.gd:13`），扩展名 `["png","jpg"]`（`:16`）
- 匹配按**脚本文件 basename**，不是 `id`/`display_name`（`:434`；文档 `:3443-3453`）。现有 106 个文件。
- 阵亡语音：`game_data/characters/audio/die/<basename>.{ogg,wav,mp3}`（+`_1`..`_8`）（文档 `:3455-3468`）
- 文件名只允许小写字母/数字/下划线（`game_database.gd:489-492`）
- `assets/` 下只有 `art/`、`shaders/`、`ui/`

### 主演（本任务需要）
- `scripts/core/starring_role_service.gd`：`CORNER_ENTRY_ID="zhuyan":10`、`CORNER_TEXT="主演":13`、`CORNER_TEXT_ORDER=50:18`、`get_starring_player_id():35`、`is_starring():52`、`set_starring():62`、`clear_starring():84`
- 至多一名；死亡/换将清理：`death_resolution_service.gd:132,300`
- 端口：`match_controller.gd:17442` `set_starring_role`、`:17448` `get_starring_role_player_id`、`:17453` `is_starring_role`
- 使用先例：`wansi.gd:113`

---

## 9. 测试约定

- 每角色机制测试：`tests/<name>_mechanics_test.gd` + 同名 `.tscn`（如 `yinzhi_xunli_lijie_test.gd`、`haiseyin_mechanics_test.gd`、`yuezhi_mechanics_test.gd`）。**每个 `.gd` 必须有同名 `.tscn`**。
- 无头运行需 PASS 标记 + 退出码 0（`docs/战斗框架回归说明.md:5,23`）。
- 骨架：`extends Node`；`_ready(): call_deferred("_run")`；`_run()` → `_create_controller()` → 一串 `if not _test_x(): return` → `print("*_PASS")` → `get_tree().quit(0)`。
- `_create_controller()`：`MatchController.new()` + 子节点 `RuleEventBus` / `AICoordinator` / `NetworkGateway` → `add_child` → `local_human_player_id = 0`、`game_flow_interval_seconds = 0.0`。
- `_reset_state(n)`：`_uninstall_all_character_skills()` → 新 `GameState`（`match_id` 非空）→ 显式身份的 `PlayerState` → `_rebuild_match_rule_services_and_root_event()` → 清 `_pending_card_choice` / `_deferred_skill_settlements`。
- `_install_skill(player_id, skill_id)`：`GameDatabase.create_skill` → `bind(controller, player_id)` → 写 `_controller.skill_instances_by_player[player_id][skill_id]` → `install()`。
- 驱动时机：`_controller._emit_rule_timing("phaseZhunbeiBegin", 0, 0, -1, {...})`。
- 作答：`PlayerAction.new("choose_cards", actor_id)`，`payload = {"request_id":…, "selected_card_uids":[…], "selected_target_ids":[…], "confirmed":bool}` → `_controller.submit_action(action)`。
- `_fail(reason)` → `printerr("XXX_FAIL %s")` + `get_tree().quit(1)`。

`tests/haiseyin_mechanics_test.gd:34-95` 是完整 setup 引用范本（见文件本体）。

---

## 10. 结论：本任务必须新建的能力

1. **运行时技能定义注册表** —— 不存在。
2. **让组合技能拥有行为** —— `SkillDefinition.new(metadata)` 只能给元数据，`install()` 是 `pass`，没有按实例的回调表。
3. **显示名称覆盖** —— `dynamic_skill_descriptions` 只覆盖描述；名称永远来自静态库。
4. **同时拥有多个同名技能** —— `grant_acquired_skill` 拒绝重复 ID（`:10302-10304`），且 `acquired_skills` / `temporary_skills` / `skill_instances_by_player` 全是 ID 键字典。
5. **组合定义的持久化** —— `_reinstall_saved_runtime_skills`（`:16163-16189`）按 ID 经 `create_skill` 还原，未知 ID 被静默 `continue`（`:16181-16183`）。
6. **「组合」选择流程** —— 通用选项选择器存在（`request_control_selection`，`skill_definition.gd:992-1014`；`continue_selection` 派发于 `match_controller.gd:4242`），但没有时机/效果池目录、没有正文模板拼装、没有池选择的 AI 评分。
7. **组合技能的自动「每回合限一次」** —— 只对 `acquired_skills` 中的 ID 生效。
8. **组合技能的 AI 支持** —— 评分实例经 `GameDatabase.create_skill(current_skill_id)` 构造（`noname_ai_evaluator.gd:473,775`、`basic_ai_policy.gd:397,423,441`、`identity_strategy_evaluator.gd:269`），合成 ID 解析为 `null` 会被跳过。
9. **技能池元数据** —— 不存在描述时机（中文标签 + `RuleTimingCatalog` ID + role）与效果（文本模板 + 实现键 + AI 价值）的数据文件。
10. **主演感知的「组合并授予」助手** —— `set_starring_role`/`is_starring_role` 已就绪，但现有技能只能授予静态 ID（`lingfu.gd:246`、`shengbian.gd:134`）。
