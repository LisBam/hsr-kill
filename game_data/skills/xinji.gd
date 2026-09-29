extends SkillDefinition

## 【薪继】技能源码。翁法罗斯势力的其他角色本局首次受伤后，由该角色决定是否令领袖获得一枚“火种”，
## 随后领袖令该角色的全部轮回技进入下一个轮回。技能本身不创建主动按钮，只订阅全场伤害完成时机。

## 翁法罗斯势力稳定ID；修改后会改变可触发本技能的角色范围。
const FACTION_ID: String = "wengfaluosi"

## “火种”公开标记稳定ID；与【负火】【轮回】共用同一标记，保证觉醒进度只有一份权威来源。
const FIRE_SEED_MARK_ID: String = "huozhong"

## “火种”公开标记首次创建元数据；文本与【负火】保持一致，避免同一标记在不同来源下说明不同。
## 上限声明只描述【负火】的积累规则，本技能按原文未限定12枚上限，因此不做数量裁剪。
const FIRE_SEED_MARK_DATA: Dictionary = {"icon":"火", "name":"火种", "description":"负火至多积累12枚“火种”；轮回觉醒会移除全部“火种”。", "source_skill_id":"fuhuo"}

## 每次发动固定给予领袖的“火种”数量；数值1来自原文“一枚”。
const FIRE_SEED_GAIN: int = 1

## AI把受伤角色对技能持有者的态度视作队友的最低门槛；严格大于0表示不敌对，对应“队友发动、敌人不发动”。
const AI_FRIENDLY_ATTITUDE_THRESHOLD: float = 0.0

## 队友确认发动时使用的固定正分；只要严格大于通用确认门槛即可，不额外计算火种与轮回收益。
const AI_FRIENDLY_CONFIRM_SCORE: float = 1.0

## 通用“零候选可取消确认”请求的默认基础分；非队友用负值抵消它，使最终评分不越过确认门槛。
const AI_DEFAULT_CONFIRM_SCORE: float = 0.1

## 本局“首次受到伤害”记录在持有者私有形态状态中的键；与【揭质】【轮回】等技能共用同一存储位置。
## 该字段随权威存档往返、不进公开快照，因此读档、复原武将牌或技能重新安装都不会重置本局首次机会。
const TRIGGERED_STATE_KEY: String = "xinji_triggered_player_ids"


## 写入技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id":"xinji",
		"name":"薪继",
		"trigger":"damageAfter",
		"ui_enabled":false,
		"leader_skill":true,
		"description":"领袖技，当一名“翁法罗斯”势力的其他角色首次受到伤害后，其可令你获得一枚“火种”标记，然后你令其所有轮回技进入下一个轮回。",
	})


## 订阅全场伤害完成时机；受伤者必须是“其他角色”，因此使用global角色过滤后在回调内自行复核。
func install() -> void:
	subscribe_timing("damageAfter", _on_damage_after, "global")


## 翁法罗斯势力的其他角色本局首次受到正数伤害后，询问该角色是否发动本技能。
func _on_damage_after(event: RuleEvent) -> void:
	# 受伤角色ID；技能持有者本人受伤由【负火】结算，不属于原文的“其他角色”。
	var victim_id: int = event.target_id if event != null else -1
	if victim_id < 0 or victim_id == owner_player_id:
		return
	# 本次伤害数量；护盾全额吸收、被抵消或零伤害都不构成“受到伤害”。
	if int(event.data.get("amount", 0)) <= 0:
		return
	# “首次”判定；同一角色一旦记录过就不再产生新的询问，无论上次是否实际发动。
	if _get_triggered_ids().has(victim_id):
		return
	# 技能持有者；死亡或离场的领袖不再接收触发时机，也不产生消耗。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 受伤角色；必须存活在场且属于“翁法罗斯”势力才能继续，否则不消耗该角色的首次机会。
	var victim: PlayerState = host.state.get_player(victim_id) as PlayerState
	if victim == null or not victim.alive or victim.out_of_game or not _is_faction_player(victim, FACTION_ID):
		return
	_mark_triggered(victim_id)
	# 选择权在受伤角色手上；它决定是否令领袖获得火种，因此请求的chooser是受伤角色本人。
	request_card_selection_for_player(victim_id, "薪继", "是否发动【薪继】令“薪继”的持有者获得一枚“火种”标记？", [], 0, 0, true, {"kind":"xinji_confirm", "victim_id":victim_id, "ai_allow_confirm":true})


## 读取本局已经消耗“首次受到伤害”机会的角色ID；记录缺失或类型异常时按“尚无记录”处理。
func _get_triggered_ids() -> Array[int]:
	# 技能持有者；实例始终绑定持有者，取不到状态时返回空记录而不报错。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return []
	return _to_int_array(owner.character_form_state.get(TRIGGERED_STATE_KEY, []) as Array)


## 记录该角色已经消耗本局“首次受到伤害”机会；重复调用不产生第二条记录。
func _mark_triggered(player_id: int) -> void:
	# 技能持有者；取不到状态时不写入任何记录。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return
	# 追加后的记录数组；先取副本再整体写回，保持character_form_state只保存纯数据。
	var triggered_ids: Array[int] = _get_triggered_ids()
	if triggered_ids.has(player_id):
		return
	triggered_ids.append(player_id)
	owner.character_form_state[TRIGGERED_STATE_KEY] = triggered_ids


## 把任意数组安全转换为整数ID数组；读档或旧数据可能保存未标注元素类型的数组。
func _to_int_array(source: Array) -> Array[int]:
	# 转换结果；非整数元素按整数语义取值，避免读档数据阻断技能。
	var result: Array[int] = []
	for entry: Variant in source:
		result.append(int(entry))
	return result


## 恢复受伤角色的发动确认；确认后按原文顺序先给予火种，再推进其全部轮回技。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null or str(context.get("kind", "")) != "xinji_confirm":
		return false
	if not response.confirmed:
		return true
	# 受伤角色；等待选择期间可能已经死亡或离场，此时不再产生任何效果。
	var victim_id: int = int(context.get("victim_id", -1))
	var victim: PlayerState = host.state.get_player(victim_id) as PlayerState
	if victim == null or not victim.alive or victim.out_of_game:
		return true
	# 技能持有者；领袖死亡或离场后既不获得火种，也不再推进他人轮回技。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return true
	# 实际发动者是受伤角色；日志与牌面提示必须归属到该角色，而不是被动受益的领袖。
	announce_activation_for_player(victim_id, {"victim_id":victim_id, "fire_seed_gain":FIRE_SEED_GAIN})
	host.call("change_player_mark_count", owner_player_id, FIRE_SEED_MARK_ID, FIRE_SEED_GAIN, FIRE_SEED_MARK_DATA)
	_advance_all_reincarnation_skills(victim_id)
	return true


## 令指定角色的全部轮回技进入下一个轮回；该角色没有登记过轮回技时自然无事发生。
func _advance_all_reincarnation_skills(player_id: int) -> void:
	# 目标角色全部轮回技；经控制器公开端口读取，技能不自行遍历PlayerState内部字典。
	var reincarnation_skill_ids: Array[String] = []
	reincarnation_skill_ids.assign(host.call("list_reincarnation_skill_ids", player_id))
	for skill_id: String in reincarnation_skill_ids:
		host.call("enter_next_reincarnation", player_id, skill_id)


## 判断权威玩家当前武将是否属于指定势力；势力元数据只筛选技能触发者，不替代身份模式阵营。
func _is_faction_player(player: PlayerState, faction_id: String) -> bool:
	if player == null:
		return false
	# 当前武将定义；空武将或未知定义不会被误判为翁法罗斯角色。
	var character: Dictionary = GameDatabase.get_character(player.character_id)
	return str(character.get("faction", "")) == faction_id


## 评估受伤角色的发动确认；与技能持有者为队友时固定发动，敌对或中立时固定取消。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文与动作负载；取消动作保持0分，由通用策略自然选择放弃。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if str(context.get("kind", "")) != "xinji_confirm" or not bool(payload.get("confirmed", false)):
		return 0.0
	# 受伤角色ID；选择者始终是受到伤害的那名翁法罗斯角色。
	var victim_id: int = int(context.get("victim_id", -1))
	if victim_id < 0 or victim_id == owner_player_id:
		return 0.0
	# 受伤角色对技能持有者的态度；正值表示在其视角中领袖属于可协作对象。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, victim_id, owner_player_id)
	if attitude <= AI_FRIENDLY_ATTITUDE_THRESHOLD:
		# 非队友固定不发动；负值抵消通用确认默认分，保证最终评分不为正。
		return -AI_DEFAULT_CONFIRM_SCORE
	return AI_FRIENDLY_CONFIRM_SCORE
