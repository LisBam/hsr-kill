class_name RuleQuery
extends RefCounted

## 规则纯查询门面。它把卡牌启用、响应、次数、目标和距离检查与触发事件、状态写入严格分离。

## 当前权威状态；查询只读取该对象，禁止在本类中移动牌或修改玩家统计。
var state: GameState

## 现有卡牌合法性服务；负责基础距离、次数、目标模式和区域规则。
var card_rules: CardRuleService

## 独立修正器管线；技能 mod 按优先级链式改变查询结果，不产生 RuleEvent。
var modifiers: RuleModifierPipeline


## 绑定当前对局状态、卡牌规则与可选修正器管线。
func _init(game_state: GameState, rule_service: CardRuleService, modifier_pipeline: RuleModifierPipeline = null) -> void:
	state = game_state
	card_rules = rule_service
	modifiers = modifier_pipeline if modifier_pipeline != null else RuleModifierPipeline.new()


## 返回实体牌是否能进入当前玩家的使用选择；这里只检查区域、存活、阶段和 cardEnabled 修正。
func card_enabled(actor_id: int, card: CardInstance, context: Dictionary = {}) -> bool:
	if state == null or card == null:
		return false
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null or not actor.alive or actor.find_playable_card(card.uid) == null:
		return false
	# 基础启用结果；选择事件可在上下文中允许回合外技能使用，不直接改写当前阶段。
	var enabled: bool = state.current_phase == "play" and state.current_player_id == actor_id
	var query_context: Dictionary = context.duplicate(true)
	query_context.merge({"actor_id":actor_id, "card_uid":card.uid, "card_id":card.definition_id}, false)
	return bool(modifiers.apply("card_enabled", enabled, query_context))


## 返回卡牌是否可作为指定模式的响应；响应模式、来源限制和 cardRespondable 修正在同一纯查询中完成。
func card_respondable(actor_id: int, card: CardInstance, response_pattern: String, context: Dictionary = {}) -> bool:
	if state == null or card == null:
		return false
	var actor: PlayerState = state.get_player(actor_id)
	if actor == null or not actor.alive or actor.find_playable_card(card.uid) == null:
		return false
	# 卡牌自身提供的响应模式；属性牌和后续扩展牌不要求稳定 ID 与模式字符串相同。
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	var respondable: bool = str(definition.get("provided_response_pattern", "")) == response_pattern
	var query_context: Dictionary = context.duplicate(true)
	query_context.merge({"actor_id":actor_id, "card_uid":card.uid, "card_id":card.definition_id, "response_pattern":response_pattern}, false)
	return bool(modifiers.apply("card_respondable", respondable, query_context))


## 返回当前牌在给定完整目标下是否通过次数与组合校验；不会增加任何卡牌专属统计或消耗实体牌。
func card_usable(actor_id: int, card: CardInstance, target_ids: Array[int], context: Dictionary = {}) -> bool:
	if not card_enabled(actor_id, card, context):
		return false
	var normalized_targets: Array[int] = card_rules.normalize_targets(actor_id, card, target_ids)
	var usable: bool = card_rules.validate_use(actor_id, card, normalized_targets).is_empty()
	var query_context: Dictionary = context.duplicate(true)
	query_context.merge({"actor_id":actor_id, "card_uid":card.uid, "target_ids":normalized_targets}, false)
	return bool(modifiers.apply("card_usable", usable, query_context))


## 返回指定目标是否属于当前牌的基础合法候选并通过 targetEnabled 修正。
func target_enabled(actor_id: int, card: CardInstance, target_id: int, context: Dictionary = {}) -> bool:
	if state == null or card == null:
		return false
	var target: PlayerState = state.get_player(target_id)
	var enabled: bool = target != null and target.alive and card_rules.list_legal_targets(actor_id, card).has(target_id)
	var query_context: Dictionary = context.duplicate(true)
	query_context.merge({"actor_id":actor_id, "target_id":target_id, "card_uid":card.uid, "card_id":card.definition_id}, false)
	return bool(modifiers.apply("target_enabled", enabled, query_context))


## 返回指定目标是否满足距离限制；先计算现有规则距离，再经过 targetInRange 修正。
func target_in_range(actor_id: int, card: CardInstance, target_id: int, context: Dictionary = {}) -> bool:
	if state == null or card == null or state.get_player(target_id) == null:
		return false
	var definition: Dictionary = GameDatabase.get_card(card.definition_id)
	# 距离配置语义；攻击范围、固定距离1和无限制全部直接来自卡牌文件。
	var distance_mode: String = str(definition.get("distance_limit", "none"))
	var distance_limit: int = -1
	if distance_mode == "one":
		distance_limit = 1
	elif distance_mode == "attack_range":
		distance_limit = card_rules.get_attack_range(actor_id)
	var in_range: bool = distance_limit < 0 or card_rules.calculate_distance(actor_id, target_id) <= distance_limit
	var query_context: Dictionary = context.duplicate(true)
	query_context.merge({"actor_id":actor_id, "target_id":target_id, "card_uid":card.uid, "distance":card_rules.calculate_distance(actor_id, target_id), "limit":distance_limit}, false)
	return bool(modifiers.apply("target_in_range", in_range, query_context))
