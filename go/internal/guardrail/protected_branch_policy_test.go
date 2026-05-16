package guardrail

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/Chachamaru127/claude-code-harness/go/pkg/hookproto"
)

func TestNormalizeProtectedBranchPushPolicy(t *testing.T) {
	cases := map[string]string{
		"":           "ask",
		"ask":        "ask",
		"confirm":    "ask",
		"DENY":       "deny",
		"block":      "deny",
		"allow":      "allow",
		"approve":    "allow",
		"unexpected": "ask",
	}
	for input, want := range cases {
		if got := normalizeProtectedBranchPushPolicy(input); got != want {
			t.Errorf("normalizeProtectedBranchPushPolicy(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestBuildContextProtectedBranchPushPolicyFromEnv(t *testing.T) {
	t.Setenv("HARNESS_PROTECTED_BRANCH_PUSH_POLICY", "deny")

	ctx := BuildContext(hookproto.HookInput{
		CWD:       t.TempDir(),
		ToolName:  "Bash",
		ToolInput: map[string]interface{}{"command": "git push origin main"},
	})

	if ctx.ProtectedBranchPushPolicy != "deny" {
		t.Fatalf("ProtectedBranchPushPolicy = %q, want deny", ctx.ProtectedBranchPushPolicy)
	}
}

func TestBuildContextProtectedBranchPushPolicyFromProjectYAML(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, ".claude-code-harness.config.yaml")
	if err := os.WriteFile(configPath, []byte("safety:\n  protected_branch_push: allow\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	ctx := BuildContext(hookproto.HookInput{
		CWD:       dir,
		ToolName:  "Bash",
		ToolInput: map[string]interface{}{"command": "git push origin main"},
	})

	if ctx.ProtectedBranchPushPolicy != "allow" {
		t.Fatalf("ProtectedBranchPushPolicy = %q, want allow", ctx.ProtectedBranchPushPolicy)
	}
}

func TestBuildContextProtectedBranchPushPolicyFromHarnessTOML(t *testing.T) {
	dir := t.TempDir()
	tomlPath := filepath.Join(dir, "harness.toml")
	data := []byte(`
[project]
name = "test"

[safety.permissions]
protectedBranchPush = "deny"
`)
	if err := os.WriteFile(tomlPath, data, 0o644); err != nil {
		t.Fatal(err)
	}

	ctx := BuildContext(hookproto.HookInput{
		CWD:       dir,
		ToolName:  "Bash",
		ToolInput: map[string]interface{}{"command": "git push origin main"},
	})

	if ctx.ProtectedBranchPushPolicy != "deny" {
		t.Fatalf("ProtectedBranchPushPolicy = %q, want deny", ctx.ProtectedBranchPushPolicy)
	}
}

func TestBuildContextProtectedBranchPushPolicyDefaultAsk(t *testing.T) {
	ctx := BuildContext(hookproto.HookInput{
		CWD:       t.TempDir(),
		ToolName:  "Bash",
		ToolInput: map[string]interface{}{"command": "git push origin main"},
	})

	if ctx.ProtectedBranchPushPolicy != "ask" {
		t.Fatalf("ProtectedBranchPushPolicy = %q, want ask", ctx.ProtectedBranchPushPolicy)
	}
}

func TestBuildContextTDDRuntimeConfigFromHarnessTOML(t *testing.T) {
	dir := t.TempDir()
	tomlPath := filepath.Join(dir, "harness.toml")
	data := []byte(`
[tdd.enforce]
enabled = true
level = "max"
hook_enabled = true
bypass_audit_required = true
`)
	if err := os.WriteFile(tomlPath, data, 0o644); err != nil {
		t.Fatal(err)
	}

	ctx := BuildContext(hookproto.HookInput{
		CWD:       dir,
		ToolName:  "Write",
		ToolInput: map[string]interface{}{"file_path": filepath.Join(dir, "src", "feature.ts")},
	})

	if ctx.TddEnforceLevel != tddEnforceLevelMax {
		t.Fatalf("TddEnforceLevel = %q, want max", ctx.TddEnforceLevel)
	}
	if !ctx.TddHookEnabled {
		t.Fatal("TddHookEnabled = false, want true")
	}
	if ctx.TddBypass {
		t.Fatal("TddBypass = true, want false")
	}
}

func TestBuildContextTDDRuntimeConfigEnvDisablesHook(t *testing.T) {
	dir := t.TempDir()
	tomlPath := filepath.Join(dir, "harness.toml")
	data := []byte(`
[tdd.enforce]
enabled = true
level = "max"
hook_enabled = true
bypass_audit_required = true
`)
	if err := os.WriteFile(tomlPath, data, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HARNESS_TDD_ENFORCE_ENABLED", "false")

	ctx := BuildContext(hookproto.HookInput{
		CWD:       dir,
		ToolName:  "Write",
		ToolInput: map[string]interface{}{"file_path": filepath.Join(dir, "src", "feature.ts")},
	})

	if ctx.TddEnforceLevel != tddEnforceLevelOff {
		t.Fatalf("TddEnforceLevel = %q, want off", ctx.TddEnforceLevel)
	}
	if ctx.TddHookEnabled {
		t.Fatal("TddHookEnabled = true, want false")
	}
}
