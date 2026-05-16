# Plans.md アーカイブ - harness-ui Plugin MCP 化

アーカイブ日時: 2025-01-02
元ファイル: .claude/Plans.md

---

## ✅ フェーズ1: MCP サーバー基盤構築（完了）

### 1.1 MCP サーバーエントリポイント作成
- [x] `harness-ui/src/mcp/server.ts` を作成
- [x] MCP SDK (`@modelcontextprotocol/sdk`) を導入
- [x] stdio transport でのサーバー初期化

### 1.2 HTTP サーバー統合
- [x] MCP サーバー起動時に HTTP サーバーも起動
- [x] 既存の `src/server/index.ts` をモジュール化
- [x] ポート 37778 での HTTP 提供を維持

### 1.3 MCP ツール定義（基本）
- [x] `harness_health` - ヘルススコア取得
- [x] `harness_usage` - Usage 情報取得
- [x] `harness_skills` - スキル一覧取得
- [x] `harness_ui_url` - UI URL 取得

---

## ✅ フェーズ2: Plugin MCP 設定（完了）

### 2.1 .mcp.json 作成
- [x] `.mcp.json` をプラグインルートに作成
- [x] stdio command を設定
- [x] 環境変数の引き継ぎ設定

### 2.2 ビルド設定
- [x] MCP サーバー用のビルドスクリプト追加 (`build:mcp`, `start:mcp`)
- [x] Bun ネイティブ実行（バンドル不要）
- [N/A] `scripts/mcp-server.cjs` → TypeScript 直接実行方式を採用

### 2.3 プラグイン統合テスト
- [x] MCP 一覧への表示確認 (`plugin:claude-code-harness:harness-ui`)
- [x] HTTP サーバーの動作確認 (http://localhost:37778/api/status)

---

## 📋 技術詳細（参考資料）

### アーキテクチャ

```
┌─────────────────────────────────────────┐
│            Claude Code                   │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │     Plugin: claude-code-harness     │ │
│  │                                      │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │   .mcp.json                   │  │ │
│  │  │   ├─ mcpServers:              │  │ │
│  │  │   │   └─ harness-ui           │  │ │
│  │  │   │       └─ stdio command    │  │ │
│  │  └──────────────────────────────┘  │ │
│  │                │                     │ │
│  │                ▼                     │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │   MCP Server (stdio)          │  │ │
│  │  │   ├─ Tools: harness_*         │  │ │
│  │  │   └─ HTTP Server (port 37778) │──┼─┼──▶ Browser
│  │  └──────────────────────────────┘  │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 課金アーキテクチャ（Polar）

```
┌─────────────────────────────────────────────────────┐
│  1. 購入フロー                                       │
│                                                      │
│  [ユーザー] → [Polar 決済ページ]                     │
│                    ↓                                 │
│             ライセンスキー発行（自動）               │
│                    ↓                                 │
│  [ユーザー] ← メールでキー受信                       │
│                    ↓                                 │
│  [設定ファイル or 環境変数にキーを設定]              │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  2. 検証フロー（harness-ui MCP 起動時）              │
│                                                      │
│  [harness-ui MCP] → ライセンスキー読み込み           │
│       ↓                                              │
│  [Polar API] ← キー検証リクエスト                    │
│       ↓                                              │
│  有効 → 全機能開放 + HTTP サーバー起動               │
│  無効 → エラーメッセージ + 購入リンク案内            │
└─────────────────────────────────────────────────────┘
```

### 参考実装
- [mcp-bridge](https://github.com/brrock/mcp-bridge) - stdio ↔ HTTP 変換
- [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) - トランスポートブリッジ
- claude-mem の `.mcp.json` 方式
- [Polar License Keys](https://polar.sh/docs/features/benefits/license-keys) - ライセンスキー管理

### 見積もり工数

| フェーズ | 工数（人日） |
|---------|------------|
| フェーズ1: MCP 基盤 | 1-2 |
| フェーズ2: Plugin 設定 | 0.5-1 |
| フェーズ3: ツール拡張 | 1 |
| フェーズ4: 仕上げ | 0.5 |
| **合計** | **3-4.5** |
