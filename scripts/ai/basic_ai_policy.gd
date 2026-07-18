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


## 创建指定座次的基础策略；同一策略实例只服务一名玩家，但身份模型可由多个策略共享。
func _init(controlled_player_id: int, shared_identity_model: IdentityAIModel = null) -> void:
	player_id = controlled_player_id
	identity_model = shared_identity_model if shared_identity_model != null else IdentityAIModel.new()
	evaluator = NonameAIEvaluator.new(identity_model)


## 从核心提供的合法动作中选择一项；动作评分由卡牌 AI 数据、身份态度和技能文件钩子共同决定。
func choose_action(authoritative_snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	identity_model.synchronize(authoritative_snapshot)
	if legal_actions.is_empty():
		return {"action_type":"end_play", "actor_id":player_id}
	# 当前最佳动作；只有评分严格提高时替换，平分保持规则层稳定枚举顺序。
	var best_action: Dictionary = {}
	# 当前最高分；使用极小值确保首个合法动作可以成为比较基准。
	var best_score: float = -INF
	for action: Dictionary in legal_actions:
		# 当前合法动作的综合效用；具体牌与技能只能修正分数，不能绕过合法动作集合。
		var score: float = _score_action(authoritative_snapshot, action)
		if score > best_score:
			best_score = score
			best_action = action
	if best_action.is_empty() or best_score <= ACTION_ACCEPTANCE_THRESHOLD:
		return {"action_type":"end_play", "actor_id":player_id}
	return _normalize_action(best_action)


## 响应统一选择请求；逐项评分合法动作，可取消请求只有在正收益时才主动确认。
func choose_card_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary:
	identity_model.synchronize(authoritative_snapshot)
	if legal_actions.is_empty():
		return {}
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
	# 不允许取消的请求必须确认，选择代价最小或收益最高的合法动作。
	if not allow_cancel:
		return _normalize_action(best_confirmed_action if not best_confirmed_action.is_empty() else legal_actions[0])
	if not best_confirmed_action.is_empty() and best_confirmed_score > OPTIONAL_CHOICE_THRESHOLD:
		return _normalize_action(best_confirmed_action)
	if not pass_action.is_empty():
		return _normalize_action(pass_action)
	return _normalize_action(best_confirmed_action if not best_confirmed_action.is_empty() else legal_actions[0])


## 记录一张公开使用牌带来的身份暴露；只更新 AI 内部观察数据，不修改对局状态。
func observe_card_use(authoritative_snapshot: Dictionary, actor_id: int, card_definition: Dictionary, target_ids: Array[int], observer_id: int = -1) -> void:
	identity_model.observe_card_use(authoritative_snapshot, actor_id, card_definition, target_ids, observer_id)


## 判断一轮无懈可击是否应响应；协调器与正式并行响应流程可复用同一效用判断。
func should_negate(authoritative_snapshot: Dictionary, context: Dictionary) -> bool:
	return evaluator.should_negate(authoritative_snapshot, player_id, context)


## 从指定实体 UID 中返回保留价值最低的固定数量牌；装备虚拟响应材料仍由规则层再次校验。
func choose_low_value_card_uids(authoritative_snapshot: Dictionary, candidate_uids: Array[int], required_count: int) -> Array[int]:
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
	return result


## 依据无名杀式牌效与技能钩子计算出牌阶段动作价值。
func _score_action(authoritative_snapshot: Dictionary, action: Dictionary) -> float:
	# 动作类型；卡牌与技能分别进入独立内容钩子。
	var action_type: String = str(action.get("action_type", ""))
	if action_type == "use_skill":
		# 主动技能 ID；兼容合法动作顶层字段与标准 PlayerAction.payload 两种表示。
		var skill_id: String = _get_action_skill_id(action)
		# 技能静态实例；AI 钩子不得访问 host 或运行时变量，只读取序列化快照。
		var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
		if skill != null:
			skill.bind(null, player_id)
			return skill.score_ai_action(authoritative_snapshot, action, evaluator)
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
				return custom_definition.score_ai_play_phase_action(authoritative_snapshot, action, evaluator)
		return score
	# 当前卡牌源码定义；特殊牌可在自身文件内修正通用元数据无法完整表达的动作收益。
	var card_definition: CardDefinition = GameDatabase.get_card_definition(str(action.get("card_definition_id", "")))
	if card_definition != null:
		score = card_definition.modify_ai_action_score(authoritative_snapshot, action, score, evaluator)
	# 使用者武将技能；锁定技和被动牌效联动可在各自技能文件中修正当前卡牌评分。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, player_id)
	# 使用者武将定义；技能 ID 数组由 CharacterDefinition 自动生成。
	var character: Dictionary = GameDatabase.get_character(str(owner.get("character_id", "")))
	for skill_id_variant: Variant in character.get("skills", []) as Array:
		# 当前技能静态实例；占位技能保持基类空实现，不影响评分。
		var skill: SkillDefinition = GameDatabase.create_skill(str(skill_id_variant))
		if skill != null:
			skill.bind(null, player_id)
			score = skill.modify_ai_card_action_score(authoritative_snapshot, action, score, evaluator)
	return score


## 计算统一选择动作价值；先应用通用规则，再叠加对应技能或卡牌文件的专属 AI。
func _score_choice_action(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary) -> float:
	# 通用选择评分；负责强制弃牌、响应、生存与基础目标态度。
	var score: float = evaluator.score_choice_action(authoritative_snapshot, choice_request, action, player_id)
	# 请求上下文；稳定 skill_id、装备定义或卡牌定义用于定位内容脚本。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 创建该请求的技能 ID；技能配套 AI 必须写在同一技能 GD 文件中。
	var skill_id: String = str(context.get("skill_id", ""))
	if not skill_id.is_empty():
		# 技能静态实例；AI 评分只读参数，不能调用 activate 或选择请求端口。
		var skill: SkillDefinition = GameDatabase.create_skill(skill_id)
		if skill != null:
			# 请求上下文保存真实技能持有者；通常等于当前 AI，显式读取便于代替他人选择的后续机制扩展。
			var skill_owner_id: int = int(context.get("skill_owner_id", player_id))
			skill.bind(null, skill_owner_id)
			score += skill.score_ai_choice(authoritative_snapshot, choice_request, action, evaluator)
	# 创建该请求的卡牌或装备定义 ID；多个兼容字段按专属程度依次读取。
	var card_definition_id: String = str(context.get("equipment_definition_id", context.get("equipment_id", context.get("card_definition_id", ""))))
	if not card_definition_id.is_empty():
		# 卡牌静态定义；复杂牌效可覆盖 score_ai_choice 提供选牌与响应专属判断。
		var card_definition: CardDefinition = GameDatabase.get_card_definition(card_definition_id)
		if card_definition != null:
			score += card_definition.score_ai_choice(authoritative_snapshot, choice_request, action, evaluator)
	return score


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
