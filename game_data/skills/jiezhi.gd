extends SkillDefinition

## 【揭质】技能源码。每局游戏限两次，当持有者发动【逐虚】后，可对相同目标执行一次相同的效果。
## 本技能不是限定技：额度由自身私有计数承载，与“每局一次”的限定技集合相互独立。

## 【逐虚】技能稳定ID；本技能只响应它的结算记录。
const SOURCE_SKILL_ID: String = "zhuxv"

## 每局游戏发动上限；数值2来自技能原文“每局游戏限两次”。
const PER_GAME_LIMIT: int = 2

## 【逐虚】写入共享结算记录的键；取值必须与逐虚的常量严格一致。
const LAST_RESOLVED_KEY: String = "zhuxv_last_resolved"

## 逐虚的随机弃牌节序号；揭质按同一编号复算效果。
const SECTION_DISCARD: int = 0

## 逐虚的随机伤害节序号；对敌人释放本节的重复收益最高。
const SECTION_DAMAGE: int = 1

## 重复①时写入随机历史的类别；与逐虚的两层随机保持可对比的命名。
const HISTORY_DISCARD_CARD: String = "jiezhi_repeat_discard_card"

## 重复效果造成的伤害值；数值1来自逐虚原文“造成1点伤害”。
const DAMAGE_AMOUNT: int = 1

## 可选装备栏稳定顺序；随机取牌需要遍历全部装备槽。
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "armor", "offensive_mount", "defensive_mount", "treasure"]

## 确认询问业务类型；确认后执行重复效果，取消不消耗次数。
const CONFIRM_KIND: String = "jiezhi_confirm"

## 询问上下文中的节编号字段名；AI估值从请求上下文读取而无法访问武将私有数据。
const CONTEXT_SECTION_INDEX: String = "section_index"

## 询问上下文中的目标字段名。
const CONTEXT_TARGET_ID: String = "target_id"

## 本局已发动次数；进入存档由通用技能状态采集自动保存，重置技能会随实例重建归零。
var _used_count: int = 0


## 写入被动技能静态信息；技能正文逐字保持设计原文，ui_enabled 为 false 表示不占用主动按钮。
func _init() -> void:
	super({
		"id":"jiezhi",
		"name":"揭质",
		"trigger":"passive/useSkillAfter",
		"ui_enabled":false,
		"description":"每局游戏限两次，当你发动“逐虚”后，你可对相同目标执行一次相同的效果。",
	})


## 订阅技能使用后时机；【逐虚】的结算记录在该时机之前已经写入持有者的武将私有数据。
func install() -> void:
	subscribe_timing("useSkillAfter", _on_skill_after, "player")


## 当持有者发动【逐虚】后创建确认询问；目标已不合法或额度用尽时不开放入口。
func _on_skill_after(event: RuleEvent) -> void:
	if str(event.data.get("skill_id", "")) != SOURCE_SKILL_ID:
		return
	# 结算记录；只有字段完整且仍属于本回合与当前武将代次时才允许重复。
	var resolved: Dictionary = _get_last_resolved()
	if resolved.is_empty() or not can_repeat(resolved):
		return
	# 空候选确认询问：本技能的效果完全由结算记录决定，玩家只需回答“是否发动”。
	# 节编号与目标一并写入上下文，使AI估值不必访问仅本人可见的武将私有数据。
	request_card_selection("揭质", "是否发动【揭质】对相同目标重复一次？", [], 0, 0, true, {"kind":CONFIRM_KIND, CONTEXT_SECTION_INDEX:int(resolved.get("section_index", SECTION_DISCARD)), CONTEXT_TARGET_ID:int(resolved.get("target_id", -1)), "ai_allow_confirm":true})


## 复核重复发动条件：额度、回合归属、武将代次与目标合法性全部成立才开放入口。
func can_repeat(resolved: Dictionary) -> bool:
	# 每局额度；用尽后不再出现入口。
	if _used_count >= PER_GAME_LIMIT:
		return false
	# 结算回合归属；跨回合的旧记录不得被延迟询问重复命中。
	if int(resolved.get("resolved_turn_number", -1)) != host.state.turn_number:
		return false
	# 技能持有者；死亡或离场后不再响应。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	# 武将代次；换将后旧记录不得命中新武将的技能实例。
	if int(resolved.get("character_generation", -1)) != owner.character_generation:
		return false
	# 目标存在性；死亡或离场的原目标不开放入口。
	var target_id: int = int(resolved.get("target_id", -1))
	var target: PlayerState = host.state.get_player(target_id)
	if target == null or not target.alive or target.out_of_game:
		return false
	# ① 情形还要求目标仍有可弃置的牌：无牌可弃时不开放入口，既不消耗次数也不产生空效果。
	if int(resolved.get("section_index", SECTION_DISCARD)) == SECTION_DISCARD:
		if _get_zone_card_uids(target_id).is_empty():
			return false
	return true


## 恢复确认询问；确认时对同一目标重复一次同一节效果，取消不消耗次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != CONFIRM_KIND:
		return false
	if not response.confirmed:
		return true
	# 询问期间目标可能已经失效；复核不通过时不消耗次数也不产生效果。
	var resolved: Dictionary = _get_last_resolved()
	if not can_repeat(resolved):
		return true
	_used_count += 1
	# 重复效果；按记录的节编号复算完全相同的效果，目标固定为原目标。
	if int(resolved.get("section_index", SECTION_DISCARD)) == SECTION_DISCARD:
		_repeat_random_discard(int(resolved.get("target_id", -1)))
	else:
		_repeat_random_damage(int(resolved.get("target_id", -1)))
	return true


## 读取【逐虚】最近一次结算记录；记录缺失时返回空字典。
func _get_last_resolved() -> Dictionary:
	# 技能持有者；不存在时没有可读记录。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return {}
	return owner.character_form_state.get(LAST_RESOLVED_KEY, {}) as Dictionary


## 重复①：对已锁定目标再次随机弃置其区域内一张牌；随机索引同样来自权威随机流。
func _repeat_random_discard(target_id: int) -> void:
	var card_uids: Array[int] = _get_zone_card_uids(target_id)
	if card_uids.is_empty():
		return
	var card_index: int = int(host.call("pick_random_candidate_index", card_uids.size(), HISTORY_DISCARD_CARD, {"skill_id":get_id(), "target_id":target_id}))
	if card_index < 0:
		return
	# 最终被弃置的实体牌；权威入口按牌所在区域选择正确路径并派发弃置时机。
	var card_uid: int = card_uids[card_index]
	announce_activation({"effect":"repeat_discard", "target_id":target_id, "card_uid":card_uid, "used_count":_used_count})
	host.call("discard_selected_player_cards", target_id, [card_uid] as Array[int], owner_player_id)


## 重复②：对已锁定目标再次造成1点伤害；伤害来源统一记为技能持有者以保留击杀归属。
func _repeat_random_damage(target_id: int) -> void:
	announce_activation({"effect":"repeat_damage", "target_id":target_id, "amount":DAMAGE_AMOUNT, "used_count":_used_count})
	host.call("damage", owner_player_id, target_id, DAMAGE_AMOUNT)


## 收集指定角色当前可被随机弃置的区域牌UID；覆盖手牌、装备区与判定区。
func _get_zone_card_uids(target_id: int) -> Array[int]:
	var player: PlayerState = host.state.get_player(target_id)
	if player == null:
		return []
	# 结果按“手牌→装备→判定”的固定顺序构建，与逐虚保持同一口径以便复现。
	var result: Array[int] = []
	for hand_card: CardInstance in player.hand:
		result.append(hand_card.uid)
	for slot: String in EQUIPMENT_SLOTS:
		if player.equipment.has(slot):
			result.append((player.equipment[slot] as CardInstance).uid)
	for judgment_card: CardInstance in player.judgment_area:
		result.append(judgment_card.uid)
	return result


## AI评估揭质选择：确认发动时按“对同一目标再执行一次”的收益评分，留到对敌人释放②时收益最高。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作负载；取消保持0分，不进入发动分支。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 请求上下文；节编号与目标由权威询问携带，AI无需访问武将私有数据。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var target_id: int = int(context.get(CONTEXT_TARGET_ID, -1))
	if evaluator.get_player(authoritative_snapshot, target_id).is_empty():
		return 0.0
	# 重复②的收益；对敌方为削弱、对友方为损失，方向由估值器按态度给出，基础加值保证合法动作得分为正。
	if int(context.get(CONTEXT_SECTION_INDEX, SECTION_DISCARD)) == SECTION_DAMAGE:
		return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, 0, -DAMAGE_AMOUNT) + 1.0
	# 重复①的收益；额外弃置一张牌同样按“目标失去一张牌”换算。
	return evaluator.score_resource_change(authoritative_snapshot, owner_player_id, target_id, -1, 0) + 1.0
