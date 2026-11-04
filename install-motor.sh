#!/usr/bin/env bash
# Installs a Mia motor on a Linux machine as a systemd user service (plan 2026-11-04-versoes-e-atualizacao).
#
#   curl -fsSL https://raw.githubusercontent.com/richardoliveira/Mia-releases/main/install-motor.sh | bash
#
# It downloads the newest motor release, checks its signature with the release key, installs it with pnpm, writes
# ~/.mia/motor.json (kept when it exists), starts the service and prints what to paste in Mia (Configurações › Motores ›
# Adicionar motor). The motor then updates itself. Needs Node.js 24+, pnpm (or corepack), git, and Claude Code and/or Codex.
#
# Overrides: MIA_DIR (motor folder, ~/mia/motor), MIA_CONF_DIR (~/.mia), MIA_PORT (first free of 7337-7347),
# MIA_SERVICE (mia-motor), MIA_MOTOR_FEED (the release manifest).
set -euo pipefail

FEED="${MIA_MOTOR_FEED:-https://raw.githubusercontent.com/richardoliveira/Mia-releases/main/motor.json}"
KEY="4yt3SZsr4cDqBaLHkKoTD3TG+wK5G7WsWQVopdlS6ro=" # the release key (app/Resources/Info.plist SUPublicEDKey)
DIR="${MIA_DIR:-$HOME/mia/motor}"
CONF_DIR="${MIA_CONF_DIR:-$HOME/.mia}"
SERVICE="${MIA_SERVICE:-mia-motor}"
CONF="$CONF_DIR/motor.json"

say() { printf '%s\n' "$*"; }
die() { printf 'install-motor: %s\n' "$*" >&2; exit 1; }

# 1. What the motor needs
[ "$(uname -s)" = Linux ] || die "this installer is for Linux; on a Mac the motor comes with the Mia app"
command -v systemctl >/dev/null || die "systemd is required (systemctl not found)"
for c in curl tar git; do command -v "$c" >/dev/null || die "$c is required"; done
NODE="$(command -v node || true)"
[ -n "$NODE" ] || die "Node.js 24 or newer is required: https://nodejs.org (or: nvm install 24)"
[ "$("$NODE" -p 'process.versions.node.split(".")[0]')" -ge 24 ] || die "Node.js 24 or newer is required (found $("$NODE" -v))"
if command -v pnpm >/dev/null; then PNPM=(pnpm); elif command -v corepack >/dev/null; then PNPM=(corepack pnpm); else die "pnpm is required: npm i -g pnpm"; fi
CLAUDE="$(command -v claude || true)"; CODEX="$(command -v codex || true)"
[ -n "$CLAUDE$CODEX" ] || say "warning: neither Claude Code nor Codex found; install one and sign in before using this motor"

if [ -d "$DIR" ] && [ ! -f "$DIR/.release" ]; then
  die "$DIR exists and is not a release install; move it away or set MIA_DIR"
fi

# 2. Download the newest release and check its signature before anything is unpacked
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$FEED" -o "$TMP/manifest.json" || die "cannot read $FEED"
read -r VERSION URL SIG LEN < <("$NODE" -e '
  const m = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")), p = m.packages.any
  console.log(m.version, p.url, p.edSignature, p.length)' "$TMP/manifest.json")
say "Mia motor $VERSION"
curl -fsSL "$URL" -o "$TMP/motor.tgz" || die "cannot download $URL"
"$NODE" -e '
  const c = require("crypto"), b = require("fs").readFileSync(process.argv[1])
  const key = c.createPublicKey({ key: Buffer.concat([Buffer.from("302a300506032b6570032100", "hex"), Buffer.from(process.argv[2], "base64")]), format: "der", type: "spki" })
  if (b.length !== Number(process.argv[4]) || !c.verify(null, b, key, Buffer.from(process.argv[3], "base64"))) process.exit(1)' \
  "$TMP/motor.tgz" "$KEY" "$SIG" "$LEN" || die "the package signature does not match; nothing was installed"

# 3. Install into a fresh folder, then put it in place
NEW="$DIR.install"
rm -rf "$NEW"; mkdir -p "$NEW"
tar -xzf "$TMP/motor.tgz" -C "$NEW"
( cd "$NEW" && "${PNPM[@]}" install --prod --frozen-lockfile >/dev/null ) \
  || die "pnpm install failed; node-pty builds from source here: sudo apt install build-essential python3 (or your distro's equivalent), then run this again"
systemctl --user stop "$SERVICE" 2>/dev/null || true
rm -rf "$DIR"; mkdir -p "$(dirname "$DIR")"; mv "$NEW" "$DIR"

# 4. Config: kept when it exists; else a free port and a new token
mkdir -p "$CONF_DIR"; chmod 700 "$CONF_DIR"
if [ ! -f "$CONF" ]; then
  "$NODE" -e '
    const fs = require("fs"), net = require("net"), [conf, dir, want, claude, codex] = process.argv.slice(1)
    const free = p => new Promise(r => { const s = net.createServer().once("error", () => r(false)).listen(p, "127.0.0.1", () => s.close(() => r(true))) })
    ;(async () => {
      let port = Number(want) || 0
      if (!port) for (let p = 7337; p <= 7347 && !port; p++) if (await free(p)) port = p
      if (!port) { console.error("install-motor: no free port in 7337-7347; set MIA_PORT"); process.exit(1) }
      const cfg = { port, token: require("crypto").randomBytes(32).toString("base64url"), name: require("os").hostname(),
        dbPath: `${dir}/motor.db`, projectsRoot: "~/Sources", projects: [],
        agents: { claudePath: claude || "claude", codexPath: codex || "codex" }, memory: { claudePath: claude || "claude" } }
      fs.writeFileSync(conf, JSON.stringify(cfg, null, 2) + "\n", { mode: 0o600 })
    })()' "$CONF" "$CONF_DIR" "${MIA_PORT:-}" "$CLAUDE" "$CODEX"
fi
[ -f "$CONF_DIR/motor.env" ] || : > "$CONF_DIR/motor.env"
chmod 600 "$CONF" "$CONF_DIR/motor.env"
read -r PORT TOKEN < <("$NODE" -e 'const c = require(process.argv[1]); console.log(c.port, c.token)' "$CONF")

# 5. The service: the user's tools on its PATH; it outlives the login (linger)
PATHS="$(dirname "$NODE")"
for t in "$CLAUDE" "$CODEX" "$(command -v pnpm || true)" "$(command -v git)"; do [ -n "$t" ] && PATHS="$PATHS:$(dirname "$t")"; done
PATHS="$PATHS:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
UNIT_DIR="$HOME/.config/systemd/user"; mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/$SERVICE.service" <<UNIT
[Unit]
Description=Mia motor

[Service]
WorkingDirectory=$CONF_DIR
ExecStart=$NODE $DIR/bin/mia-motor $CONF
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PATH=$PATHS
EnvironmentFile=-$CONF_DIR/motor.env

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE" >/dev/null 2>&1
loginctl enable-linger "$USER" 2>/dev/null || say "note: run 'sudo loginctl enable-linger $USER' so the motor keeps running after you log out"

for _ in $(seq 1 30); do
  "$NODE" -e 'require("net").connect(Number(process.argv[1]), "127.0.0.1").once("connect", () => process.exit(0)).once("error", () => process.exit(1))' "$PORT" && break
  sleep 1
done || true
"$NODE" -e 'require("net").connect(Number(process.argv[1]), "127.0.0.1").once("connect", () => process.exit(0)).once("error", () => process.exit(1))' "$PORT" \
  || die "the motor did not start; see: journalctl --user -u $SERVICE -n 30"

say ""
say "Mia motor $VERSION is running on port $PORT and updates itself."
say "In Mia: Configurações › Motores › Adicionar motor"
say "  Nome:                        $(hostname)"
say "  Conectar por SSH:            on"
say "  Host SSH:                    $USER@$(hostname)   (or the alias in your Mac's ~/.ssh/config)"
say "  Porta do motor no servidor:  $PORT"
say "  Token:                       $TOKEN"
