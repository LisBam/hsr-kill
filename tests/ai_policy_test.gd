extends Node

## 无名杀式 AI 无头回归。验证身份暴露、牌目标、无懈、技能钩子、主动技能负载与低价值弃牌选择。

## 测试使用的共享身份模型；多项断言复用同一观察状态。
var _identity_model: IdentityAIModel = IdentityAIModel.new()

## 测试使用的主公基础策略；稳定玩家 ID 为0。
var _policy: BasicAIPolicy


## 执行全部 AI 数据与决策断言；任一失败立即以非零状态退出。
func _ready() -> void:
	_policy = BasicAIPolicy.new(0, _identity_model)
	if not _test_all_cards_have_ai_profiles():
		return
	if not _test_identity_exposure():
		return
	if not _test_hidden_identity_strategy_visibility():
		return
	if not _test_identity_rescue_strategy():
		return
	if not _test_renegade_lord_survival():
		return
	if not _test_renegade_balance_strategy():
		return
	if not _test_response_and_threat_strategy():
		return
	if not _test_hostile_card_target():
		return
	if not _test_wuxie_decision():
		return
	if not _test_skill_confirmation():
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
	# 隐藏身份快照；主公身份公开，反贼真实身份仅权威 AI 可见。
	var snapshot: Dictionary = _build_snapshot(false)
	# 行动前态度；目标暴露度为0时应接近中立。
	var before_attitude: float = _identity_model.get_attitude(snapshot, 0, 1)
	# 反贼公开对主公使用【杀】；单目标行为提高其身份暴露度。
	_identity_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [0])
	# 行动后态度；主公对真实反贼的负态度应按新增暴露度显现。
	var after_attitude: float = _identity_model.get_attitude(snapshot, 0, 1)
	if not is_zero_approx(before_attitude) or after_attitude >= -0.5 or _identity_model.get_identity_mark(1) != "rebel" or _identity_model.get_exposure(1) <= 0.0:
		return _fail("identity_exposure before=%.2f after=%.2f" % [before_attitude, after_attitude])
	# 隐藏忠臣公开帮助主公；正面目标行为应形成 loyalist 标记。
	_identity_model.observe_card_use(snapshot, 2, GameDatabase.get_card("tao"), [0])
	if _identity_model.get_identity_mark(2) != "loyalist" or _identity_model.get_exposure(2) <= 0.0:
		return _fail("identity_loyalist_mark mark=%s exposure=%.2f" % [_identity_model.get_identity_mark(2), _identity_model.get_exposure(2)])
	return true


## 验证战略层不会偷看隐藏身份，只有目标产生明确行为标记后才获得阵营集火修正。
func _test_hidden_identity_strategy_visibility() -> bool:
	# 独立身份模型；避免上一项测试的行为标记影响隐藏身份断言。
	var identity_model: IdentityAIModel = IdentityAIModel.new()
	# 独立效用评估器；共享当前测试身份模型。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(identity_model)
	# 隐藏身份快照；反贼1尚未产生任何可观察阵营行为。
	var snapshot: Dictionary = _build_snapshot(false)
	# 主公对隐藏目标使用【杀】的动作；标记出现前不应获得敌方战略奖励。
	var slash_action: Dictionary = {"action_type":"use_card", "actor_id":0, "card_uid":101, "card_definition_id":"sha", "target_ids":[1], "payload":{}}
	# 行为暴露前评分；仅包含卡牌顺序与资源成本，目标牌效态度接近中立。
	var score_before_mark: float = evaluator.score_action(snapshot, slash_action, 0)
	if identity_model.get_perceived_identity(snapshot, 1) != "unknown":
		return _fail("hidden_identity_visible_before_behavior")
	# 隐藏反贼攻击主公；该公开行为形成 rebel 标记。
	identity_model.observe_card_use(snapshot, 1, GameDatabase.get_card("sha"), [0])
	# 行为暴露后评分；敌对态度与反贼威胁集火修正均可正常生效。
	var score_after_mark: float = evaluator.score_action(snapshot, slash_action, 0)
	if identity_model.get_perceived_identity(snapshot, 1) != "rebel" or score_after_mark <= score_before_mark:
		return _fail("hidden_identity_strategy before=%.2f after=%.2f perceived=%s" % [score_before_mark, score_after_mark, identity_model.get_perceived_identity(snapshot, 1)])
	return true


## 验证标准身份救援：忠臣救主、反贼不救主、多人局内奸保主且角色积极自救。
func _test_identity_rescue_strategy() -> bool:
	# 全身份公开的五人快照；公开状态用于单独验证救援阵营规则。
	var snapshot: Dictionary = _build_strategy_snapshot(true)
	# 身份战略评估器；救援测试直接读取其标准救援分数。
	var strategy: IdentityStrategyEvaluator = IdentityStrategyEvaluator.new(IdentityAIModel.new())
	# 忠臣救主评分；应显著高于零并愿意消耗一张9分【桃】。
	var loyalist_score: float = strategy.score_rescue(snapshot, 2, 0, 1, 9.0)
	# 反贼救主评分；应为负数并选择取消响应。
	var rebel_score: float = strategy.score_rescue(snapshot, 1, 0, 1, 9.0)
	# 多人局内奸救主评分；主公提前死亡会破坏内奸胜利路径，因此应为正数。
	var renegade_score: float = strategy.score_rescue(snapshot, 3, 0, 1, 9.0)
	# 角色自救评分；死亡风险下应积极使用自己的救援牌。
	var self_rescue_score: float = strategy.score_rescue(snapshot, 1, 1, 1, 9.0)
	if loyalist_score <= 0.0 or rebel_score >= 0.0 or renegade_score <= 0.0 or self_rescue_score <= 0.0:
		return _fail("identity_rescue loyal=%.2f rebel=%.2f renegade=%.2f self=%.2f" % [loyalist_score, rebel_score, renegade_score, self_rescue_score])
	return true


## 验证内奸在多人局不会对1点体力主公执行预期致命伤害。
func _test_renegade_lord_survival() -> bool:
	# 五人公开身份快照；主公被调整为1点体力以触发提前弑主惩罚。
	var snapshot: Dictionary = _build_strategy_snapshot(true)
	(snapshot.get("players", []) as Array)[0]["hp"] = 1
	# 内奸效用评估器；玩家3为内奸。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 内奸对主公使用【杀】的动作；多人局中该动作应被评为负收益。
	var lethal_lord_action: Dictionary = {"action_type":"use_card", "actor_id":3, "card_uid":601, "card_definition_id":"sha", "target_ids":[0], "payload":{}}
	# 提前弑主动作评分；负数会令基础策略结束出牌或选择其他控场目标。
	var lethal_lord_score: float = evaluator.score_action(snapshot, lethal_lord_action, 3)
	if lethal_lord_score >= 0.0:
		return _fail("renegade_early_lord_kill=%.2f" % lethal_lord_score)
	return true


## 验证内奸根据主忠或反贼优势切换压制目标，保持身份局继续进入可获胜残局。
func _test_renegade_balance_strategy() -> bool:
	# 当前【杀】AI 配置；负面目标牌效用于比较内奸控场附加分。
	var slash_ai: Dictionary = GameDatabase.get_card("sha").get("ai", {}) as Dictionary
	# 主忠明显优势快照；主公与忠臣资源充足，反贼状态较弱。
	var loyal_advantage_snapshot: Dictionary = _build_strategy_snapshot(true)
	_set_camp_strength(loyal_advantage_snapshot, true)
	# 主忠优势时攻击忠臣的控场分；应高于继续压制弱势反贼。
	var loyal_target_score: float = IdentityStrategyEvaluator.new(IdentityAIModel.new()).score_target_strategy(loyal_advantage_snapshot, 3, 2, slash_ai)
	# 主忠优势时攻击反贼的控场分；帮助优势方会受到惩罚。
	var rebel_target_when_loyal_strong: float = IdentityStrategyEvaluator.new(IdentityAIModel.new()).score_target_strategy(loyal_advantage_snapshot, 3, 1, slash_ai)
	# 反贼明显优势快照；反贼资源充足，主忠方进入低体力少手牌状态。
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
	# 主公效用评估器；所有比较共享同一身份关系模型。
	var evaluator: NonameAIEvaluator = NonameAIEvaluator.new(IdentityAIModel.new())
	# 目标没有【闪】时的等量单手牌；使用【无懈可击】保持手牌数量相同。
	(snapshot.get("players", []) as Array)[1]["hand"] = [_card(701, "wuxie", 1)]
	(snapshot.get("players", []) as Array)[1]["hand_count"] = 1
	# 主公对反贼1使用【杀】的标准动作。
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


## 验证无懈可击奇偶逻辑：保护友方免受负面锦囊，且不替敌方抵消同一负面锦囊。
func _test_wuxie_decision() -> bool:
	# 全身份公开快照；主公0、反贼1、忠臣2。
	var snapshot: Dictionary = _build_snapshot(true)
	# 无懈候选实体；响应者本人可见。
	var wuxie_candidate: Dictionary = _candidate(201, "wuxie", 0)
	# 通用放弃动作；confirmed=false 表示本轮不响应。
	var pass_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":1, "selected_card_uids":[], "selected_target_ids":[], "confirmed":false}}
	# 使用无懈动作；实体 UID 来自本次候选。
	var use_action: Dictionary = {"action_type":"choose_cards", "actor_id":0, "payload":{"request_id":1, "selected_card_uids":[201], "selected_target_ids":[], "confirmed":true}}
	# 友方受到乐不思蜀；主公应使用无懈保护忠臣。
	var friend_request: Dictionary = {"allow_cancel":true, "min_card_select":0, "max_card_select":1, "candidates":[wuxie_candidate], "context":{"kind":"trick_negation", "response_patterns":["wuxie"], "trick_id":"lebu", "target_id":2, "negated":false}}
	# 友方无懈选择结果；应确认使用候选牌。
	var friend_choice: Dictionary = _policy.choose_card_choice(snapshot, friend_request, [pass_action, use_action])
	if not bool((friend_choice.get("payload", {}) as Dictionary).get("confirmed", false)):
		return _fail("wuxie_friend=%s" % [friend_choice])
	# 敌方受到乐不思蜀；主公应保留无懈并放弃响应。
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


## 验证 AI 选择主动技能后会把稳定 skill_id 写入 PlayerAction.payload，统一提交入口能够识别。
func _test_active_skill_payload() -> bool:
	# 行军收益快照；主公无手牌，忠臣状态良好，跳过当前阶段具有正收益。
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
	# 主公手牌；提供一张【杀】用于动作价值与重复牌数量计算。
	var lord_hand: Array = [_card(101, "sha", 0), _card(201, "wuxie", 0)]
	return {
		"match_id":"ai_policy_test",
		"players":[
			{"player_id":0, "identity":"lord", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":lord_hand.size(), "hand":lord_hand, "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"xier"},
			{"player_id":1, "identity":"rebel", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":2, "max_hp":4, "hand_count":0, "hand":[], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"trailblazer"},
			{"player_id":2, "identity":"loyalist", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":2, "hand":[_card(401, "shan", 2), _card(402, "sha", 2)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"himeko"},
		],
	}


## 构建五人标准身份局快照；包含主公、反贼、忠臣、内奸和第二名反贼。
func _build_strategy_snapshot(reveal_all: bool) -> Dictionary:
	return {
		"match_id":"ai_identity_strategy_test",
		"players":[
			{"player_id":0, "identity":"lord", "identity_revealed":true, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":2, "hand":[_card(501, "sha", 0), _card(502, "tao", 0)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"xier"},
			{"player_id":1, "identity":"rebel", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "hand_count":1, "hand":[_card(511, "sha", 1)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"trailblazer"},
			{"player_id":2, "identity":"loyalist", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":4, "max_hp":4, "hand_count":2, "hand":[_card(521, "shan", 2), _card(522, "tao", 2)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"himeko"},
			{"player_id":3, "identity":"renegade", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "hand_count":2, "hand":[_card(531, "sha", 3), _card(532, "tao", 3)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"bronya"},
			{"player_id":4, "identity":"rebel", "identity_revealed":reveal_all, "alive":true, "out_of_game":false, "hp":3, "max_hp":4, "hand_count":1, "hand":[_card(541, "sha", 4)], "equipment":{}, "judgment_area":[], "wooden_ox_storage":[], "chained":false, "character_id":"danheng"},
		],
	}


## 调整五人快照的阵营强度；loyal_side_strong 为 true 时主忠占优，否则反贼占优。
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
		# 当前测试玩家；身份字段决定其属于主忠方、反贼方或中立内奸。
		var player: Dictionary = players[index] as Dictionary
		# 当前玩家是否属于主忠阵营；主公与忠臣共同取相同强弱状态。
		var is_loyal_side: bool = str(player.get("identity", "")) in ["lord", "loyalist"]
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
