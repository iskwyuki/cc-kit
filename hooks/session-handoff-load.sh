#!/bin/bash
# SessionStart hook（startup / clear）: 前回セッションが残した引き継ぎメモを読み込む。
#
# 実体は skill と共有する skills/session-handoff/handoff.sh に置いてある。
# 保存側（skill）と読み込み側（この hook）で保存先の算出がずれると
# 「保存したのに次のセッションで出てこない」という一番気づきにくい壊れ方をするため、
# パス規則は 1 本のスクリプトに閉じ込めて両側から呼ぶ。
#
# 設計上の約束:
#   - fail-open。実体が無くても壊れていても exit 0 でセッションを止めない
#   - 未読メモが無いときは無音。全プロジェクトで発火するのでノイズを出さない
#   - ただし実体が見つからないことは systemMessage で伝える。
#     stderr はユーザーに見えず、機能だけが静かに死んで気づけないため
set -u

DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 0

for CAND in \
  "$DIR/../skills/session-handoff/handoff.sh" \
  "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/skills/session-handoff/handoff.sh" \
  "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/skills/session-handoff/handoff.sh"
do
  if [ -r "$CAND" ]; then
    exec sh "$CAND" load
  fi
done

printf '{"systemMessage": "⚠ 引き継ぎメモの読み込みをスキップ: handoff.sh が見つかりません（cc-kit plugin の再 install を試してください）"}\n'
exit 0
