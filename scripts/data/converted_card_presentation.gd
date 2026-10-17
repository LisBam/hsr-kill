class_name ConvertedCardPresentation
extends RefCounted

## 「有实体材料的转化牌」的展示牌面工厂。
##
## 职责边界：本类只把「本次被消耗的材料实体」转换成一组**只读牌面数据字典**，
## 不移动任何牌、不读写 GameState、不参与规则判定，也不依赖任何服务或节点。
## 它服务的是项目的一条统一表现口径：
##
## - 只要虚拟牌有实体材料来源（普通手牌 / 木牛“粮” / 装备牌），表现层一律绘制**材料牌面**，
##   并在牌面中央叠加本次逻辑牌名的视为标签（例如两张手牌当【杀】= 两张材料牌面各带【杀】标签）。
## - 只有完全没有实体材料的「视为使用」虚拟牌，才绘制逻辑牌本身的新牌面。
##
## 使用方式：调用方必须在材料**离开原区域之前**调用 build_faces()，
## 因为材料一旦离开手牌区，其花色点数与「手牌视为」状态会被移牌服务复位，届时读不到真实牌面。
## 返回的字典与 CardInstance.to_dict() 同形，可直接交给 MatchController 的统一牌面表现事件发送端口。


## 把材料实体列表转换为逐张展示牌面数据。
## material_cards 为本次被消耗的材料实体，顺序即表现层的铺开顺序；logical_definition_id 为本次实际结算的逻辑牌定义ID。
## 返回空数组表示没有可呈现的材料（逻辑牌ID为空或材料全部缺失），调用方应回退到绘制逻辑牌本身的路径。
static func build_faces(material_cards: Array[CardInstance], logical_definition_id: String) -> Array[Dictionary]:
	# 逐张材料牌面结果；顺序与材料顺序一致，表现层据此同帧并排铺开。
	var faces: Array[Dictionary] = []
	if logical_definition_id.is_empty():
		return faces
	for material_card: CardInstance in material_cards:
		# 缺失材料只跳过自身，不影响其余材料的展示；调用方已在上游完成可用性校验。
		if material_card == null:
			continue
		faces.append(_build_face(material_card, logical_definition_id))
	return faces


## 构造单张材料的展示载体并序列化为只读字典。
##
## 载体是一个**全新 UID** 的临时 CardInstance：它不属于任何区域、不写入任何权威状态，
## 只用于复用 CardInstance.to_dict() 的稳定字段形状，避免手写字典与实体快照字段漂移。
## UID 必须与材料实体不同：界面接管本机手牌节点时不会用表现数据重新配置牌面，
## 若沿用材料 UID，本地玩家看到的就是一张没有视为标签的裸材料牌。
static func _build_face(material_card: CardInstance, logical_definition_id: String) -> Dictionary:
	# 展示载体；花色点数沿用材料自身，使角标显示材料真实牌面而不是多材料聚合结果。
	var face: CardInstance = CardInstance.new(logical_definition_id, material_card.suit, material_card.rank)
	# 展示原牌面定义；已处于手牌视为状态的材料必须回溯其实体原名，否则载体会把逻辑牌误画成材料当前的视为牌面。
	face.last_hand_view_as_original_definition_id = material_card.hand_view_as_original_definition_id if material_card.has_hand_view_as() else material_card.definition_id
	# 本次逻辑牌名；界面据此生成牌面中央的视为标签（【杀】【雷杀】等）。
	face.last_hand_view_as_definition_id = logical_definition_id
	# 载体不属于任何权威区域；zone=void 与 owner_id=-1 保证它永远不会被任何区域查询命中。
	face.zone = "void"
	face.owner_id = -1
	return face.to_dict()
