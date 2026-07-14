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

响应类操作目前由规则层的基础自动策略处理，包括闪、杀、桃、酒、无懈可击和装备可选效果。后续若需要更强 AI，应把响应窗口也包装成候选动作列表交给策略，但仍保持统一动作协议。

## 替换策略

新增策略需提供：

```gdscript
func choose_action(authoritative_snapshot: Dictionary, legal_actions: Array[Dictionary]) -> Dictionary
```

策略返回值必须可序列化，且至少包含 `action_type` 与 `actor_id`。使用牌动作还需 `card_uid` 和 `target_ids`。搜索树、效用系统、行为树或模型推理都可放在策略内部，不能调用控制器的伤害、摸牌或移动函数。

## 调度安全

- `ai_action_delay_seconds` 默认 0.35 秒，仅控制展示节奏。
- `max_ai_actions_per_turn` 默认 64，超过后强制结束出牌阶段。
- `character_candidate_count` 默认 5；基础 AI 只在自己的候选列表内选将，该数量不影响出牌阶段动作上限。
- `_ai_drive_token` 在阶段变化时递增，旧计时器不会在新阶段误操作。
- 固定对局随机种子可用于复盘和回归测试。
