extends SkillDefinition

## 【鸿运】技能源码。持有者回合开始时，可立即额外触发一次阿哈时刻；该演出结束后持有者减少1点体力上限。
## 每轮限一次；额外演出不占用阿哈时刻的每轮额度，因此与本轮常规触发可能在同一回合内先后发生。

## 发动时需要支付的体力上限代价；固定1点，与原文“减少1点体力上限”一致。
const MAX_HP_COST: int = 1

## 发动所需的体力上限下限；上限不大于该值时已无减少空间，不再开放询问。
## 该值与原文无关，是为避免玩家支付一个不会生效的代价而补全的配套边界。
const MIN_REQUIRED_MAX_HP: int = 1

## 确认请求种类；恢复时按该值分流到发动入口。
const CONFIRM_KIND: String = "hongyun_confirm"

## 演出完成上下文中的种类标识；用于把鸿运自身的续接与其他请求方区分开。
const COMPLETION_KIND: String = "hongyun_extra_moment"

## AI：我方欢愉技领先达到该值时判定为“只要上限大于1就发动”；固定2，对应需求“多2或以上”。
const AI_DOMINANT_JOY_ADVANTAGE: int = 2

## AI：我方领先该值（含0）以内时视为均势或微弱优势，需要存在体力缺口才发动；固定1。
const AI_EVEN_JOY_ADVANTAGE_CEILING: int = 1

## AI：均势或微弱优势且存在体力缺口时的确认评分；正值使AI在收益成立时发动。
const AI_EVEN_ADVANTAGE_SCORE: float = 5.0

## AI：我方明显领先时的确认评分；高于均势分支，反映额外演出收益已足以覆盖上限代价。
const AI_DOMINANT_ADVANTAGE_SCORE: float = 8.0

## AI：敌方欢愉技更多时的确认评分；负值使AI在劣势局面下放弃发动。
const AI_HOSTILE_ADVANTAGE_SCORE: float = -10.0

## AI：体力上限不足时的确认评分；负值使AI放弃支付没有意义的代价。
const AI_INSUFFICIENT_MAX_HP_SCORE: float = -10.0

## 当前轮是否已经成功发动；roundStart重置，确认但演出登记失败时不消耗次数。
var _used_this_round: bool = false


## 写入技能静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"hongyun",
		"name":"鸿运",
		"trigger":"phaseBefore",
		"ui_enabled":false,
		"description":"你的回合开始前，你可以立即触发一次额外的阿哈时刻；该阿哈时刻结束后，你减少1点体力上限。每轮限一次。",
	})


## 订阅回合开始时询问与每轮额度重置；回合开始时机的口径与项目内其他“回合开始时”技能一致。
func install() -> void:
	subscribe_timing("roundStart", _on_round_start, "global")
	subscribe_timing("phaseBefore", _on_owner_turn_before, "player")


## 新轮开始时恢复一次发动额度。
func _on_round_start(_event: RuleEvent) -> void:
	_used_this_round = false


## 持有者回合开始时询问是否发动；额度、上限空间或场上演出可用性任一不满足时不创建询问。
func _on_owner_turn_before(_event: RuleEvent) -> void:
	if _used_this_round or not _can_offer_hongyun():
		return
	request_card_selection("鸿运", "是否发动【鸿运】立即触发一次额外的阿哈时刻？该演出结束后你减少1点体力上限。", [], 0, 0, true, {"kind":CONFIRM_KIND, "ai_allow_confirm":true})


## 判断当前是否具备发动鸿运的全部前置条件；纯查询，不创建选择也不修改任何状态。
func _can_offer_hongyun() -> bool:
	if host == null or host.get("state") == null:
		return false
	# 持有者状态；回合开始时机只在持有者自己的回合派发，此处仍复核以防御异常调用。
	var owner_player: PlayerState = host.state.get_player(owner_player_id)
	if owner_player == null or not owner_player.alive or owner_player.out_of_game:
		return false
	# 上限空间；上限已无减少空间时不开放询问，避免支付一个不会生效的代价。
	if owner_player.max_hp <= MIN_REQUIRED_MAX_HP:
		return false
	# 场上可执行欢愉技；没有参演技能时额外演出只会空转，同样不开放询问。
	return _has_performable_joy_skill()


## 判断场上是否存在至少一项当前可执行的欢愉技；与阿哈时刻的参演筛选保持同一口径。
func _has_performable_joy_skill() -> bool:
	for player: PlayerState in host.state.players:
		if player == null or not player.alive or player.out_of_game:
			continue
		if not (host.call("get_joy_skill_ids", player.player_id) as Array).is_empty():
			return true
	return false


## 恢复鸿运确认；只有额外演出成功入队才消费每轮次数，体力上限代价在演出结束后统一支付。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != CONFIRM_KIND or response == null:
		return false
	if response.confirmed and not _used_this_round:
		# 演出完成上下文；只保存稳定ID与武将代次，控制器据此把控制权交回本技能实例。
		var completion_context: Dictionary = {
			"kind":COMPLETION_KIND,
			"skill_owner_id":owner_player_id,
			"skill_id":get_id(),
			"skill_character_generation":get_bound_character_generation(),
		}
		# 演出步骤；本确认窗口此时仍在等待响应，控制器会拒绝“已有待响应选择”期间创建的新请求，
		# 而首名欢愉技一演出就要创建自己的窗口，因此必须先延后到统一结算管线清空后再驱动演出。
		if host.has_pending_card_choice():
			defer_settlement(completion_context)
			return true
		_start_extra_moment(completion_context)
	return true


## 恢复确认窗口产生的嵌套选择；统一结算管线清空后立即驱动一次额外阿哈时刻。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != COMPLETION_KIND:
		return false
	_start_extra_moment(context)
	return true


## 驱动一次额外阿哈时刻；只有演出成功入队才消费每轮次数并公开发动事实。
func _start_extra_moment(completion_context: Dictionary) -> void:
	if bool(host.call("try_trigger_extra_moment", owner_player_id, completion_context)):
		_used_this_round = true
		announce_activation({})


## 额外阿哈时刻结束后支付代价；核心端口保证体力上限最低为1，上限已无空间时返回0且不写日志。
func continue_joy_performance(context: Dictionary) -> void:
	if str(context.get("kind", "")) != COMPLETION_KIND:
		return
	if host == null or host.get("state") == null:
		return
	# 上限减少实际值；核心端口会夹紧上限，因此这里只依据返回值决定是否记录代价已经支付。
	var applied_cost: int = int(host.call("change_max_hp", owner_player_id, -MAX_HP_COST, owner_player_id, get_id()))
	if applied_cost == 0:
		return
	# 体力上限端口自身不写对局日志，这里补一条公开记录，使代价在日志与复盘里可见。
	host.call("add_log", "%s因【鸿运】减少%d点体力上限。" % [host.call("format_player_log_name", owner_player_id), MAX_HP_COST])


## 评估是否发动鸿运；按双方欢愉技数量差与自身体力缺口决定，并拒绝上限不足或敌方占优的局面。
##
## 评分口径对应需求给出的三段判据：敌方更多时不发动；均势或我方只多1时要求存在体力缺口；
## 我方领先2及以上时只要上限大于1就发动——此时额外演出带来的欢愉技收益足以覆盖上限代价。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；非鸿运确认不改变通用选择评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CONFIRM_KIND:
		return 0.0
	# 取消动作保持0分；确认只有严格正收益时才会被基础策略选中。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 自身状态；体力上限不足时不支付没有意义的代价。
	var self_player: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	# 自身当前体力；只用于判断是否存在需要保留的体力缺口。
	var self_hp: int = int(self_player.get("hp", 0))
	# 自身体力上限；低于发动门槛时直接否决本次确认。
	var self_max_hp: int = int(self_player.get("max_hp", 0))
	if self_max_hp <= MIN_REQUIRED_MAX_HP:
		return AI_INSUFFICIENT_MAX_HP_SCORE
	# 双方欢愉技数量差；正值表示我方领先，与需求判据使用同一整数尺度。
	var joy_advantage: int = int(evaluator.get_side_joy_skill_count(authoritative_snapshot, owner_player_id, true)) - int(evaluator.get_side_joy_skill_count(authoritative_snapshot, owner_player_id, false))
	if joy_advantage >= AI_DOMINANT_JOY_ADVANTAGE:
		return AI_DOMINANT_ADVANTAGE_SCORE
	if joy_advantage < 0:
		return AI_HOSTILE_ADVANTAGE_SCORE
	# 均势或我方只多1；只有体力未满时才值得用上限换取一次额外演出。
	return AI_EVEN_ADVANTAGE_SCORE if self_hp < self_max_hp else AI_HOSTILE_ADVANTAGE_SCORE
