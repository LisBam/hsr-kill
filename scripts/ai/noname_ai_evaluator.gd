class_name NonameAIEvaluator
extends RefCounted

## 无名杀式效用评估器。把牌与技能文件声明的 AI 数据转换为动作、选牌、选目标和响应分数。

## 态度归一化除数；无名杀标准身份态度大多位于-10至10，除以5后保留明显阵营差异。
const ATTITUDE_SCALE: float = 5.0

## 出牌顺序在总评分中的权重；主要用于收益接近时优先执行高 order 动作。
const ORDER_WEIGHT: float = 0.12

## 卡牌保留价值在主动使用评分中的权重；避免高价值救命牌被低收益动作轻易消耗。
const CARD_COST_WEIGHT: float = 0.08

## 获得或失去1张牌的统一基础收益单位；所有直接牌差收益必须从该常量换算，不能在技能内另设比例。
const CARD_RESOURCE_VALUE: float = 1.0

## 敌方判定区延时锦囊对“弃置/获得”选择的负价值；拆走敌方【乐】【兵】等等于帮其解控，因此取负值。
const HOSTILE_JUDGMENT_DISCARD_VALUE: float = -8.0

## 友方判定区延时锦囊对“弃置/获得”选择的正价值；帮助友方解除延时锦囊是明确正收益。
const FRIENDLY_JUDGMENT_DISCARD_VALUE: float = 6.0

## 回复或失去1点体力的统一基础收益单位；固定等于2张牌，保证全局AI遵循“1点体力=2张牌”。
const HP_RESOURCE_VALUE: float = CARD_RESOURCE_VALUE * 2.0

## 重铸获得一张未知牌的基础收益；与无名杀把低价值可重铸牌视为换牌机会的思路一致。
const RECAST_DRAW_VALUE: float = 4.5

## 必须响应伤害时的基础收益；确保【闪】、【杀】等防止常规1点伤害时通常值得打出。
const RESPONSE_SURVIVAL_VALUE: float = 6.0

## 酒杀每多1点伤害对【闪】响应的额外保命收益；固定4.0分使高伤害响应明显高于普通杀。
const WINE_SLASH_RESPONSE_EXTRA_DAMAGE_BONUS: float = 4.0

## 酒杀足以打穿当前体力与护盾时的致命响应奖励；固定8.0分确保AI不会为非致命连环收益放弃保命。
const LETHAL_SLASH_RESPONSE_BONUS: float = 8.0

## 非致命酒杀威胁下保留最后1张【闪】的价值加成；固定2.0分优先于一般低价资源，但不轻易压过【桃】。
const WINE_SLASH_DODGE_RESERVE_BONUS: float = 2.0

## 致命酒杀威胁下保留最后1张【闪】的价值加成；固定6.0分允许AI为避免立即濒死而优先保留确定防御牌。
const LETHAL_WINE_SLASH_DODGE_RESERVE_BONUS: float = 6.0

## 酒杀每多1点伤害的主动目标效果倍率；固定2.0使AI同时考虑额外资源压力与更接近击杀的价值。
const WINE_SLASH_EXTRA_DAMAGE_EFFECT_MULTIPLIER: float = 2.0

## 友方属性伤害可传导至全部横置敌人时放弃【闪】的响应修正；固定8.0分，足以使AI保留响应牌并让连环伤害结算。
const FRIENDLY_CHAIN_DAMAGE_RESPONSE_DECLINE_VALUE: float = 8.0

## 目标已知拥有所需响应牌时的预期命中倍率；保留少量消耗响应资源的收益。
const KNOWN_RESPONSE_DAMAGE_MULTIPLIER: float = 0.35

## 目标无已知【闪】但装备【八卦阵】时的预期命中倍率；反映约一半判定成功率。
const BAGUA_DAMAGE_MULTIPLIER: float = 0.65

## 1点体力目标拥有已知救命牌时的预期击杀倍率；仍保留压低救援资源的收益。
const SURVIVAL_CARD_DAMAGE_MULTIPLIER: float = 0.7

## 横置角色受到传导伤害时的自身风险倍率；默认1.5使行动者已横置时主动使用属性伤害明显降权但不一概禁止技能联动。
const CHAINED_SELF_DAMAGE_RISK_MULTIPLIER: float = 1.5

## 横置角色仅剩1点体力时的传导伤害倍率；固定2.5与直接伤害的濒危权重一致，优先避免误杀队友或自己。
const CHAINED_CRITICAL_HP_MULTIPLIER: float = 2.5

## 行动者被横置传导伤害且仅剩1点体力时的额外生存惩罚；防止技能微小收益掩盖自身立即濒死风险。
const CHAINED_SELF_LETHAL_PENALTY: float = 12.0

## 【白银狮子】的稳定卡牌 ID；装备取得、换装与弃置估值共用该常量，避免在多个决策分支重复书写字符串。
const BAIYIN_LION_CARD_ID: String = "baiyin"

## 当前评估器使用的身份关系模型；由协调器共享，保证所有 AI 观察到一致的身份暴露度。
var identity_model: IdentityAIModel

## 当前评估器使用的身份战略层；负责领袖危险、威胁集火、内奸控场和濒死救援。
var identity_strategy: IdentityStrategyEvaluator

## 已读取的卡牌静态定义缓存；每个评估器只保存数据库返回的独立副本，用于消除候选评分期间对同一定义的重复深拷贝。
## 缓存内容只允许读取，卡牌规则或技能 AI 不得向其中写入任何临时评分字段；运行时无需动态修改。
var _card_definition_cache: Dictionary = {}


## 创建绑定身份模型的效用评估器；模型为空时创建独立默认实例。
func _init(model: IdentityAIModel = null) -> void:
	identity_model = model if model != null else IdentityAIModel.new()
	identity_strategy = IdentityStrategyEvaluator.new(identity_model)


## 计算指定角色获得牌与改变体力的统一资源收益；正数表示获得，负数表示失去，结果会按观察者态度转换为敌我收益。
## 牌面保留价值、濒死奖励和技能机会成本不属于基础牌差，调用方应在本结果之外单独叠加。
func score_resource_change(authoritative_snapshot: Dictionary, observer_id: int, target_id: int, card_count_change: int, hp_change: int) -> float:
	# 资源变化基础值；1点体力严格折算为2张牌，正负方向由数量符号直接表达。
	var resource_value: float = float(card_count_change) * CARD_RESOURCE_VALUE + float(hp_change) * HP_RESOURCE_VALUE
	# 观察者对资源变化目标的态度；友方获得和敌方失去都会形成正收益。
	var attitude: float = get_attitude(authoritative_snapshot, observer_id, target_id)
	return resource_value * attitude / ATTITUDE_SCALE


## 计算弃置或转移装备区【白银狮子】时的回复收益；只有受伤持有者失去实际装备才会触发该效果。
func score_baiyin_equipment_loss_recovery(authoritative_snapshot: Dictionary, observer_id: int, owner_id: int, card_data: Dictionary) -> float:
	# 当前实体定义；非白银狮子或不完整候选都没有离区回复收益。
	if str(card_data.get("definition_id", "")) != BAIYIN_LION_CARD_ID:
		return 0.0
	# 当前实体区域；手牌中的白银狮子被弃置或转移不会触发防具离区效果。
	if str(card_data.get("zone", "")) != "equipment":
		return 0.0
	# 当前装备持有者；满体力、死亡或不存在的角色不会从本次离区获得回复。
	var owner: Dictionary = get_player(authoritative_snapshot, owner_id)
	if owner.is_empty() or not bool(owner.get("alive", false)) or int(owner.get("hp", 0)) >= int(owner.get("max_hp", 0)):
		return 0.0
	return score_resource_change(authoritative_snapshot, observer_id, owner_id, 0, 1)


## 计算获得一张【白银狮子】后替换自身同名防具的额外回复价值；只用于实际取得该牌的候选选择。
func get_baiyin_acquisition_recovery_value(authoritative_snapshot: Dictionary, recipient_id: int, card_data: Dictionary) -> float:
	# 当前取得的实体定义；不是白银狮子时不需要处理换装离区回复。
	if str(card_data.get("definition_id", "")) != BAIYIN_LION_CARD_ID:
		return 0.0
	# 当前接收者；没有已装备白银狮子或已满体力时，新牌不会创造回复机会。
	var recipient: Dictionary = get_player(authoritative_snapshot, recipient_id)
	if recipient.is_empty() or int(recipient.get("hp", 0)) >= int(recipient.get("max_hp", 0)):
		return 0.0
	# 当前防具实体；只有同名防具会在装备新牌时被弃置并触发回复。
	var armor: Dictionary = (recipient.get("equipment", {}) as Dictionary).get("armor", {}) as Dictionary
	if str(armor.get("definition_id", "")) != BAIYIN_LION_CARD_ID:
		return 0.0
	return HP_RESOURCE_VALUE


## 计算一项出牌阶段动作的基础效用；具体技能可在自身文件中继续修正。
func score_action(authoritative_snapshot: Dictionary, action: Dictionary, actor_id: int) -> float:
	# 动作类型；结束阶段由策略层单独处理，不在此产生正收益。
	var action_type: String = str(action.get("action_type", ""))
	if action_type == "recast_card":
		return _score_recast_action(authoritative_snapshot, action, actor_id)
	if action_type != "use_card":
		return 0.0
	# 当前卡牌定义 ID；合法动作由核心写入该字段。
	var card_id: String = str(action.get("card_definition_id", ""))
	# 当前卡牌定义；AI 配置与规则元数据均由对应卡牌文件提供。
	var definition: Dictionary = _get_cached_card_definition(card_id)
	if definition.is_empty():
		return 0.0
	# 当前卡牌 AI 配置；每张与无名杀共有的牌在自身 GD 文件中声明其基础数据。
	var ai_profile: Dictionary = get_card_ai_profile(definition)
	# 当前卡牌出牌顺序；高 order 只作为收益接近时的优先级，不取代实际效果判断。
	var order: float = float(ai_profile.get("order", 3.0))
	# 当前卡牌保留价值；使用该牌会损失一次手牌资源。
	var card_value: float = get_card_value_by_id(card_id, authoritative_snapshot, actor_id)
	# 使用者自身结果；正值表示使用牌本身带来摸牌、回复或装备等收益。
	var player_result: float = float(ai_profile.get("player_result", 0.0))
	# 基础评分；使用者对自身态度固定为10，因此无需再次乘态度。
	var score: float = player_result + order * ORDER_WEIGHT - card_value * CARD_COST_WEIGHT
	# 装备动作使用换装净收益，不把所有装备都视为无条件正收益。
	if str(definition.get("type", "")) == "equipment":
		return _score_equipment_action(authoritative_snapshot, actor_id, definition, ai_profile, order)
	# 动作最终目标；全体牌动作在合法列表中目标为空，需要按目标模式从快照展开。
	var target_ids: Array[int] = get_effective_target_ids(authoritative_snapshot, actor_id, definition, action.get("target_ids", []) as Array)
	# 当前实体牌颜色；仁王盾等颜色型防具必须读取实际使用牌，虚拟且未声明颜色的牌保持未知。
	var action_card_color: String = _get_action_card_color(authoritative_snapshot, actor_id, action)
	# 本次牌效的预期伤害值；【杀】会读取使用者当前公开酒加成，其他伤害牌默认为1。
	var expected_damage_amount: int = _get_action_expected_damage_amount(authoritative_snapshot, actor_id, definition, action)
	# 目标结果基础值；负值代表伤害、弃牌或跳阶段，正值代表回复和摸牌。
	var target_result: float = float(ai_profile.get("target_result", 0.0))
	for target_id: int in target_ids:
		score += score_target_effect(authoritative_snapshot, actor_id, target_id, definition, ai_profile, target_result, action_card_color, expected_damage_amount)
	# 可重铸牌只有实际使用收益高于换牌收益时才使用；否则重铸动作会在合法列表中胜出。
	if bool(definition.get("recast", false)):
		score -= maxf(0.0, RECAST_DRAW_VALUE - card_value) * 0.5
	return score


## 计算一名目标承受当前牌效的观察者收益；包含身份态度、濒危状态、手牌数、防具与属性连环传播。
## card_color 仅由主动使用实体提供；空字符串表示未知颜色，不能臆测颜色型防具必定生效。
## expected_damage_amount 是本次对目标的伤害基数；默认1保持普通牌和旧调用方的原有评分语义。
func score_target_effect(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, definition: Dictionary, ai_profile: Dictionary, target_result: float, card_color: String = "", expected_damage_amount: int = 1) -> float:
	# AI 对目标的当前态度；正值为友方，负值为敌方，隐藏身份会按暴露度衰减。
	var attitude: float = get_attitude(authoritative_snapshot, actor_id, target_id)
	# 目标状态；体力和手牌会放大伤害、控制与救援效果。
	var target: Dictionary = get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return 0.0
	# 目标公开防具定义；防具无效化和伤害放大在目标状态倍率之前统一应用。
	var armor_definition: CardDefinition = _get_effective_armor_definition(authoritative_snapshot, actor_id, target, definition)
	if armor_definition != null:
		# 当前牌定义ID；群体锦囊使用稳定ID判断藤甲等防具的完全无效规则。
		var card_definition_id: String = str(definition.get("id", ""))
		# 当前伤害属性；普通【杀】会被藤甲拦截，火焰伤害则提高预期收益。
		var nature: String = str(definition.get("nature", "normal"))
		if str(definition.get("effect_id", "")) == "slash" and armor_definition.blocks_slash_by_color(card_color, nature):
			return 0.0
		if armor_definition.blocks_aoe(card_definition_id):
			return 0.0
	# 目标状态倍率；复制无名杀 get.effect 对低体力、少手牌目标的威胁放大思想。
	var status_multiplier: float = 1.0
	if bool(ai_profile.get("recover", false)) and int(target.get("hp", 0)) >= int(target.get("max_hp", 0)):
		return 0.0
	if bool(ai_profile.get("damage", false)):
		# 安全伤害值；异常或缺失数据至少按1点伤害评估。
		expected_damage_amount = maxi(expected_damage_amount, 1)
		if armor_definition != null:
			status_multiplier *= armor_definition.get_ai_incoming_damage_multiplier(str(definition.get("nature", "normal")))
		# 目标体力；1点体力时伤害价值显著上升，2点体力时次级上升。
		# 目标可承受值；体力与护盾共同决定酒杀是否会立即令其进入濒死。
		var target_survival: int = int(target.get("hp", 0)) + int(target.get("shield", 0))
		# 受伤后剩余可承受值；不大于0代表预期致命，等于1代表下一次伤害即致命。
		var remaining_survival_after_damage: int = target_survival - expected_damage_amount
		if remaining_survival_after_damage <= 0:
			status_multiplier *= 2.5
		elif remaining_survival_after_damage == 1:
			status_multiplier *= 1.8
		# 额外伤害倍率；酒杀不只更接近击杀，也会一次压缩更多体力与救援资源。
		if expected_damage_amount > 1:
			status_multiplier *= pow(WINE_SLASH_EXTRA_DAMAGE_EFFECT_MULTIPLIER, expected_damage_amount - 1)
		# 目标手牌数；无牌更难响应【杀】或群体牌，三张以上则不应过度确信命中。
		var hand_count: int = int(target.get("hand_count", 0))
		if hand_count == 0:
			status_multiplier *= 1.7 if bool(ai_profile.get("respond_sha", false)) or bool(ai_profile.get("respond_shan", false)) else 1.5
		elif hand_count == 1:
			status_multiplier *= 1.3
		elif hand_count == 2:
			status_multiplier *= 1.1
		elif hand_count >= 3:
			status_multiplier *= 0.5
		# 已知响应牌；无名杀服务端 AI 可查询目标是否持有【闪】或【杀】，有响应时降低预期命中收益。
		var required_response_pattern: String = "shan" if bool(ai_profile.get("respond_shan", false)) else ("sha" if bool(ai_profile.get("respond_sha", false)) else "")
		if not required_response_pattern.is_empty() and get_known_response_count(authoritative_snapshot, target_id, required_response_pattern) > 0:
			status_multiplier *= KNOWN_RESPONSE_DAMAGE_MULTIPLIER
		elif required_response_pattern == "shan" and _has_equipment(target, "bagua"):
			# 八卦阵红色判定约有一半成功率，因此没有手牌【闪】时仍降低预期命中收益。
			status_multiplier *= BAGUA_DAMAGE_MULTIPLIER
		# 濒危目标持有桃或自救酒时降低一次伤害直接完成击杀的预期，但仍保留压低资源的收益。
		if target_survival <= expected_damage_amount and get_survival_card_count(authoritative_snapshot, target_id) > 0:
			status_multiplier *= SURVIVAL_CARD_DAMAGE_MULTIPLIER
	# 当前目标直接效用；牌效结果乘观察者态度后，敌方负面效果会转为正收益。
	var result: float = target_result * attitude / ATTITUDE_SCALE * status_multiplier
	# 身份局战略附加分；领袖保护、反贼集火和内奸控场不改变实际牌效数值。
	result += identity_strategy.score_target_strategy(authoritative_snapshot, actor_id, target_id, ai_profile)
	if bool(ai_profile.get("damage", false)) and int(target.get("hp", 0)) + int(target.get("shield", 0)) <= expected_damage_amount:
		# 预计1点伤害即可击杀时纳入身份死亡奖惩；群体牌逐目标调用本方法，因此天然覆盖全部可能受害队友。
		# 预期伤害即可击杀时纳入身份死亡奖惩；群体牌逐目标调用本方法，因此天然覆盖全部可能受害队友。
		result += identity_strategy.score_lethal_damage_consequence(authoritative_snapshot, actor_id, target_id)
	# 属性伤害连环传播；目标已横置时把同值伤害继续计入其他横置角色。
	if bool(ai_profile.get("nature_damage", false)) and bool(target.get("chained", false)):
		for chained_variant: Variant in authoritative_snapshot.get("players", []) as Array:
			# 其他横置存活角色；当前目标已经计算，不重复加入。
			var chained_player: Dictionary = chained_variant as Dictionary
			# 其他横置角色 ID；用于读取观察者态度。
			var chained_id: int = int(chained_player.get("player_id", -1))
			if chained_id == target_id or not bool(chained_player.get("alive", false)) or not bool(chained_player.get("chained", false)):
				continue
			result += _score_chained_damage_effect(authoritative_snapshot, actor_id, chained_id, ai_profile, target_result, expected_damage_amount)
	return result


## 评估属性伤害经铁索传导到另一名横置角色的收益；统一纳入自身风险、濒危队友与预计击杀的身份奖惩。
## expected_damage_amount 与直接目标共享同一张属性【杀】的酒加成，多目标和连环均不重复消耗该状态。
func _score_chained_damage_effect(authoritative_snapshot: Dictionary, actor_id: int, chained_id: int, ai_profile: Dictionary, target_result: float, expected_damage_amount: int = 1) -> float:
	# 传导受击者快照；不存在或已离场的玩家不会参与当前属性伤害结算。
	var chained_player: Dictionary = get_player(authoritative_snapshot, chained_id)
	if chained_player.is_empty() or not bool(chained_player.get("alive", false)):
		return 0.0
	# 行动者对传导受击者的态度；友方受伤为负收益，敌方受伤为正收益。
	var attitude: float = get_attitude(authoritative_snapshot, actor_id, chained_id)
	# 传导伤害状态倍率；低体力目标更接近死亡，必须放大其对友军风险和敌军收益的影响。
	var status_multiplier: float = 1.0
	# 传导受击者可承受值；护盾与体力共同参与致命性判断。
	var chained_survival: int = int(chained_player.get("hp", 0)) + int(chained_player.get("shield", 0))
	if chained_survival <= expected_damage_amount:
		status_multiplier *= CHAINED_CRITICAL_HP_MULTIPLIER
	if expected_damage_amount > 1:
		status_multiplier *= pow(WINE_SLASH_EXTRA_DAMAGE_EFFECT_MULTIPLIER, expected_damage_amount - 1)
	# 行动者自身被传导时额外放大损失，确保“自己横置”会显著降低向横置目标施放属性伤害的评分。
	if chained_id == actor_id:
		status_multiplier *= CHAINED_SELF_DAMAGE_RISK_MULTIPLIER
	# 当前传导伤害基础收益；仍沿用卡牌或技能声明的 target_result，避免为属性伤害另建硬编码评分表。
	var result: float = target_result * attitude / ATTITUDE_SCALE * status_multiplier
	# 传导到濒危角色时的身份死亡后果；可同时处理友军误杀、击杀反贼摸牌与主公误杀忠臣的资源惩罚。
	if chained_survival <= expected_damage_amount:
		result += identity_strategy.score_lethal_damage_consequence(authoritative_snapshot, actor_id, chained_id)
		if chained_id == actor_id:
			# 自己横置且1血会在传导后立即濒死；死亡奖惩接口刻意跳过自身，因此在此补充纯生存风险。
			result -= CHAINED_SELF_LETHAL_PENALTY
	return result


## 返回当前牌效应应用的目标防具；青釭剑等无视防具武器只在【杀】结算中返回空值。
func _get_effective_armor_definition(authoritative_snapshot: Dictionary, actor_id: int, target: Dictionary, definition: Dictionary) -> CardDefinition:
	if str(definition.get("effect_id", "")) == "slash":
		# 使用者公开武器；武器源码统一声明是否无视防具，AI不硬编码装备ID。
		var actor: Dictionary = get_player(authoritative_snapshot, actor_id)
		# 当前武器快照；空槽返回空字典并自然跳过。
		var weapon: Dictionary = (actor.get("equipment", {}) as Dictionary).get("weapon", {}) as Dictionary
		# 当前武器源码；青釭剑等声明无视防具时不再读取目标防具能力。
		var weapon_definition: CardDefinition = GameDatabase.get_card_definition(str(weapon.get("definition_id", "")))
		if weapon_definition != null and weapon_definition.slash_ignores_armor():
			return null
	# 目标防具快照；不存在公开防具时没有任何修正。
	var armor: Dictionary = (target.get("equipment", {}) as Dictionary).get("armor", {}) as Dictionary
	return GameDatabase.get_card_definition(str(armor.get("definition_id", "")))


## 计算统一选择请求中的默认动作评分；卡牌与技能文件可在此结果上实现专属判断。
func score_choice_action(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, actor_id: int) -> float:
	# 动作负载；选择请求的牌与目标均保存在标准 payload 中。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 已选实体牌 UID；空数组可能表示放弃，也可能是纯目标选择。
	var selected_card_uids: Array = payload.get("selected_card_uids", []) as Array
	# 已选目标 ID；纯选目标技能和零牌费用组合通过该数组表达确认。
	var selected_target_ids: Array = payload.get("selected_target_ids", []) as Array
	# 是否确认；零牌零目标的布尔请求必须依赖该字段区分确认与取消。
	var confirmed: bool = bool(payload.get("confirmed", false))
	# 选择语义上下文；所有专属恢复字段均由权威请求写入。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 当前选择种类；弃牌阶段、响应、展示和普通选牌使用同一协议。
	var choice_kind: String = str(context.get("kind", ""))
	if not confirmed:
		return 0.0
	# 选牌资源总价值；费用与弃牌倾向选择最低价值，获得牌与展示选择可由专属卡牌调整。
	var selected_value: float = 0.0
	for selected_uid_variant: Variant in selected_card_uids:
		# 当前选择候选 UID；候选快照同时提供实际持有者和区域，用于计算白银狮子离区回复。
		var selected_uid: int = int(selected_uid_variant)
		# 当前候选数据；不存在时保持原有未知牌2分价值，不伪造装备离区效果。
		var candidate: Dictionary = _get_choice_candidate_by_uid(choice_request, selected_uid)
		# 当前候选牌面；隐藏手牌只提供空定义，白银狮子修正会自然跳过。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		# 当前候选持有者；弃置和转移时由候选快照提供，避免把发起选择者误当成装备持有者。
		var candidate_owner_id: int = int(candidate.get("owner_id", -1))
		selected_value += get_choice_card_value(authoritative_snapshot, choice_request, selected_uid, actor_id)
		# 白银狮子离区回复对敌方会减少拆取收益，对友方则增加收益；手牌候选与满体力持有者不会产生修正。
		var baiyin_loss_recovery_score: float = score_baiyin_equipment_loss_recovery(authoritative_snapshot, actor_id, candidate_owner_id, card_data)
		if choice_kind in ["discard_target", "steal_target"]:
			selected_value += baiyin_loss_recovery_score
		elif choice_kind == "discard_phase" or choice_kind in ["dieying_discard", "zaixian_discard", "guanshi_cost"] or int(choice_request.get("min_card_select", choice_request.get("min_select", 0))) > 0:
			# 自己把受伤白银狮子作为费用时，失去防具后的回复会降低净弃置成本。
			selected_value -= baiyin_loss_recovery_score
		if choice_kind in ["steal_target", "harvest"]:
			# 取得白银狮子后若可换下自身同名防具，额外回复属于取得者的真实收益。
			selected_value += get_baiyin_acquisition_recovery_value(authoritative_snapshot, actor_id, card_data)
	if choice_kind in ["discard_target", "steal_target", "harvest"]:
		# 操作他人区域或领取公共牌时优先选择已知价值最高的牌；隐藏手牌只按统一未知价值比较。
		return selected_value
	if choice_kind == "fire_attack_show":
		# 火攻目标必须展示手牌时优先公开自身最低价值牌，减少后续同花色弃牌信息收益。
		return -selected_value
	if choice_kind in ["hanbing_cards", "qilin_mount"]:
		# 寒冰剑与麒麟弓操作敌方公开区域牌时优先选择总价值最高的组合。
		return selected_value
	if choice_kind == "fire_attack_discard":
		# 火攻使用者决定是否支付同花色手牌；对敌方造成火焰伤害的收益必须高于费用牌价值。
		if str(authoritative_snapshot.get("match_id", "")).is_empty():
			# 无对局 ID 的规则预演使用确定性确认，保证机制测试可以稳定覆盖火攻伤害与死亡恢复链。
			return 1.0
		# 火攻目标 ID；用于按使用者对目标的身份态度评估伤害收益。
		var fire_target_id: int = int(context.get("target_id", -1))
		return -get_attitude(authoritative_snapshot, actor_id, fire_target_id) - selected_value
	if choice_kind == "flood_equipment":
		# 水淹七军目标比较失去全部装备与承受1点伤害；低体力时更倾向弃置低总价值装备。
		var flood_target: Dictionary = get_player(authoritative_snapshot, actor_id)
		# 伤害风险；1点体力时显著提高，2点体力时中度提高。
		var damage_risk: float = 4.0
		if int(flood_target.get("hp", 0)) <= 1:
			damage_risk = 10.0
		elif int(flood_target.get("hp", 0)) == 2:
			damage_risk = 6.5
		return damage_risk - selected_value
	if choice_kind == "discard_phase" or choice_kind in ["dieying_discard", "zaixian_discard", "guanshi_cost"] or int(choice_request.get("min_card_select", choice_request.get("min_select", 0))) > 0:
		return -selected_value
	# 响应请求；常规【闪】、【杀】与救援牌优先避免伤害或死亡，无懈可击另由专门入口判断。
	var response_patterns: Array = context.get("response_patterns", []) as Array
	if not response_patterns.is_empty():
		if response_patterns.has("wuxie"):
			return 1.0 if should_negate(authoritative_snapshot, actor_id, context) else -1.0
		if response_patterns.has("tao") or response_patterns.has("jiu"):
			# 濒死救援必须结合身份关系、领袖存亡、内奸控场、自救和救援牌成本。
			var dying_target_id: int = int(context.get("target_id", actor_id))
			return identity_strategy.score_rescue(authoritative_snapshot, actor_id, dying_target_id, int(context.get("required_recover", 1)), selected_value)
		if choice_kind == "borrow_sword_response":
			# 借刀持刀者同时考虑保住武器和【杀】命中受害者的阵营收益。
			var victim_id: int = int(context.get("victim_id", -1))
			return RESPONSE_SURVIVAL_VALUE - get_attitude(authoritative_snapshot, actor_id, victim_id) - selected_value * CARD_COST_WEIGHT
		# 当前响应保命收益；【闪】会根据真实伤害值和致命性加分，其他响应保持原有6.0分基准。
		var response_survival_value: float = RESPONSE_SURVIVAL_VALUE
		if response_patterns.has("shan"):
			# 当前预期伤害；【杀】响应上下文优先提供damage_amount，缺失时安全回退1。
			var expected_response_damage: int = maxi(int(context.get("damage_amount", context.get("amount", 1))), 1)
			response_survival_value += float(expected_response_damage - 1) * WINE_SLASH_RESPONSE_EXTRA_DAMAGE_BONUS
			# 当前响应者；体力和护盾之和不大于预期伤害时，本次【闪】属于致命防御。
			var response_player: Dictionary = get_player(authoritative_snapshot, actor_id)
			if not response_player.is_empty() and int(response_player.get("hp", 0)) + int(response_player.get("shield", 0)) <= expected_response_damage:
				response_survival_value += LETHAL_SLASH_RESPONSE_BONUS
		if _should_decline_response_for_friendly_chain_damage(authoritative_snapshot, actor_id, context, response_patterns):
			# 友方属性伤害会经本人传导到全部横置敌人；此时使用【闪】会阻断更高总收益，故把确认响应压到取消动作以下。
			return response_survival_value - FRIENDLY_CHAIN_DAMAGE_RESPONSE_DECLINE_VALUE - selected_value * CARD_COST_WEIGHT
		return response_survival_value - selected_value * CARD_COST_WEIGHT
	# 普通选目标默认按友方收益排序；专属技能通常会覆盖该分数。
	if not selected_target_ids.is_empty():
		# 首个目标 ID；当前基础协议主要枚举单目标动作。
		var target_id: int = int(selected_target_ids[0])
		return get_attitude(authoritative_snapshot, actor_id, target_id) / ATTITUDE_SCALE
	# 可选费用牌默认不主动支付，除非请求显式声明 AI 偏好选择。
	if not selected_card_uids.is_empty() and bool(context.get("ai_prefer_select", false)):
		return 1.0 - selected_value * CARD_COST_WEIGHT
	return 0.1


## 判断是否应让友方属性伤害命中自己以传导至全部横置敌人；只影响需要【闪】的可取消响应，不改变伤害或连环规则。
func _should_decline_response_for_friendly_chain_damage(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary, response_patterns: Array) -> bool:
	# 当前响应模式；只有【闪】能直接阻断即将命中的【杀】等伤害，其他响应不套用本策略。
	if not response_patterns.has("shan"):
		return false
	# 当前响应者状态；必须自身横置且仍存活，才能成为属性连环的起点。
	var responder: Dictionary = get_player(authoritative_snapshot, responder_id)
	if responder.is_empty() or not bool(responder.get("alive", false)) or not bool(responder.get("chained", false)):
		return false
	# 伤害来源；【杀】使用actor_id，部分同类卡牌使用source_id，二者都不应由客户端猜测。
	var source_id: int = int(context.get("actor_id", context.get("source_id", -1)))
	if source_id < 0 or get_attitude(authoritative_snapshot, responder_id, source_id) <= 0.0:
		return false
	# 伤害属性；优先使用响应上下文保存的真实nature，缺失时才回退当前逻辑牌定义。
	var nature: String = str(context.get("nature", ""))
	if nature.is_empty():
		var card_definition_id: String = str(context.get("slash_card_definition_id", context.get("card_definition_id", "")))
		nature = str(_get_cached_card_definition(card_definition_id).get("nature", "normal"))
	if nature == "normal" or nature.is_empty():
		return false
	# 本次预期伤害；自身会先受到这段伤害，濒死或必死时不能为了传导盲目放弃响应。
	var expected_damage: int = maxi(int(context.get("damage_amount", context.get("amount", 1))), 1)
	if int(responder.get("hp", 0)) <= expected_damage:
		return false
	# 敌方横置状态；至少有一名敌人，且所有仍在场敌人都横置时，属性伤害必定同时传导给整组敌人。
	var has_enemy: bool = false
	var all_enemies_chained: bool = true
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前场上角色；死亡、离场、响应者自身与友方来源均不属于本次“其他敌人”集合。
		var player: Dictionary = player_variant as Dictionary
		var player_id: int = int(player.get("player_id", -1))
		if player_id == responder_id or not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)) or get_attitude(authoritative_snapshot, responder_id, player_id) >= 0.0:
			continue
		has_enemy = true
		if not bool(player.get("chained", false)):
			all_enemies_chained = false
			break
	return has_enemy and all_enemies_chained


## 判断当前无懈可击是否值得响应；按奇偶状态恢复或抵消对友方/敌方的牌效。
func should_negate(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary) -> bool:
	# 当前锦囊目标；无有效目标时不浪费无懈可击。
	var target_id: int = int(context.get("target_id", -1))
	if target_id < 0:
		return false
	# 当前锦囊 ID；对应卡牌文件声明 target_result、beneficial 等 AI 数据。
	var trick_id: String = str(context.get("trick_id", context.get("card_definition_id", "")))
	# 当前锦囊定义；未知锦囊按普通负面牌处理。
	var trick_definition: Dictionary = _get_cached_card_definition(trick_id)
	# 当前锦囊 AI 配置；目标结果正负可直接表达收益方向。
	var trick_ai: Dictionary = get_card_ai_profile(trick_definition)
	# 锦囊对目标的基础结果；正值有利，负值有害。
	var target_result: float = float(trick_ai.get("target_result", 1.0 if bool(trick_definition.get("ai_beneficial", false)) else -1.0))
	# 当前锦囊源码；允许状态型锦囊按目标的实时状态反转收益方向，避免无懈策略只读取静态配置。
	var trick_definition_instance: CardDefinition = GameDatabase.get_card_definition(trick_id)
	if trick_definition_instance != null:
		target_result = trick_definition_instance.get_identity_observation_target_result(authoritative_snapshot, int(context.get("source_id", -1)), target_id, target_result)
	# 响应者对目标的态度；隐藏身份使用同一身份模型而不是直接按真实阵营二分。
	var attitude: float = get_attitude(authoritative_snapshot, responder_id, target_id)
	# 当前是否已被奇数张无懈抵消；下一张无懈会翻转该状态。
	var currently_negated: bool = bool(context.get("negated", false))
	# 原效果从响应者视角的收益；正数表示希望它生效，负数表示希望它失效。
	var effect_utility: float = target_result * attitude
	return effect_utility > 0.0 if currently_negated else effect_utility < 0.0


## 返回指定卡牌的保留价值；支持无名杀数组价值随同名牌数量递减的常用写法。
func get_card_value_by_id(card_id: String, authoritative_snapshot: Dictionary, owner_id: int) -> float:
	# 卡牌定义；未知牌使用3分中性价值。
	var definition: Dictionary = _get_cached_card_definition(card_id)
	if definition.is_empty():
		return 3.0
	# 卡牌 AI 配置；优先使用 value，缺失时兼容旧 ai_use_value。
	var ai_profile: Dictionary = get_card_ai_profile(definition)
	# 配置价值；允许单值或按同名牌序号递减的数组。
	var configured_value: Variant = ai_profile.get("value", definition.get("ai_use_value", 3.0))
	# 当前实际保留价值；先解析卡牌配置，再叠加对局上下文修正。
	var result: float = 3.0
	if configured_value is Array:
		# 持有者同名牌数量；当前牌按数组最后一个可用下标估值。
		var same_card_count: int = count_owned_cards(authoritative_snapshot, owner_id, card_id)
		# 价值数组；空数组回退3分。
		var values: Array = configured_value as Array
		if values.is_empty():
			result = 3.0
		else:
			result = float(values[mini(maxi(same_card_count - 1, 0), values.size() - 1)])
	else:
		result = float(configured_value)
	if card_id == "shan" and get_known_response_count(authoritative_snapshot, owner_id, "shan") == 1:
		result += _get_wine_slash_dodge_reserve_bonus(authoritative_snapshot, owner_id)
	return result


## 返回选择请求中某个候选实体的价值；隐藏牌只按2分未知资源估值，不猜测未公开牌面。
## 判定区候选按敌我态度重估：拆敌方延时锦囊为负收益，拆友方延时锦囊为正收益，禁止AI无脑弃置/获得敌人判定区。
func get_choice_card_value(authoritative_snapshot: Dictionary, choice_request: Dictionary, card_uid: int, owner_id: int) -> float:
	for candidate_variant: Variant in choice_request.get("candidates", []) as Array:
		# 当前候选快照；UID 不匹配时继续寻找。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) != card_uid:
			continue
		# 候选所在区域；判定区与手牌/装备使用不同收益语义。
		var candidate_zone: String = str(candidate.get("zone", ""))
		# 候选实际持有者；过河拆桥/顺手牵羊的区域归属与动作发起者 owner_id 不同。
		var candidate_owner_id: int = int(candidate.get("owner_id", -1))
		if candidate_zone == "judgment":
			return _get_judgment_choice_card_value(authoritative_snapshot, owner_id, candidate_owner_id, candidate)
		if not bool(candidate.get("visible", false)):
			return 2.0
		# 可见牌面；定义 ID 用于读取对应卡牌文件的 AI 价值。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		return get_card_value_by_id(str(card_data.get("definition_id", "")), authoritative_snapshot, owner_id)
	return 2.0


## 返回判定区候选对动作发起者的选择价值；敌方延时锦囊取负值，友方取正值，未知阵营按轻微负值保守处理。
func _get_judgment_choice_card_value(authoritative_snapshot: Dictionary, actor_id: int, candidate_owner_id: int, candidate: Dictionary) -> float:
	# 判定区牌面；缺失定义时仍按延时控制牌处理。
	var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
	# 延时锦囊定义 ID；用于必要时区分闪电与乐/兵的价值，当前统一按解控收益处理。
	var definition_id: String = str(card_data.get("definition_id", ""))
	if candidate_owner_id < 0:
		return HOSTILE_JUDGMENT_DISCARD_VALUE
	# 动作发起者对判定区持有者的态度；负值为敌，正值为友。
	var attitude: float = get_attitude(authoritative_snapshot, actor_id, candidate_owner_id)
	if attitude < 0.0:
		# 敌方判定区：弃置/获得等于帮其解控，收益为负；闪电稍轻但仍为负，避免误拆。
		return HOSTILE_JUDGMENT_DISCARD_VALUE * (0.6 if definition_id == "shandian" else 1.0)
	if attitude > 0.0:
		# 友方判定区：帮助解除延时锦囊是正收益。
		return FRIENDLY_JUDGMENT_DISCARD_VALUE * (0.6 if definition_id == "shandian" else 1.0)
	# 态度为0时保守视作轻微负收益，避免在身份不明时主动拆人判定区。
	return HOSTILE_JUDGMENT_DISCARD_VALUE * 0.5


## 按稳定 UID 返回选择请求中的候选副本；缺失候选返回空字典，调用方必须按未知资源而非猜测牌面处理。
func _get_choice_candidate_by_uid(choice_request: Dictionary, card_uid: int) -> Dictionary:
	for candidate_variant: Variant in choice_request.get("candidates", []) as Array:
		# 当前候选副本；每个请求内 UID 唯一，命中后深拷贝避免技能评分改写原始请求。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) == card_uid:
			return candidate.duplicate(true)
	return {}


## 返回持有者手牌或木牛“粮”中指定实体 UID 的保留价值；自定义装备动作使用该接口评估材料。
func get_owned_card_value_by_uid(authoritative_snapshot: Dictionary, owner_id: int, card_uid: int) -> float:
	# 持有者快照；不存在时按未知牌2分估值。
	var owner: Dictionary = get_player(authoritative_snapshot, owner_id)
	if owner.is_empty():
		return 2.0
	for zone_name: String in ["hand", "wooden_ox_storage"]:
		for card_variant: Variant in owner.get(zone_name, []) as Array:
			# 当前实体牌；UID 匹配时读取对应卡牌文件价值。
			var card: Dictionary = card_variant as Dictionary
			if int(card.get("uid", -1)) == card_uid:
				return get_card_value_by_id(str(card.get("definition_id", "")), authoritative_snapshot, owner_id)
	return 2.0


## 返回持有者手牌或木牛“粮”中指定实体 UID 的只读副本；技能AI可用它查询材料牌族、颜色和定义ID。
func get_owned_card_by_uid(authoritative_snapshot: Dictionary, owner_id: int, card_uid: int) -> Dictionary:
	# 持有者快照；异常缺失时返回空字典，调用方不得猜测牌面。
	var owner: Dictionary = get_player(authoritative_snapshot, owner_id)
	if owner.is_empty():
		return {}
	for zone_name: String in ["hand", "wooden_ox_storage"]:
		for card_variant: Variant in owner.get(zone_name, []) as Array:
			# 当前实体牌；UID匹配时返回深拷贝，避免内容脚本改写AI权威快照。
			var card: Dictionary = card_variant as Dictionary
			if int(card.get("uid", -1)) == card_uid:
				return card.duplicate(true)
	return {}


## 返回当前动作的预期伤害基数；显式动作字段优先，【杀】其次读取使用者公开酒加成，其他牌回退1。
func _get_action_expected_damage_amount(authoritative_snapshot: Dictionary, actor_id: int, definition: Dictionary, action: Dictionary) -> int:
	# 动作负载；扩展牌或技能可显式声明已经算定的伤害值。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 显式伤害值；正数时不再叠加酒状态，避免特殊动作重复计算。
	var declared_damage_amount: int = int(action.get("expected_damage_amount", payload.get("expected_damage_amount", 0)))
	if declared_damage_amount > 0:
		return declared_damage_amount
	if str(definition.get("effect_id", "")) != "slash":
		return 1
	# 【杀】使用者快照；酒加成是当前回合的公开规则状态，可用于AI攻防评估。
	var actor: Dictionary = get_player(authoritative_snapshot, actor_id)
	return maxi(1 + int(actor.get("wine_bonus", 0)), 1)


## 计算最后1张【闪】在当前酒杀威胁下的额外保留价值；只读取存活敌人、已知【杀】、酒加成、座次距离和公开武器范围。
func _get_wine_slash_dodge_reserve_bonus(authoritative_snapshot: Dictionary, owner_id: int) -> float:
	# 防守者快照；死亡或离场角色不再为未来酒杀保留手牌。
	var owner: Dictionary = get_player(authoritative_snapshot, owner_id)
	if owner.is_empty() or not bool(owner.get("alive", false)) or bool(owner.get("out_of_game", false)):
		return 0.0
	# 防守者当前可承受值；护盾可以吸收酒杀伤害，因此与体力一同判定致命性。
	var owner_survival: int = int(owner.get("hp", 0)) + int(owner.get("shield", 0))
	# 当前最高保留加成；多名威胁者存在时取其中最危险的一名，不重复累加。
	var reserve_bonus: float = 0.0
	for attacker_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 潜在酒杀使用者；只有存活、未离场且与防守者敌对的角色会形成威胁。
		var attacker: Dictionary = attacker_variant as Dictionary
		# 潜在使用者ID；用于态度、距离和攻击范围查询。
		var attacker_id: int = int(attacker.get("player_id", -1))
		if attacker_id == owner_id or not bool(attacker.get("alive", false)) or bool(attacker.get("out_of_game", false)) or get_attitude(authoritative_snapshot, owner_id, attacker_id) >= 0.0:
			continue
		# 酒加成值；不大于0表示下一张【杀】仍是普通伤害，不触发专项保留。
		var wine_bonus: int = int(attacker.get("wine_bonus", 0))
		if wine_bonus <= 0 or get_known_response_count(authoritative_snapshot, attacker_id, "sha") <= 0:
			continue
		if get_distance(authoritative_snapshot, attacker_id, owner_id) > get_attack_range(authoritative_snapshot, attacker_id):
			continue
		# 潜在酒杀伤害；与真实【杀】结算相同，基础1点叠加公开酒加成。
		var expected_damage: int = 1 + wine_bonus
		reserve_bonus = maxf(reserve_bonus, LETHAL_WINE_SLASH_DODGE_RESERVE_BONUS if owner_survival <= expected_damage else WINE_SLASH_DODGE_RESERVE_BONUS)
	return reserve_bonus


## 返回本次主动使用实体的公开颜色；手牌与木牛“粮”均可能作为合法使用区，找不到时保持未知。
func _get_action_card_color(authoritative_snapshot: Dictionary, actor_id: int, action: Dictionary) -> String:
	# 动作负载；虚拟牌可由规则层显式写入颜色，实体牌仍优先按UID读取真实花色。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 显式颜色；用于已由规则转换且仍保留材料颜色的虚拟牌，空值再回退实体查询。
	var declared_color: String = str(action.get("card_color", payload.get("card_color", "")))
	if not declared_color.is_empty():
		return declared_color
	# 当前使用实体UID；不存在实体时无法为仁王盾等颜色型防具提供确定预判。
	var card_uid: int = int(action.get("card_uid", -1))
	if card_uid < 0:
		return ""
	# 使用者完整私有快照；AI只读取自己可见的手牌与木牛“粮”。
	var actor: Dictionary = get_player(authoritative_snapshot, actor_id)
	for zone_name: String in ["hand", "wooden_ox_storage"]:
		for card_variant: Variant in actor.get(zone_name, []) as Array:
			# 当前实体快照；UID命中后直接返回其稳定颜色字段。
			var card: Dictionary = card_variant as Dictionary
			if int(card.get("uid", -1)) == card_uid:
				return str(card.get("color", ""))
	return ""


## 返回身份模型计算的当前态度；技能文件通过该公开只读接口复用身份判断。
func get_attitude(authoritative_snapshot: Dictionary, from_player_id: int, to_player_id: int) -> float:
	return identity_model.get_attitude(authoritative_snapshot, from_player_id, to_player_id)


## 返回指定玩家状态快照；技能 AI 只读体力、连环、手牌数与公开装备等序列化字段。
func get_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	return identity_model.get_player(authoritative_snapshot, player_id)


## 返回两名存活角色之间的最终距离；AI仅依据权威快照的座次与公开坐骑计算，不依赖运行时CardRuleService。
func get_distance(authoritative_snapshot: Dictionary, source_id: int, target_id: int) -> int:
	if source_id == target_id:
		return 0
	# 存活且未离场玩家；数组顺序保持权威座次顺序，死亡角色不计入距离。
	var alive_players: Array[Dictionary] = []
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；只有实际在场角色参与环形距离。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			alive_players.append(player)
	# 来源与目标座次索引；任一不存在时返回规则层使用的不可达距离999。
	var source_index: int = -1
	# 目标座次索引；与来源索引分开保存以计算双向最短距离。
	var target_index: int = -1
	for index: int in range(alive_players.size()):
		if int(alive_players[index].get("player_id", -1)) == source_id:
			source_index = index
		if int(alive_players[index].get("player_id", -1)) == target_id:
			target_index = index
	if source_index < 0 or target_index < 0:
		return 999
	# 顺时针座次差；环形桌面与逆时针方向取较小值。
	var clockwise: int = absi(target_index - source_index)
	# 基础距离；进攻与防御坐骑修正后仍至少为1。
	var distance: int = mini(clockwise, alive_players.size() - clockwise)
	# 来源玩家快照；进攻坐骑令其到其他角色距离减1。
	var source: Dictionary = alive_players[source_index]
	# 目标玩家快照；防御坐骑令其他角色到其距离加1。
	var target: Dictionary = alive_players[target_index]
	if (source.get("equipment", {}) as Dictionary).has("offensive_mount"):
		distance -= 1
	if (target.get("equipment", {}) as Dictionary).has("defensive_mount"):
		distance += 1
	return maxi(distance, 1)


## 返回指定玩家的公开攻击范围；无武器或定义异常时为1，装备武器时读取卡牌配置的attack_range。
func get_attack_range(authoritative_snapshot: Dictionary, player_id: int) -> int:
	# 玩家快照；不存在时使用规则默认攻击范围1。
	var player: Dictionary = get_player(authoritative_snapshot, player_id)
	if player.is_empty():
		return 1
	# 公开武器快照；空槽位安全回退至默认范围。
	var weapon: Dictionary = (player.get("equipment", {}) as Dictionary).get("weapon", {}) as Dictionary
	# 武器卡牌定义；所有武器范围由内容文件统一声明，AI不维护装备ID白名单。
	var weapon_definition: Dictionary = _get_cached_card_definition(str(weapon.get("definition_id", "")))
	return maxi(int(weapon_definition.get("attack_range", 1)), 1)


## 返回角色综合强度；额外回合、威胁与目标优先级可直接复用无名杀 condition 公式。
func get_condition(authoritative_snapshot: Dictionary, player_id: int) -> float:
	return identity_model.get_condition(authoritative_snapshot, player_id)


## 返回当前领忠方局势值；正值代表领忠优势，负值代表反贼优势。
func get_situation(authoritative_snapshot: Dictionary) -> int:
	return identity_model.get_situation(authoritative_snapshot)


## 返回指定目标对观察者阵营的综合威胁；技能 AI 可用于集火或控制目标排序。
func get_threat(authoritative_snapshot: Dictionary, viewer_id: int, target_id: int) -> float:
	return identity_strategy.get_threat(authoritative_snapshot, viewer_id, target_id)


## 返回当前领袖危险度；技能 AI 可在救援、保护或集火逻辑中复用。
func get_leader_danger(authoritative_snapshot: Dictionary) -> float:
	return identity_strategy.get_leader_danger(authoritative_snapshot)


## 返回卡牌文件声明的标准 AI 配置；兼容旧字段并保证调用方始终取得独立字典。
func get_card_ai_profile(definition: Dictionary) -> Dictionary:
	# 卡牌自身 AI 配置副本；调用方修改评分临时值不会污染数据库定义。
	var result: Dictionary = (definition.get("ai", {}) as Dictionary).duplicate(true)
	if not result.has("value") and definition.has("ai_use_value"):
		result["value"] = float(definition.get("ai_use_value", 3.0))
	if not result.has("target_result"):
		# 旧目标方向兼容；hostile 对应负面效果，friendly 对应正面效果。
		var target_attitude: String = str(definition.get("ai_target_attitude", "neutral"))
		if target_attitude == "hostile":
			result["target_result"] = -1.0
		elif target_attitude in ["friendly", "self_boost"]:
			result["target_result"] = 1.0
	if not result.has("beneficial") and definition.has("ai_beneficial"):
		result["beneficial"] = bool(definition.get("ai_beneficial", false))
	return result


## 展开卡牌实际作用目标；全体牌和自身牌无需在合法动作中重复携带所有目标 ID。
func get_effective_target_ids(authoritative_snapshot: Dictionary, actor_id: int, definition: Dictionary, requested_target_ids: Array) -> Array[int]:
	# 显式目标结果；保持动作提交顺序并转换为整数。
	var result: Array[int] = []
	for target_variant: Variant in requested_target_ids:
		result.append(int(target_variant))
	if not result.is_empty():
		return result
	# 目标模式；自身与群体模式由快照稳定展开。
	var target_mode: String = str(definition.get("target_mode", ""))
	if target_mode in ["self", "self_wounded"]:
		return [actor_id]
	if target_mode in ["all_players", "all_others"]:
		for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
			# 当前存活玩家；all_others 排除使用者自身。
			var player: Dictionary = player_variant as Dictionary
			# 当前玩家 ID；死亡或离场不进入牌效目标。
			var player_id: int = int(player.get("player_id", -1))
			if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and (target_mode == "all_players" or player_id != actor_id):
				result.append(player_id)
	return result


## 统计持有者当前手牌与木牛“粮”中的同名牌数量；用于数组价值随重复牌递减。
func count_owned_cards(authoritative_snapshot: Dictionary, owner_id: int, card_id: String) -> int:
	# 持有者快照；不存在时按首张牌估值。
	var owner: Dictionary = get_player(authoritative_snapshot, owner_id)
	if owner.is_empty():
		return 1
	# 同名牌数量；权威 AI 快照包含全部手牌与木牛“粮”牌面。
	var result: int = 0
	for card_variant: Variant in owner.get("hand", []) as Array:
		# 当前手牌；定义 ID 匹配时累计。
		var card: Dictionary = card_variant as Dictionary
		if str(card.get("definition_id", "")) == card_id:
			result += 1
	for card_variant: Variant in owner.get("wooden_ox_storage", []) as Array:
		# 当前木牛“粮”；可使用牌同样参与重复牌价值判断。
		var card: Dictionary = card_variant as Dictionary
		if str(card.get("definition_id", "")) == card_id:
			result += 1
	return maxi(result, 1)


## 返回指定玩家当前已知可提供某响应模式的实体牌数量；普通、火和雷【杀】共享 sha 模式。
func get_known_response_count(authoritative_snapshot: Dictionary, player_id: int, response_pattern: String) -> int:
	# 指定玩家快照；不存在时响应数为0。
	var player: Dictionary = get_player(authoritative_snapshot, player_id)
	if player.is_empty():
		return 0
	# 匹配响应牌数量；权威 AI 快照包含手牌与木牛“粮”的完整定义。
	var result: int = 0
	for zone_name: String in ["hand", "wooden_ox_storage"]:
		for card_variant: Variant in player.get(zone_name, []) as Array:
			# 当前实体牌；定义 ID 用于查找其可提供的响应模式。
			var card: Dictionary = card_variant as Dictionary
			# 当前实体牌定义；provided_response_pattern 决定实际可提供的响应类型。
			var definition: Dictionary = _get_cached_card_definition(str(card.get("definition_id", "")))
			if str(definition.get("provided_response_pattern", "")) == response_pattern:
				result += 1
	return result


## 返回指定玩家当前桃与自救酒总数；用于估算1点体力目标能否立即脱离濒死。
func get_survival_card_count(authoritative_snapshot: Dictionary, player_id: int) -> int:
	return get_known_response_count(authoritative_snapshot, player_id, "tao") + get_known_response_count(authoritative_snapshot, player_id, "jiu")


## 判断玩家公开装备区是否包含指定卡牌定义；装备字典按槽位保存完整牌面。
func _has_equipment(player: Dictionary, equipment_definition_id: String) -> bool:
	for equipment_variant: Variant in (player.get("equipment", {}) as Dictionary).values():
		# 当前公开装备；定义 ID 匹配时立即返回。
		var equipment: Dictionary = equipment_variant as Dictionary
		if str(equipment.get("definition_id", "")) == equipment_definition_id:
			return true
	return false


## 计算重铸动作收益；低保留价值卡牌更适合换取一张未知牌。
func _score_recast_action(authoritative_snapshot: Dictionary, action: Dictionary, actor_id: int) -> float:
	# 被重铸卡牌 ID；合法动作由核心写入。
	var card_id: String = str(action.get("card_definition_id", ""))
	# 被重铸牌保留价值；价值越低，换牌净收益越高。
	var card_value: float = get_card_value_by_id(card_id, authoritative_snapshot, actor_id)
	return RECAST_DRAW_VALUE - card_value


## 计算装备动作的换装净收益；同槽旧装备价值会从新装备收益中扣除。
func _score_equipment_action(authoritative_snapshot: Dictionary, actor_id: int, definition: Dictionary, ai_profile: Dictionary, order: float) -> float:
	# 新装备价值；缺失时使用3分普通装备默认值。
	var new_value: float = float(ai_profile.get("equip_value", ai_profile.get("value", 3.0)))
	# 装备槽；空槽配置异常时仍允许按新装备价值评估。
	var slot: String = str(definition.get("slot", ""))
	# 使用者快照；公开装备可用于计算换装损失。
	var actor: Dictionary = get_player(authoritative_snapshot, actor_id)
	# 当前同槽装备价值；无装备时为0。
	var old_value: float = 0.0
	# 被替换的旧装备快照；仅在当前槽位存在实体时用于评估白银狮子离区回复。
	var old_equipment: Dictionary = {}
	if not actor.is_empty() and (actor.get("equipment", {}) as Dictionary).has(slot):
		# 当前同槽装备牌面；读取其对应卡牌文件 AI 配置。
		old_equipment = (actor.get("equipment", {}) as Dictionary).get(slot, {}) as Dictionary
		# 当前同槽装备定义；未知定义按0处理。
		var old_definition: Dictionary = _get_cached_card_definition(str(old_equipment.get("definition_id", "")))
		# 当前同槽装备 AI 配置；优先 equip_value。
		var old_ai: Dictionary = get_card_ai_profile(old_definition)
		old_value = float(old_ai.get("equip_value", old_ai.get("value", 0.0)))
	# 白银狮子换装回复；装备新防具会令旧防具离区，受伤时的1点回复应增加友方自身换装收益。
	var baiyin_replacement_recovery_value: float = score_baiyin_equipment_loss_recovery(authoritative_snapshot, actor_id, actor_id, old_equipment)
	return new_value - old_value + baiyin_replacement_recovery_value + order * ORDER_WEIGHT


## 返回评估器内部缓存的卡牌静态定义；空 ID 返回空字典，命中后不再向数据库申请新的深拷贝。
## 返回值是评估器私有只读数据，调用方只能查询字段，禁止修改字典或其嵌套数组。
func _get_cached_card_definition(card_id: String) -> Dictionary:
	if card_id.is_empty():
		return {}
	if not _card_definition_cache.has(card_id):
		_card_definition_cache[card_id] = GameDatabase.get_card(card_id)
	return _card_definition_cache.get(card_id, {}) as Dictionary
