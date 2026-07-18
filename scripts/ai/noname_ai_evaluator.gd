class_name NonameAIEvaluator
extends RefCounted

## 无名杀式效用评估器。把牌与技能文件声明的 AI 数据转换为动作、选牌、选目标和响应分数。

## 态度归一化除数；无名杀标准身份态度大多位于-10至10，除以5后保留明显阵营差异。
const ATTITUDE_SCALE: float = 5.0

## 出牌顺序在总评分中的权重；主要用于收益接近时优先执行高 order 动作。
const ORDER_WEIGHT: float = 0.12

## 卡牌保留价值在主动使用评分中的权重；避免高价值救命牌被低收益动作轻易消耗。
const CARD_COST_WEIGHT: float = 0.08

## 重铸获得一张未知牌的基础收益；与无名杀把低价值可重铸牌视为换牌机会的思路一致。
const RECAST_DRAW_VALUE: float = 4.5

## 必须响应伤害时的基础收益；确保【闪】、【杀】等防止常规1点伤害时通常值得打出。
const RESPONSE_SURVIVAL_VALUE: float = 6.0

## 目标已知拥有所需响应牌时的预期命中倍率；保留少量消耗响应资源的收益。
const KNOWN_RESPONSE_DAMAGE_MULTIPLIER: float = 0.35

## 目标无已知【闪】但装备【八卦阵】时的预期命中倍率；反映约一半判定成功率。
const BAGUA_DAMAGE_MULTIPLIER: float = 0.65

## 1点体力目标拥有已知救命牌时的预期击杀倍率；仍保留压低救援资源的收益。
const SURVIVAL_CARD_DAMAGE_MULTIPLIER: float = 0.7

## 当前评估器使用的身份关系模型；由协调器共享，保证所有 AI 观察到一致的身份暴露度。
var identity_model: IdentityAIModel

## 当前评估器使用的身份战略层；负责主公危险、威胁集火、内奸控场和濒死救援。
var identity_strategy: IdentityStrategyEvaluator


## 创建绑定身份模型的效用评估器；模型为空时创建独立默认实例。
func _init(model: IdentityAIModel = null) -> void:
	identity_model = model if model != null else IdentityAIModel.new()
	identity_strategy = IdentityStrategyEvaluator.new(identity_model)


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
	var definition: Dictionary = GameDatabase.get_card(card_id)
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
	# 目标结果基础值；负值代表伤害、弃牌或跳阶段，正值代表回复和摸牌。
	var target_result: float = float(ai_profile.get("target_result", 0.0))
	for target_id: int in target_ids:
		score += score_target_effect(authoritative_snapshot, actor_id, target_id, definition, ai_profile, target_result)
	# 可重铸牌只有实际使用收益高于换牌收益时才使用；否则重铸动作会在合法列表中胜出。
	if bool(definition.get("recast", false)):
		score -= maxf(0.0, RECAST_DRAW_VALUE - card_value) * 0.5
	return score


## 计算一名目标承受当前牌效的观察者收益；包含身份态度、濒危状态、手牌数与属性连环传播。
func score_target_effect(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, definition: Dictionary, ai_profile: Dictionary, target_result: float) -> float:
	# AI 对目标的当前态度；正值为友方，负值为敌方，隐藏身份会按暴露度衰减。
	var attitude: float = get_attitude(authoritative_snapshot, actor_id, target_id)
	# 目标状态；体力和手牌会放大伤害、控制与救援效果。
	var target: Dictionary = get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return 0.0
	# 目标状态倍率；复制无名杀 get.effect 对低体力、少手牌目标的威胁放大思想。
	var status_multiplier: float = 1.0
	if bool(ai_profile.get("recover", false)) and int(target.get("hp", 0)) >= int(target.get("max_hp", 0)):
		return 0.0
	if bool(ai_profile.get("damage", false)):
		# 目标体力；1点体力时伤害价值显著上升，2点体力时次级上升。
		var target_hp: int = int(target.get("hp", 0))
		if target_hp <= 1:
			status_multiplier *= 2.5
		elif target_hp == 2:
			status_multiplier *= 1.8
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
		if int(target.get("hp", 0)) <= 1 and get_survival_card_count(authoritative_snapshot, target_id) > 0:
			status_multiplier *= SURVIVAL_CARD_DAMAGE_MULTIPLIER
	# 当前目标直接效用；牌效结果乘观察者态度后，敌方负面效果会转为正收益。
	var result: float = target_result * attitude / ATTITUDE_SCALE * status_multiplier
	# 身份局战略附加分；主公保护、反贼集火和内奸控场不改变实际牌效数值。
	result += identity_strategy.score_target_strategy(authoritative_snapshot, actor_id, target_id, ai_profile)
	# 属性伤害连环传播；目标已横置时把同值伤害继续计入其他横置角色。
	if bool(ai_profile.get("nature_damage", false)) and bool(target.get("chained", false)):
		for chained_variant: Variant in authoritative_snapshot.get("players", []) as Array:
			# 其他横置存活角色；当前目标已经计算，不重复加入。
			var chained_player: Dictionary = chained_variant as Dictionary
			# 其他横置角色 ID；用于读取观察者态度。
			var chained_id: int = int(chained_player.get("player_id", -1))
			if chained_id == target_id or not bool(chained_player.get("alive", false)) or not bool(chained_player.get("chained", false)):
				continue
			result += target_result * get_attitude(authoritative_snapshot, actor_id, chained_id) / ATTITUDE_SCALE
	return result


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
		selected_value += get_choice_card_value(authoritative_snapshot, choice_request, int(selected_uid_variant), actor_id)
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
			# 濒死救援必须结合身份关系、主公存亡、内奸控场、自救和救援牌成本。
			var dying_target_id: int = int(context.get("target_id", actor_id))
			return identity_strategy.score_rescue(authoritative_snapshot, actor_id, dying_target_id, int(context.get("required_recover", 1)), selected_value)
		if choice_kind == "borrow_sword_response":
			# 借刀持刀者同时考虑保住武器和【杀】命中受害者的阵营收益。
			var victim_id: int = int(context.get("victim_id", -1))
			return RESPONSE_SURVIVAL_VALUE - get_attitude(authoritative_snapshot, actor_id, victim_id) - selected_value * CARD_COST_WEIGHT
		return RESPONSE_SURVIVAL_VALUE - selected_value * CARD_COST_WEIGHT
	# 普通选目标默认按友方收益排序；专属技能通常会覆盖该分数。
	if not selected_target_ids.is_empty():
		# 首个目标 ID；当前基础协议主要枚举单目标动作。
		var target_id: int = int(selected_target_ids[0])
		return get_attitude(authoritative_snapshot, actor_id, target_id) / ATTITUDE_SCALE
	# 可选费用牌默认不主动支付，除非请求显式声明 AI 偏好选择。
	if not selected_card_uids.is_empty() and bool(context.get("ai_prefer_select", false)):
		return 1.0 - selected_value * CARD_COST_WEIGHT
	return 0.1


## 判断当前无懈可击是否值得响应；按奇偶状态恢复或抵消对友方/敌方的牌效。
func should_negate(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary) -> bool:
	# 当前锦囊目标；无有效目标时不浪费无懈可击。
	var target_id: int = int(context.get("target_id", -1))
	if target_id < 0:
		return false
	# 当前锦囊 ID；对应卡牌文件声明 target_result、beneficial 等 AI 数据。
	var trick_id: String = str(context.get("trick_id", context.get("card_definition_id", "")))
	# 当前锦囊定义；未知锦囊按普通负面牌处理。
	var trick_definition: Dictionary = GameDatabase.get_card(trick_id)
	# 当前锦囊 AI 配置；目标结果正负可直接表达收益方向。
	var trick_ai: Dictionary = get_card_ai_profile(trick_definition)
	# 锦囊对目标的基础结果；正值有利，负值有害。
	var target_result: float = float(trick_ai.get("target_result", 1.0 if bool(trick_definition.get("ai_beneficial", false)) else -1.0))
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
	var definition: Dictionary = GameDatabase.get_card(card_id)
	if definition.is_empty():
		return 3.0
	# 卡牌 AI 配置；优先使用 value，缺失时兼容旧 ai_use_value。
	var ai_profile: Dictionary = get_card_ai_profile(definition)
	# 配置价值；允许单值或按同名牌序号递减的数组。
	var configured_value: Variant = ai_profile.get("value", definition.get("ai_use_value", 3.0))
	if configured_value is Array:
		# 持有者同名牌数量；当前牌按数组最后一个可用下标估值。
		var same_card_count: int = count_owned_cards(authoritative_snapshot, owner_id, card_id)
		# 价值数组；空数组回退3分。
		var values: Array = configured_value as Array
		if values.is_empty():
			return 3.0
		return float(values[mini(maxi(same_card_count - 1, 0), values.size() - 1)])
	return float(configured_value)


## 返回选择请求中某个候选实体的价值；隐藏牌只按2分未知资源估值，不猜测未公开牌面。
func get_choice_card_value(authoritative_snapshot: Dictionary, choice_request: Dictionary, card_uid: int, owner_id: int) -> float:
	for candidate_variant: Variant in choice_request.get("candidates", []) as Array:
		# 当前候选快照；UID 不匹配时继续寻找。
		var candidate: Dictionary = candidate_variant as Dictionary
		if int(candidate.get("uid", -1)) != card_uid:
			continue
		if not bool(candidate.get("visible", false)):
			return 2.0
		# 可见牌面；定义 ID 用于读取对应卡牌文件的 AI 价值。
		var card_data: Dictionary = candidate.get("card_data", {}) as Dictionary
		return get_card_value_by_id(str(card_data.get("definition_id", "")), authoritative_snapshot, owner_id)
	return 2.0


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


## 返回身份模型计算的当前态度；技能文件通过该公开只读接口复用身份判断。
func get_attitude(authoritative_snapshot: Dictionary, from_player_id: int, to_player_id: int) -> float:
	return identity_model.get_attitude(authoritative_snapshot, from_player_id, to_player_id)


## 返回指定玩家状态快照；技能 AI 只读体力、连环、手牌数与公开装备等序列化字段。
func get_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	return identity_model.get_player(authoritative_snapshot, player_id)


## 返回角色综合强度；额外回合、威胁与目标优先级可直接复用无名杀 condition 公式。
func get_condition(authoritative_snapshot: Dictionary, player_id: int) -> float:
	return identity_model.get_condition(authoritative_snapshot, player_id)


## 返回当前主忠方局势值；正值代表主忠优势，负值代表反贼优势。
func get_situation(authoritative_snapshot: Dictionary) -> int:
	return identity_model.get_situation(authoritative_snapshot)


## 返回指定目标对观察者阵营的综合威胁；技能 AI 可用于集火或控制目标排序。
func get_threat(authoritative_snapshot: Dictionary, viewer_id: int, target_id: int) -> float:
	return identity_strategy.get_threat(authoritative_snapshot, viewer_id, target_id)


## 返回当前主公危险度；技能 AI 可在救援、保护或集火逻辑中复用。
func get_lord_danger(authoritative_snapshot: Dictionary) -> float:
	return identity_strategy.get_lord_danger(authoritative_snapshot)


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
			var definition: Dictionary = GameDatabase.get_card(str(card.get("definition_id", "")))
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
	if not actor.is_empty() and (actor.get("equipment", {}) as Dictionary).has(slot):
		# 当前同槽装备牌面；读取其对应卡牌文件 AI 配置。
		var old_equipment: Dictionary = (actor.get("equipment", {}) as Dictionary).get(slot, {}) as Dictionary
		# 当前同槽装备定义；未知定义按0处理。
		var old_definition: Dictionary = GameDatabase.get_card(str(old_equipment.get("definition_id", "")))
		# 当前同槽装备 AI 配置；优先 equip_value。
		var old_ai: Dictionary = get_card_ai_profile(old_definition)
		old_value = float(old_ai.get("equip_value", old_ai.get("value", 0.0)))
	return new_value - old_value + order * ORDER_WEIGHT
