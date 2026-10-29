extends Node

## 卖血决策回归；从真实内容定义和合法候选验证攻击、闪避、技能额度与伤害边界。

## 独立收益评估器；不共享其他场景身份观察历史，所有评分只能依赖本例快照。
var _evaluator: NonameAIEvaluator = NonameAIEvaluator.new()

## 累计失败数；全部断言跑完后统一决定退出码，以便一次查看所有行为回归。
var _failures: int = 0


## 执行卖血模型与策略层回归；测试不安装技能时机，不改写正式对局设置。
func _ready() -> void:
	_test_enemy_and_ally_attacks()
	_test_damage_limits_and_instances()
	_test_meizhan_observers_and_repeated_hits()
	_test_response_choices()
	_test_armor_and_chain()
	if _failures == 0:
		print("SELL_BLOOD_AI_PASS")
	get_tree().quit(0 if _failures == 0 else 1)


## 普通卖血收益不能成为拒绝攻击敌人的绝对禁令，也不足以让AI白白打伤队友。
func _test_enemy_and_ally_attacks() -> void:
	# 全公开阵营快照；敌人与友方都具有单份百折。
	var snapshot: Dictionary = _snapshot()
	_player(snapshot, 1)["mode_skill_ids"] = ["baizhe"]
	_player(snapshot, 2)["mode_skill_ids"] = ["baizhe"]
	# 攻击者策略与两项合法动作；先枚举队友，确保选择敌人不是枚举顺序造成的偶然。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0)
	# 本轮两项合法攻击候选；同时比较友方与敌方，避免单项分数遗漏。
	var attacks: Array[Dictionary] = [_attack(2), _attack(1)]
	# 策略最终返回的动作；断言目标而非只核对分数。
	var selected: Dictionary = policy.choose_action(snapshot, attacks)
	_check(selected.get("target_ids", []) == [1], "attack_sell_blood_enemy")
	_check(str(policy.choose_action(snapshot, [_attack(2)]).get("action_type", "")) == "end_play", "do_not_farm_one_value_ally")
	# 致命窗口；不预支死后收益，攻击价值与没有卖血技能时相同。
	_player(snapshot, 1)["hp"] = 1
	# 卖血目标处于击杀线时的基准评分；与无技能对照组比较。
	var lethal_score: float = _evaluator.score_action(snapshot, _attack(1), 0)
	_player(snapshot, 1)["mode_skill_ids"] = []
	_check(is_equal_approx(lethal_score, _evaluator.score_action(snapshot, _attack(1), 0)), "lethal_enemy_benefit_zero")
	_player(snapshot, 1)["mode_skill_ids"] = ["baizhe"]
	_check(str(policy.choose_action(snapshot, [_attack(1)]).get("action_type", "")) == "use_card", "finish_critical_enemy")


## 百折按最终伤害点而非伤害事件计价，受当回合每份实例三次上限约束。
func _test_damage_limits_and_instances() -> void:
	# 高体力持有者；两点伤害不会触及濒死，便于单独核对逐点额度。
	var snapshot: Dictionary = _snapshot()
	_player(snapshot, 2)["mode_skill_ids"] = ["baizhe"]
	_check(is_equal_approx(_benefit(snapshot, 2, 2, 2), 4.0), "baizhe_per_hp_point")
	# 当前实例三次真实逐点发动记录；主动发动记录和上回合记录不得额外消耗本回合额度。
	var history: Array[Dictionary] = []
	for index: int in range(3):
		history.append({"skill_id":"baizhe", "instance_key":"baizhe", "turn_number":7, "context":{"mark_id":"douzhi", "damage_point_index":index + 1}})
	_player(snapshot, 2)["skill_history"] = history
	_check(is_zero_approx(_benefit(snapshot, 2, 1, 2)), "baizhe_exhausted")
	history.pop_back()
	_check(is_equal_approx(_benefit(snapshot, 2, 2, 2), 2.0), "baizhe_remaining_one_gain")
	snapshot["turn_number"] = 8
	_check(is_equal_approx(_benefit(snapshot, 2, 2, 2), 4.0), "baizhe_new_turn_resets")
	snapshot["turn_number"] = 7
	_player(snapshot, 2)["acquired_skills"] = {"baizhe#2":{"skill_id":"baizhe"}}
	_check(is_equal_approx(_benefit(snapshot, 2, 1, 2), 4.0), "separate_instance_budgets")
	_player(snapshot, 2)["shield"] = 2
	_check(is_equal_approx(_benefit(snapshot, 2, 2, 2), 6.0), "baizhe_shield_still_counts_damage_points")
	_check(is_equal_approx(_benefit(snapshot, 2, 3, 2), 8.0), "baizhe_partial_shield_counts_damage_points")
	# 三份百折可把被护盾吸收的伤害转成足够斗志，证明护盾语义由技能决定而非通用硬禁令。
	_player(snapshot, 2)["acquired_skills"] = {"baizhe#2":{"skill_id":"baizhe"}, "baizhe#3":{"skill_id":"baizhe"}}
	_check(_evaluator.should_accept_sell_blood_damage(snapshot, 0, 2, 1), "shielded_point_skill_can_accept_when_profitable")
	_player(snapshot, 2)["alive"] = false
	_check(is_zero_approx(_benefit(snapshot, 2, 3, 2)), "dead_target_no_income")


## 梅绽按伤害事件只计算一次全体摸牌；每次新快照重新比较体力成本，避免持续刷低队友体力。
func _test_meizhan_observers_and_repeated_hits() -> void:
	# 三名我方持有梅绽；单次1点伤害能换三张我方牌，是可行的协作窗口。
	var snapshot: Dictionary = _snapshot()
	for player_id: int in [0, 2, 3]:
		_player(snapshot, player_id)["mode_skill_ids"] = ["meizhan"]
	# 按每名真实受益者计算的基准收入；包含受伤者本人且不重复。
	var expected_income: float = 0.0
	for player_id: int in [0, 2, 3]:
		expected_income += _evaluator.score_resource_change(snapshot, 0, player_id, 1, 0)
	_check(is_equal_approx(_benefit(snapshot, 2, 1, 0), expected_income), "meizhan_all_holders_once")
	_check(is_equal_approx(_benefit(snapshot, 2, 2, 0), expected_income), "meizhan_not_per_hp")
	_check(_evaluator.should_accept_sell_blood_damage(snapshot, 0, 2, 1), "safe_team_income_accept")
	# 同一张快照不能在评分中被改写；连续调用的值必须稳定。
	var before: Dictionary = snapshot.duplicate(true)
	_evaluator.score_action(snapshot, _attack(2), 0)
	_check(snapshot == before, "evaluation_read_only")
	# 当前玩家的独立策略；每次决策会清理临时上下文。
	var policy: BasicAIPolicy = BasicAIPolicy.new(0)
	_check(str(policy.choose_action(snapshot, [_attack(2)]).get("action_type", "")) == "use_card", "profitable_ally_hit_allowed")
	_player(snapshot, 2)["hp"] = 2
	_check(not _evaluator.should_accept_sell_blood_damage(snapshot, 0, 2, 1), "stop_farming_at_critical_hp")
	_check(str(policy.choose_action(snapshot, [_attack(2)]).get("action_type", "")) == "end_play", "attack_stops_at_critical_hp")
	_player(snapshot, 2)["hp"] = 4
	_player(snapshot, 3)["out_of_game"] = true
	_check(_benefit(snapshot, 2, 1, 0) < expected_income, "out_of_game_holder_excluded")
	_player(snapshot, 3)["out_of_game"] = false
	_player(snapshot, 3)["identity"] = "rebel"
	_check(not _evaluator.should_accept_sell_blood_damage(snapshot, 0, 2, 1), "enemy_holders_reduce_income")
	_player(snapshot, 3)["identity_revealed"] = false
	# 独立身份模型；此前公开快照不能给隐藏持有者残留暴露度。
	var hidden: NonameAIEvaluator = NonameAIEvaluator.new()
	_check(is_zero_approx(hidden.get_attitude(snapshot, 0, 3)), "hidden_holder_attitude_zero")
	_player(snapshot, 2)["installed_skill_ids"] = []
	_check(is_zero_approx(_benefit(snapshot, 2, 1, 0)), "lost_skill_no_phantom_income")


## 真正的响应候选必须遵循同一净收益判断；覆盖杀、范围伤害和决斗，且致命伤害始终防御。
func _test_response_choices() -> void:
	# 三名友方梅绽持有者；敌方打来的1点伤害同样允许按自身收益主动承受。
	var snapshot: Dictionary = _snapshot()
	for player_id: int in [0, 2, 3]:
		_player(snapshot, player_id)["mode_skill_ids"] = ["meizhan"]
	for kind: String in ["slash_response", "aoe_response", "duel_response"]:
		_check(not _chooses_response(snapshot, kind, 1, 1), "profitable_response_pass_" + kind)
		_check(_chooses_response(snapshot, kind, 1, 4), "lethal_response_defend_" + kind)
	_check(not _chooses_response(snapshot, "duel_response", 1, 1, {"direct_response_count":6}), "ordinary_duel_does_not_escalate")
	_player(snapshot, 1)["mode_skill_ids"] = ["zhidong"]
	_check(not _chooses_response(snapshot, "duel_response", 1, 1, {"direct_response_count":6, "direct_response_count_excluding_source":0}), "zhidong_excludes_own_responses")
	_check(_chooses_response(snapshot, "duel_response", 1, 1, {"direct_response_count":6, "direct_response_count_excluding_source":3}), "zhidong_real_lethal_bonus_defend")
	_player(snapshot, 2)["shield"] = 1
	_check(_chooses_response(snapshot, "slash_response", 0, 1), "shield_no_sell_blood_pass")
	_player(snapshot, 2)["shield"] = 0
	_player(snapshot, 2)["hp"] = 1
	_check(_chooses_response(snapshot, "slash_response", 0, 1), "ally_lethal_must_dodge")


## 防具必须先修正伤害，再判断实际掉血和卖血收益；连环继发目标不能遗漏卖血估值。
func _test_armor_and_chain() -> void:
	# 火杀定义与公开防具快照；藤甲对2点火伤固定加1，白银狮子把3点伤害压至1。
	var snapshot: Dictionary = _snapshot()
	# 正式火杀元数据；属性由内容定义提供，不依靠测试伪造。
	var fire: Dictionary = GameDatabase.get_card("sha_fire")
	_player(snapshot, 2)["equipment"] = {"armor":{"definition_id":"tengjia"}}
	_check(_evaluator.get_expected_damage_amount(snapshot, 0, 2, fire, 2) == 3, "tengjia_add_one")
	_player(snapshot, 2)["equipment"] = {"armor":{"definition_id":"baiyin"}}
	_check(_evaluator.get_expected_damage_amount(snapshot, 0, 2, fire, 3) == 1, "baiyin_cap")
	_player(snapshot, 2)["equipment"] = {}
	_player(snapshot, 1)["chained"] = true
	_player(snapshot, 2)["chained"] = true
	# 没有卖血技能时的传导收益基准；只改变同一继发目标的技能来源。
	var ordinary_score: float = _evaluator.score_action(snapshot, _attack(1, "sha_fire"), 0)
	_player(snapshot, 2)["mode_skill_ids"] = ["meizhan"]
	_check(_evaluator.score_action(snapshot, _attack(1, "sha_fire"), 0) > ordinary_score, "chained_holder_benefit_counted")
	# 存活队友的致命连环风险必须同时拦住卖血分支与原有友方连环分支。
	for player_id: int in [0, 2, 3]:
		_player(snapshot, player_id)["mode_skill_ids"] = ["meizhan"]
	_player(snapshot, 3)["hp"] = 1
	_player(snapshot, 3)["chained"] = true
	_check(_chooses_response(snapshot, "slash_response", 1, 1, {"nature":"fire", "slash_card_definition_id":"sha_fire"}), "enemy_chain_must_protect_lethal_ally")
	_check(_chooses_response(snapshot, "slash_response", 0, 1, {"nature":"fire", "slash_card_definition_id":"sha_fire"}), "legacy_friendly_chain_must_protect_lethal_ally")
	_player(snapshot, 2)["equipment"] = {"armor":{"definition_id":"tengjia"}}
	_player(snapshot, 2)["hp"] = 2
	_check(_chooses_response(snapshot, "slash_response", 0, 1, {"nature":"fire", "slash_card_definition_id":"sha_fire"}), "tengjia_lethal_response_defend")


## 创建全公开四人快照；0号领袖、1号反贼、2与3号忠臣，避免隐藏身份妨碍核心资源断言。
func _snapshot() -> Dictionary:
	# 纯值玩家列表；测试各次调用都获得独立数组和技能列表。
	var players: Array[Dictionary] = []
	for player_id: int in range(4):
		players.append({"player_id":player_id, "identity":"leader" if player_id == 0 else ("rebel" if player_id == 1 else "loyalist"), "identity_revealed":true, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "shield":0, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "character_id":"", "chained":false})
	return {"match_id":"sell_blood_ai_test", "turn_number":7, "players":players}


## 取测试玩家；ID与数组索引固定一致，仅作为夹具访问工具。
func _player(snapshot: Dictionary, player_id: int) -> Dictionary:
	return (snapshot["players"] as Array)[player_id] as Dictionary


## 构造一项规则层已提供的合法用牌候选；测试只检验策略选择，不绕过真实对局执行动作。
func _attack(target_id: int, definition_id: String = "sha") -> Dictionary:
	return {"action_type":"use_card", "actor_id":0, "card_definition_id":definition_id, "target_ids":[target_id]}


## 查询统一收益组件；伤害值已在调用方约定为防具处理后的数值。
func _benefit(snapshot: Dictionary, target_id: int, amount: int, observer_id: int) -> float:
	return _evaluator.sell_blood_evaluator.score_benefit(snapshot, 0, target_id, amount, observer_id, _evaluator)


## 使用真实策略比较确认与取消响应；决斗以当前opponent_id为伤害来源。
func _chooses_response(snapshot: Dictionary, kind: String, source_id: int, amount: int, extra_context: Dictionary = {}) -> bool:
	# 响应模式；范围伤害覆盖闪，决斗覆盖杀，防止只修普通杀分支。
	var pattern: String = "sha" if kind == "duel_response" else "shan"
	# 响应请求与规则允许的候选；候选牌属于2号响应者。
	var request: Dictionary = {"allow_cancel":true, "candidates":[{"uid":9, "owner_id":2, "zone":"hand", "visible":true, "card_data":{"uid":9, "definition_id":pattern}}], "context":{"kind":kind, "actor_id":source_id, "opponent_id":source_id, "target_id":2, "response_patterns":[pattern], "damage_amount":amount, "slash_card_definition_id":"sha"}}
	(request["context"] as Dictionary).merge(extra_context, true)
	# 核心提供的确认和取消候选；确认消耗响应牌，取消不支付。
	var actions: Array[Dictionary] = [{"action_type":"choose_cards", "actor_id":2, "payload":{"confirmed":false}}, {"action_type":"choose_cards", "actor_id":2, "payload":{"confirmed":true, "selected_card_uids":[9]}}]
	# 当前玩家的独立策略；每次决策会清理临时上下文。
	var policy: BasicAIPolicy = BasicAIPolicy.new(2)
	return bool((policy.choose_card_choice(snapshot, request, actions).get("payload", {}) as Dictionary).get("confirmed", false))


## 累积断言失败；不在首个失败时退出，确保所有边界都获得可审查结果。
func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		print("SELL_BLOOD_AI_FAIL " + label)
