extends SkillDefinition

## 【言灵】锁定技源码。「卡芙卡」的技能之一。
## 第一段：游戏开始时，由本技能把三张专属锦囊牌【言灵】随机洗入摸牌堆。
## 第二段：任意角色使用延时锦囊牌时，持有者摸一张牌并成为「主演」。
##
## 两段的共同点是不需要任何意愿确认：锁定技，满足条件即执行，因此本技能不创建任何选择窗口。
## 「主演」只由权威端口写入，本技能不解释主演的后续效果，也不与【游丝】互相识别。

## 专属锦囊牌【言灵】的稳定卡牌定义 ID；与 game_data/cards/yanling.gd 的 id 字段逐字一致。
## 注意：技能 ID 与本常量同为 "yanling"，但技能与卡牌分属两个独立索引（GameDatabase.skills / .cards），
## 需求原文对两者使用同一英文名，因此这里保持同名，不为了“看起来不冲突”而擅自改名。
const CARD_DEFINITION_ID: String = "yanling"

## 游戏开始时加入牌堆的张数；与原文「随机加入三张【言灵】」一致，改动会直接改变开局牌堆构成与可判定次数。
const INSERT_COUNT: int = 3

## 洗入时使用的位次取值；取控制器常量而不是字面量，保证「随机位次」的语义只有一处定义。
## 该值会让权威随机源在整副牌堆中均匀选位，并把结果写入随机历史，使存档恢复与回放重演得到同一落点。
const INSERT_POSITION: int = MatchController.DRAW_PILE_POSITION_RANDOM

## 第二段触发时持有者摸牌的张数；与原文「你摸一张牌」一致。
const TRIGGER_DRAW_COUNT: int = 1

## 游戏开始时机的稳定名称。
## 该时机的权威定义是「游戏正式开始时」：全部起始手牌与手气卡流程都已经结束，第一轮尚未开始。
## 因此本技能加入牌堆的三张牌不会参与任何一次手气卡重发，玩家无法用手气卡刷到【言灵】。
const GAME_START_TIMING: String = "gameStart"

## 发动公告中声明的入堆张数键名；只用于复盘与界面提示，不参与任何规则判定。
const ACTIVATION_INSERT_COUNT_KEY: String = "insert_count"

## 发动公告中声明的入堆位次键名；写入的是位次取值（0 表示权威随机位次），同样只用于复盘。
const ACTIVATION_INSERT_POSITION_KEY: String = "insert_position"

## 用牌整牌时机的稳定名称；role="global" 表示任意角色使用牌都会进入本回调。
const CARD_USED_TIMING: String = "useCard"

## 延时锦囊牌判定所需的类别值；与卡牌静态元数据 type 字段的取值域一致。
const TRICK_TYPE: String = "trick"

## 延时锦囊牌的延时标记键名；与规则层既有判定口径（type 为 trick 且 delayed 为真）逐字一致。
const DELAYED_KEY: String = "delayed"


## 写入锁定技静态信息；玩家可见描述严格保持需求提供的原文。
## ui_enabled=false：本技能没有主动发动入口，摸牌与主演都在事件触发时自动完成。
func _init() -> void:
	super({
		"id":"yanling",
		"name":"言灵",
		"trigger":"gameStart",
		"lock":true,
		"ui_enabled":false,
		"description":"锁定技，游戏开始时，你往牌堆中随机加入三张【言灵】。当一名角色使用延时锦囊牌时，你摸一张牌并成为“主演”。",
	})


## 订阅游戏开始与任意角色用牌两个时机。
## 两段都必须用 role="global"：gameStart 事件的 player_id 固定为 -1（不属于任何玩家），
## 而第二段的原文是「当一名角色使用延时锦囊牌时」，与使用者是否为持有者无关。
func install() -> void:
	subscribe_timing(GAME_START_TIMING, _on_game_start, "global")
	subscribe_timing(CARD_USED_TIMING, _on_any_card_used, "global")


## 游戏开始时把三张专属牌【言灵】随机洗入摸牌堆。
## 顺序有硬性要求：先按统一入口宣告本次发动（写入技能历史、公开日志与发动表现，与主动技、触发技完全同构），
## 再逐张调用权威入堆端口。也就是说「游戏开始时」同样算一次真实的技能发动，可复盘、有发动提示，
## 而不是一次静默的牌堆改写；反过来，先入堆再宣告会让复盘把三张牌的加入时刻记在发动之前。
## 逐张调用入堆端口而不是一次性批量：端口只负责“确定性地插入一张”，张数与时机由本技能决定，
## 因此三张牌各自独立抽取位次与牌面，也就更接近「随机加入」的语义；每张牌位次独立也是可复现的（随机历史逐条记录）。
func _on_game_start(_event: RuleEvent) -> void:
	if host == null or not host.has_method("create_and_insert_card_into_draw_pile"):
		return
	# 发动公告；键名与取值都是基础可序列化值，界面与回放可以直接读取张数与位次口径。
	announce_activation({ACTIVATION_INSERT_COUNT_KEY:INSERT_COUNT, ACTIVATION_INSERT_POSITION_KEY:INSERT_POSITION})
	for _index: int in range(INSERT_COUNT):
		# 牌面留空：专属牌的牌面由卡牌文件自带（梅花K），端口会在调用方未给牌面时读取它，而不是随机花色点数。
		host.call("create_and_insert_card_into_draw_pile", CARD_DEFINITION_ID, "", 0, INSERT_POSITION)


## 任意角色使用延时锦囊牌时，持有者摸一张牌并成为「主演」。
## 本段刻意不区分使用者阵营，也不限定【言灵】本身：任何延时锦囊（【乐不思蜀】【兵粮寸断】【闪电】【言灵】）都触发。
func _on_any_card_used(event: RuleEvent) -> void:
	if host == null:
		return
	# 技能持有者权威状态；死亡或离场后不再获得摸牌与主演身份。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 本次使用的牌定义 ID；缺失时无法判断是否为延时锦囊，按不触发处理。
	var definition_id: String = str(event.data.get("card_id", ""))
	if not _is_delayed_trick(definition_id):
		return
	# 摸牌；走权威端口，因此会正常触发摸牌相关的技能与表现，不做任何绕过。
	host.call("draw", owner_player_id, TRIGGER_DRAW_COUNT)
	# 成为「主演」；主演服务保证场上至多一名主演，原主演会被同步顶替。
	# 本语句必须在摸牌之后：摸牌可能触发濒死等流程，而“成为主演”是本次触发的结果，不应被中途状态影响。
	host.call("set_starring_role", owner_player_id)


## 判断一个卡牌定义是否为延时锦囊牌。
## 判定口径与规则层保持一致：类别为锦囊（type == "trick"）且带有延时标记。
## 这里不新增「延时锦囊」的第三种表示方式，也不依赖具体牌名白名单，因此未来新增延时锦囊会自动纳入。
func _is_delayed_trick(definition_id: String) -> bool:
	if definition_id.is_empty():
		return false
	# 卡牌静态元数据副本；定义不存在时按不触发处理。
	var definition: Dictionary = GameDatabase.get_card(definition_id)
	if definition.is_empty():
		return false
	return str(definition.get("type", "")) == TRICK_TYPE and bool(definition.get(DELAYED_KEY, false))
