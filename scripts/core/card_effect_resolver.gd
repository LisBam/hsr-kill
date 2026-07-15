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


## 执行一张已经进入处理区的牌，并返回默认结束区域：discard、equipment、judgment 或 consumed。
func resolve(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if _is_resolution_stopped():
		return "consumed"
	# 卡牌配置定义；效果 ID、类型与属性均从统一数据表取得。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 卡牌效果 ID；多个实体牌或属性变体可共享同一个底层效果。
	var effect_id: String = str(definition.get("effect_id", ""))

	if effect_id == "slash":
		_resolve_slash_card(card, actor_id, target_ids)
	elif effect_id == "peach":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			host.recover(actor_id, target_id, 1, card.definition_id)
	elif effect_id == "wine":
		# 使用者状态；每名玩家在自己的出牌阶段正常使用【酒】仍受每回合一次限制。
		var actor: PlayerState = state.get_player(actor_id)
		actor.wine_used = true
		# 【酒】目标状态；规则允许指定包括使用者在内的一名角色获得本回合下一张【杀】加值。
		var wine_target: PlayerState = state.get_player(target_ids[0])
		wine_target.wine_bonus = 1
		host.add_log("%s令%s本回合使用的下一张【杀】伤害+1。" % [actor.display_name, wine_target.display_name])
	elif effect_id == "equip":
		host.equip_from_processing(actor_id, card)
		return "equipment"
	elif bool(definition.get("delayed", false)):
		# 延时锦囊目标；配置保证只有一个目标。
		var delayed_target_id: int = target_ids[0]
		# 延时锦囊在使用结算结束后进入判定区，其实际效果在目标判定阶段生效前进入【无懈可击】窗口。
		host.place_delayed_trick(delayed_target_id, card)
		return "judgment"
	elif effect_id == "draw_two":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			host.draw_cards(target_id, 2)
	elif effect_id == "discard_target":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			host.discard_one_from_player(actor_id, target_id)
	elif effect_id == "steal_target":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			host.take_one_from_player(actor_id, target_id)
	elif effect_id == "duel":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			_resolve_duel(actor_id, target_id)
	elif effect_id == "borrow_sword":
		if target_ids.size() == 2 and not host.resolve_trick_negation(actor_id, target_ids[0], card.definition_id):
			if not _is_resolution_stopped():
				_resolve_borrow_sword(actor_id, target_ids[0], target_ids[1])
	elif effect_id == "aoe_dodge":
		_resolve_aoe(card, actor_id, target_ids, "shan")
	elif effect_id == "aoe_slash":
		_resolve_aoe(card, actor_id, target_ids, "sha")
	elif effect_id == "heal_all":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			host.recover(actor_id, target_id, 1, card.definition_id)
	elif effect_id == "harvest":
		_resolve_harvest(card, actor_id, target_ids)
	elif effect_id == "chain":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			# 当前目标状态；铁索连环令其横置状态在两种状态间切换。
			var target: PlayerState = state.get_player(target_id)
			target.chained = not target.chained
			host.add_log("%s%s。" % [target.display_name, "进入连环状态" if target.chained else "解除连环状态"])
	elif effect_id == "fire_attack":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			_resolve_fire_attack(actor_id, target_id)
	elif effect_id == "flood":
		for target_id: int in target_ids:
			if _is_resolution_stopped():
				break
			if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
				continue
			if _is_resolution_stopped():
				break
			_resolve_flood(actor_id, target_id)
	return "discard"


## 返回当前结算是否必须立即停止；游戏结束后任何牌、伤害、响应或区域移动都不得继续执行。
func _is_resolution_stopped() -> bool:
	return state == null or state.game_over


## 结算【杀】，包括酒加值、武器触发、防具无效与响应【闪】。
func _resolve_slash_card(card: CardInstance, actor_id: int, target_ids: Array[int]) -> void:
	# 使用者状态；酒加值在声明并结算本张【杀】时一次性消耗。
	var actor: PlayerState = state.get_player(actor_id)
	# 本张【杀】对所有目标共享的伤害基数。
	var base_damage: int = 1 + actor.wine_bonus
	actor.wine_bonus = 0
	# 当前【杀】属性；normal、fire 或 thunder。
	var nature: String = str(GameDatabase.get_card(card.definition_id).get("nature", "normal"))
	if nature == "normal" and host.player_has_equipment(actor_id, "zhuque"):
		nature = "fire"
		host.add_log("%s发动【朱雀羽扇】，将普通【杀】转为火【杀】。" % actor.display_name)
	# 青釭剑忽略每个目标的防具直到对应目标结算结束。
	var ignore_armor: bool = host.player_has_equipment(actor_id, "qinggang")
	for target_id: int in target_ids:
		if _is_resolution_stopped():
			break
		_resolve_single_slash(card, actor_id, target_id, base_damage, nature, ignore_armor)


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
	if host.player_has_equipment(actor_id, "cixiong") and actor_gender in ["male", "female"] and target_gender in ["male", "female"] and actor_gender != target_gender:
		if not target.hand.is_empty():
			host.discard_card_from_hand(target_id, target.hand[0].uid)
		else:
			host.draw_cards(actor_id, 1)

	if not ignore_armor:
		# 目标防具 ID；无防具时为空字符串。
		var armor_id: String = host.get_equipment_id(target_id, "armor")
		if armor_id == "tengjia" and nature == "normal":
			host.add_log("%s的【藤甲】令普通【杀】无效。" % target.display_name)
			return
		if armor_id == "renwang" and card.get_color() == "black":
			host.add_log("%s的【仁王盾】令黑色【杀】无效。" % target.display_name)
			return

	# 目标是否成功响应【闪】；八卦阵与实体【闪】都通过统一响应端口处理。
	var dodged: bool = host.consume_response(target_id, "shan")
	if _is_resolution_stopped():
		return
	if dodged and host.player_has_equipment(actor_id, "guanshi") and host.get_hand_equipment_card_count(actor_id) >= 2:
		host.discard_n_from_hand_equipment(actor_id, 2)
		dodged = false
		host.add_log("%s发动【贯石斧】，令【杀】继续生效。" % actor.display_name)
	if dodged:
		host.add_log("%s打出【闪】抵消了【杀】。" % target.display_name)
		if host.player_has_equipment(actor_id, "qinglong"):
			# 青龙偃月刀追加使用的实体【杀】；响应端口会将其直接置入弃牌堆。
			var follow_slash: CardInstance = host.consume_response_card(actor_id, "sha")
			if follow_slash != null:
				host.add_log("%s发动【青龙偃月刀】追击。" % actor.display_name)
				_resolve_single_slash(follow_slash, actor_id, target_id, 1, str(GameDatabase.get_card(follow_slash.definition_id).get("nature", "normal")), ignore_armor)
		return

	# 寒冰剑为可选替代效果；基础 AI 在目标有至少两张牌且体力大于1时选择弃牌替代伤害。
	# 实际规则条件只要求目标手牌区或装备区有牌，不以目标体力或至少两张牌作为发动门槛。
	if host.player_has_equipment(actor_id, "hanbing") and host.get_hand_equipment_card_count(target_id) >= 1:
		host.discard_n_from_hand_equipment(target_id, 2)
		host.add_log("%s发动【寒冰剑】防止伤害并弃置目标至多两张牌。" % actor.display_name)
		return

	host.damage(actor_id, target_id, damage_amount, nature, card.definition_id, false, ignore_armor)
	if _is_resolution_stopped():
		return
	if target.alive and host.player_has_equipment(actor_id, "qilin"):
		host.discard_first_mount(target_id)


## 结算【决斗】的轮流出杀，任意一方首次无法打出时受到1点伤害。
func _resolve_duel(source_id: int, target_id: int) -> void:
	# 当前需要打出【杀】的玩家 ID；由目标先开始。
	var responder_id: int = target_id
	# 当前对手 ID；未打出【杀】时成为伤害来源。
	var opponent_id: int = source_id
	# 安全轮次计数；实体牌有限，但仍设置上限防止扩展技能产生死循环。
	var exchange_count: int = 0
	while exchange_count < 100 and not _is_resolution_stopped():
		exchange_count += 1
		if host.consume_response(responder_id, "sha"):
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
	var slash: CardInstance = host.consume_response_card(weapon_holder_id, "sha")
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
		if not host.consume_response(target_id, response_pattern) and not _is_resolution_stopped():
			host.damage(actor_id, target_id, 1, "normal", card.definition_id)


## 结算【五谷丰登】；当前交互策略按行动顺序取得首张剩余牌，数据接口允许后续替换为选择请求。
func _resolve_harvest(card: CardInstance, actor_id: int, target_ids: Array[int]) -> void:
	# 亮出的公共牌数组；数量等于初始目标数。
	var revealed_cards: Array[CardInstance] = host.reveal_top_cards(target_ids.size())
	for target_id: int in target_ids:
		if _is_resolution_stopped() or revealed_cards.is_empty():
			break
		if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
			continue
		if _is_resolution_stopped():
			break
		# 当前目标获得的牌；基础交互先取首张，后续选择器可返回任意合法 UID。
		var chosen_card: CardInstance = revealed_cards.pop_front()
		host.give_revealed_card(target_id, chosen_card)
	if _is_resolution_stopped():
		return
	for remaining_card: CardInstance in revealed_cards:
		host.discard_revealed_card(remaining_card)


## 结算【火攻】；目标展示首张手牌，使用者自动弃置首张同花色手牌。
func _resolve_fire_attack(actor_id: int, target_id: int) -> void:
	if _is_resolution_stopped():
		return
	# 使用者状态；用于寻找同花色手牌。
	var actor: PlayerState = state.get_player(actor_id)
	# 目标状态；合法性层已保证其至少有一张手牌。
	var target: PlayerState = state.get_player(target_id)
	if target.hand.is_empty():
		return
	# 目标展示的手牌；当前基础选择策略取第一张。
	var shown_card: CardInstance = target.hand[0]
	host.add_log("%s展示了%s。" % [target.display_name, host.describe_card(shown_card)])
	for candidate: CardInstance in actor.hand:
		if candidate.suit == shown_card.suit:
			host.discard_card_from_hand(actor_id, candidate.uid)
			host.damage(actor_id, target_id, 1, "fire", "huogong")
			return


## 结算【水淹七军】；基础选择策略优先弃置装备，否则受到1点伤害。
func _resolve_flood(actor_id: int, target_id: int) -> void:
	if _is_resolution_stopped():
		return
	# 目标状态；装备区非空时按规则弃置全部装备。
	var target: PlayerState = state.get_player(target_id)
	if not target.equipment.is_empty():
		host.discard_all_equipment(target_id)
	else:
		host.damage(actor_id, target_id, 1, "normal", "shuiyanqijun")
