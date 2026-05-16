# 从 v4.7 升级到 v4.10 — 新版本使用指南

> 适用对象：使用 darkhucx fork（已同步 upstream `Chachamaru127/claude-code-harness@v4.10.0+ Phase 69`）
> 上游覆盖范围：v4.8.0 / v4.8.1 / v4.9.0 / v4.10.0 + Phase 69（CC 2.1.133–2.1.142）

## 本次同步带来了什么

| 类别 | 关键变化 |
|---|---|
| 评审 (`/harness-review`) | 重构为薄 dispatcher，新增 `--quick` / `--codex-closeout` 轻量路径；默认 read-only，不再自动 commit |
| 实施 (`/harness-work`) | 新增 `--tdd-bypass` 与 `--plan NAME` 两个 flag |
| 非工程师视图 (Phase 65) | 三个新 HTML 出口：`/harness-plan-brief`、`/harness-progress`、`/harness-accept` |
| Cross-project 安全 | mem 搜索默认 project-scoped；横断检索需在 yaml 中明示 group |
| CC 2.1.133–2.1.142 集成 | `worktree.baseRef`、`autoMode.hard_deny`、hook `args`/`continueOnBlock`/`terminalSequence` |
| Fork 特有（保留） | Phase 70 = Codex auth、Phase 71 = Ollama（原编号 63/64，因与 upstream 撞号已重编） |

---

## 1. `/harness-review` 三种轻重模式

之前 `harness-review` 是 878 行的单一 SKILL，做小评审也跑全套。现在按使用场景分了路径。

### 1.1 `--quick`：脏改 / 小 PR 的快速评审

```bash
/harness-review --quick
```

- 适合：working tree 还没 commit、单个小 PR、单个 commit
- 行为：自动选 review target、运行 focused tests、把发现分成 `accepted` / `rejected` 两栏
- 结束条件：clean 后就停，不再追加"为好看而做的" review

### 1.2 `--codex-closeout`：Codex 做 closeout review

```bash
/harness-review --codex-closeout
```

- 适合：想拉 Codex 做第二意见
- 行为：调 `scripts/codex-companion.sh review --base ...`，把 Codex 的指摘当 **advisory**（不是命令），由 Harness 在真实代码上验证
- Codex 不可用时：fallback 到 manual full pass（不会把失败当成功）

### 1.3 其他子模式

```bash
/harness-review code          # 代码评审
/harness-review plan          # 计划评审
/harness-review scope         # 范围评审
/harness-review --security    # 安全评审
/harness-review --ui-rubric   # UI 评分
/harness-review --team-debate # TeamAgent debate
/harness-review               # 不带参数：全量 gate
```

### 1.4 ⚠️ 行为变更：默认 read-only

| 之前 | 现在 |
|---|---|
| `APPROVE` 之后可能自动 commit | review 始终 read-only，commit / push / release 归 `harness-work` 或 `harness-release` 负责 |

如果你以前依赖 review 后的自动 commit，需要显式接 `/harness-work` 或 `/harness-release`。

---

## 2. `/harness-work` 新 flag

完整签名：

```
/harness-work [all] [task-number|range] [--codex] [--gemini] [--ollama]
              [--plan NAME] [--parallel N] [--no-commit] [--resume id]
              [--breezing] [--auto-mode] [--tdd-bypass]
```

### 2.1 `--tdd-bypass`：跳过 TDD 红测要求

```bash
/harness-work 2.3 --tdd-bypass
```

- v4.10.0 起 TDD 强制为 opt-in（默认 `enabled=false`），但启用后 worker 需要附带 red test 证据
- `--tdd-bypass` 用于 docs-only 修改或者无测试框架的项目
- 不要在产品功能变更上用 `--tdd-bypass`

### 2.2 `--plan NAME`：使用 named plan

```bash
/harness-work all --plan roadmap
```

需要先在 `plans/manifest.json` 注册 named plan：

```bash
scripts/plan-registry.sh list
scripts/plan-registry.sh switch roadmap
```

- 单次执行只用一个 named plan
- long-running / CI / issue bridge 不要依赖 active pointer，要显式 `--plan <name>`
- manifest path 必须 project root 相对（绝对路径、`..`、repo 外 symlink 都会拒绝）

### 2.3 `--ollama`（fork-only，已存在）

```bash
/harness-work 2.3 --ollama
```

走 `scripts/ollama-companion.sh task --write` 把任务委派给本地 Ollama。详见 [Phase 71 / Ollama 集成](../Plans.md)。

---

## 3. 非工程师视图：3 surface HTML (Phase 65)

发包方、PM、老板看 Plans.md 太累。提供三个**单文件 HTML**，浏览器直接打开就能判断。

### 3.1 Plan Brief — 着工前的"你这么理解对吗？"

```bash
/harness-plan-brief
```

生成内容：
- 用户请求的 Claude 侧理解
- 选项列表（多种实现路径时）
- 风险点
- 验收标准（`acceptance_criteria`）
- 自信度 0–100（含根据）

输出：单个 HTML 到 `.claude/state/views/`，自动用 `open` / `xdg-open` 打开。

### 3.2 Progress Tracker — 工事中的"还要多久？"

```bash
/harness-progress [--out <path>] [--no-open]
```

包含：
- `cc:WIP` / `cc:TODO` / `cc:完了` 计数 + 百分比
- 已用 / 预估分钟数
- 已花 / 预估 token cost
- Drift 告警（实际 vs 计划偏差）

### 3.3 Acceptance Demo — 交付时的"收不收？"

```bash
/harness-accept
```

读回 Plan Brief 阶段写入的 `acceptance_criteria`，按 verified / unverified 列出，给出 `ship` / `wait` / `reject` 推荐：

| verified 比例 | 推荐 |
|---|---|
| ≥ 0.8 | ship |
| ≥ 0.5 | wait |
| 否则 | reject |

### 3.4 三者关联

```
/harness-plan-brief      → 写入 personal-preference.v1（含 user_request_hash）
       ↓
/harness-work            → 实施
       ↓
/harness-progress        → 任意时点查看
       ↓
/harness-accept          → 用 user_request_hash join 回 plan brief 的标准
```

详细：[docs/cognitive-load-surfaces.md](cognitive-load-surfaces.md)

---

## 4. Cross-project 安全（memory 横断检索）

### 4.1 默认行为

`harness-mem` 搜索**默认仅当前 project**（D42 cross-project safety）。安全是默认，开放是 opt-in。

### 4.2 启用横断检索

第 1 步：定义 group。`.claude/rules/cross-project-groups.yaml`：

```yaml
schema_version: cross-project-group.v1
groups:
  - name: PersonalTools
    members:
      - my-cli
      - my-dotfiles
      - my-scripts
```

第 2 步：在 skill 调用时显式指定 group：

```bash
/harness-plan-brief --cross-project-group "PersonalTools"
```

### 4.3 3 层 redaction

横断检索时，其他 project 的固有名词（客户名、人名、公司名等）会**三层防御**：

1. mem 端：`<private>` strip + project filter
2. Harness 端：客户字典 + NER 自动黑塗
3. HTML 渲染前：最终 scan + 审计 log（落到 `.claude/state/redaction-audit.jsonl`）

详细：[docs/cross-project-safety.md](cross-project-safety.md) / [cross-project-groups-schema.md](cross-project-groups-schema.md)

---

## 5. Claude Code 2.1.133–2.1.142 集成（Phase 69）

CC 上游加的新 knob，Harness 已在 **template** 里放了 baseline；plugin 本体 `.claude-plugin/settings.json` 的 reflect 是 release operator 手动 merge（因为 self-write deny）。

### 5.1 `worktree.baseRef: "fresh"`（CC 2.1.133）

控制 `--worktree` / `EnterWorktree` / agent-isolation worktree 的起点。

```json
{
  "worktree": {
    "baseRef": "fresh"
  }
}
```

- `fresh`（**Harness baseline**）：从 `origin/<default>` 拉新枝，未 push 的 commits 不会无意中带过去
- `head`：从本地 HEAD 拉枝，会带本地 unpushed commits
- 想 opt-in `head` 的 project：写到 `.claude/settings.local.json`

### 5.2 `autoMode.hard_deny`（CC 2.1.136）

Auto Mode classifier 即使"看起来意图允许"也不会放行的硬 deny。Harness baseline 7 条：

```json
{
  "autoMode": {
    "hard_deny": [
      "Bash(sudo:*)",
      "Bash(rm -rf:*)",
      "Bash(rm -fr:*)",
      "Bash(git push -f:*)",
      "Bash(git push --force:*)",
      "Bash(git reset --hard:*)",
      "mcp__codex__*"
    ]
  }
}
```

未启用 Auto Mode 的 project 不受影响（不读这一节）。

### 5.3 Hook `terminalSequence`（CC 2.1.141）

无 controlling terminal 的 background session（`--bg` / `claude agents`）也能发桌面通知。

```bash
# 启用 + 选模式
export HARNESS_TERMINAL_NOTIFY=osc9   # macOS / iTerm 通知 popup
export HARNESS_TERMINAL_NOTIFY=bell   # 终端 BEL
export HARNESS_TERMINAL_NOTIFY=title  # 窗口标题更新
unset HARNESS_TERMINAL_NOTIFY         # 默认关闭
```

已自动接入：`notification-handler.sh`（4 种 notification）、`task_completed.go`（停止 / 全完 / 进度 / 普通承认 所有路径）。

### 5.4 Hook exec form `args: string[]`（CC 2.1.139）

只含 path placeholder（`${CLAUDE_PROJECT_DIR}/...`）的 hook 优先用 exec form（不走 shell，无 injection 风险）。需要 shell 控制（`&&` / pipe / heredoc）才保留 `command` 形式。

### 5.5 Hook `continueOnBlock`（CC 2.1.139）

PostToolUse hook deny 后让 Claude 继续 turn。

- 诊断类反馈（lint 提示等）：`continueOnBlock: true`
- 守护类拦截（R01-R13 / 密钥 / `.eslintrc*` 等保护配置）：**必须 `false`**

### 5.6 SessionStart / Setup / SubagentStart：只能 command 型（CC 2.1.142）

```json
{
  "hooks": {
    "SessionStart": [
      { "type": "command", "command": "..." }   // ✅
    ]
  }
}
```

不能用 `type: "prompt"` / `"agent"`（CC 2.1.142 后会 error）。需要 LLM 判断的逻辑放到 `PreToolUse`。

### 5.7 `$CLAUDE_EFFORT` 观测（CC 2.1.133）

hook stdin 里有 `effort.level`、env 里有 `$CLAUDE_EFFORT`：

- ✅ 用于 log / 观测
- ❌ 用 effort 把 deny 降级到 ask
- ❌ 用 effort 跳过 guardrail R01-R13

详细：[.claude/rules/hooks-2.1.139-plus.md](../.claude/rules/hooks-2.1.139-plus.md)

---

## 6. Fork 特有 (Phase 70 / 71，已重编号)

### Phase 70：Codex auth

```bash
bash scripts/codex-companion.sh auth         # 交互输入 OpenAI API Key
bash scripts/codex-companion.sh auth status  # 查看末 4 位 + 设定日
bash scripts/codex-companion.sh auth logout  # 删除
```

写入到 `~/.codex/config.toml`（权限 600）。

### Phase 71：Ollama 本地模型

```bash
# 直接 task
bash scripts/ollama-companion.sh task "解释这个 bug"
bash scripts/ollama-companion.sh task --model qwen2.5-coder:7b "..."

# 状态检测
bash scripts/ollama-companion.sh status
bash scripts/ollama-companion.sh models

# 复杂度评分（决定走 ollama 还是 codex/claude）
bash scripts/ollama-companion.sh score-task "add description-zh field"
# 返回 JSON：{ score, recommended_engine }

# 通过 /harness-work flag
/harness-work 2.3 --ollama
```

阈值在 `.claude-code-harness.config.yaml` 的 `routing.ollama_score_threshold` 调（默认 3）。

> ⚠️ Plans.md 中这两个 Phase 已从原本的 63/64 重编为 70/71（与 upstream Phase 63 stale-client cleanup / Phase 64 archive 改造撞号）。commit hash 保持不变。

---

## 7. 升级时的注意事项

### 7.1 Python `pyyaml` 依赖

`tests/validate-plugin.sh` 里多个 cross-project / redaction 测试需要 `pyyaml`。macOS 上 PEP 668 限制：

```bash
python3 -m pip install --user --break-system-packages pyyaml
```

### 7.2 mirror 重生成

如果你手改过 `codex/.codex/skills/` 或 `opencode/skills/` 下的 mirror，被同步流程会覆盖。SSOT 是 `skills/`：

```bash
bash scripts/sync-skill-mirrors.sh           # 从 SSOT 重生成 mirror
bash scripts/sync-skill-mirrors.sh --check   # 仅校验，不写
```

### 7.3 `.claude-plugin/settings.json` 的 self-write deny

`worktree.baseRef` 和 `autoMode.hard_deny` 的 baseline 只放进了 `templates/claude/settings.security.json.template`。Plugin 本体的 `.claude-plugin/settings.json` 因为有 self-write deny rule，agent 不能改，release operator 手动 merge。

### 7.4 验证

```bash
./tests/validate-plugin.sh           # 应该 95/95 PASS（含 cross-project 等）
bash scripts/ci/check-consistency.sh # 应该全合格
bash scripts/check-residue.sh        # 应该 0 件（migration residue）
```

### 7.5 Phase 编号变化（仅 darkhucx fork 用户需知）

| 旧编号（fork） | 新编号 | 主题 | 触发原因 |
|---|---|---|---|
| Phase 63 | Phase 70 | Codex auth | upstream 也用 Phase 63（harness-mem-client cleanup） |
| Phase 64 | Phase 71 | Ollama 集成 | upstream 也用 Phase 64（Plans.md archive 改造） |

`cc:完了` 标记中的 commit hash 保持原样不变。fork archive 文件 `.claude/memory/archive/Plans-2026-05-07-phase47-62.md` 是 local-only，未 track。

---

## 8. 升级路径速查

### 8.1 准备本地副本

```bash
git clone git@github.com:darkhucx/claude-code-harness.git
cd claude-code-harness
python3 -m pip install --user --break-system-packages pyyaml
./tests/validate-plugin.sh   # 期望 95/95 PASS
```

### 8.2 注册插件到 Claude Code（从 fork marketplace）

> ⚠️ **前置：确保 darkhucx fork 在 GitHub 上的默认分支是 `main`**
> Claude Code 克隆 marketplace 时只拿默认分支。如果默认分支还是旧的（例如 `feat/gemini-engine`），插件会安装旧版本：
> ```bash
> gh repo edit darkhucx/claude-code-harness --default-branch main
> # 或 gh repo view darkhucx/claude-code-harness --json defaultBranchRef 先确认
> ```

如果之前装过 upstream `Chachamaru127` 版本，先换 marketplace 源：

```bash
# 1. 移除旧 marketplace（避免命名冲突——upstream 与 fork 的 marketplace 内部名相同）
claude plugin marketplace remove claude-code-harness-marketplace

# 2. 添加 fork 作为 marketplace
claude plugin marketplace add darkhucx/claude-code-harness

# 3. 装到 user scope（全局可用）
claude plugin install claude-code-harness@claude-code-harness-marketplace --scope user

# 4. 验证版本
claude plugin list | grep -A3 'claude-code-harness@'
# 期望：Version: 4.10.0, Scope: user, Status: enabled
```

如果版本不是 v4.10.0，运行 `claude plugin marketplace update claude-code-harness-marketplace` 强制刷新 cache（cache 路径 `~/.claude/plugins/marketplaces/...`），然后 `claude plugin update claude-code-harness@claude-code-harness-marketplace`。

**重启 Claude Code** 才会加载新版本。

### 8.3 切换语言（fork opt-in）

```bash
./scripts/i18n/set-locale.sh zh   # 描述字段切中文
./scripts/i18n/set-locale.sh ja   # 切日文
./scripts/i18n/set-locale.sh en   # 切英文（恢复 upstream 默认）
```

> 注意：运行 `set-locale.sh zh` / `ja` 后 `bash scripts/ci/check-consistency.sh` 的 i18n gate 会失败（"description must equal description-en"）。这是 fork 故意的分歧，**仅 `set-locale.sh en` 状态下才能让 consistency check 全合格**。

---

## 9. 参考文档

- 上游 snapshot：[upstream-update-snapshot-2026-05-15.md](upstream-update-snapshot-2026-05-15.md)
- `harness-review` 运营模型：[harness-review-operating-model.md](harness-review-operating-model.md)
- 3 surface 详细：[cognitive-load-surfaces.md](cognitive-load-surfaces.md)
- Cross-project 安全：[cross-project-safety.md](cross-project-safety.md)
- Hook 2.1.139+ 规则：[../.claude/rules/hooks-2.1.139-plus.md](../.claude/rules/hooks-2.1.139-plus.md)
- Agent View 9 flag policy：[agent-view-policy.md](agent-view-policy.md)
- Plans 历史：[../Plans.md](../Plans.md) + `.claude/memory/archive/`
