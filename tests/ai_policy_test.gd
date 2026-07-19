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
	if not _test_renwang_shield_black_slash():
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
	if not _test_active_skill_payload():
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
