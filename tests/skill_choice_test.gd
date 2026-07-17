extends Node

## 技能通用选择无头回归。验证技能可通过同一协议选择目标或同时选择牌与目标，不依赖界面节点或专用技能分支。

## 本次测试使用的最小权威控制器；只安装选择协议依赖，不启动正式身份局。
var _controller: MatchController


## 测试主动技能。发动后选择1名目标，并在通用恢复入口记录最终结果。
class TargetChoiceSkill:
	extends SkillDefinition

	## 选择恢复是否已经执行；默认false，成功收到目标1后改为true。
	var selection_completed: bool = false


	## 写入主动入口与稳定测试说明；技能本身不产生任何数值效果。
	func _init() -> void:
		super({"id":"target_choice_test", "name":"目标选择", "trigger":"active", "ui_enabled":true, "enable":["phaseUse", "chooseToUse"], "description":"测试统一目标选择。"})


	## 仅在持有者自己的出牌阶段允许发动。
	func can_activate(_context: Dictionary = {}) -> bool:
		# 技能持有者状态；不存在、死亡或不在自己出牌阶段时拒绝发动。
		var owner: PlayerState = host.state.get_player(owner_player_id) if host != null and host.state != null else null
		return owner != null and owner.alive and host.state.current_player_id == owner_player_id and host.state.current_phase == "play"


	## 创建1选1目标请求；正式交互会暂停并等待标准 ChoiceResponse。
	func activate(_context: Dictionary = {}) -> String:
		request_target_selection("请选择技能目标", [1], 1, 1, false, {"kind":"async_target_test"})
		return ""


	## 接收目标选择结果；只识别本技能创建的稳定 kind。
	func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
		if str(context.get("kind", "")) != "async_target_test":
			return false
		selection_completed = response.confirmed and response.target_ids == [1]
		return true


## 构建最小控制器并执行目标选择、组合选择和技能上下文绑定断言。
func _ready() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 同步规则总线；控制器就绪时按稳定节点名取得。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；本测试不注册策略，使无交互请求进入权威稳定回退动作。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线网络网关；选择仍使用完整 ChoiceResponse，但不会产生外部通信。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	await get_tree().process_frame
	# 最小权威状态；空 match_id 表示无交互规则测试，选择由标准回退动作同步完成。
	var game_state: GameState = GameState.new()
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	game_state.players.append(PlayerState.new(0, "技能持有者"))
	game_state.players.append(PlayerState.new(1, "技能目标"))
	_controller.state = game_state
	_controller.card_rules = CardRuleService.new(game_state)
	_controller.timing_service = RuleTimingService.new(event_bus, _controller.trigger_manager, game_state)
	# 测试技能；基类负责把技能 ID 与持有者写入恢复上下文。
	var skill: SkillDefinition = SkillDefinition.new({"id":"selection_test", "name":"选择测试"})
	skill.bind(_controller, 0)
	# 同步目标选择结果；最小规则状态应稳定选择唯一目标1。
	var selected_targets: Array[int] = skill.request_target_selection("请选择一名角色", [1], 1, 1, false, {"kind":"test_target"})
	if selected_targets != [1]:
		_fail("target_selection=%s" % [selected_targets])
		return
	# 组合候选牌；序列化字段与正式手牌选择快照一致。
	var material_card: CardInstance = CardInstance.new("shan", "heart", 2)
	material_card.uid = 101
	material_card.zone = "hand"
	material_card.owner_id = 0
	# 组合选择牌面候选；公开字段与正式控制器序列化结果一致。
	var candidate: Dictionary = {"uid":101, "owner_id":0, "zone":"hand", "slot":"", "visible":true, "card_data":material_card.to_dict()}
	# 同步组合结果；唯一牌101只能选择唯一目标1。
	var combined_result: Dictionary = skill.request_card_target_selection("选择牌和目标", "请选择一张牌和一名目标", [candidate], [1], 1, 1, 1, 1, false, {"kind":"test_card_target", "target_ids_by_card_id":{"101":[1]}})
	if (combined_result.get("card_ids", []) as Array) != [101] or (combined_result.get("target_ids", []) as Array) != [1]:
		_fail("card_target_selection=%s" % combined_result)
		return
	if not _test_choose_to_use_skill_chain(game_state):
		return
	print("SKILL_CHOICE_PASS target=%s combined=%s" % [selected_targets, combined_result])
	get_tree().quit(0)


## 验证主动技能先完成 chooseToUse，再创建目标子选择，并在恢复后重新开放下一次出牌请求。
func _test_choose_to_use_skill_chain(game_state: GameState) -> bool:
	# 清理同步选择产生的历史；新请求使用非空对局 ID 进入正式本地等待模式。
	_controller.event_scheduler.reset()
	game_state.match_id = "skill_choice_test"
	game_state.current_player_id = 0
	game_state.current_phase = "play"
	# 测试技能实例；直接登记到当前玩家的独立运行时技能表。
	var active_skill: TargetChoiceSkill = TargetChoiceSkill.new()
	active_skill.bind(_controller, 0)
	_controller.skill_instances_by_player = {0:{active_skill.get_id():active_skill}}
	_controller.call("_begin_play_choice", 0)
	if not _controller.call("_has_active_play_choice"):
		return _fail_bool("play_choice_missing")
	# 主动技能动作；控制器应先用 button_ids 完成当前出牌请求，再进入技能目标选择。
	var skill_action: PlayerAction = PlayerAction.new("use_skill", 0)
	skill_action.payload = {"skill_id":active_skill.get_id()}
	if not _controller.submit_action(skill_action):
		return _fail_bool("skill_submit")
	# 技能创建的待处理请求；必须替换原 chooseToUse 并保留目标候选1。
	var pending_choice: Dictionary = _controller.get("_pending_card_choice") as Dictionary
	if pending_choice.is_empty() or str(pending_choice.get("choice_type", "")) != "target" or (pending_choice.get("target_ids", []) as Array) != [1] or _controller.call("_has_active_play_choice"):
		return _fail_bool("target_request=%s" % pending_choice)
	# 目标响应；与选牌请求相同，仍通过 choose_cards 兼容动作提交完整牌/目标数组。
	var target_action: PlayerAction = PlayerAction.new("choose_cards", 0)
	target_action.payload = {"request_id":int(pending_choice.get("request_id", -1)), "selected_card_uids":[], "selected_target_ids":[1], "confirmed":true}
	if not _controller.submit_action(target_action):
		return _fail_bool("target_submit")
	if not active_skill.selection_completed or not _controller.call("_has_active_play_choice"):
		return _fail_bool("skill_resume completed=%s play=%s" % [active_skill.selection_completed, _controller.call("_has_active_play_choice")])
	_controller.call("_cancel_active_play_choice", "test_complete")
	return true


## 输出失败原因并以非0状态结束，便于命令行直接定位选择协议回归。
func _fail(reason: String) -> void:
	printerr("SKILL_CHOICE_FAIL %s" % reason)
	get_tree().quit(1)


## 输出失败并返回 false，供多步骤辅助测试立即终止。
func _fail_bool(reason: String) -> bool:
	_fail(reason)
	return false
