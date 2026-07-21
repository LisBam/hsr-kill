extends SkillDefinition

## 【机巧】技能源码。锁定解除持有者锦囊牌距离，并保护装备区防具与宝物不被其他角色弃置。


## 写入锁定技静态信息；技能描述严格保持主公提供的原文。
func _init() -> void:
	super({
		"id":"jiqiao",
		"name":"机巧",
		"trigger":"locked",
		"ui_enabled":false,
		"lock":true,
		"description":"锁定技，你使用锦囊牌没有距离限制。其他角色不可弃置你装备区内的防具牌与宝物牌。",
	})


## 锦囊牌忽略自身配置的距离限制；基本牌与装备牌保持原规则。
func ignores_card_distance_limit(card_definition: Dictionary) -> bool:
	return str(card_definition.get("type", "")) == "trick"


## 其他角色不能弃置装备区的防具与宝物；本人费用、死亡清理与非弃置获得效果不受影响。
func can_other_player_discard_card(_source_player_id: int, _card: CardInstance, zone: String, slot: String) -> bool:
	return zone != "equipment" or slot not in ["armor", "treasure"]
