extends SkillDefinition

## 【奇袭】技能源码。持有者发动合规技能后积累“军功”，达到6枚时重置标记并按原入口额外发动该技能。

## “军功”公开标记稳定ID；升变与奇袭必须使用同一ID读取和修改数量。
const MILITARY_MERIT_MARK_ID: String = "jungong"

## “军功”公开标记首次创建元数据；图标与说明面向局内所有观察者长期展示。
const MILITARY_MERIT_MARK_DATA: Dictionary = {"icon":"军", "name":"军功", "description":"拥有“军功”标记的角色视为拥有技能“奇袭”。", "source_skill_id":"shengbian"}

## 触发额外发动所需的“军功”阈值；数值6来自技能原文，达到或超过该值时进入重置分支。
const REPEAT_THRESHOLD: int = 6

## 额外发动前保留的“军功”数量；数值1来自“移除至1”原文。
const RESET_MARK_COUNT: int = 1


## 写入锁定技静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"qixi",
		"name":"奇袭",
		"trigger":"skillAfter",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，当你发动非限定技、觉醒技、锁定技的技能后，若你的“军功”标记数少于6，你获得一枚“军功”标记；否则你将“军功”标记数移除至1，然后额外发动一次所发动的技能，若该技能有目标，则保持目标不变。",
	})


## 订阅全场实际技能发动时机；角色过滤在回调内读取player_id，避免兼容主动入口的旧skillAfter误触发。
func install() -> void:
	subscribe_timing("skillAfter", _on_skill_after, "global")


## 对持有者一次合规实际发动执行积累或重置重放；重复发动、奇袭自身及三类排除技能均不触发。
func _on_skill_after(event: RuleEvent) -> void:
	if event == null or event.player_id != owner_player_id or not bool(event.data.get("actual_activation", false)) or bool(event.data.get("repeated_activation", false)):
		return
	# 刚发动技能稳定ID；空ID与奇袭自身都不能成为额外发动对象。
	var activated_skill_id: String = str(event.data.get("skill_id", ""))
	if activated_skill_id.is_empty() or activated_skill_id == get_id():
		return
	# 刚发动技能元数据；限定、觉醒或锁定任一标签成立即不属于奇袭触发范围。
	var activated_skill_metadata: Dictionary = GameDatabase.get_skill(activated_skill_id)
	if activated_skill_metadata.is_empty() or bool(activated_skill_metadata.get("limited", false)) or bool(activated_skill_metadata.get("awakening", false)) or bool(activated_skill_metadata.get("lock", false)):
		return
	# 当前“军功”数量；标记不存在时按0处理并进入积累分支。
	var military_merit_count: int = maxi(int((host.call("get_player_mark", owner_player_id, MILITARY_MERIT_MARK_ID) as Dictionary).get("count", 0)), 0)
	if military_merit_count < REPEAT_THRESHOLD:
		announce_activation({"activated_skill_id":activated_skill_id, "military_merit_before":military_merit_count, "military_merit_after":military_merit_count + 1})
		host.call("change_player_mark_count", owner_player_id, MILITARY_MERIT_MARK_ID, 1, MILITARY_MERIT_MARK_DATA)
		return
	# 原技能发动上下文；目标字段保持原数组，额外发动入口不得重新选择另一名目标。
	var activation_context: Dictionary = (event.data.get("context", {}) as Dictionary).duplicate(true)
	# 原技能重放令牌；用于确保延迟恢复仍对应当前观察到的这次发动。
	var activation_repeat_token: int = int(event.data.get("activation_repeat_token", -1))
	# 当前武将代次；换将或失去原技能后旧额外发动请求安全失效。
	var owner: PlayerState = get_owner_skill_player().get_state()
	# 额外发动绑定的武将代次；持有者异常不存在时回退-1并由控制器拒绝。
	var character_generation: int = owner.character_generation if owner != null else -1
	announce_activation({"activated_skill_id":activated_skill_id, "target_ids":activation_context.get("target_ids", []), "military_merit_before":military_merit_count, "military_merit_after":RESET_MARK_COUNT, "will_repeat":true})
	host.call("change_player_mark_count", owner_player_id, MILITARY_MERIT_MARK_ID, RESET_MARK_COUNT - military_merit_count, MILITARY_MERIT_MARK_DATA)
	defer_settlement({"kind":"qixi_repeat_skill", "activated_skill_id":activated_skill_id, "activation_context":activation_context, "activation_repeat_token":activation_repeat_token, "activated_skill_character_generation":character_generation, "locked_skill_segment":true})


## 在原技能当前结算与嵌套选择完成后重放其入口；目标沿用原上下文且不允许旧令牌命中后续发动。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != "qixi_repeat_skill":
		return false
	# 待额外发动技能ID；控制器会再次复核实例、代次与生效状态。
	var activated_skill_id: String = str(context.get("activated_skill_id", ""))
	# 原技能上下文；目标、材料或事件业务字段均为当次发动留下的稳定副本。
	var activation_context: Dictionary = (context.get("activation_context", {}) as Dictionary).duplicate(true)
	activation_context["repeated_activation"] = true
	host.call("repeat_skill_activation", owner_player_id, activated_skill_id, activation_context, int(context.get("activation_repeat_token", -1)), int(context.get("activated_skill_character_generation", -1)))
	return true
