class_name GameState
extends RefCounted

## 一局游戏的权威状态根对象。核心规则只操作该结构，外部模块通过快照读取而不直接持有可变引用。

## 当前对局唯一 ID；联机与回放系统使用该值区分不同会话。
var match_id: String = ""

## 当前使用的牌堆配置 ID；默认采用标准、EX 与军争合并牌堆。
var deck_id: String = "standard_162"

## 按座次排列的玩家状态；死亡玩家保留在数组中以维持距离与历史索引稳定。
var players: Array[PlayerState] = []

## 摸牌堆；数组末尾视为牌堆顶，以便常数时间抽取。
var draw_pile: Array[CardInstance] = []

## 弃牌堆；按进入顺序追加，重洗时整体移回摸牌堆。
var discard_pile: Array[CardInstance] = []

## 处理区；正在使用、打出或结算中的实体牌临时存放于此。
var processing_area: Array[CardInstance] = []

## 当前行动玩家 ID；无进行中的回合时为 -1。
var current_player_id: int = -1

## 当前阶段；可取 setup、character_selection、start、judgment、draw、play、discard、finish、game_over。
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
		if player.alive:
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
		if candidate.alive:
			return candidate
	return null


## 生成面向指定观察者的完整对局快照，供 UI、AI、网络和回放统一使用。
func to_dict(viewer_id: int = -1, reveal_private: bool = false) -> Dictionary:
	# 玩家快照数组；每名玩家自行处理手牌与身份的可见性。
	var player_data: Array = []
	for player: PlayerState in players:
		player_data.append(player.to_dict(viewer_id, reveal_private))
	return {
		"match_id": match_id,
		"deck_id": deck_id,
		"players": player_data,
		"draw_pile_count": draw_pile.size(),
		"discard_pile_count": discard_pile.size(),
		"processing_count": processing_area.size(),
		"current_player_id": current_player_id,
		"current_phase": current_phase,
		"turn_number": turn_number,
		"action_sequence": action_sequence,
		"winner": winner,
		"game_over": game_over,
	}
