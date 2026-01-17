# Claude Session Manager

A lightweight PowerShell-based session manager for Claude Code CLI. Navigate, name, and resume past sessions with an interactive TUI.

## Problem

Claude Code's built-in `/resume` command shows sessions with auto-generated UUIDs, making it difficult to:
- Identify which session contains what conversation
- Find the right session after a PC crash
- Distinguish between similar sessions

## Solution

This tool provides an interactive session selector that:
- Shows the first user message as a session summary
- Allows arrow key navigation (like `/resume`)
- AI-powered session summarization (press `S`)
- Manual session naming (press `N`)
- Instantly resumes selected sessions

## Screenshot

```
=== Claude Session Manager ===

>  [1] ClaudeCodeセッション管理専用スラッシュコマ...
  *[2] Sound Platform認証機能の実装
   [3] sound platformでGoogle認証が...
  *[4] GitHub Actions CI/CD設定
   [5] ダッシュボードの全画面チャットにサ...

[Up/Down] Move  [Enter] Resume  [S] AI Summary  [N] Name  [Q] Quit
```

Sessions with custom names are marked with `*`.

## Features

### AI-Powered Summarization
Press `S` to generate an AI summary of the selected session. The tool:
1. Extracts user messages from the session
2. Calls Claude to generate a 5-10 word summary
3. Saves the summary to `~/.claude/session-names.json`

### Manual Naming
Press `N` to manually name a session. Useful when you want a specific name that the AI might not generate.

### Smart Filtering
- Automatically filters out "(no content)" and "Warmup" sessions
- Removes duplicate entries
- Shows most recent sessions first

## Installation

### Option 1: Direct Download

```powershell
# Download to Claude config directory
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/session-manager.ps1" -OutFile "$env:USERPROFILE\.claude\session-manager.ps1"
```

### Option 2: Clone Repository

```powershell
git clone https://github.com/tenormusica2024/claude-session-manager.git
cd claude-session-manager
Copy-Item session-manager.ps1 "$env:USERPROFILE\.claude\"
```

## Usage

### Interactive Mode (Default)

```powershell
# Run from anywhere
& "$env:USERPROFILE\.claude\session-manager.ps1"

# Or if in the script directory
.\session-manager.ps1
```

**Controls:**
| Key | Action |
|-----|--------|
| Up/Down | Navigate sessions |
| Enter | Resume selected session |
| S | Generate AI summary for selected session |
| N | Manually name selected session |
| Q | Quit |

### List Mode

```powershell
& "$env:USERPROFILE\.claude\session-manager.ps1" -Command list
```

Output:
```
 *e1e92b66... | Sound Platform認証機能の実装
  a3b4c5d6... | sound platformでGoogle認証が
  ...
```

## How It Works

1. Scans `~/.claude/projects/` for session files (`.jsonl`)
2. Loads custom names from `~/.claude/session-names.json`
3. Extracts the first user message from each session (as default summary)
4. Displays an interactive TUI with arrow key navigation
5. When `S` is pressed, calls `claude -p` to generate a summary
6. Saves custom names to JSON for persistence
7. Executes `claude -r <session-id>` when Enter is pressed

### Session Names Storage

Custom session names are stored in `~/.claude/session-names.json`:

```json
{
  "sessions": {
    "e1e92b66-ca93-4c1d-...": {
      "name": "Sound Platform認証機能の実装",
      "updatedAt": "2026-01-17T11:20:00",
      "type": "ai"
    },
    "a3b4c5d6-...": {
      "name": "My Custom Name",
      "updatedAt": "2026-01-17T11:25:00",
      "type": "manual"
    }
  }
}
```

### Session Storage Structure

```
~/.claude/projects/
  ├── ProjectA/
  │   ├── abc123-def456-....jsonl
  │   └── xyz789-uvw012-....jsonl
  └── ProjectB/
      └── ...
```

## Requirements

- Windows PowerShell 5.1 or later
- Claude Code CLI installed (`claude` command available)

## Configuration

Current defaults (edit script to customize):

| Setting | Default | Description |
|---------|---------|-------------|
| Sessions per folder | 15 | Max sessions loaded per project |
| Display limit | 15 | Max sessions shown in TUI |
| Summary length | 50 chars | Max length for custom names |

## Roadmap

- [x] Filter out "(no content)" and "Warmup" sessions
- [x] Session naming feature (press `N` to name)
- [x] AI-powered summarization (press `S`)
- [x] Scan all project folders
- [x] Duplicate session detection
- [ ] Auto-update summary when task changes (via hooks)
- [ ] Search/filter functionality
- [ ] Cross-platform support (bash version)

## License

MIT License

## Author

Created with Claude Code
