# Bootstrap Task: Fill Project Development Guidelines

**You (the AI) are running this task. The developer does not read this file.**

The developer just ran `trellis init` on this project for the first time.
`.trellis/` now exists with empty spec scaffolding, and this bootstrap task
exists under `.trellis/tasks/`. When they want to work on it, they should start
this task from a session that provides Trellis session identity.

**Your job**: help them populate `.trellis/spec/` with the team's real
coding conventions. Every future AI session — this project's
`trellis-implement` and `trellis-check` sub-agents — auto-loads spec files
listed in per-task jsonl manifests. Empty spec = sub-agents write generic
code. Real spec = sub-agents match the team's actual patterns.

Don't dump instructions. Open with a short greeting, figure out if the repo
has any existing convention docs (CLAUDE.md, .cursorrules, etc.), and drive
the rest conversationally.

---

## Status (update the checkboxes as you complete each item)

- [x] 按项目真实分层重建 spec 结构（删除不适用的 backend / frontend 模板）
- [x] 填写 5 个分层的指南（project / content / core / ui / adapters）
- [x] 加入真实代码路径、真实命令与权威文档引用作为依据
- [x] 本地化 `guides/` 共享思维指南，移除与本项目无关的模板内容

---

## 完成记录（2026-09-23）

本项目是 **Godot 4.6 / GDScript 单仓库项目**（主场景 `res://scenes/main.tscn`）。
`trellis init` 生成的 `spec/backend` 与 `spec/frontend`（Web 前后端模板）完全不适用，
因此**删除**并按其真实分层重建。

Trellis 的 spec 定位是「注入给 AI 编码子代理的工程约定」，不是项目百科。
项目已有 `docs/` 权威文档体系，因此 spec 只做**提炼与索引**，深度细节仍以 `docs/` 为准。

### 实际落地结构

| Spec 层 | 覆盖的真实目录 | 文件 |
|---|---|---|
| `project/` | 跨层全局约定 | `index.md`、`collaboration-rules.md`、`documentation-sync.md`、`verification.md` |
| `content/` | `game_data/cards`、`skills`、`characters`、`data/decks.json` | `index.md`、`naming-and-directory.md`、`card-authoring.md`、`skill-authoring.md`、`content-ai.md` |
| `core/` | `scripts/core`、`scripts/data`、`scripts/opportunity` | `index.md`、`layering-and-state.md`、`event-runtime-phases.md` |
| `ui/` | `scripts/ui`、`scenes` | `index.md`、`component-patterns.md` |
| `adapters/` | `scripts/ai`、`scripts/network`、`scripts/autoload`、`scripts/platform` | `index.md`、`ai-pipeline.md`、`network-layer.md`、`autoload-and-platform.md` |
| `guides/` | 跨层思维指南（已本地化） | `index.md`、`code-reuse-thinking-guide.md`、`cross-layer-thinking-guide.md` |

另有 `.trellis/spec/index.md` 作为总导航：分层地图 + `docs/` 权威文档索引 + 禁读禁改清单 + 五条总纲原则。

每个 `index.md` 均含 Trellis 约定的 **Pre-Development Checklist** 与 **Quality Check** 两节。

### 素材来源（全部来自项目真实资产）

`AGENTS.md`、`项目专属AGENTS.md`、`docs/架构说明.md`、`docs/内容制作指南.md`、
`docs/游戏机制与玩法内容.md`、`docs/卡牌系统.md`、`docs/AI模块.md`、`docs/网络通信.md`、
`docs/界面与交互.md`、`README.md`，以及 `scripts/`、`game_data/` 的真实目录与文件路径。

规则冲突时以 `docs/` 为准；spec 内的每条约定都指向真实文件或真实文档章节。

### 验证

```bash
python ./.trellis/scripts/get_context.py --mode packages
# → Spec layers: adapters, content, core, project, ui
```

`.trellis/spec/` 内已无任何模板占位符（`To fill` / `TODO: fill` / `placeholder` 均已清零）。

---

## How to fill the spec

### Step 1: Import from existing convention files first (preferred)

Search the repo for existing convention docs. If any exist, read them and
extract the relevant rules into the matching `.trellis/spec/` files —
usually much faster than documenting from scratch.

| File / Directory | Tool |
|------|------|
| `CLAUDE.md` / `CLAUDE.local.md` | Claude Code |
| `AGENTS.md` | Codex / Claude Code / agent-compatible tools |
| `.cursorrules` | Cursor |
| `.cursor/rules/*.mdc` | Cursor (rules directory) |
| `.windsurfrules` | Windsurf |
| `.clinerules` | Cline |
| `.roomodes` | Roo Code |
| `.github/copilot-instructions.md` | GitHub Copilot |
| `.vscode/settings.json` → `github.copilot.chat.codeGeneration.instructions` | VS Code Copilot |
| `CONVENTIONS.md` / `.aider.conf.yml` | aider |
| `CONTRIBUTING.md` | General project conventions |
| `.editorconfig` | Editor formatting rules |

### Step 2: Analyze the codebase for anything not covered by existing docs

Scan real code to discover patterns. Before writing each spec file:
- Find 2-3 real examples of each pattern in the codebase.
- Reference real file paths (not hypothetical ones).
- Document anti-patterns the team clearly avoids.

### Step 3: Document reality, not ideals

**Critical**: write what the code *actually does*, not what it should do.
Sub-agents match the spec, so aspirational patterns that don't exist in the
codebase will cause sub-agents to write code that looks out of place.

If the team has known tech debt, document the current state — improvement
is a separate conversation, not a bootstrap concern.

---

## Quick explainer of the runtime (share when they ask "why do we need spec at all")

- Every AI coding task spawns two sub-agents: `trellis-implement` (writes
  code) and `trellis-check` (verifies quality).
- Each task has `implement.jsonl` / `check.jsonl` manifests listing which
  spec files to load.
- The platform hook auto-injects those spec files + the task's `prd.md`
  into every sub-agent prompt, so the sub-agent codes/reviews per team
  conventions without anyone pasting them manually.
- Source of truth: `.trellis/spec/`. That's why filling it well now pays
  off forever.

---

## Completion

When the developer confirms the checklist items above are done with real
examples (not placeholders), guide them to run:

```bash
python ./.trellis/scripts/task.py finish
python ./.trellis/scripts/task.py archive 00-bootstrap-guidelines
```

After archive, every new developer who joins this project will get a
`00-join-<slug>` onboarding task instead of this bootstrap task.

---

## Suggested opening line

"Welcome to Trellis! Your init just set me up to help you fill the project
spec — a one-time setup so every future AI session follows the team's
conventions instead of writing generic code. Before we start, do you have
any existing convention docs (CLAUDE.md, .cursorrules, CONTRIBUTING.md,
etc.) I can pull from, or should I scan the codebase from scratch?"
