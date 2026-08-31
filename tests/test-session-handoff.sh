#!/bin/bash
# tests: skills/session-handoff/handoff.sh と hooks/session-handoff-load.sh
# ネットワーク非依存。fake な CLAUDE_CONFIG_DIR と一時 git リポジトリで、
# 保存 → 次セッションでの注入 → 二度目は出ない、までを通しで検証する。
# 「注入できたときだけ消費する」不変条件（失敗時は未読のまま残す）も対象。
set -u
FAIL=0
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
HANDOFF="$ROOT/skills/session-handoff/handoff.sh"
HOOK="$ROOT/hooks/session-handoff-load.sh"
TMP=$(mktemp -d)

# 実端末の git 設定を絶対に触らせない。HOME だけでは system 設定が残るため
# GIT_CONFIG_GLOBAL / GIT_CONFIG_SYSTEM も差し替える（過去に ~/.gitconfig を汚した事故がある）。
export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
export GIT_CONFIG_SYSTEM="$TMP/gitconfig-system"
: > "$GIT_CONFIG_GLOBAL"
: > "$GIT_CONFIG_SYSTEM"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; FAIL=1; }

export CLAUDE_CONFIG_DIR="$TMP/claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
# 配線済みの端末を模す（未配線警告は Y) で別途検証する）
printf '{"hooks":{"SessionStart":[{"hooks":[{"command":"session-handoff-load.sh"}]}]}}\n' \
  > "$CLAUDE_CONFIG_DIR/settings.json"

PROJ="$TMP/proj"
mkdir -p "$PROJ/sub"
( cd "$PROJ" && git init -q . && git config user.email t@example.com && git config user.name t \
  && echo hello > f.txt && git add f.txt && git commit -qm init ) || fail "準備: git リポジトリを作れない"

save() { printf '%s\n' "$2" | sh "$HANDOFF" save "$1"; }
load() { # $1=cwd $2=source → hook を実行して JSON を返す
  printf '{"source":"%s","cwd":"%s"}' "$2" "$1" | bash "$HOOK" 2>/dev/null
}
dir_of() { sh "$HANDOFF" dir "$1"; }

# --- A) save: メタデータ付きで latest.md が 1 つできる ------------------------
OUT=$(save "$PROJ" "## ゴール
テスト用の引き継ぎ本文 ALPHA")
[ -s "$OUT" ] || fail "A: save が有効なパスを返さない: $OUT"
case "$OUT" in *"/latest.md") :;; *) fail "A: 返り値が latest.md でない: $OUT";; esac
grep -q '<!-- session-handoff v1 -->' "$OUT" || fail "A: バージョンマーカーが無い"
grep -q '^- saved_at: ' "$OUT" || fail "A: saved_at が付かない"
grep -qE '^- branch: (master|main)$' "$OUT" || fail "A: branch が記録されない"
grep -q 'ALPHA' "$OUT" || fail "A: 本文が保存されない"
# GNU stat の -f は「ファイルシステム情報」で成功してしまうため、-c を先に試す
[ "$(stat -c '%a' "$OUT" 2>/dev/null || stat -f '%Lp' "$OUT")" = "600" ] \
  || fail "A: メモが他ユーザーから読める権限になっている"

# --- B) show: 未読メモを読めて、読み込み済みにはしない ------------------------
sh "$HANDOFF" show "$PROJ" | grep -q ALPHA || fail "B: show で本文が出ない"
[ -s "$(dir_of "$PROJ")/latest.md" ] || fail "B: show が未読メモを消してしまった"

# --- C) load(resume / compact): 注入しない・未読は残る ------------------------
for s in resume compact fork; do
  OUT=$(load "$PROJ" "$s")
  [ -z "$OUT" ] || fail "C: $s で注入された: $OUT"
done
[ -s "$(dir_of "$PROJ")/latest.md" ] || fail "C: 未読メモが消えた"

# --- D) load(startup): 注入されて archive へ移る ------------------------------
OUT=$(load "$PROJ" startup)
printf '%s' "$OUT" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' 2>/dev/null \
  || fail "D: 出力が JSON として妥当でない: $OUT"
echo "$OUT" | grep -q '"hookEventName": *"SessionStart"' || fail "D: SessionStart の JSON でない: $OUT"
echo "$OUT" | grep -q 'ALPHA' || fail "D: 本文が注入されない: $OUT"
echo "$OUT" | grep -q '引き継ぎメモ' || fail "D: 案内文が無い: $OUT"
echo "$OUT" | grep -q 'session-handoff v1' && fail "D: メタデータブロックが本文に二重に載っている"
[ -e "$(dir_of "$PROJ")/latest.md" ] && fail "D: 注入後も未読メモが残っている"
ls "$(dir_of "$PROJ")"/archive/*-consumed-*.md >/dev/null 2>&1 || fail "D: archive に控えが残らない"

# --- E) 二度目は出ない（毎セッション注入され続けない） ------------------------
OUT=$(load "$PROJ" startup)
[ -z "$OUT" ] || fail "E: 未読が無いのに出力された: $OUT"

# --- F) clear でも注入される（/clear 直後の続行が主動線） ---------------------
save "$PROJ" "本文 BRAVO" >/dev/null
OUT=$(load "$PROJ" clear)
echo "$OUT" | grep -q 'BRAVO' || fail "F: clear で注入されない: $OUT"

# --- G) 同一秒の連続 save でも控えを 1 件も失わない ---------------------------
save "$PROJ" "本文 ONE" >/dev/null
save "$PROJ" "本文 TWO" >/dev/null
save "$PROJ" "本文 THREE" >/dev/null
D=$(dir_of "$PROJ")
grep -q THREE "$D/latest.md" || fail "G: 最新の本文が未読になっていない"
for w in ONE TWO; do
  grep -rq "$w" "$D/archive/" || fail "G: $w が archive から消えた（同一秒の上書き）"
done

# --- H) branch が変わっていると警告が併記される -------------------------------
save "$PROJ" "本文 GOLF" >/dev/null
OUT=$(load "$PROJ" startup)
echo "$OUT" | grep -q '作業ツリーが違う可能性' && fail "H: 同一 branch なのに差異警告が出た: $OUT"
save "$PROJ" "本文 HOTEL" >/dev/null
( cd "$PROJ" && git checkout -q -b other ) || fail "H: 準備 branch を作れない"
OUT=$(load "$PROJ" startup)
echo "$OUT" | grep -q '作業ツリーが違う可能性' || fail "H: branch 差異の警告が出ない: $OUT"

# --- I) プロジェクトごとに保存先が分かれる -----------------------------------
PROJ2="$TMP/proj2"; mkdir -p "$PROJ2"
save "$PROJ2" "本文 ECHO" >/dev/null
[ "$(dir_of "$PROJ")" != "$(dir_of "$PROJ2")" ] || fail "I: 別プロジェクトで保存先が同じ"
OUT=$(load "$PROJ" startup)
[ -z "$OUT" ] || fail "I: 別プロジェクトのメモが漏れて出た: $OUT"
OUT=$(load "$PROJ2" startup)
echo "$OUT" | grep -q ECHO || fail "I: 自プロジェクトのメモが出ない: $OUT"

# --- J) 長すぎる本文は切り詰めるが、末尾（未解決・ハマった所）は残す ----------
BIG=$(awk 'BEGIN{while(i++<20000) printf "x"}')
save "$PROJ" "$BIG
## 未解決
末尾マーカー TAILKEEP" >/dev/null
OUT=$(load "$PROJ" startup)
echo "$OUT" | grep -q '中略' || fail "J: 長文が切られていない"
echo "$OUT" | grep -q 'TAILKEEP' || fail "J: 切り詰めで末尾が落ちている"

# --- K) drop: 未読を破棄しても archive には残る ------------------------------
save "$PROJ" "本文 FOX" >/dev/null
sh "$HANDOFF" drop "$PROJ" >/dev/null || fail "K: drop が失敗した"
[ -e "$(dir_of "$PROJ")/latest.md" ] && fail "K: drop 後も未読が残っている"
grep -rq FOX "$(dir_of "$PROJ")/archive/" || fail "K: drop した内容が archive に残らない"

# --- L) 空・空白のみの入力は保存しない ---------------------------------------
for body in '' '   '; do
  if printf '%s' "$body" | sh "$HANDOFF" save "$PROJ" >/dev/null 2>&1; then
    fail "L: 空の引き継ぎが保存できてしまう（入力: '$body'）"
  fi
done

# --- M) hook 単体: handoff.sh が見つからなくても fail-open する ---------------
# リポジトリ外へ hook だけコピーし、相対解決もユーザースコープ解決も外れる状況を作る
STUB="$TMP/stubhooks"; mkdir -p "$STUB"
cp "$HOOK" "$STUB/session-handoff-load.sh"
OUT=$(printf '{"source":"startup","cwd":"%s"}' "$PROJ" \
  | HOME="$TMP/nohome" CLAUDE_CONFIG_DIR="$TMP/nohome/.claude" CLAUDE_PROJECT_DIR="$TMP/nohome" \
    bash "$STUB/session-handoff-load.sh" 2>&1)
RC=$?
[ "$RC" -eq 0 ] || fail "M: handoff.sh 不在で exit 0 にならない (rc=$RC)"
echo "$OUT" | grep -q '見つかりません' || fail "M: 実体欠落を伝えない: $OUT"

# --- N) slug が衝突しうるパスでも保存先が分かれる -----------------------------
mkdir -p "$TMP/w/a-b" "$TMP/w/a/b"
save "$TMP/w/a-b" "本文 COLLIDE-A" >/dev/null
save "$TMP/w/a/b" "本文 COLLIDE-B" >/dev/null
OUT=$(load "$TMP/w/a-b" startup)
echo "$OUT" | grep -q 'COLLIDE-A' || fail "N: 自分のメモが出ない: $OUT"
echo "$OUT" | grep -q 'COLLIDE-B' && fail "N: 別プロジェクトのメモが漏れた: $OUT"

# --- O) サブディレクトリから保存してもリポジトリ単位で往復する ----------------
( cd "$PROJ/sub" && printf '本文 SUBDIR\n' | sh "$HANDOFF" save ) >/dev/null
OUT=$(load "$PROJ" startup)
echo "$OUT" | grep -q 'SUBDIR' || fail "O: サブディレクトリ保存が repo root で読めない: $OUT"

# --- P) CLAUDE_PROJECT_DIR と cwd が食い違っても往復する ----------------------
( cd "$PROJ/sub" && CLAUDE_PROJECT_DIR="$PROJ" printf '本文 ENVMIX\n' | CLAUDE_PROJECT_DIR="$PROJ" sh "$HANDOFF" save ) >/dev/null
OUT=$(load "$PROJ/sub" startup)
echo "$OUT" | grep -q 'ENVMIX' || fail "P: cwd と CLAUDE_PROJECT_DIR の食い違いで読めない: $OUT"

# --- Q) 整形に失敗したら消費しない（未読のまま残す） --------------------------
# root では chmod 000 でも読めてしまうので、権限で失敗を作るこのケースは飛ばす
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1
if [ "$IS_ROOT" -eq 1 ]; then echo "SKIP: Q は root では検証できない"; else
save "$PROJ" "本文 KEEPME" >/dev/null
D=$(dir_of "$PROJ")
BEFORE=$(ls -1 "$D"/archive/*-consumed-*.md 2>/dev/null | wc -l | tr -d ' ')
chmod 000 "$D/latest.md"
OUT=$(load "$PROJ" startup)
chmod 600 "$D/latest.md" 2>/dev/null
[ -s "$D/latest.md" ] || fail "Q: 整形に失敗したのに未読が消えた"
echo "$OUT" | grep -q '整形に失敗' || fail "Q: 失敗が伝わらない: $OUT"
grep -q KEEPME "$D/latest.md" || fail "Q: 未読の内容が壊れた"
AFTER=$(ls -1 "$D"/archive/*-consumed-*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$BEFORE" = "$AFTER" ] || fail "Q: 失敗したのに consumed の控えが増えた（$BEFORE → $AFTER）"
fi   # Q の root スキップ終わり
D=$(dir_of "$PROJ")
[ -s "$D/latest.md" ] || save "$PROJ" "本文 KEEPME" >/dev/null

# --- R) source が読めない入力では注入しない（fail-closed） --------------------
OUT=$(echo '{}' | bash "$HOOK")
[ -z "$OUT" ] || fail "R: source 不明で注入された: $OUT"
[ -s "$D/latest.md" ] || fail "R: source 不明で未読が消えた"

# --- S) python3 が無い端末では未読を残して警告する ----------------------------
STUBBIN="$TMP/binstub"; mkdir -p "$STUBBIN"
for b in sh bash sed awk cksum git head cat dirname date ls mv rm mkdir chmod tr stat wc; do
  src=$(command -v "$b" 2>/dev/null) && ln -sf "$src" "$STUBBIN/$b"
done
OUT=$(printf '{"source":"startup","cwd":"%s"}' "$PROJ" | PATH="$STUBBIN" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'python3' || fail "S: python3 不在が伝わらない: $OUT"
[ -s "$D/latest.md" ] || fail "S: python3 不在で未読が消えた"

# --- T) restore: 消費された控えを未読へ戻す -----------------------------------
OUT=$(load "$PROJ" startup)
echo "$OUT" | grep -q KEEPME || fail "T: 準備の注入が効かない: $OUT"
[ -e "$D/latest.md" ] && fail "T: 準備の消費が効かない"
sh "$HANDOFF" restore "$PROJ" >/dev/null || fail "T: restore が失敗した"
grep -q KEEPME "$D/latest.md" || fail "T: restore で戻らない"
sh "$HANDOFF" drop "$PROJ" >/dev/null

# --- U) archive は直近 20 件に刈られる ----------------------------------------
PROJ3="$TMP/proj3"; mkdir -p "$PROJ3"
D3=$(dir_of "$PROJ3")
mkdir -p "$D3/archive"
i=0; while [ "$i" -lt 25 ]; do i=$((i + 1)); printf 'old %02d\n' "$i" > "$D3/archive/old-$i.md"; done
save "$PROJ3" "本文 PRUNE" >/dev/null
[ "$(ls -1 "$D3/archive"/*.md | wc -l | tr -d ' ')" -le 20 ] || fail "U: archive が 20 件に刈られない"

# --- V) archive へ移せないときは注入を見送り、未読を残す ----------------------
if [ "$IS_ROOT" -eq 1 ]; then echo "SKIP: V は root では検証できない"; else
save "$PROJ3" "本文 LOCKED" >/dev/null
chmod 500 "$D3/archive"
OUT=$(load "$PROJ3" startup)
chmod 700 "$D3/archive"
[ -s "$D3/latest.md" ] || fail "V: archive 不可で未読が消えた"
echo "$OUT" | grep -q 'archive' || fail "V: archive の失敗が伝わらない: $OUT"
fi   # root スキップの終わり

# --- X) 同時に 2 セッションが起動しても控えを壊さない -------------------------
PROJ4="$TMP/proj4"; mkdir -p "$PROJ4"
D4=$(dir_of "$PROJ4")
race_ok=1
i=0
while [ "$i" -lt 5 ]; do
  i=$((i + 1))
  rm -rf "$D4"; mkdir -p "$D4/archive"
  save "$PROJ4" "本文 RACE-$i" >/dev/null
  load "$PROJ4" startup >/dev/null 2>&1 &
  load "$PROJ4" startup >/dev/null 2>&1 &
  wait
  # 本文はどこか 1 箇所（未読か archive）に必ず残っていること
  if ! grep -rq "RACE-$i" "$D4" 2>/dev/null; then
    race_ok=0
    break
  fi
done
[ "$race_ok" -eq 1 ] || fail "X: 同時起動で控えが消えた（$i 回目）"

# --- Y) restore は 0 バイトの残骸や drop した控えを掴まない -------------------
PROJ5="$TMP/proj5"; mkdir -p "$PROJ5"
D5=$(dir_of "$PROJ5")
mkdir -p "$D5/archive"
save "$PROJ5" "本文 DROPPED" >/dev/null
sh "$HANDOFF" drop "$PROJ5" >/dev/null
sh "$HANDOFF" restore "$PROJ5" >/dev/null 2>&1 && fail "Y: drop した控えを restore が戻した"
save "$PROJ5" "本文 REAL" >/dev/null
load "$PROJ5" startup >/dev/null
: > "$D5/archive/29991231T235959Z-consumed-00.md"   # 未来日付の 0 バイト残骸
sh "$HANDOFF" restore "$PROJ5" >/dev/null || fail "Y: restore が失敗した"
grep -q REAL "$D5/latest.md" || fail "Y: 0 バイトの残骸を掴んだ"

# --- W) 配線の有無で save 時の警告を出し分ける --------------------------------
#
# 読み込み hook は plugin の hooks/hooks.json 経由で登録される（settings.json には現れない）。
# よって配線判定は「同じ配布物に読み込み hook が同梱されているか」を先に見る。
# settings.json だけを走査していた頃の実装は、plugin 環境で毎回誤警告を出していた。

# W-1) 配布物の中から叩く = 読み込み hook が同梱されている → 警告を出さない
ERR=$(printf '本文 WIRE1\n' | CLAUDE_CONFIG_DIR="$TMP/unwired" sh "$HANDOFF" save "$PROJ3" 2>&1 >/dev/null)
echo "$ERR" | grep -q '未配線' && fail "W-1: 配布物同梱の hook があるのに未配線と警告した: $ERR"

# W-2) 配布物の外へ skill だけコピーした状態 → 警告を出す
LONELY="$TMP/lonely/skills/session-handoff"
mkdir -p "$LONELY"
cp "$HANDOFF" "$LONELY/handoff.sh"
ERR=$(printf '本文 WIRE2\n' | CLAUDE_CONFIG_DIR="$TMP/unwired" sh "$LONELY/handoff.sh" save "$PROJ3" 2>&1 >/dev/null)
echo "$ERR" | grep -q '未配線' || fail "W-2: 未配線の警告が出ない: $ERR"

if [ "$FAIL" -eq 0 ]; then echo "PASS: tests/test-session-handoff.sh"; else echo "FAILED"; fi
exit "$FAIL"
