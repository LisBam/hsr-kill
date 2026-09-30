class_name CardInstance
extends RefCounted

## 单张实体牌的运行时结构。配置定义与实体状态分离，同名牌可拥有不同花色、点数与位置。

## 下一张实体牌的递增序号；只用于本地运行时生成稳定唯一 ID。
static var _next_uid: int = 1

## 当前实体牌的唯一 ID；状态同步与操作指令必须使用此值而非数组下标。
var uid: int = 0

## 当前实体牌引用的配置 ID；效果与显示名称均通过该 ID 查询。
var definition_id: String = ""

## 当前实体牌的花色；可取 spade、heart、club、diamond。
## 多张实体牌组成的无花色虚拟牌使用 none，避免错误继承任一材料牌颜色。
var suit: String = "spade"

## 虚拟牌聚合颜色覆写；空字符串表示颜色完全由 suit 推导，实体牌与单材料虚拟牌始终为空。
## 多张材料花色不同但颜色一致时（例如红桃+方块），花色必须保持 none 却仍要表达红色，
## 因此该字段是“红色无花色牌”“黑色无花色牌”的唯一表达入口，规则判定统一读取 get_color()。
var color_override: String = ""

## 当前实体牌的点数；范围为1至13，其中1、11、12、13对应A、J、Q、K。
## 无点数虚拟牌使用0；规则判断不得把0视为任何实体牌点数。
var rank: int = 1

## 当前实体牌所在区域；默认在牌堆，移动逻辑会维护该字段。
var zone: String = "draw_pile"

## 当前实体牌的所属玩家 ID；公共区域使用 -1。
var owner_id: int = -1

## 已知该实体牌完整牌面的玩家 ID 集合；手牌移动和公开展示由移牌服务维护。
var known_to: Array[int] = []

## 是否已经发生公开展示；公开牌面不会因后续进入公共区域而重新变为未知。
var shown: bool = false

## 仅对某一持有者私密可见的玩家 ID；公开牌或公共区域使用 -1。
var private_owner_id: int = -1

## 当前手牌视为效果生效前的原始卡牌定义ID；空字符串表示实体没有临时手牌牌名，离开手牌区时恢复该定义。
var hand_view_as_original_definition_id: String = ""

## 赋予当前手牌视为效果的技能ID；只用于规则追踪与清理，不改变技能归属或实体所有者。
var hand_view_as_source_skill_id: String = ""

## 当前手牌拥有的通用标记标签；键为稳定标签ID，值保存显示文本、排序、来源技能与规则覆写，离开手牌区时整体清空。
var hand_mark_tags: Dictionary = {}

## 最近一次离开手牌时的原实体定义ID；仅供处理区与弃牌堆展示保留来源牌面，不参与后续规则判定。
var last_hand_view_as_original_definition_id: String = ""

## 最近一次离开手牌时的视为逻辑定义ID；仅供处理区与弃牌堆展示保留本次视为牌名，不参与后续规则判定。
var last_hand_view_as_definition_id: String = ""

## 当前手牌视为复制牌面前的原实体花色；空字符串表示本次视为只换牌名、不复制花色与点数。
## 该字段只在复制型视为生效期间非空，离开手牌区后会立刻恢复实体花色并清空。
var hand_view_as_original_suit: String = ""

## 当前手牌视为复制牌面前的原实体点数；0表示本次视为只换牌名、不复制花色与点数。
## 与 hand_view_as_original_suit 成对出现，恢复牌面时必须同时使用两者。
var hand_view_as_original_rank: int = 0

## 最近一次离开手牌时的视为逻辑花色；仅供处理区与弃牌堆展示保留本次视为牌面，不参与规则判定。
var last_hand_view_as_suit: String = ""

## 最近一次离开手牌时的视为逻辑点数；0表示最近一次视为没有复制牌面。
var last_hand_view_as_rank: int = 0


## 创建实体牌并分配唯一 ID；调用方需提供已校验的配置 ID、花色与点数。
## existing_uid 仅供网络快照、回放与规则续接恢复既有实体；默认-1会生成全新递增编号，运行时通常不动态指定。
func _init(card_definition_id: String = "", card_suit: String = "spade", card_rank: int = 1, existing_uid: int = -1) -> void:
	if existing_uid >= 0:
		uid = existing_uid
		# 后续新实体的安全起点；恢复较大 UID 时只推进游标防止碰撞，不把恢复动作计作一次新编号分配。
		_next_uid = maxi(_next_uid, existing_uid + 1)
	else:
		uid = _next_uid
		_next_uid += 1
	definition_id = card_definition_id
	suit = card_suit
	rank = card_rank


## 从网络安全快照恢复一张既有实体或逻辑响应代理；不会消耗新的 UID，区域与可见性字段按基础类型重建。
static func from_dict(data: Dictionary) -> CardInstance:
	# 恢复后的实体牌；稳定 UID 防止异步规则续接把同一响应误记为另一张新牌。
	var card: CardInstance = CardInstance.new(str(data.get("definition_id", "")), str(data.get("suit", "spade")), int(data.get("rank", 1)), int(data.get("uid", -1)))
	card.zone = str(data.get("zone", "draw_pile"))
	card.owner_id = int(data.get("owner_id", -1))
	# 多材料聚合颜色覆写；旧快照不含该字段时保持空值并回退按花色推导颜色。
	card.color_override = str(data.get("color_override", ""))
	card.known_to.clear()
	for player_id_variant: Variant in data.get("known_to", []) as Array:
		# 已知者稳定玩家 ID；异常类型统一转换为整数，重复项不会改变可见性语义。
		var player_id: int = int(player_id_variant)
		if not card.known_to.has(player_id):
			card.known_to.append(player_id)
	card.shown = bool(data.get("shown", false))
	card.private_owner_id = int(data.get("private_owner_id", -1))
	card.hand_view_as_original_definition_id = str(data.get("original_definition_id", ""))
	card.hand_view_as_source_skill_id = str(data.get("hand_view_as_source_skill_id", ""))
	card.hand_mark_tags = (data.get("hand_mark_tags", {}) as Dictionary).duplicate(true)
	card.last_hand_view_as_original_definition_id = str(data.get("presentation_original_definition_id", ""))
	card.last_hand_view_as_definition_id = str(data.get("view_as_definition_id", ""))
	# 复制型视为的实体牌面快照；旧快照不含该字段时保持空值，表现为普通换名视为。
	card.hand_view_as_original_suit = str(data.get("presentation_original_suit", ""))
	card.hand_view_as_original_rank = int(data.get("presentation_original_rank", 0))
	# 视为逻辑牌面；手牌中与当前快照花色点数一致，离手后表示最近一次已结束的视为牌面。
	card.last_hand_view_as_suit = str(data.get("view_as_suit", ""))
	card.last_hand_view_as_rank = int(data.get("view_as_rank", 0))
	return card


## 返回牌的颜色；优先读取多材料聚合颜色覆写，否则红桃与方块为红色、黑桃与梅花为黑色。
## 无花色且无覆写的虚拟牌返回 none，表示既不是红色也不是黑色。
func get_color() -> String:
	if not color_override.is_empty():
		return color_override
	return color_of_suit(suit)


## 按花色推导颜色；红桃与方块为红色，黑桃与梅花为黑色，其余（含 none）为无色。
## 该纯函数同时供 CardInstance 与多材料聚合逻辑复用，避免颜色映射出现第二套实现。
static func color_of_suit(card_suit: String) -> String:
	if card_suit == "heart" or card_suit == "diamond":
		return "red"
	if card_suit == "spade" or card_suit == "club":
		return "black"
	return "none"


## 将当前手牌临时视为指定逻辑牌；重复赋予时始终保留最初的实体定义，避免连续转移覆盖真实牌名。
func set_hand_view_as(view_as_definition_id: String, source_skill_id: String) -> bool:
	if zone != "hand" or view_as_definition_id.is_empty() or definition_id == view_as_definition_id:
		return false
	if hand_view_as_original_definition_id.is_empty():
		hand_view_as_original_definition_id = definition_id
	definition_id = view_as_definition_id
	hand_view_as_source_skill_id = source_skill_id
	return true


## 清除当前实体的手牌视为效果并恢复原始定义；返回清除前实际使用的逻辑牌ID。
func clear_hand_view_as() -> String:
	# 清除前逻辑牌ID；响应与虚拟使用流程可据此继续结算已经声明的牌效。
	var previous_view_as_definition_id: String = definition_id
	# 离手展示来源；弃牌与处理区仍需保留原实体与本次视为牌名，规则定义本身会立刻恢复。
	last_hand_view_as_original_definition_id = hand_view_as_original_definition_id
	last_hand_view_as_definition_id = previous_view_as_definition_id
	# 离手展示牌面；只有复制型视为才保留本次逻辑花色点数，普通换名视为必须清空以免伪造花色。
	last_hand_view_as_suit = suit if not hand_view_as_original_suit.is_empty() else ""
	last_hand_view_as_rank = rank if not hand_view_as_original_suit.is_empty() else 0
	if not hand_view_as_original_definition_id.is_empty():
		definition_id = hand_view_as_original_definition_id
	# 实体牌面恢复；花色与点数必须同时回到视为前快照，避免只恢复其一产生不存在的实体牌。
	if not hand_view_as_original_suit.is_empty():
		suit = hand_view_as_original_suit
		rank = hand_view_as_original_rank
	hand_view_as_original_definition_id = ""
	hand_view_as_original_suit = ""
	hand_view_as_original_rank = 0
	hand_view_as_source_skill_id = ""
	return previous_view_as_definition_id


## 将当前手牌临时视为指定逻辑牌，并同时复制该牌的花色与点数；重复赋予时保留最初的实体牌名与实体牌面。
## 与 set_hand_view_as 的差别只在于花色点数是否跟随逻辑牌：普通转化技能只换牌名，本入口用于“连同花色点数一起视为”。
## 花色点数覆写后，所有既有规则读取点（颜色筛选、花色判定、拼点与材料聚合）都会读到逻辑牌面，无需改动读取方。
func set_hand_view_as_with_face(view_as_definition_id: String, view_as_suit: String, view_as_rank: int, source_skill_id: String) -> bool:
	if zone != "hand" or view_as_definition_id.is_empty():
		return false
	if not is_valid_suit(view_as_suit) or not is_valid_rank(view_as_rank):
		return false
	if hand_view_as_original_definition_id.is_empty():
		hand_view_as_original_definition_id = definition_id
	# 实体牌面快照；已经处于复制型视为时保持最初快照，连续视为不会把上一次的逻辑牌面误当成实体牌面。
	if hand_view_as_original_suit.is_empty():
		hand_view_as_original_suit = suit
		hand_view_as_original_rank = rank
	definition_id = view_as_definition_id
	suit = view_as_suit
	rank = view_as_rank
	hand_view_as_source_skill_id = source_skill_id
	return true


## 判定一个花色字符串是否属于可以参与视为牌面复制的四种实体花色；无花色虚拟牌不参与复制。
static func is_valid_suit(card_suit: String) -> bool:
	return card_suit == "spade" or card_suit == "heart" or card_suit == "club" or card_suit == "diamond"


## 判定一个点数是否属于可以参与视为牌面复制的1至13范围；0与越界值都表示无实体牌面点数。
static func is_valid_rank(card_rank: int) -> bool:
	return card_rank >= 1 and card_rank <= 13


## 返回当前实体是否拥有尚未清理的手牌视为效果；区域移动组件只通过本查询决定是否恢复真实牌名。
func has_hand_view_as() -> bool:
	return not hand_view_as_original_definition_id.is_empty()


## 为当前手牌写入或更新一个通用标记标签；标签数据只接受可序列化字典，调用方负责提供长期稳定的标签ID。
func set_hand_mark_tag(tag_id: String, tag_data: Dictionary) -> bool:
	if zone != "hand" or tag_id.is_empty() or tag_data.is_empty():
		return false
	# 标准化标签数据；稳定ID同时写入数据体，网络与UI排序时不依赖字典键的迭代顺序。
	var normalized_tag_data: Dictionary = tag_data.duplicate(true)
	normalized_tag_data["id"] = tag_id
	hand_mark_tags[tag_id] = normalized_tag_data
	return true


## 移除当前手牌指定来源的通用标记标签；其他技能写入的标签保持不变，返回是否实际移除。
func remove_hand_mark_tag(tag_id: String) -> bool:
	if tag_id.is_empty() or not hand_mark_tags.has(tag_id):
		return false
	hand_mark_tags.erase(tag_id)
	return true


## 清除当前手牌的全部通用标记标签；返回是否实际移除了至少一个标签。
func clear_hand_mark_tags() -> bool:
	if hand_mark_tags.is_empty():
		return false
	hand_mark_tags.clear()
	return true


## 返回任一手牌标记是否声明指定布尔规则；多个标签可独立提供同一种临时规则能力。
func has_hand_mark_rule(rule_name: String) -> bool:
	if rule_name.is_empty():
		return false
	for tag_data_variant: Variant in hand_mark_tags.values():
		# 当前标签数据；异常旧快照会被视为空字典并安全跳过。
		var tag_data: Dictionary = tag_data_variant as Dictionary
		# 标签规则覆写；当前鸣弦使用ignore_distance_limit，结构可供后续标记机制复用。
		var rule_overrides: Dictionary = tag_data.get("rule_overrides", {}) as Dictionary
		if bool(rule_overrides.get(rule_name, false)):
			return true
	return false


## 清理已结束的视为牌展示来源；牌进入牌堆、手牌、装备、判定或木牛区域后不再保留旧一次性视为记录。
func clear_hand_view_as_presentation() -> void:
	last_hand_view_as_original_definition_id = ""
	last_hand_view_as_definition_id = ""
	# 视为牌面展示来源；与视为牌名同步清理，避免公共区域继续显示已经失效的花色点数。
	last_hand_view_as_suit = ""
	last_hand_view_as_rank = 0


## 序列化为网络安全字典；不包含任何对象引用或可执行回调。
func to_dict() -> Dictionary:
	# 原始定义 ID；手牌处于视为状态时供表现层保留实体牌面名称，空字符串表示当前没有临时视为效果。
	var original_definition_id: String = hand_view_as_original_definition_id
	# 展示原始定义 ID；已清除手牌视为状态后仍保留到本次处理或弃牌展示结束。
	var presentation_original_definition_id: String = hand_view_as_original_definition_id if not hand_view_as_original_definition_id.is_empty() else last_hand_view_as_original_definition_id
	# 展示视为定义 ID；手牌中直接使用当前逻辑定义，离手后读取最近一次已结束的视为记录。
	var view_as_definition_id: String = definition_id if not hand_view_as_original_definition_id.is_empty() else last_hand_view_as_definition_id
	# 展示实体花色；复制型视为生效时非空，供表现层保留实体原角标，普通换名视为保持空值。
	# 刻意不回填 last_hand_view_as_suit：离开手牌区时 suit/rank 已经恢复为实体原值，表现层回退读取的正是同一份实体牌面，
	# 只有需要继续解释“曾视为”的 view_as_suit/rank 才保留最近一次记录。
	var presentation_original_suit: String = hand_view_as_original_suit
	# 展示实体点数；与展示实体花色成对出现，0表示本次视为没有复制牌面。
	var presentation_original_rank: int = hand_view_as_original_rank if not hand_view_as_original_suit.is_empty() else 0
	# 视为逻辑花色；手牌中读取当前复制值，离手后读取最近一次已结束的视为牌面。
	var view_as_suit: String = suit if not hand_view_as_original_suit.is_empty() else last_hand_view_as_suit
	# 视为逻辑点数；与视为逻辑花色成对出现，0表示本次视为没有复制牌面。
	var view_as_rank: int = rank if not hand_view_as_original_suit.is_empty() else last_hand_view_as_rank
	return {
		"uid": uid,
		"definition_id": definition_id,
		"original_definition_id": original_definition_id,
		"suit": suit,
		"rank": rank,
		"color": get_color(),
		"color_override": color_override,
		"zone": zone,
		"owner_id": owner_id,
		"known_to": known_to.duplicate(),
		"shown": shown,
		"private_owner_id": private_owner_id,
		"hand_view_as_source_skill_id": hand_view_as_source_skill_id,
		"hand_mark_tags": hand_mark_tags.duplicate(true),
		"presentation_original_definition_id": presentation_original_definition_id,
		"view_as_definition_id": view_as_definition_id,
		"presentation_original_suit": presentation_original_suit,
		"presentation_original_rank": presentation_original_rank,
		"view_as_suit": view_as_suit,
		"view_as_rank": view_as_rank,
	}
