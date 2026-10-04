class_name CardDefinition
extends RefCounted

## 卡牌源码定义基类。每张具体卡牌脚本保存自身静态信息、同步效果与异步恢复入口，数据库仅负责自动发现和索引。

## 卡牌语音动作模式：使用；与核心层 VOICE_PLAY_MODE_USE 取值保持一致，内容层因此无需依赖核心层常量。
const VOICE_PLAY_MODE_USE: String = "use"

## 卡牌动作类别：使用。与核心层 CARD_ACTION_USE 取值保持一致。
## 牌进入处理区并产生牌面效果，例如成为【杀】的目标时使用【闪】抵消该【杀】。
## “使用”既不是“打出”也不是“弃置”：牌经处理区进入弃牌堆，不会触发任何“弃置牌”效果。
const CARD_ACTION_USE: String = "use"

## 卡牌动作类别：打出。与核心层 CARD_ACTION_PLAY 取值保持一致。
## 牌进入处理区但不产生牌面效果，例如响应【决斗】【南蛮入侵】打出的【杀】、响应【万箭齐发】打出的【闪】。
## “打出”同样不是“弃置”：牌经处理区进入弃牌堆，不会触发任何“弃置牌”效果。
const CARD_ACTION_PLAY: String = "play"

## 当前卡牌的完整静态元数据；由具体卡牌脚本在构造时一次性写入，运行时只通过深拷贝向外提供。
var _metadata: Dictionary = {}

## 当前区域持续效果绑定的对局控制器端口；静态数据库定义保持 null，只有装备等运行时实例会写入。
var runtime_host: Object

## 当前区域持续效果所属玩家 ID；未绑定时为 -1，绑定后使用稳定 player_id 而非座次数组下标。
var runtime_owner_player_id: int = -1

## 当前区域持续效果对应的实体牌 UID；未绑定时为 -1，用于换装或移牌后精确卸载同一实例。
var runtime_card_uid: int = -1


## 保存具体卡牌提供的完整元数据；调用方修改原始字典不会影响已创建的定义对象。
func _init(metadata: Dictionary = {}) -> void:
	_metadata = metadata.duplicate(true)


## 返回卡牌静态信息的深拷贝，用于界面、规则、AI、网络与存档读取。
func get_metadata() -> Dictionary:
	return _metadata.duplicate(true)


## 返回卡牌稳定逻辑 ID；该值必须在 game_data/cards 全目录中唯一。
func get_id() -> String:
	return str(_metadata.get("id", ""))


## 请求播放本次使用或打出的卡牌语音；卡牌源码可在效果代码中调用它以自定义播放时机。
## 默认已由核心统一出口在“声明使用”与“响应消耗”两处触发，因此牌源文件通常无需调用。
func play_voice(actor_id: int = -1) -> void:
	if runtime_host == null or not runtime_host.has_method("request_card_voice"):
		return
	# 使用者；未显式指定时回退到绑定运行时记录的持有者，保证装备与虚拟牌也能定位音源。
	var user_id: int = actor_id if actor_id >= 0 else runtime_owner_player_id
	runtime_host.call("request_card_voice", user_id, get_id(), VOICE_PLAY_MODE_USE)


## 返回卡牌文件声明的 AI 配置副本；通用策略可读取但不能修改数据库中的静态元数据。
func get_ai_profile() -> Dictionary:
	return (_metadata.get("ai", {}) as Dictionary).duplicate(true)


## 构造本次公开用牌的身份观察配置；逐目标结果允许内容文件表达切换状态等动态正负牌效。
func get_identity_observation_ai_profile(authoritative_snapshot: Dictionary, actor_id: int, target_ids: Array[int]) -> Dictionary:
	# 卡牌基础 AI 配置；身份观察副本不会修改数据库静态元数据。
	var result: Dictionary = get_ai_profile()
	# 静态目标结果；没有目标牌效的装备或纯自身牌保持0。
	var base_target_result: float = float(result.get("target_result", 0.0))
	# 各稳定目标的动态结果；身份模型按目标 ID 读取，不要求所有目标共享同一方向。
	var target_results_by_player: Dictionary = {}
	for target_id: int in target_ids:
		target_results_by_player[target_id] = get_identity_observation_target_result(authoritative_snapshot, actor_id, target_id, base_target_result)
	if not target_results_by_player.is_empty():
		result["target_results_by_player"] = target_results_by_player
	return result


## 返回本牌对单名目标的身份观察结果；回复牌对满体力目标为0，复杂切换牌可在自身源码覆盖。
func get_identity_observation_target_result(authoritative_snapshot: Dictionary, _actor_id: int, target_id: int, current_result: float) -> float:
	if not bool((_metadata.get("ai", {}) as Dictionary).get("recover", false)):
		return current_result
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前目标快照；回复牌对满体力角色没有实际收益，不应生成帮助身份线索。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == target_id and int(player.get("hp", 0)) >= int(player.get("max_hp", 0)):
			return 0.0
	return current_result


## 计算本卡牌创建的统一选择动作额外评分；复杂牌效可在对应卡牌文件中覆盖本入口。
func score_ai_choice(_authoritative_snapshot: Dictionary, _choice_request: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 修正基础 AI 对本卡牌出牌动作的评分；特殊目标切换、判定牌和复杂组合牌可在自身文件覆盖。
func modify_ai_action_score(_authoritative_snapshot: Dictionary, _action: Dictionary, current_score: float, _evaluator: Object) -> float:
	return current_score


## 修正本卡在指定持有者手中的动态保留价值；默认原样返回静态 ai.value，内容文件可结合当前场面重算。
## 对应无名杀 `ai.value` / `ai.basic.value` 允许写成函数的写法：同一张牌在不同体力与不同队友状态下价值不同。
## 语义：返回值表示“这张牌留在我手上值多少分”（0至10分档，越大越舍不得丢、用牌机会成本越高）。
## 调用方：NonameAIEvaluator.get_card_value_by_id 在解析完静态数值与既有特例修正后调用，覆盖实现必须返回最终价值。
## 约束：纯只读查询，不得修改权威快照，也不得依赖调用顺序；未覆盖本入口的卡牌行为与新增前完全一致。
func modify_ai_hand_value(_authoritative_snapshot: Dictionary, _owner_id: int, current_value: float, _evaluator: Object) -> float:
	return current_value


## 修正 AI 对本锦囊当前生效结果的收益判断；复杂锦囊可结合来源、目标和阵营关系覆盖静态 target_result。
## 返回值为原效果从响应者视角产生的效用，正数表示希望锦囊生效，负数表示希望锦囊被抵消。
func modify_ai_negation_effect_utility(_authoritative_snapshot: Dictionary, _responder_id: int, _context: Dictionary, current_utility: float, _evaluator: Object) -> float:
	return current_utility


## 计算装备或卡牌注册的自定义出牌动作评分；动作需携带 ai_card_definition_id 以定位对应内容文件。
func score_ai_play_phase_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> float:
	return 0.0


## 返回装备等自定义动作实际生成的虚拟用牌动作；基础AI据此补入卡牌本体与持有者技能的完整联动收益。
## 普通卡牌和非转化装备保持空字典；覆盖实现只能构造只读use_card代理动作，不能直接执行牌效。
func build_ai_virtual_card_action(_authoritative_snapshot: Dictionary, _action: Dictionary, _evaluator: Object) -> Dictionary:
	return {}


## 绑定需要持续存在于装备区等区域的卡牌实例；普通一次性卡牌无需调用本函数。
func bind_runtime(match_host: Object, owner_player_id: int, card_uid: int) -> void:
	runtime_host = match_host
	runtime_owner_player_id = owner_player_id
	runtime_card_uid = card_uid


## 安装卡牌的持续触发或查询修正；具体装备可覆盖本函数订阅事件或修正管线。
func install_runtime() -> void:
	pass


## 卸载卡牌持续效果；基类按实例所有者清理事件订阅，具体卡牌应在覆盖时补充自身修正管线清理。
func uninstall_runtime() -> void:
	if runtime_host != null and runtime_host.get("event_bus") != null:
		runtime_host.event_bus.unsubscribe_owner(self)
	if runtime_host != null and runtime_host.get("trigger_manager") != null:
		runtime_host.trigger_manager.unsubscribe_owner(self)


## 执行卡牌效果并返回最终区域语义；具体卡牌应覆盖本函数并调用解析器公开的规则操作入口。
func resolve(resolver: Object, card: CardInstance, actor_id: int, target_ids: Array[int]) -> String:
	return resolver.resolve_no_effect(card, actor_id, target_ids)


## 执行逐目标卡牌的当前目标内容；默认复用 resolve，特殊牌可读取共享上下文覆盖此入口。
func resolve_target(resolver: Object, card: CardInstance, actor_id: int, target_id: int, resolution_context: Dictionary) -> String:
	return resolve(resolver, card, actor_id, [target_id])


## 向整张牌的共享结算上下文写入本牌专属参数；默认不增加任何字段。
## 本函数在上下文登记到控制器之前调用，只能写入可序列化值，不得创建选择或直接推进结算。
func configure_resolution_context(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> void:
	pass


## 在共享结算上下文已经登记后执行整牌准备效果；返回 true 表示创建了等待请求并暂停进入目标流程。
func on_resolution_started(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> bool:
	return false


## 在实体牌完成使用声明时更新该牌拥有的兼容统计或触发状态；通用控制器不识别具体牌族。
func on_card_declared(_match_host: Object, _actor: PlayerState, _card: CardInstance) -> void:
	pass


## 在一名玩家的新回合建立后重置本牌拥有的回合状态；非相关卡牌保持空实现。
func on_turn_started(_match_host: Object, _player_id: int) -> void:
	pass


## 在一名玩家正常结束或因死亡中断回合时清理本牌持续状态；interrupted 表示没有进入正常结束阶段。
func on_turn_ended(_match_host: Object, _player_id: int, _interrupted: bool) -> void:
	pass


## 返回多目标声明是否必须保留玩家提交顺序；默认按行动座次规范化目标顺序。
func preserves_requested_target_order() -> bool:
	return false


## 返回本牌结算过程中是否必须由使用者本人继续选牌或指定响应。
## 声明为 true 的牌（例如【过河拆桥】【顺手牵羊】【火攻】【借刀杀人】）在结算中会向使用者本人创建选择请求，
## 使用者阵亡后这些环节无法由其他角色代理，因此整张牌直接失效，不再产生任何牌效；
## 没有声明该字段的牌在使用者阵亡后仍按“无来源”正常结算，伤害来源统一记为-1。
func requires_actor_choice() -> bool:
	return bool(_metadata.get("requires_actor_choice", false))


## 返回本牌是否为「专属锦囊牌」：专属牌正常情况**不加入游戏**，只有被其他角色的技能或其他情况触发时，
## 才会按要求加入游戏（例如由技能在“游戏开始时”把它放进摸牌堆）。
## 判定只读元数据键 `exclusive`，缺省为 false，因此既有卡牌行为完全不变。
## 该标志不影响牌的规则语义（仍按 `type`/`subtype`/`target_mode` 走同一条结算链路），只用于：
## ① 内容校验与自动化测试断言「专属牌不得出现在任何牌堆配置中」；
## ② 图鉴与牌面显示专属标识，使玩家能看出它不属于常规牌堆。
func is_exclusive() -> bool:
	return bool(_metadata.get("exclusive", false))


## 返回本牌是否为「伤害牌」：使用此牌时，其自身效果会对目标造成伤害。
## 判定只读元数据键 `is_damage`，缺省为 false，因此新增卡牌默认不是伤害牌，既有卡牌行为完全不变。
## 该入口是「成为伤害牌目标」类内容（例如【弃和】）的唯一判定依据，内容层禁止另建牌名白名单。
## 口径说明：只按**牌自身的使用效果**判定，因此装备牌（即使其装备效果会造成伤害）不是伤害牌；
## 延时锦囊【闪电】在判定结算时造成伤害，属于伤害牌，与本入口的“使用者使用它”语义一致。
func is_damage_card() -> bool:
	return bool(_metadata.get("is_damage", false))


## 返回真正进入本牌目标时机与逐目标结算的目标数组；默认与玩家声明完全一致，角色语义辅助目标可在卡牌文件中剥离。
func get_resolution_target_ids(requested_target_ids: Array[int]) -> Array[int]:
	return requested_target_ids.duplicate()


## 把玩家声明目标中的卡牌专属位置语义写入逐目标共享上下文；默认不写入任何额外字段且不得创建选择或修改状态。
func configure_requested_target_context(_match_host: Object, _card: CardInstance, _actor_id: int, _requested_target_ids: Array[int], _resolution_context: Dictionary) -> void:
	pass


## 校验当前目标在完整目标组合中的卡牌专属角色语义；空字符串表示继续执行通用目标规则。
func validate_target_selection(_rule_service: Object, _actor: PlayerState, _target_id: int, _all_target_ids: Array[int]) -> String:
	return ""


## 追加当前实体牌需要自定义组合生成的出牌阶段动作；返回 true 表示本牌已完全接管动作枚举。
func append_play_phase_card_actions(_match_host: Object, _actor_id: int, _card: CardInstance, _result: Array[Dictionary]) -> bool:
	return false


## 返回本牌在指定角色濒死救援窗口中提供的响应模式；空字符串表示当前关系下不能用于救援。
func get_dying_response_pattern(_responder_id: int, _dying_player_id: int) -> String:
	return ""


## 应用已经消费的濒死救援牌；返回 true 表示本牌完成了合法救援效果。
func resolve_dying_response(_match_host: Object, _responder_id: int, _dying_player_id: int, _card: CardInstance) -> bool:
	return false


## 恢复由当前卡牌效果创建的普通选牌请求；返回 true 表示该选择已由卡牌源码识别并处理。
func continue_choice(_resolver: Object, _context: Dictionary, _selected_uids: Array[int]) -> bool:
	return false


## 恢复由当前卡牌效果创建的通用选择请求；默认兼容旧选牌入口，需要读取目标或确认状态的卡牌可覆盖本函数。
func continue_selection(resolver: Object, context: Dictionary, response: ChoiceResponse) -> bool:
	if response == null:
		return false
	return continue_choice(resolver, context, response.card_ids)


## 恢复由当前卡牌效果创建的响应牌请求；响应实体已由控制器完成合法性校验和区域移动。
## 返回 true 表示该响应已由卡牌源码识别并处理，控制器只负责通用目标收尾。
func continue_response(_resolver: Object, _context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 恢复当前卡牌自定义的【无懈可击】后续流程；普通逐目标锦囊无需覆盖本入口。
## 返回 true 表示卡牌已自行恢复专用上下文，控制器不得再执行默认逐目标恢复。
func continue_negation(_resolver: Object, _context: Dictionary, _final_negated: bool) -> bool:
	return false


## 恢复由本卡牌或装备发起、曾被判定前选择暂停的判定结果；judgment_card 为 null 表示判定被取消或牌堆耗尽。
## 返回 true 表示当前定义识别并完成了该判定后续，控制器不得再猜测具体牌效。
func continue_judgment(_match_host: Object, _context: Dictionary, _judgment_card: CardInstance) -> bool:
	return false


## 修正装备持有者使用指定牌时的最大目标数；非相关装备保持原值。
func modify_maximum_target_count(_actor: PlayerState, _card: CardInstance, current_count: int) -> int:
	return current_count


## 返回装备是否解除指定牌的阶段使用次数限制；默认不解除任何限制。
func ignores_play_count_limit(_card_definition: Dictionary) -> bool:
	return false


## 返回武器是否令【杀】忽略目标防具；默认仍应用防具效果。
func slash_ignores_armor() -> bool:
	return false


## 在整张【杀】建立共享结算上下文后执行武器准备效果；可修改属性或创建发动选择。
## 返回 true 表示已创建等待请求，控制器应暂停进入逐目标流程。
func on_slash_resolution_started(_match_host: Object, _card: CardInstance, _actor_id: int, _resolution_context: Dictionary) -> bool:
	return false


## 判断防具是否令当前【杀】直接无效；默认不阻止伤害流程。
func blocks_slash(_card: CardInstance, _nature: String) -> bool:
	return false


## 按只读牌面颜色判断防具是否令当前【杀】无效；AI 使用本入口预判，实际结算仍必须调用 blocks_slash() 复核实体牌。
func blocks_slash_by_color(_card_color: String, _nature: String) -> bool:
	return false


## 判断防具是否令指定群体锦囊对持有者无效；默认不阻止锦囊。
func blocks_aoe(_card_definition_id: String) -> bool:
	return false


## 返回防具对指定属性伤害的AI预期倍率；只影响决策估值，实际伤害仍由modify_incoming_damage权威结算。
func get_ai_incoming_damage_multiplier(_nature: String) -> float:
	return 1.0


## 返回防具对单次伤害的AI预期上限；0表示不封顶，正数用于让AI按实际可造成伤害估值酒杀与致命收益。
func get_ai_incoming_damage_cap(_nature: String) -> int:
	return 0


## 返回锦囊被【无懈可击】抵消时是否应记录本回合AI失败目标；默认不保存牌目标记忆。
func records_failed_ai_target_when_negated() -> bool:
	return false


## 返回武器是否已通过标准damage时机处理【杀】造成伤害效果；true时跳过旧的伤害完成后兼容钩子。
## 当前标准说明：此处的“damage时机”泛指正式伤害时机协议；实现可使用扣减前的shaDamage，不要求订阅同名damage事件。
func uses_damage_timing_trigger() -> bool:
	return false


## 返回使用牌表现的分阶段目标指示语义；空数组表示使用者到全部实际目标的一段普通指示线。
func get_presentation_indicator_stages(_actor_id: int, _requested_target_ids: Array[int], _resolution_target_ids: Array[int]) -> Array[Dictionary]:
	return []


## 修正装备持有者造成的伤害；上下文包含目标、属性与来源牌 ID。
func modify_outgoing_damage(_match_host: Object, _owner: PlayerState, _target: PlayerState, _context: Dictionary, amount: int) -> int:
	return amount


## 修正装备持有者受到的伤害；ignore_armor 为 true 时控制器不会调用防具修正。
func modify_incoming_damage(_match_host: Object, _owner: PlayerState, _context: Dictionary, amount: int) -> int:
	return amount


## 处理实体牌离开装备区后的专属效果；trigger_loss_effects 为 false 时只执行区域清理。
func on_leave_equipment(_match_host: Object, _owner: PlayerState, _trigger_loss_effects: bool) -> void:
	pass


## 在【杀】开始结算单个目标、检查防具与【闪】之前执行武器专属效果。
## 返回 true 表示武器已接管或暂停流程；武器完成后必须调用 slash_effect.continue_after_weapon_targeted()。
func on_slash_targeted(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 在目标使用【闪】抵消【杀】后执行武器专属效果；context.dodged 表示当前是否仍被【闪】抵消。
## 返回 true 表示武器已接管或暂停流程；需要继续时调用 slash_effect.continue_after_weapon_dodged()。
func on_slash_dodged(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 在【杀】即将造成伤害前执行武器替代效果；返回 true 表示已防止伤害或等待选择。
## 未发动替代效果时应返回 false，或在异步恢复后调用 slash_effect.continue_slash_damage()。
func on_slash_before_damage(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 在【杀】伤害完整结算且目标仍存活后执行武器后续效果；返回 true 表示已创建等待流程。
func on_slash_damage_finished(_slash_effect: Object, _context: Dictionary) -> bool:
	return false


## 恢复由武器【杀】钩子创建的普通选牌请求；返回 true 表示当前装备源码已处理该 kind。
func continue_slash_choice(_slash_effect: Object, _context: Dictionary, _selected_uids: Array[int]) -> bool:
	return false


## 恢复由武器【杀】钩子创建的响应牌请求；返回 true 表示当前装备源码已处理该 kind。
func continue_slash_response(_slash_effect: Object, _context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 在装备持有者使用或打出一张实体牌后通知装备源码；was_hand_card 仅对真正来自手牌区的牌为 true。
func on_owner_card_consumed(_match_host: Object, _owner_id: int, _used_card: CardInstance, _was_hand_card: bool) -> void:
	pass


## 开始一条由装备源码排队的延后触发；返回 true 表示已创建选择或完成本次触发。
func begin_queued_equipment_trigger(_match_host: Object, _owner_id: int, _context: Dictionary) -> bool:
	return false


## 恢复不依附于处理区父牌的装备普通选牌；返回 true 表示当前装备定义已处理。
func continue_equipment_choice(_match_host: Object, _context: Dictionary, _selected_uids: Array[int]) -> bool:
	return false


## 恢复不依附于处理区父牌的装备响应牌选择；返回 true 表示当前装备定义已处理。
func continue_equipment_response(_match_host: Object, _context: Dictionary, _response_card: CardInstance) -> bool:
	return false


## 判断装备是否能作为当前响应模式集合中的可选入口；返回 true 时控制器展示装备实体候选。
func can_offer_equipment_response(_match_host: Object, _player_id: int, _response_patterns: Array[String]) -> bool:
	return false


## 判断装备是否需要在普通响应牌窗口之前独立询问；默认false保持手牌、技能与装备处于同一候选窗口。
func uses_immediate_equipment_response_prompt() -> bool:
	return false


## 返回装备独立响应询问的永久提示文本；只有 uses_immediate_equipment_response_prompt() 为true时使用。
func get_immediate_equipment_response_prompt() -> String:
	return "是否发动【%s】？" % GameSettings.resolve_card_name(_metadata)


## 返回装备响应需要选择的普通手牌材料数量；0表示直接选择装备即可结算。
func get_equipment_response_material_count() -> int:
	return 0


## 校验装备响应材料；空字符串表示合法，非空字符串作为统一动作拒绝原因。
func validate_equipment_response_materials(_match_host: Object, _player_id: int, _equipment_uid: int, _material_card_uids: Array[int]) -> String:
	return ""


## 消费装备响应入口并返回虚拟响应牌；材料和装备实体必须在卡牌文件中复核。
func consume_equipment_response(_match_host: Object, _player_id: int, _equipment_uid: int, _response_patterns: Array[String], _material_card_uids: Array[int], _response_context: Dictionary = {}) -> CardInstance:
	return null


## 返回装备在出牌阶段注册的自定义动作类型；控制器按动作名把校验和执行交回装备文件。
func get_play_phase_action_types() -> Array[String]:
	return []


## 返回当前装备实体是否应出现在出牌阶段可点击候选中。
func is_play_phase_action_available(_match_host: Object, _owner_id: int, _equipment_card: CardInstance) -> bool:
	return false


## 向 AI 与只读动作枚举追加该装备可执行的完整动作字典。
func append_play_phase_actions(_match_host: Object, _owner_id: int, _equipment_card: CardInstance, _result: Array[Dictionary]) -> void:
	pass


## 无副作用校验装备主动动作；空字符串表示合法，非空字符串为拒绝原因。
func validate_play_phase_action(_match_host: Object, _action: PlayerAction) -> String:
	return "该装备当前不能主动发动。"


## 执行已经通过校验的装备主动动作；返回 true 表示规则效果成功完成或已进入异步流程。
func execute_play_phase_action(_match_host: Object, _action: PlayerAction) -> bool:
	return false


## 声明主动动作执行后是否还要追加第二段独立选择；返回空字典表示该装备只有一段交互。
##
## 数组字段与语义：`prompt` 为界面提示（统一目标询问标题固定为“选择目标”），`target_ids` 为合法候选，
## `min_targets`/`max_targets` 为确认所需的目标数量范围（`min_targets = 1` 表示必须选中一名角色才能确认，
## `0` 表示可直接确认），`allow_cancel` 决定是否提供“取消”分支，`context` 为第二段选择恢复时原样回传的上下文。
## 控制器只在第一段动作真正执行成功后才会请求第二段，因此两段之间天然存在先后顺序，不会同帧合并。
func get_play_phase_follow_up_request(_match_host: Object, _action: PlayerAction) -> Dictionary:
	return {}


## 恢复装备主动动作声明的第二段独立选择；context 与创建请求时写入的上下文一致。
##
## 与 `continue_equipment_choice()` 的区别：本入口同时携带选牌与选目标结果，供需要“再选一名角色”
## 的两段式主动装备使用；两份钩子互不替代，装备可以只实现其中一份。返回 true 表示已经处理该响应。
func continue_equipment_selection(_match_host: Object, _context: Dictionary, _response: ChoiceResponse) -> bool:
	return false


## 返回装备主动动作的只读预览；字段应兼容普通卡牌预览的目标与确认信息。
func get_play_phase_action_preview(_match_host: Object, _owner_id: int, _equipment_uid: int, _payload: Dictionary, _selected_target_ids: Array[int]) -> Dictionary:
	return {}


## 结算延时锦囊到达判定阶段后的具体规则；默认安全弃置，具体延时牌应在自身文件完整覆盖。
func resolve_delayed_judgment(match_host: Object, _player_id: int, card: CardInstance, _negated: bool) -> void:
	match_host.discard_delayed_card(card)
