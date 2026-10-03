extends SkillDefinition

## 【游丝】技能源码。「卡芙卡」的技能之一。
## 第一段：其他角色的回合开始时，持有者可以把一张手牌置于牌堆顶的第一张或第二张（其他角色不可知）。
## 第二段：本回合结束时，若该角色的手牌中仍有那张牌，持有者观看其手牌并获得其一张牌。
##
## 两段之间唯一的状态载体是**权威侧的私有置牌事实**（PlayerState.private_pile_placement，见控制器
## set_private_pile_placement / get_private_pile_placement），不使用技能实例字段：
## 技能实例会在换将、复原武将牌与读档后被重建，实例字段会静默丢失，而本技能的第二段必须跨“回合开始→回合结束”存活。
## 私有事实同时保证“其他角色不可知”：它既不出现在任何观察者快照里，也不写入对局记录与公开表现。
##
## 第一段的位次由玩家/AI 通过 "card_position" 组合选择提交（一张手牌 + 一个位次文本选项），
## 因此复用了项目既有的统一选择协议与位次界面，不引入第二套选择框架。

## 第一段“选择一张手牌与一个牌堆位次”的选择上下文 kind；第二段用独立 kind，避免旧响应进入错误分支。
const PLACEMENT_CHOICE_KIND: String = "yousi_placement"

## 第二段“观看并获得其一张牌”的选择上下文 kind。
const GAIN_CHOICE_KIND: String = "yousi_gain"

## 位次选项的稳定 ID；取自控制器常量，保证界面、AI 与权威校验共用同一份取值。
const PILE_SLOT_TOP: String = MatchController.PILE_SLOT_OPTION_TOP

## 位次选项的第二个稳定 ID：置于牌堆顶第二张。
const PILE_SLOT_SECOND: String = MatchController.PILE_SLOT_OPTION_SECOND

## 取消选项的稳定 ID；取消时不得写入任何私有事实，也不放置任何牌。
const PILE_SLOT_CANCEL: String = MatchController.PILE_SLOT_OPTION_CANCEL

## 位次选项 ID 到牌堆位次的映射键值；权威端口只接受 1 或 2 这两个位次值。
const DRAW_PILE_POSITION_TOP: int = MatchController.DRAW_PILE_POSITION_TOP

## 第二个位次对应的牌堆位次值。
const DRAW_PILE_POSITION_SECOND: int = MatchController.DRAW_PILE_POSITION_SECOND

## 私有置牌事实的键名；全部取自控制器常量，禁止在技能内另起字符串。
const PRIVATE_KEY_CARD_UID: String = MatchController.PRIVATE_PLACEMENT_KEY_CARD_UID

## 私有置牌事实的位次键名。
const PRIVATE_KEY_POSITION: String = MatchController.PRIVATE_PLACEMENT_KEY_POSITION

## 私有置牌事实的回合角色键名；与回合号共同构成跨回合安全匹配条件。
const PRIVATE_KEY_TURN_PLAYER_ID: String = MatchController.PRIVATE_PLACEMENT_KEY_TURN_PLAYER_ID

## 私有置牌事实的回合号键名。
const PRIVATE_KEY_TURN_NUMBER: String = MatchController.PRIVATE_PLACEMENT_KEY_TURN_NUMBER

## 第二段“本回合结束时”的订阅时机；phaseAfter 的 player_id 是唯一权威回合来源。
const TURN_END_TIMING: String = "phaseAfter"

## 第一段“其他角色的回合开始时”的订阅时机；phaseBefore 的 player_id 同样是唯一权威回合来源。
const TURN_START_TIMING: String = "phaseBefore"

## 承载“被【游丝】放置过牌的角色本回合更急于出牌”的持续效果 ID；
## 必须与 game_data/effects/yousi_pressure.gd 的 EFFECT_ID 完全一致。
const PRESSURE_EFFECT_ID: String = "yousi_pressure"

## 第二段必须获得的牌张数与最大张数；原文是“获得其一张牌”，因此两个值都固定为1。
const REQUIRED_GAIN_COUNT: int = 1

## 第一段必须选中且只能选中的手牌张数；只有恰好一张时两个位次选项才可用。
const REQUIRED_PLACEMENT_CARD_COUNT: int = 1

## 无法解析时的回合号哨兵值；与“尚未登记任何回合”保持同一语义。
const NO_TURN: int = -1

## 改判用的延时锦囊卡牌定义 ID：【乐不思蜀】，判定需要红桃才不会跳过出牌阶段。
## 只用于 AI 判断“该放什么花色”，不影响任何规则结算。
const LEBU_DEFINITION_ID: String = "lebu"

## 改判用的延时锦囊卡牌定义 ID：【兵粮寸断】，判定需要梅花才不会跳过摸牌阶段。
const BINGLIANG_DEFINITION_ID: String = "bingliang"

## 【乐不思蜀】判定通过所需的花色；放上这张花色即可让该判定失效。
const SUIT_FOR_LEBU_MITIGATION: String = "heart"

## 【兵粮寸断】判定通过所需的花色。
const SUIT_FOR_BINGLIANG_MITIGATION: String = "club"

## AI 判定“该角色是自己人”的态度下界；与放置牌去救判定区的动机绑定，正态度即视为可救。
const AI_ALLY_ATTITUDE_LOWER_BOUND: float = 0.0

## AI 成功救援队友一次判定时的评分；显著高于“随便放一张低价值牌”的分支，保证在可行时优先救援。
const AI_MITIGATION_SCORE: float = 8.0

## AI 在敌方回放置低价值手牌时的基础评分；取正值，保证“放一张便宜牌”本身是有意愿执行的动作。
## 该值除以“手牌价值折扣”后得到最终分数，因此它同时是这一分支的分数上限。
const AI_ENEMY_TURN_BASE_SCORE: float = 3.0

## AI 放置手牌的“手牌价值折扣系数”；分数按 基础分 / (1 + 价值 × 折扣) 递减。
## 采用除法而不是减法，是为了让这一分支**恒为正**：否则一张很贵的牌会把分数压到取消选项之下，
## 而需求配套 AI 的口径是“可以放一张价值较低的牌”，不是“所有牌都贵时放弃”。
const AI_PLACED_CARD_VALUE_DISCOUNT: float = 1.0

## 第二段选牌时的固定高分；观看后获得一张牌始终是纯收益，不存在需要保留的情形。
const AI_GAIN_SCORE: float = 20.0

## AI 明确拒绝一项非法或不可行提交时的评分；低于全部正常分支。
const AI_REFUSE_SCORE: float = -100.0


## 写入技能静态信息；玩家可见描述严格保持需求提供的原文。
## ui_enabled=false：两段都由时机自动触发，不生成主动发动入口。
func _init() -> void:
	super({
		"id":"yousi",
		"name":"游丝",
		"trigger":"phaseBefore",
		"lock":false,
		"ui_enabled":false,
		"description":"其他角色的回合开始时，你可以将一张手牌置于牌堆顶的第一张或第二张（其他角色不可知）。若如此做，本回合结束时，若其手牌中有此牌，你观看并获得其一张牌。",
	})


## 订阅全部角色的回合开始与回合结束两个时机。
## 两段都必须用 role="global"：原文限定“其他角色”的回合，而“其他”是相对于持有者的判断，
## 无法用 role="player"（那只会匹配持有者自己的回合）表达；实际过滤在回调里用 event.player_id 完成。
func install() -> void:
	subscribe_timing(TURN_START_TIMING, _on_turn_started, "global")
	subscribe_timing(TURN_END_TIMING, _on_turn_finished, "global")


## 其他角色的回合开始时询问是否放置一张手牌；持有者自己回合与不可用状态一律不询问。
## 没有任何手牌时不创建请求：位次请求要求恰好选中一张手牌，无牌时创建只会得到必然取消的空窗口。
func _on_turn_started(event: RuleEvent) -> void:
	# 本回合角色 ID；phaseBefore 的 player_id 是唯一权威回合来源。
	var turn_player_id: int = event.player_id
	if turn_player_id < 0 or turn_player_id == owner_player_id:
		return
	# 技能持有者权威状态；死亡或离场后不再提供第一段，也不放置任何牌。
	var owner: PlayerState = _get_owner()
	if owner == null or not owner.alive or owner.out_of_game or owner.hand.is_empty():
		return
	# 请求上下文；只保存可序列化字段，AI 与延迟提交都据此还原本回合身份。
	var choice_context: Dictionary = {"kind":PLACEMENT_CHOICE_KIND, "turn_player_id":turn_player_id, "turn_number":_get_turn_number()}
	# 组合请求：先选一张手牌，再选位次或取消；界面只显示“牌堆顶第一张/牌堆顶第二张/取消”三个按钮。
	request_hand_card_pile_position("游丝", "你可以将一张手牌置于牌堆顶的第一张或第二张（其他角色不可知）。", true, choice_context)


## 恢复两段请求：第一段执行秘密置牌并登记私有事实，第二段观看并取走目标的一张牌。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	# 当前选择步骤；两段各自独立分支，互不推断。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == PLACEMENT_CHOICE_KIND:
		return _continue_placement(context, response)
	if choice_kind == GAIN_CHOICE_KIND:
		return _continue_gain(context, response)
	return false


## 第一段结算：把选中的手牌秘密置于牌堆指定位置，并登记“其他角色不可知”的私有事实。
## 取消、未选牌、选牌数量不为1、位次非法或在等待期间手牌已离开，全部按不发动处理且不写任何状态。
func _continue_placement(context: Dictionary, response: ChoiceResponse) -> bool:
	if not response.confirmed:
		return true
	# 选中的手牌 UID 列表；位次请求的要求是恰好一张，数量不符说明提交被伪造或已被取消。
	var selected_uids: Array = response.card_ids
	if selected_uids.size() != REQUIRED_PLACEMENT_CARD_COUNT:
		return true
	# 目标牌堆位次；取消选项与未知选项都不放置。
	var position: int = _resolve_pile_position(str(response.control_id))
	if position <= 0:
		return true
	# 技能持有者权威状态；等待期间死亡或离场时不再放置。
	var owner: PlayerState = _get_owner()
	if owner == null or not owner.alive or owner.out_of_game:
		return true
	# 所选实体牌；等待期间已经被使用或弃置时必须整体作废，避免凭空移动不存在的牌。
	var card_uid: int = int(selected_uids[0])
	if owner.find_hand_card(card_uid) == null:
		return true
	# 秘密置牌；走专用端口而不是通用移牌，因此不会触发揭示、公开记录与表现事件。
	if not bool(host.call("place_hand_card_on_draw_pile_top", owner_player_id, card_uid, position)):
		return true
	# 私有事实；回合角色与回合号同时记录，使第二段能精确匹配“这一次放置所服务的那个回合”。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	var turn_number: int = int(context.get("turn_number", NO_TURN))
	host.call("set_private_pile_placement", owner_player_id, card_uid, position, turn_player_id, turn_number)
	# AI 出牌倾向效果；只挂在“本回合角色”身上，并在该回合结束时自行到期。
	# 是否真正生效由 AI 层按“主演是不是本方队友”再判定一次，因此这里无条件安装不会造成无谓打空手牌。
	if turn_player_id >= 0 and host.has_method("install_player_effect"):
		host.call("install_player_effect", turn_player_id, PRESSURE_EFFECT_ID)
	# 发动播报；不携带牌名与位次，公开记录里不会出现“放了哪张牌、放在第几张”。
	announce_activation({})
	return true


## 第二段结算：观看目标的手牌与装备区并取走其中一张。
## 私有事实先清除再结算，保证“一个回合只兑现一次”，也保证等待选牌期间不会残留旧事实。
func _continue_gain(context: Dictionary, response: ChoiceResponse) -> bool:
	# 目标角色 ID；等待期间可能已经阵亡或离场。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	# 技能持有者权威状态；死亡或离场后不再获得任何牌。
	var owner: PlayerState = _get_owner()
	if owner == null or not owner.alive or owner.out_of_game:
		return true
	# 选中的牌 UID 列表；原文是“获得其一张牌”，数量不符时本次不获得。
	var selected_uids: Array = response.card_ids
	if not response.confirmed or selected_uids.size() != REQUIRED_GAIN_COUNT:
		return true
	# 实际取牌；权威端口会重新按 UID 在目标的手牌、装备与判定区定位实体，
	# 因此即使等待期间目标重新排列了手牌，也不会取到另一张牌。
	host.call("take_selected_player_card", owner_player_id, turn_player_id, int(selected_uids[0]))
	return true


## 本回合结束时兑现第二段：只有当私有事实记录的“回合角色 + 回合号”与当前回合同时匹配时才结算。
## 匹配两个字段而不是只匹配回合号：交换座位或额外回合会让回合号与角色错位，只按回合号会误兑现到别人身上。
func _on_turn_finished(event: RuleEvent) -> void:
	if host == null or not host.has_method("get_private_pile_placement"):
		return
	# 当前私有置牌事实；空字典表示没有进行中的【游丝】。
	var placement: Dictionary = host.call("get_private_pile_placement", owner_player_id) as Dictionary
	if placement.is_empty():
		return
	if int(placement.get(PRIVATE_KEY_TURN_PLAYER_ID, -1)) != event.player_id:
		return
	if int(placement.get(PRIVATE_KEY_TURN_NUMBER, NO_TURN)) != _get_turn_number():
		return
	# 私有事实先清除：无论后续是否满足条件，本回合的登记都只兑现一次。
	host.call("clear_private_pile_placement", owner_player_id)
	# 技能持有者权威状态；死亡或离场后不再观看与获得。
	var owner: PlayerState = _get_owner()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 本回合角色状态；阵亡或离场时其区域已经清空，第二段不成立。
	var turn_player: PlayerState = host.state.get_player(event.player_id) as PlayerState
	if turn_player == null or not turn_player.alive or turn_player.out_of_game:
		return
	# 那张牌是否仍在对方手牌中；已经打出、弃置或被移动时第二段整体不触发。
	var placed_card_uid: int = int(placement.get(PRIVATE_KEY_CARD_UID, -1))
	if placed_card_uid < 0 or turn_player.find_hand_card(placed_card_uid) == null:
		return
	# 候选：完整手牌牌面 + 装备区，**不含判定区**。
	# 需求的操作口径是“获得其一张牌”，而判定区的延时锦囊不属于该角色拥有的牌，把它列进候选会与描述不符。
	var candidates: Array[Dictionary] = host.call("get_private_hand_and_equipment_candidates", owner_player_id, event.player_id) as Array[Dictionary]
	if candidates.is_empty():
		return
	# 第二段的选择上下文；保存目标与触发来源牌，供 AI 评分与延迟提交恢复。
	var choice_context: Dictionary = {"kind":GAIN_CHOICE_KIND, "turn_player_id":event.player_id, "placed_card_uid":placed_card_uid}
	request_card_selection("游丝", "本回合结束时，若其手牌中有此牌，你观看并获得其一张牌。", candidates, REQUIRED_GAIN_COUNT, REQUIRED_GAIN_COUNT, false, choice_context)


## 把位次选项 ID 换算为权威位次值；取消与未知选项一律返回0，表示不放置。
func _resolve_pile_position(option_id: String) -> int:
	if option_id == PILE_SLOT_TOP:
		return DRAW_PILE_POSITION_TOP
	if option_id == PILE_SLOT_SECOND:
		return DRAW_PILE_POSITION_SECOND
	return 0


## 评估两段请求的 AI 动作价值。
## 第一段按需求配套 AI 口径分两种情形：① 本回合角色的判定区有可被改判的延时锦囊且它是自己人时，
## 优先放上能让该判定失效的花色并置于牌堆顶第一张；② 其他情况下放置价值最低的手牌，
## 两个位次在这一点上是等价的（都只是“随便放到顶上两位之一”），因此给出完全相同的分数，由既有枚举顺序决定。
## 第二段是无条件的纯收益，因此所有合法选牌选项同分。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；用于区分两段并读取本回合角色。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	# 标准选择负载；确认状态、已选牌与已选文字选项均从该字典取得。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	# 当前选择步骤；只处理本技能的两段请求。
	var choice_kind: String = str(context.get("kind", ""))
	if choice_kind == PLACEMENT_CHOICE_KIND:
		return _score_placement_choice(authoritative_snapshot, context, payload, evaluator)
	if choice_kind == GAIN_CHOICE_KIND:
		return AI_GAIN_SCORE if bool(payload.get("confirmed", false)) else 0.0
	return 0.0


## 评分第一段的“一张手牌 + 一个位次”组合；取消保持中性0分，非法组合明确拒绝。
func _score_placement_choice(authoritative_snapshot: Dictionary, context: Dictionary, payload: Dictionary, evaluator: Object) -> float:
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选手牌列表；必须恰好一张，否则本次提交不合法。
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_cards.size() != REQUIRED_PLACEMENT_CARD_COUNT:
		return AI_REFUSE_SCORE
	# 已选位次；取消不能以“已确认”的形式提交。
	var option_id: String = str(payload.get("selected_control_id", ""))
	if _resolve_pile_position(option_id) <= 0:
		return AI_REFUSE_SCORE
	# 本回合角色 ID；上下文中的稳定值，不依赖当前操作者推断。
	var turn_player_id: int = int(context.get("turn_player_id", -1))
	# 当前手牌快照；用于读取花色与保留价值，AI 自身手牌始终可见。
	var card_uid: int = int(selected_cards[0])
	var card_data: Dictionary = evaluator.get_owned_card_by_uid(authoritative_snapshot, owner_player_id, card_uid)
	if card_data.is_empty():
		return AI_REFUSE_SCORE
	# 需要改判的花色；空字符串表示本回合角色不需要救援，进入“放低价值牌”分支。
	var mitigation_suit: String = _resolve_mitigation_suit(authoritative_snapshot, turn_player_id, evaluator)
	if not mitigation_suit.is_empty():
		# 救援分支严格要求花色匹配且置于牌堆顶第一张：判定阶段摸到的第一张牌就是牌堆顶第一张。
		if str(card_data.get("suit", "")) != mitigation_suit:
			return AI_REFUSE_SCORE
		if _resolve_pile_position(option_id) != DRAW_PILE_POSITION_TOP:
			return AI_REFUSE_SCORE
		return AI_MITIGATION_SCORE
	# 非救援分支：手牌越便宜分数越高；两个位次同分，由既有合法动作枚举顺序决定最终提交。
	# 需求配套 AI 原文是“随机放第一或第二张”，但 AI 评分必须是确定性的（否则回放不可复现），
	# 因此这里把两个位次视为完全等价，随机性交给既有枚举顺序，不在这里引入新的随机源。
	return AI_ENEMY_TURN_BASE_SCORE / (1.0 + evaluator.get_owned_card_value_by_uid(authoritative_snapshot, owner_player_id, card_uid) * AI_PLACED_CARD_VALUE_DISCOUNT)


## 解析“本回合角色是否需要被救援”以及需要放上的花色；不需要救援时返回空字符串。
## 判定顺序按“后来居上”：判定区数组是**置入顺序**，而最先被判定的是**最后置入**的那张延时锦囊；
## 牌堆顶第一张只能改写最先被判定的那张，因此这里只读取数组末项，不遍历。
## 只识别两种会跳过阶段的延时锦囊：【乐不思蜀】需要红桃、【兵粮寸断】需要梅花。
func _resolve_mitigation_suit(authoritative_snapshot: Dictionary, turn_player_id: int, evaluator: Object) -> String:
	if turn_player_id < 0:
		return ""
	# 本回合角色公开快照；缺失时不执行任何救援判断。
	var turn_player: Dictionary = evaluator.get_player(authoritative_snapshot, turn_player_id)
	if turn_player.is_empty():
		return ""
	# 只有自己人才值得花一张关键花色的手牌去救；敌方的判定失效不构成本方收益。
	if evaluator.get_attitude(authoritative_snapshot, owner_player_id, turn_player_id) <= AI_ALLY_ATTITUDE_LOWER_BOUND:
		return ""
	# 判定区数组；顺序为置入顺序，最先被判定的是最后一项。
	var judgment_area: Array = turn_player.get("judgment_area", []) as Array
	if judgment_area.is_empty():
		return ""
	# 最先被判定的延时锦囊公开快照；只看定义 ID，不读取任何隐藏信息。
	var judgment_card: Dictionary = judgment_area[judgment_area.size() - 1] as Dictionary
	# 当前延时锦囊定义 ID。
	var definition_id: String = str(judgment_card.get("definition_id", ""))
	if definition_id == LEBU_DEFINITION_ID:
		return SUIT_FOR_LEBU_MITIGATION
	if definition_id == BINGLIANG_DEFINITION_ID:
		return SUIT_FOR_BINGLIANG_MITIGATION
	# 最先被判定的不是这两种牌时，牌堆顶第一张无法改变它的结果，救援目标就不再成立。
	return ""


## 返回技能持有者的权威状态；未绑定权威端口或角色不存在时返回null。
func _get_owner() -> PlayerState:
	if host == null or host.get("state") == null:
		return null
	return host.state.get_player(owner_player_id)


## 返回当前全局回合号；未开始对局时回退 NO_TURN，与项目既有技能口径一致。
func _get_turn_number() -> int:
	if host == null or host.get("state") == null:
		return NO_TURN
	return int(host.state.turn_number)
