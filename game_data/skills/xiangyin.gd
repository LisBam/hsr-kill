extends SkillDefinition

## 【祥音】技能源码。限定发动后给予一名尚无赐福的角色公开标记，使其每个全局回合首次使用的【杀】忽略距离。

## “赐福”公开标记稳定ID；所有同名停云共用该ID，因此已经拥有赐福的角色不会再次成为合法目标。
const BLESSING_MARK_ID: String = "cifu"

## “赐福”公开标记显示单字；固定为“赐”，只影响标记徽记正文，不参与规则判断。
const BLESSING_MARK_ICON: String = "赐"

## 赐福影响的卡牌共享组；slash同时覆盖普通、火与雷【杀】，不会影响其他牌。
const BLESSING_CARD_GROUP: String = "slash"

## AI对给予赐福的基础收益；默认3.0表达长期解除首张【杀】距离的战术价值，不改变实际规则。
const AI_BLESSING_BASE_VALUE: float = 3.0

## AI按目标每张手牌追加的潜在【杀】利用价值；默认0.2且受统一上限约束，只影响友方目标排序。
const AI_HAND_VALUE_PER_CARD: float = 0.2

## AI计入赐福潜力的最大手牌数；默认5避免长期标记在大手牌目标上产生无限评分。
const AI_HAND_VALUE_CARD_CAP: int = 5

## 祥音对目标的公开身份行为值；正1表示给予长期有利标记，不改变任何身份或阵营规则。
const IDENTITY_TARGET_RESULT: float = 1.0


## 写入技能静态信息；技能正文逐字保持需求提供的原文。
func _init() -> void:
	super({
		"id":"xiangyin",
		"name":"祥音",
		"trigger":"active",
		"enable":"phaseUse",
		"ui_enabled":true,
		"limited":true,
		"description":"限定技，出牌阶段，你可令一名未拥有“赐福”标记的角色获得“赐福”标记，拥有“赐福”标记的角色于一回合内使用的第一张【杀】无距离限制。",
	})


## 仅在自身出牌阶段、限定额度未用且场上仍有未获得赐福的角色时开放主动入口。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡、离场或限定额度已经消耗时不得继续发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	return owner != null and owner.alive and not owner.out_of_game and has_available_intrinsic_use() \
		and host.state.current_player_id == owner_player_id and host.state.current_phase == "play" \
		and not _get_target_ids().is_empty()


## 发动祥音；动作已经携带唯一目标时直接复核，否则创建统一单目标选择请求。
func activate(context: Dictionary = {}) -> String:
	# 已提交目标数组；本地、AI与网络动作都使用相同稳定玩家ID协议。
	var target_ids: Array[int] = []
	for target_id_variant: Variant in context.get("target_ids", []) as Array:
		target_ids.append(int(target_id_variant))
	if target_ids.size() == 1:
		return "" if _execute_xiangyin(target_ids[0]) else "【祥音】的目标、阶段或限定次数已经失效。"
	request_target_selection("【祥音】请选择获得“赐福”标记的角色", _get_target_ids(), 1, 1, true, {"kind":"xiangyin_target"})
	return ""


## 恢复祥音目标选择；取消不写入标记，也不消耗限定次数。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != "xiangyin_target" or response == null:
		return false
	if response.confirmed and response.target_ids.size() == 1:
		_execute_xiangyin(response.target_ids[0])
	return true


## 最终复核并写入赐福标记；来源角色ID保证停云死亡后通用标记服务能清理其给予全场的赐福。
func _execute_xiangyin(target_id: int) -> bool:
	if not can_activate() or not _get_target_ids().has(target_id):
		return false
	# 赐福公开标记数据；规则字段由公开标记服务规范化并供统一卡牌距离查询读取。
	var mark_data: Dictionary = {
		"icon":BLESSING_MARK_ICON,
		"name":"赐福",
		"description":"拥有“赐福”标记的角色于每个全局回合内使用的第一张【杀】无距离限制。",
		"count":1,
		"source_player_id":owner_player_id,
		"source_skill_id":get_id(),
		"first_use_each_turn_ignore_distance_group":BLESSING_CARD_GROUP,
		"order":0,
	}
	if not bool(host.call("set_player_mark", target_id, BLESSING_MARK_ID, mark_data)):
		return false
	announce_activation({"target_id":target_id})
	observe_identity_behavior([target_id], {"target_result":IDENTITY_TARGET_RESULT})
	return true


## 返回场上全部未拥有赐福的存活角色；“一名角色”允许选择停云自己，不按阵营预先过滤。
func _get_target_ids() -> Array[int]:
	# 合法目标结果；保持权威座次顺序供界面、AI与回放稳定复用。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if player.alive and not player.out_of_game and int((host.call("get_player_mark", player.player_id, BLESSING_MARK_ID) as Dictionary).get("count", 0)) <= 0:
			result.append(player.player_id)
	return result


## 为AI逐一枚举全部合法目标；敌我取舍由同文件评分完成，权威入口仍允许玩家自由选择任何角色。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	for target_id: int in _get_target_ids():
		result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "target_ids":[target_id], "payload":{"skill_id":get_id(), "target_ids":[target_id]}})


## 评估祥音目标；AI只会为正态度友方取得正收益，并在友方手牌较多时略微提高长期首杀距离价值。
func score_ai_action(authoritative_snapshot: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 动作目标；祥音必须且只能选择一名未拥有赐福的角色。
	var target_ids: Array = action.get("target_ids", []) as Array
	if target_ids.size() != 1:
		return -100.0
	# 目标稳定ID；用于读取公开状态和技能持有者对其态度。
	var target_id: int = int(target_ids[0])
	# 目标公开快照；缺失或已离场目标不应获得任何发动收益。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)) or bool(target.get("out_of_game", false)):
		return -100.0
	# 目标态度；正值为友方，负值为敌方，0表示当前不值得消耗限定技。
	var attitude: float = evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id)
	# 手牌潜力；只读取公开数量并限制在0至5张，未知具体牌面不会让AI作弊识别【杀】。
	var hand_potential: float = float(mini(maxi(int(target.get("hand_count", 0)), 0), AI_HAND_VALUE_CARD_CAP)) * AI_HAND_VALUE_PER_CARD
	return attitude / 5.0 * (AI_BLESSING_BASE_VALUE + hand_potential)
