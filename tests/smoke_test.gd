extends Node

## 无界面烟雾测试：校验数据规模，并让四名基础 AI 通过统一动作入口运行若干帧。

## 主战斗场景；测试从其内置卡牌模板复制手牌，并验证桌面节点结构。
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## 可编辑武将牌场景；测试直接实例化正式资源，确保编辑器所见尺寸与游戏实例一致。
const PLAYER_TARGET_VIEW_SCENE: PackedScene = preload("res://scenes/components/player_target_view.tscn")

## 游戏内座位容器场景；测试验证座次标签只在运行时容器中出现并位于武将牌正下方。
const PLAYER_SEAT_SLOT_SCENE: PackedScene = preload("res://scenes/components/player_seat_slot.tscn")

## 正式卡牌场景；测试验证根节点是 Node2D 且保留111×148的3:4实体牌尺寸。
const CARD_VIEW_SCENE: PackedScene = preload("res://scenes/components/card_view.tscn")

## 全部卡牌稳定 ID 对应的《崩铁杀》显示名称；名称调整必须保持47项完整映射且不改变逻辑 ID。
const EXPECTED_CUSTOM_CARD_NAMES: Dictionary = {
	"bagua":"穷观阵",
	"baiyin":"光能盾牌",
	"bingliang":"兵粮寸断",
	"chitu":"斯科特",
	"cixiong":"干将莫邪",
	"dawan":"泡泡",
	"dilu":"的卢",
	"fangtian":"动能激发剑",
	"guanshi":"侵晨",
	"guding":"高周波电锯",
	"guohe":"万物归虚",
	"hanbing":"支离",
	"hualiu":"骅骝",
	"huogong":"焚烧",
	"sha_fire":"火杀",
	"jiedao":"借刀杀人",
	"jiu":"酒",
	"juedou":"决斗",
	"jueying":"大地兽",
	"lebu":"美梦沉眠",
	"sha_thunder":"雷杀",
	"muniu":"货运星槎",
	"nanman":"寰宇蝗灾",
	"qilin":"曲弓",
	"qinggang":"碎星斩舰刀",
	"qinglong":"石火梦身",
	"renwang":"仁王盾",
	"sha":"杀",
	"shan":"闪",
	"shandian":"天谴",
	"shuiyanqijun":"水淹七军",
	"shunshou":"万宇入腹",
	"tao":"药",
	"taoyuan":"丰饶馈赠",
	"tengjia":"建木藤甲",
	"tiesuo":"命运连结",
	"wanjian":"天弓垂眸",
	"wugu":"普世同谐",
	"wuxie":"运演否证",
	"wuzhong":"无中生有",
	"yinyue":"击云",
	"yanling":"言灵",
	"zhangba":"银河球棒",
	"zhuahuang":"爪黄飞电",
	"zhuge":"火力风暴潮",
	"zhuque":"普罗米修斯",
	"zixin":"紫骍",
}

## 烟雾测试最多等待的进程帧数；达到上限仍未发现运行时错误也会输出阶段状态。
const MAX_FRAMES: int = 1200

## 等待开局选择自动结算的最大帧数；零延迟配置下 AI 只需数帧即可答完回合开始窗口里的技能询问。
const OPENING_SETTLE_MAX_FRAMES: int = 60

## 测试用对局控制器；在 _initialize 中按正式场景的组件结构装配。
var _controller: MatchController

## 测试开始前的离线全角色控制设置；烟雾用例要求保留“单一真人+其余AI”的历史前提，成功退出时原样恢复内存值。
var _original_control_all_characters_enabled: bool = false


## 创建纯 AI 对局并开始异步帧检查。
func _ready() -> void:
	call_deferred("_run")


## 执行数据断言和纯 AI 对局烟雾测试。
func _run() -> void:
	await get_tree().process_frame
	_original_control_all_characters_enabled = GameSettings.control_all_characters_enabled
	# 直接修改测试进程内存而不调用持久化setter；玩家正式设置文件不会因烟雾测试被改写。
	GameSettings.control_all_characters_enabled = false
	# 数据校验错误；任何非空结果都说明配置不能安全开局。
	var validation_errors: Array[String] = GameDatabase.validation_errors
	if not validation_errors.is_empty():
		printerr("SMOKE_FAIL data_validation: %s" % "；".join(validation_errors))
		get_tree().quit(1)
		return
	# 内容源码文件名格式；小写字母、数字与下划线可以组合，横线和大写字母仍必须被拒绝。
	if not GameDatabase._is_lowercase_pinyin_filename("sha_fire_2") or GameDatabase._is_lowercase_pinyin_filename("sha-fire") or GameDatabase._is_lowercase_pinyin_filename("Sha"):
		printerr("SMOKE_FAIL content_filename_validation")
		get_tree().quit(1)
		return
	# 导出包脚本目录项规范化；Android PCK中的remap、编译或加密脚本必须恢复成原`.gd`资源路径，辅助文件不能误入内容注册。
	if GameDatabase._resolve_gd_script_file_name("sha.gd") != "sha.gd" or GameDatabase._resolve_gd_script_file_name("sha.gd.remap") != "sha.gd" or GameDatabase._resolve_gd_script_file_name("sha.gdc") != "sha.gd" or GameDatabase._resolve_gd_script_file_name("sha.gde") != "sha.gd" or not GameDatabase._resolve_gd_script_file_name("sha.gd.uid").is_empty():
		printerr("SMOKE_FAIL exported_script_remap_resolution")
		get_tree().quit(1)
		return
	# 默认完整牌堆实体牌数量；官方规则集3.0身份局牌表包含【银月枪】与【木牛流马】，合计162张。
	var deck_count: int = GameDatabase.get_deck_cards("standard_162").size()
	if deck_count != 162:
		printerr("SMOKE_FAIL deck_count=%d" % deck_count)
		get_tree().quit(1)
		return
	# 卡牌定义数量；补齐【银月枪】并新增专属锦囊牌【言灵】后，当前规则表应登记47种配置 ID。
	# 注意：专属锦囊牌虽然不进入任何牌堆，但仍是一种卡牌定义，因此同样计入本数量。
	var definition_count: int = GameDatabase.cards.size()
	if definition_count != 47:
		printerr("SMOKE_FAIL card_definitions=%d" % definition_count)
		get_tree().quit(1)
		return
	# 卡牌源码定义数量；每个元数据 ID 都必须对应 game_data/cards 中唯一的独立脚本。
	var card_source_count: int = GameDatabase.card_definitions.size()
	if card_source_count != definition_count or GameDatabase.card_scripts.size() != definition_count or GameDatabase.create_card_runtime("yinyue") == null:
		printerr("SMOKE_FAIL card_source_definitions=%d" % card_source_count)
		get_tree().quit(1)
		return
	# 【顺手牵羊】源码路径；验证卡牌由约定拼音文件自动发现，而非继续读取集中 JSON。
	var shunshou_definition: CardDefinition = GameDatabase.get_card_definition("shunshou")
	if shunshou_definition == null or str(shunshou_definition.get_script().resource_path) != "res://game_data/cards/shunshouqianyang.gd":
		printerr("SMOKE_FAIL shunshou_source_path")
		get_tree().quit(1)
		return
	# 新启动的全局牌名模式；默认必须显示《崩铁杀》牌名，菜单仍可在运行时切换回原版三国杀牌名。
	if GameSettings.card_name_mode != GameSettings.NameMode.CUSTOM:
		printerr("SMOKE_FAIL default_card_name_mode=%s" % GameSettings.NameMode.keys()[GameSettings.card_name_mode])
		get_tree().quit(1)
		return
	# 默认牌名解析结果；通过正式配置验证默认模式会实际作用于前端显示名称。
	if GameSettings.resolve_card_name(GameDatabase.get_card("sha")) != "杀":
		printerr("SMOKE_FAIL default_card_name=%s" % GameSettings.resolve_card_name(GameDatabase.get_card("sha")))
		get_tree().quit(1)
		return
	# 《崩铁杀》名称完整映射；逐项校验全部47种定义，防止单张卡牌仍保留旧名或误改稳定 ID。
	if EXPECTED_CUSTOM_CARD_NAMES.size() != definition_count:
		printerr("SMOKE_FAIL custom_card_name_count=%d" % EXPECTED_CUSTOM_CARD_NAMES.size())
		get_tree().quit(1)
		return
	for custom_card_id_variant: Variant in EXPECTED_CUSTOM_CARD_NAMES.keys():
		# 当前待校验卡牌 ID；保持为内部稳定键，不随两套显示名称变化。
		var custom_card_id: String = str(custom_card_id_variant)
		# 当前期望自定义名称；来源为公开卡牌名称规则表。
		var expected_custom_name: String = str(EXPECTED_CUSTOM_CARD_NAMES[custom_card_id])
		# 当前实际自定义名称；直接读取数据库索引以覆盖源码自动发现路径。
		var actual_custom_name: String = str(GameDatabase.get_card(custom_card_id).get("custom_name", ""))
		if actual_custom_name != expected_custom_name:
			printerr("SMOKE_FAIL custom_card_name=%s/%s/%s" % [custom_card_id, actual_custom_name, expected_custom_name])
			get_tree().quit(1)
			return
	# 默认《崩铁杀》模式技能说明；多个完整【原版牌名】必须同步映射且不改变普通文本。
	var custom_skill_description: String = GameDatabase.resolve_card_names_in_text("可使用【桃】、【无懈可击】或【银月枪】。")
	if custom_skill_description != "可使用【药】、【运演否证】或【击云】。":
		printerr("SMOKE_FAIL custom_skill_description=%s" % custom_skill_description)
		get_tree().quit(1)
		return
	# 技能按钮测试定义；组件必须自行解析静态原版说明，调用方无需预先改写元数据。
	var skill_button_definition: Dictionary = {"id":"card_name_reference_test", "name":"名称测试", "description":"可使用【桃】或【银月枪】。"}
	# 技能按钮测试实例；无需加入场景树即可校验 configure 写入的当前模式说明文本。
	var skill_button_view: SkillButtonView = SkillButtonView.new()
	skill_button_view.configure(skill_button_definition)
	if skill_button_view.skill_description != "可使用【药】或【击云】。":
		printerr("SMOKE_FAIL custom_skill_button_description=%s" % skill_button_view.skill_description)
		get_tree().quit(1)
		return
	GameSettings.set_card_name_mode(GameSettings.NameMode.ORIGINAL)
	# 原版模式技能说明；切回后必须重新得到静态原版牌名，不能残留上一次解析结果。
	var original_skill_description: String = GameDatabase.resolve_card_names_in_text("可使用【桃】、【无懈可击】或【银月枪】。")
	if original_skill_description != "可使用【桃】、【无懈可击】或【银月枪】。":
		printerr("SMOKE_FAIL original_skill_description=%s" % original_skill_description)
		get_tree().quit(1)
		return
	skill_button_view.configure(skill_button_definition)
	if skill_button_view.skill_description != "可使用【桃】或【银月枪】。":
		printerr("SMOKE_FAIL original_skill_button_description=%s" % skill_button_view.skill_description)
		get_tree().quit(1)
		return
	GameSettings.set_card_name_mode(GameSettings.NameMode.CUSTOM)
	skill_button_view.free()
	# 技能元数据数量；登记大黑塔的解构、灵感与看破、白厄的薪继与刻律德菈的征服后，共登记82个独立技能源码定义。
	# 新增欢愉派系火花的【好戏】与【连戏】后为84个；【好戏】是首个欢愉技，【连戏】是普通主动技能。
	# 新增爻光的【凶星】【鸿运】以及星与穹共用的【咬它】【好活】【当赏】后为89个。
	# 新增星际和平公司真珠的【补缀】【鉴映】后为91个；【补缀】是第二个欢愉技，参演编号104。
	# 新增丹恒·腾荒的【同袍】后为92个；【同袍】是四节顺序推进的轮回技。
	# 新增丹恒·腾荒的【岳峙】后为93个；【岳峙】是接管多目标牌的限定技。
	# 新增瓦尔特的【断界】后为94个；【断界】是每次发动后删除最后一项的主动技能。
	# 新增彦卿的【遥击】与【凌霜】后为96个；两者分别负责最远目标解限与【杀】的翻面附加效果。
	# 新增白露的【悬壶】【生息】与刃的【万死】【支离】后为100个；【悬壶】是手牌上限豁免类锁定技，
	# 【生息】是永久累积额度的用牌联动技，【万死】是按回合结束后兑现的额外回合技，【支离】是目标改写类锁定技。
	# 新增卡芙卡的【言灵】【游丝】后为102个；【言灵】是开局洗入专属牌的锁定技，【游丝】是私有置牌并跨回合兑现的技能。
	# 新增青雀的【独弈】【弃和】【自摸】后为105个；【独弈】【弃和】是限制用牌与抵消伤害牌的锁定技，
	# 【自摸】是用虚拟手牌选择“视为使用”的主动技。
	# 新增丹恒·饮月的【伏辰】【濯世】后为107个；【伏辰】是获得他人“打出”的【杀】的全局锁定技，
	# 【濯世】是三段弃置基本牌换取拆牌与雷电伤害的阶段技。
	# 新增砂金的【筹码】【盲注】【风口】后为110个；【筹码】是开局按体力上限摸牌并提升手牌上限的锁定技，
	# 【盲注】是用两种颜色叠护盾与摸牌的阶段技，【风口】是批量获得时机与主动夺牌并失去自身的主动技。
	# 新增银枝的【巡礼】【礼节】后为112个；【巡礼】是插入三段额外阶段并改写距离的半锁定技，
	# 【礼节】是批量获得后令他人摸牌、被他人回复后回赠体力的主动技。
	var skill_definition_count: int = GameDatabase.skills.size()
	if skill_definition_count != 112:
		printerr("SMOKE_FAIL skill_definitions=%d" % skill_definition_count)
		get_tree().quit(1)
		return
	# 技能脚本数量；技能元数据与可创建的独立运行时代码必须一一对应。
	if GameDatabase.skill_scripts.size() != skill_definition_count or GameDatabase.create_skill("yongyi") == null or GameDatabase.create_skill("mingxian") == null or GameDatabase.create_skill("zhufeng") == null or not GameDatabase.get_skill("trailblaze_sample").is_empty():
		printerr("SMOKE_FAIL skill_source_definitions")
		get_tree().quit(1)
		return
	# 新增正式武将与技能；基础体力、势力和玩家可见技能原文必须由源码自动索引且保持稳定。
	var xier_definition: Dictionary = GameDatabase.get_character("xier")
	var jizi_definition: Dictionary = GameDatabase.get_character("himeko")
	# 三月七、杰帕德与丹恒的武将定义；用于验证新体力、势力与技能引用已替换旧占位内容。
	var march_definition: Dictionary = GameDatabase.get_character("march_7th")
	# 杰帕德武将定义；用于校验贝洛伯格势力与4点基础体力。
	var gepard_definition: Dictionary = GameDatabase.get_character("gepard")
	# 丹恒武将定义；用于校验星穹列车势力与4点基础体力。
	var dan_heng_definition: Dictionary = GameDatabase.get_character("dan_heng")
	# 五名新增武将定义；同名星与穹分别通过稳定ID区分，桑博使用贝洛伯格势力。
	var xing_definition: Dictionary = GameDatabase.get_character("xing")
	var qiong_definition: Dictionary = GameDatabase.get_character("qiong")
	var xing_preservation_definition: Dictionary = GameDatabase.get_character("xing_cunhu")
	var qiong_preservation_definition: Dictionary = GameDatabase.get_character("qiong_cunhu")
	var sampo_definition: Dictionary = GameDatabase.get_character("sangbo")
	# 素裳武将定义；用于校验仙舟联盟势力、女性性别、4点基础体力与双技能引用均已被自动索引。
	var sushang_definition: Dictionary = GameDatabase.get_character("sushang")
	# 桂乃芬武将定义；用于校验仙舟联盟势力、女性性别、3点基础体力与双技能引用均已被自动索引。
	var guinaifen_definition: Dictionary = GameDatabase.get_character("guinaifen")
	# 佩拉武将定义；用于校验贝洛伯格势力、女性性别、3点基础体力与双技能顺序。
	var peila_definition: Dictionary = GameDatabase.get_character("peila")
	# 玲可武将定义；用于校验贝洛伯格势力、女性性别、3点基础体力与双技能顺序。
	var lingke_definition: Dictionary = GameDatabase.get_character("lingke")
	# 驭空武将定义；用于校验仙舟联盟势力、女性性别、4点基础体力与双技能顺序。
	var yvkong_definition: Dictionary = GameDatabase.get_character("yvkong")
	# 停云武将定义；用于校验仙舟联盟势力、女性性别、3点基础体力与双限定技顺序。
	var tingyun_definition: Dictionary = GameDatabase.get_character("tingyun")
	# 白露武将定义；用于校验仙舟联盟势力、女性性别、3点基础体力与技能顺序。
	var bailu_definition: Dictionary = GameDatabase.get_character("bailu")
	# 刃武将定义；用于校验星核猎手势力、男性性别、4点基础体力与技能顺序。
	var ren_definition: Dictionary = GameDatabase.get_character("ren")
	if int(xier_definition.get("max_hp", 0)) != 4 or str(xier_definition.get("faction", "")) != "beiluoboge" or int(jizi_definition.get("max_hp", 0)) != 3 or int(march_definition.get("max_hp", 0)) != 3 or str(march_definition.get("faction", "")) != "xingqionglieche" or int(gepard_definition.get("max_hp", 0)) != 4 or str(gepard_definition.get("faction", "")) != "beiluoboge" or int(dan_heng_definition.get("max_hp", 0)) != 4 or int(xing_definition.get("max_hp", 0)) != 4 or int(qiong_definition.get("max_hp", 0)) != 4 or int(xing_preservation_definition.get("max_hp", 0)) != 4 or int(qiong_preservation_definition.get("max_hp", 0)) != 4 or int(sampo_definition.get("max_hp", 0)) != 4 or str(sampo_definition.get("faction", "")) != "beiluoboge" or int(sushang_definition.get("max_hp", 0)) != 4 or str(sushang_definition.get("faction", "")) != "xianzhou" or str(sushang_definition.get("gender", "")) != "female" or sushang_definition.get("skills", []) != ["jianshi", "shanqing"] or int(guinaifen_definition.get("max_hp", 0)) != 3 or str(guinaifen_definition.get("faction", "")) != "xianzhou" or str(guinaifen_definition.get("gender", "")) != "female" or guinaifen_definition.get("skills", []) != ["xifa", "touxia"]:
		printerr("SMOKE_FAIL new_character_stats")
		get_tree().quit(1)
		return
	if int(peila_definition.get("max_hp", 0)) != 3 or str(peila_definition.get("faction", "")) != "beiluoboge" or str(peila_definition.get("gender", "")) != "female" or peila_definition.get("skills", []) != ["zhuijian", "mice"] or int(lingke_definition.get("max_hp", 0)) != 3 or str(lingke_definition.get("faction", "")) != "beiluoboge" or str(lingke_definition.get("gender", "")) != "female" or lingke_definition.get("skills", []) != ["kance", "qiusheng"]:
		printerr("SMOKE_FAIL peila_lingke_stats")
		get_tree().quit(1)
		return
	if int(yvkong_definition.get("max_hp", 0)) != 4 or str(yvkong_definition.get("faction", "")) != "xianzhou" or str(yvkong_definition.get("gender", "")) != "female" or yvkong_definition.get("skills", []) != ["mingxian", "zhufeng"]:
		printerr("SMOKE_FAIL yvkong_stats")
		get_tree().quit(1)
		return
	if int(tingyun_definition.get("max_hp", 0)) != 3 or str(tingyun_definition.get("faction", "")) != "xianzhou" or str(tingyun_definition.get("gender", "")) != "female" or tingyun_definition.get("skills", []) != ["xiangyin", "guangfu"]:
		printerr("SMOKE_FAIL tingyun_stats")
		get_tree().quit(1)
		return
	# 白露与刃武将静态信息；逐字校验体力、势力、性别与技能顺序。
	if int(bailu_definition.get("max_hp", 0)) != 3 or str(bailu_definition.get("faction", "")) != "xianzhou" or str(bailu_definition.get("gender", "")) != "female" or bailu_definition.get("skills", []) != ["xuanhu", "shengxi"]:
		printerr("SMOKE_FAIL bailu_stats")
		get_tree().quit(1)
		return
	if int(ren_definition.get("max_hp", 0)) != 5 or str(ren_definition.get("faction", "")) != "xinghelieshou" or str(ren_definition.get("gender", "")) != "male" or ren_definition.get("skills", []) != ["wansi", "zhili"]:
		printerr("SMOKE_FAIL ren_stats")
		get_tree().quit(1)
		return
	if str(GameDatabase.get_skill("xingjun").get("description", "")) != "出牌阶段开始时，你可以跳过该阶段。若如此做，本回合结束时，你可令一名其他角色执行一个额外的回合。" or str(GameDatabase.get_skill("dieying").get("description", "")) != "回合结束时，你可以摸X张牌，然后弃置等量的牌。（X为本回合内进入弃牌堆的【杀】数，X至多为5。）" or str(GameDatabase.get_skill("tianzhui").get("description", "")) != "出牌阶段限一次，你可以弃置一张锦囊牌或将自身横置的武将牌竖置，然后对一名横置的角色造成1点火属性伤害。" or str(GameDatabase.get_skill("zhenqi").get("description", "")) != "领袖技，“贝洛伯格”势力的角色的回合开始时，其可弃置一张手牌/失去1点体力，然后你令另一名“贝洛伯格”势力的角色摸一张牌/回复1点体力。" or str(GameDatabase.get_skill("linghang").get("description", "")) != "领袖技，“星穹列车”势力的角色使一名角色横置时，你可对其发动此技能，然后其可重铸一张手牌。每回合限一次。" or str(GameDatabase.get_skill("jiahu").get("description", "")) != "准备阶段，你可以横置一名武将牌竖置且没有护盾的角色，并令其获得1点护盾。" or str(GameDatabase.get_skill("bingfeng").get("description", "")) != "当你使用牌指定唯一目标时，你可选择一项：1.将目标的武将牌调整为竖直；2.弃置目标一张手牌。然后若该角色不为你，你令此牌无效。每回合每名角色限一次。" or str(GameDatabase.get_skill("yongyi").get("description", "")) != "当你的体力值受到伤害后，你可以进行一个额外的弃牌阶段，然后获得1点护盾。每回合限一次，弃牌阶段开始时，你可以对自己造成1点伤害并摸一张牌，然后进行一个额外的出牌阶段。" or str(GameDatabase.get_skill("gangfeng").get("description", "")) != "你可将黑色牌当雷【杀】使用或打出。" or str(GameDatabase.get_skill("jiyu").get("description", "")) != "当你使用【杀】指定目标时，你可令目标角色调整至横置状态，然后令目标角色选择：1.其不可使用【闪】响应此【杀】；2.令你横置你攻击范围内的另一名角色。" or str(GameDatabase.get_skill("wangpai").get("description", "")) != "锁定技，你使用【杀】无次数限制。" or str(GameDatabase.get_skill("anda").get("description", "")) != "你可将一张牌当无距离限制的火【杀】使用或打出，每回合限一次。" or str(GameDatabase.get_skill("quanlei").get("description", "")) != "出牌阶段限一次，你可将一张手牌当目标上限+1的雷【杀】使用。" or str(GameDatabase.get_skill("hupo").get("description", "")) != "锁定技，你无法成为黑色【杀】的目标。" or str(GameDatabase.get_skill("tiebi").get("description", "")) != "每轮开始时，你可弃置一张【闪】并横置一名其他角色，其获得技能“琥珀”直到本轮结束。" or str(GameDatabase.get_skill("jianlei").get("description", "")) != "当一名距离为1的其他角色成为黑色【杀】的目标时，你可弃置一张【闪】并横置该角色，然后令此【杀】无效。" or str(GameDatabase.get_skill("pofeng").get("description", "")) != "结束阶段，若你于本回合内使用【杀】指定过目标，你可以弃置一张手牌并进行一个额外的回合，本回合内你使用牌仅可指定你本回合内使用【杀】指定过的角色为目标。每轮限一次。":
		printerr("SMOKE_FAIL new_skill_descriptions")
		get_tree().quit(1)
		return
	# 素裳与桂乃芬技能原文；逐项锁定需求钦定的标点、数值和语句顺序，避免后续重构改写玩家面板文本。
	if str(GameDatabase.get_skill("jianshi").get("description", "")) != "当你使用【杀】造成伤害时，你可进行判定：若判定结果为红色，此伤害+1。" or str(GameDatabase.get_skill("shanqing").get("description", "")) != "你可将两张牌当【杀】使用，这些牌中的每种花色使此【杀】获得对应效果：红桃，造成伤害后回复等量的体力值；方块，使用时你摸一张牌；黑桃，此【杀】无距离限制；梅花，使用时你弃置目标的一张牌。每回合限一次。" or str(GameDatabase.get_skill("xifa").get("description", "")) != "一名角色进行判定前，你可观看牌堆顶的两张牌，然后将这些牌以任意顺序放回牌堆顶与牌堆底。" or str(GameDatabase.get_skill("touxia").get("description", "")) != "其他角色的回合结束时，你可进行判定，然后你可以获得弃牌堆中一张于此回合出牌阶段进入弃牌堆、且花色与判定结果相同的牌，然后当前回合的角色摸一张牌。每轮限一次。":
		printerr("SMOKE_FAIL sushang_guinaifen_skill_descriptions")
		get_tree().quit(1)
		return
	# 佩拉与玲可技能原文；逐字锁定需求指定的标点、数值和语句顺序。
	if str(GameDatabase.get_skill("zhuijian").get("description", "")) != "准备阶段，你可以弃置一张牌并选择一名其他角色，其下次受到的属性伤害+1直到你的下个回合开始。" or str(GameDatabase.get_skill("mice").get("description", "")) != "回合结束时，你可令一名其他角色执行一项：1.获得一个额外的出牌阶段；2.摸一张牌并获得一个额外的弃牌阶段。该阶段结束后，你执行另一项。" or str(GameDatabase.get_skill("kance").get("description", "")) != "出牌阶段限一次，你可以观看一名其他角色的手牌，然后选择并获得牌堆中的一张属性【杀】或【桃】。" or str(GameDatabase.get_skill("qiusheng").get("description", "")) != "锁定技，当你进入濒死状态时，若你有手牌，且手牌中没有【桃】或【酒】，你弃置所有手牌并将体力值回复至1点。":
		printerr("SMOKE_FAIL peila_lingke_skill_descriptions")
		get_tree().quit(1)
		return
	# 驭空技能原文；逐字锁定需求指定的标点、数值和语句顺序。
	if str(GameDatabase.get_skill("mingxian").get("description", "")) != "出牌阶段限一次，你可令任意名与你距离为1以内的角色从牌堆中各获得一张【杀】，这些【杀】无距离限制直到离开其手牌区。" or str(GameDatabase.get_skill("zhufeng").get("description", "")) != "锁定技，当你受到或造成伤害后，你计算与其他角色的距离-1，若此时你与所有角色距离均为1，则改为摸一张牌。":
		printerr("SMOKE_FAIL yvkong_skill_descriptions")
		get_tree().quit(1)
		return
	# 白露技能原文；逐字锁定需求指定的全角括号、数值与语句顺序。
	if str(GameDatabase.get_skill("xuanhu").get("description", "")) != "锁定技，你的【桃】不计入手牌上限。当一名角色死亡后，你从牌堆中获得一张【桃】。" or str(GameDatabase.get_skill("shengxi").get("description", "")) != "每回合限X次，当你使用基本牌时，你可摸1张牌，或令本回合结束后X+1。（X初始为1）":
		printerr("SMOKE_FAIL bailu_skill_descriptions")
		get_tree().quit(1)
		return
	# 刃技能原文；逐字锁定需求指定的全角引号、数值与语句顺序。
	if str(GameDatabase.get_skill("wansi").get("description", "")) != "每回合限一次，当你受到伤害后，若你的体力值为1，你可于本回合结束后成为“主演”并执行一个额外的回合。" or str(GameDatabase.get_skill("zhili").get("description", "")) != "锁定技，你是你自己使用【杀】的合法目标。当“主演”使用【杀】造成伤害时，其回复1点体力。当你使用【杀】指定唯一目标时，你令此【杀】的目标改为与目标角色相邻的角色，此【杀】结算完毕后，你失去1点体力。":
		printerr("SMOKE_FAIL ren_skill_descriptions")
		get_tree().quit(1)
		return
	# 停云技能原文；逐字锁定需求指定的标点、引号与语句顺序。
	if str(GameDatabase.get_skill("xiangyin").get("description", "")) != "限定技，出牌阶段，你可令一名未拥有“赐福”标记的角色获得“赐福”标记，拥有“赐福”标记的角色于一回合内使用的第一张【杀】无距离限制。" or str(GameDatabase.get_skill("guangfu").get("description", "")) != "限定技，出牌阶段，你可令一名角色摸一张牌。本回合结束时，若其有已发动的限定技，你复原其中一项限定技。":
		printerr("SMOKE_FAIL tingyun_skill_descriptions")
		get_tree().quit(1)
		return
	# 武将定义数量；新增大黑塔后，共登记37名角色定义；新增欢愉派系火花后为38名。
	# 新增爻光、星（欢愉派系）与穹（欢愉派系）后为41名。新增真珠后为42名。
	# 新增丹恒·腾荒（翁法罗斯）后为43名；腾荒与同名丹恒通过稳定ID区分。
	# 新增瓦尔特（星穹列车）后为44名。
	# 新增彦卿（仙舟联盟）后为45名。
	# 新增白露（仙舟联盟）与刃（星核猎手）后为47名；两名新武将各自引用本次新增的两个技能。
	# 新增卡芙卡（星核猎手）后为48名；她引用【言灵】与【游丝】。
	# 新增青雀（仙舟联盟，3体力）后为49名；她引用【独弈】【弃和】【自摸】。
	# 新增丹恒·饮月（仙舟联盟，4体力）后为50名；他与同势力的丹恒通过稳定ID区分，引用【伏辰】【濯世】。
	# 新增砂金（星际和平公司，3体力）后为51名；他引用【筹码】【盲注】【风口】。
	# 新增银枝（星间寰宇，4体力）后为52名；他引用【巡礼】【礼节】。
	var character_definition_count: int = GameDatabase.characters.size()
	if character_definition_count != 52:
		printerr("SMOKE_FAIL character_definitions=%d" % character_definition_count)
		get_tree().quit(1)
		return
	# 势力展示元数据数量；当前35名武将定义共同使用8个独立势力主题；新增欢愉势力后为9个。
	# 新增星际和平公司与星间寰宇后为10个；两者分别使用铜色b87333与银色c7c9ce。
	var faction_definition_count: int = GameDatabase.factions.size()
	if faction_definition_count != 10:
		printerr("SMOKE_FAIL faction_definitions=%d" % faction_definition_count)
		get_tree().quit(1)
		return
	# 势力展示配色；列车与贝洛伯格分别固定为列车灰、寒冰蓝，颜色仅影响武将牌与徽记表现。
	if str(GameDatabase.get_faction("xingqionglieche").get("color", "")) != "8a919c" or str(GameDatabase.get_faction("beiluoboge").get("color", "")) != "58b8e8":
		printerr("SMOKE_FAIL faction_colors=%s/%s" % [GameDatabase.get_faction("xingqionglieche"), GameDatabase.get_faction("beiluoboge")])
		get_tree().quit(1)
		return
	# 已移除占位武将；目录扫描不得再登记旧稳定 ID，避免选将候选或存档回退到无规则角色。
	if not GameDatabase.get_character("trailblazer").is_empty():
		printerr("SMOKE_FAIL removed_trailblazer_still_registered")
		get_tree().quit(1)
		return
	# 武将插画统一目录与格式优先级；资源制作约定必须稳定为同名 PNG 优先、同名 JPG 其次。
	if GameDatabase.CHARACTER_IMAGE_DIRECTORY != "res://game_data/characters/image" or GameDatabase.CHARACTER_IMAGE_EXTENSIONS != ["png", "jpg"]:
		printerr("SMOKE_FAIL character_artwork_convention")
		get_tree().quit(1)
		return
	for character_id_variant: Variant in GameDatabase.characters.keys():
		# 当前武将稳定 ID；只用于查询数据库元数据，插画匹配仍以源码文件名为准。
		var character_id: String = str(character_id_variant)
		# 当前武将源码定义；测试从脚本资源路径取得真实文件名，避免把稳定 ID 误当作插画名称。
		var character_source_definition: CharacterDefinition = GameDatabase.character_definitions.get(character_id) as CharacterDefinition
		# 当前武将源码路径；所有已登记武将都必须保留可追溯的独立脚本资源。
		var character_source_path: String = str(character_source_definition.get_script().resource_path) if character_source_definition != null else ""
		# 按统一目录与格式顺序计算出的预期插画路径；无同名资源时为空字符串。
		var expected_character_art_path: String = GameDatabase._find_character_art_path(character_source_path)
		# 数据库实际写入的表现元数据；必须与自动发现结果完全一致，不能继续读取武将文件中的手填路径。
		var actual_character_art_path: String = str(GameDatabase.get_character(character_id).get("art_path", ""))
		if character_source_path.is_empty() or actual_character_art_path != expected_character_art_path:
			printerr("SMOKE_FAIL character_artwork_auto_discovery=%s" % character_id)
			get_tree().quit(1)
			return
	# 未登记武将的显示回退；必须保留中文占位且不泄漏调用方传入的英文稳定 ID。
	var unknown_character_display_name: String = GameDatabase.resolve_character_name("unknown_character")
	if unknown_character_display_name != "未知武将":
		printerr("SMOKE_FAIL unknown_character_display_name=%s" % unknown_character_display_name)
		get_tree().quit(1)
		return
	# 【酒】正常使用目标模式；出牌阶段只能指定已受伤的使用者本人。
	# 当前规则允许满体力使用【酒】获得下一张【杀】加伤，因此目标模式固定为不检查伤势的自己。
	if str(GameDatabase.get_card("jiu").get("target_mode", "")) != "self":
		printerr("SMOKE_FAIL wine_target_mode")
		get_tree().quit(1)
		return
	# 【桃】正常使用目标模式；只有受伤的使用者本人可以在出牌阶段成为目标。
	if str(GameDatabase.get_card("tao").get("target_mode", "")) != "self_wounded":
		printerr("SMOKE_FAIL peach_target_mode")
		get_tree().quit(1)
		return
	# 【无中生有】正常使用目标模式；规则不允许把两张摸牌效果交给其他角色。
	if str(GameDatabase.get_card("wuzhong").get("target_mode", "")) != "self":
		printerr("SMOKE_FAIL ex_nihilo_target_mode")
		get_tree().quit(1)
		return
	# 无花色且没有聚合颜色覆写的虚拟牌必须是无色牌，不能错误触发仁王盾的黑色【杀】条件；
	# 丈八蛇矛等多材料转化的真实颜色由材料聚合结果通过 color_override 表达，不再固定为无色。
	var colorless_virtual_slash: CardInstance = CardInstance.new("sha", "none", 0)
	if colorless_virtual_slash.get_color() != "none":
		printerr("SMOKE_FAIL virtual_slash_color=%s" % colorless_virtual_slash.get_color())
		get_tree().quit(1)
		return
	for card_id_variant: Variant in GameDatabase.cards.keys():
		# 当前卡牌 ID；用于生成精确的源码与双名称失败信息。
		var card_id: String = str(card_id_variant)
		# 当前卡牌定义；双名称必须完整，效果函数由同 ID 的 CardDefinition 脚本提供。
		var definition: Dictionary = GameDatabase.get_card(card_id)
		if str(definition.get("original_name", "")).is_empty() or str(definition.get("custom_name", "")).is_empty():
			printerr("SMOKE_FAIL missing_dual_name=%s" % card_id)
			get_tree().quit(1)
			return
		if GameDatabase.get_card_definition(card_id) == null:
			printerr("SMOKE_FAIL missing_card_source=%s" % card_id)
			get_tree().quit(1)
			return
	# 八人身份分配数量；用于校验标准配置仍为1主2忠4反1内。
	var eight_player_identities: Array[String] = IdentityRules.new().get_distribution(8)
	if eight_player_identities.count("leader") != 1 or eight_player_identities.count("loyalist") != 2 or eight_player_identities.count("rebel") != 4 or eight_player_identities.count("renegade") != 1:
		printerr("SMOKE_FAIL identity_distribution_8")
		get_tree().quit(1)
		return
	# 群体牌行动顺序状态；使用者为三号位时，其他角色应从四号位开始并环形回到一、二号位。
	var target_order_state: GameState = GameState.new()
	for target_order_player_id: int in range(4):
		target_order_state.players.append(PlayerState.new(target_order_player_id, "玩家%d" % (target_order_player_id + 1)))
	# 群体牌规则服务；只读取测试状态，不执行卡牌效果。
	var target_order_rules: CardRuleService = CardRuleService.new(target_order_state)
	# 测试万箭齐发实体；目标模式来自正式卡牌配置。
	var target_order_card: CardInstance = CardInstance.new("wanjian", "heart", 1)
	# 规范化群体目标顺序；预期从三号位使用者的下家四号位开始环形排列。
	var normalized_target_order: Array[int] = target_order_rules.normalize_targets(2, target_order_card, [])
	if normalized_target_order != [3, 0, 1]:
		printerr("SMOKE_FAIL all_others_action_order=%s" % normalized_target_order)
		get_tree().quit(1)
		return
	# 测试铁索连环实体；用于校验手动多目标也会按当前回合角色起算的行动顺序重排。
	var manual_multi_target_card: CardInstance = CardInstance.new("tiesuo", "club", 10)
	# 规范后的手动多目标；使用者为三号位时，点击二、四号位应先结算四号位再结算二号位。
	var normalized_manual_target_order: Array[int] = target_order_rules.normalize_targets(2, manual_multi_target_card, [1, 3])
	if normalized_manual_target_order != [3, 1]:
		printerr("SMOKE_FAIL manual_multi_target_order=%s" % normalized_manual_target_order)
		get_tree().quit(1)
		return
	# 测试多目标【杀】；由技能增加目标数时也必须忽略玩家点击顺序，始终从使用者下家开始顺时针结算。
	var multi_target_slash: CardInstance = CardInstance.new("sha", "spade", 7)
	var normalized_multi_target_slash_order: Array[int] = target_order_rules.normalize_targets(2, multi_target_slash, [1, 3])
	if normalized_multi_target_slash_order != [3, 1]:
		printerr("SMOKE_FAIL multi_target_slash_order=%s" % normalized_multi_target_slash_order)
		get_tree().quit(1)
		return
	# 测试借刀杀人实体；使用时按“持刀者、被【杀】者”保留完整声明顺序，实际目标时机由卡牌源码另行剥离第二名角色。
	var borrow_sword_order_card: CardInstance = CardInstance.new("jiedao", "club", 12)
	if target_order_rules.normalize_targets(2, borrow_sword_order_card, [1, 3]) != [1, 3]:
		printerr("SMOKE_FAIL borrow_sword_target_semantics")
		get_tree().quit(1)
		return
	# 测试火攻实体；规则允许以包括使用者在内的任意一名有手牌角色为目标。
	var fire_attack_target_card: CardInstance = CardInstance.new("huogong", "heart", 2)
	# 使用者测试手牌；只用于满足【火攻】目标须有手牌的合法性条件。
	var fire_attack_actor_hand: CardInstance = CardInstance.new("shan", "heart", 2)
	target_order_state.players[2].hand.append(fire_attack_actor_hand)
	if not target_order_rules.list_legal_targets(2, fire_attack_target_card).has(2):
		printerr("SMOKE_FAIL fire_attack_self_target")
		get_tree().quit(1)
		return
	# 受伤自身【桃】测试牌；仅用于验证复用目标模式会过滤满体力使用者。
	var self_peach_card: CardInstance = CardInstance.new("tao", "heart", 3)
	# 受伤自身【酒】测试牌；与【桃】共用同一目标模式，正常出牌阶段同样不能指定满体力或其他角色。
	var self_wine_card: CardInstance = CardInstance.new("jiu", "diamond", 9)
	# 满体力时的【桃】候选；不应产生任何合法目标。
	var healthy_peach_targets: Array[int] = target_order_rules.list_legal_targets(2, self_peach_card)
	if not healthy_peach_targets.is_empty():
		printerr("SMOKE_FAIL healthy_peach_targets=%s" % healthy_peach_targets)
		get_tree().quit(1)
		return
	# 满体力时的【酒】候选；不应产生任何合法目标。
	# 当前规则修正后满体力仍可使用【酒】，唯一合法目标必须是使用者本人。
	var healthy_wine_targets: Array[int] = target_order_rules.list_legal_targets(2, self_wine_card)
	if healthy_wine_targets != [2]:
		printerr("SMOKE_FAIL healthy_wine_targets=%s" % healthy_wine_targets)
		get_tree().quit(1)
		return
	# 受伤后的使用者体力；降低1点后【桃】应只允许自动锁定自己。
	target_order_state.players[2].hp = 3
	# 受伤自身【桃】候选；唯一目标必须为使用者本人。
	var wounded_peach_targets: Array[int] = target_order_rules.list_legal_targets(2, self_peach_card)
	if wounded_peach_targets != [2]:
		printerr("SMOKE_FAIL wounded_peach_targets=%s" % wounded_peach_targets)
		get_tree().quit(1)
		return
	# 受伤自身【酒】候选；唯一目标同样必须为使用者本人。
	var wounded_wine_targets: Array[int] = target_order_rules.list_legal_targets(2, self_wine_card)
	if wounded_wine_targets != [2]:
		printerr("SMOKE_FAIL wounded_wine_targets=%s" % wounded_wine_targets)
		get_tree().quit(1)
		return
	# 【无中生有】测试牌；用于验证其他角色不会通过手工构造目标绕过自身限制。
	var self_draw_card: CardInstance = CardInstance.new("wuzhong", "heart", 4)
	# 测试出牌阶段玩家；完整使用校验需要与测试使用者一致的回合和阶段状态。
	target_order_state.current_player_id = 2
	# 测试出牌阶段名称；完整使用校验只允许在 play 阶段执行。
	target_order_state.current_phase = "play"
	# 【无中生有】归属区域；使用牌必须位于使用者可用的手牌区域。
	self_draw_card.zone = "hand"
	# 【无中生有】归属玩家；与手牌区域共同构成实体牌来源校验。
	self_draw_card.owner_id = 2
	target_order_state.players[2].hand.append(self_draw_card)
	if not target_order_rules.validate_use(2, self_draw_card, [1]).contains("只能以自己"):
		printerr("SMOKE_FAIL ex_nihilo_other_target")
		get_tree().quit(1)
		return
	# 纯数据选将服务；验证领袖先选、默认5张候选、其他玩家同时确认和完成前隐藏选择。
	var selection_service: CharacterSelectionService = CharacterSelectionService.new()
	# 测试选将随机源；固定种子保证候选断言可复现且不依赖系统时间。
	var selection_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	selection_rng.seed = 20260715
	# 测试玩家状态；0号领袖先选，1号和2号代表随后同时选将的其他玩家。
	var selection_players: Array[PlayerState] = [PlayerState.new(0, "领袖"), PlayerState.new(1, "玩家二"), PlayerState.new(2, "玩家三")]
	selection_players[0].identity = "leader"
	selection_players[1].identity = "loyalist"
	selection_players[2].identity = "rebel"
	# 测试武将 ID 数组；使用正式数据库全部武将，候选数量应恰好为默认5张且单列表不重复。
	var selection_character_ids: Array[String] = []
	for character_id_variant: Variant in GameDatabase.characters.keys():
		selection_character_ids.append(str(character_id_variant))
	if not selection_service.begin(selection_players, selection_character_ids, 5, selection_rng).is_empty():
		printerr("SMOKE_FAIL character_selection_begin")
		get_tree().quit(1)
		return
	var leader_candidates: Array[String] = selection_service.get_candidates(0)
	if selection_service.phase != CharacterSelectionService.PHASE_LEADER or leader_candidates.size() != 5 or selection_service.can_player_select(1):
		printerr("SMOKE_FAIL character_selection_leader_phase")
		get_tree().quit(1)
		return
	# 领袖确认候选首项后立即进入其他玩家同时选将阶段，并在所有观察者快照中公开领袖武将。
	var selected_leader_character_id: String = leader_candidates[0]
	if not selection_service.select_character(0, selected_leader_character_id).is_empty() or selection_service.phase != CharacterSelectionService.PHASE_OTHERS or str(selection_service.to_dict(2).get("leader_character_id", "")) != selected_leader_character_id:
		printerr("SMOKE_FAIL character_selection_leader_reveal")
		get_tree().quit(1)
		return
	# 玩家二确认后，玩家三只能看到完成状态而不能看到玩家二具体选择；全员完成前阶段不得结束。
	var player_two_choice: String = selection_service.get_candidates(1)[0]
	selection_service.select_character(1, player_two_choice)
	var player_three_snapshot: Dictionary = selection_service.to_dict(2)
	if selection_service.phase != CharacterSelectionService.PHASE_OTHERS or player_three_snapshot.has("selections_by_player") or str(player_three_snapshot.get("local_selected_character_id", "")) == player_two_choice:
		printerr("SMOKE_FAIL character_selection_hidden_choices")
		get_tree().quit(1)
		return
	# 玩家三最终选择；候选池扩充后固定种子可能让首项与已占用武将重合，因此按候选顺序提交首个仍合法项。
	var player_three_selected: bool = false
	for player_three_candidate: String in selection_service.get_candidates(2):
		if selection_service.select_character(2, player_three_candidate).is_empty():
			player_three_selected = true
			break
	if not player_three_selected or selection_service.phase != CharacterSelectionService.PHASE_COMPLETE:
		printerr("SMOKE_FAIL character_selection_complete")
		get_tree().quit(1)
		return
	# 无名杀式手牌布局组件；实例化用于保证全局类、导出参数和基础显示数值可被无头环境解析。
	var hand_layout: DecadeHandContainer = DecadeHandContainer.new()
	if hand_layout.card_size != Vector2(111.0, 148.0) or not is_equal_approx(hand_layout.minimum_visible_width, 64.0) or not is_equal_approx(hand_layout.selected_lift, 18.0) or not is_equal_approx(hand_layout.content_height, 175.0):
		printerr("SMOKE_FAIL decade_hand_layout_defaults")
		get_tree().quit(1)
		return
	# 手牌滚动视口；400像素宽度可让5张牌压缩展示但无需滑条，用于验证悬停不会改变其他手牌位置或内容宽度。
	var hand_scroll: ScrollContainer = ScrollContainer.new()
	# 当前视口高度与1.06倍悬停牌面向上取整后的156.88像素一致，使用157像素避免裁切。
	hand_scroll.size = Vector2(400.0, 157.0)
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_scroll.add_child(hand_layout)
	# 布局测试卡牌；五张正式牌面用于形成低于完整牌宽、但高于最小露出宽度的压缩间距。
	var layout_cards: Array[CardView] = []
	for layout_card_index: int in range(5):
		# 当前布局测试牌；无需绑定规则实体，只验证正式 CardView 的位置、悬停状态与层级。
		var layout_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
		hand_layout.add_child(layout_card)
		layout_cards.append(layout_card)
	hand_layout.call("_layout_cards")
	# 正常布局位置；悬停后除当前放大牌的缩放补偿外，其余手牌必须保持原位。
	var base_card_positions: Array[Vector2] = []
	for layout_card: CardView in layout_cards:
		base_card_positions.append(layout_card.position)
	# 正常布局总宽度；悬停不得改变该值或额外触发滑条。
	var base_hand_content_width: float = hand_layout.custom_minimum_size.x
	layout_cards[2].set("_is_hovered", true)
	hand_layout.refresh_card_states()
	hand_layout.call("_layout_cards")
	# 非悬停牌位置是否保持稳定；默认true，任一其他手牌被自动让位时改为false。
	var non_hovered_cards_stay_fixed: bool = true
	for layout_card_index: int in range(layout_cards.size()):
		if layout_card_index != 2 and not layout_cards[layout_card_index].position.is_equal_approx(base_card_positions[layout_card_index]):
			non_hovered_cards_stay_fixed = false
			break
	# 当前悬停牌；用于验证理论放大后顶部和底部都完整位于157像素容器内。
	var hovered_layout_card: CardView = layout_cards[2]
	# 悬停牌放大后的底边；位置已由布局组件补偿并限制到容器顶部以内。
	var hovered_card_bottom: float = hovered_layout_card.position.y + hand_layout.card_size.y * hovered_layout_card.hover_scale
	if not non_hovered_cards_stay_fixed or layout_cards[2].z_index != CardView.HOVER_Z_INDEX or not is_equal_approx(hand_layout.custom_minimum_size.x, base_hand_content_width):
		printerr("SMOKE_FAIL hand_hover_stability fixed=%s width=%s/%s" % [non_hovered_cards_stay_fixed, hand_layout.custom_minimum_size.x, base_hand_content_width])
		get_tree().quit(1)
		return
	if hovered_layout_card.position.y < 0.0 or hovered_card_bottom > hand_layout.content_height + 0.01:
		printerr("SMOKE_FAIL hand_hover_bounds top=%s bottom=%s height=%s" % [hovered_layout_card.position.y, hovered_card_bottom, hand_layout.content_height])
		get_tree().quit(1)
		return
	# 额外手牌；超过64像素最小露出宽度仍无法容纳时，内容宽度必须溢出并由自动滑条接管。
	for overflow_card_index: int in range(3):
		# 当前溢出测试牌；加入后总数为8张，400像素视口无法按最小露出宽度完整展示。
		var overflow_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
		hand_layout.add_child(overflow_card)
		layout_cards.append(overflow_card)
	layout_cards[2].set("_is_hovered", false)
	hand_layout.refresh_card_states()
	hand_layout.call("_layout_cards")
	if hand_layout.custom_minimum_size.x <= hand_scroll.size.x:
		printerr("SMOKE_FAIL hand_scroll_threshold content=%s viewport=%s" % [hand_layout.custom_minimum_size.x, hand_scroll.size.x])
		get_tree().quit(1)
		return
	hand_scroll.free()
	# 可编辑武将牌场景实例；根节点必须是 Node2D，固定牌面尺寸由 card_size 与子视觉节点共同表达。
	var player_card_template: PlayerTargetView = PLAYER_TARGET_VIEW_SCENE.instantiate() as PlayerTargetView
	# 入树前的静态预览体力圆点数量；场景应预置三绿一暗共4枚，正式运行后会按快照重建。
	var static_preview_health_pip_count: int = (player_card_template.get_node("HealthFrame/HealthPips") as VBoxContainer).get_child_count()
	if player_card_template.get_class() != "Node2D" or player_card_template.card_size != Vector2(148.35, 197.8):
		printerr("SMOKE_FAIL player_card_node2d size=%s" % player_card_template.card_size)
		get_tree().quit(1)
		return
	player_card_template.visible = true
	get_tree().root.add_child(player_card_template)
	await get_tree().process_frame
	# 标准4/4体力预览快照；运行时几何必须与武将牌场景中保存的默认预览位置和尺寸完全一致。
	player_card_template.configure_snapshot({"player_id":0, "alive":true, "hp":4, "max_hp":4, "hand_count":4, "display_name":"玩家1", "character_id":"", "identity":"leader", "equipment":{}, "judgment_area":[]})
	await get_tree().process_frame
	# 武将牌独立输入区域；必须覆盖完整牌面，保证 Node2D 根节点不依赖按钮继承处理点击与拖放。
	var player_card_input_area: PlayerTargetInputArea = player_card_template.get_node("InputArea") as PlayerTargetInputArea
	if player_card_template.card_size != Vector2(148.35, 197.8) or (player_card_template.get_node("CardBody") as Panel).size != Vector2(148.35, 197.8) or player_card_input_area.size != Vector2(148.35, 197.8):
		printerr("SMOKE_FAIL player_card_runtime_size=%s" % player_card_template.card_size)
		get_tree().quit(1)
		return
	# 编辑器武将牌预览；座次不属于牌面节点树，体力容器预置三绿一暗四枚圆点以呈现标准3/4体力。
	# 编辑器插画槽；原生尺寸为141.35×190.8像素，只扩展插画宽度以形成3:4武将牌。
	var preview_artwork: TextureRect = player_card_template.get_node("Artwork") as TextureRect
	# 编辑器武将名竖条；缩小至22像素宽，避免占据过多插画区域；运行时按单字生成子标签以压缩间隔号“·”的行高。
	var preview_character_name: Label = player_card_template.get_node("CharacterName") as Label
	# 编辑器势力徽记；缩小至26×26像素，保留识别所需的最小尺寸。
	var preview_faction_badge: Label = player_card_template.get_node("FactionBadge") as Label
	# 编辑器手牌角标；缩小至24×24像素，降低对插画左下角的遮挡。
	var preview_hand_count: Label = player_card_template.get_node("HandCount") as Label
	# 编辑器身份徽记；进入场景树后保持23×20像素，验证静态场景内的信息控件规格。
	var preview_identity_badge: Label = player_card_template.get_node("IdentityBadge") as Label
	# 编辑器体力列；正式快照会按体力上限重建内容并动态调整右下角梯形尺寸。
	var preview_health_column: VBoxContainer = player_card_template.get_node("HealthFrame/HealthPips") as VBoxContainer
	# 编辑器体力边框；使用不透明梯形并按圆点数量缩放，默认空快照保持单枚圆点的最小高度。
	var preview_health_frame: Control = player_card_template.get_node("HealthFrame") as Control
	# 场景内体力框背景；必须直接属于武将牌场景，方便编辑器调整颜色与层级。
	var preview_health_background: Panel = player_card_template.get_node("HealthFrame/Background") as Panel
	# 场景内体力框描边；必须直接属于武将牌场景，并使用与武将牌一致的右下圆角几何。
	var preview_health_border: Line2D = player_card_template.get_node("HealthFrame/Border") as Line2D
	# 判定区组件；根节点中心线位于武将牌底边，并在运行时生成菱形标记。
	var preview_public_zone: JudgmentZoneView = player_card_template.get_node("PublicZone") as JudgmentZoneView
	# 角色状态覆盖组件；替代旧 Status 标签，集中处理阵亡滤镜与横置链条。
	var preview_state_overlay: PlayerStateOverlay = player_card_template.get_node("StateOverlay") as PlayerStateOverlay
	if player_card_template.has_node("Seat") or player_card_template.has_node("Status") or static_preview_health_pip_count != 4 or preview_health_background == null or preview_health_border == null or preview_health_border.visible or not preview_artwork.position.is_equal_approx(Vector2(4.0, 4.0)) or not preview_artwork.size.is_equal_approx(Vector2(141.35, 190.8)) or not preview_character_name.size.is_equal_approx(Vector2(22.0, 93.0)) or not preview_faction_badge.size.is_equal_approx(Vector2(26.0, 26.0)) or not preview_hand_count.size.is_equal_approx(Vector2(24.0, 24.0)) or preview_hand_count.visible or not preview_identity_badge.size.is_equal_approx(Vector2(23.0, 20.0)) or preview_identity_badge.visible or not preview_health_frame.position.is_equal_approx(Vector2(124.35, 115.8)) or not preview_health_frame.size.is_equal_approx(Vector2(24.0, 82.0)) or not is_equal_approx(preview_public_zone.position.y + preview_public_zone.marker_size * 0.5, player_card_template.card_size.y) or preview_state_overlay.card_size != player_card_template.card_size or player_card_template.health_pip_font_size != 18 or player_card_template.health_pip_separation != -10 or preview_health_column.get_theme_constant("separation") != -10:
		printerr("SMOKE_FAIL player_card_scene_preview seat=%s status=%s static_pips=%d artwork_position=%s artwork=%s name=%s faction=%s hand=%s identity=%s health_frame=%s/%s public=%s" % [player_card_template.has_node("Seat"), player_card_template.has_node("Status"), static_preview_health_pip_count, preview_artwork.position, preview_artwork.size, preview_character_name.size, preview_faction_badge.size, preview_hand_count.size, preview_identity_badge.size, preview_health_frame.position, preview_health_frame.size, preview_public_zone.position])
		get_tree().quit(1)
		return
	# 游戏内座位容器；座次标签必须位于武将牌下方，容器总高度额外包含18像素字体进入场景树后产生的26像素真实控件高度。
	var player_seat_slot: Control = PLAYER_SEAT_SLOT_SCENE.instantiate() as Control
	get_tree().root.add_child(player_seat_slot)
	await get_tree().process_frame
	# 运行时座次标签；应为座位容器的独立子节点，不能回流到武将牌场景。
	var runtime_seat: Label = player_seat_slot.get_node("Seat") as Label
	# 容器内复用的武将牌；尺寸必须继续保持统一的148.35×197.8像素规格。
	var runtime_player_card: PlayerTargetView = player_seat_slot.get_node("PlayerTargetView") as PlayerTargetView
	if player_seat_slot.size != Vector2(148.35, 223.8) or runtime_player_card.card_size != Vector2(148.35, 197.8) or runtime_seat.position != Vector2(0.0, 197.8) or runtime_seat.size != Vector2(148.35, 26.0) or runtime_seat.get_theme_font_size("font_size") != 18:
		printerr("SMOKE_FAIL player_seat_slot_layout slot=%s card=%s seat_position=%s seat_size=%s seat_font=%d" % [player_seat_slot.size, runtime_player_card.card_size, runtime_seat.position, runtime_seat.size, runtime_seat.get_theme_font_size("font_size")])
		get_tree().quit(1)
		return
	get_tree().root.remove_child(player_seat_slot)
	player_seat_slot.free()
	# 统一武将牌组件；直接使用场景实例，用于校验装备横条高度与五槽显示上限。
	var player_card_view: PlayerTargetView = player_card_template
	if not is_equal_approx(player_card_view.equipment_row_height, 15.0) or player_card_view.maximum_equipment_rows != 5:
		printerr("SMOKE_FAIL player_card_reference_layout_defaults")
		get_tree().quit(1)
		return
	# 武将牌固定尺寸；装备、名称和体力等内容只在正式牌面子节点中渲染，根节点保持 Node2D。
	if player_card_view.card_size != Vector2(148.35, 197.8) or (player_card_view.get_node("CardBody") as Panel).size != Vector2(148.35, 197.8):
		printerr("SMOKE_FAIL player_card_fixed_size")
		get_tree().quit(1)
		return
	# 带装备的角色牌测试快照；两件公开装备分别覆盖武器与防具槽，用于验证横条实际生成数量。
	var equipped_player_snapshot: Dictionary = {
		"player_id":1,
		"display_name":"测试玩家",
		"character_id":"gepard",
		"identity":"rebel",
		"hp":3,
		"max_hp":4,
		"alive":true,
		"chained":true,
		"hand_count":4,
		"equipment":{
			"weapon":{"definition_id":"qinglong", "suit":"spade", "rank":5},
			"armor":{"definition_id":"bagua", "suit":"spade", "rank":2},
			"treasure":{"definition_id":"muniu", "suit":"diamond", "rank":5},
		},
		"judgment_area":[
			{"definition_id":"lebu", "suit":"heart", "rank":6},
			{"definition_id":"bingliang", "suit":"club", "rank":4},
		],
		"wooden_ox_storage_count":3,
	}
	# 测试武将定义；提供武将名和势力 ID，使统一牌面能够生成完整覆盖层。
	var equipped_character_definition: Dictionary = GameDatabase.get_character("gepard")
	# 测试势力定义；提供圆徽简称与主题颜色，验证数据驱动入口可正常传递。
	var equipped_faction_definition: Dictionary = GameDatabase.get_faction(str(equipped_character_definition.get("faction", "")))
	player_card_view.configure_snapshot(equipped_player_snapshot, equipped_character_definition, false, equipped_faction_definition)
	# 黑白太空主题中的势力徽记；主题不得把武将原势力色强制改成中性灰。
	var configured_faction_color: Color = Color.from_string(str(equipped_faction_definition.get("color", "526b70")), Color("526b70"))
	# 运行时势力徽记样式；背景应继续由原势力色压暗生成，而不是使用主题中性占位色。
	var configured_faction_style: StyleBoxFlat = (player_card_view.get_node("FactionBadge") as Label).get_theme_stylebox("normal") as StyleBoxFlat
	if not configured_faction_style.bg_color.is_equal_approx(configured_faction_color.darkened(0.28)):
		printerr("SMOKE_FAIL space_style_faction_color=%s/%s" % [configured_faction_style.bg_color, configured_faction_color])
		get_tree().quit(1)
		return
	# 实际装备横条数量；装备承载层是角色牌的直接子节点，其富文本子节点一一对应公开装备。
	var rendered_equipment_row_count: int = 0
	# 实际装备横条是否全部保持60×15像素；默认true，发现任意尺寸不符条目后改为false。
	# 当前变量继续表示全部装备条尺寸是否正确，目标宽度已调整为武将插画的141.35像素。
	var equipment_rows_keep_original_size: bool = true
	# 货运星槎装备条是否显示公开存牌数量；默认false，找到对应文本后改为true。
	var wooden_ox_count_visible: bool = false
	for child: Node in player_card_view.get_children():
		for grandchild: Node in child.get_children():
			if grandchild is RichTextLabel:
				rendered_equipment_row_count += 1
				if (grandchild as RichTextLabel).size != Vector2(141.35, 15.0):
					equipment_rows_keep_original_size = false
				if (grandchild as RichTextLabel).text.contains("货运星槎（3）"):
					wooden_ox_count_visible = true
	# 判定区生成节点数；每张牌包含一个旋转背景与一个水平首字标签。
	var judgment_marker_child_count: int = preview_public_zone.get_child_count()
	# 体力圆点数组；3/4体力时顶部第一枚应变暗、其余三枚保持绿色，表示从上往下扣血。
	var runtime_health_pips: Array[Node] = preview_health_column.get_children()
	# 顶部体力圆点颜色；用于验证已损失体力从列表首项开始显示。
	var first_health_pip_color: Color = (runtime_health_pips[0] as Label).get_theme_color("font_color")
	# 第二枚体力圆点颜色；用于验证剩余体力紧随暗色圆点向下排列。
	var second_health_pip_color: Color = (runtime_health_pips[1] as Label).get_theme_color("font_color")
	if rendered_equipment_row_count != 3 or not equipment_rows_keep_original_size or not wooden_ox_count_visible or judgment_marker_child_count != 4 or not first_health_pip_color.is_equal_approx(BattleUIStyle.get_color("health_lost")) or not second_health_pip_color.is_equal_approx(BattleUIStyle.get_color("health_full")) or not bool(preview_state_overlay.get("_is_chained")):
		printerr("SMOKE_FAIL player_card_equipment_rows=%d" % rendered_equipment_row_count)
		get_tree().quit(1)
		return
	# 两点体力警告快照；4点上限角色剩余2点时，所有仍点亮的体力圆点必须变为黄色。
	var warning_health_snapshot: Dictionary = equipped_player_snapshot.duplicate(true)
	warning_health_snapshot["hp"] = 2
	player_card_view.configure_snapshot(warning_health_snapshot, equipped_character_definition, false, equipped_faction_definition)
	# 两点体力时首枚仍点亮圆点；顶部两枚为已损失占位，因此索引2应使用黄色警告色。
	var warning_health_color: Color = ((preview_health_column.get_child(2)) as Label).get_theme_color("font_color")
	# 一点体力危险快照；4点上限角色剩余1点时，最后一枚仍点亮圆点必须变为红色。
	var danger_health_snapshot: Dictionary = equipped_player_snapshot.duplicate(true)
	danger_health_snapshot["hp"] = 1
	player_card_view.configure_snapshot(danger_health_snapshot, equipped_character_definition, false, equipped_faction_definition)
	# 一点体力时唯一仍点亮圆点；索引3对应底部剩余体力。
	var danger_health_color: Color = ((preview_health_column.get_child(3)) as Label).get_theme_color("font_color")
	# 低上限角色快照；2点上限角色即使只剩1点体力也必须保持绿色，避免天然低上限被长期标为危险状态。
	var low_maximum_health_snapshot: Dictionary = equipped_player_snapshot.duplicate(true)
	low_maximum_health_snapshot["hp"] = 1
	low_maximum_health_snapshot["max_hp"] = 2
	player_card_view.configure_snapshot(low_maximum_health_snapshot, equipped_character_definition, false, equipped_faction_definition)
	# 2点上限角色的剩余体力圆点；索引1是唯一点亮圆点，颜色必须保持绿色。
	var low_maximum_health_color: Color = ((preview_health_column.get_child(1)) as Label).get_theme_color("font_color")
	# 1点上限角色快照；满体力时唯一圆点同样必须保持绿色。
	var single_maximum_health_snapshot: Dictionary = equipped_player_snapshot.duplicate(true)
	single_maximum_health_snapshot["hp"] = 1
	single_maximum_health_snapshot["max_hp"] = 1
	player_card_view.configure_snapshot(single_maximum_health_snapshot, equipped_character_definition, false, equipped_faction_definition)
	# 1点上限角色的唯一体力圆点颜色；不得因当前体力等于1而套用普通角色的红色危险语义。
	var single_maximum_health_color: Color = ((preview_health_column.get_child(0)) as Label).get_theme_color("font_color")
	if not warning_health_color.is_equal_approx(BattleUIStyle.get_color("health_warning")) or not danger_health_color.is_equal_approx(BattleUIStyle.get_color("health_danger")) or not low_maximum_health_color.is_equal_approx(BattleUIStyle.get_color("health_full")) or not single_maximum_health_color.is_equal_approx(BattleUIStyle.get_color("health_full")):
		printerr("SMOKE_FAIL health_threshold_colors=%s/%s/%s/%s" % [warning_health_color, danger_health_color, low_maximum_health_color, single_maximum_health_color])
		get_tree().quit(1)
		return
	player_card_view.configure_snapshot(equipped_player_snapshot, equipped_character_definition, false, equipped_faction_definition)
	# 阵亡状态快照；覆盖层应显示黑白滤镜与红色“阵亡”，并让阵亡表现优先于横置链条。
	equipped_player_snapshot["alive"] = false
	player_card_view.configure_snapshot(equipped_player_snapshot, equipped_character_definition, false, equipped_faction_definition)
	if not (preview_state_overlay.get_node("DeathBackBuffer") as BackBufferCopy).visible or not (preview_state_overlay.get_node("DeathFilter") as ColorRect).visible or not (preview_state_overlay.get_node("DeathLabel") as Label).visible or (preview_state_overlay.get_node("DeathLabel") as Label).text != "阵亡":
		printerr("SMOKE_FAIL player_death_overlay")
		get_tree().quit(1)
		return
	get_tree().root.remove_child(player_card_view)
	player_card_view.free()
	# 主场景预览实例；只读取菜单与控制器默认参数，不进入场景树以避免启动正式对局。
	var main_scene_preview: Control = MAIN_SCENE.instantiate() as Control
	# 主场景手牌滚动区；自动模式保证只有内容超过最小压缩宽度时才出现滑条。
	var main_hand_scroll: ScrollContainer = main_scene_preview.get_node("HandPanel/HandScroll") as ScrollContainer
	if main_hand_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_AUTO:
		printerr("SMOKE_FAIL hand_scroll_mode=%d" % main_hand_scroll.horizontal_scroll_mode)
		get_tree().quit(1)
		return
	# 主场景对局控制器；直接运行场景时由该节点的导出默认值决定开局人数。
	var main_scene_match_controller: MatchController = main_scene_preview.get_node("MatchController") as MatchController
	if main_scene_match_controller.default_player_count != 8 or main_scene_match_controller.first_turn_seat_number != 1 or not main_scene_match_controller.randomize_local_human_seat or main_scene_match_controller.default_deck_id != "standard_162":
		printerr("SMOKE_FAIL default_player_count=%d" % main_scene_match_controller.default_player_count)
		get_tree().quit(1)
		return
	# 正式卡牌组件实例；验证根节点为 Node2D、牌面模型尺寸为111×148且不再继承按钮。
	var card_view: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 卡牌独立输入区域；场景静态尺寸必须与正式牌面一致，进入任意容器后都能保持完整命中范围。
	var card_input_area: CardInputArea = card_view.get_node("InputArea") as CardInputArea
	# 场景内置纸张面板；编辑器预览必须保存与运行时默认基本牌一致的纸色、边框与阴影。
	var card_body: Panel = card_view.get_node("CardBody") as Panel
	# 场景内置默认样式；运行时只覆盖状态，不应依赖桌面临时创建另一套卡牌 UI。
	var card_body_style: StyleBoxFlat = card_body.get_theme_stylebox("panel") as StyleBoxFlat
	# 场景内置花色点数预览；用于保证直接打开场景时能看到完整牌面。
	var preview_corner: Label = card_view.get_node("CardBody/Corner") as Label
	# 场景内置牌名预览；默认与脚本未绑定实体牌时的显示保持一致。
	var preview_name: Label = card_view.get_node("CardBody/Name") as Label
	# 场景内置类别预览；手牌、弹窗和动画实例都复用该标签节点。
	var preview_type: Label = card_view.get_node("CardBody/Type") as Label
	if card_view.get_class() != "Node2D" or not is_equal_approx(card_view.card_width, 111.0) or not is_equal_approx(card_view.card_height, 148.0) or card_view.get_card_size() != Vector2(111.0, 148.0) or card_input_area.size != Vector2(111.0, 148.0) or card_body_style == null or not card_body_style.bg_color.is_equal_approx(Color("e8dcc3")) or preview_corner.text != "♠7" or preview_name.text != "杀" or preview_type.text != "基本牌":
		printerr("SMOKE_FAIL card_view_node2d_defaults")
		get_tree().quit(1)
		return
	get_tree().root.add_child(card_view)
	# 黑白太空主题的基本牌快照；主题只调整纸张与框架，顶部类别条必须保留基本牌类别色。
	var themed_basic_card: Dictionary = {"uid":70001, "definition_id":"sha", "suit":"spade", "rank":7}
	card_view.configure(themed_basic_card, GameDatabase.get_card("sha"), false, true)
	# 主题化类别条；颜色必须来自 `card_basic` 语义而不是统一灰色或全屏滤镜。
	var themed_accent_bar: ColorRect = card_view.get_node("CardBody/AccentBar") as ColorRect
	if not themed_accent_bar.color.is_equal_approx(BattleUIStyle.get_color("card_basic")):
		printerr("SMOKE_FAIL space_style_card_category=%s" % themed_accent_bar.color)
		get_tree().quit(1)
		return
	# 五种装备子类型的牌面类别文本；底部必须直接显示实际装备槽位，不再统一显示“装备牌”。
	var equipment_type_expectations: Dictionary = {
		"qinggang":"武器牌",
		"bagua":"防具牌",
		"chitu":"进攻坐骑牌",
		"dilu":"防御坐骑牌",
		"muniu":"宝物牌",
	}
	# 装备测试实体 UID；每次递增保证正式配置签名变化并刷新同一类别标签节点。
	var equipment_type_card_uid: int = 71000
	for equipment_definition_id: String in equipment_type_expectations:
		card_view.configure({"uid":equipment_type_card_uid, "definition_id":equipment_definition_id, "suit":"spade", "rank":1}, GameDatabase.get_card(equipment_definition_id), false, true)
		if preview_type.text != str(equipment_type_expectations[equipment_definition_id]):
			printerr("SMOKE_FAIL equipment_type_text=%s:%s" % [equipment_definition_id, preview_type.text])
			get_tree().quit(1)
			return
		equipment_type_card_uid += 1
	get_tree().root.remove_child(card_view)
	card_view.free()
	# 弃牌动画层；两张正式卡牌应同时从各自起点进入中央队列、保持水平铺开并在停留后全部淡出。
	var animation_layer: CardUseAnimationLayer = CardUseAnimationLayer.new()
	# 摸牌默认节奏；飞行、停留与淡出分别保持短时长，避免未来调整后重新出现拖慢摸牌的问题。
	if not is_equal_approx(animation_layer.draw_flight_duration, 0.24) or not is_equal_approx(animation_layer.draw_hold_duration, 0.10) or not is_equal_approx(animation_layer.draw_fade_duration, 0.18):
		printerr("SMOKE_FAIL draw_animation_defaults=%s/%s/%s" % [animation_layer.draw_flight_duration, animation_layer.draw_hold_duration, animation_layer.draw_fade_duration])
		get_tree().quit(1)
		return
	animation_layer.card_flight_duration = 0.01
	animation_layer.card_hold_duration = 0.08
	animation_layer.target_line_fade_duration = 0.04
	animation_layer.draw_flight_duration = 0.01
	animation_layer.draw_hold_duration = 0.01
	animation_layer.draw_fade_duration = 0.04
	animation_layer.target_line_draw_duration = 0.02
	animation_layer.queue_reflow_duration = 0.01
	get_tree().root.add_child(animation_layer)
	# 第一张动画牌；模拟一名其他玩家从左侧座位使用卡牌。
	var first_animation_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 第二张动画牌；模拟另一名玩家在前一张牌消失前继续使用卡牌。
	var second_animation_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	animation_layer.add_child(first_animation_card)
	animation_layer.add_child(second_animation_card)
	first_animation_card.position = Vector2(80.0, 120.0)
	second_animation_card.position = Vector2(900.0, 120.0)
	animation_layer.play_card(first_animation_card, first_animation_card.position, Vector2(500.0, 300.0), [Vector2(800.0, 200.0)])
	animation_layer.play_card(second_animation_card, second_animation_card.position, Vector2(500.0, 300.0), [])
	# 第一条目标线表现数据；必须保存来源、目标和动态延伸进度，确保不是一次性绘制静态整线。
	var first_line_presentation: Dictionary = animation_layer._line_presentations.get(1, {}) as Dictionary
	if first_line_presentation.get("target_positions", []) != [Vector2(800.0, 200.0)] or not first_line_presentation.has("progress"):
		printerr("SMOKE_FAIL target_line_presentation=%s" % first_line_presentation)
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.04).timeout
	if first_animation_card.rotation != 0.0 or second_animation_card.rotation != 0.0 or is_equal_approx(first_animation_card.position.x, second_animation_card.position.x):
		printerr("SMOKE_FAIL discard_animation_queue")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.04).timeout
	if animation_layer._line_presentations.has(1):
		printerr("SMOKE_FAIL target_line_fade_after_draw")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.3).timeout
	if animation_layer.get_child_count() != 0:
		printerr("SMOKE_FAIL discard_animation_cleanup=%d" % animation_layer.get_child_count())
		get_tree().quit(1)
		return
	# 三张连续摸牌动画；同一玩家摸几张就必须保留几张正式牌面，并按顺序形成可见堆叠。
	var first_draw_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 第二张摸牌动画；使用同一堆叠键但获得第二层偏移与层级。
	var second_draw_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 第三张摸牌动画；使用同一堆叠键并在前两张之后开始飞行。
	var third_draw_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	first_draw_card.configure_back(91001, false)
	second_draw_card.configure_back(91002, false)
	third_draw_card.configure_back(91003, false)
	animation_layer.add_child(first_draw_card)
	animation_layer.add_child(second_draw_card)
	animation_layer.add_child(third_draw_card)
	# 摸牌动画起点；模拟中央牌堆位置。
	var draw_start_position: Vector2 = Vector2(500.0, 260.0)
	# 摸牌动画终点；模拟同一玩家的手牌锚点。
	var draw_target_position: Vector2 = Vector2(700.0, 460.0)
	animation_layer.play_transfer(first_draw_card, draw_start_position, draw_target_position, "draw:0")
	animation_layer.play_transfer(second_draw_card, draw_start_position, draw_target_position, "draw:0")
	animation_layer.play_transfer(third_draw_card, draw_start_position, draw_target_position, "draw:0")
	await get_tree().create_timer(0.05).timeout
	# 当前摸牌堆叠数组；三张牌必须同时存在，不能被同坐标的单张替代表现覆盖。
	var draw_stack: Array = animation_layer._draw_transfer_stacks.get("draw:0", []) as Array
	# 第一层实时堆叠偏移；头部模式可能在补间抵达前唤醒计时器，因此只要求其已沿配置方向产生可见位移。
	var first_draw_stack_offset: Vector2 = second_draw_card.position - first_draw_card.position
	# 第二层实时堆叠偏移；应与第一层保持相同进度和方向，证明三张牌由同一并行补间稳定铺开。
	var second_draw_stack_offset: Vector2 = third_draw_card.position - second_draw_card.position
	if draw_stack.size() != 3 or first_draw_stack_offset.is_zero_approx() or second_draw_stack_offset.is_zero_approx() or (first_draw_stack_offset - second_draw_stack_offset).length() > 0.01 or first_draw_stack_offset.dot(animation_layer.draw_stack_offset) <= 0.0 or absf(first_draw_stack_offset.cross(animation_layer.draw_stack_offset)) > 0.01:
		printerr("SMOKE_FAIL draw_transfer_stack size=%d positions=%s/%s/%s" % [draw_stack.size(), first_draw_card.position, second_draw_card.position, third_draw_card.position])
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.2).timeout
	if animation_layer.get_child_count() != 0 or not animation_layer._draw_transfer_stacks.is_empty():
		printerr("SMOKE_FAIL draw_transfer_cleanup children=%d stacks=%s" % [animation_layer.get_child_count(), animation_layer._draw_transfer_stacks])
		get_tree().quit(1)
		return
	# 两次独立摸牌批次；首批两张必须同时居中飞行，另一名玩家的第二批也必须立即并行开始。
	animation_layer.card_flight_duration = 0.04
	animation_layer.card_hold_duration = 0.04
	animation_layer.target_line_fade_duration = 0.04
	animation_layer.draw_flight_duration = 0.04
	animation_layer.draw_hold_duration = 0.04
	animation_layer.draw_fade_duration = 0.04
	# 首批左侧牌背；与右侧牌背共同验证两张牌的整体居中与同步飞行。
	var first_batch_left_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 首批右侧牌背；与左侧牌背保持固定的对称间距。
	var first_batch_right_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	# 第二批牌背；用于验证不同玩家的摸牌批次不会被首批阻塞。
	var second_batch_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	first_batch_left_card.configure_back(91101, false)
	first_batch_right_card.configure_back(91102, false)
	second_batch_card.configure_back(91103, false)
	animation_layer.play_draw_transfer_batch([first_batch_left_card, first_batch_right_card], draw_start_position, draw_target_position)
	# 第二批目标锚点；模拟另一名玩家，使并行批次的独立整体居中可被直接验证。
	var second_draw_target_position: Vector2 = Vector2(900.0, 360.0)
	animation_layer.play_draw_transfer_batch([second_batch_card], draw_start_position, second_draw_target_position)
	# 两个批次均必须在提交当帧开始；不得因首批飞行、停留或淡出而隐藏第二批。
	if animation_layer._draw_transfer_batch_tweens.size() != 2 or not first_batch_left_card.visible or not first_batch_right_card.visible or not second_batch_card.visible:
		printerr("SMOKE_FAIL draw_batch_parallel initial=%s/%s/%s" % [animation_layer._draw_transfer_batch_tweens, first_batch_right_card.visible, second_batch_card.visible])
		get_tree().quit(1)
		return
	# 最后启动批次的飞行补间；两个批次使用相同持续时间并在同帧启动，等待它完成即可稳定校验全部最终落点。
	var last_batch_flight_tween: Tween = animation_layer._draw_transfer_batch_tweens.get(animation_layer._draw_transfer_batch_sequence) as Tween
	if last_batch_flight_tween == null:
		printerr("SMOKE_FAIL draw_batch_flight_tween_missing")
		get_tree().quit(1)
		return
	await last_batch_flight_tween.finished
	# 首批抵达后两张牌的整体中心必须等于目标锚点，且两张之间保持固定对称间距。
	# 首批牌面整体中心；以两张牌各自中心的平均值计算，不读取动画层的内部定位公式。
	var first_batch_center: Vector2 = (first_batch_left_card.position + first_batch_left_card.get_card_size() * 0.5 + first_batch_right_card.position + first_batch_right_card.get_card_size() * 0.5) * 0.5
	# 第二批单张中心；单张也必须立即抵达自己的目标锚点，不能继承首批玩家的位置。
	var second_batch_center: Vector2 = second_batch_card.position + second_batch_card.get_card_size() * 0.5
	if not first_batch_center.is_equal_approx(draw_target_position) or not is_equal_approx(first_batch_right_card.position.x - first_batch_left_card.position.x, animation_layer.draw_batch_card_spacing) or not second_batch_center.is_equal_approx(second_draw_target_position):
		printerr("SMOKE_FAIL draw_batch_parallel_center=%s/%s spacing=%s" % [first_batch_center, second_batch_center, first_batch_right_card.position.x - first_batch_left_card.position.x])
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.16).timeout
	if animation_layer.get_child_count() != 0 or not animation_layer._transfer_cards.is_empty() or not animation_layer._draw_transfer_batch_tweens.is_empty():
		printerr("SMOKE_FAIL draw_batch_cleanup children=%d cards=%s batches=%s" % [animation_layer.get_child_count(), animation_layer._transfer_cards, animation_layer._draw_transfer_batch_tweens])
		get_tree().quit(1)
		return
	# 重开中断牌面；模拟摸牌转移尚未完成时玩家立即从菜单重新开局。
	var interrupted_transfer_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	interrupted_transfer_card.configure_back(92001, false)
	animation_layer.add_child(interrupted_transfer_card)
	animation_layer.play_transfer(interrupted_transfer_card, draw_start_position, draw_target_position, "draw:restart")
	if animation_layer._transfer_cards.size() != 1 or animation_layer._transfer_tweens.size() != 1 or (animation_layer._draw_transfer_stacks.get("draw:restart", []) as Array).size() != 1:
		printerr("SMOKE_FAIL restart_transfer_not_registered")
		get_tree().quit(1)
		return
	animation_layer.clear_presentations()
	await get_tree().create_timer(0.2).timeout
	if animation_layer.get_child_count() != 0 or not animation_layer._transfer_cards.is_empty() or not animation_layer._transfer_tweens.is_empty() or not animation_layer._draw_transfer_stacks.is_empty():
		printerr("SMOKE_FAIL restart_transfer_cleanup children=%d cards=%s tweens=%s stacks=%s" % [animation_layer.get_child_count(), animation_layer._transfer_cards, animation_layer._transfer_tweens, animation_layer._draw_transfer_stacks])
		get_tree().quit(1)
		return
	# 重开后新牌面；验证清场代次不会阻止下一局的正常区域转移动画。
	var resumed_transfer_card: CardView = CARD_VIEW_SCENE.instantiate() as CardView
	resumed_transfer_card.configure_back(92002, false)
	animation_layer.add_child(resumed_transfer_card)
	animation_layer.play_transfer(resumed_transfer_card, draw_start_position, draw_target_position, "draw:after_restart")
	await get_tree().create_timer(0.2).timeout
	if animation_layer.get_child_count() != 0 or not animation_layer._transfer_cards.is_empty() or not animation_layer._transfer_tweens.is_empty() or not animation_layer._draw_transfer_stacks.is_empty():
		printerr("SMOKE_FAIL post_restart_transfer_cleanup")
		get_tree().quit(1)
		return
	get_tree().root.remove_child(animation_layer)
	animation_layer.free()
	# 右上角菜单组件；替代独立牌名和重开按钮，并默认保存8人作为下一局配置。
	var menu_button: Button = main_scene_preview.get_node("%MenuButton") as Button
	if menu_button.text != "菜单" or main_scene_preview.has_node("%NameModeButton") or main_scene_preview.has_node("%RestartButton"):
		printerr("SMOKE_FAIL match_menu_structure")
		get_tree().quit(1)
		return
	main_scene_preview.free()
	# 逻辑视口宽度；保持1280像素作为全部场景坐标和布局文档的统一设计基准。
	var viewport_width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	# 逻辑视口高度；保持720像素以维持十周年牌桌的16:9布局比例。
	var viewport_height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	# 默认启动窗口宽度；使用1152像素为系统窗口边框预留屏幕空间，同时由画布拉伸保持完整界面。
	var initial_window_width: int = int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))
	# 默认启动窗口高度；使用648像素避免720高屏幕上的标题栏和任务栏把底部界面推到屏幕外。
	var initial_window_height: int = int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	# 画布拉伸宽高比策略；固定为keep以保证非16:9窗口完整显示逻辑视口而不是裁切底部或右侧内容。
	var stretch_aspect: String = str(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	if viewport_width != 1280 or viewport_height != 720 or initial_window_width != 1152 or initial_window_height != 648 or stretch_aspect != "keep":
		printerr("SMOKE_FAIL safe_window_size viewport=%dx%d window=%dx%d aspect=%s" % [viewport_width, viewport_height, initial_window_width, initial_window_height, stretch_aspect])
		get_tree().quit(1)
		return

	_controller = MatchController.new()
	_controller.name = "MatchController"
	_controller.local_human_player_id = -1
	_controller.ai_action_delay_seconds = 0.0
	# 测试规则事件总线；节点名必须与正式控制器的组件约定一致。
	var event_bus: RuleEventBus = RuleEventBus.new()
	event_bus.name = "RuleEventBus"
	_controller.add_child(event_bus)
	# 测试 AI 调度组件；四名玩家均会登记基础策略。
	var ai_coordinator: AICoordinator = AICoordinator.new()
	ai_coordinator.name = "AICoordinator"
	_controller.add_child(ai_coordinator)
	# 测试通信网关；保持离线模式，不接入外部网络。
	var network_gateway: NetworkGateway = NetworkGateway.new()
	if NetworkGateway.PROTOCOL_VERSION != 11:
		printerr("SMOKE_FAIL protocol_version=%d" % NetworkGateway.PROTOCOL_VERSION)
		get_tree().quit(1)
		return
	network_gateway.name = "NetworkGateway"
	_controller.add_child(network_gateway)
	get_tree().root.add_child(_controller)
	await get_tree().process_frame
	# 无头测试 AI 延迟；控制器入树时会读取全局菜单设置，因此在 _ready 完成后再次覆盖为0秒，保证固定帧数能推进且收尾不遗留长计时器。
	_controller.ai_action_delay_seconds = 0.0
	# 总烟雾测试包含大量同步阶段与死亡转交断言，关闭表现节奏并由专项测试单独验证正式间隔。
	_controller.game_flow_interval_seconds = 0.0
	# 借刀动作枚举状态；三名存活角色足以覆盖使用者、唯一持刀者与后续被杀者的牌效条件。
	var borrow_sword_action_state: GameState = GameState.new()
	# 借刀动作测试座次 ID；依次创建0至2号三名玩家，修改人数会改变持刀者是否存在合法攻击对象。
	for borrow_sword_player_id: int in range(3):
		# 借刀动作测试玩家；默认存活且相邻座次可满足持刀者的基础攻击范围。
		var borrow_sword_player: PlayerState = PlayerState.new(borrow_sword_player_id, "玩家%d" % (borrow_sword_player_id + 1))
		borrow_sword_action_state.players.append(borrow_sword_player)
	borrow_sword_action_state.current_player_id = 0
	borrow_sword_action_state.current_phase = "play"
	# 借刀测试实体；位于一号位使用者手牌，供统一合法动作入口执行真实枚举。
	var borrow_sword_action_card: CardInstance = CardInstance.new("jiedao", "club", 12)
	borrow_sword_action_card.zone = "hand"
	borrow_sword_action_card.owner_id = 0
	borrow_sword_action_state.players[0].hand.append(borrow_sword_action_card)
	# 持刀者测试武器；装备后令二号位成为借刀杀人的合法第一目标。
	var borrow_sword_test_weapon: CardInstance = CardInstance.new("qinggang", "spade", 6)
	borrow_sword_test_weapon.zone = "equipment"
	borrow_sword_test_weapon.owner_id = 1
	borrow_sword_action_state.players[1].equipment["weapon"] = borrow_sword_test_weapon
	_controller.state = borrow_sword_action_state
	_controller.card_rules = CardRuleService.new(borrow_sword_action_state)
	# 借刀合法动作；调用卡牌源码的复杂目标钩子，确保动态端口接收到严格的 Array[int]。
	var borrow_sword_legal_actions: Array[Dictionary] = _controller.get_legal_actions(0)
	# 是否找到同时指定二号位持刀者与三号位被【杀】者的标准动作；默认false，匹配完整两目标声明后置为true。
	var found_borrow_sword_action: bool = false
	# 当前借刀合法动作；逐项读取目标数组，不修改控制器返回的动作内容。
	for borrow_sword_action: Dictionary in borrow_sword_legal_actions:
		if borrow_sword_action.get("target_ids", []) == [1, 2]:
			found_borrow_sword_action = true
			break
	if not found_borrow_sword_action:
		printerr("SMOKE_FAIL borrow_sword_legal_actions=%s" % [borrow_sword_legal_actions])
		get_tree().quit(1)
		return
	# 随机座次样本；多个固定种子应产生不同的本地座次与领袖座次，且至少一局本地玩家不是领袖。
	var observed_local_seats: Dictionary = {}
	# 随机领袖座次样本；键为座次 ID，用于验证领袖不固定于一号位。
	var observed_leader_seats: Dictionary = {}
	# 是否观察到本地玩家不为领袖；默认 false，样本中出现后置为 true。
	var observed_non_leader_local_player: bool = false
	_controller.local_human_player_id = 0
	_controller.randomize_local_human_seat = true
	for random_seed: int in range(20260701, 20260717):
		if not _controller.start_match(8, random_seed, "identity"):
			printerr("SMOKE_FAIL randomized_start seed=%d" % random_seed)
			get_tree().quit(1)
			return
		# 当前种子分配的本地座次；每局可以不同，但固定种子的结果可复现。
		var randomized_local_seat: int = _controller.local_human_player_id
		# 当前种子分配的领袖；身份池整体洗牌后可位于任意座次。
		var randomized_leader: PlayerState = _controller._find_player_by_identity("leader")
		observed_local_seats[randomized_local_seat] = true
		observed_leader_seats[randomized_leader.player_id] = true
		if randomized_leader.player_id != randomized_local_seat:
			observed_non_leader_local_player = true
	if observed_local_seats.size() <= 1 or observed_leader_seats.size() <= 1 or observed_leader_seats.has(0) and observed_leader_seats.size() == 1 or not observed_non_leader_local_player:
		printerr("SMOKE_FAIL randomized_seats local=%s leader=%s non_leader_local=%s" % [observed_local_seats.keys(), observed_leader_seats.keys(), observed_non_leader_local_player])
		get_tree().quit(1)
		return
	# 无懈可击响应状态；三号位是当前回合角色，应比一号位更早响应同一有害锦囊。
	var negation_state: GameState = GameState.new()
	for negation_player_id: int in range(4):
		# 无懈响应测试玩家；目标与两名响应者同属领忠阵营。
		var negation_player: PlayerState = PlayerState.new(negation_player_id, "玩家%d" % (negation_player_id + 1))
		negation_player.identity = "leader" if negation_player_id == 1 else ("rebel" if negation_player_id == 3 else "loyalist")
		negation_state.players.append(negation_player)
	negation_state.current_player_id = 2
	# 一号位无懈可击；若仍从数组首项询问就会被错误消耗。
	var seat_one_counter: CardInstance = CardInstance.new("wuxie", "spade", 11)
	seat_one_counter.zone = "hand"
	seat_one_counter.owner_id = 0
	negation_state.players[0].hand.append(seat_one_counter)
	# 三号位无懈可击；当前回合角色应首先消耗该牌。
	var seat_three_counter: CardInstance = CardInstance.new("wuxie", "spade", 13)
	seat_three_counter.zone = "hand"
	seat_three_counter.owner_id = 2
	negation_state.players[2].hand.append(seat_three_counter)
	_controller.state = negation_state
	_controller.card_rules = CardRuleService.new(negation_state)
	# 一号位此前是否由AI控制；规则顺序断言后按原状态恢复，避免影响后续烟雾测试。
	var seat_one_was_ai_controlled: bool = _controller.ai_coordinator.is_ai_controlled(0)
	# 三号位此前是否由AI控制；本段临时使用公开身份回退规则，排除随机本地座次对测试分支的影响。
	var seat_three_was_ai_controlled: bool = _controller.ai_coordinator.is_ai_controlled(2)
	_controller.ai_coordinator.unregister_ai(0)
	_controller.ai_coordinator.unregister_ai(2)
	# 无懈链同步结果；临时取消AI注册后应严格按当前回合角色起始的行动顺序裁决。
	var negation_resolved: bool = _controller.resolve_trick_negation(3, 1, "guohe")
	if seat_one_was_ai_controlled:
		_controller.ai_coordinator.register_basic_ai(0)
	if seat_three_was_ai_controlled:
		_controller.ai_coordinator.register_basic_ai(2)
	if not negation_resolved or negation_state.players[2].hand.size() != 0 or negation_state.players[0].hand.size() != 1:
		printerr("SMOKE_FAIL negation_response_order seat1=%d seat3=%d" % [negation_state.players[0].hand.size(), negation_state.players[2].hand.size()])
		get_tree().quit(1)
		return
	# 连环传导测试状态；当前回合为三号位，初始受伤目标为二号位，其余横置角色应按三、四、一的顺序传导。
	var chain_order_state: GameState = GameState.new()
	for chain_player_id: int in range(4):
		# 连环传导玩家；全部初始为4点体力且处于横置状态。
		var chain_player: PlayerState = PlayerState.new(chain_player_id, "玩家%d" % (chain_player_id + 1))
		chain_player.chained = true
		chain_order_state.players.append(chain_player)
	chain_order_state.current_player_id = 2
	# 伤害后目标顺序；事件回调同步记录初始伤害与后续传导的实际结算次序。
	var chain_damage_order: Array[int] = []
	# 连环顺序监听者；仅在本次同步伤害结算期间保持有效。
	var chain_listener: RefCounted = RefCounted.new()
	_controller.event_bus.subscribe("damage_after", chain_listener, func(event: RuleEvent) -> void: chain_damage_order.append(event.target_id))
	_controller.state = chain_order_state
	_controller.card_rules = CardRuleService.new(chain_order_state)
	_controller.damage(2, 1, 1, "fire", "sha_fire")
	_controller.event_bus.unsubscribe_owner(chain_listener)
	if chain_damage_order != [1, 2, 3, 0]:
		printerr("SMOKE_FAIL chain_damage_order=%s" % chain_damage_order)
		get_tree().quit(1)
		return
	# 银月枪测试状态；回合外打出黑色手牌后，基础 AI 确认发动且敌方无【闪】时应受到1点伤害。
	var silver_moon_state: GameState = GameState.new()
	for silver_player_id: int in range(3):
		# 银月枪测试玩家；一号位反贼持有武器，二号位领袖作为优先敌方。
		var silver_player: PlayerState = PlayerState.new(silver_player_id, "玩家%d" % (silver_player_id + 1))
		silver_player.identity = "rebel" if silver_player_id != 1 else "leader"
		silver_moon_state.players.append(silver_player)
	silver_moon_state.current_player_id = 2
	# 银月枪实体牌；位于一号位武器槽并提供3点攻击范围。
	var silver_moon_weapon: CardInstance = CardInstance.new("yinyue", "diamond", 12)
	silver_moon_weapon.zone = "equipment"
	silver_moon_weapon.owner_id = 0
	silver_moon_state.players[0].equipment["weapon"] = silver_moon_weapon
	# 触发用黑色手牌；模拟已在回合外打出并移入弃牌堆的【无懈可击】。
	var silver_trigger_card: CardInstance = CardInstance.new("wuxie", "spade", 11)
	silver_trigger_card.zone = "discard_pile"
	silver_moon_state.discard_pile.append(silver_trigger_card)
	_controller.state = silver_moon_state
	_controller.card_rules = CardRuleService.new(silver_moon_state)
	_controller._notify_equipment_card_consumed(0, silver_trigger_card, true)
	# 推进已登记的非锁定装备触发；纯规则状态同步使用同一选择协议，由基础 AI 明确选择银月枪实体表示发动。
	_controller.process_next_equipment_trigger()
	if silver_moon_state.players[1].hp != 3:
		printerr("SMOKE_FAIL silver_moon_damage hp=%d" % silver_moon_state.players[1].hp)
		get_tree().quit(1)
		return
	# 当前回合死亡状态；二号位反贼在自己回合对自己使用【火攻】死亡，仍有另一名反贼使对局继续。
	var current_death_state: GameState = GameState.new()
	for death_player_id: int in range(4):
		# 当前回合死亡测试玩家；身份依次为领袖、反贼、反贼与忠臣。
		var death_player: PlayerState = PlayerState.new(death_player_id, "玩家%d" % (death_player_id + 1))
		death_player.identity = ["leader", "rebel", "rebel", "loyalist"][death_player_id]
		current_death_state.players.append(death_player)
	current_death_state.current_player_id = 1
	current_death_state.current_phase = "play"
	current_death_state.turn_number = 1
	current_death_state.players[1].hp = 1
	# 自伤火攻实体牌；作为当前行为从手牌进入处理区。
	var self_fire_attack: CardInstance = CardInstance.new("huogong", "heart", 2)
	self_fire_attack.zone = "hand"
	self_fire_attack.owner_id = 1
	current_death_state.players[1].hand.append(self_fire_attack)
	# 火攻同花色手牌；目标展示后由同一玩家弃置，对自己造成1点火焰伤害。
	var self_fire_cost: CardInstance = CardInstance.new("shan", "heart", 3)
	self_fire_cost.zone = "hand"
	self_fire_cost.owner_id = 1
	current_death_state.players[1].hand.append(self_fire_cost)
	# 后继回合第一张摸牌；当前回合死亡会立刻启动三号位摸牌阶段，测试状态必须提供实体避免空牌堆按规则判平局。
	var successor_draw_one: CardInstance = CardInstance.new("sha", "club", 4)
	successor_draw_one.zone = "draw_pile"
	successor_draw_one.owner_id = -1
	current_death_state.draw_pile.append(successor_draw_one)
	# 后继回合第二张摸牌；标准摸牌阶段固定摸两张，第二张保证完整走到出牌阶段。
	var successor_draw_two: CardInstance = CardInstance.new("shan", "diamond", 5)
	successor_draw_two.zone = "draw_pile"
	successor_draw_two.owner_id = -1
	current_death_state.draw_pile.append(successor_draw_two)
	_controller.state = current_death_state
	_controller.card_rules = CardRuleService.new(current_death_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, current_death_state)
	if not _controller.submit_action(PlayerAction.new("use_card", 1, self_fire_attack.uid, [1])) or current_death_state.players[1].alive or current_death_state.current_player_id != 2 or current_death_state.current_phase != "play" or current_death_state.turn_number != 2:
		printerr("SMOKE_FAIL current_player_death alive=%s current=%d phase=%s turn=%d" % [current_death_state.players[1].alive, current_death_state.current_player_id, current_death_state.current_phase, current_death_state.turn_number])
		get_tree().quit(1)
		return
	# 胜负结束死亡状态；最后一名反贼亮出身份后立即满足领忠胜利条件。
	var terminal_death_state: GameState = GameState.new()
	# 终局领袖；保持存活以使最后反贼死亡后判定领忠胜利。
	var terminal_leader: PlayerState = PlayerState.new(0, "领袖")
	terminal_leader.identity = "leader"
	terminal_death_state.players.append(terminal_leader)
	# 终局反贼；携带1张手牌，用于确认胜负条件在死亡弃牌之前立即终止结算。
	var terminal_rebel: PlayerState = PlayerState.new(1, "反贼")
	terminal_rebel.identity = "rebel"
	terminal_rebel.hp = 0
	var terminal_rebel_card: CardInstance = CardInstance.new("shan", "heart", 2)
	terminal_rebel_card.zone = "hand"
	terminal_rebel_card.owner_id = 1
	terminal_rebel.hand.append(terminal_rebel_card)
	terminal_death_state.players.append(terminal_rebel)
	terminal_death_state.current_player_id = 0
	_controller.state = terminal_death_state
	_controller.card_rules = CardRuleService.new(terminal_death_state)
	_controller._resolve_death(1, 0)
	if not terminal_death_state.game_over or terminal_death_state.winner != "leader_and_loyalists" or terminal_rebel.hand.size() != 1:
		printerr("SMOKE_FAIL terminal_death winner=%s hand=%d" % [terminal_death_state.winner, terminal_rebel.hand.size()])
		get_tree().quit(1)
		return
	# 群体牌终局状态；首名目标死亡满足胜负条件后，必须终止后续目标与使用牌区域移动。
	var terminal_aoe_state: GameState = GameState.new()
	for terminal_aoe_player_id: int in range(3):
		# 群体牌终局玩家；身份依次为领袖、最后一名反贼与忠臣。
		var terminal_aoe_player: PlayerState = PlayerState.new(terminal_aoe_player_id, "玩家%d" % (terminal_aoe_player_id + 1))
		terminal_aoe_player.identity = ["leader", "rebel", "loyalist"][terminal_aoe_player_id]
		terminal_aoe_state.players.append(terminal_aoe_player)
	terminal_aoe_state.current_player_id = 0
	terminal_aoe_state.current_phase = "play"
	terminal_aoe_state.players[1].hp = 1
	# 终局测试万箭齐发；规则顺序先处理二号位反贼，再处理三号位忠臣。
	var terminal_aoe_card: CardInstance = CardInstance.new("wanjian", "heart", 1)
	terminal_aoe_card.zone = "hand"
	terminal_aoe_card.owner_id = 0
	terminal_aoe_state.players[0].hand.append(terminal_aoe_card)
	_controller.state = terminal_aoe_state
	_controller.card_rules = CardRuleService.new(terminal_aoe_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, terminal_aoe_state)
	# 终局场景使用独立事件运行时；上一场景的 game_over 会中断旧根事件，替换 GameState 时必须同步创建新根。
	_controller.event_scheduler.reset()
	# 群体牌终局根事件；保持开放以执行真实 CardUseEvent 及其逐目标 content 子树。
	var terminal_aoe_root: GameEvent = _controller.event_scheduler.create_event("RootGameEvent", "root", [], {"match_id":"terminal_aoe"})
	_controller._runtime_root_event_id = terminal_aoe_root.event_id
	_controller.event_scheduler.begin_root(terminal_aoe_root.event_id, true)
	if not _controller.submit_action(PlayerAction.new("use_card", 0, terminal_aoe_card.uid, [])) or not terminal_aoe_state.game_over or terminal_aoe_state.players[2].hp != 4 or not terminal_aoe_state.processing_area.has(terminal_aoe_card) or terminal_aoe_state.discard_pile.has(terminal_aoe_card):
		printerr("SMOKE_FAIL terminal_aoe winner=%s later_hp=%d processing=%s discard=%s" % [terminal_aoe_state.winner, terminal_aoe_state.players[2].hp, terminal_aoe_state.processing_area.has(terminal_aoe_card), terminal_aoe_state.discard_pile.has(terminal_aoe_card)])
		get_tree().quit(1)
		return
	# 判定阶段死亡状态；当前角色被闪电击杀但仍有同阵营角色存活，对局应转交给其下名存活角色。
	var judgment_death_state: GameState = GameState.new()
	for judgment_death_player_id: int in range(4):
		# 判定死亡测试玩家；身份依次为领袖、当前反贼、另一名反贼与忠臣。
		var judgment_death_player: PlayerState = PlayerState.new(judgment_death_player_id, "玩家%d" % (judgment_death_player_id + 1))
		judgment_death_player.identity = ["leader", "rebel", "rebel", "loyalist"][judgment_death_player_id]
		judgment_death_state.players.append(judgment_death_player)
	judgment_death_state.players[1].hp = 1
	# 待结算闪电；进入二号位判定区，命中后造成3点无来源雷电伤害。
	var pending_lightning: CardInstance = CardInstance.new("shandian", "spade", 1)
	pending_lightning.zone = "judgment"
	pending_lightning.owner_id = 1
	judgment_death_state.players[1].judgment_area.append(pending_lightning)
	# 闪电判定牌；牌堆末尾为顶部，黑桃2保证本次判定命中。
	var lightning_judgment: CardInstance = CardInstance.new("shan", "spade", 2)
	lightning_judgment.zone = "draw_pile"
	judgment_death_state.draw_pile.append(lightning_judgment)
	_controller.ai_coordinator._policies.clear()
	_controller.state = judgment_death_state
	_controller.card_rules = CardRuleService.new(judgment_death_state)
	_controller.effect_resolver = CardEffectResolver.new(_controller, judgment_death_state)
	_controller._start_turn(1)
	if judgment_death_state.game_over or judgment_death_state.players[1].alive or judgment_death_state.current_player_id != 2 or judgment_death_state.current_phase != "play" or judgment_death_state.turn_number != 2:
		printerr("SMOKE_FAIL judgment_turn_transfer game_over=%s alive=%s current=%d phase=%s turn=%d" % [judgment_death_state.game_over, judgment_death_state.players[1].alive, judgment_death_state.current_player_id, judgment_death_state.current_phase, judgment_death_state.turn_number])
		get_tree().quit(1)
		return
	# 纯 AI 四人局；领袖座次随机，完成选将后应立即成为首回合角色且不获得小于5人局的体力加值。
	_controller.local_human_player_id = -1
	if not _controller.start_match(4, 20260714, "identity"):
		printerr("SMOKE_FAIL start_match")
		get_tree().quit(1)
		return
	# 四人局领袖；用于同时校验随机座次首回合和小人数体力上限。
	var four_player_leader: PlayerState = _controller._find_player_by_identity("leader")
	# 四人局领袖武将基础体力；应与实际上限完全一致。
	var four_player_leader_base_hp: int = int(GameDatabase.get_character(four_player_leader.character_id).get("max_hp", 4))
	if not await _settle_opening_choices():
		printerr("SMOKE_FAIL first_turn_opening_choice current=%d pending=%s" % [_controller.state.current_player_id, _controller._pending_card_choice])
		get_tree().quit(1)
		return
	if _controller.state.current_player_id != four_player_leader.player_id or _controller.state.turn_number != 1 or four_player_leader.max_hp != four_player_leader_base_hp:
		printerr("SMOKE_FAIL first_turn seat=%d turn=%d" % [_controller.state.current_player_id + 1, _controller.state.turn_number])
		get_tree().quit(1)
		return
	# 四人局技能实例表；选将完成后每名玩家都应安装自己武将文件直接引用的独立技能代码。
	if _controller.skill_instances_by_player.size() != 4:
		printerr("SMOKE_FAIL installed_skill_players=%d" % _controller.skill_instances_by_player.size())
		get_tree().quit(1)
		return
	for four_player: PlayerState in _controller.state.players:
		# 当前玩家实际安装的技能；必须完整覆盖武将文件声明的技能，并允许存在局内动态获得的技能。
		var installed_skills: Dictionary = _controller.skill_instances_by_player.get(four_player.player_id, {}) as Dictionary
		# 当前玩家武将定义；运行时安装器以该技能列表为唯一来源。
		var installed_character: Dictionary = GameDatabase.get_character(four_player.character_id)
		# 武将文件声明的技能；非领袖身份不安装领袖技，其余必须逐个存在。
		var declared_skill_ids: Array = installed_character.get("skills", []) as Array
		for declared_skill_id_variant: Variant in declared_skill_ids:
			# 当前声明技能ID与其元数据；领袖技按身份过滤后参与存在性校验。
			var declared_skill_id: String = str(declared_skill_id_variant)
			var installed_skill_definition: Dictionary = GameDatabase.get_skill(declared_skill_id)
			if bool(installed_skill_definition.get("leader_skill", false)) and four_player.identity != "leader":
				continue
			if not installed_skills.has(declared_skill_id):
				printerr("SMOKE_FAIL installed_skills_missing player=%d character=%s skill=%s installed=%s" % [four_player.player_id, four_player.character_id, declared_skill_id, str(installed_skills.keys())])
				get_tree().quit(1)
				return
		# 超出武将声明的实例；必须是局内获得技能（例如【升变】以“军功”动态赋予的【奇袭】）并留有获得记录。
		for installed_skill_id_variant: Variant in installed_skills.keys():
			# 当前已安装技能ID；声明列表内的固有能力已经在上一步校验过。
			var installed_skill_id: String = str(installed_skill_id_variant)
			if declared_skill_ids.has(installed_skill_id):
				continue
			if not (four_player.acquired_skills as Dictionary).has(installed_skill_id):
				printerr("SMOKE_FAIL installed_skills_unexpected player=%d character=%s skill=%s installed=%s acquired=%s" % [four_player.player_id, four_player.character_id, installed_skill_id, str(installed_skills.keys()), str(four_player.acquired_skills)])
				get_tree().quit(1)
				return
	# 纯 AI 五人局；规则集规定从五人起领袖的体力上限才增加1点。
	if not _controller.start_match(5, 20260715, "identity"):
		printerr("SMOKE_FAIL five_player_start")
		get_tree().quit(1)
		return
	# 五人局领袖；用于校验不少于5人时的唯一体力加值。
	var five_player_leader: PlayerState = _controller._find_player_by_identity("leader")
	# 五人局领袖武将基础体力；实际上限应比该值高1点。
	var five_player_leader_base_hp: int = int(GameDatabase.get_character(five_player_leader.character_id).get("max_hp", 4))
	if not await _settle_opening_choices():
		printerr("SMOKE_FAIL five_player_opening_choice current=%d pending=%s" % [_controller.state.current_player_id, _controller._pending_card_choice])
		get_tree().quit(1)
		return
	if _controller.state.current_player_id != five_player_leader.player_id or five_player_leader.max_hp != five_player_leader_base_hp + 1:
		printerr("SMOKE_FAIL leader_hp_bonus seat=%d hp=%d base=%d" % [five_player_leader.player_id + 1, five_player_leader.max_hp, five_player_leader_base_hp])
		get_tree().quit(1)
		return

	for frame_index: int in range(MAX_FRAMES):
		await get_tree().process_frame
		if _controller.state.game_over:
			await _finish_success("SMOKE_PASS game_over winner=%s actions=%d frames=%d" % [_controller.state.winner, _controller.state.action_sequence, frame_index])
			return
	await _finish_success("SMOKE_PASS running phase=%s turn=%d actions=%d" % [_controller.state.current_phase, _controller.state.turn_number, _controller.state.action_sequence])


## 等待开局回合开始窗口自动结算完成；返回false表示超时后仍存在待处理选择或首回合尚未开始。
## 部分武将技能会在回合开始/游戏开始时立即创建选择（例如爻光的【凶星】），而固定种子选将会随武将池变化而换人，
## 因此不能假设 start_match 返回时首回合已经同步开始：必须先让零延迟 AI 自行答完这些开局选择。
func _settle_opening_choices() -> bool:
	# 已等待帧数；达到上限即判定开局选择无法自动结算。
	var waited_frames: int = 0
	while waited_frames < OPENING_SETTLE_MAX_FRAMES and (_controller.state.current_player_id < 0 or not _controller._pending_card_choice.is_empty()):
		waited_frames += 1
		await get_tree().process_frame
	return _controller.state.current_player_id >= 0 and _controller._pending_card_choice.is_empty()


## 输出成功结果并释放纯 AI 测试控制器；额外等待一帧让零延迟 AI 计时器完成断连，避免测试退出时残留 SceneTreeTimer。
func _finish_success(message: String) -> void:
	print(message)
	GameSettings.control_all_characters_enabled = _original_control_all_characters_enabled
	if _controller != null and is_instance_valid(_controller):
		# 收尾令牌；递增后所有已经创建的 AI 延迟任务都会在超时回调中判定失效。
		_controller._ai_drive_token += 1
		# 测试 AI 策略表；清空后即使当前回调到达也不会继续为任何角色安排后续行动。
		_controller.ai_coordinator._policies.clear()
		# 等待中的零延迟计时器需要经过一个进程帧发出 timeout，才能释放内部引用。
		await get_tree().process_frame
		# 已停止异步任务的测试控制器；先脱离场景树再立即释放，避免成功退出时保留测试节点。
		get_tree().root.remove_child(_controller)
		_controller.free()
		_controller = null
	await get_tree().process_frame
	get_tree().quit(0)
