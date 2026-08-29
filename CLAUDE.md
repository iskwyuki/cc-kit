# cc-kit 運用ルール

- 統合は常に PR ブランチ経由。main への直接コミットはしない
- 配布物（`skills/` / `agents/` / `hooks/`）を変更したら `.claude-plugin/plugin.json` の version を bump する
- **`git add -A` / `git add .` は禁止。コミットは明示パス指定のみ**（ランタイム状態ファイルの混入を防ぐ）
- `hooks/` に置くのは**ブロックしない読み取り専用 hook だけ**。コマンドを止める hook は配布しない
- 外部由来 skill は無改変ミラーを原則とする。改変したものは skill 直下の `NOTICE.md` に改変内容を書く
- 出典は `.github/upstream-skills.manifest` に記録する。上流への自動追従は行わない
