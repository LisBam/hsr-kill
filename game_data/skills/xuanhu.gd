extends SkillDefinition

## 【悬壶】锁定技源码。持有者的【桃】不计入手牌上限，并在任意角色死亡后从句牌堆取得一张【桃】。
## 两个效果都是锁定效果：不创建任何选择窗口、不消耗任何次数额度，满足条件即自动执行。

## 【桃】的稳定卡牌定义ID；作为锁定技的效果目标是固定牌名，因此直接以定义ID识别。
## 本技能原文明确写出【桃】这个名字（而不是“一张基本牌”），因此不改用 effect_id 等更宽的牌族口径。
const PEACH_DEFINITION_ID: String = "tao"


## 写入锁定技静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"xuanhu",
		"name":"悬壶",
		"lock":true,
		"ui_enabled":false,
		"description":"锁定技，你的【桃】不计入手牌上限。当一名角色死亡后，你从牌堆中获得一张【桃】。",
	})


## 订阅任意角色死亡后的全局时机；锁定技无主动入口，不使用任何选择恢复。
func install() -> void:
	subscribe_timing("dieAfter", _on_player_died, "global")


## 声明持有者的【桃】不计入手牌上限；由控制器在弃牌阶段统计溢出张数时统一询问。
func does_not_count_toward_hand_limit(card: CardInstance, definition: Dictionary) -> bool:
	return str(definition.get("id", "")) == PEACH_DEFINITION_ID


## 任意角色死亡后从句牌堆取得一张【桃】；持有者本人死亡时不再获得任何牌。
## 从牌堆顶端向底端寻找第一张【桃】，因此不要求该牌原本位于牌堆顶，符合“从牌堆中获得”的口径。
func _on_player_died(_event: RuleEvent) -> void:
	# 持有者状态；已死亡或已离场的持有者不能再获得牌，此时本效果整体跳过。
	var owner: PlayerState = _get_player(owner_player_id)
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 权威牌堆；数组顺序即“从顶端到底端”的顺序，因此首个命中即为原文含义的“一张【桃】”。
	var draw_pile_cards: Array = host.state.draw_pile
	for card_variant: Variant in draw_pile_cards:
		# 当前牌堆实体；异常空位直接跳过，保证遍历不会因脏数据中断。
		var card: CardInstance = card_variant as CardInstance
		if card == null or card.definition_id != PEACH_DEFINITION_ID:
			continue
		# 取得该实体牌；取得失败说明牌已在等待期间离开牌堆，按“本次不获得”处理。
		var gained_card: CardInstance = host.call("gain_draw_pile_card_by_uid", owner_player_id, card.uid, get_id()) as CardInstance
		if gained_card == null:
			return
		announce_activation({"gained_card_uid":card.uid, "gained_card_id":PEACH_DEFINITION_ID})
		return
	# 牌堆中没有【桃】时本效果无牌可得；不洗牌、不改动牌堆，也不产生任何日志与错误。


## 返回指定角色的权威状态；未绑定权威端口或角色不存在时返回null。
func _get_player(player_id: int) -> PlayerState:
	if host == null or host.get("state") == null:
		return null
	return host.state.get_player(player_id)
