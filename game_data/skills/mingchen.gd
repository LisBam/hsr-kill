extends SkillDefinition

## 【冥谶】技能源码。持有者失去最后的手牌后必须选择一名角色获得最顶上的【无中生有】，非本人目标随后对自己造成雷属性伤害。

## 技能检索的固定卡牌定义ID；牌堆缺失时由通用接口继续从弃牌堆顶向下查找。
const DRAW_TRICK_DEFINITION_ID: String = "wuzhong"

## 非本人目标对自己造成的雷属性伤害值；固定1点。
const SELF_THUNDER_DAMAGE_AMOUNT: int = 1


## 写入技能静态信息；锁定技元数据阻止界面与AI把效果当作可取消行为。
func _init() -> void:
	super({
		"id": "mingchen",
		"name": "冥谶",
		"trigger": "loseAfter",
		"ui_enabled": false,
		"lock": true,
		"description": "锁定技，当你失去最后的手牌后，你令一名角色从牌堆或弃牌堆中获得一张【无中生有】。若该角色不为你，你令其对其造成1点雷属性伤害。",
	})


## 订阅持有者失去牌后时机；只处理来源为普通手牌区且结算后手牌数为0的移动。
func install() -> void:
	subscribe_timing("loseAfter", _on_owner_lose_after, "player")


## 失去最后手牌后创建不可取消的目标选择；装备、判定区与木牛“粮”离区不会触发。
func _on_owner_lose_after(event: RuleEvent) -> void:
	# 技能持有者状态；必须仍存活在场且普通手牌已经归零。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game or str(event.data.get("from_zone", "")) != "hand" or not owner.hand.is_empty():
		return
	# 可选目标；锁定技仍需由持有者选择效果角色，但不能取消。
	var target_ids: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game:
			target_ids.append(player.player_id)
	if not target_ids.is_empty():
		request_target_selection("【冥谶】请选择一名角色", target_ids, 1, 1, false, {"kind":"mingchen_target"})


## 恢复冥谶目标并依次执行获得牌与非本人自伤；牌堆和弃牌堆均缺牌时后续伤害仍按原文结算。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "mingchen_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == 1:
		# 最终目标；等待期间阵亡或离场时整个当前目标效果失效。
		var target_id: int = response.target_ids[0]
		# 最终目标状态；用于恢复时再次复核存活与在场条件。
		var target: PlayerState = host.state.get_player(target_id)
		if target == null or not target.alive or target.out_of_game:
			return true
		announce_activation({"target_id":target_id})
		host.call("gain_top_named_card_from_draw_or_discard", target_id, DRAW_TRICK_DEFINITION_ID, get_id())
		if target_id != owner_player_id:
			get_skill_player(target_id).damage(SELF_THUNDER_DAMAGE_AMOUNT, get_skill_player(target_id), "thunder")
			observe_identity_behavior([target_id], {"target_result":-0.5, "damage":true, "thunder_damage":true, "nature_damage":true})
	return true


## 评估冥谶目标；通常优先自己获得资源，能够令敌方进入濒死时显著提高非本人目标收益。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 选择请求上下文；仅处理冥谶创建的强制目标请求。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "mingchen_target":
		return 0.0
	# 唯一目标；锁定选择没有取消动作。
	var targets: Array = (action.get("payload", {}) as Dictionary).get("selected_target_ids", []) as Array
	if targets.size() != 1:
		return -20.0
	# 唯一目标稳定ID；选择自己时使用固定优先分。
	var target_id: int = int(targets[0])
	if target_id == owner_player_id:
		return 6.0
	# 给牌收益与自伤收益方向相反；目标越敌对、体力越低，自伤越有价值。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 目标公开快照；体力与横置状态用于濒死和连环修正。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	# 综合目标评分；给牌按0.45态度、伤害按反向0.65态度计算。
	var score: float = attitude * 0.45 - attitude * 0.65
	if int(target.get("hp", 0)) <= SELF_THUNDER_DAMAGE_AMOUNT and attitude < 0.0:
		score += 8.0
	# 横置目标的雷伤会计入连环风险；敌方连环结构提高进攻价值，友方连环结构降低选择价值。
	if bool(target.get("chained", false)):
		score -= attitude * 0.35
	return score
