extends SkillDefinition

## 【伏辰】技能源码。持有者在其他角色打出一张【杀】后获得该实体牌。
##
## 本技能是**完整锁定技**：满足条件即自动执行，没有确认、没有选牌、没有选目标，
## 因此不存在任何可供 AI 评分的决策点。为一个没有分支的锁定技伪造 score_ai_action /
## score_ai_choice / append_play_phase_actions，只会留下永不执行的死代码并让后续维护者
## 误以为存在可选分支。`content-ai.md` 要求补齐 AI 的对象是**存在 AI 决策点**的技能，
## 本文件因此刻意不提供任何 AI 钩子。

## 【杀】的稳定响应牌名；核心在 respond 事件数据中写入 response_pattern，本技能只接这一种。
const RESPONSE_PATTERN_SHA: String = "sha"

## 「打出」的稳定动作名；核心保证 respond 只对应打出，读取它用于在代码中显式表达需求口径。
const RESPONSE_ACTION_PLAY: String = "play"


## 写入锁定技静态信息；技能描述严格保持需求提供的原文。
func _init() -> void:
	super({
		"id":"fuchen",
		"name":"伏辰",
		"trigger":"respond",
		"lock":true,
		"ui_enabled":false,
		"description":"锁定技，当其他角色打出一张【杀】后，你获得之。",
	})


## 订阅打出时机。
## role 必须是 "global"：respond 事件由核心以 player_id 定位响应者、target_id 恒为 -1 派发
## （响应没有目标维度），因此 "player" 与 "source" 都只能匹配到打出者自己，无法监听其他角色。
func install() -> void:
	subscribe_timing("respond", _on_other_player_played_sha, "global")


## 其他角色打出一张【杀】后获得该实体牌。
func _on_other_player_played_sha(event: RuleEvent) -> void:
	# 持有者状态；阵亡或离场后不再获得任何牌。
	var owner: PlayerState = get_owner_skill_player().get_state()
	if owner == null or not owner.alive or owner.out_of_game:
		return
	# 本次响应者；必须排除持有者自己打出的【杀】。
	if event.player_id == owner_player_id:
		return
	# 本次响应动作类别；核心只把实体响应牌的动作写进 respond，因此它恒为“打出”。
	# 该判断是需求「注意，是打出」的语义自证：任何“使用”路径走的是 useCard 而不是 respond，
	# 即使内容层误把【杀】标记成使用牌，也仍然不会命中本技能。
	if str(event.data.get("response_action", "")) != RESPONSE_ACTION_PLAY:
		return
	# 本次响应牌名；只获得【杀】，【闪】【无懈可击】等其它响应一律不触发。
	if str(event.data.get("response_pattern", "")) != RESPONSE_PATTERN_SHA:
		return
	# 本次打出的实体牌 UID；只有真正消耗实体牌的响应才写入该字段。
	# 装备区提供的响应（写入 equipment_uid 与 material_card_uids）与技能的无线响应
	# （只写入 skill_id）都没有该字段，因此天然被这一条挡下，不会误取他人装备。
	var played_card_uid: int = int(event.data.get("card_uid", -1))
	if played_card_uid < 0:
		return
	# 获得该实体牌；核心已在派发 respond 之前把响应牌经处理区置入弃牌堆，
	# 因此回调执行时该实体已在弃牌堆，权威获得端口可以按弃牌堆来源取回。
	# 牌在等待期间被其它效果移走时端口返回 false，本技能静默跳过：不写日志、不创建任何选择。
	host.call("gain_card_to_hand_by_uid", owner_player_id, played_card_uid, get_id())
