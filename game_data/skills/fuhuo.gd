extends SkillDefinition

## 【负火】技能源码。四类事件在每个全局回合分别至多触发一次，积累“火种”并在手牌少于5时补牌。

## “火种”公开标记稳定ID；负火积累与轮回觉醒共同使用该ID。
const FIRE_SEED_MARK_ID: String = "huozhong"

## “火种”公开标记首次创建元数据；上限与觉醒条件写入说明供所有观察者理解。
const FIRE_SEED_MARK_DATA: Dictionary = {"icon":"火", "name":"火种", "description":"负火至多积累12枚“火种”；轮回觉醒会移除全部“火种”。", "source_skill_id":"fuhuo"}

## “火种”可由负火积累的最大数量；数值12来自技能原文。
const MAX_FIRE_SEED_COUNT: int = 12

## 补牌判定使用的手牌阈值；手牌数小于5时固定摸一张。
const DRAW_HAND_THRESHOLD: int = 5

## 每次合规事件固定获得的“火种”数量；数值1来自“一枚”原文。
const FIRE_SEED_GAIN: int = 1

## 每次合规事件在手牌不足时固定摸牌数；数值1来自“摸一张牌”原文。
const DRAW_COUNT: int = 1

## 当前四项额度对应的全局回合号；默认-1，首次触发时建立本回合记录。
var _tracked_turn_number: int = -1

## 当前全局回合已经触发的项目集合；键为use_card、targeted、damaged、damage_dealt，换回合时整体清空。
var _used_items_this_turn: Dictionary = {}


## 写入锁定技静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"fuhuo",
		"name":"负火",
		"trigger":["useCard", "useCardToTargeted", "damageAfter"],
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，每回合每项限一次，1.当你使用一张牌时，2.当你成为牌的目标时，3.当你受到伤害时，4.当你造成伤害时，若你的“火种”标记数小于12，你获得一枚“火种”标记，然后若你的手牌数小于5，你摸一张牌。",
	})


## 分别订阅四项触发关系；受到与造成同一次自伤会命中两个独立额度，符合“每项限一次”。
func install() -> void:
	subscribe_timing("useCard", _on_use_card, "source")
	subscribe_timing("useCardToTargeted", _on_become_card_target, "target")
	subscribe_timing("damageAfter", _on_damage_taken, "target")
	subscribe_timing("damageAfter", _on_damage_dealt, "source")


## 持有者使用一张牌时消费第1项本回合额度。
func _on_use_card(event: RuleEvent) -> void:
	_apply_item("use_card", event)


## 持有者成为牌的目标时消费第2项本回合额度；多目标或重复目标时机只取首次。
func _on_become_card_target(event: RuleEvent) -> void:
	_apply_item("targeted", event)


## 持有者受到正数伤害后消费第3项本回合额度。
func _on_damage_taken(event: RuleEvent) -> void:
	if event != null and int(event.data.get("amount", 0)) > 0:
		_apply_item("damaged", event)


## 持有者造成正数伤害后消费第4项本回合额度。
func _on_damage_dealt(event: RuleEvent) -> void:
	if event != null and int(event.data.get("amount", 0)) > 0:
		_apply_item("damage_dealt", event)


## 统一执行一项首次触发；火种已达12时原文条件不成立，因此既不消费额度也不摸牌。
func _apply_item(item_id: String, event: RuleEvent) -> void:
	_sync_turn_usage()
	if item_id.is_empty() or bool(_used_items_this_turn.get(item_id, false)) or _get_fire_seed_count() >= MAX_FIRE_SEED_COUNT:
		return
	# 技能持有者；事件派发期间仍需复核其存活在场与手牌数量。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	_used_items_this_turn[item_id] = true
	host.call("change_player_mark_count", owner_player_id, FIRE_SEED_MARK_ID, FIRE_SEED_GAIN, FIRE_SEED_MARK_DATA)
	# 补牌数量；先增加火种，再按当前手牌是否小于5执行固定摸1张。
	var draw_count: int = DRAW_COUNT if owner.hand.size() < DRAW_HAND_THRESHOLD else 0
	announce_activation({"item_id":item_id, "related_event_id":event.event_id if event != null else -1, "fire_seed_count":_get_fire_seed_count(), "draw_count":draw_count})
	if draw_count > 0:
		host.call("draw", owner_player_id, draw_count)


## 跨全局回合时清空四项额度；额外回合拥有新的turn_number并正常获得四项新额度。
func _sync_turn_usage() -> void:
	# 当前全局回合号；无对局状态时保持-1并清空旧数据。
	var current_turn_number: int = host.state.turn_number if host != null and host.get("state") != null else -1
	if _tracked_turn_number == current_turn_number:
		return
	_tracked_turn_number = current_turn_number
	_used_items_this_turn.clear()


## 返回当前“火种”数量；标记不存在时按0处理。
func _get_fire_seed_count() -> int:
	return maxi(int((host.call("get_player_mark", owner_player_id, FIRE_SEED_MARK_ID) as Dictionary).get("count", 0)), 0)
