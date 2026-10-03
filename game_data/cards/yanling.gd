extends CardDefinition

## 【言灵】卡牌源码。**专属锦囊牌**：正常情况不加入游戏中，只有被其他角色的技能或其他情况触发时
## 才会按要求加入游戏（例如被技能在“游戏开始时”放入摸牌堆），因此它不出现在 data/decks.json 的任何牌堆中。
##
## 牌面：梅花K（suit=club / rank=13）。普通牌的牌面由牌堆配置的紧凑条目给出，
## 专属牌没有牌堆条目，所以花色点数由本文件自己声明，并由
## MatchController.create_and_insert_card_into_draw_pile() 在调用方未显式给出牌面时读取。
##
## 效果：延时锦囊，置入一名其他角色的判定区；其判定结果为梅花且场上有「主演」时，本回合由「主演」操控。

## 判定生效所需的花色；与原文「判定结果为梅花时」逐字对应，不得改成其他花色。
const REQUIRED_JUDGMENT_SUIT: String = "club"

## 本牌声明的花色与点数；梅花 K。与卡牌静态元数据的 suit/rank 使用同一对常量，避免两处各写一遍。
const DECLARED_SUIT: String = "club"

## 本牌声明的点数；13 对应 K，与实体牌点数取值域（1=A ~ 13=K）一致。
const DECLARED_RANK: int = 13

## 判定 AI 上下文中「目标保住本回合操作权」的安全结果值；非梅花时目标不受影响，属于对目标有利的结果。
## 数值口径与【乐不思蜀】【兵粮寸断】的 AI_SAFE_RESULT_VALUE 同档，供通用改判定 AI 直接比较。
const AI_TARGET_SAFE_RESULT_VALUE: float = 4.0

## 主演为队友时的基础出牌评分；高于同类延时锦囊的通用价值，使 AI 在条件满足时优先考虑本牌。
const AI_ALLY_STARRING_VALUE: float = 6.0

## 不满足使用条件时的拒绝评分；低于全部正常出牌评分，等效于「不使用此牌」。
## 覆盖两种情况：场上没有主演，以及主演是敌人（含态度不明）。
const AI_REFUSE_SCORE: float = -100.0

## 目标不是「距离主演回合最近的敌人」时的评分；同样低于全部正常出牌评分，保证 AI 只对那名敌人使用。
const AI_NON_NEAREST_TARGET_SCORE: float = -100.0


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
## exclusive=true 是本牌区别于普通延时锦囊的唯一元数据；rules 语义仍按 type/subtype 走同一条结算链路。
func _init() -> void:
	super({
		"id": "yanling",
		"original_name": "言灵",
		"custom_name": "言灵",
		"type": "trick",
		"subtype": "delayed",
		"effect_id": "turn_control",
		"nature": "normal",
		"target_mode": "single_other",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "wuxie",
		"recast": false,
		"delayed": true,
		"description": "判定结果为梅花时，若场上有“主演”，本回合由“主演”操控。",
		"resolution_mode": "whole",
		"final_zone": "judgment",
		"provided_response_pattern": "",
		"exclusive": true,
		"suit": DECLARED_SUIT,
		"rank": DECLARED_RANK,
		"ai": {"order":1.0, "value":0.0, "target_result":-1.0},
		"ai_target_attitude": "hostile",
	})


## 执行【言灵】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
## 本牌不改变目标的手牌或体力，而是把牌本身置入目标判定区，等待其判定阶段结算。
func resolve(resolver: Object, card: CardInstance, _actor_id: int, target_ids: Array[int]) -> String:
	if target_ids.is_empty():
		return "discard"
	resolver.host.place_delayed_trick(target_ids[0], card)
	return "judgment"


## 结算【言灵】判定；未被无懈抵消且结果为梅花、且场上存在「主演」时，把本回合的输入权交给「主演」。
func resolve_delayed_judgment(match_host: Object, player_id: int, card: CardInstance, negated: bool) -> void:
	if negated:
		match_host.discard_delayed_card(card)
		return
	# 判定恢复上下文；延时牌 UID 用于等待期间确认原牌仍位于处理区。
	var continuation: Dictionary = {"receiver_type":"card", "card_definition_id":get_id(), "context":{"kind":"yanling_delayed_judgment", "player_id":player_id, "delayed_card_uid":card.uid}}
	# 非梅花时目标保住本回合操作权，属于对目标有利的结果；梅花为不利结果。
	# 判定 AI 上下文与本牌判定结论使用同一份花色常量，改花色时两处必然同步。
	var judgment_ai_context: Dictionary = {"favorable_condition":{"not":{"suits":[REQUIRED_JUDGMENT_SUIT]}}, "unfavorable_condition":{"suits":[REQUIRED_JUDGMENT_SUIT]}, "favorable_result_player_values":{str(player_id):AI_TARGET_SAFE_RESULT_VALUE}}
	# 【言灵】判定牌；判定前存在选择时由 continue_judgment 恢复，不提前移动原延时牌。
	var judgment_card: CardInstance = match_host.request_judgment(player_id, "【言灵】", continuation, judgment_ai_context)
	if match_host.has_pending_judgment_request():
		return
	_apply_delayed_result(match_host, player_id, card, judgment_card)


## 恢复【言灵】异步判定，并在原延时牌仍有效时应用操控结果。
func continue_judgment(match_host: Object, context: Dictionary, judgment_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "yanling_delayed_judgment":
		return false
	# 原延时牌；等待期间已经离开处理区时旧判定结果不再建立任何操控登记。
	var delayed_card: CardInstance = _find_processing_card(match_host, int(context.get("delayed_card_uid", -1)))
	if delayed_card != null:
		_apply_delayed_result(match_host, int(context.get("player_id", -1)), delayed_card, judgment_card)
	return true


## 应用【言灵】最终判定：梅花且场上有「主演」时登记「本回合由主演操控」，之后原延时牌进入弃牌堆。
## 操控登记只由权威端口建立，本牌不解释操控的具体表现，也不改变回合归属与阶段推进。
func _apply_delayed_result(match_host: Object, player_id: int, card: CardInstance, judgment_card: CardInstance) -> void:
	if judgment_card != null and judgment_card.suit == REQUIRED_JUDGMENT_SUIT:
		# 当前「主演」ID；场上没有主演时为 -1，此时判定虽然为梅花但不建立任何操控。
		var starring_player_id: int = int(match_host.get_starring_role_player_id())
		if starring_player_id >= 0:
			# 操控登记；主演正好是本回合角色时端口按“禁止自环”拒绝，等价于无需操控，属于预期结果。
			# 登记失败（角色已离场、主演正被他人操控等）不产生任何副作用，本牌仍正常进入弃牌堆。
			match_host.begin_turn_input_delegation(player_id, starring_player_id)
	match_host.discard_delayed_card(card)


## 依据配套 AI 提示修正【言灵】的主动使用评分。
## 提示原文口径：主演是队友才对敌人使用，且只对「距离其回合最近的敌人」使用；主演是敌人则完全不使用。
## 因此本函数承担两个职责：① 条件不满足时把评分压到拒绝阈值以下；② 条件满足但目标不是最近的那名敌人时同样拒绝。
func modify_ai_action_score(authoritative_snapshot: Dictionary, action: Dictionary, current_score: float, evaluator: Object) -> float:
	# 当前行动者；缺失时不改变通用评分。
	var actor_id: int = int(action.get("actor_id", -1))
	if actor_id < 0:
		return current_score
	# 当前「主演」ID；主演是公开状态，AI 只读取公开快照即可得到，不依赖任何隐藏信息。
	var starring_player_id: int = _resolve_starring_player_id(authoritative_snapshot)
	if starring_player_id < 0:
		return AI_REFUSE_SCORE
	# 主演阵营；态度不大于0表示主演是敌人或身份不明，按提示不使用此牌。
	if evaluator.get_attitude(authoritative_snapshot, actor_id, starring_player_id) <= 0.0:
		return AI_REFUSE_SCORE
	# 动作目标列表；本牌固定单目标，没有目标时不能声称可以打出。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.is_empty():
		return AI_REFUSE_SCORE
	# 应被指定的敌人；从主演座位向后找到的第一名敌人，即“距离主演回合最近”的敌人。
	var nearest_enemy_id: int = _resolve_nearest_enemy_after_player(authoritative_snapshot, actor_id, starring_player_id, evaluator)
	if nearest_enemy_id < 0 or int(target_ids[0]) != nearest_enemy_id:
		return AI_NON_NEAREST_TARGET_SCORE
	return AI_ALLY_STARRING_VALUE


## 从公开快照解析当前「主演」ID；没有任何角色携带主演条目时返回 -1。
## 主演的公开载体是武将牌左上角条目，条目 ID 取自权威服务常量，内容层不另写一份字面量。
func _resolve_starring_player_id(authoritative_snapshot: Dictionary) -> int:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色公开快照；旧快照缺少条目字段时按非主演处理。
		var player: Dictionary = player_variant as Dictionary
		var entries: Dictionary = player.get("character_corner_text_entries", {}) as Dictionary
		if entries.has(StarringRoleService.CORNER_ENTRY_ID):
			return int(player.get("player_id", -1))
	return -1


## 从 start_player_id 的座位起沿行动顺序向后找到第一名敌对角色；找不到时返回 -1。
## 「距离其回合最近」按座位顺序判定的理由：牌是在目标**下一次**判定阶段结算的，
## 从主演座位向后数第一名敌人，就是主演本次操控能最快兑现收益的那个回合。
## 数到一圈为止，因此全部其他角色都是友方时返回 -1，调用方据此拒绝出牌。
func _resolve_nearest_enemy_after_player(authoritative_snapshot: Dictionary, actor_id: int, start_player_id: int, evaluator: Object) -> int:
	# 全部角色公开快照；顺序即权威座次顺序，AI 与界面据此看到同一份行动顺序。
	var players: Array = authoritative_snapshot.get("players", []) as Array
	if players.is_empty():
		return -1
	# 起始座位下标；未找到时从0开始，仍然只数一圈。
	var start_index: int = 0
	for player_index: int in range(players.size()):
		if int((players[player_index] as Dictionary).get("player_id", -1)) == start_player_id:
			start_index = player_index
			break
	for offset: int in range(1, players.size()):
		# 当前候选角色；跳过使用者自己，其他角色按态度决定是否为敌人。
		var candidate: Dictionary = players[(start_index + offset) % players.size()] as Dictionary
		var candidate_id: int = int(candidate.get("player_id", -1))
		if candidate_id < 0 or candidate_id == actor_id:
			continue
		if not bool(candidate.get("alive", false)) or bool(candidate.get("out_of_game", false)):
			continue
		if evaluator.get_attitude(authoritative_snapshot, actor_id, candidate_id) < 0.0:
			return candidate_id
	return -1


## 按 UID 查找仍在公共处理区的原延时牌；异步恢复不依赖同名牌或数组位置。
func _find_processing_card(match_host: Object, card_uid: int) -> CardInstance:
	for processing_card: CardInstance in match_host.state.processing_area:
		if processing_card.uid == card_uid:
			return processing_card
	return null
