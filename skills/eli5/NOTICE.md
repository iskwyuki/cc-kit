# NOTICE

この skill は [anthropics/claude-plugins-community](https://github.com/anthropics/claude-plugins-community) からの選別ミラーです（無改変・verbatim）。何も知らない読者に向けて、大きな図と最小限の言葉の HTML artifact で仕組みを説明します。

- 上流パス: `eli5/skills/eli5/SKILL.md`
- 作者: Thariq Shihipar（上流 `eli5/.claude-plugin/plugin.json` の `author` による）
- 同期: **自動追従は行わない**（2026-08-23 廃止）。上流の出典は `.github/upstream-skills.manifest` に記録してあるので、
  取り込みたくなったら手で差分を確認すること。ワンショット skill は一度取り込めば機能し、自動追従は破壊的変更を持ち込むリスクの方が大きいと判断した
- 本ファイル（NOTICE.md）と `LICENSE-Apache-2.0.txt` は同期対象外のローカル追加ファイル

## License（上流の構造上、2 つの読み方が成り立つ）

上流は Anthropic が運営する **community plugin marketplace の read-only ミラー**で、外部からの投稿プラグインが同居しています（eli5 / quickdesign / testdino / tres-finance-plugin）。ライセンス表記は 2 か所にあり、次の 2 通りに読めます。

| 場所 | 表記 | 読み方 |
|---|---|---|
| リポジトリ直下の `LICENSE` | Apache License 2.0 | マーケットプレイス基盤全体（Anthropic 所有） |
| `eli5/.claude-plugin/plugin.json` の `license` | MIT | 各投稿者のコンテンツ（同居する 4 プラグインすべてが MIT を宣言） |

「基盤と投稿コンテンツのスコープ分離」と読めば MIT が適用され、「単一リポジトリ内の表記の食い違い」と読めば Apache 2.0 が適用されます。上流はどちらが優先されるかを明示していないため、**どちらの読みでも無条件に適法となるよう、両方の通知要件を満たしています**。

- Apache License 2.0 — 全文を同ディレクトリの [`LICENSE-Apache-2.0.txt`](./LICENSE-Apache-2.0.txt) に同梱（上流 `LICENSE` の verbatim コピー）。原文の所在: <https://github.com/anthropics/claude-plugins-community/blob/main/LICENSE>
- MIT — 下記に全文と著作権表示を記載

本ミラーは上流ファイルを一切改変していません（Apache License 2.0 第 4 条 (b) にいう変更に該当する改変なし）。上流ルートに NOTICE ファイルは存在せず、上流 `LICENSE` の Appendix も `Copyright [yyyy] [name of copyright owner]` のテンプレートのままで著作権者を特定していないため、以下の著作権表示は `plugin.json` の `author` に基づいて書き起こしたものです。上流でライセンス表記が統一された場合は、この NOTICE も追随して更新してください。

```
MIT License

Copyright (c) Thariq Shihipar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 運用上の注意

上流は community 投稿を自動スキャン後に掲載する仕組みで、プラグインは delist されることがあります。SKILL.md は全プロジェクトに配られる**エージェントへの指示文**なので、日次同期 PR は必ず差分を人が確認してからマージしてください（自動マージの対象にしないこと）。
