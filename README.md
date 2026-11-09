# skill-sandbox

Claude Code のスキル開発用のサンドボックス devcontainer です。
Claude Code をネットワーク・権限・ファイルの 3 方向から閉じ込めたうえで、`.claude/skills/` 配下のスキルを作って試せます。

```
            ┌──────────── sandbox ネットワーク（internal: 外部ルートなし）────────────┐
            │                                                                        │
 [claude] ──┼──▶ [egress-proxy] (squid)  ──▶ 許可リストのドメインだけ ──▶ インターネット
 非 root    │                                                                        │
 cap なし   └──▶ [api-gateway]  (nginx)  ──▶ x-api-key を注入 ──────────▶ api.anthropic.com
 RO rootfs
```

- `claude` コンテナは internal ネットワークにしかつながっておらず、デフォルトルートも外部 DNS もありません。プロキシを無視した通信（IP 直打ち、`dig @8.8.8.8`、IPv6、`fetch()` など）は経路がないので失敗します。
- 本物の API キーは `api-gateway` コンテナにしかありません。Claude Code はダミーのトークンでゲートウェイに投げ、ゲートウェイがキーを差し替えます。
- 起動のたびに `verify-sandbox` が走り、上記の制限が効いていることを確かめます。

## 構成ファイル

| パス | 内容 |
| --- | --- |
| `.devcontainer/devcontainer.json` | devcontainer の定義。起動時に `verify-sandbox` を実行 |
| `.devcontainer/compose.yaml` | 3 コンテナ・2 ネットワークの定義とハードニング設定 |
| `.devcontainer/claude/` | Claude Code を入れたイメージ、managed settings、検証スクリプト |
| `.devcontainer/proxy/` | squid の設定と許可ドメイン（`allowlist.txt`） |
| `.devcontainer/gateway/` | API キーを注入する nginx |
| `.claude/skills/` | 開発するスキルの置き場所（コンテナから書き込める唯一の `.claude` 配下） |

## セットアップ

### 1. API キーをリポジトリの外に置く

`.devcontainer/` はコンテナから読めるので、キーはホームディレクトリ側に置きます。実験専用のキーを作り、Console で利用上限を設定しておいてください。

```bash
mkdir -p ~/.config/skill-sandbox
```

```bash
printf 'ANTHROPIC_API_KEY=%s\n' 'sk-ant-...' > ~/.config/skill-sandbox/gateway.env
```

```bash
chmod 600 ~/.config/skill-sandbox/gateway.env
```

別の場所に置く場合は、環境変数 `SKILL_SANDBOX_ENV_FILE` でパスを指定します。

### 2. VS Code 側の設定（VS Code で開く場合）

Dev Containers 拡張は、git の認証情報ヘルパーや `.gitconfig` をコンテナに自動で持ち込みます。ホスト側の **ユーザー設定** に次を入れて止めます。

```jsonc
{
  "dev.containers.copyGitConfig": false,
  "dev.containers.gitCredentialHelperConfigLocation": "none",
  // コンテナからは Marketplace に出られないので、拡張機能はホスト側で取得する
  "remote.downloadExtensionsLocally": true
}
```

SSH エージェントは `devcontainer.json` の `remoteEnv` で `SSH_AUTH_SOCK` を空にしています。

### 3. 起動する

VS Code なら「Dev Containers: Reopen in Container」。CLI なら次のとおりです。

```bash
devcontainer up --workspace-folder .
```

```bash
devcontainer exec --workspace-folder . claude
```

起動ログの最後に `結果: OK 26 / NG 0` のように出れば制限が効いています。✘ が出たら起動は続きますが、そのまま使わないでください。手動でも確認できます。

```bash
verify-sandbox
```

## スキルを開発する

`.claude/skills/<スキル名>/SKILL.md` を作ると、コンテナ内の Claude Code がプロジェクトスキルとして読み込みます。

コンテナからの書き込み可否は次のとおりです。ホスト側で後から実行され得る場所は読み取り専用で上書きしています。

| パス | コンテナから | 理由 |
| --- | --- | --- |
| `/workspace`（リポジトリ全体） | 書き込み可 | 作業場所 |
| `/workspace/.claude/skills` | 書き込み可 | 開発対象 |
| `/workspace/.claude`（skills 以外） | 読み取り専用 | `settings.json` の hooks を書き換えられると、ホストで Claude Code を開いたときに実行される |
| `/workspace/.git` | 読み取り専用 | git hooks の書き換え防止。コミットはホスト側で行う |
| `/workspace/.devcontainer` | 読み取り専用 | compose や Dockerfile を書き換えられると、次の起動時にホストへ抜けられる |
| `/`（ルートファイルシステム） | 読み取り専用 | 書き込みは `/tmp`（tmpfs, noexec）とホーム（volume）だけ |

スキル自体（`SKILL.md` やスクリプト、frontmatter の hooks）はホストでも使うことになるので、**ホストに持ち出す前に差分を必ずレビュー** してください。これはサンドボックスでは守れない部分です。

このサンドボックス内なら `claude --dangerously-skip-permissions` で確認なしに動かしても、被害はコンテナとワークスペースの中に収まります。

## 許可ドメインを足す

`.devcontainer/proxy/allowlist.txt` に 1 行 1 ドメインで書き、プロキシを再起動します（先頭の `.` でサブドメインも許可）。Claude 自身はこのファイルを書き換えられません。

```bash
docker compose -f .devcontainer/compose.yaml restart egress-proxy
```

既定では何も許可していません。Claude Code の API 通信はゲートウェイ経由なので、空でも Claude Code は動きます。github.com などを許可すると、そこが持ち出し経路（gist、issue など）になる点に注意してください。

## ログを見る

```bash
docker compose -f .devcontainer/compose.yaml logs -f egress-proxy
```

```bash
docker compose -f .devcontainer/compose.yaml logs -f api-gateway
```

プロキシは許可（`TCP_TUNNEL/200`）も拒否（`TCP_DENIED/403`）もすべて記録します。ゲートウェイはパスとステータスだけを記録し、ヘッダーやボディは出しません。

## Pro/Max サブスクリプション（OAuth）で使う場合

ゲートウェイ方式は API キー専用です。サブスクリプションでログインする場合は次のように変えます。この場合、ログイン後のトークンはコンテナ内（`~/.claude`）に置かれ、Claude から読める点に注意してください。

1. `compose.yaml` の `claude` サービスから `ANTHROPIC_BASE_URL` と `ANTHROPIC_AUTH_TOKEN` を消す
2. `allowlist.txt` の「Pro/Max サブスクリプション」のドメインのコメントを外す
3. `gateway.env` には `ANTHROPIC_API_KEY=unused` のようなダミー値を入れておく（ゲートウェイは起動するが使われない）
4. コンテナを作り直し、`claude` を起動して `/login` する

## Claude Code 側の設定

`/etc/claude-code/managed-settings.json`（ユーザー設定で上書き不可）で次を設定しています。

- `WebSearch` と `WebFetch` を deny。WebSearch は Anthropic 側で実行されるのでネットワーク制限では止まらない
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`、`DISABLE_AUTOUPDATER=1`

使いたい場合は `.devcontainer/claude/managed-settings.json` を編集してイメージを作り直してください。

## 守れないもの・既知の制約

- **API に送る内容**: プロンプトと Claude が読んだファイルは API に送られます。秘密情報をワークスペースに置かないでください。
- **許可ドメイン経由の持ち出し**: squid は TLS を終端しないので、許可したドメインへの通信の中身は見えません。ドメインフロンティングも防げません。中身まで見たい場合は mitmproxy などに差し替え、コンテナに CA を入れて `NODE_EXTRA_CA_CERTS` を設定します。
- **API 経由の持ち出し**: ゲートウェイは `/v1/` 配下を中継するので、Claude はキーを使って任意の API 呼び出しができます（結果はあなたのアカウントに残るだけですが、利用上限は必ず設定してください）。
- **組み込みの Bash サンドボックス（`/sandbox`）**: bubblewrap はユーザー名前空間を作る必要があり、`cap_drop: ALL` と Docker 既定の seccomp の下では動かない見込みなので有効にしていません。
- **`/tmp` は noexec**: `/tmp` に置いたバイナリを実行するツール（一部のビルドツールなど）は失敗します。必要なら `compose.yaml` の tmpfs から `noexec` を外してください。
- **Windows**: `env_file` の既定パスは `${HOME}` を使います。設定されていない場合は `SKILL_SANDBOX_ENV_FILE` を指定してください。

## さらに固める

`compose.yaml` にコメントで書いてあります。

- `runtime: runsc` で gVisor を使う（カーネル脆弱性経由の脱出対策。ファイル I/O は大幅に遅くなる）
- `security_opt` に独自の seccomp プロファイルを足す
- Docker デーモンで `userns-remap` を有効にする
