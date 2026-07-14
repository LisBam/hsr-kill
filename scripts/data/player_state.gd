class_name PlayerState
extends RefCounted

## 单名玩家的权威对局状态。该结构不依赖 UI、AI 或网络节点，可独立序列化与测试。

## 玩家在本局中的稳定座次 ID；范围从0开始，死亡后也不复用。
var player_id: int = -1

## 玩家显示名称；可由本地设置或联机房间资料提供。
var display_name: String = "玩家"

## 当前武将配置 ID；通过数据仓库查询名称、性别、势力与技能。
var character_id: String = ""

## 当前武将是否已经向所有玩家亮出；选将阶段主公先公开，其他玩家完成后同时公开。
var character_revealed: bool = false

## 当前身份；可取 lord、loyalist、rebel、renegade。
var identity: String = "rebel"

## 身份是否对公共信息可见；主公开局明置，其他身份通常在死亡时公开。
var identity_revealed: bool = false

## 当前体力值；可降至0以下以完整表达濒死所需回复量。
var hp: int = 4

## 当前体力上限；默认4，样例武将配置可覆盖为3或其他正整数。
var max_hp: int = 4

## 当前是否存活；死亡结算完成后设为 false，之后不再参与行动顺序。
var alive: bool = true

## 当前是否处于连环状态；属性伤害结算后会触发横置角色间的伤害传导。
var chained: bool = false

## 当前是否处于翻面状态；为后续武将技能与完整回合规则预留。
var face_down: bool = false

## 当前手牌数组；仅本人和权威对局核心可读取完整实体牌信息。
var hand: Array[CardInstance] = []

## 当前装备区；键为 weapon、armor、offensive_mount、defensive_mount、treasure。
var equipment: Dictionary = {}

## 当前判定区中的延时锦囊；按进入顺序在判定阶段依次处理。
var judgment_area: Array[CardInstance] = []

## 当前回合已使用【杀】次数；进入新回合时重置为0。
var slash_count: int = 0

## 当前回合是否已使用【酒】；进入新回合时重置为 false。
var wine_used: bool = false

## 【酒】提供的下一张【杀】伤害加值；声明使用下一张【杀】时消耗。
var wine_bonus: int = 0

## 本回合需要跳过的阶段集合；延时锦囊判定后写入 draw 或 play。
var skipped_phases: Dictionary = {}

## 木牛流马下扣置的“粮”；装备离开且未转移给他人时应置入弃牌堆。
var wooden_ox_storage: Array[CardInstance] = []

## 当前出牌阶段是否已发动木牛流马存粮；每个回合开始时重置为 false。
var wooden_ox_used: bool = false


## 使用稳定 ID 与显示名创建玩家状态，其他字段由开局流程填充。
func _init(id: int = -1, name: String = "玩家") -> void:
	player_id = id
	display_name = name


## 返回当前武器实体牌；未装备武器时返回 null。
func get_weapon() -> CardInstance:
	return equipment.get("weapon") as CardInstance


## 返回当前防具实体牌；未装备防具时返回 null。
func get_armor() -> CardInstance:
	return equipment.get("armor") as CardInstance


## 返回手牌上限。基础规则等于当前体力值，最低可为0。
func get_hand_limit() -> int:
	return maxi(hp, 0)


## 按实体牌 UID 查找手牌；未找到时返回 null。
func find_hand_card(card_uid: int) -> CardInstance:
	for card: CardInstance in hand:
		if card.uid == card_uid:
			return card
	return null


## 按实体牌 UID 查找可使用或打出的牌，包括手牌与当前木牛流马下的“粮”。
func find_playable_card(card_uid: int) -> CardInstance:
	# 手牌查询结果；优先返回普通手牌。
	var hand_card: CardInstance = find_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for stored_card: CardInstance in wooden_ox_storage:
		if stored_card.uid == card_uid:
			return stored_card
	return null


## 移除并返回指定 UID 的手牌；该函数不决定卡牌后续目标区域。
func take_hand_card(card_uid: int) -> CardInstance:
	for index: int in range(hand.size()):
		if hand[index].uid == card_uid:
			return hand.pop_at(index)
	return null


## 移除并返回可使用或打出的牌；先查手牌，再查木牛流马下的“粮”。
func take_playable_card(card_uid: int) -> CardInstance:
	# 从手牌移出的结果；不为空时无需继续查询“粮”。
	var hand_card: CardInstance = take_hand_card(card_uid)
	if hand_card != null:
		return hand_card
	for index: int in range(wooden_ox_storage.size()):
		if wooden_ox_storage[index].uid == card_uid:
			return wooden_ox_storage.pop_at(index)
	return null


## 返回手牌与“粮”组成的可使用牌数组副本；调用方不得据此直接修改玩家区域。
func get_playable_cards() -> Array[CardInstance]:
	# 合并后的可用牌数组；手牌保持在前，“粮”追加在后。
	var result: Array[CardInstance] = hand.duplicate()
	result.append_array(wooden_ox_storage)
	return result


## 返回适合指定观察者的状态快照；他人只能看到手牌数量，不能看到牌面。
func to_dict(viewer_id: int = -1, reveal_private: bool = false) -> Dictionary:
	# 序列化后的装备区；装备属于公共信息，始终包含完整实体牌数据。
	var equipment_data: Dictionary = {}
	for slot_variant: Variant in equipment.keys():
		# 当前装备槽名称；用于保持网络结构与规则层一致。
		var slot: String = str(slot_variant)
		# 当前装备实体牌；空槽不会出现在字典中。
		var card: CardInstance = equipment[slot] as CardInstance
		equipment_data[slot] = card.to_dict()

	# 序列化后的手牌；只有本人、回放或服务器调试快照包含牌面。
	var hand_data: Array = []
	if reveal_private or viewer_id == player_id:
		for card: CardInstance in hand:
			hand_data.append(card.to_dict())

	# 序列化后的判定区；延时锦囊属于公共信息。
	var judgment_data: Array = []
	for card: CardInstance in judgment_area:
		judgment_data.append(card.to_dict())

	# 序列化后的“粮”；仅所有者或权威调试快照可看到牌面，其他玩家只看到数量。
	var wooden_ox_data: Array = []
	if reveal_private or viewer_id == player_id:
		for card: CardInstance in wooden_ox_storage:
			wooden_ox_data.append(card.to_dict())

	return {
		"player_id": player_id,
		"display_name": display_name,
		"character_id": character_id if character_revealed or viewer_id == player_id or reveal_private else "",
		"character_revealed": character_revealed,
		"identity": identity if identity_revealed or viewer_id == player_id or reveal_private else "hidden",
		"identity_revealed": identity_revealed,
		"hp": hp,
		"max_hp": max_hp,
		"alive": alive,
		"chained": chained,
		"face_down": face_down,
		"hand_count": hand.size(),
		"hand": hand_data,
		"equipment": equipment_data,
		"judgment_area": judgment_data,
		"wooden_ox_storage_count": wooden_ox_storage.size(),
		"wooden_ox_storage": wooden_ox_data,
	}
