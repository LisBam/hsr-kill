class_name ChoiceRequest
extends RefCounted

## 通用玩家选择请求。请求保存基础和活动上下文，支持技能 backup/restore、重做与候选排除。

## 选择请求状态；等待、完成、取消、超时和事件中断分别记录，便于网络恢复与回放审计。
enum Status {
	PENDING,
	RESOLVED,
	CANCELLED,
	TIMED_OUT,
	ABORTED,
}

## 请求稳定 ID；由 EventScheduler 单调递增分配，默认 -1 表示尚未登记。
var request_id: int = -1

## 创建请求的事件 ID；响应必须同时匹配 request_id 和 event_id。
var event_id: int = -1

## 需要作出选择的玩家 ID；非当前响应者提交会被权威端拒绝。
var actor_id: int = -1

## 选择类型；支持 use、respond、card、target、button、control、bool 与 discard 等稳定值。
var choice_type: String = "card"

## 面向当前响应者的长期语义提示；只描述本次选择目标，不承担规则执行逻辑。
var prompt: String = ""

## 可选实体牌 UID；只包含当前观察者有权选择的候选，不包含 CardInstance 引用。
var card_ids: Array[int] = []

## 可选目标玩家 ID；按权威座次或卡牌语义顺序排列。
var target_ids: Array[int] = []

## 可选按钮稳定 ID；技能按钮和自定义候选按钮均通过该数组表达。
var button_ids: Array[String] = []

## 可选控制项稳定 ID；适用于单选菜单、是否发动与排序控制。
var control_ids: Array[String] = []

## 最少选择数量；默认 0 允许空选择，具体维度由 choice_type 决定。
var min_count: int = 0

## 最多选择数量；默认 1，必须不小于 min_count。
var max_count: int = 1

## 组合选择中的最少卡牌数；默认 -1 表示继续使用 min_count，只有 card_target 等多维请求需要单独配置。
var min_card_count: int = -1

## 组合选择中的最多卡牌数；默认 -1 表示继续使用 max_count，修改后会独立约束响应中的 card_ids。
var max_card_count: int = -1

## 组合选择中的最少目标数；默认 -1 表示 target 请求继续使用 min_count，card_target 请求应显式配置。
var min_target_count: int = -1

## 组合选择中的最多目标数；默认 -1 表示 target 请求继续使用 max_count，修改后会独立约束响应中的 target_ids。
var max_target_count: int = -1

## 是否属于规则强制请求；强制请求不能通过 confirmed=false 取消。
var forced: bool = false

## 是否允许主动取消；默认 true，forced=true 时该值不会绕过强制校验。
var can_cancel: bool = true

## 权威截止时间毫秒；0 表示没有自动超时，网络层可按该值启用托管 AI。
var deadline_msec: int = 0

## deadline 的兼容别名；与 deadline_msec 保持同一毫秒数，便于外部协议按分析文档字段读取。
var deadline: int = 0

## 当前已选实体牌 UID；用于 UI 重建、断线恢复与增量合法性检查。
var selected_card_ids: Array[int] = []

## 当前已选目标玩家 ID；保留玩家选择顺序，不在请求层擅自按座次重排。
var selected_target_ids: Array[int] = []

## 当前已选按钮稳定 ID；允许多按钮请求保存完整恢复状态。
var selected_button_ids: Array[String] = []

## 基础选择上下文；保存最初过滤器 ID、选择范围、提示和规则参数的可序列化快照。
var base_context: Dictionary = {}

## 当前活动选择上下文；技能 backup 后可临时替换，restore 时恢复 base_context。
var active_context: Dictionary = {}

## 本次请求排除的候选及原因；只影响当前事件，不写入玩家永久技能或静态数据。
var excluded_candidates: Dictionary = {}

## 请求当前状态；新请求默认为 PENDING，终态请求不能再次接受响应。
var status: Status = Status.PENDING

## 最终选择结果；完成、取消或超时后保存 ChoiceResponse 的可序列化字典。
var result: Dictionary = {}

## 本请求关联的暂停 token ID；由 EventScheduler 登记，默认 -1 表示尚未暂停事件。
var pause_token_id: int = -1

## 当前上下文修订号；backup、restore 和 redo 每次递增，远端可据此丢弃过期增量界面。
var revision: int = 0


## 创建一个最小选择请求；候选和上下文由调用方在登记前填充。
func _init(owner_event_id: int = -1, chooser_id: int = -1, type: String = "card", message: String = "") -> void:
	event_id = owner_event_id
	actor_id = chooser_id
	choice_type = type
	prompt = message


## 从网络或回放字典恢复选择请求；请求仍需由 EventScheduler 重新登记后才具有权威生命周期。
static func from_dict(data: Dictionary) -> ChoiceRequest:
	# 新建请求；字段缺失时保持无效默认值，防止旧封包自动命中当前事件。
	var request: ChoiceRequest = ChoiceRequest.new(int(data.get("event_id", -1)), int(data.get("actor_id", -1)), str(data.get("choice_type", "card")), str(data.get("prompt", "")))
	request.request_id = int(data.get("request_id", -1))
	for card_id_variant: Variant in data.get("card_ids", []) as Array:
		request.card_ids.append(int(card_id_variant))
	for target_id_variant: Variant in data.get("target_ids", []) as Array:
		request.target_ids.append(int(target_id_variant))
	for button_id_variant: Variant in data.get("button_ids", []) as Array:
		request.button_ids.append(str(button_id_variant))
	for control_id_variant: Variant in data.get("control_ids", []) as Array:
		request.control_ids.append(str(control_id_variant))
	request.min_count = int(data.get("min_count", 0))
	request.max_count = int(data.get("max_count", 1))
	request.min_card_count = int(data.get("min_card_count", -1))
	request.max_card_count = int(data.get("max_card_count", -1))
	request.min_target_count = int(data.get("min_target_count", -1))
	request.max_target_count = int(data.get("max_target_count", -1))
	request.forced = bool(data.get("forced", false))
	request.can_cancel = bool(data.get("can_cancel", true))
	request.deadline_msec = int(data.get("deadline_msec", data.get("deadline", 0)))
	request.deadline = int(data.get("deadline", request.deadline_msec))
	request.base_context = (data.get("base_context", {}) as Dictionary).duplicate(true)
	request.active_context = (data.get("active_context", request.base_context) as Dictionary).duplicate(true)
	request.excluded_candidates = (data.get("excluded_candidates", {}) as Dictionary).duplicate(true)
	request.revision = int(data.get("revision", 0))
	return request


## 使用技能或候选能力临时替换活动上下文；所有数据深拷贝，避免脚本闭包进入网络协议。
func backup_context(skill_id: String, generated_card: Dictionary, filters: Dictionary, select_ranges: Dictionary) -> void:
	if base_context.is_empty():
		base_context = active_context.duplicate(true)
	active_context = {
		"skill_id": skill_id,
		"generated_card": generated_card.duplicate(true),
		"filters": filters.duplicate(true),
		"select_ranges": select_ranges.duplicate(true),
	}
	revision += 1


## 恢复请求的基础上下文；失败技能仍保留在 excluded_candidates，防止 AI 在同一步无限重试。
func restore_context() -> void:
	active_context = base_context.duplicate(true)
	selected_card_ids.clear()
	selected_target_ids.clear()
	selected_button_ids.clear()
	revision += 1


## 重做当前选择步骤；不改变基础上下文，只清空临时选择并递增修订号。
func redo_current_step() -> void:
	selected_card_ids.clear()
	selected_target_ids.clear()
	selected_button_ids.clear()
	revision += 1


## 在本次请求中排除一个候选并保存稳定原因；同一候选后写入的原因会覆盖旧原因。
func exclude_candidate(candidate_id: String, reason: String) -> void:
	excluded_candidates[candidate_id] = reason
	revision += 1


## 校验通用响应归属、取消语义、选择数量、候选存在性和重复项；返回空字符串表示通过。
func validate_response(response: ChoiceResponse) -> String:
	if status != Status.PENDING:
		return "选择请求已经结束。"
	if response.request_id != request_id or response.event_id != event_id:
		return "选择请求标识已失效。"
	if response.actor_id != actor_id:
		return "响应者不是当前选择玩家。"
	if not response.confirmed:
		if forced or not can_cancel:
			return "当前选择不能取消。"
		return ""
	# 卡牌选择范围；普通选牌沿用 min_count/max_count，组合选择使用独立范围。
	var card_range: Vector2i = _get_card_count_range()
	# 目标选择范围；普通选目标沿用 min_count/max_count，组合选择使用独立范围。
	var target_range: Vector2i = _get_target_count_range()
	# 按请求维度校验数量；未启用的维度返回 -1 范围并跳过数量限制。
	if card_range.x >= 0 and (response.card_ids.size() < card_range.x or response.card_ids.size() > card_range.y):
		return "选择的卡牌数量不符合要求。"
	if target_range.x >= 0 and (response.target_ids.size() < target_range.x or response.target_ids.size() > target_range.y):
		return "选择的目标数量不符合要求。"
	if choice_type == "button" and (response.button_ids.size() < min_count or response.button_ids.size() > max_count):
		return "选择的按钮数量不符合要求。"
	if choice_type in ["control", "bool"]:
		# 控制项选择数量；空字符串为0项，非空稳定 ID 为1项。
		var control_count: int = 0 if response.control_id.is_empty() else 1
		if control_count < min_count or control_count > max_count:
			return "选择的控制项数量不符合要求。"
	# 所有实际提交的维度均校验候选与重复项，避免 card_target 请求只校验卡牌而放过伪造目标。
	var candidate_error: String = _validate_selected_candidates(response.card_ids, card_ids)
	if not candidate_error.is_empty():
		return candidate_error
	candidate_error = _validate_selected_candidates(response.target_ids, target_ids)
	if not candidate_error.is_empty():
		return candidate_error
	candidate_error = _validate_selected_candidates(response.button_ids, button_ids)
	if not candidate_error.is_empty():
		return candidate_error
	if not response.control_id.is_empty() and not control_ids.has(response.control_id):
		return "选择结果包含无效候选。"
	# 可选的牌到目标映射；键使用实体 UID 字符串，值为该牌当前允许的目标 ID 数组。
	var targets_by_card_id: Dictionary = active_context.get("target_ids_by_card_id", {}) as Dictionary
	if targets_by_card_id.is_empty():
		# backup 上下文可把动态过滤器收纳在 filters 中；网络仍只传递其中的可序列化映射。
		targets_by_card_id = (active_context.get("filters", {}) as Dictionary).get("target_ids_by_card_id", {}) as Dictionary
	if not targets_by_card_id.is_empty() and not response.card_ids.is_empty():
		for selected_card_id: int in response.card_ids:
			# 当前所选卡牌允许的目标 ID；缺少映射时该卡牌不能与任何目标组合提交。
			var allowed_target_ids: Array = targets_by_card_id.get(str(selected_card_id), targets_by_card_id.get(selected_card_id, [])) as Array
			for selected_target_id: int in response.target_ids:
				if not allowed_target_ids.has(selected_target_id):
					return "所选卡牌与目标的组合不合法。"
	return ""


## 写入已经通过权威校验的最终响应；请求终态根据 confirmed 区分完成和取消。
func resolve(response: ChoiceResponse) -> void:
	result = response.to_dict()
	status = Status.RESOLVED if response.confirmed else Status.CANCELLED


## 因超时托管结束请求；传入的托管响应仍使用标准 ChoiceResponse 格式并保存完整来源。
func timeout(response: ChoiceResponse) -> void:
	result = response.to_dict()
	status = Status.TIMED_OUT


## 因父事件或对局结束中断请求；旧客户端随后提交同一 request_id 也不能恢复事件。
func abort(reason: String) -> void:
	status = Status.ABORTED
	result = {"confirmed": false, "reason": reason}


## 返回当前 choice_type 对应的选择结果数组；bool 与 control 也转换为长度 0 或 1 的数组参与通用数量校验。
func _get_selected_values(response: ChoiceResponse) -> Array:
	if choice_type in ["use", "respond", "card", "discard"]:
		return response.card_ids
	if choice_type == "target":
		return response.target_ids
	if choice_type == "button":
		return response.button_ids
	if choice_type in ["control", "bool"]:
		return [] if response.control_id.is_empty() else [response.control_id]
	return response.card_ids


## 返回当前 choice_type 对应的合法候选数组；调用方可用 active_context 保存更复杂的组合过滤信息。
func _get_allowed_values() -> Array:
	if choice_type in ["use", "respond", "card", "discard"]:
		return card_ids
	if choice_type == "target":
		return target_ids
	if choice_type == "button":
		return button_ids
	if choice_type in ["control", "bool"]:
		return control_ids
	return card_ids


## 返回卡牌维度的数量范围；Vector2i(-1, -1) 表示当前请求不以卡牌作为选择维度。
func _get_card_count_range() -> Vector2i:
	if choice_type in ["use", "respond", "card", "discard"]:
		return Vector2i(min_count, max_count)
	if choice_type == "card_target":
		return Vector2i(maxi(min_card_count, 0), maxi(max_card_count, maxi(min_card_count, 0)))
	return Vector2i(-1, -1)


## 返回目标维度的数量范围；Vector2i(-1, -1) 表示当前请求不以目标作为选择维度。
func _get_target_count_range() -> Vector2i:
	if choice_type == "target":
		return Vector2i(min_count, max_count)
	if choice_type == "card_target":
		return Vector2i(maxi(min_target_count, 0), maxi(max_target_count, maxi(min_target_count, 0)))
	return Vector2i(-1, -1)


## 校验一个响应数组是否全部来自请求候选且没有重复值；空数组始终合法，数量由独立范围函数判断。
func _validate_selected_candidates(selected_values: Array, allowed_values: Array) -> String:
	# 已见候选集合；Dictionary 同时支持整数与字符串稳定 ID。
	var seen_values: Dictionary = {}
	for selected_value: Variant in selected_values:
		if not allowed_values.has(selected_value):
			return "选择结果包含无效候选。"
		if seen_values.has(selected_value):
			return "选择结果不能包含重复候选。"
		seen_values[selected_value] = true
	return ""


## 生成完整可序列化请求快照；不包含脚本 Callable 或权威状态对象引用。
func to_dict() -> Dictionary:
	return {
		"request_id": request_id,
		"event_id": event_id,
		"actor_id": actor_id,
		"choice_type": choice_type,
		"prompt": prompt,
		"card_ids": card_ids.duplicate(),
		"target_ids": target_ids.duplicate(),
		"button_ids": button_ids.duplicate(),
		"control_ids": control_ids.duplicate(),
		"min_count": min_count,
		"max_count": max_count,
		"min_card_count": min_card_count,
		"max_card_count": max_card_count,
		"min_target_count": min_target_count,
		"max_target_count": max_target_count,
		"forced": forced,
		"can_cancel": can_cancel,
		"deadline_msec": deadline_msec,
		"deadline": deadline_msec if deadline == 0 else deadline,
		"selected_card_ids": selected_card_ids.duplicate(),
		"selected_target_ids": selected_target_ids.duplicate(),
		"selected_button_ids": selected_button_ids.duplicate(),
		"base_context": base_context.duplicate(true),
		"active_context": active_context.duplicate(true),
		"excluded_candidates": excluded_candidates.duplicate(true),
		"status": Status.keys()[status].to_lower(),
		"result": result.duplicate(true),
		"revision": revision,
	}
