extends CardDefinition

## 【木牛流马】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。
##
## 主动动作是**两段式**：第一段把一张普通手牌扣置为“粮”并立即结束，第二段才用独立询问
## “是否将此装备移动给其他角色？”决定宝物与全部“粮”的归属。两段之间没有共享的同一次请求，
## 因此第一段的确定绝对不会顺带完成转移。

## “粮”的总容量上限；数值5来自需求“木牛流马最多存放5张粮”。
## 取值范围为正整数，且必须不小于 play_phase_material_count（否则装备永远无法发动）。
## 修改影响：调小会立即禁止继续存粮（达到上限时装备不再可点击、AI 不再枚举动作、规则校验拒绝超限提交）；
## 调大只会放宽容量，不影响已存“粮”的使用、打出与离装备区弃置语义。
const WOODEN_OX_STORAGE_CAPACITY: int = 5

## 第二段转移询问的稳定选择种类标识；请求创建与响应恢复共用同一键值，防止旧响应进入其他分支。
const TRANSFER_SELECTION_KIND: String = "wooden_ox_transfer"

## AI 对“把宝物与全部粮整体交给友方”的基础估值；只是持有者换人，团队资产不变，因此基础值较小。
const AI_TRANSFER_BASE_VALUE: float = 1.2

## AI 对每张随装备一起转移的“粮”的估值；粮越多，交给友方越能继续使用、交给敌方越危险。
const AI_TRANSFER_STORED_CARD_VALUE: float = 0.9


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "muniu",
		"original_name": "木牛流马",
		"custom_name": "货运星槎",
		"type": "equipment",
		"subtype": "treasure",
		"effect_id": "equip",
		"slot": "treasure",
		"attack_range": 0,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "出牌阶段限一次，可将一张手牌扣置为“粮”；可使用或打出“粮”，并可将此装备移动给其他角色。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":7.0, "value":7.0, "equip_value":7.0},
		"play_phase_interaction": "store_attachment",
		"play_phase_action_type": "store_wooden_ox",
		"play_phase_material_count": 1,
		"play_phase_action_card_source": "material",
		"shows_attachment_count": true,
	})


## 执行【木牛流马】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 木牛流马离开装备区时将其全部“粮”置入弃牌堆，并清空附属存储区。
func on_leave_equipment(match_host: Object, owner: PlayerState, trigger_loss_effects: bool) -> void:
	for stored_card: CardInstance in owner.wooden_ox_storage:
		match_host.discard_card_instance(stored_card)
	owner.wooden_ox_storage.clear()


## 新回合开始时重置持有者本回合的存粮发动次数。
func on_turn_started(match_host: Object, player_id: int) -> void:
	# 新回合玩家；无效角色不写入兼容状态。
	var player: PlayerState = match_host.state.get_player(player_id)
	if player != null:
		player.wooden_ox_used = false


## 木牛流马注册的出牌阶段主动存粮动作类型。
func get_play_phase_action_types() -> Array[String]:
	return ["store_wooden_ox"]


## 本阶段尚未发动、持有至少1张普通手牌且“粮”未达上限时允许点击木牛流马。
func is_play_phase_action_available(match_host: Object, owner_id: int, equipment_card: CardInstance) -> bool:
	# 装备持有者；已有“粮”不能再次作为存入材料。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	return owner != null and _can_store_more_cards(owner) and not owner.hand.is_empty()


## 为基础 AI 追加每张普通手牌的存粮动作；第一段不携带转移目标，转移改由第二段独立询问决定。
func append_play_phase_actions(match_host: Object, owner_id: int, equipment_card: CardInstance, result: Array[Dictionary]) -> void:
	# 装备持有者；本阶段已发动或“粮”已满时不产生任何动作。
	var owner: PlayerState = match_host.state.get_player(owner_id)
	if owner == null or not _can_store_more_cards(owner):
		return
	for hand_card: CardInstance in owner.hand:
		result.append({"action_type":"store_wooden_ox", "actor_id":owner_id, "card_uid":hand_card.uid, "target_ids":[], "card_definition_id":"muniu_store", "ai_card_definition_id":get_id()})


## 评估木牛流马存粮动作；手牌超上限时收益显著提高，并优先扣置保留价值最低的手牌。
func score_ai_play_phase_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 发动者 ID；用于读取手牌、体力与材料价值。
	var actor_id: int = int(action.get("actor_id", -1))
	# 发动者状态；不存在时不发动。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, actor_id)
	if actor.is_empty():
		return 0.0
	# 手牌溢出量；存粮不计入弃牌阶段手牌上限，因此每张溢出牌提供明显收益。
	var overflow_count: int = maxi(int(actor.get("hand_count", 0)) - maxi(int(actor.get("hp", 0)), 0), 0)
	# 被扣置材料价值；木牛“粮”仍可使用，只施加轻微可见性与宝物丢失风险成本。
	var material_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, actor_id, int(action.get("card_uid", -1)))
	return 0.8 + float(overflow_count) * 1.5 - material_value * 0.08


## 校验木牛存粮动作；材料必须为普通手牌，且第一段不接受任何转移目标。
func validate_play_phase_action(match_host: Object, action: PlayerAction) -> String:
	if action.action_type != "store_wooden_ox":
		return "木牛流马不支持该动作。"
	# 装备持有者；必须处于自己的出牌阶段且本阶段尚未发动。
	var owner: PlayerState = match_host.state.get_player(action.actor_id)
	if owner == null or match_host.state.current_phase != "play" or match_host.state.current_player_id != action.actor_id:
		return "当前不能发动木牛流马。"
	# 当前宝物实体；必须仍为木牛流马。
	var equipment_card: CardInstance = match_host.get_equipment_card(action.actor_id, "treasure")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return "玩家未装备木牛流马。"
	if owner.wooden_ox_used:
		return "本阶段已经发动过木牛流马。"
	if not _can_store_more_cards(owner):
		return "木牛流马的“粮”已达到%d张上限。" % WOODEN_OX_STORAGE_CAPACITY
	if owner.find_hand_card(action.card_uid) == null:
		return "木牛流马只能扣置一张普通手牌。"
	# 第二段才决定归属；第一段携带目标会绕过独立询问，因此在这里显式拒绝。
	if not action.target_ids.is_empty():
		return "转移目标请在存入后的询问中选择。"
	return ""


## 执行木牛存粮第一段；只把一张手牌扣置为“粮”，不移动宝物本身。
func execute_play_phase_action(match_host: Object, action: PlayerAction) -> bool:
	# 权威校验结果；失败时不移动任何实体牌。
	var validation_error: String = validate_play_phase_action(match_host, action)
	if not validation_error.is_empty():
		return false
	# 装备持有者；用于状态标记、附属牌集合与日志。
	var owner: PlayerState = match_host.state.get_player(action.actor_id)
	# 被扣置手牌；成功后进入 wooden_ox 附属区域。
	var stored_card: CardInstance = match_host.move_hand_card_to_equipment_attachment(action.actor_id, action.card_uid, "wooden_ox")
	if stored_card == null:
		return false
	owner.wooden_ox_used = true
	match_host.add_log("%s将一张手牌扣置于【木牛流马】下。" % owner.display_name)
	return true


## 第一段存入成功后声明第二段独立询问：是否把宝物与全部“粮”移动给其他角色。
func get_play_phase_follow_up_request(match_host: Object, action: PlayerAction) -> Dictionary:
	# 合法转移目标；与既有规则一致，只能是其他存活角色。
	var target_ids: Array[int] = _get_transfer_target_ids(match_host, action.actor_id)
	if target_ids.is_empty():
		return {}
	return {
		"prompt":"是否将此装备移动给其他角色？",
		"target_ids":target_ids,
		"min_targets":1,
		"max_targets":1,
		"allow_cancel":true,
		"context":{"kind":TRANSFER_SELECTION_KIND},
	}


## 恢复第二段转移选择；取消表示宝物与全部“粮”留在原装备区，本次发动到此结束。
func continue_equipment_selection(match_host: Object, context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != TRANSFER_SELECTION_KIND:
		return false
	if response == null or not response.confirmed or response.target_ids.size() != 1:
		return true
	# 选择者与原持有者；等待期间换将或阵亡时本次转移安全作废。
	var owner_id: int = int(context.get("choice_chooser_id", -1))
	var target_id: int = int(response.target_ids[0])
	var owner: PlayerState = match_host.state.get_player(owner_id)
	var target: PlayerState = match_host.state.get_player(target_id)
	if owner == null or target == null or not target.alive or target.player_id == owner_id:
		return true
	# 当前宝物实体；等待期间被移动或替换时不再转移。
	var equipment_card: CardInstance = match_host.get_equipment_card(owner_id, "treasure")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return true
	# 转移前附属牌快照；包含本次新存入的手牌与原有全部“粮”。
	var attachment_cards: Array[CardInstance] = owner.wooden_ox_storage.duplicate()
	if not match_host.transfer_equipment_with_attachments(owner_id, target.player_id, "treasure", attachment_cards, "wooden_ox"):
		return true
	owner.wooden_ox_storage.clear()
	match_host.add_log("%s将【木牛流马】及其下的“粮”转移给%s。" % [owner.display_name, target.display_name])
	return true


## 评估木牛流马第二段转移目标；友方为正、敌方为负，随行的“粮”越多价值越高。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只有木牛自己的转移询问参与本技能评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != TRANSFER_SELECTION_KIND:
		return 0.0
	# 动作负载；取消表示宝物留在原装备区，保持0分让通用取消价值决定。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；第二段必须且只能指定一名其他角色。
	var target_ids: Array = payload.get("selected_target_ids", []) as Array
	if target_ids.size() != 1:
		return -100.0
	# 目标稳定ID与选择者ID；两者都只用于读取公开快照。
	var target_id: int = int(target_ids[0])
	var chooser_id: int = int(context.get("choice_chooser_id", -1))
	# 选择者对目标的阵营态度；正值表示交给友方继续使用，负值表示把资产送给敌方。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, chooser_id, target_id)
	# 随装备一起转移的“粮”数量；装备与粮是一个整体，因此数量直接参与估值。
	var chooser_snapshot: Dictionary = evaluator.get_player(authoritative_snapshot, chooser_id)
	var storage_count: int = maxi(int(chooser_snapshot.get("wooden_ox_storage_count", 0)), 0)
	return attitude * (AI_TRANSFER_BASE_VALUE + float(storage_count) * AI_TRANSFER_STORED_CARD_VALUE)


## 返回木牛存粮预览；本段只选择一张手牌，转移目标由第一段结束后的独立询问决定。
func get_play_phase_action_preview(match_host: Object, owner_id: int, equipment_uid: int, payload: Dictionary, selected_target_ids: Array[int]) -> Dictionary:
	# 当前材料 UID；UI 使用数组统一承载不同装备的材料选择。
	var material_card_uids: Array = payload.get("material_card_uids", []) as Array
	# 预览动作；材料存在时把首张普通手牌作为动作 card_uid，且不携带任何转移目标。
	var action: PlayerAction = PlayerAction.new("store_wooden_ox", owner_id, int(material_card_uids[0]) if not material_card_uids.is_empty() else -1, [])
	# 当前校验结果；材料未选时保持明确提示。
	var validation_error: String = "请选择一张要存入木牛流马的手牌。" if material_card_uids.is_empty() else validate_play_phase_action(match_host, action)
	return {
		"card_found":not material_card_uids.is_empty(),
		"can_submit":validation_error.is_empty(),
		"validation_error":validation_error,
		"confirm_prompt":"确定后将这张手牌扣置为“粮”",
		"legal_target_ids":[],
		"normalized_target_ids":[],
		"target_mode":"none",
		"min_targets":0,
		"max_targets":0,
		"description":str(get_metadata().get("description", "")),
	}


## 判断持有者是否还能继续存粮；已发动过或“粮”达到上限时都不再提供入口。
func _can_store_more_cards(owner: PlayerState) -> bool:
	return owner != null and not owner.wooden_ox_used and owner.wooden_ox_storage.size() < WOODEN_OX_STORAGE_CAPACITY


## 返回可接收木牛与全部“粮”的其他存活角色；座次顺序即界面与AI的候选顺序。
func _get_transfer_target_ids(match_host: Object, owner_id: int) -> Array[int]:
	# 候选结果；不含持有者本人，也不含已阵亡或离场角色。
	var result: Array[int] = []
	for player: PlayerState in match_host.state.players:
		if player.alive and not player.out_of_game and player.player_id != owner_id:
			result.append(player.player_id)
	return result

