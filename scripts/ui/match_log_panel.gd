class_name MatchLogPanel
extends Control

## 可折叠对局日志组件。组件只管理日志面板的展开状态和按钮文本，不读取对局状态或提交规则动作。

## 展开按钮显示文本；默认“记录”，用于牌桌左侧常驻入口，运行时通常无需动态修改。
@export var collapsed_button_text: String = "记录"

## 收起按钮显示文本；默认“收起记录”，明确提示再次点击会隐藏日志内容，运行时通常无需动态修改。
@export var expanded_button_text: String = "收起记录"

## 日志展开按钮；始终保持可见并独立接收鼠标输入。
@onready var _toggle_button: Button = %LogToggleButton

## 日志正文面板；默认隐藏，展开后显示标题与可滚动日志文本。
@onready var _content_panel: PanelContainer = %LogContentPanel

## 当前日志是否展开；仅控制界面可见性，不影响日志内容的持续追加。
var _is_expanded: bool = false


## 连接展开按钮并应用默认折叠状态。
func _ready() -> void:
	_toggle_button.pressed.connect(_toggle_log)
	_set_expanded(false)


## 切换日志正文显隐；隐藏期间新增日志仍由原文本节点保存，重新展开即可查看。
func _toggle_log() -> void:
	_set_expanded(not _is_expanded)


## 统一写入展开状态、正文可见性和按钮文本，避免多个节点分别维护状态。
func _set_expanded(expanded: bool) -> void:
	_is_expanded = expanded
	_content_panel.visible = _is_expanded
	_toggle_button.text = expanded_button_text if _is_expanded else collapsed_button_text
