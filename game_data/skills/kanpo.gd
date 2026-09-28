extends SkillDefinition

## 【看破】技能源码。当持有者成为其他角色使用的锦囊牌的目标时，
## 可移除【解构】中与此牌相同的牌名，然后令此牌对持有者无效；每轮限一次。

## 发动确认选择类别；用于在恢复回调中区分本技能自己的请求。
const CHOICE_KIND: String = "kanpo_confirm"

## 每轮的发动上限；数值1来自技能原文“每轮限一次”。
const ROUND_LIMIT: int = 1

## 判定“其他角色使用”的比较基准；使用者等于持有者本人时不是原文所指的其他角色。
const SELF_ACTOR_ID: int = -1

## 锦囊牌大类；只有锦囊才可能被【看破】取消。
const TRICK_TYPE: String = "trick"

## 禁止被【看破】响应的牌名；【无懈可击】本身是响应类锦囊，不会成为普通用牌的目标。
const WUXIE_DEFINITION_ID: String = "wuxie"

## 被【看破】判定为对持有者不利的锦囊牌名；AI据此倾向发动。
const NEGATIVE_TRICK_IDS: Array[String] = ["nanman", "wanjian", "juedou", "guohe", "shunshou", "huogong", "tiesuo", "shuiyanqijun", "lebu", "bingliang", "shandian"]

## 被【看破】判定为对持有者有利的锦囊牌名；AI据此避免浪费每轮一次的额度。
const POSITIVE_TRICK_IDS: Array[String] = ["taoyuan", "wugu", "wuzhong"]

## AI对不利锦囊的发动评分；必须严格为正，保证【看破】不会因为保守而永不发动。
const AI_NEGATIVE_TRICK_SCORE: float = 2.0

## AI对有利锦囊的发动评分；取负值以阻止AI抵消队友的增益锦囊。
const AI_POSITIVE_TRICK_SCORE: float = -3.0

## 最近一次发动所在的轮次号；-1表示本局尚未发动，与当前轮次比较实现“每轮限一次”。
var _used_round_number: int = -1


## 写入触发技静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"kanpo",
		"name":"看破",
		"trigger":"passive/useCardToTargeted",
		"ui_enabled":false,
		"description":"当你成为其他角色使用的锦囊牌的目标时，你可移除“解构”中与此牌相同的牌名，然后令此牌对你无效。每轮限一次。",
	})


## 订阅“成为牌的目标”时机；role 为target时只有持有者本人被指定才会回调。
func install() -> void:
	subscribe_timing("useCardToTargeted", _on_become_card_target, "target")


## 持有者成为其他角色使用的锦囊目标时询问是否发动【看破】。
func _on_become_card_target(event: RuleEvent) -> void:
	if event == null:
		return
	# 技能持有者；死亡或离场的持有者不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 当前目标ID；逐目标时机优先读取data中的稳定字段，其次回退到事件目标。
	var target_id: int = int(event.data.get("target_id", event.target_id))
	if target_id != owner_player_id:
		return
	# 使用者必须是其他角色；自己使用的锦囊不能对自己发动【看破】。
	var actor_id: int = int(event.source_id)
	if actor_id == owner_player_id or actor_id <= SELF_ACTOR_ID:
		return
	# 当前使用牌稳定UID；只有仍处于使用生命周期中的牌才能被标记为对本目标无效。
	var card_uid: int = int(event.data.get("card_uid", -1))
	if card_uid < 0:
		return
	# 当前使用牌定义ID；由控制器在时机数据中以card_id下发。
	var trick_id: String = str(event.data.get("card_id", ""))
	if not _is_negatable_trick(trick_id):
		return
	# 记录条件；只有【解构】记录过的同名锦囊才可以被移除，也才允许发动。
	if not owner.recorded_card_names.has(trick_id):
		return
	# 每轮额度；同一轮内重复成为目标只询问一次。
	if _used_round_number == host.state.round_number:
		return
	request_card_selection("看破", "是否发动【看破】令此牌对你无效？", [], 0, 0, true, {"kind":CHOICE_KIND, "card_uid":card_uid, "trick_id":trick_id, "ai_allow_confirm":true})


## 恢复【看破】发动确认；确认后先移除记录，再令此牌对持有者无效。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != CHOICE_KIND:
		return false
	if not response.confirmed:
		return true
	# 技能持有者；异步确认期间可能已经死亡或离场。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return true
	var trick_id: String = str(context.get("trick_id", ""))
	var card_uid: int = int(context.get("card_uid", -1))
	if trick_id.is_empty() or card_uid < 0:
		return true
	# 条件复核；确认期间记录可能已被其他效果移除，此时不再消耗额度。
	if not owner.recorded_card_names.has(trick_id):
		return true
	# 原文顺序：先移除【解构】中与此牌相同的牌名，再令此牌对持有者无效。
	host.call("remove_recorded_card_name", owner_player_id, trick_id)
	if not bool(host.call("exclude_card_target", card_uid, owner_player_id, get_id())):
		return true
	_used_round_number = host.state.round_number
	announce_activation({"card_uid":card_uid, "trick_id":trick_id, "target_id":owner_player_id})
	return true


## 判断一个牌面定义是否属于【看破】可取消的锦囊；排除无懈可击等响应类锦囊。
func _is_negatable_trick(trick_id: String) -> bool:
	if trick_id.is_empty() or trick_id == WUXIE_DEFINITION_ID:
		return false
	var definition: Dictionary = GameDatabase.get_card(trick_id)
	if definition.is_empty():
		return false
	return str(definition.get("type", "")) == TRICK_TYPE


## 评估【看破】的发动选择：抵消敌方不利锦囊为正收益，抵消有利锦囊为负收益。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	var trick_id: String = str(context.get("trick_id", ""))
	if POSITIVE_TRICK_IDS.has(trick_id):
		return AI_POSITIVE_TRICK_SCORE
	if NEGATIVE_TRICK_IDS.has(trick_id):
		return AI_NEGATIVE_TRICK_SCORE
	# 其余锦囊默认按不利处理：原文允许对任意同名锦囊发动，AI保守地视为值得抵消。
	return AI_NEGATIVE_TRICK_SCORE
