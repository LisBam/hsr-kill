extends SkillDefinition

## 【幽锋】技能源码。每轮开始强制弃置其他角色的一张牌并转移唯一【猎物】标记，随后根据自身状态离场或失去体力。

## 猎物标记稳定ID；全场相同ID只允许一名角色持有，修改会影响【掠袭】的全部联动查询。
const HUNT_MARK_ID: String = "liewu"

## 猎物标记显示单字；固定为“猎”，用于圆形图标中央且不参与规则判断。
const HUNT_MARK_ICON: String = "猎"

## 已处于离场状态时失去的体力值；固定为1，与技能原文一致。
const OUT_OF_GAME_HP_LOSS: int = 1

## AI对敌对目标的基础优先倍率；态度越负越优先成为猎物，只影响选择不改变技能数值。
const AI_HOSTILE_ATTITUDE_WEIGHT: float = 1.6

## AI对低生存目标的优先倍率；体力与护盾越少越容易被后续伤害触发【掠袭】。
const AI_VULNERABILITY_WEIGHT: float = 1.2


## 写入离场锁定技静态信息；技能描述严格保持主公钦定原文。
func _init() -> void:
	super({
		"id":"youfeng",
		"name":"幽锋",
		"trigger":"roundStart",
		"ui_enabled":false,
		"lock":true,
		"out_of_game_skill":true,
		"description":"离场技，锁定技，每轮开始时，你弃置一名其他角色的一张牌并令其获得“猎物”标记，然后若你未处于离场状态，你离场；若你已处于离场状态，你失去1点体力。",
	})


## 订阅每轮开始时机；离场技元数据保证持有者离场后仍会接收该全局事件。
func install() -> void:
	subscribe_timing("roundStart", _on_round_start, "global")


## 每轮开始强制选择一名其他存活在场角色；没有合法其他角色时不创建无法完成的请求。
func _on_round_start(_event: RuleEvent) -> void:
	# 其他角色候选；标记允许保持在原目标上，因此当前已拥有猎物的角色不会被排除。
	var target_ids: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.player_id != owner_player_id and player.alive and not player.out_of_game:
			target_ids.append(player.player_id)
	if target_ids.is_empty():
		return
	request_target_selection("【幽锋】请选择一名角色弃置其一张牌并令其获得“猎物”标记", target_ids, 1, 1, false, {"kind":"youfeng_target"})


## 恢复目标或弃牌步骤；有区域牌时先强制选择一张，空区域目标直接进入标记与自身状态结算。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	# 当前选择步骤；幽锋使用两个连续请求并共享同一技能实例恢复。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind not in ["youfeng_target", "youfeng_discard"] or response == null:
		return false
	if not response.confirmed:
		return true
	if choice_kind == "youfeng_target":
		if response.target_ids.size() != 1:
			return true
		# 最终猎物目标；等待期间必须仍然存活且在场。
		var target_id: int = response.target_ids[0]
		# 目标权威状态；失效目标不写入标记，也不继续改变貊泽状态。
		var target: PlayerState = host.state.get_player(target_id)
		if target == null or not target.alive or target.out_of_game or target_id == owner_player_id:
			return true
		# 目标全部区域候选；手牌对貊泽保持暗置，装备与判定区公开。
		var candidates: Array[Dictionary] = host.call("get_player_zone_candidates", owner_player_id, target_id) as Array[Dictionary]
		if candidates.is_empty():
			_apply_hunt_target(target_id)
			return true
		request_card_selection("幽锋", "请选择弃置目标区域内的一张牌", candidates, 1, 1, false, {"kind":"youfeng_discard", "target_id":target_id})
		return true
	if response.card_ids.size() != 1:
		return true
	# 弃牌目标ID；区域移动前由控制器再次校验实体归属与保护技能。
	var target_id: int = int(context.get("target_id", -1))
	# 弃置是否实际成立；失败时仍按当前有效目标继续强制标记，避免旧候选令整轮锁定技永久中断。
	var discarded: bool = bool(host.call("discard_selected_player_card", owner_player_id, target_id, response.card_ids[0]))
	if discarded and defer_settlement({"kind":"youfeng_apply_hunt", "target_id":target_id}):
		return true
	_apply_hunt_target(target_id)
	return true


## 在弃牌移动产生的嵌套触发全部完成后继续标记与自身状态结算。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "youfeng_apply_hunt":
		return false
	_apply_hunt_target(int(context.get("target_id", -1)))
	return true


## 写入全场唯一猎物标记，并按貊泽当前离场状态执行离场或失去1点体力。
func _apply_hunt_target(target_id: int) -> void:
	# 猎物目标；结算等待期间死亡或离场时不建立无效标记。
	var target: PlayerState = host.state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game or target_id == owner_player_id:
		return
	# 猎物公开说明；来源ID使多名同名武将的后续技能只响应自己创建的标记。
	var mark_data: Dictionary = {
		"icon":HUNT_MARK_ICON,
		"name":"猎物标记",
		"description":"由【幽锋】指定。标记来源的【掠袭】视其距离为1、令其不可响应来源使用的牌，并会在其受到伤害或死亡后触发后续效果。",
		"count":1,
		"source_player_id":owner_player_id,
		"order":0,
	}
	if not bool(host.call("set_player_mark", target_id, HUNT_MARK_ID, mark_data, true)):
		return
	announce_activation({"target_id":target_id})
	observe_identity_behavior([target_id], {"target_result":-0.8})
	# 貊泽当前状态；离场时仍可由离场技失去体力，未离场时通过统一接口中断自身当前回合。
	var owner: PlayerState = host.state.get_player(owner_player_id)
	if owner == null or not owner.alive:
		return
	if owner.out_of_game:
		get_owner_skill_player().loseHp(OUT_OF_GAME_HP_LOSS, get_owner_skill_player(), true)
	else:
		host.call("remove_player_from_game", owner_player_id, get_id())


## AI优先选择敌方低体力、低护盾且高威胁角色；若只能选择友方则自然选择损失较小者。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 当前请求上下文；非幽锋步骤不提供额外评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 当前动作负载；两段选择都使用标准choose_cards结构。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if str(context.get("kind", "")) == "youfeng_target":
		# 已选目标；锁定技必须恰好选择一名角色。
		var targets: Array = payload.get("selected_target_ids", []) as Array
		if targets.size() != 1:
			return -100.0
		# 目标公开状态；体力、护盾、手牌与威胁共同表达脆弱和后续伤害机会。
		var target_id: int = int(targets[0])
		# 目标快照；异常目标使用极低分避免AI提交。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
		if target.is_empty():
			return -100.0
		# 阵营态度；负值为敌方，取反后形成正向集火收益。
		var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
		# 目标有效生存值；护盾与体力都能延缓猎物受到致命伤害。
		var survival: int = maxi(int(target.get("hp", 0)) + int(target.get("shield", 0)), 0)
		# 脆弱度；以常见4点生存为基准，越低分数越高。
		var vulnerability: float = float(maxi(5 - survival, 0)) * AI_VULNERABILITY_WEIGHT
		return -attitude * AI_HOSTILE_ATTITUDE_WEIGHT + vulnerability + evaluator.get_threat(authoritative_snapshot, owner_player_id, target_id) * 0.35
	if str(context.get("kind", "")) == "youfeng_discard":
		# 已选实体；强制单选请求没有取消动作。
		var selected_cards: Array = payload.get("selected_card_uids", []) as Array
		if selected_cards.size() != 1:
			return -100.0
		# 被弃牌角色；对敌时优先高价值牌，对友时优先低价值牌降低副作用。
		var target_id: int = int(context.get("target_id", -1))
		# 当前候选价值；隐藏手牌只按统一未知资源估值，不读取真实牌面作弊。
		var card_value: float = evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)
		return card_value if evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) < 0.0 else -card_value
	return 0.0
