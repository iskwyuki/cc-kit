#!/bin/sh
# tests: skills/wt-parallel/scripts/wt-identity.sh の純粋関数（Plans 6.1 / §10）
# slug 正規化・strict-subset パーサ（scalar/list）・.dev/ 除外の冪等性・plugin 可用性判定を
# 副作用から切り離して検証する。既存 tests/test-pre-commit-gate.sh の型を踏襲。
set -u
FAIL=0
LIB="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/skills/wt-parallel/scripts/wt-identity.sh"

fail() { echo "FAIL: $1"; FAIL=1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (got '$1' want '$2')"; }

[ -f "$LIB" ] || { echo "FAIL: lib が無い: $LIB"; echo "test-wt-identity: FAILED"; exit 1; }
. "$LIB"

# ── slug 正規化 ─────────────────────────────
assert_eq "$(wt_slugify 'feature/Foo Bar')" "feature-foo-bar" "slug: path+space+case"
assert_eq "$(wt_slugify 'FIX-#29!!')"        "fix-29"          "slug: 記号圧縮+trim"
assert_eq "$(wt_slugify '  --xx--  ')"       "xx"              "slug: 前後ハイフン/空白 trim"
assert_eq "$(wt_slugify '@@@')"              "wt"              "slug: 空になったら wt にフォールバック"

TMP=$(mktemp -d)

# 実端末の git 設定を絶対に触らせない。HOME だけでは system 設定が残るため
# GIT_CONFIG_GLOBAL / GIT_CONFIG_SYSTEM も差し替える（過去に ~/.gitconfig を汚した事故がある）。
export GIT_CONFIG_GLOBAL="$TMP/gitconfig-global"
export GIT_CONFIG_SYSTEM="$TMP/gitconfig-system"
: > "$GIT_CONFIG_GLOBAL"
: > "$GIT_CONFIG_SYSTEM"

# ── strict-subset: トップレベルスカラ ───────────
cat > "$TMP/m.yaml" <<'EOF'
base_ref: origin/main
start: "pnpm dev"
other: 'single'  # trailing comment
notmine_base_ref: nope
EOF
assert_eq "$(wt_yaml_scalar "$TMP/m.yaml" base_ref)" "origin/main" "scalar: 素の値"
assert_eq "$(wt_yaml_scalar "$TMP/m.yaml" start)"    "pnpm dev"    "scalar: ダブルクォート剥がし"
assert_eq "$(wt_yaml_scalar "$TMP/m.yaml" other)"    "single"      "scalar: シングルクォート+コメント"
assert_eq "$(wt_yaml_scalar "$TMP/m.yaml" missing)"  ""            "scalar: 不在は空"
assert_eq "$(wt_yaml_scalar "$TMP/nope.yaml" start)" ""            "scalar: ファイル不在は空"

# ── strict-subset: ブロックリスト ──────────────
cat > "$TMP/l.yaml" <<'EOF'
inherit:
  - backend/.env
  - frontend/.env
start: x
EOF
GOT=$(wt_yaml_list "$TMP/l.yaml" inherit | tr '\n' ',')
assert_eq "$GOT" "backend/.env,frontend/.env," "list: 2 要素・次キーで停止"
assert_eq "$(wt_yaml_list "$TMP/l.yaml" missing)" "" "list: 不在キーは空"

# ── .dev/ 除外の冪等追記 ─────────────────────
wt_ensure_dev_ignored "$TMP/gitcommon"
wt_ensure_dev_ignored "$TMP/gitcommon"
CNT=$(grep -cxF '.dev/' "$TMP/gitcommon/info/exclude" 2>/dev/null || echo 0)
assert_eq "$CNT" "1" "exclude: .dev/ は一度だけ追記（冪等）"

# ── plugin 可用性判定 ───────────────────────
if ( WT_SKIP_PLUGIN_REGISTER=1; wt_plugin_available ); then fail "plugin: WT_SKIP=1 で無効化されるべき"; fi
if ( PATH=/nonexistent-xyz; wt_plugin_available ); then fail "plugin: 壊れた PATH（非 CC）で無効化されるべき"; fi
if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  wt_plugin_available || fail "plugin: claude+jq があれば有効のはず"
fi

# ── plugin 抽出（project 有効 ∧ user 未有効のみ・§10 単体テスト対象）──
if command -v jq >/dev/null 2>&1; then
  printf '{"enabledPlugins":{"user-shared@mk":true}}\n'                      > "$TMP/user.json"
  printf '{"enabledPlugins":{"proj-a@mk":true,"proj-off@mk":false}}\n'       > "$TMP/proj.json"
  printf '{"enabledPlugins":{"proj-b@mk":true,"user-shared@mk":true}}\n'     > "$TMP/proj.local.json"
  GOT=$(wt_plugins_to_register "$TMP/user.json" "$TMP/proj.json" "$TMP/proj.local.json" | tr '\n' ',')
  assert_eq "$GOT" "proj-a@mk,proj-b@mk," "plugins: project 有効かつ user 未有効のみ（user共有と false は除外）"
  assert_eq "$(wt_plugins_to_register "$TMP/user.json" "$TMP/nope.json" | tr '\n' ',')" "" "plugins: project 設定不在は空"
else
  echo "SKIP: jq 不在のため wt_plugins_to_register テストを省略"
fi

# ── wt_inherit_file: 正常コピー ＋ パストラバーサル拒否 ──
mkdir -p "$TMP/ir/root/s" "$TMP/ir/wt"
echo A > "$TMP/ir/root/s/f"
wt_inherit_file "$TMP/ir/root" "$TMP/ir/wt" "s/f" 2>/dev/null
[ -f "$TMP/ir/wt/s/f" ] || fail "inherit: 正常な相対パスがコピーされない"
W=$(wt_inherit_file "$TMP/ir/root" "$TMP/ir/wt" "../evil" 2>&1)
case "$W" in *スキップ*) ;; *) fail "inherit: ../ を含むパスが拒否されない" ;; esac
W=$(wt_inherit_file "$TMP/ir/root" "$TMP/ir/wt" "/etc/hostname" 2>&1)
case "$W" in *スキップ*) ;; *) fail "inherit: 絶対パスが拒否されない" ;; esac

# ══════════════════════════════════════════════════════════════
# Task 6.3（起動系）純粋関数: 2階層マップパーサ / flow list / 検証 /
#   offset 採番 / env 式展開サンドボックス（§5.1・§7・§12.3）
# ══════════════════════════════════════════════════════════════

# ── strict-subset: 2 階層マップ（env / health / hooks / ports）───
cat > "$TMP/mm.yaml" <<'EOF'
base_ref: origin/main
env:
  FRONTEND_PORT: "$((3000 + WT_OFFSET))"
  DATABASE_URL: "postgres://localhost/app_${WT_SLUG}"
ports:
  check: [3000, 8000]
health:
  url: "http://localhost:${FRONTEND_PORT}/health"
  timeout: 60
hooks:
  pre_start: "echo hi"
start: "run it"
EOF
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" env FRONTEND_PORT)" '$((3000 + WT_OFFSET))' "map: env.FRONTEND_PORT（クォート剥がし）"
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" env DATABASE_URL)" 'postgres://localhost/app_${WT_SLUG}' "map: env.DATABASE_URL"
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" health url)" 'http://localhost:${FRONTEND_PORT}/health' "map: health.url"
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" health timeout)" "60" "map: health.timeout（素の値）"
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" ports check)" "[3000, 8000]" "map: ports.check（flow list 生値）"
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" hooks pre_start)" "echo hi" "map: hooks.pre_start"
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" env MISSING)" "" "map: 不在サブキーは空"
assert_eq "$(wt_yaml_map_value "$TMP/mm.yaml" start url)" "" "map: スカラ親のサブキーは空"
assert_eq "$(wt_yaml_map_keys "$TMP/mm.yaml" env | tr '\n' ',')" "FRONTEND_PORT,DATABASE_URL," "map: env のキー列挙（宣言順）"
assert_eq "$(wt_yaml_map_keys "$TMP/mm.yaml" hooks | tr '\n' ',')" "pre_start," "map: hooks のキー列挙"

# ── inline flow list の分解 ────────────────────
assert_eq "$(wt_flow_items '[3000, 8000]' | tr '\n' ',')" "3000,8000," "flow: 2 要素"
assert_eq "$(wt_flow_items '[3000]' | tr '\n' ',')" "3000," "flow: 1 要素"
assert_eq "$(wt_flow_items '[]' | tr '\n' ',')" "" "flow: 空リスト"

# ── マニフェスト検証（範囲外構文の loud-error 拒否・§5.1）──
# 正常系: シェル && を含むクォート値は通る（誤検知しないこと）
cat > "$TMP/good.yaml" <<'EOF'
base_ref: origin/main
env:
  PORT: "$((3000 + WT_OFFSET))"
hooks:
  post_create: "uv sync && pnpm install"
start: "pnpm dev"
health:
  url: "http://localhost:${PORT}/"
  timeout: 60
EOF
wt_manifest_validate "$TMP/good.yaml" 2>/dev/null || fail "validate: 正常マニフェスト（&& 含む）が拒否された"

check_reject() { # <name> <heredoc-file>
  if wt_manifest_validate "$1" >/dev/null 2>&1; then fail "validate: $2 が拒否されない"; fi
}
printf 'a: 1\n\t- x\n'                 > "$TMP/tab.yaml";     check_reject "$TMP/tab.yaml" "タブインデント"
printf 'a: 1\n---\nb: 2\n'             > "$TMP/doc.yaml";     check_reject "$TMP/doc.yaml" "多文書 ---"
printf 'note: |\n  multi\n'            > "$TMP/blk.yaml";     check_reject "$TMP/blk.yaml" "block scalar |"
printf 'note: >\n  folded\n'           > "$TMP/fold.yaml";    check_reject "$TMP/fold.yaml" "block scalar >"
printf 'env: {a: b}\n'                 > "$TMP/flow.yaml";    check_reject "$TMP/flow.yaml" "flow map {}"
printf 'ports:\n  check: [1, [2]]\n'   > "$TMP/nest.yaml";    check_reject "$TMP/nest.yaml" "inline list 入れ子"
printf 'x: &anc 1\n'                   > "$TMP/anc.yaml";     check_reject "$TMP/anc.yaml" "anchor &"
printf 'x: *anc\n'                     > "$TMP/ali.yaml";     check_reject "$TMP/ali.yaml" "alias *"
printf 'health:\n  url:\n    deep: 1\n'> "$TMP/deep.yaml";    check_reject "$TMP/deep.yaml" "3 階層ネスト"
printf 'inherit:\n  - *anchor\n'       > "$TMP/lali.yaml";    check_reject "$TMP/lali.yaml" "リスト項目の alias *"
printf 'inherit:\n  - &anc x\n'        > "$TMP/lanc.yaml";    check_reject "$TMP/lanc.yaml" "リスト項目の anchor &"

# ── offset 採番（空きポート探索・wt_port_free をスタブ）──
# 3000/8000 を基準に、3000・8000・3001 を使用中とみなす → offset 2 が最小
wt_port_free() { case "$1" in 3000|8000|3001) return 1 ;; *) return 0 ;; esac; }
assert_eq "$(wt_find_offset 20 3000 8000)" "2" "offset: 最小の同時空き offset"
wt_port_free() { return 0; }
assert_eq "$(wt_find_offset 20 3000 8000)" "0" "offset: すべて空きなら 0"
wt_port_free() { return 1; }
if wt_find_offset 3 3000 >/dev/null 2>&1; then fail "offset: 全滅なら非ゼロで失敗すべき"; fi
unset -f wt_port_free 2>/dev/null || true
. "$LIB"   # 本物の wt_port_free を復元

# ── env 式展開サンドボックス（§12.3）──
export WT_OFFSET=5 WT_SLUG=foo FRONTEND_PORT=3005
assert_eq "$(wt_expand_value '$((3000 + WT_OFFSET))')" "3005" "expand: 算術（WT_OFFSET）"
assert_eq "$(wt_expand_value '$((2 * WT_OFFSET))')" "10" "expand: 算術（乗算）"
assert_eq "$(wt_expand_value 'postgres://localhost/app_${WT_SLUG}')" "postgres://localhost/app_foo" "expand: \${VAR}"
assert_eq "$(wt_expand_value 'http://localhost:${FRONTEND_PORT}/health')" "http://localhost:3005/health" "expand: 展開済み env 参照"
assert_eq "$(wt_expand_value 'p-$WT_SLUG-x')" "p-foo-x" "expand: 素の \$VAR"
assert_eq "$(wt_expand_value 'plain')" "plain" "expand: 置換なしはそのまま"
# サンドボックス: コマンド置換・backtick は loud-error 拒否
if wt_expand_value 'x$(whoami)' >/dev/null 2>&1; then fail "expand: コマンド置換 \$(...) を拒否すべき"; fi
if wt_expand_value 'x`id`'      >/dev/null 2>&1; then fail "expand: backtick を拒否すべき"; fi
if wt_expand_value '$(( $(id) ))' >/dev/null 2>&1; then fail "expand: 算術内のコマンド置換を拒否すべき"; fi
if wt_expand_value '${VAR:-default}' >/dev/null 2>&1; then fail "expand: パラメータ展開 \${VAR:-default} は非対応・拒否すべき"; fi
unset WT_OFFSET WT_SLUG FRONTEND_PORT

cd /; rm -rf "$TMP"
if [ "$FAIL" -eq 0 ]; then echo "test-wt-identity: ALL PASS"; else echo "test-wt-identity: FAILED"; fi
exit "$FAIL"
