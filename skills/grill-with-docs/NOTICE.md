# NOTICE

この skill は [mattpocock/skills](https://github.com/mattpocock/skills) からの選別ミラーです（無改変・verbatim）。

- 上流パス: `skills/engineering/grill-with-docs/`
- 上流コミット: `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`（コミット日 2026-08-24 14:19:57 UTC / 上流プラグイン version 1.2.3）
- 取得日: 2026-08-31（JST）
- 同期: **自動追従は行わない。** 上流を見に行くときは `.github/upstream-skills.manifest` を手がかりに手で差分を確認すること
- 取り込まなかった上流ファイル: `agents/openai.yaml`（OpenAI 側エージェント基盤の表示名メタデータ。SKILL.md からは参照されず Claude Code では読まれない）
- 本ファイル（NOTICE.md）は同期対象外のローカル追加ファイル

## 単体では完結しない

この skill の中身は `grilling` と `domain-modeling` を呼ぶ 1 行だけです。呼び出し先はどちらも cc-kit に同梱済みで（[`grilling`](../grilling/) / [`domain-modeling`](../domain-modeling/)）、cc-kit を入れていれば `cc-kit:grilling` `cc-kit:domain-modeling` として解決されます。

`disable-model-invocation: true` が付いているため model 側の skill 一覧には出ません。`/grill-with-docs` から明示的に呼ぶ用途です。grill しながら ADR と用語集（`CONTEXT.md` / `docs/adr/`）を書き足していく点が `grill-me` との違いです。

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
