extends SkillDefinition

## 【遥击】技能源码。锁定技：你对距离与你最远的角色使用【杀】时没有距离限制。

## 允许解除距离限制的牌效果ID；只有【杀】族命中，普通、火、雷【杀】与技能视为的【杀】共用该效果ID。
const SLASH_EFFECT_ID: String = "slash"

## AI：让原本因距离不可达的最远敌方目标重新可达时补充的收益。
const AI_FARTHEST_REACHABILITY_BONUS: float = 1.5


## 写入锁定技静态信息；技能描述逐字保持需求提供的原文。
## 正文含“锁定技”，基类据此自动标记 lock，无需额外声明。
func _init() -> void:
	super({
		"id":"yaoji",
		"name":"遥击",
		"trigger":"passive",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，你对距离与你最远的角色使用【杀】没有距离限制。",
	})


## 带目标上下文的距离豁免：只对【杀】、且只对距离最远的角色解除距离限制。
## 本钩子只在用牌目标的距离校验处被询问，且完全不改 calculate_distance()，因此距离数值本身不变；
## 其他依赖距离的技能与界面读取结果保持原样，也不会连带放宽【顺手牵羊】等距离敏感牌。
func ignores_card_distance_limit_to_target(card_definition: Dictionary, target_id: int) -> bool:
	# 只对【杀】生效；任何其他距离敏感牌都必须继续受基础距离限制。
	if not _is_slash_definition(card_definition):
		return false
	# 只对距离与持有者最远的角色生效；距离不足时不得放宽。
	return _is_farthest_opponent(target_id)


## 判断牌定义是否属于【杀】族；读 effect_id 而不是牌名，因此普通、火与雷【杀】统一命中。
func _is_slash_definition(card_definition: Dictionary) -> bool:
	return str(card_definition.get("effect_id", "")) == SLASH_EFFECT_ID


## 判断目标是否为距离持有者最远的角色；并列角色全部满足，1v1时对唯一对手生效。
func _is_farthest_opponent(target_id: int) -> bool:
	if host == null or host.get("state") == null or host.card_rules == null:
		return false
	# 目标角色；死亡、离场与持有者自己都不参与最远判定。
	var target: PlayerState = host.state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or target_id == owner_player_id:
		return false
	# 目标到持有者的当前距离；直接读取权威距离，不做任何改写。
	var target_distance: int = int(host.card_rules.calculate_distance(owner_player_id, target_id))
	# 其余存活在场角色的最大距离。
	# 必须先过滤死亡与离场：calculate_distance 对无效目标返回哨兵值，不过滤会污染最大值。
	var max_distance: int = -1
	for player: PlayerState in host.state.players:
		if player.player_id == owner_player_id or not player.alive or player.out_of_game:
			continue
		max_distance = maxi(max_distance, int(host.card_rules.calculate_distance(owner_player_id, player.player_id)))
	return max_distance >= 0 and target_distance >= max_distance


## 为AI补充可达性收益：原本因距离打不到的最远敌方目标在本技能下变为合法动作，应优先被选中。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 只调整使用【杀】的动作；技能与装备等其他动作不受影响。
	if str(action.get("action_type", "")) != "use_card":
		return current_score
	# 当前逻辑牌定义；直接读动作携带的定义ID，不绑定实体牌UID。
	var definition: Dictionary = GameDatabase.get_card(str(action.get("card_definition_id", "")))
	if not _is_slash_definition(definition):
		return current_score
	# 唯一目标；多目标【杀】不适用本技能的可达性语义。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return current_score
	var target_id: int = int(target_ids[0])
	if not _is_farthest_opponent(target_id):
		return current_score
	# 只对敌方目标补充收益；对队友使用【杀】不应因为打得到而被鼓励。
	if evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) >= 0.0:
		return current_score
	return current_score + AI_FARTHEST_REACHABILITY_BONUS
