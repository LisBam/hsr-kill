extends SkillDefinition

## 【剑势】技能源码。持有者的【杀】即将造成伤害时可判定，红色结果为当前目标追加1点伤害。

## 红色判定追加的固定伤害值；固定为1，与技能原文一致，运行时无需动态修改。
const DAMAGE_BONUS: int = 1

## AI 对敌方目标确认发动的固定收益；高分保证其不会因可取消询问而放弃，友方目标则返回负分。
const AI_HOSTILE_ACTIVATION_SCORE: float = 100.0

## 红色判定对技能来源与伤害目标的基础 AI 价值绝对值；来源取正、目标取负，供改判定技能按阵营汇总。
const AI_FAVORABLE_RESULT_VALUE: float = 2.0


## 写入触发技能静态信息；玩家可见描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"jianshi",
		"name":"剑势",
		"trigger":"shaDamage",
		"ui_enabled":false,
		"description":"当你使用【杀】造成伤害时，你可进行判定：若判定结果为红色，此伤害+1。",
	})


## 订阅持有者作为【杀】来源的 shaDamage 时机；每个实际目标独立询问并独立判定。
func install() -> void:
	subscribe_timing("shaDamage", _on_sha_damage, "source")


## 在伤害真正扣减前创建可取消发动询问；原【杀】上下文只保存稳定 UID、目标与基础伤害数据。
func _on_sha_damage(event: RuleEvent) -> void:
	if event == null or event.source_id != owner_player_id or int(event.data.get("parent_card_uid", -1)) < 0:
		return
	# 发动上下文；判定选择期间目标或父牌可能变化，最终加值时会再次由核心按 UID 复核。
	var activation_context: Dictionary = {
		"kind":"jianshi_confirm",
		"parent_card_uid":int(event.data.get("parent_card_uid", -1)),
		"target_id":event.target_id,
		"ai_allow_confirm":true,
	}
	request_card_selection("剑势", "是否发动【剑势】进行判定？", [], 0, 0, true, activation_context)


## 恢复发动确认；取消不产生判定，确认后同步或异步进入统一判定请求。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "jianshi_confirm" or response == null:
		return false
	if response.confirmed:
		_begin_judgment(context)
	return true


## 建立剑势判定，并公开红色有利、黑色不利及结果对来源与目标的相反价值。
func _begin_judgment(context: Dictionary) -> void:
	# 当前父牌 UID；用于把判定成功的加值精确写入本张【杀】的当前目标。
	var parent_card_uid: int = int(context.get("parent_card_uid", -1))
	# 当前伤害目标 ID；红色结果对目标不利，对技能持有者有利。
	var target_id: int = int(context.get("target_id", -1))
	announce_activation({"parent_card_uid":parent_card_uid, "target_id":target_id})
	# 异步判定接收者；换将后旧武将代次不会接管尚未完成的剑势结果。
	var continuation: Dictionary = {
		"receiver_type":"skill",
		"skill_owner_id":owner_player_id,
		"skill_id":get_id(),
		"skill_character_generation":get_bound_character_generation(),
		"context":{"kind":"jianshi_judgment", "parent_card_uid":parent_card_uid, "target_id":target_id},
	}
	# 判定 AI 上下文；改判定角色可按阵营计算红色增伤究竟帮助哪一方。
	var judgment_ai_context: Dictionary = {
		"favorable_condition":{"colors":["red"]},
		"unfavorable_condition":{"colors":["black"]},
		"favorable_result_player_values":{str(owner_player_id):AI_FAVORABLE_RESULT_VALUE, str(target_id):-AI_FAVORABLE_RESULT_VALUE},
	}
	# 最终判定牌；没有判定前交互时同步返回，有【戏法】时由 continue_judgment 恢复。
	var judgment_card: CardInstance = host.call("request_judgment", owner_player_id, "【剑势】", continuation, judgment_ai_context) as CardInstance
	if not bool(host.call("has_pending_judgment_request")):
		_apply_judgment_result(parent_card_uid, target_id, judgment_card)


## 恢复曾被判定前技能暂停的剑势结果，并把红色加值写入原【杀】目标。
func continue_judgment(context: Dictionary, judgment_card: CardInstance) -> bool:
	if str(context.get("kind", "")) != "jianshi_judgment":
		return false
	_apply_judgment_result(int(context.get("parent_card_uid", -1)), int(context.get("target_id", -1)), judgment_card)
	return true


## 应用最终判定；只有红色牌成功增加1点本目标伤害，黑色、取消或空结果均不修改数值。
func _apply_judgment_result(parent_card_uid: int, target_id: int, judgment_card: CardInstance) -> void:
	if judgment_card == null or judgment_card.get_color() != "red":
		return
	if bool(host.call("add_card_target_damage_bonus", parent_card_uid, target_id, DAMAGE_BONUS, get_id())):
		host.call("add_log", "【剑势】判定为红色，此【杀】对当前目标的伤害+%d。" % DAMAGE_BONUS)


## AI 仅在目标为敌方时无条件确认发动；友方或关系非敌对目标保留原伤害，不主动增加风险。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理剑势自身的零材料确认动作。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 选择负载；取消动作保持0分，确认动作根据目标阵营返回固定正负值。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if str(context.get("kind", "")) != "jianshi_confirm" or not bool(payload.get("confirmed", false)):
		return 0.0
	# 当前伤害目标；态度为负表示敌方，符合“对敌人无脑发动”的指定逻辑。
	var target_id: int = int(context.get("target_id", -1))
	return AI_HOSTILE_ACTIVATION_SCORE if evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id) < 0.0 else -AI_HOSTILE_ACTIVATION_SCORE
