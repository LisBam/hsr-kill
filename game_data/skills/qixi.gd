extends SkillDefinition

## 【奇袭】技能源码。持有者发动“出牌阶段限一次”或“轮回技”的技能后积累“军功”，
## 达到6枚时把标记移除至1，并按刚发动技能的类型复原其出牌阶段额度或令其进入下一个轮回节。

## “军功”公开标记稳定ID；升变与奇袭必须使用同一ID读取和修改数量。
const MILITARY_MERIT_MARK_ID: String = "jungong"

## “军功”公开标记首次创建元数据；图标与说明面向局内所有观察者长期展示。
const MILITARY_MERIT_MARK_DATA: Dictionary = {"icon":"军", "name":"军功", "description":"拥有“军功”标记的角色视为拥有技能“奇袭”。", "source_skill_id":"shengbian"}

## 进入重置分支所需的“军功”阈值；数值6来自技能原文，达到或超过该值时不再积累而改为移除至1。
const REPEAT_THRESHOLD: int = 6

## 重置分支保留的“军功”数量；数值1来自“移除至1”原文。
const RESET_MARK_COUNT: int = 1


## 写入锁定技静态信息；技能描述逐字保持需求提供的原文，其中两个技能标签均带引号。
func _init() -> void:
	super({
		"id":"qixi",
		"name":"奇袭",
		"trigger":"skillAfter",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，当你发动“出牌阶段限一次”或“轮回技”的技能后，若你的“军功”标记数少于6，你获得一枚“军功”标记；否则你将“军功”标记数移除至1，若此技能为“出牌阶段限一次”，则视为本回合未发动过此技能；若此技能为“轮回技”，则进入下一个轮回节。",
	})


## 订阅全场实际技能发动时机；角色过滤在回调内读取player_id，避免兼容主动入口的旧skillAfter误触发。
func install() -> void:
	subscribe_timing("skillAfter", _on_skill_after, "global")


## 对持有者一次合规实际发动执行积累或重置分支；重复发动与奇袭自身均不触发。
func _on_skill_after(event: RuleEvent) -> void:
	if event == null or event.player_id != owner_player_id or not bool(event.data.get("actual_activation", false)) or bool(event.data.get("repeated_activation", false)):
		return
	# 刚发动技能稳定ID；空ID与奇袭自身都不能成为本次结算对象。
	var activated_skill_id: String = str(event.data.get("skill_id", ""))
	if activated_skill_id.is_empty() or activated_skill_id == get_id():
		return
	# 刚发动技能元数据；两类判定所需的轮回技标签与技能正文都从该静态定义读取。
	var activated_skill_metadata: Dictionary = GameDatabase.get_skill(activated_skill_id)
	if activated_skill_metadata.is_empty():
		return
	# 刚发动技能正文；“出牌阶段限一次”没有元数据标签，仍按正文声明识别，引号内提及（含奇袭自身正文）不计入。
	var activated_description: String = str(activated_skill_metadata.get("description", ""))
	# 该技能是否为“出牌阶段限一次”技能；决定重置分支是否复原其阶段额度。
	var is_play_phase_once_skill: bool = description_declares_tag(activated_description, PLAY_PHASE_ONCE_TAG)
	# 该技能是否为“轮回技”；只读技能源码声明的轮回技标签，不按正文判断，避免引用他人轮回技的技能被误算。
	var is_reincarnation_skill: bool = bool(activated_skill_metadata.get("reincarnation", false))
	if not is_play_phase_once_skill and not is_reincarnation_skill:
		return
	# 当前“军功”数量；标记不存在时按0处理并进入积累分支。
	var military_merit_count: int = maxi(int((host.call("get_player_mark", owner_player_id, MILITARY_MERIT_MARK_ID) as Dictionary).get("count", 0)), 0)
	if military_merit_count < REPEAT_THRESHOLD:
		announce_activation({"activated_skill_id":activated_skill_id, "military_merit_before":military_merit_count, "military_merit_after":military_merit_count + 1})
		host.call("change_player_mark_count", owner_player_id, MILITARY_MERIT_MARK_ID, 1, MILITARY_MERIT_MARK_DATA)
		return
	announce_activation({"activated_skill_id":activated_skill_id, "military_merit_before":military_merit_count, "military_merit_after":RESET_MARK_COUNT, "reset_play_phase_usage":is_play_phase_once_skill, "advance_reincarnation_section":is_reincarnation_skill})
	host.call("change_player_mark_count", owner_player_id, MILITARY_MERIT_MARK_ID, RESET_MARK_COUNT - military_merit_count, MILITARY_MERIT_MARK_DATA)
	# 重置后续结算上下文；只保存稳定ID与两个布尔分支，不持有技能对象或角色节点。
	defer_settlement({"kind":"qixi_merit_reset", "activated_skill_id":activated_skill_id, "reset_play_phase_usage":is_play_phase_once_skill, "advance_reincarnation_section":is_reincarnation_skill, "locked_skill_segment":true})


## 在原技能完整结算后执行“视为未发动”与“进入下一个轮回节”；延后保证原技能自己的额度消费与轮回推进已经落定。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "qixi_merit_reset":
		return false
	# 待处理技能稳定ID；等待期间该技能被卸载或换将时两个效果都会被权威端口安全拒绝。
	var activated_skill_id: String = str(context.get("activated_skill_id", ""))
	if activated_skill_id.is_empty():
		return true
	# “视为本回合未发动过此技能”；只复原该技能自己的出牌阶段额度。
	if bool(context.get("reset_play_phase_usage", false)):
		host.call("reset_skill_play_phase_usage", owner_player_id, activated_skill_id)
	# “进入下一个轮回节”；非轮回技或轮回登记已清除时端口返回false且不产生副作用。
	if bool(context.get("advance_reincarnation_section", false)):
		host.call("enter_next_reincarnation_section", owner_player_id, activated_skill_id)
	return true
