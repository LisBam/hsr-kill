extends SkillDefinition

## 【留白】技能源码。限定技：发动时重置所有其他技能，并在本回合结束时失去全部技能。
## 两段效果分属两个时机：重置立即生效，失去技能按原文推迟到本回合结束。
## “失去”只是一次性移除当时身上的技能，不记录任何名单：之后通过机缘卡等来源新获得的技能照常安装与发动。

## 失去技能时写入日志的原因标识；该文本只用于权威日志，不参与规则判定。
const CLEAR_REASON: String = "留白"

## 待清算回合号；-1 表示尚未登记，其余取值保存登记时的全局回合号。
## 以回合号而非“已登记”布尔量记录，使存档恢复后能拒绝上一回合遗留的过期登记。
var _clear_turn_number: int = -1

## 每复原一项已发动限定技计入的收益值；数值3.0来自停云【光覆】的同类估值口径。
const LIMIT_RESET_VALUE: float = 3.0

## 失去全部技能时的代价系数；每项还持有的技能扣减一分，使AI在收益不足时保持克制。
const SKILL_LOSS_COST: float = 1.0


## 写入主动限定技静态信息；技能正文逐字保持设计原文。
func _init() -> void:
	super({
		"id":"liubai",
		"name":"留白",
		"trigger":["active", "phaseEnd"],
		"enable":"phaseUse",
		"ui_enabled":true,
		"limited":true,
		"description":"限定技，出牌阶段，你可重置所有其他技能。本回合结束时，你失去所有技能。",
	})


## 订阅持有者回合结束阶段；失去技能的第二段效果在该时机执行。
func install() -> void:
	subscribe_timing("phaseEnd", _on_phase_end, "player")


## 仅在自身出牌阶段、限定额度未用且本回合尚未登记清算时开放主动入口。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或限定额度已经消耗时不得继续发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# 限定技额度；由基类统一维护已发动标记，重复发动不消耗额外次数但也不再产生收益。
	if not has_available_intrinsic_use():
		return false
	# 同一回合内不重复登记清算；第二段效果在回合结束时统一执行一次。
	return _clear_turn_number != host.state.turn_number


## 发动第一段效果：立即重置所有其他技能，并登记本回合结束时的失去技能清算。
func activate(_context: Dictionary = {}) -> String:
	if not can_activate():
		return "【留白】当前不满足发动条件。"
	# 重置全部其他技能；排除项为自身稳定ID，避免自身的限定技标记被一并清零而变成可重复发动。
	var reset_count: int = int(host.call("reset_all_other_skills", owner_player_id, get_id()))
	_clear_turn_number = host.state.turn_number
	# 技能正文只承诺“重置”与“失去”，重置数量写入公告供界面与AI复盘，不参与任何规则判定。
	announce_activation({"reset_count":reset_count, "clear_turn_number":_clear_turn_number})
	return ""


## 持有者回合结束阶段：仅执行本回合登记的清算，过期登记直接丢弃。
func _on_phase_end(_event: RuleEvent) -> void:
	if _clear_turn_number != host.state.turn_number:
		return
	# 先清空登记再执行移除：移除过程会卸载本技能实例自身，登记必须先失效以防御重入。
	_clear_turn_number = -1
	host.call("remove_all_skills", owner_player_id, CLEAR_REASON)


## 为AI枚举本技能在出牌阶段的候选动作；重置与失去都是无参数效果，因此只提交一个空负载动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## AI评估留白的发动收益：重置额度带来后续收益，但失去全部技能代价极大，因此只在收益明显时发动。
## AI钩子没有host，只能读取权威快照与估值器；本技能按“重置了多少已消耗额度”估算收益。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	# 持有者快照；缺失时不给分，避免无效动作进入AI候选。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return 0.0
	# 已发动限定技数量；每复原一项限定技都让后续回合多一次强力发动机会。
	var used_limited_count: float = float((owner.get("used_limited_skill_ids", []) as Array).size())
	# 已进入轮回的技数量；轮回进度被重置后需要重新累积，因此计入负向调整。
	var reincarnation_count: float = float((owner.get("reincarnation_skills", {}) as Dictionary).size())
	# 收益扣减失去全部技能的代价；扣除项高于重置收益时AI不会选择发动。
	return LIMIT_RESET_VALUE * used_limited_count - SKILL_LOSS_COST * (reincarnation_count + 1.0)
