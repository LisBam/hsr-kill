class_name ReincarnationSkillService
extends RefCounted

## 轮回技权威状态服务。组件只维护轮回数、轮回节、永劫与通用限次，并通过控制器公开端口派发规则时机。

## 当前绑定的对局控制器；服务只调用稳定规则端口，不直接持有界面节点或技能运行时实例。
var _host: Object


## 绑定当前对局控制器；每局创建新状态后重新配置，旧局状态不会泄漏到新局。
func configure(match_host: Object) -> void:
	_host = match_host


## 为一个声明为轮回技的技能建立公开权威状态；重复注册只同步静态配置，不覆盖已有进度。
func register_skill(player_id: int, skill_id: String, metadata: Dictionary) -> bool:
	if _host == null or _host.get("state") == null or skill_id.is_empty() or not bool(metadata.get("reincarnation", false)):
		return false
	# 技能持有者；无效玩家不能创建孤立的轮回状态。
	var player: PlayerState = _host.state.get_player(player_id) as PlayerState
	if player == null:
		return false
	# 轮回节总数；没有①②等显式轮回节的轮回技按一个轮回节处理。
	var section_count: int = maxi(int(metadata.get("reincarnation_section_count", 1)), 1)
	# 已有轮回状态；重新安装技能时必须保留局内轮回进度。
	var skill_state: Dictionary = player.reincarnation_skills.get(skill_id, {}) as Dictionary
	if skill_state.is_empty():
		skill_state = {
			"round_count":1,
			"section_index":0,
			"section_count":section_count,
			"explicit_sections":bool(metadata.get("reincarnation_has_explicit_sections", section_count > 1)),
			"section_started":false,
			"eternal":false,
			"eternal_per_turn_limit":0,
			"eternal_turn_number":-1,
			"eternal_uses_this_turn":0,
			"each_section_once_per_play_phase":bool(metadata.get("reincarnation_each_section_once_per_play_phase", false)),
			"used_sections_this_play_phase":[],
		}
	else:
		skill_state["section_count"] = section_count
		skill_state["section_index"] = clampi(int(skill_state.get("section_index", 0)), 0, section_count - 1)
		skill_state["explicit_sections"] = bool(metadata.get("reincarnation_has_explicit_sections", section_count > 1))
		skill_state["each_section_once_per_play_phase"] = bool(metadata.get("reincarnation_each_section_once_per_play_phase", false))
	player.reincarnation_skills[skill_id] = skill_state
	return true


## 彻底移除指定技能的轮回权威状态；技能被卸载时调用，使该技能下次安装重新从①与轮回数1开始。
## 与 reset_skill 的区别：本入口删除登记，之后 register_skill 会建立全新初始状态，不会保留任何旧进度。
func clear_skill_state(player_id: int, skill_id: String) -> bool:
	# 技能持有者；无效玩家没有可清理的轮回登记。
	var player: PlayerState = _get_player(player_id)
	if player == null or not player.reincarnation_skills.has(skill_id):
		return false
	player.reincarnation_skills.erase(skill_id)
	_notify_state_changed()
	return true


## 返回指定技能的轮回公开状态深拷贝；空字典表示技能没有登记为轮回技。
func get_skill_state(player_id: int, skill_id: String) -> Dictionary:
	# 技能持有者；查询失败时使用空字典，调用方无需判空玩家对象。
	var player: PlayerState = _get_player(player_id)
	if player == null:
		return {}
	return (player.reincarnation_skills.get(skill_id, {}) as Dictionary).duplicate(true)


## 返回当前轮回数；轮回技尚未登记时按初始值1处理，便于技能公式安全回退。
func get_round_count(player_id: int, skill_id: String) -> int:
	return maxi(int(get_skill_state(player_id, skill_id).get("round_count", 1)), 1)


## 返回当前轮回节的零基索引；未登记时回退①对应的0。
func get_section_index(player_id: int, skill_id: String) -> int:
	return maxi(int(get_skill_state(player_id, skill_id).get("section_index", 0)), 0)


## 检查轮回技是否满足永劫每回合限次与“每个轮回节每出牌阶段限一次”约束。
func can_activate(player_id: int, skill_id: String) -> bool:
	# 技能轮回状态；未登记技能不通过本机制开放发动权限。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	if skill_state.is_empty():
		return false
	_sync_eternal_turn_counter(skill_state)
	# 永劫每回合上限；0表示永劫状态没有附加发动次数限制。
	var eternal_limit: int = maxi(int(skill_state.get("eternal_per_turn_limit", 0)), 0)
	if bool(skill_state.get("eternal", false)) and eternal_limit > 0 and int(skill_state.get("eternal_uses_this_turn", 0)) >= eternal_limit:
		return false
	if bool(skill_state.get("each_section_once_per_play_phase", false)) and _is_owner_play_phase(player_id):
		# 本出牌阶段已经发动过的轮回节索引；不同轮回节分别拥有一次额度。
		var used_sections: Array = skill_state.get("used_sections_this_play_phase", []) as Array
		if used_sections.has(int(skill_state.get("section_index", 0))):
			return false
	_store_skill_state(player_id, skill_id, skill_state)
	return true


## 标记一次轮回技效果开始；首次进入初始轮回节时补发轮回与轮回节开始时机。
func begin_activation(player_id: int, skill_id: String) -> bool:
	if not can_activate(player_id, skill_id):
		return false
	# 当前轮回状态；can_activate 已完成缺失与限次校验。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	_ensure_current_section_started(player_id, skill_id, skill_state)
	_store_skill_state(player_id, skill_id, skill_state)
	return true


## 完成一次轮回技发动并自动进入下一轮回节；最后一节或永劫状态会直接进入下一轮回。
func complete_activation(player_id: int, skill_id: String) -> bool:
	# 当前轮回状态；未调用注册或状态已被移除时不产生虚假推进。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	if skill_state.is_empty():
		return false
	_consume_activation_limits(player_id, skill_state)
	_finish_current_section_and_advance(player_id, skill_id, skill_state, false)
	_store_skill_state(player_id, skill_id, skill_state)
	_notify_state_changed()
	return true


## 令技能直接进入下一个轮回节；永劫状态下保持当前轮回节并进入下一轮回。
func enter_next_section(player_id: int, skill_id: String) -> bool:
	# 当前轮回状态；外部推进只能作用于已经登记的轮回技。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	if skill_state.is_empty():
		return false
	_ensure_current_section_started(player_id, skill_id, skill_state)
	_finish_current_section_and_advance(player_id, skill_id, skill_state, false)
	_store_skill_state(player_id, skill_id, skill_state)
	_notify_state_changed()
	return true


## 令技能直接进入下一个轮回；普通状态回到①，永劫状态则继续锁定当前轮回节。
func enter_next_round(player_id: int, skill_id: String) -> bool:
	# 当前轮回状态；不存在时不创建隐式技能状态。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	if skill_state.is_empty():
		return false
	_ensure_current_section_started(player_id, skill_id, skill_state)
	_emit_lifecycle("reincarnationSectionEnd", player_id, skill_id, skill_state)
	_emit_lifecycle("reincarnationEnd", player_id, skill_id, skill_state)
	skill_state["round_count"] = maxi(int(skill_state.get("round_count", 1)), 1) + 1
	if not bool(skill_state.get("eternal", false)):
		skill_state["section_index"] = 0
	_emit_lifecycle("reincarnationStart", player_id, skill_id, skill_state)
	_emit_lifecycle("reincarnationSectionStart", player_id, skill_id, skill_state)
	skill_state["section_started"] = true
	_store_skill_state(player_id, skill_id, skill_state)
	_notify_state_changed()
	return true


## 重置轮回数为1并回到①；clear_eternal为true时同时清除永劫及其每回合额度。
func reset_skill(player_id: int, skill_id: String, clear_eternal: bool = false, emit_lifecycle: bool = true) -> bool:
	# 当前轮回状态；只有轮回技可以被重置。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	if skill_state.is_empty():
		return false
	if emit_lifecycle and bool(skill_state.get("section_started", false)):
		_emit_lifecycle("reincarnationSectionEnd", player_id, skill_id, skill_state)
		_emit_lifecycle("reincarnationEnd", player_id, skill_id, skill_state)
	skill_state["round_count"] = 1
	skill_state["section_index"] = 0
	skill_state["section_started"] = false
	skill_state["used_sections_this_play_phase"] = []
	if clear_eternal:
		skill_state["eternal"] = false
		skill_state["eternal_per_turn_limit"] = 0
		skill_state["eternal_turn_number"] = -1
		skill_state["eternal_uses_this_turn"] = 0
	if emit_lifecycle:
		_emit_lifecycle("reincarnationStart", player_id, skill_id, skill_state)
		_emit_lifecycle("reincarnationSectionStart", player_id, skill_id, skill_state)
		skill_state["section_started"] = true
	_store_skill_state(player_id, skill_id, skill_state)
	_notify_state_changed()
	return true


## 进入永劫状态并锁定当前轮回节；已经处于永劫时返回false且不刷新或覆盖已有额度。
func enter_eternal_state(player_id: int, skill_id: String, per_turn_limit: int = 0) -> bool:
	# 当前轮回状态；永劫只作用于已经登记的轮回技。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	if skill_state.is_empty() or bool(skill_state.get("eternal", false)):
		return false
	skill_state["eternal"] = true
	skill_state["eternal_per_turn_limit"] = maxi(per_turn_limit, 0)
	skill_state["eternal_turn_number"] = _get_turn_number()
	skill_state["eternal_uses_this_turn"] = 0
	_store_skill_state(player_id, skill_id, skill_state)
	_notify_state_changed()
	return true


## 退出永劫状态并解除当前轮回节锁定；轮回数、当前轮回节与已开始状态均保持不变，非永劫技能无事发生。
func exit_eternal_state(player_id: int, skill_id: String) -> bool:
	# 当前轮回状态；不存在或未处于永劫时不发送冗余快照，也不改写任何额度。
	var skill_state: Dictionary = get_skill_state(player_id, skill_id)
	if skill_state.is_empty() or not bool(skill_state.get("eternal", false)):
		return false
	skill_state["eternal"] = false
	skill_state["eternal_per_turn_limit"] = 0
	skill_state["eternal_turn_number"] = -1
	skill_state["eternal_uses_this_turn"] = 0
	_store_skill_state(player_id, skill_id, skill_state)
	_notify_state_changed()
	return true


## 每次进入任意普通或额外出牌阶段时清空该角色各轮回节的阶段发动记录。
func on_play_phase_started(player_id: int) -> void:
	# 技能持有者；无效角色没有需要重置的轮回阶段额度。
	var player: PlayerState = _get_player(player_id)
	if player == null:
		return
	for skill_id_variant: Variant in player.reincarnation_skills.keys():
		# 当前技能稳定ID；作为字典键回写清空后的状态。
		var skill_id: String = str(skill_id_variant)
		# 当前技能状态；只清空出牌阶段额度，轮回数与永劫计数保持不变。
		var skill_state: Dictionary = player.reincarnation_skills.get(skill_id, {}) as Dictionary
		skill_state["used_sections_this_play_phase"] = []
		player.reincarnation_skills[skill_id] = skill_state


## 读取指定玩家；服务内全部入口复用该防御性查询。
func _get_player(player_id: int) -> PlayerState:
	if _host == null or _host.get("state") == null:
		return null
	return _host.state.get_player(player_id) as PlayerState


## 把修改后的技能状态写回玩家公开状态；字典深复制避免调用方继续持有可写引用。
func _store_skill_state(player_id: int, skill_id: String, skill_state: Dictionary) -> void:
	# 技能持有者；等待期间玩家失效时安全丢弃本次回写。
	var player: PlayerState = _get_player(player_id)
	if player != null:
		player.reincarnation_skills[skill_id] = skill_state.duplicate(true)


## 首次实际使用或外部推进前发布当前轮回与轮回节开始时机。
func _ensure_current_section_started(player_id: int, skill_id: String, skill_state: Dictionary) -> void:
	if bool(skill_state.get("section_started", false)):
		return
	_emit_lifecycle("reincarnationStart", player_id, skill_id, skill_state)
	_emit_lifecycle("reincarnationSectionStart", player_id, skill_id, skill_state)
	skill_state["section_started"] = true


## 发布当前轮回节结束，推进状态并立即发布新轮回节开始；force_new_round供明确整轮推进扩展使用。
func _finish_current_section_and_advance(player_id: int, skill_id: String, skill_state: Dictionary, force_new_round: bool) -> void:
	_ensure_current_section_started(player_id, skill_id, skill_state)
	_emit_lifecycle("reincarnationSectionEnd", player_id, skill_id, skill_state)
	# 当前轮回节总数；异常旧存档最少按一个轮回节处理。
	var section_count: int = maxi(int(skill_state.get("section_count", 1)), 1)
	# 当前轮回节索引；永劫状态下视作唯一且最后一个轮回节。
	var current_section_index: int = clampi(int(skill_state.get("section_index", 0)), 0, section_count - 1)
	# 本次是否结束当前轮回；最后一节、强制推进或永劫锁定均直接进入下一轮回。
	var enters_new_round: bool = force_new_round or bool(skill_state.get("eternal", false)) or current_section_index >= section_count - 1
	if enters_new_round:
		_emit_lifecycle("reincarnationEnd", player_id, skill_id, skill_state)
		skill_state["round_count"] = maxi(int(skill_state.get("round_count", 1)), 1) + 1
		if not bool(skill_state.get("eternal", false)):
			skill_state["section_index"] = 0
		_emit_lifecycle("reincarnationStart", player_id, skill_id, skill_state)
	else:
		skill_state["section_index"] = current_section_index + 1
	_emit_lifecycle("reincarnationSectionStart", player_id, skill_id, skill_state)
	skill_state["section_started"] = true


## 在轮回技效果实际完成时消费永劫与每轮回节阶段额度；取消发动不会调用本入口。
func _consume_activation_limits(player_id: int, skill_state: Dictionary) -> void:
	_sync_eternal_turn_counter(skill_state)
	if bool(skill_state.get("eternal", false)):
		skill_state["eternal_uses_this_turn"] = int(skill_state.get("eternal_uses_this_turn", 0)) + 1
	if bool(skill_state.get("each_section_once_per_play_phase", false)) and _is_owner_play_phase(player_id):
		# 本阶段已用轮回节集合；数组保存零基索引并保证不重复。
		var used_sections: Array = (skill_state.get("used_sections_this_play_phase", []) as Array).duplicate()
		# 本次实际发动的轮回节索引；推进发生前记录，因此准确归属于效果段。
		var section_index: int = int(skill_state.get("section_index", 0))
		if not used_sections.has(section_index):
			used_sections.append(section_index)
		skill_state["used_sections_this_play_phase"] = used_sections


## 跨全局回合时惰性重置永劫发动计数；进入永劫前的发动不会写入该计数。
func _sync_eternal_turn_counter(skill_state: Dictionary) -> void:
	if not bool(skill_state.get("eternal", false)):
		return
	# 当前权威回合号；测试或未开始对局时回退0。
	var turn_number: int = _get_turn_number()
	if int(skill_state.get("eternal_turn_number", -1)) != turn_number:
		skill_state["eternal_turn_number"] = turn_number
		skill_state["eternal_uses_this_turn"] = 0


## 判断当前是否为技能持有者自己的出牌阶段；阶段外触发不占用“出牌阶段每个轮回节限一次”。
func _is_owner_play_phase(player_id: int) -> bool:
	return _host != null and _host.get("state") != null and _host.state.current_player_id == player_id and str(_host.state.current_phase) == "play"


## 返回当前全局回合号；服务不自行维护第二套回合计数。
func _get_turn_number() -> int:
	return int(_host.state.turn_number) if _host != null and _host.get("state") != null else 0


## 通过控制器发布标准轮回生命周期时机；事件数据只包含稳定ID与数值快照。
func _emit_lifecycle(event_name: String, player_id: int, skill_id: String, skill_state: Dictionary) -> void:
	if _host == null or not _host.has_method("emit_rule_timing"):
		return
	# 轮回事件数据；section_number使用从1开始的玩家可见编号，section_index保留程序零基索引。
	var event_data: Dictionary = {
		"skill_id":skill_id,
		"round_count":maxi(int(skill_state.get("round_count", 1)), 1),
		"section_index":maxi(int(skill_state.get("section_index", 0)), 0),
		"section_number":maxi(int(skill_state.get("section_index", 0)), 0) + 1,
		"section_count":maxi(int(skill_state.get("section_count", 1)), 1),
		"eternal":bool(skill_state.get("eternal", false)),
	}
	_host.call("emit_rule_timing", event_name, player_id, player_id, player_id, event_data)


## 请求控制器发布新公开快照；服务不了解网络、回放或界面订阅者。
func _notify_state_changed() -> void:
	if _host != null and _host.has_method("notify_reincarnation_state_changed"):
		_host.call("notify_reincarnation_state_changed")
