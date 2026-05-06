# darkhucx/claude-code-harness — Gemini 引擎 + 多语言使用说明

| 字段 | 值 |
|---|---|
| 文档版本 | v2.0 |
| 更新日期 | 2026-05-07 |
| 适用插件版本 | darkhucx/claude-code-harness `feat/zh-i18n-on-v4.7`（v4.7.0） |
| 基于原版 | Chachamaru127/claude-code-harness v4.7.0 |

---

## 1. 这个 fork 加了什么

darkhucx/claude-code-harness 在原版基础上新增了两大功能：

### 1.1 Gemini CLI 作为第一等委托引擎

与 Codex CLI 完全对等，所有 harness 工作流均可通过 `--gemini` 委托给 Gemini 执行：

| 能力 | 原版 v4.7.0 | 此 fork v4.7.0 |
|---|---|---|
| `--codex` 委托执行 | ✅ | ✅ |
| `--gemini` 委托执行 | ❌ | ✅ |
| Gemini adversarial review | ❌ | ✅ |
| effort → thinking 自动映射 | ❌ | ✅ |
| `--codex` + `--gemini` 同时使用 | — | ❌（互斥） |

新增文件：
- `scripts/gemini-companion.sh` — Gemini 委托代理（核心）
- `scripts/gemini-review-extract.sh` — review 结果 JSON 提取/规范化

### 1.2 中文（zh）国际化支持（v4.7.0 新增）

所有 92 个技能（SKILL.md）新增 `description-zh` 字段，支持三语言切换：

| 语言 | 命令 | 说明 |
|---|---|---|
| 英文（默认） | `./scripts/i18n/set-locale.sh en` | 恢复到英文 description |
| 日文 | `./scripts/i18n/set-locale.sh ja` | 切换到日文 description-ja |
| 中文 | `./scripts/i18n/set-locale.sh zh` | 切换到中文 description-zh |

---

## 2. 前置依赖

### 2.1 Claude Code CLI

```bash
# 验证版本（推荐 v2.1.111+）
claude --version
```

### 2.2 Gemini CLI

```bash
# 安装或升级（需要 >= 0.38.1，ACP broker 兼容性要求）
npm install -g @google/gemini-cli@latest

# 验证版本
gemini --version   # 应 >= 0.38.1
```

> **注意**：如果 npm 全局路径（`~/.npm-global/bin`）不在系统 PATH 前面，
> `npm install -g` 安装的新版本会被 `/usr/local/bin/gemini`（旧版）覆盖。
> 修复方法（**必须在独立终端执行，不能通过 Claude Code bash 工具**）：
>
> ```bash
> sudo ln -sf ~/.npm-global/bin/gemini /usr/local/bin/gemini
> gemini --version   # 确认版本已更新
> ```

### 2.3 Gemini OAuth 登录

```bash
gemini auth          # 浏览器弹出，用 Google 账号登录
gemini auth status   # 确认 authenticated: true
```

### 2.4 gemini-plugin-cc（companion 核心）

`gemini-companion.sh` 会在 `~/.claude/plugins` 和 `~/.codex/plugins` 目录下
动态查找 `gemini-companion.mjs`。该文件由 `sakibsadmanshajib/gemini-plugin-cc` 插件提供。

**在 Claude Code 提示符里安装：**

```
/plugin marketplace add sakibsadmanshajib/gemini-plugin-cc
/plugin install gemini@google-gemini
```

验证安装：

```bash
find ~/.claude/plugins -name "gemini-companion.mjs" 2>/dev/null
# 应输出类似：
# /Users/xxx/.claude/plugins/cache/google-gemini/gemini/1.0.1/scripts/gemini-companion.mjs
```

---

## 3. 安装流程

### 3.1 新项目完整安装（推荐路径）

**Step 1：安装原版 harness 插件**

```bash
# 在 Claude Code 提示符里
/plugin marketplace add Chachamaru127/claude-code-harness
/plugin install claude-code-harness
```

**Step 2：手动安装 fork 新增脚本**

此 fork 暂未发布到官方 marketplace，需手动覆盖两个脚本：

```bash
# 下载 Gemini companion 脚本
curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/gemini-companion.sh" \
  -o scripts/gemini-companion.sh

curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/gemini-review-extract.sh" \
  -o scripts/gemini-review-extract.sh

chmod +x scripts/gemini-companion.sh scripts/gemini-review-extract.sh
```

**Step 3：安装 gemini-plugin-cc**

```
/plugin marketplace add sakibsadmanshajib/gemini-plugin-cc
/plugin install gemini@google-gemini
```

**Step 4：验证**

```bash
bash scripts/gemini-companion.sh setup
# 期望输出：
# - Gemini CLI: installed (0.x.x)
# - Authentication: authenticated
# - Auth method: oauth-personal
```

---

### 3.2 已有项目升级到 v4.7.0

如果已使用旧版（v4.4.0 等），执行以下步骤同步新功能：

```bash
# 1. 拉取最新 fork 脚本（覆盖现有）
curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/gemini-companion.sh" \
  -o scripts/gemini-companion.sh

curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/gemini-review-extract.sh" \
  -o scripts/gemini-review-extract.sh

# 2. 拉取 i18n 脚本（v4.7.0 新增）
mkdir -p scripts/i18n
curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/i18n/set-locale.sh" \
  -o scripts/i18n/set-locale.sh

curl -fsSL \
  "https://raw.githubusercontent.com/darkhucx/claude-code-harness/feat/zh-i18n-on-v4.7/scripts/i18n/check-translations.sh" \
  -o scripts/i18n/check-translations.sh

chmod +x scripts/i18n/set-locale.sh scripts/i18n/check-translations.sh
chmod +x scripts/gemini-companion.sh scripts/gemini-review-extract.sh
```

---

## 4. 语言切换（v4.7.0 新功能）

### 4.1 三语言切换命令

```bash
# 切换到中文（darkhucx fork 专属）
./scripts/i18n/set-locale.sh zh

# 切换到日文
./scripts/i18n/set-locale.sh ja

# 恢复英文（默认）
./scripts/i18n/set-locale.sh en
```

切换后，Claude Code 的技能自动加载面板（`/` 斜杠菜单）将以对应语言显示技能说明。

### 4.2 验证语言切换

```bash
# 检查翻译完整性
./scripts/i18n/check-translations.sh
# description-zh 缺失时显示 warn，不会 fail

# 验证某个技能的当前 description
head -5 skills/harness-work/SKILL.md
# description 字段应为当前语言的值
```

### 4.3 round-trip 恢复

语言切换是可逆的，切换到 `zh` 或 `ja` 时，原始英文值会自动备份到 `description-en`：

```bash
./scripts/i18n/set-locale.sh zh   # en → zh，原文备份到 description-en
./scripts/i18n/set-locale.sh en   # 从 description-en 恢复
```

---

## 5. Gemini 使用方式

### 5.1 基本命令

```bash
# 委托 Gemini 执行 Plans.md 全部任务（自动选模式）
/harness-work all --gemini

# 指定 auto-gemini-3 模型（thinking: high）
/harness-work all --gemini --model auto-gemini-3

# 简写：*3 = auto-gemini-3
/harness-work all --gemini *3

# 团队模式（Breezing）+ Gemini
/harness-work all --gemini --breezing

# 指定具体任务编号
/harness-work 63.1 --gemini
```

### 5.2 可用模型别名

| 别名 | 对应模型 | thinking 级别映射 |
|---|---|---|
| `pro` | Gemini 2.5 Pro | high |
| `flash` | Gemini 2.5 Flash | medium |
| `flash-lite` | Gemini Flash Lite | low |
| `auto-gemini-3` | 自动选（gemini-3 系列） | 根据任务计算 |
| `auto-gemini-2.5` | Gemini 2.5 系列 | 根据任务计算 |

### 5.3 effort → thinking 自动映射

harness 计算任务复杂度后，自动把 Codex 的 6 级 effort 转换为 Gemini 的 4 级 thinking：

| Codex effort | Gemini thinking |
|---|---|
| `none` / `minimal` | `off` |
| `low` | `low` |
| `medium` | `medium` |
| `high` / `xhigh` | `high` |

### 5.4 直接调用 companion（不经过 harness）

```bash
# 委托一个任务
bash scripts/gemini-companion.sh task --write "实现 description-zh 字段批量添加"

# 代码 review
bash scripts/gemini-companion.sh review --base HEAD~3

# 对抗性 review（质疑设计决策）
bash scripts/gemini-companion.sh adversarial-review --base HEAD~3 --background

# 查询后台任务状态
bash scripts/gemini-companion.sh status
bash scripts/gemini-companion.sh result <job-id> --json

# 取消任务
bash scripts/gemini-companion.sh cancel <job-id>
```

---

## 6. 常见问题排查

### 问题 1：`--gemini` 参数不生效 / 找不到脚本

**症状**：运行 `/harness-work --gemini` 后提示脚本不存在或回落到默认模式。

**原因**：`scripts/gemini-companion.sh` 未安装。原版 harness 不包含此文件。

**解决**：按 [3.1 Step 2](#31-新项目完整安装推荐路径) 手动下载脚本。

---

### 问题 2：`ERROR: gemini-plugin-cc が見つかりません`

**症状**：运行 `bash scripts/gemini-companion.sh` 报错找不到 companion。

**原因**：`sakibsadmanshajib/gemini-plugin-cc` 插件未安装。

**解决**：

```bash
# 先检查是否已安装
find ~/.claude/plugins -name "gemini-companion.mjs" 2>/dev/null

# 无输出则安装：
# /plugin marketplace add sakibsadmanshajib/gemini-plugin-cc
# /plugin install gemini@google-gemini
```

---

### 问题 3：Gemini CLI 版本过旧（< 0.38.1）

**症状**：`setup` 或 `task` 调用失败，ACP broker 兼容性错误。

**诊断**：`gemini --version` 显示 < 0.38.1。

**解决**：

```bash
npm install -g @google/gemini-cli@latest

# 如果系统路径仍指向旧版（必须在独立终端，非 Claude Code 执行）：
sudo ln -sf ~/.npm-global/bin/gemini /usr/local/bin/gemini
```

---

### 问题 4：`set-locale.sh zh` 报错"找不到文件"

**症状**：`(eval):1: no such file or directory: ./scripts/i18n/set-locale.sh`

**原因**：i18n 脚本只在 v4.7.0 之后存在，或从子目录执行。

**解决**：

```bash
# 确认在项目根目录执行
cd /path/to/your-project

# 如果脚本不存在，按 3.2 升级步骤下载
ls scripts/i18n/set-locale.sh

# 执行时用项目根目录的相对路径
./scripts/i18n/set-locale.sh zh
```

---

### 问题 5：`/plugin install darkhucx/claude-code-harness` 失败

**症状**：`Marketplace "darkhucx/claude-code-harness" not found`。

**原因**：darkhucx fork 的 marketplace 名称与原版冲突，plugin 系统无法区分。

**解决**：放弃通过 marketplace 安装整个 fork，改用 [3.1 Step 2](#31-新项目完整安装推荐路径) 只安装脚本文件。

---

### 问题 6：`--codex` 和 `--gemini` 同时使用

**症状**：报错或行为异常。

**原因**：两个引擎互斥，不能同时指定。

**解决**：只选一个。如需两者对比，分两次运行。

---

## 7. 当前项目状态核验

运行以下命令确认所有组件就绪：

```bash
# Gemini companion
bash scripts/gemini-companion.sh setup
# 期望：CLI installed, authenticated, auth method: oauth-personal

# i18n 翻译完整性
./scripts/i18n/check-translations.sh
# 期望：✓ All 92 files have translations

# 验证中文切换（可选）
./scripts/i18n/set-locale.sh zh && echo "✓ zh switch OK"
./scripts/i18n/set-locale.sh en && echo "✓ en restore OK"
```

| 组件 | 核验命令 | 期望结果 |
|---|---|---|
| `gemini-companion.sh` | `bash scripts/gemini-companion.sh setup` | CLI installed + authenticated |
| `set-locale.sh` | `./scripts/i18n/set-locale.sh zh` | Updated: 92, Errors: 0 |
| `check-translations.sh` | `./scripts/i18n/check-translations.sh` | All 92 files have translations |
| Gemini OAuth | `gemini auth status` | authenticated: true |
| Gemini CLI 版本 | `gemini --version` | >= 0.38.1 |
