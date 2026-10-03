class_name NonameAIEvaluator
extends RefCounted

## 无名杀式效用评估器。把牌与技能文件声明的 AI 数据转换为动作、选牌、选目标和响应分数。

## 态度归一化除数；无名杀标准身份态度大多位于-10至10，除以5后保留明显阵营差异。
const ATTITUDE_SCALE: float = 5.0

## 出牌顺序在总评分中的权重；主要用于收益接近时优先执行高 order 动作。
const ORDER_WEIGHT: float = 0.12

## 卡牌保留价值在主动使用评分中的权重；避免高价值救命牌被低收益动作轻易消耗。
const CARD_COST_WEIGHT: float = 0.08

## 【无懈可击】在响应评分中的保留价值权重；默认0.12让锦囊收益必须覆盖这张稀缺防御牌的机会成本，运行时无需动态修改。
const NEGATION_CARD_COST_WEIGHT: float = 0.12

## 仅剩最后一张【无懈可击】时为敌方后续关键锦囊保留的额外价值；默认1.5能压低普通牌差锦囊，但不会阻止保护友方免受【乐不思蜀】等强控制。
const LAST_WUXIE_RESERVE_VALUE: float = 1.5

## 仅剩最后一张【无懈可击】且当前已是关键锦囊时保留的较低额外价值；默认0.5使AI继续顾及后续风险，但不会因过度囤牌而放任两张摸牌或关键资源流失。
const LAST_WUXIE_KEY_TRICK_RESERVE_VALUE: float = 0.5

## 非关键锦囊在仅剩最后一张【无懈可击】时的收益倍率；默认0.45进一步区分普通牌差与跳过阶段、致命伤害等关键牌效。
const NON_KEY_TRICK_NEGATION_MULTIPLIER: float = 0.45

## 敌方拆取或获得目标资源时，单张公开装备或响应者可见手牌达到此价值即视为关键资源；默认5分可保护【桃】、高价值装备等，且不会为低价值冗余牌耗尽最后一张【无懈可击】。
const KEY_NEGATION_RESOURCE_CARD_VALUE: float = 5.0

## 敌方锦囊可令目标获得至少此数量牌时，最后一张【无懈可击】也应优先阻止其扩大手牌差；默认2张对应【无中生有】的完整收益。
const KEY_NEGATION_CARD_GAIN_COUNT: int = 2

## 敌方回复锦囊的目标体力不高于此值时视为濒危救治，最后一张【无懈可击】应允许阻止其脱离击杀窗口；默认1点仅覆盖临界生存场景。
const KEY_NEGATION_CRITICAL_HP_THRESHOLD: int = 1

## 面对【闪电】时使用【无懈可击】的收益倍率；默认0.10反映闪电命中概率低且可能继续传递，运行时无需动态修改。
const LIGHTNING_NEGATION_UTILITY_MULTIPLIER: float = 0.10

## 目标本人已有充足响应资源时使用【无懈可击】的收益倍率；默认0.20优先让【杀】或【闪】承担本次锦囊响应。
const SUFFICIENT_RESPONSE_NEGATION_UTILITY_MULTIPLIER: float = 0.20

## 替他人抵消负面锦囊所需的最低目标态度；默认3.5要求目标属于响应者的明确队友。
## 内奸制衡反贼、反贼结盟内奸、领袖笼络内奸以及低置信度身份标记推测出的“友方”态度上限只有3.0，
## 这些角色并非响应者的同阵营队友；替它们令【乐不思蜀】【兵粮寸断】等锦囊失效属于纯粹的负面收益，
## 因此保护性响应必须先跨过该门槛，不能只按“态度为正”就消耗稀缺的【无懈可击】。运行时无需动态修改。
const PROTECTIVE_NEGATION_ALLY_ATTITUDE_THRESHOLD: float = 3.5

## 判定【决斗】响应资源充足所需的已知【杀】数量；默认2张用于覆盖至少一轮往返，避免仅持一张时被误判为稳定应对。
const DUEL_SUFFICIENT_SHA_COUNT: int = 2

## 面对【制动】角色且拼杀资源明显劣势时继续打出【杀】的基础评分；默认-4分使非致命场景优先停止响应。
const ZHIDONG_DUEL_DECLINE_SCORE: float = -4.0

## 面对【制动】与贯石斧可支付强制命中时使用【闪】的基础评分；默认-5分优先保留无效防御牌。
const ZHIDONG_FORCED_HIT_DODGE_DECLINE_SCORE: float = -5.0

## 判定与【制动】角色拼杀时“自身【杀】较少”的最大已知数量；默认1张表示只剩当前响应资源。
const ZHIDONG_LOW_SHA_COUNT_THRESHOLD: int = 1

## 判定【制动】角色“斗志”资源较多的公开标记阈值；默认2枚可同时威胁百折与后续制动。
const ZHIDONG_DOUZHI_THREAT_THRESHOLD: int = 2

## 【决斗】停止响应时的基础伤害；固定1点，再叠加本张牌已累计的直接响应数。
const DUEL_BASE_DAMAGE_AMOUNT: int = 1

## 贯石斧强制命中需要支付的其他牌数量；固定2张，与装备规则源码保持一致。
const GUANSHI_FORCE_HIT_COST_COUNT: int = 2

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

## 防具完全无效一次攻击时的目标收益；默认-0.5，等于半张牌的资源价值。
## 为什么必须是负数而不是0：被【藤甲】【仁王盾】拦下的攻击既没有产生任何牌效，又实际消耗了使用者的牌与出牌机会。
## 若按0处理，纯出牌顺序分（order）会让AI误以为该动作仍有正向收益，从而在多目标混战中继续为被无效的目标付费。
## 取值幅度必须小于“一张低价值牌的资源成本 + 技能联动收益”，以便【星火】这类牌本身无效但技能有独立正收益的动作
## 仍能通过完整评分保留下来（领袖黑色【杀】打【仁王盾】目标触发【星火】横置时总收益约 +0.1）；
## 而没有任何技能联动的单纯攻击会落到0以下，被策略层按纯负收益动作丢弃。
## 无视防具的效果（如【青釭剑】）在 _get_effective_armor_definition() 中已提前返回空防具，不受本惩罚影响。
const ARMOR_VOID_TARGET_PENALTY: float = -0.5

## 横置角色受到传导伤害时的自身风险倍率；默认1.5使行动者已横置时主动使用属性伤害明显降权但不一概禁止技能联动。
const CHAINED_SELF_DAMAGE_RISK_MULTIPLIER: float = 1.5

## 横置角色仅剩1点体力时的传导伤害倍率；固定2.5与直接伤害的濒危权重一致，优先避免误杀队友或自己。
const CHAINED_CRITICAL_HP_MULTIPLIER: float = 2.5

## 行动者被横置传导伤害且仅剩1点体力时的额外生存惩罚；防止技能微小收益掩盖自身立即濒死风险。
const CHAINED_SELF_LETHAL_PENALTY: float = 12.0

## 【白银狮子】的稳定卡牌 ID；装备取得、换装与弃置估值共用该常量，避免在多个决策分支重复书写字符串。
const BAIYIN_LION_CARD_ID: String = "baiyin"

## 【追歼】公开标记的稳定ID前缀；实际完整ID以来源玩家ID拼接，支持多名佩拉同时标记同一目标。
const ZHUIJIAN_MARK_ID_PREFIX: String = "zhuijian:"

## 【追歼】武将牌提示条目的稳定ID前缀；条目以来源玩家ID结尾，供AI在不读取公开标记时识别每个有效来源。
const ZHUIJIAN_CORNER_ENTRY_ID_PREFIX: String = "zhuijian:"

## 队友追歼目标承受属性伤害时的额外目标评分；固定4分使火焰、雷电攻击优先集火，普通伤害和敌方来源标记不受影响。
const ZHUIJIAN_TEAMMATE_ATTRIBUTE_DAMAGE_PRIORITY_BONUS: float = 4.0

## 补充：追歼已不创建公开标记；该固定4分改由公开的武将牌提示来源条目触发，来源阵营判断保持不变。

## 当前评估器使用的身份关系模型；由协调器共享，保证所有 AI 观察到一致的身份暴露度。
var identity_model: IdentityAIModel

## 当前评估器使用的身份战略层；负责领袖危险、威胁集火、内奸控场和濒死救援。
var identity_strategy: IdentityStrategyEvaluator

## 已读取的卡牌静态定义缓存；每个评估器只保存数据库返回的独立副本，用于消除候选评分期间对同一定义的重复深拷贝。
## 缓存内容只允许读取，卡牌规则或技能 AI 不得向其中写入任何临时评分字段；运行时无需动态修改。
var _card_definition_cache: Dictionary = {}

## 已统计的武将欢愉技数量缓存；键为武将稳定ID，值为该武将声明的欢愉技数量。
## 同为静态元数据缓存：一次决策内多次比较双方欢愉技数量时不再重复读取武将与其技能定义。
var _character_joy_skill_count_cache: Dictionary = {}

## 当前一次出牌决策的完整合法动作副本；卡牌专属AI只可查询实际可执行后续，不得据手牌猜测已超次数的动作。
var _current_legal_actions: Array[Dictionary] = []

## 当前一次出牌决策的首轮完整动作评分；供需要比较连续行动的卡牌读取真实的直接行动收益。
## 每项仅保存动作副本与只读分数，不能跨决策保留，也不能用来修改核心提供的合法动作。
var _current_scored_legal_actions: Array[Dictionary] = []


## 创建绑定身份模型的效用评估器；模型为空时创建独立默认实例。
func _init(model: IdentityAIModel = null) -> void:
	identity_model = model if model != null else IdentityAIModel.new()
	identity_strategy = IdentityStrategyEvaluator.new(identity_model)


## 写入本次决策的合法动作上下文；每项深拷贝，卡牌评分不能改写控制器提供的权威候选。
func set_current_legal_actions(legal_actions: Array[Dictionary]) -> void:
	_current_legal_actions.clear()
	for action: Dictionary in legal_actions:
		_current_legal_actions.append(action.duplicate(true))


## 返回本次决策的合法动作副本；直接评分或选择请求期间没有动作上下文时返回空数组。
func get_current_legal_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action: Dictionary in _current_legal_actions:
		result.append(action.duplicate(true))
	return result


## 写入当前合法动作的首轮完整评分；连续行动牌据此与真正的直接行动比较，避免只按局部牌效推断后续。
func set_current_legal_action_scores(scored_actions: Array[Dictionary]) -> void:
	_current_scored_legal_actions.clear()
	for scored_action: Dictionary in scored_actions:
		# 当前动作副本；空动作不构成可比较的后续行动。
		var action: Dictionary = scored_action.get("action", {}) as Dictionary
		if action.is_empty():
			continue
		_current_scored_legal_actions.append({
			"action":action.duplicate(true),
			"score":float(scored_action.get("score", -INF)),
		})


## 返回当前合法动作的首轮完整评分副本；没有建立两阶段评分上下文时返回空数组。
func get_current_legal_action_scores() -> Array[Dictionary]:
	# 当前评分结果副本；调用方只能读取，不能改写本次策略的内部比较基线。
	var result: Array[Dictionary] = []
	for scored_action: Dictionary in _current_scored_legal_actions:
		result.append(scored_action.duplicate(true))
	return result


## 清理单次出牌决策的合法动作上下文；策略返回动作后必须调用，避免下一次决策读取旧阶段候选。
func clear_current_legal_actions() -> void:
	_current_legal_actions.clear()
	_current_scored_legal_actions.clear()


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
		# 防具完全无效的攻击按明确负收益计算，而不是0：普通【杀】对【藤甲】、黑色【杀】对【仁王盾】
		# 以及被【藤甲】拦截的【南蛮入侵】【万箭齐发】都属于“白白消耗一张牌”，必须让AI看到净损失。
		if str(definition.get("effect_id", "")) == "slash" and armor_definition.blocks_slash_by_color(card_color, nature):
			return ARMOR_VOID_TARGET_PENALTY
		if armor_definition.blocks_aoe(card_definition_id):
			return ARMOR_VOID_TARGET_PENALTY
	# 目标状态倍率；复制无名杀 get.effect 对低体力、少手牌目标的威胁放大思想。
	var status_multiplier: float = 1.0
	if bool(ai_profile.get("recover", false)) and int(target.get("hp", 0)) >= int(target.get("max_hp", 0)):
		return 0.0
	if bool(ai_profile.get("damage", false)):
		# 安全伤害值；异常或缺失数据至少按1点伤害评估。
		expected_damage_amount = maxi(expected_damage_amount, 1)
		if armor_definition != null:
			# 防具伤害上限；白银狮子等会把酒杀或其他高额伤害的实际收益压缩到规则上限。
			var damage_cap: int = maxi(armor_definition.get_ai_incoming_damage_cap(str(definition.get("nature", "normal"))), 0)
			if damage_cap > 0:
				expected_damage_amount = mini(expected_damage_amount, damage_cap)
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
	# 目标技能对来牌结局的修正；濒死自救等效果在此替换普通击杀预期，不改变实际规则或其他角色技能评分。
	result = _modify_incoming_card_effect_by_target_skills(authoritative_snapshot, actor_id, target_id, target, definition, ai_profile, target_result, expected_damage_amount, result)
	# 属性伤害连环传播；目标已横置时把同值伤害继续计入其他横置角色。
	if bool(ai_profile.get("nature_damage", false)) and bool(target.get("chained", false)):
		for chained_variant: Variant in authoritative_snapshot.get("players", []) as Array:
			# 其他横置存活角色；当前目标已经计算，不重复加入。
			var chained_player: Dictionary = chained_variant as Dictionary
			# 其他横置角色 ID；用于读取观察者态度。
			var chained_id: int = int(chained_player.get("player_id", -1))
			if chained_id == target_id or not bool(chained_player.get("alive", false)) or not bool(chained_player.get("chained", false)):
				continue
			result += _score_chained_damage_effect(authoritative_snapshot, actor_id, chained_id, definition, ai_profile, target_result, expected_damage_amount)
	# 追歼协同；己方佩拉公开标记的目标会在属性伤害评分中获得固定集火优先级，仍保留前面的护甲、响应与连环风险校验。
	# 补充：追歼现仅显示武将牌提示；提示条目连同来源ID会进入权威快照，因此属性伤害仍可获得协同集火评分而无需公开标记。
	if bool(ai_profile.get("nature_damage", false)):
		result += _score_teammate_zhuijian_priority(authoritative_snapshot, actor_id, target)
	return result


## 返回公开快照中的当前「主演」玩家 ID；没有任何角色携带主演条目时返回 -1。
## 主演是**公开状态**（载体是武将牌左上角提示条目），因此这里只读取公开快照，
## 不需要、也不允许任何隐藏信息通道；与【言灵】【游丝】的具体技能实现完全解耦。
func get_starring_player_id(authoritative_snapshot: Dictionary) -> int:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色公开快照；旧快照缺少条目字段时按非主演处理。
		var player: Dictionary = player_variant as Dictionary
		# 当前角色公开提示条目集合；键为稳定来源ID。
		var entries: Dictionary = player.get("character_corner_text_entries", {}) as Dictionary
		if entries.has(StarringRoleService.CORNER_ENTRY_ID):
			return int(player.get("player_id", -1))
	return -1


## 判断指定角色是否需要防备“本回合结束时手牌被当前主演获得”。
## 判据：主演存在、不是自己、且不是自己的明确队友。主演是自己人时不需要防备——牌被队友拿走不算损失。
## 明确队友的门槛复用【无懈可击】保护性响应的同一阈值，避免两处对“队友”给出不同标准。
func should_dump_hand_against_starring(authoritative_snapshot: Dictionary, player_id: int) -> bool:
	# 当前主演ID；场上没有主演时不存在“被主演获得手牌”的风险。
	var starring_player_id: int = get_starring_player_id(authoritative_snapshot)
	if starring_player_id < 0 or starring_player_id == player_id:
		return false
	return get_attitude(authoritative_snapshot, player_id, starring_player_id) < PROTECTIVE_NEGATION_ALLY_ATTITUDE_THRESHOLD


## 计算友方追歼公开标记带来的属性伤害集火收益；每个有效友方来源对应其实际可触发的一次+1伤害。
## 补充：当前从武将牌左上角提示的来源条目读取，不读取或依赖`public_marks`。
func _score_teammate_zhuijian_priority(authoritative_snapshot: Dictionary, actor_id: int, target: Dictionary) -> float:
	# 目标公开标记集合；仅使用网络快照已公开的数据，不读取任何技能实例私有字段。
	# 补充：追歼提示来源集合；键为`zhuijian:<source_player_id>`，值必须保留精确文本“追歼”。
	var character_corner_text_entries: Dictionary = target.get("character_corner_text_entries", {}) as Dictionary
	# 叠加后的集火收益；多名友方佩拉标记同一目标时按来源逐项累加。
	var priority_bonus: float = 0.0
	for mark_id_variant: Variant in character_corner_text_entries.keys():
		# 当前公开标记ID；只有追歼来源标记会参与属性伤害集火。
		var mark_id: String = str(mark_id_variant)
		if not mark_id.begins_with(ZHUIJIAN_CORNER_ENTRY_ID_PREFIX):
			continue
		# 当前公开标记数据；数量为零、异常来源或已失效数据都不提供评分。
		# 补充：当前条目不再存储标记数量；只有文本为“追歼”且来源ID为合法整数时才代表有效持续效果。
		# 当前提示条目数据；只读取序列化文本，不访问追歼技能实例的私有目标字段。
		var mark_data: Dictionary = character_corner_text_entries.get(mark_id_variant, {}) as Dictionary
		# 来源玩家ID文本；由稳定提示条目ID去除前缀得到，必须保持整数格式才能参与阵营判断。
		var source_player_id_text: String = mark_id.trim_prefix(ZHUIJIAN_CORNER_ENTRY_ID_PREFIX)
		if str(mark_data.get("text", "")) != "追歼" or not source_player_id_text.is_valid_int():
			continue
		# 标记施加者ID；仅当行动者将其视为友方时才形成协同集火意图。
		# 补充：当前数值来自提示条目ID，而非公开标记数据。
		var source_player_id: int = source_player_id_text.to_int()
		if source_player_id < 0 or get_attitude(authoritative_snapshot, actor_id, source_player_id) <= 0.0:
			continue
		priority_bonus += ZHUIJIAN_TEAMMATE_ATTRIBUTE_DAMAGE_PRIORITY_BONUS
	return priority_bonus


## 依次应用目标当前固有、模式、临时与局内获得技能的来牌估值钩子；相同技能ID只执行一次。
func _modify_incoming_card_effect_by_target_skills(authoritative_snapshot: Dictionary, actor_id: int, target_id: int, target: Dictionary, definition: Dictionary, ai_profile: Dictionary, target_result: float, expected_damage_amount: int, current_score: float) -> float:
	# 目标全部技能ID；先按武将声明顺序加入固有技能，再补充模式与运行时来源。
	var skill_ids: Array[String] = []
	# 行动者对目标的当前态度；正值表示友方卖血可转化为收益，负值表示敌方卖血会降低攻击价值。
	var attitude: float = get_attitude(authoritative_snapshot, actor_id, target_id)
	# 目标武将定义；未亮将或异常ID返回空技能数组。
	var character: Dictionary = GameDatabase.get_character(str(target.get("character_id", "")))
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		# 当前固有技能ID；空值与重复值不会进入估值链。
		var native_skill_id: String = str(skill_id_variant)
		if not native_skill_id.is_empty() and not skill_ids.has(native_skill_id):
			skill_ids.append(native_skill_id)
	for mode_skill_id_variant: Variant in target.get("mode_skill_ids", []) as Array:
		# 当前模式技能ID；与固有技能同名时只保留首次出现的一项估值钩子。
		var mode_skill_id: String = str(mode_skill_id_variant)
		if not mode_skill_id.is_empty() and not skill_ids.has(mode_skill_id):
			skill_ids.append(mode_skill_id)
	for runtime_skill_map_variant: Variant in [target.get("temporary_skills", {}), target.get("acquired_skills", {})]:
		# 当前运行时技能映射；键为稳定技能ID，值不参与静态AI钩子。
		var runtime_skill_map: Dictionary = runtime_skill_map_variant as Dictionary
		for skill_id_variant: Variant in runtime_skill_map.keys():
			# 当前运行时技能ID；已存在的固有同名技能不会重复执行。
			var runtime_skill_id: String = str(skill_id_variant)
			if not runtime_skill_id.is_empty() and not skill_ids.has(runtime_skill_id):
				skill_ids.append(runtime_skill_id)
	# 当前累计评分；每项技能只读取快照与上一项结果。
	var result: float = current_score
	for current_skill_id: String in skill_ids:
		# 无运行时状态的技能实例；只调用纯AI钩子，不安装时机或修改对局。
		var skill: SkillDefinition = GameDatabase.create_skill(current_skill_id)
		if skill == null:
			continue
		skill.bind(null, target_id)
		# 当前技能卖血价值；1点严格按1张牌的基础资源单位换算，只有伤害牌会兑现该收益。
		var sell_blood_value: float = skill.get_sell_blood_value()
		if bool(ai_profile.get("damage", false)) and sell_blood_value > 0.0 and not is_zero_approx(attitude):
			# 卖血方向修正；友方主动造成伤害获得正收益，敌方攻击则扣除同值收益，中立目标保持不变。
			result += sell_blood_value * CARD_RESOURCE_VALUE * (1.0 if attitude > 0.0 else -1.0)
		result = skill.modify_ai_incoming_card_effect(authoritative_snapshot, actor_id, target_id, definition, ai_profile, target_result, expected_damage_amount, result, self)
	return result


## 评估属性伤害经铁索传导到另一名横置角色的收益；统一纳入自身风险、濒危队友与预计击杀的身份奖惩。
## expected_damage_amount 与直接目标共享同一张属性【杀】的实际传导值，多目标和连环均不重复消耗该状态。
func _score_chained_damage_effect(authoritative_snapshot: Dictionary, actor_id: int, chained_id: int, definition: Dictionary, ai_profile: Dictionary, target_result: float, expected_damage_amount: int = 1) -> float:
	# 传导受击者快照；不存在或已离场的玩家不会参与当前属性伤害结算。
	var chained_player: Dictionary = get_player(authoritative_snapshot, chained_id)
	if chained_player.is_empty() or not bool(chained_player.get("alive", false)):
		return 0.0
	# 传导伤害状态倍率；低体力目标、防具与自身风险都在同一倍率上叠加。
	var status_multiplier: float = 1.0
	# 传导目标防具；无视防具武器与直接目标共用同一判断，白银狮子会再次限制该角色实际承受的伤害。
	var chained_armor_definition: CardDefinition = _get_effective_armor_definition(authoritative_snapshot, actor_id, chained_player, definition)
	if chained_armor_definition != null:
		# 传导目标伤害上限；0表示防具不封顶，正数时只降低该名角色的预期承伤。
		var chained_damage_cap: int = maxi(chained_armor_definition.get_ai_incoming_damage_cap(str(definition.get("nature", "normal"))), 0)
		if chained_damage_cap > 0:
			expected_damage_amount = mini(expected_damage_amount, chained_damage_cap)
		status_multiplier *= chained_armor_definition.get_ai_incoming_damage_multiplier(str(definition.get("nature", "normal")))
	# 行动者对传导受击者的态度；友方受伤为负收益，敌方受伤为正收益。
	var attitude: float = get_attitude(authoritative_snapshot, actor_id, chained_id)
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
	# 传导目标的自救或减伤技能与直接目标共用同一纯查询钩子，避免AI只在首个属性伤害目标上识别预期结局。
	result = _modify_incoming_card_effect_by_target_skills(authoritative_snapshot, actor_id, chained_id, chained_player, definition, ai_profile, target_result, expected_damage_amount, result)
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


## 返回指定玩家公开防具的当前卡牌定义；不存在公开防具、玩家缺失或防具ID未登记时返回 null。
## 该查询只读权威快照中公开的装备区，不窥探任何角色的隐藏手牌，供需要“目标能否承受某属性”的卡牌与技能复用。
func get_public_armor_definition(authoritative_snapshot: Dictionary, player_id: int) -> CardDefinition:
	# 当前玩家快照；缺失时没有任何防具能力可读。
	var player: Dictionary = get_player(authoritative_snapshot, player_id)
	if player.is_empty():
		return null
	# 公开防具快照；空槽返回空字典并自然跳过后继查询。
	var armor: Dictionary = (player.get("equipment", {}) as Dictionary).get("armor", {}) as Dictionary
	return GameDatabase.get_card_definition(str(armor.get("definition_id", "")))


## 返回指定玩家当前能够实际承受的属性伤害类型集合；AI 只读存活状态与公开防具的能力钩子。
## 判定口径：防具把该属性的预期伤害倍率压到0表示完全免除该属性伤害（例如未来的“免疫火焰伤害”类防具）；
## 当前项目没有任何防具或技能完全免除火焰/雷电伤害（【藤甲】放大火焰、白银狮子封顶），
## 因此存活在场角色的结果恒为 ["fire", "thunder"]，保留该查询是为了让新增属性免疫内容无需修改调用方即可生效。
func get_capable_damage_natures(authoritative_snapshot: Dictionary, player_id: int) -> Array[String]:
	# 当前玩家快照；死亡或离场角色不再构成伤害承受者。
	var player: Dictionary = get_player(authoritative_snapshot, player_id)
	if player.is_empty() or not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
		return []
	# 公开防具定义；无防具时两种属性伤害全部可承受。
	var armor_definition: CardDefinition = get_public_armor_definition(authoritative_snapshot, player_id)
	if armor_definition == null:
		return ["fire", "thunder"]
	# 可承受属性；逐属性读取防具声明的预期伤害倍率，0表示该属性伤害被完全免除。
	var capable_natures: Array[String] = []
	for nature: String in ["fire", "thunder"]:
		if armor_definition.get_ai_incoming_damage_multiplier(nature) > 0.0:
			capable_natures.append(nature)
	return capable_natures


## 返回指定玩家对某个伤害属性的公开防具倍率；1.0表示无修正，大于1表示该属性伤害被放大，0表示完全免除。
func get_incoming_damage_multiplier(authoritative_snapshot: Dictionary, player_id: int, nature: String) -> float:
	# 公开防具定义；无防具时按无修正处理。
	var armor_definition: CardDefinition = get_public_armor_definition(authoritative_snapshot, player_id)
	if armor_definition == null:
		return 1.0
	return maxf(armor_definition.get_ai_incoming_damage_multiplier(nature), 0.0)


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
	# 技能全权评分标志；由创建请求的技能在上下文中显式写入 true。
	# 语义：本请求的收益已由该技能自己的 score_ai_choice 完整表达，通用层不得再叠加任何牌值成本或语义修正，
	# 只需保留上方“未确认按0分”的取消基准。
	# 缺少该入口时，通用层“自己选中的牌即为自己支付的费用”口径会与技能自有收益重复计费：
	# 技能提出的正收益动作在确认时被同额牌值扣成负分，而取消恒为0分，AI 于是每次发动都在第一步取消，
	# 进而在整个出牌阶段反复进入同一技能，表现为回合停滞。
	# 该字段完全可选：只有显式声明它的请求才跳过通用评分，其余请求继续走下方原有全部分支。
	if bool(context.get("ai_choice_skill_scored", false)):
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
	# 技能显式声明的选牌语义；与上一条白名单同义，用于“选择种类由技能自定义、但选中即为收益”的请求。
	# 该字段完全可选：只有声明它的请求才反转符号方向，其余请求继续走下方“自己支付费用”的默认口径，
	# 因此既有技能与卡牌的选牌评分完全不受影响。缺少这一入口时，拆解他人区域的技能会被误判成自己付费，
	# 对任何候选都得到负分并一律取消，使该技能的选牌窗口永远无法完成。
	if str(context.get("ai_choice_card_semantics", "")) in ["discard_target", "steal_target", "harvest"]:
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
			return score_negation(authoritative_snapshot, actor_id, context)
		if response_patterns.has("tao") or response_patterns.has("jiu"):
			# 濒死救援必须结合身份关系、领袖存亡、内奸控场、自救和救援牌成本。
			var dying_target_id: int = int(context.get("target_id", actor_id))
			return identity_strategy.score_rescue(authoritative_snapshot, actor_id, dying_target_id, int(context.get("required_recover", 1)), selected_value)
		if choice_kind == "borrow_sword_response":
			# 借刀持刀者同时考虑保住武器和【杀】命中受害者的阵营收益。
			var victim_id: int = int(context.get("victim_id", -1))
			return RESPONSE_SURVIVAL_VALUE - get_attitude(authoritative_snapshot, actor_id, victim_id) - selected_value * CARD_COST_WEIGHT
		if choice_kind == "duel_response" and response_patterns.has("sha") and _should_decline_duel_response_against_zhidong(authoritative_snapshot, actor_id, context):
			# 与制动角色拼杀会继续累计原【决斗】的直接响应数；资源明显劣势且当前承伤不致命时主动停止交换。
			return ZHIDONG_DUEL_DECLINE_SCORE - selected_value * CARD_COST_WEIGHT
		# 当前响应保命收益；【闪】会根据真实伤害值和致命性加分，其他响应保持原有6.0分基准。
		var response_survival_value: float = RESPONSE_SURVIVAL_VALUE
		if response_patterns.has("shan"):
			if _should_decline_dodge_against_zhidong_forced_hit(authoritative_snapshot, actor_id, context):
				# 贯石斧具备足够支付资源时，【闪】只会增加制动伤害且无法阻止命中，因此优先保留。
				return ZHIDONG_FORCED_HIT_DODGE_DECLINE_SCORE - selected_value * CARD_COST_WEIGHT
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


## 判断AI是否应在资源劣势时停止与【制动】角色继续拼【杀】；当前累计伤害致命时仍优先响应自救。
func _should_decline_duel_response_against_zhidong(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary) -> bool:
	# 当前决斗对手；只有对手实际拥有制动时，继续打【杀】才会扩大其锁定增伤。
	var opponent_id: int = int(context.get("opponent_id", -1))
	# 当前决斗对手快照；用于检查技能、手牌与公开标记资源。
	var opponent: Dictionary = get_player(authoritative_snapshot, opponent_id)
	# 当前响应者快照；用于检查体力、护盾、手牌与已知【杀】数量。
	var responder: Dictionary = get_player(authoritative_snapshot, responder_id)
	if opponent.is_empty() or responder.is_empty() or not _snapshot_player_has_skill(opponent, "zhidong"):
		return false
	# 当前原【决斗】已经收到的直接响应数；现在放弃时预期伤害为基础1点加已有响应数。
	var current_direct_response_count: int = maxi(int(context.get("direct_response_count", 0)), 0)
	# 当前停止响应时的预计伤害；用于避免AI在致命伤害前错误放弃拼杀。
	var expected_damage_if_declined: int = DUEL_BASE_DAMAGE_AMOUNT + current_direct_response_count
	if int(responder.get("hp", 0)) + int(responder.get("shield", 0)) <= expected_damage_if_declined:
		return false
	# 响应者已知【杀】数量；仅剩当前一张或没有实体【杀】时视为拼杀资源偏少。
	var responder_sha_count: int = get_known_response_count(authoritative_snapshot, responder_id, "sha")
	if responder_sha_count > ZHIDONG_LOW_SHA_COUNT_THRESHOLD:
		return false
	# 响应者手牌数量；与对手公开手牌总数比较其继续拼杀的资源。
	var responder_hand_count: int = int(responder.get("hand_count", (responder.get("hand", []) as Array).size()))
	# 对手手牌数量；高于响应者时视为继续响应潜力更强。
	var opponent_hand_count: int = int(opponent.get("hand_count", (opponent.get("hand", []) as Array).size()))
	# 对手公开标记集合；只读取所有观察者都可见的“斗志”，不推测隐藏资源。
	var opponent_marks: Dictionary = opponent.get("public_marks", {}) as Dictionary
	# 对手“斗志”数量；达到阈值时同时保留百折与制动的后续威胁。
	var opponent_douzhi_count: int = int((opponent_marks.get("douzhi", {}) as Dictionary).get("count", 0))
	return opponent_hand_count > responder_hand_count or opponent_douzhi_count >= ZHIDONG_DOUZHI_THREAT_THRESHOLD


## 判断【闪】是否会被装备贯石斧强制命中并为【制动】额外增加1点伤害；仅在攻击者有足够公开支付资源时放弃。
func _should_decline_dodge_against_zhidong_forced_hit(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary) -> bool:
	# 【杀】攻击者；必须是敌对且实际拥有制动的角色。
	var attacker_id: int = int(context.get("actor_id", context.get("source_id", -1)))
	# 【杀】攻击者快照；用于读取技能、装备和可支付费用牌数。
	var attacker: Dictionary = get_player(authoritative_snapshot, attacker_id)
	if attacker.is_empty() or attacker_id == responder_id or get_attitude(authoritative_snapshot, responder_id, attacker_id) >= 0.0 or not _snapshot_player_has_skill(attacker, "zhidong"):
		return false
	# 攻击者公开装备区；用于取得武器并计算非武器装备费用。
	var equipment: Dictionary = attacker.get("equipment", {}) as Dictionary
	# 攻击者武器；当前强制命中实现由贯石斧提供，装备不存在时保持普通闪避策略。
	var weapon: Dictionary = equipment.get("weapon", {}) as Dictionary
	if str(weapon.get("definition_id", "")) != "guanshi":
		return false
	# 可支付牌数；贯石斧需要弃置两张其他牌，手牌加非武器装备不足时不能假定其一定强命。
	var available_cost_count: int = int(attacker.get("hand_count", (attacker.get("hand", []) as Array).size()))
	for slot_variant: Variant in equipment.keys():
		if str(slot_variant) != "weapon":
			available_cost_count += 1
	return available_cost_count >= GUANSHI_FORCE_HIT_COST_COUNT


## 判断玩家快照是否持有指定固有、模式、临时或局内获得技能；仅使用公开稳定ID，不读取运行时技能对象。
func _snapshot_player_has_skill(player: Dictionary, skill_id: String) -> bool:
	if player.is_empty() or skill_id.is_empty():
		return false
	# 当前武将固有技能；CharacterDefinition自动生成稳定技能ID数组。
	var character: Dictionary = GameDatabase.get_character(str(player.get("character_id", "")))
	if (character.get("skills", []) as Array).has(skill_id):
		return true
	if (player.get("mode_skill_ids", []) as Array).has(skill_id):
		return true
	return (player.get("temporary_skills", {}) as Dictionary).has(skill_id) or (player.get("acquired_skills", {}) as Dictionary).has(skill_id)


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
## 补充：本入口现计算连续净收益，正数使用、非正数保留，供同步判断与异步候选评分共同复用。
func score_negation(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary) -> float:
	# 当前锦囊目标；无有效目标时不浪费无懈可击。
	var target_id: int = int(context.get("target_id", -1))
	if target_id < 0:
		return -1.0
	# 当前锦囊 ID；对应卡牌文件声明 target_result、beneficial 等 AI 数据。
	var trick_id: String = str(context.get("trick_id", context.get("card_definition_id", "")))
	# 当前锦囊定义；未知锦囊按普通负面牌处理。
	var trick_definition: Dictionary = _get_cached_card_definition(trick_id)
	# 当前锦囊 AI 配置；目标结果正负可直接表达收益方向。
	var trick_ai: Dictionary = get_card_ai_profile(trick_definition)
	# 当前锦囊源码；允许状态型锦囊按目标的实时状态反转收益方向，避免无懈策略只读取静态配置。
	var trick_definition_instance: CardDefinition = GameDatabase.get_card_definition(trick_id)
	# 当前是否已被奇数张无懈抵消；下一张无懈会翻转该状态。
	var currently_negated: bool = bool(context.get("negated", false))
	# 当前锦囊来源；来源为正态度队友时，需要尊重其对自己或响应者的主动锦囊决策。
	var source_id: int = int(context.get("source_id", -1))
	# 队友在原锦囊尚未被抵消时对自身或响应者使用锦囊，响应者固定保留【无懈可击】；反无懈仍可恢复队友已经被抵消的锦囊。
	# 队友对响应者本人使用动态结果为负的锦囊时，首轮保留无懈并相信队友的战术意图；反无懈仍可恢复该锦囊生效。
	if not currently_negated and source_id >= 0 and source_id != responder_id and get_attitude(authoritative_snapshot, responder_id, source_id) > 0.0 and (target_id == source_id or target_id == responder_id):
		return -1.0
	# 原效果从响应者视角的通用收益；所有普通、群体与延时锦囊都读取各自 AI 配置和动态钩子，正数表示希望它生效，负数表示希望它失效。
	var effect_utility: float = _get_trick_effect_utility_for_negation(authoritative_snapshot, responder_id, target_id, context, trick_definition, trick_ai, trick_definition_instance)
	# 响应者对目标的当前态度；同一数值既判断本次响应属于保护还是攻击，也用于弱正态度门槛。
	var target_attitude: float = get_attitude(authoritative_snapshot, responder_id, target_id)
	# 本次响应是否在为目标的利益服务；首轮抵消有害锦囊与反无懈恢复有益锦囊都属于“替目标挡灾”。
	# 判定依据取自原效果的动态收益方向，因此延时锦囊的跳过阶段、普通锦囊的伤害与增益牌效共用同一口径。
	var protects_target: bool = effect_utility > 0.0 if currently_negated else effect_utility < 0.0
	# 保护性响应的明确队友门槛；目标不是响应者本人、态度为正但未达到该门槛时不为它消耗【无懈可击】。
	# 弱正态度只来自阵营平衡博弈或低置信度身份标记，替这类角色抵消锦囊属于负面收益：
	# 例如对敌人判定区的【乐不思蜀】【兵粮寸断】使用【无懈可击】只会令该锦囊失效，反而帮助敌方保留出牌与摸牌阶段。
	# 攻击性响应（抵消敌方收益锦囊、反无懈恢复敌方受损效果）态度为负，不进入本分支，仍由后续通用收益判断。
	if protects_target and target_id != responder_id and target_attitude > 0.0 and target_attitude < PROTECTIVE_NEGATION_ALLY_ATTITUDE_THRESHOLD:
		return -1.0
	# 下一张无懈造成的正向收益；首轮抵消负收益，反无懈则恢复正收益，并按统一态度尺度归一化。
	var negation_utility: float = (effect_utility if currently_negated else -effect_utility) / ATTITUDE_SCALE
	if negation_utility <= 0.0:
		return negation_utility
	# 【闪电】命中具有低概率且未命中会继续传递；无论首轮还是反无懈都大幅降低为其消耗资源的倾向。
	if trick_id == "shandian":
		negation_utility *= LIGHTNING_NEGATION_UTILITY_MULTIPLIER
	# 首轮保护目标本人时，若目标就是响应者且已拥有足量【杀】或【闪】，优先保留无懈应对不可直接响应的关键锦囊。
	if not currently_negated and target_id == responder_id and _has_sufficient_trick_response(authoritative_snapshot, responder_id, trick_id, trick_ai):
		negation_utility *= SUFFICIENT_RESPONSE_NEGATION_UTILITY_MULTIPLIER
	# AI 当前可见的实体【无懈可击】数量；技能提供的虚拟响应不会占用手牌，因此不应套用实体牌的资源成本与保留策略。
	var known_wuxie_count: int = get_known_response_count(authoritative_snapshot, responder_id, "wuxie")
	# 当前实体无懈的实际机会成本；重复持有时价值数组会自动降低，技能生成的虚拟无懈成本为零。
	var wuxie_cost: float = get_card_value_by_id("wuxie", authoritative_snapshot, responder_id) * NEGATION_CARD_COST_WEIGHT if known_wuxie_count > 0 else 0.0
	# 最后一张无懈的关键牌储备；反无懈不额外储备，否则会错误放弃恢复己方已经被抵消的关键收益。
	var reserve_value: float = 0.0
	if not currently_negated and known_wuxie_count == 1:
		# 当前锦囊是否属于最后一张无懈也应优先处理的关键牌效；该结果同时决定收益降权与储备额度。
		var is_key_trick: bool = _is_key_trick_for_negation(authoritative_snapshot, responder_id, target_id, trick_id, trick_ai)
		if not is_key_trick:
			negation_utility *= NON_KEY_TRICK_NEGATION_MULTIPLIER
		# 关键牌仍保留少量应对后续的空间，普通牌效则维持完整储备，防止AI为了低收益牌差耗尽唯一无懈。
		reserve_value = LAST_WUXIE_KEY_TRICK_RESERVE_VALUE if is_key_trick else LAST_WUXIE_RESERVE_VALUE
	return negation_utility - wuxie_cost - reserve_value


## 汇总单个锦囊对无懈响应的真实收益；统一读取静态目标结果、运行时状态修正和卡牌专属钩子，新增锦囊无需在无懈逻辑中硬编码牌名。
func _get_trick_effect_utility_for_negation(authoritative_snapshot: Dictionary, responder_id: int, target_id: int, context: Dictionary, trick_definition: Dictionary, trick_ai: Dictionary, trick_definition_instance: CardDefinition) -> float:
	# 锦囊对目标的基础结果；正值有利、负值有害，缺失配置时沿用卡牌的 ai_beneficial 声明。
	var target_result: float = float(trick_ai.get("target_result", 1.0 if bool(trick_definition.get("ai_beneficial", false)) else -1.0))
	if trick_definition_instance != null:
		target_result = trick_definition_instance.get_identity_observation_target_result(authoritative_snapshot, int(context.get("source_id", -1)), target_id, target_result)
	# 响应者对目标的态度；隐藏身份使用同一身份模型而不是直接按真实阵营二分。
	var attitude: float = get_attitude(authoritative_snapshot, responder_id, target_id)
	# 未经卡牌专属修正的目标收益；作为【借刀杀人】等复合锦囊钩子的统一输入尺度。
	var effect_utility: float = target_result * attitude
	if trick_definition_instance != null:
		effect_utility = trick_definition_instance.modify_ai_negation_effect_utility(authoritative_snapshot, responder_id, context, effect_utility, self)
	return effect_utility


## 判断当前无懈可击是否值得响应；所有调用方统一读取净收益，避免同步与异步响应采用不同策略。
func should_negate(authoritative_snapshot: Dictionary, responder_id: int, context: Dictionary) -> bool:
	return score_negation(authoritative_snapshot, responder_id, context) > 0.0


## 判断锦囊目标是否已经拥有足量直接响应资源；仅读取AI可见手牌与木牛“粮”，不会猜测其他角色隐藏牌。
func _has_sufficient_trick_response(authoritative_snapshot: Dictionary, responder_id: int, trick_id: String, trick_ai: Dictionary) -> bool:
	# 当前锦囊要求的响应模式；万箭使用【闪】，南蛮与决斗使用【杀】，其他锦囊不套用资源充足修正。
	var response_pattern: String = "shan" if bool(trick_ai.get("respond_shan", false)) else ("sha" if bool(trick_ai.get("respond_sha", false)) else "")
	if response_pattern.is_empty():
		return false
	# 足量响应牌阈值；决斗可能连续往返，至少两张【杀】才视为充足，其他锦囊一张即可完成本目标响应。
	var required_response_count: int = DUEL_SUFFICIENT_SHA_COUNT if trick_id == "juedou" else 1
	return get_known_response_count(authoritative_snapshot, responder_id, response_pattern) >= required_response_count


## 判断原锦囊是否值得为其动用最后一张【无懈可击】；阶段跳过、致命伤害、关键资源拆取与显著牌差均属于关键牌效。
func _is_key_trick_for_negation(authoritative_snapshot: Dictionary, responder_id: int, target_id: int, trick_id: String, trick_ai: Dictionary) -> bool:
	if trick_id == "shandian":
		return false
	if bool(trick_ai.get("skip_play", false)) or bool(trick_ai.get("skip_draw", false)):
		return true
	# 当前目标生存值；护盾与体力共同抵消即将到来的常规1点锦囊伤害。
	var target: Dictionary = get_player(authoritative_snapshot, target_id)
	if bool(trick_ai.get("damage", false)):
		# 锦囊预期伤害；缺失显式数值时按常规1点判断是否会立即进入濒死。
		var expected_damage: int = maxi(int(trick_ai.get("damage_amount", 1)), 1)
		if not target.is_empty() and int(target.get("hp", 0)) + int(target.get("shield", 0)) <= expected_damage:
			return true
	# 【过河拆桥】、【顺手牵羊】等通过卡牌定义的 effect_id 声明拆取或获得目标资源；兼容旧配置把该字段置于 AI 数据内的写法。
	# 只保护公开装备和响应者自己可见的高价值牌，不窥探其他角色隐藏手牌。
	var effect_id: String = str(_get_cached_card_definition(trick_id).get("effect_id", trick_ai.get("effect_id", "")))
	if effect_id == "discard_target" or effect_id == "steal_target" or bool(trick_ai.get("lose_card", false)):
		return _has_negation_worthy_target_resource(authoritative_snapshot, responder_id, target_id)
	# 目标获得多张牌会明显扩大敌我牌差；读取通用 draw 字段，覆盖所有具有相同收益结构的锦囊。
	if int(trick_ai.get("draw", 0)) >= KEY_NEGATION_CARD_GAIN_COUNT:
		return true
	# 敌方在濒危时的回复会直接关闭当前击杀窗口；普通回复不因最后一张无懈而被过度重视。
	return bool(trick_ai.get("recover", false)) and not target.is_empty() and int(target.get("hp", 0)) <= KEY_NEGATION_CRITICAL_HP_THRESHOLD


## 判断拆取目标是否拥有值得用最后一张【无懈可击】保护的资源；公共装备始终可见，手牌与木牛“粮”仅在目标为响应者本人时读取。
func _has_negation_worthy_target_resource(authoritative_snapshot: Dictionary, responder_id: int, target_id: int) -> bool:
	# 被拆取目标的公开状态；不存在时没有可保护资源。
	var target: Dictionary = get_player(authoritative_snapshot, target_id)
	if target.is_empty():
		return false
	# 公开装备集合；装备区信息对所有 AI 可见，逐张评估即可避免因低价值装备浪费最后一张无懈。
	var equipment: Dictionary = target.get("equipment", {}) as Dictionary
	for equipment_card_variant: Variant in equipment.values():
		# 当前公开装备实体；缺失定义时以中性值估算，保持评估器对扩展卡包的兼容性。
		var equipment_card: Dictionary = equipment_card_variant as Dictionary
		if get_card_value_by_id(str(equipment_card.get("definition_id", "")), authoritative_snapshot, target_id) >= KEY_NEGATION_RESOURCE_CARD_VALUE:
			return true
	# 非响应者的手牌与木牛“粮”不应被 AI 读取；只有自己可见资源才能作为自保依据。
	if target_id != responder_id:
		return false
	# 响应者自己的手牌；跳过即将打出的无懈本身，避免以“保护这张无懈”作为消耗它的循环理由。
	var own_hand: Array = target.get("hand", []) as Array
	for hand_card_variant: Variant in own_hand:
		# 当前可见手牌实体；牌名为空的异常实体不满足高价值判定。
		var hand_card: Dictionary = hand_card_variant as Dictionary
		var hand_card_id: String = str(hand_card.get("definition_id", ""))
		if hand_card_id != "wuxie" and get_card_value_by_id(hand_card_id, authoritative_snapshot, responder_id) >= KEY_NEGATION_RESOURCE_CARD_VALUE:
			return true
	# 响应者自己的木牛“粮”；其与手牌同属本人可见私有资源，纳入同一保护阈值。
	var wooden_ox_storage: Array = target.get("wooden_ox_storage", []) as Array
	for storage_card_variant: Variant in wooden_ox_storage:
		# 当前木牛“粮”实体；仅使用稳定卡牌定义ID评估保留价值。
		var storage_card: Dictionary = storage_card_variant as Dictionary
		if get_card_value_by_id(str(storage_card.get("definition_id", "")), authoritative_snapshot, responder_id) >= KEY_NEGATION_RESOURCE_CARD_VALUE:
			return true
	return false


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
## 返回持有者手牌、木牛“粮”或装备区中指定实体 UID 的保留价值；转化技能使用该接口评估材料机会成本。
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
	for equipment_variant: Variant in (owner.get("equipment", {}) as Dictionary).values():
		# 当前装备实体；装备作为技能材料时使用场面装备价值，而不是普通手牌保留价值。
		var equipment_card: Dictionary = equipment_variant as Dictionary
		if int(equipment_card.get("uid", -1)) != card_uid:
			continue
		# 当前装备定义与 AI 配置；优先读取 equip_value，缺失时回退普通 value 或未知牌2分。
		var equipment_definition: Dictionary = _get_cached_card_definition(str(equipment_card.get("definition_id", "")))
		# 当前装备 AI 配置；与正常换装估值保持同一静态数值来源。
		var equipment_ai_profile: Dictionary = get_card_ai_profile(equipment_definition)
		# 当前装备保留价值；数组 value 仅作异常回退，标准装备应填写单值 equip_value。
		var configured_equipment_value: Variant = equipment_ai_profile.get("equip_value", equipment_ai_profile.get("value", 2.0))
		if configured_equipment_value is Array:
			# 装备异常数组价值；读取首项保持确定性，空数组回退未知牌2分。
			var equipment_values: Array = configured_equipment_value as Array
			return float(equipment_values[0]) if not equipment_values.is_empty() else 2.0
		return float(configured_equipment_value)
	return 2.0


## 返回持有者手牌或木牛“粮”中指定实体 UID 的只读副本；技能AI可用它查询材料牌族、颜色和定义ID。
## 返回持有者手牌、木牛“粮”或装备区中指定实体 UID 的只读副本；技能 AI 可用它查询材料牌族、花色、颜色和定义 ID。
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
	for equipment_variant: Variant in (owner.get("equipment", {}) as Dictionary).values():
		# 当前公开装备实体；UID 匹配时返回副本，技能不得修改权威快照中的装备字典。
		var equipment_card: Dictionary = equipment_variant as Dictionary
		if int(equipment_card.get("uid", -1)) == card_uid:
			return equipment_card.duplicate(true)
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


## 统计观察者本方或敌对一方当前拥有的欢愉技总数；供技能 AI 比较双方欢愉技数量差。
##
## 本方包含观察者自己与态度非负的其他存活在场角色，敌对一方只统计态度为负的角色，
## 态度为0的中立角色不计入任何一方。武将未明置时按0计——AI不从隐藏信息推断技能构成。
func get_side_joy_skill_count(authoritative_snapshot: Dictionary, viewer_id: int, allied: bool) -> int:
	# 欢愉技总数结果。
	var total_count: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；死亡或离场角色不再提供欢愉技。
		var player: Dictionary = player_variant as Dictionary
		var other_id: int = int(player.get("player_id", -1))
		if other_id < 0 or not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		# 阵营筛选；观察者自己恒属于本方，其余角色按公开态度正负划分。
		if other_id == viewer_id:
			if not allied:
				continue
		else:
			# 当前角色对观察者的态度；正值友方，负值敌方。
			var attitude: float = get_attitude(authoritative_snapshot, viewer_id, other_id)
			if allied and attitude < 0.0:
				continue
			if not allied and attitude >= 0.0:
				continue
		total_count += _get_cached_character_joy_skill_count(str(player.get("character_id", "")))
	return total_count


## 返回某个已明置武将声明的欢愉技数量；结果按武将ID缓存，不重复深拷贝技能定义。
## 武将ID为空（未明置或对当前视角不可见）时返回0。
func _get_cached_character_joy_skill_count(character_id: String) -> int:
	if character_id.is_empty():
		return 0
	if not _character_joy_skill_count_cache.has(character_id):
		# 武将声明的技能ID列表；静态元数据，与对局状态无关。
		var character_definition: Dictionary = GameDatabase.get_character(character_id)
		# 欢愉技数量；只读取技能定义中的 joy_skill 标签，不读取正文文本。
		var joy_skill_count: int = 0
		for skill_id_variant: Variant in character_definition.get("skills", []) as Array:
			if bool(GameDatabase.get_skill(str(skill_id_variant)).get("joy_skill", false)):
				joy_skill_count += 1
		_character_joy_skill_count_cache[character_id] = joy_skill_count
	return int(_character_joy_skill_count_cache.get(character_id, 0))


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


## 返回指定卡牌是否为延时锦囊；供技能 AI 按标签判断弃置价值，不匹配具体牌名。
## 运行期类别一律读取卡牌定义的 type 与 delayed 字段，与核心的延时锦囊判定保持同一口径。
func is_delayed_trick_definition(definition_id: String) -> bool:
	# 卡牌静态定义；使用评估器私有缓存，避免同一决策内重复深拷贝。
	var definition: Dictionary = _get_cached_card_definition(definition_id)
	return str(definition.get("type", "")) == "trick" and bool(definition.get("delayed", false))


## 返回指定武将是否拥有至少一项欢愉技；供技能 AI 判断“令其发动欢愉技”是否成立。
## 静态元数据查询，未明置武将与空ID一律按没有欢愉技处理。
func character_has_joy_skill(character_id: String) -> bool:
	return _get_cached_character_joy_skill_count(character_id) > 0


## 返回评估器内部缓存的卡牌静态定义；空 ID 返回空字典，命中后不再向数据库申请新的深拷贝。
## 返回值是评估器私有只读数据，调用方只能查询字段，禁止修改字典或其嵌套数组。
func _get_cached_card_definition(card_id: String) -> Dictionary:
	if card_id.is_empty():
		return {}
	if not _card_definition_cache.has(card_id):
		_card_definition_cache[card_id] = GameDatabase.get_card(card_id)
	return _card_definition_cache.get(card_id, {}) as Dictionary
