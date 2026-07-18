class_name IdentityAIModel
extends RefCounted

## 身份局 AI 关系模型。实现无名杀身份模式的局势强度、真实态度与隐藏身份暴露度组合逻辑。

## 身份完全公开时使用的暴露度；固定为1，表示态度无需再按猜测可信度衰减。
const REVEALED_EXPOSURE: float = 1.0

## 隐藏身份通过一次明确目标行为获得的基础暴露度；对应无名杀单目标行为通常增加约0.2。
const SINGLE_TARGET_EXPOSURE_GAIN: float = 0.2

## 隐藏身份通过一次多目标行为获得的基础暴露度；多目标行为对身份指向较弱，默认增加0.1。
const MULTI_TARGET_EXPOSURE_GAIN: float = 0.1

## 暴露度上限；沿用无名杀 `player.ai.shown` 的0.95上限，保留少量身份判断不确定性。
const MAX_EXPOSURE: float = 0.95

## 暴露度下限；沿用无名杀允许负暴露的边界，供特殊反向行为与后续模式扩展使用。
const MIN_EXPOSURE: float = -0.5

## 行为收益被视为较弱线索的绝对值阈值；低于5时只累计一半基础暴露度。
const WEAK_EFFECT_THRESHOLD: float = 5.0

# 兼容保留：旧版5.0阈值不再参与身份观察；当前无名杀对齐逻辑使用 `FULL_EXPOSURE_EFFECT_THRESHOLD=1.0`。

## 较弱行为线索的暴露倍率；固定0.5避免小收益动作过快揭示身份。
const WEAK_EXPOSURE_MULTIPLIER: float = 0.5

## 忠反行为信号绝对边界；限制到1避免长期对局累计无限增长。
const CAMP_SIGNAL_LIMIT: float = 1.0

## 忠反临时标记阈值；达到正负0.2即形成初步阵营推断。
const IDENTITY_MARK_THRESHOLD: float = 0.2

# 兼容保留：旧版累计阈值不再直接生成标记；0.2仍由目标证据下限与单目标基础步长分别声明。

## 存在忠反标记时的最低可信权重；保证明确行为能实际影响战略目标。
const IDENTITY_MARK_MINIMUM_CONFIDENCE: float = 0.5

## 全部反贼已暴露时其他隐藏非反贼角色的最低推断权重；对应无名杀弱身份收敛。
const NON_REBEL_MINIMUM_CONFIDENCE: float = 0.3

## 目标暴露度低于该值时不作为身份判断依据；对应无名杀 `shown < 0.2` 的零权重区间。
const TARGET_EVIDENCE_IGNORE_THRESHOLD: float = 0.2

## 目标暴露度低于该值时只采用一半牌效；对应无名杀 `shown < 0.4` 的弱证据区间。
const TARGET_EVIDENCE_HALF_THRESHOLD: float = 0.4

## 目标暴露度低于该值时采用八成牌效；对应无名杀 `shown < 0.6` 的较强证据区间。
const TARGET_EVIDENCE_MOST_THRESHOLD: float = 0.6

## 弱目标证据的牌效权重；固定为0.5，避免刚产生少量暴露的角色立即成为完整阵营锚点。
const TARGET_EVIDENCE_HALF_WEIGHT: float = 0.5

## 较强目标证据的牌效权重；固定为0.8，在身份完全明确前保留少量不确定性。
const TARGET_EVIDENCE_MOST_WEIGHT: float = 0.8

## 行为收益达到该值时获得完整基础暴露步长；小于1的正收益只按一半步长累计。
const FULL_EXPOSURE_EFFECT_THRESHOLD: float = 1.0

## 非本地角色公开行为的暴露倍率；对应无名杀从本地观察者视角把其他角色 `shown` 乘以2。
const REMOTE_ACTOR_EXPOSURE_MULTIPLIER: float = 2.0

## 忠臣作用于完全未知目标时的最低正行为收益；对应无名杀避免忠臣长期保持零暴露的0.1补偿。
const LOYALIST_UNKNOWN_TARGET_EFFECT: float = 0.1

## 当前身份模型所属对局 ID；对局变化时自动清空上一局的观察结果。
var _match_id: String = ""

## 各玩家的身份行为暴露度；键为稳定玩家 ID，值范围为-0.5至1.0。
var _exposure_by_player: Dictionary = {}

## 各玩家相对领袖阵营的行为信号；正值偏忠、负值偏反，范围限制为-1.0至1.0。
var _camp_signal_by_player: Dictionary = {}

## 各隐藏玩家的临时身份标记；值为空、loyalist或rebel，对应无名杀 identity_mark 的忠反推断。
var _identity_mark_by_player: Dictionary = {}

## 各隐藏玩家的身份标记是否已经终结；忠反角色定型、内奸出现相反行为后均不再反复改标。
var _identity_mark_finished_by_player: Dictionary = {}


## 清空全部身份观察状态；新对局、重开或测试独立构造快照时均可安全调用。
func reset() -> void:
	_match_id = ""
	_exposure_by_player.clear()
	_camp_signal_by_player.clear()
	_identity_mark_by_player.clear()
	_identity_mark_finished_by_player.clear()


## 确保模型已经与当前快照同步；公开身份固定为1，隐藏身份保留既有观察值。
func synchronize(authoritative_snapshot: Dictionary) -> void:
	# 当前快照的对局 ID；空 ID 用于规则测试，同一模型仍按玩家表持续工作。
	var snapshot_match_id: String = str(authoritative_snapshot.get("match_id", ""))
	if snapshot_match_id != _match_id:
		_match_id = snapshot_match_id
		_exposure_by_player.clear()
		_camp_signal_by_player.clear()
		_identity_mark_by_player.clear()
		_identity_mark_finished_by_player.clear()
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家公开快照；只读取身份公开标志和稳定玩家 ID。
		var player: Dictionary = player_variant as Dictionary
		# 当前玩家 ID；无效条目不会进入身份模型。
		var player_id: int = int(player.get("player_id", -1))
		if player_id < 0:
			continue
		if bool(player.get("identity_revealed", false)) or str(player.get("identity", "")) == "leader":
			_exposure_by_player[player_id] = REVEALED_EXPOSURE
			_identity_mark_by_player[player_id] = ""
			_identity_mark_finished_by_player[player_id] = true
		elif not _exposure_by_player.has(player_id):
			_exposure_by_player[player_id] = 0.0
		if not _camp_signal_by_player.has(player_id):
			_camp_signal_by_player[player_id] = 0.0
		if not _identity_mark_by_player.has(player_id):
			_identity_mark_by_player[player_id] = ""
		if not _identity_mark_finished_by_player.has(player_id):
			_identity_mark_finished_by_player[player_id] = false


## 记录一次公开使用牌行为；目标越明确、牌自身 expose 越高，行动者身份可信度越高。
func observe_card_use(authoritative_snapshot: Dictionary, actor_id: int, card_definition: Dictionary, target_ids: Array[int], observer_id: int = -1) -> void:
	synchronize(authoritative_snapshot)
	# 行动者快照；公开身份不需要继续累计暴露度。
	var actor: Dictionary = get_player(authoritative_snapshot, actor_id)
	if actor.is_empty() or bool(actor.get("identity_revealed", false)) or str(actor.get("identity", "")) == "leader":
		return
	# 卡牌 AI 配置；`expose` 对应无名杀卡牌主动声明的额外身份暴露量。
	var ai_profile: Dictionary = card_definition.get("ai", {}) as Dictionary
	# 卡牌显式暴露量；对应无名杀卡牌定义主动声明的 expose。
	var explicit_exposure: float = float(ai_profile.get("expose", 0.0))
	# 行动者身份；内奸执行违背当前自身真实收益的行为时允许减少暴露度，模拟身份伪装。
	var actor_identity: String = str(actor.get("identity", ""))
	# 卡牌对目标的基础结果；正值为增益，负值为伤害或控制。
	var target_result: float = float(ai_profile.get("target_result", 0.0))
	# 各目标动态牌效；卡牌源码可按稳定玩家 ID 覆盖切换状态或无实际收益目标的结果。
	var target_results_by_player: Dictionary = ai_profile.get("target_results_by_player", {}) as Dictionary
	# 行动者自身视角的总行为收益；只用真实身份关系判断该行动是否符合其阵营目标。
	var actor_effect: float = 0.0
	# 领袖阵营视角的总行为收益；用于生成隐藏身份的忠反标记。
	var leader_camp_effect: float = 0.0
	# 领袖玩家 ID；不存在领袖时不生成忠反信号。
	var leader_id: int = find_identity_player_id(authoritative_snapshot, "leader")
	# 是否为唯一目标指向行动者自己的行为；无名杀不会用这种自用行为推断忠反身份。
	var self_target_only: bool = target_ids.size() == 1 and target_ids[0] == actor_id
	for target_id: int in target_ids:
		# 当前目标实际牌效；优先读取整数 ID，兼容序列化后转为字符串的字典键。
		var current_target_result: float = float(target_results_by_player.get(target_id, target_results_by_player.get(str(target_id), target_result)))
		# 当前目标证据权重；只允许已经通过公开行为暴露的非内奸目标提供阵营参照。
		var target_evidence_weight: float = _get_target_evidence_weight(authoritative_snapshot, target_id)
		if is_zero_approx(target_evidence_weight):
			# 目标当前暴露度；只有严格为0的完全未知角色会触发无名杀忠臣弱暴露补偿。
			var unknown_target_exposure: float = absf(float(_exposure_by_player.get(target_id, 0.0)))
			# 行动者对未知目标的可感知牌效；结果为0表示补偿不依赖目标隐藏真实身份。
			var perceived_unknown_target_effect: float = current_target_result * get_attitude(authoritative_snapshot, actor_id, target_id)
			if actor_identity == "loyalist" and target_id != actor_id and is_zero_approx(unknown_target_exposure) and is_zero_approx(perceived_unknown_target_effect):
				actor_effect += LOYALIST_UNKNOWN_TARGET_EFFECT
			continue
		# 行动者对当前目标的真实态度；不受隐藏暴露衰减，用于判断行动是否符合自身阵营利益。
		var actor_target_attitude: float = get_real_attitude(authoritative_snapshot, actor_id, target_id)
		actor_effect += current_target_result * actor_target_attitude * target_evidence_weight
		if leader_id >= 0:
			# 领袖阵营对当前目标的真实态度；正面帮助友方或负面打击敌方均产生正忠向信号。
			var leader_target_attitude: float = get_real_attitude(authoritative_snapshot, leader_id, target_id)
			leader_camp_effect += current_target_result * leader_target_attitude * target_evidence_weight
	# 目标行为暴露量；只有该行为符合行动者自身收益时才增加，内奸反向伪装行为可减少。
	var target_exposure: float = 0.0
	if not self_target_only and not is_zero_approx(actor_effect):
		# 本次目标行为的基础暴露步长；单目标指向明确，多目标行为只提供较弱线索。
		var exposure_step: float = SINGLE_TARGET_EXPOSURE_GAIN if target_ids.size() == 1 else MULTI_TARGET_EXPOSURE_GAIN
		if actor_effect > 0.0:
			# 无名杀以1为正收益强弱边界；小于1的线索只获得一半基础暴露。
			target_exposure = exposure_step * (WEAK_EXPOSURE_MULTIPLIER if actor_effect < FULL_EXPOSURE_EFFECT_THRESHOLD else 1.0)
		elif actor_identity == "renegade" and observer_id >= 0 and actor_id == observer_id:
			target_exposure = -exposure_step
	# 当前暴露度；每次只累计可观察行为，不读取或修改游戏规则状态。
	var current_exposure: float = float(_exposure_by_player.get(actor_id, 0.0))
	# 更新后的暴露度；本地观察者看到其他角色行动时按无名杀规则整体乘2，再限制到合法区间。
	var updated_exposure: float = current_exposure + explicit_exposure + target_exposure
	if observer_id >= 0 and actor_id != observer_id:
		updated_exposure *= REMOTE_ACTOR_EXPOSURE_MULTIPLIER
	_exposure_by_player[actor_id] = clampf(updated_exposure, MIN_EXPOSURE, MAX_EXPOSURE)
	if not is_zero_approx(leader_camp_effect):
		# 忠反信号步长；单目标行为比群体行为更明确，并按实际牌效强弱限制到一次0.2。
		var signal_step: float = SINGLE_TARGET_EXPOSURE_GAIN if target_ids.size() == 1 else MULTI_TARGET_EXPOSURE_GAIN
		# 当前忠反信号；正值代表行为有利领忠，负值代表行为有利反贼。
		var current_signal: float = float(_camp_signal_by_player.get(actor_id, 0.0))
		_camp_signal_by_player[actor_id] = clampf(current_signal + signf(leader_camp_effect) * signal_step, -CAMP_SIGNAL_LIMIT, CAMP_SIGNAL_LIMIT)
	_update_identity_mark(authoritative_snapshot, actor_id, leader_camp_effect, observer_id, self_target_only)


## 记录一次公开打出的响应牌；当前只处理【无懈可击】可确定原锦囊来源、目标与奇偶方向的身份线索。
func observe_card_response(authoritative_snapshot: Dictionary, actor_id: int, card_definition: Dictionary, response_subject_definition: Dictionary, response_context: Dictionary, observer_id: int = -1) -> void:
	synchronize(authoritative_snapshot)
	# 响应牌模式；只有无懈可击具备官方 `ai.expose` 的特殊响应语义。
	var response_pattern: String = str(card_definition.get("provided_response_pattern", ""))
	if response_pattern != "wuxie":
		return
	# 原锦囊使用者 ID；无名杀只在原使用者已经暴露时累计无懈响应者的身份暴露。
	var source_id: int = int(response_context.get("source_id", -1))
	# 原锦囊当前目标 ID；响应者为该目标本人时不把自保行为作为忠反证据。
	var target_id: int = int(response_context.get("target_id", -1))
	if source_id < 0 or target_id < 0 or actor_id == target_id or is_zero_approx(get_exposure(source_id)):
		return
	# 原锦囊 AI 配置；用于把当前无懈奇偶结果还原为对目标的正负行为方向。
	var subject_ai_profile: Dictionary = response_subject_definition.get("ai", {}) as Dictionary
	# 原锦囊对目标的基础结果；缺省值依据 beneficial 语义保持正面牌为1、负面牌为-1。
	var subject_target_result: float = float(subject_ai_profile.get("target_result", 1.0 if bool(subject_ai_profile.get("beneficial", response_subject_definition.get("ai_beneficial", false))) else -1.0))
	# 响应后的抵消状态；true 表示本张无懈阻止原效果，false 表示反无懈恢复原效果。
	var negated_after_response: bool = bool(response_context.get("negated", false))
	# 本张无懈对原目标的等效结果；阻止时反转牌效，恢复时沿用原牌效。
	var response_target_result: float = -subject_target_result if negated_after_response else subject_target_result
	# 带上下文牌效的响应定义副本；只用于身份观察，不修改内容数据库中的卡牌定义。
	var contextual_response_definition: Dictionary = card_definition.duplicate(true)
	# 响应牌 AI 配置副本；保留无懈自身0.2显式暴露值，并补入当前奇偶方向的目标结果。
	var contextual_ai_profile: Dictionary = (contextual_response_definition.get("ai", {}) as Dictionary).duplicate(true)
	contextual_ai_profile["target_result"] = response_target_result
	contextual_response_definition["ai"] = contextual_ai_profile
	observe_card_use(authoritative_snapshot, actor_id, contextual_response_definition, [target_id], observer_id)


## 返回观察者对目标的当前态度；真实身份关系会按目标身份暴露度衰减，复刻无名杀 rawAttitude 思路。
func get_attitude(authoritative_snapshot: Dictionary, from_player_id: int, to_player_id: int) -> float:
	synchronize(authoritative_snapshot)
	# 观察者快照；不存在时无法建立身份关系。
	var from_player: Dictionary = get_player(authoritative_snapshot, from_player_id)
	# 目标快照；不存在时保持中立。
	var to_player: Dictionary = get_player(authoritative_snapshot, to_player_id)
	if from_player.is_empty() or to_player.is_empty():
		return 0.0
	# 目标身份标记；内奸或其他隐藏身份可暂时按公开行为被推断为忠臣或反贼。
	# 已公开身份始终覆盖旧的临时标记，避免角色死亡公开后仍按忠反猜测计算真实态度。
	var identity_mark: String = "" if bool(to_player.get("identity_revealed", false)) or str(to_player.get("identity", "")) == "leader" else str(_identity_mark_by_player.get(to_player_id, ""))
	# 真实或推断身份态度；身份标记存在时先按标记身份计算，对齐无名杀 identity_mark 的临时替代关系。
	var real_attitude: float = get_real_attitude(authoritative_snapshot, from_player_id, to_player_id, identity_mark)
	if from_player_id == to_player_id or bool(to_player.get("identity_revealed", false)) or str(to_player.get("identity", "")) == "leader":
		return real_attitude
	# 目标当前身份暴露度；0表示行为尚不足以支持明确阵营判断。
	var exposure: float = float(_exposure_by_player.get(to_player_id, 0.0))
	if identity_mark in ["loyalist", "rebel"]:
		exposure = maxf(exposure, IDENTITY_MARK_MINIMUM_CONFIDENCE)
	# 未暴露角色的弱推断；当场上反贼均已有明确行为时，其余隐藏非领袖角色获得0.3的最低判断权重。
	if is_zero_approx(exposure) and str(to_player.get("identity", "")) not in ["leader", "rebel"] and _all_rebels_exposed(authoritative_snapshot, from_player_id):
		exposure = NON_REBEL_MINIMUM_CONFIDENCE
	return real_attitude * exposure


## 返回不考虑身份隐藏的真实阵营态度；数值表依据无名杀标准身份模式并保留内奸动态平衡。
func get_real_attitude(authoritative_snapshot: Dictionary, from_player_id: int, to_player_id: int, assumed_target_identity: String = "") -> float:
	# 观察者状态；身份字段来自权威 AI 快照。
	var from_player: Dictionary = get_player(authoritative_snapshot, from_player_id)
	# 目标状态；体力、手牌和身份共同参与动态关系。
	var to_player: Dictionary = get_player(authoritative_snapshot, to_player_id)
	if from_player.is_empty() or to_player.is_empty():
		return 0.0
	if from_player_id == to_player_id:
		return 10.0
	# 观察者身份；项目稳定名称映射无名杀 zhu、zhong、fan、nei。
	var from_identity: String = str(from_player.get("identity", "renegade"))
	# 目标身份；未知值按内奸处理，避免把异常配置误判为固定友方。
	var to_identity: String = assumed_target_identity if assumed_target_identity in ["leader", "loyalist", "rebel", "renegade"] else str(to_player.get("identity", "renegade"))
	# 当前领忠方相对局势；正值代表领忠优势，负值代表反贼优势。
	var situation: int = get_situation(authoritative_snapshot)
	# 存活反贼数量；用于残局中的领袖、反贼与内奸关系调整。
	var rebel_count: int = get_population(authoritative_snapshot, "rebel")
	# 存活忠臣数量；用于判断反贼是否应继续容忍内奸。
	var loyalist_count: int = get_population(authoritative_snapshot, "loyalist")
	# 存活内奸数量；领袖在三人残局中需要平衡反贼与内奸威胁。
	var renegade_count: int = get_population(authoritative_snapshot, "renegade")
	# 当前存活人数；二人和三人残局采用无名杀的特殊关系分支。
	var alive_count: int = get_alive_player_count(authoritative_snapshot)
	if from_identity == "leader":
		if to_identity == "leader":
			return 10.0
		if to_identity == "loyalist":
			return 6.0
		if to_identity == "rebel":
			if rebel_count == 1 and renegade_count == 1 and alive_count == 3:
				return -3.0
			return -4.0
		if to_identity == "renegade":
			if alive_count == 2:
				return -10.0
			if rebel_count == 0:
				return -0.5
			if situation > 1:
				return 0.0
			return float(mini(3, rebel_count))
	if from_identity == "loyalist":
		if to_identity == "leader":
			return 10.0
		if to_identity == "loyalist":
			return 4.0
		if to_identity == "rebel":
			return -8.0
		if to_identity == "renegade":
			return -2.0 if rebel_count == 0 else float(mini(3, -situation))
	if from_identity == "rebel":
		if to_identity == "leader":
			return -5.0 if renegade_count > 0 and situation > 0 else -8.0
		if to_identity == "loyalist":
			return -7.0
		if to_identity == "rebel":
			return 5.0
		if to_identity == "renegade":
			if rebel_count == 1:
				return 0.0
			if loyalist_count == 0:
				return -2.0
			return 3.0
	if from_identity == "renegade":
		if to_identity == "leader" and alive_count == 2:
			return -10.0
		if to_identity != "leader" and alive_count == 3:
			return -8.0
		if to_identity == "leader":
			if rebel_count == 0:
				return -5.0
			if situation > 1:
				return -2.0
			return float(rebel_count + maxi(0, 3 - int(to_player.get("hp", 0))))
		if to_identity == "loyalist":
			if rebel_count == 0:
				return -5.0
			return float(mini(0, -situation))
		if to_identity == "rebel":
			if situation < -1:
				return -3.0
			if situation < 0 or loyalist_count == 0:
				return -2.0
			if situation > 1:
				return 1.0
			return 0.0
		if to_identity == "renegade":
			return 0.0
	return -1.0


## 计算无名杀身份 AI 使用的领忠方局势值；正数代表领忠优势，负数代表反贼优势。
func get_situation(authoritative_snapshot: Dictionary) -> int:
	# 领忠方净强度；领袖、忠臣和反贼使用不同权重累计。
	var loyal_side_strength: float = 0.0
	# 全部参与比较的总强度；用于把结果归一化到约-10至10。
	var total_strength: float = 0.0
	# 领袖基础强度；极端劣势时用于追加无名杀的领袖危险修正。
	var leader_strength: float = 0.0
	# 反贼总强度；与领袖强度共同判断领袖濒危局面。
	var rebel_strength: float = 0.0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前存活玩家；死亡或离场角色不再参与局势强度。
		var player: Dictionary = player_variant as Dictionary
		if not bool(player.get("alive", false)) or bool(player.get("out_of_game", false)):
			continue
		# 体力贡献；无名杀把过高体力限制到6，避免异常上限完全压过牌差。
		var hp_value: float = float(mini(int(player.get("hp", 0)), 6))
		# 手牌数量；身份 AI 只需要数量估值，不依赖具体隐藏牌面。
		var hand_count: float = float(player.get("hand_count", 0))
		# 装备数量；每件装备按1.5张手牌计入场面强度。
		var equipment_count: float = float((player.get("equipment", {}) as Dictionary).size())
		# 当前玩家基础强度；公式与无名杀 `get.situation()` 保持一致。
		var player_strength: float = hand_count + equipment_count * 1.5 + hp_value * 2.0
		# 当前玩家身份；只对标准四身份计入阵营净值。
		var identity: String = str(player.get("identity", ""))
		if identity == "leader":
			leader_strength = player_strength
			loyal_side_strength += player_strength * 1.2 + 5.0
			total_strength += player_strength * 1.2 + 5.0
		elif identity == "loyalist":
			loyal_side_strength += player_strength * 0.8 + 3.0
			total_strength += player_strength * 0.8 + 3.0
		elif identity == "rebel":
			loyal_side_strength -= player_strength + 4.0
			total_strength += player_strength + 4.0
			rebel_strength += player_strength + 4.0
	if total_strength <= 0.0:
		return 0
	# 归一化结果；取整方式与无名杀 parseInt 的向零截断语义一致。
	var result: int = int(10.0 * absf(loyal_side_strength / total_strength))
	if loyal_side_strength < 0.0:
		result = -result
	if leader_strength < 12.0 and rebel_strength > 30.0:
		result -= 1
	if leader_strength < 6.0 and rebel_strength > 15.0:
		result -= 1
	if leader_strength < 4.0:
		result -= 1
	return result


## 返回指定玩家的无名杀 condition 强度；体力、手牌和装备共同表示其行动与生存能力。
func get_condition(authoritative_snapshot: Dictionary, player_id: int) -> float:
	# 指定玩家快照；不存在时强度为0。
	var player: Dictionary = get_player(authoritative_snapshot, player_id)
	if player.is_empty():
		return 0.0
	# 基础体力强度；超过4点的部分使用平方根衰减。
	var condition: float = float(player.get("hp", 0))
	if condition > 4.0:
		condition = 4.0 + sqrt(condition - 4.0)
	elif int(player.get("hp", 0)) == int(player.get("max_hp", 0)):
		if int(player.get("hp", 0)) == 3:
			condition += 0.5
		elif int(player.get("hp", 0)) < 3:
			condition += 1.0
	condition += float(player.get("hand_count", 0)) / 2.0
	# 装备强度；身份模型保持独立，不读取内容数据库，每件公开装备按无名杀普通3分装备增加0.2。
	condition += float((player.get("equipment", {}) as Dictionary).size()) * 0.2
	return condition


## 按稳定玩家 ID 查找快照；返回深层引用只供本次只读评估，不得由 AI 修改。
func get_player(authoritative_snapshot: Dictionary, player_id: int) -> Dictionary:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；ID 匹配后立即返回。
		var player: Dictionary = player_variant as Dictionary
		if int(player.get("player_id", -1)) == player_id:
			return player
	return {}


## 返回指定身份的存活人数；死亡与离场角色不参与残局关系。
func get_population(authoritative_snapshot: Dictionary, identity: String) -> int:
	# 匹配人数；从0开始累计。
	var result: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；只统计仍在游戏中的指定身份。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and str(player.get("identity", "")) == identity:
			result += 1
	return result


## 返回当前存活且未离场的玩家数量；用于二人和三人残局特殊态度。
func get_alive_player_count(authoritative_snapshot: Dictionary) -> int:
	# 存活人数；逐项统计避免依赖数组是否保留死亡玩家。
	var result: int = 0
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；死亡或离场时跳过。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)):
			result += 1
	return result


## 返回指定身份的首名存活玩家 ID；标准身份局领袖唯一，其他身份只用于通用查询。
func find_identity_player_id(authoritative_snapshot: Dictionary, identity: String) -> int:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；只返回仍存活且未离场的指定身份。
		var player: Dictionary = player_variant as Dictionary
		if bool(player.get("alive", false)) and not bool(player.get("out_of_game", false)) and str(player.get("identity", "")) == identity:
			return int(player.get("player_id", -1))
	return -1


## 返回隐藏身份当前忠反标记；空字符串表示行为不足以形成稳定推断。
func get_identity_mark(player_id: int) -> String:
	return str(_identity_mark_by_player.get(player_id, ""))


## 返回指定玩家当前身份暴露度；测试、调试与战略层只读使用。
func get_exposure(player_id: int) -> float:
	return float(_exposure_by_player.get(player_id, 0.0))


## 返回观察者当前可用于战略判断的目标身份；只允许公开身份和行为标记，禁止通过权威快照偷看隐藏身份。
func get_perceived_identity(authoritative_snapshot: Dictionary, player_id: int) -> String:
	# 目标玩家快照；不存在时返回 unknown，调用方应按中立目标处理。
	var player: Dictionary = get_player(authoritative_snapshot, player_id)
	if player.is_empty():
		return "unknown"
	# 目标真实身份；仅在领袖或身份已公开时可直接用于战略层。
	var identity: String = str(player.get("identity", ""))
	if identity == "leader" or bool(player.get("identity_revealed", false)):
		return identity
	# 目标行为身份标记；隐藏角色只能依据忠反信号暂时归入领忠方或反贼方。
	var identity_mark: String = get_identity_mark(player_id)
	return identity_mark if identity_mark in ["loyalist", "rebel"] else "unknown"


## 返回当前目标可作为身份参照的证据权重；未暴露目标与内奸均不能向行动者反推稳定阵营。
func _get_target_evidence_weight(authoritative_snapshot: Dictionary, target_id: int) -> float:
	# 目标玩家快照；不存在的目标不提供任何身份线索。
	var target: Dictionary = get_player(authoritative_snapshot, target_id)
	if target.is_empty() or str(target.get("identity", "")) == "renegade":
		return 0.0
	# 目标当前暴露度绝对值；负暴露同样代表已经产生可观察身份行为。
	var target_exposure: float = absf(float(_exposure_by_player.get(target_id, 0.0)))
	if target_exposure < TARGET_EVIDENCE_IGNORE_THRESHOLD:
		return 0.0
	if target_exposure < TARGET_EVIDENCE_HALF_THRESHOLD:
		return TARGET_EVIDENCE_HALF_WEIGHT
	if target_exposure < TARGET_EVIDENCE_MOST_THRESHOLD:
		return TARGET_EVIDENCE_MOST_WEIGHT
	return 1.0


## 根据信号更新忠反标记；达到正负0.2即形成初步判断，回到中间区间则清除。
## 当前标记状态机进一步对齐无名杀：忠反角色按真实身份在正暴露后定型，内奸相反行为会清空并永久终结猜测。
func _update_identity_mark(authoritative_snapshot: Dictionary, player_id: int, leader_camp_effect: float, observer_id: int, self_target_only: bool) -> void:
	# 当前忠反行为信号；正值偏忠，负值偏反。
	var camp_signal: float = float(_camp_signal_by_player.get(player_id, 0.0))
	# 信号边界完整性检查；正常入口始终先限制到正负1，异常值不应生成不可信标记。
	if absf(camp_signal) > CAMP_SIGNAL_LIMIT:
		return
	# 行动者快照；身份公开、领袖、本地观察者本人和纯自用行为都不生成自动猜测。
	var actor: Dictionary = get_player(authoritative_snapshot, player_id)
	if actor.is_empty() or bool(actor.get("identity_revealed", false)) or str(actor.get("identity", "")) == "leader" or player_id == observer_id or self_target_only:
		return
	if bool(_identity_mark_finished_by_player.get(player_id, false)):
		return
	# 行动者真实身份；只用于复刻无名杀非内奸正暴露后的确定阵营显示，不向战略层直接公开。
	var actor_identity: String = str(actor.get("identity", ""))
	# 当前临时身份标记；内奸需要用它判断本次行为是否与既有伪装方向相反。
	var current_identity_mark: String = str(_identity_mark_by_player.get(player_id, ""))
	if actor_identity == "renegade":
		if leader_camp_effect > 0.0:
			if current_identity_mark == "rebel":
				_identity_mark_by_player[player_id] = ""
				_identity_mark_finished_by_player[player_id] = true
			else:
				_identity_mark_by_player[player_id] = "loyalist"
		elif leader_camp_effect < 0.0 and get_population(authoritative_snapshot, "rebel") > 0:
			if current_identity_mark == "loyalist":
				_identity_mark_by_player[player_id] = ""
				_identity_mark_finished_by_player[player_id] = true
			else:
				_identity_mark_by_player[player_id] = "rebel"
		return
	# 非内奸只有产生正暴露后才按真实忠反阵营定型；违背自身利益的误操作不会反向贴错身份。
	var exposure: float = float(_exposure_by_player.get(player_id, 0.0))
	if exposure <= 0.0:
		return
	if actor_identity == "rebel":
		_identity_mark_by_player[player_id] = "rebel"
		_identity_mark_finished_by_player[player_id] = true
	elif actor_identity == "loyalist":
		_identity_mark_by_player[player_id] = "loyalist"
		_identity_mark_finished_by_player[player_id] = true


## 判断除观察者外的全部存活反贼是否已有可判断行为；用于无名杀隐藏身份的最低推断权重。
func _all_rebels_exposed(authoritative_snapshot: Dictionary, observer_id: int) -> bool:
	for player_variant: Variant in authoritative_snapshot.get("players", []) as Array:
		# 当前玩家快照；只检查其他仍存活的反贼。
		var player: Dictionary = player_variant as Dictionary
		# 当前玩家 ID；观察者自己不影响对其他身份的最低推断。
		var player_id: int = int(player.get("player_id", -1))
		if player_id == observer_id or not bool(player.get("alive", false)) or str(player.get("identity", "")) != "rebel":
			continue
		if is_zero_approx(float(_exposure_by_player.get(player_id, 0.0))):
			return false
	return true
