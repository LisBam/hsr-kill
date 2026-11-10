extends RefCounted

## 响应选择的消费与接收编排；不在消费调用栈中提前保存空结果。

## 权威宿主；只在当前内容序列存活期间使用。
var _host: Object

## 当前消费结果对象；子序列结束后再读取。
var _resolution: RefCounted

## 已完成的响应结果；供没有异步窗口的兼容调用者读取。
var result: CardInstance

## 选择内容完成标志；尚未完成与明确放弃是不同状态。
var completed: bool = false

## 是否通过接收路由通知父内容；同步查询路径只返回结果，异步路径只通知一次。
var _notify: bool = true


## 绑定权威宿主。
func _init(host: Object) -> void:
	_host = host


## route=auto保留同步返回兼容；其余路由始终在消费完成后通知原接收者。
func begin(context: Dictionary, selected_uids: Array[int], patterns: Array[String], route: String) -> void:
	_notify = route != "auto"
	# 稳定选择内容；重试和接收都保持原父牌、技能与请求的上下文。
	var data: Dictionary = {"sequence_kind":"response_choice", "rule_context":context.duplicate(true), "selected_uids":selected_uids.duplicate(), "patterns":patterns.duplicate(), "route":route}
	# 消费与接收严格分步；子消费产生的时机、判定和移牌先于接收完成。
	var steps: Array[Callable] = [_consume, _apply]
	_host.run_rule_sequence(steps, data)
	if not completed:
		_notify = true


## 消费只执行一次；装备取消后的重试由结果步骤统一处理。
func _consume(sequence: RuleStepSequence) -> void:
	if (sequence.context.selected_uids as Array).is_empty() and str(sequence.context.rule_context.get("selected_cardless_response_skill_id", "")).is_empty():
		return
	# 原响应参数；材料和技能选择均在权威提交时已经写入。
	var context: Dictionary = sequence.context.rule_context
	# 响应角色；技能默认自身，其余响应默认原目标。
	var responder_id: int = int(context.get("responder_id", context.get("skill_owner_id", context.get("target_id", -1))))
	# 消费入口的强类型参数；上下文中的普通数组在边界显式转换。
	var patterns: Array[String] = _host._string_array(sequence.context.patterns)
	# 装备费用清单；普通响应为空。
	var materials: Array[int] = _host._int_array(context.get("equipment_material_uids", []))
	_resolution = _host.begin_response_resolution(responder_id, int(sequence.context.selected_uids[0]) if not (sequence.context.selected_uids as Array).is_empty() else -1, patterns, materials, str(context.get("selected_response_skill_id", "")), context)


## 子内容完成后再记录直接响应、执行装备重试或通知唯一接收者。
func _apply(sequence: RuleStepSequence) -> void:
	result = _resolution.result if _resolution != null and _resolution.completed else null
	# 原响应上下文；重试不能丢失已排除装备集合或父牌身份。
	var context: Dictionary = sequence.context.rule_context
	# 当前接收路由；无懈的直接响应计数由链自身按奇偶关系记录。
	var route: String = str(sequence.context.route)
	# 响应角色；重试与原窗口保持相同授权主体。
	var responder_id: int = int(context.get("responder_id", context.get("skill_owner_id", context.get("target_id", -1))))
	if result == null and route not in ["negation", "simultaneous"]:
		# 未成功的装备入口；本次失败后只排除该入口，不视为整次响应已经放弃。
		var equipment_uid: int = int(context.get("immediate_response_equipment_uid", -1)) if (sequence.context.selected_uids as Array).is_empty() else int(context.get("selected_response_equipment_uid", -1))
		if equipment_uid >= 0:
			# 当前合法模式；重开时与原窗口完全一致。
			var patterns: Array[String] = _host._string_array(sequence.context.patterns)
			result = _host._retry_response_after_equipment_attempt(context, responder_id, patterns, equipment_uid)
			if _host.has_pending_card_choice() or _host._sequence_waits_for_child_judgment(sequence):
				completed = true
				return
	elif result != null and route not in ["negation", "simultaneous"]:
		_host._record_direct_response_from_context(context)
	completed = true
	if _notify:
		_host._dispatch_resolved_response(context, result, route)
