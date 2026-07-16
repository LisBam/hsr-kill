class_name SlashCardEffect
extends RefCounted

## 【杀】牌族共享效果组件。普通【杀】、火【杀】与雷【杀】只复用规则流程，属性和静态信息仍由各自卡牌文件提供。

## 当前卡牌效果调度器；只提供通用停止判断、结束区域与卡牌源码恢复分发。
var resolver: CardEffectResolver

## 对局控制器规则端口；所有摸牌、伤害、响应和区域移动都通过该端口执行。
var host: Object

## 当前权威对局状态；只读取玩家和公共处理区，不替换状态对象。
var state: GameState


## 绑定本次效果使用的通用调度器；组件生命周期只覆盖一次同步执行或一次异步恢复。
func _init(effect_resolver: CardEffectResolver) -> void:
	resolver = effect_resolver
	host = effect_resolver.host
	state = effect_resolver.state


## 结算整张【杀】；兼容不使用逐目标事件树的调用路径。
func resolve(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	# 使用者状态；酒加值在声明并结算本张【杀】时一次性消耗。
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null:
		return "discard"
	# 本张【杀】对所有目标共享的伤害基数。
	var base_damage: int = 1 + actor.wine_bonus
	actor.wine_bonus = 0
	# 当前【杀】属性；normal、fire 或 thunder。
	var nature: String = str(GameDatabase.get_card(card.definition_id).get("nature", "normal"))
	# 当前武器定义；是否忽略防具由装备卡牌源码提供。
	var weapon_definition: CardDefinition = host.get_equipment_definition(actor_id, "weapon")
	# 本张【杀】是否忽略防具；该值对整张多目标【杀】保持一致。
	var ignore_armor: bool = weapon_definition != null and weapon_definition.slash_ignores_armor()
	for target_id: int in target_ids:
		if resolver.is_resolution_stopped():
			break
		resolve_external_target(card, actor_id, target_id, base_damage, nature, ignore_armor)
	return resolver.default_destination()


## 使用整张【杀】预先确定的共享参数结算一个目标；异步请求出现时返回 pending。
func resolve_target(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> String:
	resolve_external_target(card, actor_id, target_id, damage_amount, nature, ignore_armor)
	return resolver.default_destination()


## 供【借刀杀人】、青龙偃月刀等规则使用实体【杀】时复用完整单目标流程。
func resolve_external_target(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> void:
	if resolver.is_resolution_stopped():
		return
	# 攻击者状态；用于武器触发与日志。
	var actor: PlayerState = state.get_player(actor_id)
	# 目标状态；死亡目标会直接跳过后续结算。
	var target: PlayerState = state.get_player(target_id)
	if actor == null or target == null or not target.alive:
		return

	# 攻击者性别；unknown 不参与雌雄双股剑的异性比较。
	var actor_gender: String = host.get_player_gender(actor_id)
	# 目标性别；只有双方均为明确二元性别且不同才触发。
	var target_gender: String = host.get_player_gender(target_id)
	if state.processing_area.has(card) and host.player_has_equipment(actor_id, "cixiong") and actor_gender in ["male", "female"] and target_gender in ["male", "female"] and actor_gender != target_gender:
		# 雌雄双股剑触发上下文；所有字段可序列化，发动后再进入目标弃牌或来源摸牌步骤。
		var cixiong_context: Dictionary = {
			"kind":"cixiong_trigger",
			"parent_card_uid":card.uid,
			"actor_id":actor_id,
			"target_id":target_id,
			"damage_amount":damage_amount,
			"nature":nature,
			"ignore_armor":ignore_armor,
		}
		# 是否发动雌雄双股剑；非锁定装备必须显式选择。
		var cixiong_activated: bool = host.request_equipment_trigger(actor_id, "cixiong", "雌雄双股剑", "是否发动【雌雄双股剑】？", cixiong_context, true)
		if resolver.is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_cixiong_trigger(cixiong_context, cixiong_activated)
		return
	_continue_slash_after_cixiong(card, actor_id, target_id, damage_amount, nature, ignore_armor)


## 按选择用途恢复【杀】内部的装备触发；返回 true 表示已识别当前上下文。
func continue_choice(context: Dictionary, selected_uids: Array[int]) -> bool:
	# 选择用途；只接受由【杀】流程创建的稳定 kind。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "cixiong_trigger":
		continue_cixiong_trigger(context, not selected_uids.is_empty())
	elif choice_kind == "cixiong_discard":
		continue_cixiong_discard(context, selected_uids)
	elif choice_kind == "guanshi_cost":
		continue_guanshi_cost(context, selected_uids)
	elif choice_kind == "hanbing_cards":
		continue_hanbing_cards(context, selected_uids)
	elif choice_kind == "qilin_mount":
		continue_qilin_mount(context, selected_uids)
	else:
		return false
	return true


## 恢复【闪】或青龙偃月刀追加【杀】响应；返回 true 表示已识别当前上下文。
func continue_response(context: Dictionary, response_card: CardInstance) -> bool:
	# 响应用途；响应牌已由控制器验证并移入弃牌堆。
	var response_kind: String = str(context.get("kind", ""))
	if response_kind == "slash_response":
		continue_slash_response(context, response_card != null)
		return true
	if response_kind == "qinglong_response":
		if response_card != null and not resolver.is_resolution_stopped():
			# 追击者 ID；青龙偃月刀响应者就是原【杀】使用者。
			var actor_id: int = int(context.get("responder_id", -1))
			host.add_log("%s发动【青龙偃月刀】追击。" % state.get_player(actor_id).display_name)
			resolve_external_target(response_card, actor_id, int(context.get("target_id", -1)), 1, str(GameDatabase.get_card(response_card.definition_id).get("nature", "normal")), bool(context.get("ignore_armor", false)))
		return true
	return false


## 恢复雌雄双股剑发动选择；发动后由目标选择弃一张手牌或让使用者摸一张。
func continue_cixiong_trigger(context: Dictionary, activated: bool) -> void:
	# 原【杀】实体；必须仍在处理区，旧选择不能恢复已经结束的攻击。
	var card: CardInstance = resolver.find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 攻击者 ID；用于摸牌和继续攻击。
	var actor_id: int = int(context.get("actor_id", -1))
	# 目标 ID；用于弃牌与继续响应。
	var target_id: int = int(context.get("target_id", -1))
	# 当前目标；等待期间死亡或离场时停止本目标结算。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
		return
	if activated:
		if target.hand.is_empty():
			host.draw(actor_id, 1)
		else:
			# 目标手牌候选；木牛“粮”和装备不属于此弃牌选项。
			var candidates: Array[Dictionary] = host.get_hand_candidates(target_id, target_id)
			# 目标选择上下文；空选择表示拒绝弃牌并让攻击者摸一张牌。
			var discard_context: Dictionary = context.duplicate(true)
			discard_context["kind"] = "cixiong_discard"
			discard_context["ai_prefer_select"] = true
			# 目标弃牌选择；允许取消，恢复时再次校验 UID 所在区域。
			var selected_uids: Array[int] = host.request_card_choice(target_id, "雌雄双股剑", "请弃置一张手牌，否则对方摸一张牌。", candidates, 0, 1, true, discard_context)
			if resolver.is_resolution_stopped() or host.has_pending_card_choice():
				return
			continue_cixiong_discard(discard_context, selected_uids)
			return
	_continue_slash_after_cixiong(card, actor_id, target_id, int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)))


## 恢复雌雄双股剑目标弃牌；弃牌失败或取消时改为攻击者摸一张。
func continue_cixiong_discard(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原【杀】实体；响应必须仍属于当前处理区结算。
	var card: CardInstance = resolver.find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 目标实际弃置数量；数量为1才视为接受弃牌选项。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count != 1:
		host.draw(int(context.get("actor_id", -1)), 1)
	_continue_slash_after_cixiong(card, int(context.get("actor_id", -1)), int(context.get("target_id", -1)), int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)))


## 在雌雄双股剑步骤结束后继续防具检查与【闪】响应。
func _continue_slash_after_cixiong(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> void:
	# 当前目标；装备选择等待期间可能已经死亡或离场。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or resolver.is_resolution_stopped():
		return
	if not ignore_armor:
		# 目标防具定义；具体无效条件由防具卡牌源码判断。
		var armor_definition: CardDefinition = host.get_equipment_definition(target_id, "armor")
		if armor_definition != null and armor_definition.blocks_slash(card, nature):
			host.add_log("%s的防具令此【杀】无效。" % target.display_name)
			return
	if host.has_method("is_card_target_direct_hit") and bool(host.is_card_target_direct_hit(card.uid, target_id)):
		_finish_single_slash_response(card, actor_id, target_id, damage_amount, nature, ignore_armor, false)
		return
	# 响应恢复上下文；所有字段可序列化并通过父牌 UID 回到本组件。
	var response_context: Dictionary = {"kind":"slash_response", "parent_card_uid":card.uid, "card_definition_id":card.definition_id, "actor_id":actor_id, "target_id":target_id, "damage_amount":damage_amount, "nature":nature, "ignore_armor":ignore_armor}
	# 目标打出的实体【闪】；为空可能表示放弃，也可能表示等待人类选择。
	var response_card: CardInstance = host.request_response_card(target_id, "shan", "是否打出【闪】响应【杀】？", response_context)
	if resolver.is_resolution_stopped() or host.has_pending_card_choice():
		return
	_finish_single_slash_response(card, actor_id, target_id, damage_amount, nature, ignore_armor, response_card != null)


## 在【闪】询问完成后继续结算贯石斧、青龙偃月刀、寒冰剑、伤害与麒麟弓。
func _finish_single_slash_response(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool, dodged: bool) -> void:
	# 攻击者状态；响应等待期间可能已经由插入结算改变状态。
	var actor: PlayerState = state.get_player(actor_id)
	# 目标状态；若响应插入结算使其离场则停止本次【杀】。
	var target: PlayerState = state.get_player(target_id)
	if actor == null or target == null or not target.alive or resolver.is_resolution_stopped():
		return
	if dodged and state.processing_area.has(card) and host.player_has_equipment(actor_id, "guanshi") and host.get_hand_equipment_card_count(actor_id) >= 2:
		# 贯石斧费用候选；攻击者可选择两张手牌或装备。
		var candidates: Array[Dictionary] = host.get_hand_equipment_candidates(actor_id, actor_id)
		# 贯石斧恢复上下文；保存【闪】后的完整攻击参数。
		var guanshi_context: Dictionary = {"kind":"guanshi_cost", "parent_card_uid":card.uid, "actor_id":actor_id, "target_id":target_id, "damage_amount":damage_amount, "nature":nature, "ignore_armor":ignore_armor, "ai_prefer_select":true}
		# 两张费用牌；允许取消但确认时必须正好选择2张。
		var selected_uids: Array[int] = host.request_card_choice(actor_id, "贯石斧", "是否弃置两张牌发动【贯石斧】？", candidates, 2, 2, true, guanshi_context)
		if resolver.is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_guanshi_cost(guanshi_context, selected_uids)
		return
	_continue_slash_after_guanshi(card, actor_id, target_id, damage_amount, nature, ignore_armor, dodged)


## 恢复贯石斧费用选择；完整支付两张费用才令原【杀】继续生效。
func continue_guanshi_cost(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原【杀】实体；旧费用请求不能操作已经结束的攻击。
	var card: CardInstance = resolver.find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 实际支付数量；等待期间牌已移动会导致支付失败。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("actor_id", -1)), selected_uids)
	# 是否仍被闪抵消；完整支付两张费用时改为 false。
	var dodged: bool = discarded_count != 2
	if not dodged:
		host.add_log("%s发动【贯石斧】，令【杀】继续生效。" % state.get_player(int(context.get("actor_id", -1))).display_name)
	_continue_slash_after_guanshi(card, int(context.get("actor_id", -1)), int(context.get("target_id", -1)), int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)), dodged)


## 在贯石斧选择结束后处理青龙偃月刀或进入伤害前的寒冰剑选择。
func _continue_slash_after_guanshi(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool, dodged: bool) -> void:
	# 攻击者状态；用于日志和装备触发。
	var actor: PlayerState = state.get_player(actor_id)
	# 目标状态；用于响应结果与寒冰剑发动条件。
	var target: PlayerState = state.get_player(target_id)
	if actor == null or target == null or not target.alive or resolver.is_resolution_stopped():
		return
	if dodged:
		host.add_log("%s打出【闪】抵消了【杀】。" % target.display_name)
		if host.player_has_equipment(actor_id, "qinglong"):
			# 青龙偃月刀追击上下文；响应后仍通过原【杀】定义恢复。
			var qinglong_context: Dictionary = {"kind":"qinglong_response", "responder_id":actor_id, "target_id":target_id, "parent_card_uid":card.uid, "ignore_armor":ignore_armor}
			# 青龙偃月刀追加使用的实体【杀】；为空表示放弃发动。
			var follow_slash: CardInstance = host.request_response_card(actor_id, "sha", "是否发动【青龙偃月刀】继续打出【杀】？", qinglong_context)
			if host.has_pending_card_choice():
				return
			if follow_slash != null:
				host.add_log("%s发动【青龙偃月刀】追击。" % actor.display_name)
				resolve_external_target(follow_slash, actor_id, target_id, 1, str(GameDatabase.get_card(follow_slash.definition_id).get("nature", "normal")), ignore_armor)
		return
	if state.processing_area.has(card) and host.player_has_equipment(actor_id, "hanbing") and host.get_hand_equipment_card_count(target_id) >= 1:
		# 寒冰剑目标牌候选；发动者可选择目标一至两张手牌或装备。
		var candidates: Array[Dictionary] = host.get_hand_equipment_candidates(actor_id, target_id)
		# 寒冰剑恢复上下文；选择成功时防止伤害，取消时继续伤害。
		var hanbing_context: Dictionary = {"kind":"hanbing_cards", "parent_card_uid":card.uid, "actor_id":actor_id, "target_id":target_id, "damage_amount":damage_amount, "nature":nature, "ignore_armor":ignore_armor, "ai_prefer_select":target.hp > 1}
		# 目标弃牌选择；最多两张且允许取消。
		var selected_uids: Array[int] = host.request_card_choice(actor_id, "寒冰剑", "是否发动【寒冰剑】并弃置目标至多两张牌？", candidates, 0, mini(2, candidates.size()), true, hanbing_context)
		if resolver.is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_hanbing_cards(hanbing_context, selected_uids)
		return
	_continue_slash_after_hanbing(card, actor_id, target_id, damage_amount, nature, ignore_armor)


## 恢复寒冰剑选牌；至少成功弃置一张时防止伤害。
func continue_hanbing_cards(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原【杀】实体；旧请求不能恢复已经结束的伤害事件。
	var card: CardInstance = resolver.find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 实际弃置数量；最多两张，至少一张成功才视为发动。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count > 0:
		host.add_log("%s发动【寒冰剑】防止伤害并弃置目标至多两张牌。" % state.get_player(int(context.get("actor_id", -1))).display_name)
		return
	_continue_slash_after_hanbing(card, int(context.get("actor_id", -1)), int(context.get("target_id", -1)), int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)))


## 在寒冰剑步骤结束后造成伤害，并在目标存活时询问麒麟弓。
func _continue_slash_after_hanbing(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> void:
	host.damage(actor_id, target_id, damage_amount, nature, card.definition_id, false, ignore_armor)
	if resolver.is_resolution_stopped():
		return
	# 伤害后的最新目标状态；伤害、濒死和技能可能改变其存活或装备。
	var target: PlayerState = state.get_player(target_id)
	if state.processing_area.has(card) and target != null and target.alive and host.player_has_equipment(actor_id, "qilin"):
		# 可弃置坐骑；没有坐骑时不创建空发动窗口。
		var candidates: Array[Dictionary] = host.get_mount_candidates(actor_id, target_id)
		if candidates.is_empty():
			return
		# 麒麟弓恢复上下文；选择一张坐骑表示发动。
		var qilin_context: Dictionary = {"kind":"qilin_mount", "parent_card_uid":card.uid, "actor_id":actor_id, "target_id":target_id, "ai_prefer_select":true}
		# 坐骑选择；允许取消且不能自动弃置第一张坐骑。
		var selected_uids: Array[int] = host.request_card_choice(actor_id, "麒麟弓", "是否发动【麒麟弓】弃置目标一张坐骑？", candidates, 0, 1, true, qilin_context)
		if resolver.is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_qilin_mount(qilin_context, selected_uids)


## 恢复麒麟弓坐骑选择；只弃置明确选择且仍位于目标装备区的实体牌。
func continue_qilin_mount(context: Dictionary, selected_uids: Array[int]) -> void:
	if selected_uids.is_empty():
		return
	# 实际弃置数量；候选只包含目标坐骑。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count == 1:
		host.add_log("%s发动【麒麟弓】弃置目标一张坐骑。" % state.get_player(int(context.get("actor_id", -1))).display_name)


## 由异步【闪】选择恢复一张【杀】；父牌必须仍位于公共处理区。
func continue_slash_response(context: Dictionary, dodged: bool) -> void:
	# 原始【杀】实体；旧请求不能恢复已经结束的结算。
	var slash_card: CardInstance = resolver.find_processing_card(int(context.get("parent_card_uid", -1)))
	if slash_card == null:
		return
	_finish_single_slash_response(slash_card, int(context.get("actor_id", -1)), int(context.get("target_id", -1)), int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)), dodged)
