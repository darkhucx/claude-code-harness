package hookhandler

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestHandleNotification_EmptyInput(t *testing.T) {
	var out bytes.Buffer
	err := HandleNotification(strings.NewReader(""), &out)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// 通知ハンドラは空入力で出力なし
	if out.Len() != 0 {
		t.Errorf("expected no output for empty input, got %q", out.String())
	}
}

func TestHandleNotification_InvalidJSON(t *testing.T) {
	var out bytes.Buffer
	err := HandleNotification(strings.NewReader("{invalid json}"), &out)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// パース失敗でも出力なし（正常終了）
	if out.Len() != 0 {
		t.Errorf("expected no output for invalid JSON, got %q", out.String())
	}
}

func TestHandleNotification_BasicEvent(t *testing.T) {
	tmpDir := t.TempDir()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	t.Setenv("PROJECT_ROOT", tmpDir)
	t.Setenv("CLAUDE_PLUGIN_DATA", "")

	input := `{"notification_type":"auth_success","session_id":"sess-001","agent_type":"worker"}`
	var out bytes.Buffer
	if err := HandleNotification(strings.NewReader(input), &out); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// JSONL ログが作成されていること
	logFile := filepath.Join(tmpDir, ".claude", "state", "notification-events.jsonl")
	data, readErr := os.ReadFile(logFile)
	if readErr != nil {
		t.Fatalf("log file not created: %v", readErr)
	}

	var entry notificationLogEntry
	if jsonErr := json.Unmarshal(bytes.TrimSpace(data), &entry); jsonErr != nil {
		t.Fatalf("invalid JSONL entry: %v, raw: %s", jsonErr, string(data))
	}

	if entry.Event != "notification" {
		t.Errorf("expected event=notification, got %q", entry.Event)
	}
	if entry.NotificationType != "auth_success" {
		t.Errorf("expected notification_type=auth_success, got %q", entry.NotificationType)
	}
	if entry.SessionID != "sess-001" {
		t.Errorf("expected session_id=sess-001, got %q", entry.SessionID)
	}
	if entry.AgentType != "worker" {
		t.Errorf("expected agent_type=worker, got %q", entry.AgentType)
	}
	if entry.Timestamp == "" {
		t.Error("expected non-empty timestamp")
	}
}

func TestHandleNotification_TypeFallback(t *testing.T) {
	tmpDir := t.TempDir()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	t.Setenv("PROJECT_ROOT", tmpDir)
	t.Setenv("CLAUDE_PLUGIN_DATA", "")

	// notification_type がない場合は type でフォールバック
	input := `{"type":"idle_prompt","session_id":"sess-002"}`
	var out bytes.Buffer
	if err := HandleNotification(strings.NewReader(input), &out); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	logFile := filepath.Join(tmpDir, ".claude", "state", "notification-events.jsonl")
	data, readErr := os.ReadFile(logFile)
	if readErr != nil {
		t.Fatalf("log file not created: %v", readErr)
	}

	var entry notificationLogEntry
	if jsonErr := json.Unmarshal(bytes.TrimSpace(data), &entry); jsonErr != nil {
		t.Fatalf("invalid JSONL entry: %v", jsonErr)
	}
	if entry.NotificationType != "idle_prompt" {
		t.Errorf("expected notification_type=idle_prompt (from type field), got %q", entry.NotificationType)
	}
}

func TestHandleNotification_MatcherFallback(t *testing.T) {
	tmpDir := t.TempDir()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	t.Setenv("PROJECT_ROOT", tmpDir)
	t.Setenv("CLAUDE_PLUGIN_DATA", "")

	// notification_type も type もない場合は matcher でフォールバック
	input := `{"matcher":"permission_prompt","session_id":"sess-003","agent_type":"task-worker"}`
	var out bytes.Buffer
	if err := HandleNotification(strings.NewReader(input), &out); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	logFile := filepath.Join(tmpDir, ".claude", "state", "notification-events.jsonl")
	data, readErr := os.ReadFile(logFile)
	if readErr != nil {
		t.Fatalf("log file not created: %v", readErr)
	}

	var entry notificationLogEntry
	if jsonErr := json.Unmarshal(bytes.TrimSpace(data), &entry); jsonErr != nil {
		t.Fatalf("invalid JSONL entry: %v", jsonErr)
	}
	if entry.NotificationType != "permission_prompt" {
		t.Errorf("expected notification_type=permission_prompt (from matcher), got %q", entry.NotificationType)
	}
}

func TestHandleNotification_RotatesAtLimit(t *testing.T) {
	tmpDir := t.TempDir()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	t.Setenv("PROJECT_ROOT", tmpDir)
	t.Setenv("CLAUDE_PLUGIN_DATA", "")

	// ログファイルに501行のダミーエントリを書き込む
	stateDir := filepath.Join(tmpDir, ".claude", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	logFile := filepath.Join(stateDir, "notification-events.jsonl")
	f, err := os.Create(logFile)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 501; i++ {
		f.WriteString(`{"event":"notification","notification_type":"dummy"}` + "\n")
	}
	f.Close()

	input := `{"notification_type":"auth_success","session_id":"sess-rotate"}`
	var out bytes.Buffer
	if err := HandleNotification(strings.NewReader(input), &out); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	data, readErr := os.ReadFile(logFile)
	if readErr != nil {
		t.Fatalf("log file not found: %v", readErr)
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	// 401行（400行 + 1行の新エントリ）になっていること
	if len(lines) > 401 {
		t.Errorf("expected ≤401 lines after rotation, got %d", len(lines))
	}
}

func TestHandleNotification_NoOutput(t *testing.T) {
	// 通知ハンドラは HARNESS_TERMINAL_NOTIFY 未設定なら stdout に何も書かない
	// (既存挙動: opt-in 維持の後方互換性テスト)
	tmpDir := t.TempDir()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	t.Setenv("PROJECT_ROOT", tmpDir)
	t.Setenv("CLAUDE_PLUGIN_DATA", "")
	t.Setenv("HARNESS_TERMINAL_NOTIFY", "")

	input := `{"notification_type":"auth_success","session_id":"sess-out"}`
	var out bytes.Buffer
	if err := HandleNotification(strings.NewReader(input), &out); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// stdout には何も書かない（bash の exit 0 に相当）
	if out.Len() != 0 {
		t.Errorf("notification handler should produce no stdout output when env unset, got %q", out.String())
	}
}

// TestHandleNotification_TerminalSequenceEmit は
// HARNESS_TERMINAL_NOTIFY=osc9 で permission_prompt 受信時に
// terminalSequence 付き JSON が emit されることを確認する (CC 2.1.141+ Phase 69)。
func TestHandleNotification_TerminalSequenceEmit(t *testing.T) {
	tmpDir := t.TempDir()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	t.Setenv("PROJECT_ROOT", tmpDir)
	t.Setenv("CLAUDE_PLUGIN_DATA", "")
	t.Setenv("HARNESS_TERMINAL_NOTIFY", "osc9")

	input := `{"notification_type":"permission_prompt","agent_type":"worker","session_id":"s1"}`
	var out bytes.Buffer
	if err := HandleNotification(strings.NewReader(input), &out); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if out.Len() == 0 {
		t.Fatal("expected JSON output when HARNESS_TERMINAL_NOTIFY=osc9 + permission_prompt, got none")
	}

	var resp map[string]interface{}
	if jsonErr := json.Unmarshal(out.Bytes(), &resp); jsonErr != nil {
		t.Fatalf("invalid JSON output: %v, raw=%q", jsonErr, out.String())
	}

	if resp["decision"] != "approve" {
		t.Errorf("expected decision=approve, got %v", resp["decision"])
	}
	seq, ok := resp["terminalSequence"].(string)
	if !ok || seq == "" {
		t.Errorf("expected terminalSequence string in response, got %v (type %T)", resp["terminalSequence"], resp["terminalSequence"])
	}
	// OSC 9 sequence は ESC ]9; ... BEL の形
	if !strings.HasPrefix(seq, "\x1b]9;") || !strings.HasSuffix(seq, "\x07") {
		t.Errorf("terminalSequence does not match OSC 9 shape: %q", seq)
	}
}

// TestHandleNotification_TerminalSequence_UnknownType は
// 未知の notification_type では terminalSequence を emit しないことを確認する。
func TestHandleNotification_TerminalSequence_UnknownType(t *testing.T) {
	tmpDir := t.TempDir()
	origDir, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(tmpDir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(origDir)

	t.Setenv("PROJECT_ROOT", tmpDir)
	t.Setenv("CLAUDE_PLUGIN_DATA", "")
	t.Setenv("HARNESS_TERMINAL_NOTIFY", "osc9")

	input := `{"notification_type":"unknown_xyz","session_id":"s1"}`
	var out bytes.Buffer
	if err := HandleNotification(strings.NewReader(input), &out); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// 未知 type は silent
	if out.Len() != 0 {
		t.Errorf("unknown notification_type should not emit terminalSequence, got %q", out.String())
	}
}

// TestHandleNotification_TerminalSequence_AllTypes は
// 既知 4 種 (permission_prompt / elicitation_dialog / idle_prompt / auth_success) で
// terminalSequence が emit されることを確認する。
func TestHandleNotification_TerminalSequence_AllTypes(t *testing.T) {
	knownTypes := []string{"permission_prompt", "elicitation_dialog", "idle_prompt", "auth_success"}
	for _, nt := range knownTypes {
		t.Run(nt, func(t *testing.T) {
			tmpDir := t.TempDir()
			origDir, _ := os.Getwd()
			if err := os.Chdir(tmpDir); err != nil {
				t.Fatal(err)
			}
			defer os.Chdir(origDir)
			t.Setenv("PROJECT_ROOT", tmpDir)
			t.Setenv("CLAUDE_PLUGIN_DATA", "")
			t.Setenv("HARNESS_TERMINAL_NOTIFY", "osc9")

			input := `{"notification_type":"` + nt + `","agent_type":"worker"}`
			var out bytes.Buffer
			if err := HandleNotification(strings.NewReader(input), &out); err != nil {
				t.Fatalf("err: %v", err)
			}
			if out.Len() == 0 {
				t.Fatalf("expected terminalSequence for %s, got nothing", nt)
			}
			var resp map[string]interface{}
			if err := json.Unmarshal(out.Bytes(), &resp); err != nil {
				t.Fatalf("invalid JSON: %v", err)
			}
			if _, ok := resp["terminalSequence"]; !ok {
				t.Errorf("type=%s: terminalSequence missing", nt)
			}
		})
	}
}
