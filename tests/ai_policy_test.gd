extends Node

## 无名杀式 AI 无头回归。验证身份暴露、牌目标、无懈、技能钩子、主动技能负载与低价值弃牌选择。
## 自动身份标记同时覆盖目标证据权重、忠反误操作、内奸终结状态与公开响应牌观察。

## 测试使用的共享身份模型；多项断言复用同一观察状态。
var _identity_model: IdentityAIModel = IdentityAIModel.new()

## 测试使用的领袖基础策略；稳定玩家 ID 为0。
var _policy: BasicAIPolicy


## 执行全部 AI 数据与决策断言；任一失败立即以非零状态退出。
func _ready() -> void:
	_policy = BasicAIPolicy.new(0, _identity_model)
	if not _test_all_cards_have_ai_profiles():
		return
	if not _test_scoring_cache_lifecycle():
		return
	if not _test_identity_exposure():
		return
	if not _test_identity_target_evidence():
		return
	if not _test_dynamic_card_identity_observation():
		return
	if not _test_identity_role_consistency():
		return
	if not _test_renegade_identity_mark_finalization():
		return
	if not _test_wuxie_identity_observation():
		return
	if not _test_dying_rescue_identity_observation():
		return
	if not _test_public_skill_identity_observation():
		return
	if not _test_hidden_identity_strategy_visibility():
		return
	if not _test_identity_rescue_strategy():
		return
	if not _test_renegade_leader_survival():
		return
	if not _test_renegade_balance_strategy():
		return
	if not _test_response_and_threat_strategy():
		return
	if not _test_hostile_card_target():
		return
	if not _test_tiesuo_prefers_recast_when_use_value_is_low():
		return
	if not _test_quanlei_slash_material_priority():
		return
	if not _test_conversion_virtual_card_skill_synergy():
		return
	if not _test_xingqi_always_activates():
		return
	if not _test_xingluo_requires_other_target():
		return
	if not _test_sushang_guinaifen_skill_ai():
		return
	if not _test_renwang_shield_black_slash():
		return
	if not _test_friendly_chain_damage_response():
		return
	if not _test_wine_slash_defense():
		return
	if not _test_wine_action_value_and_baiyin_damage_cap():
		return
	if not _test_chained_damage_team_risk():
		return
	if not _test_fire_attack_failed_target_memory():
		return
	if not _test_wuxie_decision():
		return
	if not _test_skill_confirmation():
		return
	if not _test_leader_skill_confirmation():
		return
	if not _test_linghang_recast_choice():
		return
	if not _test_active_skill_payload():
		return
	if not _test_peila_lingke_skill_ai():
		return
	if not _test_zhuijian_teammate_attribute_priority():
		return
	if not _test_low_value_discard():
		return
	print("AI_POLICY_PASS cards=%d" % GameDatabase.cards.size())
	get_tree().quit(0)


## 验证全部卡牌文件都声明本地 AI 配置，新增内容不能继续依赖中央卡牌 ID 白名单。
func _test_all_cards_have_ai_profiles() -> bool:
	for card_id_variant: Variant in GameDatabase.cards.keys():
		# 当前卡牌 ID；用于输出精确失败信息。
		var card_id: String = str(card_id_variant)
		# 当前卡牌 AI 配置；空字典表示内容文件没有提供基础评分数据。
		var ai_profile: Dictionary = GameDatabase.get_card(card_id).get("ai", {}) as Dictionary
		if ai_profile.is_empty():
			return _fail("missing_card_ai=%s" % card_id)
	return true


## 验证静态定义在重复评分中只缓存一次，并且单次决策技能实例会复用且在决策后释放。
func _test_scoring_cache_lifecycle() -> bool:
	# 独立完整快照；希儿的两项技能可同时验证武将定义缓存与决策技能实例集合。
	var snapshot: Dictionary = _build_snapshot(true)
	# 独立评估器；避免其他用例已经填充的缓存掩盖首次评分行为。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 标准【杀】动作；重复评分必须得到相同结果且不继续增加静态卡牌缓存种类。
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 第一次评分；会按需缓存【杀】和当前已知响应牌定义。
	var first_score: float = evaluator.score_action(snapshot, slash_action, 0)
	# 首次评分后的缓存条目数；必须大于0才能证明用例确实经过缓存入口。
	var first_cache_size: int = (evaluator.get("_card_definition_cache") as Dictionary).size()
	# 第二次评分；相同快照与动作不得改变分数或扩张静态定义缓存。
	var second_score: float = evaluator.score_action(snapshot, slash_action, 0)
	# 重复评分后的缓存条目数；应与首次完全一致。
	var second_cache_size: int = (evaluator.get("_card_definition_cache") as Dictionary).size()
	if first_cache_size <= 0 or second_cache_size != first_cache_size or not is_equal_approx(first_score, second_score):
		return _fail("static_definition_cache first=%d second=%d scores=%.3f/%.3f" % [first_cache_size, second_cache_size, first_score, second_score])
	# 独立策略；手动准备一次评分上下文以检查同一技能 ID 返回的对象身份。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	policy.call("_prepare_action_scoring_context", snapshot)
	# 当前武将修正技能集合；希儿至少配置【再现】与【蝶影】，不能为空。
	var modifier_skills: Array[SkillDefinition] = policy.get("_decision_card_modifier_skills") as Array[SkillDefinition]
	# 当前技能实例索引；每个修正器应按稳定技能 ID 登记一次。
	var skill_instances: Dictionary = policy.get("_decision_skill_instances") as Dictionary
	if modifier_skills.is_empty() or skill_instances.size() != modifier_skills.size():
		return _fail("decision_skill_prepare modifiers=%d instances=%d" % [modifier_skills.size(), skill_instances.size()])
	# 首个修正器；再次按 ID 查询时必须返回同一 RefCounted 实例，而不是重新创建脚本对象。
	var first_skill: SkillDefinition = modifier_skills[0]
	# 同 ID 查询结果；对象实例 ID 用于确定引用身份，不依赖脚本字典相等比较。
	var reused_skill: SkillDefinition = policy.call("_get_decision_skill_instance", first_skill.get_id()) as SkillDefinition
	if reused_skill == null or reused_skill.get_instance_id() != first_skill.get_instance_id():
		return _fail("decision_skill_not_reused:%s" % first_skill.get_id())
	policy.call("_clear_action_scoring_context")
	if bool(policy.get("_action_scoring_context_prepared")) or not (policy.get("_decision_card_modifier_skills") as Array).is_empty() or not (policy.get("_decision_skill_instances") as Dictionary).is_empty():
		return _fail("decision_skill_context_not_cleared")
	# 独立索引模型；正式 choose_action() 应在两轮候选评分之间共享同一份玩家查询索引。
	var indexed_identity_model: IdentityAIModel = IdentityAIModel.new()
	# 独立索引策略；固定控制0号领袖，避免共享模型的既有诊断计数影响断言。
	var indexed_policy: BasicAIPolicy = BasicAIPolicy.new(0, indexed_identity_model)
	# 决策前索引构建次数；一次 choose_action() 无论评分多少轮都只能增加1。
	var index_build_count_before: int = int(indexed_identity_model.get("_evaluation_index_build_count"))
	# 决策前线性玩家查询次数；评分期间全部查询都应命中单次决策索引。
	var uncached_lookup_count_before: int = int(indexed_identity_model.get("_uncached_player_lookup_count"))
	indexed_policy.choose_action(snapshot, [slash_action])
	if int(indexed_identity_model.get("_evaluation_index_build_count")) != index_build_count_before + 1 \
			or int(indexed_identity_model.get("_uncached_player_lookup_count")) != uncached_lookup_count_before \
			or bool(indexed_identity_model.get("_evaluation_context_active")) \
			or not (indexed_identity_model.get("_evaluation_player_index") as Dictionary).is_empty():
		return _fail("decision_player_index builds=%d lookups=%d active=%s retained=%d" % [int(indexed_identity_model.get("_evaluation_index_build_count")), int(indexed_identity_model.get("_uncached_player_lookup_count")), bool(indexed_identity_model.get("_evaluation_context_active")), (indexed_identity_model.get("_evaluation_player_index") as Dictionary).size()])
	return true


## 验证隐藏反贼在未行动时接近中立，公开使用目标牌后身份态度按暴露度转为敌对。
func _test_identity_exposure() -> bool:
	_identity_model.reset()
	# 隐藏身份快照；领袖身份公开，反贼真实身份仅权威 AI 可见。
	var snapshot: Dictionary = _build_snapshot(false)
	# 行动前态度；目标暴露度为0时应接近中立。
	var before_attitude: float = _identity_model.get_attitude(snapshot, 0, 1)
	# 反贼公开对领袖使用【杀】；单目标行为提高其身份暴露度。
	_identity_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [0])
	# 行动后态度；领袖对真实反贼的负态度应按新增暴露度显现。
	var after_attitude: float = _identity_model.get_attitude(snapshot, 0, 1)
	if not is_zero_approx(before_attitude) or after_attitude >= -0.5 or _identity_model.get_identity_mark(1) != "rebel" or _identity_model.get_exposure(1) <= 0.0:
		return _fail("identity_exposure before=%.2f after=%.2f" % [before_attitude, after_attitude])
	# 隐藏忠臣公开帮助领袖；正面目标行为应形成 loyalist 标记。
	_identity_model.observe_card_use(snapshot, 2, GameDatabase.get_card("tao"), [0])
	if _identity_model.get_identity_mark(2) != "loyalist" or _identity_model.get_exposure(2) <= 0.0:
		return _fail("identity_loyalist_mark mark=%s exposure=%.2f" % [_identity_model.get_identity_mark(2), _identity_model.get_exposure(2)])
	return true


## 验证尚未暴露的隐藏目标不能充当阵营锚点，目标公开后相同行为才形成可靠身份线索。
func _test_identity_target_evidence() -> bool:
	# 独立身份模型；该测试需要从全部隐藏身份的零暴露状态开始。
	var identity_model: IdentityAIModel = IdentityAIModel.new()
	# 五人隐藏身份快照；反贼1与忠臣2均尚未通过公开行为暴露。
	var snapshot: Dictionary = _build_strategy_snapshot(false)
	# 反贼攻击未暴露忠臣；观察者不能偷看目标真实身份并据此给行动者贴反贼标签。
	identity_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [2])
	if not is_zero_approx(identity_model.get_exposure(1)) or not identity_model.get_identity_mark(1).is_empty():
		return _fail("hidden_target_leaked mark=%s exposure=%.2f" % [identity_model.get_identity_mark(1), identity_model.get_exposure(1)])
	# 公开忠臣身份；同步后该目标具备完整1.0证据权重。
	(snapshot.get("players", []) as Array)[2]["identity_revealed"] = true
	# 反贼再次攻击已公开忠臣；相同行为现在应形成反贼标记。
	identity_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [2])
	if identity_model.get_identity_mark(1) != "rebel" or identity_model.get_exposure(1) <= 0.0:
		return _fail("revealed_target_not_used mark=%s exposure=%.2f" % [identity_model.get_identity_mark(1), identity_model.get_exposure(1)])
	# 忠臣弱暴露模型；官方逻辑会对其作用于完全未知目标的行为提供固定0.1补偿，但不读取目标身份。
	var loyalist_unknown_model: IdentityAIModel = IdentityAIModel.new()
	# 重新隐藏目标身份；该行为只验证忠臣自身的弱暴露特例。
	(snapshot.get("players", []) as Array)[2]["identity_revealed"] = false
	loyalist_unknown_model.observe_card_use(snapshot, 2, GameDatabase.get_card("sha"), [1])
	if loyalist_unknown_model.get_identity_mark(2) != "loyalist" or not is_equal_approx(loyalist_unknown_model.get_exposure(2), 0.1):
		return _fail("loyalist_unknown_compensation mark=%s exposure=%.2f" % [loyalist_unknown_model.get_identity_mark(2), loyalist_unknown_model.get_exposure(2)])
	return true


## 验证卡牌源码可按目标当前状态提供动态身份牌效，避免【铁索连环】横置与重置被识别为同一方向。
func _test_dynamic_card_identity_observation() -> bool:
	# 五人隐藏身份快照；目标忠臣2公开后可作为完整阵营证据。
	var snapshot: Dictionary = _build_strategy_snapshot(false)
	(snapshot.get("players", []) as Array)[2]["identity_revealed"] = true
	# 【铁索连环】源码；动态身份观察配置由内容文件生成，不在 AI 模型识别卡牌 ID。
	var chain_definition: CardDefinition = GameDatabase.get_card_definition("tiesuo")
	# 未横置目标配置；反贼1施加横置为负面行为，应形成反贼标记。
	var chain_profile: Dictionary = chain_definition.get_identity_observation_ai_profile(snapshot, 1, [2])
	var chain_model: IdentityAIModel = IdentityAIModel.new()
	chain_model.observe_card_use(snapshot, 1, {"ai":chain_profile}, [2])
	if chain_model.get_identity_mark(1) != "rebel":
		return _fail("chain_apply_mark=%s" % chain_model.get_identity_mark(1))
	# 已横置目标配置；相同反贼解除忠臣横置属于帮助行为，不应产生正暴露或错误反贼标记。
	(snapshot.get("players", []) as Array)[2]["chained"] = true
	var unchain_profile: Dictionary = chain_definition.get_identity_observation_ai_profile(snapshot, 1, [2])
	var unchain_model: IdentityAIModel = IdentityAIModel.new()
	unchain_model.observe_card_use(snapshot, 1, {"ai":unchain_profile}, [2])
	if not is_zero_approx(unchain_model.get_exposure(1)) or not unchain_model.get_identity_mark(1).is_empty():
		return _fail("chain_remove_mark=%s exposure=%.2f" % [unchain_model.get_identity_mark(1), unchain_model.get_exposure(1)])
	# 满体力回复配置；【桃园结义】对满体力领袖的动态结果必须为0，不凭无实际效果的回复标记忠臣。
	(snapshot.get("players", []) as Array)[2]["identity_revealed"] = false
	var recovery_definition: CardDefinition = GameDatabase.get_card_definition("taoyuan")
	var recovery_profile: Dictionary = recovery_definition.get_identity_observation_ai_profile(snapshot, 2, [0])
	var recovery_model: IdentityAIModel = IdentityAIModel.new()
	recovery_model.observe_card_use(snapshot, 2, {"ai":recovery_profile}, [0])
	if not is_zero_approx(recovery_model.get_exposure(2)) or not recovery_model.get_identity_mark(2).is_empty():
		return _fail("full_health_recovery_mark=%s exposure=%.2f" % [recovery_model.get_identity_mark(2), recovery_model.get_exposure(2)])
	return true


## 验证忠臣或反贼违背自身阵营利益的误操作不会被直接贴成相反身份，本地玩家本人也不会自动显示猜测。
func _test_identity_role_consistency() -> bool:
	# 忠臣误操作使用的独立身份模型；避免后续正确行为受其他测试状态影响。
	var loyalist_model: IdentityAIModel = IdentityAIModel.new()
	# 三人隐藏身份快照；领袖公开，可作为完整阵营证据目标。
	var snapshot: Dictionary = _build_snapshot(false)
	# 忠臣攻击领袖；该行为不符合忠臣真实收益，因此不能被错误标记为反贼。
	loyalist_model.observe_card_use(snapshot, 2, GameDatabase.get_card("sha"), [0])
	if not is_zero_approx(loyalist_model.get_exposure(2)) or not loyalist_model.get_identity_mark(2).is_empty():
		return _fail("loyalist_mistake_marked mark=%s exposure=%.2f" % [loyalist_model.get_identity_mark(2), loyalist_model.get_exposure(2)])
	# 反贼伪装使用的独立身份模型；确保帮助领袖不会直接贴成忠臣。
	var rebel_model: IdentityAIModel = IdentityAIModel.new()
	# 反贼帮助领袖；行为不符合反贼真实收益，不应产生正暴露或忠臣标记。
	rebel_model.observe_card_use(snapshot, 1, GameDatabase.get_card("tao"), [0])
	if not is_zero_approx(rebel_model.get_exposure(1)) or not rebel_model.get_identity_mark(1).is_empty():
		return _fail("rebel_camouflage_marked mark=%s exposure=%.2f" % [rebel_model.get_identity_mark(1), rebel_model.get_exposure(1)])
	# 本地观察者模型；玩家1攻击领袖会产生暴露，但不应给观察者本人生成自动徽记。
	var local_observer_model: IdentityAIModel = IdentityAIModel.new()
	local_observer_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [0], 1)
	if local_observer_model.get_exposure(1) <= 0.0 or not local_observer_model.get_identity_mark(1).is_empty():
		return _fail("local_actor_auto_marked mark=%s exposure=%.2f" % [local_observer_model.get_identity_mark(1), local_observer_model.get_exposure(1)])
	# 其他角色观察模型；玩家0观察玩家1时，单目标0.2暴露应按官方规则整体乘2成为0.4。
	var remote_actor_model: IdentityAIModel = IdentityAIModel.new()
	remote_actor_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [0], 0)
	if remote_actor_model.get_identity_mark(1) != "rebel" or not is_equal_approx(remote_actor_model.get_exposure(1), 0.4):
		return _fail("remote_actor_multiplier mark=%s exposure=%.2f" % [remote_actor_model.get_identity_mark(1), remote_actor_model.get_exposure(1)])
	return true


## 验证内奸可暂时显示忠反倾向，但出现一次相反行为后会清除并永久终结自动猜测。
func _test_renegade_identity_mark_finalization() -> bool:
	# 独立身份模型；内奸终结状态必须从空标记开始验证。
	var identity_model: IdentityAIModel = IdentityAIModel.new()
	# 五人隐藏身份快照；玩家3为内奸，场上仍有两名存活反贼。
	var snapshot: Dictionary = _build_strategy_snapshot(false)
	# 内奸帮助领袖；从领袖阵营视角为正收益，形成暂时忠臣倾向。
	identity_model.observe_card_use(snapshot, 3, GameDatabase.get_card("tao"), [0])
	if identity_model.get_identity_mark(3) != "loyalist":
		return _fail("renegade_loyal_mark=%s" % identity_model.get_identity_mark(3))
	# 内奸随后攻击领袖；与既有忠臣倾向相反，应清空标记并进入 finished 状态。
	identity_model.observe_card_use(snapshot, 3, GameDatabase.get_card("sha"), [0])
	if not identity_model.get_identity_mark(3).is_empty():
		return _fail("renegade_contradiction_not_cleared=%s" % identity_model.get_identity_mark(3))
	# 终结后再次帮助领袖；不得重新在忠反之间来回翻转。
	identity_model.observe_card_use(snapshot, 3, GameDatabase.get_card("tao"), [0])
	if not identity_model.get_identity_mark(3).is_empty():
		return _fail("renegade_finished_reopened=%s" % identity_model.get_identity_mark(3))
	return true


## 验证成功打出的无懈可击进入身份观察，同时过滤原使用者未暴露与目标本人自保两类弱证据。
func _test_wuxie_identity_observation() -> bool:
	# 独立身份模型；用于验证领袖公开来源下的无懈响应暴露。
	var identity_model: IdentityAIModel = IdentityAIModel.new()
	# 三人隐藏身份快照；领袖0公开，反贼1响应，忠臣2为原锦囊目标。
	var snapshot: Dictionary = _build_snapshot(false)
	# 无懈响应上下文；negated=true 表示本张无懈刚刚阻止了原正面锦囊效果。
	var response_context: Dictionary = {"source_id":0, "target_id":2, "trick_id":"wuzhong", "negated":true}
	identity_model.observe_card_response(snapshot, 1, GameDatabase.get_card("wuxie"), GameDatabase.get_card("wuzhong"), response_context)
	if identity_model.get_identity_mark(1) != "rebel" or identity_model.get_exposure(1) < 0.2:
		return _fail("wuxie_response_not_observed mark=%s exposure=%.2f" % [identity_model.get_identity_mark(1), identity_model.get_exposure(1)])
	# 目标本人自保使用无懈的独立模型；这种行为不应作为忠反身份线索。
	var self_response_model: IdentityAIModel = IdentityAIModel.new()
	self_response_model.observe_card_response(snapshot, 2, GameDatabase.get_card("wuxie"), GameDatabase.get_card("wuzhong"), response_context)
	if not is_zero_approx(self_response_model.get_exposure(2)) or not self_response_model.get_identity_mark(2).is_empty():
		return _fail("self_wuxie_marked mark=%s exposure=%.2f" % [self_response_model.get_identity_mark(2), self_response_model.get_exposure(2)])
	# 未暴露来源响应上下文；玩家1尚无公开证据，忠臣2的无懈不应借真实身份生成标记。
	var hidden_source_context: Dictionary = {"source_id":1, "target_id":0, "trick_id":"lebu", "negated":true}
	var hidden_source_model: IdentityAIModel = IdentityAIModel.new()
	hidden_source_model.observe_card_response(snapshot, 2, GameDatabase.get_card("wuxie"), GameDatabase.get_card("lebu"), hidden_source_context)
	if not is_zero_approx(hidden_source_model.get_exposure(2)) or not hidden_source_model.get_identity_mark(2).is_empty():
		return _fail("hidden_source_wuxie_marked mark=%s exposure=%.2f" % [hidden_source_model.get_identity_mark(2), hidden_source_model.get_exposure(2)])
	return true


## 验证成功救援其他角色的【桃】按实际濒死目标形成身份线索，而【酒】式本人自救不会自动标记。
func _test_dying_rescue_identity_observation() -> bool:
	# 无内置策略的协调器；对应控制器在救援卡牌效果成功后使用的公开行为入口。
	var coordinator: AICoordinator = AICoordinator.new()
	# 三人隐藏身份快照；忠臣2救援公开领袖0，应形成稳定忠臣标记。
	var snapshot: Dictionary = _build_snapshot(false)
	# 【桃】AI 配置；正向 target_result=2.0由卡牌源码声明，不在控制器硬编码救援牌名。
	var peach_ai_profile: Dictionary = GameDatabase.get_card_definition("tao").get_ai_profile()
	coordinator.observe_public_behavior(snapshot, 2, peach_ai_profile, [0])
	if coordinator.get_identity_mark(2) != "loyalist":
		return _fail("dying_peach_mark=%s" % coordinator.get_identity_mark(2))
	# 本人自救模型；唯一目标为行动者本人，即使效果为正也不得生成自动身份猜测。
	var self_rescue_coordinator: AICoordinator = AICoordinator.new()
	self_rescue_coordinator.observe_public_behavior(snapshot, 1, peach_ai_profile, [1])
	if not self_rescue_coordinator.get_identity_mark(1).is_empty():
		return _fail("dying_self_rescue_mark=%s" % self_rescue_coordinator.get_identity_mark(1))
	coordinator.free()
	self_rescue_coordinator.free()
	return true


## 验证卡牌之外的公开技能行为通过协调器进入同一身份模型，且不依赖具体技能 ID 白名单。
func _test_public_skill_identity_observation() -> bool:
	# 无内置策略的协调器；自动标记仍应直接使用共享身份模型记录技能行为。
	var coordinator: AICoordinator = AICoordinator.new()
	# 三人隐藏身份快照；领袖公开，可作为伤害或帮助技能的完整阵营参照。
	var snapshot: Dictionary = _build_snapshot(false)
	# 反贼对领袖造成负面技能效果；通用 target_result 数据应形成反贼标记。
	coordinator.observe_public_behavior(snapshot, 1, {"target_result":-1.0}, [0])
	if coordinator.get_identity_mark(1) != "rebel":
		return _fail("public_skill_rebel_mark=%s" % coordinator.get_identity_mark(1))
	# 忠臣对领袖提供正面技能效果；同一入口应形成忠臣标记。
	coordinator.observe_public_behavior(snapshot, 2, {"target_result":1.0}, [0])
	if coordinator.get_identity_mark(2) != "loyalist":
		return _fail("public_skill_loyalist_mark=%s" % coordinator.get_identity_mark(2))
	coordinator.free()
	return true


## 验证战略层不会偷看隐藏身份，只有目标产生明确行为标记后才获得阵营集火修正。
func _test_hidden_identity_strategy_visibility() -> bool:
	# 独立身份模型；避免上一项测试的行为标记影响隐藏身份断言。
	var identity_model: IdentityAIModel = IdentityAIModel.new()
	# 独立效用评估器；共享当前测试身份模型。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(identity_model)
	# 隐藏身份快照；反贼1尚未产生任何可观察阵营行为。
	var snapshot: Dictionary = _build_snapshot(false)
	# 领袖对隐藏目标使用【杀】的动作；标记出现前不应获得敌方战略奖励。
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 行为暴露前评分；仅包含卡牌顺序与资源成本，目标牌效态度接近中立。
	var score_before_mark: float = evaluator.score_action(snapshot, slash_action, 0)
	if identity_model.get_perceived_identity(snapshot, 1) != "unknown":
		return _fail("hidden_identity_visible_before_behavior")
	# 隐藏反贼攻击领袖；该公开行为形成 rebel 标记。
	identity_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [0])
	# 行为暴露后评分；敌对态度与反贼威胁集火修正均可正常生效。
	var score_after_mark: float = evaluator.score_action(snapshot, slash_action, 0)
	if identity_model.get_perceived_identity(snapshot, 1) != "rebel" or score_after_mark <= score_before_mark:
		return _fail("hidden_identity_strategy before=%.2f after=%.2f perceived=%s" % [score_before_mark, score_after_mark, identity_model.get_perceived_identity(snapshot, 1)])
	return true


## 验证标准身份救援：忠臣救领袖、反贼不救领袖、多人局内奸保护领袖且角色积极自救。
func _test_identity_rescue_strategy() -> bool:
	# 全身份公开的五人快照；公开状态用于单独验证救援阵营规则。
	var snapshot: Dictionary = _build_strategy_snapshot(true)
	# 身份战略评估器；救援测试直接读取其标准救援分数。
	var strategy: IdentityStrategyEvaluator = IdentityStrategyEvaluator.new(IdentityAIModel.new())
	# 忠臣救领袖评分；应显著高于零并愿意消耗一张9分【桃】。
	var loyalist_score: float = strategy.score_rescue(snapshot, 2, 0, 1, 9.0)
	# 反贼救领袖评分；应为负数并选择取消响应。
	var rebel_score: float = strategy.score_rescue(snapshot, 1, 0, 1, 9.0)
	# 多人局内奸救领袖评分；领袖提前死亡会破坏内奸胜利路径，因此应为正数。
	var renegade_score: float = strategy.score_rescue(snapshot, 3, 0, 1, 9.0)
	# 角色自救评分；死亡风险下应积极使用自己的救援牌。
	var self_rescue_score: float = strategy.score_rescue(snapshot, 1, 1, 1, 9.0)
	if loyalist_score <= 0.0 or rebel_score >= 0.0 or renegade_score <= 0.0 or self_rescue_score <= 0.0:
		return _fail("identity_rescue loyal=%.2f rebel=%.2f renegade=%.2f self=%.2f" % [loyalist_score, rebel_score, renegade_score, self_rescue_score])
	# 普通友方基准救援；目标有手牌、即将行动且判定区为空。
	var ally_snapshot: Dictionary = _build_strategy_snapshot(true)
	ally_snapshot["current_player_id"] = 1
	# 领袖救忠臣的基准分；只用于比较资源转化条件，不要求固定绝对值。
	var ready_ally_score: float = strategy.score_rescue(ally_snapshot, 0, 2, 1, 5.0)
	# 低价值救援场景；目标空手、距离下个回合较久且同时受乐不思蜀与兵粮寸断威胁。
	var delayed_ally_snapshot: Dictionary = ally_snapshot.duplicate(true)
	delayed_ally_snapshot["current_player_id"] = 3
	# 目标忠臣快照；公开判定区使用最小定义ID数据即可参与通用救援估值。
	var delayed_ally: Dictionary = (delayed_ally_snapshot.get("players", []) as Array)[2] as Dictionary
	delayed_ally["hand_count"] = 0
	delayed_ally["hand"] = []
	delayed_ally["judgment_area"] = [{"definition_id":"lebu"}, {"definition_id":"bingliang"}]
	# 条件不利时的救援分；必须严格低于资源充足且即将行动的队友。
	var delayed_ally_score: float = strategy.score_rescue(delayed_ally_snapshot, 0, 2, 1, 5.0)
	if delayed_ally_score >= ready_ally_score:
		return _fail("rescue_readiness ready=%.2f delayed=%.2f" % [ready_ally_score, delayed_ally_score])
	return true


## 验证内奸在多人局不会对1点体力领袖执行预期致命伤害。
func _test_renegade_leader_survival() -> bool:
	# 五人公开身份快照；领袖被调整为1点体力以触发提前杀死领袖惩罚。
	var snapshot: Dictionary = _build_strategy_snapshot(true)
	(snapshot.get("players", []) as Array)[0]["hp"] = 1
	# 内奸效用评估器；玩家3为内奸。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 内奸对领袖使用【杀】的动作；多人局中该动作应被评为负收益。
	var lethal_leader_action: Dictionary = {"action_type":"use_card", "actor_id":3, "card_uid":601, "card_definition_id":"sha", "target_ids":[0], "payload":{}}
	# 提前杀死领袖动作评分；负数会令基础策略结束出牌或选择其他控场目标。
	var lethal_leader_score: float = evaluator.score_action(snapshot, lethal_leader_action, 3)
	if lethal_leader_score >= 0.0:
		return _fail("renegade_early_leader_kill=%.2f" % lethal_leader_score)
	return true


## 验证内奸根据领忠或反贼优势切换压制目标，保持身份局继续进入可获胜残局。
func _test_renegade_balance_strategy() -> bool:
	# 当前【杀】AI 配置；负面目标牌效用于比较内奸控场附加分。
	var slash_ai: Dictionary = GameDatabase.get_card("sha").get("ai", {}) as Dictionary
	# 领忠明显优势快照；领袖与忠臣资源充足，反贼状态较弱。
	var loyal_advantage_snapshot: Dictionary = _build_strategy_snapshot(true)
	_set_camp_strength(loyal_advantage_snapshot, true)
	# 领忠优势时攻击忠臣的控场分；应高于继续压制弱势反贼。
	var loyal_target_score: float = IdentityStrategyEvaluator.new(IdentityAIModel.new()).score_target_strategy(loyal_advantage_snapshot, 3, 2, slash_ai)
	# 领忠优势时攻击反贼的控场分；帮助优势方会受到惩罚。
	var rebel_target_when_loyal_strong: float = IdentityStrategyEvaluator.new(IdentityAIModel.new()).score_target_strategy(loyal_advantage_snapshot, 3, 1, slash_ai)
	# 反贼明显优势快照；反贼资源充足，领忠方进入低体力少手牌状态。
	var rebel_advantage_snapshot: Dictionary = _build_strategy_snapshot(true)
	_set_camp_strength(rebel_advantage_snapshot, false)
	# 反贼优势时攻击反贼的控场分；应高于继续压制弱势忠臣。
	var rebel_target_score: float = IdentityStrategyEvaluator.new(IdentityAIModel.new()).score_target_strategy(rebel_advantage_snapshot, 3, 1, slash_ai)
	# 反贼优势时攻击忠臣的控场分；帮助优势方会受到惩罚。
	var loyal_target_when_rebel_strong: float = IdentityStrategyEvaluator.new(IdentityAIModel.new()).score_target_strategy(rebel_advantage_snapshot, 3, 2, slash_ai)
	if loyal_target_score <= rebel_target_when_loyal_strong or rebel_target_score <= loyal_target_when_rebel_strong:
		return _fail("renegade_balance loyal=%.2f/%.2f rebel=%.2f/%.2f" % [loyal_target_score, rebel_target_when_loyal_strong, rebel_target_score, loyal_target_when_rebel_strong])
	return true


## 验证已知响应牌降低伤害预期，并验证同阵营敌人中高 condition、高伤害牌和武器目标威胁更高。
func _test_response_and_threat_strategy() -> bool:
	# 全身份公开快照；目标1与目标4均为反贼，便于隔离响应牌和威胁差异。
	var snapshot: Dictionary = _build_strategy_snapshot(true)
	# 领袖效用评估器；所有比较共享同一身份关系模型。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 目标没有【闪】时的等量单手牌；使用【无懈可击】保持手牌数量相同。
	(snapshot.get("players", []) as Array)[1]["hand"] = [_card(701, "wuxie", 1)]
	(snapshot.get("players", []) as Array)[1]["hand_count"] = 1
	# 领袖对反贼1使用【杀】的标准动作。
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 目标没有已知【闪】时的伤害评分。
	var score_without_dodge: float = evaluator.score_action(snapshot, slash_action, 0)
	# 把同一张已知手牌替换为【闪】，只改变响应能力而不改变手牌数量。
	(snapshot.get("players", []) as Array)[1]["hand"] = [_card(702, "shan", 1)]
	# 目标拥有已知【闪】时的伤害评分；预期命中倍率应下降。
	var score_with_dodge: float = evaluator.score_action(snapshot, slash_action, 0)
	if evaluator.get_known_response_count(snapshot, 1, "shan") != 1 or score_with_dodge >= score_without_dodge:
		return _fail("known_response without=%.2f with=%.2f" % [score_without_dodge, score_with_dodge])
	# 低威胁反贼状态；无手牌、低体力且无装备。
	(snapshot.get("players", []) as Array)[1]["hp"] = 2
	(snapshot.get("players", []) as Array)[1]["hand"] = []
	(snapshot.get("players", []) as Array)[1]["hand_count"] = 0
	# 高威胁反贼状态；高体力、两张伤害牌并装备武器。
	(snapshot.get("players", []) as Array)[4]["hp"] = 4
	(snapshot.get("players", []) as Array)[4]["hand"] = [_card(703, "sha", 4), _card(704, "sha_fire", 4)]
	(snapshot.get("players", []) as Array)[4]["hand_count"] = 2
	(snapshot.get("players", []) as Array)[4]["equipment"] = {"weapon":_card(705, "qinggang", 4)}
	# 低威胁目标分；作为阵营内比较基线。
	var low_threat: float = evaluator.get_threat(snapshot, 0, 1)
	# 高威胁目标分；condition、伤害牌和武器应共同提高结果。
	var high_threat: float = evaluator.get_threat(snapshot, 0, 4)
	if high_threat <= low_threat:
		return _fail("threat_priority low=%.2f high=%.2f" % [low_threat, high_threat])
	return true


## 验证【杀】优先选择敌方而非友方，目标体力与身份态度共同参与评分。
func _test_hostile_card_target() -> bool:
	# 全身份公开快照；目标1为反贼，目标2为忠臣。
	var snapshot: Dictionary = _build_snapshot(true)
	# 对反贼使用【杀】的合法动作。
	var enemy_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 对忠臣使用【杀】的合法动作。
	var friend_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[2], "payload":{}}
	# 策略选择结果；目标必须为反贼1。
	var chosen: Dictionary = _policy.choose_action(snapshot, [friend_action, enemy_action])
	if (chosen.get("target_ids", []) as Array) != [1]:
		return _fail("hostile_target=%s" % [chosen])
	return true


## 验证【铁索连环】解除敌方横置等低收益用法不会被出牌顺序驱动，AI会改为重铸摸1张牌。
func _test_tiesuo_prefers_recast_when_use_value_is_low() -> bool:
	# 全身份公开快照；敌方已经横置，本次使用只会帮助其解除连环。
	var snapshot: Dictionary = _build_snapshot(true)
	# 使用者手牌；确保使用与重铸引用同一张铁索连环实体。
	var actor: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	actor["hand"] = [_card(450, "tiesuo", 0)]
	actor["hand_count"] = 1
	# 已横置敌方；对其使用铁索连环属于负收益目标效果。
	(snapshot.get("players", []) as Array)[1]["chained"] = true
	# 低收益使用动作；实际规则允许解除敌方横置，但AI不应主动帮助敌方。
	var use_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":450, "card_definition_id":"tiesuo", "target_ids":[1], "payload":{}}
	# 同实体重铸动作；弃置后摸1张未知牌，作为低收益使用的直接替代项。
	var recast_action: Dictionary = {"action_type":"recast_card", "actor_id":0, "card_uid":450, "card_definition_id":"tiesuo", "target_ids":[], "payload":{}}
	# 独立策略；避免其他测试的身份暴露历史改变敌我态度。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	# 最终选择；必须提交重铸而不是使用铁索连环。
	var chosen: Dictionary = policy.choose_action(snapshot, [use_action, recast_action])
	if str(chosen.get("action_type", "")) != "recast_card" or int(chosen.get("card_uid", -1)) != 450:
		return _fail("tiesuo_low_value_recast=%s" % chosen)
	return true


## 验证【全垒】AI在持有实体【杀】时，会把该【杀】转化为目标上限+1的雷【杀】同时攻击两名正收益敌人。
func _test_quanlei_slash_material_priority() -> bool:
	# 公开五人身份快照；领袖0与反贼1、4之间有稳定敌对态度，可对比单目标【杀】与双目标【全垒】。
	var snapshot: Dictionary = _build_strategy_snapshot(true)
	# 全垒使用者快照；手中只保留一张实体【杀】，确保技能选中的材料就是需求所指卡牌。
	var actor: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	actor["character_id"] = "qiong"
	actor["hand"] = [_card(501, "sha", 0)]
	actor["hand_count"] = 1
	# 两名敌方目标；清空已知【闪】使两段雷【杀】均保持严格正收益。
	for target_index: int in [1, 4]:
		# 当前反贼快照；体力3、空手牌作为稳定可攻击基线。
		var target: Dictionary = (snapshot.get("players", []) as Array)[target_index] as Dictionary
		target["hp"] = 3
		target["hand"] = []
		target["hand_count"] = 0
	# 普通实体【杀】动作；仅指定一名反贼，作为技能选择的直接竞争项。
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":501, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 全垒双目标动作；使用同一张实体【杀】作材料，同时指定两名反贼。
	var quanlei_action: Dictionary = {"action_type":"use_skill", "actor_id":0, "skill_id":"quanlei", "target_ids":[1, 4], "payload":{"skill_id":"quanlei", "material_card_uid":501, "target_ids":[1, 4]}}
	# 独立领袖策略；不复用前序身份暴露历史，确保选择只由本快照与全垒评分决定。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	# AI最终动作；应优先全垒并保留【杀】材料UID与两名目标。
	var chosen: Dictionary = policy.choose_action(snapshot, [slash_action, quanlei_action])
	var chosen_payload: Dictionary = chosen.get("payload", {}) as Dictionary
	if str(chosen.get("action_type", "")) != "use_skill" or str(chosen_payload.get("skill_id", "")) != "quanlei" or int(chosen_payload.get("material_card_uid", -1)) != 501 or (chosen.get("target_ids", []) as Array) != [1, 4]:
		return _fail("quanlei_slash_material_priority=%s" % chosen)
	# 藤甲单目标场景；普通【杀】完全无效，但转化后的雷【杀】可以正常造成伤害。
	var vine_snapshot: Dictionary = _build_snapshot(true)
	# 全垒使用者手牌；只持有一张黑色普通【杀】，排除其他材料干扰。
	var vine_actor: Dictionary = (vine_snapshot.get("players", []) as Array)[0] as Dictionary
	vine_actor["character_id"] = "qiong"
	vine_actor["hand"] = [_card(502, "sha", 0)]
	vine_actor["hand_count"] = 1
	# 藤甲敌方；普通【杀】的目标效果为0，雷【杀】不受藤甲免疫。
	(vine_snapshot.get("players", []) as Array)[1]["equipment"] = {"armor":_card(503, "tengjia", 1)}
	# 普通【杀】动作；用于证明AI不会直接消耗被藤甲完全拦截的实体牌。
	var blocked_slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":502, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 全垒单目标动作；同一张普通【杀】转化为雷【杀】后应成为明确正收益。
	var thunder_conversion_action: Dictionary = {"action_type":"use_skill", "actor_id":0, "skill_id":"quanlei", "target_ids":[1], "payload":{"skill_id":"quanlei", "material_card_uid":502, "target_ids":[1]}}
	# 独立藤甲场景策略；最终必须选择全垒转化。
	var vine_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var vine_choice: Dictionary = vine_policy.choose_action(vine_snapshot, [blocked_slash_action, thunder_conversion_action])
	if str(vine_choice.get("action_type", "")) != "use_skill" or str((vine_choice.get("payload", {}) as Dictionary).get("skill_id", "")) != "quanlei":
		return _fail("quanlei_tengjia_thunder_conversion=%s" % vine_choice)
	return true


## 验证转化技能生成的虚拟牌会进入持有者被动技能评分链，避免只计算材料费用而漏掉实际用牌收益。
func _test_conversion_virtual_card_skill_synergy() -> bool:
	# 基础快照；黑色普通【杀】作为罡风材料，目标为公开敌方。
	var snapshot: Dictionary = _build_snapshot(true)
	# 使用者手牌；稳定材料UID用于两份对照快照。
	var actor: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	actor["hand"] = [_card(560, "sha", 0)]
	actor["hand_count"] = 1
	# 罡风转化动作；完整评分应把生成的雷【杀】继续交给疾雨等modify_ai_card_action_score钩子。
	var conversion_action: Dictionary = {"action_type":"use_skill", "actor_id":0, "skill_id":"gangfeng", "target_ids":[1], "payload":{"skill_id":"gangfeng", "material_card_uid":560, "target_ids":[1]}}
	# 无疾雨对照；角色本身不提供任何【杀】联动，只保留罡风的虚拟雷【杀】与材料成本。
	actor["character_id"] = "xier"
	var baseline_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var baseline_score: float = float(baseline_policy.call("_score_action", snapshot, conversion_action))
	# 丹恒快照；固有疾雨会对任意【杀】增加4分，转化后的雷【杀】也必须获得同一收益。
	var synergy_snapshot: Dictionary = snapshot.duplicate(true)
	(synergy_snapshot.get("players", []) as Array)[0]["character_id"] = "dan_heng"
	var synergy_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var synergy_score: float = float(synergy_policy.call("_score_action", synergy_snapshot, conversion_action))
	if synergy_score < baseline_score + 3.9:
		return _fail("conversion_virtual_skill_synergy baseline=%.3f synergy=%.3f" % [baseline_score, synergy_score])
	return true


## 验证【星祈】在存在锦囊候选时无条件确认发动，不会把牌堆顶候选误当作自身弃牌成本而取消。
func _test_xingqi_always_activates() -> bool:
	# 全身份公开快照；技能选择只依赖稳定持有者ID，不需要运行时规则宿主。
	var snapshot: Dictionary = _build_snapshot(true)
	# 牌堆顶锦囊候选；归属为-1表示公共牌堆，不是AI自身手牌。
	var trick_candidate: Dictionary = _candidate(570, "wuzhong", -1)
	trick_candidate["zone"] = "draw_pile"
	# 星祈首步请求；保持原规则“可以”的可取消语义，仅由AI评分选择确认。
	var choice_request: Dictionary = {"request_id":570, "choice_type":"card", "allow_cancel":true, "min_select":1, "max_select":1, "min_card_select":1, "max_card_select":1, "candidates":[trick_candidate], "context":{"kind":"xingqi_trick", "skill_id":"xingqi", "skill_owner_id":0}}
	# 取消动作；通用可取消选择的0分基线。
	var cancel_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":570, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	# 确认动作；选择唯一锦囊后应获得星祈固定发动分。
	var confirm_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":570, "selected_card_uids":[570], "selected_target_ids":[], "confirmed":true}}
	# 独立策略选择；必须确认并保留所选锦囊UID。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var chosen: Dictionary = policy.choose_card_choice(snapshot, choice_request, [cancel_action, confirm_action])
	var chosen_payload: Dictionary = chosen.get("payload", {}) as Dictionary
	if not bool(chosen_payload.get("confirmed", false)) or chosen_payload.get("selected_card_uids", []) != [570]:
		return _fail("xingqi_always_activate=%s" % chosen)
	# 星祈技能实例；直接核对固定确认分，防止通用评分增长后又不足以压过取消动作。
	var xingqi: SkillDefinition = GameDatabase.create_skill("xingqi")
	xingqi.bind(null, 0)
	# 独立评估器；星祈首步只读取候选牌价值与固定确认分，不需要运行时对局宿主。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 唯一锦囊确认动作的技能评分；必须保持10000分级别的无脑发动优先级。
	var confirmation_score: float = xingqi.score_ai_choice(snapshot, choice_request, confirm_action, evaluator)
	if confirmation_score < 10000.0:
		return _fail("xingqi_confirmation_score=%.3f" % confirmation_score)
	return true


## 验证【星落】必须至少指定一名其他角色；直接提交空目标不能绕过技能的目标下限。
func _test_xingluo_requires_other_target() -> bool:
	# 静态星落技能；空宿主仍可在目标前置校验处拒绝空数组，不会进入重铸流程。
	var xingluo: SkillDefinition = GameDatabase.create_skill("xingluo")
	xingluo.bind(null, 0)
	# 直接空目标发动结果；非空错误信息表示技能没有把“仅重铸自己”作为合法动作。
	var activation_error: String = xingluo.activate({"target_ids":[]})
	if activation_error.is_empty():
		return _fail("xingluo_empty_target_accepted")
	return true


## 验证剑势只对敌方确认、戏法固定发动、投狭按友方与关键牌边界判断，并能选择正收益山倾动作。
func _test_sushang_guinaifen_skill_ai() -> bool:
	# 全身份公开快照；0号领袖、1号反贼、2号忠臣使敌友关系确定。
	var snapshot: Dictionary = _build_snapshot(true)
	# 通用取消动作；零材料确认请求均使用相同取消基线。
	var cancel_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":610, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	# 通用确认动作；具体技能通过请求上下文定位自身评分钩子。
	var confirm_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":610, "selected_card_uids":[], "selected_target_ids":[], "confirmed":true}}
	# 敌方剑势请求；AI 指定逻辑要求无条件确认。
	var enemy_jianshi_request: Dictionary = {"request_id":610, "choice_type":"card", "allow_cancel":true, "min_card_select":0, "max_card_select":0, "candidates":[], "context":{"kind":"jianshi_confirm", "skill_id":"jianshi", "skill_owner_id":0, "target_id":1, "ai_allow_confirm":true}}
	# 独立策略；同一身份模型在每次 choose_card_choice 前会同步当前快照。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	# 敌方剑势最终选择；用于确认固定正分能够压过取消动作。
	var enemy_jianshi_choice: Dictionary = policy.choose_card_choice(snapshot, enemy_jianshi_request, [cancel_action, confirm_action])
	if not bool((enemy_jianshi_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("jianshi_enemy_cancelled=%s" % enemy_jianshi_choice)
	# 友方剑势请求；目标改为忠臣后应选择取消，避免无脑增加友方所受伤害。
	var ally_jianshi_request: Dictionary = enemy_jianshi_request.duplicate(true)
	(ally_jianshi_request.get("context", {}) as Dictionary)["target_id"] = 2
	# 友方剑势最终选择；固定负分应保留取消动作。
	var ally_jianshi_choice: Dictionary = policy.choose_card_choice(snapshot, ally_jianshi_request, [cancel_action, confirm_action])
	if bool((ally_jianshi_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("jianshi_ally_confirmed=%s" % ally_jianshi_choice)
	# 戏法确认请求；只要可以发动就固定确认，不受当前判定对象敌友影响。
	var xifa_request: Dictionary = {"request_id":611, "choice_type":"card", "allow_cancel":true, "min_card_select":0, "max_card_select":0, "candidates":[], "context":{"kind":"xifa_confirm", "skill_id":"xifa", "skill_owner_id":0, "judgment_player_id":1, "ai_allow_confirm":true}}
	# 戏法最终选择；固定高正分必须选择确认。
	var xifa_choice: Dictionary = policy.choose_card_choice(snapshot, xifa_request, [cancel_action, confirm_action])
	if not bool((xifa_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("xifa_not_always_activate=%s" % xifa_choice)
	# 友方投狭请求；即使当前没有高价值弃牌，也应为了友方摸牌与潜在回收通常发动。
	var friendly_touxia_request: Dictionary = {"request_id":612, "choice_type":"card", "allow_cancel":true, "min_card_select":0, "max_card_select":0, "candidates":[], "context":{"kind":"touxia_confirm", "skill_id":"touxia", "skill_owner_id":0, "turn_player_id":2, "maximum_candidate_value":0.0, "ai_allow_confirm":true}}
	# 友方投狭最终选择；基础团队收益应压过取消动作。
	var friendly_touxia_choice: Dictionary = policy.choose_card_choice(snapshot, friendly_touxia_request, [cancel_action, confirm_action])
	if not bool((friendly_touxia_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("touxia_friend_cancelled=%s" % friendly_touxia_choice)
	# 敌方普通弃牌请求；没有达到关键牌阈值时应取消，避免无收益地令敌方摸牌。
	var enemy_low_touxia_request: Dictionary = friendly_touxia_request.duplicate(true)
	(enemy_low_touxia_request.get("context", {}) as Dictionary)["turn_player_id"] = 1
	(enemy_low_touxia_request.get("context", {}) as Dictionary)["maximum_candidate_value"] = 3.0
	# 敌方低价值投狭选择；关键牌收益不足时应取消。
	var enemy_low_touxia_choice: Dictionary = policy.choose_card_choice(snapshot, enemy_low_touxia_request, [cancel_action, confirm_action])
	if bool((enemy_low_touxia_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("touxia_enemy_low_confirmed=%s" % enemy_low_touxia_choice)
	# 敌方关键牌请求；价值达到阈值后应确认，体现“为了关键牌可对敌人发动”的指定边界。
	var enemy_key_touxia_request: Dictionary = enemy_low_touxia_request.duplicate(true)
	(enemy_key_touxia_request.get("context", {}) as Dictionary)["maximum_candidate_value"] = 7.0
	# 敌方关键牌投狭选择；越过阈值后应确认发动。
	var enemy_key_touxia_choice: Dictionary = policy.choose_card_choice(snapshot, enemy_key_touxia_request, [cancel_action, confirm_action])
	if not bool((enemy_key_touxia_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("touxia_enemy_key_cancelled=%s" % enemy_key_touxia_choice)
	# 山倾动作快照；两张低价值黑桃材料可无距离攻击低体力敌方，应形成正收益主动动作。
	var actor: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	actor["character_id"] = "sushang"
	actor["hand"] = [_card(620, "sha", 0), _card(621, "tiesuo", 0)]
	actor["hand_count"] = 2
	# 山倾合法动作；目标与材料均由规则层预先枚举，AI只负责收益比较。
	var shanqing_action: Dictionary = {"action_type":"use_skill", "actor_id":0, "skill_id":"shanqing", "target_ids":[1], "payload":{"skill_id":"shanqing", "material_card_uids":[620, 621], "target_ids":[1]}}
	# 山倾最终主动动作；唯一正收益组合应被策略保留为技能动作。
	var shanqing_choice: Dictionary = policy.choose_action(snapshot, [shanqing_action])
	if str(shanqing_choice.get("action_type", "")) != "use_skill" or str((shanqing_choice.get("payload", {}) as Dictionary).get("skill_id", "")) != "shanqing":
		return _fail("shanqing_positive_action=%s" % shanqing_choice)
	# 山倾装备材料；通用自有牌查询必须读取公开装备花色，并按八卦阵 equip_value=7.5 计算保留成本。
	var equipment_material: Dictionary = _card(622, "bagua", 0)
	equipment_material["zone"] = "equipment"
	actor["equipment"] = {"armor":equipment_material}
	# 独立评估器；直接验证所有转化技能共享的装备材料查询接口，不依赖具体动作排列。
	var material_evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 装备材料快照；花色与定义 ID 都应保持公开实体原值。
	var resolved_equipment_material: Dictionary = material_evaluator.get_owned_card_by_uid(snapshot, 0, 622)
	# 装备材料价值；八卦阵静态 equip_value 固定为7.5，不能回退成未知牌2分。
	var equipment_material_value: float = material_evaluator.get_owned_card_value_by_uid(snapshot, 0, 622)
	if str(resolved_equipment_material.get("definition_id", "")) != "bagua" or str(resolved_equipment_material.get("suit", "")) != "spade" or not is_equal_approx(equipment_material_value, 7.5):
		return _fail("shanqing_equipment_material data=%s value=%.2f" % [resolved_equipment_material, equipment_material_value])
	# 友方梅花弃牌请求；若山倾因其他收益指定队友，AI应在强制弃牌中保留高价值【桃】。
	var friendly_club_request: Dictionary = {"request_id":613, "choice_type":"card", "allow_cancel":false, "min_select":1, "max_select":1, "min_card_select":1, "max_card_select":1, "candidates":[_candidate(623, "sha", 2), _candidate(624, "tao", 2)], "context":{"kind":"shanqing_club_discard", "skill_id":"shanqing", "skill_owner_id":0, "target_id":2}}
	# 弃置友方低价值【杀】的动作；应优先于弃置其高价值救援牌。
	var discard_friendly_slash_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":613, "selected_card_uids":[623], "selected_target_ids":[], "confirmed":true}}
	# 弃置友方高价值【桃】的动作；完整 AI 应降低其评分以减少对队友的资源伤害。
	var discard_friendly_peach_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":613, "selected_card_uids":[624], "selected_target_ids":[], "confirmed":true}}
	# 友方梅花最终选择；必须保留【桃】并弃置价值更低的【杀】。
	var friendly_club_choice: Dictionary = policy.choose_card_choice(snapshot, friendly_club_request, [discard_friendly_slash_action, discard_friendly_peach_action])
	if ((friendly_club_choice.get("payload", {}) as Dictionary).get("selected_card_uids", []) as Array) != [623]:
		return _fail("shanqing_friendly_club_discard=%s" % friendly_club_choice)
	return true


## 验证 AI 会跳过防具完全免疫的攻击，但【星火】等仍能产生正向技能收益时保留该合法动作。
func _test_renwang_shield_black_slash() -> bool:
	# 全身份公开快照；一号反贼是唯一敌方目标，黑色【杀】实体来自领袖完整手牌。
	var snapshot: Dictionary = _build_snapshot(true)
	# 敌方防具；公开装备信息足以让 AI 预判黑色【杀】完全无效。
	(snapshot.get("players", []) as Array)[1]["equipment"] = {"armor":_card(801, "renwang", 1)}
	# 黑色【杀】动作；基础策略若接受该动作即表示没有正确读取仁王盾的防具拦截钩子。
	var black_slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 未装备无视防具武器时的选择；唯一行动完全无效，因此 AI 必须结束出牌而不是消耗【杀】。
	var blocked_choice: Dictionary = _policy.choose_action(snapshot, [black_slash_action])
	if str(blocked_choice.get("action_type", "")) != "end_play":
		return _fail("renwang_black_slash=%s" % [blocked_choice])
	# 无视防具武器；青釭剑的公开装备声明使同一黑色【杀】重新成为有效攻击选择。
	(snapshot.get("players", []) as Array)[0]["equipment"] = {"weapon":_card(802, "qinggang", 0)}
	var ignored_armor_choice: Dictionary = _policy.choose_action(snapshot, [black_slash_action])
	if str(ignored_armor_choice.get("action_type", "")) != "use_card" or int(ignored_armor_choice.get("card_uid", -1)) != 101:
		return _fail("renwang_ignored_by_qinggang=%s" % [ignored_armor_choice])
	# 藤甲目标；普通【杀】、南蛮入侵与万箭齐发均应判定为完全无效。
	(snapshot.get("players", []) as Array)[0]["equipment"] = {}
	(snapshot.get("players", []) as Array)[1]["equipment"] = {"armor":_card(803, "tengjia", 1)}
	var tengjia_normal_choice: Dictionary = _policy.choose_action(snapshot, [black_slash_action])
	if str(tengjia_normal_choice.get("action_type", "")) != "end_play":
		return _fail("tengjia_normal_slash=%s" % [tengjia_normal_choice])
	# 南蛮入侵群体动作；空目标数组会由AI按全体其他角色展开，并识别唯一敌方目标的藤甲免疫。
	var nanman_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":804, "card_definition_id":"nanman", "target_ids":[], "payload":{}}
	# 只保留敌方目标存活；忠臣暂时离场使本动作的全部实际目标都由藤甲拦截。
	(snapshot.get("players", []) as Array)[2]["alive"] = false
	var tengjia_nanman_choice: Dictionary = _policy.choose_action(snapshot, [nanman_action])
	if str(tengjia_nanman_choice.get("action_type", "")) != "end_play":
		return _fail("tengjia_nanman=%s" % [tengjia_nanman_choice])
	# 万箭齐发群体动作；与南蛮入侵相同，唯一实际目标被藤甲免疫时不得只因高出牌顺序消耗实体牌。
	var wanjian_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":805, "card_definition_id":"wanjian", "target_ids":[], "payload":{}}
	var tengjia_wanjian_choice: Dictionary = _policy.choose_action(snapshot, [wanjian_action])
	if str(tengjia_wanjian_choice.get("action_type", "")) != "end_play":
		return _fail("tengjia_wanjian=%s" % [tengjia_wanjian_choice])
	# 姬子【星火】会在指定唯一目标后横置敌方，即使黑色【杀】被仁王盾拦截仍有独立正收益。
	(snapshot.get("players", []) as Array)[0]["character_id"] = "himeko"
	(snapshot.get("players", []) as Array)[1]["equipment"] = {"armor":_card(804, "renwang", 1)}
	var xinghuo_blocked_slash_choice: Dictionary = _policy.choose_action(snapshot, [black_slash_action])
	if str(xinghuo_blocked_slash_choice.get("action_type", "")) != "use_card" or int(xinghuo_blocked_slash_choice.get("card_uid", -1)) != 101:
		return _fail("xinghuo_blocked_slash=%s" % [xinghuo_blocked_slash_choice])
	# 火【杀】动作；藤甲不会拦截且火焰伤害加1应提高目标伤害收益。
	(snapshot.get("players", []) as Array)[0]["character_id"] = "xier"
	(snapshot.get("players", []) as Array)[1]["equipment"] = {"armor":_card(803, "tengjia", 1)}
	var fire_slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":805, "card_definition_id":"sha_fire", "target_ids":[1], "payload":{}}
	# AI评估器；直接比较有无藤甲时相同火【杀】目标收益。
	var fire_evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	var fire_score_with_tengjia: float = fire_evaluator.score_action(snapshot, fire_slash_action, 0)
	# 无防具对照快照；其余体力、手牌和身份保持不变。
	var no_armor_snapshot: Dictionary = snapshot.duplicate(true)
	(no_armor_snapshot.get("players", []) as Array)[1]["equipment"] = {}
	var fire_score_without_tengjia: float = fire_evaluator.score_action(no_armor_snapshot, fire_slash_action, 0)
	if fire_score_with_tengjia <= fire_score_without_tengjia:
		return _fail("tengjia_fire_value with=%.2f without=%.2f" % [fire_score_with_tengjia, fire_score_without_tengjia])
	return true


## 验证横置友方受到友方属性【杀】时，全部敌人同样横置会保留【闪】以让伤害传导；敌人未全横置则正常响应。
func _test_friendly_chain_damage_response() -> bool:
	# 公开三人快照；领袖0对忠臣2使用雷【杀】，反贼1是属性伤害的唯一其他可传导敌方。
	var snapshot: Dictionary = _build_snapshot(true)
	(snapshot.get("players", []) as Array)[1]["chained"] = true
	(snapshot.get("players", []) as Array)[2]["chained"] = true
	# 忠臣响应策略；独立身份模型避免前序测试的暴露历史影响本次友敌判断。
	var loyalist_policy: BasicAIPolicy = BasicAIPolicy.new(2, IdentityAIModel.new())
	# 可取消的【闪】响应请求；上下文保留实际伤害来源、属性、目标与伤害值，字段与【杀】响应流程一致。
	var response_request: Dictionary = {
		"allow_cancel":true,
		"min_card_select":0,
		"max_card_select":1,
		"candidates":[_candidate(801, "shan", 2)],
		"context":{"kind":"slash_response", "response_patterns":["shan"], "actor_id":0, "target_id":2, "nature":"thunder", "damage_amount":1, "slash_card_definition_id":"sha_thunder"},
	}
	# 两种标准选择动作；确认会消耗【闪】，取消会让友方雷伤命中并经连环传导。
	var pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":2, "payload":{"request_id":801, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	var dodge_action: Dictionary = {"action_type":"choose_cards", "actor_id":2, "payload":{"request_id":801, "selected_card_uids":[801], "selected_target_ids":[], "confirmed":true}}
	# 敌人全部横置；忠臣应放弃【闪】，让领袖的雷属性伤害同时传导至反贼。
	var chained_enemy_choice: Dictionary = loyalist_policy.choose_card_choice(snapshot, response_request, [pass_action, dodge_action])
	if bool((chained_enemy_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("friendly_chain_damage_should_pass=%s" % chained_enemy_choice)
	# 敌人解除横置后不再具备完整传导收益；忠臣应恢复普通生存逻辑并打出【闪】。
	(snapshot.get("players", []) as Array)[1]["chained"] = false
	var unchained_enemy_choice: Dictionary = loyalist_policy.choose_card_choice(snapshot, response_request, [pass_action, dodge_action])
	if not bool((unchained_enemy_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("friendly_chain_damage_should_dodge=%s" % unchained_enemy_choice)
	return true


## 验证参考无名杀的防酒杀策略：高伤害与致命响应加权、保留最后【闪】，并在主动评估中识别酒加成。
func _test_wine_slash_defense() -> bool:
	# 玩家权威状态；公开的酒使用与伤害加值必须进入序列化快照，供服务端AI和联机表现一致读取。
	var serialized_player: PlayerState = PlayerState.new(9, "酒杀测试")
	serialized_player.wine_used = true
	serialized_player.wine_bonus = 1
	var serialized_data: Dictionary = serialized_player.to_dict(9, true)
	if not bool(serialized_data.get("wine_used", false)) or int(serialized_data.get("wine_bonus", 0)) != 1:
		return _fail("wine_state_serialization=%s" % serialized_data)
	# 公开三人身份快照；领袖0用于响应和保牌，反贼1用于构造可达的酒杀威胁。
	var snapshot: Dictionary = _build_snapshot(true)
	# 领袖的唯一【闪】；响应请求和后续弃牌比较都使用该实体UID。
	var defender: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	defender["hp"] = 2
	defender["shield"] = 0
	defender["hand"] = [_card(601, "shan", 0)]
	defender["hand_count"] = 1
	# 普通【杀】响应请求；伤害值1用于对比酒杀的额外防守分。
	var normal_response_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[_candidate(601, "shan", 0)], "context":{"kind":"slash_response", "response_patterns":["shan"], "actor_id":1, "target_id":0, "nature":"normal", "damage_amount":1, "slash_card_definition_id":"sha"}}
	# 酒杀响应请求；其他字段与普通【杀】一致，只把真实伤害提高到2。
	var wine_response_request: Dictionary = normal_response_request.duplicate(true)
	(wine_response_request.get("context", {}) as Dictionary)["damage_amount"] = 2
	# 标准【闪】确认动作；两份请求共用同一响应牌以隔离伤害值差异。
	var dodge_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":601, "selected_card_uids":[601], "selected_target_ids":[], "confirmed":true}}
	# 取消响应动作；致命酒杀场景下不应成为AI最终选择。
	var pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":601, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	# 响应评估器；直接比较两份确认动作分数，证明酒杀不是仅与普通杀作相同布尔决策。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	var normal_response_score: float = evaluator.score_choice_action(snapshot, normal_response_request, dodge_action, 0)
	var wine_response_score: float = evaluator.score_choice_action(snapshot, wine_response_request, dodge_action, 0)
	if wine_response_score <= normal_response_score:
		return _fail("wine_slash_response_score normal=%.2f wine=%.2f" % [normal_response_score, wine_response_score])
	# 领袖响应策略；2点酒杀足以打穿2点体力，必须打出【闪】。
	var defender_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var lethal_response_choice: Dictionary = defender_policy.choose_card_choice(snapshot, wine_response_request, [pass_action, dodge_action])
	if not bool((lethal_response_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wine_slash_lethal_response=%s" % lethal_response_choice)
	# 酒杀主动评分动作；目标体力2且无护盾，酒加成应使该【杀】的预期收益高于普通状态。
	var attack_snapshot: Dictionary = _build_snapshot(true)
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	var normal_slash_score: float = evaluator.score_action(attack_snapshot, slash_action, 0)
	((attack_snapshot.get("players", []) as Array)[0] as Dictionary)["wine_bonus"] = 1
	var wine_slash_score: float = evaluator.score_action(attack_snapshot, slash_action, 0)
	if wine_slash_score <= normal_slash_score:
		return _fail("wine_slash_action_score normal=%.2f wine=%.2f" % [normal_slash_score, wine_slash_score])
	# 致命威胁者；反贼1已使用【酒】、手中有已知【杀】，且与领袖距离1。
	var attacker: Dictionary = (snapshot.get("players", []) as Array)[1] as Dictionary
	attacker["wine_bonus"] = 1
	attacker["hand"] = [_card(701, "sha", 1)]
	attacker["hand_count"] = 1
	# 强制弃牌候选；【桃】的默认价值9高于【闪】7，没有酒杀威胁时应先弃【闪】。
	defender["hand"] = [_card(601, "shan", 0), _card(602, "tao", 0)]
	defender["hand_count"] = 2
	var discard_request: Dictionary = {"allow_cancel":false, "min_card_select":1, "max_card_select":1, "candidates":[_candidate(601, "shan", 0), _candidate(602, "tao", 0)], "context":{"kind":"discard_phase"}}
	var discard_dodge_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":602, "selected_card_uids":[601], "selected_target_ids":[], "confirmed":true}}
	var discard_peach_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":602, "selected_card_uids":[602], "selected_target_ids":[], "confirmed":true}}
	var wine_threat_discard_choice: Dictionary = defender_policy.choose_card_choice(snapshot, discard_request, [discard_dodge_action, discard_peach_action])
	if ((wine_threat_discard_choice.get("payload", {}) as Dictionary).get("selected_card_uids", []) as Array) != [602]:
		return _fail("wine_slash_keep_last_dodge=%s" % wine_threat_discard_choice)
	# 移除酒加成的对照选择；没有即将到来的2点【杀】时，AI应恢复默认价值并优先弃置【闪】。
	attacker["wine_bonus"] = 0
	var normal_threat_discard_choice: Dictionary = defender_policy.choose_card_choice(snapshot, discard_request, [discard_dodge_action, discard_peach_action])
	if ((normal_threat_discard_choice.get("payload", {}) as Dictionary).get("selected_card_uids", []) as Array) != [601]:
		return _fail("normal_slash_discard_baseline=%s" % normal_threat_discard_choice)
	return true


## 验证属性伤害会计入自身与友方横置传导风险，群体牌会避开1血队友，并按身份局死亡奖惩估值。
func _test_chained_damage_team_risk() -> bool:
	# 全身份公开快照；领袖0攻击横置反贼1，忠臣2用于验证友军连环与群体伤害风险。
	var snapshot: Dictionary = _build_snapshot(true)
	# 反贼成为火【杀】直接目标；横置后会把属性伤害传导给全部其他横置角色。
	(snapshot.get("players", []) as Array)[1]["chained"] = true
	# 火【杀】动作；使用真实属性伤害卡牌定义，避免测试人为构造未声明nature_damage的配置。
	var fire_slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha_fire", "target_ids":[1], "payload":{}}
	# 独立评估器；本测试不复用前序身份观察，确保分差只来自快照横置状态。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 行动者未横置时的属性伤害收益；作为连环自伤风险的对照值。
	var score_without_self_chain: float = evaluator.score_action(snapshot, fire_slash_action, 0)
	# 行动者横置后同样会承受传导伤害，主动攻击横置敌人的收益必须降低。
	(snapshot.get("players", []) as Array)[0]["chained"] = true
	var score_with_self_chain: float = evaluator.score_action(snapshot, fire_slash_action, 0)
	if score_with_self_chain >= score_without_self_chain:
		return _fail("chained_self_damage_risk plain=%.2f chained=%.2f" % [score_without_self_chain, score_with_self_chain])
	# 忠臣横置且体力安全时的分数；先取消行动者横置，隔离同阵营濒危角色的传导风险。
	(snapshot.get("players", []) as Array)[0]["chained"] = false
	(snapshot.get("players", []) as Array)[2]["chained"] = true
	(snapshot.get("players", []) as Array)[2]["hp"] = 4
	var score_with_safe_chained_ally: float = evaluator.score_action(snapshot, fire_slash_action, 0)
	# 忠臣降至1血后，火【杀】会传导并可能误杀队友，收益必须明显降低。
	(snapshot.get("players", []) as Array)[2]["hp"] = 1
	var score_with_critical_chained_ally: float = evaluator.score_action(snapshot, fire_slash_action, 0)
	if score_with_critical_chained_ally >= score_with_safe_chained_ally:
		return _fail("chained_ally_critical_risk safe=%.2f critical=%.2f" % [score_with_safe_chained_ally, score_with_critical_chained_ally])
	# 群体伤害动作；【南蛮入侵】会直接命中所有其他存活角色，必须也把1血忠臣的误杀风险纳入总分。
	var nanman_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":901, "card_definition_id":"nanman", "target_ids":[], "payload":{}}
	# 忠臣安全体力时的群体牌分数；移除横置只验证群体牌自身的友军濒危逻辑。
	(snapshot.get("players", []) as Array)[2]["chained"] = false
	(snapshot.get("players", []) as Array)[2]["hp"] = 4
	var aoe_score_with_safe_ally: float = evaluator.score_action(snapshot, nanman_action, 0)
	# 忠臣1血时的群体牌分数；预计击杀的主公误杀后果应令分数下降。
	(snapshot.get("players", []) as Array)[2]["hp"] = 1
	var aoe_score_with_critical_ally: float = evaluator.score_action(snapshot, nanman_action, 0)
	if aoe_score_with_critical_ally >= aoe_score_with_safe_ally:
		return _fail("aoe_ally_critical_risk safe=%.2f critical=%.2f" % [aoe_score_with_safe_ally, aoe_score_with_critical_ally])
	# 主公误杀忠臣后果；4张手牌和1件装备会全部弃置，结果应包含固定阵营惩罚与5项资源惩罚。
	(snapshot.get("players", []) as Array)[0]["hand_count"] = 4
	(snapshot.get("players", []) as Array)[0]["equipment"] = {"weapon":_card(902, "qinggang", 0)}
	var leader_kill_loyalist_score: float = evaluator.identity_strategy.score_lethal_damage_consequence(snapshot, 0, 2)
	var expected_leader_kill_loyalist_score: float = -IdentityStrategyEvaluator.ALLY_LETHAL_DAMAGE_PENALTY - IdentityStrategyEvaluator.LEADER_KILL_LOYALIST_BASE_PENALTY - 5.0 * IdentityStrategyEvaluator.LEADER_KILL_LOYALIST_RESOURCE_PENALTY
	if not is_equal_approx(leader_kill_loyalist_score, expected_leader_kill_loyalist_score):
		return _fail("leader_kill_loyalist_penalty actual=%.2f expected=%.2f" % [leader_kill_loyalist_score, expected_leader_kill_loyalist_score])
	# 第二名公开反贼；用于验证反贼击杀反贼时仍会计算规则规定的摸三张牌收益。
	var rebel_ally: Dictionary = {"player_id":3, "identity":"rebel", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":1, "max_hp":4, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"march7th"}
	(snapshot.get("players", []) as Array).append(rebel_ally)
	var rebel_kill_rebel_score: float = evaluator.identity_strategy.score_lethal_damage_consequence(snapshot, 1, 3)
	var expected_rebel_kill_rebel_score: float = IdentityStrategyEvaluator.REBEL_DEFEAT_DRAW_REWARD - IdentityStrategyEvaluator.ALLY_LETHAL_DAMAGE_PENALTY
	if not is_equal_approx(rebel_kill_rebel_score, expected_rebel_kill_rebel_score):
		return _fail("rebel_kill_rebel_reward actual=%.2f expected=%.2f" % [rebel_kill_rebel_score, expected_rebel_kill_rebel_score])
	return true


## 验证AI在同一回合记住未造成伤害的火攻目标，避免再次对该角色重复消耗【火攻】。
func _test_fire_attack_failed_target_memory() -> bool:
	# 全身份公开快照；一号反贼是领袖使用火攻的明确敌方目标。
	var snapshot: Dictionary = _build_snapshot(true)
	# 火攻动作；目标手牌非空时原本具有正向敌对牌收益。
	var fire_attack_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":806, "card_definition_id":"huogong", "target_ids":[1], "payload":{}}
	# 未记录失败时的选择；用于证明本动作本身具有足够收益而不是天然结束出牌。
	var first_choice: Dictionary = _policy.choose_action(snapshot, [fire_attack_action])
	if str(first_choice.get("action_type", "")) != "use_card":
		return _fail("fire_attack_initial_choice=%s" % [first_choice])
	# 行动者失败目标记忆；键为稳定牌定义ID，值为本回合已无效的目标ID。
	(snapshot.get("players", []) as Array)[0]["ai_failed_card_target_ids"] = {"huogong":[1]}
	# 记忆生效后的选择；唯一火攻目标被排除后应结束出牌而非连续火攻同一角色。
	var repeated_choice: Dictionary = _policy.choose_action(snapshot, [fire_attack_action])
	if str(repeated_choice.get("action_type", "")) != "end_play":
		return _fail("fire_attack_repeated_choice=%s" % [repeated_choice])
	return true


## 验证无懈可击奇偶逻辑：保护友方免受负面锦囊，且不替敌方抵消同一负面锦囊。
func _test_wuxie_decision() -> bool:
	# 全身份公开快照；领袖0、反贼1、忠臣2。
	var snapshot: Dictionary = _build_snapshot(true)
	# 无懈候选实体；响应者本人可见。
	var wuxie_candidate: Dictionary = _candidate(201, "wuxie", 0)
	# 通用放弃动作；confirmed=false 表示本轮不响应。
	var pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":1, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	# 使用无懈动作；实体 UID 来自本次候选。
	var use_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":1, "selected_card_uids":[201], "selected_target_ids":[], "confirmed":true}}
	# 友方受到乐不思蜀；领袖应使用无懈保护忠臣。
	var friend_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"lebu", "target_id":2, "negated":false}}
	# 友方无懈选择结果；应确认使用候选牌。
	var friend_choice: Dictionary = _policy.choose_card_choice(snapshot, friend_request, [pass_action, use_action])
	if not bool((friend_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_friend=%s" % [friend_choice])
	# 敌方受到乐不思蜀；领袖应保留无懈并放弃响应。
	var enemy_request: Dictionary = friend_request.duplicate(true)
	(enemy_request.get("context", {}) as Dictionary)["target_id"] = 1
	# 敌方无懈选择结果；应取消响应并保留手牌。
	var enemy_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_request, [pass_action, use_action])
	if bool((enemy_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_enemy=%s" % [enemy_choice])
	# 队友对领袖本人使用借刀杀人；持刀者可攻击敌方或拒绝后把武器交给队友，因此抵消锦囊属于负收益。
	var allied_borrow_sword_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"jiedao", "source_id":2, "target_id":0, "negated":false}}
	# 队友借刀的无懈选择结果；应明确取消并保留无懈可击。
	var allied_borrow_sword_choice: Dictionary = _policy.choose_card_choice(snapshot, allied_borrow_sword_request, [pass_action, use_action])
	if bool((allied_borrow_sword_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_allied_borrow_sword=%s" % [allied_borrow_sword_choice])
	# 队友对领袖本人使用普通负面锦囊；即使静态牌效对自己不利，也应相信队友战术并保留无懈。
	var allied_negative_trick_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"lebu", "source_id":2, "target_id":0, "negated":false}}
	# 队友负面锦囊的无懈选择结果；应取消响应，不把通用负面牌效覆盖在队友关系之上。
	var allied_negative_trick_choice: Dictionary = _policy.choose_card_choice(snapshot, allied_negative_trick_request, [pass_action, use_action])
	if bool((allied_negative_trick_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_allied_negative_trick=%s" % [allied_negative_trick_choice])
	# 队友对自己使用【闪电】；该牌静态结果为负，若缺少来源与目标保护分支，领袖会错误消耗无懈可击。
	var allied_self_lightning_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"shandian", "source_id":2, "target_id":2, "negated":false}}
	# 队友自用锦囊的无懈选择结果；应明确取消并保留无懈可击。
	var allied_self_lightning_choice: Dictionary = _policy.choose_card_choice(snapshot, allied_self_lightning_request, [pass_action, use_action])
	if bool((allied_self_lightning_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_allied_self_lightning=%s" % [allied_self_lightning_choice])
	# 敌方对领袖使用乐不思蜀；友方来源保护不能扩展到敌方来源，领袖仍应使用无懈自保。
	var enemy_negative_trick_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"lebu", "source_id":1, "target_id":0, "negated":false}}
	# 敌方负面锦囊的无懈选择结果；应确认使用候选牌。
	var enemy_negative_trick_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_negative_trick_request, [pass_action, use_action])
	if not bool((enemy_negative_trick_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_enemy_negative_trick=%s" % [enemy_negative_trick_choice])
	# 友方已横置时的【铁索连环】会解除连环，动态逐目标结果为正收益，不能再错误地使用无懈抵消。
	(snapshot.get("players", []) as Array)[2]["chained"] = true
	var chained_tiesuo_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"tiesuo", "source_id":1, "target_id":2, "negated":false}}
	var chained_tiesuo_choice: Dictionary = _policy.choose_card_choice(snapshot, chained_tiesuo_request, [pass_action, use_action])
	if bool((chained_tiesuo_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_chained_tiesuo=%s" % [chained_tiesuo_choice])
	# 敌方对领袖使用【闪电】；低命中且会传递的延时锦囊不值得消耗最后一张无懈。
	var enemy_lightning_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"shandian", "source_id":1, "target_id":0, "negated":false}}
	# 闪电响应选择；即使目标为自己且来源敌对，也应明确保留无懈。
	var enemy_lightning_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_lightning_request, [pass_action, use_action])
	if bool((enemy_lightning_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_enemy_lightning=%s" % [enemy_lightning_choice])
	# 敌方对1体力领袖使用【南蛮入侵】；领袖已有一张【杀】时可以直接响应，应下调使用无懈的收益。
	(snapshot.get("players", []) as Array)[0]["hp"] = 1
	var enemy_nanman_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"nanman", "source_id":1, "target_id":0, "negated":false}}
	# 资源充足时的南蛮响应；已知【杀】能够承担本次防御，保留最后一张无懈。
	var supplied_nanman_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_nanman_request, [pass_action, use_action])
	if bool((supplied_nanman_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_nanman_with_sha=%s" % [supplied_nanman_choice])
	# 移除领袖【杀】后的手牌；同一锦囊现在会造成致命伤害，且没有直接响应资源。
	(snapshot.get("players", []) as Array)[0]["hand"] = [_card(201, "wuxie", 0)]
	(snapshot.get("players", []) as Array)[0]["hand_count"] = 1
	# 资源不足时的南蛮响应；致命关键牌应允许动用最后一张无懈。
	var unsupported_nanman_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_nanman_request, [pass_action, use_action])
	if not bool((unsupported_nanman_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_nanman_without_sha=%s" % [unsupported_nanman_choice])
	# 恢复安全体力并验证普通牌差锦囊；只有最后一张无懈时应为后续关键牌保留。
	(snapshot.get("players", []) as Array)[0]["hp"] = 4
	var enemy_guohe_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"guohe", "source_id":1, "target_id":0, "negated":false}}
	# 最后一张无懈面对普通过河拆桥；储备策略应选择放弃。
	var reserved_guohe_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_guohe_request, [pass_action, use_action])
	if bool((reserved_guohe_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_last_copy_reserve=%s" % [reserved_guohe_choice])
	# 领袖持有【桃】时的手牌；敌方拆牌会破坏明确的保命资源，最后一张无懈必须改为保护。
	(snapshot.get("players", []) as Array)[0]["hand"] = [_card(201, "wuxie", 0), _card(203, "tao", 0)]
	(snapshot.get("players", []) as Array)[0]["hand_count"] = 2
	# 关键【桃】面对【过河拆桥】的响应；通用资源保护应确认无懈。
	var protected_guohe_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_guohe_request, [pass_action, use_action])
	if not bool((protected_guohe_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_protect_tao_from_guohe=%s" % [protected_guohe_choice])
	# 敌方【顺手牵羊】请求；同样通过通用 steal_target 牌效读取关键资源，而非对牌名写死分支。
	var enemy_shunshou_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"shunshou", "source_id":1, "target_id":0, "negated":false}}
	# 关键【桃】面对【顺手牵羊】的响应；应确认无懈，避免关键牌被敌方获得。
	var protected_shunshou_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_shunshou_request, [pass_action, use_action])
	if not bool((protected_shunshou_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_protect_tao_from_shunshou=%s" % [protected_shunshou_choice])
	# 仅一张无懈的手牌；敌方【无中生有】能稳定获得两张牌，应纳入所有锦囊的通用收益计算并被抵消。
	(snapshot.get("players", []) as Array)[0]["hand"] = [_card(201, "wuxie", 0)]
	(snapshot.get("players", []) as Array)[0]["hand_count"] = 1
	var enemy_wuzhong_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"wuzhong", "source_id":1, "target_id":1, "negated":false}}
	# 敌方两张摸牌的无懈响应；应确认，证明无懈不再只按少数牌名做关键性判断。
	var enemy_wuzhong_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_wuzhong_request, [pass_action, use_action])
	if not bool((enemy_wuzhong_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_block_enemy_wuzhong=%s" % [enemy_wuzhong_choice])
	# 第二张无懈副本；资源不再稀缺时可以抵消明确不利的普通锦囊。
	(snapshot.get("players", []) as Array)[0]["hand"] = [_card(201, "wuxie", 0), _card(202, "wuxie", 0)]
	(snapshot.get("players", []) as Array)[0]["hand_count"] = 2
	var surplus_guohe_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_guohe_request, [pass_action, use_action])
	if not bool((surplus_guohe_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_surplus_copy=%s" % [surplus_guohe_choice])
	return true


## 验证【酒】只为当前合法且能从加伤取得正边际收益的【杀】使用，并把白银狮子的预期承伤封顶为1点。
func _test_wine_action_value_and_baiyin_damage_cap() -> bool:
	# 全身份公开快照；领袖0持有【酒】与【杀】，反贼1作为唯一合法攻击目标。
	var snapshot: Dictionary = _build_snapshot(true)
	var actor: Dictionary = (snapshot.get("players", []) as Array)[0] as Dictionary
	actor["hand"] = [_card(101, "sha", 0), _card(102, "jiu", 0)]
	actor["hand_count"] = 2
	# 【酒】与【杀】合法动作；结束阶段动作作为0分基线，确保无意义喝酒会被明确拒绝。
	var wine_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":102, "card_definition_id":"jiu", "target_ids":[0], "payload":{}}
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	var end_action: Dictionary = {"action_type":"end_play", "actor_id":0}
	# 本阶段【杀】已经不可用的动作集合；手里仍有【杀】也不能让AI空喝【酒】。
	var no_legal_slash_choice: Dictionary = _policy.choose_action(snapshot, [wine_action, end_action])
	if str(no_legal_slash_choice.get("action_type", "")) != "end_play":
		return _fail("wine_without_legal_slash=%s" % [no_legal_slash_choice])
	# 无防具敌人；酒后2点伤害产生真实正边际收益，AI应先使用【酒】而不是直接出【杀】。
	var profitable_wine_choice: Dictionary = _policy.choose_action(snapshot, [wine_action, slash_action, end_action])
	if str(profitable_wine_choice.get("card_definition_id", "")) != "jiu":
		return _fail("wine_before_profitable_slash=%s" % [profitable_wine_choice])
	# 反向枚举顺序；即使规则先列出【杀】，连续评分也必须识别酒杀链路并稳定选择先喝酒。
	var slash_first_wine_choice: Dictionary = _policy.choose_action(snapshot, [slash_action, wine_action, end_action])
	if str(slash_first_wine_choice.get("card_definition_id", "")) != "jiu":
		return _fail("wine_before_slash_regardless_of_enumeration=%s" % [slash_first_wine_choice])
	# 已经没有可执行【杀】时的后续决策；只剩【酒】必须直接结束出牌，不能产生“先杀后喝酒”的空行动。
	actor["hand"] = [_card(102, "jiu", 0)]
	actor["hand_count"] = 1
	var post_slash_wine_choice: Dictionary = _policy.choose_action(snapshot, [wine_action, end_action])
	if str(post_slash_wine_choice.get("action_type", "")) != "end_play":
		return _fail("wine_after_slash_without_follow_up=%s" % [post_slash_wine_choice])
	# 还原后续白银狮子场景所需的【杀】实体与手牌数量。
	actor["hand"] = [_card(101, "sha", 0), _card(102, "jiu", 0)]
	actor["hand_count"] = 2
	# 白银狮子目标；其单次承伤固定封顶1点，普通杀与酒杀的目标收益应完全相同。
	var target: Dictionary = (snapshot.get("players", []) as Array)[1] as Dictionary
	# 白银狮子装备快照；区域字段保持equipment，供离区与防具语义统一识别。
	var baiyin_armor: Dictionary = _card(701, "baiyin", 1)
	baiyin_armor["zone"] = "equipment"
	target["equipment"] = {"armor":baiyin_armor}
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	var slash_definition: Dictionary = GameDatabase.get_card("sha")
	var slash_ai: Dictionary = evaluator.get_card_ai_profile(slash_definition)
	var plain_score: float = evaluator.score_target_effect(snapshot, 0, 1, slash_definition, slash_ai, float(slash_ai.get("target_result", -1.0)), "black", 1)
	var wine_score: float = evaluator.score_target_effect(snapshot, 0, 1, slash_definition, slash_ai, float(slash_ai.get("target_result", -1.0)), "black", 2)
	if not is_equal_approx(plain_score, wine_score):
		return _fail("baiyin_damage_cap plain=%.3f wine=%.3f" % [plain_score, wine_score])
	# 同一合法动作集合面对白银狮子；【酒】没有边际收益，AI应直接出【杀】而不是酒杀。
	var baiyin_choice: Dictionary = _policy.choose_action(snapshot, [wine_action, slash_action, end_action])
	if str(baiyin_choice.get("card_definition_id", "")) != "sha":
		return _fail("wine_against_baiyin=%s" % [baiyin_choice])
	return true


## 验证技能文件内的【军势】AI 会确认令友方摸牌，并取消令敌方摸牌。
func _test_skill_confirmation() -> bool:
	# 全身份公开快照；忠臣2为友方，反贼1为敌方。
	var snapshot: Dictionary = _build_snapshot(true)
	# 零材料取消动作；布尔请求通过 confirmed 区分结果。
	var pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":2, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	# 零材料确认动作；由 ai_allow_confirm 请求枚举。
	var confirm_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":2, "selected_card_uids":[], "selected_target_ids":[], "confirmed":true}}
	# 友方使用【杀】时的军势确认请求。
	var friend_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":0, "candidates":[], "context":{"kind":"junshi_confirm", "skill_id":"junshi", "skill_owner_id":0, "slash_user_id":2, "ai_allow_confirm":true}}
	# 友方军势选择结果；应确认发动技能。
	var friend_choice: Dictionary = _policy.choose_card_choice(snapshot, friend_request, [pass_action, confirm_action])
	if not bool((friend_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("junshi_friend=%s" % [friend_choice])
	# 敌方使用【杀】时不应发动军势。
	var enemy_request: Dictionary = friend_request.duplicate(true)
	(enemy_request.get("context", {}) as Dictionary)["slash_user_id"] = 1
	# 敌方军势选择结果；应取消发动技能。
	var enemy_choice: Dictionary = _policy.choose_card_choice(snapshot, enemy_request, [pass_action, confirm_action])
	if bool((enemy_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("junshi_enemy=%s" % [enemy_choice])
	return true


## 验证两项领袖技的 AI 会选择帮助可感知友方，并拒绝为敌方支付费用或提供重铸机会。
func _test_leader_skill_confirmation() -> bool:
	# 全身份公开快照；把领袖武将设为布洛妮娅，并让忠臣2成为另一名贝洛伯格角色。
	var snapshot: Dictionary = _build_snapshot(true)
	(snapshot.get("players", []) as Array)[0]["character_id"] = "bronya"
	(snapshot.get("players", []) as Array)[2]["character_id"] = "xier"
	# 文字选项请求动作；取消、弃牌和失去体力分别使用独立控制项 ID。
	var pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":4, "selected_control_id":"", "confirmed":false}}
	var discard_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":4, "selected_control_id":"discard_hand", "confirmed":true}}
	var lose_hp_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":4, "selected_control_id":"lose_hp", "confirmed":true}}
	# 振旗友方费用请求；弃牌费用低于失去体力，且另一名贝洛伯格忠臣形成正收益。
	var zhenqi_request: Dictionary = {"choice_type":"control", "allow_cancel":true, "min_select":1, "max_select":1, "min_card_select":0, "max_card_select":0, "control_options":[{"id":"discard_hand", "label":"弃牌"}, {"id":"lose_hp", "label":"失去体力"}], "context":{"kind":"zhenqi_cost_option", "skill_id":"zhenqi", "skill_owner_id":0, "turn_player_id":0}}
	var zhenqi_friend_choice: Dictionary = _policy.choose_card_choice(snapshot, zhenqi_request, [pass_action, discard_action, lose_hp_action])
	if str((zhenqi_friend_choice.get("payload", {}) as Dictionary).get("selected_control_id", "")) != "discard_hand":
		return _fail("zhenqi_friend=%s" % [zhenqi_friend_choice])
	# 移除另一名贝洛伯格角色；没有正收益受益者时应取消，而不是无条件支付任一费用。
	(snapshot.get("players", []) as Array)[2]["character_id"] = "himeko"
	var zhenqi_no_friend_choice: Dictionary = _policy.choose_card_choice(snapshot, zhenqi_request, [pass_action, discard_action, lose_hp_action])
	if bool((zhenqi_no_friend_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("zhenqi_no_friend=%s" % [zhenqi_no_friend_choice])
	# 领航零材料确认请求；对忠臣来源角色确认，对反贼来源角色取消。
	var confirm_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":5, "selected_card_uids":[], "selected_target_ids":[], "confirmed":true}}
	var linghang_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":0, "candidates":[], "context":{"kind":"linghang_confirm", "skill_id":"linghang", "skill_owner_id":0, "source_player_id":2, "ai_allow_confirm":true}}
	var linghang_friend_choice: Dictionary = _policy.choose_card_choice(snapshot, linghang_request, [pass_action, confirm_action])
	if not bool((linghang_friend_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("linghang_friend=%s" % [linghang_friend_choice])
	(linghang_request.get("context", {}) as Dictionary)["source_player_id"] = 1
	var linghang_enemy_choice: Dictionary = _policy.choose_card_choice(snapshot, linghang_request, [pass_action, confirm_action])
	if bool((linghang_enemy_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("linghang_enemy=%s" % [linghang_enemy_choice])
	return true


## 验证【领航】来源角色会重铸保留价值最低的普通手牌，并在所有候选价值不低于未知摸牌价值时取消。
func _test_linghang_recast_choice() -> bool:
	# 全身份公开快照；玩家2作为领航来源角色，独立策略只负责其自身的重铸选择。
	var snapshot: Dictionary = _build_snapshot(true)
	(snapshot.get("players", []) as Array)[2]["hand"] = [_card(701, "tiesuo", 2), _card(702, "tao", 2)]
	(snapshot.get("players", []) as Array)[2]["hand_count"] = 2
	# 来源角色策略；技能持有者仍为领袖0，二者必须通过上下文字段解耦。
	var source_policy: BasicAIPolicy = BasicAIPolicy.new(2, IdentityAIModel.new())
	# 取消与两张候选牌的合法动作；正式控制器会从同一请求生成等价枚举。
	var pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":2, "payload":{"request_id":6, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	var recast_tiesuo_action: Dictionary = {"action_type":"choose_cards", "actor_id":2, "payload":{"request_id":6, "selected_card_uids":[701], "selected_target_ids":[], "confirmed":true}}
	var recast_tao_action: Dictionary = {"action_type":"choose_cards", "actor_id":2, "payload":{"request_id":6, "selected_card_uids":[702], "selected_target_ids":[], "confirmed":true}}
	# 低价值【铁索连环】与高价值【桃】候选；未知摸牌价值4.5应只接受价值4.0的前者。
	var recast_request: Dictionary = {"allow_cancel":true, "min_card_select":1, "max_card_select":1, "candidates":[_candidate(701, "tiesuo", 2), _candidate(702, "tao", 2)], "context":{"kind":"linghang_recast", "skill_id":"linghang", "skill_owner_id":0, "source_player_id":2}}
	var low_value_choice: Dictionary = source_policy.choose_card_choice(snapshot, recast_request, [pass_action, recast_tiesuo_action, recast_tao_action])
	if (low_value_choice.get("payload", {}) as Dictionary).get("selected_card_uids", []) != [701]:
		return _fail("linghang_recast_lowest=%s" % [low_value_choice])
	# 只保留价值9.0的【桃】时，4.5减9.0不为正，AI应提交取消而不是滞留请求。
	(snapshot.get("players", []) as Array)[2]["hand"] = [_card(702, "tao", 2)]
	(snapshot.get("players", []) as Array)[2]["hand_count"] = 1
	var expensive_request: Dictionary = recast_request.duplicate(true)
	expensive_request["candidates"] = [_candidate(702, "tao", 2)]
	var expensive_choice: Dictionary = source_policy.choose_card_choice(snapshot, expensive_request, [pass_action, recast_tao_action])
	if bool((expensive_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("linghang_recast_cancel=%s" % [expensive_choice])
	return true


## 验证 AI 选择主动技能后会把稳定 skill_id 写入 PlayerAction.payload，统一提交入口能够识别。
func _test_active_skill_payload() -> bool:
	# 行军收益快照；领袖无手牌，忠臣状态良好，跳过当前阶段具有正收益。
	var snapshot: Dictionary = _build_snapshot(true)
	(snapshot.get("players", []) as Array)[0]["hand_count"] = 0
	(snapshot.get("players", []) as Array)[0]["hand"] = []
	# 行军合法动作；同时保留旧顶层 skill_id 供内容枚举和调试展示。
	var skill_action: Dictionary = {"action_type":"use_skill", "actor_id":0, "skill_id":"xingjun", "target_ids":[], "payload":{"skill_id":"xingjun"}}
	# 主动技能选择结果；标准 payload 中必须保留稳定技能 ID。
	var chosen: Dictionary = _policy.choose_action(snapshot, [skill_action])
	if str((chosen.get("payload", {}) as Dictionary).get("skill_id", "")) != "xingjun":
		return _fail("active_skill_payload=%s" % [chosen])
	return true


## 验证追歼敌我目标、秘策目标阶段组合、勘测牌类倾向与求生致命伤害修正。
func _test_peila_lingke_skill_ai() -> bool:
	# 完整公开身份快照；佩拉为领袖，二号反贼与三号忠臣提供稳定敌我态度。
	var snapshot: Dictionary = _build_snapshot(true)
	# 快照玩家数组；后续分别调整佩拉手牌、敌方超限牌量与玲可生存条件。
	var players: Array = snapshot.get("players", []) as Array
	# 佩拉本人快照；3点体力与两张完整可见手牌用于计算自身额外出牌阶段收益。
	var peila_player: Dictionary = players[0] as Dictionary
	peila_player["character_id"] = "peila"
	peila_player["hp"] = 3
	peila_player["max_hp"] = 3
	peila_player["hand"] = [_card(101, "sha", 0), _card(201, "wuxie", 0)]
	peila_player["hand_count"] = 2
	peila_player["hand_limit_bonus"] = 0
	peila_player["mode_hand_limit_bonus"] = 0
	# 敌方反贼快照；2点体力却有8张牌，使“摸1张后额外弃牌阶段”产生稳定的大额失牌收益。
	var rebel_player: Dictionary = players[1] as Dictionary
	rebel_player["hp"] = 2
	rebel_player["hand_count"] = 8
	rebel_player["hand"] = []
	rebel_player["hand_limit_bonus"] = 0
	rebel_player["mode_hand_limit_bonus"] = 0
	# 忠臣快照；正常牌量提供可比较的友方额外出牌收益，但不应压过敌方严重超限弃牌收益。
	var loyalist_player: Dictionary = players[2] as Dictionary
	loyalist_player["hp"] = 4
	loyalist_player["hand_count"] = 4
	loyalist_player["hand_limit_bonus"] = 0
	loyalist_player["mode_hand_limit_bonus"] = 0
	# 通用AI评估器；技能纯查询评分不得依赖运行时控制器或界面节点。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 追歼静态技能；同一低价值费用下应严格偏好敌方目标而不是忠臣目标。
	var zhuijian: SkillDefinition = GameDatabase.create_skill("zhuijian")
	zhuijian.bind(null, 0)
	var zhuijian_request: Dictionary = {"candidates":[_candidate(201, "wuxie", 0)], "context":{"kind":"zhuijian_cost_target"}}
	var zhuijian_enemy_action: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[201], "selected_target_ids":[1]}}
	var zhuijian_friend_action: Dictionary = {"payload":{"confirmed":true, "selected_card_uids":[201], "selected_target_ids":[2]}}
	if zhuijian.score_ai_choice(snapshot, zhuijian_request, zhuijian_enemy_action, evaluator) <= zhuijian.score_ai_choice(snapshot, zhuijian_request, zhuijian_friend_action, evaluator):
		return _fail("zhuijian_enemy_priority")
	# 秘策复合选择请求；基础策略必须比较完整“目标×阶段”动作而非先独立选目标再固定选项。
	var mice_request: Dictionary = {"allow_cancel":true, "choice_type":"target_control", "min_select":1, "max_select":1, "min_target_select":1, "max_target_select":1, "target_ids":[1, 2], "control_options":[{"id":"play_phase", "label":"出牌阶段"}, {"id":"discard_phase", "label":"弃牌阶段"}], "context":{"kind":"mice_target_option", "skill_id":"mice", "skill_owner_id":0}}
	# 秘策取消动作；所有组合收益不为正时可由策略保留此0分边界。
	var mice_pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":6101, "selected_card_uids":[], "selected_target_ids":[], "selected_control_id":"", "confirmed":false}}
	# 四个目标阶段组合；当前局面应选择让严重超限敌人执行弃牌阶段，并由佩拉获得额外出牌阶段。
	var mice_actions: Array[Dictionary] = [mice_pass_action]
	for target_id: int in [1, 2]:
		for option_id: String in ["play_phase", "discard_phase"]:
			# 当前合法复合动作；目标与选项通过同一payload提交。
			var mice_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":6101, "selected_card_uids":[], "selected_target_ids":[target_id], "selected_control_id":option_id, "confirmed":true}}
			mice_actions.append(mice_action)
	var mice_policy: BasicAIPolicy = BasicAIPolicy.new(0, IdentityAIModel.new())
	var chosen_mice_action: Dictionary = mice_policy.choose_card_choice(snapshot, mice_request, mice_actions)
	var chosen_mice_payload: Dictionary = chosen_mice_action.get("payload", {}) as Dictionary
	if (chosen_mice_payload.get("selected_target_ids", []) as Array) != [1] or str(chosen_mice_payload.get("selected_control_id", "")) != "discard_phase":
		return _fail("mice_combination_choice=%s" % [chosen_mice_action])
	# 勘测静态技能；满体力时属性杀行动价值高于保留桃，低体力时桃的生存价值反超。
	var kance: SkillDefinition = GameDatabase.create_skill("kance")
	kance.bind(null, 0)
	var kance_slash_action: Dictionary = {"payload":{"target_id":1, "control_id":"nature_slash"}}
	var kance_tao_action: Dictionary = {"payload":{"target_id":1, "control_id":"tao"}}
	if kance.score_ai_action(snapshot, kance_slash_action, evaluator) <= kance.score_ai_action(snapshot, kance_tao_action, evaluator):
		return _fail("kance_full_hp_priority")
	peila_player["hp"] = 1
	var wounded_snapshot: Dictionary = snapshot.duplicate(true)
	if kance.score_ai_action(wounded_snapshot, kance_tao_action, evaluator) <= kance.score_ai_action(wounded_snapshot, kance_slash_action, evaluator):
		return _fail("kance_wounded_priority")
	# 求生目标无桃酒且预计受到致命伤害；AI应识别其会弃置全部手牌并存活至1点，从而降低普通击杀收益。
	var lethal_snapshot: Dictionary = _build_snapshot(true)
	var lethal_players: Array = lethal_snapshot.get("players", []) as Array
	var qiusheng_target: Dictionary = lethal_players[1] as Dictionary
	qiusheng_target["character_id"] = "lingke"
	qiusheng_target["hp"] = 1
	qiusheng_target["max_hp"] = 3
	qiusheng_target["shield"] = 0
	qiusheng_target["hand"] = [_card(711, "wuxie", 1), _card(712, "tiesuo", 1)]
	qiusheng_target["hand_count"] = 2
	var lethal_slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	var qiusheng_score: float = evaluator.score_action(lethal_snapshot, lethal_slash_action, 0)
	qiusheng_target["character_id"] = "gepard"
	var ordinary_lethal_score: float = evaluator.score_action(lethal_snapshot, lethal_slash_action, 0)
	if qiusheng_score >= ordinary_lethal_score:
		return _fail("qiusheng_lethal_score skill=%.3f ordinary=%.3f" % [qiusheng_score, ordinary_lethal_score])
	# 手牌中存在桃时求生不会发动；玲可与无求生目标必须保持相同来牌评分。
	qiusheng_target["hand"] = [_card(713, "tao", 1)]
	qiusheng_target["hand_count"] = 1
	qiusheng_target["character_id"] = "lingke"
	var blocked_qiusheng_score: float = evaluator.score_action(lethal_snapshot, lethal_slash_action, 0)
	qiusheng_target["character_id"] = "gepard"
	var blocked_ordinary_score: float = evaluator.score_action(lethal_snapshot, lethal_slash_action, 0)
	if not is_equal_approx(blocked_qiusheng_score, blocked_ordinary_score):
		return _fail("qiusheng_survival_card_block skill=%.3f ordinary=%.3f" % [blocked_qiusheng_score, blocked_ordinary_score])
	return true


## 验证己方追歼标记会使所有队友的属性伤害优先集火该目标，敌方来源标记不改变本方目标评分。
func _test_zhuijian_teammate_attribute_priority() -> bool:
	# 全身份公开快照；0号领袖施加追歼，2号忠臣使用火杀攻击两名等价反贼目标。
	var snapshot: Dictionary = _build_snapshot(true)
	# 快照玩家数组；追加第二名反贼后形成两个基础状态完全相同的攻击目标。
	var players: Array = snapshot.get("players", []) as Array
	# 行动者快照；补入火杀实体，保证评分读取的实际实体与动作定义一致。
	var actor: Dictionary = players[2] as Dictionary
	actor["hand"] = [_card(420, "sha_fire", 2)]
	actor["hand_count"] = 1
	# 被友方追歼标记的反贼目标；其公开标记来源为同阵营领袖0。
	var marked_target: Dictionary = players[1] as Dictionary
	marked_target["hp"] = 3
	# 补充：追歼仅写入武将牌提示来源条目；公开标记保持空，AI须从该提示识别友方来源0。
	marked_target["character_corner_text_entries"] = {"zhuijian:0":{"text":"追歼", "order":50}}
	marked_target["public_marks"] = {}
	# 未受友方追歼的等价反贼目标；保留敌方来源标记，用于断言不会错误形成协同收益。
	# 补充：对照目标保留伪造的友方旧公开标记，但提示来源为敌方1；它不能获得协同评分，验证AI未回退读取public_marks。
	var comparison_target: Dictionary = {"player_id":3, "identity":"rebel", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"gepard", "character_corner_text_entries":{"zhuijian:1":{"text":"追歼", "order":50}}, "public_marks":{"zhuijian:0":{"count":1, "source_player_id":0}}}
	players.append(comparison_target)
	# 指向友方标记目标的火杀动作；属性伤害应得到固定集火优先级。
	var marked_action: Dictionary = {"action_type":"use_card", "actor_id":2, "card_uid":420, "card_definition_id":"sha_fire", "target_ids":[1], "payload":{}}
	# 指向等价目标的火杀动作；敌方来源的同名标记不应提供加分。
	var comparison_action: Dictionary = {"action_type":"use_card", "actor_id":2, "card_uid":420, "card_definition_id":"sha_fire", "target_ids":[3], "payload":{}}
	# 独立评估器；避免共享测试身份暴露状态影响队友识别。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 两个动作的最终评分；友方追歼目标必须显著高于未受友方标记的等价目标。
	var marked_score: float = evaluator.score_action(snapshot, marked_action, 2)
	var comparison_score: float = evaluator.score_action(snapshot, comparison_action, 2)
	# 补充：追歼不再创建公开标记，通用AI不能从伪造或旧快照的标记得到集火加分，两个等价目标应保持同分。
	# 补充：AI改读提示来源条目后，友方来源0的目标必须比敌方来源1的对照目标至少高出固定4分。
	if marked_score < comparison_score + NonameAIEvaluator.ZHUIJIAN_TEAMMATE_ATTRIBUTE_DAMAGE_PRIORITY_BONUS - 0.01:
		return _fail("zhuijian_teammate_attribute_priority marked=%.3f comparison=%.3f" % [marked_score, comparison_score])
	return true


## 验证强制弃两张牌时选择低价值【杀】与【铁索连环】，保留高价值【桃】。
func _test_low_value_discard() -> bool:
	# 全身份公开快照；手牌实体与候选 UID 保持一致。
	var snapshot: Dictionary = _build_snapshot(true)
	(snapshot.get("players", []) as Array)[0]["hand"] = [_card(301, "tao", 0), _card(302, "sha", 0), _card(303, "tiesuo", 0)]
	(snapshot.get("players", []) as Array)[0]["hand_count"] = 3
	# 三张可见候选；弃牌阶段必须选择两张。
	var request: Dictionary = {"allow_cancel":false, "min_card_select":2, "max_card_select":2, "candidates":[_candidate(301, "tao", 0), _candidate(302, "sha", 0), _candidate(303, "tiesuo", 0)], "context":{"kind":"discard_phase"}}
	# 三种合法二选组合；正式控制器使用相同组合枚举器生成。
	var actions: Array[Dictionary] = [
		{"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":3, "selected_card_uids":[301, 302], "selected_target_ids":[], "confirmed":true}},
		{"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":3, "selected_card_uids":[301, 303], "selected_target_ids":[], "confirmed":true}},
		{"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":3, "selected_card_uids":[302, 303], "selected_target_ids":[], "confirmed":true}},
	]
	# 强制弃牌选择结果；应保留最高价值【桃】。
	var chosen: Dictionary = _policy.choose_card_choice(snapshot, request, actions)
	if (chosen.get("payload", {}) as Dictionary).get("selected_card_uids", []) != [302, 303]:
		return _fail("low_value_discard=%s" % [chosen])
	return true


## 构建三人身份局快照；reveal_all 控制反贼与忠臣身份是否公开。
func _build_snapshot(reveal_all: bool) -> Dictionary:
	# 领袖手牌；提供一张【杀】用于动作价值与重复牌数量计算。
	var leader_hand: Array = [_card(101, "sha", 0), _card(201, "wuxie", 0)]
	return {
		"match_id":"ai_policy_test",
		"players":[
			{"player_id":0, "identity":"leader", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":leader_hand.size(), "hand":leader_hand, "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"xier"},
			{"player_id":1, "identity":"rebel", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":2, "max_hp":4, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"gepard"},
			{"player_id":2, "identity":"loyalist", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":2, "hand":[_card(401, "shan", 2), _card(402, "sha", 2)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"himeko"},
		],
	}


## 构建五人标准身份局快照；包含领袖、反贼、忠臣、内奸和第二名反贼。
func _build_strategy_snapshot(reveal_all: bool) -> Dictionary:
	return {
		"match_id":"ai_identity_strategy_test",
		"players":[
			{"player_id":0, "identity":"leader", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":2, "hand":[_card(501, "sha", 0), _card(502, "tao", 0)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"xier"},
			{"player_id":1, "identity":"rebel", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "hand_count":1, "hand":[_card(511, "sha", 1)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"gepard"},
			{"player_id":2, "identity":"loyalist", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":2, "hand":[_card(521, "shan", 2), _card(522, "tao", 2)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"himeko"},
			{"player_id":3, "identity":"renegade", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "hand_count":2, "hand":[_card(531, "sha", 3), _card(532, "tao", 3)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"bronya"},
			{"player_id":4, "identity":"rebel", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "hand_count":1, "hand":[_card(541, "sha", 4)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"danheng"},
		],
	}


## 调整五人快照的阵营强度；loyal_side_strong 为 true 时领忠占优，否则反贼占优。
func _set_camp_strength(snapshot: Dictionary, loyal_side_strong: bool) -> void:
	# 快照玩家数组；固定测试构造保证座次0至4分别对应既定身份。
	var players: Array = snapshot.get("players", []) as Array
	# 强势方体力；4点用于形成稳定局势差。
	var strong_hp: int = 4
	# 弱势方体力；1点用于形成稳定局势差。
	var weak_hp: int = 1
	# 强势方手牌数；6张用于显著提高 condition 与 situation。
	var strong_hand_count: int = 6
	# 弱势方手牌数；0张表示缺乏防御与行动资源。
	var weak_hand_count: int = 0
	for index: int in range(players.size()):
		# 当前测试玩家；身份字段决定其属于领忠方、反贼方或中立内奸。
		var player: Dictionary = players[index] as Dictionary
		# 当前玩家是否属于领忠阵营；领袖与忠臣共同取相同强弱状态。
		var is_loyal_side: bool = str(player.get("identity", "")) in ["leader", "loyalist"]
		# 当前玩家是否属于反贼阵营；两名反贼共同取相同强弱状态。
		var is_rebel_side: bool = str(player.get("identity", "")) == "rebel"
		if is_loyal_side:
			player["hp"] = strong_hp if loyal_side_strong else weak_hp
			player["hand_count"] = strong_hand_count if loyal_side_strong else weak_hand_count
		elif is_rebel_side:
			player["hp"] = weak_hp if loyal_side_strong else strong_hp
			player["hand_count"] = weak_hand_count if loyal_side_strong else strong_hand_count


## 构建一张可见选择候选；字段与 MatchController 的统一候选快照保持一致。
func _candidate(uid: int, definition_id: String, owner_id: int) -> Dictionary:
	return {"uid":uid, "owner_id":owner_id, "zone":"hand", "slot":"", "visible":true, "card_data":_card(uid, definition_id, owner_id)}


## 构建最小实体牌快照；AI 测试只需要 UID、定义 ID、区域和持有者。
func _card(uid: int, definition_id: String, owner_id: int) -> Dictionary:
	return {"uid":uid, "definition_id":definition_id, "suit":"spade", "rank":1, "color":"black", "zone":"hand", "owner_id":owner_id}


## 输出失败原因并以状态1结束测试；返回false便于调用方直接中止后续断言。
func _fail(reason: String) -> bool:
	printerr("AI_POLICY_FAIL %s" % reason)
	get_tree().quit(1)
	return false
