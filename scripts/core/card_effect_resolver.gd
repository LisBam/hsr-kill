class_name CardEffectResolver
extends RefCounted

## 卡牌效果通用调度器。具体卡牌规则全部由 game_data/cards 下的源码定义拥有，本类只负责定位定义与提供生命周期查询。

## 对局控制器规则端口；卡牌源码通过该对象调用摸牌、伤害、选择与区域移动等权威操作。
var host: Object

## 当前权威状态；卡牌源码可读取玩家与公共区域，但不得替换状态对象。
var state: GameState


## 绑定对局规则端口与状态；调度器不负责二者的生命周期。
func _init(match_host: Object, game_state: GameState) -> void:
	host = match_host
	state = game_state


## 执行一张已经进入处理区的牌；具体同步效果来自对应卡牌源码。
func resolve(card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	if is_resolution_stopped():
		return "consumed"
	# 当前卡牌源码定义；缺失表示牌堆或存档引用已经失效。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if definition == null:
		host.add_log("卡牌【%s】缺少源码定义，效果未执行。" % card.definition_id)
		return "discard"
	return definition.resolve(self, card, actor_id, target_ids)


## 执行活动逐目标结算的当前目标；卡牌源码可读取整张牌共享的可序列化上下文。
func resolve_target(card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	if is_resolution_stopped():
		return "consumed"
	# 当前卡牌源码定义；逐目标与整牌入口使用同一个自动发现结果。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	if definition == null:
		return "discard"
	return definition.resolve_target(self, card, actor_id, target_id, resolution_context)


## 按父牌 UID 将普通选牌结果交回对应卡牌源码；调度器不识别任何具体卡牌或选择 kind。
func continue_choice(context: Dictionary, selected_uids: Array[int]) -> bool:
	# 原效果牌；异步恢复只允许操作仍位于公共处理区的父牌。
	var card: CardInstance = find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return false
	# 原效果牌定义；卡牌文件自行识别其创建的选择用途。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	return definition != null and definition.continue_choice(self, context, selected_uids)


## 按父牌 UID 将已消费的响应牌交回对应卡牌源码；null 表示响应者明确放弃。
func continue_response(context: Dictionary, response_card: CardInstance) -> bool:
	# 原效果牌；响应等待期间离开处理区时旧请求自动失效。
	var card: CardInstance = find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return false
	# 原效果牌定义；实际响应结果由卡牌文件决定伤害、轮换或后续装备触发。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	return definition != null and definition.continue_response(self, context, response_card)


## 按父牌 UID 恢复卡牌自定义的无懈后续流程；返回 false 时控制器执行普通逐目标恢复。
func continue_negation(context: Dictionary, final_negated: bool) -> bool:
	# 原效果牌；专用恢复同样要求父牌仍处于有效处理区。
	var card: CardInstance = find_processing_card(int(context.get("parent_card_uid", -1)))
	if card == null:
		return false
	# 原效果牌定义；整牌流程可覆盖专用无懈恢复。
	var definition: CardDefinition = GameDatabase.get_card_definition(card.definition_id)
	return definition != null and definition.continue_negation(self, context, final_negated)


## 处理没有主动使用效果的响应牌；实体响应由统一响应流程消费。
func resolve_no_effect(_card: CardInstance, _actor_id: int, _target_ids: Array[int]) -> String:
	return "discard"


## 判断普通锦囊当前目标是否应停止或被【无懈可击】跳过。
func should_skip_trick_target(card: CardInstance, actor_id: int, target_id: int) -> bool:
	if is_resolution_stopped():
		return true
	if host.resolve_trick_negation(actor_id, target_id, card.definition_id):
		return true
	return is_resolution_stopped()


## 返回卡牌同步入口的统一结束区域；存在选择时保留处理区等待恢复。
func default_destination() -> String:
	return "pending" if host.has_pending_card_choice() else "discard"


## 返回当前结算是否必须立即停止；等待选择或游戏结束时不得继续修改状态。
func is_resolution_stopped() -> bool:
	return state == null or state.game_over or host.has_pending_card_choice()


## 按稳定 UID 查找公共处理区父牌；异步恢复不使用易冲突的卡牌定义 ID。
func find_processing_card(card_uid: int) -> CardInstance:
	if state == null:
		return null
	for processing_card: CardInstance in state.processing_area:
		if processing_card.uid == card_uid:
			return processing_card
	return null
