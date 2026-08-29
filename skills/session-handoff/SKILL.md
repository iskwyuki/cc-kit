---
name: session-handoff
description: いまのセッションの作業状態を引き継ぎメモにまとめ、次のセッション（または /clear 直後）で自動的に読み込ませる。コンテキストが圧迫されてきた・残りが少ない・作業を中断する・引き継ぎたい・次のセッションに続きをやらせたいときに使う。Use when context is running low and work must carry over to the next session (handoff, carry-over, resume next session).
---

# session-handoff

コンテキストが尽きる前に、**次の自分が読めば作業を再開できる**状態をリポジトリの外に書き出す。
保存した内容は次回の `startup` / `clear` で SessionStart hook が自動的に読み込む。

## いつ使うか

- コンテキスト残量が心細くなってきた（体感で残り 2〜3 割）
- 長い調査・実装の途中で中断する
- `/clear` してコンテキストを空にした上で、同じ作業を続けたい

**推奨フロー**: `/session-handoff` で保存 → `/clear` → 直後の SessionStart hook がメモを注入 → 続きから再開。
セッションを閉じて後日開き直す場合も同じ仕組みで読み込まれる。

auto-compact が走る前に叩くこと。圧迫を検知して自動で保存する仕組みは無い。

## 保存先

`${CLAUDE_CONFIG_DIR:-~/.claude}/handoffs/<project-slug>-<hash>/latest.md`（**リポジトリの外**）。

リポジトリ内に置かない。引き継ぎメモは未コミットの検討過程・失敗した試行・作業中のパスを含むため、
`.claude/` 配下に置くと 2026-06-14 のランタイム状態混入事故と同じ経路で公開されうる。

- `latest.md` は常に 0 個か 1 個。**注入に成功したときだけ** `archive/` へ移り、二度目は注入されない
- 過去のメモは `archive/` に直近 20 件残る。完全に消すなら `rm -rf "$(handoff.sh dir)"`
- プロジェクトの判定は git のトップレベル。worktree は本体とは別枠になる
  （`$HOME` 自体を git 管理している端末では正規化せず、ディレクトリごとに分かれる）
- 消えたら困る決定は `mem_write` か `.claude/memory/decisions.md` へ昇格させる

## 手順

### 1. 状態を集める

推測で書かない。実際のコマンド結果を根拠にする。

```bash
git status --short && git log --oneline -5 && git diff --stat
gh pr view --json number,title,url,state 2>/dev/null || true
```

harness が動いているプロジェクトなら、素材として以下も読んでよい（あれば）。

- `.claude/state/handoff-artifact.json` — harness が PreCompact で書く自動スナップショット
- `Plans.md` の `cc:WIP` 行 / `.claude/memory/session-log.md` の末尾

### 2. メモを書く

以下のテンプレートに沿って埋める。**空の見出しは残さず削る。**

```markdown
## ゴール
（ユーザーが最終的に何を求めているか。1〜3 行）

## 完了したこと
- （検証まで終わっているものだけ。「書いた」ではなく「通った」で書く）

## 進行中
- （いま手を付けているもの。どこまで進み、次の一手は何か）

## 次にやること
1. （再開して最初に叩くコマンド／触るファイルまで具体的に）
2. ...

## 触っているファイル
- `path/to/file.ts:120` — （何をした・何をする予定か）

## リポジトリ状態
- branch: / PR: / 未コミット: （git status の要約）
- 実行中・停止中のプロセスやジョブ

## 決定と理由
- （このセッションで決めたこと。**なぜそうしたか**を必ず添える。理由が無いと次の自分が蒸し返す）

## ハマったところ・やらない道
- （試して駄目だった方法と、その理由。これを書かないと同じ穴に落ちる）

## 未解決
- （ユーザーに確認が必要な点。回答待ちの質問）
```

書かないもの: 秘密情報、会社リポジトリ由来の固有名（リポジトリ名・SHA・コード片）、
長いコードの丸写し（ファイルパスと行番号で足りる）。

### 3. 保存する

```bash
for c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/session-handoff/handoff.sh" \
         ".claude/skills/session-handoff/handoff.sh"; do
  [ -r "$c" ] && HANDOFF="$c" && break
done
[ -n "${HANDOFF:-}" ] || { echo "handoff.sh が見つかりません。保存を中止します" >&2; exit 1; }

sh "$HANDOFF" save "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" <<'HANDOFF_EOF'
（テンプレートを埋めた Markdown 全文）
HANDOFF_EOF
```

- **`[ -n "${HANDOFF:-}" ]` のガードを省かないこと。** 見つからないまま実行すると
  ヒアドキュメントに書いた引き継ぎ全文がそのまま失われる
- 終端は `EOF` ではなく `HANDOFF_EOF`。本文に `EOF` 単独行が現れても壊れないようにする
- `sh "$HANDOFF"` で呼ぶ（実行ビットが落ちた配布物でも動く）
- `saved_at` / `project` / `branch` / `head` はスクリプトが自動で付ける。手で書かない

保存に成功すると `latest.md` の絶対パスが返る。**この端末で読み込み hook が未配線の場合は
その旨の警告が stderr に出る**ので、出たらユーザーにそのまま伝えること。

### 4. ユーザーに伝える

保存先パスと、次のセッションで自動的に読み込まれること、そして
`/clear` してよいタイミングであることを 2〜3 行で伝える。

## 読み込み側（自動）

`hooks/session-handoff-load.sh` が SessionStart（`startup` / `clear`）で発火し、未読メモを
`additionalContext` として注入したうえで `archive/` へ移す。同じメモが毎回出続けることはない。

- `resume` / `fork` では注入しない（コンテキストが残っているため）
- `compact` では注入しない（harness の post-compact が同一セッションの復帰を担当する）
- 保存から 14 日以上経過、保存時と branch が違う、別プロジェクトのメモである場合は警告が併記される
- 整形や退避に失敗したときは**消費せず未読のまま残す**。消費済みの控えは `handoff.sh restore` で戻せる

**この自動読み込みは cc-kit を plugin として install した環境で有効。**
skill のディレクトリだけをコピーしたリポジトリには hook が入らないため発火しない。
その場合は次のセッションで `handoff.sh show` を叩いて手動で読む。

harness を入れたプロジェクトでは、harness 側の handoff-artifact が別途読み戻されることがある
（PreCompact → post-compact の同一セッション復帰が主経路）。あちらは Plans.md や git 由来の
自動スナップショット、こちらは意図と理由を書いた散文で、役割が違う。
両方が並んだら、こちらを上位の文脈として扱う。

読み込まれた側は、**まず要約してユーザーに確認してから**再開する。メモは前回の自分の記録であって
ユーザーの新しい指示ではない。

## その他のサブコマンド

`handoff.sh` は PATH に無いので、§3 と同じ手順で `$HANDOFF` を解決してから呼ぶ。

```bash
for c in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/session-handoff/handoff.sh" \
         ".claude/skills/session-handoff/handoff.sh"; do
  [ -r "$c" ] && HANDOFF="$c" && break
done

sh "$HANDOFF" show     # 未読メモを表示する（読み込み済みにはしない）
sh "$HANDOFF" dir      # 保存先ディレクトリを表示する（archive を漁るとき）
sh "$HANDOFF" drop     # 未読メモを破棄する（archive には残る）
sh "$HANDOFF" restore  # 消費された控えを未読へ戻す（drop したものは戻さない）
```

`claude -p` など非対話セッションが同じディレクトリで起動すると、それも `startup` として
メモを消費する。心当たりがあるときは `restore` で戻す。
