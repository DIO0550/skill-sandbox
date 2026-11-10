# skill-sandbox

Claude Code のスキル（Agent Skills）を、ホスト環境から隔離された Docker コンテナの中で開発・テストするためのサンドボックスです。

- 非 root ユーザー（`claude`）で動作し、Linux capabilities はすべて削除、`no-new-privileges` を有効化
- ホストから見えるのは `./workspace/skills` と `./workspace/project` の 2 フォルダだけ
- ログイン状態や設定は名前付きボリュームに保存され、ホストの `~/.claude` には触れません
- 外部への通信は許可リスト型プロキシ（Squid）経由のみ。許可したドメイン以外には接続できません

## 必要なもの

- Docker（Compose v2 プラグイン込み）
- Claude のアカウント、または Anthropic API キー

## クイックスタート

```bash
cp .env.example .env
# Linux では .env の USER_UID / USER_GID を `id -u` / `id -g` の値に合わせておくと、
# workspace 内のファイルの所有者がずれません

docker compose up -d --build        # ビルドしてバックグラウンドで起動
docker compose exec sandbox bash    # コンテナ内のシェルに入る
```

コンテナ内で:

```bash
claude            # 初回は /login でログイン（API キーを .env に書いた場合は不要）
```

使い捨てで 1 回だけシェルを開くなら、次のコマンドでも構いません。

```bash
docker compose run --rm sandbox
```

終了・片付け:

```bash
docker compose down        # コンテナを停止・削除（ログイン状態は残る）
docker compose down -v     # ログイン状態や設定のボリュームも削除
```

## ディレクトリ構成とマウント

| ホスト | コンテナ | 用途 |
| --- | --- | --- |
| `./workspace/skills` | `/home/claude/.claude/skills` | 開発中のスキル。ここに置いたスキルはユーザースキルとして Claude Code に読み込まれる |
| `./workspace/project` | `/workspace` | スキルを試すための作業ディレクトリ（コンテナ起動時のカレント） |
| ボリューム `claude-config` | `/home/claude/.claude` | ログイン情報・設定・履歴（`CLAUDE_CONFIG_DIR`） |
| `./proxy`（proxy コンテナ側） | `/etc/squid/sandbox`（読み取り専用） | プロキシ設定と許可ドメイン一覧 |

これ以外のホストのファイル（ホームディレクトリ、SSH 鍵、ホストの `~/.claude` など）はコンテナからは見えません。

## スキルの作り方と試し方

1. `workspace/skills/<スキル名>/SKILL.md` を作成します（サンプル: [`workspace/skills/hello-sandbox`](workspace/skills/hello-sandbox/SKILL.md)）。
2. コンテナ内で `claude` を起動し、スキルが発火しそうな依頼を投げます。サンプルなら「hello sandbox」と入力します。
3. `/skills` で読み込まれているスキルの一覧を確認できます。
4. ホスト側のエディタで `SKILL.md` を編集したら、`claude` を再起動して変更を反映させます。

テスト用のファイルやリポジトリは `workspace/project` に置いてください。スキルが作業ディレクトリに書き込んだ結果はホストからそのまま確認できます。

## 設定（`.env`）

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `USER_UID` / `USER_GID` | `1000` | コンテナ内ユーザーの uid / gid。ホストのユーザーに合わせる |
| `CLAUDE_CODE_VERSION` | `latest` | インストールする Claude Code のバージョン。固定したい場合に指定 |
| `ANTHROPIC_API_KEY` | （空） | 指定すると対話ログインの代わりに API キーで認証 |

`USER_UID` / `USER_GID` や `CLAUDE_CODE_VERSION` を変えたら `docker compose build` で再ビルドしてください。

### Claude Code の更新

コンテナ内の自動アップデートと `claude update` は使わず、イメージの再ビルドで更新します。

```bash
# 最新版に上げる（CLAUDE_CODE_VERSION=latest のままだとビルドキャッシュが効いて更新されないため --no-cache を付ける）
docker compose build --no-cache sandbox
docker compose up -d

# 特定のバージョンに固定する場合は .env の CLAUDE_CODE_VERSION を書き換えて再ビルド
```

ネイティブインストーラーの自動アップデートや `claude update` は `downloads.claude.ai` に接続しますが、このイメージは npm でインストールしており、ビルドはプロキシの制限の外で行われるため、許可リストに `downloads.claude.ai` を入れる必要はありません。実行ファイルを含むプラグインを使う場合だけ、[`proxy/allowed-domains.txt`](proxy/allowed-domains.txt) のコメントを外してください。

## ネットワーク制限（許可リスト型プロキシ）

```
sandbox ──(HTTPS_PROXY)──▶ proxy (Squid) ──(許可ドメインのみ)──▶ インターネット

sandbox ネットワーク: sandbox, proxy   ← internal: true（外への経路なし）
egress ネットワーク : proxy のみ        ← 外に出られるのはここだけ
```

- `sandbox` コンテナは `internal: true` の Docker ネットワークにだけ接続しています。このネットワークにはゲートウェイがないため、プロキシを経由しない通信（直接の TCP 接続、IP 直打ち、`HTTPS_PROXY` を無視するツール）はすべて失敗します。外部ドメインの DNS 解決もできません。
- 外に出られるのは `proxy` コンテナ（Squid）経由だけです。`HTTPS_PROXY` / `HTTP_PROXY` は `compose.yaml` で設定済みで、Claude Code・curl・git・npm・pip などはそのままプロキシを使います。
- プロキシは [`proxy/allowed-domains.txt`](proxy/allowed-domains.txt) に書かれたドメインへの接続だけを許可し、それ以外は `403 Forbidden` を返します。接続先ポートは 443（HTTPS）と 80 のみ、IP アドレス直指定やサブドメインのすり抜けも拒否します。
- プロキシのポートはホストに公開していません。

### 既定で許可しているドメイン

[公式ドキュメントの Network access requirements](https://code.claude.com/docs/en/network-config#network-access-requirements) のうち、npm でインストールした Claude Code を使うのに必須のものだけです。

| ドメイン | 用途 |
| --- | --- |
| `api.anthropic.com` | Claude API（WebFetch のドメイン安全チェック、機能フラグ取得を含む） |
| `claude.ai` | claude.ai アカウントでの認証 |
| `platform.claude.com` | OAuth トークンの交換・更新（claude.ai / Console どちらのログインでも必要） |

許可リストに入れていない通信先を使う機能は、`compose.yaml` の環境変数で止めています。

| 環境変数 | 止めるもの |
| --- | --- |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | テレメトリ・エラーレポート（Datadog）、自動アップデートなど必須でない通信 |
| `ENABLE_CLAUDEAI_MCP_SERVERS=false` | claude.ai で設定した MCP コネクタ（`mcp-proxy.anthropic.com`） |
| `CLAUDE_CODE_DISABLE_ARTIFACT=1` | Artifact の読み込み（`*.frame.claudeusercontent.com`） |

### 許可ドメインの追加

`proxy/allowed-domains.txt` に 1 行 1 ドメインで追記し、プロキシに再読み込みさせます（コンテナの再起動は不要）。

```bash
echo "registry.npmjs.org" >> proxy/allowed-domains.txt
docker compose exec proxy squid -k reconfigure -f /etc/squid/sandbox/squid.conf
```

`example.com` は完全一致、`.example.com` はサブドメインも含めて一致します。プラグインのインストール（`registry.npmjs.org`、`github.com`）や PyPI など、よく使うものはファイル内にコメントアウトして用意してあります。

許可したドメインには、コンテナ内のコードが自由にデータを送れることに注意してください。必要なものだけを追加するのが原則です。

### 通信ログの確認

```bash
docker compose logs -f proxy
```

許可された接続は `TCP_TUNNEL/200`、拒否された接続は `TCP_DENIED/403` として、接続先ドメインと一緒に記録されます。スキルがどこに通信しようとしたかを確認するのに使えます。

### 制限の確認

```bash
docker compose exec sandbox bash -lc '
  curl -sS -o /dev/null -w "%{http_code}\n" https://api.anthropic.com/   # 404 など: 到達できる
  curl -sS -o /dev/null https://example.com/                             # 403: プロキシが拒否
  curl -sS -o /dev/null --noproxy "*" --max-time 5 https://example.com/  # 失敗: 直接通信は経路なし
'
```

### この方式の限界

- 許可したドメインの中身（URL パスやリクエスト本文）までは検査しません。HTTPS は CONNECT トンネルでそのまま中継するため、プロキシから見えるのは接続先のドメインとポートだけです。
- イメージのビルド（`docker compose build`）は通常の Docker ネットワークで行われるため、この制限の対象外です。

## その他のセキュリティ上の制限

`compose.yaml` で次の制限もかけています。

- `cap_drop: ALL` と `no-new-privileges`（sudo なし、root への昇格不可）
- `pids_limit: 512`、`mem_limit: 4g`、`cpus: 2`
- `/tmp` は 512MB の tmpfs
- proxy コンテナも capabilities を最小限（Squid の権限降格に必要な分だけ）に絞り、`no-new-privileges` を有効化

## トラブルシューティング

- **`/workspace` に書き込めない (`Permission denied`)**: ホストのユーザーとコンテナの uid が一致していません。`.env` の `USER_UID` / `USER_GID` を `id -u` / `id -g` の値にして `docker compose up -d --build` で作り直してください。
- **ログインし直したい**: `docker compose down -v` で設定ボリュームを削除してから起動し直します。
- **何かのコマンドが `403 Forbidden` やタイムアウトで失敗する**: プロキシが接続先を拒否しています。`docker compose logs proxy` で `TCP_DENIED` の行を探し、必要なドメインなら `proxy/allowed-domains.txt` に追加してください。
- **Node.js の `fetch()` など、プロキシ設定を読まないツールが通信できない**: 内部ネットワークでは直接通信できないため想定どおりの動作です。そのツールのプロキシ設定を使ってください（Node.js 24 以降なら `NODE_USE_ENV_PROXY=1`）。
