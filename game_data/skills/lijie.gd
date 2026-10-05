extends SkillDefinition

## 【礼节】技能源码。
##
## 两段互不相关的可选回赠，各自用核心已经提供的权威时机判定，本技能不额外写名单或阶段过滤：
##
## 一、当你一次性获得至少两张牌后，你可令一名其他角色摸一张牌。
##    “一次性”直接使用核心的批量获得时机 `cardsGainedBatchAfter`：核心以**一次动作**划分批次
##    （摸牌、获得全部手牌、逐组获得等），因此本技能不需要自己判断“是否同一次”。
##    开局前起始手牌分发不构成“获得牌”动作，核心不会派发该时机，天然不计入。
##    时机负载的 `batch_size` 即本次动作实际进入手牌的张数。
##
## 二、当其他角色令你回复体力后，你可令其回复1点体力。
##    “令你回复体力”以回复结算的 `source_id` 为准：来源为其他角色时才成立，
##    自己令自己回复（例如自己使用【桃】）以及无来源的系统回复都不触发。
##    实际回复量为0（例如体力已满被截断）的通知同样不触发。
##
## 交互实现：两段的询问都先登记为**延后结算**，等统一结算管线清空后再创建选择窗口。
## 原因：批量获得与回复都在中场结算内部派发，此时直接创建请求会被控制器以“已有待响应选择”拒绝，
## 与【风口】【咬它】的处理方式一致。
##
## AI：摸牌目标按“目标获得一张牌的收益 + 友方手牌缺口”评分；回复来源按“来源获得1点体力的收益”评分，
## 因此只会把回赠与回复给到态度为正的角色，对敌方来源保持取消。

## 第一段“令一名其他角色摸一张牌”的请求种类。
const CHOICE_KIND_GAIN_TARGET: String = "lijie_gain_target"

## 第二段“令回复来源回复1点体力”的请求种类。
const CHOICE_KIND_RECOVER_SOURCE: String = "lijie_recover_source"

## 第二段确认选项的稳定ID；仅用于选择协议与回放，玩家可见文本由选项label提供。
const CONFIRM_OPTION_ID: String = "lijie_recover_yes"

## 第一段延后结算的种类。
const SETTLEMENT_KIND_GAIN: String = "lijie_defer_gain"

## 第二段延后结算的种类。
const SETTLEMENT_KIND_RECOVER: String = "lijie_defer_recover"

## 延后结算上下文中携带回复来源玩家ID的键名。
const SETTLEMENT_SOURCE_ID_KEY: String = "source_id"

## 延后结算上下文中携带本次批量张数的键名。
const SETTLEMENT_BATCH_SIZE_KEY: String = "batch_size"

## 延后结算上下文中携带批次号的键名。
const SETTLEMENT_BATCH_ID_KEY: String = "gain_batch_id"

## 构成“一次性获得至少两张牌”的最小张数；单张获得不构成发动条件。
const MIN_BATCH_SIZE: int = 2

## 第一段令目标摸牌的张数；与原文“摸一张牌”一致，运行时不得修改。
const DRAW_COUNT: int = 1

## 第二段令来源回复的体力值；与原文“回复1点体力”一致，运行时不得修改。
const RECOVER_AMOUNT: int = 1

## 技能效果写入手牌或体力时使用的来源标记；便于回溯本次回复由技能造成。
const REASON_LIJIE: String = "lijie"

## 第一段手牌缺口修正的参考手牌数；低于该值的友方获得额外补牌优先级。
const AI_HAND_GAP_REFERENCE: float = 3.0

## 第一段每点手牌缺口的修正系数；保持较低权重，避免压过资源收益的方向判断。
const AI_HAND_GAP_WEIGHT: float = 0.25

## 条件已失效却仍提交选择时的惩罚分；防止等待期间目标死亡后AI继续提交。
const AI_INVALID_PENALTY: float = -100.0


## 写入技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"lijie",
		"name":"礼节",
		"trigger":"cardsGainedBatchAfter/recoverAfter",
		"ui_enabled":false,
		"description":"当你一次性获得至少两张牌后，你可令一名其他角色摸一张牌。当其他角色令你回复体力后，你可令其回复1点体力。",
	})


## 订阅“一次性获得至少两张牌”与“持有者回复体力后”两个时机。
## 批量获得使用 player 关系：原文只关心**你自己**一次获得至少两张牌。
## 回复使用 target 关系：只有回复对象是持有者本人时才成立。
func install() -> void:
	subscribe_timing("cardsGainedBatchAfter", _on_cards_gained_batch, "player")
	subscribe_timing("recoverAfter", _on_owner_recovered, "target")


## 一次性获得至少两张牌后登记延后询问；批量不足、持有者失效或没有其他角色时完全不询问。
func _on_cards_gained_batch(event: RuleEvent) -> void:
	# 本次动作实际进入手牌的张数；核心按一次动作划分批次。
	var batch_size: int = int(event.data.get(SETTLEMENT_BATCH_SIZE_KEY, 0))
	if batch_size < MIN_BATCH_SIZE:
		return
	if not _is_player_usable(owner_player_id):
		return
	# 其他角色候选；没有可选目标时不登记，避免出现“点了确认却没有效果”的空询问。
	if _get_other_player_ids().is_empty():
		return
	defer_settlement({
		"kind":SETTLEMENT_KIND_GAIN,
		SETTLEMENT_BATCH_SIZE_KEY:batch_size,
		SETTLEMENT_BATCH_ID_KEY:int(event.data.get(SETTLEMENT_BATCH_ID_KEY, -1)),
	})


## 其他角色令持有者回复体力后登记延后询问；自己令自己回复与无来源回复都不触发。
func _on_owner_recovered(event: RuleEvent) -> void:
	# 实际回复量；被体力上限截断为0的通知不构成“回复体力”。
	if int(event.data.get("amount", 0)) <= 0:
		return
	# 回复来源；负数表示无来源的系统回复，等于持有者本人表示自己令自己回复。
	var source_id: int = int(event.source_id)
	if source_id < 0 or source_id == owner_player_id:
		return
	if not _is_player_usable(source_id):
		return
	defer_settlement({"kind":SETTLEMENT_KIND_RECOVER, SETTLEMENT_SOURCE_ID_KEY:source_id})


## 统一结算管线清空后创建两段的询问窗口；此时创建请求不会被“已有待响应选择”拒绝。
func continue_settlement(context: Dictionary) -> bool:
	# 当前延后步骤；区分两段。
	var kind: String = str(context.get("kind", ""))
	if kind == SETTLEMENT_KIND_GAIN:
		if not _is_player_usable(owner_player_id):
			return true
		# 其他角色候选；等待期间可能有人死亡或离场，因此重新计算而不是复用登记时的列表。
		var target_ids: Array[int] = _get_other_player_ids()
		if target_ids.is_empty():
			return true
		request_target_selection("【礼节】请选择一名其他角色，令其摸一张牌", target_ids, 1, 1, true, {
			"kind":CHOICE_KIND_GAIN_TARGET,
			SETTLEMENT_BATCH_SIZE_KEY:int(context.get(SETTLEMENT_BATCH_SIZE_KEY, 0)),
			SETTLEMENT_BATCH_ID_KEY:int(context.get(SETTLEMENT_BATCH_ID_KEY, -1)),
		})
		return true
	if kind == SETTLEMENT_KIND_RECOVER:
		# 回复来源；等待期间死亡或离场时不再询问。
		var source_id: int = int(context.get(SETTLEMENT_SOURCE_ID_KEY, -1))
		if not _is_player_usable(owner_player_id) or not _is_player_usable(source_id):
			return true
		# 确认选项；只有一项，取消表示不回报这次回复。
		var options: Array[Dictionary] = [{"id":CONFIRM_OPTION_ID, "label":"确定"}]
		request_control_selection("礼节", "【礼节】是否令%s回复1点体力？" % host.format_player_state_log_name(host.state.get_player(source_id)), options, true, {
			"kind":CHOICE_KIND_RECOVER_SOURCE,
			SETTLEMENT_SOURCE_ID_KEY:source_id,
		})
		return true
	return false


## 恢复两段询问的选择结果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 当前选择步骤；两段使用独立评分与效果。
	var kind: String = str(context.get("kind", ""))
	if kind == CHOICE_KIND_GAIN_TARGET:
		if response == null or not response.confirmed or response.target_ids.size() != 1:
			return true
		# 最终摸牌目标；等待期间死亡或离场时跳过本次效果。
		var target_id: int = response.target_ids[0]
		if target_id == owner_player_id or not _is_player_usable(target_id):
			return true
		announce_activation({"target_id":target_id, "draw_count":DRAW_COUNT, SETTLEMENT_BATCH_SIZE_KEY:int(context.get(SETTLEMENT_BATCH_SIZE_KEY, 0)), SETTLEMENT_BATCH_ID_KEY:int(context.get(SETTLEMENT_BATCH_ID_KEY, -1))})
		host.call("draw", target_id, DRAW_COUNT)
		return true
	if kind == CHOICE_KIND_RECOVER_SOURCE:
		if response == null or not response.confirmed or response.control_id != CONFIRM_OPTION_ID:
			return true
		# 回复来源；等待期间死亡或离场时跳过本次效果。
		var source_id: int = int(context.get(SETTLEMENT_SOURCE_ID_KEY, -1))
		if not _is_player_usable(owner_player_id) or not _is_player_usable(source_id):
			return true
		# 回复前体力；只有实际回复成立时才记录发动，满体力调用保持无副作用。
		var previous_hp: int = host.state.get_player(source_id).hp
		host.call("recover", owner_player_id, source_id, RECOVER_AMOUNT, REASON_LIJIE)
		if host.state.get_player(source_id).hp > previous_hp:
			announce_activation({"target_id":source_id, "recover":RECOVER_AMOUNT})
		return true
	return false


## 评估礼节两段询问：第一段按“目标获得一张牌 + 友方手牌缺口”选目标，第二段按“来源获得1点体力”评分。
## 两段都以持有者态度换算敌我方向，因此敌方目标得到负分，AI会退回取消（中性0分）。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；区分两段。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 动作负载；保存所选目标或确认项。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 当前选择步骤；不同步骤使用独立评分模型。
	var kind: String = str(context.get("kind", ""))
	if kind == CHOICE_KIND_GAIN_TARGET:
		# 所选目标数组；取消或数量异常时交回通用中性分。
		var targets: Array = payload.get("selected_target_ids", []) as Array
		if targets.size() != 1:
			return 0.0
		# 唯一摸牌目标稳定ID；用于读取公开状态与态度。
		var target_id: int = int(targets[0])
		# 目标权威快照；不存在或已死亡时不提交。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if target.is_empty() or not bool(target.get("alive", false)) or bool(target.get("out_of_game", false)):
			return AI_INVALID_PENALTY
		# 目标获得一张牌的收益；友方为正、敌方为负，方向由统一资源换算给出。
		var score: float = evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, DRAW_COUNT, 0)
		# 手牌缺口修正；关系为正且手牌越少的友方越需要这一张牌。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		if attitude > 0.0:
			score += maxf(AI_HAND_GAP_REFERENCE - float(target.get("hand_count", 0)), 0.0) * AI_HAND_GAP_WEIGHT
		return score
	if kind == CHOICE_KIND_RECOVER_SOURCE:
		if not bool(payload.get("confirmed", false)) or str(payload.get("selected_control_id", "")) != CONFIRM_OPTION_ID:
			return 0.0
		# 回复来源；不存在或已死亡时不提交。
		var source_id: int = int(context.get(SETTLEMENT_SOURCE_ID_KEY, -1))
		var source: Dictionary = evaluator.get_player(authoritative_snapshot, source_id)
		if source.is_empty() or not bool(source.get("alive", false)) or bool(source.get("out_of_game", false)):
			return AI_INVALID_PENALTY
		# 来源获得1点体力的收益；友方为正、敌方为负，因此回报只给态度为正的来源。
		return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, source_id, 0, RECOVER_AMOUNT)
	return 0.0


## 返回全部可作为“其他角色”的稳定玩家ID；只包含存活且未离场、且不是持有者本人的角色。
func _get_other_player_ids() -> Array[int]:
	# 候选结果；保持权威座次顺序，界面、AI与回放据此稳定复现。
	var result: Array[int] = []
	if host == null or host.state == null:
		return result
	for player_variant: Variant in host.state.players as Array:
		var player: PlayerState = player_variant as PlayerState
		if player == null or player.player_id == owner_player_id:
			continue
		if not player.alive or player.out_of_game:
			continue
		result.append(player.player_id)
	return result


## 判断指定角色此刻是否可以承载技能效果；不存在的角色一律返回false。
func _is_player_usable(player_id: int) -> bool:
	if host == null or host.state == null or player_id < 0:
		return false
	var player: PlayerState = host.state.get_player(player_id)
	return player != null and player.alive and not player.out_of_game
