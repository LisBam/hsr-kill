# 【铁索连环】使用时机与重铸时机 —— 无名杀参考实现 vs 本项目现状（只读调研证据）

本文件是子任务 `10-01-tiesuo-lianhuan-ai` 的调研证据留档，供实现时逐条对照。全部结论来自只读阅读 `无名杀参考代码\` 与本项目源码，未修改任何文件。

## 1. 无名杀卡牌定义与 `ai` 字段

定义在 `无名杀参考代码\无名杀诗笺版Windows64位\resources\app\card\extra.js:327`。

```js
tiesuo: {
    type: "trick", enable: true, filterTarget: true,
    selectTarget: [1, 2], complexTarget: true,
    content: function () { target.link(); },   // 切换横置，等价本项目 toggle_player_linked
    recastable: true,
ai: { wuxie: (target, card, player, viewer, status) => {
        if (status * get.attitude(viewer, player._trueMe || player) > 0 || target.hasSkillTag("nodamage") || target.hasSkillTag("nofire") || target.hasSkillTag("nothunder") || get.attitude(viewer, player) > 0 || (1 + target.countCards("hs")) * _status.event.getRand() > 1.57) return 0;
    },
    basic: { order: 7.3, useful: 1.2, value: 4 },
```

### `ai.result.target`（`extra.js:348-389`）要点

```js
result: { target: (player, target) => {
    if (target.hasSkillTag("link")) return 0;                    // 免疫横置者直接跳过
    let curs = game.filterPlayer(current => {                    // 能承受火/雷伤害的角色
        if (current.hasSkillTag("nodamage")) return false;
        return !current.hasSkillTag("nofire") || !current.hasSkillTag("nothunder");
    });
    if (curs.length < 2) return 0;                               // 场上不足2人可被属性伤害 → 不用
    let f = target.hasSkillTag("nofire"), t = target.hasSkillTag("nothunder"), res = 0.9;
    if ((f && t) || target.hasSkillTag("nodamage")) return 0;
    if (f || t) res = 0.45;                                      // 只免疫一种属性 → 收益减半
    if (!f && target.getEquip("tengjia")) res *= 2;              // 【藤甲】= 横置收益翻倍
    if (!target.isLinked()) res = -res;                          // 令未横置者横置 = 对目标负收益
    if (ui.selected.targets.length) return res;                  // 第二个目标跳过下面全部全局否决
    let fs = 0, es = 0, att = get.attitude(player, target), linkf = false, alink = true;
    curs.forEach(i => {
        let atti = get.attitude(player, i);
        if (atti > 0) { fs++; if (i.isLinked()) linkf = true; }
        else if (atti < 0) { es++; if (!i.isLinked()) alink = false; }
    });
    if (es < 2 && !alink) {
        if (att <= 0 || (att > 0 && linkf && fs < 2)) return 0;  // ≥2敌且已有敌人横置时不再横置敌人
    }
    return res;
}},
tag: { multitarget: 1, multineg: 1, norepeat: 1 },
```

`res` 的符号是“对目标本人”的方向（横置=负、解除=正），再由 `get.effect_use` 乘态度；因此横置敌人为正、解除敌营为负。

### 属性伤害侧联动

- `card/standard.js:329-340`：【杀】的 `order` 基础 3.2；带 `linked` 属性且场上横置人数 ≥2 时提升到 3.35。
- `card/standard.js:292-293`：`canLink` 要求目标已横置或来源拥有 `wutiesuolian_skill`。
- `ai.wuxie` 的消费点在 `standard.js:3492-3504`，非 `multitarget` 牌按 `-get.effect(target,card,source,viewer)*state` 决策。

## 2. 无名杀通用「重铸」机制

重铸不是卡牌字段驱动，而是全局技能 `lib.skill._recasting`（出牌阶段可用），可用性走 `lib.filter.cardRecastable`。

- `noname/library/index.js:10030-10044` `cardRecastable`：`strict` 模式下要求牌在 `hand`，且 `info.recastable || info.chongzhu` 为真。
- `noname/library/index.js:12161-12207` `_recasting`：`ai: { basic: { order: 6 }, result: { player: 1 } }`，即**重铸的 order 固定为6**。
- `noname/library/element/player.js:1003-1028` `recast()`：弃置所选牌并摸等量的牌。

### AI 用牌 vs 重铸的裁决链（结论：先按 order 试“用”，用不出去才退化为重铸）

- `noname/library/element/player.js:4639-4640`：默认 `ai1 = get.cacheOrder`（候选按 order 从高到低试），`ai2 = get.cacheEffectUse`。
- `noname/get/index.js:4864-4881`：`order()` 取 `ai.order` 或 `ai.basic.order`。
- `noname/ai/basic.js:131-148`：`if (check(cards[ix]) <= 0) ... return ok;`，即 `order > 0` 即通过；选中技能（如 `_recasting`）后 `check = info.check || get.unuseful2`。
- `noname/library/element/content.js:4161-4180`：`chooseCard` 成功但 `chooseTarget` 失败时执行 `get.card(true).aiexclude(); game.uncheck(); event.redo();`，即把该实体牌排除后重投。
- `noname/get/index.js:4750-4751`：`get.unuseful2 = 10 - get.useful(card)`。

铁索 order 7.3 > 重铸 order 6，因此 AI 先尝试使用；只有当**没有任何正收益目标**（`ai.result.target` 对全部目标返回 0/负）导致目标选择失败时，才把这张实体牌排除，让下一顺位的 `_recasting` 胜出，并在手牌中挑出最没用的那张重铸。

## 3. 无名杀对【铁索连环】的 AI 决策要素

- **横置敌人**：先过“场上至少2名能受火/雷伤害的角色”；未横置敌人 `res=-0.9` 乘负态度后为正；`es >= 2 && !alink` 时拒绝继续横置敌人。
- **重置自己/队友**：`if (!target.isLinked()) res = -res` 使已横置目标返回 `+0.9`，乘正态度即为正收益；`linkf && fs < 2` 分支专门保留“解除单名队友横置”这条通道。
- **免疫与减免**：`link` / `nodamage` / `nofire && nothunder` 的目标直接0；只免疫一种属性则 `res = 0.45`；【藤甲】且不免火则 `res *= 2`。
- **重铸 vs 使用**：无独立判断，完全由 order 排序 + “目标选不出来就 aiexclude 退化”决定。
- **单/双目标**：`selectTarget:[1,2]` + `complexTarget:true`；首个目标决定整张牌是否值得使用，第二个目标只受自身 `res > 0` 约束。
- **配合属性伤害**：铁索侧只提供“场上可受属性伤害者 ≥2”与藤甲翻倍，属性伤害侧由【杀】自己判断。
- **无懈侧**：`(1 + target.countCards("hs")) * getRand() > 1.57` 的随机保留策略。

## 4. 本项目现状

卡牌：`game_data/cards/tiesuolianhuan.gd`（141行；`recast: true` 第32行；`ai: {order 7.3, value 4.0, target_result -0.5, multitarget true}` 第38行）。

- 效果 `resolve()` 第44-54行逐目标 `resolver.host.toggle_player_linked()`，与无名杀 `target.link()` 同义。
- 目标枚举 `append_play_phase_card_actions()` 第70-81行穷举 C(n,1)+C(n,2) 组合，接管了 `scripts/core/match_controller.gd:2210-2213` 的默认单目标枚举。
- **使用打分**：通用式在 `scripts/ai/noname_ai_evaluator.gd:282`（`player_result + order*0.12 - card_value*0.08`），逐目标加 `score_target_effect()`（第371行，`target_result * attitude / 5`），第297-298行对可重铸牌额外扣 `max(0, 4.5 - card_value) * 0.5`；随后进入卡牌专属 `modify_ai_action_score()`（`tiesuolianhuan.gd:85-141`）：1v1（存活=2，第93-103行）强制重铸；否则逐目标把 `target_result` 按 `chained` 反号（第116-121行）；无正收益目标或不超过 `recast_score + 0.15`（第137-140行）时返回重铸分。
- **重铸打分**：`noname_ai_evaluator.gd:1323-1329` `_score_recast_action() = RECAST_DRAW_VALUE(4.5) - card_value`；合法动作由 `match_controller.gd:2201-2202` 为每张 `recast:true` 手牌生成，执行入口 `_execute_recast()`（第13308-13322行）、`recast_hand_card()`（第13326行）。
- 横置规则 `match_controller.gd:4547-4575`；属性伤害传导 `match_controller.gd:4755-4786` + `scripts/core/damage_resolution_service.gd:386-394`。
- 现有横置相关 AI：`noname_ai_evaluator.gd:380-389` / `472-508`（已横置传导收益 `_score_chained_damage_effect()`）、第711-747行 `_should_decline_response_for_friendly_chain_damage()`、第813-824行无懈调用 `get_identity_observation_target_result()`（`tiesuolianhuan.gd:57-66`）。
- **数值实证（att=±10）**：使用基础分 = `7.3×0.12 − 4.0×0.08 − (4.5−4.0)×0.5` = **0.306**；重铸分 = `4.5 − 4.0` = **0.5**；使用需超过 `0.65`。未横置敌人 `1.306` → 用；未横置队友 `−0.694` → 重铸；已横置敌人 `1.306−2.0−0.75` → 重铸；已横置队友 `1.306` → 用（解链）。

## 5. 可移植差异清单（按重要性排序）

1. **缺“场上可受属性伤害角色 ≥2”的硬门槛**（无名杀 `extra.js:351-355`）。本项目残局只剩1名可受伤角色时仍给正分。建议在 `modify_ai_action_score()` 内统计快照中“非 nodamage 且非（免火且免雷）”的存活角色数，<2 时按重铸分返回。
2. **缺“≥2敌且已有敌人横置则不再横置敌人”的否决**（`extra.js:364-382` 的 `es`/`alink`/`fs`/`linkf` 四量）。建议在卡牌 `modify_ai_action_score()` 内先统计敌方数与敌方已横置数，命中条件时把该组合压到重铸分之下。
3. **缺目标免疫横置/免疫单属性伤害的筛选与【藤甲】翻倍**（`extra.js:350-361`）。本项目 `score_target_effect()` 对铁索一律按 `-0.5 × att` 计分。建议给 `score_target_effect()` 增加“牌效为横置”的标记分支，把倍率与免疫查询放进护甲定义与技能标签查询，而不是在卡牌文件里硬编码【藤甲】牌名。
4. **1v1 强制重铸是项目专属规则**（`tiesuolianhuan.gd:11/93-103`）。无名杀无此分支。建议保留但补注释说明差异。
5. **双目标判定口径不同**。无名杀要求第二个目标自身 `res>0`，本项目按整组合总分权衡。建议保留现口径但注释标明差异。
6. **`multitarget` 字段未被铁索使用**。当前唯一消费点是 `game_data/skills/wuxie_2.gd:86`。若采纳第1、2条可复用该字段作为“需要群体协同判断”的开关，避免新增字段。
7. **无懈侧无“目标手牌越多越不无懈”的保留策略**（`extra.js:341`）。本项目为确定性净收益（`noname_ai_evaluator.gd:752-809`）。低优先级；若要移植请改成确定性手牌阈值，**不要**照搬 `getRand()`（本项目不使用随机）。
