class_name CardDefinition
extends RefCounted

## 卡牌源码定义基类。每张具体卡牌脚本保存自身静态信息、同步效果与异步恢复入口，数据库仅负责自动发现和索引。

## 当前卡牌的完整静态元数据；由具体卡牌脚本在构造时一次性写入，运行时只通过深拷贝向外提供。
var _metadata: Dictionary = {}

## 当前区域持续效果绑定的对局控制器端口；静态数据库定义保持 null，只有装备等运行时实例会写入。
var runtime_host: Object

## 当前区域持续效果所属玩家 ID；未绑定时为 -1，绑定后使用稳定 player_id 而非座次数组下标。
var runtime_owner_player_id: int = -1

## 当前区域持续效果对应的实体牌 UID；未绑定时为 -1，用于换装或移牌后精确卸载同一实例。
var runtime_card_uid: int = -1


## 保存具体卡牌提供的完整元数据；调用方修改原始字典不会影响已创建的定义对象。
func _init(metadata: Dictionary = {}) -> void:
	_metadata = metadata.duplicate(true)


## 返回卡牌静态信息的深拷贝，用于界面、规则、AI、网络与存档读取。
func get_metadata() -> Dictionary:
	return _metadata.duplicate(true)


## 返回卡牌稳定逻辑 ID；该值必须在 game_data/cards 全目录中唯一。
func get_id() -> String:
	return str(_metadata.get("id", ""))


## 绑定需要持续存在于装备区等区域的卡牌实例；普通一次性卡牌无需调用本函数。
func bind_runtime(match_host: Object, owner_player_id: int, card_uid: int) -> void:
	runtime_host = match_host
	runtime_owner_player_id = owner_player_id
	runtime_card_uid = card_uid


## 安装卡牌的持续触发或查询修正；具体装备可覆盖本函数订阅事件或修正管线。
func install_runtime() -> void:
	pass


## 卸载卡牌持续效果；基类按实例所有者清理事件订阅，具体卡牌应在覆盖时补充自身修正管线清理。
func uninstall_runtime() -> void:
	if runtime_host != null and runtime_host.get("event_bus") != null:
		runtime_host.event_bus.unsubscribe_owner(self)
	if runtime_host != null and runtime_host.get("trigger_manager") != null:
		runtime_host.trigger_manager.unsubscribe_owner(self)


## 执行卡牌效果并返回最终区域语义；具体卡牌应覆盖本函数并调用解析器公开的规则操作入口。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_no_effect(card, actor_id, target_ids)


## 执行逐目标卡牌的当前目标内容；默认复用 resolve，特殊牌可读取共享上下文覆盖此入口。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	return resolve(resolver, card, actor_id, [target_id])


## 恢复由当前卡牌效果创建的普通选牌请求；返回 true 表示该选择已由卡牌源码识别并处理。
func continue_choice(_resolver: Object, _context: Dictionary, _selected_uids: Array[int]) -> bool:
	return false


## 恢复由当前卡牌效果创建的响应牌请求；响应实体已由控制器完成合法性校验和区域移动。
## 返回 true 表示该响应已由卡牌源码识别并处理，控制器只负责通用目标收尾。
func continue_response(_resolver: Object, _context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 恢复当前卡牌自定义的【无懈可击】后续流程；普通逐目标锦囊无需覆盖本入口。
## 返回 true 表示卡牌已自行恢复专用上下文，控制器不得再执行默认逐目标恢复。
func continue_negation(_resolver: Object, _context: Dictionary, _final_negated: bool) -> bool:
	return false


## 修正装备持有者使用指定牌时的最大目标数；非相关装备保持原值。
func modify_maximum_target_count(_actor: PlayerState, _card: CardInstance, current_count: int) -> int:
	return current_count


## 返回装备是否解除指定牌的阶段使用次数限制；默认不解除任何限制。
func ignores_play_count_limit(_card_definition: Dictionary) -> bool:
	return false


## 返回武器是否令【杀】忽略目标防具；默认仍应用防具效果。
func slash_ignores_armor() -> bool:
	return false


## 判断防具是否令当前【杀】直接无效；默认不阻止伤害流程。
func blocks_slash(_card: CardInstance, _nature: String) -> bool:
	return false


## 判断防具是否令指定群体锦囊对持有者无效；默认不阻止锦囊。
func blocks_aoe(_card_definition_id: String) -> bool:
	return false


## 修正装备持有者造成的伤害；上下文包含目标、属性与来源牌 ID。
func modify_outgoing_damage(_match_host: Object, _owner: PlayerState, _target: PlayerState, _context: Dictionary, amount: int) -> int:
	return amount


## 修正装备持有者受到的伤害；ignore_armor 为 true 时控制器不会调用防具修正。
func modify_incoming_damage(_match_host: Object, _owner: PlayerState, _context: Dictionary, amount: int) -> int:
	return amount


## 处理实体牌离开装备区后的专属效果；trigger_loss_effects 为 false 时只执行区域清理。
func on_leave_equipment(_match_host: Object, _owner: PlayerState, _trigger_loss_effects: bool) -> void:
	pass


## 结算延时锦囊到达判定阶段后的具体规则；默认安全弃置，具体延时牌应在自身文件完整覆盖。
func resolve_delayed_judgment(match_host: Object, _player_id: int, card: CardInstance, _negated: bool) -> void:
	match_host.discard_delayed_card(card)
