class_name BasicAIPolicy
extends RefCounted

## 无名杀式基础 AI 策略。通用层只组合身份态度、牌效价值与内容文件提供的 AI 钩子，不执行任何规则效果。

## 无正收益时结束出牌阶段的阈值；固定为0，确保 AI 不为纯负收益动作消耗资源。
const ACTION_ACCEPTANCE_THRESHOLD: float = 0.0

## 可取消选择请求的确认阈值；正分才主动确认，零分和负分优先保留资源并取消。
const OPTIONAL_CHOICE_THRESHOLD: float = 0.0

## AI 控制的玩家 ID；用于从快照中定位自身状态与身份关系。
var player_id: int = -1

## 当前策略使用的共享身份关系模型；记录无名杀式身份暴露度并计算动态阵营态度。
var identity_model: IdentityAIModel

## 当前策略使用的效用评估器；负责通用牌效、保留价值、响应与目标状态评分。
var evaluator: NonameAIEvaluator

## 已读取的卡牌静态定义缓存；策略只保存数据库返回的独立副本，用于复用防具拦截与出牌顺序查询。
## 缓存值只允许读取，运行时无需动态修改，任何动作评分都不得向定义内写入临时数据。
var _card_definition_cache: Dictionary = {}

## 已读取的武将静态定义缓存；同一策略服务固定玩家，缓存可避免每个合法动作重复深拷贝相同技能列表。
## 武将定义只在数据库初始化时建立，运行时无需动态修改，调用方不得写入缓存内容。
var _character_definition_cache: Dictionary = {}

## 当前一次出牌决策复用的武将技能 AI 修正器；数组只在合法动作评分期间存在，决策结束后立即清空。
var _decision_card_modifier_skills: Array[SkillDefinition] = []

## 当前一次出牌决策按技能 ID 复用的技能实例；同一技能的多个目标组合共享纯只读 AI 钩子，决策结束后立即清空。
var _decision_skill_instances: Dictionary = {}

## 当前是否已经准备出牌动作评分上下文；默认 false，允许专项测试直接调用评分函数时自动建立一次上下文。
var _action_scoring_context_prepared: bool = false

## 当前一次选择决策复用的技能 AI 修正器；没有技能上下文时为 null，选择完成后立即释放引用。
var _decision_choice_skill: SkillDefinition = null

## 当前是否已经准备选择动作评分上下文；默认 false，防止直接评分路径遗漏技能 AI 钩子。
var _choice_scoring_context_prepared: bool = false


## 创建指定座次的基础策略；同一策略实例只服务一名玩家，但身份模型可由多个策略共享。
func _init(controlled_player_id: int, shared_identity_model: IdentityAIModel = null) -> void:
	player_id = controlled_player_id
	identity_model = shared_identity_model if shared_identity_model != null else IdentityAIModel.new()
	evaluator = NonameAIEvaluator.new(identity_model)


## 从核心提供的合法动作中选择一项；动作评分由卡牌 AI 数据、身份态度和技能文件钩子共同决定。
func choose_action(authoritative_snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	if legal_actions.is_empty():
		identity_model.end_evaluation()
		identity_model.synchronize(authoritative_snapshot)
		return {"action_type":"end_play", "actor_id":player_id}
	identity_model.begin_evaluation(authoritative_snapshot)
	# 当前合法动作上下文；卡牌专属AI据此识别阶段次数、目标与防具校验后仍可执行的真实后续动作。
	evaluator.set_current_legal_actions(legal_actions)
	_prepare_action_scoring_context(authoritative_snapshot)
	# 首轮动作评分；连续行动牌可据此比较“先准备再行动”与直接行动的完整收益。
	var preliminary_scored_actions: Array[Dictionary] = []
	for action: Dictionary in legal_actions:
		# 当前动作的完整直接评分；包含卡牌、装备和已安装技能的全部只读修正。
		var score: float = _score_action(authoritative_snapshot, action)
		preliminary_scored_actions.append({"action":action.duplicate(true), "score":score})
	# 首轮评分上下文；只有在此之后，连续行动牌才允许读取其他合法动作的真实完整分数。
	evaluator.set_current_legal_action_scores(preliminary_scored_actions)
	# 当前最佳动作；只有评分严格提高时替换，平分保持规则层稳定枚举顺序。
	var best_action: Dictionary = {}
	# 当前最高分；使用极小值确保首个合法动作可以成为比较基准。
	var best_score: float = -INF
	for action: Dictionary in legal_actions:
		# 当前合法动作的综合效用；具体牌与技能只能修正分数，不能绕过合法动作集合。
		# 连续行动牌会基于首轮完整评分修正自身链路收益，仍只能在同一合法动作集合中竞争。
		var score: float = _score_action(authoritative_snapshot, action)
		if score > best_score:
			best_score = score
			best_action = action
	# 最终动作；先完成评分再统一清理单次决策缓存，避免返回分支遗留技能实例引用。
	var result: Dictionary = {"action_type":"end_play", "actor_id":player_id}
	if not best_action.is_empty() and best_score > ACTION_ACCEPTANCE_THRESHOLD:
		result = _normalize_action(best_action)
	_clear_action_scoring_context()
	evaluator.clear_current_legal_actions()
	identity_model.end_evaluation()
	return result


## 响应统一选择请求；逐项评分合法动作，可取消请求只有在正收益时才主动确认。
func choose_card_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	if legal_actions.is_empty():
		identity_model.end_evaluation()
		identity_model.synchronize(authoritative_snapshot)
		return {}
	identity_model.begin_evaluation(authoritative_snapshot)
	_prepare_choice_scoring_context(choice_request)
	# 当前请求是否允许取消；允许取消时即使 min_count 大于0，也可用 confirmed=false 放弃整次选择。
	var allow_cancel: bool = bool(choice_request.get("allow_cancel", false))
	# 当前最佳确认动作；取消动作单独保存，避免零分平局误消耗牌。
	var best_confirmed_action: Dictionary = {}
	# 当前确认动作最高分；从负无穷开始允许强制请求选择代价最小的负收益动作。
	var best_confirmed_score: float = -INF
	# 当前合法取消动作；不存在时强制请求使用评分最高的确认动作。
	var pass_action: Dictionary = {}
	for action: Dictionary in legal_actions:
		# 当前动作负载；confirmed=false 是标准取消语义。
		var payload: Dictionary = action.get("payload", {}) as Dictionary
		if not bool(payload.get("confirmed", false)):
			pass_action = action
			continue
		# 当前选择动作综合评分；技能与卡牌专属 AI 均通过请求上下文自动定位。
		var score: float = _score_choice_action(authoritative_snapshot, choice_request, action)
		if score > best_confirmed_score:
			best_confirmed_score = score
			best_confirmed_action = action
	# 最终选择动作；统一出口保证单次选择技能实例不会跨请求保留。
	var result: Dictionary
	# 不允许取消的请求必须确认，选择代价最小或收益最高的合法动作。
	if not allow_cancel:
		result = _normalize_action(best_confirmed_action if not best_confirmed_action.is_empty() else legal_actions[0])
	elif not best_confirmed_action.is_empty() and best_confirmed_score > OPTIONAL_CHOICE_THRESHOLD:
		result = _normalize_action(best_confirmed_action)
	elif not pass_action.is_empty():
		result = _normalize_action(pass_action)
	else:
		result = _normalize_action(best_confirmed_action if not best_confirmed_action.is_empty() else legal_actions[0])
	_clear_choice_scoring_context()
	identity_model.end_evaluation()
	return result


## 记录一张公开使用牌带来的身份暴露；只更新 AI 内部观察数据，不修改对局状态。
func observe_card_use(authoritative_snapshot: Dictionary, actor_id: int, card_definition: Dictionary, target_ids: Array[int], observer_id: int = -1) -> void:
	identity_model.observe_card_use(authoritative_snapshot, actor_id, card_definition, target_ids, observer_id)


## 判断一轮无懈可击是否应响应；协调器与正式并行响应流程可复用同一效用判断。
func should_negate(authoritative_snapshot: Dictionary, context: Dictionary) -> bool:
	identity_model.begin_evaluation(authoritative_snapshot)
	# 当前无懈响应结论；先保存结果再结束评估，避免返回后仍保留权威快照引用。
	var result: bool = evaluator.should_negate(authoritative_snapshot, player_id, context)
	identity_model.end_evaluation()
	return result


## 从指定实体 UID 中返回保留价值最低的固定数量牌；装备虚拟响应材料仍由规则层再次校验。
func choose_low_value_card_uids(authoritative_snapshot: Dictionary, candidate_uids: Array[int], required_count: int) -> Array[int]:
	identity_model.begin_evaluation(authoritative_snapshot)
	# 可排序候选副本；不修改控制器提供的权威候选顺序。
	var sorted_uids: Array[int] = candidate_uids.duplicate()
	sorted_uids.sort_custom(func(first_uid: int, second_uid: int) -> bool:
		# 第一张牌保留价值；数值更低时排在前方。
		var first_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, player_id, first_uid)
		# 第二张牌保留价值；相同价值按 UID 保持确定性。
		var second_value: float = evaluator.get_owned_card_value_by_uid(authoritative_snapshot, player_id, second_uid)
		return first_uid < second_uid if is_equal_approx(first_value, second_value) else first_value < second_value
	)
	# 结果数组；数量不会超过候选总数。
	var result: Array[int] = []
	for index: int in range(mini(maxi(required_count, 0), sorted_uids.size())):
		result.append(sorted_uids[index])
	identity_model.end_evaluation()
	return result


## 依据无名杀式牌效与技能钩子计算出牌阶段动作价值。
func _score_action(authoritative_snapshot: Dictionary, action: Dictionary) -> float:
	if not _action_scoring_context_prepared:
		_prepare_action_scoring_context(authoritative_snapshot)
	# 动作类型；卡牌与技能分别进入独立内容钩子。
	var action_type: String = str(action.get("action_type", ""))
	if action_type == "use_skill":
		# 主动技能 ID；兼容合法动作顶层字段与标准 PlayerAction.payload 两种表示。
		var skill_id: String = _get_action_skill_id(action)
		# 技能静态实例；AI 钩子不得访问 host 或运行时变量，只读取序列化快照。
		var skill: SkillDefinition = _get_decision_skill_instance(skill_id)
		if skill != null:
			skill.bind(null, player_id)
			# 技能自身评分；负责材料、体力等发动成本以及技能独有的额外收益。
			var skill_score: float = skill.score_ai_action(authoritative_snapshot, action, evaluator)
			# 技能生成的虚拟用牌代理；转化牌必须继续经过卡牌本体和持有者其他技能的完整评分链。
			var virtual_card_action: Dictionary = skill.build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
			if not virtual_card_action.is_empty():
				# 技能评分中已经包含的通用虚拟牌收益；只追加完整评分相对该基础值的差额，避免重复计算目标牌效。
				var base_virtual_score: float = evaluator.score_action(authoritative_snapshot, virtual_card_action, player_id)
				# 完整虚拟牌收益；包含卡牌专属修正、被动技能联动以及防具完全拦截判断。
				var complete_virtual_score: float = _score_ai_virtual_card_action(authoritative_snapshot, virtual_card_action)
				skill_score += complete_virtual_score - base_virtual_score
			return skill_score
		return 0.0
	# 通用卡牌或重铸基础评分；具体卡牌数据来自自身 GD 文件的 ai 字典。
	var score: float = evaluator.score_action(authoritative_snapshot, action, player_id)
	if action_type != "use_card":
		# 自定义装备动作来源；木牛流马、丈八蛇矛等动作由对应卡牌文件自行评分。
		var custom_card_id: String = str(action.get("ai_card_definition_id", ""))
		if not custom_card_id.is_empty():
			# 自定义动作所属卡牌定义；内容文件负责补充专属评分，规则合法性仍由核心保证。
			var custom_definition: CardDefinition = GameDatabase.get_card_definition(custom_card_id)
			if custom_definition != null:
				# 自定义动作本体评分；装备材料成本仍由对应卡牌文件独立维护。
				var custom_score: float = custom_definition.score_ai_play_phase_action(authoritative_snapshot, action, evaluator)
				# 自定义动作生成的虚拟用牌代理；丈八蛇矛等转化装备由此获得持有者技能联动收益。
				var custom_virtual_action: Dictionary = custom_definition.build_ai_virtual_card_action(authoritative_snapshot, action, evaluator)
				if not custom_virtual_action.is_empty():
					# 自定义评分中已经包含的通用虚拟牌收益；仅追加完整链路产生的差额。
					var custom_base_virtual_score: float = evaluator.score_action(authoritative_snapshot, custom_virtual_action, player_id)
					# 自定义虚拟牌完整收益；与主动技能转化使用相同的卡牌和被动技能评分入口。
					var custom_complete_virtual_score: float = _score_ai_virtual_card_action(authoritative_snapshot, custom_virtual_action)
					custom_score += custom_complete_virtual_score - custom_base_virtual_score
				return custom_score
		return score
	# 当前卡牌源码定义；特殊牌可在自身文件内修正通用元数据无法完整表达的动作收益。
	var card_definition: CardDefinition = GameDatabase.get_card_definition(str(action.get("card_definition_id", "")))
	if card_definition != null:
		score = card_definition.modify_ai_action_score(authoritative_snapshot, action, score, evaluator)
	# 使用者武将技能；锁定技和被动牌效联动可在各自技能文件中修正当前卡牌评分。
	for skill: SkillDefinition in _decision_card_modifier_skills:
		score = skill.modify_ai_card_action_score(authoritative_snapshot, action, score, evaluator)
	# 防具完全拦截所有目标时，先保留已计算的卡牌与技能联动收益，再排除纯出牌顺序带来的伪正分。
	if _is_slash_fully_blocked_by_armor(authoritative_snapshot, action):
		# 当前逻辑牌定义；未知牌没有顺序偏好，按0处理以避免异常动作获得豁免。
		var action_definition: Dictionary = _get_cached_card_definition(str(action.get("card_definition_id", "")))
		# 当前牌AI配置；order只用于收益接近时排序，不能单独构成消耗无效牌的理由。
		var action_ai_profile: Dictionary = evaluator.get_card_ai_profile(action_definition)
		# 纯顺序分；移除后剩余分数才表示防具拦截之外的真实卡牌或技能收益。
		var action_order_score: float = float(action_ai_profile.get("order", 0.0)) * NonameAIEvaluator.ORDER_WEIGHT
		if score - action_order_score <= ACTION_ACCEPTANCE_THRESHOLD:
			return -INF
	return score


## 计算一项已经由规则确认合法的虚拟用牌完整收益；只补齐卡牌专属与持有者技能修正，不执行任何牌效。
func _score_ai_virtual_card_action(authoritative_snapshot: Dictionary, action: Dictionary) -> float:
	# 通用虚拟牌收益；包含定义自身的顺序、目标效果与属性伤害估值。
	var score: float = evaluator.score_action(authoritative_snapshot, action, player_id)
	if str(action.get("action_type", "")) != "use_card":
		return score
	# 当前虚拟牌源码；复杂卡牌仍可通过自身钩子修正动作收益。
	var card_definition: CardDefinition = GameDatabase.get_card_definition(str(action.get("card_definition_id", "")))
	if card_definition != null:
		score = card_definition.modify_ai_action_score(authoritative_snapshot, action, score, evaluator)
	# 使用者全部有效技能；转化牌实际使用后会触发的被动联动必须与实体牌使用保持一致。
	for skill: SkillDefinition in _decision_card_modifier_skills:
		score = skill.modify_ai_card_action_score(authoritative_snapshot, action, score, evaluator)
	# 防具完全拦截时移除纯出牌顺序造成的伪收益；仍允许星火等独立技能收益保留该动作。
	if _is_slash_fully_blocked_by_armor(authoritative_snapshot, action):
		# 当前虚拟牌静态定义；用于读取只承担排序作用的order字段。
		var action_definition: Dictionary = _get_cached_card_definition(str(action.get("card_definition_id", "")))
		# 当前虚拟牌AI配置；缺失order时按0处理。
		var action_ai_profile: Dictionary = evaluator.get_card_ai_profile(action_definition)
		# 纯顺序分；扣除后没有正向联动表示该虚拟牌不值得使用。
		var action_order_score: float = float(action_ai_profile.get("order", 0.0)) * NonameAIEvaluator.ORDER_WEIGHT
		if score - action_order_score <= ACTION_ACCEPTANCE_THRESHOLD:
			return -INF
	return score


## 判断一项【杀】动作是否会被所有已选目标的防具完全拦截；只读取公开装备和自身完整手牌快照，不修改实体牌或规则状态。
## 同一查询也覆盖防具明确声明完全拦截的伤害类群体锦囊。
func _is_slash_fully_blocked_by_armor(authoritative_snapshot: Dictionary, action: Dictionary) -> bool:
	# 当前逻辑牌定义；只有共享 slash 牌族才需要检查防具的【杀】拦截钩子。
	# 防具声明拦截的伤害类群体锦囊也复用本入口，具体牌名由防具源码判断。
	var definition: Dictionary = _get_cached_card_definition(str(action.get("card_definition_id", "")))
	# 当前是否为共享【杀】牌族；决定颜色、属性与无视防具武器的检查方式。
	var is_slash: bool = str(definition.get("effect_id", "")) == "slash"
	# 当前卡牌定义ID；群体锦囊防具钩子按该稳定值判断。
	var card_definition_id: String = str(definition.get("id", ""))
	if not is_slash and not bool((definition.get("ai", {}) as Dictionary).get("damage", false)):
		return false
	# 当前使用实体 UID；虚拟或丢失实体没有稳定花色，不能错误套用黑色【杀】防具规则。
	# 只按伤害属性判断的防具仍可在颜色未知时完成预判。
	var card_uid: int = int(action.get("card_uid", -1))
	# 当前使用实体快照；仅【杀】的颜色型防具需要读取该字段。
	var used_card: Dictionary = _find_owned_card(authoritative_snapshot, player_id, card_uid)
	# 当前动作负载；虚拟用牌会在此显式保留真实材料颜色。
	var action_payload: Dictionary = action.get("payload", {}) as Dictionary
	# 当前实体或材料颜色；显式虚拟颜色优先，空值再回退实体牌快照。
	var card_color: String = str(action.get("card_color", action_payload.get("card_color", used_card.get("color", ""))))
	# 当前使用者公开武器；声明无视防具时不应把合法攻击误判为无效。
	var actor: Dictionary = evaluator.get_player(authoritative_snapshot, player_id)
	# 当前武器快照；只在【杀】动作中参与防具忽略判断。
	var weapon: Dictionary = (actor.get("equipment", {}) as Dictionary).get("weapon", {}) as Dictionary
	# 当前武器源码；由装备自身声明规则能力。
	var weapon_definition: CardDefinition = GameDatabase.get_card_definition(str(weapon.get("definition_id", "")))
	if is_slash and weapon_definition != null and weapon_definition.slash_ignores_armor():
		return false
	# 当前实际目标；标准合法动作始终已写入完整数组，多目标【杀】只有全部被拦截时才放弃动作。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.is_empty() and not is_slash:
		# 群体牌合法动作通常不携带目标数组；按定义目标模式从快照展开实际存活目标。
		target_ids = evaluator.get_effective_target_ids(authoritative_snapshot, player_id, definition, target_ids)
	if target_ids.is_empty():
		return false
	for target_id_variant: Variant in target_ids:
		# 当前目标公开防具；无防具或不拦截本颜色【杀】时，本动作仍有可结算目标。
		var target: Dictionary = evaluator.get_player(authoritative_snapshot, int(target_id_variant))
		var armor: Dictionary = (target.get("equipment", {}) as Dictionary).get("armor", {}) as Dictionary
		var armor_definition: CardDefinition = GameDatabase.get_card_definition(str(armor.get("definition_id", "")))
		if armor_definition == null:
			return false
		if is_slash and not armor_definition.blocks_slash_by_color(card_color, str(definition.get("nature", "normal"))):
			return false
		if not is_slash and not armor_definition.blocks_aoe(card_definition_id):
			return false
	return true


## 从 AI 权威快照中按 UID 返回持有者的手牌或木牛“粮”；找不到时返回空字典，调用方不得猜测其花色。
func _find_owned_card(authoritative_snapshot: Dictionary, owner_id: int, card_uid: int) -> Dictionary:
	# 当前持有者快照；AI 决策快照包含自身完整私有牌面，异常缺失时安全返回空字典。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_id)
	for zone_name: String in ["hand", "wooden_ox_storage"]:
		for card_variant: Variant in owner.get(zone_name, []) as Array:
			# 当前实体牌快照；稳定 UID 命中后返回深拷贝，避免策略改写原快照对象。
			var card: Dictionary = card_variant as Dictionary
			if int(card.get("uid", -1)) == card_uid:
				return card.duplicate(true)
	return {}


## 计算统一选择动作价值；先应用通用规则，再叠加对应技能或卡牌文件的专属 AI。
func _score_choice_action(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary) -> float:
	if not _choice_scoring_context_prepared:
		_prepare_choice_scoring_context(choice_request)
	# 通用选择评分；负责强制弃牌、响应、生存与基础目标态度。
	var score: float = evaluator.score_choice_action(authoritative_snapshot, choice_request, action, player_id)
	# 请求上下文；稳定 skill_id、装备定义或卡牌定义用于定位内容脚本。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 创建该请求的技能 ID；技能配套 AI 必须写在同一技能 GD 文件中。
	var skill_id: String = str(context.get("skill_id", ""))
	if not skill_id.is_empty():
		# 技能静态实例；AI 评分只读参数，不能调用 activate 或选择请求端口。
		var skill: SkillDefinition = _decision_choice_skill
		if skill != null:
			score += skill.score_ai_choice(authoritative_snapshot, choice_request, action, evaluator)
	# 创建该请求的卡牌或装备定义 ID；多个兼容字段按专属程度依次读取。
	var card_definition_id: String = str(context.get("equipment_definition_id", context.get("equipment_id", context.get("card_definition_id", ""))))
	if not card_definition_id.is_empty():
		# 卡牌静态定义；复杂牌效可覆盖 score_ai_choice 提供选牌与响应专属判断。
		var card_definition: CardDefinition = GameDatabase.get_card_definition(card_definition_id)
		if card_definition != null:
			score += card_definition.score_ai_choice(authoritative_snapshot, choice_request, action, evaluator)
	return score


## 为一组合法出牌动作建立共享评分上下文；武将技能实例仅执行只读 AI 钩子，不连接时机或保存规则状态。
func _prepare_action_scoring_context(authoritative_snapshot: Dictionary) -> void:
	_clear_action_scoring_context()
	_action_scoring_context_prepared = true
	# 使用者武将技能；锁定技和被动牌效联动可在各自技能文件中修正当前卡牌评分。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, player_id)
	# 使用者武将定义；技能 ID 数组由 CharacterDefinition 自动生成。
	var character: Dictionary = _get_cached_character_definition(str(owner.get("character_id", "")))
	# 本次全部技能ID；固有、模式、临时与局内永久获得技能都应参与卡牌联动估值。
	var all_skill_ids: Array[String] = []
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		all_skill_ids.append(str(skill_id_variant))
	for mode_skill_id_variant: Variant in owner.get("mode_skill_ids", []) as Array:
		# 当前模式技能ID；与固有技能重复时只创建一个只读评分实例。
		var mode_skill_id: String = str(mode_skill_id_variant)
		if not mode_skill_id.is_empty() and not all_skill_ids.has(mode_skill_id):
			all_skill_ids.append(mode_skill_id)
	for runtime_skill_map_variant: Variant in [owner.get("temporary_skills", {}), owner.get("acquired_skills", {})]:
		# 当前运行时技能映射；键为稳定技能ID，值只保存持续或次数状态。
		var runtime_skill_map: Dictionary = runtime_skill_map_variant as Dictionary
		for runtime_skill_id_variant: Variant in runtime_skill_map.keys():
			# 当前运行时技能ID；按快照字典顺序追加且去重。
			var runtime_skill_id: String = str(runtime_skill_id_variant)
			if not runtime_skill_id.is_empty() and not all_skill_ids.has(runtime_skill_id):
				all_skill_ids.append(runtime_skill_id)
	for skill_id: String in all_skill_ids:
		# 当前技能 ID；用于让主动动作与卡牌修正复用同一纯评估实例。
		var resolved_skill_id: String = skill_id
		# 当前技能静态实例；占位技能保持基类空实现，不影响评分。
		var skill: SkillDefinition = GameDatabase.create_skill(resolved_skill_id)
		# 领袖技只在使用者身份确为领袖时参与牌效联动估值；非领袖不会借用武将静态列表中的领袖能力。
		# 非锁定技失效时只保留完整锁定技的通用牌效修正；半锁定技后段通过时机独立结算，不把非锁定前段误加入动作评分。
		var skill_effect_available: bool = skill != null and (not bool(owner.get("non_locked_skills_disabled", false)) or skill.lock)
		if skill_effect_available and (not skill.leader_skill or str(owner.get("identity", "")) == "leader"):
			skill.bind(null, player_id)
			_decision_card_modifier_skills.append(skill)
			_decision_skill_instances[resolved_skill_id] = skill


## 清理一次出牌决策的技能评分上下文；静态元数据缓存保留，运行时技能实例不跨决策复用。
func _clear_action_scoring_context() -> void:
	_decision_card_modifier_skills.clear()
	_decision_skill_instances.clear()
	_action_scoring_context_prepared = false


## 返回当前决策中指定技能的共享 AI 实例；不属于武将修正器的主动技能在首次评分时按需创建。
func _get_decision_skill_instance(skill_id: String) -> SkillDefinition:
	if skill_id.is_empty():
		return null
	# 已存在的单次决策技能实例；同一技能的不同目标组合直接复用该引用。
	var cached_skill: SkillDefinition = _decision_skill_instances.get(skill_id) as SkillDefinition
	if cached_skill != null:
		return cached_skill
	# 首次遇到的主动技能实例；只绑定固定 AI 玩家，不连接规则宿主。
	var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
	if skill != null:
		skill.bind(null, player_id)
		_decision_skill_instances[skill_id] = skill
	return skill


## 为一组统一选择动作建立共享技能评分上下文；同一请求的材料或目标组合复用一个纯 AI 技能实例。
func _prepare_choice_scoring_context(choice_request: Dictionary) -> void:
	_clear_choice_scoring_context()
	_choice_scoring_context_prepared = true
	# 请求上下文；稳定 skill_id 用于创建本次请求唯一的技能评分器。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 创建该请求的技能 ID；空值表示本请求只使用通用或卡牌 AI。
	var skill_id: String = str(context.get("skill_id", ""))
	if skill_id.is_empty():
		return
	# 技能静态实例；AI 评分只读参数，不能调用 activate 或选择请求端口。
	_decision_choice_skill = GameDatabase.create_skill(skill_id)
	if _decision_choice_skill != null:
		# 请求上下文保存真实技能持有者；通常等于当前 AI，显式读取便于代替他人选择的后续机制扩展。
		var skill_owner_id: int = int(context.get("skill_owner_id", player_id))
		_decision_choice_skill.bind(null, skill_owner_id)


## 清理一次统一选择决策的技能评分上下文；确保请求取消、完成或替换后不保留旧技能引用。
func _clear_choice_scoring_context() -> void:
	_decision_choice_skill = null
	_choice_scoring_context_prepared = false


## 返回策略内部缓存的卡牌静态定义；空 ID 安全返回空字典，缓存内容只能用于只读评分。
func _get_cached_card_definition(card_id: String) -> Dictionary:
	if card_id.is_empty():
		return {}
	if not _card_definition_cache.has(card_id):
		_card_definition_cache[card_id] = GameDatabase.get_card(card_id)
	return _card_definition_cache.get(card_id, {}) as Dictionary


## 返回策略内部缓存的武将静态定义；同一武将只从数据库取得一次独立副本，调用方不得修改返回值。
func _get_cached_character_definition(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not _character_definition_cache.has(character_id):
		_character_definition_cache[character_id] = GameDatabase.get_character(character_id)
	return _character_definition_cache.get(character_id, {}) as Dictionary


## 返回主动技能动作中的稳定技能 ID；顶层兼容字段只用于旧合法动作，最终动作统一写入 payload。
func _get_action_skill_id(action: Dictionary) -> String:
	# 动作负载；标准提交入口只读取 payload.skill_id。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	return str(payload.get("skill_id", action.get("skill_id", "")))


## 规范化策略返回动作；主动技能自动把顶层 skill_id 写入标准 payload，其他字段保持深拷贝。
func _normalize_action(action: Dictionary) -> Dictionary:
	# 可写动作副本；不会修改核心传入的合法动作列表。
	var result: Dictionary = action.duplicate(true)
	if str(result.get("action_type", "")) == "use_skill":
		# 标准动作负载；保留技能追加的其他可序列化参数。
		var payload: Dictionary = (result.get("payload", {}) as Dictionary).duplicate(true)
		payload["skill_id"] = str(payload.get("skill_id", result.get("skill_id", "")))
		result["payload"] = payload
	return result
