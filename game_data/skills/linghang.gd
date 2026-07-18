extends SkillDefinition

## 【领航】技能源码。星穹列车角色造成任意方向的连环状态切换后，领袖可令该事件来源角色选择重铸一张手牌。

## 星穹列车势力稳定 ID；修改后会改变可触发本技能的事件来源角色范围。
const FACTION_ID: String = "xingqionglieche"

## AI 估算重铸后获得一张未知牌的资源价值；只影响是否选择重铸，不修改真实摸牌数量。
const AI_UNKNOWN_DRAW_VALUE: float = 2.0

## AI 将技能持有者对触发角色的身份态度换算为发动收益的除数；越小越倾向帮助友方重铸。
const AI_ATTITUDE_DIVISOR: float = 2.0

## 最近一次已经发动技能的全局回合编号；-1表示本局尚未发动，确认发动后写入 state.turn_number。
var _used_turn_number: int = -1


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": "linghang",
		"name": "领航",
		"trigger": "linkAfter",
		"ui_enabled": false,
		"leader_skill": true,
		"description": "领袖技，“星穹列车”势力的角色使一名角色横置时，你可对其发动此技能，然后其可重铸一张手牌。每回合限一次。",
	})


## 订阅连环状态完成时机；set_player_linked 的两个变化方向共用同一 linkAfter 事实事件。
func install() -> void:
	subscribe_timing("linkAfter", _on_link_after, "global")


## 任意星穹列车角色使连环状态发生变化后询问技能持有者；横置转竖直同样满足“使一名角色横置时”。
func _on_link_after(event: RuleEvent) -> void:
	if _used_turn_number == host.state.turn_number:
		return
	# 技能持有者；死亡或离场领袖不能发动其触发技。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 连环切换来源角色；必须是实际调用统一连环端口的星穹列车角色，而不是状态变化的目标角色。
	var source_player_id: int = event.source_id
	var source_player: PlayerState = host.state.get_player(source_player_id) as PlayerState
	if source_player == null or not source_player.alive or source_player.out_of_game or not _is_faction_player(source_player, FACTION_ID):
		return
	request_card_selection("领航", "是否对使角色横置状态发生变化的角色发动【领航】？", [], 0, 0, true, {"kind":"linghang_confirm", "source_player_id":source_player_id, "ai_allow_confirm":true})


## 恢复领袖发动确认与来源角色重铸选择；发动次数在首段确认时消耗，取消重铸不会返还。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；确认发动与选择重铸牌使用不同 kind，保证次数消费只发生一次。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "linghang_confirm":
		if not response.confirmed or _used_turn_number == host.state.turn_number:
			return true
		# 一旦姬子确认发动便立即记录本回合次数，后续没有手牌或直接取消重铸都不会返还。
		_used_turn_number = host.state.turn_number
		announce_activation({"source_player_id":int(context.get("source_player_id", -1))})
		var source_player_id: int = int(context.get("source_player_id", -1))
		var source_player: PlayerState = host.state.get_player(source_player_id) as PlayerState
		if source_player == null or not source_player.alive or source_player.out_of_game or not _is_faction_player(source_player, FACTION_ID):
			return true
		# 来源角色普通手牌候选；重铸者是使连环状态变化的角色，不是被横置或竖置的目标。
		var candidates: Array[Dictionary] = host.call("get_hand_candidates", source_player_id, source_player_id) as Array[Dictionary]
		if candidates.is_empty():
			return true
		request_card_selection_for_player(source_player_id, "领航", "你可重铸一张手牌，或直接取消", candidates, 1, 1, true, {"kind":"linghang_recast", "source_player_id":source_player_id})
		return true
	if choice_kind == "linghang_recast":
		if response.confirmed and response.card_ids.size() == 1:
			# 权威重铸端口会再次复核实体仍在来源角色的普通手牌区，取消或失效均不影响已消耗次数。
			host.call("recast_hand_card", int(context.get("source_player_id", -1)), response.card_ids[0])
		return true
	return false


## 判断权威玩家当前武将是否属于指定势力；势力元数据只筛选技能触发者，不替代身份模式阵营。
func _is_faction_player(player: PlayerState, faction_id: String) -> bool:
	if player == null:
		return false
	# 当前武将定义；空武将或未知定义不会被误判为星穹列车角色。
	var character: Dictionary = GameDatabase.get_character(player.character_id)
	return str(character.get("faction", "")) == faction_id


## 评估领袖确认与来源角色重铸选择；友方更值得发动，实际重铸优先使用低于未知摸牌价值的手牌。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文与动作负载；取消动作由通用策略保留为0分，不在技能内重复奖励。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == "linghang_confirm":
		if not bool(payload.get("confirmed", false)):
			return 0.0
		return evaluator.get_attitude(authoritative_snapshot, owner_player_id, int(context.get("source_player_id", -1))) / AI_ATTITUDE_DIVISOR
	if choice_kind == "linghang_recast":
		# 已选手牌；只有预期摸牌价值严格高于保留价值时，AI 才确认重铸而不是直接取消。
		var selected_cards: Array = payload.get("selected_card_uids", []) as Array
		return AI_UNKNOWN_DRAW_VALUE - evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), int(context.get("source_player_id", -1))) if selected_cards.size() == 1 else 0.0
	return 0.0
