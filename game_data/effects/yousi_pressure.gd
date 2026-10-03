extends PlayerEffect

## 「游丝·压力」角色持续效果源码。
##
## 存在的理由：需求配套 AI 提示要求“被发动【游丝】的角色，若主演不为队友，则本回合内会尽可能把手牌打出去/弃置，
## 避免被主演获得手牌”。这条倾向属于**被施加的角色**，而且施加者（卡芙卡）可能在本回合中途阵亡或换将，
## 届时技能实例会被整体卸载——如果把倾向实现成技能实例字段，它会连同技能一起消失，
## 而目标角色“少留牌”的动机在本回合内依然成立。因此这里改用 PlayerEffect 承载。
##
## 本效果刻意只提供一个标量倾向值，不携带任何隐藏事实：它不让 AI 知道牌堆顶放了什么、是谁放的，
## 也不进入任何观察者快照牌面，只回答“这个角色本回合是否更急着出牌”。
## 生命周期完全由自己维护：绑定的角色自己的回合结束时自行清除状态并请求移除，不依赖施加者是否仍然存活。
##
## 持久状态写在**承载角色自己**的 `character_form_state`，与【凶星】的口径一致。
## 这样做的理由是宿主的重建探测（`PlayerEffectService.restore_effects()`）只创建一个**未绑定 host** 的实例，
## 然后问 `has_persisted_state(该角色)`；任何依赖 host 或依赖“别人的状态”的判断在那里都读不到，
## 会被静默判为“无状态”而让效果在读档后消失。

## 本效果在角色效果表中的稳定 ID；与脚本文件名保持一致，宿主据此创建、查询与移除实例。
const EFFECT_ID: String = "yousi_pressure"

## 承载角色身上“本回合受游丝影响、更急于出牌”这一状态的键名。
## 该字段随权威存档往返；改名会使旧存档中的压力状态失效，必须保持稳定。
## 只记录“是否存在”而不记录牌名与位次：秘密本身在卡芙卡的 `private_pile_placement` 里，与本键无关。
const PRESSURE_STATE_KEY: String = "yousi_pressure_active"

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


## 判断承载角色身上是否仍有本效果需要继续结算的持久状态。
## 纯只读、只用传进来的角色自身状态：宿主的重建探测不会绑定 host，任何依赖 host 或其他人状态的判断都会失效。
## 只按“键是否存在”判断而不比对回合号：效果在承载者自己的回合结束时必然清除本键，
## 因此残留键不存在；而探测阶段本来就拿不到“当前回合号”可比较。
func has_persisted_state(player: PlayerState) -> bool:
	return player != null and player.character_form_state.has(PRESSURE_STATE_KEY)


## 登记本效果需要的时机并写入持久状态。
## 时机只有承载角色**自己**的回合结束：role 取 "player" 表示按事件中的回合角色匹配，其他角色的回合结束不会提前移除。
## 持久状态在此写入而不是由技能写入，因此显式安装与读档重建都会自动补上，不会出现“有实例无状态”的分叉。
func install_effect() -> void:
	subscribe_timing("phaseAfter", _on_target_turn_finished, "player")
	var target: PlayerState = _get_target_player()
	if target != null:
		target.character_form_state[PRESSURE_STATE_KEY] = true


## 卸载时清除持久状态；本效果是“本回合内”的临时倾向，不跨回合也不跨读档残留。
## 承载者死亡路径同样会走到这里（基类先回调 on_target_died()，再由宿主移除实例）。
func uninstall_effect() -> void:
	_clear_persisted_state()


## 承载角色死亡时清除持久状态；死亡后本回合的压力已无意义，残留会让复活后的同名效果被误判为已登记。
func on_target_died() -> void:
	_clear_persisted_state()


## 承载角色回合结束时清除持久状态并请求宿主移除本效果。
func _on_target_turn_finished(_event: RuleEvent) -> void:
	_clear_persisted_state()
	if host != null and host.has_method("remove_player_effect"):
		host.call("remove_player_effect", target_player_id, EFFECT_ID)


## 清除承载角色身上的压力状态键；承载者不存在时什么也不做。
func _clear_persisted_state() -> void:
	var target: PlayerState = _get_target_player()
	if target != null:
		target.character_form_state.erase(PRESSURE_STATE_KEY)


## 返回承载角色的权威状态；未绑定权威端口或角色不存在时返回null。
func _get_target_player() -> PlayerState:
	if host == null or host.get("state") == null:
		return null
	return host.state.get_player(target_player_id)
