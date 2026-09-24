extends SkillDefinition

## 【永劫】技能源码。锁定地把手牌非伤害牌转化为无距离火【杀】，并以火焰伤害推进三段轮回及完成卡厄斯兰那返生。

## 令其他轮回技进入永劫所在的①轮回节零基索引。
const ENTER_ETERNAL_SECTION_INDEX: int = 0

## 固定摸一张牌所在的②轮回节零基索引。
const DRAW_SECTION_INDEX: int = 1

## 摸一张牌并退出其他轮回技永劫所在的③轮回节零基索引。
const DRAW_AND_EXIT_ETERNAL_SECTION_INDEX: int = 2

## 永劫状态下其他轮回技每回合发动上限；数值1来自“每回合限一次”。
const OTHER_SKILL_ETERNAL_PER_TURN_LIMIT: int = 1

## ②与③固定摸牌数；数值1来自技能原文。
const DRAW_COUNT: int = 1

## 濒死返生后固定体力值；数值2来自技能原文。
const RETURN_HP: int = 2

## 非伤害牌转化的火【杀】稳定定义ID；主动与响应入口共用。
const FIRE_SLASH_DEFINITION_ID: String = "sha_fire"

## 永劫视为牌的隐藏规则标签稳定ID；牌面由视为名称横条显示，标签只提供无距离规则且不会重复显示文字。
const HAND_VIEW_AS_MARK_TAG_ID: String = "yongjie_view_as"

## 返生后替换回的白厄武将稳定ID。
const RETURN_CHARACTER_ID: String = "baie"

## 跨形态保存离场友方ID的私有状态键；与【轮回】写入键保持一致。
const REMOVED_ALLY_IDS_STATE_KEY: String = "baie_removed_ally_ids"

## AI消耗非伤害手牌转化火杀时的材料保留价值权重；默认0.45避免轻易消耗高价值回复或防御牌。
const AI_MATERIAL_COST_WEIGHT: float = 0.45


## 写入锁定轮回技静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"yongjie",
		"name":"永劫",
		"trigger":["gainAfter", "damageAfter", "dyingBegin"],
		"enable":[],
		"ui_enabled":false,
		"lock":true,
		"reincarnation":true,
		"reincarnation_section_count":3,
		"reincarnation_has_explicit_sections":true,
		"description":"锁定技，轮回技，你手牌中的非伤害牌均视为无距离限制的火【杀】。当你造成火焰伤害后，①你令你的所有其他轮回技进入每回合限一次的永劫状态；②摸一张牌；③摸一张牌并退出所有其他轮回技的永劫状态。当你体力值不大于0时，你将体力值回复至2点，恢复装备区与判定区，将武将牌替换为“白厄”，并复原武将牌上的技能，然后所有友方角色返场。",
	})


## 订阅持有者造成火焰伤害与进入濒死的锁定时机；主动转化由统一技能动作入口提供。
## 当前规则不再开放主动转化入口；安装与gainAfter直接维护标准卡牌入口可见的持续手牌视为状态。
func install() -> void:
	subscribe_timing("gainAfter", _on_owner_gain_after, "player")
	subscribe_timing("damageAfter", _on_fire_damage_after, "source")
	subscribe_timing("dyingBegin", _on_owner_dying_begin, "player", 1000)
	_refresh_locked_hand_view_as()


## 卸载永劫时只清除本技能建立的手牌视为与隐藏距离标签；其他来源的手牌标签保持原样。
func uninstall() -> void:
	# 技能持有者；换形或复原时仍可从旧实例绑定的稳定玩家ID取得当前手牌。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 是否实际恢复过至少一张手牌；只有变化时才需要刷新公开牌面。
	var changed: bool = false
	if owner != null:
		for card: CardInstance in owner.hand:
			if card.hand_view_as_source_skill_id == get_id():
				card.clear_hand_view_as()
				card.clear_hand_view_as_presentation()
				changed = true
			if card.remove_hand_mark_tag(HAND_VIEW_AS_MARK_TAG_ID):
				changed = true
	if changed and host != null and host.has_method("refresh_public_state_snapshot"):
		host.call("refresh_public_state_snapshot")
	super()


## 响应入口要求【杀】且存在非伤害手牌；主动入口要求自身出牌阶段并至少有一组合法材料目标。
func can_activate(context: Dictionary = {}) -> bool:
	# 永劫的视为牌属于锁定状态，不开放主动技能或响应技能按钮；普通卡牌入口直接使用已经视为火【杀】的实体。
	if get_active_entries().is_empty():
		return false
	# 技能持有者；死亡或离场状态不开放主动与响应转化。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	# 非伤害普通手牌候选；永劫不允许木牛“粮”或装备作为材料。
	var candidates: Array[Dictionary] = _get_non_damage_hand_candidates()
	if str(context.get("active_entry", "")) == "chooseToRespond":
		return (context.get("response_patterns", []) as Array).has("sha") and not candidates.is_empty()
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play" or candidates.is_empty():
		return false
	# 材料目标映射；真实材料颜色参与来牌限制，ignore_distance_limit只解除距离而不解除杀次数。
	var selection_data: Dictionary = build_virtual_target_selection_data(FIRE_SLASH_DEFINITION_ID, candidates, {"ignore_distance_limit":true})
	return not (selection_data.get("target_ids", []) as Array).is_empty()


## 主动把一张非伤害手牌当无距离火【杀】使用；AI可直接携带材料与目标，人类使用统一牌目标选择。
func activate(context: Dictionary = {}) -> String:
	if get_active_entries().is_empty():
		return "【永劫】是锁定视为效果，请直接使用标记为火【杀】的手牌。"
	# 动作材料UID；负数表示需要创建玩家选择。
	var material_card_uid: int = int(context.get("material_card_uid", -1))
	# 动作目标数组；标准火杀要求恰好一名其他角色。
	var target_ids: Array[int] = _int_array(context.get("target_ids", []) as Array)
	if material_card_uid >= 0 and target_ids.size() == 1:
		return "" if _execute_fire_slash_conversion(material_card_uid, target_ids) else "【永劫】材料、次数或目标已不合法。"
	# 当前非伤害手牌候选；没有材料时不创建空选择窗口。
	var candidates: Array[Dictionary] = _get_non_damage_hand_candidates()
	# 每张材料到合法火【杀】目标的映射；真实颜色与无距离覆写在此统一计算。
	var selection_data: Dictionary = build_virtual_target_selection_data(FIRE_SLASH_DEFINITION_ID, candidates, {"ignore_distance_limit":true})
	# 所有材料合法目标的并集；界面在材料尚未确定时使用该集合高亮。
	var legal_target_ids: Array[int] = _int_array(selection_data.get("target_ids", []) as Array)
	if candidates.is_empty() or legal_target_ids.is_empty():
		return "当前没有可转化的非伤害手牌或合法火【杀】目标。"
	request_card_target_selection("永劫", "请选择一张非伤害手牌和一名火杀目标", candidates, legal_target_ids, 1, 1, 1, 1, true, {"kind":"yongjie_fire_slash", "target_ids_by_card_id":selection_data.get("target_ids_by_card_id", {})})
	return ""


## 恢复主动牌目标组合选择；取消或条件变化不会消耗材料。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "yongjie_fire_slash" or response == null:
		return false
	if response.confirmed and response.card_ids.size() == 1 and response.target_ids.size() == 1:
		_execute_fire_slash_conversion(response.card_ids[0], response.target_ids)
	return true


## 权威复核并提交非伤害手牌转化；仅解除距离，已经达到杀次数上限时仍不可使用。
func _execute_fire_slash_conversion(material_card_uid: int, target_ids: Array[int]) -> bool:
	# 当前材料实体；必须仍位于普通手牌区且卡牌定义不具有伤害属性。
	var material_card: CardInstance = _get_non_damage_hand_card(material_card_uid)
	# 永劫规则覆写；材料真实颜色由虚拟用牌入口覆盖同名字段。
	var rule_overrides: Dictionary = {"ignore_distance_limit":true}
	if material_card == null or validate_virtual_use_for_material(FIRE_SLASH_DEFINITION_ID, material_card, target_ids, rule_overrides) != "":
		return false
	# 单材料UID数组；强类型保证动态控制器调用参数稳定。
	var material_card_uids: Array[int] = [material_card_uid]
	if not bool(host.call("execute_virtual_card_use", owner_player_id, FIRE_SLASH_DEFINITION_ID, material_card_uids, target_ids, "", rule_overrides, {"source_skill_id":get_id()})):
		return false
	announce_activation({"material_card_uid":material_card_uid, "target_ids":target_ids.duplicate(), "virtual_card_id":FIRE_SLASH_DEFINITION_ID})
	observe_identity_behavior(target_ids, {"target_result":-1.5, "damage":true, "respond_shan":true, "nature_damage":true})
	return true


## 判断一张自有实体牌能否在响应窗口通过永劫转化为火【杀】；只接受普通手牌中的非伤害牌。
func can_convert_response_card(card: CardInstance, response_patterns: Array[String]) -> bool:
	# 手牌已由锁定效果直接变为火【杀】，响应系统会按牌自身模式处理，不再创建永劫技能按钮。
	return not get_active_entries().is_empty() and card != null and card.zone == "hand" and card.owner_id == owner_player_id and _is_non_damage_definition(card.definition_id) and response_patterns.has("sha")


## 返回永劫响应转化后的火【杀】定义；等待期间条件失效时返回空字符串。
func get_converted_response_definition_id(card: CardInstance, response_patterns: Array[String]) -> String:
	return FIRE_SLASH_DEFINITION_ID if can_convert_response_card(card, response_patterns) else ""


## 非伤害手牌已经成功转化并响应后记录永劫发动；响应本身没有目标选择。
func on_converted_response_consumed(card: CardInstance, response_pattern: String, virtual_definition_id: String) -> void:
	announce_activation({"material_card_uid":card.uid if card != null else -1, "response_pattern":response_pattern, "virtual_card_id":virtual_definition_id})


## 持有者获得普通手牌后立即应用永劫锁定视为；摸牌、交牌与获得牌统一经过gainAfter。
func _on_owner_gain_after(event: RuleEvent) -> void:
	if event == null:
		return
	# 当前持有者；获得时机结束后实体已经进入其普通手牌区。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return
	# 是否至少有一张本次获得牌新增了永劫视为；统一刷新一次避免逐牌广播重复快照。
	var changed: bool = false
	for card_uid_variant: Variant in event.data.get("card_uids", []) as Array:
		# 本次获得的实体牌；等待其他获得触发后仍按UID复核其当前区域。
		var card: CardInstance = owner.find_hand_card(int(card_uid_variant))
		if _apply_locked_hand_view_as(card):
			changed = true
	if changed and host != null and host.has_method("refresh_public_state_snapshot"):
		host.call("refresh_public_state_snapshot")


## 为安装技能时已经持有的全部普通手牌同步永劫视为；伤害牌保持原定义与原使用方式。
func _refresh_locked_hand_view_as() -> void:
	# 技能持有者；静态数据库实例没有宿主时不修改任何卡牌。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return
	# 是否至少有一张手牌发生变化；批量结束后只发布一次公开状态。
	var changed: bool = false
	for card: CardInstance in owner.hand:
		if _apply_locked_hand_view_as(card):
			changed = true
	if changed and host != null and host.has_method("refresh_public_state_snapshot"):
		host.call("refresh_public_state_snapshot")


## 将一张非伤害普通手牌持续视为火【杀】，并写入只作用于该实体的无距离规则标签。
func _apply_locked_hand_view_as(card: CardInstance) -> bool:
	if card == null or card.zone != "hand" or card.owner_id != owner_player_id:
		return false
	# 实体原始牌定义；已经被其他效果视为牌时仍按最初牌名判断其是否属于非伤害牌。
	var original_definition_id: String = card.hand_view_as_original_definition_id if card.has_hand_view_as() else card.definition_id
	if not _is_non_damage_definition(original_definition_id):
		return false
	# 本次是否新建或替换了视为定义；重复同步同一张牌保持幂等。
	var changed: bool = false
	if card.definition_id != FIRE_SLASH_DEFINITION_ID or card.hand_view_as_source_skill_id != get_id():
		if not card.set_hand_view_as(FIRE_SLASH_DEFINITION_ID, get_id()):
			return false
		changed = true
	# 隐藏规则标签；视为横条已经显示“火【杀】”，此处空label避免牌面出现重复文字。
	var mark_data: Dictionary = {"id":HAND_VIEW_AS_MARK_TAG_ID, "label":"", "order":0, "source_skill_id":get_id(), "rule_overrides":{"ignore_distance_limit":true}}
	if not card.hand_mark_tags.has(HAND_VIEW_AS_MARK_TAG_ID) or card.hand_mark_tags.get(HAND_VIEW_AS_MARK_TAG_ID, {}) != mark_data:
		card.set_hand_mark_tag(HAND_VIEW_AS_MARK_TAG_ID, mark_data)
		changed = true
	return changed


## 持有者造成正数火焰伤害后强制执行当前轮回节，并在效果完成后推进。
func _on_fire_damage_after(event: RuleEvent) -> void:
	if event == null or int(event.data.get("amount", 0)) <= 0 or str(event.data.get("nature", "normal")) != "fire" or not begin_reincarnation_activation():
		return
	# 当前轮回节；①进入永劫，②摸1，③摸1并退出永劫。
	var section_index: int = get_reincarnation_section_index()
	# 本次受影响的其他轮回技；仅枚举当前真实安装技能，避免旧形态残留状态被误修改。
	var affected_skill_ids: Array[String] = _get_other_reincarnation_skill_ids()
	if section_index == ENTER_ETERNAL_SECTION_INDEX:
		for skill_id: String in affected_skill_ids:
			host.call("enter_eternal_reincarnation_state", owner_player_id, skill_id, OTHER_SKILL_ETERNAL_PER_TURN_LIMIT)
	elif section_index == DRAW_SECTION_INDEX:
		host.call("draw", owner_player_id, DRAW_COUNT)
	elif section_index == DRAW_AND_EXIT_ETERNAL_SECTION_INDEX:
		host.call("draw", owner_player_id, DRAW_COUNT)
		for skill_id: String in affected_skill_ids:
			host.call("exit_eternal_reincarnation_state", owner_player_id, skill_id)
	announce_activation({"section_number":section_index + 1, "round_count":get_reincarnation_round_count(), "damage_event_id":int(event.data.get("damage_event_id", -1)), "affected_skill_ids":affected_skill_ids.duplicate(), "draw_count":DRAW_COUNT if section_index in [DRAW_SECTION_INDEX, DRAW_AND_EXIT_ETERNAL_SECTION_INDEX] else 0})
	complete_reincarnation_activation()


## 体力不大于0时强制回复至2、恢复区域、换回白厄、复原新武将技能并恢复轮回时离场的友方。
func _on_owner_dying_begin(_event: RuleEvent) -> void:
	# 卡厄斯兰那状态；只有仍存活在场且体力不大于0时执行返生，其他形态不会误用旧订阅。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or owner.hp > 0 or owner.character_id == RETURN_CHARACTER_ID:
		return
	# 【轮回】实际移出的友方ID；该私有快照保证换形链中的原友方不因后续公开状态变化而遗漏。
	var removed_ally_ids: Array[int] = _int_array(owner.character_form_state.get(REMOVED_ALLY_IDS_STATE_KEY, []) as Array)
	# 本次应返场的全部友方ID；先保留原移出集合，再按原文“所有友方角色返场”补入当前其他存活离场友方。
	var returning_ally_ids: Array[int] = []
	for ally_id: int in removed_ally_ids:
		# 原移出友方的当前状态；已死亡或已返场的角色不再加入恢复集合。
		var removed_ally: PlayerState = host.state.get_player(ally_id) as PlayerState
		if removed_ally != null and removed_ally.alive and removed_ally.out_of_game and not returning_ally_ids.has(ally_id):
			returning_ally_ids.append(ally_id)
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and player.out_of_game and bool(host.call("is_friendly", owner_player_id, player.player_id)) and not returning_ally_ids.has(player.player_id):
			returning_ally_ids.append(player.player_id)
	announce_activation({"return_character_id":RETURN_CHARACTER_ID, "return_hp":RETURN_HP, "returning_ally_ids":returning_ally_ids.duplicate()})
	if owner.hp < RETURN_HP:
		host.call("recover", owner_player_id, owner_player_id, RETURN_HP - owner.hp, get_id())
	host.call("set_player_zones_abolished", owner_player_id, false, false, get_id())
	if not bool(host.call("replace_player_character_card", owner_player_id, RETURN_CHARACTER_ID, get_id(), true)):
		return
	host.call("restore_character_card_skills", owner_player_id, get_id())
	# 换回白厄后的同一角色状态；清除已消费的跨形态友方列表，避免下一次返生重复恢复旧角色。
	var returned_owner: PlayerState = host.state.get_player(owner_player_id) as PlayerState
	if returned_owner != null:
		returned_owner.character_form_state.erase(REMOVED_ALLY_IDS_STATE_KEY)
	for ally_id: int in returning_ally_ids:
		host.call("restore_player_to_game", ally_id, get_id())


## 返回当前安装的其他轮回技ID；永劫自身必须排除，否则会锁定负责切换状态的轮回节。
func _get_other_reincarnation_skill_ids() -> Array[String]:
	# 轮回技结果；保持当前技能安装顺序，状态变化与日志顺序稳定。
	var result: Array[String] = []
	for skill_id: String in host.call("get_installed_skill_ids", owner_player_id) as Array[String]:
		if skill_id != get_id() and bool(GameDatabase.get_skill(skill_id).get("reincarnation", false)):
			result.append(skill_id)
	return result


## 返回普通手牌区全部非伤害牌候选；木牛“粮”、装备与卡牌AI标记为伤害的定义均被排除。
func _get_non_damage_hand_candidates() -> Array[Dictionary]:
	# 候选结果；本人查看自身手牌，因此牌面定义ID完整可用。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]:
		# 候选卡牌定义ID；空牌面不会被当作可转化材料。
		var definition_id: String = str((candidate.get("card_data", {}) as Dictionary).get("definition_id", ""))
		if _is_non_damage_definition(definition_id):
			result.append(candidate.duplicate(true))
	return result


## 按UID返回仍位于普通手牌区的非伤害实体；等待期间离区或定义变化时返回null。
func _get_non_damage_hand_card(card_uid: int) -> CardInstance:
	# 技能持有者；不存在时没有手牌实体。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 当前普通手牌；find_hand_card不会返回木牛“粮”或装备。
	var card: CardInstance = owner.find_hand_card(card_uid) if owner != null else null
	return card if card != null and _is_non_damage_definition(card.definition_id) else null


## 判断卡牌定义是否属于非伤害牌；项目卡牌统一以ai.damage=true声明直接伤害行为。
func _is_non_damage_definition(definition_id: String) -> bool:
	# 卡牌定义与AI字段；缺失定义不允许转化，缺失damage字段按非伤害处理以兼容纯资源扩展牌。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	return not definition.is_empty() and not bool((definition.get("ai", {}) as Dictionary).get("damage", false))


## 为AI枚举每张非伤害手牌与其无距离火【杀】合法目标组合。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	# 锁定视为牌由普通use_card动作枚举，永劫自身不再生成use_skill动作。
	if get_active_entries().is_empty():
		return
	if not can_activate():
		return
	# 可转化的非伤害手牌候选；每张牌将分别枚举目标。
	var candidates: Array[Dictionary] = _get_non_damage_hand_candidates()
	# 材料与目标的独立合法性结果；真实颜色仍参与目标技能限制。
	var selection_data: Dictionary = build_virtual_target_selection_data(FIRE_SLASH_DEFINITION_ID, candidates, {"ignore_distance_limit":true})
	# 实体材料UID到合法目标的序列化映射；键为字符串UID以兼容网络快照。
	var target_ids_by_card_id: Dictionary = selection_data.get("target_ids_by_card_id", {}) as Dictionary
	for candidate: Dictionary in candidates:
		# 当前材料UID；稳定键用于读取该牌真实颜色下的合法目标。
		var material_card_uid: int = int(candidate.get("uid", -1))
		for target_id_variant: Variant in target_ids_by_card_id.get(str(material_card_uid), []) as Array:
			# 当前目标数组；标准火杀只有一名目标。
			var target_ids: Array[int] = [int(target_id_variant)]
			result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":target_ids.duplicate(), "payload":{"skill_id":get_id(), "material_card_uid":material_card_uid, "target_ids":target_ids.duplicate()}})


## AI按标准火【杀】收益并扣除非伤害手牌保留价值，避免无收益地消耗桃、闪等关键牌。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；保存材料UID与实际目标。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 火杀代理动作；通用评估器处理敌我、响应、属性连环与其他技能联动。
	var fire_slash_action: Dictionary = build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
	# 材料保留价值；高价值非伤害牌会显著降低转化意愿。
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	return evaluator.score_action(authoritative_snapshot, fire_slash_action, owner_player_id) - material_value * AI_MATERIAL_COST_WEIGHT


## 构造永劫主动转化对应的火【杀】代理动作；目标与材料颜色保持真实值。
func build_ai_virtual_card_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> Dictionary:
	# 动作负载；提供材料UID和目标的权威副本。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 材料牌快照；其真实颜色用于防具和来牌限制的AI复核。
	var material_card: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, int(payload.get("material_card_uid", -1)))
	return {"action_type":"use_card", "actor_id":owner_player_id, "card_definition_id":FIRE_SLASH_DEFINITION_ID, "card_color":str(material_card.get("color", "")), "target_ids":(action.get("target_ids", payload.get("target_ids", [])) as Array).duplicate()}


## 把弱类型数组收敛为整数数组；动作、网络、私有形态状态与回放输入共用该防御性转换。
func _int_array(values: Array) -> Array[int]:
	# 转换结果；保留原顺序供友方返场和技能目标使用。
	var result: Array[int] = []
	for value_variant: Variant in values:
		result.append(int(value_variant))
	return result
