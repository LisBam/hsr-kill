extends "res://tests/card_single_sequence_test.gd"

## 主动技能生命周期与响应声明；所有窗口可等待，原响应先关闭，材料和次数不提前消费。


## 最小真实技能入口，隔离生命周期本身；效果仍调用正常伤害和选择API。
class ActivationProbe:
	extends SkillDefinition

	## 主体真实调用次数；取消或换将时必须保持0。
	var activation_count: int = 0

	func _init() -> void:
		super({"id":"activation_probe", "name":"流程测试", "enable":"phaseUse", "trigger":"active", "ui_enabled":true})

	func can_activate(_context: Dictionary = {}) -> bool:
		return true

	func activate(context: Dictionary = {}) -> String:
		activation_count += 1
		if str(context.get("mode", "damage")) == "choose":
			request_target_selection("流程选择", [1], 0, 1, true, {"kind":"activation_body"})
		elif str(context.get("mode", "damage")) == "remove_self":
			host.remove_skill(owner_player_id, get_id())
		elif str(context.get("mode", "damage")) == "damage":
			host.damage(owner_player_id, 1, 1)
		return ""

	func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
		if str(context.get("kind", "")) != "activation_body":
			return false
		if response.confirmed and response.target_ids == [1]:
			host.damage(owner_player_id, 1, 1)
		return true


func _run() -> void:
	for timing_name: String in ["logSkillBegin", "logSkill", "useSkillBegin", "useSkill", "useSkillAfter", "skillAfter", "skill_used"]:
		await _test_activation_window(timing_name, false)
	await _test_activation_window("useSkillBegin", true)
	await _test_activation_window("useSkill", true)
	await _test_activation_generation()
	await _test_body_choice()
	await _test_self_removal()
	await _test_response_front(false, false)
	await _test_response_front(false, true)
	await _test_response_front(true, false)
	await _test_response_front(true, true)
	await _test_untrusted_paid_flag()
	if _controller != null:
		_controller.free()
	if not _failed:
		print("SKILL_ACTIVATION_SEQUENCE_PASS windows cancellation generation body response choice_identity")
	get_tree().quit(1 if _failed else 0)


## 正式安装本次探针，保证原武将代次与技能实例键经过控制器验证。
func _install_probe() -> ActivationProbe:
	_reset_controller()
	# 本次唯一技能实例；不作为共享静态定义缓存。
	var skill: ActivationProbe = ActivationProbe.new()
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"activation_probe":skill}
	return skill


## 每个声明与后置窗口独占等待；前置取消不进入主体或损失目标体力。
func _test_activation_window(timing_name: String, cancel_activation: bool) -> void:
	# 正式待发动技能；主体造成1点伤害用于观察提交位置。
	var skill: ActivationProbe = _install_probe()
	_controller.trigger_manager.subscribe(timing_name, self, _pause_window)
	# 完整请求结果；前后窗口期间都不能completed。
	var result: RefCounted = _controller.begin_skill_activation(0, "activation_probe")
	_check(_controller.has_pending_card_choice() and not result.completed, "activation skipped window " + timing_name)
	_check(skill.activation_count == (1 if timing_name in ["useSkillAfter", "skillAfter", "skill_used"] else 0), "activation body order " + timing_name)
	if cancel_activation:
		_paused_event.cancel("test_activation_cancel")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.success != cancel_activation and skill.activation_count == (0 if cancel_activation else 1) and _controller.state.get_player(1).hp == (20 if cancel_activation else 19), "activation final result " + timing_name)
	_check_clean("activation window " + timing_name)


## 前置中的换将使原技能失效；不调用新角色同名实例，也不生成成功After。
func _test_activation_generation() -> void:
	# 原代次实例；后续被同名新实例替代。
	var skill: ActivationProbe = _install_probe()
	_controller.trigger_manager.subscribe("useSkillBegin", self, _pause_window)
	# 本次原请求；结果必须明确完成失败。
	var result: RefCounted = _controller.begin_skill_activation(0, "activation_probe")
	_controller.state.get_player(0).character_generation += 1
	_submit_choice()
	await _settle_single()
	_check(result.completed and not result.success and skill.activation_count == 0, "activation used changed generation")
	_check_clean("activation generation")


## 技能自己创建的选择及其后续子伤害完成前，useSkillAfter不能提前触发。
func _test_body_choice() -> void:
	# 正式技能实例；主体先创建目标选择。
	var skill: ActivationProbe = _install_probe()
	# 真实After观察；应看到主体子伤害完整结束。
	var after: Array[int] = []
	_controller.trigger_manager.subscribe("useSkillAfter", self, func(_event: RuleEvent) -> void: after.append(_controller.state.get_player(1).hp))
	_controller.trigger_manager.subscribe("damageBefore", self, _pause_window)
	# 技能请求；主体选择尚未提交。
	var result: RefCounted = _controller.begin_skill_activation(0, "activation_probe", {"mode":"choose"})
	_check(not result.completed and after.is_empty() and skill.activation_count == 1, "activation After preceded body choice")
	_submit_choice([1])
	_check(_controller.has_pending_card_choice() and after.is_empty(), "activation After skipped selected child damage")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.success and after == [19], "activation lost choice continuation")
	_check_clean("activation body choice")


## 主体主动移除自身技能仍保留已发生的后置事实，不依赖旧技能还在安装表。
func _test_self_removal() -> void:
	_install_probe()
	_controller.trigger_manager.subscribe("useSkillAfter", self, _pause_window)
	# 自身卸载后的请求；不能因为get_skill_instance为空而吞掉After。
	var result: RefCounted = _controller.begin_skill_activation(0, "activation_probe", {"mode":"remove_self"})
	_check(_controller.has_pending_card_choice() and not result.completed and _controller.get_skill_instance(0, "activation_probe") == null, "activation self-removal skipped After")
	_submit_choice()
	await _settle_single()
	_check(result.completed and result.success, "activation lost self-removal completion")
	_check_clean("activation self removal")


## 原响应请求先关闭，再等待真正技能前置；取消不支付体力或实体，预览按钮不重复发动。
func _test_response_front(converted: bool, cancel_activation: bool) -> void:
	_reset_controller()
	# 正式响应技能；安打消费材料，倾力消费体力。
	var skill: SkillDefinition = GameDatabase.create_skill("anda" if converted else "qingli")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {skill.get_id():skill}
	skill.install()
	# 响应材料；倾力不需要也不应消耗它。
	var card: CardInstance = _add_single_card()
	# 父步骤收到的最终响应；空数组表示仍在等待，空字符串表示明确失败。
	var observed: Array[String] = []
	_controller.trigger_manager.subscribe("useSkillBegin", self, _pause_window)
	_controller.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void: skill.request_step_response(sequence, 0, ["sha"], "技能响应", {"response_action":"play"}),
		func(sequence: RuleStepSequence) -> void: observed.append(sequence.response_card.definition_id if sequence.response_card != null else ""),
	])
	# 原权威响应身份；技能前置的新询问必须拥有不同ID。
	var request_id: int = int(_controller._pending_card_choice.get("request_id", -1))
	if converted:
		_check(_controller.activate_skill(0, "anda", {"active_entry":"chooseToRespond"}) and int(_controller._pending_card_choice.get("request_id", -1)) == request_id, "response preview consumed original request")
		# 正式材料响应动作；AI直接提交同一协议，无需先点预览。
		var action: PlayerAction = PlayerAction.new("choose_cards", 0)
		action.payload = {"request_id":request_id, "selected_card_uids":[card.uid], "response_skill_id":"anda", "confirmed":true}
		_check(_controller._submit_card_choice(action), "converted response action rejected")
	else:
		_check(_controller.activate_skill(0, "qingli", {"active_entry":"chooseToRespond"}), "cardless response button rejected")
	_check(_controller.has_pending_card_choice() and _paused_event != null and _paused_event.name == "useSkillBegin" and int(_controller._pending_card_choice.get("request_id", -1)) != request_id and card.zone == "hand" and _controller.state.get_player(0).hp == 20 and observed.is_empty(), "response activation overwrote original choice or paid before window")
	if cancel_activation:
		_paused_event.cancel("test_response_activation_cancel")
	_submit_choice()
	await _settle_single()
	_check(observed == ([""] if cancel_activation else ["sha_fire" if converted else "sha_thunder"]) and card.zone == ("discard_pile" if converted and not cancel_activation else "hand") and _controller.state.get_player(0).hp == (19 if not converted and not cancel_activation else 20), "response activation result/cost mismatch")
	_check_clean("response activation")


## 客户端旧paid标志不能跳过制动斗志费用；全部支付只由关闭选择后的技能主体执行。
func _test_untrusted_paid_flag() -> void:
	_reset_controller()
	_controller.player_mark_service = PlayerMarkService.new(_controller.state)
	# 正式无材料响应实例；制动费用仍为1枚斗志。
	var skill: SkillDefinition = GameDatabase.create_skill("zhidong")
	skill.bind(_controller, 0)
	_controller.skill_instances_by_player[0] = {"zhidong":skill}
	skill.install()
	_controller.change_player_mark_count(0, "douzhi", 1)
	# 父响应观察；只接受真正成功消费后的杀。
	var observed: Array[String] = []
	_controller.run_rule_sequence([
		func(sequence: RuleStepSequence) -> void: skill.request_step_response(sequence, 0, ["sha"], "斗志响应", {"response_action":"play"}),
		func(sequence: RuleStepSequence) -> void: observed.append(sequence.response_card.definition_id if sequence.response_card != null else ""),
	])
	# 模拟携带过时paid标志的网络动作；权威仍应实际支付。
	var action: PlayerAction = PlayerAction.new("choose_cards", 0)
	action.payload = {"request_id":int(_controller._pending_card_choice.get("request_id", -1)), "selected_card_uids":[], "cardless_response_skill_id":"zhidong", "cardless_cost_paid":true, "confirmed":true}
	_check(_controller._submit_card_choice(action), "cardless paid-flag response rejected")
	await _settle_single()
	_check(observed == ["sha"] and int(_controller.get_player_mark(0, "douzhi").get("count", 0)) == 0, "client paid flag bypassed real skill cost")
	_check_clean("response paid flag")
