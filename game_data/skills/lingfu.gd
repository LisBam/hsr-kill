extends SkillDefinition

## 【灵赋】技能源码。出牌阶段限一次：重铸一张手牌，然后令一名角色获得技能“梅绽”；
## 若其已拥有“梅绽”，则改为令其增加1点体力上限并回复1点体力，然后阮梅失去本技能。
##
## 两条次数限制**同时成立**，缺一不可：
## ① “出牌阶段限一次”——每个出牌阶段至多发动一次，记录在实例字段 `_used_this_play_phase`，phaseUseBegin 时复原；
## ② “每种类别限一次”——**整局游戏**内 basic / trick / equipment 各自至多被重铸一次，
##    记录在持有者的 `character_form_state` 中；项目不会在读档、复原武将牌或换将时清空该字段，
##    因此分支二令阮梅失去本技能后，即使重新获得【灵赋】也不会复活额度。
##
## 由此整局最多发动 3 次，分布在最多 3 个出牌阶段。这是唯一能同时满足两条限制的解释：
## 若“出牌阶段限一次”是唯一限制，“每种类别限一次”的全局约束永远不会被触达，原文的注意条款就没有意义。
##
## 操作顺序（用户明确要求）：一次交互内同时选择一张牌与一个目标，按下确定后**先重铸**，然后才触发后续效果。
## 该顺序由 defer_settlement 保证：重铸的补摸登记在 `_rule_continuations` 上，
## 而结算管线先排空 `_rule_continuations` 再回调 `continue_settlement`。

## 本技能稳定ID；授予与失去都按该 ID 判定。
const LINGFU_SKILL_ID: String = "lingfu"

## 被授予 / 被检查的目标技能稳定ID。
const MEIZHAN_SKILL_ID: String = "meizhan"

## 组合选择请求的业务键；continue_selection 按它分流。
const CHOICE_KIND: String = "lingfu_grant_target"

## 续结算业务键；重铸完成后按它恢复后续效果。
const SETTLEMENT_KIND: String = "lingfu_after_recast"

## 全局限次记录在 PlayerState.character_form_state 中的稳定键名；值类型为 Array[String]。
const USED_CATEGORIES_KEY: String = "lingfu_used_card_categories"

## 三种牌类别；与 CardDefinition 的 type 取值一一对应，也是“每种类别限一次”的全部取值范围。
const CARD_CATEGORIES: Array[String] = ["basic", "trick", "equipment"]

## 分支二增加的体力上限点数；修改后必须同步技能描述与玩法数值文档。
const MAX_HP_GAIN: int = 1

## 分支二回复的体力点数；修改后必须同步技能描述与玩法数值文档。
const RECOVER_AMOUNT: int = 1

## 授予技能时写入 acquired_skills 的来源标识；只用于来源追溯，失去技能时不按它区分。
const GRANT_SOURCE: String = "lingfu"

## 重铸一张牌的机会成本系数；沿用【连戏】的既有口径，使不同重铸技能的 AI 代价可比。
const AI_RECAST_COST_RATIO: float = 0.35

## 给一名队友授予“梅绽”的基础收益；按两张牌的资源价值计价（获得一项可持续摸牌的卖血能力）。
const AI_GRANT_ALLY_VALUE: float = NonameAIEvaluator.CARD_RESOURCE_VALUE * 2.0

## 对敌方或身份未暴露目标发动分支一的惩罚分；白送技能给对手必须严格为负。
const AI_HOSTILE_GRANT_PENALTY: float = -2.0

## 对敌方或身份未暴露目标发动分支二的额外惩罚分；在“对手获得等量体力资源”之上再扣一层。
const AI_HOSTILE_UPGRADE_PENALTY: float = -2.0

## 自身失去【灵赋】的代价；与【留白】的 SKILL_LOSS_COST 口径一致，避免 AI 为一点体力无脑自弃技能。
const AI_SKILL_LOSS_COST: float = 1.0

## 选择动作缺少唯一目标或唯一材料时的评分；必须远低于取消动作的 0 分。
const AI_INVALID_CHOICE_SCORE: float = -10.0

## 本技能此刻不可能产生收益时的动作评分（没有任何队友可作为目标）；
## 必须严格为负，否则会与“结束出牌阶段”的 0 分打平而让 AI 白发动一次。
const AI_UNPAYABLE_ACTION_SCORE: float = -100.0

## 当前出牌阶段是否已经发动过；phaseUseBegin 时置回 false，因此额外出牌阶段同样恢复一次额度。
var _used_this_play_phase: bool = false


## 写入主动技能静态信息；技能描述必须与武将面板展示原文完全一致。
func _init() -> void:
	super({
		"id": LINGFU_SKILL_ID,
		"name": "灵赋",
		"trigger": "active",
		"enable": "phaseUse",
		"ui_enabled": true,
		"description": "出牌阶段限一次，你可以重铸一张手牌（每种类别限一次），然后令一名角色获得技能“梅绽”。若其已拥有技能“梅绽”，则改为令其增加1点体力上限并回复1点体力，然后你失去此技能。",
	})


## 订阅自身每个出牌阶段的开始时机；“出牌阶段限一次”的额度在这里复原，额外出牌阶段同样复原。
func install() -> void:
	subscribe_timing("phaseUseBegin", _on_phase_use_begin, "player")


## 复原本阶段的发动额度；“每种类别限一次”是整局额度，不在此处恢复。
func _on_phase_use_begin(_event: RuleEvent) -> void:
	_used_this_play_phase = false


## 返回本局已被【灵赋】重铸过的牌类别集合；字段缺失或类型异常时按空集合处理，避免旧存档阻断技能。
func _get_used_categories() -> Array[String]:
	# 技能持有者；实例始终绑定持有者，取不到状态时按空集合处理。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return []
	return _to_string_array(owner.character_form_state.get(USED_CATEGORIES_KEY, []) as Array)


## 把一个牌类别写入全局已用集合；重复写入不产生第二条记录。
func _mark_used_category(category: String) -> void:
	# 技能持有者；取不到状态时不写入任何记录。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or category.is_empty():
		return
	# 追加后的类别数组；先取副本再整体写回，保持 character_form_state 只保存纯数据。
	var used_categories: Array[String] = _get_used_categories()
	if used_categories.has(category):
		return
	used_categories.append(category)
	owner.character_form_state[USED_CATEGORIES_KEY] = used_categories


## 把任意数组安全转换为字符串数组；读档或旧数据可能保存未标注元素类型的数组。
func _to_string_array(source: Array) -> Array[String]:
	# 转换结果；非字符串元素按字符串语义取值，避免异常写入阻断技能。
	var result: Array[String] = []
	for entry: Variant in source:
		result.append(str(entry))
	return result


## 返回指定牌名所属的牌类别；取不到定义时返回空字符串，调用方按“不可重铸”处理。
func _get_card_category(definition_id: String) -> String:
	return str(GameDatabase.get_card(definition_id).get("type", ""))


## 判断指定牌名此刻是否仍有全局类别额度；这是候选枚举与提交复核共用的唯一额度判定入口。
func _has_category_quota(definition_id: String) -> bool:
	# 当前牌类别；不属于三种可重铸类别时直接拒绝。
	var category: String = _get_card_category(definition_id)
	if not CARD_CATEGORIES.has(category):
		return false
	return not _get_used_categories().has(category)


## 返回本次仍可重铸的普通手牌候选；已用尽额度的类别整体不出现在候选里，因此 AI 无需再判额度。
func _get_recast_candidates() -> Array[Dictionary]:
	# 全部普通手牌候选；由控制器统一序列化，界面、AI 与网络使用同一份牌面数据。
	var candidates: Array[Dictionary] = host.call("get_hand_candidates", owner_player_id, owner_player_id) as Array[Dictionary]
	# 过滤后的候选；保持原手牌顺序，使界面列表顺序与手牌完全一致。
	var result: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		# 当前候选的稳定牌名ID；类别额度已用尽时不进入候选。
		var definition_id: String = str((candidate.get("card_data", {}) as Dictionary).get("definition_id", ""))
		if _has_category_quota(definition_id):
			result.append(candidate)
	return result


## 返回本次可指定的目标；原文“一名角色”按项目既有口径**包含自己**（【升变】同样允许选择自己）。
## 阮梅自己固有拥有“梅绽”，因此以自己为目标时必然进入分支二。
func _get_target_ids() -> Array[int]:
	# 目标ID列表；按座次顺序收集，保证界面与 AI 的候选顺序一致。
	var result: Array[int] = []
	for player: PlayerState in host.state.players:
		if not player.alive or player.out_of_game:
			continue
		result.append(player.player_id)
	return result


## 仅在自身出牌阶段、本阶段未发动、且同时存在可用材料与合法目标时开放技能按钮。
func can_activate(_context: Dictionary = {}) -> bool:
	# 技能持有者；死亡或离场时不能发动。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return false
	# 只能在自己的出牌阶段发动；其他阶段与别人的回合都不开放。
	if host.state.current_player_id != owner_player_id or host.state.current_phase != "play":
		return false
	# “出牌阶段限一次”；额外出牌阶段由 phaseUseBegin 复原。
	if _used_this_play_phase:
		return false
	# 没有仍可重铸的类别或没有任何目标时不点亮按钮，也不创建空窗口。
	return not _get_recast_candidates().is_empty() and not _get_target_ids().is_empty()


## 创建“选一张手牌 + 选一名角色”的一次性组合请求；确定后由 continue_selection 统一支付费用。
func activate(_context: Dictionary = {}) -> String:
	request_card_target_selection("灵赋", "请选择一张手牌与一名角色；确定后先重铸该牌，再结算后续效果", _get_recast_candidates(), _get_target_ids(), 1, 1, 1, 1, true, {"kind":CHOICE_KIND})
	return ""


## 恢复组合选择：先复核目标与材料，再重铸，最后登记后续效果。
func continue_selection(context: Dictionary, response: ChoiceResponse) -> bool:
	if str(context.get("kind", "")) != CHOICE_KIND or response == null:
		return false
	# 取消或数量不符：不消耗任何额度，直接结束本次发动。
	if not response.confirmed or response.target_ids.size() != 1 or response.card_ids.size() != 1:
		return true
	# 目标复核；等待期间死亡或离场时本次发动作废，不消耗额度也不重铸。
	var target: PlayerState = host.state.get_player(response.target_ids[0]) as PlayerState
	if target == null or not target.alive or target.out_of_game:
		return true
	# 材料复核；必须仍是本人普通手牌区中的牌，且其类别仍有全局额度。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null:
		return true
	# 被选中的费用牌；木牛“粮”、装备与判定牌都不会被 find_hand_card 返回。
	var cost_card: CardInstance = owner.find_hand_card(response.card_ids[0])
	if cost_card == null or not _has_category_quota(cost_card.definition_id):
		return true
	# 先重铸；返回 false（牌已离手等）表示费用未支付，此时不记账也不进入后续效果。
	if not bool(host.call("recast_hand_card", owner_player_id, cost_card.uid)):
		return true
	# 记账时机严格在重铸成功之后：全局类别额度只被真实发生的重铸消耗。
	_mark_used_category(_get_card_category(cost_card.definition_id))
	_used_this_play_phase = true
	announce_activation({"target_id":target.player_id, "recast_definition_id":cost_card.definition_id})
	# 后续效果登记到延后结算队列：重铸的补摸属于规则续接，结算管线先排空它再回调 continue_settlement，
	# 因此“先重铸（含补摸）、后授予技能或升级”这一顺序得到严格保证。
	if defer_settlement({"kind":SETTLEMENT_KIND, "target_id":target.player_id}):
		return true
	# 兜底：登记失败（技能代次失效等）时同步执行后续效果，保证效果不丢失。
	_resolve_grant(target.player_id)
	return true


## 恢复重铸完成后的后续效果；上下文只携带稳定目标ID。
func continue_settlement(context: Dictionary) -> bool:
	if str(context.get("kind", "")) != SETTLEMENT_KIND:
		return false
	_resolve_grant(int(context.get("target_id", -1)))
	return true


## 兑现后续效果：目标没有“梅绽”则授予；已拥有则升级其体力并令阮梅失去本技能。
func _resolve_grant(target_id: int) -> void:
	# 目标复核；等待期间死亡或离场时后续效果不再兑现。
	var target: PlayerState = host.state.get_player(target_id) as PlayerState
	if target == null or not target.alive or target.out_of_game:
		return
	# 拥有判定走项目唯一入口：被【留白】类效果剥夺过“梅绽”的角色会重新走授予分支，与原文一致。
	if bool(host.call("has_skill", target_id, MEIZHAN_SKILL_ID)):
		# 分支二：严格按原文顺序——先增加体力上限，再回复体力，最后阮梅失去本技能。
		# change_max_hp 的 delta 为正不会触发濒死，recover 也不会超过上限。
		host.call("change_max_hp", target_id, MAX_HP_GAIN, owner_player_id, LINGFU_SKILL_ID)
		host.call("recover", owner_player_id, target_id, RECOVER_AMOUNT, LINGFU_SKILL_ID)
		host.call("remove_skill", owner_player_id, LINGFU_SKILL_ID, LINGFU_SKILL_ID)
		return
	# 分支一：永久授予，无次数限制也无回合限制；端口自身拒绝重复授予，因此无需处理返回值。
	host.call("grant_acquired_skill", target_id, MEIZHAN_SKILL_ID, 0, 0, GRANT_SOURCE)


## 为 AI 枚举本技能在出牌阶段的候选动作；无参数效果，因此只提交一个空负载动作。
func append_play_phase_actions(result: Array[Dictionary]) -> void:
	if not can_activate():
		return
	result.append({"action_type":"use_skill", "actor_id":owner_player_id, "skill_id":get_id(), "payload":{"skill_id":get_id()}})


## 返回本次重铸的机会成本；取“AI 实际会选中的最低价值候选”折算。
## 动作层与选择层共用本函数与同一系数，避免出现“提议发动后立刻取消”的死循环（【天坠】的既有教训）。
func _get_recast_cost_value(authoritative_snapshot: Dictionary, evaluator: Object) -> float:
	# 可用候选的保留价值；为空表示没有任何可重铸的牌。
	var candidate_values: Array[float] = _get_ai_candidate_values(authoritative_snapshot, evaluator)
	if candidate_values.is_empty():
		return 0.0
	# 最低保留价值；AI 在多个候选中总是选择价值最低的那张。
	var lowest_value: float = candidate_values[0]
	for value: float in candidate_values:
		lowest_value = minf(lowest_value, value)
	return lowest_value * AI_RECAST_COST_RATIO


## 收集 AI 视角下仍可重铸的候选牌保留价值。
## 额度判定与规则段共用同一常量与同一字段名，因此 AI 不会另建第二套“哪些类别还能重铸”的判断。
func _get_ai_candidate_values(authoritative_snapshot: Dictionary, evaluator: Object) -> Array[float]:
	# 持有者快照；缺失时表示没有可用材料。
	var owner: Dictionary = evaluator.get_player(authoritative_snapshot, owner_player_id)
	if owner.is_empty():
		return []
	# 已用类别集合；字段缺失或类型异常时按空集合处理，与规则段读取口径完全一致。
	var used_categories: Array[String] = _to_string_array(owner.get(USED_CATEGORIES_KEY, []) as Array)
	# 候选保留价值；按手牌顺序收集。
	var values: Array[float] = []
	for card_variant: Variant in owner.get("hand", []) as Array:
		# 当前手牌快照；本人手牌对本人可见，因此定义ID一定可读。
		var card: Dictionary = card_variant as Dictionary
		# 当前牌名ID与类别；只保留仍在全局额度内的三种类别。
		var definition_id: String = str(card.get("definition_id", ""))
		var category: String = _get_card_category(definition_id)
		if not CARD_CATEGORIES.has(category) or used_categories.has(category):
			continue
		values.append(float(evaluator.get_card_value_by_id(definition_id, authoritative_snapshot, owner_player_id)))
	return values


## 按用户给定的三级优先选出【灵赋】的最佳目标；没有合法目标时返回 -1。
## 一级：优先对“还没有梅绽的队友”发动（授予技能）。
## 二级：队友都已拥有梅绽时，优先对“有卖血技能的队友”发动（升级分支）。
## 三级：没有卖血技能队友、或有多个时，对体力值最低的使用。
func _pick_ai_target(authoritative_snapshot: Dictionary, evaluator: Object) -> int:
	# 还没有“梅绽”的队友；一级优先池。
	var grant_ids: Array[int] = []
	# 已拥有“梅绽”的队友；二级与三级优先池。
	var upgrade_ids: Array[int] = []
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；死亡或离场者不参与。
		var player: Dictionary = player_variant as Dictionary
		if not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		# 候选玩家ID；用于后续按体力排序。
		var player_id: int = int(player.get("player_id", -1))
		if player_id < 0:
			continue
		# 队友判定：自己永远计入我方，其余按公开态度判定，避免未卜先知。
		var is_ally: bool = player_id == owner_player_id or float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, player_id)) > 0.0
		if not is_ally:
			continue
		if snapshot_has_skill(player, MEIZHAN_SKILL_ID):
			upgrade_ids.append(player_id)
		else:
			grant_ids.append(player_id)
	# 一级优先：还没有“梅绽”的队友。池内所有目标的授予收益完全相同（都是同一项能力），
	# 因此由 _pick_best_target 的同分规则决定，最终落到“体力值最低者”。
	if not grant_ids.is_empty():
		return _pick_best_target(authoritative_snapshot, grant_ids, evaluator)
	return _pick_upgrade_target(authoritative_snapshot, upgrade_ids, evaluator)


## 从“已拥有梅绽的队友”中按二级 / 三级优先选出一名。
func _pick_upgrade_target(authoritative_snapshot: Dictionary, upgrade_ids: Array[int], evaluator: Object) -> int:
	if upgrade_ids.is_empty():
		return -1
	# 其中“有卖血技能”的队友；判定复用既有 sell_blood_value 元数据，不写技能ID白名单。
	#
	# 说明：由于“梅绽”自身就是一项卖血技能（sell_blood_value = 1.0），进入本池的候选必然全部满足该条件，
	# 因此这一层筛选在【灵赋】的实际局面上不会进一步区分候选，最终由 _pick_best_target 的同分规则
	# 落到“体力值最低者”——这正是原文对“有多个”情形给出的处置。
	var sell_blood_ids: Array[int] = []
	for player_id: int in upgrade_ids:
		# 当前候选快照；卖血价值直接读取权威元数据，自动覆盖【百折】与本次新增的【梅绽】。
		var player: Dictionary = evaluator.get_player(authoritative_snapshot, player_id)
		if float(evaluator.get_snapshot_sell_blood_value(player)) > 0.0:
			sell_blood_ids.append(player_id)
	# 没有卖血技能候选时退回完整池，保证“一个都不满足”也不会漏掉可发动目标。
	var pool: Array[int] = sell_blood_ids if not sell_blood_ids.is_empty() else upgrade_ids
	return _pick_best_target(authoritative_snapshot, pool, evaluator)


## 从给定池中选出**毛收益最高**的目标；同分时优先体力值最低者，再按座次取最小ID，保证决策稳定可复现。
##
## 用毛收益而不是单纯按体力排序，是为了让“对自己发动会失去【灵赋】”的代价真实参与比较：
## 自己与队友体力相同时，扣掉技能损失后的自己必然低于队友，因此只有池中别无他人（或他人收益更低）时
## AI 才会选择自己，而不会为了1点体力上限白弃掉本技能。
func _pick_best_target(authoritative_snapshot: Dictionary, pool: Array[int], evaluator: Object) -> int:
	# 当前最优目标；-1表示尚未选定，池非空由调用方保证。
	var best_id: int = -1
	# 当前最优毛收益；初值取负无穷，使第一个候选必然被选中。
	var best_score: float = -INF
	# 当前最优目标的体力；只在同分比较时使用。
	var best_hp: int = 0
	for player_id: int in pool:
		# 当前候选的毛收益与体力；两者共同决定取舍。
		var score: float = _score_target_gross(authoritative_snapshot, player_id, evaluator)
		var hp: int = int(evaluator.get_player(authoritative_snapshot, player_id).get("hp", 0))
		if best_id < 0 or score > best_score or (is_equal_approx(score, best_score) and (hp < best_hp or (hp == best_hp and player_id < best_id))):
			best_id = player_id
			best_score = score
			best_hp = hp
	return best_id


## 估算对指定目标发动的毛收益；敌方与身份未暴露目标一律给严格负分，避免白送技能或资敌。
func _score_target_gross(authoritative_snapshot: Dictionary, target_id: int, evaluator: Object) -> float:
	# 目标快照；无效目标不构成发动。
	var target: Dictionary = evaluator.get_player(authoritative_snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)) or bool(target.get("out_of_game", false)):
		return AI_INVALID_CHOICE_SCORE
	# 自己永远计入我方，不依赖身份模型对自指关系的取值。
	var is_self: bool = target_id == owner_player_id
	# 持有者对目标的公开态度；只用 get_attitude，不用 get_real_attitude，避免泄露隐藏身份。
	var attitude: float = 1.0 if is_self else float(evaluator.get_attitude(authoritative_snapshot, owner_player_id, target_id))
	if not snapshot_has_skill(target, MEIZHAN_SKILL_ID):
		# 分支一：授予技能。对敌方或身份未暴露者发动等于白送一项能力，必须给严格负分。
		if attitude <= 0.0:
			return AI_HOSTILE_GRANT_PENALTY
		return AI_GRANT_ALLY_VALUE
	# 分支二：+1体力上限并回复1点体力；两者都按统一资源尺度折算，合计等于2点体力资源。
	var upgrade_value: float = float(MAX_HP_GAIN + RECOVER_AMOUNT) * NonameAIEvaluator.HP_RESOURCE_VALUE
	if is_self:
		# 对自己发动会令阮梅失去【灵赋】自身；扣掉失去技能的代价，避免为一点体力无脑自弃技能。
		upgrade_value -= AI_SKILL_LOSS_COST
	if attitude <= 0.0:
		# 资敌：对手同时获得体力上限与体力，在“对手获得等量资源”之上再扣一层。
		return -upgrade_value + AI_HOSTILE_UPGRADE_PENALTY
	return upgrade_value


## 评估【灵赋】的发动收益；没有可用材料或没有队友目标时给严格负分，避免白发动一次。
func score_ai_action(authoritative_snapshot: Dictionary, _action: Dictionary, evaluator: Object) -> float:
	# 可用材料；为空时本技能不可能发动。
	if _get_ai_candidate_values(authoritative_snapshot, evaluator).is_empty():
		return AI_UNPAYABLE_ACTION_SCORE
	# 按三级优先选出的目标；没有队友可指定时严格负分（对敌方发动只会资敌，不进入候选）。
	var target_id: int = _pick_ai_target(authoritative_snapshot, evaluator)
	if target_id < 0:
		return AI_UNPAYABLE_ACTION_SCORE
	return _score_target_gross(authoritative_snapshot, target_id, evaluator) - _get_recast_cost_value(authoritative_snapshot, evaluator)


## 评估【灵赋】组合选择的确认动作；取消恒为0分，因此只有毛收益高于材料机会成本时才会确认。
func score_ai_choice(authoritative_snapshot: Dictionary, choice_request: Dictionary, action: Dictionary, evaluator: Object) -> float:
	# 请求上下文；只处理本技能自己的组合请求。
	var context: Dictionary = choice_request.get("context", {}) as Dictionary
	if str(context.get("kind", "")) != CHOICE_KIND:
		return 0.0
	# 动作负载；取消动作表示放弃本次发动。
	var payload: Dictionary = action.get("payload", {}) as Dictionary
	if not bool(payload.get("confirmed", false)):
		return 0.0
	# 已选目标与材料；两者都必须恰好一个，否则不是一次有效发动。
	var selected_targets: Array = payload.get("selected_target_ids", []) as Array
	var selected_cards: Array = payload.get("selected_card_uids", []) as Array
	if selected_targets.size() != 1 or selected_cards.size() != 1:
		return AI_INVALID_CHOICE_SCORE
	# 材料机会成本；按被选中牌的实际保留价值折算，使 AI 优先重铸价值最低的牌。
	# 该式与 _get_recast_cost_value() 同源：后者取候选最小值，正好等于本式在全部候选上的最大值。
	var material_cost: float = float(evaluator.get_choice_card_value(authoritative_snapshot, choice_request, int(selected_cards[0]), owner_player_id)) * AI_RECAST_COST_RATIO
	return _score_target_gross(authoritative_snapshot, int(selected_targets[0]), evaluator) - material_cost
