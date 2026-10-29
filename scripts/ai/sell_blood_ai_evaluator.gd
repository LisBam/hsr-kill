class_name SellBloodAIEvaluator
extends RefCounted

## 受伤收益的纯快照评估。技能报告资源收益，本组件统一处理实际掉血、濒危风险与观察者视角。
## 不把“拥有卖血技能”当作受伤有利；主动攻击与响应必须比较同一笔体力损失和资源收入。

## 承伤后仅剩1点体力的风险倍率；默认1.8与通用目标估值一致，避免为少量资源反复压低队友体力。
const CRITICAL_HP_MULTIPLIER: float = 1.8

## 伤害达到濒死线时的风险倍率；默认2.5与通用伤害估值一致，此时不预支伤后技能收益。
const LETHAL_HP_MULTIPLIER: float = 2.5

## 主动承伤必须超过的净收益；默认0.25张牌资源，避免收支相等时反复消耗队友体力。
const ACCEPT_DAMAGE_MARGIN: float = 0.25


## 返回一次最终伤害触发的技能净资源收益；观察者可为攻击者或响应者，不读取隐藏真实态度。
## damage_amount 必须已经应用防具；濒死、死亡或离场时不预支收益，护盾是否影响触发由技能判断。
func score_benefit(snapshot: Dictionary, source_id: int, target_id: int, damage_amount: int, observer_id: int, evaluator: Object) -> float:
	# 受击者只读快照；不存在时不能假设任何技能或收益。
	var target: Dictionary = evaluator.get_player(snapshot, target_id)
	if target.is_empty() or not bool(target.get("alive", false)) or bool(target.get("out_of_game", false)):
		return 0.0
	# 护盾吸收后的实际掉血；与最终伤害分开传入，技能各自核对逐点或实际掉血的触发语义。
	var hp_lost: int = maxi(damage_amount - maxi(int(target.get("shield", 0)), 0), 0)
	# 伤害与掉血是不同事实：百折在护盾吸收后仍按伤害点触发，梅绽由自身钩子要求实际掉血。
	if damage_amount <= 0 or hp_lost >= int(target.get("hp", 0)):
		return 0.0
	# 每份实际安装技能各自的收入；实例键保证重复技能不会共用次数或被去重。
	var result: float = 0.0
	for skill_key: String in SkillDefinition.collect_snapshot_skill_keys(target):
		# 无规则宿主的评分实例；只读取公开快照，不安装时机或改写权威状态。
		var skill: SkillDefinition = GameDatabase.create_skill(SkillDefinition.base_skill_id_of(skill_key))
		if skill == null or (bool(target.get("non_locked_skills_disabled", false)) and not skill.lock and not skill.half_locked):
			continue
		skill.set_instance_key(skill_key)
		skill.bind(null, target_id)
		result += skill.score_ai_damage_benefit(snapshot, source_id, target_id, damage_amount, hp_lost, observer_id, evaluator)
	return result


## 合并一次确定命中伤害的资源损失与技能收入；不包含出牌成本、出牌顺序和身份集火奖励。
## 响应者用此值决定是否承伤，避免把攻击者的阵营奖励误当成自己受伤的好处。
func score_trade(snapshot: Dictionary, source_id: int, target_id: int, damage_amount: int, observer_id: int, evaluator: Object) -> float:
	# 目标快照；缺少目标时没有可比较的伤害交换。
	var target: Dictionary = evaluator.get_player(snapshot, target_id)
	if target.is_empty():
		return 0.0
	# 扣除护盾后的剩余体力；濒危时提高体力损失成本，收入不随风险放大。
	var remaining_hp: int = int(target.get("hp", 0)) - maxi(damage_amount - int(target.get("shield", 0)), 0)
	# 体力风险倍率；正常体力为1，临界与致命伤害分别采用公开常量。
	var risk: float = LETHAL_HP_MULTIPLIER if remaining_hp <= 0 else (CRITICAL_HP_MULTIPLIER if remaining_hp == 1 else 1.0)
	return evaluator.score_resource_change(snapshot, observer_id, target_id, 0, -damage_amount) * risk \
		+ score_benefit(snapshot, source_id, target_id, damage_amount, observer_id, evaluator)
