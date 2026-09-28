class_name CharacterCornerTextBadge
extends PanelContainer

## 武将牌左上角通用文本组件。组件只显示调用方提供的公开文本，不读取技能、玩家状态或规则服务。

## 实际文字标签；场景固定使用黑色背景与白色文本，脚本只更新内容和显隐。
@onready var _text_label: Label = $TextLabel


## 设置当前展示文本；空字符串隐藏整个组件，非空文本按内容自动扩展宽度。
func set_display_text(display_text: String) -> void:
	visible = not display_text.is_empty()
	# 内部标签由 @onready 在进入场景树时取得，未入树时它仍是 null。这里静默跳过而不是抛出
	# “Invalid assignment ... on a base object of type 'Nil'”，避免一次排版时序问题打断技能结算。
	# 调用方仍应先 add_child 再写文本，本判断只是防止同类问题再次升级为中断性错误。
	if _text_label != null:
		_text_label.text = display_text


## 返回当前展示文本；供界面测试验证快照已经正确投射到组件。
func get_display_text() -> String:
	return _text_label.text if _text_label != null else ""
