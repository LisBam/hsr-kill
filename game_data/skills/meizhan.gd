extends SkillDefinition

## 【梅绽】技能源码。锁定技：任意一名持有者受到伤害后，所有拥有本技能的角色各摸一张牌。
##
## 结算口径按**伤害事件**成立一次，不随实际损失体力点数翻倍——原文是“受到伤害后”而不是“每受到1点伤害后”，
## 与【百折】逐点结算的 damagePointAfter 形成对照。
##
## 拥有者判定统一走项目唯一入口（规则段 `host.has_skill`、AI 段 `SkillDefinition.snapshot_has_skill`），
## 因此【灵赋】授予的“梅绽”能正常参与摸牌，被【留白】类效果剥夺后也会立刻停止参与，
## 不需要本技能维护任何“谁拥有梅绽”的名单。

## 本技能稳定ID；授予、失去与拥有判定都按该 ID 进行。
const MEIZHAN_SKILL_ID: String = "meizhan"

## 每次触发时每名持有者摸牌数；修改后必须同步技能描述与玩法数值文档。
const DRAW_COUNT: int = 1

## 卖血价值静态声明；表达“受伤者自己摸1张牌”这一份收益。
##
## 其余持有者的跨阵营收益由 modify_ai_incoming_card_effect() 动态追加，两者相加恰好等于
## “（对出手方态度为正的持有者数 − 态度为负的持有者数）× 1张牌”的净计数：
## 通用静态路径按 sign(态度(出手方→受伤者)) 贡献 ±1，正好等价于把受伤者自己算进净计数。
##
## 该值必须保持非0：【闪避决策】通过 get_snapshot_sell_blood_value(...) > 0 判断“是不是卖血角色”，
## 若改成 0.0 会让梅绽持有者完全不被视为卖血角色，与设计口径冲突。
## 统一估值契约：静态值只用于能力声明；下方 score_ai_damage_benefit 包含本人和所有持有者收入，
## 不再叠加旧静态/来牌补偿。是否让伤由实际掉血、非致命生存与净收益共同决定。
const SELL_BLOOD_VALUE: float = 1.0


## 写入锁定技静态信息；技能描述必须与武将面板展示原文完全一致（两处引号都是原文右引号）。
func _init() -> void:
	super({
		"id": MEIZHAN_SKILL_ID,
		"name": "梅绽",
		"trigger": ["damageAfter"],
		"lock": true,
		"ui_enabled": false,
		"sell_blood_value": SELL_BLOOD_VALUE,
		"description": "锁定技，当你受到伤害后，所有拥有技能”梅绽”的角色各摸一张牌。",
	})


## 订阅持有者受到伤害之后的时机；角色限定为受击者本人，因此每个伤害事件只触发一次。
func install() -> void:
	subscribe_timing("damageAfter", _on_owner_damaged, "target")


## 持有者受到伤害后，令所有此刻拥有本技能的角色各摸一张牌。
func _on_owner_damaged(event: RuleEvent) -> void:
	# 本次实际损失的体力点数；护盾全额吸收、伤害被归零或被取消时不存在“受到伤害”这一事实，锁定技也不触发。
	var hp_lost: int = int(event.data.get("hp_lost", 0))
	if hp_lost <= 0:
		return
	if host == null:
		return
	# 当前对局状态；技能只在真实对局中运行，取不到状态时安全返回。
	var state: GameState = host.state as GameState
	if state == null:
		return
	# 按座次顺序遍历全部角色；固定顺序保证摸牌日志顺序与回放结果稳定，与场上座次一致。
	for player: PlayerState in state.players:
		# 死亡或已离场的角色不参与摸牌；技能归属仍如实存在，但摸牌这一收益无法兑现。
		if not player.alive or player.out_of_game:
			continue
		# 拥有判定走项目唯一入口；不读武将固有技能列表，也不读运行时记录字典。
		if not bool(host.call("has_skill", player.player_id, MEIZHAN_SKILL_ID)):
			continue
		host.call("draw", player.player_id, DRAW_COUNT)


## 按场上梅绽持有者的敌我分布修正来牌估值。
##
## 参照系固定为**出手方（AI 自己）**：对出手方态度为正的持有者各加一张牌的价值，态度为负的各减一张，
## 中立（态度为0，通常意味着身份尚未暴露）不计入，与项目“中立关系不修正”的既有口径一致。
##
## 前置条件：本钩子只会在**受伤者本人拥有【梅绽】**时被调用（调用方按受伤者的技能清单逐项回调），
## 因此不需要在此重复判定受伤者是否持有本技能。
## 现行统一入口：通用层已经验证非致命最终伤害，本钩子再核验实际掉血；静态值只作能力声明，包含受伤者在内的全部收入在此按观察者态度计价。
func score_ai_damage_benefit(authoritative_snapshot: Dictionary, _source_id: int, _target_id: int, _damage_amount: int, hp_lost: int, observer_id: int, evaluator: Object) -> float:
	# 只有确实造成伤害的来牌才会触发“受到伤害后”；非伤害牌（装备、增益等）原样返回。
	# 调用约束由 SellBloodAIEvaluator 保证，此处不再维护另一条来牌加分路径。
	# 梅绽规则明确要求实际掉血；护盾全吸收的正数伤害不会触发摸牌。
	if hp_lost <= 0:
		return 0.0
	# 其余持有者的净计数；正数表示本次伤害整体有利于出手方一侧，负数表示整体有害。
	var net_holder_count: float = 0.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前角色快照；字段缺失时按无效条目跳过。
		var player: Dictionary = player_variant as Dictionary
		# 受伤者本人那一份已由静态 sell_blood_value 按态度符号计入，此处跳过以免重复计算。
		# 收入统一从本钩子结算，静态路径不再加分，因此受伤者本人也必须计入。
		# 死亡或离场者不会摸牌，因此不产生任何收益。
		if not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		# 持有判定走快照侧统一入口；与规则段共用同一套来源清单与“实际安装”裁剪规则。
		if not snapshot_has_skill(player, MEIZHAN_SKILL_ID):
			continue
		# 出手方对该持有者的公开态度；只用 get_attitude，不用 get_real_attitude，避免泄露隐藏身份。
		var attitude: float = float(evaluator.get_attitude(authoritative_snapshot, observer_id, int(player.get("player_id", -1))))
		net_holder_count += attitude / NonameAIEvaluator.ATTITUDE_SCALE
	return net_holder_count * float(DRAW_COUNT) * NonameAIEvaluator.CARD_RESOURCE_VALUE
