#!/usr/bin/env bash
# 起動中のサンドボックスに対して、制限が実際に効いているかを確認するスクリプト。
#
#   docker compose up -d --build
#   ./scripts/verify.sh
#
# すべて OK なら終了コード 0、1 つでも NG があれば 1 を返す。
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
ok() { echo "OK  $*"; }
ng() { echo "NG  $*"; fail=1; }

echo "== ホスト側からの確認 =="

if docker compose exec -T firewall iptables -S OUTPUT 2>/dev/null | grep -qx -- '-P OUTPUT DROP'; then
  ok "ファイアウォールの既定ポリシーが DROP になっている"
else
  ng "ファイアウォールの既定ポリシーが DROP になっていない（firewall コンテナを確認してください）"
fi

accept_rules=$(docker compose exec -T firewall iptables -S OUTPUT 2>/dev/null | grep -c -- '--ctstate NEW -j ACCEPT' || true)
if [ "$accept_rules" = "1" ]; then
  ok "新規接続を許可するルールはプロキシ宛ての 1 つだけ"
else
  ng "新規接続を許可するルールが ${accept_rules} 個ある（1 個のはず）"
fi

if [ -z "$(docker compose port proxy 3128 2>/dev/null)" ]; then
  ok "プロキシのポートはホストに公開されていない"
else
  ng "プロキシのポートがホストに公開されている"
fi

echo
echo "== sandbox コンテナ内からの確認 =="

# 以降は sandbox コンテナの中で Node.js のスクリプトとして実行する
docker compose exec -T sandbox node - <<'NODE' || fail=1
const http = require('http'), net = require('net'), tls = require('tls'), dns = require('dns'), os = require('os'), fs = require('fs');
const { execFileSync } = require('child_process');

let failed = false;
const ok = (m) => console.log('OK  ' + m);
const ng = (m, detail) => { failed = true; console.log('NG  ' + m + (detail ? `  [${detail}]` : '')); };
const BLOCK_CN = 'blocked-by-skill-sandbox-proxy';
// ファイル自体か、置かれているディレクトリ（消して置き換えられる）に書き込めるか
const writable = (p) => [p, require('path').dirname(p)].some((x) => {
  try { fs.accessSync(x, fs.constants.W_OK); return true; } catch { return false; }
});

const proxyUrl = new URL(process.env.HTTPS_PROXY || process.env.https_proxy || 'http://proxy:3128');

// プロキシに CONNECT し、成功したら TLS を張って HTTP のステータス行まで読む
function viaProxy(host, port, { sni = host, raw = false } = {}) {
  return new Promise((resolve) => {
    const out = { connect: null, tls: false, cn: null, status: null, error: null };
    const finish = () => resolve(out);
    const timer = setTimeout(() => { out.error = out.error || 'TIMEOUT'; finish(); }, 15000);
    const done = () => { clearTimeout(timer); finish(); };
    const req = http.request({ host: proxyUrl.hostname, port: proxyUrl.port, method: 'CONNECT', path: `${host}:${port}` });
    req.on('error', (e) => { out.error = e.code || e.message; done(); });
    req.on('connect', (res, sock) => {
      out.connect = res.statusCode;
      if (res.statusCode !== 200) { sock.destroy(); return done(); }
      if (raw) {
        sock.on('data', () => { out.status = 'DATA'; });
        sock.on('error', (e) => { out.error = e.code; });
        sock.on('close', () => done());
        sock.write('SSH-2.0-OpenSSH_9.6\r\n');
        return;
      }
      // 証明書の検証は自前でやる（拒否時にプロキシが出す自己署名証明書の名前を読みたいため）
      const s = tls.connect({ socket: sock, servername: net.isIP(sni) ? undefined : sni, rejectUnauthorized: false }, () => {
        out.tls = true;
        out.authorized = s.authorized;
        out.cn = (s.getPeerCertificate().subject || {}).CN || null;
        s.write(`GET / HTTP/1.1\r\nHost: ${sni}\r\nConnection: close\r\n\r\n`);
      });
      s.once('data', (d) => { out.status = d.toString().split('\r\n')[0]; s.destroy(); done(); });
      s.on('error', (e) => { out.error = e.code || e.message; done(); });
      s.on('close', () => done());
    });
    req.end();
  });
}

// プロキシを使わない直接の TCP 接続
function direct(host, port) {
  return new Promise((resolve) => {
    const s = net.connect({ host, port, timeout: 4000 });
    s.on('connect', () => { s.destroy(); resolve('CONNECTED'); });
    s.on('timeout', () => { s.destroy(); resolve('TIMEOUT'); });
    s.on('error', (e) => resolve(e.code || 'ERROR'));
  });
}

const blocked = (r) => r.connect !== 200 || r.cn === BLOCK_CN || !r.tls;
const show = (r) => JSON.stringify(r);

(async () => {
  // --- 許可した通信は通る ---
  let r = await viaProxy('api.anthropic.com', 443);
  if (r.connect === 200 && r.tls && r.authorized && r.status) ok(`許可ドメイン api.anthropic.com にプロキシ経由で接続できる（${r.status}）`);
  else ng('許可ドメイン api.anthropic.com に接続できない', show(r));

  // --- 許可していない宛先はプロキシが拒否する ---
  for (const [desc, host, port] of [
    ['許可していないドメイン example.com', 'example.com', 443],
    ['許可していないサブドメイン evil.api.anthropic.com', 'evil.api.anthropic.com', 443],
    ['IP アドレス直接指定 1.1.1.1', '1.1.1.1', 443],
    ['許可ドメインの 443 以外のポート api.anthropic.com:22', 'api.anthropic.com', 22],
  ]) {
    r = await viaProxy(host, port);
    if (blocked(r)) ok(`${desc} はプロキシが拒否する`);
    else ng(`${desc} に接続できてしまう`, show(r));
  }

  // --- CONNECT は許可ドメイン、TLS のサーバー名（SNI）は別ドメイン ---
  r = await viaProxy('api.anthropic.com', 443, { sni: 'example.com' });
  if (!r.tls) ok('許可ドメインに CONNECT して別のサーバー名（SNI）を名乗る接続は切断される');
  else ng('SNI を偽った接続が通ってしまう', show(r));

  // --- CONNECT のあとに TLS 以外の通信を流す ---
  r = await viaProxy('api.anthropic.com', 443, { raw: true });
  if (r.status !== 'DATA') ok('許可ドメインへのトンネルに TLS 以外の通信を流すと切断される');
  else ng('TLS 以外の通信が通ってしまう', show(r));

  // --- プロキシを通らない通信はできない ---
  let d = await direct('1.1.1.1', 443);
  if (d !== 'CONNECTED') ok(`プロキシを通さない外部への直接接続はできない（${d}）`);
  else ng('プロキシを通さずに外部へ接続できてしまう');

  // ホスト（Docker ブリッジのゲートウェイ = サブネットの先頭アドレス）への接続
  const nic = Object.values(os.networkInterfaces()).flat().find((i) => i.family === 'IPv4' && !i.internal);
  if (nic) {
    const ip = nic.address.split('.').map(Number), mask = nic.netmask.split('.').map(Number);
    const gw = ip.map((o, i) => o & mask[i]); gw[3] += 1;
    const gateway = gw.join('.');
    const results = [];
    for (const port of [Number(proxyUrl.port), 22, 80, 2375]) results.push(`${port}:${await direct(gateway, port)}`);
    if (!results.some((x) => x.endsWith('CONNECTED'))) ok(`ホスト側（${gateway}）のポートには接続できない`);
    else ng(`ホスト側（${gateway}）のポートに接続できてしまう`, results.join(' '));
  } else {
    ng('ネットワークインターフェースが見つからない（firewall コンテナが再起動した可能性。docker compose restart sandbox を実行）');
  }

  // 外部ドメインの DNS 解決（古い Docker では内部ネットワークからも外へ問い合わせが漏れる）
  const resolved = await new Promise((res) => dns.resolve4('example.com', (e, a) => res(e ? null : a)));
  if (!resolved) ok('外部ドメインの DNS 解決はできない');
  else ng('外部ドメインを DNS 解決できてしまう（Docker を 25.0.5 / 26.0 以降に更新してください）', resolved.join(','));

  // --- 権限 ---
  const status = fs.readFileSync('/proc/self/status', 'utf8');
  const capEff = (status.match(/^CapEff:\s*(\S+)/m) || [])[1];
  const noNewPrivs = (status.match(/^NoNewPrivs:\s*(\S+)/m) || [])[1];
  if (process.getuid() !== 0) ok(`root 以外のユーザーで動いている（uid=${process.getuid()}）`);
  else ng('root で動いている');
  if (/^0+$/.test(capEff || '')) ok('Linux capabilities を持っていない');
  else ng('Linux capabilities を持っている', capEff);
  if (noNewPrivs === '1') ok('no-new-privileges が有効');
  else ng('no-new-privileges が無効');

  // --- Claude Code ---
  try { ok('claude コマンドが使える（' + execFileSync('claude', ['--version'], { encoding: 'utf8' }).trim() + '）'); }
  catch (e) { ng('claude コマンドが実行できない', e.message.split('\n')[0]); }
  // ログインシェルでも npm 版（root 所有）の claude が使われ、sandbox のユーザーが書き換えられない
  try {
    const claudePath = fs.realpathSync(execFileSync('bash', ['-lc', 'command -v claude'], { encoding: 'utf8' }).trim());
    if (!claudePath.includes('/node_modules/@anthropic-ai/claude-code/')) ng('claude が npm 版ではない', claudePath);
    else if (writable(claudePath)) ng('claude を sandbox のユーザーが書き換えられる', claudePath);
    else ok('claude は npm 版で、書き換えられない');
  } catch (e) { ng('claude の場所を確認できない', e.message.split('\n')[0]); }

  // --- Claude Code 以外の AI ツール（gist で入れたもの） ---
  for (const cmd of ['copilot', 'codex', 'cursor-agent', 'agent', 'agy', 'opencode']) {
    try {
      const target = fs.realpathSync(execFileSync('bash', ['-lc', `command -v ${cmd}`], { encoding: 'utf8' }).trim());
      if (writable(target)) { ng(`${cmd} を sandbox のユーザーが書き換えられる`, target); continue; }
      const ver = execFileSync(cmd, ['--version'], { encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'] }).trim().split('\n')[0];
      ok(`${cmd} が使える（${ver}）`);
    } catch (e) { ng(`${cmd} が実行できない`, (e.message || '').split('\n')[0]); }
  }

  process.exit(failed ? 1 : 0);
})();
NODE

echo
if [ "$fail" = "0" ]; then
  echo "すべての確認に成功しました。"
else
  echo "NG の項目があります。docker compose ps と docker compose logs で状態を確認してください。"
fi
exit "$fail"
