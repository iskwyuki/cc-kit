# NOTICE

この skill は [mattpocock/skills](https://github.com/mattpocock/skills) からの選別ミラーです（無改変・verbatim）。

- 上流パス: `skills/productivity/grilling/`
- 上流コミット: `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`（コミット日 2026-08-24 14:19:57 UTC / 上流プラグイン version 1.2.3）
- 取得日: 2026-08-31（JST）
- 同期: **自動追従は行わない。** 上流を見に行くときは `.github/upstream-skills.manifest` を手がかりに手で差分を確認すること
- 取り込まなかった上流ファイル: `agents/openai.yaml`（OpenAI 側エージェント基盤の表示名メタデータ。SKILL.md からは参照されず Claude Code では読まれない。他の選別ミラー（prototype）と同じ扱い）
- 本ファイル（NOTICE.md）は同期対象外のローカル追加ファイル

## 経緯

2026-08-23 に「上流の grill-me がラッパー化したため現行版で凍結する」と決めたが、2026-08-31 にこれを撤回し、上流の grilling 系（`grilling` / `grill-me` / `grill-with-docs` / `domain-modeling`）を最新版で取り込んだ。凍結していた旧 grill-me（単体で完結する版）は削除済み。

**質問の出し方が変わっている。** 旧 grill-me は「1 問ずつ」だったが、grilling は依存関係の解けた質問をまとめて出す「ラウンド単位」になっている。凍結を選んだ当時の理由はまさにこの食い違いだったので、運用側のルール（グローバル CLAUDE.md 等）が「1 問ずつ」を前提にしている場合は、そちらを実態に合わせること。

## License (upstream)

```
MIT License

Copyright (c) 2026 Matt Pocock

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
