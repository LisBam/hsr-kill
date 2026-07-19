class_name IdentityStrategyEvaluator
extends RefCounted

## 标准身份局战略评估器。处理领袖危险、阵营集火、内奸控场、残局保护、威胁和濒死救援。

## 领袖进入高危状态的体力阈值；2点及以下开始显著影响忠臣、反贼和内奸决策。
const LEADER_DANGER_HP_THRESHOLD: int = 2

## 内奸在非单挑阶段避免直接杀死领袖的惩罚分；固定12足以压过常规1点伤害收益。
const RENEGADE_EARLY_LEADER_KILL_PENALTY: float = 12.0

## 濒死救援的基础收益；与消耗一张高价值【桃】比较后决定是否出牌。
const BASE_RESCUE_VALUE: float = 8.0

## 阵营被视为明显占优的局势绝对阈值；超过1后内奸开始主动压制优势方。
const CAMP_ADVANTAGE_THRESHOLD: int = 1

## 领袖危险度进入战略高危的阈值；达到4后显著改变集火、保护与内奸扶弱决策。
const LEADER_CRITICAL_DANGER: float = 4.0

## 领忠方攻击反贼时的威胁权重；高威胁目标更适合优先控制。
const LOYAL_THREAT_WEIGHT: float = 0.3

## 领忠方攻击反贼时的领袖危险权重；领袖越危险，清除反贼收益越高。
const LOYAL_LEADER_DANGER_WEIGHT: float = 0.45

## 反贼攻击领袖的基础集火分；确保同等牌效下优先完成阵营目标。
const REBEL_LEADER_FOCUS_BASE: float = 3.0

## 反贼攻击领袖时的危险度权重；领袖越濒危，终结价值越高。
const REBEL_LEADER_DANGER_WEIGHT: float = 0.7

## 反贼控制忠臣时的威胁权重；仅在领袖尚未进入高危时发挥完整作用。
const REBEL_LOYALIST_THREAT_WEIGHT: float = 0.2

## 领袖高危时反贼攻击忠臣的降权分；引导其改为直接集火领袖。
const REBEL_LOYALIST_DANGER_PENALTY: float = 1.5

## 内奸压制优势方或扶助弱势方的固定收益；用于形成稳定控场倾向。
const RENEGADE_BALANCE_BONUS: float = 3.0

## 内奸帮助优势方或攻击弱势方的固定惩罚；避免局势过早一边倒。
const RENEGADE_WRONG_CAMP_PENALTY: float = 2.0

## 领忠方在反贼清空后攻击内奸的残局收益；此时内奸成为唯一主要敌人。
const LOYAL_RENEGADE_ENDGAME_BONUS: float = 2.5

## 场上仍有反贼时领忠方攻击内奸的降权分；优先资源应投入反贼目标。
const LOYAL_RENEGADE_EARLY_PENALTY: float = 1.0

## 反贼数量很少时继续攻击内奸的降权分；避免反贼在关键残局主动削弱潜在制衡者。
const REBEL_RENEGADE_ENDGAME_PENALTY: float = 2.0

## 领忠方为领袖施加正面效果时的危险度权重；领袖越危险，保护收益越高。
const LEADER_SUPPORT_DANGER_WEIGHT: float = 0.8

## 反贼为同阵营角色施加正面效果的基础收益；体现阵营协作。
const REBEL_ALLY_SUPPORT_BASE: float = 1.5

## 反贼扶助同阵营高威胁角色时的附加权重；优先保住有效输出点。
const REBEL_ALLY_THREAT_WEIGHT: float = 0.1

## 内奸在领袖高危时为领袖施加正面效果的保护收益；用于保留多人局胜利路径。
const RENEGADE_LEADER_SUPPORT_BONUS: float = 6.0

## 无效救援请求的拒绝分；保证异常目标永远不会优先于合法取消动作。
const INVALID_RESCUE_SCORE: float = -100.0

## 自救避免自身死亡的额外收益；即使使用高价值救援牌也应积极响应。
const SELF_RESCUE_BONUS: float = 6.0

## 自救时救援牌价值的成本权重；死亡风险下只保留一半资源成本。
const SELF_RESCUE_COST_WEIGHT: float = 0.5

## 每多缺少1点回复量时单张救援的边际降权；避免误判一张牌必然救活深度濒死目标。
const EXTRA_RECOVER_PENALTY: float = 1.5

## 忠臣救领袖的身份额外收益；体现领袖存亡高于普通友方资源交换。
const LOYALIST_LEADER_RESCUE_BONUS: float = 8.0

## 多人局内奸救领袖的身份额外收益；领袖提前死亡会使内奸直接失去胜利路径。
const RENEGADE_LEADER_RESCUE_BONUS: float = 7.0

## 反贼救领袖的身份惩罚；确保常规情况下不会违背反贼胜利目标。
const REBEL_LEADER_RESCUE_PENALTY: float = 20.0

## 内奸或同阵营救助弱势角色时的控场收益；用于延缓优势阵营清场。
const WEAK_CAMP_RESCUE_BONUS: float = 4.0

## 领忠方救忠臣的身份额外收益；低于救领袖权重。
const LOYALIST_RESCUE_BONUS: float = 3.0

## 救援者仅剩1点体力时保留救援牌的惩罚；救领袖时不应用该惩罚。
const LOW_HP_RESCUE_RESERVE_PENALTY: float = 3.0

## 濒死友方没有手牌时的救援降权；缺少可立即转化为行动的资源时降低【桃】的长期收益。
const EMPTY_HAND_RESCUE_PENALTY: float = 2.5

## 濒死友方距离其下个回合每多等待一名角色的降权；从第二个等待座次开始累计。
const RESCUE_TURN_DISTANCE_PENALTY: float = 0.75

## 回合距离对救援价值的最大降权；避免长桌座次完全压过领袖保护与明确阵营目标。
const MAX_RESCUE_TURN_DISTANCE_PENALTY: float = 3.0

## 濒死友方判定区存在【乐不思蜀】时的降权；其下个出牌阶段可能被跳过。
const LEBU_RESCUE_PENALTY: float = 2.5

## 濒死友方判定区存在【兵粮寸断】时的降权；其下个摸牌阶段可能被跳过。
const BINGLIANG_RESCUE_PENALTY: float = 1.5

## 每张已知伤害牌增加的威胁值；用于区分同等体力与手牌数下的进攻能力。
const DAMAGE_CARD_THREAT: float = 0.6

## 公开武器增加的威胁值；武器通常提高攻击距离或伤害牌利用率。
const WEAPON_THREAT: float = 1.0

## 友方或未明确敌对目标保留的最低威胁倍率；供扶助和均势比较使用，但不会压过明确敌人。
const MINIMUM_THREAT_MULTIPLIER: float = 0.25

## 态度转换为威胁倍率时的归一化除数；标准身份态度约位于-10至10。
const THREAT_ATTITUDE_SCALE: float = 5.0

## 领袖每低于安全体力区间1点增加的危险值；体力风险高于单张手牌差。
const LEADER_HP_DANGER_WEIGHT: float = 2.0

## 领袖安全手牌阈值；不足2张时按缺口逐点增加危险度。
const LEADER_SAFE_HAND_COUNT: int = 2

## 每点敌方 condition 计入领袖危险度的权重；多个反贼可累积形成集火压力。
const ENEMY_PRESSURE_WEIGHT: float = 0.15

## 均势时内奸按目标 condition 压制强者的权重；避免固定身份偏好破坏平衡。
const RENEGADE_CONDITION_WEIGHT: float = 0.2

## 当前战略层使用的身份模型；共享暴露度、身份标记、真实态度和局势计算。
var identity_model: IdentityAIModel


## 创建绑定身份模型的战略评估器；模型为空时创建独立默认实例。
func _init(model: IdentityAIModel = null) -> void:
	identity_model = model if model != null else IdentityAIModel.new()


## 返回一项牌效指定目标时的身份战略附加分；通用牌效分之外再处理集火与控场。
func score_target_strategy(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, ai_profile: Dictionary) -> float:
	# 行动者快照；无效玩家不产生战略修正。
	var actor: Dictionary = identity_model.get_player(authoritative_snapshot, actor_id)
	# 目标快照；只读取公开状态，身份归属由感知身份接口提供。
	var target: Dictionary = identity_model.get_player(authoritative_snapshot, target_id)
	if actor.is_empty() or target.is_empty():
		return 0.0
	# 牌效方向；负值为伤害或控制，正值为回复、摸牌或其他增益。
	var target_result: float = float(ai_profile.get("target_result", 0.0))
	if is_zero_approx(target_result):
		return 0.0
	# 行动者身份；决定领袖保护、反贼集火或内奸控场策略。
	var actor_identity: String = str(actor.get("identity", ""))
	# 目标感知身份；只允许公开身份或忠反行为标记，禁止战略层偷看隐藏身份。
	var target_identity: String = identity_model.get_perceived_identity(authoritative_snapshot, target_id)
	# 当前领忠局势；正值领忠强，负值反贼强。
	var situation: int = identity_model.get_situation(authoritative_snapshot)
	# 当前领袖危险度；体力、手牌与敌方压力共同决定。
	var leader_danger: float = get_leader_danger(authoritative_snapshot)
	# 目标威胁；对敌方施加负面牌时优先高威胁角色。
	var target_threat: float = get_threat(authoritative_snapshot, actor_id, target_id)
	# 当前战略修正；按牌效正负分别处理。
	var score: float = 0.0
	if target_result < 0.0:
		if actor_identity in ["leader", "loyalist"]:
			if target_identity == "rebel":
				score += target_threat * LOYAL_THREAT_WEIGHT + leader_danger * LOYAL_LEADER_DANGER_WEIGHT
			elif target_identity == "renegade":
				# 场上仍有反贼时降低对内奸投入，反贼清空后转为主要敌人。
				score += LOYAL_RENEGADE_ENDGAME_BONUS if identity_model.get_population(authoritative_snapshot, "rebel") == 0 else -LOYAL_RENEGADE_EARLY_PENALTY
		elif actor_identity == "rebel":
			if target_identity == "leader":
				# 反贼优先集火领袖；领袖越危险，终结价值越高。
				score += REBEL_LEADER_FOCUS_BASE + leader_danger * REBEL_LEADER_DANGER_WEIGHT
			elif target_identity == "loyalist":
				# 忠臣威胁越高越值得控制，但领袖已高危时应优先领袖。
				score += target_threat * REBEL_LOYALIST_THREAT_WEIGHT - (REBEL_LOYALIST_DANGER_PENALTY if leader_danger >= LEADER_CRITICAL_DANGER else 0.0)
			elif target_identity == "renegade" and identity_model.get_population(authoritative_snapshot, "rebel") <= 1:
				score -= REBEL_RENEGADE_ENDGAME_PENALTY
		elif actor_identity == "renegade":
			score += _score_renegade_negative_effect(authoritative_snapshot, target, target_identity, situation)
	else:
		if actor_identity in ["leader", "loyalist"] and target_identity == "leader":
			score += leader_danger * LEADER_SUPPORT_DANGER_WEIGHT
		elif actor_identity == "rebel" and target_identity == "rebel":
			score += REBEL_ALLY_SUPPORT_BASE + target_threat * REBEL_ALLY_THREAT_WEIGHT
		elif actor_identity == "renegade":
			score += _score_renegade_positive_effect(target_identity, situation, leader_danger)
	return score


## 评估濒死救援选择；身份目标、领袖存亡、内奸残局和自身资源共同参与。
func score_rescue(authoritative_snapshot: Dictionary, responder_id: int, dying_player_id: int, required_recover: int, selected_card_value: float) -> float:
	# 救援者快照；无效角色不能救援。
	var responder: Dictionary = identity_model.get_player(authoritative_snapshot, responder_id)
	# 濒死者快照；身份未公开时只允许依据行为标记决定阵营救援。
	var dying_player: Dictionary = identity_model.get_player(authoritative_snapshot, dying_player_id)
	if responder.is_empty() or dying_player.is_empty():
		return INVALID_RESCUE_SCORE
	if responder_id == dying_player_id:
		# 自救直接避免自身死亡；即使消耗高价值牌也具有最高优先级。
		return BASE_RESCUE_VALUE + SELF_RESCUE_BONUS - selected_card_value * SELF_RESCUE_COST_WEIGHT
	# 救援者身份；AI 始终知道自身身份，用于确定自身胜利目标。
	var responder_identity: String = str(responder.get("identity", ""))
	# 濒死目标感知身份；只允许公开身份或行为推断身份参与额外阵营奖励。
	var dying_identity: String = identity_model.get_perceived_identity(authoritative_snapshot, dying_player_id)
	# 当前存活人数；内奸在多人局必须避免领袖提前死亡，单挑时不再救领袖。
	var alive_count: int = identity_model.get_alive_player_count(authoritative_snapshot)
	# 当前隐藏身份态度；未暴露角色不会仅凭真实身份无条件获救。
	var attitude: float = identity_model.get_attitude(authoritative_snapshot, responder_id, dying_player_id)
	# 基础救援收益；达到1点还需回复越多，单张救援对最终存活的边际价值略降低。
	var score: float = attitude + BASE_RESCUE_VALUE - float(maxi(required_recover - 1, 0)) * EXTRA_RECOVER_PENALTY
	# 明确友方的行动转化能力；敌对与未知角色不借此重复降权，领袖等战略奖励仍在后续独立计算。
	if attitude > 0.0:
		if int(dying_player.get("hand_count", 0)) <= 0:
			score -= EMPTY_HAND_RESCUE_PENALTY
		# 距离目标下回合的等待座次；紧邻行动不惩罚，从第二名等待角色开始逐步降低价值。
		var turn_distance: int = _get_turn_distance(authoritative_snapshot, dying_player_id)
		score -= minf(float(maxi(turn_distance - 1, 0)) * RESCUE_TURN_DISTANCE_PENALTY, MAX_RESCUE_TURN_DISTANCE_PENALTY)
		for judgment_variant: Variant in dying_player.get("judgment_area", []) as Array:
			# 判定区牌快照；固定定义ID用于区分跳过出牌与跳过摸牌风险。
			var judgment_card: Dictionary = judgment_variant as Dictionary
			# 判定区牌定义ID；同类延时锦囊不会重复放置，但循环仍保持通用。
			var judgment_id: String = str(judgment_card.get("definition_id", ""))
			if judgment_id == "lebu":
				score -= LEBU_RESCUE_PENALTY
			elif judgment_id == "bingliang":
				score -= BINGLIANG_RESCUE_PENALTY
	if dying_identity == "leader":
		if responder_identity == "loyalist":
			score += LOYALIST_LEADER_RESCUE_BONUS
		elif responder_identity == "renegade" and alive_count > 2:
			score += RENEGADE_LEADER_RESCUE_BONUS
		elif responder_identity == "rebel":
			score -= REBEL_LEADER_RESCUE_PENALTY
	elif responder_identity == "rebel" and dying_identity == "rebel":
		score += WEAK_CAMP_RESCUE_BONUS
	elif responder_identity in ["leader", "loyalist"] and dying_identity == "loyalist":
		score += LOYALIST_RESCUE_BONUS
	elif responder_identity == "renegade":
		# 内奸按局势救助弱势方，避免任一阵营过早清场。
		var situation: int = identity_model.get_situation(authoritative_snapshot)
		if situation > CAMP_ADVANTAGE_THRESHOLD and dying_identity == "rebel":
			score += WEAK_CAMP_RESCUE_BONUS
		elif situation < -CAMP_ADVANTAGE_THRESHOLD and dying_identity in ["leader", "loyalist"]:
			score += WEAK_CAMP_RESCUE_BONUS
	# 救援牌成本；自身1点体力时额外保留一张【桃】，除救领袖外降低出牌意愿。
	score -= selected_card_value
	if int(responder.get("hp", 0)) <= 1 and dying_identity != "leader":
		score -= LOW_HP_RESCUE_RESERVE_PENALTY
	return score


## 返回从当前行动者到目标下个回合需要经过的存活座次数；当前行动者就是目标时返回0。
func _get_turn_distance(authoritative_snapshot: Dictionary, target_id: int) -> int:
	# 存活玩家ID；死亡或离场角色不占用后续回合距离。
	var alive_player_ids: Array[int] = []
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；保持权威座次顺序。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			alive_player_ids.append(int(player.get("player_id", -1)))
	# 当前行动者座次；不存在时无法可靠估算，按不降权处理。
	var current_index: int = alive_player_ids.find(int(authoritative_snapshot.get("current_player_id", -1)))
	# 目标座次；不存在时同样按不降权处理。
	var target_index: int = alive_player_ids.find(target_id)
	if current_index < 0 or target_index < 0 or alive_player_ids.is_empty():
		return 0
	return posmod(target_index - current_index, alive_player_ids.size())


## 返回目标对观察者阵营的综合威胁；状态、伤害牌、武器和目标身份共同参与。
func get_threat(authoritative_snapshot: Dictionary, viewer_id: int, target_id: int) -> float:
	# 目标快照；不存在时威胁为0。
	var target: Dictionary = identity_model.get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return 0.0
	# 基础角色强度；复用无名杀 condition 公式。
	var threat: float = identity_model.get_condition(authoritative_snapshot, target_id)
	# 已知伤害牌数量；权威 AI 与无名杀服务端 AI 均可读取完整手牌，但仍只用于决策。
	var damage_card_count: int = 0
	for card_variant: Variant in target.get("hand", []) as Array:
		# 当前手牌实体；只读取稳定卡牌定义 ID。
		var card: Dictionary = card_variant as Dictionary
		# 当前手牌定义；伤害牌与【杀】均提高主动威胁。
		var definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
		# 当前手牌 AI 配置；damage 标志表示主动伤害能力。
		var ai_profile: Dictionary = definition.get("ai", {}) as Dictionary
		if bool(ai_profile.get("damage", false)) or str(definition.get("effect_id", "")) == "slash":
			damage_card_count += 1
	threat += float(damage_card_count) * DAMAGE_CARD_THREAT
	if (target.get("equipment", {}) as Dictionary).has("weapon"):
		threat += WEAPON_THREAT
	# 对观察者阵营的敌对程度；友方角色保留强度信息但不作为攻击优先级。
	var attitude: float = identity_model.get_attitude(authoritative_snapshot, viewer_id, target_id)
	return threat * maxf(-attitude / THREAT_ATTITUDE_SCALE, MINIMUM_THREAT_MULTIPLIER)


## 返回当前领袖危险度；体力、手牌短缺和敌方总威胁越高，数值越大。
func get_leader_danger(authoritative_snapshot: Dictionary) -> float:
	# 领袖 ID；标准身份局不存在领袖时危险度为0。
	var leader_id: int = identity_model.find_identity_player_id(authoritative_snapshot, "leader")
	if leader_id < 0:
		return 0.0
	# 领袖状态；体力和手牌直接决定防御能力。
	var leader: Dictionary = identity_model.get_player(authoritative_snapshot, leader_id)
	# 基础危险度；2点以下体力与不足2张手牌分别增加风险。
	var danger: float = float(maxi(LEADER_DANGER_HP_THRESHOLD + 1 - int(leader.get("hp", 0)), 0)) * LEADER_HP_DANGER_WEIGHT
	danger += float(maxi(LEADER_SAFE_HAND_COUNT - int(leader.get("hand_count", 0)), 0))
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前敌对角色；反贼威胁全部计入，内奸只在反贼清空后计入。
		var player: Dictionary = player_variant as Dictionary
		if not bool(player.get("alive", false)):
			continue
		# 当前敌对角色身份；领袖危险属于全局局势判断，可使用模式已知阵营构成计算压力。
		var identity: String = str(player.get("identity", ""))
		if identity == "rebel" or (identity == "renegade" and identity_model.get_population(authoritative_snapshot, "rebel") == 0):
			danger += identity_model.get_condition(authoritative_snapshot, int(player.get("player_id", -1))) * ENEMY_PRESSURE_WEIGHT
	return danger


## 返回内奸施加负面效果的控场分；压制优势方并避免多人局提前杀死领袖。
func _score_renegade_negative_effect(authoritative_snapshot: Dictionary, target: Dictionary, target_identity: String, situation: int) -> float:
	# 当前存活人数；超过2人时领袖死亡通常直接令内奸失败。
	var alive_count: int = identity_model.get_alive_player_count(authoritative_snapshot)
	if target_identity == "leader" and int(target.get("hp", 0)) <= 1 and alive_count > 2:
		return -RENEGADE_EARLY_LEADER_KILL_PENALTY
	if situation > CAMP_ADVANTAGE_THRESHOLD:
		return RENEGADE_BALANCE_BONUS if target_identity in ["leader", "loyalist"] else -RENEGADE_WRONG_CAMP_PENALTY
	if situation < -CAMP_ADVANTAGE_THRESHOLD:
		return RENEGADE_BALANCE_BONUS if target_identity == "rebel" else -RENEGADE_WRONG_CAMP_PENALTY
	# 均势时优先压制场上综合状态更强的角色。
	return identity_model.get_condition(authoritative_snapshot, int(target.get("player_id", -1))) * RENEGADE_CONDITION_WEIGHT


## 返回内奸施加正面效果的控场分；扶助弱势方并在多人局保护濒危领袖。
func _score_renegade_positive_effect(target_identity: String, situation: int, leader_danger: float) -> float:
	if target_identity == "leader" and leader_danger >= LEADER_CRITICAL_DANGER:
		return RENEGADE_LEADER_SUPPORT_BONUS
	if situation > CAMP_ADVANTAGE_THRESHOLD:
		return RENEGADE_BALANCE_BONUS if target_identity == "rebel" else -RENEGADE_WRONG_CAMP_PENALTY
	if situation < -CAMP_ADVANTAGE_THRESHOLD:
		return RENEGADE_BALANCE_BONUS if target_identity in ["leader", "loyalist"] else -RENEGADE_WRONG_CAMP_PENALTY
	return 0.0
