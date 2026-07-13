extends Node

## 全局显示与对局配置入口。该节点只保存跨场景配置，不持有任何具体对局状态。

signal card_name_mode_changed(mode: NameMode)

## 卡牌名称显示模式；CUSTOM 展示《崩铁杀》名称，ORIGINAL 展示原版三国杀名称。
enum NameMode {
	CUSTOM,
	ORIGINAL,
}

## 当前卡牌名称模式；默认使用《崩铁杀》自定义牌名，可在运行时安全切换。
var card_name_mode: NameMode = NameMode.CUSTOM


## 设置全局卡牌名称模式，并通知所有已连接的界面刷新显示文本。
func set_card_name_mode(mode: NameMode) -> void:
	if card_name_mode == mode:
		return
	card_name_mode = mode
	card_name_mode_changed.emit(card_name_mode)


## 在两套卡牌名称之间切换，适合直接绑定设置按钮。
func toggle_card_name_mode() -> void:
	if card_name_mode == NameMode.CUSTOM:
		set_card_name_mode(NameMode.ORIGINAL)
	else:
		set_card_name_mode(NameMode.CUSTOM)


## 根据当前全局模式，从卡牌配置中返回唯一的前端显示名称。
func resolve_card_name(card_definition: Dictionary) -> String:
	if card_name_mode == NameMode.ORIGINAL:
		return str(card_definition.get("original_name", card_definition.get("id", "未知牌")))
	return str(card_definition.get("custom_name", card_definition.get("original_name", "未知牌")))
