class_name MobileKeyboardGuard
extends RefCounted

## 移动端软键盘焦点工具。界面切换时统一释放文本控件焦点并关闭系统输入法，不持有任何场景节点或业务状态。


## 释放当前视口中的文本输入焦点，并在Android隐藏系统软键盘；非文本焦点保持不变。
static func release_text_focus_and_hide(viewport: Viewport) -> void:
	if OS.get_name() != "Android":
		return
	if viewport != null:
		# 当前GUI焦点控件；只有文本输入控件会被释放，普通按钮与手柄导航焦点不受影响。
		var focus_owner: Control = viewport.gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			focus_owner.release_focus()
	DisplayServer.virtual_keyboard_hide()


## 清理文本焦点后把导航焦点交给非文本控件；用于移动端进入新页面时避免自动弹出输入法。
static func focus_non_text(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	release_text_focus_and_hide(control.get_viewport())
	control.grab_focus()
