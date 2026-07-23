class_name SlashCardEffect
extends RefCounted

## 【杀】牌族共享流程组件。这里只规定目标、武器钩子、防具、【闪】和伤害的通用顺序，不包含任何具体装备 ID。

## 当前卡牌效果调度器；负责生命周期判断与父牌源码恢复。
var resolver: CardEffectResolver

## 对局控制器规则端口；所有状态修改均通过该端口完成。
var host: Object

## 当前权威对局状态；用于只读查询玩家与实体牌区域。
var state: GameState


## 写入【杀】牌族逐目标共享的伤害、属性与防具状态；同一张多目标【杀】只消耗一次酒加值。
static func configure_shared_resolution_context(match_host: Object, card: CardInstance, actor_id: int, resolution_context: Dictionary) -> void:
	# 【杀】使用者；无效角色保持安全默认值，后续目标流程会直接停止。
	var actor: PlayerState = match_host.state.get_player(actor_id)
	if actor == null:
		resolution_context["slash_damage_amount"] = 1
		resolution_context["slash_nature"] = "normal"
		resolution_context["slash_ignore_armor"] = false
		return
	# 本次消耗的酒伤害加值；读取后立即清零，并在进入任何防具或响应窗口前刷新公开红色滤镜。
	var consumed_wine_bonus: int = actor.wine_bonus
	resolution_context["slash_damage_amount"] = 1 + consumed_wine_bonus
	actor.wine_bonus = 0
	if consumed_wine_bonus > 0:
		match_host.refresh_public_state_snapshot()
	resolution_context["slash_nature"] = str(GameDatabase.get_card(card.definition_id).get("nature", "normal"))
	# 当前武器定义；是否忽略防具由装备源码钩子声明，不依赖任何具体装备 ID。
	var weapon_definition: CardDefinition = match_host.get_equipment_definition(actor_id, "weapon")
	resolution_context["slash_ignore_armor"] = weapon_definition != null and weapon_definition.slash_ignores_armor()


## 在共享上下文登记后执行当前武器的整牌准备钩子；返回 true 表示等待装备选择。
static func begin_shared_resolution(match_host: Object, card: CardInstance, actor_id: int, resolution_context: Dictionary) -> bool:
	# 当前武器定义；普通武器默认不接管整张【杀】的准备阶段。
	var weapon_definition: CardDefinition = match_host.get_equipment_definition(actor_id, "weapon")
	return weapon_definition != null and weapon_definition.on_slash_resolution_started(match_host, card, actor_id, resolution_context)


## 绑定一次同步结算或异步恢复所需的通用调度器。
func _init(effect_resolver: CardEffectResolver) -> void:
	resolver = effect_resolver
	host = effect_resolver.host
	state = effect_resolver.state


## 结算整张【杀】；不使用逐目标事件树的兼容路径会直接遍历全部目标。
func resolve(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	# 使用者状态；酒加值在整张【杀】开始时只读取并消耗一次。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null:
		return "discard"
	# 本次消耗的酒伤害加值；整牌兼容入口同样必须在【杀】开始时立即撤销公开红色滤镜。
	var consumed_wine_bonus: int = actor.wine_bonus
	# 本张【杀】对全部目标共享的基础伤害。
	var base_damage: int = 1 + consumed_wine_bonus
	actor.wine_bonus = 0
	if consumed_wine_bonus > 0:
		host.refresh_public_state_snapshot()
	# 当前实体【杀】属性；允许 normal、fire 或 thunder。
	var nature: String = str(GameDatabase.get_card(card.definition_id).get("nature", "normal"))
	# 当前武器定义；锁定效果通过源码钩子声明是否忽略防具。
	var weapon_definition: CardDefinition = host.get_equipment_definition(actor_id, "weapon")
	# 整张【杀】共享的无视防具状态；多目标结算期间保持不变。
	var ignore_armor: bool = weapon_definition != null and weapon_definition.slash_ignores_armor()
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		resolve_external_target(card, actor_id, target_id, base_damage, nature, ignore_armor)
	return resolver.default_destination()


## 使用整张牌预先保存的共享参数结算一个目标。
func resolve_target(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> String:
	resolve_external_target(card, actor_id, target_id, damage_amount, nature, ignore_armor)
	return resolver.default_destination()


## 供借刀杀人和武器追击复用单目标【杀】流程；可指定真正负责异步恢复的父牌 UID。
func resolve_external_target(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool, resolution_parent_card_uid: int = -1) -> void:
	if resolver.is_resolution_stopped():
		return
	# 攻击者状态；不存在或死亡时不能继续发动武器。
	var actor: PlayerState = state.get_player(actor_id)
	# 目标状态；死亡或离场目标直接跳过本次结算。
	var target: PlayerState = state.get_player(target_id)
	if actor == null or not actor.alive or actor.out_of_game or target == null or not target.alive or target.out_of_game:
		return
	# 通用【杀】上下文；只保存可序列化字段，异步恢复时重新查询实体与装备。
	# 当前使用牌对本目标的技能伤害加值；多目标【杀】按目标独立读取，不污染其他目标基础伤害。
	var parent_card_uid: int = card.uid if resolution_parent_card_uid < 0 else resolution_parent_card_uid
	# 本张逻辑【杀】的最终目标数；普通用牌读取整张【杀】的目标数组，借刀与武器追击产生的外部【杀】固定为单目标。
	var slash_target_count: int = int(host.call("get_card_use_target_count", parent_card_uid)) if resolution_parent_card_uid < 0 and host.has_method("get_card_use_target_count") else 1
	var target_damage_bonus: int = int(host.call("get_card_target_damage_bonus", parent_card_uid, target_id)) if host.has_method("get_card_target_damage_bonus") else 0
	var context: Dictionary = {
		"parent_card_uid":parent_card_uid,
		"slash_card_uid":card.uid,
		"slash_card_definition_id":card.definition_id,
		"damage_card_target_count":maxi(slash_target_count, 1),
		"actor_id":actor_id,
		"target_id":target_id,
		"base_damage_amount":maxi(damage_amount, 0),
		"applied_target_damage_bonus":target_damage_bonus,
		"damage_amount":maxi(damage_amount + target_damage_bonus, 0),
		"nature":nature,
		"ignore_armor":ignore_armor,
	}
	# 虚拟牌扩展存储；【山倾】等多材料【杀】通过该纯数据字段把花色效果传入伤害与目标时机。
	context["virtual_storage"] = (host.call("get_card_virtual_storage", parent_card_uid) as Dictionary).duplicate(true) if host.has_method("get_card_virtual_storage") else {}
	# 当前武器定义；每件武器自行判断是否在“指定目标后”接管流程。
	var weapon_definition: CardDefinition = host.get_equipment_definition(actor_id, "weapon")
	if state.processing_area.has(card) and weapon_definition != null and weapon_definition.on_slash_targeted(self, context):
		return
	continue_after_weapon_targeted(context)


## 在武器“指定目标后”钩子完成后继续防具检查和【闪】响应。
func continue_after_weapon_targeted(context: Dictionary) -> void:
	# 当前【杀】实体；响应牌可能已经进入弃牌堆，因此按 UID 搜索全部权威区域。
	var card: CardInstance = _find_card(int(context.get("slash_card_uid", -1)))
	# 当前目标状态；等待期间死亡或离场时停止。
	var target: PlayerState = state.get_player(int(context.get("target_id", -1)))
	if card == null or target == null or not target.alive or target.out_of_game or resolver.is_resolution_stopped():
		return
	# 当前攻击者武器；目标结算开始时再次读取，确保借刀【杀】与异步恢复都能正确应用青釭剑的无视防具能力。
	var current_weapon_definition: CardDefinition = host.get_equipment_definition(int(context.get("actor_id", -1)), "weapon")
	if current_weapon_definition != null and current_weapon_definition.slash_ignores_armor():
		context["ignore_armor"] = true
	if not bool(context.get("ignore_armor", false)):
		# 目标防具定义；具体无效条件由防具文件实现。
		var armor_definition: CardDefinition = host.get_equipment_definition(target.player_id, "armor")
		if armor_definition != null and armor_definition.blocks_slash(card, str(context.get("nature", "normal"))):
			host.record_equipment_activation(target.player_id, armor_definition.get_id())
			host.add_log("%s的防具令此【杀】无效。" % target.display_name)
			host.emit_rule_timing("shaCancelled", int(context.get("actor_id", -1)), int(context.get("actor_id", -1)), target.player_id, context)
			return
	if host.has_method("is_card_target_direct_hit") and bool(host.is_card_target_direct_hit(int(context.get("parent_card_uid", -1)), target.player_id)):
		_finish_slash_response(context, false)
		return
	# 【闪】响应上下文；kind 用于卡牌源码恢复，其他字段保持原通用上下文。
	var response_context: Dictionary = context.duplicate(true)
	response_context["kind"] = "slash_response"
	response_context["complete_parent_target_after_response"] = true
	# 目标实际打出的【闪】；为空可能表示放弃或正在等待玩家选择。
	var response_card: CardInstance = host.request_response_card(target.player_id, "shan", "是否打出【闪】响应【杀】？", response_context)
	if resolver.is_resolution_stopped() or host.has_pending_card_choice():
		return
	_finish_slash_response(response_context, response_card != null)


## 在【闪】结果确定后执行当前武器的“被闪抵消后”钩子。
func _finish_slash_response(context: Dictionary, dodged: bool) -> void:
	# 攻击者状态；响应等待期间可能已经离场。
	var actor: PlayerState = state.get_player(int(context.get("actor_id", -1)))
	# 目标状态；响应插入结算可能已经改变其存活状态。
	var target: PlayerState = state.get_player(int(context.get("target_id", -1)))
	if actor == null or not actor.alive or actor.out_of_game or target == null or not target.alive or target.out_of_game or resolver.is_resolution_stopped():
		return
	# 武器阶段上下文；dodged 可由贯石斧等装备在支付费用后改写。
	var weapon_context: Dictionary = context.duplicate(true)
	weapon_context["dodged"] = dodged
	# 当前武器定义；装备文件自行决定是否暂停或替换后续流程。
	var weapon_definition: CardDefinition = host.get_equipment_definition(actor.player_id, "weapon")
	if weapon_definition != null and weapon_definition.on_slash_dodged(self, weapon_context):
		return
	continue_after_weapon_dodged(weapon_context)


## 在武器处理【闪】结果后继续；仍被抵消则结束，否则进入伤害前武器钩子。
func continue_after_weapon_dodged(context: Dictionary) -> void:
	# 目标状态；用于记录【闪】抵消日志。
	var target: PlayerState = state.get_player(int(context.get("target_id", -1)))
	if target == null or not target.alive or target.out_of_game or resolver.is_resolution_stopped():
		return
	if bool(context.get("dodged", false)):
		host.emit_rule_timing("shaMiss", int(context.get("actor_id", -1)), int(context.get("actor_id", -1)), target.player_id, context)
		host.add_log("%s打出【闪】抵消了【杀】。" % target.display_name)
		return
	host.emit_rule_timing("shaHit", int(context.get("actor_id", -1)), int(context.get("actor_id", -1)), target.player_id, context)
	# 当前武器定义；寒冰剑等替代伤害效果在自身文件接管。
	var weapon_definition: CardDefinition = host.get_equipment_definition(int(context.get("actor_id", -1)), "weapon")
	if weapon_definition != null and weapon_definition.on_slash_before_damage(self, context):
		return
	continue_slash_damage(context)


## 在武器费用或效果引发嵌套选择后恢复指定【杀】阶段；没有屏障时立即继续，存在屏障时只登记可序列化步骤。
func continue_or_defer_after_weapon(resume_stage: String, context: Dictionary) -> void:
	if host.has_pending_card_choice():
		host.defer_slash_continuation(resume_stage, context)
		return
	if resume_stage == "after_weapon_targeted":
		continue_after_weapon_targeted(context)
	elif resume_stage == "after_weapon_dodged":
		continue_after_weapon_dodged(context)


## 造成【杀】伤害并在伤害完整结束后执行武器后续钩子。
func continue_slash_damage(context: Dictionary) -> void:
	# 当前【杀】实体；伤害记录使用实体自身定义 ID。
	var card: CardInstance = _find_card(int(context.get("slash_card_uid", -1)))
	if card == null or resolver.is_resolution_stopped():
		return
	# 【杀】造成伤害前专属时机；取消或中立化时本次目标不进入通用伤害流程。
	var damage_timing: RuleEvent = host.emit_rule_timing("shaDamage", int(context.get("actor_id", -1)), int(context.get("actor_id", -1)), int(context.get("target_id", -1)), context)
	if damage_timing != null and (damage_timing.cancelled or damage_timing.neutralized):
		return
	# 判定、选牌等可选技能必须在真正扣减体力前完成；恢复时会重新读取本目标最新技能伤害加值。
	if host.has_pending_card_choice() or (host.has_method("has_pending_judgment_request") and bool(host.call("has_pending_judgment_request"))):
		host.defer_slash_continuation("after_sha_damage", damage_timing.data if damage_timing != null else context)
		return
	continue_after_sha_damage(damage_timing.data if damage_timing != null else context)


## 在 shaDamage 的全部可选技能与判定完成后造成伤害；目标加值按最新权威状态重读，避免异步判定沿用旧数值。
func continue_after_sha_damage(context: Dictionary) -> void:
	# 当前【杀】实体；等待期间已经离开全部权威区域时原伤害不再恢复。
	var card: CardInstance = _find_card(int(context.get("slash_card_uid", -1)))
	if card == null or resolver.is_resolution_stopped():
		return
	# 当前目标独立技能加值；剑势等效果在 shaDamage 判定完成后写入，不能重复叠加请求建立前已经读取的值。
	var current_target_damage_bonus: int = int(host.call("get_card_target_damage_bonus", int(context.get("parent_card_uid", -1)), int(context.get("target_id", -1)))) if host.has_method("get_card_target_damage_bonus") else int(context.get("applied_target_damage_bonus", 0))
	# 本张【杀】的酒等共享基础伤害；与目标加值分离保存，可确保多目标牌互不污染。
	var final_damage_amount: int = maxi(int(context.get("base_damage_amount", context.get("damage_amount", 1))) + current_target_damage_bonus, 0)
	context["damage_amount"] = final_damage_amount
	context["applied_target_damage_bonus"] = current_target_damage_bonus
	# 实际造成伤害的逻辑牌目标数；普通多目标【杀】保留整张牌的目标数，外部生成的单目标【杀】保持1。
	context["damage_card_target_count"] = maxi(int(context.get("damage_card_target_count", 1)), 1)
	host.damage(int(context.get("actor_id", -1)), int(context.get("target_id", -1)), final_damage_amount, str(context.get("nature", "normal")), card.definition_id, false, bool(context.get("ignore_armor", false)), context)
	if resolver.is_resolution_stopped():
		return
	# 伤害后的目标状态；死亡目标不再执行任何伤害后装备效果。
	var target: PlayerState = state.get_player(int(context.get("target_id", -1)))
	if target == null or not target.alive:
		return
	# 当前武器定义；伤害后的选择和处理全部由装备文件拥有。
	var weapon_definition: CardDefinition = host.get_equipment_definition(int(context.get("actor_id", -1)), "weapon")
	if weapon_definition != null and not weapon_definition.uses_damage_timing_trigger():
		weapon_definition.on_slash_damage_finished(self, context)


## 恢复【杀】通用响应或把武器专属响应交回创建请求的装备定义。
func continue_response(context: Dictionary, response_card: CardInstance) -> bool:
	# 响应用途；slash_response 属于通用流程，其他 kind 由装备文件识别。
	var response_kind: String = str(context.get("kind", ""))
	if response_kind == "slash_response":
		_finish_slash_response(context, response_card != null)
		return true
	# 创建响应的装备定义 ID；上下文缺失时不猜测当前武器。
	var equipment_definition_id: String = str(context.get("equipment_definition_id", ""))
	# 创建响应的装备定义；等待期间换装也能由原定义验证实体 UID 后安全拒绝。
	var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_definition_id)
	return equipment_definition != null and equipment_definition.continue_slash_response(self, context, response_card)


## 恢复武器【杀】钩子创建的普通选牌；共享组件不识别任何具体选择 kind。
func continue_choice(context: Dictionary, selected_uids: Array[int]) -> bool:
	# 创建选择的装备定义 ID；每个装备文件只处理自己的 kind。
	var equipment_definition_id: String = str(context.get("equipment_definition_id", ""))
	# 创建选择的装备定义；旧请求由装备文件自行复核实体 UID 与当前状态。
	var equipment_definition: CardDefinition = GameDatabase.get_card_definition(equipment_definition_id)
	return equipment_definition != null and equipment_definition.continue_slash_choice(self, context, selected_uids)


## 按稳定 UID 查找任意权威区域中的实体牌；异步【杀】可能已经作为响应牌进入弃牌堆。
func _find_card(card_uid: int) -> CardInstance:
	for processing_card: CardInstance in state.processing_area:
		if processing_card.uid == card_uid:
			return processing_card
	for discarded_card: CardInstance in state.discard_pile:
		if discarded_card.uid == card_uid:
			return discarded_card
	for player: PlayerState in state.players:
		for hand_card: CardInstance in player.hand:
			if hand_card.uid == card_uid:
				return hand_card
		for equipment_variant: Variant in player.equipment.values():
			# 当前装备实体；响应恢复只按 UID 比较，不修改装备区。
			var equipment_card: CardInstance = equipment_variant as CardInstance
			if equipment_card.uid == card_uid:
				return equipment_card
		for judgment_card: CardInstance in player.judgment_area:
			if judgment_card.uid == card_uid:
				return judgment_card
		for stored_card: CardInstance in player.wooden_ox_storage:
			if stored_card.uid == card_uid:
				return stored_card
	return null
