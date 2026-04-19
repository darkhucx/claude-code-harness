package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// memHealthOutput は `bin/harness mem health` の JSON 出力スキーマ。
type memHealthOutput struct {
	Healthy bool   `json:"healthy"`
	Reason  string `json:"reason"`
}

// runMem は `harness mem <subcommand>` を処理する。
func runMem(args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Usage: harness mem <health>")
		os.Exit(1)
	}
	switch args[0] {
	case "health":
		runMemHealth(args[1:])
	default:
		fmt.Fprintf(os.Stderr, "Unknown mem subcommand: %s\n", args[0])
		os.Exit(1)
	}
}

// runMemHealth は `harness mem health` サブコマンドを実行する。
// ~/.claude-mem/ のヘルスチェックを行い JSON を stdout に出力する。
// exit 0: healthy, exit 1: unhealthy
func runMemHealth(_ []string) {
	result, code := runMemHealthCheck()
	data, _ := json.Marshal(result)
	fmt.Printf("%s\n", data)
	os.Exit(code)
}

// runMemHealthCheck はヘルスチェックロジックを実行し、結果と exit code を返す。
// テストからも直接呼び出せるよう os.Exit を含まない形で分離する。
func runMemHealthCheck() (memHealthOutput, int) {
	home, err := os.UserHomeDir()
	if err != nil {
		return memHealthOutput{Healthy: false, Reason: "not-initialized"}, 1
	}

	claudeMem := filepath.Join(home, ".claude-mem")

	// ~/.claude-mem/ の存在チェック
	if _, err := os.Stat(claudeMem); os.IsNotExist(err) {
		return memHealthOutput{Healthy: false, Reason: "not-initialized"}, 1
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

	return memHealthOutput{Healthy: true, Reason: ""}, 0
}
