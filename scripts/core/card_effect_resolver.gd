class_name CardEffectResolver
extends RefCounted

## 通用卡牌效果执行器。所有效果只通过 MatchController 暴露的规则操作端口改变状态。

## 对局控制器端口；提供摸牌、伤害、移动与响应等权威操作。
var host: Object

## 当前权威状态；用于读取玩家、装备和目标状态，不直接替换状态对象。
var state: GameState


## 绑定对局操作端口与状态；执行器不负责二者的生命周期。
func _init(match_host: Object, game_state: GameState) -> void:
	host = match_host
	state = game_state


## 执行一张已经进入处理区的牌；具体函数来自 game_data/cards 中对应卡牌文件。
func resolve(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if _is_resolution_stopped():
		return "consumed"
	# 当前卡牌源码定义；数据库按稳定 ID 自动发现，不存在表示牌堆或存档引用已经失效。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if definition == null:
		host.add_log("卡牌【%s】缺少源码定义，效果未执行。" % card.definition_id)
		return "discard"
	return definition.resolve(self, card, actor_id, target_ids)


## 执行活动逐目标结算的当前目标；特殊卡牌可在自身文件读取整张牌共享上下文。
func resolve_target(card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	if _is_resolution_stopped():
		return "consumed"
	# 当前卡牌源码定义；逐目标入口与普通整牌入口使用同一个自动发现结果。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if definition == null:
		return "discard"
	return definition.resolve_target(self, card, actor_id, target_id, resolution_context)


## 处理没有主动使用效果的响应牌；实体响应由统一响应流程消费，本入口只提供安全默认终点。
func resolve_no_effect(_card: CardInstance, _actor_id: int, _target_ids: Array[int]) -> String:
	return "discard"


## 结算整张【杀】；迁移期独立调用会遍历目标，正式事件树通常通过卡牌文件的 resolve_target 逐个处理。
func resolve_slash(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	_resolve_slash_card(card, actor_id, target_ids)
	return _default_destination()


## 结算回复类基本牌；每名有效目标固定回复1点体力。
func resolve_peach(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _is_resolution_stopped():
			break
		host.recover(actor_id, target_id, 1, card.definition_id)
	return _default_destination()


## 结算【酒】的出牌阶段增益；本回合下一张【杀】伤害基数固定增加1点。
func resolve_wine(_card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	# 使用者状态；每名玩家在自己的出牌阶段正常使用【酒】仍受每回合一次限制。
	var actor: PlayerState = state.get_player(actor_id)
	# 【酒】目标状态；规则层限定为已受伤的使用者本人，使加值不会错误授予其他角色。
	var wine_target: PlayerState = state.get_player(target_ids[0])
	if actor == null or wine_target == null:
		return "discard"
	actor.wine_used = true
	wine_target.wine_bonus = 1
	host.add_log("%s使用【酒】，本回合下一张【杀】伤害+1。" % actor.display_name)
	return _default_destination()


## 结算装备牌进入对应装备槽；装备替换与离开装备区效果仍由控制器统一处理。
func resolve_equipment(card: CardInstance, actor_id: int, _target_ids: Array[int]) -> String:
	host.equip_from_processing(actor_id, card)
	return "equipment"


## 结算延时锦囊进入目标判定区；实际判定效果在目标判定阶段执行。
func resolve_delayed(card: CardInstance, _actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	host.place_delayed_trick(target_ids[0], card)
	return "judgment"


## 结算摸两张牌效果；每个目标在无懈检查通过后固定摸2张牌。
func resolve_draw_two(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		host.draw_cards(target_id, 2)
	return _default_destination()


## 结算弃置目标区域一张牌效果；出现统一选牌请求时返回 pending。
func resolve_discard_target(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		host.discard_one_from_player(actor_id, target_id, card.uid)
		if host.has_pending_card_choice():
			return "pending"
	return _default_destination()


## 结算获得目标区域一张牌效果；出现统一选牌请求时返回 pending。
func resolve_steal_target(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		host.take_one_from_player(actor_id, target_id, card.uid)
		if host.has_pending_card_choice():
			return "pending"
	return _default_destination()


## 结算【决斗】；双方轮流响应【杀】，首先未响应者受到1点伤害。
func resolve_duel(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		_resolve_duel(card.uid, actor_id, target_id)
	return _default_destination()


## 结算【借刀杀人】；目标数组固定为持刀者与被杀者两项。
func resolve_borrow_sword(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.size() == 2 and not host.resolve_trick_negation(actor_id, target_ids[0], card.definition_id):
		if not _is_resolution_stopped():
			_resolve_borrow_sword(actor_id, target_ids[0], target_ids[1])
	return _default_destination()


## 结算要求每名目标响应【闪】的群体锦囊。
func resolve_aoe_dodge(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	_resolve_aoe(card, actor_id, target_ids, "shan")
	return _default_destination()


## 结算要求每名目标响应【杀】的群体锦囊。
func resolve_aoe_slash(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	_resolve_aoe(card, actor_id, target_ids, "sha")
	return _default_destination()


## 结算群体回复效果；每名未被无懈抵消的目标固定回复1点体力。
func resolve_heal_all(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		host.recover(actor_id, target_id, 1, card.definition_id)
	return _default_destination()


## 结算【五谷丰登】公共展示与依次选择流程。
func resolve_harvest(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	host.resolve_harvest_choices(card.uid, actor_id, target_ids)
	return _default_destination()


## 结算连环状态切换；每名未被无懈抵消的目标在横置与重置之间切换一次。
func resolve_chain(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		# 当前目标状态；铁索连环令其横置状态在两种状态间切换。
		var target: PlayerState = state.get_player(target_id)
		if target == null:
			continue
		target.chained = not target.chained
		host.add_log("%s%s。" % [target.display_name, "进入连环状态" if target.chained else "解除连环状态"])
	return _default_destination()


## 结算【火攻】展示与同花色弃牌流程；选择会通过统一请求暂停当前内容事件。
func resolve_fire_attack(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		host.resolve_fire_attack_choice(card.uid, actor_id, target_id)
		if host.has_pending_card_choice():
			return "pending"
	return _default_destination()


## 结算【水淹七军】弃装备或受伤选择；选择会通过统一请求暂停当前内容事件。
func resolve_flood(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if _should_skip_trick_target(card, actor_id, target_id):
			continue
		host.resolve_flood_choice(card.uid, actor_id, target_id)
		if host.has_pending_card_choice():
			return "pending"
	return _default_destination()


## 判断当前锦囊目标是否因游戏结束、等待选择或无懈可击而跳过后续效果。
func _should_skip_trick_target(card: CardInstance, actor_id: int, target_id: int) -> bool:
	if _is_resolution_stopped():
		return true
	if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
		return true
	return _is_resolution_stopped()


## 返回普通牌的统一结束区域；存在选择时保持 pending，否则进入弃牌堆。
func _default_destination() -> String:
	return "pending" if host.has_pending_card_choice() else "discard"


## 返回当前结算是否必须立即停止；游戏结束后任何牌、伤害、响应或区域移动都不得继续执行。
func _is_resolution_stopped() -> bool:
	return state == null or state.game_over or host.has_pending_card_choice()


## 按稳定 UID 查找仍在公共处理区的原效果牌；异步装备选择只能恢复当前仍有效的卡牌事件。
func _find_processing_card(card_uid: int) -> CardInstance:
	for processing_card: CardInstance in state.processing_area:
		if processing_card.uid == card_uid:
			return processing_card
	return null


## 结算【杀】，包括酒加值、武器触发、防具无效与响应【闪】。
func _resolve_slash_card(card: CardInstance, actor_id: int, target_ids: Array[int]) -> void:
	# 使用者状态；酒加值在声明并结算本张【杀】时一次性消耗。
	var actor: PlayerState = state.get_player(actor_id)
	# 本张【杀】对所有目标共享的伤害基数。
	var base_damage: int = 1 + actor.wine_bonus
	actor.wine_bonus = 0
	# 当前【杀】属性；normal、fire 或 thunder。
	var nature: String = str(GameDatabase.get_card(card.definition_id).get("nature", "normal"))
	# 青釭剑忽略每个目标的防具直到对应目标结算结束。
	var ignore_armor: bool = host.player_has_equipment(actor_id, "qinggang")
	for target_id: int in target_ids:
		if _is_resolution_stopped():
			break
		_resolve_single_slash(card, actor_id, target_id, base_damage, nature, ignore_armor)


## 使用整张【杀】预先确定的共享参数结算一个目标；目标出现响应选择时返回 pending，否则返回 discard 表示本目标完成。
func resolve_slash_target(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> String:
	_resolve_single_slash(card, actor_id, target_id, damage_amount, nature, ignore_armor)
	return "pending" if host.has_pending_card_choice() else "discard"


## 结算【杀】对一个目标的完整流程。
func _resolve_single_slash(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> void:
	if _is_resolution_stopped():
		return
	# 攻击者状态；用于武器触发与日志。
	var actor: PlayerState = state.get_player(actor_id)
	# 目标状态；死亡目标会直接跳过后续结算。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
		return

	# 雌雄双股剑的异性触发；目标有手牌时自动弃一张，否则攻击者摸一张。
	# 攻击者性别；unknown 不参与雌雄双股剑的异性比较。
	var actor_gender: String = host.get_player_gender(actor_id)
	# 目标性别；只有双方均为明确二元性别且不同才触发。
	var target_gender: String = host.get_player_gender(target_id)
	if state.processing_area.has(card) and host.player_has_equipment(actor_id, "cixiong") and actor_gender in ["male", "female"] and target_gender in ["male", "female"] and actor_gender != target_gender:
		# 雌雄双股剑触发上下文；所有字段可序列化，玩家选择发动后再进入目标弃牌或来源摸牌步骤。
		var cixiong_context: Dictionary = {
			"kind":"cixiong_trigger",
			"parent_card_uid":card.uid,
			"actor_id":actor_id,
			"target_id":target_id,
			"damage_amount":damage_amount,
			"nature":nature,
			"ignore_armor":ignore_armor,
		}
		# 是否发动雌雄双股剑；非锁定装备必须显式选择，取消不会执行弃牌或摸牌。
		var cixiong_activated: bool = host.request_equipment_trigger(actor_id, "cixiong", "雌雄双股剑", "是否发动【雌雄双股剑】？", cixiong_context, true)
		if _is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_cixiong_trigger(cixiong_context, cixiong_activated)
		return
	_continue_slash_after_cixiong(card, actor_id, target_id, damage_amount, nature, ignore_armor)


## 恢复雌雄双股剑发动选择；发动后由目标在同一规则链中选择弃一张手牌或取消让使用者摸牌。
func continue_cixiong_trigger(context: Dictionary, activated: bool) -> void:
	# 原【杀】实体；必须仍在处理区，旧选择不能恢复已经结束的攻击。
	var card: CardInstance = _find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 攻击者与目标 ID；用于后续弃牌、摸牌和继续响应【闪】。
	var actor_id: int = int(context.get("actor_id", -1))
	var target_id: int = int(context.get("target_id", -1))
	# 当前目标；等待期间死亡或离场时停止本目标结算。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive:
		return
	if activated:
		if target.hand.is_empty():
			host.draw_cards(actor_id, 1)
		else:
			# 目标手牌候选；只能选择普通手牌，木牛“粮”和装备不属于此弃牌选项。
			var candidates: Array[Dictionary] = host.get_hand_candidates(target_id, target_id)
			# 目标选择上下文；空选择表示拒绝弃牌并让攻击者摸一张牌。
			var discard_context: Dictionary = context.duplicate(true)
			discard_context["kind"] = "cixiong_discard"
			discard_context["ai_prefer_select"] = true
			# 目标弃牌选择；允许取消，选中后仍由规则层再次校验 UID 所在区域。
			var selected_uids: Array[int] = host.request_card_choice(target_id, "雌雄双股剑", "请弃置一张手牌，否则对方摸一张牌。", candidates, 0, 1, true, discard_context)
			if _is_resolution_stopped() or host.has_pending_card_choice():
				return
			continue_cixiong_discard(discard_context, selected_uids)
			return
	_continue_slash_after_cixiong(card, actor_id, target_id, int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)))


## 恢复雌雄双股剑目标弃牌；成功弃牌后继续【杀】，取消或牌已移动则改为攻击者摸一张。
func continue_cixiong_discard(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原【杀】实体；响应必须仍属于当前处理区结算。
	var card: CardInstance = _find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 目标实际弃置数量；候选只有普通手牌，数量为1才视为接受弃牌选项。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count != 1:
		host.draw_cards(int(context.get("actor_id", -1)), 1)
	_continue_slash_after_cixiong(card, int(context.get("actor_id", -1)), int(context.get("target_id", -1)), int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)))


## 在雌雄双股剑步骤结束后继续防具检查与【闪】响应；该入口避免异步恢复时重复询问装备。
func _continue_slash_after_cixiong(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> void:
	# 当前目标；装备选择等待期间可能已经死亡或离场。
	var target: PlayerState = state.get_player(target_id)
	if target == null or not target.alive or _is_resolution_stopped():
		return

	if not ignore_armor:
		# 目标防具 ID；无防具时为空字符串。
		var armor_id: String = host.get_equipment_id(target_id, "armor")
		if armor_id == "tengjia" and nature == "normal":
			host.add_log("%s的【藤甲】令普通【杀】无效。" % target.display_name)
			return
		if armor_id == "renwang" and card.get_color() == "black":
			host.add_log("%s的【仁王盾】令黑色【杀】无效。" % target.display_name)
			return
	# 直击目标跳过【闪】响应；武器发动、防具无效与后续伤害流程仍按原顺序完整执行。
	if host.has_method("is_card_target_direct_hit") and bool(host.is_card_target_direct_hit(card.uid, target_id)):
		_finish_single_slash_response(card, actor_id, target_id, damage_amount, nature, ignore_armor, false)
		return

	# 响应恢复上下文；无论玩家还是 AI 都先收到同一【闪】询问，再通过标准选择动作提交。
	var response_context: Dictionary = {
		"kind":"slash_response",
		"parent_card_uid":card.uid,
		"card_definition_id":card.definition_id,
		"actor_id":actor_id,
		"target_id":target_id,
		"damage_amount":damage_amount,
		"nature":nature,
		"ignore_armor":ignore_armor,
	}
	# 目标打出的实体【闪】；为空可能表示明确放弃，也可能表示正在等待人类选择。
	var response_card: CardInstance = host.request_response_card(target_id, "shan", "是否打出【闪】响应【杀】？", response_context)
	if _is_resolution_stopped() or host.has_pending_card_choice():
		return
	_finish_single_slash_response(card, actor_id, target_id, damage_amount, nature, ignore_armor, response_card != null)


## 在【闪】询问完成后继续结算贯石斧、青龙偃月刀、寒冰剑、伤害与麒麟弓。
func _finish_single_slash_response(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool, dodged: bool) -> void:
	# 攻击者状态；响应等待期间可能已经由插入结算改变状态。
	var actor: PlayerState = state.get_player(actor_id)
	# 目标状态；若响应插入结算使其离场则停止本次【杀】。
	var target: PlayerState = state.get_player(target_id)
	if actor == null or target == null or not target.alive or _is_resolution_stopped():
		return
	if dodged and state.processing_area.has(card) and host.player_has_equipment(actor_id, "guanshi") and host.get_hand_equipment_card_count(actor_id) >= 2:
		# 贯石斧费用候选；由攻击者明确选择两张手牌或装备，取消表示保留【闪】的抵消结果。
		var candidates: Array[Dictionary] = host.get_hand_equipment_candidates(actor_id, actor_id)
		# 贯石斧恢复上下文；保存【闪】后的完整攻击参数，费用支付后从此步骤继续。
		var guanshi_context: Dictionary = {"kind":"guanshi_cost", "parent_card_uid":card.uid, "actor_id":actor_id, "target_id":target_id, "damage_amount":damage_amount, "nature":nature, "ignore_armor":ignore_armor, "ai_prefer_select":true}
		# 两张费用牌；允许取消但一旦确认必须正好选择2张。
		var selected_uids: Array[int] = host.request_card_choice(actor_id, "贯石斧", "是否弃置两张牌发动【贯石斧】？", candidates, 2, 2, true, guanshi_context)
		if _is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_guanshi_cost(guanshi_context, selected_uids)
		return
	_continue_slash_after_guanshi(card, actor_id, target_id, damage_amount, nature, ignore_armor, dodged)


## 恢复贯石斧费用选择；只有两张费用均成功弃置才令原【杀】继续生效。
func continue_guanshi_cost(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原【杀】实体；旧费用请求不能操作已经结束的攻击。
	var card: CardInstance = _find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 实际支付数量；等待期间牌已移动会导致支付失败并保留【闪】结果。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("actor_id", -1)), selected_uids)
	# 是否仍被闪抵消；完整支付两张费用时改为 false。
	var dodged: bool = discarded_count != 2
	if not dodged:
		host.add_log("%s发动【贯石斧】，令【杀】继续生效。" % state.get_player(int(context.get("actor_id", -1))).display_name)
	_continue_slash_after_guanshi(card, int(context.get("actor_id", -1)), int(context.get("target_id", -1)), int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)), dodged)


## 在贯石斧选择结束后处理青龙偃月刀或进入伤害前的寒冰剑选择。
func _continue_slash_after_guanshi(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool, dodged: bool) -> void:
	# 攻击者与目标；用于日志、后续装备触发和状态有效性检查。
	var actor: PlayerState = state.get_player(actor_id)
	var target: PlayerState = state.get_player(target_id)
	if actor == null or target == null or not target.alive or _is_resolution_stopped():
		return
	if dodged:
		host.add_log("%s打出【闪】抵消了【杀】。" % target.display_name)
		if host.player_has_equipment(actor_id, "qinglong"):
			# 青龙偃月刀追击上下文；持有者仍需通过统一询问决定是否打出下一张【杀】。
			var qinglong_context: Dictionary = {"kind":"qinglong_response", "responder_id":actor_id, "target_id":target_id, "parent_card_uid":card.uid, "ignore_armor":ignore_armor}
			# 青龙偃月刀追加使用的实体【杀】；响应提交后进入弃牌堆并继续本目标结算。
			var follow_slash: CardInstance = host.request_response_card(actor_id, "sha", "是否发动【青龙偃月刀】继续打出【杀】？", qinglong_context)
			if host.has_pending_card_choice():
				return
			if follow_slash != null:
				host.add_log("%s发动【青龙偃月刀】追击。" % actor.display_name)
				_resolve_single_slash(follow_slash, actor_id, target_id, 1, str(GameDatabase.get_card(follow_slash.definition_id).get("nature", "normal")), ignore_armor)
		return

	# 寒冰剑为可选替代效果；基础 AI 在目标有至少两张牌且体力大于1时选择弃牌替代伤害。
	# 实际规则条件只要求目标手牌区或装备区有牌，不以目标体力或至少两张牌作为发动门槛。
	if state.processing_area.has(card) and host.player_has_equipment(actor_id, "hanbing") and host.get_hand_equipment_card_count(target_id) >= 1:
		# 寒冰剑目标牌候选；发动者从目标手牌区与装备区选择一至两张，取消表示正常造成伤害。
		var candidates: Array[Dictionary] = host.get_hand_equipment_candidates(actor_id, target_id)
		# 寒冰剑恢复上下文；选择成功时防止伤害，取消时从伤害步骤继续。
		var hanbing_context: Dictionary = {"kind":"hanbing_cards", "parent_card_uid":card.uid, "actor_id":actor_id, "target_id":target_id, "damage_amount":damage_amount, "nature":nature, "ignore_armor":ignore_armor, "ai_prefer_select":target.hp > 1}
		# 目标弃牌选择；最多两张且允许取消，至少选择一张才视为发动。
		var selected_uids: Array[int] = host.request_card_choice(actor_id, "寒冰剑", "是否发动【寒冰剑】并弃置目标至多两张牌？", candidates, 0, mini(2, candidates.size()), true, hanbing_context)
		if _is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_hanbing_cards(hanbing_context, selected_uids)
		return
	_continue_slash_after_hanbing(card, actor_id, target_id, damage_amount, nature, ignore_armor)


## 恢复寒冰剑选牌；至少成功弃置一张时防止伤害，取消或选择失效则正常进入伤害步骤。
func continue_hanbing_cards(context: Dictionary, selected_uids: Array[int]) -> void:
	# 原【杀】实体；旧请求不能恢复已经结束的伤害事件。
	var card: CardInstance = _find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return
	# 实际弃置数量；最多两张，至少一张成功才视为发动寒冰剑。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count > 0:
		host.add_log("%s发动【寒冰剑】防止伤害并弃置目标至多两张牌。" % state.get_player(int(context.get("actor_id", -1))).display_name)
		return
	_continue_slash_after_hanbing(card, int(context.get("actor_id", -1)), int(context.get("target_id", -1)), int(context.get("damage_amount", 1)), str(context.get("nature", "normal")), bool(context.get("ignore_armor", false)))


## 在寒冰剑步骤结束后造成伤害，并在目标仍存活时询问是否发动麒麟弓选择坐骑。
func _continue_slash_after_hanbing(card: CardInstance, actor_id: int, target_id: int, damage_amount: int, nature: String, ignore_armor: bool) -> void:
	host.damage(actor_id, target_id, damage_amount, nature, card.definition_id, false, ignore_armor)
	if _is_resolution_stopped():
		return
	# 伤害后的最新目标状态；伤害、濒死和技能可能已经改变其存活状态或装备区。
	var target: PlayerState = state.get_player(target_id)
	if state.processing_area.has(card) and target != null and target.alive and host.player_has_equipment(actor_id, "qilin"):
		# 可弃置坐骑；没有坐骑时不创建空发动窗口。
		var candidates: Array[Dictionary] = host.get_mount_candidates(actor_id, target_id)
		if candidates.is_empty():
			return
		# 麒麟弓恢复上下文；选择一张坐骑表示发动，取消表示不修改目标装备。
		var qilin_context: Dictionary = {"kind":"qilin_mount", "parent_card_uid":card.uid, "actor_id":actor_id, "target_id":target_id, "ai_prefer_select":true}
		# 坐骑选择；非锁定装备必须允许取消且不能自动弃置第一张坐骑。
		var selected_uids: Array[int] = host.request_card_choice(actor_id, "麒麟弓", "是否发动【麒麟弓】弃置目标一张坐骑？", candidates, 0, 1, true, qilin_context)
		if _is_resolution_stopped() or host.has_pending_card_choice():
			return
		continue_qilin_mount(qilin_context, selected_uids)


## 恢复麒麟弓坐骑选择；只弃置玩家明确选择且仍位于目标装备区的实体牌。
func continue_qilin_mount(context: Dictionary, selected_uids: Array[int]) -> void:
	if selected_uids.is_empty():
		return
	# 实际弃置数量；候选只包含目标坐骑，成功时记录装备发动日志。
	var discarded_count: int = host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count == 1:
		host.add_log("%s发动【麒麟弓】弃置目标一张坐骑。" % state.get_player(int(context.get("actor_id", -1))).display_name)


## 由 MatchController 在延迟选择提交后恢复一张【杀】；上下文只含可序列化规则字段。
func continue_slash_response(context: Dictionary, dodged: bool) -> void:
	# 原始【杀】实体；必须仍位于处理区，避免旧请求恢复已经结束的结算。
	var slash_card: CardInstance
	for processing_card: CardInstance in state.processing_area:
		if processing_card.uid == int(context.get("parent_card_uid", -1)):
			slash_card = processing_card
			break
	if slash_card == null:
		return
	_finish_single_slash_response(
		slash_card,
		int(context.get("actor_id", -1)),
		int(context.get("target_id", -1)),
		int(context.get("damage_amount", 1)),
		str(context.get("nature", "normal")),
		bool(context.get("ignore_armor", false)),
		dodged
	)


## 结算【决斗】的轮流出杀，任意一方首次无法打出时受到1点伤害。
func _resolve_duel(parent_card_uid: int, source_id: int, target_id: int) -> void:
	# 当前需要打出【杀】的玩家 ID；由目标先开始。
	var responder_id: int = target_id
	# 当前对手 ID；未打出【杀】时成为伤害来源。
	var opponent_id: int = source_id
	_continue_duel_exchange(parent_card_uid, responder_id, opponent_id)


## 从指定响应者继续决斗轮换；每轮都创建相同的【杀】响应询问。
func _continue_duel_exchange(parent_card_uid: int, responder_id: int, opponent_id: int) -> void:
	# 安全轮次计数；实体牌有限，但仍设置上限防止扩展技能产生死循环。
	var exchange_count: int = 0
	while exchange_count < 100 and not _is_resolution_stopped():
		exchange_count += 1
		var response_context: Dictionary = {"kind":"duel_response", "parent_card_uid":parent_card_uid, "responder_id":responder_id, "opponent_id":opponent_id}
		var response_card: CardInstance = host.request_response_card(responder_id, "sha", "请响应决斗并打出【杀】。", response_context)
		if host.has_pending_card_choice():
			return
		if response_card != null:
			# 临时交换双方；下一次由刚才的对手响应。
			var previous_responder_id: int = responder_id
			responder_id = opponent_id
			opponent_id = previous_responder_id
		else:
			host.damage(opponent_id, responder_id, 1, "normal", "juedou")
			return


## 结算【借刀杀人】；被借刀者优先使用实体【杀】，否则交出武器。
func _resolve_borrow_sword(source_id: int, weapon_holder_id: int, victim_id: int) -> void:
	# 被借刀者打出的实体【杀】；为空表示拒绝或无法使用。
	var response_context: Dictionary = {"kind":"borrow_sword_response", "responder_id":weapon_holder_id, "source_id":source_id, "victim_id":victim_id}
	var slash: CardInstance = host.request_response_card(weapon_holder_id, "sha", "请响应借刀杀人并打出【杀】。", response_context)
	if host.has_pending_card_choice():
		return
	if _is_resolution_stopped():
		return
	if slash != null:
		# 被借刀者状态；其本回合获得的【酒】加值应作用于这张被要求使用的【杀】。
		var weapon_holder: PlayerState = state.get_player(weapon_holder_id)
		# 借刀【杀】伤害基数；读取后立即消耗【酒】加值。
		var damage_amount: int = 1 + weapon_holder.wine_bonus
		weapon_holder.wine_bonus = 0
		_resolve_single_slash(slash, weapon_holder_id, victim_id, damage_amount, str(GameDatabase.get_card(slash.definition_id).get("nature", "normal")), host.player_has_equipment(weapon_holder_id, "qinggang"))
	else:
		host.transfer_equipment(weapon_holder_id, source_id, "weapon")


## 结算群体响应锦囊；藤甲可令南蛮入侵与万箭齐发直接无效。
func _resolve_aoe(card: CardInstance, actor_id: int, target_ids: Array[int], response_pattern: String) -> void:
	for target_id: int in target_ids:
		if _is_resolution_stopped():
			break
		# 当前目标；死亡目标或已离场目标不再结算。
		var target: PlayerState = state.get_player(target_id)
		if target == null or not target.alive:
			continue
		if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
			continue
		if _is_resolution_stopped():
			break
		if host.get_equipment_id(target_id, "armor") == "tengjia":
			host.add_log("%s的【藤甲】令锦囊无效。" % target.display_name)
			continue
		var response_context: Dictionary = {"kind":"aoe_response", "responder_id":target_id, "actor_id":actor_id, "pattern":response_pattern, "card_definition_id":card.definition_id, "parent_card_uid":card.uid}
		var response_card: CardInstance = host.request_response_card(target_id, response_pattern, "请选择是否响应群体锦囊。", response_context)
		if host.has_pending_card_choice():
			return
		if response_card == null and not _is_resolution_stopped():
			host.damage(actor_id, target_id, 1, "normal", card.definition_id)
