# Gemini 引擎集成指南

> 版本：4.7.0 | 分支：feat/zh-i18n-on-v4.7 | 更新日期：2026-05-07

---

## 概述

`--gemini` 标志是与 `--codex` 完全对等的第二 LLM 引擎。  
底层插件为 `sakibsadmanshajib/gemini-plugin-cc`（`openai/codex-plugin-cc` 的 Gemini 移植版），  
共享 `review-output.schema.json`，因此 `write-review-result.sh` 的 verdict 归一化逻辑可直接复用。

v4.7.0 新增内容：
- **中文（zh）i18n 支持**：92 个技能的 `description-zh` 字段，支持三语言切换
- **harness-mem 托管 companion**：`harness mem status|setup|update|doctor|off|purge`
- **Sandbagging 感知弱监督**：`weak-supervision-report.v1`、`elicitation-event.v1`

---

## 1. 新用户完整安装流程

### Step 1：安装原版 harness 插件

在 Claude Code 提示符里执行：

```
/plugin marketplace add Chachamaru127/claude-code-harness
/plugin install claude-code-harness
```

### Step 2：手动覆盖 fork 专属脚本

此 fork 暂未发布到官方 marketplace，需手动下载以下脚本：

```bash
# Gemini companion 核心脚本
curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/gemini-companion.sh" \
  -o scripts/gemini-companion.sh

curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/gemini-review-extract.sh" \
  -o scripts/gemini-review-extract.sh

# i18n 语言切换脚本（v4.7.0 新增）
mkdir -p scripts/i18n
curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/i18n/set-locale.sh" \
  -o scripts/i18n/set-locale.sh

curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/i18n/check-translations.sh" \
  -o scripts/i18n/check-translations.sh

chmod +x scripts/gemini-companion.sh scripts/gemini-review-extract.sh \
         scripts/i18n/set-locale.sh scripts/i18n/check-translations.sh
```

### Step 3：安装 Gemini CLI（>= 0.38.1）

```bash
npm install -g @google/gemini-cli@latest
gemini --version   # 确认 >= 0.38.1
```

> 如果 `/usr/local/bin/gemini` 仍指向旧版，**在独立终端（非 Claude Code）** 执行：
> ```bash
> sudo ln -sf ~/.npm-global/bin/gemini /usr/local/bin/gemini
> ```

### Step 4：安装 gemini-plugin-cc

```
/plugin marketplace add sakibsadmanshajib/gemini-plugin-cc
/plugin install gemini@google-gemini
```

### Step 5：Gemini 认证

```bash
gemini auth          # 浏览器弹出，Google 账号登录（推荐）
# 或者通过环境变量传入 API Key（在 shell 配置文件中设置，勿写入代码）
# 参考：https://ai.google.dev/gemini-api/docs/api-key
```

### Step 6：验证

```bash
bash scripts/gemini-companion.sh setup --json
# 期望：{ "geminiAvailable": true, "authenticated": true, "authMethod": "oauth-personal" }
```

**安装后文件位置**：

```
~/.claude/plugins/gemini-plugin-cc/<version>/gemini-companion.mjs
或
~/.codex/plugins/.../gemini-companion.mjs
```

`gemini-companion.sh` 启动时会遍历两个目录，按语义版本降序自动选最新版，路径不需要硬编码。

---

## 2. 语言切换（v4.7.0 新功能）

### 2.1 三语言切换命令

```bash
./scripts/i18n/set-locale.sh zh   # 切换到中文（darkhucx fork 专属）
./scripts/i18n/set-locale.sh ja   # 切换到日文
./scripts/i18n/set-locale.sh en   # 恢复英文（默认）
```

切换后，`/` 斜杠菜单中的技能说明会以对应语言显示。

### 2.2 验证与翻译完整性检查

```bash
./scripts/i18n/check-translations.sh
# description-zh 缺失时显示 warn，不会导致 fail

# 查看切换结果
head -6 skills/harness-work/SKILL.md   # description 字段应为当前语言
```

### 2.3 Round-trip 机制

切换到非英文时，原始英文值自动备份到 `description-en`，可随时恢复：

```bash
./scripts/i18n/set-locale.sh zh   # 原文备份到 description-en
./scripts/i18n/set-locale.sh en   # 从 description-en 恢复
```

---

## 3. 核心文件说明

### `scripts/gemini-companion.sh` — 核心代理脚本

所有 Gemini 调用均通过此脚本，禁止直接使用 `gemini` 命令或 MCP 工具。

| 功能 | 说明 |
|------|------|
| **插件自动发现** | 遍历 `~/.claude/plugins` 和 `~/.codex/plugins`，按版本降序选最新 |
| **Thinking 传播** | 通过 `calculate-effort.sh` 计算任务复杂度，自动映射到 `--thinking` 标志 |
| **STDIN 安全处理** | stdin 通过 tmpfile 传递（bash 变量会丢失 null byte） |
| **argparse 修正** | 支持 `--flag=value` 格式，防止短标志被误当作任务描述解析 |

**Effort → Thinking 映射**：

| Codex effort | Gemini thinking |
|---|---|
| `none` / `minimal` | `off` |
| `low` | `low` |
| `medium` | `medium` |
| `high` / `xhigh` | `high` |

**可用子命令**：

```bash
# 任务委托（可写）
bash scripts/gemini-companion.sh task --write "任务内容"

# stdin 传入（大提示词）
cat prompt.md | bash scripts/gemini-companion.sh task --write

# 恢复上次线程
bash scripts/gemini-companion.sh task --resume-last --write "继续上次"

# 指定模型（默认 auto-gemini-3）
bash scripts/gemini-companion.sh task --write --model pro "任务内容"

# 设置确认
bash scripts/gemini-companion.sh setup --json

# 任务管理
bash scripts/gemini-companion.sh status
bash scripts/gemini-companion.sh result <job-id> --json
bash scripts/gemini-companion.sh cancel <job-id>

# 对抗性 review（background 必须）
bash scripts/gemini-companion.sh adversarial-review --base HEAD~1 --background
```

### `scripts/gemini-review-extract.sh` — review 结果提取脚本

Gemini plugin 在 `--background` 模式下将 schema JSON 包装在 ` ```json ... ``` ` fence 里存入 `rawOutput`。  
此脚本去除 fence，将结果规范化为 `write-review-result.sh` 可读的格式。

**处理流程**：

```
gemini-companion.sh result <job-id> --json
  ↓
gemini-review-extract.sh（去除 fence + 补全缺失字段）
  ↓
write-review-result.sh（写入 verdict）
```

**字段补全规则**：
- `severity` 缺失 → 填 `"medium"`（保守侧，归入 followups）
- `title` 缺失 → 用 `finding` / `body` 内容替代

### `scripts/i18n/set-locale.sh` — 语言切换脚本（v4.7.0 新增）

覆盖范围：`skills/`、`opencode/skills/`、`codex/.codex/skills/`、`skills-codex/` 下所有 SKILL.md。

---

## 4. 技能层使用

### `/harness-work --gemini`（任务委托）

```bash
/harness-work --gemini                  # 委托给 Gemini CLI
/harness-work --gemini --breezing       # Gemini + 团队执行
/harness-work --gemini --model flash    # 指定 Flash 模型
```

- 仅在明确指定时生效（不参与自动模式选择）
- 与 `--codex` 互斥
- 可与 `--breezing` 组合

### `/harness-review --gemini`（并行代码 review）

```bash
/harness-review --gemini       # Gemini 并行 review
/harness-review code --gemini  # 代码 review 使用 Gemini
```

**5 步 pipeline**（`--background` 必须，foreground 有 ACP 初始化 bug）：

```bash
# Step 1：后台启动 adversarial-review
JOB_OUT=$(bash scripts/gemini-companion.sh adversarial-review \
  --base "${BASE_REF:-HEAD~1}" --background)
JOB_ID=$(echo "$JOB_OUT" | grep -oE 'gemini-[0-9]+-[a-z0-9]+' | head -1)

# Step 2：轮询直到完成（平均 2～4 分钟）
until bash scripts/gemini-companion.sh status "$JOB_ID" 2>&1 \
  | grep -qE "Status:\*\* (completed|failed|cancelled)"; do
  sleep 10
done

# Step 3：获取结果
bash scripts/gemini-companion.sh result "$JOB_ID" --json > /tmp/gemini-raw.json

# Step 4：去除 rawOutput 中的 JSON fence
bash scripts/gemini-review-extract.sh /tmp/gemini-raw.json > /tmp/gemini-clean.json

# Step 5：写入 verdict（与 Codex 同一归一化路径）
bash scripts/write-review-result.sh /tmp/gemini-clean.json "${COMMIT_HASH}"
```

最终 review 结果携带 `dual_review.engine = "gemini"` 字段。

---

## 5. Codex vs Gemini 对比

| 项目 | Codex (`--codex`) | Gemini (`--gemini`) |
|---|---|---|
| 认证 | OpenAI API Key | `gemini auth` OAuth 或 `GEMINI_API_KEY` |
| Effort 参数 | `--effort`（6 级） | `--thinking`（4 级，自动映射） |
| 默认模型 | codex-1 | auto-gemini-3 |
| Review 子命令 | `review`（前台可用） | `adversarial-review --background` 必须 |
| 结果提取 | 直接解析 | `gemini-review-extract.sh` 去除 fence |
| ACP 稳定性 | 前台/后台均支持 | 仅后台稳定 |
| 互斥 | 与 `--gemini` 互斥 | 与 `--codex` 互斥 |
| breezing 组合 | 支持 | 支持 |
| 语言切换 | 不涉及 | 不涉及（i18n 独立于引擎） |

---

## 6. 可用模型别名

| 别名 | 对应模型 | thinking 级别 |
|---|---|---|
| `pro` | Gemini 2.5 Pro | high |
| `flash` | Gemini 2.5 Flash | medium |
| `flash-lite` | Gemini Flash Lite | low |
| `auto-gemini-3` | 自动选（gemini-3 系列） | 根据任务计算 |
| `auto-gemini-2.5` | Gemini 2.5 系列 | 根据任务计算 |

---

## 7. 权限配置

`.claude-plugin/settings.json` 的 `deny` 列表已添加 `mcp__gemini__*`：

```json
{
  "permissions": {
    "deny": [
      "mcp__codex__*",
      "mcp__gemini__*"
    ]
  }
}
```

**目的**：防止 Agent 绕过 `gemini-companion.sh` 直接调用 Gemini MCP。  
所有调用必须经过版本发现、thinking 映射、STDIN 安全处理的代理层。

> **注意**：此 deny 条目受自我写保护约束，Agent 无法自行添加，需手动编辑配置文件。

---

## 8. 最小冒烟测试

```bash
# 1. 设置确认
bash scripts/gemini-companion.sh setup --json
# → "geminiAvailable": true, "authenticated": true

# 2. 任务委托测试
bash scripts/gemini-companion.sh task --write "计算 2+2 并返回结果"
# → 返回 "4" 即为正常（实测约 4.7 秒）

# 3. 语言切换测试（v4.7.0）
./scripts/i18n/set-locale.sh zh && echo "✓ zh OK"
./scripts/i18n/set-locale.sh en && echo "✓ en restore OK"

# 4. 翻译完整性
./scripts/i18n/check-translations.sh
# → ✓ All 92 files have translations

# 5. review pipeline 测试
bash scripts/gemini-companion.sh adversarial-review --base HEAD~1 --background
# → 获取 JOB_ID → 轮询 → extract → write-review-result
# → verdict: REQUEST_CHANGES 或 APPROVE，schema_version: review-result.v1
```

---

## 9. Fallback 行为

| 状态 | 行为 |
|---|---|
| `geminiAvailable=false` | 回退到 Claude 单独 review，输出警告 |
| `authenticated=false` | 同上 |
| `status=failed` | 同上 |
| `gemini-companion.sh` 不存在 | 报错退出，输出安装步骤 |
| Ollama 未启动（Phase 64，待实现） | `⚠️ Ollama is not running. Start with: ollama serve` |

---

## 10. 相关文件索引

| 文件 | 作用 |
|---|---|
| `scripts/gemini-companion.sh` | Gemini CLI 代理（核心） |
| `scripts/gemini-review-extract.sh` | 从 rawOutput 提取 schema JSON |
| `scripts/i18n/set-locale.sh` | 三语言切换（zh/ja/en） |
| `scripts/i18n/check-translations.sh` | 翻译完整性检查 |
| `scripts/codex-companion.sh` | Codex CLI 代理（参考实现） |
| `scripts/write-review-result.sh` | verdict 写入（Gemini/Codex 共用） |
| `skills/harness-work/SKILL.md` | `--gemini` 标志的技能定义 |
| `skills/harness-review/SKILL.md` | Step 3.5b：Gemini 并行 review 步骤 |
| `.claude-plugin/settings.json` | `mcp__gemini__*` deny 配置 |
| `docs/harness-gemini-setup.md` | 新用户安装向导（中文，含语言切换） |
