extends PlayerEffect

## 「游丝·压力」角色持续效果源码。
##
## 存在的理由：需求配套 AI 提示要求“被发动【游丝】的角色，若主演不为队友，则本回合内会尽可能把手牌打出去/弃置，
## 避免被主演获得手牌”。这条倾向属于**被施加的角色**，而且施加者（卡芙卡）可能在本回合中途阵亡或换将，
## 届时技能实例会被整体卸载——如果把倾向实现成技能实例字段，它会连同技能一起消失，
## 而目标角色“少留牌”的动机在本回合内依然成立。因此这里改用 PlayerEffect 承载。
##
## 本效果刻意只提供一个标量倾向值，不携带任何隐藏事实：它不让 AI 知道牌堆顶放了什么、是谁放的，
## 也不进入任何观察者快照或存档，只回答“这个角色本回合是否更急着出牌”。
## 生命周期完全由自己维护：绑定的角色自己的回合结束时自行请求移除，不依赖施加者是否仍然存活。

## 本效果在角色效果表中的稳定 ID；与脚本文件名保持一致，宿主据此创建、查询与移除实例。
const EFFECT_ID: String = "yousi_pressure"

## 本效果向 AI 决策声明的手牌消耗倾向值；正数表示更愿意打出手牌。
## 取值理由：通用策略给每个用牌动作保留了“保牌机会成本”为负项，本值设在同一个数量级，
## 足以让中等收益的用牌动作越过接受阈值，又不足以让明确亏牌的动作变成正收益。
## 改动它会直接改变被施加角色的 AI 出牌积极性，运行时不应动态调整。
const AI_HAND_PRESSURE: float = 3.0


## 返回效果稳定 ID；必须与 game_data/effects 目录中的脚本文件名一致，便于长期维护定位。
func get_id() -> String:
	return EFFECT_ID


## 返回效果静态元数据；只描述效果语义，不承载任何运行时状态。
func get_metadata() -> Dictionary:
	return {
		"id":EFFECT_ID,
		"display_name":"游丝·压力",
		"description":"承载角色本回合的 AI 更愿意把手牌打出或弃置，以免回合结束时手牌被他人获得。",
	}


## 声明本效果要求承载角色的 AI 在本次决策中额外消耗手牌的倾向值。
## 只读、幂等：AI 可能在同一个回合内被请求多次决策，本函数每次都必须返回同一个值。
func get_ai_hand_pressure() -> float:
	return AI_HAND_PRESSURE


## 登记本效果需要的时机：只有承载角色**自己**的回合结束时才自然到期。
## role 取 "player" 表示按事件中的回合角色匹配，因此其他角色的回合结束不会提前移除本效果。
func install_effect() -> void:
	subscribe_timing("phaseAfter", _on_target_turn_finished, "player")


## 承载角色回合结束时请求宿主移除本效果；本效果是“本回合内”的临时倾向，不跨回合保留。
func _on_target_turn_finished(_event: RuleEvent) -> void:
	if host != null and host.has_method("remove_player_effect"):
		host.call("remove_player_effect", target_player_id, EFFECT_ID)


## 判断承载角色身上是否仍有本效果需要继续结算的持久状态。
## 判据是权威状态里的私有置牌事实：只有当“本回合角色恰好是承载者”的那条事实仍然存在时，
## 本效果才需要被重建，因此读档恢复不会凭空给任何角色加上出牌压力。
func has_persisted_state(player: PlayerState) -> bool:
	if host == null or not host.has_method("get_private_pile_placement"):
		return false
	# 该角色当前登记的私有置牌事实；空字典表示没有进行中的【游丝】。
	var placement: Dictionary = host.call("get_private_pile_placement", player.player_id) as Dictionary
	return int(placement.get("turn_player_id", -1)) == player.player_id
