extends RefCounted

## 无交互规则预演的无懈内容；使用正式响应消费与同一规则步骤，不用同步while跳过异步窗口。

## 权威宿主；不进入网络数据。
var _host: Object

## 当前完整响应；下一步骤才读取结果。
var _response: RefCounted

## 链完成标志；尚未完成时调用方必须保留原效果。
var completed: bool = false

## 最终奇偶抵消状态；仅completed之后作为最终结果。
var negated: bool = false

## 是否需要回调原父牌；同步路径直接返回，异步路径通知一次。
var _notify: bool = false


## 绑定当前规则宿主。
func _init(host: Object) -> void:
	_host = host


## 行动顺序仅用于预演同帧平局；生产联机仍使用正式同时响应请求。
func begin(context: Dictionary) -> void:
	# 完整链上下文；每轮成功消费后才重置行动游标。
	var data: Dictionary = {"sequence_kind":"negation_preview", "rule_context":context.duplicate(true), "index":0, "completed":false}
	# 动态宿主边界需要强类型数组；字面量Array不会自动转换。
	var steps: Array[Callable] = [_next]
	_host.run_rule_sequence(steps, data)
	_notify = not completed


## 每次只挑选一个实际响应者；完整消费结束后再更新奇偶与下一轮。
func _next(sequence: RuleStepSequence) -> void:
	# 本目标独立的无懈上下文。
	var context: Dictionary = sequence.context.rule_context
	# 稳定平局顺序；失效玩家逐项跳过，不消费旧候选。
	var order: Array = context.get("response_order_ids", [])
	while int(sequence.context.index) < order.size() and not _host.state.game_over:
		# 当前询问角色；失败只前进当前游标。
		var responder_id: int = int(order[int(sequence.context.index)])
		sequence.context.index = int(sequence.context.index) + 1
		# 当前角色状态；预演复用正式AI收益判断。
		var responder: PlayerState = _host.state.get_player(responder_id)
		if responder == null or not responder.alive or responder.out_of_game or not _host._should_auto_negate(responder, int(context.get("source_id", -1)), int(context.get("target_id", -1)), str(context.get("trick_id", "")), bool(context.get("negated", false))):
			continue
		# 当前合法候选；实际支付由统一响应服务再次复核。
		# 单一合法响应模式；显式类型用于动态规则端口。
		var patterns: Array[String] = ["wuxie"]
		var candidates: Array[Dictionary] = _host._build_response_choice_candidates(responder, patterns)
		if candidates.is_empty():
			continue
		sequence.context["responder_id"] = responder_id
		# 无装备指定材料；候选装备的费用仍由响应服务声明。
		var materials: Array[int] = []
		_response = _host.begin_response_resolution(responder_id, int(candidates[0].get("uid", -1)), patterns, materials, "", context)
		sequence.insert_steps([_apply, _next])
		return
	sequence.insert_steps([_finish])


## After及其全部子内容结束后才翻转奇偶；取消费用不会被记为无懈。
func _apply(sequence: RuleStepSequence) -> void:
	if _response == null or not _response.completed or _response.result == null:
		return
	# 最终实体或代理；只从已完成响应读取。
	var card: CardInstance = _response.result as CardInstance
	# 原链上下文；本轮成功后从首个角色重新询问反无懈。
	var context: Dictionary = sequence.context.rule_context
	context["negated"] = not bool(context.get("negated", false))
	_host._record_wuxie_chain_response(context, int(sequence.context.responder_id), card)
	_host.add_log("%s使用【无懈可击】，当前锦囊%s。" % [_host.format_player_log_name(int(sequence.context.responder_id)), "被抵消" if bool(context.negated) else "恢复生效"])
	sequence.context.index = 0


## 异步路径只通知父内容一次；先标记链完成，恢复原效果不会再次把自己识别为未完成子链。
func _finish(sequence: RuleStepSequence) -> void:
	negated = bool(sequence.context.rule_context.get("negated", false))
	completed = true
	sequence.context.completed = true
	if _notify:
		_notify = false
		_host._finish_trick_negation_chain(sequence.context.rule_context, negated)
