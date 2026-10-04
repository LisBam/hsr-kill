extends SkillDefinition

## 【筹码】锁定技：游戏开始时，持有者摸X张牌，其手牌上限+X。X为持有者的体力上限。
##
## 本技能没有可拒绝的分支：开局即触发、效果固定、既无选牌也无选目标，
## 因此实现文件内**不提供任何 AI 钩子**。给没有决策点的技能伪造
## `score_ai_action()` / `score_ai_choice()` 只会留下永不执行的死代码，
## 让后来者误以为存在可选分支。
##
## 幂等性：`gameStart` 在单局中只派发一次，但重开、读档恢复、换将回来
## 以及纯规则测试都可能重复派发同一事件，因此用实例标记保证摸牌与
## 手牌上限加成各自只发生一次，避免效果被叠加。

## 体力上限读取失败时的回退值；与砂金的基础体力上限保持一致，保证效果仍然执行而不是静默丢失。
const DEFAULT_MAX_HP: int = 3
## 每点体力上限折算的手牌上限加成；固定为1，使描述中的「X」同时表示摸牌张数与上限加成，便于统一调整。
const HAND_LIMIT_BONUS_PER_HP: int = 1
## 发动公告中「摸牌张数」的键名；界面与回放直接读取该键显示本次摸牌数量。
const ACTIVATION_DRAW_COUNT_KEY: String = "draw_count"
## 发动公告中「手牌上限加成」的键名；界面与回放直接读取该键显示本局获得的上限增量。
const ACTIVATION_HAND_LIMIT_KEY: String = "hand_limit_bonus"

## 本局是否已经结算过；防止同一 gameStart 被重复派发时摸牌与上限加成被叠加。
var _applied: bool = false


func _init() -> void:
	super({
		"id": "chouma",
		"name": "筹码",
		"trigger": "gameStart",
		"lock": true,
		"ui_enabled": false,
		"description": "锁定技，游戏开始时，你摸X张牌，你的手牌上限+X。（X为你的体力上限）",
	})


func install() -> void:
	# gameStart 的玩家、来源与目标三项 ID 全部为 -1，因此只能以 global 角色监听任意角色开局。
	subscribe_timing("gameStart", _on_game_start, "global")


## 游戏开始时结算一次：先摸X张牌，再让手牌上限+X。
func _on_game_start(_event: RuleEvent) -> void:
	if host == null or _applied:
		return
	# 技能持有者权威状态；无法读取时不结算，也不写入幂等标记，保证后续重复派发仍有结算机会。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return
	_applied = true
	# X 的最终取值；同时作为摸牌张数与上限加成的基数。
	var x: int = _resolve_x(owner)
	# 上限加成的实际数值；与摸牌张数解耦，便于以后把「X」与「上限+X」调成不同量级。
	var hand_limit_bonus: int = x * HAND_LIMIT_BONUS_PER_HP
	# 发动公告；必须先于实际效果上报，使日志与回放的顺序与结算顺序一致。
	announce_activation({ACTIVATION_DRAW_COUNT_KEY:x, ACTIVATION_HAND_LIMIT_KEY:hand_limit_bonus})
	host.call("draw", owner_player_id, x)
	host.call("add_hand_limit_bonus", owner_player_id, hand_limit_bonus, get_id())


## 解析 X：取持有者的体力上限；异常情况下回退到默认值，保证锁定技不会什么都不做。
func _resolve_x(owner: PlayerState) -> int:
	# 持有者当前体力上限；模式加成与换形已经在权威状态中生效，这里读取的是最终值。
	var max_hp: int = int(owner.max_hp)
	if max_hp <= 0:
		return DEFAULT_MAX_HP
	return max_hp
