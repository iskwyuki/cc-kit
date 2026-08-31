#!/bin/sh
# tests: wt-up.sh / wt-down.sh の統合スモーク（Plans 6.3 / §6・§7・§10）
# 一時 repo で wt-new→wt-up→health 緑→wt-down→wt-rm を一巡させる。
#   - 主経路（常時実行）: health.command モード。外部依存なしで決定的。
#     ポート採番（.dev/offset 永続化）・env 式注入・pre_start/post_start フック・
#     ログ集約・停止までを検証する。
#   - 追加経路（python3+curl があれば実行）: 実 HTTP サーバを起動し health.url で
#     ポーリング → 稼働中の 2 本目が別 offset を採ること（ポート衝突自動回避）を E2E で確認。
set -u
FAIL=0
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NEW="$BASE/skills/wt-parallel/scripts/wt-new.sh"
UP="$BASE/skills/wt-parallel/scripts/wt-up.sh"
DOWN="$BASE/skills/wt-parallel/scripts/wt-down.sh"
RM="$BASE/skills/wt-parallel/scripts/wt-rm.sh"

fail() { echo "FAIL: $1"; FAIL=1; }
for f in "$NEW" "$UP" "$DOWN" "$RM"; do
  [ -f "$f" ] || { echo "FAIL: $f が無い"; echo "test-wt-startup: FAILED"; exit 1; }
done

TMP=$(mktemp -d)

# 実端末の git 設定を絶対に触らせない。HOME だけでは system 設定が残るため
# GIT_CONFIG_GLOBAL / GIT_CONFIG_SYSTEM も差し替える（過去に ~/.gitconfig を汚した事故がある）。
export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
export GIT_CONFIG_SYSTEM="$TMP/gitconfig-system"
: > "$GIT_CONFIG_GLOBAL"
: > "$GIT_CONFIG_SYSTEM"
export WT_SKIP_PLUGIN_REGISTER=1

# ══════════════════════════════════════════════════════════════
# 主経路: health.command モードのフルライフサイクル
# ══════════════════════════════════════════════════════════════
SRC="$TMP/src"
mkdir -p "$SRC"
cat > "$TMP/manifest-cmd.yaml" <<'EOF'
ports:
  check: [3000, 8000]
env:
  APP_PORT: "$((3000 + WT_OFFSET))"
hooks:
  pre_start: "echo prestart-$APP_PORT > .dev/pre.marker"
  post_start: "echo poststart > .dev/post.marker"
start: "echo booting; ( sleep 0.4; : > .dev/ready ) & exec sleep 30"
health:
  command: "test -f .dev/ready"
  timeout: 15
EOF
(
  cd "$SRC"
  git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
  git config user.email t@t; git config user.name t
  echo hi > README.md
  cp "$TMP/manifest-cmd.yaml" .wt-parallel.yaml
  git add README.md .wt-parallel.yaml
  git commit -q -m init
)

WT=$(cd "$SRC" && sh "$NEW" feature/up-cmd 2>/dev/null); RC=$?
{ [ "$RC" -eq 0 ] && [ -d "$WT" ]; } || { fail "cmd: wt-new 失敗 (rc=$RC path=$WT)"; }

if [ -d "$WT" ]; then
  UPERR="$TMP/up.err"
  (cd "$WT" && sh "$UP" >"$TMP/up.out" 2>"$UPERR"); RC=$?
  [ "$RC" -eq 0 ] || fail "cmd: wt-up exit 0 期待 got $RC ($(cat "$UPERR"))"

  # ポート採番: .dev/offset が永続化され、env 注入が offset に一致する
  [ -f "$WT/.dev/offset" ] || fail "cmd: .dev/offset 未永続化"
  OFFSET=$(cat "$WT/.dev/offset" 2>/dev/null || echo "")
  case "$OFFSET" in ''|*[!0-9]*) fail "cmd: offset が数値でない ($OFFSET)" ;; esac
  if [ -n "$OFFSET" ]; then
    EXPECT_PORT=$((3000 + OFFSET))
    [ -f "$WT/.dev/pre.marker" ] || fail "cmd: pre_start フック未実行"
    grep -qxF "prestart-$EXPECT_PORT" "$WT/.dev/pre.marker" 2>/dev/null \
      || fail "cmd: env(APP_PORT) 注入が offset と不一致（want prestart-$EXPECT_PORT got $(cat "$WT/.dev/pre.marker" 2>/dev/null))"
  fi

  # start がバックグラウンド起動しログが集約される
  LOG=$(ls "$WT/.dev/logs/"*.log 2>/dev/null | head -1)
  [ -n "$LOG" ] && [ -f "$LOG" ] || fail "cmd: .dev/logs にログが無い"
  [ -n "$LOG" ] && grep -q booting "$LOG" 2>/dev/null || fail "cmd: start の出力がログに無い"

  # health 緑の後にだけ post_start が走る
  [ -f "$WT/.dev/ready" ] || fail "cmd: start が readiness を作っていない"
  [ -f "$WT/.dev/post.marker" ] || fail "cmd: post_start フック未実行（health 緑後）"

  # PID 記録・プロセス生存・提示（ログパス）
  [ -f "$WT/.dev/pid" ] || fail "cmd: .dev/pid 未記録"
  PID=$(cat "$WT/.dev/pid" 2>/dev/null || echo "")
  case "$PID" in ''|*[!0-9]*) fail "cmd: pid が数値でない ($PID)" ;; *) kill -0 "$PID" 2>/dev/null || fail "cmd: 起動プロセスが生存していない" ;; esac
  grep -q "\.dev/logs" "$UPERR" 2>/dev/null || fail "cmd: ログパスの提示が無い"

  # wt-down: 停止のみ（worktree は残す）
  (cd "$WT" && sh "$DOWN" >/dev/null 2>&1); RC=$?
  [ "$RC" -eq 0 ] || fail "cmd: wt-down exit 0 期待 got $RC"
  if [ -n "${PID:-}" ]; then
    i=0; while [ "$i" -lt 25 ] && kill -0 "$PID" 2>/dev/null; do i=$((i+1)); sleep 0.2; done
    kill -0 "$PID" 2>/dev/null && fail "cmd: wt-down 後もプロセスが生存"
  fi
  [ -f "$WT/.dev/pid" ] && fail "cmd: wt-down 後も .dev/pid が残存" || true
  [ -d "$WT" ] || fail "cmd: wt-down が worktree を消した（停止のみのはず）"

  # 二重停止は冪等（起動記録なしでも exit 0）
  (cd "$WT" && sh "$DOWN" >/dev/null 2>&1) || fail "cmd: wt-down は起動記録なしでも exit 0 のはず"

  (cd "$SRC" && sh "$RM" "$WT" >/dev/null 2>&1) || fail "cmd: wt-rm 失敗"
fi

# ── opt-in: start 宣言が無ければ案内して正常終了 ──
NOSTART="$TMP/nostart"
mkdir -p "$NOSTART"
(
  cd "$NOSTART"
  git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
  git config user.email t@t; git config user.name t
  printf 'base_ref: origin/main\n' > .wt-parallel.yaml
  echo hi > R.md; git add R.md .wt-parallel.yaml; git commit -q -m init
)
(cd "$NOSTART" && sh "$UP" >/dev/null 2>"$TMP/nostart.err"); RC=$?
[ "$RC" -eq 0 ] || fail "opt-in: start 無しの wt-up は exit 0 のはず (rc=$RC)"
grep -q "宣言" "$TMP/nostart.err" 2>/dev/null || fail "opt-in: 起動対象なしの案内が無い"

# ══════════════════════════════════════════════════════════════
# 追加経路: 実 HTTP・実ポートバインドで URL health とポート衝突回避（python3+curl 必須）
# ══════════════════════════════════════════════════════════════
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  BP=39517   # 使用中である見込みの低い基準ポート
  URLSRC="$TMP/urlsrc"
  mkdir -p "$URLSRC"
  cat > "$TMP/manifest-url.yaml" <<EOF
ports:
  check: [$BP]
env:
  PORT: "\$((${BP} + WT_OFFSET))"
start: "exec python3 -m http.server \${PORT} --bind 127.0.0.1"
health:
  url: "http://127.0.0.1:\${PORT}/"
  timeout: 20
EOF
  (
    cd "$URLSRC"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
    git config user.email t@t; git config user.name t
    echo hi > R.md
    cp "$TMP/manifest-url.yaml" .wt-parallel.yaml
    git add R.md .wt-parallel.yaml; git commit -q -m init
  )
  W1=$(cd "$URLSRC" && sh "$NEW" feature/url-1 2>/dev/null)
  W2=$(cd "$URLSRC" && sh "$NEW" feature/url-2 2>/dev/null)
  if [ -d "$W1" ] && [ -d "$W2" ]; then
    (cd "$W1" && sh "$UP" >/dev/null 2>"$TMP/w1.err"); RC1=$?
    [ "$RC1" -eq 0 ] || fail "url: 1本目 wt-up 失敗 rc=$RC1 ($(cat "$TMP/w1.err"))"
    # 1本目が基準ポートを実バインド中 → 2本目は別 offset を採るはず
    (cd "$W2" && sh "$UP" >/dev/null 2>"$TMP/w2.err"); RC2=$?
    [ "$RC2" -eq 0 ] || fail "url: 2本目 wt-up 失敗 rc=$RC2 ($(cat "$TMP/w2.err"))"
    O1=$(cat "$W1/.dev/offset" 2>/dev/null || echo x)
    O2=$(cat "$W2/.dev/offset" 2>/dev/null || echo y)
    [ "$O1" = "0" ] || fail "url: 1本目 offset は 0 のはず (got $O1)"
    [ "$O1" != "$O2" ] || fail "url: ポート衝突が回避されていない（offset が同一 ${O1}）"
    grep -q "127.0.0.1" "$TMP/w1.err" 2>/dev/null || fail "url: 解決済み health URL の提示が無い"
    (cd "$W1" && sh "$DOWN" >/dev/null 2>&1) || fail "url: 1本目 wt-down 失敗"
    (cd "$W2" && sh "$DOWN" >/dev/null 2>&1) || fail "url: 2本目 wt-down 失敗"
    (cd "$URLSRC" && sh "$RM" "$W1" >/dev/null 2>&1) || true
    (cd "$URLSRC" && sh "$RM" "$W2" >/dev/null 2>&1) || true
  else
    fail "url: worktree 作成に失敗（$W1 / ${W2}）"
  fi
else
  echo "SKIP: python3/curl 不在のため URL health・実ポート衝突 E2E を省略"
fi

cd /; rm -rf "$TMP"
if [ "$FAIL" -eq 0 ]; then echo "test-wt-startup: ALL PASS"; else echo "test-wt-startup: FAILED"; fi
exit "$FAIL"
