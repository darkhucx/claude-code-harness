# Codex Plugin Workflows Policy

最終更新: 2026-05-05

Codex plugin / workflow 連携を Harness で扱う時の運用方針。

## ひとことで

Harness の SSOT は `Plans.md`。
Codex 側の `/goal` や workflow state は補助入力として扱い、同じ計画を二重管理しない。

## たとえると

`Plans.md` はチームのホワイトボード。
`/goal` はその場のメモ。
メモは便利だが、ホワイトボードと食い違ったら、どちらを見ればよいか分からなくなる。

## `/goal` と `Plans.md`

| 項目 | 方針 |
|------|------|
| 長期タスク管理 | `Plans.md` を正本にする |
| Codex `/goal` | 現在 turn / current run の補助メモとして扱う |
| task status | `Plans.md` の `cc:TODO` / `cc:WIP` / `cc:完了` を優先 |
| conflict | `Plans.md` を読み、必要なら `/goal` 側を更新する |

禁止:

- `/goal` にだけ acceptance criteria を置く
- `Plans.md` と `/goal` に別々の task list を持つ
- Codex worker が `Plans.md` を読まずに `/goal` だけで完了判断する

## Plugin-bundled hooks

Codex `0.128.0` の plugin-bundled hooks は、Harness では opt-in の workflow extension として扱う。

Plugin に hooks を同梱する場合、既定で project の挙動を強く変えない。

方針:

- hook は opt-in にする
- 破壊的操作、push、deploy、外部送信は既定無効
- `PostToolUse` で output を改変する場合は `docs/output-governance.md` に従う
- hook の stdout は JSON contract を守る

なぜ:

plugin を入れただけで hook が勝手に強く動くと、user / project の権限境界が見えにくくなるため。

## External agent import ownership

外部 agent を import する時は、所有者を明確にする。

| ケース | 所有者 | 方針 |
|--------|--------|------|
| Harness 配布 agent | Harness | repo 内で review / test / sync 対象 |
| user local agent | User | Harness は上書きしない |
| third-party plugin agent | Third-party plugin | Harness は依存関係として扱い、内容を fork しない |
| copied external agent | Harness fork | fork 元、変更理由、更新責任を docs に残す |

禁止:

- 外部 agent を黙って Harness 配布物に混ぜる
- user local agent を setup で上書きする
- fork 元の policy / license / update path を記録せずに改変する

## MultiAgentV2 and `agents.max_threads = 8`

`agents.max_threads = 8` は強い並列実行の上限として扱う。
常に 8 並列で走らせるという意味ではない。

方針:

- default は task size と risk に応じて少なめに始める
- IO-bound な調査は並列度を上げてよい
- 同じファイルを触る worker は並列にしない
- write-heavy work は ownership file list を先に固定する
- 8 は上限。review / integration / final verification は直列に戻す

例:

| 作業 | 推奨 |
|------|------|
| docs grep / evidence collection | 4-8 threads |
| 独立した docs 章の作成 | 2-4 threads |
| 同じ TypeScript module の修正 | 1-2 threads |
| release / version sync | 1 thread |

## Sticky environments

Sticky environment は、同じ作業環境を再利用して setup cost を下げる仕組みとして扱う。
ただし、古い server / cache / artifact が残るリスクがある。

safe default:

- one primary environment per write turn を維持する
- remote / sticky environment は read-only first で確認し、書き込み前に primary environment を明示する
- task 開始時に `git status --short` を確認する
- app server の port / pid / health を確認する
- env var と secret をログに出さない
- stale artifact を見つけても、担当外なら勝手に削除しない

## App-server artifacts

app server が生成する artifact は、review / reproduction に役立つ一方で、古くなると誤判定の原因になる。

方針:

- screenshot、trace、coverage、test output は path と生成時刻を報告する
- artifact を根拠にする時は、再生成コマンドも残す
- stale artifact を cleanup する時は、対象 path を明示する
- production credential や customer data を artifact に含めない

## Codex cloud / local boundary

Codex cloud task は sandboxed environment で動く。
Harness repo 内の local `Plans.md` と cloud 側の task state は自動同期される前提にしない。

そのため:

- cloud task の成果は PR / diff / report として受け取る
- Harness の完了判定は local repo で `git diff`、tests、`Plans.md` を確認して行う
- cloud artifact をそのまま source of truth にしない

## Sources

- OpenAI Codex docs: https://platform.openai.com/docs/codex
