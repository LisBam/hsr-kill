class_name AndroidBackAdapter
extends Node

## 安卓系统返回键适配组件。组件只把平台窗口通知转换为标准输入动作，不依赖主菜单、牌桌或联机面板节点。

## 当前界面没有消费标准取消动作时发出的回退请求；场景协调器可据此打开局内菜单或退出顶层页面。
signal unhandled_back_requested

## 安卓返回键对应的标准输入动作；默认使用Godot内置ui_cancel，使所有已有菜单和取消逻辑无需平台分支即可复用，运行时通常无需修改。
@export var cancel_action_name: StringName = &"ui_cancel"

## 是否只在Android平台转换返回通知；默认开启，防止桌面窗口通知意外生成取消动作，运行时通常无需修改。
@export var android_only: bool = true


## 接收系统级窗口通知；Android返回手势与实体返回键都会进入同一标准取消动作。
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if android_only and OS.get_name() != "Android":
		return
	call_deferred("_emit_cancel_action")


## 注入一次完整的取消动作按下与释放；现有_unhandled_input链会按当前最上层界面决定关闭、退出或取消选择。
func _emit_cancel_action() -> void:
	# 返回键按下事件；动作名来自导出参数，强度1.0表示一次完整数字按键输入。
	var press_event: InputEventAction = InputEventAction.new()
	press_event.action = cancel_action_name
	press_event.pressed = true
	press_event.strength = 1.0
	Input.parse_input_event(press_event)
	# 标准取消动作是否已被当前最上层界面消费；未消费时交给场景协调器处理页面级返回语义。
	var cancel_was_handled: bool = get_viewport() != null and get_viewport().is_input_handled()
	# 返回键释放事件；紧随按下发送，避免输入状态停留在持续按住并影响后续界面。
	var release_event: InputEventAction = InputEventAction.new()
	release_event.action = cancel_action_name
	release_event.pressed = false
	release_event.strength = 0.0
	Input.parse_input_event(release_event)
	if not cancel_was_handled:
		unhandled_back_requested.emit()
