extends CharacterDefinition

## 【阮梅】武将源码。武将通过独立技能组件组合【梅绽】【灵赋】【阮弦】。
## 三个技能共享“梅绽”这一技能归属：本人受击时触发全队摸牌，【灵赋】把这份能力授予他人或升级已有持有者，
## 【阮弦】在结束阶段为其他持有者补牌。技能之间不互相持有引用，全部通过项目统一的技能拥有查询入口协作。

## 【梅绽】技能脚本；负责持有者受到伤害后令所有“梅绽”持有者各摸一张牌。
const MEIZHAN_SKILL: Script = preload("res://game_data/skills/meizhan.gd")

## 【灵赋】技能脚本；负责重铸一张手牌，并授予“梅绽”或升级已有持有者。
const LINGFU_SKILL: Script = preload("res://game_data/skills/lingfu.gd")

## 【阮弦】技能脚本；负责结束阶段重铸一张锦囊牌，并为其他“梅绽”持有者补牌。
const RUANXIAN_SKILL: Script = preload("res://game_data/skills/ruanxian.gd")


## 写入武将静态信息与技能组件引用；技能顺序固定为 梅绽 → 灵赋 → 阮弦，也是技能栏展示顺序。
func _init() -> void:
	super({
		"id":"ruanmei",
		"display_name":"阮梅",
		"gender":"female",
		"faction":"yinhexvezhe",
		"max_hp":3,
		"description":"银河学者，以“梅绽”把受伤转化为全队的牌差，并把这份能力传递给队友。",
	}, [MEIZHAN_SKILL, LINGFU_SKILL, RUANXIAN_SKILL])
