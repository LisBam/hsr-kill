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


## 向整张牌的共享结算上下文写入本牌专属参数；默认不增加任何字段。
## 本函数在上下文登记到控制器之前调用，只能写入可序列化值，不得创建选择或直接推进结算。
func configure_resolution_context(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> void:
	pass


## 在共享结算上下文已经登记后执行整牌准备效果；返回 true 表示创建了等待请求并暂停进入目标流程。
func on_resolution_started(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> bool:
	return false


## 在实体牌完成使用声明时更新该牌拥有的兼容统计或触发状态；通用控制器不识别具体牌族。
func on_card_declared(_match_host: Object, _actor: PlayerState, _card: CardInstance) -> void:
	pass


## 在一名玩家的新回合建立后重置本牌拥有的回合状态；非相关卡牌保持空实现。
func on_turn_started(_match_host: Object, _player_id: int) -> void:
	pass


## 在一名玩家正常结束或因死亡中断回合时清理本牌持续状态；interrupted 表示没有进入正常结束阶段。
func on_turn_ended(_match_host: Object, _player_id: int, _interrupted: bool) -> void:
	pass


## 返回多目标声明是否必须保留玩家提交顺序；默认按行动座次规范化目标顺序。
func preserves_requested_target_order() -> bool:
	return false


## 校验当前目标在完整目标组合中的卡牌专属角色语义；空字符串表示继续执行通用目标规则。
func validate_target_selection(_rule_service: Object, _actor: PlayerState, _target_id: int, _all_target_ids: Array[int]) -> String:
	return ""


## 追加当前实体牌需要自定义组合生成的出牌阶段动作；返回 true 表示本牌已完全接管动作枚举。
func append_play_phase_card_actions(_match_host: Object, _actor_id: int, _card: CardInstance, _result: Array[Dictionary]) -> bool:
	return false


## 返回本牌在指定角色濒死救援窗口中提供的响应模式；空字符串表示当前关系下不能用于救援。
func get_dying_response_pattern(_responder_id: int, _dying_player_id: int) -> String:
	return ""


## 应用已经消费的濒死救援牌；返回 true 表示本牌完成了合法救援效果。
func resolve_dying_response(_match_host: Object, _responder_id: int, _dying_player_id: int, _card: CardInstance) -> bool:
	return false


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


## 在整张【杀】建立共享结算上下文后执行武器准备效果；可修改属性或创建发动选择。
## 返回 true 表示已创建等待请求，控制器应暂停进入逐目标流程。
func on_slash_resolution_started(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> bool:
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


## 在【杀】开始结算单个目标、检查防具与【闪】之前执行武器专属效果。
## 返回 true 表示武器已接管或暂停流程；武器完成后必须调用 slash_effect.continue_after_weapon_targeted()。
func on_slash_targeted(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 在目标打出【闪】后执行武器专属效果；context.dodged 表示当前是否仍被【闪】抵消。
## 返回 true 表示武器已接管或暂停流程；需要继续时调用 slash_effect.continue_after_weapon_dodged()。
func on_slash_dodged(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 在【杀】即将造成伤害前执行武器替代效果；返回 true 表示已防止伤害或等待选择。
## 未发动替代效果时应返回 false，或在异步恢复后调用 slash_effect.continue_slash_damage()。
func on_slash_before_damage(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 在【杀】伤害完整结算且目标仍存活后执行武器后续效果；返回 true 表示已创建等待流程。
func on_slash_damage_finished(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 恢复由武器【杀】钩子创建的普通选牌请求；返回 true 表示当前装备源码已处理该 kind。
func continue_slash_choice(_slash_effect: Object, _context: Dictionary, _selected_uids: Array[int]) -> bool:
	return false


## 恢复由武器【杀】钩子创建的响应牌请求；返回 true 表示当前装备源码已处理该 kind。
func continue_slash_response(_slash_effect: Object, _context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 在装备持有者使用或打出一张实体牌后通知装备源码；was_hand_card 仅对真正来自手牌区的牌为 true。
func on_owner_card_consumed(_match_host: Object, _owner_id: int, _used_card: CardInstance, _was_hand_card: bool) -> void:
	pass


## 开始一条由装备源码排队的延后触发；返回 true 表示已创建选择或完成本次触发。
func begin_queued_equipment_trigger(_match_host: Object, _owner_id: int, _context: Dictionary) -> bool:
	return false


## 恢复不依附于处理区父牌的装备普通选牌；返回 true 表示当前装备定义已处理。
func continue_equipment_choice(_match_host: Object, _context: Dictionary, _selected_uids: Array[int]) -> bool:
	return false


## 恢复不依附于处理区父牌的装备响应牌选择；返回 true 表示当前装备定义已处理。
func continue_equipment_response(_match_host: Object, _context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 判断装备是否能作为当前响应模式集合中的可选入口；返回 true 时控制器展示装备实体候选。
func can_offer_equipment_response(_match_host: Object, _player_id: int, _response_patterns: Array[String]) -> bool:
	return false


## 返回装备响应需要选择的普通手牌材料数量；0表示直接选择装备即可结算。
func get_equipment_response_material_count() -> int:
	return 0


## 校验装备响应材料；空字符串表示合法，非空字符串作为统一动作拒绝原因。
func validate_equipment_response_materials(_match_host: Object, _player_id: int, _equipment_uid: int, _material_card_uids: Array[int]) -> String:
	return ""


## 消费装备响应入口并返回虚拟响应牌；材料和装备实体必须在卡牌文件中复核。
func consume_equipment_response(_match_host: Object, _player_id: int, _equipment_uid: int, _response_patterns: Array[String], _material_card_uids: Array[int]) -> CardInstance:
	return null


## 返回装备在出牌阶段注册的自定义动作类型；控制器按动作名把校验和执行交回装备文件。
func get_play_phase_action_types() -> Array[String]:
	return []


## 返回当前装备实体是否应出现在出牌阶段可点击候选中。
func is_play_phase_action_available(_match_host: Object, _owner_id: int, _equipment_card: CardInstance) -> bool:
	return false


## 向 AI 与只读动作枚举追加该装备可执行的完整动作字典。
func append_play_phase_actions(_match_host: Object, _owner_id: int, _equipment_card: CardInstance, _result: Array[Dictionary]) -> void:
	pass


## 无副作用校验装备主动动作；空字符串表示合法，非空字符串为拒绝原因。
func validate_play_phase_action(_match_host: Object, _action: PlayerAction) -> String:
	return "该装备当前不能主动发动。"


## 执行已经通过校验的装备主动动作；返回 true 表示规则效果成功完成或已进入异步流程。
func execute_play_phase_action(_match_host: Object, _action: PlayerAction) -> bool:
	return false


## 返回装备主动动作的只读预览；字段应兼容普通卡牌预览的目标与确认信息。
func get_play_phase_action_preview(_match_host: Object, _owner_id: int, _equipment_uid: int, _payload: Dictionary, _selected_target_ids: Array[int]) -> Dictionary:
	return {}


## 结算延时锦囊到达判定阶段后的具体规则；默认安全弃置，具体延时牌应在自身文件完整覆盖。
func resolve_delayed_judgment(match_host: Object, _player_id: int, card: CardInstance, _negated: bool) -> void:
	match_host.discard_delayed_card(card)
