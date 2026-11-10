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

## 当前实体牌的自定义显示牌名；空字符串表示完全按 definition_id 查库取牌名。
## 取值由运行时造牌端口写入（例如【以太】创造一张玩家自由命名的牌），长度上限与牌名规则由造牌端口统一校验。
## 默认空字符串的原因：绝大多数实体牌都是牌堆里的正式牌，牌名由卡牌定义唯一决定，只有造出来的牌才需要覆写。
## 修改影响：所有牌名显示点必须经 game_settings.resolve_instance_display_name() 读取，直接查库会忽略本字段；
## 本字段只影响**显示**，不影响 definition_id 驱动的牌效、花色点数判定、同名查重与存档里的定义引用。
var custom_display_name: String = ""

## 当前实体牌的铸造来源技能ID；空字符串表示这张牌来自正式牌堆或牌堆洗牌，不是运行时造出来的。
## 取值是技能稳定ID（例如 "yitai"），用于在不依赖牌名的前提下回答“这张牌是不是某个技能造出来的”。
## 默认空字符串的原因：造牌是少数效果，绝大多数实体牌的来源就是牌堆本身。
## 修改影响：清空该字段会让“找出由某技能创造的牌”类效果失效；它不参与牌效结算，只参与来源识别与展示。
var minted_skill_id: String = ""

## 持久区域视为前的原实体牌面；空字典表示普通实体，区域离开时按此恢复，不改UID。
var persistent_view_as: Dictionary = {}

## 同一虚拟装备或延时牌的其他实体材料；由唯一移牌服务维护，不与标准区域数组重复持有。
var persistent_materials: Array[CardInstance] = []

## 附属材料的主实体UID；默认-1为非附属牌，持久区内部材料不能单独成为普通区域候选。
var material_parent_uid: int = -1


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
	# 运行时造牌字段；旧快照不含这两个键时保持空值，读档后表现为“这张牌来自牌堆”，与造牌功能引入前完全一致。
	# 注意 from_dict 是逐键白名单读取：新增字段必须在此显式读取，否则 to_dict 写出的内容会在网络与存档往返中被丢弃。
	card.custom_display_name = str(data.get("custom_display_name", ""))
	card.minted_skill_id = str(data.get("minted_skill_id", ""))
	card.persistent_view_as = (data.get("persistent_view_as", {}) as Dictionary).duplicate(true)
	card.material_parent_uid = int(data.get("material_parent_uid", -1))
	# 持久材料按原UID恢复；存档不重造实体，也不把同一份材料另放处理区。
	for material_data: Dictionary in data.get("persistent_materials", []) as Array:
		card.persistent_materials.append(CardInstance.from_dict(material_data))
	return card


## 以原首材料承载持久规则牌面；其他材料仍保留各自原牌面，由移牌服务统一附属。
func set_persistent_view_as(logical_card: CardInstance, persistent_zone: String) -> void:
	if persistent_view_as.is_empty():
		persistent_view_as = {"definition_id":definition_id, "suit":suit, "rank":rank, "color_override":color_override, "custom_display_name":custom_display_name, "zone":persistent_zone}
	definition_id = logical_card.definition_id
	suit = logical_card.suit
	rank = logical_card.rank
	color_override = logical_card.color_override
	custom_display_name = ""


## 离开持久规则区域后恢复原实体牌面，保留一次离区展示；材料UID与铸造来源保持不变。
func clear_persistent_view_as() -> void:
	if persistent_view_as.is_empty() or bool(persistent_view_as.get("ephemeral", false)):
		return
	last_hand_view_as_definition_id = definition_id
	last_hand_view_as_suit = suit
	last_hand_view_as_rank = rank
	definition_id = str(persistent_view_as.definition_id)
	suit = str(persistent_view_as.suit)
	rank = int(persistent_view_as.rank)
	color_override = str(persistent_view_as.color_override)
	custom_display_name = str(persistent_view_as.custom_display_name)
	last_hand_view_as_original_definition_id = definition_id
	persistent_view_as.clear()


## 当前规则对象拥有的原实体UID；无材料持久效果是逻辑状态，不凭空产生可获得的实体牌。
func get_physical_card_uids() -> Array[int]:
	# 原物理成员；普通实体和有材料持久牌均包含本UID。
	var result: Array[int] = []
	if not bool(persistent_view_as.get("ephemeral", false)):
		result.append(uid)
	for material: CardInstance in persistent_materials:
		result.append(material.uid)
	return result


## 持久牌仅在同类持久区内保留逻辑身份；延时判定的处理区仍属于原延时牌生命周期。
func retains_persistent_identity(to_zone: String) -> bool:
	return not persistent_view_as.is_empty() and (to_zone == str(persistent_view_as.get("zone", "")) or (str(persistent_view_as.get("zone", "")) == "judgment" and to_zone == "processing"))


## 从只读快照展开离开持久区域后真正得到的实体牌面；AI可复用此纯函数，不创建实例或消耗UID。
static func get_physical_card_data(data: Dictionary) -> Array[Dictionary]:
	# 原持久视为牌面；空字典表示普通实体，ephemeral表示没有物理材料。
	var original: Dictionary = data.get("persistent_view_as", {}) as Dictionary
	# 原物理成员快照；每个成员只返回一次，返回值与输入不共享可变字典。
	var result: Array[Dictionary] = []
	if bool(original.get("ephemeral", false)):
		return result
	# 第一份原实体；恢复实体牌面后不能把附属材料重复带入下一层评估。
	var primary: Dictionary = data.duplicate(true)
	# 可临时覆盖的牌面键；实体UID与铸造来源不在此列，始终保持原身份。
	for key: String in ["definition_id", "suit", "rank", "color_override", "custom_display_name"]:
		if original.has(key):
			primary[key] = original[key]
	primary.erase("persistent_view_as")
	primary.erase("persistent_materials")
	result.append(primary)
	# 其余原材料；按绑定顺序输出独立副本，不递归复制主实体。
	for material: Dictionary in data.get("persistent_materials", []) as Array:
		result.append(material.duplicate(true))
	return result


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
## 本函数刻意不改 custom_display_name：视为改的是“这张牌被当作什么用”，而自定义牌名是实体自己的名字，
## 牌面因此显示“实体原名（造牌牌名）+ 视为横条”，与「视为不抹掉实体身份」的既有口径一致。
func set_hand_view_as(view_as_definition_id: String, source_skill_id: String) -> bool:
	if zone != "hand" or view_as_definition_id.is_empty() or definition_id == view_as_definition_id:
		return false
	if hand_view_as_original_definition_id.is_empty():
		hand_view_as_original_definition_id = definition_id
	definition_id = view_as_definition_id
	hand_view_as_source_skill_id = source_skill_id
	return true


## 清除当前实体的手牌视为效果并恢复原始定义；返回清除前实际使用的逻辑牌ID。
## 与 set_hand_view_as 对称：本函数同样不触碰 custom_display_name，清除视为后牌面继续显示实体自己的牌名。
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
## 本函数同样保留 custom_display_name：复制型视为复制的是牌名与花色点数，不是实体身份，造牌牌名必须留下。
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
		"custom_display_name": custom_display_name,
		"minted_skill_id": minted_skill_id,
		"persistent_view_as": persistent_view_as.duplicate(true),
		"persistent_materials": persistent_materials.map(func(material: CardInstance) -> Dictionary: return material.to_dict()),
		"material_parent_uid": material_parent_uid,
	}


## 返回本实体牌用于显示的牌名覆写值；空字符串表示调用方应回退到 definition_id 查库取牌名。
## 单独提供只读入口而不是让调用方直接读字段，是为了让“牌名从哪来”这条规则只有一个实现点：
## 显示层统一调用 game_settings.resolve_instance_display_name()，该方法内部只通过本入口取覆写值。
func get_display_name_override() -> String:
	return custom_display_name
