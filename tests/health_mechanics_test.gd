extends Node

## 护盾、失去体力与伤害语法回归测试。验证三类技能操作的数值、事件隔离、伤害历史和武将牌显示。

## 正式武将牌场景；测试直接读取运行时生成的体力与护盾标签，避免建立第二套 UI 假实现。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 测试使用的权威控制器；角色语法最终必须委托给该对象完成统一结算。
var _controller: MatchController

## 已捕获的伤害后事件；数组长度用于确认 loseHp 不会触发受到伤害或造成伤害技能时机。
var _damage_after_events: Array[Dictionary] = []

## 已捕获的失去体力后事件；只允许 loseHp 写入，普通伤害不能混入该数组。
var _lose_hp_after_events: Array[Dictionary] = []

## 已捕获的通用体力减少事件；伤害穿透护盾和 loseHp 都应记录，并明确 reduction_type。
var _hp_reduced_events: Array[Dictionary] = []

## 已捕获的获得护盾后事件；用于确认来源角色、目标角色与累计护盾值均可供技能读取。
var _shield_after_events: Array[Dictionary] = []


## 延迟执行测试，确保自动加载数据、主题和全局类名已经完成初始化。
func _ready() -> void:
	call_deferred("_run")


## 依次验证技能角色语法、权威数值结算、事件边界和两种体力 UI 模式。
func _run() -> void:
	_create_controller()
	if not _test_skill_health_syntax():
		return
	if not await _test_shield_ui():
		return
	print("HEALTH_MECHANICS_PASS damage=2 lose_hp=1 shield=3 ui=dot+numeric")
	get_tree().quit(0)


## 创建与正式场景一致的控制器组件，并写入两名不会触发濒死流程的最小玩家状态。
func _create_controller() -> void:
	_controller = MatchController.new()
	_controller.name = "MatchController"
	# 规则事件总线；测试通过正式订阅接口观察伤害、失去体力与护盾事件。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# AI 协调器；本测试不驱动回合，只用于满足控制器的标准组件依赖。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 离线通信网关；本测试不发送动作，但控制器初始化要求统一通信端口存在。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	add_child(_controller)
	_controller.state = GameState.new()
	_controller.state.match_id = "health-mechanics-test"
	_controller.state.current_player_id = 0
	_controller.state.current_phase = "play"
	# 测试玩家稳定 ID；固定创建来源0号与目标1号两名角色。
	for player_id: int in range(2):
		# 测试玩家状态；双方固定4点体力，全部结算结束后目标仍高于0点以避免进入求桃选择。
		var player: PlayerState = PlayerState.new(player_id, "测试玩家%d" % (player_id + 1))
		player.max_hp = 4
		player.hp = 4
		_controller.state.players.append(player)
	_controller.card_rules = CardRuleService.new(_controller.state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, _controller.state)
	_controller.card_movement = CardMovementService.new(_controller.state)
	_controller.event_bus.subscribe("damage_after", self, _on_damage_after)
	_controller.event_bus.subscribe("lose_hp_after", self, _on_lose_hp_after)
	_controller.event_bus.subscribe("hp_reduced", self, _on_hp_reduced)
	_controller.event_bus.subscribe("shield_after", self, _on_shield_after)


## 使用技能文件实际可写的角色语法验证护盾优先、loseHp 穿盾以及 damage 独占伤害触发。
func _test_skill_health_syntax() -> bool:
	# 测试技能定义；稳定 ID 会作为三类数值操作的原因写入事件与回放记录。
	var skill: SkillDefinition = SkillDefinition.new({"id":"health_syntax_test", "name":"体力语法测试"})
	skill.bind(_controller, 0)
	# 伤害与护盾来源角色；后续直接调用 source.damage(count, who) 验证制作语法。
	var source: SkillPlayer = skill.get_owner_skill_player()
	# 获得护盾、受到伤害和失去体力的目标角色；后续直接调用 who.shield 与 who.loseHp。
	var who: SkillPlayer = skill.get_skill_player(1)
	# 目标权威状态；只用于断言，测试效果本身不能直接修改该对象。
	var target_state: PlayerState = who.get_state()

	if who.shield(3, source) != 3 or target_state.shield != 3 or _shield_after_events.size() != 1:
		return _fail("shield_gain=%d events=%s" % [target_state.shield, _shield_after_events])
	source.damage(2, who)
	if target_state.hp != 4 or target_state.shield != 1 or _damage_after_events.size() != 1 or not _hp_reduced_events.is_empty():
		return _fail("shield_absorb hp=%d shield=%d damage=%s hp_reduced=%s" % [target_state.hp, target_state.shield, _damage_after_events, _hp_reduced_events])
	# 首次伤害后事件数据；完整伤害被护盾吸收时 damage 仍触发，但实际体力减少必须为0。
	var absorbed_damage: Dictionary = _damage_after_events[0]
	if int(absorbed_damage.get("amount", -1)) != 2 or int(absorbed_damage.get("shield_absorbed", -1)) != 2 or int(absorbed_damage.get("hp_lost", -1)) != 0:
		return _fail("absorbed_damage=%s" % absorbed_damage)

	if who.loseHp(1, source) != 1 or target_state.hp != 3 or target_state.shield != 1:
		return _fail("lose_hp hp=%d shield=%d" % [target_state.hp, target_state.shield])
	if _damage_after_events.size() != 1 or _lose_hp_after_events.size() != 1 or _hp_reduced_events.size() != 1 or str(_hp_reduced_events[0].get("reduction_type", "")) != "lose_hp":
		return _fail("lose_hp_event_isolation damage=%s lose=%s reduced=%s" % [_damage_after_events, _lose_hp_after_events, _hp_reduced_events])

	source.damage(3, who)
	if target_state.hp != 1 or target_state.shield != 0 or _damage_after_events.size() != 2 or _lose_hp_after_events.size() != 1 or _hp_reduced_events.size() != 2:
		return _fail("partial_absorb hp=%d shield=%d damage=%s lose=%s reduced=%s" % [target_state.hp, target_state.shield, _damage_after_events, _lose_hp_after_events, _hp_reduced_events])
	# 穿盾伤害后的通用体力减少事件；只记录实际减少的2点体力，并保留原始3点伤害值。
	var reduced_by_damage: Dictionary = _hp_reduced_events[1]
	if str(reduced_by_damage.get("reduction_type", "")) != "damage" or int(reduced_by_damage.get("amount", -1)) != 2 or int(reduced_by_damage.get("damage_amount", -1)) != 3:
		return _fail("damage_hp_reduced=%s" % reduced_by_damage)
	# 目标和来源伤害历史；两次 damage 各记录一次，loseHp 不得写入伤害历史。
	var source_state: PlayerState = source.get_state()
	if target_state.damage_history.size() != 2 or source_state.damage_history.size() != 2:
		return _fail("damage_history source=%s target=%s" % [source_state.damage_history, target_state.damage_history])
	# 公开快照护盾；所有观察者都必须读取相同非负值供武将牌渲染。
	var target_snapshot: Dictionary = target_state.to_dict(0, false)
	if int(target_snapshot.get("shield", -1)) != 0:
		return _fail("shield_snapshot=%s" % target_snapshot)
	return true


## 验证1至5点体力使用灰色护盾圆点，高于5点时体力按纵向加粗分数、护盾按加粗单值显示。
func _test_shield_ui() -> bool:
	# 正式武将牌实例；加入场景树后由原组件创建体力框和主题样式。
	var player_view: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	add_child(player_view)
	await get_tree().process_frame
	# 圆点模式快照；2点护盾应位于4个体力圆点之前，共生成6个标签。
	var pip_snapshot: Dictionary = {"player_id":1, "alive":true, "hp":3, "max_hp":4, "shield":2, "hand_count":0, "display_name":"护盾目标", "character_id":"", "identity":"rebel", "equipment":{}, "judgment_area":[]}
	player_view.configure_snapshot(pip_snapshot)
	# 正式体力容器；只读取组件生成结果，不直接调用私有绘制函数。
	var health_container: VBoxContainer = player_view.get_node("HealthFrame/HealthPips") as VBoxContainer
	if health_container.get_child_count() != 6:
		return _fail("shield_pip_count=%d" % health_container.get_child_count())
	# 第一枚护盾圆点颜色；必须使用独立灰色语义色，不与已损失体力暗色混用。
	var shield_pip_color: Color = (health_container.get_child(0) as Label).get_theme_color("font_color")
	if not shield_pip_color.is_equal_approx(BattleUIStyle.get_color("health_shield")):
		return _fail("shield_pip_color=%s" % shield_pip_color)

	# 数字模式快照；体力上限6触发纵向数字显示，3点护盾也必须显示为单独灰色单值标签。
	var numeric_snapshot: Dictionary = pip_snapshot.duplicate(true)
	numeric_snapshot["hp"] = 5
	numeric_snapshot["max_hp"] = 6
	numeric_snapshot["shield"] = 3
	player_view.configure_snapshot(numeric_snapshot)
	if health_container.get_child_count() != 2:
		return _fail("numeric_health_child_count=%d" % health_container.get_child_count())
	# 数字护盾标签；护盾没有独立上限，只显示当前护盾值。
	var shield_number: Label = health_container.get_child(0) as Label
	# 数字体力标签；继续显示当前体力/体力上限，不把护盾并入真实体力。
	# 三行文本依次为当前体力、分隔斜杠和体力上限，防止高体力分数恢复为横向排版。
	var health_number: Label = health_container.get_child(1) as Label
	# 数字模式排版参数；字号和负行间距共同保证三行分数更醒目且保持紧凑。
	if shield_number.text != "3" or health_number.text != "5\n/\n6" or not shield_number.get_theme_color("font_color").is_equal_approx(BattleUIStyle.get_color("health_shield")) or not health_number.get_theme_color("font_color").is_equal_approx(BattleUIStyle.get_color("health_full")) or shield_number.get_theme_font_size("font_size") != player_view.numeric_health_font_size or health_number.get_theme_font_size("font_size") != player_view.numeric_health_font_size or shield_number.get_theme_constant("outline_size") != player_view.numeric_health_outline_size or health_number.get_theme_constant("outline_size") != player_view.numeric_health_outline_size or health_number.get_theme_constant("line_spacing") != player_view.numeric_health_line_spacing:
		return _fail("numeric_health=%s/%s" % [shield_number.text, health_number.text])
	return true


## 捕获伤害后事件深拷贝；来源和目标保留在字典中便于失败输出定位。
func _on_damage_after(event: RuleEvent) -> void:
	# 伤害事件数据副本；补充来源与目标后保存，避免后续处理器修改原事件影响断言。
	var data: Dictionary = event.data.duplicate(true)
	data["source_id"] = event.source_id
	data["target_id"] = event.target_id
	_damage_after_events.append(data)


## 捕获失去体力后事件深拷贝；本数组不得收到任何 damage 调用产生的事件。
func _on_lose_hp_after(event: RuleEvent) -> void:
	# 失去体力事件数据副本；补充来源与目标后保存，避免持有可变事件引用。
	var data: Dictionary = event.data.duplicate(true)
	data["source_id"] = event.source_id
	data["target_id"] = event.target_id
	_lose_hp_after_events.append(data)


## 捕获通用体力减少事件深拷贝；reduction_type 用于区分 damage 与 lose_hp。
func _on_hp_reduced(event: RuleEvent) -> void:
	# 体力减少事件数据副本；用于核对 reduction_type 与实际减少点数。
	var data: Dictionary = event.data.duplicate(true)
	data["source_id"] = event.source_id
	data["target_id"] = event.target_id
	_hp_reduced_events.append(data)


## 捕获获得护盾后事件深拷贝；记录来源和目标确保技能能识别护盾给予者与接收者。
func _on_shield_after(event: RuleEvent) -> void:
	# 护盾事件数据副本；用于核对来源角色、目标角色与累计护盾值。
	var data: Dictionary = event.data.duplicate(true)
	data["source_id"] = event.source_id
	data["target_id"] = event.target_id
	_shield_after_events.append(data)


## 输出稳定失败原因并以非0状态结束测试；返回 false 便于调用方立即终止后续断言。
func _fail(reason: String) -> bool:
	printerr("HEALTH_MECHANICS_FAIL %s" % reason)
	get_tree().quit(1)
	return false
