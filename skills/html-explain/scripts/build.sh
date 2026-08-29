#!/usr/bin/env bash
# build.sh — 1つのソース HTML から、Artifact 用と ローカル単体ファイル用の
# 2 通りの成果物を作る。どちらも同梱アセットを実体として持つ自己完結ファイル。
#
# Usage:
#   scripts/build.sh [--standalone] <src.html> [out.html]
#
# モード:
#   既定（Artifact 用）
#     doctype / html / head / body を付けずに中身だけを出力する。Artifact は
#     publish 時にこれらで包むため、ページ側に書くと壊れる。
#   --standalone（ローカル用）
#     doctype から </html> までを付けた通常の HTML を出力する。ブラウザで直接
#     開けて、render-pdf.sh にもかけられる。
#
# ソース側のマーカー:
#   <!--MB:HEAD-->  ... <!--MB:/HEAD-->
#       head に入れたい範囲。--standalone ではこの範囲が <head> の中へ入る。
#       Artifact モードでは単にマーカー行だけが取り除かれる。
#   <!--MB:CSS-->   -> design-system/document.css
#   <!--MB:HLJS-->  -> design-system/vendor/highlight.min.js（+ 初期化）
#   <!--MB:MATH-->  -> design-system/math-copy.js + vendor/mathjax-tex-svg-full.js
#
#   アセットのマーカーは必要なものだけ書けばよい。数式が無い文書で
#   <!--MB:MATH--> を省けば、MathJax の約 2.1MB はページに入らない。
#
# 出力先を省略した場合:
#   Artifact 用   : <basename から .src を除いた名前>.html
#   --standalone  : <同>.local.html

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DS="$SKILL_DIR/design-system"

STANDALONE=0
if [[ "${1:-}" == "--standalone" ]]; then
  STANDALONE=1
  shift
fi

SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  echo "usage: $0 [--standalone] <src.html> [out.html]" >&2
  exit 64
fi
if [[ ! -f "$SRC" ]]; then
  echo "not found: $SRC" >&2
  exit 66
fi

SRC_DIR="$(cd "$(dirname "$SRC")" && pwd)"
BASE="$(basename "$SRC")"
BASE="${BASE%.html}"
BASE="${BASE%.src}"

if [[ -n "${2:-}" ]]; then
  OUT="$2"
elif (( STANDALONE )); then
  OUT="$SRC_DIR/$BASE.local.html"
else
  OUT="$SRC_DIR/$BASE.html"
fi

OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
if [[ "$SRC_DIR/$(basename "$SRC")" == "$OUT_DIR/$(basename "$OUT")" ]]; then
  echo "src と out が同一ファイルです: $SRC" >&2
  exit 64
fi

# ソースは常に「中身だけ」で書く。骨格タグは --standalone のときに build.sh が付ける
if grep -qiE '<!doctype|<html[ >]|<html>|<head[ >]|<head>|<body[ >]|<body>' "$SRC"; then
  echo "ソースに doctype / html / head / body タグがあります。" >&2
  echo "骨格タグはソースに書かず、ローカル版が必要なら --standalone を使ってください:" >&2
  grep -niE '<!doctype|<html[ >]|<html>|<head[ >]|<head>|<body[ >]|<body>' "$SRC" >&2
  exit 65
fi

if ! grep -qi '<title>' "$SRC"; then
  echo "warning: <title> がありません。Artifact のタブ名とギャラリー名に使われます" >&2
fi

for f in "$DS/document.css" "$DS/math-copy.js" \
         "$DS/vendor/highlight.min.js" "$DS/vendor/mathjax-tex-svg-full.js"; do
  [[ -f "$f" ]] || { echo "同梱アセットが見つかりません: $f" >&2; exit 66; }
done

awk -v ds="$DS" -v standalone="$STANDALONE" '
function dump(path,   line) {
  while ((getline line < path) > 0) print line
  close(path)
  # minified ファイルは末尾に改行が無い。閉じタグが同じ行に流れないよう改行を足す
  print ""
}
BEGIN {
  if (standalone) {
    print "<!DOCTYPE html>"
    print "<html lang=\"ja\">"
    print "<head>"
    print "<meta charset=\"UTF-8\">"
    print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
    head_open = 1
  }
}
{
  if ($0 ~ /^[[:space:]]*<!--MB:HEAD-->[[:space:]]*$/) {
    next
  }
  if ($0 ~ /^[[:space:]]*<!--MB:\/HEAD-->[[:space:]]*$/) {
    if (standalone && head_open) {
      print "</head>"
      print "<body>"
      head_open = 0
    }
    next
  }
  if ($0 ~ /^[[:space:]]*<!--MB:CSS-->[[:space:]]*$/) {
    print "<style>"
    dump(ds "/document.css")
    print "</style>"
  } else if ($0 ~ /^[[:space:]]*<!--MB:HLJS-->[[:space:]]*$/) {
    print "<script>"
    dump(ds "/vendor/highlight.min.js")
    print "</script>"
    print "<script>document.addEventListener(\"DOMContentLoaded\", function () { hljs.highlightAll(); });</script>"
  } else if ($0 ~ /^[[:space:]]*<!--MB:MATH-->[[:space:]]*$/) {
    # math-copy.js が window.MathJax を定義するので MathJax 本体より前に置く
    print "<script>"
    dump(ds "/math-copy.js")
    print "</script>"
    print "<script>"
    dump(ds "/vendor/mathjax-tex-svg-full.js")
    print "</script>"
  } else {
    print
  }
}
END {
  if (standalone) {
    if (head_open) {
      # <!--MB:/HEAD--> が無いソースでも壊れた HTML を出さない
      print "</head>"
      print "<body>"
    }
    print "</body>"
    print "</html>"
  }
}
' "$SRC" > "$OUT"

BYTES="$(wc -c < "$OUT" | tr -d ' ')"
if (( STANDALONE == 0 )); then
  LIMIT=$((16 * 1024 * 1024))
  if (( BYTES > LIMIT )); then
    echo "出力が Artifact の上限 16MB を超えています: ${BYTES} bytes" >&2
    exit 65
  fi
fi

printf 'built: %s (%s bytes)\n' "$OUT" "$BYTES"
