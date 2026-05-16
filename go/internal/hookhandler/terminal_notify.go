package hookhandler

// terminal_notify.go
// CC 2.1.141+ hook JSON output `terminalSequence` フィールドを構築する共有ヘルパー。
// HARNESS_TERMINAL_NOTIFY env で opt-in。
//
// 詳細: .claude/rules/hooks-2.1.139-plus.md
// shell 版参考実装: scripts/lib/terminal-notify.sh

import (
	"os"
	"strings"
)

// terminalNotifyMode は HARNESS_TERMINAL_NOTIFY env を解釈した結果。
type terminalNotifyMode int

const (
	notifyOff terminalNotifyMode = iota
	notifyBell
	notifyTitle
	notifyOSC9
	notifyDesktop // OSC 777
)

// resolveTerminalNotifyMode は env から mode を解決する。未知値は notifyOff。
func resolveTerminalNotifyMode() terminalNotifyMode {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("HARNESS_TERMINAL_NOTIFY"))) {
	case "", "0":
		return notifyOff
	case "1", "bell":
		return notifyBell
	case "title":
		return notifyTitle
	case "osc9":
		return notifyOSC9
	case "notify":
		return notifyDesktop
	default:
		// 未知値は silent (rule との一致)
		return notifyOff
	}
}

// sanitizeTerminalText は title / body から制御文字 (0x00-0x1F, 0x7F) を除去する。
// terminal corruption / secret 漏洩防止のため、印字可能な文字だけを通す。
func sanitizeTerminalText(s string) string {
	if s == "" {
		return ""
	}
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		// 0x00-0x1F は制御文字、0x7F は DEL
		if r < 0x20 || r == 0x7F {
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}

// BuildTerminalSequence は terminalSequence の raw OSC sequence を構築する。
//
// title が空の場合、bell mode のみ BEL を返し、それ以外は空文字列を返す。
// HARNESS_TERMINAL_NOTIFY 未設定なら常に空文字列を返す (opt-in 維持)。
//
// 戻り値は raw bytes。JSON にする場合は json.Marshal で encode する。
func BuildTerminalSequence(title, body string) string {
	mode := resolveTerminalNotifyMode()
	if mode == notifyOff {
		return ""
	}

	cleanTitle := sanitizeTerminalText(title)
	cleanBody := sanitizeTerminalText(body)

	// bell mode は title 不要、それ以外は title 必須
	if mode != notifyBell && cleanTitle == "" {
		return ""
	}

	const (
		esc = "\x1b"
		bel = "\x07"
	)

	switch mode {
	case notifyBell:
		return bel
	case notifyTitle:
		return esc + "]0;" + cleanTitle + bel
	case notifyOSC9:
		return esc + "]9;" + cleanTitle + bel
	case notifyDesktop:
		// OSC 777;notify;<title>;<body><BEL>
		if cleanBody != "" {
			return esc + "]777;notify;" + cleanTitle + ";" + cleanBody + bel
		}
		return esc + "]777;notify;" + cleanTitle + bel
	}
	return ""
}

// AugmentWithTerminalSequence は hook 応答 map に terminalSequence フィールドを追加する。
// HARNESS_TERMINAL_NOTIFY が未設定 / title が空 (非 bell) の場合は何もしない。
func AugmentWithTerminalSequence(resp map[string]interface{}, title, body string) {
	if resp == nil {
		return
	}
	seq := BuildTerminalSequence(title, body)
	if seq != "" {
		resp["terminalSequence"] = seq
	}
}
