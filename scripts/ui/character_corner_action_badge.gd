class_name CharacterCornerActionBadge
extends Button

## 武将牌左上角通用按钮角标组件。
## 与 CharacterCornerTextBadge 共用同一套视觉规格（背景色、圆角、内边距、字号、描边），
## 区别只在于本组件接收鼠标点击并把“哪个条目被按下”交回协调器。
##
## 职责边界：本组件不读取技能、玩家状态、快照或任何规则服务，也不判断 view_kind 的取值含义。
## 它只负责“显示文本 + 发出稳定来源标识”，具体打开哪种只读界面由 match_table 按映射表决定。
## 这样新增第二种可查看内容时，无需修改本组件，也不会在界面层出现按技能名分支的写法。

## 按钮被按下时发出稳定来源ID与中性查看类型；两者都原样来自角标条目，组件不做任何加工。
signal action_pressed(entry_id: String, view_kind: String)

## 本条目的稳定来源ID；与写入角标条目时的 entry_id 一致，供协调器回到条目字典取数据。
var entry_id: String = ""

## 本条目的中性查看类型；由内容层技能声明，取值语义只由表现层的映射表解释。
var view_kind: String = ""


## 初始化组件并把 pressed 信号接到本组件的回调；只连一次，避免重复配置后叠加多次发射。
func _ready() -> void:
	pressed.connect(_on_pressed)


## 配置条目标识、显示文本与查看类型；显示文本为空时隐藏，与文本角标的空文本隐藏语义保持一致。
func configure(entry_identifier: String, display_text: String, entry_view_kind: String) -> void:
	entry_id = entry_identifier
	view_kind = entry_view_kind
	text = display_text
	visible = not display_text.is_empty()


## 返回当前按钮文本；供界面测试验证角标条目已经正确投射到组件上。
func get_display_text() -> String:
	return text


## 把来源标识与查看类型交回协调器；组件自身不产生任何规则动作或状态写入。
func _on_pressed() -> void:
	action_pressed.emit(entry_id, view_kind)
