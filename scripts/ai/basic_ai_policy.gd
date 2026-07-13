class_name BasicAIPolicy
extends RefCounted

## 基础内置 AI 策略。策略只读取完整状态快照与合法动作列表，不调用或修改对局核心。

## AI 控制的玩家 ID；用于从快照中定位自身状态与身份关系。
var player_id: int = -1


## 创建指定座次的基础策略；同一策略实例只服务一名玩家。
func _init(controlled_player_id: int) -> void:
	player_id = controlled_player_id


## 从核心提供的合法动作中选择一项；无可用动作时返回结束出牌阶段。
func choose_action(authoritative_snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	if legal_actions.is_empty():
		return {"action_type": "end_play", "actor_id": player_id}
	# 当前最佳动作；初始使用首项，后续按启发式分数替换。
	var best_action: Dictionary = legal_actions[0]
	# 当前最高分；使用极小值确保任意合法动作可覆盖。
	var best_score: float = -1000000.0
	for action: Dictionary in legal_actions:
		# 当前动作的启发式评分；分数只影响 AI 决策，不影响合法性与结算。
		var score: float = _score_action(authoritative_snapshot, action)
		if score > best_score:
			best_score = score
			best_action = action
	if best_score <= 0.0:
		return {"action_type": "end_play", "actor_id": player_id}
	return best_action.duplicate(true)


## 依据牌型、体力与身份关系计算动作价值；后续可替换为搜索、效用网络或模型策略。
func _score_action(snapshot: Dictionary, action: Dictionary) -> float:
	# 当前动作使用的卡牌定义 ID；结束阶段等动作可能为空。
	var card_id: String = str(action.get("card_definition_id", ""))
	# 当前动作目标数组；多数基础动作只有一个目标。
	var targets: Array = action.get("target_ids", []) as Array
	# 基础牌型价值；装备、补牌和治疗具有稳定正收益。
	var score: float = {
		"tao": 8.0, "jiu": 2.0, "wuzhong": 9.0, "wugu": 5.0, "taoyuan": 4.0,
		"zhuge": 5.0, "qinggang": 5.0, "cixiong": 4.0, "guanshi": 4.0,
		"qinglong": 4.0, "zhangba": 4.0, "fangtian": 5.0, "qilin": 4.0,
		"hanbing": 4.0, "guding": 4.0, "zhuque": 4.0, "bagua": 5.0,
		"renwang": 5.0, "baiyin": 5.0, "tengjia": 4.0, "jueying": 3.0,
		"dilu": 3.0, "zhuahuang": 3.0, "hualiu": 3.0, "chitu": 3.0,
		"dawan": 3.0, "zixin": 3.0, "muniu": 3.0, "tiesuo": 1.0,
	}.get(card_id, 3.0)
	if targets.is_empty():
		return score
	# 首个目标 ID；用于估算伤害、控制、治疗与身份阵营关系。
	var target_id: int = int(targets[0])
	# AI 对目标的阵营态度；正值代表友方，负值代表敌方。
	var attitude: float = _get_attitude(snapshot, target_id)
	if card_id in ["sha", "sha_fire", "sha_thunder", "juedou", "guohe", "shunshou", "huogong", "lebu", "bingliang", "shuiyanqijun"]:
		score += -attitude * 5.0
	elif card_id in ["tao", "wuzhong"]:
		score += attitude * 6.0
	elif card_id == "jiu":
		# 基础 AI 优先把【酒】用于自己，避免无后续联动信息时随机强化其他角色。
		score += 6.0 if target_id == player_id else attitude * 2.0
	return score


## 依据标准身份目标计算简化阵营态度；内奸会动态优先攻击人数占优的一方。
func _get_attitude(snapshot: Dictionary, target_id: int) -> float:
	# 快照玩家数组；权威 AI 快照包含全部身份与私有信息。
	var players: Array = snapshot.get("players", []) as Array
	# AI 自身身份；未找到时使用 rebel 作为保守默认值。
	var own_identity: String = "rebel"
	# 目标身份；未找到时视为隐藏并保持中立。
	var target_identity: String = "hidden"
	for player_variant: Variant in players:
		# 当前玩家快照；用于同时定位自己与目标。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			own_identity = str(player.get("identity", "rebel"))
		if int(player.get("player_id", -1)) == target_id:
			target_identity = str(player.get("identity", "hidden"))
	if own_identity == target_identity and own_identity != "renegade":
		return 1.0
	if own_identity in ["lord", "loyalist"] and target_identity in ["lord", "loyalist"]:
		return 1.0
	if own_identity == "rebel" and target_identity in ["lord", "loyalist"]:
		return -1.0
	if own_identity in ["lord", "loyalist"] and target_identity in ["rebel", "renegade"]:
		return -1.0
	if own_identity == "renegade":
		return -0.4
	return -0.7
