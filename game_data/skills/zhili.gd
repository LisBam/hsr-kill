extends SkillDefinition

## 【支离】锁定技源码。持有者是自己使用【杀】的合法目标；主演用【杀】造成伤害时回复1点体力；
## 持有者使用【杀】指定唯一目标时把目标整体改为该目标的相邻角色，并在该【杀】结算完毕后失去1点体力。

## 【杀】牌族的稳定效果标识；普通、火焰与雷电【杀】共用该值，因此无需列举具体牌名。
const SLASH_EFFECT_ID: String = "slash"

## 【杀】的稳定卡牌定义ID；AI需要一张可代表整个【杀】牌族的实体定义来复用通用牌效评估。
const SLASH_DEFINITION_ID: String = "sha"

## 唯一目标判定要求的精确目标数；与原文“指定唯一目标”一致。
const SOLE_TARGET_COUNT: int = 1

## 结算完毕后失去的体力点数；与原文“你失去1点体力”一致。
const HP_COST: int = 1

## 主演因【杀】造成伤害时回复的体力点数；与原文“其回复1点体力”一致。
const STARRING_RECOVER_AMOUNT: int = 1

## 目标改写的时间窗口名；必须使用会写回用牌上下文的整牌时机。
## useCardBefore / useCardBegin 等窗口不写回上下文，改写会被静默丢弃。
const REWRITE_TIMING: String = "useCard"

## 本次用牌中已经完成目标改写的牌UID；防止异常重复派发导致目标被反复改写。
## 数组元素为稳定牌UID，随技能实例生命周期存在，不进入任何存档字段。
var _rewritten_card_uids: Array[int] = []

## 已改写、等待结算完毕后支付体力代价的牌UID；结算完毕时机据此精确配对。
## 代价是无条件支付的，因此只要本次用牌符合改写条件就会登记，与最终目标是否为空无关。
var _pending_hp_cost_card_uids: Array[int] = []


## 写入锁定技静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"zhili",
		"name":"支离",
		"lock":true,
		"ui_enabled":false,
		"description":"锁定技，你是你自己使用【杀】的合法目标。当“主演”使用【杀】造成伤害时，其回复1点体力。当你使用【杀】指定唯一目标时，你令此【杀】的目标改为与目标角色相邻的角色，此【杀】结算完毕后，你失去1点体力。",
	})


## 订阅目标改写、结算后代价支付、主演回复与死亡清理四个时机。
## useCard 使用 global 角色而非 source：主演回复效果属于“任意主演”，与持有者是否为伤害来源无关。
func install() -> void:
	subscribe_timing(REWRITE_TIMING, _on_owner_slash_used, "source")
	subscribe_timing("useCardAfter", _on_owner_slash_after, "source")
	subscribe_timing("damageSource", _on_starring_slash_damage, "global")
	subscribe_timing("dieAfter", _on_player_died, "global")


## 卸载技能时清空实例内的待结算标记，避免换将或重装技能后残留到新实例。
func uninstall() -> void:
	_rewritten_card_uids.clear()
	_pending_hp_cost_card_uids.clear()
	super()


## 声明持有者本人是自己使用【杀】的合法目标；只对【杀】牌族生效，不影响任何其他牌。
## 本钩子同时放宽目标枚举与距离限制：自己到自己的距离恒为0，因此不会被攻击范围拒绝。
func allows_self_as_card_target(card_definition: Dictionary) -> bool:
	return _is_slash_definition(card_definition)


## 预览持有者使用【杀】时的最终目标数组；把整牌时机的改写结果提前告知只读预览。
## 只处理“【杀】且唯一目标”的情形，其他数量返回原目标，保证预览与真实结算完全一致。
func preview_card_use_targets(card_definition: Dictionary, target_ids: Array[int]) -> Array[int]:
	if not _is_slash_definition(card_definition) or target_ids.size() != SOLE_TARGET_COUNT:
		return target_ids
	# 改写后的目标数组；无相邻角色时保留原目标，与规则层同一口径。
	var neighbor_ids: Array[int] = _get_seat_neighbor_ids(int(target_ids[0]))
	return neighbor_ids if not neighbor_ids.is_empty() else target_ids


## 持有者使用【杀】指定唯一目标时，把该【杀】的目标整体改为原目标的相邻角色，并登记体力代价。
func _on_owner_slash_used(event: RuleEvent) -> void:
	# 只处理持有者自己使用的牌；其他角色的用牌由各自技能负责。
	if event.source_id != owner_player_id:
		return
	# 牌实体UID；缺失时既无法改写也无法登记代价。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if card_uid < 0:
		return
	# 本次用牌改写的防重入；同一张牌只允许改写一次。
	if _rewritten_card_uids.has(card_uid):
		return
	# 牌定义判定；非【杀】牌族不进入本技能的任何效果。
	if not _is_slash_card_id(str(event.data.get("card_id", ""))):
		return
	# 目标数组；原文限定“指定唯一目标”，多目标与其他数量均不触发。
	var target_ids: Array = event.data.get("target_ids", []) as Array
	if target_ids.size() != SOLE_TARGET_COUNT:
		return
	# 唯一目标ID；目标在等待期间已经离场时仍要支付代价，因此替换失败不影响登记。
	var sole_target_id: int = int(target_ids[0])
	# 改写后的目标数组；原目标的存活环相邻角色，允许去重后只剩一名（例如2人局）。
	var neighbor_ids: Array[int] = _get_seat_neighbor_ids(sole_target_id)
	# 相邻角色为空时保留原目标继续结算；代价仍然无条件支付。
	if not neighbor_ids.is_empty():
		# 改写经权威端口提交，并按改写后的真实目标重新指示一次。
		# 出牌时播放的原始指向线是按改写前的旧目标绘制的，不重新指示会让玩家看到的箭头与实际结算对象不一致。
		if bool(host.call("replace_card_use_targets", card_uid, neighbor_ids, get_id())):
			indicate_targets(neighbor_ids)
	_rewritten_card_uids.append(card_uid)
	_pending_hp_cost_card_uids.append(card_uid)
	announce_activation({"card_uid":card_uid, "original_target_id":sole_target_id, "rewritten_target_ids":neighbor_ids.duplicate()})


## 【杀】整牌结算完毕后支付代价：持有者无条件失去1点体力。
func _on_owner_slash_after(event: RuleEvent) -> void:
	# 只处理自己使用的牌；其他角色的用牌不会登记本技能的代价。
	if event.source_id != owner_player_id:
		return
	# 牌实体UID；据此精确配对本次用牌登记的代价。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if card_uid < 0 or not _pending_hp_cost_card_uids.has(card_uid):
		return
	# 先清除登记再支付；无论支付是否真正生效，同一个UID都只兑现一次。
	_pending_hp_cost_card_uids.erase(card_uid)
	get_owner_skill_player().loseHp(HP_COST, get_owner_skill_player())


## 任意主演使用【杀】造成伤害时，该主演回复1点体力；效果归属主演本人而不是技能持有者。
func _on_starring_slash_damage(event: RuleEvent) -> void:
	# 伤害来源ID；无来源伤害（例如失去体力）不触发本效果。
	var damage_source_id: int = event.source_id
	if damage_source_id < 0 or not _is_starring_role(damage_source_id):
		return
	# 本次伤害必须由【杀】牌族造成；其他伤害来源（锦囊、技能）不回复。
	if not _is_slash_card_id(str(event.data.get("card_id", ""))):
		return
	# 伤害必须实际大于0；被完全抵消或归零的伤害不构成“造成伤害”。
	if int(event.data.get("amount", 0)) <= 0:
		return
	# 回复主体是主演本人；由权威端口统一处理回复上限与回复事件。
	host.call("recover", damage_source_id, damage_source_id, STARRING_RECOVER_AMOUNT, get_id())
	announce_activation({"starring_player_id":damage_source_id, "recover_amount":STARRING_RECOVER_AMOUNT})


## 任意角色死亡后清理指向该角色的待结算标记；死亡角色的【杀】不会再结算完毕。
func _on_player_died(event: RuleEvent) -> void:
	if event.player_id == owner_player_id:
		_rewritten_card_uids.clear()
		_pending_hp_cost_card_uids.clear()


## 修正持有者使用【杀】的AI评分；按改写后实际会命中的相邻角色重新计分，并扣除自身失去1点体力的代价。
## 需求口径：目标选择不再按“想杀谁就指定谁”评分，而是评估技能触发后真正被打到的人。
func modify_ai_card_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 动作必须是自己使用的【杀】；其他牌与技能动作不进入本钩子。
	if not _is_slash_card_id(str(action.get("card_definition_id", ""))):
		return current_score
	# 目标数组；只有“唯一目标”的【杀】才会被改写，其他数量保持原评分。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != SOLE_TARGET_COUNT:
		return current_score
	# 原指定目标ID；通用层已按它计入收益，改写生效时必须先把这部分收益撤销。
	var original_target_id: int = int(target_ids[0])
	# 改写后实际命中的目标ID数组；与规则层共用同一份相邻查询，保证规则与AI同源。
	var neighbor_ids: Array[int] = _get_snapshot_seat_neighbor_ids(authoritative_snapshot, original_target_id)
	# 改写后的评分；从通用层已计入的原目标收益出发做精确替换。
	var rewritten_score: float = current_score
	if not neighbor_ids.is_empty():
		# 撤销通用层对原目标的收益；原目标在改写后不再是本【杀】的目标。
		rewritten_score -= _score_single_slash_target(authoritative_snapshot, original_target_id, evaluator)
		# 按改写后真实命中的相邻角色重新计入收益；相邻者含自己或队友时自然得到负分。
		for neighbor_id: int in neighbor_ids:
			rewritten_score += _score_single_slash_target(authoritative_snapshot, neighbor_id, evaluator)
	# 代价：本次用牌结算完毕后持有者无条件失去1点体力；无相邻角色（保留原目标）时同样支付。
	rewritten_score += _score_self_hp_cost(authoritative_snapshot, evaluator)
	return rewritten_score


## 返回一张【杀】指向指定目标时的通用牌效估值；直接复用统一身份战略与牌效评估，不另立比例。
func _score_single_slash_target(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 【杀】的静态定义；缺失时不猜测收益。
	var definition: Dictionary = GameDatabase.get_card(SLASH_DEFINITION_ID)
	if definition.is_empty():
		return 0.0
	# 卡牌AI配置；与基础AI评分链读取同一份元数据。
	var ai_profile: Dictionary = evaluator.get_card_ai_profile(definition)
	return evaluator.score_target_effect(authoritative_snapshot, owner_player_id, target_id, definition, ai_profile, float(ai_profile.get("target_result", 0.0)))


## 返回持有者失去1点体力的AI估值；使用统一资源换算端口，不重复声明体力与牌的折算比例。
## 修正说明：资源变化的“目标”就是持有者本人，而 score_resource_change 内部会再乘一次对目标的态度；
## 自己对自己的态度恒为满值（10/ATTITUDE_SCALE = 2），会把1点体力的代价放大一倍（-4.0而非文档声明的 -HP_RESOURCE_VALUE=-2.0），
## 使斗地主等低收益场景下“指定自己再改判给相邻敌人”的净分被压成负数，AI 因而不出这张【杀】。
## 因此这里直接按统一资源常量计价：1点体力 = HP_RESOURCE_VALUE，与文档口径和其余内容层技能一致。
func _score_self_hp_cost(_authoritative_snapshot: Dictionary, _evaluator: Object) -> float:
	return -float(HP_COST) * NonameAIEvaluator.HP_RESOURCE_VALUE


## 返回指定角色在存活环座次上的相邻角色ID数组；无相邻者或目标无效时返回空数组。
## 结果按“从持有者开始的行动顺序”重排：结算顺序以使用者为起点，而相邻关系的天然顺序以**原目标**为起点
## （下家在前、上家在后），两者在以原目标为起点的场景下恰好一致，其余场景会颠倒。
## 例如4人局0号用【杀】指定1号，邻居集合为{2号, 0号}：以1号为起点是[2号, 0号]，
## 以使用者0号为起点才是[0号, 2号]；不重排会让持有者自己的伤害排在队友之后结算。
func _get_seat_neighbor_ids(player_id: int) -> Array[int]:
	if host == null or host.get("state") == null:
		return []
	return _sort_by_action_order(host.state.get_seat_neighbor_player_ids(player_id) as Array[int])


## 按“从持有者开始的行动顺序”重排一组角色ID；无效座次或缺失权威状态时返回原数组副本。
## 只做顺序调整，不增删成员：未被行动顺序覆盖的ID（例如等待期间已经离场的角色）一律原序追加，避免目标丢失。
func _sort_by_action_order(player_ids: Array[int]) -> Array[int]:
	if player_ids.size() <= 1 or host == null or host.get("state") == null:
		return player_ids.duplicate()
	# 重排结果；按持有者起算的环形行动顺序逐个收集。
	var result: Array[int] = []
	# 当前遍历角色；从持有者本人开始，因为他同样可能出现在改写后的目标里。
	var current_id: int = owner_player_id
	# 环形遍历一圈即可覆盖全部存活角色，邻居数量至多为二，因此不需要额外的排序数据结构。
	for _step: int in range(host.state.players.size()):
		if player_ids.has(current_id) and not result.has(current_id):
			result.append(current_id)
		# 下一名存活角色；权威查询返回角色对象，缺失时保持当前游标以避免死循环。
		var next_player: PlayerState = host.state.get_next_alive_player(current_id)
		if next_player == null:
			break
		current_id = next_player.player_id
	# 未被行动顺序覆盖的成员原序追加；正常局不会出现，只用于异常座次下的防御。
	for player_id: int in player_ids:
		if not result.has(player_id):
			result.append(player_id)
	return result


## 从只读快照计算指定角色的相邻角色ID；AI侧不复用权威状态，只能读取快照公开字段。
## 判定口径与 GameState.get_seat_neighbor_player_ids() 完全一致：存活且未离场的座次环形左右各一名并去重。
func _get_snapshot_seat_neighbor_ids(authoritative_snapshot: Dictionary, player_id: int) -> Array[int]:
	# 相邻结果；无有效目标时保持为空。
	var result: Array[int] = []
	# 有序座次数组；快照 order 即桌面座次顺序。
	var players: Array = authoritative_snapshot.get("players", []) as Array
	if players.is_empty():
		return result
	# 目标在座次数组中的位置；找不到时没有任何相邻关系。
	var target_index: int = -1
	for index: int in range(players.size()):
		var player: Dictionary = players[index] as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			target_index = index
			break
	if target_index < 0:
		return result
	# 存活且未离场角色的座次索引集合；死亡与离场角色被跳过并顺延。
	var alive_indexes: Array[int] = []
	for index: int in range(players.size()):
		var player: Dictionary = players[index] as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			alive_indexes.append(index)
	# 目标必须自身在存活环上，否则其相邻关系无意义。
	if not alive_indexes.has(target_index) or alive_indexes.size() < 2:
		return result
	# 目标在存活环中的位置；用于按下家→上家方向取两侧邻居。
	var ring_position: int = alive_indexes.find(target_index)
	var next_index: int = alive_indexes[(ring_position + 1) % alive_indexes.size()]
	var previous_index: int = alive_indexes[posmod(ring_position - 1, alive_indexes.size())]
	result.append(int((players[next_index] as Dictionary).get("player_id", -1)))
	# 存活角色不足3名时左右邻居指向同一名角色，去重后只保留一次。
	var previous_id: int = int((players[previous_index] as Dictionary).get("player_id", -1))
	if not result.has(previous_id):
		result.append(previous_id)
	return result


## 判断卡牌定义是否为【杀】牌族；只按统一的 effect_id 判定，不列举具体牌名。
func _is_slash_definition(definition: Dictionary) -> bool:
	return str(definition.get("effect_id", "")) == SLASH_EFFECT_ID


## 判断卡牌定义ID是否为【杀】牌族；虚拟【杀】同样通过其逻辑定义命中。
func _is_slash_card_id(card_id: String) -> bool:
	if card_id.is_empty():
		return false
	return _is_slash_definition(GameDatabase.get_card(card_id))


## 判断指定角色当前是否为「主演」；由权威控制器统一回答，AI与规则共用同一口径。
func _is_starring_role(player_id: int) -> bool:
	return host != null and host.has_method("is_starring_role") and bool(host.call("is_starring_role", player_id))
