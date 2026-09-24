extends SkillDefinition

## 【聚寇】技能源码。任意角色在其回合首次造成伤害后可令持有者执行当前轮回节，并以“币”提高永久手牌上限。

## 摸牌效果所在的①轮回节零基索引；固定0对应玩家可见的①。
const DRAW_SECTION_INDEX: int = 0

## 获得“币”效果所在的②轮回节零基索引；固定1对应玩家可见的②。
const COIN_SECTION_INDEX: int = 1

## ①轮回节固定摸牌数；数值1来自技能原文。
const DRAW_COUNT: int = 1

## ②轮回节固定获得的“币”数量；数值1来自“一枚”原文。
const COIN_GAIN_COUNT: int = 1

## “币”公开标记稳定ID；换日与手牌上限联动共用该ID。
const COIN_MARK_ID: String = "bi"

## “币”公开标记首次创建元数据；图标、名称与说明只负责长期可读展示。
const COIN_MARK_DATA: Dictionary = {"icon":"币", "name":"币", "description":"每枚“币”令赛飞儿的手牌上限+1。", "source_skill_id":"jvkou"}

## AI对友方或自身无条件确认聚寇的固定高分；敌方则取相反值并选择取消。
const AI_UNCONDITIONAL_CONFIRM_SCORE: float = 100.0


## 写入轮回技静态信息；技能描述逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"jvkou",
		"name":"聚寇",
		"trigger":"damageAfter",
		"ui_enabled":false,
		"reincarnation":true,
		"reincarnation_section_count":2,
		"reincarnation_has_explicit_sections":true,
		"description":"轮回技，一名角色于其回合内首次造成伤害后，其可令你①摸一张牌；②获得一枚“币”标记。你每有一枚“币”标记，你的手牌上限便+1。",
	})


## 订阅全场伤害后时机；伤害来源本人是本次可选发动的决定者。
func install() -> void:
	subscribe_timing("damageAfter", _on_damage_after, "global")


## 仅在来源角色自己的回合且这是其首次正数伤害时，向来源创建可取消确认请求。
func _on_damage_after(event: RuleEvent) -> void:
	if event == null or event.source_id < 0 or int(event.data.get("amount", 0)) <= 0 or host.state.current_player_id != event.source_id or not can_activate_reincarnation():
		return
	# 本次伤害来源；必须仍存活在场才有权作出发动选择。
	var damage_source: PlayerState = host.state.get_player(event.source_id) as PlayerState
	if damage_source == null or not damage_source.alive or damage_source.out_of_game or not _is_first_damage_of_turn(damage_source, int(event.data.get("damage_event_id", -1))):
		return
	request_card_selection_for_player(event.source_id, "聚寇", "是否发动【聚寇】令赛飞儿执行当前轮回节？", [], 0, 0, true, {"kind":"jvkou_confirm", "damage_source_id":event.source_id, "ai_allow_confirm":true})


## 恢复伤害来源的发动确认；取消不推进轮回节，确认后按最新状态执行并推进。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "jvkou_confirm" or response == null:
		return false
	if not response.confirmed or not begin_reincarnation_activation():
		return true
	# 本次选择者即伤害来源；只用于公开发动上下文与AI身份观察。
	var damage_source_id: int = int(context.get("damage_source_id", -1))
	# 当前轮回节索引；等待选择期间不会自行推进，但仍从权威状态重新读取。
	var section_index: int = get_reincarnation_section_index()
	# 当前轮回数；聚寇效果当前不使用X，仍写入历史便于回放追踪轮回进度。
	var round_count: int = get_reincarnation_round_count()
	if section_index == DRAW_SECTION_INDEX:
		announce_activation({"damage_source_id":damage_source_id, "section_number":section_index + 1, "round_count":round_count, "draw_count":DRAW_COUNT})
		host.call("draw", owner_player_id, DRAW_COUNT)
	elif section_index == COIN_SECTION_INDEX:
		announce_activation({"damage_source_id":damage_source_id, "section_number":section_index + 1, "round_count":round_count, "coin_gain":COIN_GAIN_COUNT})
		host.call("change_player_mark_count", owner_player_id, COIN_MARK_ID, COIN_GAIN_COUNT, COIN_MARK_DATA)
		host.call("add_hand_limit_bonus", owner_player_id, COIN_GAIN_COUNT, get_id())
	complete_reincarnation_activation()
	return true


## 判断当前伤害是否为来源角色本回合第一次实际造成的正数伤害；历史已在damageAfter前写入当前事件。
func _is_first_damage_of_turn(damage_source: PlayerState, current_damage_event_id: int) -> bool:
	# 来源在本回合造成的有效伤害条目数；目标自身保存的受伤记录不会因source_id不同误计。
	var caused_damage_count: int = 0
	for history_entry: Dictionary in damage_source.damage_history:
		if int(history_entry.get("source_id", -1)) == damage_source.player_id and int(history_entry.get("amount", 0)) > 0:
			caused_damage_count += 1
			if caused_damage_count > 1:
				return false
	# 防御性确认唯一条目就是当前伤害；旧格式缺event_id时仍按唯一伤害成立。
	return caused_damage_count == 1 and (current_damage_event_id < 0 or int(damage_source.damage_history[-1].get("event_id", current_damage_event_id)) == current_damage_event_id or damage_source.damage_history.size() == 1)


## AI按伤害来源与赛飞儿的关系决定确认；自身及友方无条件发动，敌方无条件取消。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理聚寇自身的零材料确认。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != "jvkou_confirm":
		return 0.0
	# 选择负载；取消动作保持0分，确认动作按阵营给出绝对优先级。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 本次伤害来源与选择者；自身或对赛飞儿态度为正即视为队友。
	var damage_source_id: int = int(context.get("damage_source_id", -1))
	return AI_UNCONDITIONAL_CONFIRM_SCORE if damage_source_id == owner_player_id or evaluator.get_attitude(authoritative_snapshot, damage_source_id, owner_player_id) > 0.0 else -AI_UNCONDITIONAL_CONFIRM_SCORE
