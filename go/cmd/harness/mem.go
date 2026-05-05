package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Chachamaru127/claude-code-harness/go/internal/harnessmem"
)

// memHealthOutput は `bin/harness mem health` の JSON 出力スキーマ。
type memHealthOutput struct {
	Healthy bool   `json:"healthy"`
	Reason  string `json:"reason"`
}

// daemonProbe は harness-mem daemon への到達性確認。
// テスト注入のため package 変数。本番では probeHarnessMemDaemon を使う。
var daemonProbe = probeHarnessMemDaemon

// probeHarnessMemDaemon は HARNESS_MEM_HOST:HARNESS_MEM_PORT に TCP connect を試す。
// 既定 127.0.0.1:37888。接続失敗はそのまま error を返す（fail-silent な呼び出し側で処理）。
func probeHarnessMemDaemon() error {
	host := os.Getenv("HARNESS_MEM_HOST")
	if host == "" {
		host = "127.0.0.1"
	}
	port := os.Getenv("HARNESS_MEM_PORT")
	if port == "" {
		port = "37888"
	}
	addr := net.JoinHostPort(host, port)
	conn, err := net.DialTimeout("tcp", addr, 500*time.Millisecond)
	if err != nil {
		return err
	}
	_ = conn.Close()
	return nil
}

// runMem は `harness mem <subcommand>` を処理する。
func runMem(args []string) {
	os.Exit(runMemCommand(args, os.Stdout, os.Stderr))
}

func runMemCommand(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, "Usage: harness mem <status|setup|update|doctor|off|purge|health>")
		return 1
	}
	switch args[0] {
	case "health":
		return writeMemHealth(stdout)
	case "status":
		return runMemStatus(args[1:], stdout, stderr)
	case "setup":
		return runMemSetup(args[1:], stdout, stderr)
	case "update":
		return streamHarnessMem("update", args[1:], true, stdout, stderr)
	case "doctor":
		return runMemDoctor(args[1:], stdout, stderr)
	case "off":
		return streamHarnessMem("recall", []string{"off"}, false, stdout, stderr)
	case "purge":
		return runMemPurge(args[1:], stdout, stderr)
	default:
		fmt.Fprintf(stderr, "Unknown mem subcommand: %s\n", args[0])
		return 1
	}
}

// runMemHealth は `harness mem health` サブコマンドを実行する。
// ~/.claude-mem/ のファイルチェック後に daemon への TCP probe を行い、
// いずれかの段階で失敗したら unhealthy を返す。
// exit 0: healthy, exit 1: unhealthy
func runMemHealth(_ []string) {
	os.Exit(writeMemHealth(os.Stdout))
}

func writeMemHealth(stdout io.Writer) int {
	result, code := runMemHealthCheck()
	data, _ := json.Marshal(result)
	fmt.Fprintf(stdout, "%s\n", data)
	return code
}

// runMemHealthCheck はヘルスチェックロジックを実行し、結果と exit code を返す。
// テストからも直接呼び出せるよう os.Exit を含まない形で分離する。
//
// harness-mem が未設定のケース (`~/.claude-mem/` が存在しない) は、
// 「壊れている」ではなく「監視対象外」として扱う。
// healthy=true + reason="not-configured" を返すことで、
// MonitorHandler 側の `⚠️ harness-mem unhealthy` 警告を抑止する。
// daemon 停止 (daemon-unreachable) や構成破損 (corrupted) は従来どおり unhealthy。
func runMemHealthCheck() (memHealthOutput, int) {
	home, err := os.UserHomeDir()
	if err != nil {
		// ホームディレクトリ解決失敗は環境異常。
		// harness-mem 未設定判定もできない状態なので healthy=true で手を引く。
		return memHealthOutput{Healthy: true, Reason: "not-configured"}, 0
	}

	harnessMemHome := os.Getenv("HARNESS_MEM_HOME")
	if harnessMemHome == "" {
		harnessMemHome = filepath.Join(home, ".harness-mem")
	}
	claudeMem := filepath.Join(home, ".claude-mem")

	// ~/.harness-mem/ または legacy ~/.claude-mem/ の存在チェック。
	// 両方不在 = harness-mem がそもそもインストールされていない。
	// 監視対象外として healthy 扱いにして exit 0 を返す。
	if _, err := os.Stat(harnessMemHome); os.IsNotExist(err) {
		if _, legacyErr := os.Stat(claudeMem); os.IsNotExist(legacyErr) {
			return memHealthOutput{Healthy: true, Reason: "not-configured"}, 0
		}
		harnessMemHome = claudeMem
	}

	if looksConfiguredHarnessMem(harnessMemHome) {
		if err := daemonProbe(); err != nil {
			return memHealthOutput{Healthy: false, Reason: "daemon-unreachable"}, 1
		}
		return memHealthOutput{Healthy: true, Reason: ""}, 0
	}

	if harnessMemHome != claudeMem {
		return memHealthOutput{Healthy: true, Reason: "not-configured"}, 0
	}

	// settings.json または supervisor.json のいずれかが読めるか
	settingsPath := filepath.Join(claudeMem, "settings.json")
	supervisorPath := filepath.Join(claudeMem, "supervisor.json")

	settingsOK := false
	if _, err := os.Stat(settingsPath); err == nil {
		settingsOK = true
	}
	supervisorOK := false
	if _, err := os.Stat(supervisorPath); err == nil {
		supervisorOK = true
	}

	if !settingsOK && !supervisorOK {
		return memHealthOutput{Healthy: false, Reason: "corrupted"}, 1
	}

	// daemon reachability probe: ファイルは揃っていても daemon 停止中は unhealthy
	if err := daemonProbe(); err != nil {
		return memHealthOutput{Healthy: false, Reason: "daemon-unreachable"}, 1
	}

	return memHealthOutput{Healthy: true, Reason: ""}, 0
}

func looksConfiguredHarnessMem(root string) bool {
	configPath := filepath.Join(root, "config.json")
	runtimeCLI := filepath.Join(root, "runtime", "harness-mem", "scripts", "harness-mem")
	dbPath := filepath.Join(root, "harness-mem.db")
	for _, path := range []string{configPath, runtimeCLI, dbPath} {
		if _, err := os.Stat(path); err == nil {
			return true
		}
	}
	return false
}

func runMemStatus(args []string, stdout, stderr io.Writer) int {
	jsonOutput := hasFlag(args, "--json")
	ctx, cancel := harnessmem.DefaultTimeoutContext()
	defer cancel()

	report, result, err := harnessmem.Doctor(ctx, false)
	if errors.Is(err, harnessmem.ErrNotInstalled) {
		if jsonOutput {
			fmt.Fprintln(stdout, `{"status":"not_configured","installed":false,"all_green":false,"failed_count":0,"checks":[],"fix_command":"harness mem setup"}`)
		} else {
			fmt.Fprintln(stdout, "harness-mem companion: not configured")
			fmt.Fprintln(stdout, "Run: harness mem setup")
		}
		return 0
	}
	if err != nil {
		if jsonOutput {
			payload := map[string]interface{}{
				"status":       "unknown",
				"installed":    true,
				"all_green":    false,
				"failed_count": 1,
				"error":        err.Error(),
				"fix_command":  "harness mem doctor",
			}
			data, _ := json.Marshal(payload)
			fmt.Fprintf(stdout, "%s\n", data)
		} else {
			fmt.Fprintf(stderr, "harness-mem status failed: %v\n", err)
			if strings.TrimSpace(result.Stdout) != "" {
				fmt.Fprintln(stderr, strings.TrimSpace(result.Stdout))
			}
			if strings.TrimSpace(result.Stderr) != "" {
				fmt.Fprintln(stderr, strings.TrimSpace(result.Stderr))
			}
		}
		return 1
	}

	if jsonOutput {
		fmt.Fprint(stdout, ensureTrailingNewline(result.Stdout))
		return 0
	}
	state := "degraded"
	if report.AllGreen {
		state = "ready"
	}
	fmt.Fprintf(stdout, "harness-mem companion: %s (status=%s, failed=%d, backend=%s)\n",
		state, report.Status, report.FailedCount, report.BackendMode)
	if report.FixCommand != "" && !report.AllGreen {
		fmt.Fprintf(stdout, "Fix: %s\n", report.FixCommand)
	}
	return 0
}

func runMemSetup(args []string, stdout, stderr io.Writer) int {
	ctx, cancel := harnessmem.DefaultTimeoutContext()
	defer cancel()

	report, _, err := harnessmem.Doctor(ctx, false)
	if err == nil && report.AllGreen {
		fmt.Fprintln(stdout, "harness-mem companion already ready")
		return 0
	}

	setupArgs := []string{"--platform", harnessmem.DefaultPlatforms, "--skip-quality", "--auto-update", "enable"}
	setupArgs = append(setupArgs, args...)
	return streamHarnessMem("setup", setupArgs, true, stdout, stderr)
}

func runMemDoctor(args []string, stdout, stderr io.Writer) int {
	doctorArgs := appendDefaultPlatform(args)
	return streamHarnessMem("doctor", doctorArgs, true, stdout, stderr)
}

func runMemPurge(args []string, stdout, stderr io.Writer) int {
	if !hasFlag(args, "--confirm-purge") && os.Getenv("CLAUDE_CODE_HARNESS_MEM_CONFIRM_PURGE") != "1" {
		fmt.Fprintln(stderr, "Refusing to purge harness-mem data without explicit confirmation.")
		fmt.Fprintln(stderr, "Run: harness mem purge --confirm-purge")
		return 2
	}
	filtered := removeFlag(args, "--confirm-purge")
	purgeArgs := []string{"--platform", harnessmem.DefaultPlatforms, "--purge-db"}
	purgeArgs = append(purgeArgs, filtered...)
	return streamHarnessMem("uninstall", purgeArgs, false, stdout, stderr)
}

func streamHarnessMem(command string, args []string, allowNpx bool, stdout, stderr io.Writer) int {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	code, err := harnessmem.Stream(ctx, command, args, allowNpx, stdout, stderr)
	if errors.Is(err, harnessmem.ErrNotInstalled) {
		return code
	}
	return code
}

func appendDefaultPlatform(args []string) []string {
	for _, arg := range args {
		if arg == "--platform" || strings.HasPrefix(arg, "--platform=") {
			return args
		}
	}
	out := append([]string{}, args...)
	out = append(out, "--platform", harnessmem.DefaultPlatforms)
	return out
}

func hasFlag(args []string, flag string) bool {
	for _, arg := range args {
		if arg == flag {
			return true
		}
	}
	return false
}

func removeFlag(args []string, flag string) []string {
	out := make([]string, 0, len(args))
	for _, arg := range args {
		if arg == flag {
			continue
		}
		out = append(out, arg)
	}
	return out
}

func ensureTrailingNewline(s string) string {
	if strings.HasSuffix(s, "\n") {
		return s
	}
	return s + "\n"
}
