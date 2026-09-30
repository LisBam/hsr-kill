extends SkillDefinition

## 【飞焰】技能源码。准备阶段可虚拟使用【火攻】，命中后摸牌并把本回合主要阶段转换为出牌阶段。

## 飞焰命中后摸牌数；固定为3，修改时必须同步技能原文与玩法文档。
const DRAW_COUNT: int = 3

## AI判定为手牌较少并优先对自己使用火攻的手牌上限。
const AI_LOW_HAND_THRESHOLD: int = 2

## AI低手牌时选择自己的固定优先分；保证能展示并弃置同一张牌来稳定命中。
const AI_SELF_TARGET_SCORE: float = 18.0

## AI发动飞焰的基础收益；体现摸3张牌和四段出牌阶段带来的高行动价值。
const AI_ACTIVATION_VALUE: float = 12.0

## 本回合被【飞焰】转换为普通出牌阶段的主要阶段数量；判定、摸牌、正常出牌、弃牌四个阶段各一次，
## 修改时必须同步技能效果描述与玩法文档中的阶段转换说明。
const MAIN_PHASE_CONVERT_COUNT: int = 4

## AI：单个普通出牌阶段的行动价值；与项目其他“额外一个出牌阶段”类效果的估值同档。
const AI_PLAY_PHASE_VALUE: float = 1.2

## virtual_storage 中“命中联动奖励”的稳定键名；【火攻】按同一键名读取本次命中能换回的联动收益，
## 两处必须保持一致，否则视为使用【火攻】的技能无法参与自身弃牌伤害的收益判断。
const VIRTUAL_STORAGE_HIT_REWARD_KEY: String = "hit_reward_value"

## AI：飞焰命中一次的真实联动奖励估值 = 摸3张牌 + 四个普通出牌阶段的行动价值。
## 该值经 virtual_storage 随虚拟【火攻】传递，使【火攻】在“使用者对自己使用”时按联动收益评分，
## 而不是只看到通用层的自伤惩罚；修改摸牌数或阶段转换数量时必须同步本式。
const AI_HIT_REWARD_VALUE: float = DRAW_COUNT * NonameAIEvaluator.CARD_RESOURCE_VALUE + MAIN_PHASE_CONVERT_COUNT * AI_PLAY_PHASE_VALUE

## 准备阶段虚拟使用火攻的规则覆写；只解除出牌阶段限制，不跳过目标、距离或次数校验。
const VIRTUAL_RULE_OVERRIDES: Dictionary = {"ignore_phase_limit":true}

## 当前是否正在结算由飞焰使用的虚拟火攻；只在该牌完整生命周期内为true。
var _resolving_feiyan_huogong: bool = false

## 当前飞焰是否已经因造成伤害结算过命中奖励；每次发动至多触发一次。
var _reward_resolved: bool = false


## 写入技能静态信息；技能描述严格保持需求钦定原文。
func _init() -> void:
	super({
		"id":"feiyan",
		"name":"飞焰",
		"trigger":"phaseZhunbeiBegin",
		"ui_enabled":false,
		"description":"准备阶段，你可以视为使用一张【火攻】，若此牌造成伤害，你摸三张牌，且本回合内你的所有主要阶段都变为出牌阶段。",
	})


## 订阅准备阶段、伤害后与整牌使用结束时机，限定奖励只属于本次飞焰火攻。
func install() -> void:
	subscribe_timing("phaseZhunbeiBegin", _on_preparation_phase_begin, "player")
	subscribe_timing("damageAfter", _on_damage_after, "source")
	subscribe_timing("useCardAfter", _on_card_use_after, "source")


## 准备阶段枚举虚拟火攻合法目标；没有手牌目标时不创建空询问。
func _on_preparation_phase_begin(_event: RuleEvent) -> void:
	# 当前虚拟火攻合法目标；卡牌规则负责目标存活、手牌与免疫校验。
	var target_ids: Array[int] = []
	for target_variant: Variant in host.card_rules.list_legal_virtual_targets(owner_player_id, "huogong", VIRTUAL_RULE_OVERRIDES):
		target_ids.append(int(target_variant))
	if target_ids.is_empty():
		return
	request_target_selection("【飞焰】请选择【火攻】的目标", target_ids, 0, 1, true, {"kind":"feiyan_target"})


## 恢复飞焰目标选择并通过标准无实体虚拟牌入口使用火攻。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "feiyan_target" or response == null:
		return false
	if not response.confirmed or response.target_ids.size() != 1:
		return true
	# 最终火攻目标ID；执行前由统一虚拟牌入口再次完成完整合法性校验。
	var target_id: int = response.target_ids[0]
	# 强类型火攻目标数组；通过Object.call调用参数为Array[int]的端口时，禁止直接传入会推断为普通Array的字面量。
	var target_ids: Array[int] = [target_id]
	_resolving_feiyan_huogong = true
	_reward_resolved = false
	# 本次虚拟火攻的扩展存储；携带来源技能与“命中即可换回的联动奖励”，随逻辑牌生命周期一起传递。
	# 【火攻】在结算与AI评分时读取该键，从而在使用者对自己使用火攻时按真实联动收益决策，
	# 而不是只看到统一评分给出的自伤惩罚；实体火攻没有扩展存储，行为完全不受影响。
	var virtual_storage: Dictionary = {"source_skill_id":get_id(), VIRTUAL_STORAGE_HIT_REWARD_KEY:AI_HIT_REWARD_VALUE}
	if not bool(host.call("execute_cardless_virtual_card_use", owner_player_id, "huogong", target_ids, "虎克发动【飞焰】，视为使用【火攻】。", VIRTUAL_RULE_OVERRIDES, virtual_storage)):
		_resolving_feiyan_huogong = false
		return true
	announce_activation({"target_id":target_id})
	return true


## 飞焰火攻首次造成正数伤害后立即结算摸牌与本回合阶段替换。
func _on_damage_after(event: RuleEvent) -> void:
	if not _resolving_feiyan_huogong or _reward_resolved or event.source_id != owner_player_id or str(event.data.get("card_id", "")) != "huogong" or int(event.data.get("amount", 0)) <= 0:
		return
	_reward_resolved = true
	host.call("draw", owner_player_id, DRAW_COUNT)
	# 主要阶段转换；四个阶段直接按普通出牌阶段执行，不派发跳过时机，也不进入额外出牌阶段队列。
	host.call("convert_current_turn_main_phases_to_play", owner_player_id, "feiyan")


## 本次虚拟火攻完整结束后清理运行时识别标记，避免后续普通火攻误触发飞焰奖励。
func _on_card_use_after(event: RuleEvent) -> void:
	if _resolving_feiyan_huogong and event.source_id == owner_player_id and str(event.data.get("card_id", "")) == "huogong":
		_resolving_feiyan_huogong = false


## AI评估飞焰目标；低手牌时优先自己，其他情况优先对敌方制造火焰伤害。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 当前请求上下文；非飞焰目标步骤不提供技能评分。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "feiyan_target":
		return 0.0
	# 当前动作负载；取消不产生任何收益。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标；飞焰每次只能指定一名火攻目标。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	if selected_targets.size() != 1:
		return -INF
	# 虎克权威快照；手牌较少且仍有牌时自目标可以稳定完成展示与同花色弃置。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	# 最终目标ID；用于比较自目标与敌对目标收益。
	var target_id: int = int(selected_targets[0])
	# 当前手牌数；至少1张才能通过火攻目标规则并完成自目标命中策略。
	var hand_count: int = int(owner.get("hand_count", 0))
	if target_id == owner_player_id:
		return AI_SELF_TARGET_SCORE if hand_count > 0 and hand_count <= AI_LOW_HAND_THRESHOLD else -4.0
	# 对其他角色的评分按态度反向转换；敌意越强越值得作为火攻目标。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	return AI_ACTIVATION_VALUE - attitude
