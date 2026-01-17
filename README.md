# Claude Session Manager

A lightweight PowerShell-based session manager for Claude Code CLI. Navigate and resume past sessions with an interactive TUI.

## Problem

Claude Code's built-in `/resume` command shows sessions with auto-generated UUIDs, making it difficult to:
- Identify which session contains what conversation
- Find the right session after a PC crash
- Distinguish between similar sessions

## Solution

This tool provides an interactive session selector that:
- Shows the first user message as a session summary
- Allows arrow key navigation (like `/resume`)
- Instantly resumes selected sessions

## Screenshot

```
=== Claude Session Manager ===

> [1] ClaudeCodeセッション管理専用スラッシュコマ...
  [2] sound platformでGoogle認証が...
  [3] 了解、続きからだね♪ じゃあ遷移ボ...
  [4] sound-platform-v8 プロジェクト...
  [5] ダッシュボードの全画面チャットにサ...

[Up/Down] Move  [Enter] Resume  [Q] Quit
```

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
| Q | Quit |

### List Mode

```powershell
& "$env:USERPROFILE\.claude\session-manager.ps1" -Command list
```

Output:
```
  e1e92b66... | ClaudeCodeセッション管理専用スラッシュ
  a3b4c5d6... | sound platformでGoogle認証が
  ...
```

## How It Works

1. Scans `~/.claude/projects/` for session files (`.jsonl`)
2. Extracts the first user message from each session
3. Displays an interactive TUI with arrow key navigation
4. Executes `claude -r <session-id>` when Enter is pressed

### Session Storage Structure

```
~/.claude/projects/
  ├── ProjectA/
  │   ├── abc123-def456-....jsonl
  │   └── xyz789-uvw012-....jsonl
  └── ProjectB/
      └── ...
```

Each `.jsonl` file contains session data with:
- `sessionId`: UUID for the session
- `message.content`: First user message (used as summary)

## Requirements

- Windows PowerShell 5.1 or later
- Claude Code CLI installed (`claude` command available)

## Configuration

Current defaults (edit script to customize):

| Setting | Default | Description |
|---------|---------|-------------|
| Project folders scanned | 2 | Number of project directories to scan |
| Sessions per folder | 10 | Max sessions loaded per project |
| Display limit | 10 | Max sessions shown in TUI |
| Summary length | 40 chars | Truncation length for summaries |

## Roadmap

- [ ] Filter out "(no content)" and "Warmup" sessions
- [ ] Session naming feature (press `n` to name)
- [ ] Scan all project folders
- [ ] Duplicate session detection
- [ ] Search/filter functionality
- [ ] Cross-platform support (bash version)

## License

MIT License

## Author

Created with Claude Code
