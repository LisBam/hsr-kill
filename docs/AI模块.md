# AI 模块

## 分层接口

AI 不持有 `GameState` 的可变引用。每次需要行动时，控制器执行以下流程：

1. 根据当前状态和卡牌规则枚举合法动作。
2. 使用 `state.to_dict(player_id, true)` 生成权威完整快照。
3. 调用 `AICoordinator.request_action(player_id, snapshot, legal_actions)`。
4. AI 策略只返回动作字典。
5. 动作重新转换为 `PlayerAction`，进入与人类玩家相同的 `submit_action` 校验入口。

选将阶段由 `MatchController` 查询 `CharacterSelectionService` 的待确认玩家。基础 AI 从自己的随机候选列表选择首项，并构造 `select_character` 动作；主公 AI 先确认并亮将，其他 AI 只在阶段推进后同时确认。AI 不直接写入玩家武将或体力，也不能读取其他玩家未公开的候选和选择。

这保证 AI 即使读取全局身份、全部手牌、装备和阶段，也不能绕过次数、距离、目标或区域规则。

## 当前基础策略

`BasicAIPolicy` 使用轻量启发式评分：优先补牌、治疗、装备和对敌方使用伤害/控制牌；主公与忠臣互相视为友方，反贼以主忠为敌方，内奸采用保守负态度。无正收益动作时结束出牌阶段。

响应类操作统一创建选择请求，包括【闪】、【杀】、【桃】、【酒】、【无懈可击】、银月枪和装备可选效果。AI 先收到与人类相同的候选牌快照，再由 `choose_card_choice()` 返回 `choose_cards` 动作；控制器会重新校验请求序号、候选 UID、选择数量和当前牌区，不能直接消耗牌。无响应牌时仍创建允许放弃的空候选请求，确保是否响应不由规则层根据是否持牌直接强制决定。具有有效`match_id`的正式对局中，AI 选牌响应不会同步提交：请求会保持暂停，等待全局 AI 响应时间后才构造标准动作并恢复结算。无`match_id`的纯规则预演和无头测试仍同步调用相同策略，以保证服务端查询和固定数据断言具有确定性；该边界不影响任何正式对局节奏。

运行时层把上述兼容动作转换为 `ChoiceResponse`。`AICoordinator.request_choice()` 返回与本地和网络完全相同的请求 ID、事件 ID、actor、confirmed、实体牌 UID 和 source 字段；AI 不需要知道 `GameEvent` 的 Callable 或控制器对象。超时托管只需把 source 改为 `timeout`，规则校验路径不变。

弃牌阶段、火攻展示与弃牌、过河拆桥、顺手牵羊、五谷丰登和其他区域选牌也使用相同的请求协议。候选完全属于本人手牌或木牛“粮”时由桌面手牌区维护临时 UID 选择，其他区域由 `CardSelectionPanel` 展示正面或牌背；两者都只发出提交信号，不直接修改 `GameState`。五谷的 AI 仍按可调响应时间提交标准 `choose_cards` 动作，但公共窗口不会因当前选择者是 AI 而关闭；权威 `public_card_choice_display` 会持续公开固定牌位和已领取归属，AI 只能从当前请求仍允许的 UID 中选择。

## 替换策略

新增策略需提供：

```gdscript
func choose_action(authoritative_snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary
```

策略返回值必须可序列化，且至少包含 `action_type` 与 `actor_id`。使用牌动作还需 `card_uid` 和 `target_ids`。搜索树、效用系统、行为树或模型推理都可放在策略内部，不能调用控制器的伤害、摸牌或移动函数。

选择请求动作必须包含 `action_type="choose_cards"`、`actor_id`、`payload.request_id` 和 `payload.selected_card_uids`。候选中的 `visible=false` 手牌只提供稳定 UID 与牌背语义，不包含定义 ID、花色或点数。

## 调度安全

- `GameSettings.ai_response_delay_seconds` 默认 0.30 秒，局内菜单“AI响应速度”可在 0.05 至 1.00 秒之间以 0.05 秒步长调整；数值表示每次 AI 行动或选牌响应前的等待时间，数值越小响应越快。
- `ai_action_delay_seconds` 是控制器当前使用的等待值，会订阅全局设置用于后续计时器；自动化测试可直接覆盖该字段以缩短测试等待，不改变玩家运行时设置。
- `max_ai_actions_per_turn` 默认 64，超过后强制结束出牌阶段。
- `character_candidate_count` 默认 5；基础 AI 只在自己的候选列表内选将，该数量不影响出牌阶段动作上限。
- `_ai_drive_token` 在阶段变化时递增，旧计时器不会在新阶段误操作。
- `_scheduled_ai_drive_token` 记录当前阶段已经安排但尚未执行的唯一任务；AI 出牌被本地【闪】、无懈、五谷或其他选择暂停后，响应完成会重新安排后续行动，同一阶段令牌不会生成重复计时器。
- `_scheduled_ai_choice_request_id` 记录当前等待的 AI 选牌请求；重开、换回合、终局或请求 ID 变化后，旧计时器不会向新请求提交响应。
- 固定对局随机种子可用于复盘和回归测试。
- `GameState.random_seed`、`random_history`、事件历史和移牌历史可独立保存；AI 决策不依赖 Godot 场景节点。
