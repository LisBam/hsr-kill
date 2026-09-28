extends Node

## 角标区排版回归测试。
##
## 覆盖曾经造成线上中断的排版时序问题：纯文本角标（无 view_kind，当前为【安可】【酩酊】【逐风】【追歼】）
## 与按钮角标（带 view_kind，当前为【解构】）都必须在进入场景树后再写入内容。
## CharacterCornerTextBadge 用 @onready 取内部 Label，入树前该引用为 null，提前写入会抛出
## “Invalid assignment ... on a base object of type 'Nil'”，并沿状态广播栈上抛打断正在结算的技能。
##
## 【本测试的覆盖边界】它断言的是“角标最终排版结果正确”——子控件数量、组件类型、文本内容都与预期一致。
## 它**不**直接断言“入树前写入是否抛错”，因为组件自身已有判空防护会让该情形静默跳过而不报错。
## 因此修复由两层共同保证，缺一不可：调用顺序保证内容真的写进去（本测试可验证），
## 组件判空保证任何时序意外都不会升级为中断性错误（由组件实现保证）。
## 只回退其中任一层，本测试都可能仍然通过，所以修改角标排版时必须同时检查这两处。
##
## 本测试直接驱动表现层组件，不依赖权威状态与对局流程，因此能在无对局环境下稳定复现排版问题。

## 武将牌组件场景；角标区位于其下，测试只关心排版结果。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 文本角标用例；取值与正式技能写入的文本形态保持一致，便于定位真实回归。
const TEXT_ENTRY: Dictionary = {"entry_id":"zhufeng:distance", "text":"逐风 2", "view_kind":""}

## 按钮角标用例；view_kind 非空表示该条目需要点击查看。
const BUTTON_ENTRY: Dictionary = {"entry_id":"jiegou:recorded_names", "text":"解构", "view_kind":"recorded_card_names"}

## 失败原因；为空表示当前用例尚未失败。
var _failure: String = ""


## 依次执行两个用例并把结论写入标准输出；测试运行器按 _PASS 标记判定成功。
func _ready() -> void:
	await get_tree().process_frame
	# 武将牌根节点是 Node2D（透明输入区与角标区都是它的 Control 子节点），因此按 Node2D 接收。
	var view: Node2D = PLAYER_TARGET_VIEW_SCENE.instantiate() as Node2D
	if view == null:
		_fail("scene_instantiate")
		return
	add_child(view)
	await get_tree().process_frame
	if not await _check_text_entry(view):
		return
	if not await _check_button_entry(view):
		return
	view.queue_free()
	await get_tree().process_frame
	print("CORNER_BADGE_PASS text_entry=1 button_entry=1")
	get_tree().quit(0)


## 校验纯文本角标：必须成功创建1个子控件，且内部标签已写入文本。
func _check_text_entry(view: Node2D) -> bool:
	view.call("_rebuild_corner_stack", [TEXT_ENTRY] as Array[Dictionary])
	await get_tree().process_frame
	var stack: Control = view.get_node("CharacterCornerStack")
	if stack.get_child_count() != 1:
		_fail("text_entry_count=%d" % stack.get_child_count())
		return false
	var badge: Control = stack.get_child(0)
	if badge == null or not badge.has_method("get_display_text"):
		_fail("text_entry_type=%s" % (badge.get_class() if badge != null else "null"))
		return false
	# 内部标签写入结果；@onready 未就绪时这里会是空字符串而不是正确文本。
	var displayed: String = str(badge.call("get_display_text"))
	if displayed != str(TEXT_ENTRY["text"]):
		_fail("text_entry_text=%s" % displayed)
		return false
	return true


## 校验按钮角标：必须创建为按钮、文本为技能名、且带稳定来源标识。
func _check_button_entry(view: Node2D) -> bool:
	view.call("_rebuild_corner_stack", [BUTTON_ENTRY] as Array[Dictionary])
	await get_tree().process_frame
	var stack: Control = view.get_node("CharacterCornerStack")
	if stack.get_child_count() != 1:
		_fail("button_entry_count=%d" % stack.get_child_count())
		return false
	var badge: Control = stack.get_child(0)
	if badge == null or not (badge is Button):
		_fail("button_entry_type=%s" % (badge.get_class() if badge != null else "null"))
		return false
	if str(badge.get("text")) != str(BUTTON_ENTRY["text"]):
		_fail("button_entry_text=%s" % str(badge.get("text")))
		return false
	if str(badge.get("entry_id")) != str(BUTTON_ENTRY["entry_id"]):
		_fail("button_entry_id=%s" % str(badge.get("entry_id")))
		return false
	return true


## 记录失败原因并按非零码退出；保证 CI 能通过退出码发现回归。
func _fail(reason: String) -> void:
	_failure = reason
	print("CORNER_BADGE_FAIL %s" % reason)
	get_tree().quit(1)
