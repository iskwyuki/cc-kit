#!/bin/sh
# tests: wt-rm.sh の Stage 2 破棄フロー（Plans 6.4 / §6・§8・§9）
#   A) pre_rm フック実行 + WT_SLUG 注入（失敗は警告どまりで破棄続行）
#   B) 破棄前に起動プロセスを停止（wt-up 済みの worktree を wt-rm で止めてから remove）
#   C) plugin 対称解除（install した分だけ uninstall・ダングリング無し）を stub claude で決定的に検証
set -u
FAIL=0
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NEW="$BASE/skills/wt-parallel/scripts/wt-new.sh"
UP="$BASE/skills/wt-parallel/scripts/wt-up.sh"
RM="$BASE/skills/wt-parallel/scripts/wt-rm.sh"

fail() { echo "FAIL: $1"; FAIL=1; }
for f in "$NEW" "$UP" "$RM"; do
  [ -f "$f" ] || { echo "FAIL: $f が無い"; echo "test-wt-teardown: FAILED"; exit 1; }
done

TMP=$(mktemp -d)

# 実端末の git 設定を絶対に触らせない。HOME だけでは system 設定が残るため
# GIT_CONFIG_GLOBAL / GIT_CONFIG_SYSTEM も差し替える（過去に ~/.gitconfig を汚した事故がある）。
export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
export GIT_CONFIG_SYSTEM="$TMP/gitconfig-system"
: > "$GIT_CONFIG_GLOBAL"
: > "$GIT_CONFIG_SYSTEM"

# ══════════════════════════════════════════════════════════════
# A) pre_rm フック + WT_SLUG 注入
# ══════════════════════════════════════════════════════════════
SA="$TMP/a/src"
mkdir -p "$SA"
cat > "$TMP/manifest-a.yaml" <<'EOF'
hooks:
  pre_rm: "echo removed-${WT_SLUG} > ../prerm.marker"
EOF
(
  cd "$SA"
  git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
  git config user.email t@t; git config user.name t
  echo hi > R.md; cp "$TMP/manifest-a.yaml" .wt-parallel.yaml
  git add R.md .wt-parallel.yaml; git commit -q -m init
)
WA=$(cd "$SA" && WT_SKIP_PLUGIN_REGISTER=1 sh "$NEW" feature/teardown 2>/dev/null)
if [ -d "$WA" ]; then
  SLUG=$(cat "$WA/.dev/slug" 2>/dev/null || echo "")
  (cd "$SA" && WT_SKIP_PLUGIN_REGISTER=1 sh "$RM" "$WA" >/dev/null 2>&1); RC=$?
  [ "$RC" -eq 0 ] || fail "A: wt-rm exit 0 期待 got $RC"
  [ -d "$WA" ] && fail "A: worktree が残存" || true
  MK="$TMP/a/prerm.marker"   # worktree の親（dirname(src) = $TMP/a）に書かれる
  [ -f "$MK" ] || fail "A: pre_rm フックが実行されていない（marker 無し）"
  [ -f "$MK" ] && grep -qxF "removed-$SLUG" "$MK" 2>/dev/null \
    || fail "A: pre_rm に WT_SLUG が注入されていない（want removed-$SLUG got $(cat "$MK" 2>/dev/null))"
else
  fail "A: wt-new 失敗（${WA}）"
fi

# ── pre_rm 失敗でも破棄は続行（§6: 警告どまり）──
SF="$TMP/f/src"; mkdir -p "$SF"
printf 'hooks:\n  pre_rm: "exit 3"\n' > "$TMP/manifest-f.yaml"
(
  cd "$SF"
  git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
  git config user.email t@t; git config user.name t
  echo hi > R.md; cp "$TMP/manifest-f.yaml" .wt-parallel.yaml
  git add R.md .wt-parallel.yaml; git commit -q -m init
)
WF=$(cd "$SF" && WT_SKIP_PLUGIN_REGISTER=1 sh "$NEW" feature/prerm-fail 2>/dev/null)
if [ -d "$WF" ]; then
  (cd "$SF" && WT_SKIP_PLUGIN_REGISTER=1 sh "$RM" "$WF" >/dev/null 2>&1); RC=$?
  [ "$RC" -eq 0 ] || fail "A2: pre_rm 失敗でも wt-rm は破棄続行し exit 0 のはず (rc=$RC)"
  [ -d "$WF" ] && fail "A2: pre_rm 失敗で worktree が残存（破棄されていない）" || true
fi

# ══════════════════════════════════════════════════════════════
# B) 破棄前にプロセス停止（wt-up 済みを wt-rm で止めてから remove）
# ══════════════════════════════════════════════════════════════
SB="$TMP/b/src"; mkdir -p "$SB"
cat > "$TMP/manifest-b.yaml" <<'EOF'
start: "( sleep 0.3; : > .dev/ready ) & exec sleep 30"
health:
  command: "test -f .dev/ready"
  timeout: 15
hooks:
  pre_rm: "echo bye > ../prerm-b.marker"
EOF
(
  cd "$SB"
  git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
  git config user.email t@t; git config user.name t
  echo hi > R.md; cp "$TMP/manifest-b.yaml" .wt-parallel.yaml
  git add R.md .wt-parallel.yaml; git commit -q -m init
)
WB=$(cd "$SB" && WT_SKIP_PLUGIN_REGISTER=1 sh "$NEW" feature/rm-stop 2>/dev/null)
if [ -d "$WB" ]; then
  (cd "$WB" && sh "$UP" >/dev/null 2>&1); RC=$?
  PID=$(cat "$WB/.dev/pid" 2>/dev/null || echo "")
  { [ "$RC" -eq 0 ] && [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; } || fail "B: wt-up でプロセスが起動していない"
  (cd "$SB" && WT_SKIP_PLUGIN_REGISTER=1 sh "$RM" "$WB" >/dev/null 2>&1); RC=$?
  [ "$RC" -eq 0 ] || fail "B: wt-rm exit 0 期待 got $RC"
  if [ -n "$PID" ]; then
    i=0; while [ "$i" -lt 25 ] && kill -0 "$PID" 2>/dev/null; do i=$((i+1)); sleep 0.2; done
    kill -0 "$PID" 2>/dev/null && fail "B: wt-rm が起動プロセスを停止していない（pid 生存）"
  fi
  [ -f "$TMP/b/prerm-b.marker" ] || fail "B: pre_rm が実行されていない"
  [ -d "$WB" ] && fail "B: worktree が残存" || true
else
  fail "B: wt-new 失敗（${WB}）"
fi

# ══════════════════════════════════════════════════════════════
# C) plugin 対称解除（stub claude・install と同数の uninstall = ダングリング無し）
# ══════════════════════════════════════════════════════════════
if command -v jq >/dev/null 2>&1; then
  STUB="$TMP/bin"; mkdir -p "$STUB"
  LOGF="$TMP/claude-calls.log"; : > "$LOGF"
  cat > "$STUB/claude" <<EOF
#!/bin/sh
echo "\$*" >> "$LOGF"
exit 0
EOF
  chmod +x "$STUB/claude"

  SC="$TMP/c/src"; mkdir -p "$SC/.claude"
  (
    cd "$SC"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
    git config user.email t@t; git config user.name t
    echo hi > R.md
    printf '{"enabledPlugins":{"demo-a@mk":true,"demo-b@mk":true}}\n' > .claude/settings.local.json
    git add R.md; git commit -q -m init
  )
  # stub claude + 本物 jq。WT_SKIP は unset（install を走らせる）。user 設定は空にして全て project 対象に。
  WC=$(cd "$SC" && PATH="$STUB:$PATH" HOME="$TMP/fakehome" sh "$NEW" feature/plugin-sym 2>/dev/null)
  if [ -d "$WC" ]; then
    [ -f "$WC/.dev/plugins" ] || fail "C: install した plugin が .dev/plugins に記録されていない"
    # worktree は wt-rm で消えるため、記録を先にスナップショットする
    cp "$WC/.dev/plugins" "$TMP/c-plugins-snapshot" 2>/dev/null || : > "$TMP/c-plugins-snapshot"
    INS=$(grep -c 'plugin install' "$LOGF" 2>/dev/null); INS=${INS:-0}
    [ "$INS" -ge 1 ] || fail "C: claude plugin install が呼ばれていない (ins=$INS)"
    : > "$LOGF"   # rm 時の uninstall だけを見る
    (cd "$SC" && PATH="$STUB:$PATH" HOME="$TMP/fakehome" sh "$RM" "$WC" >/dev/null 2>&1); RC=$?
    [ "$RC" -eq 0 ] || fail "C: wt-rm exit 0 期待 got $RC"
    # .dev/plugins に記録された各 plugin について uninstall が対称に呼ばれること（ダングリング無し）
    while IFS= read -r plug; do
      [ -n "$plug" ] || continue
      grep -qF "plugin uninstall $plug --scope project" "$LOGF" \
        || fail "C: $plug の対称 uninstall が呼ばれていない（ダングリング）"
    done < "$TMP/c-plugins-snapshot" 2>/dev/null
    [ -d "$WC" ] && fail "C: worktree が残存" || true
  else
    fail "C: wt-new 失敗（${WC}）"
  fi
else
  echo "SKIP: jq 不在のため plugin 対称解除テストを省略"
fi

# ══════════════════════════════════════════════════════════════
# D) strict-subset 外マニフェスト → pre_rm スキップ + 破棄続行（§5.1・§6）
# ══════════════════════════════════════════════════════════════
SD="$TMP/d/src"; mkdir -p "$SD"
cat > "$TMP/manifest-d.yaml" <<'EOF'
env: {a: b}
hooks:
  pre_rm: "echo ran > ../prerm-d.marker"
EOF
(
  cd "$SD"
  git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main; }
  git config user.email t@t; git config user.name t
  echo hi > R.md; cp "$TMP/manifest-d.yaml" .wt-parallel.yaml
  git add R.md .wt-parallel.yaml; git commit -q -m init
)
WD=$(cd "$SD" && WT_SKIP_PLUGIN_REGISTER=1 sh "$NEW" feature/rm-invalid 2>/dev/null)
if [ -d "$WD" ]; then
  (cd "$SD" && WT_SKIP_PLUGIN_REGISTER=1 sh "$RM" "$WD" >/dev/null 2>&1); RC=$?
  [ "$RC" -eq 0 ] || fail "D: strict-subset 外でも wt-rm は破棄続行し exit 0 のはず (rc=$RC)"
  [ -f "$TMP/d/prerm-d.marker" ] && fail "D: 無効マニフェストで pre_rm がスキップされていない" || true
  [ -d "$WD" ] && fail "D: worktree が残存（破棄されていない）" || true
else
  fail "D: wt-new 失敗（${WD}）"
fi

cd /; rm -rf "$TMP"
if [ "$FAIL" -eq 0 ]; then echo "test-wt-teardown: ALL PASS"; else echo "test-wt-teardown: FAILED"; fi
exit "$FAIL"
