# NOTICE

この skill は [mathbullet/skills](https://github.com/mathbullet/skills) の `html` skill を元にした **改変版フォーク**です。

本リポジトリの他の外部由来 skill（prototype / find-skills / eli5 / grill-me）はすべて「無改変・verbatim」の選別ミラーですが、**これは違います**。上流の成果物の形態そのものを変えているため、ミラーではなくフォークとして扱ってください。上流の更新を機械的に取り込むことはできません。

## 上流

- リポジトリ: <https://github.com/mathbullet/skills>
- 上流パス: `plugins/html/skills/html/`
- 上流コミット: `fe96c626b39abba47fad2d4a4ef738e8a27602b1`（コミット日 2026-08-02 +0900 / 取得 2026-08-26 JST）
- 上流プラグインバージョン: 1.0.0
- 作者: mathbullet
- 同期: **自動追従は行わない**（本リポジトリの方針。`.github/upstream-skills.manifest` を参照）

## 改変内容

### 1. 目次を左サイドバーへ移した

上流は `nav.mb-toc` を `.mb-main` の先頭にインライン配置し、`.mb-wrap` は本文 + 右サイドバー（用語リスト）の 2 カラムでした。これを 3 カラム（左に目次、中央に本文、右に用語リスト）へ変更しています。

- `.mb-page` の最大幅を 1100px から 1400px へ広げた
- `.mb-wrap` を `240px minmax(0, 1fr) 300px` の 3 カラムグリッドにした
- `.mb-wrap > nav.mb-toc` を sticky にし、独立したスクロール領域を与えた
- 折り返しの段階を 2 つにした。1200px 以下で用語リストを本文の下へ送り、860px 以下で 1 カラムにする（上流は 1000px で一気に 1 カラム）
- `@media print` で目次の sticky を解除した

### 2. 画面をダーク固定にし、配色を差し替えた

上流はオフホワイト背景のライト 1 種類でした。これを**画面はダーク固定、紙（印刷）はライト**という構成に変えています。

上流の `document.css` は既に全色を `:root` の設計トークンに集約していたため、部品側の規則には手を入れていません。

- 部品側にベタ書きされていた 5 色（インラインコード背景、差分の加除 2 色ずつ）をトークン化した
- `:root` のパレットをダークに差し替えた
- **`@media print` の中でトークンをライトへ戻した。** これは必須の手当てです。上流の `@media print` は `html, body` の背景と `a` の色しか上書きしておらず、トークンを戻していません。ダークのまま印刷すると白地に白い文字が出て読めなくなります（実際に描画して確認しました）
- `color-scheme` を宣言した

現在のダークのパレットは、利用者が別途持っていたページ（緑みのある濃灰の地に淡色の文字、細い罫線）の配色を移植したものです。上流とも、私が最初に作った配色とも異なります。

#### 配色を決めるまでに一度失敗している

最初は上流のオフホワイトを反転させた暖色系のダーク（地 `#12110F` / 本文 `#E3E0D8`、コントラスト比 14.3:1）を作りました。「純黒に純白で目が痛い」との指摘を受け、地と文字を両側から灰へ寄せて 9.5:1 まで下げたところ、今度は「文字が頭に入ってこない」という結果になりました。

4 つの配色を同一の本文・字体・組みで並べて測ったところ、原因が分かりました。

| 配色 | 本文 / 地 | 比 |
|---|---|---|
| 現在（移植した配色） | `#E7EAE5` / `#101312` | 15.4:1 |
| 上流のライト | `#1A1A1A` / `#FAF9F6` | 16.5:1 |
| 失敗した低コントラスト版 | `#C4C0B5` / `#1C1B18` | 9.5:1 |

**コントラストを下げたのが誤りでした。** 痛みの原因は比の高さではなく、純黒に純白という組み合わせそのものです。極端な色を避けたうえでコントラストは高く保つのが正解で、上流のライトも移植元も同じ構造になっています。両側を灰へ寄せると輪郭が甘くなり、読んでも頭に入らない文章になります。

この経緯は `SKILL.md` にも指針として残しました。

#### OS 追従をやめた経緯

当初は OS 設定に追従する実装（`prefers-color-scheme` と `data-theme` の 2 ブロック）でしたが、ライトを使う予定が無いという利用者の判断でダーク固定に単純化しました。配色定義は約 77 行から約 39 行に、色を 1 つ足すときに書く箇所は 4 箇所から 2 箇所になっています。

ページ内にテーマ切替ボタンは置いていません。ページが自前の背景色を塗るため、Artifact ビューアのテーマ操作はこのページには効きません。共有した相手の画面でも常にダークで表示されます。Artifact の仕様上、単一の見た目へ決め打つ設計は許容されています。

### 3. Claude Artifact を既定の成果物にした

これが最も大きな改変です。Artifact は厳格な CSP で外部ホストへの通信を遮断するため、上流の「CDN から MathJax と Highlight.js を読み込む」書き方がそのままでは動きません。

- **MathJax を CHTML 出力から SVG 出力へ変更した。** CHTML は描画時に MathJax 自身の woff フォントを CDN から取得するため CSP で止まります。SVG 出力はグリフをパスとして描くのでフォントを取りに行きません
- **バンドルを `tex-mml-svg` ではなく `tex-svg-full` にした。** 上流と同じ構成の `tex-mml-svg` では、`\boldsymbol` のような標準的なコマンドが実行時の遅延読み込み頼みになり、CSP 下では未定義コマンドとして赤字で表示されてしまいます（実際に描画して確認しました）。`tex-svg-full` は TeX の全パッケージを内包するので、遅延読み込みなしで解決できます。代償として MathML の**入力**に対応しなくなりますが、このスキルは TeX で数式を書くため影響しません
- **MathJax と Highlight.js を `design-system/vendor/` へ同梱した**（下記「同梱している第三者ソフトウェア」）
- **`scripts/build.sh` を追加した。** ソースに置いたマーカーを、同梱アセットの中身へ置き換えます。1 つのソースから Artifact 用（骨格タグなし）とローカル単体ファイル用（`--standalone`）の 2 通りを出力します
- **`templates/document.src.html` を追加した**
- **`math-copy.js` に MathJax の設定を足した。** `require` パッケージと右クリックメニューを無効にしています。CSP 下ではどちらも遅延読み込みが CDN へ出て遮断されるためです
- `component-samples.html` を新しいレイアウトに合わせ、CDN 参照を同梱アセット参照へ差し替えた
- `SKILL.md` を上記に合わせて書き換えた

`render-pdf.sh` は**無改変で維持**しています。PDF 出力は Artifact からは構造上不可能（ビューアのサンドボックスがダウンロードを遮断する）なため、`--standalone` でビルドしたローカルファイル向けに残しました。

### 改変していないファイル

- `render-pdf.sh`（完全に無改変）
- `LICENSE-MIT.txt`（上流ルートの `LICENSE` の verbatim コピー）

## License

### 上流 skill — MIT

全文と著作権表示を同ディレクトリの [`LICENSE-MIT.txt`](./LICENSE-MIT.txt) に同梱しています。原文の所在: <https://github.com/mathbullet/skills/blob/main/LICENSE>

```
Copyright (c) 2026 mathbullet
```

MIT は改変版の再配布を認めており、条件はライセンス本文と著作権表示の複製です。同梱により満たしています。

## 同梱している第三者ソフトウェア

`design-system/vendor/` に、上流には含まれていなかったファイルを追加しています。Artifact の CSP 下では CDN から読み込めないためです。いずれも無改変のリリース成果物です。

| ファイル | 由来 | バージョン | ライセンス |
|---|---|---|---|
| `mathjax-tex-svg-full.js` | [MathJax](https://github.com/mathjax/MathJax) | 3.2.2（`tex-svg-full` 版） | Apache-2.0 |
| `highlight.min.js` | [highlight.js](https://github.com/highlightjs/highlight.js) | 11.11.1 | BSD-3-Clause |

ライセンス全文をそれぞれ [`vendor/LICENSE-MathJax-Apache-2.0.txt`](./design-system/vendor/LICENSE-MathJax-Apache-2.0.txt) と [`vendor/LICENSE-highlightjs-BSD-3-Clause.txt`](./design-system/vendor/LICENSE-highlightjs-BSD-3-Clause.txt) に同梱しています。

取得元:

- `https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-svg-full.js`
- `https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js`

## サイズについて

`design-system/vendor/mathjax-tex-svg-full.js` が約 2.1MB あり、この skill の大半を占めます。生成されるページのサイズも、数式を含む場合は約 2.3MB になります（Artifact の上限は 16MB）。

数式が無い文書では、ソースから `<!--MB:MATH-->` を省いてください。MathJax はページに入らず、出力は約 150KB に収まります。

## 本ファイルについて

`NOTICE.md` は上流に存在しないローカル追加ファイルです。
