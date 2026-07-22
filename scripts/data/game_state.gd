class_name GameState
extends RefCounted

## 一局游戏的权威状态根对象。核心规则只操作该结构，外部模块通过快照读取而不直接持有可变引用。

## 当前对局唯一 ID；联机与回放系统使用该值区分不同会话。
var match_id: String = ""

## 当前规则源码快照标识；回放必须匹配该值才能保证事件和选择语义一致。
var rules_snapshot: String = "noname-v1.10.16"

## 当前对局随机种子；固定种子可复现身份、候选武将和牌堆顺序。
var random_seed: int = 0

## 已消费随机结果摘要；关键随机分支保存用途与结果，回放可以跳过实时随机源。
var random_history: Array[Dictionary] = []

## 当前使用的牌堆配置 ID；默认采用标准、EX 与军争合并牌堆。
var deck_id: String = "standard_162"

## 本局由离线玩家或局域网房主在创建时锁定的开局选项；只包含可序列化配置，不随菜单中途变化。
var match_options: Dictionary = {}

## 当前对局模式稳定ID；identity=标准身份局、doudizhu=斗地主、team2v2=2v2、wheel_duel=1v1车轮战，缺省identity兼容旧状态。
var match_mode: String = "identity"

## 按座次排列的玩家状态；死亡玩家保留在数组中以维持距离与历史索引稳定。
var players: Array[PlayerState] = []

## 摸牌堆；数组末尾视为牌堆顶，以便常数时间抽取。
var draw_pile: Array[CardInstance] = []

## 弃牌堆；按进入顺序追加，重洗时整体移回摸牌堆。
var discard_pile: Array[CardInstance] = []

## 处理区；正在使用、打出或结算中的实体牌临时存放于此。
var processing_area: Array[CardInstance] = []

## 统一移牌事件历史；每次牌区变化追加 CardMoveEvent 摘要，回放不依赖场景节点。
var card_move_history: Array[Dictionary] = []

## 当前事件栈顶 ID；由 MatchController 同步 EventScheduler 的公开快照，默认 -1。
var current_event_id: int = -1

## 当前等待的选择请求摘要；普通观察者只能看到经过裁剪的候选信息。
var current_choice_request: Dictionary = {}

## 当前全体玩家可见的公共选牌展示；用于五谷丰登等需要跨多名选择者持续保留牌位的公开界面。
## 空字典表示没有公共展示；内容只能包含可序列化牌面快照、当前操作玩家 ID 与领取归属，不保存节点或规则对象。
var public_card_choice_display: Dictionary = {}

## 当前同时响应展示；保存本轮所有被询问玩家 ID 与锦囊目标，不包含任何玩家是否持有响应牌的私有信息。
var simultaneous_response_display: Dictionary = {}

## 当前开局前公共交互状态；用于房主调整 AI 武将等阶段，只保存可点击玩家 ID 与房主 ID，不含私有候选。
var pre_game_setup: Dictionary = {}

## 当前机缘系统公开交互状态；权威端保存全体候选，生成观察者快照时只向对应角色公开其三张候选牌。
var opportunity_state: Dictionary = {}

## 已完成事件摘要历史；记录事件父子、步骤和终止原因，支持规则回放与无头验收。
var event_history: Array[Dictionary] = []

## 全局轮数；每名存活角色完成一轮后递增，和 turn_number 保持独立。
var round_number: int = 0

## 当前阶段在标准阶段数组中的索引；阶段跳过和回放不依赖中文显示文本。
var phase_index: int = -1

## 当前濒死事件中的角色 ID 队列；允许多个嵌套伤害事件按顺序等待救援。
var dying_queue: Array[int] = []

## 当前对局的终局原因；winner 保存阵营，end_reason 保存 deck_empty、identity 或 system 等稳定原因。
var end_reason: String = ""

## 当前行动玩家 ID；无进行中的回合时为 -1。
var current_player_id: int = -1

## 当前阶段；可取 setup、character_selection、start、judgment、draw、play、choice、discard、finish、game_over。
var current_phase: String = "setup"

## 已开始的回合总数；每名角色开始回合时递增，用于日志与同步序号。
var turn_number: int = 0

## 全局动作序号；每次接受有效操作后递增，用于网络去重与回放排序。
var action_sequence: int = 0

## 当前获胜阵营描述；对局未结束时为空字符串。
var winner: String = ""

## 当前是否已经结束；结束后动作入口拒绝新的游戏指令。
var game_over: bool = false


## 按稳定 ID 返回玩家；不存在时返回 null。
func get_player(player_id: int) -> PlayerState:
	for player: PlayerState in players:
		if player.player_id == player_id:
			return player
	return null


## 返回所有仍存活玩家，顺序与桌面座次一致。
func get_alive_players() -> Array[PlayerState]:
	# 存活玩家结果数组；新数组可由调用方安全排序或筛选。
	var result: Array[PlayerState] = []
	for player: PlayerState in players:
		if player.alive and not player.out_of_game:
			result.append(player)
	return result


## 返回指定玩家之后的下一名存活玩家；全场仅一人时返回其自身。
func get_next_alive_player(player_id: int) -> PlayerState:
	if players.is_empty():
		return null
	# 指定玩家在座次数组中的位置；找不到时从0开始寻找。
	var start_index: int = 0
	for index: int in range(players.size()):
		if players[index].player_id == player_id:
			start_index = index
			break
	for offset: int in range(1, players.size() + 1):
		# 循环后的候选座次索引；使用取模保证从末尾回到开头。
		var candidate_index: int = (start_index + offset) % players.size()
		# 当前候选玩家；死亡玩家会被跳过。
		var candidate: PlayerState = players[candidate_index]
		if candidate.alive and not candidate.out_of_game:
			return candidate
	return null


## 返回指定玩家之前的上一名存活且未离场玩家；按座次向前环形查找，全场仅一名在场角色时返回其自身。
func get_previous_alive_player(player_id: int) -> PlayerState:
	if players.is_empty():
		return null
	# 指定玩家在座次数组中的位置；找不到时从一号位之前开始向前寻找。
	var start_index: int = 0
	for index: int in range(players.size()):
		if players[index].player_id == player_id:
			start_index = index
			break
	for offset: int in range(1, players.size() + 1):
		# 向前环形移动后的候选索引；posmod保证一号位的上家从数组末尾继续查找。
		var candidate_index: int = posmod(start_index - offset, players.size())
		# 当前候选玩家；死亡或离场角色不属于规则定义中的上家。
		var candidate: PlayerState = players[candidate_index]
		if candidate.alive and not candidate.out_of_game:
			return candidate
	return null


## 生成面向指定观察者的完整对局快照，供 UI、AI、网络和回放统一使用。
func to_dict(viewer_id: int = -1, reveal_private: bool = false) -> Dictionary:
	# 玩家快照数组；每名玩家自行处理手牌与身份的可见性。
	var player_data: Array = []
	for seat_index: int in range(players.size()):
		# 当前座位玩家；MatchController 会在身份确定后把领袖旋转到数组首位。
		var player: PlayerState = players[seat_index]
		# 座次快照；从1开始，供界面显示领袖为一号位且不依赖稳定 player_id。
		var serialized_player: Dictionary = player.to_dict(viewer_id, reveal_private)
		serialized_player["seat_number"] = seat_index + 1
		# 模式授予技能 ID；供技能栏与武将信息框展示飞扬/跋扈/共苦等，不修改武将静态定义。
		var mode_skill_ids: Array[String] = IdentityRules.new().get_mode_skill_ids(player.identity, match_mode)
		serialized_player["mode_skill_ids"] = mode_skill_ids
		player_data.append(serialized_player)
	# 当前选择请求快照；非响应者不能看到私有牌候选、已选牌和技能活动上下文。
	var choice_request_data: Dictionary = current_choice_request.duplicate(true)
	if not reveal_private and int(choice_request_data.get("actor_id", -1)) != viewer_id:
		choice_request_data["card_ids"] = []
		choice_request_data["target_ids"] = []
		choice_request_data["button_ids"] = []
		choice_request_data["control_ids"] = []
		choice_request_data["selected_card_ids"] = []
		choice_request_data["selected_target_ids"] = []
		choice_request_data["selected_button_ids"] = []
		choice_request_data["base_context"] = {}
		choice_request_data["active_context"] = {}
	# 当前公共处理区实体 UID；界面只用该集合核对中央牌面生命周期，不获得可变实体引用或额外私有牌面。
	var processing_card_uids: Array[int] = []
	# 当前处理区实体；只序列化稳定 UID，不附加新的牌面可见信息。
	for processing_card: CardInstance in processing_area:
		processing_card_uids.append(processing_card.uid)
	# 当前机缘快照；候选牌属于各角色私有信息，非权威观察者只能读取自己的候选数组。
	var opportunity_snapshot: Dictionary = opportunity_state.duplicate(true)
	if not opportunity_snapshot.is_empty() and not reveal_private:
		# 全体候选映射；权威状态保留每名参与者的三张牌，普通快照只投射当前观察者自己的条目。
		var all_options_by_player: Dictionary = opportunity_snapshot.get("options_by_player", {}) as Dictionary
		# 当前观察者候选；字符串键兼容网络序列化后的字典形式。
		var viewer_options: Array = all_options_by_player.get(str(viewer_id), all_options_by_player.get(viewer_id, [])) as Array
		opportunity_snapshot["options_by_player"] = {str(viewer_id):viewer_options.duplicate(true)} if viewer_id >= 0 else {}
		# 已选择卡牌正文只属于权威结算数据，公共界面仅需要知道哪些角色已经完成选择。
		opportunity_snapshot.erase("selected_cards_by_player")
	return {
		"match_id": match_id,
		"rules_snapshot": rules_snapshot,
		"random_seed": random_seed,
		"random_history_count": random_history.size(),
		"deck_id": deck_id,
		"match_mode": match_mode,
		"match_options": match_options.duplicate(true),
		"players": player_data,
		"draw_pile_count": draw_pile.size(),
		"discard_pile_count": discard_pile.size(),
		"processing_count": processing_area.size(),
		"processing_card_uids": processing_card_uids,
		"current_event_id": current_event_id,
		"current_choice_request": choice_request_data,
		"public_card_choice_display": public_card_choice_display.duplicate(true),
		"simultaneous_response_display": simultaneous_response_display.duplicate(true),
		"pre_game_setup": pre_game_setup.duplicate(true),
		"opportunity_state": opportunity_snapshot,
		"event_history_count": event_history.size(),
		"card_move_history_count": card_move_history.size(),
		"round_number": round_number,
		"phase_index": phase_index,
		"dying_queue": dying_queue.duplicate(),
		"current_player_id": current_player_id,
		"current_phase": current_phase,
		"turn_number": turn_number,
		"action_sequence": action_sequence,
		"winner": winner,
		"end_reason": end_reason,
		"game_over": game_over,
	}
