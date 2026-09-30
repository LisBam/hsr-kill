extends PlayerEffect

## 【凶星】伤害加成效果源码。效果实例挂在“被施加凶星的角色”身上，与施加者（爻光）的技能实例完全解耦：
## 爻光阵亡、换将或被“非锁定技失效”压制都不影响本效果继续结算，因为层数本来就属于目标。
## 施加层数由【凶星】技能调用 add_stacks() 完成；本效果只负责“受伤时把层数计入伤害并在伤害成立后消费”。

## 效果稳定ID；与脚本文件名保持一致，便于维护定位与宿主按 ID 重建实例。
const EFFECT_ID: String = "xiongxingshanghai"

## 目标身上“下次受伤+N”累计层数在 character_form_state 中的稳定键名。
## 该字段随权威存档往返、不进入公开快照；改名会使旧存档中的层数失效，必须保持稳定。
const DAMAGE_STACK_STATE_KEY: String = "xiongxing_damage_stacks"

## 目标身上“已预留加成、尚未结算”的伤害事件ID键名。
## 该标记按目标存放而不是写进伤害事件的 data：伤害各修改窗口的 data 不保证是同一份字典，
## 而按目标存放还能让多名义光共享同一份预留状态，避免同一伤害被重复加成。
const RESERVED_EVENT_STATE_KEY: String = "xiongxing_reserved_damage_event_id"

## 单层凶星提供的伤害加成；固定1点，多层时累加为“下次受到的伤害+N”。
const DAMAGE_BONUS_PER_STACK: int = 1

## 角标条目ID；不带来源玩家后缀，因为层数已按目标聚合，同一目标只需要一条凶星文本。
const CORNER_ENTRY_ID: String = "xiongxing"

## 角标基础文本；1层时显示该文本。
const CORNER_TEXT_BASE: String = "凶星"

## 角标显示层数后缀的最小层数；固定2，对应“大于等于2层时才显示层数”。
const CORNER_TEXT_STACK_DISPLAY_MIN: int = 2

## 凶星文本在武将牌左上角组合条目中的排序值；50与【酩酊】【追歼】同档，使短期受击提示优先于回合统计文本。
const CORNER_TEXT_ORDER: int = 50


## 返回效果稳定ID；宿主用它按状态重建实例，技能用它查询自己施加的效果。
func get_id() -> String:
	return EFFECT_ID


## 返回效果静态元数据；仅供工具链与文档读取，不承载运行时状态。
func get_metadata() -> Dictionary:
	return {
		"id": EFFECT_ID,
		"name": "凶星伤害",
		"description": "目标下次受到的伤害+1；层数挂在目标身上，不随施加者的阵亡、换将或技能失效而撤回。",
	}


## 登记四个伤害时机；role="target" 表示只有承载者本人成为伤害目标时才回调。
## 不再需要像技能实现那样比对事件目标ID：TriggerManager 已按 role 过滤，承载者之外的伤害不会进入本效果。
func install_effect() -> void:
	subscribe_timing("damageBegin3", _on_damage_begin_three, "target")
	subscribe_timing("damage", _on_damage_happened, "target")
	subscribe_timing("damageCancelled", _on_damage_not_happened, "target")
	subscribe_timing("damageZero", _on_damage_not_happened, "target")
	# 实例建立时按权威层数刷新一次角标：存档恢复后角标即使缺失也能在此自愈，且重复刷新没有副作用。
	_refresh_corner_text(get_stacks())


## 卸载时按当前真实层数刷新角标，保持“界面显示”与“权威数据”一致；
## 层数仍大于0说明还有未结算的凶星，因此不在这里清除数据——数据只由伤害消费或承载者死亡清除。
func uninstall_effect() -> void:
	_refresh_corner_text(get_stacks())


## 判断承载角色身上是否仍有凶星层数；宿主在开局与读档恢复时据此重建效果实例。
func has_persisted_state(player: PlayerState) -> bool:
	return player != null and int(player.character_form_state.get(DAMAGE_STACK_STATE_KEY, 0)) > 0


## 叠加凶星层数并刷新角标；返回叠加后的总层数，供施加者播报与界面使用。
## 层数按目标聚合：多名义光、多次发动都作用在同一份计数上，与“谁施加的”无关。
func add_stacks(amount: int) -> int:
	# 叠加后的层数；先读后写，保证并发施加时正确累加而不是互相覆盖。
	var next_stacks: int = get_stacks() + maxi(amount, 0)
	_set_stacks(next_stacks)
	return next_stacks


## 返回承载角色身上当前的凶星层数；角色不存在或未记录时返回0。
func get_stacks() -> int:
	var target: PlayerState = _get_target_player()
	if target == null:
		return 0
	return maxi(int(target.character_form_state.get(DAMAGE_STACK_STATE_KEY, 0)), 0)


## 写入承载角色的凶星层数并同步刷新其角标；层数不大于0时删除键并移除角标。
func _set_stacks(stacks: int) -> void:
	var target: PlayerState = _get_target_player()
	if target == null:
		return
	# 规范化层数；负数统一按0处理，避免异常输入产生“负层数”导致加伤异常。
	var normalized_stacks: int = maxi(stacks, 0)
	if normalized_stacks <= 0:
		target.character_form_state.erase(DAMAGE_STACK_STATE_KEY)
	else:
		target.character_form_state[DAMAGE_STACK_STATE_KEY] = normalized_stacks
	_refresh_corner_text(normalized_stacks)


## 在第三伤害修改窗口把承载角色身上的全部凶星层数一次性计入本次伤害；层数在伤害实际成立时才消费。
func _on_damage_begin_three(event: RuleEvent) -> void:
	var target: PlayerState = _get_target_player()
	if target == null:
		return
	# 承载角色身上的层数；为0表示当前没有凶星，直接跳过。
	var stacks: int = get_stacks()
	if stacks <= 0:
		return
	# 当前伤害事件ID；缺失时无法做幂等保护，宁可不加成也不冒重复加成的风险。
	var damage_event_id: int = int(event.data.get("damage_event_id", -1))
	if damage_event_id < 0:
		return
	# 预留幂等；目标身上已有任何未结算预留时不再加成。
	# 该判断同时覆盖两种重复来源：多名义光针对同一伤害的重复加成，以及外层伤害内部嵌套出的新伤害。
	if int(target.character_form_state.get(RESERVED_EVENT_STATE_KEY, -1)) >= 0:
		return
	target.character_form_state[RESERVED_EVENT_STATE_KEY] = damage_event_id
	event.data["amount"] = maxi(int(event.data.get("amount", 0)), 0) + stacks * DAMAGE_BONUS_PER_STACK


## 伤害实际成立时消费承载角色身上的全部层数；凶星的每一层都作用于“下一次”，因此一次性清空。
func _on_damage_happened(event: RuleEvent) -> void:
	# 只有本次伤害确实由凶星加成过才允许消费层数，否则会把无关伤害的层数一并清掉。
	if not _release_reservation(int(event.data.get("damage_event_id", -1))):
		return
	_set_stacks(0)


## 伤害被取消或最终归零时只释放事件占用；层数继续保留给下一次真正成立的伤害。
func _on_damage_not_happened(event: RuleEvent) -> void:
	_release_reservation(int(event.data.get("damage_event_id", -1)))


## 释放承载角色身上的预留标记；返回本次调用是否确实清除了与给定伤害事件对应的预留。
## 该返回值同时充当“本次伤害是否由凶星加成过”的凭据，并让多名义光共享的消费动作只成功一次。
func _release_reservation(damage_event_id: int) -> bool:
	var target: PlayerState = _get_target_player()
	if target == null or damage_event_id < 0:
		return false
	if int(target.character_form_state.get(RESERVED_EVENT_STATE_KEY, -1)) != damage_event_id:
		return false
	target.character_form_state.erase(RESERVED_EVENT_STATE_KEY)
	return true


## 承载角色死亡后清除其身上的层数与预留标记；效果由基类在清理完成后请求宿主移除。
## 层数已按目标聚合，无法也不应追溯具体来源，因此这里无条件清空。
func on_target_died() -> void:
	_set_stacks(0)
	# 死亡角色身上的预留标记同样失去意义；残留会让后续同名伤害事件ID被误判为已加成。
	var target: PlayerState = _get_target_player()
	if target != null:
		target.character_form_state.erase(RESERVED_EVENT_STATE_KEY)


## 按层数刷新承载角色武将牌左上角的凶星文本；1层显示“凶星”，多层显示“凶星N”（层数直接跟随名称），0层移除条目。
func _refresh_corner_text(stacks: int) -> void:
	if host == null or not host.has_method("set_character_corner_text_entry") or not host.has_method("remove_character_corner_text_entry"):
		return
	if stacks <= 0:
		host.call("remove_character_corner_text_entry", target_player_id, CORNER_ENTRY_ID)
		return
	# 显示文本；低于多层阈值时只显示基础文本，达到阈值后直接把层数接在名称后面。
	var display_text: String = CORNER_TEXT_BASE
	if stacks >= CORNER_TEXT_STACK_DISPLAY_MIN:
		display_text = "%s%d" % [CORNER_TEXT_BASE, stacks]
	host.call("set_character_corner_text_entry", target_player_id, CORNER_ENTRY_ID, display_text, CORNER_TEXT_ORDER)


## 返回承载角色的权威状态；未绑定权威端口或角色不存在时返回null。
func _get_target_player() -> PlayerState:
	if host == null or host.get("state") == null:
		return null
	return host.state.get_player(target_player_id)
