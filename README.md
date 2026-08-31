# cc-kit

Claude Code の skill と agent の詰め合わせ。コードレビュー、PR / Issue 操作、セッションの引き継ぎ、git worktree での並列開発をカバーする。

## 入れる

```sh
claude plugin marketplace add iskwyuki/cc-kit
claude plugin install cc-kit@cc-kit
```

install するスコープ（user / project）は選べる。

## skill（17 個）

### 自作（9 個）

| skill | 用途 |
|---|---|
| `code-review` | 複数の専門エージェントを並列起動してコードレビューする（lite / standard / full） |
| `pr-review-loop` | PR に対してレビュー → 修正 → コメント → 再レビューを自律で回す。マージはしない |
| `pr` | Pull Request の作成（テンプレート付き） |
| `issue` | GitHub Issue の作成・更新・クローズ |
| `todo` | オープン中の Issue をカテゴリ・概要付きで一覧する |
| `commit` | コミットメッセージの生成とコミット実行 |
| `session-handoff` | 作業状態を引き継ぎメモにまとめ、次のセッションで自動的に読み込ませる |
| `wt-new` | git worktree を切って並列開発を始める入口 |
| `wt-parallel` | worktree ライフサイクルの正本（作成/破棄・起動/停止・ポート採番・マニフェスト仕様） |

### 外部由来（8 個）

| skill | 上流 | 形態 |
|---|---|---|
| `domain-modeling` | mattpocock/skills | 無改変ミラー（用語集と ADR を書きながら設計する。`grill-with-docs` の呼び出し先） |
| `eli5` | anthropics/claude-plugins-community | 無改変ミラー |
| `find-skills` | vercel-labs/skills | 無改変ミラー |
| `grill-me` | mattpocock/skills | 無改変ミラー（`grilling` を呼ぶラッパー） |
| `grill-with-docs` | mattpocock/skills | 無改変ミラー（`grilling` + `domain-modeling` を呼ぶラッパー） |
| `grilling` | mattpocock/skills | 無改変ミラー（計画や設計をラウンド単位で問い詰める本体） |
| `html-explain` | mathbullet/skills | 改変フォーク |
| `prototype` | mattpocock/skills | 無改変ミラー |

出典は [`.github/upstream-skills.manifest`](.github/upstream-skills.manifest)、ライセンスと改変内容は各 skill 直下の `NOTICE.md` / `LICENSE-*.txt` を参照。**上流への自動追従は行わない。**

## agent（4 個）

| agent | 用途 |
|---|---|
| `codebase-analyst` | 変更前に既存実装の構造・依存関係・影響範囲を把握する |
| `planner` | 調査結果を踏まえ、実装ステップ・トレードオフ・リスクを整理する |
| `researcher` | ライブラリ比較や API 仕様など、外部の技術情報を調べる |
| `reviewer` | 設計・セキュリティ・パフォーマンスの観点で深くレビューする |

## hook

`session-handoff` の読み込み hook を 1 本だけ持つ。SessionStart（`startup` / `clear`）で未読の引き継ぎメモを `additionalContext` として注入する。読み取り専用で、コマンドを止めることはない。

**コマンドをブロックする hook は配布しない。** skill は呼ばれたときだけ動くので失敗してもその場でやめられるが、割り込む hook は誤爆すると解除できない袋小路を作る。

## ライセンス

自作の skill / agent は MIT。外部由来 skill は上流のライセンスに従う（各 `NOTICE.md` 参照）。
