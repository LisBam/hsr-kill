class_name AhhaMomentSystem
extends Node

## 阿哈时刻系统组件。组件只负责触发概率、参演技能收集与排序、串行执行推进，
## 不执行任何具体欢愉技效果，也不持有技能实例、角色对象或界面节点。

## 触发随机值写入随机历史时使用的稳定类型标识；固定种子回放与测试据此复核本次判定。
const TRIGGER_HISTORY_KIND: String = "ahha_moment_trigger_roll"

## 阿哈时刻开始的公开日志模板；%d 为本轮实际参演技能数量，数量为0时不会触发本流程。
const LOG_TRIGGER_TEMPLATE: String = "阿哈时刻：%d项欢愉技依次演出。"

## 单次同步推进允许连续执行的参演技能数上限；超过后退回下一帧推进，避免异常内容形成深递归调用栈。
const MAX_SYNCHRONOUS_ADVANCES: int = 64


## 当前权威对局控制器；组件只调用其公开端口，不直接改变体力、牌区、技能或座次数组。
var _host: MatchController

## 当前权威对局状态；组件只读取座次、轮数与存活状态，不写入任何权威字段。
var _state: GameState

## 当前对局共享随机源；由控制器注入，保证固定种子、回放历史与其他随机流程处于同一序列。
var _rng: RandomNumberGenerator

## 当前组件是否对本局启用；默认false，未启用时全部公开入口均无副作用。
var _enabled: bool = false

## 当前已经初始化概率状态的轮数；默认-1，进入新轮时更新并重置本轮触发标记。
var _tracked_round_number: int = -1

## 当前轮是否已经触发过阿哈时刻；true时本轮后续回合开始不再重复判定。
var _triggered_this_round: bool = false

## 当前轮每名角色回合开始时使用的相同触发概率；按本轮开始时在场人数倒数计算并锁定到轮末。
var _round_trigger_probability: float = 0.0

## 待执行的参演技能队列；每项只保存可序列化的player_id、skill_id、performance_number与seat_order。
var _performance_queue: Array[Dictionary] = []

## 当前正在执行的队列位置；-1表示尚未开始或已经结束。
var _active_index: int = -1

## 当前参演技能是否已经产生效果、只等待嵌套结算屏障；true时恢复后直接推进下一项。
var _waiting_for_barrier: bool = false

## 阿哈时刻完成后的回合开始恢复角色ID；-1表示没有待恢复角色。
var _resume_player_id: int = -1

## 阿哈时刻完成后的回合恢复是否开启新轮；由触发时上下文固化，恢复期间座次变化不得改写该结论。
var _resume_starts_new_round: bool = false

## 是否已经登记下一帧继续参演队列；防止重复连接process_frame或产生递归deferred调用。
var _next_performance_scheduled: bool = false

## 本次同步推进已连续执行的参演技能数；达到上限后退回下一帧推进。
var _synchronous_advance_count: int = 0


## 让阿哈时刻在场景树暂停期间仍能由帧回调推进队列，保证联机选择后的恢复不被冻结。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 为新对局绑定权威服务并重置全部运行时状态；enabled决定本局是否参与触发判定。
func configure(host: MatchController, state: GameState, rng: RandomNumberGenerator, enabled: bool) -> void:
	shutdown()
	_host = host
	_state = state
	_rng = rng
	_enabled = enabled


## 释放进行中的队列与全部跨步骤状态；重新开局、放弃对局与组件退出时均可安全重复调用。
func shutdown() -> void:
	if is_inside_tree() and get_tree().process_frame.is_connected(_on_next_performance_frame):
		get_tree().process_frame.disconnect(_on_next_performance_frame)
	_performance_queue.clear()
	_active_index = -1
	_waiting_for_barrier = false
	_resume_player_id = -1
	_resume_starts_new_round = false
	_next_performance_scheduled = false
	_synchronous_advance_count = 0
	_tracked_round_number = -1
	_triggered_this_round = false
	_round_trigger_probability = 0.0
	_enabled = false


## 当前是否正在执行阿哈时刻；阶段恢复与停滞自修复据此避免重复触发。
func is_active() -> bool:
	return _enabled and not _performance_queue.is_empty() and _active_index >= 0


## 当前是否已经完成某个欢愉技、只等待嵌套结算屏障；停滞自修复据此安全轻推，不会越过仍在等待响应的技能。
func is_waiting_for_barrier() -> bool:
	return is_active() and _waiting_for_barrier


## 返回本轮已经锁定的触发概率；只读诊断接口，供测试与调试复核概率口径，不参与任何规则判定。
func get_round_trigger_probability() -> float:
	return _round_trigger_probability


## 返回本轮是否已经触发过阿哈时刻；只读诊断接口，供测试与调试复核每轮额度。
func has_triggered_this_round() -> bool:
	return _triggered_this_round


## 在普通回合开始之前尝试触发阿哈时刻；返回true表示该角色的回合事实必须等待本次演出完整结束。
## 本入口由控制器在机缘判定之后调用：此时尚未建立current_player_id与turn_number，该角色也尚未开始回合。
func try_trigger_before_turn_start(turn_context: Dictionary, is_extra_turn: bool) -> bool:
	if is_extra_turn or not _can_trigger_now():
		return false
	# 当前轮数；控制器已在调用前完成新轮递增，因此首名角色与后续角色读取同一稳定值。
	var current_round_number: int = _state.round_number
	if _tracked_round_number != current_round_number:
		_initialize_round_probability(current_round_number)
	if _triggered_this_round:
		return false
	# 触发角色；回合事实尚未建立，因此该值来自调用方上下文而不是current_player_id。
	var trigger_player_id: int = int(turn_context.get("player_id", -1))
	# 参演序列；为空表示场上当前没有任何可执行欢愉技，此时直接跳过。
	# 该判断必须先于随机取值：跳过时不得消耗随机数，也不得占用本轮额度，否则会破坏固定种子的可复现性。
	var performance_order: Array[Dictionary] = build_performance_order(trigger_player_id)
	if performance_order.is_empty():
		return false
	# 本次公开随机值；固定种子下与其他随机流程共同进入同一可回放序列。
	var trigger_roll: float = _rng.randf()
	_state.random_history.append({"kind":TRIGGER_HISTORY_KIND, "round_number":current_round_number, "player_id":trigger_player_id, "probability":_round_trigger_probability, "roll":trigger_roll})
	if trigger_roll >= _round_trigger_probability:
		return false
	_triggered_this_round = true
	_performance_queue = performance_order
	_active_index = -1
	_waiting_for_barrier = false
	_synchronous_advance_count = 0
	_resume_player_id = trigger_player_id
	_resume_starts_new_round = bool(turn_context.get("starts_new_round", false))
	_host.add_log(LOG_TRIGGER_TEMPLATE % _performance_queue.size())
	_advance_to_next_valid_entry()
	return true


## 构建阿哈时刻的欢愉技执行序列；纯查询，不修改任何状态，执行与测试共用同一排序结果。
## 排序键依次为：参演编号升序、以触发角色起算的座次正序、技能稳定ID字典序。
func build_performance_order(trigger_player_id: int) -> Array[Dictionary]:
	# 参演序列结果；没有任何可执行欢愉技时返回空数组，调用方据此跳过整个流程。
	var result: Array[Dictionary] = []
	if _host == null or _state == null or _state.players.is_empty():
		return result
	# 起始座次；触发角色无效时回退当前回合角色，仍无效则不产生任何参演项。
	var trigger_index: int = _resolve_seat_index(trigger_player_id)
	if trigger_index < 0:
		return result
	# 完整座次数量；正序环回展开，保证交换座位后立即使用新顺序。
	var seat_count: int = _state.players.size()
	for seat_offset: int in range(seat_count):
		# 当前座次下标；从触发角色起沿座次正序排列，同编号技能据此决定先后。
		var seat_index: int = posmod(trigger_index + seat_offset, seat_count)
		# 当前座次角色；死亡与离场角色不参与阿哈时刻。
		var player: PlayerState = _state.players[seat_index]
		if player == null or not player.alive or player.out_of_game:
			continue
		# 当前角色的技能实例表；键为稳定技能ID，值为该角色独立持有的技能实例。
		var player_skills: Dictionary = _host.skill_instances_by_player.get(player.player_id, {}) as Dictionary
		for skill_id_variant: Variant in player_skills.keys():
			# 当前技能实例；数据库定义对象与已卸载技能不会出现在本索引中。
			var skill: SkillDefinition = player_skills[skill_id_variant] as SkillDefinition
			if skill == null or not skill.is_joy_skill() or not skill.can_perform_joy_skill():
				continue
			result.append({"player_id":player.player_id, "skill_id":skill.get_id(), "performance_number":skill.get_performance_number(), "seat_order":seat_offset})
	result.sort_custom(Callable(self, "_compare_performance_entries"))
	return result


## 回报当前欢愉技已完整结束；由技能实例在效果成立后调用，匹配成功后推进下一项参演技能。
func finish_joy_skill_performance(player_id: int, skill_id: String) -> bool:
	if not is_active():
		return false
	# 当前参演项；只有回报者与当前项完全一致才接受，避免过期回调推进错误的技能。
	var entry: Dictionary = _performance_queue[_active_index]
	if int(entry.get("player_id", -1)) != player_id or str(entry.get("skill_id", "")) != skill_id:
		return false
	_complete_current_performance()
	return true


## 在通用结算栈清空后恢复阿哈时刻；由控制器在屏障恢复点与停滞自修复处调用。
func continue_after_barrier() -> void:
	if not is_active():
		return
	_waiting_for_barrier = false
	_advance_to_next_valid_entry()


## 初始化新轮相同触发概率；按本轮开始时在场角色数倒数计算，与机缘选择使用同一算法口径。
func _initialize_round_probability(round_number: int) -> void:
	_tracked_round_number = round_number
	_triggered_this_round = false
	# 本轮开始时在场角色数量；死亡与离场角色不获得回合开始触发机会。
	var active_player_count: int = 0
	for player: PlayerState in _state.players:
		if player != null and player.alive and not player.out_of_game:
			active_player_count += 1
	_round_trigger_probability = 1.0 / float(active_player_count) if active_player_count > 0 else 0.0


## 判断当前是否具备开始新一轮阿哈时刻的基础条件；活动流程、终局或未启用时统一拒绝。
func _can_trigger_now() -> bool:
	return _enabled and _host != null and _state != null and not _state.game_over and _rng != null and not is_active()


## 返回指定角色在座次数组中的下标；无效时依次回退到当前回合角色，仍无效返回-1。
func _resolve_seat_index(player_id: int) -> int:
	# 首选角色；触发角色在回合事实建立前仍然有效。
	var player: PlayerState = _state.get_player(player_id)
	if player != null:
		var index: int = _state.players.find(player)
		if index >= 0:
			return index
	# 回退角色；座次或角色列表异常时使用当前回合角色，保证演出仍能定性推进。
	var current_player: PlayerState = _state.get_player(_state.current_player_id)
	return _state.players.find(current_player) if current_player != null else -1


## 参演序列比较函数；先按参演编号升序，再按座次正序，最后按技能稳定ID字典序。
## 第三排序键不可省略：sort_custom不是稳定排序，同一角色持有同编号技能时需要固定次序才能复现。
func _compare_performance_entries(left: Dictionary, right: Dictionary) -> bool:
	# 主排序键；编号越小越先演出。
	var left_number: int = int(left.get("performance_number", 0))
	var right_number: int = int(right.get("performance_number", 0))
	if left_number != right_number:
		return left_number < right_number
	# 次排序键；编号相同时按以当前回合位置起算的座次正序。
	var left_seat: int = int(left.get("seat_order", 0))
	var right_seat: int = int(right.get("seat_order", 0))
	if left_seat != right_seat:
		return left_seat < right_seat
	return str(left.get("skill_id", "")) < str(right.get("skill_id", ""))


## 推进到下一项可执行的参演技能；跳过已死亡、已离场或失去技能的持有者。
func _advance_to_next_valid_entry() -> void:
	_synchronous_advance_count += 1
	if _synchronous_advance_count > MAX_SYNCHRONOUS_ADVANCES:
		# 超长队列或异常内容：改为下一帧继续，避免同步递归耗尽调用栈。
		_schedule_next_performance()
		return
	while _active_index + 1 < _performance_queue.size():
		_active_index += 1
		# 当前参演项；只保存稳定ID，执行前重新读取角色与技能实例，防止前一项已令其失效。
		var entry: Dictionary = _performance_queue[_active_index]
		var performer_id: int = int(entry.get("player_id", -1))
		var skill_id: String = str(entry.get("skill_id", ""))
		# 持有者状态；死亡或离场时跳过本项，不影响后续参演技能。
		var performer: PlayerState = _state.get_player(performer_id)
		if performer == null or not performer.alive or performer.out_of_game:
			continue
		# 技能实例；换将或技能重装后ID不变但实例可能已重建，必须重新读取。
		var skill: SkillDefinition = _host.get_skill_instance(performer_id, skill_id) as SkillDefinition
		if skill == null or not skill.can_perform_joy_skill():
			continue
		_waiting_for_barrier = false
		# 参演上下文；只保存可序列化基础值，供内容文件描述本次演出的来源与座次。
		skill.perform_joy_skill({"ahha_moment":true, "trigger_player_id":_resume_player_id, "seat_order":int(entry.get("seat_order", 0)), "performance_number":int(entry.get("performance_number", 0))})
		return
	_complete_all_performances()


## 完成当前参演技能；若仍有嵌套结算则登记通用续接，否则立即推进下一项。
func _complete_current_performance() -> void:
	if _host.has_nested_settlement_barrier():
		_waiting_for_barrier = true
		_host.defer_ahha_moment_resolution()
		return
	_advance_to_next_valid_entry()


## 全部参演技能结束后清空组件状态并交还回合开始流程。
func _complete_all_performances() -> void:
	# 恢复信息副本；先清空组件状态，恢复阶段若立即触发新流程不会与旧队列混淆。
	var resume_player_id: int = _resume_player_id
	var resume_starts_new_round: bool = _resume_starts_new_round
	_performance_queue.clear()
	_active_index = -1
	_waiting_for_barrier = false
	_resume_player_id = -1
	_resume_starts_new_round = false
	_synchronous_advance_count = 0
	_host.continue_after_ahha_moment(resume_player_id, resume_starts_new_round)


## 登记下一帧继续参演队列；同一等待周期只连接一次process_frame。
func _schedule_next_performance() -> void:
	if _next_performance_scheduled or not is_inside_tree():
		return
	_next_performance_scheduled = true
	if not get_tree().process_frame.is_connected(_on_next_performance_frame):
		get_tree().process_frame.connect(_on_next_performance_frame, Object.CONNECT_ONE_SHOT)


## process_frame恢复点；仍有待回应选择时继续等待下一帧，否则推进下一项参演技能。
func _on_next_performance_frame() -> void:
	if not _next_performance_scheduled:
		return
	_next_performance_scheduled = false
	if not is_active() or _state == null or _state.game_over:
		return
	if _host.has_pending_card_choice():
		_schedule_next_performance()
		return
	_synchronous_advance_count = 0
	_advance_to_next_valid_entry()
