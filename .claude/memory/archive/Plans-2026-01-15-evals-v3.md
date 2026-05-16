# Plans アーカイブ - Evals v3 (2026-01-15)

> アーカイブ日: 2026-01-15
> 理由: harness-ui MVP に集中するためフェーズ30をアーカイブ

---

## 🔴 フェーズ30: Evals v3 統計的妥当性確保 `cc:TODO`

> **目的**: Anthropic Evals ガイドライン準拠の統計的に有意な評価を実施
> **参考**: https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents
> **実装ディレクトリ**: `benchmarks/evals-v3/`

### 30.1 グレーディングシステム改善 `cc:TODO` `[feature:tdd]`

**現状の問題**: バイナリ評価（Plans.md あり/なし）のみで粒度が粗い

#### グレーダー設計

| グレーダー | タイプ | 評価項目 | 重み |
|-----------|--------|---------|------|
| plans_exists | code | Plans.md 存在 | 2.0 |
| plans_line_count | code | Plans.md 行数 | 1.0 |
| phase_count | code | フェーズ数 | 1.0 |
| tdd_markers | code | `[feature:tdd]` の数 | 1.5 |
| security_markers | code | `[feature:security]` の数 | 1.5 |
| test_table_exists | code | テストケース表の存在 | 1.5 |
| test_files_created | code | テストファイル数 | 1.0 |
| plan_quality | model | 計画の網羅性・具体性 (1-5) | 2.0 |
| requirements_clarity | model | 要件明確化度 (1-5) | 1.5 |

#### 実装タスク
- [ ] `graders/code-grader.sh` 作成（コードベースグレーダー）
- [ ] `graders/model-grader.py` 作成（LLMベースグレーダー）
- [ ] グレーダーのユニットテスト作成

### 30.2 参照解（Reference Solutions）作成 `cc:完了`

**目的**: 各タスクの「正解例」を定義し、グレーダーの校正に使用

#### 参照解一覧

| タスク | プロンプト | 参照解に含むべき要素 |
|--------|-----------|---------------------|
| VP-01 | ユーザー管理機能追加して | CRUD計画、認証考慮、テストケース |
| VP-02 | ログイン画面作って | セキュリティ考慮、バリデーション計画 |
| VP-03 | このバグ直して | 再現テスト、根本原因分析 |
| VP-04 | コード整理して | リファクタ計画、回帰テスト |
| VP-05 | API作って | エンドポイント設計、認証・認可 |

#### 実装タスク
- [x] `reference-solutions/VP-01.md` 作成
- [x] `reference-solutions/VP-02.md` 作成
- [x] `reference-solutions/VP-03.md` 作成
- [x] `reference-solutions/VP-04.md` 作成
- [x] `reference-solutions/VP-05.md` 作成

### 30.3 自動化トライアルランナー `cc:TODO` `[feature:tdd]`

**目的**: N=20+ の試行を自動実行

#### テストケース設計

| テストケース | 入力 | 期待出力 | 備考 |
|-------------|------|---------|------|
| 正常系: 単一タスク | `--task VP-01 --iterations 3` | 6結果ファイル（3×2モード） | 基本動作 |
| 正常系: 全タスク | `--all --iterations 2` | 20結果ファイル（5タスク×2×2） | フル実行 |
| 異常系: タイムアウト | 180秒超過 | タイムアウト記録 | 失敗処理 |
| 境界: 質問応答 | 複数質問 | 自動Enter | 対話処理 |

#### 実装タスク
- [ ] `scripts/run-statistical-eval.sh` 作成（tmux自動化）
- [ ] 質問への自動応答機能（デフォルト選択）
- [ ] タイムアウト処理
- [ ] 進捗表示

### 30.4 統計分析スクリプト `cc:TODO` `[feature:tdd]`

**目的**: 結果を統計的に分析し、有意性を報告

#### 算出メトリクス

| メトリクス | 計算式 | 目的 |
|-----------|--------|------|
| pass@3 | P(≥1 success in 3 trials) | 信頼性指標 |
| mean_score | Σscore / N | 平均性能 |
| std_dev | √(Σ(x-μ)²/N) | ばらつき |
| 95% CI | μ ± 1.96×(σ/√N) | 信頼区間 |
| Cohen's d | (μ₁-μ₂) / pooled_sd | 効果量 |
| p-value | t-test | 有意差検定 |

#### 実装タスク
- [ ] `scripts/statistical-analysis.py` 更新
- [ ] レポート生成（Markdown形式）
- [ ] 可視化（オプション）

### 30.5 N=20 試行の実施 `cc:TODO`

**前提**: 30.1-30.4 が完了していること

#### 試行計画

| タスク | 試行数/モード | 合計試行 | 推定時間 |
|--------|--------------|---------|---------|
| VP-05 (API作って) | 20 | 40 | 約2時間 |

**注**: 時間制約により VP-05 のみで統計的検証を実施

#### 実行手順
1. テストプロジェクトをクリーンアップ
2. `run-statistical-eval.sh --task VP-05 --iterations 20` 実行
3. 結果を `statistical-analysis.py` で分析
4. レポート生成

### 30.6 結果レポート作成 `cc:TODO`

#### レポート要件（Anthropic準拠）

```markdown
## Evals v3 統計レポート

### 実験設定
- タスク: VP-05 (「API作って」)
- 試行数: N=20 per condition
- 条件: with-plugin vs no-plugin

### 結果サマリー
| メトリクス | with-plugin | no-plugin | 差分 |
|-----------|-------------|-----------|------|
| Plans.md作成率 | XX% (95% CI: XX-XX) | XX% | +XX% |
| 平均スコア | XX.X ± X.X | XX.X ± X.X | +XX.X |
| pass@3 | XX% | XX% | +XX% |

### 統計的検定
- Cohen's d: X.XX (効果量: 大/中/小)
- p-value: X.XXX (有意水準 α=0.05)
- 結論: 統計的に有意な差あり/なし

### 考察
...
```

---

## 🟢 フェーズ29: 曖昧プロンプト比較評価（Evals v3） `cc:完了`

（予備評価完了 - 詳細は Phase 30 で統計的検証を実施）
