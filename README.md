# Mia — My Intelligent Agents

Mia downloads for Mac (Apple Silicon). The source code lives in a private repository; this one only holds the releases.

Mia has two parts: the **app** (the Mac window) and the **motor** (Mia's name for the engine that runs the agents and reads the
cards). The app brings a motor for the Mac; Linux and Windows machines can run more.

## Install

1. Download `Mia-<version>.dmg` from the [latest release](https://github.com/richardoliveira/Mia-releases/releases/latest).
2. Open the DMG and drag **Mia** to **Applications**.
3. Open Mia. macOS says "Apple could not verify…". Click **OK**.
4. Open **System Settings › Privacy & Security**, scroll to "Mia was blocked" and click **Open Anyway**.
5. Open Mia again and click **Open Anyway**.
6. Install and sign in to [Claude Code](https://docs.claude.com/claude-code) and [Codex](https://github.com/openai/codex).

From the Terminal, instead of steps 3 to 5:

```
xattr -dr com.apple.quarantine /Applications/Mia.app
```

The Apple warning only shows on the first install.

## A motor on a Linux or Windows machine

To add a Linux machine, run there (Node.js 24+, pnpm, git
and Claude Code or Codex first):

```
curl -fsSL https://raw.githubusercontent.com/richardoliveira/Mia-releases/main/install-motor.sh | bash
```

It installs the newest signed motor as a systemd user service and prints what to paste in Mia (Configurações › Motores ›
Adicionar motor, with "Conectar por SSH" on). The motor then updates itself.

On Windows (Node.js 24+, git and Claude Code or Codex first), in PowerShell:

```
irm https://raw.githubusercontent.com/richardoliveira/Mia-releases/main/install-motor.ps1 | iex
```

It starts the motor when you log in to Windows (apps it opens need the desktop) and says how to turn on the OpenSSH Server, which
the Mac uses to reach it.

## Updates

Mia updates itself: when a new version is out, it shows **Update to vX** next to Settings. The motor also updates itself
when no session is running. Every release is signed; Mia only installs what the signature confirms.

- `app-vX.Y.Z`: the app (DMG).
- `motor-vX.Y.Z`: the motor (Mac, Linux and Windows).
