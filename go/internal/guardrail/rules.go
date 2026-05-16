// Package guard implements the Harness v4 declarative guardrail rules engine.
//
// Each rule is a (toolPattern, evaluate) pair evaluated in order;
// the first match wins (short-circuit).
package guardrail

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/Chachamaru127/claude-code-harness/go/pkg/hookproto"
)

// GuardRule is a single declarative guard rule.
type GuardRule struct {
	ID          string
	ToolPattern *regexp.Regexp
	Evaluate    func(ctx hookproto.RuleContext) *hookproto.HookResult
}

// Pre-compiled patterns for R08 (breezing reviewer prohibited commands)
var r08ReviewerProhibitedPatterns = []*regexp.Regexp{
	regexp.MustCompile(`\bgit\s+(?:commit|push|reset|checkout|merge|rebase)\b`),
	regexp.MustCompile(`\brm\s+`),
	regexp.MustCompile(`\bmv\s+`),
	regexp.MustCompile(`\bcp\s+.*-r\b`),
}

// Pre-compiled patterns for R09 (secret file detection)
var r09SecretPatterns = []*regexp.Regexp{
	regexp.MustCompile(`\.env$`),
	regexp.MustCompile(`id_rsa$`),
	regexp.MustCompile(`\.pem$`),
	regexp.MustCompile(`\.key$`),
	regexp.MustCompile(`secrets?/`),
}

var (
	r14SourcePathPattern = regexp.MustCompile(`(?:^|/)(?:app|cmd|go|internal|lib|pkg|src)/(?:.+)\.(?:cs|go|java|js|jsx|kt|php|py|rb|rs|swift|ts|tsx)$`)
	r14TestPathPattern   = regexp.MustCompile(`(?:^|/)(?:__tests__|test|tests)(?:/|$)|(?:_test\.go|_test\.py|\.spec\.[jt]sx?|\.test\.[jt]sx?)$`)
)

func protectedPathHookResult(match protectedPathMatch, filePath, operation string) *hookproto.HookResult {
	switch match.Level {
	case protectedPathDeny:
		return &hookproto.HookResult{
			Decision: hookproto.DecisionDeny,
			Reason:   fmt.Sprintf("%s は禁止されています: %s（%s）", operation, filePath, match.Reason),
		}
	case protectedPathAsk:
		return &hookproto.HookResult{
			Decision: hookproto.DecisionAsk,
			Reason:   fmt.Sprintf("%s は確認が必要です: %s（%s）", operation, filePath, match.Reason),
		}
	case protectedPathWarn:
		return &hookproto.HookResult{
			Decision:      hookproto.DecisionApprove,
			SystemMessage: fmt.Sprintf("警告: %s を検出しました: %s（%s）", operation, filePath, match.Reason),
		}
	default:
		return nil
	}
}

func isTddSourceWriteCandidate(filePath, projectRoot string) bool {
	if !isUnderProjectRoot(filePath, projectRoot) {
		return false
	}
	normalized := normalizePathForGuardrail(filePath)
	if r14TestPathPattern.MatchString(normalized) {
		return false
	}
	return r14SourcePathPattern.MatchString(normalized)
}

func tddBypassHookResult(ctx hookproto.RuleContext, filePath string) *hookproto.HookResult {
	reason := strings.TrimSpace(ctx.TddBypassReason)
	message := fmt.Sprintf("TDD enforcement bypass active for %s (HARNESS_TDD_BYPASS=1).", filePath)
	if reason != "" {
		message += fmt.Sprintf(" reason=%q", reason)
	} else if ctx.TddBypassReasonRequired {
		message += " HARNESS_TDD_BYPASS_REASON is required for audit but was empty."
	} else {
		message += " HARNESS_TDD_BYPASS_REASON was empty."
	}
	return &hookproto.HookResult{
		Decision:      hookproto.DecisionApprove,
		SystemMessage: message,
	}
}

func r14TddRequiredLocalTrialResult(ctx hookproto.RuleContext) *hookproto.HookResult {
	if ctx.TddEnforceLevel != tddEnforceLevelMax || !ctx.TddHookEnabled {
		return nil
	}
	filePath, ok := ctx.Input.ToolInput["file_path"].(string)
	if !ok {
		return nil
	}
	if !isTddSourceWriteCandidate(filePath, ctx.ProjectRoot) {
		return nil
	}
	if ctx.TddBypass {
		// TDD bypass only bypasses the future TDD-specific denial path. It must
		// not short-circuit later non-TDD guardrails such as Codex direct-write
		// denial.
		return nil
	}

	// Phase 68 B1-B3 local trial: R14 is registered but non-blocking until the
	// dedicated TDD evaluator is added by the follow-up helper implementation.
	return nil
}

// Rules is the ordered table of all guard rules.
var Rules = []GuardRule{
	// R01: sudo block (Bash)
	{
		ID:          "R01:no-sudo",
		ToolPattern: regexp.MustCompile(`^Bash$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			command, ok := ctx.Input.ToolInput["command"].(string)
			if !ok {
				return nil
			}
			if !hasSudo(command) {
				return nil
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionDeny,
				Reason:   "sudo の使用は禁止されています。必要な場合はユーザーに手動実行を依頼してください。",
			}
		},
	},

	// R02: protected path write block (Write/Edit/MultiEdit)
	{
		ID:          "R02:no-write-protected-paths",
		ToolPattern: regexp.MustCompile(`^(?:Write|Edit|MultiEdit)$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			filePath, ok := ctx.Input.ToolInput["file_path"].(string)
			if !ok {
				return nil
			}
			match := classifyProtectedPath(filePath)
			if match.Level == protectedPathNone {
				return nil
			}
			return protectedPathHookResult(match, filePath, "保護パスへのファイル書き込み")
		},
	},

	// R03: Bash write to protected paths block
	{
		ID:          "R03:no-bash-write-protected-paths",
		ToolPattern: regexp.MustCompile(`^Bash$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			command, ok := ctx.Input.ToolInput["command"].(string)
			if !ok {
				return nil
			}
			match := classifyBashProtectedWrite(command)
			if match.Level == protectedPathNone {
				return nil
			}
			return protectedPathHookResult(match, match.Path, "保護パスへのシェル書き込み")
		},
	},

	// R14: TDD required for source writes (local-trial registration only)
	{
		ID:          "R14:test-required-for-src-write",
		ToolPattern: regexp.MustCompile(`^(?:Write|Edit|MultiEdit)$`),
		Evaluate:    r14TddRequiredLocalTrialResult,
	},

	// R04: confirm write outside project root
	{
		ID:          "R04:confirm-write-outside-project",
		ToolPattern: regexp.MustCompile(`^(?:Write|Edit|MultiEdit)$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			filePath, ok := ctx.Input.ToolInput["file_path"].(string)
			if !ok {
				return nil
			}
			if isUnderProjectRoot(filePath, ctx.ProjectRoot) {
				return nil
			}
			// Work mode skips confirmation
			if ctx.WorkMode {
				return nil
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionAsk,
				Reason:   fmt.Sprintf("プロジェクトルート外への書き込みです: %s\n許可しますか？", filePath),
			}
		},
	},

	// R05: confirm dangerous deletion commands
	{
		ID:          "R05:confirm-rm-rf",
		ToolPattern: regexp.MustCompile(`^Bash$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			command, ok := ctx.Input.ToolInput["command"].(string)
			if !ok {
				return nil
			}
			if !hasDangerousRmRf(command) {
				return nil
			}
			if ctx.WorkMode {
				return nil
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionAsk,
				Reason:   fmt.Sprintf("危険な削除コマンドを検出しました:\n%s\n実行しますか？", command),
			}
		},
	},

	// R06: git push --force block (no bypass even in work mode)
	{
		ID:          "R06:no-force-push",
		ToolPattern: regexp.MustCompile(`^Bash$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			command, ok := ctx.Input.ToolInput["command"].(string)
			if !ok {
				return nil
			}
			if !hasForcePush(command) {
				return nil
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionDeny,
				Reason:   "git push --force は禁止されています。履歴を破壊する操作は許可されません。",
			}
		},
	},

	// R07: Codex mode — no Write/Edit
	{
		ID:          "R07:codex-mode-no-write",
		ToolPattern: regexp.MustCompile(`^(?:Write|Edit|MultiEdit)$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			if !ctx.CodexMode {
				return nil
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionDeny,
				Reason:   "Codex モード中は Claude が直接ファイルを書き込めません。実装は Codex Worker (codex exec) に委譲してください。",
			}
		},
	},

	// R08: Breezing reviewer — no write operations
	{
		ID:          "R08:breezing-reviewer-no-write",
		ToolPattern: regexp.MustCompile(`^(?:Write|Edit|MultiEdit|Bash)$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			if ctx.BreezingRole != "reviewer" {
				return nil
			}
			toolName := ctx.Input.ToolName
			if toolName == "Bash" {
				command, ok := ctx.Input.ToolInput["command"].(string)
				if !ok {
					return nil
				}
				matched := false
				for _, p := range r08ReviewerProhibitedPatterns {
					if p.MatchString(command) {
						matched = true
						break
					}
				}
				if !matched {
					return nil
				}
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionDeny,
				Reason:   "Breezing reviewer ロールはファイル書き込みおよびデータ変更コマンドを実行できません。",
			}
		},
	},

	// R09: warn on secret file read
	{
		ID:          "R09:warn-secret-file-read",
		ToolPattern: regexp.MustCompile(`^Read$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			filePath, ok := ctx.Input.ToolInput["file_path"].(string)
			if !ok {
				return nil
			}
			for _, p := range r09SecretPatterns {
				if p.MatchString(filePath) {
					return &hookproto.HookResult{
						Decision:      hookproto.DecisionApprove,
						SystemMessage: fmt.Sprintf("警告: 機密情報が含まれる可能性のあるファイルを読み取っています: %s", filePath),
					}
				}
			}
			return nil
		},
	},

	// R10: --no-verify / --no-gpg-sign block
	{
		ID:          "R10:no-git-bypass-flags",
		ToolPattern: regexp.MustCompile(`^Bash$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			command, ok := ctx.Input.ToolInput["command"].(string)
			if !ok {
				return nil
			}
			if !hasDangerousGitBypassFlag(command) {
				return nil
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionDeny,
				Reason:   "--no-verify / --no-gpg-sign の使用は禁止されています。フックや署名検証を迂回しないでください。",
			}
		},
	},

	// R11: protected branch git reset --hard block
	{
		ID:          "R11:no-reset-hard-protected-branch",
		ToolPattern: regexp.MustCompile(`^Bash$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			command, ok := ctx.Input.ToolInput["command"].(string)
			if !ok {
				return nil
			}
			if !hasProtectedBranchResetHard(command) {
				return nil
			}
			return &hookproto.HookResult{
				Decision: hookproto.DecisionDeny,
				Reason:   "protected branch への git reset --hard は禁止されています。履歴を壊さない方法を使ってください。",
			}
		},
	},

	// R12: configurable direct push policy for protected branches
	{
		ID:          "R12:confirm-direct-push-protected-branch",
		ToolPattern: regexp.MustCompile(`^Bash$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			command, ok := ctx.Input.ToolInput["command"].(string)
			if !ok {
				return nil
			}
			if !hasDirectPushToProtectedBranch(command) {
				return nil
			}

			switch normalizeProtectedBranchPushPolicy(ctx.ProtectedBranchPushPolicy) {
			case protectedBranchPushPolicyDeny:
				return &hookproto.HookResult{
					Decision: hookproto.DecisionDeny,
					Reason:   "main/master への直接 push は設定で禁止されています。feature branch 経由で PR を作成してください。",
				}
			case protectedBranchPushPolicyAllow:
				return nil
			default:
				return &hookproto.HookResult{
					Decision: hookproto.DecisionAsk,
					Reason:   "main/master への直接 push です。ユーザー確認後に実行しますか？（設定: protected_branch_push=ask）",
				}
			}
		},
	},

	// R13: warn on protected review paths (Write/Edit/MultiEdit)
	{
		ID:          "R13:warn-protected-review-paths",
		ToolPattern: regexp.MustCompile(`^(?:Write|Edit|MultiEdit)$`),
		Evaluate: func(ctx hookproto.RuleContext) *hookproto.HookResult {
			filePath, ok := ctx.Input.ToolInput["file_path"].(string)
			if !ok {
				return nil
			}
			if !isProtectedReviewPath(filePath) {
				return nil
			}
			return &hookproto.HookResult{
				Decision:      hookproto.DecisionApprove,
				SystemMessage: fmt.Sprintf("警告: 重要ファイルへの変更を検出しました: %s", filePath),
			}
		},
	},
}

// EvaluateRules evaluates all guard rules in order and returns the first match.
// If no rule matches, it returns approve.
func EvaluateRules(ctx hookproto.RuleContext) hookproto.HookResult {
	toolName := ctx.Input.ToolName
	for _, rule := range Rules {
		if !rule.ToolPattern.MatchString(toolName) {
			continue
		}
		if result := rule.Evaluate(ctx); result != nil {
			return *result
		}
	}
	return hookproto.HookResult{Decision: hookproto.DecisionApprove}
}
