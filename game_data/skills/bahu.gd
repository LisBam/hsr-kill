extends SkillDefinition

## 【跋扈】技能源码。锁定技：准备阶段摸一张牌；出牌阶段使用【杀】的次数上限+1。


## 写入锁定技静态信息；技能描述必须与主公提供的原文完全一致。
func _init() -> void:
	super({
		"id": "bahu",
		"name": "跋扈",
		"trigger": "phaseZhunbeiBegin",
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，准备阶段，你摸一张牌。你于出牌阶段内使用【杀】的次数上限+1。",
	})


## 订阅持有者准备阶段开始时机；锁定技在时机到达时强制执行摸牌。
func install() -> void:
	subscribe_timing("phaseZhunbeiBegin", _on_phase_zhunbei_begin, "player")


## 准备阶段开始时摸一张牌；锁定技不允许取消。
func _on_phase_zhunbei_begin(_event: RuleEvent) -> void:
	announce_activation({})
	host.call("draw", owner_player_id, 1)


## 出牌阶段使用【杀】的次数上限+1；仅对 slash 牌族生效，不解除距离与目标限制。
func get_play_count_limit_bonus(card_definition: Dictionary) -> int:
	if str(card_definition.get("play_limit_group", "")) == "slash":
		return 1
	return 0
