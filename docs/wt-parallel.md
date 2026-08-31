# wt-parallel — git worktree 並列開発ツール（利用者向け導入）

複数の Issue を git worktree で分けて**並列に開発・起動・動作確認**するためのツール一式です。
worktree のライフサイクル（作成・設定/plugin 引き継ぎ・起動/停止・破棄・ポート採番）を汎用化し、
app 固有部分はリポジトリ直下の任意マニフェスト `.wt-parallel.yaml` 1 本＋フックに externalize します。

- **仕様の正本（SSOT）**: `skills/wt-parallel/SKILL.md`（＋同ディレクトリ `.wt-parallel.yaml.example`）
- **設計正本**: [wt-parallel-design.md](./wt-parallel-design.md)
- このページは導入の入口です。詳細は上記 2 つを参照してください。

## 導入

cc-kit の一部として配布されます。スクリプトは skill ディレクトリ同梱で、**対象リポジトリの直下は汚しません**。

```sh
claude plugin marketplace add iskwyuki/cc-kit
claude plugin install cc-kit@cc-kit
```

user スコープで入れれば全プロジェクトから使えます。

## コマンド

worktree の作成・片付けは**必ず**このツール経由で行います（`git worktree add`/`remove` の直叩き禁止・
孤児リソースや plugin 登録残骸を防ぐため）。

| コマンド | 役割 |
|---------|------|
| `wt-new.sh <branch> [base_ref] [dir]` | worktree 作成 → 設定引き継ぎ（`.env`/`settings.local.json`/`inherit`）→ plugin 登録 |
| `wt-up.sh [dir]` | 起動。offset 採番 → env 展開 → `pre_start` → start を BG 起動 → ログ集約 → health 待ち → `post_start` → URL/ログパス提示 |
| `wt-down.sh [dir]` | 停止のみ（worktree・外部リソース・ポート採番は残す） |
| `wt-rm.sh <dir>` | 破棄。stop → `pre_rm` → plugin 対称解除 → `git worktree remove` |

マニフェストが無い（または `start` 未宣言）なら、`wt-new` は作成＋引き継ぎ＋plugin 登録のみを行い、
起動系は「宣言されていません」と案内して正常終了します（起動は opt-in）。

## マニフェスト最小例

```yaml
# .wt-parallel.yaml（リポジトリ直下・すべて任意）
ports:
  check: [3000]                        # これらが同時に空く最小 offset を採番し WT_OFFSET を .dev/ に永続化
env:
  PORT: "$((3000 + WT_OFFSET))"        # 展開結果を start・health・全フックに同一値で注入
start: "PORT=${PORT} npm run dev"
health:
  url: "http://localhost:${PORT}/"     # url か command の一方。既定タイムアウト 60s
```

- `env` 値と `health.url` は**値**なので、専用サンドボックスで `${VAR}`/`$VAR`/`$((算術))` のみ解決し、
  コマンド置換 `$(...)` と backtick は拒否します（誤ってコマンドを実行させない）。
- `start` / `hooks` / `health.command` は**コマンド**なので、注入済み env のもと `sh -c` で実行します。
- 対応構文は strict-subset（yq 非依存）。範囲外の構文は起動前に明示エラーで拒否します。

## フックと安全（重要）

破壊的操作（特に `pre_rm` の DB drop）は **`${WT_SLUG}` で自 worktree 固有のリソースだけに限定**し、
共有/ソースを消さないこと。冪等（`dropdb --if-exists` 等）に書くこと。

```yaml
hooks:
  post_create: "pnpm install"                 # 作成直後の依存初期化（worktree は node_modules を持たない）
  pre_start:   "prisma generate"              # 起動前の準備（複製先に対して。ソースは触らない）
  pre_rm:      "dropdb --if-exists app_${WT_SLUG}"   # 自 worktree 固有だけを落とす
```

> 汎用側はフックを「宣言タイミングで worktree ルートで実行する」だけで、中身の安全性は各 app のフックが担保します。

## 動作確認（実アプリでの一巡）

実アプリ（Next.js + Prisma 構成）で worktree 作成 → 起動 → health 緑 → 停止 → 破棄の一巡を検証済みです。
ポート自動採番（offset）で既存 3000 番と衝突回避し、`pre_start` の依存初期化 → `next dev` を
バックグラウンド起動 → health（`url` が非 2xx でも `command` の port-open フォールバックで「サーバ起動」を
検知）→ URL/ログパス提示 → `wt-down` で停止 → `wt-rm` で破棄まで、対象リポジトリに痕跡を残さず一巡しました。

> 実アプリ横展開のヒント: worktree は gitignore された `node_modules` を持ちません。依存初期化は
> `post_create` / `pre_start` フック（`pnpm install` 等）で行ってください。Next.js の Turbopack は
> プロジェクト外を指す `node_modules` シンボリックリンクを受け付けないため、実 install が必要です。
