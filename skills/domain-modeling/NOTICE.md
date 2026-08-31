# NOTICE

この skill は [mattpocock/skills](https://github.com/mattpocock/skills) からの選別ミラーです（無改変・verbatim）。

- 上流パス: `skills/engineering/domain-modeling/`
- 上流コミット: `6654f6b60cd9d5be8b54c6fafe44346dabeb3b76`（コミット日 2026-08-24 14:19:57 UTC / 上流プラグイン version 1.2.3）
- 取得日: 2026-08-31（JST）
- 取り込んだファイル: `SKILL.md` / `ADR-FORMAT.md` / `CONTEXT-FORMAT.md`（SKILL.md 本文が後ろ 2 つを相対パスで参照するため 3 点セット）
- 同期: **自動追従は行わない。** 上流を見に行くときは `.github/upstream-skills.manifest` を手がかりに手で差分を確認すること
- 取り込まなかった上流ファイル: `agents/openai.yaml`（OpenAI 側エージェント基盤の表示名メタデータ。SKILL.md からは参照されず Claude Code では読まれない）
- 本ファイル（NOTICE.md）は同期対象外のローカル追加ファイル

## 取り込んだ理由と運用上の注意

単独でも使えますが、cc-kit が同梱しているのは [`grill-with-docs`](../grill-with-docs/) の呼び出し先だからです。

**この skill は `disable-model-invocation` を持たないため、model 側から自発的に起動します。** 上流の description が「用語について話す / `CONTEXT.md` を書く / ADR を記録する」を発火条件にしているので、`grill-with-docs` を使っていないセッションでも、設計の議論中に起動して `CONTEXT.md` や `docs/adr/` を作りにいくことがあります。作成は「書くものができたときだけ」という遅延生成が上流の指示ですが、意図しないファイルが増えるのが困る場面では起動していないか気にしてください。

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
