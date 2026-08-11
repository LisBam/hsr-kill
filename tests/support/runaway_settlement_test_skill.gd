class_name RunawaySettlementTestSkill
extends SkillDefinition

## 统一结算熔断专项测试技能。它只在无头回归中构造异常续结算链，不会进入正式武将或技能数据库。

## continue_settlement实际执行次数；初始值0，测试用它确认熔断前的执行次数严格有限。
var resume_count: int = 0


## 创建只用于结算保护回归的锁定技元数据；锁定语义避免非锁定技失效状态干扰测试。
func _init() -> void:
	super({
		"id":"runaway_settlement_test_skill",
		"name":"续结算熔断测试",
		"description":"仅用于无头测试的异常续结算链。",
		"lock":true,
	})


## 继续测试结算；identical_loop重新登记同一上下文，changing_loop递增step以验证总链长保护。
func continue_settlement(context: Dictionary) -> bool:
	resume_count += 1
	# 当前异常模式；只允许两种专项值，其他值返回false以验证内容契约。
	var loop_kind: String = str(context.get("kind", ""))
	if loop_kind == "identical_loop":
		return defer_settlement(context)
	if loop_kind == "changing_loop":
		# 下一条上下文；每次递增整数step，使语义键持续变化而必须由因果链总步数熔断。
		var next_context: Dictionary = context.duplicate(true)
		next_context["step"] = int(context.get("step", 0)) + 1
		return defer_settlement(next_context)
	return false
