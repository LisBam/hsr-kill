class_name OpportunitySystem
extends Node

## 可插拔机缘系统组件。组件负责触发概率、全体三选一、私有候选、暂停与逆时针结算，不依赖具体主菜单模式。

## 每名角色每次出现的机缘卡数量；默认3张，修改会直接改变弹窗牌位数量与选择协议。
@export_range(1, 6, 1) var cards_per_choice: int = 3

## 绿卡抽取权重；默认100，是当前最低品质与最高基础出现率，运行时通常不动态修改。
@export_range(0, 1000, 1) var green_weight: int = 100

## 蓝卡抽取权重；默认80，低于绿卡且高于紫卡，运行时通常不动态修改。
@export_range(0, 1000, 1) var blue_weight: int = 80

## 紫卡抽取权重；默认60，作为中高品质的基础出现率，运行时通常不动态修改。
@export_range(0, 1000, 1) var purple_weight: int = 60

## 橙卡抽取权重；默认30，与需求给出的第四项权重一致，运行时通常不动态修改。
@export_range(0, 1000, 1) var orange_weight: int = 30

## 红卡抽取权重；需求未给出第五项数值，默认补全为10并暴露在检查器中供直接调整。
@export_range(0, 1000, 1) var red_weight: int = 10

## 全体投票收齐后公开每名玩家票面与当选机缘的展示秒数；默认2秒，设为0可供无头测试跳过表现等待，运行时通常无需动态修改。
@export_range(0.0, 10.0, 0.1) var vote_reveal_duration_seconds: float = 2.0

## 机缘刷新时各品质可提升到的下一档稳定ID；灰色对应需求中的白色，红色已经是最高品质因此没有下一档。
const REFRESH_UPGRADE_QUALITY_BY_QUALITY: Dictionary = {"gray":"green", "green":"blue", "blue":"purple", "purple":"orange", "orange":"red"}

## 当前权威对局控制器；组件只调用其公开规则端口，不直接改变体力、牌区、技能或座次数组。
var _host: MatchController

## 当前权威对局状态；组件只写入自身opportunity_state交互快照，其他状态变化交给控制器接口。
var _state: GameState

## 当前对局共享随机源；由控制器注入以保证固定种子、回放历史与其他随机流程处于同一序列。
var _rng: RandomNumberGenerator

## 本局五种随机品质对应的稳定机缘ID池；配置时从静态目录复制一次，抽取期间不再扫描或复制完整卡牌定义。
var _random_card_ids_by_quality: Dictionary = {}

## 当前效果解析器；每局重新绑定，独立负责目标与具体效果，不承担触发概率和选择队列。
var _effect_resolver: OpportunityEffectResolver = OpportunityEffectResolver.new()

## 当前组件是否对本局启用；模式或测试可在开局时配置，禁用后所有钩子均无副作用。
var _enabled: bool = false

## 当前模式是否允许在普通回合开始与轮末自动触发全体机缘；过关斩将只使用明确的开局与层完成时机，因此保持false。
var _automatic_triggers_enabled: bool = false

## 当前已经初始化概率状态的轮数；默认-1，进入新轮时更新并重置本轮触发标记。
var _tracked_round_number: int = -1

## 当前轮是否已经触发过全体机缘；true时本轮后续普通回合开始与轮末均不再重复触发。
var _triggered_this_round: bool = false

## 当前轮每名角色回合开始时使用的相同触发概率；按本轮开始时在场人数倒数计算并锁定到轮末。
var _round_trigger_probability: float = 0.0

## 尚未完成机缘卡选择的角色队列；按触发角色起逆时针排列，所有选择完成前不会执行任何效果。
var _selection_queue: Array[int] = []

## 已选择机缘卡映射；键为角色ID字符串，值为完整静态卡定义副本，供后续逆时针结算。
var _selected_cards_by_player: Dictionary = {}

## 尚未结算机缘效果的角色队列；固定从触发角色（即将开始回合的那名角色）开始逆时针执行。
var _resolution_queue: Array[int] = []

## 当前正在结算机缘效果的角色ID；默认-1，异步目标选择期间保持稳定。
var _current_effect_owner_id: int = -1

## 当前正在结算的机缘卡定义；空字典表示没有活动效果或正在等待下一张。
var _current_effect_card: Dictionary = {}

## 当前角色因“随机获得机缘”追加的待结算卡队列；每项仅保存获得者稳定ID与静态定义副本，先于下一名原始选择者结算。
var _bonus_effect_queue: Array[Dictionary] = []

## 当前效果是否已经执行且只等待嵌套结算屏障；恢复后应直接进入下一张机缘而不能重复执行效果。
var _current_effect_waiting_for_barrier: bool = false

## 是否已经登记下一帧继续机缘队列；防止响应请求清理边界重复连接process_frame或产生递归deferred调用。
var _next_effect_retry_scheduled: bool = false

## 当前流程是否为“投票选择”模式；true时全体参与者共享同一组候选，全部提交后按票数决出唯一当选机缘。
var _vote_mode: bool = false

## 当前投票流程是否已经登记延迟提交内置AI选票的帧回调；防止多名玩家连续提交时重复安排同一批AI决策。
var _simultaneous_ai_vote_submission_scheduled: bool = false

## 当前投票公开阶段的生命周期代号；新流程与关闭组件都会递增，使旧计时器回调不能推进已经失效的机缘状态。
var _vote_reveal_generation: int = 0

## 机缘流程完成后的恢复类型；before_turn_start恢复尚未开始回合的角色，round_end恢复轮末到下一回合的阶段切换。
var _resume_kind: String = ""

## 机缘流程完成后的可序列化恢复上下文；不保存Callable、节点或PlayerState引用。
var _resume_context: Dictionary = {}

## 触发机缘前的公开阶段；选择与结算期间使用opportunity，完成后恢复原值再交还阶段游标。
var _resume_phase: String = ""

## 选择机缘期间持有的全局暂停令牌；默认-1，全部角色选完后立即释放，目标选择沿用标准规则暂停。
var _selection_pause_token: int = -1


## 让机缘组件在场景树暂停期间仍能接收联机选择动作并释放自身暂停令牌。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 为新对局绑定权威服务并重置全部运行时状态；enabled决定当前模式是否挂载机缘规则。
func configure(host: MatchController, state: GameState, rng: RandomNumberGenerator, enabled: bool, automatic_triggers_enabled: bool = enabled) -> void:
	shutdown()
	_host = host
	_state = state
	_rng = rng
	_enabled = enabled
	_automatic_triggers_enabled = automatic_triggers_enabled and enabled
	for quality_id: String in OpportunityCatalog.QUALITY_ORDER:
		_random_card_ids_by_quality[quality_id] = OpportunityCatalog.get_card_ids_by_quality(quality_id)
	_effect_resolver.configure(self, _host, _state)
	if _state != null:
		_state.opportunity_state.clear()


## 释放进行中的暂停与所有跨步骤状态；重新开局、放弃对局和组件退出时均可安全重复调用。
func shutdown() -> void:
	if is_inside_tree() and get_tree().process_frame.is_connected(_on_next_effect_retry_frame):
		get_tree().process_frame.disconnect(_on_next_effect_retry_frame)
	if _selection_pause_token >= 0 and _host != null:
		_host.release_gameplay_pause(_selection_pause_token)
	_selection_pause_token = -1
	_selection_queue.clear()
	_selected_cards_by_player.clear()
	_resolution_queue.clear()
	_random_card_ids_by_quality.clear()
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_bonus_effect_queue.clear()
	_current_effect_waiting_for_barrier = false
	_next_effect_retry_scheduled = false
	_vote_mode = false
	_simultaneous_ai_vote_submission_scheduled = false
	_vote_reveal_generation += 1
	_resume_kind = ""
	_resume_context.clear()
	_resume_phase = ""
	_tracked_round_number = -1
	_triggered_this_round = false
	_round_trigger_probability = 0.0
	if _state != null:
		_state.opportunity_state.clear()
	_enabled = false
	_automatic_triggers_enabled = false


## 当前组件是否启用且正在选择或结算机缘；阶段恢复与测试可据此避免重复触发。
func is_active() -> bool:
	return _enabled and _state != null and not _state.opportunity_state.is_empty()


## 在普通回合开始之前尝试触发机缘；返回true表示该角色的回合事实必须等待本次机缘完整结束。
## 本入口位于回合事实之前：控制器调用时尚未把 current_player_id、turn_number 与回合开始初始化
## 推进到该角色，因此本次机缘在规则上不处于任何角色的回合，该角色也尚未开始回合。
func try_trigger_before_turn_start(turn_context: Dictionary, is_extra_turn: bool) -> bool:
	if not _automatic_triggers_enabled or not _can_trigger_now() or is_extra_turn:
		return false
	# 当前轮数；控制器已在调用前完成新轮递增，因此首名角色与后续角色读取同一稳定值。
	var current_round_number: int = _state.round_number
	if _tracked_round_number != current_round_number:
		_initialize_round_probability(current_round_number)
	if _triggered_this_round:
		return false
	# 本次公开随机值；固定种子下与卡牌候选共同进入同一可回放序列。
	var trigger_roll: float = _rng.randf()
	_state.random_history.append({"kind":"opportunity_trigger_roll", "round_number":current_round_number, "player_id":int(turn_context.get("player_id", -1)), "probability":_round_trigger_probability, "roll":trigger_roll})
	if trigger_roll >= _round_trigger_probability:
		return false
	_begin_trigger(int(turn_context.get("player_id", -1)), false, "before_turn_start", turn_context)
	return true


## 在普通轮末强制补触发；仅当本轮所有回合开始均未触发时返回true并阻止进入下一回合。
func try_trigger_at_round_end(finished_player_id: int) -> bool:
	if not _automatic_triggers_enabled or not _can_trigger_now():
		return false
	if _tracked_round_number != _state.round_number:
		_initialize_round_probability(_state.round_number)
	if _triggered_this_round:
		return false
	_begin_trigger(finished_player_id, true, "round_end", {"finished_player_id":finished_player_id})
	return true


## 供测试、调试器或其他模式按明确时机主动触发机缘；活动流程存在时拒绝重复开始。
func force_trigger(trigger_player_id: int, resume_kind: String = "manual", resume_context: Dictionary = {}) -> bool:
	if not _can_trigger_now():
		return false
	if _tracked_round_number != _state.round_number:
		_initialize_round_probability(_state.round_number)
	_begin_trigger(trigger_player_id, true, resume_kind, resume_context)
	return true


## 按明确名单触发机缘选择；过关斩将等模式可只让指定玩家三选一，不继承全体逆时针参与者规则。
func force_trigger_for_players(trigger_player_id: int, participant_ids: Array[int], resume_kind: String = "manual", resume_context: Dictionary = {}) -> bool:
	if not _can_trigger_now():
		return false
	if _tracked_round_number != _state.round_number:
		_initialize_round_probability(_state.round_number)
	var valid_participant_ids: Array[int] = _filter_alive_participant_ids(participant_ids)
	if valid_participant_ids.is_empty():
		return false
	_begin_trigger(trigger_player_id, true, resume_kind, resume_context, valid_participant_ids)
	return true


## 按明确名单以“投票选择”触发机缘：全体参与者共享同一组三张候选并同时获得投票资格，各自独立提交一票。
## 全部提交后取票数最高的机缘，平票时在同票机缘中随机；当选机缘写入每名存活参与者的公开历史并逐人结算。
## 单一参与者时投票结果必然是本人所投机缘，行为与各自选择完全一致。
func force_trigger_vote_for_players(trigger_player_id: int, participant_ids: Array[int], resume_kind: String = "manual", resume_context: Dictionary = {}) -> bool:
	if not _can_trigger_now():
		return false
	if _tracked_round_number != _state.round_number:
		_initialize_round_probability(_state.round_number)
	var valid_participant_ids: Array[int] = _filter_alive_participant_ids(participant_ids)
	if valid_participant_ids.is_empty():
		return false
	_begin_trigger(trigger_player_id, true, resume_kind, resume_context, valid_participant_ids, true)
	return true


## 过滤请求参与者中仍存活的角色并去重；死亡角色不进入选择或投票队列，离场但存活角色继续参与。
func _filter_alive_participant_ids(participant_ids: Array[int]) -> Array[int]:
	# 合法参与者结果；保持调用方传入顺序，重复稳定ID只保留首个。
	var result: Array[int] = []
	for participant_id: int in participant_ids:
		# 当前候选参与者状态；死亡角色跳过，离场但存活角色仍参与机缘流程。
		var participant: PlayerState = _state.get_player(participant_id)
		if participant != null and participant.alive and not result.has(participant_id):
			result.append(participant_id)
	return result


## 接受玩家、局域网客户端或回放提交的机缘卡ID；投票与各自选择都接受任一尚未提交的参与者，不存在先后解锁的当前选择者。
func submit_choice(player_id: int, card_id: String) -> bool:
	if not is_active() or str(_state.opportunity_state.get("stage", "")) != "choosing":
		return false
	# 待提交集合；所有名单内玩家可并行提交，已经提交过的玩家会因不在集合中而被拒绝重复提交。
	# 投票与各自选择共用同一份同时开放集合：各自选择不再有逐个解锁的当前选择者，因此这里不再读取 current_chooser_id。
	if not _selection_queue.has(player_id):
		return false
	# 当前角色私有候选；字符串键是权威状态的稳定形式，兼容JSON网络序列化。
	var options_by_player: Dictionary = _state.opportunity_state.get("options_by_player", {}) as Dictionary
	# 当前候选数组；只在服务器权威状态中包含完整三张定义。
	var player_options: Array = options_by_player.get(str(player_id), []) as Array
	# 匹配的合法卡定义；空字典表示伪造ID或旧弹窗提交。
	var selected_card: Dictionary = {}
	for option_variant: Variant in player_options:
		# 当前候选定义；逐项比较稳定ID，不信任客户端提交的品质或正文。
		var option: Dictionary = option_variant as Dictionary
		if str(option.get("id", "")) == card_id:
			selected_card = OpportunityCatalog.get_card(card_id)
			break
	if selected_card.is_empty():
		return false
	_record_player_choice(player_id, selected_card)
	_selection_queue.erase(player_id)
	_advance_selection_queue()
	return true


## 为被托管、断线接管或停滞修复的玩家代选机缘卡；投票与各自选择都允许任一尚未提交的目标独立代选。
## 代选复用与内置AI完全相同的估值入口，并经由submit_choice权威校验推进状态，不形成绕过校验的第二条写路径。
func choose_for_managed_player(player_id: int) -> bool:
	if not is_active() or str(_state.opportunity_state.get("stage", "")) != "choosing":
		return false
	if not _selection_queue.has(player_id):
		return false
	# 该玩家私有候选；估值与提交都只使用权威状态中的候选，不信任任何外部传入卡面。
	var managed_player_options: Array = (_state.opportunity_state.get("options_by_player", {}) as Dictionary).get(str(player_id), []) as Array
	# AI估值选出的机缘卡；估值异常返回空字典时回退首张候选，保证接管路径始终能解除全体等待。
	var chosen_card: Dictionary = _choose_ai_card(player_id, managed_player_options)
	var chosen_card_id: String = str(chosen_card.get("id", ""))
	if chosen_card_id.is_empty() and not managed_player_options.is_empty():
		chosen_card_id = str((managed_player_options[0] as Dictionary).get("id", ""))
	if chosen_card_id.is_empty():
		return false
	return submit_choice(player_id, chosen_card_id)


## 恢复机缘解析器创建的标准ChoiceRequest；控制器在普通卡牌、技能处理前优先调用本入口。
func continue_choice(context: Dictionary, response: ChoiceResponse) -> bool:
	if not is_active() or str(_state.opportunity_state.get("stage", "")) != "resolving":
		return false
	return _effect_resolver.continue_choice(context, response)


## 完成当前单张机缘效果；若体力或移牌插入嵌套选择，则登记通用续接并等待屏障清空。
func complete_current_effect() -> void:
	if _state == null or _state.game_over:
		_finish_without_resume()
		return
	if _host.has_nested_settlement_barrier():
		_current_effect_waiting_for_barrier = true
		_host.defer_opportunity_resolution()
		return
	_finish_current_effect_and_continue()


## 在通用结算栈清空后恢复机缘；多目标伤害优先继续剩余目标，否则推进下一张已执行效果。
func continue_after_barrier() -> void:
	if not is_active():
		return
	if _effect_resolver.continue_after_barrier():
		return
	if _current_effect_waiting_for_barrier:
		_current_effect_waiting_for_barrier = false
		_finish_current_effect_and_continue()
		return
	_schedule_next_effect_resolution()


## 返回完整机缘卡目录，供无头测试与内容校验读取；调用方获得深拷贝。
func get_card_catalog() -> Array[Dictionary]:
	return OpportunityCatalog.get_all_cards()


## 返回当前品质权重快照；键顺序不作为规则契约，抽取过程始终按OpportunityCatalog.QUALITY_ORDER遍历。
func get_quality_weights() -> Dictionary:
	return {"green":green_weight, "blue":blue_weight, "purple":purple_weight, "orange":orange_weight, "red":red_weight}


## 将一名角色已拥有的全部机缘替换为同品质新机缘；每张非红机缘独立按指定概率升级一档，返回是否已成功写入新历史。
func refresh_player_acquired_opportunities(player_id: int, upgrade_chance: float) -> bool:
	# 当前刷新对象；死亡角色已经不会结算机缘，离场但存活角色仍可按机缘模式规则刷新自身历史。
	var player: PlayerState = _state.get_player(player_id) if _state != null else null
	if player == null or not player.alive or _host == null or _rng == null:
		return false
	# 原机缘历史副本；刷新必须以本次红色机缘入历史后的完整集合为准，允许包含重复ID。
	var original_opportunity_ids: Array[String] = player.acquired_opportunity_ids.duplicate()
	if original_opportunity_ids.is_empty():
		return false
	# 刷新后的稳定ID数组；未知旧ID无法判定品质，保留原值以避免损坏回放历史。
	var refreshed_opportunity_ids: Array[String] = []
	# 本次随机过程摘要；保存每张旧卡、目标品质、随机值与新ID，供固定种子回放复核。
	var refresh_entries: Array[Dictionary] = []
	# 已限制到合法区间的升级概率；目录当前传入0.3，接口仍防御异常扩展内容。
	var normalized_upgrade_chance: float = clampf(upgrade_chance, 0.0, 1.0)
	for original_opportunity_id: String in original_opportunity_ids:
		# 旧机缘静态定义；缺失定义时不改写该历史项，后续条目仍可正常刷新。
		var original_card: Dictionary = OpportunityCatalog.get_card(original_opportunity_id)
		var original_quality_id: String = str(original_card.get("quality", ""))
		if original_card.is_empty() or original_quality_id.is_empty():
			refreshed_opportunity_ids.append(original_opportunity_id)
			refresh_entries.append({"old_id":original_opportunity_id, "new_id":original_opportunity_id, "quality":"", "upgraded":false})
			continue
		# 可提升品质；红色或未知品质没有下一档，保持原品质且不消耗随机数。
		var target_quality_id: String = original_quality_id
		var upgrade_roll: float = -1.0
		var upgraded: bool = false
		var upgrade_quality_id: String = str(REFRESH_UPGRADE_QUALITY_BY_QUALITY.get(original_quality_id, ""))
		if not upgrade_quality_id.is_empty():
			upgrade_roll = _rng.randf()
			if upgrade_roll < normalized_upgrade_chance:
				target_quality_id = upgrade_quality_id
				upgraded = true
		# 目标品质可选池；同品质刷新必须排除原卡，确保“新机缘”不会原样保留。
		var candidate_ids: Array[String] = OpportunityCatalog.get_card_ids_by_quality(target_quality_id)
		if target_quality_id == original_quality_id:
			candidate_ids.erase(original_opportunity_id)
		# 刷新后的稳定ID；理论上每档至少有两张卡，异常配置候选为空时保留原ID而不中断整次刷新。
		var refreshed_opportunity_id: String = original_opportunity_id
		if not candidate_ids.is_empty():
			refreshed_opportunity_id = candidate_ids[_rng.randi_range(0, candidate_ids.size() - 1)]
		refreshed_opportunity_ids.append(refreshed_opportunity_id)
		refresh_entries.append({"old_id":original_opportunity_id, "new_id":refreshed_opportunity_id, "quality":target_quality_id, "upgraded":upgraded, "roll":upgrade_roll})
	# 控制器统一调整历史派生的技能、体力上限与手牌上限；一次性效果不会倒放或重复执行。
	if not _host.replace_acquired_opportunity_history(player_id, refreshed_opportunity_ids, "opportunity_refresh"):
		return false
	_state.random_history.append({"kind":"opportunity_refresh", "player_id":player_id, "upgrade_chance":normalized_upgrade_chance, "entries":refresh_entries})
	_host.add_log("%s刷新了%d项机缘。" % [_host.format_player_log_name(player_id), refreshed_opportunity_ids.size()])
	_host.refresh_state_snapshot()
	return true


## 随机授予指定品质中尚未拥有的机缘，并把它们插入当前角色的后续结算队列；返回实际取得的定义数组。
func grant_random_unowned_opportunities(player_id: int, quality_id: String, requested_count: int) -> Array[Dictionary]:
	# 当前获得者；死亡角色不能新增历史，离场但存活角色允许结算自己的机缘奖励。
	var player: PlayerState = _state.get_player(player_id) if _state != null else null
	# 请求数量；0或负数不消耗随机数，也不创建空的后续效果队列。
	var grant_count: int = maxi(requested_count, 0)
	var granted_cards: Array[Dictionary] = []
	if player == null or not player.alive or _rng == null or grant_count == 0:
		return granted_cards
	# 已拥有ID集合；同名机缘重复取得不满足“未拥有”，本次随机还会从候选池删除以保证三项互不重复。
	var owned_opportunity_ids: Dictionary = {}
	for owned_opportunity_id: String in player.acquired_opportunity_ids:
		owned_opportunity_ids[owned_opportunity_id] = true
	# 可随机取得的候选池；目录返回独立数组，删除已拥有项不会污染本局常驻品质池。
	var candidate_ids: Array[String] = OpportunityCatalog.get_card_ids_by_quality(quality_id)
	for candidate_index: int in range(candidate_ids.size() - 1, -1, -1):
		# 当前候选稳定ID；历史中已出现的项目从尾部安全移除。
		var candidate_id: String = candidate_ids[candidate_index]
		if owned_opportunity_ids.has(candidate_id):
			candidate_ids.remove_at(candidate_index)
	while granted_cards.size() < grant_count and not candidate_ids.is_empty():
		# 本次随机位置；使用对局共享随机源，保证网络权威端与回放的结果可复现。
		var random_index: int = _rng.randi_range(0, candidate_ids.size() - 1)
		# 本次获得ID；立刻从局部候选移除，确保同一张红色机缘得到的三项互不重复。
		var granted_opportunity_id: String = candidate_ids[random_index]
		candidate_ids.remove_at(random_index)
		# 当前静态定义；异常目录ID跳过，不把空定义写入历史或效果队列。
		var granted_card: Dictionary = OpportunityCatalog.get_card(granted_opportunity_id)
		if granted_card.is_empty():
			continue
		player.acquired_opportunity_ids.append(granted_opportunity_id)
		granted_cards.append(granted_card)
		_bonus_effect_queue.append({"owner_player_id":player_id, "card_definition":granted_card.duplicate(true)})
	if not granted_cards.is_empty():
		# 随机历史只保存稳定ID；正文与数值继续由静态目录按当前规则版本解析。
		var granted_opportunity_ids: Array[String] = []
		for granted_card: Dictionary in granted_cards:
			granted_opportunity_ids.append(str(granted_card.get("id", "")))
		_state.random_history.append({"kind":"opportunity_random_unowned", "player_id":player_id, "quality":quality_id, "opportunity_ids":granted_opportunity_ids})
		_host.add_log("%s随机获得了%d项%s机缘。" % [_host.format_player_log_name(player_id), granted_cards.size(), OpportunityCatalog.get_quality_name(quality_id)])
		_host.refresh_state_snapshot()
	return granted_cards


## 开始一次全体机缘；先生成全部私有候选并暂停场景树，所有角色选完后才释放暂停和执行效果。
## vote_mode=true 时只抽取一组共享候选并复制给每名参与者，全部提交后按票数决出唯一当选机缘。
func _begin_trigger(trigger_player_id: int, forced: bool, resume_kind: String, resume_context: Dictionary, requested_participant_ids: Array[int] = [], vote_mode: bool = false) -> void:
	_triggered_this_round = true
	_vote_mode = vote_mode
	_simultaneous_ai_vote_submission_scheduled = false
	_vote_reveal_generation += 1
	_resume_kind = resume_kind
	_resume_context = resume_context.duplicate(true)
	_resume_phase = _state.current_phase
	_state.current_phase = "opportunity"
	# 本次参与者与逆时针顺序；触发角色无效时回退当前回合角色，再回退首名在场角色。
	var participant_ids: Array[int] = requested_participant_ids.duplicate() if not requested_participant_ids.is_empty() else _build_counterclockwise_order(trigger_player_id)
	if participant_ids.is_empty():
		_finish_without_resume()
		return
	_selection_queue = participant_ids.duplicate()
	_resolution_queue = participant_ids.duplicate()
	_selected_cards_by_player.clear()
	# 每名角色私有候选映射；权威状态保存完整定义，GameState.to_dict负责按观察者裁剪。
	var options_by_player: Dictionary = {}
	# 随机历史只记录稳定ID；正文与效果参数始终由同一静态目录解析，避免长期历史重复保存完整定义。
	var option_ids_by_player: Dictionary = {}
	if vote_mode:
		# 投票共享候选；只抽取一次并复制给全部参与者，因此每名玩家看到与投出的都是同一组机缘。
		var shared_options: Array[Dictionary] = _draw_options_for_player(participant_ids[0])
		# 共享候选稳定ID；随机历史只保存一份紧凑摘要，固定种子回放可据此复核抽取结果。
		var shared_option_ids: Array[String] = []
		for option_definition: Dictionary in shared_options:
			shared_option_ids.append(str(option_definition.get("id", "")))
		for participant_id: int in participant_ids:
			options_by_player[str(participant_id)] = shared_options.duplicate(true)
			option_ids_by_player[str(participant_id)] = shared_option_ids.duplicate()
	else:
		for participant_id: int in participant_ids:
			# 当前角色私有候选；权威交互状态仍保存完整卡面，只有随机历史改为紧凑ID摘要。
			var participant_options: Array[Dictionary] = _draw_options_for_player(participant_id)
			options_by_player[str(participant_id)] = participant_options
			# 当前角色候选ID；顺序必须与实际三张卡一致，固定种子回放可据此复核抽取结果。
			var participant_option_ids: Array[String] = []
			for option_definition: Dictionary in participant_options:
				participant_option_ids.append(str(option_definition.get("id", "")))
			option_ids_by_player[str(participant_id)] = participant_option_ids
	_state.opportunity_state = {
		"active":true,
		"stage":"choosing",
		"round_number":_state.round_number,
		"trigger_player_id":participant_ids[0],
		"forced":forced,
		"vote_mode":vote_mode,
		"participant_ids":participant_ids.duplicate(),
		"chosen_player_ids":[],
		"pending_chooser_ids":participant_ids.duplicate(),
		"current_chooser_id":-1,
		"current_resolver_id":-1,
		"options_by_player":options_by_player,
	}
	_state.random_history.append({"kind":"opportunity_options", "round_number":_state.round_number, "trigger_player_id":participant_ids[0], "vote_mode":vote_mode, "option_ids_by_player":option_ids_by_player})
	if vote_mode and participant_ids.size() > 1:
		_host.add_log("触发全体机缘投票：所有玩家从同一组三张机缘卡中各投一票，票数最高者当选。")
	else:
		_host.add_log("触发全体机缘选择：每名角色从三张机缘卡中选择一张。")
	_selection_pause_token = _host.acquire_gameplay_pause("opportunity_selection")
	_advance_selection_queue()


## 推进全体选择状态；所有参与者同时开放提交，不再存在逐个解锁的当前选择者。
## 参与者逆时针顺序只决定效果结算顺序，不决定谁能先选；效果仍要等全部选择完成后统一逆时针结算。
## 投票模式与各自选择的差别只在候选是否共享、结果是否公开票面：前者延迟驱动AI以先公开“可投票”状态，后者在同一调用栈内批量完成AI估值。
func _advance_selection_queue() -> void:
	if not is_active() or str(_state.opportunity_state.get("stage", "")) != "choosing":
		return
	# 当前仍合法的待选玩家；死亡角色跳过，仍存活的离场角色继续参与机缘三选一。
	var pending_chooser_ids: Array[int] = []
	for pending_player_id: int in _selection_queue:
		# 当前待选玩家状态；死亡或缺失角色不再保留选择资格，避免其余参与者永久等待。
		var pending_chooser: PlayerState = _state.get_player(pending_player_id)
		if pending_chooser != null and pending_chooser.alive:
			pending_chooser_ids.append(pending_player_id)
	_selection_queue = pending_chooser_ids
	if _vote_mode:
		_state.opportunity_state["current_chooser_id"] = -1
		_state.opportunity_state["pending_chooser_ids"] = _selection_queue.duplicate()
		if _selection_queue.is_empty():
			_finish_all_choices()
			return
		# 离线控制全部角色只有一个本地观察者；切到首名待投角色供同一屏幕逐个代管，权威待投集合仍同时开放且LAN不会切换观察者。
		_host.prepare_opportunity_chooser(_selection_queue[0])
		# AI投票延后一帧，使全部真人观察者先收到同一“可投票”状态；回调内仍逐票经过同一候选估值和待提交集合校验。
		if not _simultaneous_ai_vote_submission_scheduled:
			for pending_player_id: int in _selection_queue:
				if _host.ai_coordinator != null and _host.ai_coordinator.is_ai_controlled(pending_player_id):
					_simultaneous_ai_vote_submission_scheduled = true
					call_deferred("_submit_simultaneous_ai_votes", _vote_reveal_generation)
					break
		_host.refresh_state_snapshot()
		return
	# 各自选择：在同一调用栈内连续完成全部内置AI的估值，不为每名AI广播一次无视觉价值的整局重绘。
	# 遍历副本以便就地移除，使AI与真人提交共用同一份待提交集合语义。
	for pending_player_id: int in _selection_queue.duplicate():
		if _host.ai_coordinator == null or not _host.ai_coordinator.is_ai_controlled(pending_player_id):
			continue
		_try_submit_ai_choice(pending_player_id)
		_selection_queue.erase(pending_player_id)
	_state.opportunity_state["current_chooser_id"] = -1
	_state.opportunity_state["pending_chooser_ids"] = _selection_queue.duplicate()
	if _selection_queue.is_empty():
		_finish_all_choices()
		return
	# 离线控制全部角色只有一个本地观察者；切到首名待选角色供同一屏幕逐个代管，权威待选集合仍同时开放且LAN不会切换观察者。
	_host.prepare_opportunity_chooser(_selection_queue[0])
	# 其余待选者全部是真人；一次性广播同一份“可选择”状态，本地与远端真人之间不存在先后解锁关系。
	_host.refresh_state_snapshot()


## 为单名内置AI估值并记录其机缘选择；投票与各自选择共用同一估值入口，不形成第二条写路径。
func _try_submit_ai_choice(player_id: int) -> bool:
	# 当前AI私有候选；从权威映射读取，基础策略不接触其他角色的机缘牌面。
	var options_by_player: Dictionary = _state.opportunity_state.get("options_by_player", {}) as Dictionary
	# AI候选数组；每项均来自静态目录，不包含可执行Callable或运行时对象。
	var ai_options: Array = options_by_player.get(str(player_id), []) as Array
	# AI选择结果；空字典只可能来自异常空候选，此时跳过该角色避免死锁，由停滞修复兜底。
	var ai_card: Dictionary = _choose_ai_card(player_id, ai_options)
	if ai_card.is_empty():
		return false
	_record_player_choice(player_id, ai_card)
	return true


## 为本次投票中的全部内置AI分别估值并提交一张；提交顺序不控制真人资格，也不会公开尚未收齐的具体票面。
func _submit_simultaneous_ai_votes(expected_generation: int) -> void:
	_simultaneous_ai_vote_submission_scheduled = false
	if expected_generation != _vote_reveal_generation or not is_active() or not _vote_mode or str(_state.opportunity_state.get("stage", "")) != "choosing":
		return
	# 本帧需要自动提交的AI名单；先复制待投集合，避免提交过程中修改正在遍历的数组。
	var ai_voter_ids: Array[int] = []
	for pending_player_id: int in _selection_queue:
		if _host.ai_coordinator != null and _host.ai_coordinator.is_ai_controlled(pending_player_id):
			ai_voter_ids.append(pending_player_id)
	for ai_voter_id: int in ai_voter_ids:
		if not _selection_queue.has(ai_voter_id):
			continue
		# 当前AI估值结果；空候选由下一轮停滞修复处理，因此此处保留其待投资格而不伪造票面。
		if not _try_submit_ai_choice(ai_voter_id):
			continue
		_selection_queue.erase(ai_voter_id)
	_advance_selection_queue()


## 记录一名角色的最终机缘选择；公开状态只暴露已完成角色ID，不在其他观察者快照中公开卡面正文。
func _record_player_choice(player_id: int, card_definition: Dictionary) -> void:
	_selected_cards_by_player[str(player_id)] = card_definition.duplicate(true)
	# 已完成选择角色列表；只追加一次，供等待界面显示进度。
	var chosen_player_ids: Array = (_state.opportunity_state.get("chosen_player_ids", []) as Array).duplicate()
	if not chosen_player_ids.has(player_id):
		chosen_player_ids.append(player_id)
	_state.opportunity_state["chosen_player_ids"] = chosen_player_ids
	_host.add_log("%s已完成机缘%s。" % [_host.format_player_log_name(player_id), "投票" if _vote_mode else "选择"])


## 全体选择完成后进入明确的结果边界；投票先公开每人票面并等待展示，各自选择直接进入效果结算。
func _finish_all_choices() -> void:
	if _vote_mode:
		_apply_vote_result()
		_state.opportunity_state["current_chooser_id"] = -1
		_state.opportunity_state["pending_chooser_ids"] = []
		_state.opportunity_state["stage"] = "revealing"
		_host.refresh_state_snapshot()
		if vote_reveal_duration_seconds > 0.0 and is_inside_tree():
			# 本次公开阶段代号；计时结束时用于拒绝重开或关闭组件前创建的旧回调。
			var expected_generation: int = _vote_reveal_generation
			get_tree().create_timer(vote_reveal_duration_seconds, true).timeout.connect(Callable(self, "_continue_after_vote_reveal").bind(expected_generation), Object.CONNECT_ONE_SHOT)
			return
	_begin_effect_resolution_after_choices()


## 投票结果展示计时结束后进入效果结算；生命周期代号与阶段双重校验保证旧计时器不能恢复新对局。
func _continue_after_vote_reveal(expected_generation: int) -> void:
	if expected_generation != _vote_reveal_generation or not is_active() or str(_state.opportunity_state.get("stage", "")) != "revealing":
		return
	_begin_effect_resolution_after_choices()


## 把最终机缘写入存活参与者历史，释放选择暂停并开始按既定顺序执行效果。
func _begin_effect_resolution_after_choices() -> void:
	if not is_active() or _state.game_over:
		_finish_without_resume()
		return
	# 已获得机缘历史；全体选择完成后才公开写入，避免其他观察者在私有选择阶段反推出具体卡面。
	for player_id_key: Variant in _selected_cards_by_player.keys():
		# 选择者稳定ID；字典键使用字符串以兼容网络序列化。
		var player_id: int = int(str(player_id_key))
		# 选择者状态；死亡前已经完成选择的角色不再获得历史，离场但存活角色正常记录。
		var player: PlayerState = _state.get_player(player_id)
		if player == null or not player.alive:
			continue
		# 已选机缘ID；允许跨轮重复获得同一机缘，详情按真实获得顺序逐项展示。
		var opportunity_id: String = str((_selected_cards_by_player.get(str(player_id), {}) as Dictionary).get("id", ""))
		if not opportunity_id.is_empty():
			player.acquired_opportunity_ids.append(opportunity_id)
	_state.opportunity_state["current_chooser_id"] = -1
	_state.opportunity_state["pending_chooser_ids"] = []
	_state.opportunity_state["stage"] = "resolving"
	if _selection_pause_token >= 0:
		_host.release_gameplay_pause(_selection_pause_token)
		_selection_pause_token = -1
	_host.refresh_state_snapshot()
	_schedule_next_effect_resolution()


## 汇总全体投票并把当选机缘写入每名参与者的选择结果；平票时使用对局随机源在同票机缘中随机决出。
## 计票摘要写入随机历史，当选正文写入对局日志；死亡角色的历史与结算仍由通用存活检查过滤。
func _apply_vote_result() -> void:
	# 首名参与者的共享候选；投票模式下所有参与者候选完全一致，以此数组保持稳定计票顺序。
	var shared_options: Array = (_state.opportunity_state.get("options_by_player", {}) as Dictionary).get(str(int(_state.opportunity_state.get("trigger_player_id", -1))), []) as Array
	# 各候选得票数；键为机缘稳定ID，值为票数，仅统计实际提交的投票。
	var vote_counts: Dictionary = {}
	for voted_card_variant: Variant in _selected_cards_by_player.values():
		# 当前一票对应的机缘定义；死亡前已投出的票仍然有效。
		var voted_card_id: String = str((voted_card_variant as Dictionary).get("id", ""))
		if not voted_card_id.is_empty():
			vote_counts[voted_card_id] = int(vote_counts.get(voted_card_id, 0)) + 1
	if vote_counts.is_empty():
		return
	# 最高票数；先扫描一遍取得极值，再按候选稳定顺序收集全部同票机缘。
	var highest_vote_count: int = 0
	for vote_count_variant: Variant in vote_counts.values():
		highest_vote_count = maxi(highest_vote_count, int(vote_count_variant))
	# 与最高票并列的机缘ID；顺序沿用共享候选顺序，保证固定种子下平票随机可复现。
	var tied_card_ids: Array[String] = []
	for option_variant: Variant in shared_options:
		# 当前候选稳定ID；只有得票等于最高票的候选进入平票池。
		var option_card_id: String = str((option_variant as Dictionary).get("id", ""))
		if int(vote_counts.get(option_card_id, 0)) == highest_vote_count and not tied_card_ids.has(option_card_id):
			tied_card_ids.append(option_card_id)
	if tied_card_ids.is_empty():
		# 候选与投票意外脱节时回退首个得票机缘；该路径只服务损坏状态，不改变正常规则。
		tied_card_ids.append(str(vote_counts.keys()[0]))
	# 最终当选机缘ID；仅一项时直接采用，平票时使用对局共享随机源在同票机缘中等概率决出。
	var winner_card_id: String = tied_card_ids[0]
	if tied_card_ids.size() > 1 and _rng != null:
		winner_card_id = tied_card_ids[_rng.randi_range(0, tied_card_ids.size() - 1)]
	# 当选机缘完整定义；从静态目录重新读取，不信任投票过程中缓存的候选副本。
	var winner_card: Dictionary = OpportunityCatalog.get_card(winner_card_id)
	if winner_card.is_empty():
		return
	# 逐玩家公开票面；只在全部选票收齐后构建，选择阶段的普通观察者无法由本字段提前推断他人选择。
	var revealed_votes: Array[Dictionary] = []
	# 逐玩家投票ID映射；进入随机历史用于回放复核，键采用字符串兼容JSON网络序列化。
	var vote_card_ids_by_player: Dictionary = {}
	for participant_id_variant: Variant in _state.opportunity_state.get("participant_ids", []) as Array:
		# 当前投票参与者稳定ID；顺序沿用本次参与名单，所有客户端显示一致。
		var participant_id: int = int(participant_id_variant)
		# 当前玩家实际投出的机缘ID；从尚未覆盖为当选机缘的原始选择映射读取。
		var voted_card_id: String = str((_selected_cards_by_player.get(str(participant_id), {}) as Dictionary).get("id", ""))
		if voted_card_id.is_empty():
			continue
		revealed_votes.append({"player_id":participant_id, "card_id":voted_card_id})
		vote_card_ids_by_player[str(participant_id)] = voted_card_id
	_state.opportunity_state["revealed_votes"] = revealed_votes
	_state.opportunity_state["winner_card_id"] = winner_card_id
	_state.random_history.append({"kind":"opportunity_vote_result", "vote_counts":vote_counts.duplicate(), "vote_card_ids_by_player":vote_card_ids_by_player, "tied_card_ids":tied_card_ids.duplicate(), "winner_card_id":winner_card_id})
	_host.add_log("机缘投票结束：以%d票当选——%s" % [highest_vote_count, str(winner_card.get("description", ""))] + ("（平票随机决出）" if tied_card_ids.size() > 1 else ""))
	# 把当选机缘写入每名参与者的最终选择；随后的公开历史写入与逐人结算完全复用普通流程。
	for participant_id: int in _resolution_queue:
		_selected_cards_by_player[str(participant_id)] = winner_card.duplicate(true)


## 取得逆时针队列中的下一名角色并执行其已选机缘；全部完成后恢复触发前流程。
func _resolve_next_effect() -> void:
	if not is_active() or _state.game_over:
		return
	if _host.has_pending_card_choice():
		# 响应或无懈的最后一条续接可能先于控制器清空兼容请求字段恢复；按帧重试且同一时刻只保留一个回调。
		_schedule_next_effect_resolution()
		return
	while not _bonus_effect_queue.is_empty():
		# 追加机缘条目；只在取得它的角色仍存活时结算，离场存活角色继续享有机缘自用效果例外。
		var bonus_effect_entry: Dictionary = _bonus_effect_queue.pop_front()
		# 追加机缘持有者；稳定ID在入队时保存，结算前重新读取状态以防前一张追加卡导致死亡。
		var bonus_owner_player_id: int = int(bonus_effect_entry.get("owner_player_id", -1))
		var bonus_owner: PlayerState = _state.get_player(bonus_owner_player_id)
		if bonus_owner == null or not bonus_owner.alive:
			continue
		# 追加机缘静态定义；队列只接受目录深拷贝，空定义不会阻塞原始机缘结算队列。
		var bonus_card_definition: Dictionary = bonus_effect_entry.get("card_definition", {}) as Dictionary
		if bonus_card_definition.is_empty():
			continue
		_current_effect_owner_id = bonus_owner_player_id
		_current_effect_card = bonus_card_definition.duplicate(true)
		_current_effect_waiting_for_barrier = false
		_state.opportunity_state["current_resolver_id"] = bonus_owner_player_id
		_host.add_log("%s结算新获得的机缘：%s" % [_host.format_player_log_name(bonus_owner_player_id), str(bonus_card_definition.get("description", ""))])
		_effect_resolver.resolve_card(bonus_owner_player_id, bonus_card_definition)
		return
	while not _resolution_queue.is_empty():
		# 下一名结算角色；队列在触发时已经固定为当前角色起逆时针顺序。
		var owner_player_id: int = _resolution_queue.pop_front()
		# 结算时角色状态；死亡角色不再生效，存活离场角色仍可结算自己已经选择的模式机缘。
		var owner: PlayerState = _state.get_player(owner_player_id)
		if owner == null or not owner.alive:
			continue
		# 该角色选择的完整卡定义；未完成选择的异常角色直接跳过。
		var selected_card: Dictionary = _selected_cards_by_player.get(str(owner_player_id), {}) as Dictionary
		if selected_card.is_empty():
			continue
		_current_effect_owner_id = owner_player_id
		_current_effect_card = selected_card.duplicate(true)
		_current_effect_waiting_for_barrier = false
		_state.opportunity_state["current_resolver_id"] = owner_player_id
		_host.add_log("%s触发机缘：%s" % [_host.format_player_log_name(owner_player_id), str(selected_card.get("description", ""))])
		_effect_resolver.resolve_card(owner_player_id, selected_card)
		return
	_finish_flow()


## 清理当前效果并延迟推进下一名角色；延迟调用避免在伤害或选择回调栈中重入下一张机缘。
func _finish_current_effect_and_continue() -> void:
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_current_effect_waiting_for_barrier = false
	if not _state.opportunity_state.is_empty():
		_state.opportunity_state["current_resolver_id"] = -1
	_schedule_next_effect_resolution()


## 在下一帧尝试继续机缘效果；同一等待周期只连接一次SceneTree.process_frame。
func _schedule_next_effect_resolution() -> void:
	if _next_effect_retry_scheduled or not is_inside_tree():
		return
	_next_effect_retry_scheduled = true
	_connect_next_effect_retry_frame()


## 连接单次帧信号；从帧回调内部重试时延迟调用，等待上一条ONE_SHOT连接先自动解除。
func _connect_next_effect_retry_frame() -> void:
	if not _next_effect_retry_scheduled or not is_inside_tree():
		return
	if not get_tree().process_frame.is_connected(_on_next_effect_retry_frame):
		get_tree().process_frame.connect(_on_next_effect_retry_frame, Object.CONNECT_ONE_SHOT)


## process_frame恢复点；请求仍未清理时继续等待下一帧，否则进入唯一效果队列入口。
func _on_next_effect_retry_frame() -> void:
	if not _next_effect_retry_scheduled:
		return
	if not is_active() or _state.game_over:
		_next_effect_retry_scheduled = false
		return
	if _host.has_pending_card_choice():
		call_deferred("_connect_next_effect_retry_frame")
		return
	_next_effect_retry_scheduled = false
	_resolve_next_effect()


## 全部机缘结算完成后恢复原阶段，并通过控制器唯一入口续接回合开始或轮末流程。
func _finish_flow() -> void:
	# 恢复信息副本；先清空组件状态，续接阶段若立即触发新请求不会与旧机缘快照混淆。
	var resume_kind: String = _resume_kind
	# 可序列化恢复上下文；控制器会再次校验对局、阶段和当前玩家。
	var resume_context: Dictionary = _resume_context.duplicate(true)
	_state.current_phase = _resume_phase
	_state.opportunity_state.clear()
	_selection_queue.clear()
	_selected_cards_by_player.clear()
	_resolution_queue.clear()
	_bonus_effect_queue.clear()
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_current_effect_waiting_for_barrier = false
	_vote_mode = false
	_resume_kind = ""
	_resume_context.clear()
	_resume_phase = ""
	_host.refresh_state_snapshot()
	_host.continue_after_opportunity(resume_kind, resume_context)


## 终局或异常无参与者时只清理机缘状态，不尝试恢复已经失效的阶段游标。
func _finish_without_resume() -> void:
	if _selection_pause_token >= 0 and _host != null:
		_host.release_gameplay_pause(_selection_pause_token)
	_selection_pause_token = -1
	_selection_queue.clear()
	_selected_cards_by_player.clear()
	_resolution_queue.clear()
	_bonus_effect_queue.clear()
	_current_effect_owner_id = -1
	_current_effect_card.clear()
	_current_effect_waiting_for_barrier = false
	_vote_mode = false
	_resume_kind = ""
	_resume_context.clear()
	_resume_phase = ""
	if _state != null:
		_state.opportunity_state.clear()
	if _host != null:
		_host.refresh_state_snapshot()


## 初始化新轮相同触发概率；按本轮开始时在场角色数倒数计算，确保2至10人都保持期望约一次。
func _initialize_round_probability(round_number: int) -> void:
	_tracked_round_number = round_number
	_triggered_this_round = false
	# 本轮开始时在场角色数量；死亡与离场角色不获得回合开始触发机会。
	var active_player_count: int = 0
	for player: PlayerState in _state.players:
		if player != null and player.alive and not player.out_of_game:
			active_player_count += 1
	_round_trigger_probability = 1.0 / float(active_player_count) if active_player_count > 0 else 0.0


## 判断当前是否具备开始新机缘流程的基础条件；活动流程、终局或无状态时统一拒绝。
func _can_trigger_now() -> bool:
	return _enabled and _host != null and _state != null and not _state.game_over and _state.opportunity_state.is_empty() and _rng != null


## 从触发角色开始沿座次数组逆时针返回全部存活角色；离场角色仍参与机缘，每名角色只出现一次。
func _build_counterclockwise_order(trigger_player_id: int) -> Array[int]:
	# 逆时针顺序结果；触发角色有效时固定放在首位。
	var result: Array[int] = []
	# 起始角色；无效时优先回退当前回合角色，再回退首名存活角色。
	var start_player: PlayerState = _state.get_player(trigger_player_id)
	if start_player == null or not start_player.alive:
		start_player = _state.get_player(_state.current_player_id)
	if start_player == null or not start_player.alive:
		for player: PlayerState in _state.players:
			if player != null and player.alive:
				start_player = player
				break
	if start_player == null:
		return result
	# 起始座次索引；机缘逆时针顺序按完整座次数组移动，只跳过死亡角色而保留离场角色。
	var start_index: int = _state.players.find(start_player)
	if start_index < 0:
		return result
	for step: int in range(_state.players.size()):
		# 当前逆时针座次；从起点向数组前方环回，确保交换座位后立即使用新顺序。
		var seat_index: int = posmod(start_index - step, _state.players.size())
		# 当前座次角色；离场但存活者仍加入，死亡角色跳过。
		var participant: PlayerState = _state.players[seat_index]
		if participant != null and participant.alive:
			result.append(participant.player_id)
	return result


## 为一名角色抽取互不重复的机缘候选；每张先按品质权重抽品质，再在该品质卡池内等概率抽牌。
func _draw_options_for_player(_player_id: int) -> Array[Dictionary]:
	# 本次候选结果；数量不会超过目录内不同卡牌总数。
	var result: Array[Dictionary] = []
	# 已抽取卡牌ID；同一名角色的三张候选不能重复，其他角色之间允许出现相同机缘。
	var excluded_card_ids: Array[String] = []
	for _option_index: int in range(cards_per_choice):
		# 单张抽取结果；卡池异常耗尽时停止，避免加入空卡占位。
		var card_definition: Dictionary = _draw_single_card(excluded_card_ids)
		if card_definition.is_empty():
			break
		result.append(card_definition)
		excluded_card_ids.append(str(card_definition.get("id", "")))
	return result


## 按当前检查器权重抽取一张未被排除的机缘卡；无可用正权重卡池时回退全部剩余卡等概率抽取。
func _draw_single_card(excluded_card_ids: Array[String]) -> Dictionary:
	# 可参与抽取的品质到剩余稳定ID池映射；只处理短字符串，选中后才复制一份完整卡牌定义。
	var available_card_ids_by_quality: Dictionary = {}
	# 当前有效总权重；只累加仍有候选且配置为正数的品质。
	var total_weight: int = 0
	for quality_id: String in OpportunityCatalog.QUALITY_ORDER:
		# 当前品质剩余ID池；过滤同一角色已经抽到的稳定ID，其他角色仍可独立抽到相同机缘。
		var available_card_ids: Array[String] = []
		for card_id_variant: Variant in _random_card_ids_by_quality.get(quality_id, []) as Array:
			# 当前候选稳定ID；空ID与本角色已经抽到的ID都不进入可用池。
			var card_id: String = str(card_id_variant)
			if not card_id.is_empty() and not excluded_card_ids.has(card_id):
				available_card_ids.append(card_id)
		available_card_ids_by_quality[quality_id] = available_card_ids
		if not available_card_ids.is_empty():
			total_weight += maxi(_get_quality_weight(quality_id), 0)
	if total_weight > 0:
		# 品质权重随机点；范围1至总权重，逐品质扣减保证边界值不会偏向前一品质。
		var quality_roll: int = _rng.randi_range(1, total_weight)
		for quality_id: String in OpportunityCatalog.QUALITY_ORDER:
			# 当前品质剩余ID池；空池或零权重直接跳过。
			var quality_card_ids: Array = available_card_ids_by_quality.get(quality_id, []) as Array
			# 当前品质非负权重；负数检查器异常值按0处理。
			var quality_weight: int = maxi(_get_quality_weight(quality_id), 0)
			if quality_card_ids.is_empty() or quality_weight <= 0:
				continue
			quality_roll -= quality_weight
			if quality_roll <= 0:
				# 选中的稳定ID；到此才通过目录索引复制唯一一份完整定义写入权威候选。
				var selected_card_id: String = str(quality_card_ids[_rng.randi_range(0, quality_card_ids.size() - 1)])
				return OpportunityCatalog.get_card(selected_card_id)
	# 回退卡池；所有权重为0时仍允许组件工作，便于检查器调试而不产生空弹窗。
	var fallback_card_ids: Array[String] = []
	for quality_id: String in OpportunityCatalog.QUALITY_ORDER:
		for card_id_variant: Variant in available_card_ids_by_quality.get(quality_id, []) as Array:
			fallback_card_ids.append(str(card_id_variant))
	if fallback_card_ids.is_empty():
		return {}
	return OpportunityCatalog.get_card(fallback_card_ids[_rng.randi_range(0, fallback_card_ids.size() - 1)])


## 返回指定随机品质当前配置权重；抽取热路径直接读取导出变量，避免为每张候选重复构造权重字典。
func _get_quality_weight(quality_id: String) -> int:
	match quality_id:
		"green":
			return green_weight
		"blue":
			return blue_weight
		"purple":
			return purple_weight
		"orange":
			return orange_weight
		"red":
			return red_weight
	return 0


## 为AI从三张机缘中选择综合收益最高的一张；品质基础价值再结合当前体力、手牌和已有技能修正。
func _choose_ai_card(player_id: int, options: Array) -> Dictionary:
	# 当前最高分；负无穷确保首张合法卡可以成为稳定基准。
	var best_score: float = -INF
	# 当前最佳卡；平分保持候选生成顺序，固定种子下结果可复现。
	var best_card: Dictionary = {}
	for option_variant: Variant in options:
		# 当前候选卡；只读取静态参数并交给纯估值函数。
		var card_definition: Dictionary = option_variant as Dictionary
		# 当前候选综合分；高品质通常更强，但无可执行目标或重复技能会降低实际收益。
		var score: float = _score_ai_card(player_id, card_definition)
		if score > best_score:
			best_score = score
			best_card = card_definition.duplicate(true)
	return best_card


## 计算单张机缘对指定AI角色的基础收益；不修改状态、不预抽牌，也不读取其他角色私有候选。
func _score_ai_card(player_id: int, card_definition: Dictionary) -> float:
	# 品质基础价值；体现高品质卡的整体强度，同时允许具体效果按局势覆盖选择。
	var score: float = float({"gray":0, "green":2, "blue":5, "purple":9, "orange":14, "red":22}.get(str(card_definition.get("quality", "green")), 0))
	# 当前AI角色；不存在时只返回品质基础分。
	var player: PlayerState = _state.get_player(player_id)
	if player == null:
		return score
	# 当前效果稳定ID；针对资源、体力与重复技能做局势修正。
	var effect_id: String = str(card_definition.get("effect", ""))
	if effect_id == "draw":
		score += float(int(card_definition.get("count", 0))) * 1.5
	elif effect_id in ["recover", "recover_full"]:
		score += float(maxi(player.max_hp - player.hp, 0)) * 3.0
	elif effect_id in ["max_hp", "double_max_hp"]:
		score += float(player.max_hp) * (1.0 if effect_id == "double_max_hp" else 0.5)
	elif effect_id == "hand_limit":
		score += float(int(card_definition.get("count", 0))) * 2.0
	elif effect_id == "draw_phase_bonus":
		# 每回合稳定额外摸牌；长期收益高于一次性摸牌，但不读取未公开牌堆内容。
		score += float(int(card_definition.get("count", 0))) * 5.0
	elif effect_id == "slash_play_limit_bonus":
		# 次数上限只在拥有可用【杀】或后续摸牌时转化为收益，基础分保持保守避免无脑选择。
		score += float(int(card_definition.get("count", 0))) * (3.0 if not player.hand.is_empty() else 1.0)
	elif effect_id == "damage_bonus":
		# 伤害加成对后续每次正数伤害生效；基础AI仅按在场敌对角色数估算可实现次数。
		# 当前可受伤的敌对角色数量；最多按三名估算，避免多人局将长期加成无限放大。
		var damage_bonus_hostile_count: int = 0
		for target: PlayerState in _state.players:
			if target != null and target.alive and not target.out_of_game and target.player_id != player_id and not _host.is_friendly(player_id, target.player_id):
				damage_bonus_hostile_count += 1
		score += float(int(card_definition.get("count", 0)) * mini(damage_bonus_hostile_count, 3)) * 2.0
	elif effect_id == "grant_skill":
		# 重复技能不会创建第二个实例，因此AI显著降低已拥有技能卡的价值。
		var skill_id: String = str(card_definition.get("skill_id", ""))
		var owned_skills: Dictionary = _host.skill_instances_by_player.get(player_id, {}) as Dictionary
		score += -12.0 if owned_skills.has(skill_id) else 6.0
	elif effect_id in ["discard_two_from_player", "damage_target", "gain_one_from_player", "max_hp_target", "lose_hp_target", "discard_all_hand_target", "damage_targets", "gain_all_hand_target", "discard_one_each_target", "discard_half_all_cards_target", "lose_half_hp_target", "remove_until_round_end_target", "reduce_half_max_hp_target", "damage_current_hp_target"]:
		# 敌对角色数量；存在敌人才为负面机缘提供正收益，没有敌人时降低误伤风险。
		var hostile_count: int = 0
		for target: PlayerState in _state.players:
			if target != null and target.alive and not target.out_of_game and target.player_id != player_id and not _host.is_friendly(player_id, target.player_id):
				hostile_count += 1
		score += 5.0 if hostile_count > 0 else -8.0
	elif effect_id in ["swap_hand_targets", "swap_equipment_targets", "swap_character_targets"]:
		# 交换类效果至少需要一名敌方和一名友方才能稳定转化为己方收益。
		var has_hostile: bool = false
		var has_friendly: bool = false
		for target: PlayerState in _state.players:
			if target == null or not target.alive or target.out_of_game:
				continue
			if _host.is_friendly(player_id, target.player_id):
				has_friendly = true
			else:
				has_hostile = true
		score += 7.0 if has_hostile and has_friendly else -6.0
	elif effect_id == "virtual_card_use":
		# 群体伤害锦囊在敌方数量多于友方时更有价值；最终无懈、响应和防具仍由卡牌AI与规则层处理。
		var virtual_hostile_count: int = 0
		var virtual_friendly_count: int = 0
		for target: PlayerState in _state.players:
			if target == null or not target.alive or target.out_of_game or target.player_id == player_id:
				continue
			if _host.is_friendly(player_id, target.player_id):
				virtual_friendly_count += 1
			else:
				virtual_hostile_count += 1
		score += float(virtual_hostile_count - virtual_friendly_count) * 2.5
	elif effect_id == "discard_own_zone_and_draw":
		score += float(player.judgment_area.size()) * 3.0
	elif effect_id == "gain_distinct_delayed":
		score += 6.0
	elif effect_id == "view_all_hand_as":
		score += float(player.hand.size()) * 2.0
	elif effect_id == "gain_all_equipment":
		score += float(_host.get_all_global_equipment_card_uids().size()) * 1.5
	elif effect_id == "gain_random_zone_cards_each":
		score += float(_state.players.size()) * float(int(card_definition.get("count", 0)))
	elif effect_id == "extra_turns":
		score += float(int(card_definition.get("count", 0))) * 8.0
	return score


## 组件退出场景树时归还仍持有的暂停令牌，避免切换场景后SceneTree永久停留在暂停状态。
func _exit_tree() -> void:
	shutdown()
