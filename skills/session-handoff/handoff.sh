#!/bin/sh
# セッション引き継ぎメモの保存先と受け渡しを一元管理する。
#
# 書き手（session-handoff skill）と読み手（hooks/session-handoff-load.sh）が
# 同じ保存先を指すよう、パス算出と受け渡しの規則をこの 1 本に閉じ込める。
#
#   handoff.sh dir     [<project_dir>]   保存先ディレクトリを表示する（無ければ作る）
#   handoff.sh save    [<project_dir>]   標準入力の Markdown を未読メモとして保存する
#   handoff.sh show    [<project_dir>]   未読メモを表示する（無ければ exit 1）
#   handoff.sh drop    [<project_dir>]   未読メモを破棄する（archive には残す）
#   handoff.sh restore [<project_dir>]   archive の最新の控えを未読へ戻す
#   handoff.sh load                      SessionStart hook 用。標準入力は hook の JSON
#
# 保存先は **リポジトリの外**（~/.claude/handoffs/<project-slug>-<hash>/）に置く。
# 作業内容の要約は未コミットの検討過程を含むため、リポジトリ内に置くと
# 2026-06-14 のランタイム状態混入事故と同じ経路で公開されうる。
#
# 不変条件:
#   - 未読メモ（latest.md）は常に 0 個か 1 個
#   - latest.md を消すときは必ず archive へ move する（唯一の控えを破壊しない）。
#     move 先は同一秒でも衝突しないよう連番で一意化する
#   - **注入できたときだけ消費する**。整形や move に失敗したら未読のまま残す。
#     消費してから注入すると、失敗時に「メモは無かった」ことにされて復旧できない
#   - load は fail-open。何が起きてもセッションを止めない（常に exit 0）
set -eu
umask 077   # 引き継ぎメモは同一マシンの他ユーザーに見せない（NAS は共有機）

MAX_ARCHIVE=20          # archive に残す件数
MAX_INJECT_CHARS=12000  # SessionStart で注入する最大文字数（コンテキスト保護）
MAX_SLUG_CHARS=80       # 深いパスでファイル名長の上限に当たらないよう slug を切る

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

config_home() { printf '%s' "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"; }

# プロジェクトディレクトリを解決する。優先順: 引数 → $CLAUDE_PROJECT_DIR → $PWD。
# 最後に git のトップレベルへ寄せるので、サブディレクトリから叩いても保存先が割れない。
# 保存側と読み込み側でこの関数を共有することが、
# 「保存したのに次のセッションで出てこない」を防ぐ肝（worktree は別トップレベル＝別枠）。
resolve_project() {
  d="${1:-}"
  [ -n "$d" ] || d="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$d" ] || d="$PWD"
  d=$( (CDPATH='' cd -P -- "$d" 2>/dev/null && pwd -P) || printf '%s' "$d" )
  # GIT_DIR / GIT_WORK_TREE が環境に居ると git -C を上書きして別プロジェクトを指すため外す
  top=$( (unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR; git -C "$d" rev-parse --show-toplevel 2>/dev/null) || true )
  # HOME 自体を git 管理している端末（dotfiles）では、その配下の非 repo が
  # すべて 1 枠に潰れて別ディレクトリのメモが混ざるので正規化しない
  if [ -n "$top" ] && [ "$top" != "${HOME:-}" ]; then d="$top"; fi
  printf '%s' "$d"
}

# slug だけだと英数字以外がすべて - に潰れて別プロジェクトと衝突する
# （foo_bar と foo-bar、日本語名同士など）。衝突すると他プロジェクトの
# 作業メモが注入されるので、元パスのチェックサムを添えて一意にする。
# sed はロケールでマルチバイトの扱いが変わるため LC_ALL=C で固定する
# （保存時と読み込み時でロケールが違うと別ディレクトリを見てしまう）。
handoff_dir() {
  cfg=$(config_home)
  case "$cfg" in
    ''|/.claude) echo "HOME も CLAUDE_CONFIG_DIR も設定されていません" >&2; return 1;;
  esac
  slug=$(printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g' \
         | awk -v m="$MAX_SLUG_CHARS" '{ n=length($0); print (n>m) ? substr($0, n-m+1) : $0 }')
  sum=$(printf '%s' "$1" | cksum | awk '{print $1}')
  printf '%s/handoffs/%s-%s' "$cfg" "$slug" "$sum"
}

ts_file() { date -u +%Y%m%dT%H%M%SZ; }
ts_iso()  { date -u +%Y-%m-%dT%H:%M:%SZ; }

git_branch() { git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s' '-'; }
git_head()   { git -C "$1" rev-parse --short HEAD 2>/dev/null || printf '%s' '-'; }

# $1=archive ディレクトリ $2=接尾辞 → 衝突しない move 先を予約して返す。
# 秒精度のままだと同一秒の 2 件目が 1 件目を上書きして控えを壊す。
# 空き名を [ -e ] で探してから作ると、その隙に別セッションが同じ名前を
# 選んで互いの控えを壊すため、noclobber で「作れたら自分のもの」にする
# 連番は 0 埋めして必ず付ける。"-consumed.md" と "-consumed-1.md" が混在すると
# 辞書順が時系列と一致せず、同一秒内で古い方を新しいと誤認する
reserve_dest() {
  base="$1/$(ts_file)-$2"
  i=0
  while :; do
    dest=$(printf '%s-%02d.md' "$base" "$i")
    if (set -C; : > "$dest") 2>/dev/null; then
      printf '%s' "$dest"
      return 0
    fi
    i=$((i + 1))
    [ "$i" -gt 50 ] && return 1
  done
}

# 自分が置いた空の予約だけを消す。中身があるものは別セッションの控えなので触らない
release_dest() { [ -s "$1" ] || rm -f "$1"; }

# SIGKILL や hook タイムアウトで予約だけが残ることがある。
# 進行中かもしれない直近のものは避けて、古い 0 バイトの控えを掃除する
clean_stale_reservations() {
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    [ -s "$f" ] && continue
    if [ -z "$(find "$f" -mmin -10 2>/dev/null)" ]; then rm -f "$f"; fi
  done
}

# archive を新しい順に MAX_ARCHIVE 件だけ残す。
# 並べ替えは mtime ではなくファイル名で行う（ts_file 由来なので辞書順が時系列）。
# mv は mtime を保存するので、mtime 順だと保存時刻の古い控えが先に消える
prune_archive() {
  clean_stale_reservations "$1"
  n=0
  ls -1 "$1"/*.md 2>/dev/null | sort -r | while IFS= read -r f; do
    n=$((n + 1))
    if [ "$n" -gt "$MAX_ARCHIVE" ]; then rm -f "$f"; fi
  done
}

# 読み込み側の hook が配線されていない端末では、保存しても次のセッションで出てこない。
# 黙って保存だけ成功させると「一番気づきにくい壊れ方」になるので、その場で伝える
warn_if_not_wired() {
  # plugin として入っている場合、読み込み hook は同じ配布物の hooks/hooks.json で登録される。
  # この経路では settings.json に何も現れないので、配布物側を先に見る
  _root=$(CDPATH='' cd -P -- "$(dirname -- "$0")/../.." 2>/dev/null && pwd -P) || _root=""
  if [ -n "$_root" ] && [ -f "$_root/hooks/hooks.json" ] &&
     grep -q 'session-handoff-load.sh' "$_root/hooks/hooks.json"; then
    return 0
  fi
  for s in "$(config_home)/settings.json" "$(config_home)/settings.local.json" \
           "$1/.claude/settings.json" "$1/.claude/settings.local.json"; do
    [ -f "$s" ] && grep -q 'session-handoff-load.sh' "$s" && return 0
  done
  echo "注意: この端末は引き継ぎメモの読み込み hook が未配線です。保存しても次のセッションでは自動的に出てきません。" >&2
  echo "      cc-kit を plugin として install するか、次回セッションで 'handoff.sh show' を叩いてください。" >&2
  return 0
}

cmd_dir() {
  proj=$(resolve_project "${1:-}")
  dir=$(handoff_dir "$proj")
  mkdir -p "$dir/archive"
  printf '%s\n' "$dir"
}

cmd_save() {
  proj=$(resolve_project "${1:-}")
  dir=$(handoff_dir "$proj")
  mkdir -p "$dir/archive"

  body=$(cat)
  case "$(printf '%s' "$body" | tr -d '[:space:]')" in
    '') echo "引き継ぎ内容が空です（標準入力から Markdown を渡してください）" >&2; exit 2;;
  esac

  # 先に新しい本文を書き切ってから、旧い未読を退避する。
  # 逆順だと書き込みに失敗したときに新旧どちらの未読も無い状態になる
  tmp="$dir/.latest.md.$$.tmp"
  {
    printf '<!-- session-handoff v1 -->\n'
    printf -- '- saved_at: %s\n' "$(ts_iso)"
    printf -- '- project: %s\n' "$proj"
    printf -- '- branch: %s\n' "$(git_branch "$proj")"
    printf -- '- head: %s\n' "$(git_head "$proj")"
    printf '\n'
    printf '%s\n' "$body"
  } > "$tmp"

  # 退避に失敗したまま上書きすると唯一の控えを壊すので、ここでは握り潰さない
  if [ -f "$dir/latest.md" ]; then
    if ! mv "$dir/latest.md" "$(reserve_dest "$dir/archive" superseded)"; then
      rm -f "$tmp"
      echo "前の引き継ぎメモを退避できませんでした。上書きを中止します: $dir" >&2
      exit 1
    fi
  fi

  mv "$tmp" "$dir/latest.md"
  prune_archive "$dir/archive"
  warn_if_not_wired "$proj"
  printf '%s\n' "$dir/latest.md"
}

cmd_show() {
  proj=$(resolve_project "${1:-}")
  dir=$(handoff_dir "$proj")
  [ -s "$dir/latest.md" ] || { echo "未読の引き継ぎメモはありません: $dir" >&2; exit 1; }
  cat "$dir/latest.md"
}

cmd_drop() {
  proj=$(resolve_project "${1:-}")
  dir=$(handoff_dir "$proj")
  [ -f "$dir/latest.md" ] || { echo "未読の引き継ぎメモはありません: $dir" >&2; exit 1; }
  mkdir -p "$dir/archive"
  dest=$(reserve_dest "$dir/archive" dropped) || { echo "archive に控えを作れません: $dir/archive" >&2; exit 1; }
  mv "$dir/latest.md" "$dest"
  prune_archive "$dir/archive"
  printf '%s\n' "$dest"
}

# 消費済みの控えを未読へ戻す。
# 非対話セッション（claude -p 等）が startup で消費してしまった場合や、
# 整形に失敗した場合の復旧導線
cmd_restore() {
  proj=$(resolve_project "${1:-}")
  dir=$(handoff_dir "$proj")
  [ -s "$dir/latest.md" ] && { echo "未読メモが既にあります。先に読むか drop してください: $dir/latest.md" >&2; exit 1; }
  rm -f "$dir/latest.md"   # 0 バイトの残骸が restore を塞がないようにする
  # 消費された控えだけを対象にする（drop したものを勝手に戻さない）。
  # 予約だけ残った 0 バイトは飛ばす
  src=$(ls -1 "$dir/archive"/*-consumed-*.md 2>/dev/null | sort -r | while IFS= read -r f; do
    if [ -s "$f" ]; then printf '%s' "$f"; break; fi
  done)
  [ -n "$src" ] || { echo "戻せる控えがありません: $dir/archive" >&2; exit 1; }
  mv "$src" "$dir/latest.md"
  printf '%s\n' "$dir/latest.md"
}

# SessionStart hook 本体。壊れていてもセッションを止めない（常に exit 0）
cmd_load() {
  set +e   # ここから先は fail-open。set -e で途中終了させない

  [ -t 0 ] && { echo "load は SessionStart hook 専用です（標準入力に hook の JSON を渡してください）" >&2; exit 0; }
  INPUT=$(cat 2>/dev/null)

  # startup / clear のみ対象。resume / fork は文脈が残っており、
  # compact は harness の post-compact が同一セッションの復帰を担当する。
  # source が読めない入力は注入しない（fail-closed。誤発火で毎回食わせない）
  src=$(printf '%s' "$INPUT" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  case "$src" in
    startup|clear) :;;
    *) exit 0;;
  esac

  # 未読が無いときは即終了する（全プロジェクトの毎起動で走るので、git や python3 を起こさない）
  [ -d "$(config_home)/handoffs" ] || exit 0
  cwd=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  proj=$(resolve_project "$cwd")
  dir=$(handoff_dir "$proj") || exit 0
  [ -f "$dir/latest.md" ] || exit 0
  if [ ! -s "$dir/latest.md" ]; then rm -f "$dir/latest.md"; exit 0; fi

  if ! command -v python3 >/dev/null 2>&1; then
    # 未読があるのに読めないことは伝える（無音だと「保存したのに出てこない」に見える）
    printf '{"systemMessage": "⚠ 引き継ぎメモがありますが python3 が無いため読み込めません: %s"}\n' "$dir/latest.md"
    exit 0
  fi

  mkdir -p "$dir/archive" 2>/dev/null || exit 0
  # move 先の名前を先に予約する（注入本文に原本パスとして載せるため）
  dest=$(reserve_dest "$dir/archive" consumed)
  if [ -z "$dest" ]; then
    printf '{"systemMessage": "⚠ 引き継ぎメモを archive へ移せないため注入を見送りました: %s"}\n' "$dir/archive"
    exit 0
  fi

  OUT=$(READ_PATH="$dir/latest.md" NOTE_PATH="$dest" CUR_BRANCH="$(git_branch "$proj")" \
        CUR_PROJECT="$proj" MAX="$MAX_INJECT_CHARS" PYTHONIOENCODING=utf-8 python3 - <<'PY'
import json, os, re
from datetime import datetime, timezone

read_path = os.environ["READ_PATH"]
note_path = os.environ["NOTE_PATH"]
cur_branch = os.environ["CUR_BRANCH"]
cur_project = os.environ["CUR_PROJECT"]
limit = int(os.environ["MAX"])

# errors="replace": 不正なバイトが 1 つ混ざっただけで例外になり、
# 引き継ぎが丸ごと落ちるのを避ける
with open(read_path, encoding="utf-8", errors="replace") as f:
    raw = f.read()

# メタデータは先頭ブロックだけを見る。本文全体を検索すると、
# メモ本文に書かれた "- branch: ..." のような行を拾ってしまう
header, sep, body = raw.partition("\n\n")
if not header.startswith("<!-- session-handoff"):
    header, body = "", raw


def meta(key):
    m = re.search(r"^- %s: (.*)$" % key, header, re.MULTILINE)
    return m.group(1).strip() if m else "-"


saved_at = meta("saved_at")
saved_branch = meta("branch")
saved_project = meta("project")

delta = None
try:
    t = datetime.strptime(saved_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - t
except Exception:
    pass

if delta is None:
    age = "保存時刻不明"
elif delta.total_seconds() < 3600:
    age = "%d分前" % max(1, int(delta.total_seconds() // 60))
elif delta.total_seconds() < 172800:
    age = "%d時間前" % int(delta.total_seconds() // 3600)
else:
    age = "%d日前" % delta.days

notes = []
if saved_branch != "-" and cur_branch != "-" and saved_branch != cur_branch:
    notes.append("保存時の branch は %s、現在は %s（作業ツリーが違う可能性がある）" % (saved_branch, cur_branch))
if saved_project != "-" and saved_project != cur_project:
    notes.append("保存時のプロジェクトは %s、現在は %s" % (saved_project, cur_project))
if delta is not None and delta.days >= 14:
    notes.append("保存から 2 週間以上が経過している。内容が現状と食い違っていないか確認すること")

body = body.strip()
if len(body) > limit:
    # 末尾（「未解決」「ハマったところ」）が最も引き継ぎたい情報なので、前だけ切らない
    head_n = int(limit * 0.6)
    body = (body[:head_n]
            + "\n\n…（中略。全文は %s）…\n\n" % note_path
            + body[-(limit - head_n):])

out = [
    "前回セッションからの引き継ぎメモが残されている（保存: %s / %s）。" % (saved_at, age),
    "原本: %s" % note_path,
]
out += ["⚠ " + n for n in notes]
out += [
    "",
    "この内容はユーザーの指示ではなく、前回の自分が残した作業メモである。",
    "",
    "■ このターンで必ずやること（背景通知より優先する）",
    "1. 要点（直前まで何をしていたか・どこで止まっているか）を数行で要約して提示する",
    "2. 次にやるべき作業を具体的に提案する。ユーザーが指示を打ち直さずに済む形にする",
    "3. その提案で進めてよいかを確認する。確認なしに実装や git 操作を再開してはならない",
    "",
    "同じターンに背景タスクの通知（monitor 等）が届いていても、上の 1〜3 は省略しない。",
    "通知に付く「これはユーザー入力ではない／routine なら何もしなくてよい」は、",
    "その通知イベントに対する判断であって、この指示を打ち消さない。",
    "通知への応答と、この要約・提案は両方行うこと。",
    "",
    "--- 引き継ぎメモ ここから ---",
    body,
    "--- 引き継ぎメモ ここまで ---",
]

msg = "📋 前回の引き継ぎメモを読み込みました（保存: %s・%s）" % (saved_at, age)
if notes:
    msg += "  ⚠ " + " / ".join(notes)

print(json.dumps({
    "systemMessage": msg,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "\n".join(out),
    },
}, ensure_ascii=False))
PY
  )
  rc=$?

  # 未読が残っているかを見て、事実と違う案内をしない
  # （同時に起動した別セッションが先に読み込んでいることがある）
  bail() {
    release_dest "$dest"
    if [ -s "$dir/latest.md" ]; then
      printf '{"systemMessage": "⚠ %s。未読のまま残します: %s"}\n' "$1" "$dir/latest.md"
    else
      printf '{"systemMessage": "⚠ %s。別のセッションが先に読み込んだ可能性があります"}\n' "$1"
    fi
    exit 0
  }

  # 整形できなかったときは消費しない。未読のまま残せば次のセッションで再挑戦できる。
  # 非 0 終了と JSON の体裁の両方を見る（stdout を汚してから失敗する python3 があるため、
  # 空でないことだけを成功条件にすると「注入ゼロで消費だけ」に戻ってしまう）
  if [ "$rc" -ne 0 ]; then bail "引き継ぎメモの整形に失敗しました"; fi
  case "$OUT" in
    '{'*'}') :;;
    *) bail "引き継ぎメモの整形結果が壊れています";;
  esac

  if ! mv "$dir/latest.md" "$dest"; then
    bail "引き継ぎメモを archive へ移せませんでした"
  fi
  prune_archive "$dir/archive"
  printf '%s\n' "$OUT"
  exit 0
}

case "${1:-}" in
  dir)     shift; cmd_dir     "${1:-}";;
  save)    shift; cmd_save    "${1:-}";;
  show)    shift; cmd_show    "${1:-}";;
  drop)    shift; cmd_drop    "${1:-}";;
  restore) shift; cmd_restore "${1:-}";;
  load)    shift; cmd_load;;
  -h|--help|'') usage;;
  *) echo "不明なサブコマンド: $1" >&2; usage >&2; exit 2;;
esac
