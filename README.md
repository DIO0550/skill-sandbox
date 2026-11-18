# skill-sandbox

Claude Code のスキル（Agent Skills）を、ホスト環境から隔離された Docker コンテナの中で開発・テストするためのサンドボックスです。

- 非 root ユーザー（`claude`）で動作し、Linux capabilities はすべて削除、`no-new-privileges` を有効化
- ホストから見えるのは `./workspace/skills` と `./workspace/project` の 2 フォルダだけ
- ログイン状態や設定は名前付きボリュームに保存され、ホストの `~/.claude` には触れません
- 外部への通信は許可リスト型プロキシ（Squid）経由のみ。許可したドメイン以外には接続できません
- さらに iptables のファイアウォールで、sandbox からはプロキシ以外（ホストや他のコンテナを含む）への通信をすべて拒否します
- 制限が実際に効いているかは [`scripts/verify.sh`](scripts/verify.sh) で確認できます
- Claude Code と、Copilot CLI・Codex・Cursor CLI・Antigravity・OpenCode が入っています。どれも npm ではなく gist のインストーラーで入れています（[詳しく](#claude-code-と-ai-ツールの入れ方)）
- `gh`（GitHub CLI）も spec-viewer と同じ gist で入れています。ログインやトークンは[こちら](#ghgithub-cli)
- コンテナ内の pnpm / npm には、spec-viewer と同じサプライチェーン対策（pnpm の `minimumReleaseAge`、npm の `ignore-scripts`、safe-chain）を設定しています
- Docker まわりのファイル（Dockerfile、compose、proxy、firewall）は [`.devcontainer`](.devcontainer) にまとめています
- VS Code の Dev Containers でも開けます。中身は同じ構成で、通信制限もそのまま効きます（[詳しく](#vs-codedev-containersで開く)）

## 必要なもの

- Docker Engine 25.0.5 以降と Docker Compose v2.17 以降（`docker version` / `docker compose version` で確認）
  - これより古い Docker Engine では、内部ネットワークからも DNS の問い合わせが外に漏れます
- Claude のアカウント、または Anthropic API キー

## クイックスタート

`docker compose` のコマンドは、`compose.yaml` のある `.devcontainer` フォルダで実行します。

```bash
cd .devcontainer
cp .env.example .env
# Linux では .env の USER_UID / USER_GID を `id -u` / `id -g` の値に合わせておくと、
# workspace 内のファイルの所有者がずれません

docker compose up -d --build        # ビルドしてバックグラウンドで起動
../scripts/verify.sh                # 制限が効いているかを確認（初回や設定変更後に）
docker compose exec sandbox bash    # コンテナ内のシェルに入る
```

コンテナ内で:

```bash
claude
```

初回は画面の案内に従ってログインします。コンテナにはブラウザがないので、表示された URL をホストのブラウザで開き、ログイン後に表示されるコードをターミナルに貼り付けてください（API キーを `.devcontainer/.env` に書いた場合は不要です）。

使い捨てで 1 回だけシェルを開くなら、次のコマンドでも構いません（以下、`docker compose` は `.devcontainer` で実行します）。

```bash
docker compose run --rm sandbox
```

終了・片付け:

```bash
docker compose down        # コンテナを停止・削除（ログイン状態は残る）
docker compose down -v     # ログイン状態や設定のボリュームも削除
```

## VS Code（Dev Containers）で開く

VS Code と [Dev Containers 拡張機能](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)があれば、このリポジトリのフォルダを開いて、コマンドパレットの **Dev Containers: Reopen in Container** でコンテナの中に入れます。

- [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) は同じフォルダの `compose.yaml` をそのまま使います。sandbox・firewall・proxy の 3 つが起動し、通信制限やコンテナの権限は `docker compose up` で起動したときと同じです。VS Code のウィンドウを閉じると 3 つとも止まります。
- Docker Compose v2.24 以降が必要です（上書き用の [`.devcontainer/compose.devcontainer.yaml`](.devcontainer/compose.devcontainer.yaml) で `!reset` を使うため）。
- イメージは、開くときにホスト側で `docker compose -f .devcontainer/compose.yaml build` を実行して作ります（`initializeCommand`）。Dev Containers 自身にビルドさせると、Buildx 0.37.2 以降で `additional privileges requested: pass "--allow=fs.read=..."` というエラーになるためです（[既知の不具合](https://github.com/microsoft/vscode-remote-release/issues/11896)）。Claude Code などを最新版に上げるときは、ホスト側の `.devcontainer` で `docker compose build --no-cache sandbox` を実行してから **Dev Containers: Rebuild Container** を実行します。
- Compose のプロジェクト名は `compose.yaml` で `skill-sandbox` に固定しているので、Dev Containers で開いていても、ホスト側の `.devcontainer` で `docker compose exec proxy reload` や `docker compose logs proxy` を実行できます。`./scripts/verify.sh` もそのまま使えます。
- 開くフォルダは `/workspace`（ホストの `workspace/project`）です。スキルは `/home/claude/.claude/skills`（ホストの `workspace/skills`）にあるので、編集するときは **File: Add Folder to Workspace** で追加するか、ホスト側のエディタで開いてください。
- Linux では、`docker compose` で使う場合と同じく `.devcontainer/.env` の `USER_UID` / `USER_GID` をホストのユーザーに合わせてください。Dev Containers の uid を自動で合わせる機能（`updateRemoteUserUID`）は切っています。ホストのユーザーが root だとコンテナ内のユーザーを uid 0 に書き換えてしまい、非 root で動かす制限が外れるためです。
- devcontainer の features は使っていません。features は外部から取得したスクリプトを root で実行するためです。必要なツールは [`.devcontainer/sandbox/Dockerfile`](.devcontainer/sandbox/Dockerfile) に追加してください。
- VS Code Server 本体は、Dev Containers がホスト側でダウンロードしてコンテナに転送するので、許可リストへの追加は不要です（[公式 FAQ](https://code.visualstudio.com/docs/remote/faq#_what-are-the-connectivity-requirements-for-vs-code-server)）。拡張機能はコンテナの中からプロキシ経由でインストールするため、Marketplace（`marketplace.visualstudio.com`、`*.gallery.vsassets.io`、`*.gallerycdn.vsassets.io`）を許可しています。拡張機能を入れないなら、[`.devcontainer/proxy/allowed-domains.txt`](.devcontainer/proxy/allowed-domains.txt) のその行をコメントアウトしてかまいません。
- VS Code Server と拡張機能はコンテナ内のホームディレクトリに入るので、コンテナを作り直すと入れ直しになります。
- VS Code Server が送ろうとするテレメトリなどは許可リストにないので、`docker compose logs proxy` に `TCP_DENIED` の行が出ることがあります。止まっても動作には影響しません。

### Dev Containers で開くときの注意（ホストとのつながり）

`docker compose exec` でシェルに入る場合と違って、VS Code はホストとコンテナの間に専用の通信路を作り、ホスト側の機能をコンテナから使えるようにします。外部への通信制限（プロキシの許可リスト）は変わりませんが、ホストから切り離す度合いは `docker compose exec` より弱くなります。

- **認証情報**: 既定では、ホストの Git の認証情報・`~/.gitconfig`・Docker の認証情報・GitHub CLI のトークンがコンテナから使えるようになります。`github.com` は許可しているので、そのままだとコンテナ内のコードがホストのアカウントでリポジトリに書き込めてしまいます。`devcontainer.json` で次の設定をオフにしていますが、これらは VS Code のホスト側で読まれる設定で、拡張機能のバージョンによっては `devcontainer.json` からの指定が効かない可能性があります。確実にするため、ホストの VS Code のユーザー設定（`settings.json`）にも同じものを入れておくことをおすすめします。

  ```jsonc
  "dev.containers.copyGitConfig": false,
  "dev.containers.gitCredentialHelperConfigLocation": "none",
  "dev.containers.dockerCredentialHelper": false,
  "dev.containers.githubCLILoginWithToken": false
  ```

- **SSH エージェント**: ホストで SSH エージェントが動いていると、Dev Containers は自動でコンテナに転送します（[公式ドキュメント](https://code.visualstudio.com/remote/advancedcontainers/sharing-git-credentials)）。プロキシは 443 番ポートの TLS しか通さないので、外部への SSH 接続には使えません。気になる場合は、Dev Containers で開く前にエージェントを止めるか、鍵を外しておいてください。
- **その他**: コンテナ内の拡張機能やターミナルからホストのブラウザで URL を開く、コンテナのポートをホストに転送する、といった VS Code の機能も使えます。
- 中身を確かめていないスキルや、信用できないコードを試すときは、VS Code ではなく `docker compose exec sandbox bash` で入るほうが安全です。

## ディレクトリ構成とマウント

```text
.
├── .devcontainer/
│   ├── devcontainer.json          VS Code（Dev Containers）用の設定
│   ├── compose.yaml               sandbox・firewall・proxy の構成
│   ├── compose.devcontainer.yaml  Dev Containers で開くときだけ使う上書き
│   ├── .env.example               .env のひな形（.env もここに置く）
│   ├── sandbox/                   sandbox のイメージ（Dockerfile、link-ai-tools.sh）
│   ├── firewall/                  firewall のイメージと iptables の設定
│   └── proxy/                     proxy（Squid）のイメージ、設定、許可ドメイン一覧
├── scripts/verify.sh              制限が効いているかの確認
└── workspace/
    ├── skills/                    開発中のスキル
    └── project/                   スキルを試す作業ディレクトリ
```

| ホスト | コンテナ | 用途 |
| --- | --- | --- |
| `./workspace/skills` | `/home/claude/.claude/skills` | 開発中のスキル。ここに置いたスキルはユーザースキルとして Claude Code に読み込まれる |
| `./workspace/project` | `/workspace` | スキルを試すための作業ディレクトリ（コンテナ起動時のカレント） |
| ボリューム `claude-config` | `/home/claude/.claude` | ログイン情報・設定・履歴（`CLAUDE_CONFIG_DIR`） |
| `./.devcontainer/proxy`（proxy コンテナ側） | `/etc/squid/sandbox`（読み取り専用） | プロキシ設定と許可ドメイン一覧 |

これ以外のホストのファイル（ホームディレクトリ、SSH 鍵、ホストの `~/.claude` など）はコンテナからは見えません。

## スキルの作り方と試し方

1. `workspace/skills/<スキル名>/SKILL.md` を作成します（サンプル: [`workspace/skills/hello-sandbox`](workspace/skills/hello-sandbox/SKILL.md)）。
2. コンテナ内で `claude` を起動し、スキルが発火しそうな依頼を投げます。サンプルなら「hello sandbox」と入力します。
3. `/skills` で読み込まれているスキルの一覧を確認できます。
4. ホスト側のエディタで `SKILL.md` を編集すると、Claude Code がスキルのフォルダを監視して読み込み直します。反映されないときは `claude` を起動し直してください。

テスト用のファイルやリポジトリは `workspace/project` に置いてください。スキルが作業ディレクトリに書き込んだ結果はホストからそのまま確認できます。

## 設定（`.devcontainer/.env`）

`.env` は `compose.yaml` と同じ `.devcontainer` フォルダに置きます（Git には含めません）。

| 変数 | 既定値 | 説明 |
| --- | --- | --- |
| `USER_UID` / `USER_GID` | `1000` | コンテナ内ユーザーの uid / gid。ホストのユーザーに合わせる |
| `ANTHROPIC_API_KEY` | （空） | 指定すると対話ログインの代わりに API キーで認証 |
| `GH_TOKEN` | （空） | 指定すると `gh auth login` の代わりにこのトークンで `gh` を使う。権限を絞ったトークンにする（[gh（GitHub CLI）](#ghgithub-cli)） |

`USER_UID` / `USER_GID` を変えたら `docker compose build` で再ビルドしてください。

### Claude Code の更新

コンテナ内の自動アップデートと `claude update` は使わず、イメージの再ビルドで更新します（Claude Code は root 所有で入っているので、コンテナ内からは書き換えられません）。

```bash
cd .devcontainer
# 最新版に上げる（ビルドキャッシュが効くと gist やインストーラーが実行されないため --no-cache を付ける）
docker compose build --no-cache sandbox
docker compose up -d
```

gist のインストーラーは常にその時点の最新版を入れるので、バージョンの固定はできません。

ネイティブ版の自動アップデートや `claude update` は `downloads.claude.ai` に接続しますが、このイメージではビルド時に入れて再ビルドで更新し、ビルドはプロキシの制限の外で行われるため、許可リストに `downloads.claude.ai` を入れる必要はありません。実行ファイルを含むプラグインを使う場合だけ、[`.devcontainer/proxy/allowed-domains.txt`](.devcontainer/proxy/allowed-domains.txt) のコメントを外してください。

## Claude Code と AI ツールの入れ方

Claude Code と、いろいろなエージェントでスキルや作業を試すための CLI を入れています。どれも npm では入れず、spec-viewer と同じ gist（[`install-ai-tools.sh`](https://gist.github.com/DIO0550/148b1392cf435ba3562da0d398bee442) と、その前提の [`pnpm-safe-chain-setup.sh`](https://gist.github.com/DIO0550/dcc09dc9d2dcefceb9b0cda183e7ef8e)）を、編集せずにビルド時に取得して実行しています。

| コマンド | ツール |
| --- | --- |
| `claude` | Claude Code（ネイティブ版） |
| `copilot` | GitHub Copilot CLI |
| `codex` | OpenAI Codex CLI |
| `cursor-agent`（`agent`） | Cursor CLI |
| `agy` | Antigravity CLI |
| `opencode` | OpenCode |

- gist は root 権限・`HOME=/opt/ai-tools` で実行するので、各ツールは `/opt/ai-tools` に root 所有で入ります。後始末は [`.devcontainer/sandbox/link-ai-tools.sh`](.devcontainer/sandbox/link-ai-tools.sh) が行い、コマンドを `/usr/local/bin` にリンクします。sandbox のユーザーはバイナリを書き換えられません（各ツールの自動アップデートも効きません）。
- gist を更新すると、次のビルドからそのまま反映されます。gist の置き場所は Dockerfile の `SAFE_CHAIN_GIST_URL` / `AI_TOOLS_GIST_URL` で変えられます。
- Claude Code 以外の各ツールのログインと API の接続先は、[`.devcontainer/proxy/allowed-domains.txt`](.devcontainer/proxy/allowed-domains.txt) の「Claude Code 以外の AI ツール」の欄で**既定で許可しています**（Copilot CLI のログイン用に `github.com` も許可）。使わないツールの行はコメントアウトし、`docker compose exec proxy reload` で反映すれば閉じられます。書いてあるのは代表的な接続先なので、足りないときは `docker compose logs proxy` の `TCP_DENIED` の行を見て追加します。
- ログインは各ツールの案内に従います。コンテナにはブラウザがないので、表示された URL をホストのブラウザで開いてください（Codex は `codex login --device-auth` を使うと手順が簡単です）。
- Claude Code 以外のログイン情報・設定はホームディレクトリ（コンテナ内）に保存されるので、`docker compose down` やイメージの再ビルドでコンテナを作り直すと消えます。止めるだけなら `docker compose stop` / `docker compose start` を使ってください。
- 合計で 1.7GB ほどあるため、イメージが大きくなり、ビルドにも時間がかかります。
- 更新は Claude Code と同じくイメージの再ビルドで行います（`docker compose build --no-cache sandbox`）。gist とインストーラーは毎回その時点の最新版を取得します。
- 各ツールが使えて、書き換えられないこと、npm 版の Claude Code が入っていないことは [`scripts/verify.sh`](scripts/verify.sh) でも確認します。

### gh（GitHub CLI）

`gh` も spec-viewer と同じ gist（[`install-gh-local.sh`](https://gist.github.com/DIO0550/f5999a0512a369a232b7d4f824f0cc08)）を、編集せずにビルド時に取得して実行しています。AI ツールと同じく root 権限・`HOME=/opt/ai-tools` で入れて `/usr/local/bin/gh` にリンクするので、sandbox のユーザーは書き換えられません。

- 入るのはビルド時点の最新リリースです。更新はイメージの再ビルドで行います（`docker compose build --no-cache sandbox`）。
- gist は `uname -m` で amd64 / arm64 を判定し、公式のチェックサムで確認してから入れます（Apple Silicon の Mac でも arm64 版が入ります）。バージョンは GitHub API ではなく `github.com` の releases/latest から取るので、API の回数上限には当たりません。
- 接続先の `github.com` と `api.github.com` は既定で許可しているので、追加の設定はいりません（[`allowed-domains.txt`](.devcontainer/proxy/allowed-domains.txt) で Copilot CLI の行を閉じるときも、gh を使うならこの 2 つは残してください）。

#### ログインとトークンの扱い

コンテナ内の AI ツールも、同じ認証情報で `gh` を実行できます（リポジトリへの push、PR やイシューの作成・削除なども含みます）。**渡すトークンは、試すのに必要なリポジトリと権限だけに絞ってください。**

- おすすめは [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) です。「Repository access」で対象のリポジトリだけを選び、権限は必要なものだけ（読むだけなら Contents と Metadata の Read-only、PR を作るなら Pull requests の Read and write を足す）にして、有効期限も短めにします。
- トークンは `.devcontainer/.env` の `GH_TOKEN` に書くと、コンテナ内で `gh` がそのまま使います（`.env` は Git に含めません）。変えたら `docker compose up -d` でコンテナを作り直してください。
- `GH_TOKEN` を空にしておけば、コンテナ内で `gh auth login` を実行して対話でログインすることもできます（「Login with a web browser」を選び、表示された URL をホストのブラウザで開きます）。この場合のトークンはコンテナ内の `~/.config/gh` に保存され、コンテナを作り直すと消えます。対話ログインで発行されるトークンは、そのアカウントが触れるすべてのリポジトリに及ぶので、権限を絞りたいときは `GH_TOKEN` を使ってください。
- spec-viewer と違い、ホストの `~/.config/gh` はマウントしていません。ホストのログイン情報をコンテナに持ち込まないためです（Dev Containers の `dev.containers.githubCLILoginWithToken` も無効にしています）。
- HTTPS で `git push` するときに `gh` の認証情報を使うには、コンテナ内で `gh auth setup-git` を実行します。

### pnpm / npm のサプライチェーン対策

sandbox のユーザー（`claude`）のシェルにも、spec-viewer と同じく [`pnpm-safe-chain-setup.sh`](https://gist.github.com/DIO0550/dcc09dc9d2dcefceb9b0cda183e7ef8e) を適用しています。コンテナ内でスキルやツールを試すときにパッケージを入れる場合も、次の設定が効きます。

- pnpm の `minimumReleaseAge` が 7200（公開から 5 日未満のバージョンは入れない）
- npm の `ignore-scripts`（インストール時のスクリプトを実行しない）
- [safe-chain](https://github.com/AikidoSec/safe-chain) が npm / pnpm / npx などを包み、既知のマルウェアを含むパッケージのインストールを止める

既定ではパッケージのレジストリを許可していないので、コンテナ内でパッケージを入れるには [`.devcontainer/proxy/allowed-domains.txt`](.devcontainer/proxy/allowed-domains.txt) の `registry.npmjs.org` と、safe-chain がマルウェア一覧を取得する `malware-list.aikido.dev` のコメントを外してください。これらの設定が効いていることは [`scripts/verify.sh`](scripts/verify.sh) で確認します。

## ネットワーク制限（ファイアウォール＋許可リスト型プロキシ）

```
sandbox ──(HTTPS_PROXY)──▶ proxy (Squid) ──(許可ドメインのみ)──▶ インターネット
   └ firewall の iptables: プロキシ（IP アドレス 1 つ、ポート 3128）以外への送信はすべて拒否

sandbox ネットワーク: firewall(+sandbox), proxy  ← internal: true（外への経路なし）
egress ネットワーク : proxy のみ                  ← 外に出られるのはここだけ
```

通信は 3 段階で制限しています。どれか 1 つが設定ミスなどで効かなくなっても、残りで止まるようにしています。

1. **内部ネットワーク**: sandbox がいるのは `internal: true` の Docker ネットワークだけです。外への経路がないので、プロキシを経由しない通信（直接の TCP 接続、IP 直打ち、`HTTPS_PROXY` を無視するツール）は失敗します。外部ドメインの DNS 解決もできません。
2. **ファイアウォール（iptables）**: sandbox から出ていく通信は、プロキシコンテナの IP アドレスのポート 3128 への TCP 接続だけを許可し、それ以外はすべて拒否します。ホスト（Docker のブリッジ経由で届くポート）、同じネットワークにつながった他のコンテナ、プロキシの別ポート、UDP、ICMP、IPv6 も通りません（DNS はコンテナ内のループバックにある Docker 内蔵 DNS だけ使えます）。
3. **許可リスト型プロキシ**: プロキシを通る通信も、許可したドメインにしか接続できません。接続先として指定したホスト名（CONNECT）に加えて、TLS で名乗るサーバー名（SNI）も許可リストと照合します。

プロキシの動作:

- 外に出られるのは `proxy` コンテナ（Squid）経由だけです。`HTTPS_PROXY` / `HTTP_PROXY` は `.devcontainer/compose.yaml` で設定済みで、Claude Code・curl・git・npm・pip などはそのままプロキシを使います。
- [`.devcontainer/proxy/allowed-domains.txt`](.devcontainer/proxy/allowed-domains.txt) に書かれたドメインへの接続だけを中継します。接続先ポートは 443（HTTPS）と 80 のみで、IP アドレス直指定や許可していないサブドメインは拒否します。
- 許可ドメインに接続すると見せかけて、TLS では別のサーバー名を名乗る接続は切断します。接続先のホスト名だけを見るプロキシでは、この方法で同じ CDN に載っている別のサイトに届いてしまうためです（curl なら `--connect-to` オプション 1 つで試せます）。TLS 以外の通信をトンネルに流した場合も切断します。
- 許可した通信の中身は復号しません。プロキシが見るのは、接続先のホスト名・ポートと、TLS の最初のメッセージに平文で入っているサーバー名だけです。
- プロキシは一般ユーザーで動き、Linux capabilities は持ちません。ポートはホストに公開していません。

### ファイアウォールの仕組み

ファイアウォールは [`.devcontainer/firewall/init-firewall.sh`](.devcontainer/firewall/init-firewall.sh) が専用の `firewall` コンテナで設定します。sandbox は `network_mode: service:firewall` でこのコンテナのネットワーク名前空間を共有するので、ルールは sandbox の通信にそのまま適用されます。

- iptables を操作する `NET_ADMIN` 権限を持つのは `firewall` コンテナだけです。sandbox は capabilities をすべて削除しているので、コンテナ内で root 相当の操作ができてもルールを変更できません。
- 公式の [devcontainer](https://code.claude.com/docs/en/devcontainer) はコンテナ自身に `NET_ADMIN` を与えて起動時にルールを設定しますが、この構成では Claude Code が動くコンテナにその権限を渡さずに済みます。
- 許可する宛先は、起動時に調べたプロキシコンテナの IP アドレス 1 つだけです。サブネット全体を許可すると、ホスト側で 3128 番ポートを待ち受けているサービス（別のプロキシなど）にも届いてしまうためです。
- ルールを設定し、プロキシにつながることと既定ポリシーが DROP になったことを確認してから healthy になります。sandbox はそれまで起動しません。
- `docker compose restart` や `docker compose up -d` で `proxy` や `firewall` が再起動・再作成されたときは、sandbox も自動で起動し直します。
- `firewall` コンテナが Compose を介さずに再起動した場合（`docker restart` など）、sandbox はネットワークインターフェースを失い、どこにも通信できなくなります（制限が外れることはありません）。`docker compose ps` で sandbox が `unhealthy` と表示されるので、`docker compose restart sandbox` で復旧してください。

ルールの確認:

```bash
docker compose exec firewall iptables -L -v -n
```

### 既定で許可しているドメイン

[公式ドキュメントの Network access requirements](https://code.claude.com/docs/en/network-config#network-access-requirements) のうち、Claude Code を使うのに必須のものと、Artifact 用のものは次のとおりです。このほかに、イメージに入っている Claude Code 以外の AI ツールの接続先（と `github.com`）と、VS Code の拡張機能の Marketplace も許可しています（[Claude Code と AI ツールの入れ方](#claude-code-と-ai-ツールの入れ方)、[VS Code（Dev Containers）で開く](#vs-codedev-containersで開く)）。

| ドメイン | 用途 |
| --- | --- |
| `api.anthropic.com` | Claude API（WebFetch のドメイン安全チェック、機能フラグ取得を含む） |
| `claude.ai` | claude.ai アカウントでの認証 |
| `platform.claude.com` | OAuth トークンの交換・更新（claude.ai / Console どちらのログインでも必要） |
| `*.frame.claudeusercontent.com` | [Artifact](https://code.claude.com/docs/en/artifacts.md) の内容の読み込み（Artifact の公開は `api.anthropic.com` 経由） |

許可リストに入れていない通信先を使う機能は、`.devcontainer/compose.yaml` の環境変数で止めています。

| 環境変数 | 止めるもの |
| --- | --- |
| `DISABLE_ERROR_REPORTING=1` | エラーレポート（Datadog） |
| `ENABLE_CLAUDEAI_MCP_SERVERS=false` | claude.ai で設定した MCP コネクタ（`mcp-proxy.anthropic.com`） |

自動アップデートは `.devcontainer/sandbox/Dockerfile` の `DISABLE_AUTOUPDATER=1` で止めています（Claude Code 自体も root 所有なので書き換えられません）。`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`、`DISABLE_TELEMETRY`、`DO_NOT_TRACK` は**設定しないでください**。これらは Claude Code が Anthropic から機能フラグを取得するのも止めるので、Remote Control、claude.ai と同期したスキル・プラグイン、advisor ツールなど、機能フラグで有効になる新機能が使えなくなります（[公式ドキュメント](https://code.claude.com/docs/en/env-vars#features-that-need-feature-flag-fetching)）。機能フラグの取得先は許可済みの `api.anthropic.com` です。使用状況のテレメトリの一部は Datadog（`http-intake.logs.us5.datadoghq.com`）にも送られますが、許可リストにないのでプロキシで止まります。

### 許可ドメインの追加

`.devcontainer/proxy/allowed-domains.txt` に 1 行 1 ドメインで追記し、プロキシに再読み込みさせます（コンテナの再起動は不要）。

```bash
cd .devcontainer
echo "registry.npmjs.org" >> proxy/allowed-domains.txt
docker compose exec proxy reload
```

`reload` は設定を検査してから反映します。書き間違いがあるときは何も変更せずにエラーを表示するので、動作中のプロキシが止まることはありません。

`example.com` は完全一致、`.example.com` はサブドメインも含めて一致します。プラグインのインストール（`registry.npmjs.org`）や PyPI など、よく使うものはファイル内にコメントアウトして用意してあります。

許可したドメインには、コンテナ内のコードが自由にデータを送れることに注意してください。必要なものだけを追加するのが原則です。

### 通信ログの確認

```bash
docker compose logs -f proxy
```

接続 1 回につき 1 行で、結果・接続先・TLS で名乗ったサーバー名（`sni`）が記録されます。スキルがどこに通信しようとしたかを確認するのに使えます。

```
2026-11-11 13:11:11 172.18.0.3 TCP_TUNNEL/200 CONNECT api.anthropic.com:443 sni=api.anthropic.com tls=splice   ← 中継した
2026-11-11 13:11:11 172.18.0.3 TCP_DENIED/200 CONNECT example.com:443 sni=example.com tls=bump                 ← 許可リストにないので拒否
2026-11-11 13:11:11 172.18.0.3 NONE_NONE/200 CONNECT api.anthropic.com:443 sni=example.com tls=terminate       ← サーバー名が違うので切断
```

拒否した接続でも数字は `200` になります（Squid は拒否の応答を TLS の中で返すため）。拒否かどうかは `TCP_DENIED` や `tls=terminate` で判断してください。

### 制限の確認

起動した状態で、ホスト側から次のスクリプトを実行します。

```bash
./scripts/verify.sh
```

sandbox の中から実際に接続を試して、次の点を確認します。1 つでも問題があれば `NG` と表示して終了コード 1 を返します。

- 許可ドメイン（`api.anthropic.com`）にはプロキシ経由で接続できる
- 許可していないドメイン・サブドメイン、IP アドレス直指定、443 以外のポートはプロキシが拒否する
- 許可ドメインに接続して別のサーバー名（SNI）を名乗る接続、TLS 以外の通信は切断される
- プロキシを通さない外部への接続、ホスト側のポートへの接続はできない
- 外部ドメインの DNS 解決はできない
- root 以外のユーザーで動いていて、capabilities を持たず、`no-new-privileges` が有効
- ファイアウォールの既定ポリシーが DROP で、許可ルールはプロキシ宛ての 1 つだけ
- Claude Code と各 AI ツール、`gh` が gist で入れたもので、sandbox のユーザーが書き換えられない（npm 版の Claude Code は入っていない）
- sandbox のユーザーのシェルで pnpm の `minimumReleaseAge`、npm の `ignore-scripts`、safe-chain が有効

同じスクリプトを GitHub Actions（[`.github/workflows/verify.yml`](.github/workflows/verify.yml)）でも実行しています。プルリクエストごとに、何も入っていない環境でイメージをビルドして起動し、制限が効いていることを確認します。Dev Containers と同じ手順（[Dev Containers CLI](https://github.com/devcontainers/cli) の `devcontainer up`）で起動した場合も同じスクリプトで確認し、あわせてコンテナ内の VS Code Server から拡張機能をインストールできることも確かめています。

### この方式の限界

- 許可したドメインには、コンテナ内のコードが任意のデータを送れます。通信の中身は復号・検査しません。たとえば `api.anthropic.com` を許可している以上、別のアカウントの API キーを使ってそこにデータを送ることは止められません。
- サーバー名の検査は、TLS の最初のメッセージに平文で書かれた名前を見ています。本当の接続先を暗号化する仕組み（ECH）を使われると、プロキシからは確認できません。許可ドメインと同じ CDN に載っている別サイトへの通信まで確実に止めるには、プロキシで TLS を復号して検査する構成（sandbox に専用の CA を信頼させる）が必要です。
- イメージのビルド（`docker compose build`）は通常の Docker ネットワークで行われるため、この制限の対象外です。

## その他のセキュリティ上の制限

`.devcontainer/compose.yaml` で次の制限もかけています。

- `cap_drop: ALL` と `no-new-privileges`（sudo なし、root への昇格不可）
- `pids_limit: 512`、`mem_limit: 4g`、`cpus: 2`
- `/tmp` は 512MB の tmpfs
- proxy コンテナは一般ユーザーで動作し、capabilities なし、`no-new-privileges`、ルートファイルシステムは読み取り専用
- firewall コンテナは `NET_ADMIN` だけを持ち、ルートファイルシステムは読み取り専用
- `USER_UID=0`（root）を指定するとビルドが失敗します

## トラブルシューティング

- **`/workspace` に書き込めない (`Permission denied`)**: ホストのユーザーとコンテナの uid が一致していません。`.devcontainer/.env` の `USER_UID` / `USER_GID` を `id -u` / `id -g` の値にして `docker compose up -d --build` で作り直してください。
- **ログインし直したい**: `docker compose down -v` で設定ボリュームを削除してから起動し直します。
- **何かのコマンドが証明書エラー（`self-signed certificate` など）や `403 Forbidden` で失敗する**: プロキシが接続先を拒否しています。HTTPS の場合、拒否の応答は `blocked-by-skill-sandbox-proxy` という名前の自己署名証明書で返るので、クライアントには証明書エラーとして見えます。`docker compose logs proxy` で `TCP_DENIED` の行を探し、必要なドメインなら `.devcontainer/proxy/allowed-domains.txt` に追加してください。証明書の検証を無効にしても接続できるようにはなりません。
- **sandbox から突然どこにもつながらなくなった**: `firewall` コンテナが再起動した可能性があります。`docker compose ps` で sandbox が `unhealthy` になっていないか確認し、`docker compose restart sandbox` を実行してください。
- **ビルドで `USER_UID must not be 0` と表示される**: `.devcontainer/.env` の `USER_UID` に 0 以外（通常は `id -u` の値）を指定してください。
- **Node.js の `fetch()` など、プロキシ設定を読まないツールが通信できない**: 内部ネットワークでは直接通信できないため想定どおりの動作です。そのツールのプロキシ設定を使ってください（Node.js 24 以降なら `NODE_USE_ENV_PROXY=1`）。
