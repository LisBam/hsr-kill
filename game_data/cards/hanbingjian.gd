extends CardDefinition

## 【寒冰剑】卡牌源码。静态信息与效果入口均在本文件维护，目录扫描会自动完成注册。

## 选牌请求的稳定种类标识；效果入口、异步恢复与AI专属评分共用同一字符串，避免三处各写一份字面量。
const CHOICE_KIND: String = "hanbing_cards"

## 本次【杀】原将造成的伤害点数默认值；请求上下文缺失伤害字段时按普通【杀】的1点回退。
const AI_DEFAULT_DAMAGE_AMOUNT: int = 1

## 1点体力的统一资源价值；直接复用全局评估器常量（1点体力=2张牌），不在本卡牌内另设换算比例。
const AI_HP_RESOURCE_VALUE: float = NonameAIEvaluator.HP_RESOURCE_VALUE


## 写入卡牌名称、类别、目标规则、数值、说明与区域语义。
func _init() -> void:
	super({
		"id": "hanbing",
		"original_name": "寒冰剑",
		"custom_name": "支离",
		"type": "equipment",
		"subtype": "weapon",
		"effect_id": "equip",
		"slot": "weapon",
		"attack_range": 2,
		"target_mode": "self",
		"min_targets": 1,
		"max_targets": 1,
		"distance_limit": "none",
		"play_limit": 0,
		"response_pattern": "",
		"recast": false,
		"delayed": false,
		"description": "【杀】将造成伤害时，若目标手牌区或装备区有牌，可防止伤害并依次弃置其至多两张牌。",
		"resolution_mode": "whole",
		"final_zone": "equipment",
		"provided_response_pattern": "",
		"ai": {"order":3.0, "value":2.0, "equip_value":2.0},
		"ai_use_value": 4.0,
	})


## 执行【寒冰剑】效果；状态修改统一通过 CardEffectResolver 暴露的规则端口完成。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	resolver.host.equip_from_processing(actor_id, card)
	return "equipment"


## 【杀】即将造成伤害时，可防止伤害并弃置目标手牌区或装备区至多2张牌。
func on_slash_before_damage(slash_effect: Object, context: Dictionary) -> bool:
	# 攻击者 ID；负责选择目标区域牌。
	var actor_id: int = int(context.get("actor_id", -1))
	# 目标 ID；其手牌区和装备区必须至少有1张牌。
	var target_id: int = int(context.get("target_id", -1))
	if slash_effect.host.get_hand_equipment_card_count(target_id) < 1:
		return false
	# 当前武器实体；UID 用于等待期间验证仍装备同一张寒冰剑。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.definition_id != get_id():
		return false
	# 目标区域候选；只包含普通手牌与装备，不包含判定区。
	var candidates: Array[Dictionary] = slash_effect.host.get_hand_equipment_candidates(actor_id, target_id)
	# 选牌恢复上下文；保存原【杀】全部伤害参数与武器实体 UID。
	var choice_context: Dictionary = context.duplicate(true)
	choice_context["kind"] = CHOICE_KIND
	choice_context["equipment_definition_id"] = get_id()
	choice_context["equipment_uid"] = equipment_card.uid
	# 本次【杀】原将造成的伤害点数；AI 用它计算“放弃伤害”的机会成本，上下文字段缺失时按普通【杀】的1点回退。
	choice_context["damage_amount"] = maxi(int(context.get("damage_amount", context.get("base_damage_amount", AI_DEFAULT_DAMAGE_AMOUNT))), AI_DEFAULT_DAMAGE_AMOUNT)
	# 目标当前状态；基础 AI 在目标体力大于1时倾向发动替代伤害。
	# 该字段只作用于通用层的“可选费用牌默认不主动支付”兜底分支；寒冰剑的选牌请求由下方的 score_ai_choice() 完整接管，
	# 通用层对 hanbing_cards 另有专门的收益分支，因此本字段不参与寒冰剑的实际评分。
	var target: PlayerState = slash_effect.state.get_player(target_id)
	choice_context["ai_prefer_select"] = target != null and target.hp > 1
	# 弃牌选择；允许取消，选择1至2张才防止伤害。
	var selected_uids: Array[int] = slash_effect.host.request_card_choice(actor_id, "寒冰剑", "是否发动【寒冰剑】并弃置目标至多两张牌？", candidates, 0, mini(2, candidates.size()), true, choice_context)
	if slash_effect.host.has_pending_card_choice():
		return true
	return _apply_choice(slash_effect, choice_context, selected_uids)


## 应用寒冰剑选择；成功弃置至少1张时返回 true 表示伤害已被防止。
func _apply_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	# 攻击者 ID；用于复核当前武器实体和记录日志。
	var actor_id: int = int(context.get("actor_id", -1))
	# 当前武器实体；换装后旧选择自动失效并正常造成伤害。
	var equipment_card: CardInstance = slash_effect.host.get_equipment_card(actor_id, "weapon")
	if equipment_card == null or equipment_card.uid != int(context.get("equipment_uid", -1)):
		return false
	# 实际弃置数量；至少成功弃置1张才防止伤害。
	var discarded_count: int = slash_effect.host.discard_selected_hand_equipment(int(context.get("target_id", -1)), selected_uids)
	if discarded_count <= 0:
		return false
	slash_effect.host.add_log("%s发动【寒冰剑】防止伤害并弃置目标至多两张牌。" % slash_effect.state.get_player(actor_id).display_name)
	return true


## 恢复寒冰剑选牌；发动失败时回到通用【杀】伤害步骤。
func continue_slash_choice(slash_effect: Object, context: Dictionary, selected_uids: Array[int]) -> bool:
	if str(context.get("kind", "")) != CHOICE_KIND:
		return false
	if not _apply_choice(slash_effect, context, selected_uids):
		slash_effect.continue_slash_damage(context)
	return true


## AI评估寒冰剑的弃牌选择；在通用评分之上扣除“放弃本次【杀】伤害”的机会成本。
## 通用层对 hanbing_cards 只把弃置目标公开区域牌本身算作收益（弃1张=1张牌值、弃2张=2张牌值），
## 完全没有扣除这张【杀】本应造成的伤害；于是只要目标手牌区或装备区有任意1张牌，确认动作就恒为正分而必然发动，
## 表现为“目标只有1张牌时也照发动”，1点伤害被无偿放弃。本入口把放弃的伤害按统一体力资源口径折算为成本。
## 换算采用手算常量而不是 score_resource_change()：该端口会再乘一次观察者态度比例，使敌方1点伤害只记1.6分，
## 于是“弃1张牌换1点伤害”仍以微弱正分发动，无法形成“1张打平、2张才划算”的稳定门槛（规范五之二.2同理）。
## 目标为友方时该成本取负值：防止对友方的伤害本身就是收益，此时应当更愿意发动。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只有寒冰剑自身的选牌步骤带有本卡牌需要识别的字段。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	# 动作负载；取消不会防止伤害，通用层的“未确认=0分”取消基准保持不变。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 本次【杀】原将造成的伤害点数；上下文字段缺失时按普通【杀】的1点回退。
	var damage_amount: int = maxi(int(context.get("damage_amount", AI_DEFAULT_DAMAGE_AMOUNT)), AI_DEFAULT_DAMAGE_AMOUNT)
	# 使用者与目标ID；两者用于判断这点伤害打在谁身上，目标缺失时按普通敌方处理。
	var actor_id: int = int(context.get("actor_id", -1))
	var target_id: int = int(context.get("target_id", -1))
	# 放弃伤害的机会成本；对敌方是本次替代的代价，对友方则相反。
	var damage_cost: float = float(damage_amount) * AI_HP_RESOURCE_VALUE
	if target_id >= 0 and target_id != actor_id and evaluator.get_attitude(authoritative_snapshot, actor_id, target_id) > 0.0:
		# 友方目标；防止这点伤害本身即为正收益，因此成本取负值等价于给本次弃牌加分。
		damage_cost = -damage_cost
	return -damage_cost
