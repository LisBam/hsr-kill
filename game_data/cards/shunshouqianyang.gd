extends CardDefinition

## 【顺手牵羊】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
## requires_actor_choice=true：结算中必须由使用者本人选定要获得的目标区域牌，
## 使用者在结算前阵亡后无法代理该选择，本牌整体失效，牌不会交给已经阵亡的使用者。
func _init() -> void:
	super({
		"id": "shunshou",
		"original_name": "顺手牵羊",
		"custom_name": "万宇入腹",
		"type": "trick",
		"subtype": "normal",
		"effect_id": "steal_target",
		"nature": "normal",
		"target_mode": "single_other_with_cards",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "one",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": false,
		"description": "获得距离为1的一名其他角色区域里的一张牌。",
		"resolution_mode": "per_target",
		"final_zone": "discard",
		"requires_actor_choice": true,
		"provided_response_pattern": "",
		"ai": {"order":7.5, "value":9.0, "player_result":1.0, "target_result":-1.5, "lose_card":true, "gain":true},
		"ai_target_attitude": "hostile",
	})


## 执行【顺手牵羊】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	for target_id: int in target_ids:
		if resolver.should_skip_trick_target(card, actor_id, target_id):
			continue
		resolver.host.take_one_from_player(actor_id, target_id, card.uid)
		if resolver.host.has_pending_card_choice():
			return "pending"
	return resolver.default_destination()

## 修正对目标区域仅含判定区牌时的主动使用评分；获得敌方延时锦囊属于解控负收益，AI应避免打出。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 当前行动者；缺失时不做额外修正。
	var actor_id: int = int(action.get("actor_id", -1))
	# 动作目标列表；过河拆桥与顺手牵羊均为单目标。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.is_empty():
		return current_score
	# 当前目标快照；用于统计手牌、装备与判定区公开数量。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, int(target_ids[0]))
	if target.is_empty():
		return current_score
	# 目标手牌数；隐藏手牌只读数量，不猜牌面。
	var hand_count: int = int(target.get("hand_count", 0))
	# 目标装备区实体数；公开装备始终可计。
	var equipment_count: int = (target.get("equipment", {}) as Dictionary).size()
	# 目标判定区实体数；公开延时锦囊始终可计。
	var judgment_count: int = (target.get("judgment_area", []) as Array).size()
	# 仅有判定区牌时，收益完全取决于解控语义，不能沿用“失去一张牌”的通用负向目标分。
	if hand_count <= 0 and equipment_count <= 0 and judgment_count > 0:
		# 动作发起者对目标的态度；敌方解控为负，友方解控为正。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, actor_id, int(target_ids[0]))
		if attitude < 0.0:
			# 敌方仅判定区：使用本牌是净负收益，直接压到拒绝阈值以下。
			return -4.0
		if attitude > 0.0:
			# 友方仅判定区：帮助解除延时锦囊，保留正分鼓励。
			return maxf(current_score, 2.0)
		# 态度不明时保守拒绝，避免误拆他人判定区。
		return -2.0
	return current_score

