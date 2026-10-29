class_name ComposedSkillBase
extends SkillDefinition

## 【进程】/【缺陷】组合技能的公共底座。
##
## 设计意图：这两个技能在需求里被描述为「组合一项技能」，即**同一份技能脚本**在不同的时机与效果组合下
## 表现出完全不同的行为。因此不能为每一种组合写一个技能文件（23 × 24 + 23 × 18 种组合），
## 而是把「时机」与「效果」拆成两张**纯数据池**（见 ZhuruComposePools），
## 由本底座在 install() 时读取该实例的运行时配置，把数据翻译成时机订阅与效果分派。
##
## 与项目架构的接入方式：
## ① 组合结果仍是**普通技能实例**——它由 MatchController.grant_acquired_skill 以 allow_duplicate=true 授予，
##    因此天然获得「同名技能多份实例各自独立结算」的能力（技能实例键底座）；
## ② 每份实例的配置存放在 PlayerState.runtime_skill_data（键为实例键），随权威存档往返，
##    不引入任何新的全局注册表，因此换将、失去技能、存档与回放都自动一致；
## ③ 本类只读数据池、只调用 MatchController 公开端口，不直接改写 GameState，也不移动实体牌。
##
## 子类职责：只覆写 _pool_kind() 与 _init() 的静态元数据，其余全部由本底座承担。

## 运行时配置中「时机键」的字段名；值必须是 ZhuruComposePools.TIMING_ENTRIES 中的 key。
const RUNTIME_KEY_TIMING: String = "timing_key"

## 运行时配置中「效果键」的字段名；值必须是所属类别效果池中的 key。
const RUNTIME_KEY_EFFECT: String = "effect_key"

## 本技能自有选择请求的上下文类型；用于把组合技能的两段式选择与其它技能的选择区分开。
const CHOICE_KIND_EFFECT: String = "composed_effect_choice"

## 选择步骤名：先选角色。
const STEP_TARGET: String = "target"

## 选择步骤名：再选牌。
const STEP_CARD: String = "card"

## 「以太」技能ID；进程效果池里「从牌堆中获得一张以太牌」按造牌来源识别，因此这里需要它的稳定ID。
const YITAI_SKILL_ID: String = "yitai"

## 回合域窗口键：防止持有者受到伤害直到回合结束。
const WINDOW_PREVENT_DAMAGE: String = "prevent_damage"

## 回合域窗口键：持有者下次受到的伤害+1。
const WINDOW_NEXT_DAMAGE: String = "next_damage"

## 回合域窗口键：持有者下次受到的属性伤害+1。
const WINDOW_NEXT_ELEMENTAL_DAMAGE: String = "next_elemental_damage"

## 回合域窗口键：持有者下次回复的体力-1。
const WINDOW_NEXT_RECOVER: String = "next_recover"

## 回合域窗口键：出牌阶段使用【杀】的次数上限+1。
const WINDOW_SLASH_LIMIT: String = "slash_limit"

## 回合域窗口键：攻击范围+2。
const WINDOW_ATTACK_RANGE: String = "attack_range"

## 回合域窗口键：计算与其他角色的距离-1。
const WINDOW_DISTANCE: String = "distance"

## 窗口记账中的「登记时所在回合的角色」字段名；到期判定与回合号双重匹配。
const WINDOW_TURN_PLAYER_FIELD: String = "turn_player_id"

## 窗口记账中的「登记时回合号」字段名；回合号单调递增，因此跨回合不会误匹配。
const WINDOW_TURN_NUMBER_FIELD: String = "turn_number"

## 「你受到的下一次伤害+1」的固定增量；与效果池原文「+1」一致。
const NEXT_DAMAGE_BONUS: int = 1

## 「你下次回复的体力-1」的固定减量；与效果池原文「-1」一致。
const NEXT_RECOVER_PENALTY: int = 1

## 「你的手牌上限+2直到回合结束」的固定增量；与效果池原文「+2」一致。
const TURN_HAND_LIMIT_BONUS: int = 2

## 「你的手牌上限-1直到回合结束」的固定减量；与效果池原文「-1」一致。
const TURN_HAND_LIMIT_PENALTY: int = 1

## 「你使用攻击范围+2直到回合结束」的固定增量；与效果池原文「+2」一致。
const TURN_ATTACK_RANGE_BONUS: int = 2

## 「你计算与其他角色距离-1直到回合结束」的固定减量；与效果池原文「-1」一致。
const TURN_DISTANCE_REDUCTION: int = 1

## 「你摸两张牌并失去本技能」的摸牌张数；与效果池原文「两张」一致。
const DRAW_TWO_COUNT: int = 2

## 「你回复1点体力并失去本技能」的回复量；与效果池原文「1点」一致。
const RECOVER_ONE_AMOUNT: int = 1

## 「你获得1点护盾并失去本技能」的护盾量；与效果池原文「1点」一致。
const GAIN_SHIELD_AMOUNT: int = 1

## 「你增加1点体力上限并失去本技能」的体力上限增量；与效果池原文「1点」一致。
const MAX_HP_GAIN_AMOUNT: int = 1

## 「你减少1点体力上限并失去本技能」的体力上限减量；与效果池原文「1点」一致。
const MAX_HP_LOSS_AMOUNT: int = 1

## 「你失去1点体力并失去本技能」的失去体力值；与效果池原文「1点」一致。
const LOSE_HP_AMOUNT: int = 1

## 「你受到1点伤害并失去本技能」及其属性变体的伤害值；与效果池原文「1点」一致。
const TAKE_DAMAGE_AMOUNT: int = 1

## 「你随机弃置…」系列固定的弃置张数；与效果池原文「一张」一致。
const RANDOM_DISCARD_COUNT: int = 1

## 纯查询型时机修正的随机历史种类；本底座不产生随机数，此常量只用于保持文档口径一致。
## 说明：组合技能的全部随机行为都走 pick_random_candidate_index，禁止直接调用 randi()，否则回放与联机不同步。
const RANDOM_DISCARD_HISTORY_KIND: String = "composed_random_discard"

## 组合技能强制用牌的阶段覆写；仍保留距离、目标和次数等常规合法性约束。
const COMPOSED_USE_RULE_OVERRIDES: Dictionary = {"ignore_phase_limit":true}

## 随机获得【闪】时的权威随机历史类型；用于回放复现候选下标。
const RANDOM_DODGE_HISTORY_KIND: String = "composed_random_gain_dodge"

## 已实现的效果键清单；与 ZhuruComposePools 的两个效果池键一一对应。
## 用途：组合技能测试会核对「池中每个键都在本清单里」，避免新增池条目后忘记实现对应效果
## （漏实现的表现是「技能发动了但什么都没发生」，没有任何报错，靠人工比对极易漏掉）。
const IMPLEMENTED_EFFECT_KEYS: Array[String] = [
	"draw_one",
	"gain_trick",
	"gain_basic",
	"gain_equipment",
	"gain_yitai_card",
	"gain_dodge",
	"gain_slash",
	"use_random_pile_equipment",
	"reset_chain",
	"discard_zone_card",
	"take_equipment",
	"take_other_turn_player_hand",
	"turn_hand_limit_plus2",
	"turn_slash_limit_plus1",
	"turn_attack_range_plus2",
	"turn_distance_minus1",
	"prevent_damage_until_turn_end",
	"virtual_slash",
	"virtual_duel",
	"virtual_shunshou",
	"draw_two_lose_skill",
	"recover_one_lose_skill",
	"gain_max_hp_lose_skill",
	"gain_shield_lose_skill",
	"discard_one_hand",
	"random_discard_one",
	"random_discard_equipment",
	"random_discard_basic",
	"random_discard_trick",
	"turn_hand_limit_minus1",
	"set_chain",
	"give_card_to_turn_player",
	"block_response_until_turn_end",
	"turn_distance_plus1",
	"next_damage_plus1",
	"next_elemental_damage_plus1",
	"next_recover_minus1",
	"lose_hp_lose_skill",
	"take_damage_lose_skill",
	"take_thunder_damage_lose_skill",
	"take_fire_damage_lose_skill",
	"lose_max_hp_lose_skill",
]

## 本实例的时机键；install() 时从运行时配置读取，未安装或配置非法时为空字符串。
var _timing_key: String = ""

## 本实例的效果键；install() 时从运行时配置读取，未安装或配置非法时为空字符串。
var _effect_key: String = ""

## 回合域持续窗口登记表；键为 WINDOW_* 常量，值为 {turn_player_id, turn_number}。
##
## 【为什么按「回合角色 + 回合号」记账而不是一个布尔】持有者可能在**别人的回合**里开启窗口
## （最典型的是「当你受到伤害后」在别人的出牌阶段触发）。若只存一个布尔，先结束的那个回合会把
## 属于另一个回合的窗口一起吃掉；按双重匹配记账后，每笔窗口只在自己所属的那个回合结束时失效。
var _windows: Dictionary = {}

## 「下一次伤害+1」已经预留的伤害事件ID；默认-1，防止同一外层伤害里的嵌套伤害重复获得加成。
## 与【追歼】同一口径：damageBegin3 预留，damage 成立时消费，damageCancelled/damageZero 时释放。
var _reserved_damage_event_id: int = -1


## 返回本技能所属的效果池类别；子类必须覆写为 ZhuruComposePools.KIND_* 之一。
## 基类返回空字符串表示「没有效果池」，此时 install() 会按配置非法处理并拒绝订阅。
func _pool_kind() -> String:
	return ""


## 组合技能一律自带每回合额度声明：组合出来的正文固定以「每回合限一次。」结尾。
## 因此在这里统一声明 declares_own_per_turn_limit，界面不再追加「每回合可发动1次」——
## 同一句限制在悬停说明里出现两次只会让玩家以为是两个不同的限制。
## 【为什么在基类统一写入】任何新增的组合技能类别都自动继承该口径，不必逐个类别重复声明。
func _init(metadata: Dictionary = {}) -> void:
	# 生效元数据；先复制再补字段，避免修改调用方传入的字典（子类可能复用同一个常量字典）。
	var effective_metadata: Dictionary = metadata.duplicate(true)
	effective_metadata["declares_own_per_turn_limit"] = true
	super(effective_metadata)


## 返回本技能的中文名；缺失元数据时回落到技能ID，保证日志与选择标题始终可读。
func _skill_name() -> String:
	return str(get_metadata().get("name", get_id()))


## 读取本实例的运行时组合配置；未安装、被移除或配置缺失时返回空字典。
## 键为实例键而不是技能ID：同名技能的多份实例各自持有独立组合，用技能ID 会让第二份读到第一份的配置。
func _read_runtime_config() -> Dictionary:
	if host == null or not host.has_method("get_runtime_skill_data"):
		return {}
	return host.call("get_runtime_skill_data", owner_player_id, get_instance_key()) as Dictionary


## 订阅时机；配置非法时不建立任何订阅，只留一条可追溯的报错与公开日志。
##
## 【为什么非法配置不能「退化成某个默认组合」】组合技能的效果范围很大（含失去技能、强制伤害等），
## 静默退化会让一个配置错误变成一局无法解释的对局结果。宁可让这份技能完全不生效并明确报错。
func install() -> void:
	# 本实例的组合配置；空字典表示尚未写入，按配置非法处理。
	var config: Dictionary = _read_runtime_config()
	_timing_key = str(config.get(RUNTIME_KEY_TIMING, ""))
	_effect_key = str(config.get(RUNTIME_KEY_EFFECT, ""))
	# 配置校验；时机键与效果键都必须属于本类别的效果池。
	if not ZhuruComposePools.is_valid_timing_key(_timing_key) or not ZhuruComposePools.is_valid_effect_key(_pool_kind(), _effect_key):
		push_error("组合技能配置非法：instance=%s kind=%s timing=%s effect=%s" % [get_instance_key(), _pool_kind(), _timing_key, _effect_key])
		if host != null and host.has_method("add_log"):
			host.call("add_log", "【%s】的组合配置无效，这一份技能不会生效。" % _skill_name())
		return
	# 当前时机条目；订阅角色由数据池声明，避免每个效果各自硬编码角色。
	var entry: Dictionary = ZhuruComposePools.get_timing_entry(_timing_key)
	# 触发角色；global 表示任何角色的该时机都成立，其余按事件角色精确匹配。
	var role: String = str(entry.get(ZhuruComposePools.ROLE_FIELD, ZhuruComposePools.ROLE_GLOBAL))
	# 主时机与附加时机；「体力上限发生变化后」需要同时订阅 gainMaxHpAfter 与 loseMaxHpAfter。
	for timing_name: String in ZhuruComposePools.get_subscription_timings(_timing_key):
		subscribe_timing(timing_name, _on_composed_timing, role)
	# 回合域窗口统一过期；走窗口订阅而不是普通订阅，理由见 _subscribe_window_timing 的说明。
	_subscribe_window_timing("phaseAfter", _on_phase_after)
	_install_effect_windows()


## 卸载技能时清空窗口登记，再释放基类管理的全部订阅与规则修正。
func uninstall() -> void:
	_windows.clear()
	_reserved_damage_event_id = -1
	super()


## 订阅一个**持续窗口**时机。
##
## 【为什么不能直接用 subscribe_timing】普通订阅统一经过 SkillDefinition._can_receive_timing_event，
## 其中包含「局内获得技能的每回合额度」检查：额度耗尽后该实例的**全部**订阅都不再接收时机。
## 而持续窗口效果的额度恰恰在**开窗那一次**就被消耗掉了，于是同一个回合内真正需要生效的那一次伤害
## 会被额度检查挡在门外——表现为「日志写了发动，伤害却照常结算」，且不产生任何报错。
##
## 因此窗口时机改走底层事件总线的无守卫订阅，由技能自己完成守卫：
## ① 持有者存活且未离场；② 武将代次与订阅时一致；③ 窗口标记仍然有效（窗口本身按回合记账）。
## 解除订阅由 SkillDefinition.uninstall() 统一调用 event_bus.unsubscribe_owner(self) 完成，不会泄漏。
func _subscribe_window_timing(event_name: String, callback: Callable) -> void:
	if host == null or host.get("event_bus") == null or not RuleTimingCatalog.has_timing(event_name):
		return
	host.get("event_bus").subscribe(event_name, self, callback)


## 按效果键安装该效果自带的持续窗口订阅；不需要窗口的效果不建立任何额外订阅。
## 只为**确实需要**窗口的效果挂钩子：每份实例都会独立安装，无差别挂满会让触发链上多出大量永不成立的判断。
func _install_effect_windows() -> void:
	match _effect_key:
		"prevent_damage_until_turn_end":
			_subscribe_window_timing("damageBegin4", _on_prevent_damage_begin_four)
		"next_damage_plus1", "next_elemental_damage_plus1":
			# 属性变体与普通变体共用同一套实现，属性过滤在回调内按窗口键完成。
			_subscribe_window_timing("damageBegin3", _on_next_damage_begin_three)
			_subscribe_window_timing("damage", _on_next_damage_resolved)
			_subscribe_window_timing("damageCancelled", _on_next_damage_released)
			_subscribe_window_timing("damageZero", _on_next_damage_released)
		"next_recover_minus1":
			_subscribe_window_timing("recoverBegin", _on_next_recover_begin)


## 判断持有者当前是否仍可执行本技能；窗口订阅不经过统一守卫，因此必须自行复核。
func _owner_is_active() -> bool:
	if host == null or host.get("state") == null:
		return false
	# 技能持有者权威状态；死亡、离场或换将后不再执行任何窗口效果。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	return matches_character_generation(get_bound_character_generation())


## 主时机回调；条件复核通过后记录发动并分派效果。
func _on_composed_timing(event: RuleEvent) -> void:
	if not _passes_timing_condition(event):
		return
	# 需要选择的效果先确认存在合法候选：没有任何可选项时直接跳过，避免把每回合额度空转掉。
	if not _has_executable_choice():
		return
	# 记录发动；锁定技在时机到达时即成立，额度在此消耗。
	# 上下文只带可序列化值：实例键供回放与界面定位到具体是哪一份组合技能。
	announce_activation({"timing_key":_timing_key, "effect_key":_effect_key, "instance_key":get_instance_key()})
	_dispatch_effect()


## 复核时机条目的附加条件；不满足时本次时机不发动。
func _passes_timing_condition(event: RuleEvent) -> bool:
	# 当前时机条目；install() 已保证存在，此处仍按缺失处理以防御运行时被改写的数据。
	var entry: Dictionary = ZhuruComposePools.get_timing_entry(_timing_key)
	if entry.is_empty():
		return false
	# 条件种类；数据池声明，避免每个效果各自硬编码判定。
	var condition: String = str(entry.get(ZhuruComposePools.CONDITION_FIELD, ZhuruComposePools.CONDITION_NONE))
	match condition:
		ZhuruComposePools.CONDITION_ELEMENTAL:
			# 属性伤害只承认 fire 与 thunder；普通伤害不满足。
			return ZhuruComposePools.is_elemental_nature(str(event.data.get("nature", "normal")))
		ZhuruComposePools.CONDITION_SLASH:
			return _is_slash_event(event)
		ZhuruComposePools.CONDITION_OUTSIDE_TURN:
			# 回合外：当前回合角色不是持有者本人。
			return int(host.state.current_player_id) != owner_player_id
		_:
			return true


## 判断一条用牌时机事件是否由【杀】族牌产生。
## 判定依据是**逻辑牌定义**而不是牌名：普通、火与雷【杀】共享 effect_id=slash，
## 转化牌也走同一份逻辑牌定义，因此按定义判定可以把三种【杀】与全部转化【杀】一并覆盖。
func _is_slash_event(event: RuleEvent) -> bool:
	# 逻辑牌定义ID；逐目标时机与整牌时机都写同一字段。
	var definition_id: String = str(event.data.get("card_id", ""))
	if definition_id.is_empty():
		return false
	# 当前牌静态定义；未登记定义按不满足处理。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if definition.is_empty():
		return false
	return str(definition.get("effect_id", "")) == "slash" or str(definition.get("play_limit_group", "")) == "slash"


## 判断本效果此刻是否存在合法可选项；不需要选择的效果恒为 true。
## 只做**第一步**的候选检查：后续步骤在 continue_selection 内若发现候选为空，会安全收尾（效果不产生变化）。
func _has_executable_choice() -> bool:
	match _effect_key:
		"discard_zone_card":
			return not _collect_zone_card_target_ids().is_empty()
		"take_equipment":
			return not _collect_equipment_target_ids().is_empty()
		"take_other_turn_player_hand":
			return _resolve_other_turn_player_id() >= 0
		"discard_one_hand":
			return not (host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array).is_empty()
		"give_card_to_turn_player":
			return _resolve_other_turn_player_id() >= 0 and not (host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array).is_empty()
		"virtual_slash":
			return not _list_legal_virtual_targets("sha").is_empty()
		"virtual_duel":
			return not _list_legal_virtual_targets("juedou").is_empty()
		"virtual_shunshou":
			return not _list_legal_virtual_targets("shunshou").is_empty()
		_:
			return true


## 返回指定虚拟牌定义当前的合法目标；走卡牌规则服务，与真人出牌共用同一份目标合法性。
func _list_legal_virtual_targets(definition_id: String) -> Array[int]:
	if host == null or host.get("card_rules") == null:
		return []
	return host.card_rules.list_legal_virtual_targets(owner_player_id, definition_id, _virtual_use_rule_overrides(definition_id))


## 返回本次虚拟用牌的规则覆写；阶段外不适用仅限出牌阶段的次数上限，其余限制仍保留。
func _virtual_use_rule_overrides(definition_id: String) -> Dictionary:
	# 本次规则覆写；复制常量以避免改变其他组合实例的规则。
	var overrides: Dictionary = COMPOSED_USE_RULE_OVERRIDES.duplicate(true)
	# 卡牌静态规则；只有次数范围明确为出牌阶段的牌才在阶段外放行次数限制。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if str(definition.get("play_limit_scope", "turn")) == "phase" and not bool(host.call("is_play_phase_of", owner_player_id)):
		overrides["ignore_play_count_limit"] = true
	return overrides


## 返回全部「存活且未离场」的角色ID，包含持有者本人。
## 口径：组合技能效果里的「一名角色」按项目通用口径取存活未离场者，不排除自己
## （原文若限定「其他角色」会显式写明，本效果池全部条目都没有该限定）。
func _collect_alive_player_ids() -> Array[int]:
	# 结果数组；顺序沿用权威座次，界面与AI据此得到相同排列。
	var result: Array[int] = []
	if host == null or host.get("state") == null:
		return result
	for player: PlayerState in host.state.players:
		if player != null and player.alive and not player.out_of_game:
			result.append(player.player_id)
	return result


## 返回「区域内至少有一张可弃置牌」的角色ID列表；用于「你弃置一名角色区域内的一张牌」的候选检查。
func _collect_zone_card_target_ids() -> Array[int]:
	# 结果数组；按座次排列。
	var result: Array[int] = []
	for target_id: int in _collect_alive_player_ids():
		if not (host.call("get_player_zone_candidates", owner_player_id, target_id) as Array).is_empty():
			result.append(target_id)
	return result


## 返回「装备区内至少有一张牌」的角色ID列表；用于「你获得一名角色装备区内的一张牌」的候选检查。
func _collect_equipment_target_ids() -> Array[int]:
	# 结果数组；按座次排列。
	var result: Array[int] = []
	for target_id: int in _collect_alive_player_ids():
		if not (host.call("get_equipment_candidates", owner_player_id, target_id, [] as Array[String]) as Array).is_empty():
			result.append(target_id)
	return result


## 返回「不为持有者的当前回合角色」ID；不存在（即当前回合就是自己）时返回-1。
func _resolve_other_turn_player_id() -> int:
	if host == null or host.get("state") == null:
		return -1
	# 当前回合角色；死亡或离场角色仍可能是当前回合角色，但此时不提供任何交互。
	var turn_player_id: int = int(host.state.current_player_id)
	if turn_player_id < 0 or turn_player_id == owner_player_id:
		return -1
	# 当前回合角色权威状态；死亡或离场时视为不存在。
	var turn_player: PlayerState = host.state.get_player(turn_player_id)
	if turn_player == null or not turn_player.alive or turn_player.out_of_game:
		return -1
	return turn_player_id


## 分派效果；每个效果只使用 MatchController 的公开端口，不直接改写权威状态。
func _dispatch_effect() -> void:
	match _effect_key:
		"draw_one":
			host.call("draw", owner_player_id, 1)
		"gain_trick":
			_gain_top_draw_card_by_filter({"type":"trick"}, "composed_gain_trick")
		"gain_basic":
			_gain_top_draw_card_by_filter({"type":"basic"}, "composed_gain_basic")
		"gain_equipment":
			_gain_top_draw_card_by_filter({"type":"equipment"}, "composed_gain_equipment")
		"gain_yitai_card":
			# 「以太」牌按**铸造来源**识别，不按牌名：牌名由玩家自由输入，同名撞车是设计内允许的。
			host.call("gain_top_minted_card_from_draw_or_discard", owner_player_id, YITAI_SKILL_ID, "composed_gain_yitai_card")
		"gain_dodge":
			_gain_random_dodge_from_draw_pile()
		"gain_slash":
			_gain_top_draw_card_by_filter({"effect_id":"slash"}, "composed_gain_slash")
		"use_random_pile_equipment":
			host.call("use_random_equipment_card_from_draw_pile", owner_player_id, "composed_use_random_pile_equipment")
		"reset_chain":
			host.call("set_player_linked", owner_player_id, false, owner_player_id, "composed_reset_chain")
		"discard_zone_card":
			_request_zone_card_target_step()
		"take_equipment":
			_request_equipment_target_step()
		"take_other_turn_player_hand":
			_request_other_turn_player_hand_step()
		"turn_hand_limit_plus2":
			host.call("add_turn_hand_limit_bonus", owner_player_id, TURN_HAND_LIMIT_BONUS, owner_player_id, "composed_turn_hand_limit_plus2")
		"turn_hand_limit_minus1":
			host.call("add_turn_hand_limit_bonus", owner_player_id, -TURN_HAND_LIMIT_PENALTY, owner_player_id, "composed_turn_hand_limit_minus1")
		"turn_slash_limit_plus1":
			_open_window(WINDOW_SLASH_LIMIT)
		"turn_attack_range_plus2":
			_open_window(WINDOW_ATTACK_RANGE)
		"turn_distance_minus1":
			_open_window(WINDOW_DISTANCE)
		"prevent_damage_until_turn_end":
			_open_window(WINDOW_PREVENT_DAMAGE)
		"virtual_slash":
			_request_virtual_card_target_step("sha")
		"virtual_duel":
			_request_virtual_card_target_step("juedou")
		"virtual_shunshou":
			_request_virtual_card_target_step("shunshou")
		"draw_two_lose_skill":
			host.call("draw", owner_player_id, DRAW_TWO_COUNT)
			_finish_effect()
		"recover_one_lose_skill":
			host.call("recover", owner_player_id, owner_player_id, RECOVER_ONE_AMOUNT, "composed_recover_one")
			_finish_effect()
		"gain_max_hp_lose_skill":
			host.call("change_max_hp", owner_player_id, MAX_HP_GAIN_AMOUNT, owner_player_id, "composed_gain_max_hp")
			_finish_effect()
		"gain_shield_lose_skill":
			host.call("shield", owner_player_id, GAIN_SHIELD_AMOUNT, owner_player_id, "composed_gain_shield")
			_finish_effect()
		"discard_one_hand":
			_request_own_hand_discard_step()
		"random_discard_one":
			_random_discard_from_candidates(host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary], "composed_random_discard_one")
		"random_discard_equipment":
			_random_discard_from_candidates(_collect_own_candidates_by_type("equipment"), "composed_random_discard_equipment")
		"random_discard_basic":
			_random_discard_from_candidates(_collect_own_candidates_by_type("basic"), "composed_random_discard_basic")
		"random_discard_trick":
			_random_discard_from_candidates(_collect_own_candidates_by_type("trick"), "composed_random_discard_trick")
		"set_chain":
			host.call("set_player_linked", owner_player_id, true, owner_player_id, "composed_set_chain")
		"give_card_to_turn_player":
			_request_give_card_step()
		"block_response_until_turn_end":
			host.call("set_response_blocked_until_turn_end", owner_player_id, true, owner_player_id, "composed_block_response")
		"turn_distance_plus1":
			# 原文是「你计算与其他角色的距离+1」，属于**计算者一侧**的修正，
			# 与「距离-1」共用同一窗口槽位；方向由效果键在 modify_distance_to_target 内决定。
			_open_window(WINDOW_DISTANCE)
		"next_damage_plus1":
			_open_window(WINDOW_NEXT_DAMAGE)
		"next_elemental_damage_plus1":
			_open_window(WINDOW_NEXT_ELEMENTAL_DAMAGE)
		"next_recover_minus1":
			_open_window(WINDOW_NEXT_RECOVER)
		"lose_hp_lose_skill":
			host.call("lose_hp", owner_player_id, owner_player_id, LOSE_HP_AMOUNT, "composed_lose_hp")
			_finish_effect()
		"take_damage_lose_skill":
			host.call("damage", owner_player_id, owner_player_id, TAKE_DAMAGE_AMOUNT, "normal", "", false, false, {"source_skill_id":get_instance_key()})
			_finish_effect()
		"take_thunder_damage_lose_skill":
			host.call("damage", owner_player_id, owner_player_id, TAKE_DAMAGE_AMOUNT, "thunder", "", false, false, {"source_skill_id":get_instance_key()})
			_finish_effect()
		"take_fire_damage_lose_skill":
			host.call("damage", owner_player_id, owner_player_id, TAKE_DAMAGE_AMOUNT, "fire", "", false, false, {"source_skill_id":get_instance_key()})
			_finish_effect()
		"lose_max_hp_lose_skill":
			host.call("change_max_hp", owner_player_id, -MAX_HP_LOSS_AMOUNT, owner_player_id, "composed_lose_max_hp")
			_finish_effect()
		_:
			# 池条目存在但没有实现分支；IMPLEMENTED_EFFECT_KEYS 与数据池的一致性由测试核对。
			push_error("组合技能效果未实现：%s" % _effect_key)


## 从摸牌堆顶检索一张满足过滤器的牌；过滤器字段由 MatchController._does_draw_card_match_filter 定义。
func _gain_top_draw_card_by_filter(filter: Dictionary, reason: String) -> void:
	host.call("gain_top_draw_card_matching", owner_player_id, filter, reason)


## 从摸牌堆中随机获得一张【闪】；无候选时不消耗随机数，移动与私有信息由权威端口处理。
func _gain_random_dodge_from_draw_pile() -> void:
	# 符合【闪】牌效的实体 UID；按牌堆顺序收集，确保随机下标可复现。
	var candidate_uids: Array[int] = []
	for card: CardInstance in host.state.draw_pile:
		if str(GameDatabase.get_card(card.definition_id).get("effect_id", "")) == "dodge":
			candidate_uids.append(card.uid)
	if candidate_uids.is_empty():
		return
	# 权威随机下标；随机历史记录来源与候选数以支持联机和回放。
	var selected_index: int = int(host.call("pick_random_candidate_index", candidate_uids.size(), RANDOM_DODGE_HISTORY_KIND, {"player_id":owner_player_id, "candidate_count":candidate_uids.size()}))
	if selected_index < 0 or selected_index >= candidate_uids.size():
		return
	host.call("gain_card_to_hand_by_uid", owner_player_id, candidate_uids[selected_index], "composed_gain_dodge")


## 效果收尾：按效果池声明决定是否失去本技能。
##
## 【为什么必须按实例键移除】同一角色可以累积多份【进程】/【缺陷】，
## 用技能ID 移除会删掉**首实例**，让「失去本技能」的那一份活下来、没触发的那一份反而消失。
func _finish_effect() -> void:
	if not ZhuruComposePools.effect_loses_skill(_pool_kind(), _effect_key):
		return
	# 本实例的实例键；空值表示尚未安装，此时无技能可失去。
	var instance_key: String = get_instance_key()
	if instance_key.is_empty() or host == null or not host.has_method("remove_skill"):
		return
	host.call("remove_skill", owner_player_id, instance_key, _effect_key)


## 开启一个回合域窗口；同一实例同一窗口重复开启时刷新为最新回合，不会叠加。
func _open_window(window_key: String) -> void:
	_windows[window_key] = {
		WINDOW_TURN_PLAYER_FIELD: int(host.state.current_player_id),
		WINDOW_TURN_NUMBER_FIELD: int(host.state.turn_number),
	}


## 判断窗口是否仍然有效；必须同时匹配「登记时所在回合的角色」与「登记时回合号」。
func _is_window_active(window_key: String) -> bool:
	if not _windows.has(window_key):
		return false
	# 当前窗口登记；空字典表示已被清理。
	var entry: Dictionary = _windows.get(window_key, {}) as Dictionary
	if entry.is_empty():
		return false
	if int(entry.get(WINDOW_TURN_NUMBER_FIELD, -1)) != int(host.state.turn_number):
		return false
	return int(entry.get(WINDOW_TURN_PLAYER_FIELD, -1)) == int(host.state.current_player_id)


## 关闭指定窗口；消费型窗口（下一次伤害、下一次回复）在兑现或释放后立即关闭。
func _close_window(window_key: String) -> void:
	_windows.erase(window_key)


## 回合结束统一清理；只清理属于**刚刚结束的那个回合**的窗口。
func _on_phase_after(_event: RuleEvent) -> void:
	if host == null or host.get("state") == null:
		return
	# 刚结束的回合角色与回合号；phaseAfter 派发时 state.turn_number 尚未递增。
	var turn_player_id: int = int(host.state.current_player_id)
	var turn_number: int = int(host.state.turn_number)
	for window_key_variant: Variant in _windows.keys():
		# 当前窗口登记；与本回合不匹配的窗口属于别的回合，必须原样保留。
		var entry: Dictionary = _windows.get(window_key_variant, {}) as Dictionary
		if int(entry.get(WINDOW_TURN_PLAYER_FIELD, -1)) != turn_player_id:
			continue
		if int(entry.get(WINDOW_TURN_NUMBER_FIELD, -1)) != turn_number:
			continue
		_windows.erase(window_key_variant)


## 防止持有者受到伤害直到回合结束；在最终伤害数值确定后的窗口整体取消本次伤害。
## 窗口订阅走底层总线、不带角色过滤，因此必须自行确认**受伤者就是持有者**。
func _on_prevent_damage_begin_four(event: RuleEvent) -> void:
	if event.target_id != owner_player_id:
		return
	if not _is_window_active(WINDOW_PREVENT_DAMAGE) or not _owner_is_active():
		return
	# 非正数伤害无需防止；提前返回可避免为0伤害写出无意义的发动记录。
	if int(event.data.get("amount", 0)) <= 0:
		return
	announce_activation({"timing_key":_timing_key, "effect_key":_effect_key, "prevented_damage":true})
	event.cancel("composed_prevent_damage")


## 为「下一次受到的伤害」或「下一次受到的属性伤害」增加固定值；在第三伤害修改窗口写入。
## 窗口订阅走底层总线、不带角色过滤，因此必须自行确认**受伤者就是持有者**。
func _on_next_damage_begin_three(event: RuleEvent) -> void:
	if event.target_id != owner_player_id or not _owner_is_active():
		return
	# 本效果是普通还是属性变体；两者共用同一实现，靠窗口键区分。
	var is_elemental_variant: bool = _is_window_active(WINDOW_NEXT_ELEMENTAL_DAMAGE)
	if not is_elemental_variant and not _is_window_active(WINDOW_NEXT_DAMAGE):
		return
	if is_elemental_variant and not ZhuruComposePools.is_elemental_nature(str(event.data.get("nature", "normal"))):
		return
	# 当前伤害事件ID；外层伤害一旦预留，嵌套产生的不同伤害必须等待外层实际结果后再判断。
	var damage_event_id: int = int(event.data.get("damage_event_id", -1))
	if damage_event_id < 0 or (_reserved_damage_event_id >= 0 and _reserved_damage_event_id != damage_event_id):
		return
	_reserved_damage_event_id = damage_event_id
	event.data["amount"] = maxi(int(event.data.get("amount", 0)), 0) + NEXT_DAMAGE_BONUS


## 预留的伤害实际成立时消费窗口；即使伤害全部由护盾吸收，仍属于「受到伤害」。
func _on_next_damage_resolved(event: RuleEvent) -> void:
	if event.target_id != owner_player_id:
		return
	if int(event.data.get("damage_event_id", -1)) != _reserved_damage_event_id:
		return
	_reserved_damage_event_id = -1
	_close_window(WINDOW_NEXT_DAMAGE)
	_close_window(WINDOW_NEXT_ELEMENTAL_DAMAGE)


## 预留的伤害被取消或最终归零时只释放事件占用，窗口继续等待下一次实际伤害。
func _on_next_damage_released(event: RuleEvent) -> void:
	if event.target_id != owner_player_id:
		return
	if int(event.data.get("damage_event_id", -1)) == _reserved_damage_event_id:
		_reserved_damage_event_id = -1


## 令持有者下一次回复的体力-1；在回复数值确定的窗口内直接扣减，最低归零。
## 窗口订阅走底层总线、不带角色过滤，因此必须自行确认**回复者就是持有者**。
func _on_next_recover_begin(event: RuleEvent) -> void:
	if event.target_id != owner_player_id:
		return
	if not _is_window_active(WINDOW_NEXT_RECOVER) or not _owner_is_active():
		return
	# 本次回复的请求数值；减1后最低为0，回复端口对0值会直接跳过。
	var requested_amount: int = int(event.data.get("amount", 0))
	if requested_amount <= 0:
		return
	_close_window(WINDOW_NEXT_RECOVER)
	announce_activation({"timing_key":_timing_key, "effect_key":_effect_key, "reduced_recover":NEXT_RECOVER_PENALTY})
	event.data["amount"] = maxi(requested_amount - NEXT_RECOVER_PENALTY, 0)


## 修正持有者的出牌阶段【杀】次数上限；仅在窗口有效时生效。
func get_play_count_limit_bonus(card_definition: Dictionary) -> int:
	if not _is_window_active(WINDOW_SLASH_LIMIT):
		return 0
	if str(card_definition.get("play_limit_group", "")) == "slash":
		return 1
	return 0


## 修正持有者的攻击范围；仅在窗口有效时生效。
func modify_attack_range(current_range: int) -> int:
	if not _is_window_active(WINDOW_ATTACK_RANGE):
		return current_range
	return current_range + TURN_ATTACK_RANGE_BONUS


## 修正持有者到目标的距离；「距离-1」与「距离+1」共用同一窗口，按登记方向决定正负。
func modify_distance_to_target(target_id: int, current_distance: int) -> int:
	if target_id == owner_player_id:
		return current_distance
	if not _is_window_active(WINDOW_DISTANCE):
		return current_distance
	# 本实例的距离效果方向；由效果键决定，避免为两个方向各写一个几乎相同的函数。
	if _effect_key == "turn_distance_plus1":
		return current_distance + TURN_DISTANCE_REDUCTION
	return maxi(current_distance - TURN_DISTANCE_REDUCTION, 1)


## 返回持有者自己的手牌+装备候选，并按定义类型过滤；用于「随机弃置一张基本/锦囊牌」。
func _collect_own_candidates_by_type(card_type: String) -> Array[Dictionary]:
	# 结果候选；保持统一区域候选结构，随机弃置仍走同一份实体移动入口。
	var result: Array[Dictionary] = []
	for candidate_variant: Variant in host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array:
		# 当前候选；card_data 提供定义ID，可见性由统一候选结构决定。
		var candidate: Dictionary = candidate_variant as Dictionary
		# 候选牌面数据；隐藏手牌没有 definition_id，按不匹配处理。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		if str(GameDatabase.get_card(str(card_data.get("definition_id", ""))).get("type", "")) == card_type:
			result.append(candidate)
	return result


## 从候选里**随机**弃置一张自有牌；候选为空时不做任何事。
##
## 【随机源】下标必须经 pick_random_candidate_index 取得并写入 random_history，
## 否则回放与联机对局无法复现被弃置的是哪一张（规则层禁止直接调用 randi()）。
func _random_discard_from_candidates(candidates: Array[Dictionary], reason: String) -> void:
	if candidates.is_empty():
		return
	# 权威随机下标；历史数据记录候选数与来源，便于回放核对。
	var selected_index: int = int(host.call("pick_random_candidate_index", candidates.size(), RANDOM_DISCARD_HISTORY_KIND, {"player_id":owner_player_id, "reason":reason, "candidate_count":candidates.size()}))
	if selected_index < 0 or selected_index >= candidates.size():
		return
	# 被选中的牌UID；随后按区域走统一弃置入口。
	var selected_uid: int = int((candidates[selected_index] as Dictionary).get("uid", -1))
	if selected_uid < 0:
		return
	host.call("discard_selected_player_card", owner_player_id, owner_player_id, selected_uid)


## 请求「弃置一名角色区域内的一张牌」的第一步：选择角色。
func _request_zone_card_target_step() -> void:
	# 候选角色；只列出区域内确实有牌可弃置的角色，避免玩家点进一个空列表。
	var target_ids: Array[int] = _collect_zone_card_target_ids()
	if target_ids.is_empty():
		return
	request_target_selection("【%s】请选择一名角色" % _skill_name(), target_ids, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_TARGET})


## 请求「获得一名角色装备区内的一张牌」的第一步：选择角色。
func _request_equipment_target_step() -> void:
	# 候选角色；只列出装备区确实有牌的角色。
	var target_ids: Array[int] = _collect_equipment_target_ids()
	if target_ids.is_empty():
		return
	request_target_selection("【%s】请选择一名角色" % _skill_name(), target_ids, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_TARGET})


## 请求「获得不为你的当前回合角色的一张手牌」。
func _request_other_turn_player_hand_step() -> void:
	# 目标角色；不是自己且仍在场，否则没有合法目标。
	var turn_player_id: int = _resolve_other_turn_player_id()
	if turn_player_id < 0:
		return
	# 目标手牌候选；手牌数可能为0，此时直接放弃本次效果。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, turn_player_id) as Array[Dictionary]
	if candidates.is_empty():
		return
	request_card_selection("【%s】请选择要获得的牌" % _skill_name(), "选择%s的一张手牌" % _player_name(turn_player_id), candidates, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_CARD, "target_id":turn_player_id})


## 请求「你弃置一张手牌」。
func _request_own_hand_discard_step() -> void:
	# 自己的手牌候选；没有手牌时本次效果不产生变化。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	if candidates.is_empty():
		return
	request_card_selection("【%s】请弃置一张手牌" % _skill_name(), "选择一张手牌弃置", candidates, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_CARD, "target_id":owner_player_id})


## 请求「你交给不为你的当前回合角色一张牌」。
func _request_give_card_step() -> void:
	# 接收者；不是自己且仍在场。
	var receiver_id: int = _resolve_other_turn_player_id()
	if receiver_id < 0:
		return
	# 可交出的自有牌；手牌与装备区都算「一张牌」。
	var candidates: Array[Dictionary] = host.call("get_hand_equipment_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	if candidates.is_empty():
		return
	request_card_selection("【%s】请选择要交出的牌" % _skill_name(), "选择一张牌交给%s" % _player_name(receiver_id), candidates, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_CARD, "target_id":receiver_id})


## 请求「视为使用一张虚拟牌」的目标。
func _request_virtual_card_target_step(definition_id: String) -> void:
	# 合法目标；走卡牌规则服务，与真人出牌共用同一份目标合法性判定。
	var target_ids: Array[int] = _list_legal_virtual_targets(definition_id)
	if target_ids.is_empty():
		return
	request_target_selection("【%s】请选择目标" % _skill_name(), target_ids, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_TARGET, "virtual_definition_id":definition_id})


## 返回玩家日志名；用于选择标题与提示文本。
func _player_name(player_id: int) -> String:
	if host != null and host.has_method("format_player_log_name"):
		return str(host.call("format_player_log_name", player_id))
	return "该角色"


## 恢复组合技能的两段式选择；返回 true 表示本请求由组合技能消费。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != CHOICE_KIND_EFFECT:
		return false
	# 取消不应发生（本技能为锁定技，参数选择不允许取消）；防御性处理为本次效果不产生变化。
	if not response.confirmed:
		return true
	# 当前步骤；缺失时按第一步处理，兼容只创建单步请求的效果。
	var step: String = str(context.get("step", STEP_TARGET))
	# 虚拟牌目标选择：单步完成，直接执行虚拟用牌。
	var virtual_definition_id: String = str(context.get("virtual_definition_id", ""))
	if not virtual_definition_id.is_empty():
		_execute_virtual_use(virtual_definition_id, response.target_ids)
		return true
	# 步骤分派；每个效果只走自己声明的那条路径。
	match _effect_key:
		"discard_zone_card":
			_continue_discard_zone_card(step, context, response)
		"take_equipment":
			_continue_take_equipment(step, context, response)
		"take_other_turn_player_hand":
			_continue_take_other_turn_player_hand(context, response)
		"discard_one_hand":
			_continue_discard_own_card(context, response, "hand")
		"give_card_to_turn_player":
			_continue_give_card(context, response)
		_:
			return false
	return true


## 恢复「弃置一名角色区域内的一张牌」：第一步选角色，第二步选牌。
func _continue_discard_zone_card(step: String, context: Dictionary, response: ChoiceResponse) -> void:
	if step == STEP_TARGET:
		if response.target_ids.is_empty():
			return
		# 已选角色；随后列出该角色区域内的全部可弃置牌。
		var target_id: int = int(response.target_ids[0])
		var candidates: Array[Dictionary] = host.call("get_player_zone_candidates", owner_player_id, target_id) as Array[Dictionary]
		if candidates.is_empty():
			return
		request_card_selection("【%s】请选择要弃置的牌" % _skill_name(), "选择%s区域内的一张牌" % _player_name(target_id), candidates, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_CARD, "target_id":target_id})
		return
	# 第二步：执行弃置；统一入口会复核保护技能，旧候选失效时安全返回 false。
	if response.card_ids.is_empty():
		return
	host.call("discard_selected_player_card", owner_player_id, int(context.get("target_id", -1)), int(response.card_ids[0]))


## 恢复「获得一名角色装备区内的一张牌」：第一步选角色，第二步选牌。
func _continue_take_equipment(step: String, context: Dictionary, response: ChoiceResponse) -> void:
	if step == STEP_TARGET:
		if response.target_ids.is_empty():
			return
		# 已选角色；随后列出其装备区候选。
		var target_id: int = int(response.target_ids[0])
		var candidates: Array[Dictionary] = host.call("get_equipment_candidates", owner_player_id, target_id, [] as Array[String]) as Array[Dictionary]
		if candidates.is_empty():
			return
		request_card_selection("【%s】请选择要获得的装备" % _skill_name(), "选择%s装备区内的一张牌" % _player_name(target_id), candidates, 1, 1, false, {"kind":CHOICE_KIND_EFFECT, "step":STEP_CARD, "target_id":target_id})
		return
	if response.card_ids.is_empty():
		return
	host.call("take_selected_player_card", owner_player_id, int(context.get("target_id", -1)), int(response.card_ids[0]))


## 恢复「获得不为你的当前回合角色的一张手牌」。
func _continue_take_other_turn_player_hand(context: Dictionary, response: ChoiceResponse) -> void:
	if response.card_ids.is_empty():
		return
	host.call("take_selected_player_card", owner_player_id, int(context.get("target_id", -1)), int(response.card_ids[0]))


## 恢复「弃置自己的一张牌」；area 目前只用于手牌，保留参数以便后续扩展到装备区。
func _continue_discard_own_card(_context: Dictionary, response: ChoiceResponse, _area: String) -> void:
	if response.card_ids.is_empty():
		return
	host.call("discard_selected_player_card", owner_player_id, owner_player_id, int(response.card_ids[0]))


## 恢复「交给不为你的当前回合角色一张牌」。
func _continue_give_card(context: Dictionary, response: ChoiceResponse) -> void:
	if response.card_ids.is_empty():
		return
	# 接收者；统一获得入口同时支持手牌与装备，并在装备离区时完成统一清理。
	host.call("gain_card_to_hand_by_uid", int(context.get("target_id", -1)), int(response.card_ids[0]), "composed_give_card")


## 执行一次虚拟牌使用；目标合法性由核心端口再次复核，失效目标会被安全拒绝。
func _execute_virtual_use(definition_id: String, target_ids: Array[int]) -> void:
	if target_ids.is_empty():
		return
	host.call("execute_cardless_virtual_card_use", owner_player_id, definition_id, target_ids, "", _virtual_use_rule_overrides(definition_id), {"source_skill_id":get_instance_key()})


## 组合技能没有主动按钮，因此不提供任何主动动作评分。
func score_ai_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 为组合技能自己的选择请求评分；只处理本技能创建的请求，其余请求返回0不干扰通用评分。
##
## 评分口径：只做**粗粒度方向性**排序，不复刻每个效果的完整收益模型。
## 理由：组合技能的效果组合空间极大（23×24 + 23×18），为每个组合写专属评分既不可能也没必要；
## AI 只需要在「明显有收益」与「明显是代价」之间做出区分，具体数值仍由通用评分与出牌策略决定。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非组合技能选择不修改通用评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND_EFFECT:
		return 0.0
	# 标准选择负载；取消保持0分。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 当前步骤；第一步选角色、第二步选牌，两者评分口径不同。
	var step: String = str(context.get("step", STEP_TARGET))
	if step == STEP_TARGET:
		# 目标选择：收益类效果（获得对方的牌）与代价类效果（把代价指向谁）都偏向敌方。
		# 态度值为负表示敌方，取负号后敌方得正分。
		# 目标态度求和；多目标效果逐项累加。
		var attitude_sum: float = 0.0
		for target_variant: Variant in payload.get("selected_target_ids", []) as Array:
			attitude_sum += float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, int(target_variant)))
		return -attitude_sum
	# 第二步选牌：优先交出/弃置价值最低的牌，优先获得价值最高的牌。
	# 使用通用单牌资源值，避免在组合技能里另立一套估值口径。
	var card_value_sum: float = 0.0
	for card_uid_variant: Variant in payload.get("selected_card_uids", []) as Array:
		card_value_sum += float(evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(card_uid_variant), owner_player_id))
	# 自己获得牌 vs 自己付出牌；两种方向的符号相反。
	if _effect_gains_card_from_target():
		return card_value_sum
	if _effect_gives_card_away():
		return -card_value_sum
	return 0.0


## 判断效果是否为「从目标处获得牌」。
func _effect_gains_card_from_target() -> bool:
	return _effect_key == "take_equipment" or _effect_key == "take_other_turn_player_hand"


## 判断效果是否为「把自己的牌交出去或弃置」。
func _effect_gives_card_away() -> bool:
	return _effect_key == "give_card_to_turn_player" or _effect_key == "discard_one_hand" or _effect_key.begins_with("random_discard")
