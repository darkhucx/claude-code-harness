package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// memHealthResult は runMemHealth が返す JSON のスキーマ（テスト用）。
type memHealthResult struct {
	Healthy bool   `json:"healthy"`
	Reason  string `json:"reason"`
}

func TestRunMemHealth_Healthy(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	// ~/.claude-mem/ と settings.json を作成
	claudeMem := filepath.Join(home, ".claude-mem")
	if err := os.MkdirAll(claudeMem, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(claudeMem, "settings.json"), []byte(`{}`), 0600); err != nil {
		t.Fatal(err)
	}

	out, exitCode := captureMemHealth()
	if exitCode != 0 {
		t.Fatalf("expected exit 0 for healthy, got %d; output: %s", exitCode, out)
	}

	var result memHealthResult
	if err := json.Unmarshal([]byte(out), &result); err != nil {
		t.Fatalf("invalid JSON output: %v\nraw: %s", err, out)
	}
	if !result.Healthy {
		t.Errorf("expected healthy=true, got false (reason: %s)", result.Reason)
	}
}

func TestRunMemHealth_NotInitialized(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	// ~/.claude-mem/ を作成しない

	out, exitCode := captureMemHealth()
	if exitCode == 0 {
		t.Fatalf("expected non-zero exit for not-initialized, got 0; output: %s", out)
	}

	var result memHealthResult
	if err := json.Unmarshal([]byte(out), &result); err != nil {
		t.Fatalf("invalid JSON output: %v\nraw: %s", err, out)
	}
	if result.Healthy {
		t.Errorf("expected healthy=false")
	}
	if result.Reason != "not-initialized" {
		t.Errorf("expected reason=not-initialized, got %q", result.Reason)
	}
}

func TestRunMemHealth_Corrupted(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	// ~/.claude-mem/ は存在するが settings.json も supervisor.json もない
	claudeMem := filepath.Join(home, ".claude-mem")
	if err := os.MkdirAll(claudeMem, 0700); err != nil {
		t.Fatal(err)
	}
	// config ファイルは作成しない

	out, exitCode := captureMemHealth()
	if exitCode == 0 {
		t.Fatalf("expected non-zero exit for corrupted, got 0; output: %s", out)
	}

	var result memHealthResult
	if err := json.Unmarshal([]byte(out), &result); err != nil {
		t.Fatalf("invalid JSON output: %v\nraw: %s", err, out)
	}
	if result.Healthy {
		t.Errorf("expected healthy=false")
	}
	if result.Reason != "corrupted" {
		t.Errorf("expected reason=corrupted, got %q", result.Reason)
	}
}

// captureMemHealth は runMemHealth の stdout と exit code を文字列で返す。
// 内部関数のためシグネチャを直接呼ぶ。
func captureMemHealth() (string, int) {
	result, code := runMemHealthCheck()
	data, _ := json.Marshal(result)
	return string(data), code
}
