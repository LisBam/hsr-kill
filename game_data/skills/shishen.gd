extends SkillDefinition

## 【弑神】技能源码。持有者使用本阶段前X张【杀】时解除距离与次数限制，并在逐目标指定时失去体力、增加伤害。

## 弑神读取轮回数的关联技能稳定ID；仅通过公开轮回状态查询，不持有血仇运行时实例。
const REINCARNATION_SOURCE_SKILL_ID: String = "xvechou"

## 每次【杀】指定一名目标时固定失去的体力；数值1来自技能原文。
const HP_LOSS_PER_TARGET: int = 1

## 每名目标获得的固定【杀】伤害加值；数值1来自技能原文。
const DAMAGE_BONUS_PER_TARGET: int = 1


## 写入锁定技静态信息；技能描述逐字保持主公提供的原文。
func _init() -> void:
	super({
		"id":"shishen",
		"name":"弑神",
		"trigger":"useCardToTargeted",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，出牌阶段，你使用的前X张【杀】无距离与次数限制。当你使用【杀】指定目标时，你失去1点体力并令此【杀】伤害+1。",
	})


## 订阅持有者使用【杀】逐目标指定完成时机；多目标【杀】对每名目标分别执行一次。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_owner_slash_targeted, "source")


## 前X张【杀】在使用前达到次数上限时仍可通过；声明后依旧正常计入次数历史。
func ignores_play_count_limit(card_definition: Dictionary) -> bool:
	return _is_slash(card_definition) and _is_within_unrestricted_slash_window(card_definition)


## 前X张【杀】忽略距离限制；同一次纯查询读取与次数解除完全一致的计数组。
func ignores_card_distance_limit(card_definition: Dictionary) -> bool:
	return _is_slash(card_definition) and _is_within_unrestricted_slash_window(card_definition)


## 对每名【杀】目标强制支付1点体力并写入该目标1点伤害加值。
func _on_owner_slash_targeted(event: RuleEvent) -> void:
	# 当前逻辑牌定义；普通、火与雷【杀】统一以effect_id识别。
	var card_definition: Dictionary = GameDatabase.get_card(str(event.data.get("card_id", "")))
	if not _is_slash(card_definition):
		return
	# 当前父牌UID；伤害加值必须精确绑定本张【杀】与当前目标。
	var parent_card_uid: int = int(event.data.get("card_uid", -1))
	# 当前实际目标ID；逐目标时机优先读取data中的稳定字段。
	var target_id: int = int(event.data.get("target_id", event.target_id))
	if parent_card_uid < 0 or target_id < 0:
		return
	announce_activation({"card_uid":parent_card_uid, "target_id":target_id, "hp_loss":HP_LOSS_PER_TARGET, "damage_bonus":DAMAGE_BONUS_PER_TARGET})
	# 当前逐目标时机事件也保存同一伤害加值；真实CardUseEvent完成回写时不会再用派发前旧customArgs覆盖技能结果。
	_write_event_target_damage_bonus(event, target_id, DAMAGE_BONUS_PER_TARGET)
	host.call("add_card_target_damage_bonus", parent_card_uid, target_id, DAMAGE_BONUS_PER_TARGET, get_id())
	# 失去体力可能立即插入完整濒死流程；增伤已先绑定到原【杀】，濒死结束后才会继续本牌后续结算。
	get_owner_skill_player().loseHp(HP_LOSS_PER_TARGET, get_owner_skill_player())
	observe_identity_behavior([target_id], {"target_result":-1.0, "damage":true, "respond_shan":true})


## 把当前目标的伤害加值同步写入逐目标事件数据；控制器随后会将该副本合并回原CardUseEvent上下文。
func _write_event_target_damage_bonus(event: RuleEvent, target_id: int, amount: int) -> void:
	if event == null or target_id < 0 or amount == 0:
		return
	# 本张牌全部目标的自定义参数；字符串目标ID与控制器公开协议保持一致。
	var custom_args: Dictionary = (event.data.get("custom_args", {}) as Dictionary).duplicate(true)
	# 当前目标的独立参数；多目标【杀】不会把弑神加值扩散到其他目标。
	var target_args: Dictionary = (custom_args.get(str(target_id), {}) as Dictionary).duplicate(true)
	target_args["damage_bonus"] = int(target_args.get("damage_bonus", 0)) + amount
	custom_args[str(target_id)] = target_args
	event.data["custom_args"] = custom_args


## 判断当前【杀】是否仍位于本阶段前X张窗口；X读取血仇当前轮回数，缺失状态时安全回退1。
func _is_within_unrestricted_slash_window(card_definition: Dictionary) -> bool:
	if host == null or host.get("card_rules") == null:
		return false
	# 血仇轮回状态；弑神只读取序列化数值，不依赖另一个技能对象。
	var reincarnation_state: Dictionary = host.call("get_reincarnation_skill_state", owner_player_id, REINCARNATION_SOURCE_SKILL_ID) as Dictionary
	# 当前可解除限制的【杀】张数X；轮回数初始与缺省值均为1。
	var unrestricted_count: int = maxi(int(reincarnation_state.get("round_count", 1)), 1)
	# 当前阶段实际使用过的【杀】数；即使此前某张【杀】不计入次数限制，它仍占用“前X张”的使用序号。
	var used_slash_count: int = int(host.card_rules.get_grouped_actual_play_count(owner_player_id, card_definition))
	return used_slash_count < unrestricted_count


## 判断卡牌定义是否属于【杀】牌族；通过共享effect_id兼容普通、火与雷【杀】。
func _is_slash(card_definition: Dictionary) -> bool:
	return str(card_definition.get("effect_id", "")) == "slash"


## AI为弑神必定追加的目标伤害计入收益，但按主公要求不因失去体力而降低【杀】使用意愿。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 当前动作卡牌定义；非【杀】不受弑神影响。
	var card_definition: Dictionary = GameDatabase.get_card(str(action.get("card_definition_id", "")))
	if not _is_slash(card_definition):
		return current_score
	# 弑神额外伤害总收益；逐目标按1点体力资源变化计算，不扣除持有者支付的体力。
	var bonus_score: float = 0.0
	for target_id_variant: Variant in action.get("target_ids", []) as Array:
		# 当前目标稳定ID；合法动作中的目标均存在，仍通过统一评估器读取阵营价值。
		var target_id: int = int(target_id_variant)
		bonus_score += evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 0, -DAMAGE_BONUS_PER_TARGET)
	return current_score + bonus_score
