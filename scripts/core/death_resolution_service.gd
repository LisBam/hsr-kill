class_name DeathResolutionService
extends RefCounted

## 死亡内容组件；前置修改、事实提交、区域清理、奖惩和尾部各自拥有可暂停步骤。

## “摸四张牌”类击杀奖惩的稳定类型字符串；技能改写击杀奖惩时返回该值，死亡结算据此执行摸牌。
const KILL_REWARD_DRAW_FOUR_TYPE: String = "draw_four"

## “摸四张牌”类击杀奖惩的固定摸牌数；数值4来自内容原文，修改会同时改变所有声明该奖惩类型的技能强度。
const KILL_REWARD_DRAW_FOUR_COUNT: int = 4

## 权威控制器；只在当前对局持有，不把节点引用写进玩法上下文。
var _host: Object


## 绑定规则端口；调度、选择和技能排序继续由统一运行时负责。
func _init(host: Object) -> void:
	_host = host


## 建立一次死亡内容；原武将代次防止选择期间换将后杀死新武将。
func begin(victim_id: int, killer_id: int) -> void:
	# 当前死亡候选；无效或已经死亡的对象不重复提交统计。
	var victim: PlayerState = _host.state.get_player(victim_id)
	if victim == null or not victim.alive:
		return
	if _host.state.current_player_id == victim_id:
		_host._cancel_active_play_choice("death_resolution")
	# 同一武将已有死亡序列时复用其所有权，避免dieBefore中的嵌套效果重复登记。
	for active_sequence: RuleStepSequence in _host._rule_sequences.values():
		if str(active_sequence.context.get("sequence_kind", "")) == "death" and int(active_sequence.context.get("victim_id", -1)) == victim_id and int(active_sequence.context.get("generation", -1)) == victim.character_generation:
			return
	# 死亡内容身份；模式和事实字段在对应提交步骤补充。
	var context: Dictionary = {"sequence_kind":"death", "victim_id":victim_id, "killer_id":killer_id, "generation":victim.character_generation, "event_data":{"hp":victim.hp}}
	# 每个前置时机都先等完全部子内容，再读取取消和最终数据。
	var steps: Array[Callable] = [_restore, _before.bind("dieBefore"), _before.bind("dieBegin"), _commit, _after_die, _clear_regions, _mode_effect, _end.bind("dieEnd"), _end.bind("dieAfter"), _cleanup]
	_host.run_rule_sequence(steps, context)


## 离场死亡先返场；返场时机完成后才进入死亡前置。
func _restore(sequence: RuleStepSequence) -> void:
	# 当前死亡候选；返场只对仍处于原代次的对象执行。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim != null and victim.out_of_game:
		_host.restore_player_to_game(victim.player_id, "death_before_resolution")


## 校验原武将和上一窗口最终结果；取消要求内容自行修正体力，沿用现有规则。
func _accept_previous(sequence: RuleStepSequence) -> bool:
	# 当前角色；不沿用等待前的PlayerState引用。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim == null or not victim.alive or victim.character_generation != int(sequence.context.generation):
		sequence.finish()
		return false
	if sequence.waiting_event != null:
		sequence.context.event_data = sequence.waiting_event.data.duplicate(true)
		if sequence.waiting_event.cancelled or sequence.waiting_event.neutralized:
			victim.dying = false
			_host.state.dying_queue.erase(victim.player_id)
			sequence.finish()
			return false
		sequence.waiting_event = null
	return true


## 派发一个可修改的死亡前置窗口；下一步读取同一RuleEvent的最终结果。
func _before(sequence: RuleStepSequence, timing_name: String) -> void:
	if _accept_previous(sequence):
		_emit(sequence, timing_name)


## 唯一死亡事实提交点；模式选择不含异步回调，统计和资源只提交一次。
func _commit(sequence: RuleStepSequence) -> void:
	if not _accept_previous(sequence):
		return
	# 当前候选；前置条件已确认，以下操作形成一次原子事实。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	# 原击杀来源；无来源伤害使用-1。
	var killer_id: int = int(sequence.context.killer_id)
	sequence.context["death_event_id"] = _host._record_runtime_event("die", "death", {"victim_id":victim.player_id, "killer_id":killer_id})
	_host.state.dying_queue.erase(victim.player_id)
	sequence.context["mode"] = "normal"
	sequence.context["defeated_character_name"] = GameDatabase.resolve_character_name(victim.character_id)
	sequence.context.event_data = {"hp":victim.hp, "death_event_id":sequence.context.death_event_id, "player_character_generation":victim.character_generation, "target_character_generation":victim.character_generation}
	if _host.identity_rules.normalize_mode(str(_host.state.match_mode)) == IdentityRules.MODE_CONQUEST and _host.conquest_mode != null:
		if _host.conquest_mode.can_revive_player(victim.player_id) and _host.conquest_mode.consume_player_revive(victim.player_id):
			sequence.context.mode = "revival"
			sequence.context.event_data["conquest_revival"] = true
			sequence.context.event_data["remaining_revives"] = _host.conquest_mode.get_player_revives_remaining(victim.player_id)
		elif _host.conquest_mode.is_enemy(victim.player_id):
			sequence.context.mode = "enemy"
			sequence.context.event_data["conquest_enemy_defeat"] = true
	elif _host.identity_rules.normalize_mode(str(_host.state.match_mode)) == IdentityRules.MODE_WHEEL_DUEL:
		victim.wheel_duel_defeated_count += 1
		if victim.wheel_duel_defeated_count < WheelDuelSelectionService.LINEUP_CHARACTER_COUNT_PER_PLAYER:
			sequence.context.mode = "wheel"
			sequence.context.event_data["wheel_duel_replacement"] = true
	if str(sequence.context.mode) not in ["wheel", "enemy"]:
		victim.alive = false
		victim.dying = false
		victim.death_confirmed = true
		victim.identity_revealed = true
	if str(sequence.context.mode) != "revival":
		_host._record_match_kill(killer_id, victim.player_id)
		# 音频表现：死亡事实成立时请求一次武将阵亡语音。
		# 触发点放在事实提交之后、die时机派发之前：被前置窗口取消的死亡不会走到这里，因此不会误播；
		# 复活模式并未真正阵亡（角色返场并回满体力），因此同样不发声。
		# 武将ID使用死亡时的原武将，保证模式换将后仍为阵亡者本人的音色。
		_host.request_die_voice(victim.player_id, victim.character_id)
	_emit(sequence, "die")


## die全部子内容结束后再判断终局；终局沿用立即结束、不执行奖惩的规则。
func _after_die(sequence: RuleStepSequence) -> void:
	# 当前阵亡角色；后置步骤始终重取对象。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim == null or victim.character_generation != int(sequence.context.generation):
		sequence.finish()
		return
	match str(sequence.context.mode):
		"normal":
			_host.add_log("%s死亡，身份为%s。" % [_host.format_player_state_log_name(victim), _host._identity_text(victim.identity)])
			_host._check_game_over()
			if _host.state.game_over:
				# 终局通知只报告事实；玩法已经停止，不再建立可回复的交互。
				sequence.context.event_data["game_over"] = true
				_host._record_runtime_event("dieAfter", "death", {"victim_id":victim.player_id, "game_over":true}, {}, int(sequence.context.death_event_id))
				_host.emit_rule_timing("dieEnd", victim.player_id, int(sequence.context.killer_id), victim.player_id, sequence.context.event_data, int(sequence.context.death_event_id))
				_host.emit_rule_timing("dieAfter", victim.player_id, int(sequence.context.killer_id), victim.player_id, sequence.context.event_data, int(sequence.context.death_event_id))
				if _host.player_mark_service != null:
					_host.player_mark_service.clear_marks_for_dead_player(victim.player_id)
				sequence.finish()
		"revival":
			_host.add_log("%s死亡并触发复活，剩余复活次数%d。" % [_host.format_player_state_log_name(victim), int(sequence.context.event_data.remaining_revives)])
		"wheel":
			_host.add_log("%s的武将【%s】阵亡。" % [victim.display_name, str(sequence.context.defeated_character_name)])
		"enemy":
			_host.add_log("%s击败敌方武将【%s】。" % [_host.format_player_log_name(int(sequence.context.killer_id)), str(sequence.context.defeated_character_name)])
			victim.alive = false
			victim.dying = false
			victim.death_confirmed = true
			victim.identity_revealed = true


## 区域清理在die结束后执行；每个持有区域复用权威卡牌移动入口。
func _clear_regions(sequence: RuleStepSequence) -> void:
	# 当前待清理角色；清理对象只能是本次阵亡实例。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim == null or victim.character_generation != int(sequence.context.generation):
		sequence.finish()
		return
	if str(sequence.context.mode) in ["revival", "enemy"]:
		_host._discard_all_conquest_player_cards(victim)
	else:
		# 区域清理快照；先建立步骤再逐张移动，避免异步选择期间重复弹出牌。
		var steps: Array[Callable] = []
		for card: CardInstance in victim.hand.duplicate():
			steps.append(_discard_card.bind(card.uid))
		steps.append(_discard_equipment)
		for card: CardInstance in victim.judgment_area.duplicate():
			steps.append(_discard_card.bind(card.uid))
		sequence.insert_steps(steps)


## 一张牌只移动一次；按UID重找原区域，之前已被技能移走的牌不再处理。
func _discard_card(sequence: RuleStepSequence, card_uid: int) -> void:
	# 当前阵亡角色；等待期间可能发生模式换将。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim == null or victim.character_generation != int(sequence.context.generation):
		return
	for card: CardInstance in victim.hand + victim.judgment_area:
		if card.uid == card_uid:
			_move_to_discard_sequence(sequence, card, "death")
			return


## 装备清理复用现有卸载契约，死亡清理不触发失去防具回复。
func _discard_equipment(sequence: RuleStepSequence) -> void:
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim == null:
		return
	var steps: Array[Callable] = []
	for slot_variant: Variant in victim.equipment.keys():
		steps.append(Callable(self, "_discard_death_equipment_slot").bind(victim.player_id, str(slot_variant)))
	sequence.insert_steps(steps)


## 装备离区效果先卸载，再由步骤移牌服务等待完整弃牌时机。
func _discard_death_equipment_slot(sequence: RuleStepSequence, player_id: int, slot: String) -> void:
	var player: PlayerState = _host.state.get_player(player_id)
	if player == null or not player.equipment.has(slot):
		return
	var card: CardInstance = player.equipment[slot] as CardInstance
	_host._on_equipment_lost(player, card, false)
	_move_to_discard_sequence(sequence, card, "death_equipment")


## 将弃牌的全部生命周期挂在当前死亡父序列下，避免同步入口跨过异步选择。
func _move_to_discard_sequence(sequence: RuleStepSequence, card: CardInstance, reason: String) -> void:
	if card == null:
		return
	var source_zone: String = card.zone
	var source_player_id: int = card.owner_id
	var discard_event_id: int = _host._record_runtime_event("cardsDiscard", "card_move", {"card_uids":[card.uid], "from_zone":source_zone, "reason":reason}, {}, _host._current_rule_parent_event_id())
	var movement: CardMoveResolutionService = CardMoveResolutionService.new(_host)
	movement.begin(sequence, card.uid, "discard_pile", -1, reason, discard_event_id)


## 模式副作用独立于时机派发；其中产生的摸牌等子流程先于死亡尾部。
func _mode_effect(sequence: RuleStepSequence) -> void:
	# 当前角色；本步骤的换将会显式更新允许的代次。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim == null or victim.character_generation != int(sequence.context.generation):
		sequence.finish()
		return
	# 奖惩来源；保持原身份规则定义。
	var killer_id: int = int(sequence.context.killer_id)
	match str(sequence.context.mode):
		"normal":
			# 击杀者状态；无来源伤害或击杀者已不存在时不执行奖惩。
			var killer: PlayerState = _host.state.get_player(killer_id)
			# 本次击杀的最终奖惩类型；身份规则给出基础结论，击杀者技能仍可通过统一端口整体覆盖。
			var reward: String = _host.resolve_death_reward(killer_id, victim.player_id, str(_host.state.match_mode))
			if reward == "teammate_draw":
				# 2v2：队友死亡后（不论击杀者），存活队友各摸一张；击杀队友无额外惩罚。
				for ally: PlayerState in _host.state.players:
					if ally == null or not ally.alive or ally.out_of_game:
						continue
					if ally.player_id == victim.player_id:
						continue
					if _host.identity_rules.are_teammates(ally, victim, str(_host.state.match_mode)):
						_host.draw(ally.player_id, 1)
						_host.add_log("%s因队友阵亡摸了1张牌。" % ally.display_name)
			elif reward == "draw_three" and killer != null and killer.alive:
				_host.draw(killer.player_id, 3)
			elif reward == KILL_REWARD_DRAW_FOUR_TYPE and killer != null and killer.alive:
				# 技能改写后的四张牌奖惩；固定摸4张，不叠加身份规则原有的三张或弃置全部牌。
				_host.draw(killer.player_id, KILL_REWARD_DRAW_FOUR_COUNT)
			elif reward == "leader_penalty" and killer != null and killer.alive:
				while not killer.hand.is_empty():
					_host._move_to_discard(killer.hand.pop_back())
				_host.discard_all_equipment(killer.player_id, true)
				_host.add_log("领袖杀死忠臣，弃置全部手牌和装备。")
		"revival":
			victim.hp = victim.max_hp
			victim.alive = true
			victim.dying = false
			victim.death_confirmed = false
			_host.draw(victim.player_id, ConquestModeService.REVIVAL_DRAW_COUNT)
			_host.add_log("%s体力回复至%d并摸%d张牌，继续游戏。" % [_host.format_player_state_log_name(victim), victim.max_hp, ConquestModeService.REVIVAL_DRAW_COUNT])
		"wheel":
			victim.wheel_duel_lineup_index += 1
			# 下一名出场武将ID；阵容固定3名且索引已由阵亡数量保护，不会越界。
			var next_character_id: String = victim.wheel_duel_lineup[victim.wheel_duel_lineup_index]
			_host._apply_character(victim, next_character_id, true)
			_host._reinstall_character_skills_for_player(victim)
			victim.hp = victim.max_hp
			victim.shield = 0
			victim.dying = false
			victim.death_confirmed = false
			victim.chained = false
			victim.face_down = false
			victim.skipped_phases.clear()
			victim.slash_count = 0
			victim.wine_used = false
			victim.wine_bonus = 0
			victim.wooden_ox_used = false
			_host.draw(victim.player_id, 4)
			_host.add_log("%s亮出下一名武将【%s】，体力补至%d并摸4张牌。" % [victim.display_name, GameDatabase.resolve_character_name(next_character_id), victim.max_hp])
			sequence.context.event_data["next_character_id"] = next_character_id
		"enemy":
			# 清层事实仅在敌方全部死亡后成立，尾部与后续模式迁移共享这一快照。
			var level_cleared: bool = _host.conquest_mode.is_current_level_cleared()
			sequence.context.event_data["conquest_level_cleared"] = level_cleared
			sequence.context.event_data["conquest_replacement"] = level_cleared
	sequence.context.event_data["game_over"] = false


## 非终局死亡的End与After均可交互；事实记录只在End开始时写入一次。
func _end(sequence: RuleStepSequence, timing_name: String) -> void:
	if timing_name == "dieEnd":
		_host._record_runtime_event("dieAfter", "death", {"victim_id":sequence.context.victim_id, "game_over":false}, sequence.context.event_data, int(sequence.context.death_event_id))
	_emit(sequence, timing_name)


## 全部尾部结束后清理标记并安排模式或回合后续；伤害父内容自行恢复，无专用尾部映射。
func _cleanup(sequence: RuleStepSequence) -> void:
	# 当前角色；模式换将允许新代次存在，后续仅使用旧代次中断旧回合。
	var victim: PlayerState = _host.state.get_player(int(sequence.context.victim_id))
	if victim == null:
		return
	if _host.player_mark_service != null:
		_host.player_mark_service.clear_marks_for_dead_player(victim.player_id)
	match str(sequence.context.mode):
		"normal":
			if _host.state.current_player_id == victim.player_id:
				_host.defer_after_settlement("current_player_death", {"player_id":victim.player_id, "generation":int(sequence.context.generation), "turn_number":_host.state.turn_number})
		"wheel":
			if _host.state.current_player_id == victim.player_id:
				_host.state.current_phase = "wheel_duel_replacing"
				_host.state.phase_index = -1
				_host.defer_after_settlement("current_player_death", {"player_id":victim.player_id, "generation":int(sequence.context.generation), "turn_number":_host.state.turn_number})
			else:
				_host._emit_state()
		"revival":
			_host._emit_state()
		"enemy":
			# 模式转场保留原低优先级续接；全部父牌和伤害事实结束后才能创建下一层。
			var level_cleared: bool = bool(sequence.context.event_data.get("conquest_level_cleared", false))
			var defeat_context: Dictionary = {"defeated_enemy_id":victim.player_id, "defeated_character_generation":int(sequence.context.generation), "current_player_id":_host.state.current_player_id, "level_cleared":level_cleared}
			if level_cleared:
				defeat_context["defeated_enemy_ids"] = _host.conquest_mode.get_enemy_ids()
				_host.add_log("本层全部敌方均已阵亡，完成第%d关。" % _host.conquest_mode.get_level())
				_host.defer_after_settlement("conquest_enemy_replacement", defeat_context)
			else:
				_host.add_log("本层仍有%d名敌方存活，关卡继续。" % _host._get_alive_conquest_enemy_ids().size())
				_host.defer_after_settlement("conquest_enemy_defeat", defeat_context)


## 死亡时机共享父事件与原武将代次；同一窗口派发完成后才进入下个步骤。
func _emit(sequence: RuleStepSequence, timing_name: String) -> void:
	_host.emit_sequence_timing(sequence, timing_name, int(sequence.context.victim_id), int(sequence.context.killer_id), int(sequence.context.victim_id), sequence.context.event_data, int(sequence.context.get("death_event_id", -2)))
