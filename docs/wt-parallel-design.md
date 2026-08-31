# wt-parallel 設計仕様書

**ステータス**: 設計確定（grill 2026-07-09、Q1–Q19）／実装未着手
**対象**: cc-kit が配布する「git worktree 並列開発ツール」の設計正本
**関連**: Phase 6（計画表は cc-kit-private の Plans.md／完了済みのため `docs/plans-archive-2026-08.md`）

---

## 1. 概要

git worktree で複数 issue を分けて並列に開発・動作確認するためのツール一式を、**cc-kit の配布物として汎用化**する。各プロジェクトは plugin として取り込み、リポジトリ直下に置いた任意のマニフェスト `.wt-parallel.yaml` 1 本で起動方法を宣言する。

### 背景

業務で使う worktree 並列起動キット（約 1,200 行、Postgres 実データ複製・process-compose 起動が app スタック固有）を**設計参考**とする。kit のうち **worktree ライフサイクル（作成・設定/plugin 引き継ぎ・破棄・ポート採番）は汎用化可能**で、app 固有部分（DB 複製・依存同期・起動コマンド）はマニフェスト＋フックに externalize する。

> **機密分離**: kit は他リポジトリからの抽出物。kit を**設計仕様書としてのみ参照しゼロから再実装**し、kit 固有識別子・由来リポジトリ名を docs / コミット / コメントに一切残さない（本リポジトリの機密分離ルール）。

---

## 2. スコープ

### 汎用版が担うこと

- worktree の作成（ブランチ起点解決・派生ディレクトリ命名）
- gitignore 済みファイル（`.env` / `.claude/settings.local.json` 等）の引き継ぎ
- Claude Code plugin の project スコープ登録／破棄時の対称解除
- ポート offset の自動採番と `.dev/` への永続化
- 起動オーケストレーション（start をバックグラウンド実行 → ログ集約 → health 待ち → return）
- 停止・破棄・ライフサイクルフックの実行

### app 側に委ねること（汎用版は関知しない）

- DB 複製・マイグレーション・依存同期（`pre_start` / `post_create` フック）
- マルチプロセスの依存順序（`start` コマンドの中で process-compose 等を呼ぶ）
- 実ポート番号の意味づけ（`env` マップで宣言）
- 破棄時の外部リソース解放（`pre_rm` フック）

---

## 3. 設計判断サマリ（grill Q1–Q19）

| # | 論点 | 決定 | 要点 |
|---|------|------|------|
| Q1 | 導入形態 | 配信 asset として汎用化 | 価値の主軸は他 app プロジェクトへの pull 配布 |
| Q2 | 由来の扱い | 設計参考の再実装 | kit 固有識別子・由来名を残さない |
| Q3 | externalize 方式 | 宣言的マニフェスト | 動的処理はマニフェスト内フックコマンドに集約 |
| Q4 | スコープ | 起動オーケストレーションまで | DB 複製は pre-start フックに委任・孤児 DB 掃除は持たない |
| Q5 | 配置 | skill 同梱 | `skills/<name>/scripts/` → plugin として配布・skill 経由実行 |
| Q6 | skill 構成 | 2 skill | 作成入口（手動発火・**AskUserQuestion 不使用**）／ライフサイクル正本 |
| Q7 | plugin 登録 | 標準機能 | 非 CC/jq 不在で自動スキップ・env でオプトアウト可 |
| Q8 | 表現力 | 最小コア | 単一 start + health URL・**process-compose 非必須** |
| Q9 | フォールバック | マニフェスト任意・起動 opt-in | 無ければ作成＋引き継ぎ＋plugin 登録のみ（**自リポジトリで dogfood 可**）|
| Q10 | 命名 | `wt-parallel` 系 | `/wt-new`・`wt-parallel`・`.wt-parallel.yaml` |
| Q11 | コマンド体系 | `wt-` 統一 | `wt-new` / `wt-up` / `wt-down` / `wt-rm` + `wt-identity` |
| Q12 | health 方式 | url / command 両対応 | タイムアウト付き（既定 60s）|
| Q13 | フック粒度 | 4 種 | post-create / pre-start / post-start / pre-rm |
| Q14 | ポート採番 | offset のみ採番 | 汎用側はポートの意味を持たない |
| Q15 | ポート橋渡し | env マップ | `WT_OFFSET`/`WT_SLUG` 参照式を start・health.url・全フックに共通注入 |
| Q16 | 引き継ぎ | settings.local.json + .env デフォルト | `inherit:` で追加・非存在は無警告スキップ |
| Q17 | ブランチ起点 | 自動検出 + 上書き | env `BASE_REF` > マニフェスト `base_ref` > `origin/HEAD` > 現在ブランチ |
| Q18 | テスト戦略 | 純粋関数 単体 + 統合スモーク | 既存 `test-pre-commit-gate.sh` の型を踏襲 |
| Q19 | docs | skill 集約 + 最小 docs | 仕様の SSOT は SKILL.md ＋ `.example`・導入入口 1 ページを docs/ に |

---

## 4. アーキテクチャ

### スクリプト構成（`skills/wt-parallel/scripts/`）

| スクリプト | 役割 |
|-----------|------|
| `wt-new.sh` | worktree 作成 → 引き継ぎ（`.env` / `settings.local.json` / `inherit`）→ plugin 登録 → 次手順表示 |
| `wt-up.sh` | 起動。identity 採番 → env 展開 → `pre_start` → start をバックグラウンド起動 → ログを `.dev/logs/` へ → health 待ち → `post_start` → URL/ログパス提示 |
| `wt-down.sh` | 停止のみ（worktree と外部リソースは残す）|
| `wt-rm.sh` | 破棄。停止 → `pre_rm` フック → plugin 登録解除 → `git worktree remove` |
| `wt-identity.sh` | 共通ライブラリ。slug 採番・offset 採番（空きポート探索）・`.dev/` 永続化 |

- 起動が opt-in（Q9）のため、`wt-up`/`wt-down` はマニフェスト不在時に「起動対象が宣言されていません」と案内して正常終了する。
- 孤児 DB 掃除（kit 側の専用スクリプト相当）は DB 密結合ゆえ汎用版に持たない。

### skill 構成（2 skill・Q6）

| skill | 種別 | 役割 |
|-------|------|------|
| `wt-new` | 手動発火（`disable-model-invocation`）| 会話文脈からブランチ名を推定 →**テキスト番号付き確認**→ `wt-new.sh` 実行。**AskUserQuestion は使わない**（グローバルルール） |
| `wt-parallel` | モデル自動参照可 | ライフサイクル正本。起動/停止/破棄・ポート・ログ・マニフェスト仕様・安全不変条件の SSOT |

### 配布と実行導線（Q5）

- スクリプトは skill ディレクトリに同梱し、plugin としてそのまま配布される。**対象リポジトリの直下は汚さない**。
- plugin を user スコープで install していれば全プロジェクトから引けるため、**dogfooding は追加作業なしで成立**する。
- 頻繁に叩くコマンドは skill が絶対パスを提示する。

---

## 5. マニフェスト仕様 `.wt-parallel.yaml`

**すべて任意。無ければ `wt-new` は作成＋引き継ぎ＋plugin 登録のみ行う（起動系は opt-in）。**

```yaml
# .wt-parallel.yaml — worktree 並列開発マニフェスト（リポジトリ直下・任意）

# ── ブランチ起点（省略時: origin/HEAD 自動検出 → 現在ブランチ / env BASE_REF が最優先）
base_ref: origin/main

# ── 追加の引き継ぎファイル（.env と .claude/settings.local.json はデフォルトで自動）
inherit:
  - backend/.env
  - frontend/.env

# ── ポート採番: 汎用側は「これらが offset とともに同時に空く最小 offset」を探索し
#    WT_OFFSET を .dev/ に永続化。ポートの意味づけは持たない（Q14）
ports:
  check: [3000, 8000]     # 空き判定の基準ポート群。省略時は offset 採番をスキップ

# ── env マップ: WT_OFFSET / WT_SLUG を参照するシェル式。
#    展開結果を start・health.url・全フックに共通注入（Q15）
env:
  FRONTEND_PORT: "$((3000 + WT_OFFSET))"
  BACKEND_PORT:  "$((8000 + WT_OFFSET))"
  DATABASE_URL:  "postgres://localhost/app_${WT_SLUG}"

# ── 起動コマンド（単一。マルチプロセスは start の中で process-compose 等を呼ぶ・Q8）
start: "pnpm dev"

# ── 起動完了判定（url か command の一方・Q12）
health:
  url: "http://localhost:${FRONTEND_PORT}/health"
  timeout: 60
  # command: "curl -sf http://localhost:$((3000 + WT_OFFSET))/"   # ← HTTP を持たない app 用

# ── ライフサイクルフック（宣言したものだけ実行・worktree ルートで実行・Q13）
hooks:
  post_create: "uv sync && pnpm install"          # 作成直後の依存初期化
  pre_start:   "./scripts/seed-db.sh"             # DB 複製・マイグレーション（app 責務）
  post_start:  "curl -s http://localhost:${FRONTEND_PORT}/warmup"
  pre_rm:      "dropdb app_${WT_SLUG}"            # 破棄前クリーンアップ
```

### 最小例（起動だけしたい単純 app）

```yaml
ports:
  check: [3000]
env:
  PORT: "$((3000 + WT_OFFSET))"
start: "npm run dev"
health:
  url: "http://localhost:${PORT}/"
```

### 5.1 パース対応部分集合（strict subset・自前パーサ・§12.4 確定）

`yq` に依存せず bash（awk）で読む。**YAML 全仕様は解さない。**下記の部分集合のみ受理し、範囲外の構文は**明示エラーで拒否**する（黙って誤読しない）。

**受理する構文**

| 形 | 例 | 対応フィールド |
|----|----|--------------|
| トップレベルスカラ | `base_ref: origin/main` / `start: "pnpm dev"` | `base_ref` / `start` |
| ブロックリスト（スカラ要素のみ） | `inherit:` 改行 `  - backend/.env` | `inherit` |
| inline flow list（スカラ要素のみ・1 形式のみ） | `check: [3000, 8000]` | `ports.check` |
| 2 階層マップ（`key:`→`  sub: val`） | `env:` 改行 `  BACKEND_PORT: "..."` | `ports` / `env` / `health` / `hooks` |
| クォート | `'...'` / `"..."`（囲みを剥がし中身は逐語） | 値全般 |
| 行コメント・空行 | `# ...` | — |

- **ネストは最大 2 階層**（`env.FOO` まで。3 階層以上は拒否）。
- **値は逐語**（unquote 後の中身は解釈せず下流へ渡す）。`env`/`hooks` の値に含まれる `$((...))`・`${...}` の評価は §12.3 の別論点として 6.3 で扱う。パーサはシェル式を評価しない。

**明示的に拒否する構文（loud error）**

- anchor / alias（`&` / `*`）
- block scalar（`|` / `>` の複数行）
- 多文書区切り（`---`）
- flow map（`{a: b}`）／inline list の入れ子
- タブインデント（スペース 2 のみ許可）
- 3 階層以上のネスト

**インデント規約**: スペース 2。リスト項目は親キーから 2、マップ子キーも親から 2。

---

## 6. ライフサイクルとフック

```
wt-new ─▶ [git worktree add] ─▶ [inherit コピー] ─▶ [plugin 登録] ─▶ post_create
                                                                          │
wt-up  ─▶ [identity 採番] ─▶ [env 展開] ─▶ pre_start ─▶ [start をBG起動]  │
                                                            │             │
                                            [ログ → .dev/logs/] ─▶ [health 待ち] ─▶ post_start ─▶ 完了
wt-down ─▶ [stop]
wt-rm  ─▶ [stop] ─▶ pre_rm ─▶ [plugin 登録解除] ─▶ [git worktree remove]
```

| フック | タイミング | 典型用途 | 失敗時 |
|--------|-----------|---------|--------|
| `post_create` | 作成＋引き継ぎ直後 | 依存の初回同期 | 中断 |
| `pre_start` | 起動直前 | DB seed・マイグレーション | 起動中断 |
| `post_start` | health 緑の後 | warmup・seed データ投入 | 起動中断 |
| `pre_rm` | 破棄直前 | DB drop・外部リソース解放 | **警告どまり・破棄続行** |

---

## 7. ポート採番と env 注入（Q14 + Q15）

- **汎用側の責務**: `ports.check` の全ポートが offset とともに同時に空く最小 offset N を探索し、`WT_OFFSET` として `.dev/offset` に永続化（再起動で同じポート再利用）。slug は `.dev/slug` に永続化。
- **意味づけの責務は app**: 実ポートは `env` マップ（`$((3000 + WT_OFFSET))` 等のシェル式）で宣言。汎用側はポート名を知らない。
- **注入先の一貫性**: 展開済み env は **start・health.url・全フックに同一の値で注入**され、URL とプロセスのポートが必ず一致する。
- **公開変数**: `WT_SLUG`（識別子）・`WT_OFFSET`（ポート offset）を全実行文脈に export。

---

## 8. plugin 登録引き継ぎ（Q7）

- `settings.json` / `settings.local.json` の `enabledPlugins=true` のうち、**user スコープ済みを除外**したものを新 worktree パスに `claude plugin install --scope project` で登録。共有キャッシュ・他 worktree に影響しない。
- `wt-rm` は破棄時に `claude plugin uninstall --scope project` で**対称に解除**し、`installed_plugins.json` にダングリングを残さない。
- `claude` / `jq` 不在時は自動スキップ（警告のみ・`set -e` を落とさない）。env `WT_SKIP_PLUGIN_REGISTER=1` でオプトアウト可。

---

## 9. 安全不変条件

- 共有外部リソース（DB コンテナ等）は worktree 操作で**止めない/消さない**。破棄対象は当該 worktree 固有のリソースのみ（`.dev/slug` と突き合わせて自 worktree 分だけ）。
- `.env` は書き換えず、`env` マップの export で上書きする。
- worktree の作成は `git worktree add` 直叩きではなく必ず `wt-new`、片付けは必ず `wt-rm` を使う（孤児リソース・plugin 登録残骸を防ぐ）。
- `pre_rm` フック（DB drop 等）は app 責務。汎用版は「破棄前に呼ぶ」だけで中身の安全性は各 app のフックが担保する。
- `.dev/`（offset / slug / logs / socket）は各 repo で gitignore 必須（**導入時の gitignore 追記は未確定・§12 参照**）。

---

## 10. テスト戦略（Q18）

- **単体（純粋関数）**: slug 正規化・offset 採番の空きポート探索境界・マニフェスト env 式展開・plugin 対象抽出（user スコープ除外の jq）・安全ガードを副作用から切り離してテスト。既存 `tests/test-pre-commit-gate.sh` の型（一時 repo・`assert_*`・STDIN 判定）を踏襲。
- **統合スモーク 1 本**: 一時 repo で `wt-new`→`wt-rm` を通す。health ポーリングは 1 経路確認。
- **CLI 不在スキップ**: `claude` を PATH から外して plugin 登録がスキップされることを検証。

---

## 11. タスク分割・段階リリース

各ステージ完了時に配信 asset 変更につき `plugin.json` を bump。

| リリース | ステージ | タスク | 内容 | 価値が出る対象 |
|---------|---------|--------|------|---------------|
| **1** | 土台 | 6.1 / 6.2 | `wt-new`/`wt-rm`/`wt-identity`＋引き継ぎ＋plugin 登録＋`/wt-new` skill／マニフェストスキーマ確定＋`.example` | **自リポジトリで即 dogfood**（起動なしで並列）|
| **2** | 起動 | 6.3 / 6.4 | `wt-up`（start＋ログ＋health）/`wt-down`＋ポート採番＋フック＋正本 skill／plugin 対称解除＋オプトアウト | app 系プロジェクト（起動込み）|
| **3** | 実証・横展開 | 6.5 | 実 app 1 つで起動実走・`docs/wt-parallel.md`・README 導線・配布確認 | 横展開・実証 |

- **リリース 1 が MVP かつ dogfooding 起点**（マニフェスト任意・起動 opt-in のため起動対象を持たない自リポジトリでも動く）。
- **リリース 2 が本命の DX**（1 コマンド起動 → health 緑まで待つ）。
- **リリース 3 で初めて実 app に触る**（それまでは汎用ロジック＋サンプルで閉じる）。

---

## 12. 未解決の論点（実装前 or 実装中に確定）

1. **マニフェスト詳細スキーマ** — フィールド名・必須/任意。Task 6.2 で確定。パース対応範囲は §5.1（strict subset）に確定済み。
2. ~~**`.dev/` の gitignore 追記**~~ — **確定（2026-07-09・6.1 実装時）: `wt-new` が git-native exclude（`$GIT_COMMON_DIR/info/exclude`）へ `.dev/` を冪等追記する。** tracked な `.gitignore` を汚さず全 worktree に一括で効き、コミット不要。当初案の「`.gitignore` へ追記」を、この理由でリファインした。`wt_ensure_dev_ignored` として実装。
3. ~~**health url のポート展開の実装詳細**~~ — **確定（2026-07-12・6.3 実装時）: 専用サンドボックス `wt_expand_value` で `${VAR}` / `$VAR` / `$((算術))` のみ解決する。テンプレート全体を eval せず、コマンド置換 `$(...)` と backtick は loud-error 拒否、算術はコマンド実行不能な算術コンテキスト `$(( ))` のみで評価。** 適用先は「値であってコマンドではない」`env` 値と `health.url`。`start` / `hooks` / `health.command` は意図的なコマンド実行なので注入済み env のもと `sh -c` 実行と責務分離した。純粋関数として `test-wt-identity.sh` で単体テスト（算術・変数・展開済み env 参照・コマンド置換/backtick 拒否）。
4. ~~**YAML 依存**~~ — **確定（2026-07-09）: 最小自前パース（strict subset）。`yq` 前提にしない。**
   - 決め手: (a) パースは `wt-up`（Stage 2）の生命線でありオプショナル自動スキップが効かない → ハード依存化は dogfood を壊す、(b) 配信元マシンに `yq` 未導入（`jq` は導入済み・配信 hooks で使用実績あり）、(c) 「2 種類の yq」構文差という移植性の地雷、(d) スキーマが 2 階層・フラットで小さく自前が低リスクに成立（Q8 最小コア）。
   - 対応部分集合と拒否対象は §5.1 に定義。実装は 6.3、env 式展開は §10 どおり純粋関数として単体テスト。

---

## 13. 由来の扱い（機密分離チェック）

- kit のコードは**再実装**であり行レベルの移植をしない（Q2）。
- 公開ファイル（本 repo）に持ち込まない: 由来リポジトリ名・SHA、由来固有の DB 名・コンテナ名などの固有値。
- コミットメッセージ・コメント・docs にも由来リポジトリ名を書かない。
- サンプル値（`app_${WT_SLUG}` 等）は汎用のプレースホルダのみ使う。
