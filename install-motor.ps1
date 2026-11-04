# Installs a Mia motor on a Windows machine (plan 2026-11-04-versoes-e-atualizacao). In PowerShell:
#
#   irm https://raw.githubusercontent.com/richardoliveira/Mia-releases/main/install-motor.ps1 | iex
#
# It downloads the newest motor release, checks its signature with the release key, installs it with pnpm, writes
# ~\.mia\motor.json (kept when it exists), starts the motor at logon and prints what to paste in Mia (Configurações › Motores ›
# Adicionar motor). The motor runs in your logon session, not as a service: Windows apps it opens need the desktop. It then
# updates itself. Needs Node.js 24+ (corepack comes with it), git, Claude Code and/or Codex, and the OpenSSH Server for the Mac
# to reach it.
#
# Overrides ($env:...): MIA_DIR (motor folder, ~\mia\motor), MIA_CONF_DIR (~\.mia), MIA_PORT (first free of 7337-7347),
# MIA_TASK ("Mia Motor"), MIA_MOTOR_FEED (the release manifest). Works in Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Fail($msg) { Write-Host "install-motor: $msg" -ForegroundColor Red; throw "install-motor: $msg" }
function Env($name, $default) { $v = [Environment]::GetEnvironmentVariable($name); if ($v) { $v } else { $default } }

$Feed = Env 'MIA_MOTOR_FEED' 'https://raw.githubusercontent.com/richardoliveira/Mia-releases/main/motor.json'
$Key = '4yt3SZsr4cDqBaLHkKoTD3TG+wK5G7WsWQVopdlS6ro=' # the release key (app/Resources/Info.plist SUPublicEDKey)
$Dir = Env 'MIA_DIR' (Join-Path $HOME 'mia\motor')
$ConfDir = Env 'MIA_CONF_DIR' (Join-Path $HOME '.mia')
$Task = Env 'MIA_TASK' 'Mia Motor'
$Conf = Join-Path $ConfDir 'motor.json'

# 1. What the motor needs
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { Fail 'Node.js 24 or newer is required: https://nodejs.org' }
if ([int](& $node -p "process.versions.node.split('.')[0]") -lt 24) { Fail "Node.js 24 or newer is required (found $(& $node -v))" }
if (Get-Command pnpm -ErrorAction SilentlyContinue) { $pnpm = @('pnpm') }
elseif (Get-Command corepack -ErrorAction SilentlyContinue) { $pnpm = @('corepack', 'pnpm') }
else { Fail 'pnpm is required: npm i -g pnpm' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is required: https://git-scm.com/download/win' }
$claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
$codex = (Get-Command codex -ErrorAction SilentlyContinue).Source
if (-not ($claude -or $codex)) { Write-Host 'warning: neither Claude Code nor Codex found; install one and sign in before using this motor' }
if ((Test-Path $Dir) -and -not (Test-Path (Join-Path $Dir '.release'))) { Fail "$Dir exists and is not a release install; move it away or set MIA_DIR" }

# Node snippets go through files: Windows PowerShell 5.1 drops the double quotes of arguments to native programs.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("mia-install-" + [Guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
function Js($name, $code) { $f = Join-Path $tmp $name; Set-Content -Path $f -Value $code -Encoding ascii; $f }
try {
# 2. Download the newest release and check its signature before anything is unpacked
  $m = Invoke-RestMethod -Uri $Feed -Headers @{ 'Cache-Control' = 'no-cache' }
  $p = $m.packages.any
  Write-Host "Mia motor $($m.version)"
  $pkg = Join-Path $tmp 'motor.tgz'
  Invoke-WebRequest -Uri $p.url -OutFile $pkg -UseBasicParsing
  & $node (Js 'verify.js' @'
const c = require("crypto"), b = require("fs").readFileSync(process.argv[2])
const key = c.createPublicKey({ key: Buffer.concat([Buffer.from("302a300506032b6570032100", "hex"), Buffer.from(process.argv[3], "base64")]), format: "der", type: "spki" })
if (b.length !== Number(process.argv[5]) || !c.verify(null, b, key, Buffer.from(process.argv[4], "base64"))) process.exit(1)
'@) $pkg $Key $p.edSignature $p.length
  if ($LASTEXITCODE -ne 0) { Fail 'the package signature does not match; nothing was installed' }

  # 3. Install into a fresh folder, then put it in place
  $new = "$Dir.install"
  if (Test-Path $new) { Remove-Item -Recurse -Force $new }
  New-Item -ItemType Directory $new | Out-Null
  & tar.exe -xzf $pkg -C $new
  if ($LASTEXITCODE -ne 0) { Fail 'cannot unpack the package' }
  Push-Location $new
  try {
    $rest = @(); if ($pnpm.Count -gt 1) { $rest = $pnpm[1..($pnpm.Count - 1)] }
    & $pnpm[0] @rest install --prod --frozen-lockfile | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'pnpm install failed' }
  } finally { Pop-Location }

# The motor this replaces stops first (its logon task restarts it from the new files).
if (Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $Task }
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains("$Dir\bin\mia-motor") } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
New-Item -ItemType Directory (Split-Path $Dir) -Force | Out-Null
Move-Item $new $Dir

# 4. Config: kept when it exists; else a free port and a new token
New-Item -ItemType Directory $ConfDir -Force | Out-Null
if (-not (Test-Path $Conf)) {
  & $node (Js 'config.js' @'
const fs = require("fs"), net = require("net"), [conf, dir, want, c1, c2] = process.argv.slice(2)
const claude = c1 === "-" ? "" : c1, codex = c2 === "-" ? "" : c2
const free = p => new Promise(r => { const s = net.createServer().once("error", () => r(false)).listen(p, "127.0.0.1", () => s.close(() => r(true))) })
;(async () => {
  let port = Number(want) || 0
  if (!port) for (let p = 7337; p <= 7347 && !port; p++) if (await free(p)) port = p
  if (!port) { console.error("install-motor: no free port in 7337-7347; set MIA_PORT"); process.exit(1) }
  const cfg = { port, token: require("crypto").randomBytes(32).toString("base64url"), name: require("os").hostname(),
    dbPath: require("path").join(dir, "motor.db"), projectsRoot: "~/Sources", projects: [],
    agents: { claudePath: claude || "claude", codexPath: codex || "codex" }, memory: { claudePath: claude || "claude" } }
  fs.writeFileSync(conf, JSON.stringify(cfg, null, 2) + "\n")
})()
'@) $Conf $ConfDir (Env 'MIA_PORT' '0') $(if ($claude) { $claude } else { '-' }) $(if ($codex) { $codex } else { '-' }) # 5.1 drops empty arguments
  if ($LASTEXITCODE -ne 0) { Fail 'cannot write motor.json' }
}
# Only this user reads the folder that holds the motor's token.
& icacls $ConfDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
$cfg = Get-Content $Conf -Raw | ConvertFrom-Json

# 5. Start at logon: a loop that restarts node (the motor exits to update itself)
$launcher = Join-Path (Split-Path $Dir) 'run-motor.cmd'
@"
@echo off
rem Mia motor, started by the "$Task" logon task (install-motor.ps1); restarts the motor when it exits.
cd /d "$ConfDir"
:loop
"$node" "$Dir\bin\mia-motor" "$Conf" >> "$ConfDir\motor.log" 2>&1
ping -n 6 127.0.0.1 >nul
goto loop
"@ | Set-Content -Path $launcher -Encoding ascii
schtasks /Create /F /TN $Task /SC ONLOGON /IT /RL LIMITED /TR "conhost.exe --headless cmd.exe /c `"$launcher`"" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'cannot create the logon task' }
schtasks /Run /TN $Task | Out-Null

$up = $false
for ($i = 0; $i -lt 30 -and -not $up; $i++) {
  try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', [int]$cfg.port); $c.Close(); $up = $true } catch { Start-Sleep 1 }
}
if (-not $up) { Fail "the motor did not start; see $ConfDir\motor.log" }

# 6. The Mac reaches this motor over SSH
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $sshd -or $sshd.Status -ne 'Running') {
  Write-Host ''
  Write-Host 'The Mac reaches this motor over SSH: turn on the OpenSSH Server once, in PowerShell as administrator:' -ForegroundColor Yellow
  Write-Host '  Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0'
  Write-Host '  Set-Service sshd -StartupType Automatic; Start-Service sshd'
}

Write-Host ''
Write-Host "Mia motor $($m.version) is running on port $($cfg.port) and updates itself. It starts when you log in to Windows."
Write-Host 'In Mia: Configurações › Motores › Adicionar motor'
Write-Host "  Nome:                        $env:COMPUTERNAME"
Write-Host '  Conectar por SSH:            on'
Write-Host "  Host SSH:                    $env:USERNAME@$env:COMPUTERNAME   (or this machine's address)"
Write-Host "  Porta do motor no servidor:  $($cfg.port)"
Write-Host "  Token:                       $($cfg.token)"
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
