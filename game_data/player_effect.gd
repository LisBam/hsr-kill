class_name PlayerEffect
extends RefCounted

## 挂在角色身上的持续效果基类。具体效果文件放在 game_data/effects 目录，由内容数据库自动发现。
##
## 存在的理由：有些效果一旦施加就属于**被施加的角色**，不再属于施放它的技能。
## 技能实例会随施放者阵亡、换将、被“非锁定技失效”压制而停止接收时机，
## 而这些状态都不应该撤回已经挂在目标身上的效果，因此需要一个生命周期只看承载角色的载体。
##
## 与 SkillDefinition 的三点关键差异（都是本基类刻意保留的）：
## ①存活判定只看承载角色，不比对武将代次——效果挂在角色身上，换将后仍属于同一名角色；
## ②不检查“非锁定技失效”与获得技能额度——效果不是技能，不受施加者的技能压制状态影响；
## ③订阅所有者是本效果实例，宿主销毁实例时自动释放，不需要挂到技能或卡牌实例表上。

## 承载效果的角色ID；由 bind() 写入，-1 表示尚未绑定到任何角色。
var target_player_id: int = -1

## 规则宿主对象；本项目为 MatchController，效果只通过它读取权威状态并调用公开端口。
var host: Object = null


## 返回效果稳定ID；子类必须覆盖，并与 game_data/effects 目录中的脚本文件名保持一致以便维护定位。
func get_id() -> String:
	return ""


## 返回效果静态元数据；子类可覆盖，供工具链、界面与文档读取；不承载任何运行时状态。
func get_metadata() -> Dictionary:
	return {}


## 绑定规则宿主与承载角色；只写字段、不注册任何时机，因此可安全用于“是否需要重建”的只读探测。
func bind(match_host: Object, effect_target_player_id: int) -> void:
	host = match_host
	target_player_id = effect_target_player_id


## 登记效果运行所需的全部时机；由宿主在创建实例后调用一次。
## 基类先登记“承载者死亡即回收”，再交给子类补充自身订阅；子类不得覆盖本函数，改为覆盖 install_effect()。
func install() -> void:
	subscribe_timing("dieAfter", _handle_target_died, "player")
	install_effect()


## 子类在此登记自身需要的时机与资源；默认空实现，不需要效果时不必覆盖。
func install_effect() -> void:
	pass


## 释放效果占用的资源；由宿主在移除实例前调用。
## 基类先让子类释放自身资源，再统一退订全部时机；子类不得覆盖本函数，改为覆盖 uninstall_effect()。
func uninstall() -> void:
	uninstall_effect()
	unsubscribe_all_timings()


## 子类在此释放自身资源（例如界面提示或外部注册）；默认空实现。
func uninstall_effect() -> void:
	pass


## 统一释放本效果登记的全部时机订阅；重复调用安全，宿主销毁实例前也会调用一次。
func unsubscribe_all_timings() -> void:
	if host == null or host.get("trigger_manager") == null:
		return
	# 当前对局高级触发器；按所有者一次性注销，不依赖逐个保存订阅ID。
	var manager: TriggerManager = host.get("trigger_manager") as TriggerManager
	manager.unsubscribe_owner(self)


## 登记一个标准时机订阅并返回订阅ID。
## role 语义与技能一致：player/source/target 分别对应事件中的同名玩家字段，global 表示全部事件。
## 与技能订阅的关键区别见类注释：承载角色只要仍存活且通过内容条件就接收时机。
func subscribe_timing(event_name: String, callback: Callable, role: String = "target", priority: int = 0, first_do: bool = false, last_do: bool = false, condition: Callable = Callable()) -> int:
	if host == null or host.get("trigger_manager") == null:
		return -1
	if not RuleTimingCatalog.has_timing(event_name):
		return -1
	# 当前对局高级触发器；效果实例自己充当订阅所有者，卸载时由 unsubscribe_all_timings 统一释放。
	var manager: TriggerManager = host.get("trigger_manager") as TriggerManager
	# 统一守卫；把内容条件与本效果自己的承载角色存活校验组合在一起。
	var guarded_condition: Callable = Callable(self, "_can_receive_timing_event").bind(condition)
	return manager.subscribe(event_name, self, callback, priority, target_player_id, role, first_do, last_do, guarded_condition)


## 判断本效果是否仍可接收时机；只要求承载角色存在且存活。
## 刻意不检查离场、不检查技能失效、不检查获得技能额度、不比对武将代次：这些都是“技能”的概念，
## 而效果已经挂在角色身上，只有角色本身的生死才决定它是否还需要继续结算。
func _can_receive_timing_event(event: RuleEvent, custom_condition: Callable) -> bool:
	if host == null or host.get("state") == null:
		return false
	# 承载角色权威状态；角色已被移除或已阵亡时不再接收任何时机。
	var target: PlayerState = host.state.get_player(target_player_id)
	if target == null or not target.alive:
		return false
	return not custom_condition.is_valid() or bool(custom_condition.call(event))


## 判断指定角色身上是否仍有本效果需要继续结算的持久状态。
## 宿主在开局与读档恢复时据此重建实例：返回 true 才会创建新实例，因此子类必须覆盖为纯只读查询。
func has_persisted_state(_player: PlayerState) -> bool:
	return false


## 返回本效果要求承载角色的 AI 在本回合额外消耗手牌的倾向值；默认 0.0 表示完全不改变 AI 决策。
## 存在理由：某些效果的价值取决于“承载者回合结束时会留下多少张手牌”，而这类判断只发生在 AI 决策内部，
## 又不允许把相关隐藏事实写进任何快照（写进去等于让全部观察者都看得到）。
## 因此本钩子只提供**一个标量倾向值**，不泄漏来源、不泄漏具体牌，也从不进入快照或存档；
## 汇总与消费全部发生在规则层与 AI 层，内容层只声明“希望承载者少留牌”这一意图。
## 取值语义：正值为“更愿意打出/弃置手牌”，数值越大越激进；默认值必须是 0.0，保证无效果时 AI 行为逐字不变。
func get_ai_hand_pressure() -> float:
	return 0.0


## 承载者死亡时的子类清理钩子；用于删除自己写入该角色的状态键与界面提示。
## 基类保证它先于实例被宿主移除执行，因此子类不需要关心时机顺序。
func on_target_died() -> void:
	pass


## 统一的承载者死亡回调；先清理状态，再请求宿主移除本实例，避免残留实例在角色复活后继续结算旧数据。
func _handle_target_died(_event: RuleEvent) -> void:
	on_target_died()
	if host != null and host.has_method("remove_player_effect"):
		host.call("remove_player_effect", target_player_id, get_id())
