extends Node

## 阿哈时刻专项测试：校验欢愉技分类参数、正文类型识别、参演排序、触发概率与串行演出推进。
## 测试复用真实MatchController与全部运行时服务，避免构造缺失依赖的替代控制器。

## 正式主场景；测试直接使用其中的权威控制器、暂停服务与AI绑定。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 测试用参演技能ID前缀；与正式内容ID隔离，避免与数据库既有技能重名。
const TEST_SKILL_PREFIX: String = "test_joy_"

## 过场动画自然播完（含淡出）的等待上限毫秒数；精简版过场约1.7秒，这里留足余量避免慢机器假失败。
## 等待本身走帧推进与条件判定，该常量只作为“永不满足”时的兜底上限。
const CUTSCENE_RELEASE_TIMEOUT_MILLISECONDS: int = 15000

## 复核“视频没有被本组件自己申请的暂停冻结”所需的观察帧数；20帧足以让解码位置产生明显前进。
const VIDEO_PROGRESS_OBSERVATION_FRAMES: int = 20

## 超时兜底用例使用的暂停令牌上限（秒）。取值范围下界为1.0，且必须显著小于过场视频时长（约1.7秒），
## 这样“视频自然结束之前令牌就已经被释放”本身就是兜底计时确实生效的直接证据。
const TIMEOUT_PROBE_PAUSE_SECONDS: float = 1.0

## 超时兜底用例中“令牌必须仍然持有且过场仍在播放”的观察时刻（毫秒）；取上限时长的一半，同时远离两个边界。
const TIMEOUT_PROBE_HOLD_OBSERVATION_MILLISECONDS: int = 600

## 过场令牌正常释放后等待“迟到兜底回调”的毫秒数；必须大于 TIMEOUT_PROBE_PAUSE_SECONDS 对应的毫秒数。
const STALE_WATCHDOG_OBSERVATION_MILLISECONDS: int = 1400

## 本地待办守卫用例使用的伪请求ID；只需一个稳定的非负整数，不参与任何真实规则请求。
const PENDING_CHOICE_PROBE_REQUEST_ID: int = 4242

## 本次测试主场景实例；完成后显式释放，避免跨测试保留暂停令牌或全局信号连接。
var _main_instance: Control

## 本次测试权威控制器；技能实例直接注册到其技能索引，便于验证排序与执行顺序。
var _controller: MatchController

## 测试欢愉技的全局执行记录；按调用顺序保存“角色ID:技能ID”，供串行演出断言使用。
var _performance_log: Array[String] = []

## 本次测试使用的固定随机源；由组件持有，测试通过其state确认跳过分支未消耗随机数。
var _rng: RandomNumberGenerator

## 模拟联机角色前的网关通信模式；用例结束必须原样恢复，避免影响同一进程内的后续用例。
var _saved_gateway_mode: int = NetworkGateway.Mode.OFFLINE

## 模拟联机角色前的网关会话角色；用例结束必须原样恢复。
var _saved_gateway_role: int = NetworkGateway.LanRole.NONE

## 模拟联机角色前的网关连接标记；用例结束必须原样恢复。
var _saved_gateway_connected: bool = true

## 模拟联机角色前的“对局已开始”标记；用例结束必须原样恢复。
var _saved_gateway_match_active: bool = false


## 测试用欢愉技；只记录执行顺序并同步回报结束，不读写任何牌区、体力或阶段状态。
class TestJoySkill:
	extends SkillDefinition

	## 外层测试的执行记录数组；技能不持有测试节点引用，只按共享数组回报调用顺序。
	var performance_log: Array[String]

	## 构造参演技能；skill_id 与参演编号由用例指定，正文按类型段写法声明欢愉技。
	func _init(skill_id: String, performance_number: int, log: Array[String]) -> void:
		super({"id":skill_id, "name":"测试欢愉", "trigger":"passive", "joy_skill":true, "performance_number":performance_number, "description":"欢愉技，参演编号%d，测试用演出。" % performance_number})
		performance_log = log

	## 记录本次演出并立即回报结束；同步回报会驱动组件在同一调用栈内推进下一项。
	func perform_joy_skill(_context: Dictionary) -> void:
		performance_log.append("%d:%s" % [owner_player_id, get_id()])
		finish_joy_skill_performance()


## 运行全部断言；测试节点保持ALWAYS，使演出期间的暂停状态不阻断帧回调推进。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main_instance = MAIN_SCENE.instantiate() as Control
	add_child(_main_instance)
	await get_tree().process_frame
	_controller = _main_instance.get_node("MatchController") as MatchController
	_setup_test_state()
	if not _test_skill_parameters():
		return
	if not _test_description_type_detection():
		return
	if not _test_performance_order_by_number():
		return
	if not _test_performance_order_by_seat():
		return
	if not _test_order_skips_inactive():
		return
	if not _test_empty_candidates_consume_no_random():
		return
	if not _test_trigger_probability():
		return
	if not _test_extra_turn_never_triggers():
		return
	if not await _test_serial_performance_end_to_end():
		return
	if not _test_round_end_fallback_trigger():
		return
	if not _test_round_end_boundary_after_opportunity():
		return
	if not _test_round_quota_single_trigger_per_round():
		return
	if not await _test_offline_cutscene_pauses_and_releases():
		return
	if not await _test_lan_host_cutscene_pauses():
		return
	if not await _test_lan_client_event_plays_and_pauses():
		return
	if not await _test_client_pending_choice_guard_skips_pause():
		return
	if not await _test_network_client_pause_grey_switch():
		return
	if not await _test_unknown_network_event_degrades_safely():
		return
	if not await _test_cutscene_pause_timeout_watchdog():
		return
	if not await _test_stale_watchdog_keeps_foreign_pause():
		return
	if not await _test_match_finished_stops_cutscene():
		return
	if not await _test_replay_playback_does_not_pause():
		return
	if not await _test_lan_session_closed_stops_cutscene():
		return
	_finish_success()


## 建立四名在场角色的最小权威状态；阿哈时刻组件使用主场景中的真实实例。
func _setup_test_state() -> void:
	# 测试对局状态；固定模式、轮数与当前角色便于验证轮边界与座次起点。
	var state: GameState = GameState.new()
	state.match_id = "ahha-test"
	state.match_mode = IdentityRules.MODE_IDENTITY
	state.current_phase = "start"
	state.current_player_id = 0
	state.round_number = 1
	state.turn_number = 1
	for player_id: int in range(4):
		# 测试角色；身份交替设置，保证后续涉及身份判定的通用逻辑存在稳定关系。
		var player: PlayerState = PlayerState.new(player_id, "玩家%d" % (player_id + 1))
		player.identity = "leader" if player_id == 0 else ("loyalist" if player_id == 2 else "rebel")
		player.identity_revealed = player_id == 0
		player.character_id = ""
		player.character_revealed = true
		state.players.append(player)
	_controller.state = state
	_controller.card_rules = CardRuleService.new(state, _controller)
	_controller.effect_resolver = CardEffectResolver.new(_controller, state)
	_controller.skill_instances_by_player = {0:{}, 1:{}, 2:{}, 3:{}}
	# 轮回技权威服务；真实对局由 _rebuild_match_rule_services_and_root_event() 创建并配置同一实例，
	# 测试最小状态必须补上该组件，否则技能安装期的轮回技登记会被 null 服务静默拒绝。
	if _controller.reincarnation_skill_service == null:
		_controller.reincarnation_skill_service = ReincarnationSkillService.new()
	_controller.reincarnation_skill_service.configure(_controller)
	# 固定随机源；触发判定与随机历史可复现，测试只依赖概率数值、随机数消耗与顺序结果。
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260930
	_controller.ahha_moment_system.configure(_controller, state, _rng, true)


## 校验欢愉技分类参数的解析口径：标签、参演编号、默认值与异常值收敛。
func _test_skill_parameters() -> bool:
	# 显式声明欢愉技与参演编号；运行期判定只读标签，不读正文。
	var joy_skill: SkillDefinition = SkillDefinition.new({"id":"param_joy", "name":"参数欢愉", "trigger":"passive", "joy_skill":true, "performance_number":144, "description":"欢愉技，参演编号144，参数测试。"})
	if not joy_skill.is_joy_skill() or joy_skill.get_performance_number() != 144:
		return _fail("joy_metadata joy=%s number=%d" % [str(joy_skill.is_joy_skill()), joy_skill.get_performance_number()])
	# 普通技能；未声明标签时编号必须归零，避免非欢愉技出现在参演序列中。
	var plain_skill: SkillDefinition = SkillDefinition.new({"id":"param_plain", "name":"参数普通", "trigger":"passive", "description":"测试用普通技能。"})
	if plain_skill.is_joy_skill() or plain_skill.get_performance_number() != 0:
		return _fail("plain_metadata joy=%s number=%d" % [str(plain_skill.is_joy_skill()), plain_skill.get_performance_number()])
	# 负数参演编号；收敛到0，避免产生无法排序的负数键。
	var negative_skill: SkillDefinition = SkillDefinition.new({"id":"param_negative", "name":"参数负数", "trigger":"passive", "joy_skill":true, "performance_number":-5, "description":"欢愉技，参演编号-5，参数测试。"})
	if negative_skill.get_performance_number() != 0:
		return _fail("negative_number %d" % negative_skill.get_performance_number())
	# 残留编号；非欢愉技即使误写编号也必须归零。
	var stale_skill: SkillDefinition = SkillDefinition.new({"id":"param_stale", "name":"参数残留", "trigger":"passive", "performance_number":9, "description":"测试用普通技能。"})
	if stale_skill.get_performance_number() != 0:
		return _fail("stale_number %d" % stale_skill.get_performance_number())
	# 基类默认执行入口；未绑定的技能调用必须安全无副作用。
	var base_skill: SkillDefinition = SkillDefinition.new({"id":"param_base", "name":"参数基类", "trigger":"passive", "joy_skill":true, "performance_number":1, "description":"欢愉技，参演编号1，基类测试。"})
	base_skill.perform_joy_skill({})
	if not base_skill.can_perform_joy_skill():
		return _fail("base_can_perform")
	return true


## 校验正文类型声明的识别口径；必须与轮回技判定保持同一套规则。
func _test_description_type_detection() -> bool:
	# 类型段声明；正文首个欢愉技标签紧跟逗号。
	if not SkillDefinition.description_declares_joy_type("欢愉技，参演编号144，你可弃置0-2名其他角色各一张随机手牌。"):
		return _fail("joy_type_declared")
	# 类型段声明；锁定技前缀不影响识别。
	if not SkillDefinition.description_declares_joy_type("锁定技，欢愉技，你摸一张牌。"):
		return _fail("joy_type_midway")
	# 引用他人欢愉技；标签后紧跟实词，不构成类型声明。
	if SkillDefinition.description_declares_joy_type("锁定技，当一名角色的欢愉技执行时，你摸一张牌。"):
		return _fail("joy_type_referenced")
	# 引用他人欢愉技且以句号收尾；句号不能作为类型声明证据，
	# 否则“令一名角色发动其欢愉技。”这类正文会被误判为欢愉技，加载期直接拦下合法技能。
	if SkillDefinition.description_declares_joy_type("每种花色限一次，你的回合开始前，你可以弃置一张手牌，然后令一名角色发动其欢愉技。若其没有欢愉技，则令其执行一个额外的出牌阶段。"):
		return _fail("joy_type_referenced_sentence")
	# 标签位于正文末尾；不构成类型声明。
	if SkillDefinition.description_declares_joy_type("锁定技，本技能视为欢愉技"):
		return _fail("joy_type_trailing")
	# 完全不含标签与空正文。
	if SkillDefinition.description_declares_joy_type("锁定技，你摸一张牌。"):
		return _fail("joy_type_absent")
	if SkillDefinition.description_declares_joy_type(""):
		return _fail("joy_type_empty")
	# 与轮回技判定口径一致；两套类型声明必须使用同一规则，避免维护两套正文解析。
	if not SkillDefinition.description_declares_reincarnation_type("轮回技，你摸一张牌。"):
		return _fail("reincarnation_parity_declared")
	if SkillDefinition.description_declares_reincarnation_type("当该轮回技进入下一个轮回时，你摸一张牌。"):
		return _fail("reincarnation_parity_referenced")
	return true


## 校验参演序列的第一排序键：参演编号升序，与座次无关。
func _test_performance_order_by_number() -> bool:
	_clear_joy_skills()
	_install_joy_skills({0:[["test_joy_a", 200]], 1:[["test_joy_b", 144]], 2:[["test_joy_c", 100]], 3:[["test_joy_d", 144]]})
	# 参演序列；从玩家0起算，座次偏移与角色ID一致。
	var order: Array[Dictionary] = _controller.ahha_moment_system.build_performance_order(0)
	# 序列摘要；按“角色ID:技能ID:参演编号”比对，编号相同时再由座次决定先后。
	var summary: Array[String] = []
	for entry: Dictionary in order:
		summary.append("%d:%s:%d" % [int(entry.get("player_id", -1)), str(entry.get("skill_id", "")), int(entry.get("performance_number", 0))])
	# 期望顺序：编号100（玩家2）→ 编号144（玩家1，座次更靠前）→ 编号144（玩家3）→ 编号200（玩家0）。
	if summary != ["2:test_joy_c:100", "1:test_joy_b:144", "3:test_joy_d:144", "0:test_joy_a:200"]:
		return _fail("order_by_number %s" % str(summary))
	return true


## 校验参演序列的第二排序键：编号相同时按“以当前回合位置起算的座次正序”执行。
func _test_performance_order_by_seat() -> bool:
	_clear_joy_skills()
	_install_joy_skills({0:[["test_joy_a", 144]], 2:[["test_joy_b", 144]], 3:[["test_joy_c", 144]]})
	# 从玩家1起算：座次偏移依次为 玩家2=1、玩家3=2、玩家0=3。
	var order: Array[Dictionary] = _controller.ahha_moment_system.build_performance_order(1)
	# 座次摘要；直接比对角色ID与座次偏移，确认环回展开方向为座次正序。
	var summary: Array[String] = []
	for entry: Dictionary in order:
		summary.append("%d:%d" % [int(entry.get("player_id", -1)), int(entry.get("seat_order", -1))])
	if summary != ["2:1", "3:2", "0:3"]:
		return _fail("order_by_seat %s" % str(summary))
	return true


## 校验死亡、离场与非欢愉技都不会进入参演序列。
func _test_order_skips_inactive() -> bool:
	_clear_joy_skills()
	_install_joy_skills({0:[["test_joy_a", 100]], 1:[["test_joy_b", 100]], 2:[["test_joy_c", 100]]})
	# 死亡角色；其欢愉技不参演。
	_controller.state.get_player(1).alive = false
	if _controller.ahha_moment_system.build_performance_order(0).size() != 2:
		return _fail("skip_dead")
	# 离场角色；其欢愉技同样不参演。
	_controller.state.get_player(1).alive = true
	_controller.state.get_player(1).out_of_game = true
	if _controller.ahha_moment_system.build_performance_order(0).size() != 2:
		return _fail("skip_out_of_game")
	_controller.state.get_player(1).out_of_game = false
	# 非欢愉技；即使挂在场上角色也未参演。
	_clear_joy_skills()
	var plain_skill: SkillDefinition = SkillDefinition.new({"id":"test_plain", "name":"测试普通", "trigger":"passive", "description":"测试用普通技能。"})
	plain_skill.bind(_controller, 2)
	_controller.skill_instances_by_player[2] = {"test_plain":plain_skill}
	if not _controller.ahha_moment_system.build_performance_order(0).is_empty():
		return _fail("plain_skill_included")
	return true


## 校验无候选参演技能时的完整跳过：不触发、不消耗随机数、不写入随机历史、不占用本轮额度。
func _test_empty_candidates_consume_no_random() -> bool:
	_clear_joy_skills()
	_controller.state.game_over = false
	_controller.state.random_history.clear()
	_controller.state.round_number = 11
	_controller.ahha_moment_system._tracked_round_number = 11
	_controller.ahha_moment_system._triggered_this_round = false
	_controller.ahha_moment_system._round_trigger_probability = 1.0
	# 随机源状态快照；跳过分支必须先于随机取值，因此状态必须逐位不变。
	var rng_state_before: int = _rng.state
	if _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":true}, false):
		return _fail("empty_candidates_triggered")
	if _rng.state != rng_state_before:
		return _fail("empty_candidates_consumed_random")
	if not _controller.state.random_history.is_empty():
		return _fail("empty_candidates_wrote_history %s" % str(_controller.state.random_history))
	if _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("empty_candidates_claimed_round")
	return true


## 校验触发概率的算法口径：按本轮开始时在场角色数量倒数计算。
func _test_trigger_probability() -> bool:
	# 无参演技能时概率仍会被计算，因此本用例可在无副作用前提下复核数值。
	# 轮号刻意与已跟踪轮号不同，模拟进入新轮，组件才会重新按在场人数锁定概率。
	_clear_joy_skills()
	_controller.state.game_over = false
	_controller.state.round_number = 21
	_controller.ahha_moment_system._tracked_round_number = 20
	_controller.ahha_moment_system._triggered_this_round = false
	_controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":true}, false)
	if not is_equal_approx(_controller.ahha_moment_system.get_round_trigger_probability(), 0.25):
		return _fail("probability_four_players %f" % _controller.ahha_moment_system.get_round_trigger_probability())
	# 二人存活时概率提升为 1/2；死亡与离场角色均不计入分母。
	_controller.state.get_player(1).alive = false
	_controller.state.get_player(2).out_of_game = true
	_controller.state.round_number = 22
	_controller.ahha_moment_system._tracked_round_number = 21
	_controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":true}, false)
	if not is_equal_approx(_controller.ahha_moment_system.get_round_trigger_probability(), 0.5):
		return _fail("probability_two_players %f" % _controller.ahha_moment_system.get_round_trigger_probability())
	_controller.state.get_player(1).alive = true
	_controller.state.get_player(2).out_of_game = false
	return true


## 校验额外回合不参与阿哈时刻判定。
func _test_extra_turn_never_triggers() -> bool:
	_install_joy_skills({0:[["test_joy_a", 144]]})
	_controller.ahha_moment_system._triggered_this_round = false
	_controller.ahha_moment_system._round_trigger_probability = 1.0
	if _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":false}, true):
		return _fail("extra_turn_triggered")
	if _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("extra_turn_claimed_round")
	return true


## 校验端到端演出：按排序结果串行执行、演出期间不建立回合事实、结束后才真正开始回合，且本轮不再二次触发。
func _test_serial_performance_end_to_end() -> bool:
	_performance_log.clear()
	_clear_joy_skills()
	# 待开始角色为玩家0；上一名已结束回合的角色为玩家3，与真实回合边界一致。
	_controller.state.game_over = false
	_controller.state.current_player_id = 3
	_controller.state.current_phase = "finish"
	_controller.state.round_number = 31
	_controller.state.turn_number = 4
	_controller._current_turn_is_extra = false
	_controller._extra_turn_queue.clear()
	_controller._extra_turn_resume_player_ids.clear()
	_controller._pending_turn_start_context.clear()
	# 参演技能；期望按编号升序执行：编号100（玩家1）→ 编号144（玩家2）→ 编号200（玩家0）。
	_install_joy_skills({0:[["test_joy_b", 200]], 1:[["test_joy_c", 100]], 2:[["test_joy_a", 144]]})
	# 机缘不参与本用例；概率置0保证机缘判定不接管流程，同时保留其随机数消耗行为。
	_controller.opportunity_system._tracked_round_number = 32
	_controller.opportunity_system._triggered_this_round = false
	_controller.opportunity_system._round_trigger_probability = 0.0
	# 阿哈时刻必定触发；轮号与控制器递增后的期望值一致，组件不会重新初始化概率。
	_controller.ahha_moment_system._tracked_round_number = 32
	_controller.ahha_moment_system._triggered_this_round = false
	_controller.ahha_moment_system._round_trigger_probability = 1.0
	# 走正式回合入口；演出触发点必须早于该角色的回合事实。
	_controller._start_turn(0)
	if _performance_log != ["1:test_joy_c", "2:test_joy_a", "0:test_joy_b"]:
		return _fail("serial_order %s" % str(_performance_log))
	# 演出结束后队列必须清空，且本轮额度已被占用。
	if _controller.ahha_moment_system.is_active():
		return _fail("serial_not_finished")
	if not _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("serial_round_not_claimed")
	if _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":false}, false):
		return _fail("serial_triggered_twice")
	# 演出全部结束才建立回合事实；当前角色必须是原定待开始角色。
	if _controller.state.current_player_id != 0:
		return _fail("serial_turn_not_started current=%d" % _controller.state.current_player_id)
	if _controller.state.turn_number != 5:
		return _fail("serial_turn_number %d" % _controller.state.turn_number)
	# 等待演出后创建的选择请求完成入场，避免收尾阶段残留待办请求。
	for _wait_frame: int in range(4):
		await get_tree().process_frame
	return true


## 校验轮末强制补触发：整轮所有普通回合开始前的检定都未通过时，本轮额度在轮末兜底使用，保证每轮必定触发一次。
## 该口径与机缘选择的「整轮未触发则轮末强制触发」完全一致，并且同样不消耗随机数、不写随机历史。
func _test_round_end_fallback_trigger() -> bool:
	_performance_log.clear()
	_clear_joy_skills()
	# 轮末补触发沿用常规参演序列；只装一项以保持断言简洁。
	_install_joy_skills({1:[["test_joy_a", 144]]})
	_controller.state.game_over = false
	_controller.state.current_player_id = 2
	_controller.state.current_phase = "finish"
	_controller.state.round_number = 41
	# 概率为0，模拟整轮每一名角色回合开始前的检定都没有通过。
	_controller.ahha_moment_system._tracked_round_number = 41
	_controller.ahha_moment_system._triggered_this_round = false
	_controller.ahha_moment_system._round_trigger_probability = 0.0
	if _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":true}, false):
		return _fail("round_end_fallback_premature")
	if _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("round_end_fallback_claimed_early")
	# 随机源状态与随机历史长度快照；轮末补触发是「未触发」结果的收尾动作，必须两者都不变。
	var rng_state_before: int = _rng.state
	var history_size_before: int = _controller.state.random_history.size()
	if not _controller.ahha_moment_system.try_trigger_at_round_end(2):
		return _fail("round_end_fallback_not_triggered")
	if _performance_log != ["1:test_joy_a"]:
		return _fail("round_end_fallback_log %s" % str(_performance_log))
	if _rng.state != rng_state_before or _controller.state.random_history.size() != history_size_before:
		return _fail("round_end_fallback_consumed_random")
	if not _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("round_end_fallback_round_not_claimed")
	if _controller.ahha_moment_system.is_active():
		return _fail("round_end_fallback_still_active")
	# 每轮至多一次；同一轮的第二次补触发必须被拒绝。
	if _controller.ahha_moment_system.try_trigger_at_round_end(2):
		return _fail("round_end_fallback_triggered_twice")
	# 空候选分支：本轮末没有任何可执行欢愉技时不触发，也不额外占用额度。
	# 轮号刻意与已跟踪轮号不同，模拟进入新轮，组件才会重新初始化本轮额度。
	_clear_joy_skills()
	_controller.state.round_number = 42
	_controller.ahha_moment_system._tracked_round_number = 41
	if _controller.ahha_moment_system.try_trigger_at_round_end(2):
		return _fail("round_end_fallback_empty_triggered")
	if _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("round_end_fallback_empty_claimed")
	return true


## 校验真实轮末边界的环节顺序：机缘轮末保底已接管时，阿哈时刻仍会在同一次轮末补触发。
## 两个环节在轮末与回合开始前使用同一顺序（机缘在前、阿哈时刻在后），且各自只占用自己的轮次额度。
func _test_round_end_boundary_after_opportunity() -> bool:
	_performance_log.clear()
	_clear_joy_skills()
	_install_joy_skills({0:[["test_joy_a", 144]]})
	_controller.state.game_over = false
	_controller.state.current_player_id = 2
	_controller.state.current_phase = "finish"
	_controller.state.round_number = 51
	# 机缘已在本轮末触发过；其额度被占用，因此再次进入轮末边界只会继续尝试阿哈时刻。
	_controller.opportunity_system._tracked_round_number = 51
	_controller.opportunity_system._triggered_this_round = true
	_controller.opportunity_system._round_trigger_probability = 0.0
	# 阿哈时刻本轮回合开始前全部未触发；概率置0模拟该情况，保底仍必须补触发。
	_controller.ahha_moment_system._tracked_round_number = 51
	_controller.ahha_moment_system._triggered_this_round = false
	_controller.ahha_moment_system._round_trigger_probability = 0.0
	# 随机源状态与随机历史长度快照；两个环节都已无掷骰空间，必须逐位不变。
	var rng_state_before: int = _rng.state
	var history_size_before: int = _controller.state.random_history.size()
	_controller._continue_round_end_after_restore(2)
	if _performance_log != ["0:test_joy_a"]:
		return _fail("round_end_boundary_log %s" % str(_performance_log))
	if _rng.state != rng_state_before or _controller.state.random_history.size() != history_size_before:
		return _fail("round_end_boundary_consumed_random")
	if not _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("round_end_boundary_not_claimed")
	return true


## 校验“每轮至多一次常规阿哈时刻”的额度约束。
## 回合开始前的概率触发与轮末保底**共用同一份额度**，因此两者任意一个先成立都会挡住另一个；
## 额度只在轮号变化时重置，所以跨轮后重新可用；技能请求的额外演出既不占用额度、也不受额度限制。
func _test_round_quota_single_trigger_per_round() -> bool:
	_performance_log.clear()
	_clear_joy_skills()
	_install_joy_skills({1:[["test_joy_a", 144]]})
	_controller.state.game_over = false
	_controller.state.current_player_id = 2
	_controller.state.current_phase = "finish"
	_controller.state.round_number = 61
	# 第61轮：回合开始前的检定必定通过，先由该入口占用本轮额度。
	_controller.ahha_moment_system._tracked_round_number = 61
	_controller.ahha_moment_system._triggered_this_round = false
	_controller.ahha_moment_system._round_trigger_probability = 1.0
	if not _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":true}, false):
		return _fail("round_quota_first_trigger")
	# 同一轮内另一名角色的回合开始前：额度已用尽，不得再次触发。
	if _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":1, "starts_new_round":false}, false):
		return _fail("round_quota_second_turn_start")
	# 同一轮的轮末保底：与回合开始前共用额度，同样必须被拒绝。
	if _controller.ahha_moment_system.try_trigger_at_round_end(2):
		return _fail("round_quota_round_end_after_turn_start")
	# 技能请求的额外演出不占用该额度，演完后额度仍保持“已占用”而不是被改写。
	if not _controller.ahha_moment_system.try_trigger_extra_moment(0, {"kind":"round_quota_extra", "skill_owner_id":0, "skill_id":"test", "skill_character_generation":-1}):
		return _fail("round_quota_extra_moment")
	if _controller.ahha_moment_system.is_active() or not _controller.ahha_moment_system.has_triggered_this_round():
		return _fail("round_quota_extra_moment_state active=%s claimed=%s" % [str(_controller.ahha_moment_system.is_active()), str(_controller.ahha_moment_system.has_triggered_this_round())])
	# 第62轮：轮号变化才重置额度，轮末保底重新可用。
	_controller.state.round_number = 62
	if not _controller.ahha_moment_system.try_trigger_at_round_end(2):
		return _fail("round_quota_next_round_fallback")
	# 新一轮内反向组合：保底先成立后，该轮的回合开始前入口同样必须被拒绝。
	if _controller.ahha_moment_system.try_trigger_before_turn_start({"player_id":0, "starts_new_round":false}, false):
		return _fail("round_quota_turn_start_after_fallback")
	if _controller.ahha_moment_system.try_trigger_at_round_end(2):
		return _fail("round_quota_next_round_twice")
	return true


## 清空全部角色的技能索引；保证用例之间不残留上一次安装的参演技能。
func _clear_joy_skills() -> void:
	for player: PlayerState in _controller.state.players:
		_controller.skill_instances_by_player[player.player_id] = {}


## 返回本场景中桌面创建的阿哈时刻过场组件；缺失时返回null，由调用方按失败处理。
func _cutscene() -> AhhaMomentCutscene:
	return _main_instance.get("ahha_moment_cutscene") as AhhaMomentCutscene


## 返回过场组件内的视频播放节点；用于复核视频是否在被自己造成的暂停中继续解码。
func _cutscene_video() -> VideoStreamPlayer:
	# 当前过场组件；缺失时无法取得视频节点。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return null
	return cutscene.get_node_or_null(AhhaMomentCutscene.VIDEO_NODE_NAME) as VideoStreamPlayer


## 返回暂停服务当前的活动原因副本；用于断言过场令牌是否仍然存在。
func _active_pause_reasons() -> Array[String]:
	return _controller.gameplay_pause_service.get_active_reasons()


## 停止过场并清空它可能持有的暂停令牌；每个用例的开始与结束都调用，保证用例之间互不影响。
func _stop_cutscene_safely() -> void:
	# 当前过场组件；缺失时无需清理。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return
	cutscene.stop_cutscene()


## 清空桌面上的本地待办选择请求痕迹，使“允许暂停”这一前置条件成立。
##
## 必要性：本测试的对局状态是手工构造的最小状态，回合推进会为本地角色产生与真实阿哈时刻无关的待办请求，
## 而“本机存在待办请求时不得暂停”本身是正式规则。因此验证“正常情况下应当暂停”之前必须先让前置条件
## 回到“没有待办”；待办守卫自身由 _test_client_pending_choice_guard_skips_pause 单独验证。
func _clear_local_pending_choice_state() -> void:
	# 待办请求ID列表；数组是引用类型，取出引用后清空即可改写桌面持有的同一份数据。
	var pending_request_ids: Array = _main_instance.get("_local_pending_choice_request_ids") as Array
	pending_request_ids.clear()
	# 内联询问字典；同样按引用清空，避免类型收窄导致的赋值错误。
	var inline_choice: Dictionary = _main_instance.get("_inline_card_choice") as Dictionary
	inline_choice.clear()
	_main_instance.set("_has_local_pending_choice_request_ids", false)
	_main_instance.set("_modal_choice_request_id", -1)


## 在桌面上登记一条伪本地待办请求，模拟“客户端正持有响应窗口”这一危险状态。
func _mark_local_pending_choice() -> void:
	# 待办请求ID列表；追加伪请求ID即等价于权威端仍然等待本机作答。
	var pending_request_ids: Array = _main_instance.get("_local_pending_choice_request_ids") as Array
	pending_request_ids.append(PENDING_CHOICE_PROBE_REQUEST_ID)
	_main_instance.set("_has_local_pending_choice_request_ids", true)


## 把网关临时切到「已连接的局域网客户端」角色。只改写三个公开角色字段，不建立真实连接、不伪造封包。
## 目的：在不派生第二个Godot进程的前提下复核“收到房主表现事件后播放并暂停”的客户端链路。
func _enter_simulated_lan_client() -> void:
	_save_gateway_role()
	# 当前网关；模拟只写公开角色字段，不触碰连接与会话内部状态。
	var gateway: NetworkGateway = _controller.network_gateway
	gateway.mode = NetworkGateway.Mode.LAN
	gateway.lan_role = NetworkGateway.LanRole.CLIENT
	gateway.connected = true


## 把网关临时切到「已连接的局域网房主」角色，并标记对局已开始。
func _enter_simulated_lan_host() -> void:
	_save_gateway_role()
	# 当前网关；房主角色决定 is_lan_host() 与 is_lan_match_active() 的返回值。
	var gateway: NetworkGateway = _controller.network_gateway
	gateway.mode = NetworkGateway.Mode.LAN
	gateway.lan_role = NetworkGateway.LanRole.HOST
	gateway.connected = true
	gateway.set("_lan_match_active", true)


## 保存网关当前角色，供 _restore_gateway_role 逐字段还原。
func _save_gateway_role() -> void:
	# 当前网关；保存前先确认组件存在，避免测试初始化异常时二次报错。
	var gateway: NetworkGateway = _controller.network_gateway
	_saved_gateway_mode = gateway.mode
	_saved_gateway_role = gateway.lan_role
	_saved_gateway_connected = gateway.connected
	_saved_gateway_match_active = gateway.is_lan_match_active()


## 还原网关角色；未发生模拟时同样安全，恢复的是保存下来的原值。
func _restore_gateway_role() -> void:
	# 当前网关；逐字段还原，保证同一进程内后续用例看到的仍是离线模式。
	var gateway: NetworkGateway = _controller.network_gateway
	gateway.mode = _saved_gateway_mode
	gateway.lan_role = _saved_gateway_role
	gateway.connected = _saved_gateway_connected
	gateway.set("_lan_match_active", _saved_gateway_match_active)


## 等待条件成立；等待走帧推进，超时返回false由调用方按失败处理，不使用固定墙钟休眠。
func _wait_until(condition: Callable, timeout_milliseconds: int) -> bool:
	# 兜底截止时刻；只作为“永不满足”时的上限，不作为等待策略本身。
	var deadline_msec: int = Time.get_ticks_msec() + timeout_milliseconds
	while Time.get_ticks_msec() < deadline_msec:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return bool(condition.call())


## 推进若干帧；测试节点始终处理，因此场景树暂停期间同样可以推进并观察表现层状态。
func _advance_frames(frame_count: int) -> void:
	for _frame_index: int in range(frame_count):
		await get_tree().process_frame


## 校验离线（局域网房主同构）过场期间的暂停与播完立即恢复，并证明视频没有被自己造成的暂停冻结。
func _test_offline_cutscene_pauses_and_releases() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件与视频节点；任一缺失说明桌面装配被破坏，直接失败。
	var cutscene: AhhaMomentCutscene = _cutscene()
	var video: VideoStreamPlayer = _cutscene_video()
	if cutscene == null or video == null:
		return _fail("cutscene_component_missing")
	# 根节点必须保持 PROCESS_MODE_ALWAYS：它是“视频在自己造成的暂停下仍继续播放”的唯一依据，禁止改动。
	if cutscene.process_mode != Node.PROCESS_MODE_ALWAYS:
		return _fail("cutscene_root_process_mode_changed %d" % cutscene.process_mode)
	# 场景覆盖：正式牌桌必须由 .tscn 打开暂停开关，脚本默认值保持最保守的false。
	if not cutscene.pause_gameplay_while_playing:
		return _fail("cutscene_pause_switch_disabled")
	if get_tree().paused:
		return _fail("tree_already_paused_before_cutscene")
	# 正式表现入口：控制器信号与真实阿哈时刻完全同一条链路。
	_controller.ahha_moment_started.emit(2, AhhaMomentSystem.SOURCE_TURN_START)
	if not cutscene.is_pause_held():
		return _fail("offline_cutscene_no_pause_token")
	if not get_tree().paused or not _controller.is_gameplay_paused():
		return _fail("offline_cutscene_tree_not_paused")
	if not _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		return _fail("offline_cutscene_reason_missing %s" % str(_active_pause_reasons()))
	# 视频完整性：根节点为 PROCESS_MODE_ALWAYS，因此解码进度必须在暂停期间继续前进。
	var position_before: float = video.stream_position
	await _advance_frames(VIDEO_PROGRESS_OBSERVATION_FRAMES)
	if video.stream_position <= position_before:
		return _fail("cutscene_video_frozen_by_own_pause %.3f/%.3f" % [position_before, video.stream_position])
	if not cutscene.is_cutscene_playing():
		return _fail("cutscene_stopped_too_early")
	# 自然播完（含淡出结束）后必须立即恢复：等待条件成立，超时上限只防御解码挂死。
	var released: bool = await _wait_until(func() -> bool: return not cutscene.is_pause_held(), CUTSCENE_RELEASE_TIMEOUT_MILLISECONDS)
	if not released:
		return _fail("offline_cutscene_pause_not_released")
	if get_tree().paused or _controller.is_gameplay_paused():
		return _fail("offline_cutscene_tree_still_paused")
	if _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		return _fail("offline_cutscene_reason_residual %s" % str(_active_pause_reasons()))
	return true


## 按“角色ID → [[技能ID, 参演编号], ...]”安装测试欢愉技；技能实例绑定真实控制器与持有者。
func _install_joy_skills(skill_specs: Dictionary) -> void:
	for player_id_variant: Variant in skill_specs.keys():
		var player_id: int = int(player_id_variant)
		# 该角色的技能索引；同一用例可给一名角色安装多项参演技能。
		var player_skills: Dictionary = {}
		for spec: Array in skill_specs[player_id_variant] as Array:
			var skill_id: String = str(spec[0])
			var skill: TestJoySkill = TestJoySkill.new(skill_id, int(spec[1]), _performance_log)
			skill.bind(_controller, player_id)
			player_skills[skill_id] = skill
		_controller.skill_instances_by_player[player_id] = player_skills


## 局域网房主：行为必须与离线一致，房主自己也要停。
func _test_lan_host_cutscene_pauses() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；报告缺失时直接失败，避免后续断言读到null。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("host_cutscene_component_missing")
	_enter_simulated_lan_host()
	# 探针接线复核：房主不是客户端，因此客户端灰开关不应影响它。
	if _main_instance.call("_is_local_network_client"):
		_restore_gateway_role()
		return _fail("host_probe_reported_client")
	_controller.ahha_moment_started.emit(1, AhhaMomentSystem.SOURCE_ROUND_END)
	if not cutscene.is_pause_held() or not get_tree().paused:
		_restore_gateway_role()
		return _fail("host_cutscene_no_pause")
	if not _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		_restore_gateway_role()
		return _fail("host_cutscene_reason_missing %s" % str(_active_pause_reasons()))
	# 房主广播只发送表现，不改变本机暂停归属：原因列表必须恰好只有过场这一项。
	if _active_pause_reasons().size() != 1:
		_restore_gateway_role()
		return _fail("host_cutscene_extra_reasons %s" % str(_active_pause_reasons()))
	_stop_cutscene_safely()
	if cutscene.is_pause_held() or get_tree().paused or _controller.is_gameplay_paused():
		_restore_gateway_role()
		return _fail("host_cutscene_stop_not_released")
	_restore_gateway_role()
	return true


## 局域网客户端收到房主表现事件后播放过场并暂停本机；同时确认客户端没有因此运行任何规则。
func _test_lan_client_event_plays_and_pauses() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；缺失时后续断言无法成立。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("client_cutscene_component_missing")
	# 协议事件名冻结：改名必须同步客户端白名单，因此这里显式锁定线上字符串。
	if MatchController.PRESENTATION_EVENT_AHHA_MOMENT_STARTED != "ahha_moment_started":
		return _fail("presentation_event_name_changed %s" % MatchController.PRESENTATION_EVENT_AHHA_MOMENT_STARTED)
	_enter_simulated_lan_client()
	if not _main_instance.call("_is_local_network_client"):
		_restore_gateway_role()
		return _fail("client_probe_not_detected")
	# 客户端不跑规则的前置状态：真实客户端从不 configure AhhaMomentSystem，这里用 shutdown 复现同一状态。
	_controller.ahha_moment_system.shutdown()
	# 随机历史长度快照；收到表现事件不得消耗任何随机数。
	var random_history_size_before: int = _controller.state.random_history.size()
	_controller._on_network_game_event_received(MatchController.PRESENTATION_EVENT_AHHA_MOMENT_STARTED, {
		"performance_count":3,
		"source":AhhaMomentSystem.SOURCE_TURN_START,
	})
	if not cutscene.is_cutscene_playing():
		_restore_gateway_role()
		return _fail("client_event_not_played")
	if not cutscene.is_pause_held() or not get_tree().paused:
		_restore_gateway_role()
		return _fail("client_event_no_pause")
	if not _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		_restore_gateway_role()
		return _fail("client_event_reason_missing %s" % str(_active_pause_reasons()))
	# 客户端未运行任何规则：规则组件仍处于未启用状态，也没有消耗随机数、没有演出队列。
	if _controller.ahha_moment_system.get("_enabled"):
		_restore_gateway_role()
		return _fail("client_ahha_system_enabled")
	if _controller.ahha_moment_system.is_active():
		_restore_gateway_role()
		return _fail("client_ahha_queue_active")
	if _controller.state.random_history.size() != random_history_size_before:
		_restore_gateway_role()
		return _fail("client_event_consumed_random")
	# 播完（含淡出）必须恢复：客户端暂停同样由组件自身生命周期负责。
	var released: bool = await _wait_until(func() -> bool: return not cutscene.is_pause_held(), CUTSCENE_RELEASE_TIMEOUT_MILLISECONDS)
	_restore_gateway_role()
	if not released:
		return _fail("client_pause_not_released")
	if get_tree().paused or _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		return _fail("client_pause_residual %s" % str(_active_pause_reasons()))
	return true


## 客户端待办守卫：本机仍有待办选择请求时收到阿哈事件只播放、不暂停（防真死锁）。
func _test_client_pending_choice_guard_skips_pause() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；缺失时无法复核播放状态。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("pending_guard_cutscene_missing")
	_enter_simulated_lan_client()
	# 危险前置：本机正持有响应窗口，此时若冻结场景树就会让权威端一直等待真人输入。
	_mark_local_pending_choice()
	_controller.ahha_moment_system.shutdown()
	_controller._on_network_game_event_received(MatchController.PRESENTATION_EVENT_AHHA_MOMENT_STARTED, {
		"performance_count":1,
		"source":AhhaMomentSystem.SOURCE_EXTRA_MOMENT,
	})
	if not cutscene.is_cutscene_playing():
		_restore_gateway_role()
		return _fail("pending_guard_not_played")
	if cutscene.is_pause_held() or get_tree().paused or _controller.is_gameplay_paused():
		_restore_gateway_role()
		return _fail("pending_guard_paused_anyway")
	if _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		_restore_gateway_role()
		return _fail("pending_guard_reason_residual %s" % str(_active_pause_reasons()))
	# 播完仍必须正常收场：跳过暂停不影响过场自身的播放与结束。
	var finished: bool = await _wait_until(func() -> bool: return not cutscene.is_cutscene_playing(), CUTSCENE_RELEASE_TIMEOUT_MILLISECONDS)
	_restore_gateway_role()
	if not finished:
		return _fail("pending_guard_cutscene_never_finished")
	_clear_local_pending_choice_state()
	if get_tree().paused:
		return _fail("pending_guard_tree_still_paused")
	return true


## 客户端暂停灰开关：allow_pause_on_network_client 为假时客户端只播放、不暂停。
func _test_network_client_pause_grey_switch() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；灰开关写在组件上，因此必须对它写入。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("grey_switch_cutscene_missing")
	_enter_simulated_lan_client()
	cutscene.allow_pause_on_network_client = false
	_controller.ahha_moment_started.emit(1, AhhaMomentSystem.SOURCE_TURN_START)
	var played_without_pause: bool = cutscene.is_cutscene_playing() and not cutscene.is_pause_held() and not get_tree().paused
	cutscene.allow_pause_on_network_client = true
	_stop_cutscene_safely()
	_restore_gateway_role()
	if not played_without_pause:
		return _fail("grey_switch_paused_client")
	return true


## 未知网络事件安全降级：闭式白名单之外的任何事件都必须被静默忽略，且不存在暂停类事件。
func _test_unknown_network_event_degrades_safely() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；用于确认未知事件没有意外触发演出或暂停。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("unknown_event_cutscene_missing")
	_enter_simulated_lan_client()
	# 暂停语义不得进入网络协议：即便伪造同名事件，客户端也必须完全忽略。
	_controller._on_network_game_event_received("pause_started", {"reason":"ahha_moment_cutscene"})
	_controller._on_network_game_event_received("pause_released", {})
	_controller._on_network_game_event_received("ahha_moment_unknown", {"performance_count":1})
	var degraded_safely: bool = not cutscene.is_cutscene_playing() and not cutscene.is_pause_held() and not get_tree().paused
	_restore_gateway_role()
	if not degraded_safely:
		return _fail("unknown_event_had_side_effect")
	return true


## 超时兜底：令牌持有上限到点后强制结束过场并释放令牌，且必须早于视频自然结束。
func _test_cutscene_pause_timeout_watchdog() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件与视频节点；两者共同支撑“兜底早于自然结束”的判定。
	var cutscene: AhhaMomentCutscene = _cutscene()
	var video: VideoStreamPlayer = _cutscene_video()
	if cutscene == null or video == null:
		return _fail("timeout_cutscene_missing")
	# 缩短令牌上限，使兜底在视频自然结束之前必然到期；用例结束再还原为脚本默认值。
	cutscene.max_pause_seconds = TIMEOUT_PROBE_PAUSE_SECONDS
	# 本次观察起点；用于判定释放究竟来自兜底还是来自视频自然结束。
	var started_msec: int = Time.get_ticks_msec()
	cutscene.play_cutscene(AhhaMomentSystem.SOURCE_TURN_START)
	if not cutscene.is_pause_held():
		cutscene.max_pause_seconds = 30.0
		return _fail("timeout_cutscene_no_pause")
	# 中途复核：上限到点之前令牌仍在、过场仍在播放，证明释放不是视频自然结束造成的。
	var hold_observed: bool = await _wait_until(func() -> bool: return Time.get_ticks_msec() - started_msec >= TIMEOUT_PROBE_HOLD_OBSERVATION_MILLISECONDS, CUTSCENE_RELEASE_TIMEOUT_MILLISECONDS)
	if not hold_observed or not cutscene.is_pause_held() or not cutscene.is_cutscene_playing():
		cutscene.max_pause_seconds = 30.0
		return _fail("timeout_probe_released_before_deadline")
	# 超过上限后必须由兜底强制收场：令牌被释放、过场停止、场景树恢复。
	var released: bool = await _wait_until(func() -> bool: return not cutscene.is_pause_held(), CUTSCENE_RELEASE_TIMEOUT_MILLISECONDS)
	# 令牌释放时刻相对申请起点的毫秒数；必须小于视频自然结束所需时间才能证明兜底生效。
	var released_after_msec: int = Time.get_ticks_msec() - started_msec
	# 视频自然结束所需毫秒数（时长+淡出）；兜底必须在它之前完成，否则本用例无法区分两条释放路径。
	var natural_release_msec: int = int((video.get_stream_length() + cutscene.fade_out_seconds) * 1000.0)
	cutscene.max_pause_seconds = 30.0
	if not released:
		return _fail("timeout_watchdog_not_fired")
	if released_after_msec >= natural_release_msec:
		return _fail("timeout_watchdog_too_late %d/%d" % [released_after_msec, natural_release_msec])
	if cutscene.is_cutscene_playing() or get_tree().paused or _controller.is_gameplay_paused():
		return _fail("timeout_watchdog_state_residual")
	if _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		return _fail("timeout_watchdog_reason_residual %s" % str(_active_pause_reasons()))
	return true


## 迟到的兜底回调不得影响其他暂停所有者：过场令牌正常释放后，外部令牌必须原样保留。
func _test_stale_watchdog_keeps_foreign_pause() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；先申请再立即释放，制造一个“已过期但尚未到点”的兜底计时器。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("stale_watchdog_cutscene_missing")
	cutscene.max_pause_seconds = TIMEOUT_PROBE_PAUSE_SECONDS
	cutscene.call("_acquire_pause", true)
	if not cutscene.is_pause_held():
		cutscene.max_pause_seconds = 30.0
		return _fail("stale_watchdog_acquire_failed")
	_stop_cutscene_safely()
	if cutscene.is_pause_held():
		cutscene.max_pause_seconds = 30.0
		return _fail("stale_watchdog_release_failed")
	# 外部暂停所有者；模拟另一个界面入口在同一次过场之后申请了暂停。
	var foreign_token: int = _controller.acquire_gameplay_pause("ahha_test_foreign_pause")
	if foreign_token < 0 or not get_tree().paused:
		cutscene.max_pause_seconds = 30.0
		return _fail("stale_watchdog_foreign_pause_failed")
	# 等待超过过场令牌原本的上限：过期回调若仍生效，就会误释放或误结束这段外部暂停。
	await _wait_until(func() -> bool: return Time.get_ticks_msec() >= STALE_WATCHDOG_OBSERVATION_MILLISECONDS, CUTSCENE_RELEASE_TIMEOUT_MILLISECONDS)
	var foreign_pause_kept: bool = get_tree().paused and not cutscene.is_pause_held() and _active_pause_reasons().has("ahha_test_foreign_pause")
	_controller.release_gameplay_pause(foreign_token)
	cutscene.max_pause_seconds = 30.0
	if not foreign_pause_kept:
		return _fail("stale_watchdog_touched_foreign_pause %s" % str(_active_pause_reasons()))
	if get_tree().paused:
		return _fail("stale_watchdog_foreign_release_failed")
	return true


## 终局兜底：收到 match_finished 后过场必须结束且不残留过场暂停令牌。
func _test_match_finished_stops_cutscene() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；终局兜底由桌面订阅同一信号，因此断言组件状态即可。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("match_finished_cutscene_missing")
	_controller.ahha_moment_started.emit(1, AhhaMomentSystem.SOURCE_TURN_START)
	if not cutscene.is_pause_held():
		return _fail("match_finished_setup_no_pause")
	_controller.match_finished.emit("leader")
	if cutscene.is_pause_held() or cutscene.is_cutscene_playing():
		return _fail("match_finished_cutscene_not_stopped")
	if get_tree().paused or _controller.is_gameplay_paused():
		return _fail("match_finished_pause_residual")
	if _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		return _fail("match_finished_reason_residual %s" % str(_active_pause_reasons()))
	return true


## 回放重演期不申请暂停：重演只播放画面，不冻结任何真实规则。
func _test_replay_playback_does_not_pause() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；回放标记由桌面持有，本用例直接改写同一字段复核接线。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("replay_cutscene_missing")
	_main_instance.set("_replay_session_active", true)
	_controller.ahha_moment_started.emit(1, AhhaMomentSystem.SOURCE_TURN_START)
	# 回放期必须“播放但不暂停”。
	var played_without_pause: bool = cutscene.is_cutscene_playing() and not cutscene.is_pause_held() and not get_tree().paused
	_main_instance.set("_replay_session_active", false)
	_stop_cutscene_safely()
	if not played_without_pause:
		return _fail("replay_paused_gameplay")
	return true


## 联机会话关闭兜底：收到 lan_session_closed 后过场必须结束且不残留过场暂停令牌。
## 本用例会触发桌面的整套联机收场流程，因此固定排在全部过场用例之后执行。
func _test_lan_session_closed_stops_cutscene() -> bool:
	_stop_cutscene_safely()
	_clear_local_pending_choice_state()
	# 当前过场组件；断线兜底同样由桌面订阅信号。
	var cutscene: AhhaMomentCutscene = _cutscene()
	if cutscene == null:
		return _fail("lan_closed_cutscene_missing")
	_controller.ahha_moment_started.emit(1, AhhaMomentSystem.SOURCE_EXTRA_MOMENT)
	if not cutscene.is_pause_held():
		return _fail("lan_closed_setup_no_pause")
	_controller.network_gateway.lan_session_closed.emit("测试断线兜底")
	if cutscene.is_pause_held() or cutscene.is_cutscene_playing():
		return _fail("lan_closed_cutscene_not_stopped")
	if get_tree().paused or _controller.is_gameplay_paused():
		return _fail("lan_closed_pause_residual")
	if _active_pause_reasons().has(AhhaMomentCutscene.PAUSE_REASON):
		return _fail("lan_closed_reason_residual %s" % str(_active_pause_reasons()))
	return true


## 输出失败原因并退出；返回false便于调用方立即终止后续断言。
func _fail(reason: String) -> bool:
	# 兜底收场：任何用例失败都可能停在“过场持有暂停令牌”的状态，必须先释放再退出。
	_stop_cutscene_safely()
	_restore_gateway_role()
	_controller.ahha_moment_system.shutdown()
	print("AHHA_MOMENT_FAIL %s" % reason)
	get_tree().quit(1)
	return false


## 清理主场景并输出成功标记；CI通过进程退出码与固定文本共同确认结果。
func _finish_success() -> void:
	_controller.ahha_moment_system.shutdown()
	_main_instance.queue_free()
	print("AHHA_MOMENT_PASS")
	get_tree().quit(0)
