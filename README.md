# skill-sandbox

Claude Code のスキル（Agent Skills）を、ホスト環境から隔離された Docker コンテナの中で開発・テストするためのサンドボックスです。

- 非 root ユーザー（`claude`）で動作し、Linux capabilities はすべて削除、`no-new-privileges` を有効化
- ホストから見えるのは `./workspace/skills` と `./workspace/project` の 2 フォルダだけ
- ログイン状態や設定は名前付きボリュームに保存され、ホストの `~/.claude` には触れません

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

`USER_UID` / `USER_GID` や `CLAUDE_CODE_VERSION` を変えたら `docker compose build` で再ビルドしてください。コンテナ内の自動アップデートは無効化しているので、Claude Code の更新も再ビルドで行います。

## セキュリティ上の制限

`compose.yaml` で次の制限をかけています。

- `cap_drop: ALL` と `no-new-privileges`（sudo なし、root への昇格不可）
- `pids_limit: 512`、`mem_limit: 4g`、`cpus: 2`
- `/tmp` は 512MB の tmpfs

ネットワークは Anthropic API に接続するため通常どおり外部に出られます。外向き通信も絞りたい場合は、プロキシやファイアウォールを別途組み合わせてください。

## トラブルシューティング

- **`/workspace` に書き込めない (`Permission denied`)**: ホストのユーザーとコンテナの uid が一致していません。`.env` の `USER_UID` / `USER_GID` を `id -u` / `id -g` の値にして `docker compose up -d --build` で作り直してください。
- **ログインし直したい**: `docker compose down -v` で設定ボリュームを削除してから起動し直します。
