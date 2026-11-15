// OpenCode のプラグイン（/etc/opencode/plugins/deny-pkg-managers.js）。
// /etc/opencode/opencode.json の "plugin" から読み込まれ、bash ツールの実行前に
// deny-pkg-managers でコマンドを調べて、パッケージマネージャーなら例外で止める。
import { spawnSync } from "node:child_process"

export const DenyPkgManagers = async () => ({
  "tool.execute.before": async (input, output) => {
    if (input?.tool !== "bash") return
    const command = output?.args?.command
    if (typeof command !== "string") return
    const r = spawnSync("/usr/local/bin/deny-pkg-managers", ["--check", command], { encoding: "utf8" })
    if (r.status === 0) return
    throw new Error(
      "このサンドボックスでは、パッケージマネージャー（npm / npx / pnpm / yarn / bun / pip / uv など）" +
        "の実行と、標準ライブラリ以外のパッケージの導入を禁止しています。標準ライブラリだけで実装してください。" +
        (r.stderr ? `（${r.stderr.trim()}）` : ""),
    )
  },
})
