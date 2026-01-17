# Claude Session Manager

A lightweight PowerShell-based session manager for Claude Code CLI. Navigate, name, and resume past sessions with an interactive TUI.

**Enhanced `/resume` alternative** - Smart AI-powered session titles, parallel processing, and intelligent filtering.

## Problem

Claude Code's built-in `/resume` command shows sessions with auto-generated UUIDs, making it difficult to:
- Identify which session contains what conversation
- Find the right session after a PC crash
- Distinguish between similar sessions

## Solution

This tool provides an interactive session selector that:
- **AI-powered session titles** - Automatically generates descriptive Japanese titles using Haiku
- **Parallel processing** - Validates up to 15 sessions simultaneously (~10 seconds total)
- **Smart filtering** - Excludes empty, warmup, and hook-generated sessions
- Arrow key navigation (like `/resume`)
- Manual session naming (press `N`)
- Instantly resumes selected sessions

## Screenshot

```
=== Claude Session Manager ===
  Validating 7 session titles with AI...
  -> Session 9: GitHubイシューモニター処理の「complete」誤認問題調査
  -> Session 8: AIモデルのシステムプロンプト限界と性能比較論
  -> Session 7: AI最前線24時間ニュース更新完了
Found 117 sessions

>  [1] React Component Debug & Firebase Auth Fix
   [2] ココナラのAIエージェント競合サービス3件の説明文・特徴取得
   [3] ココナラAI相談サービスの競合調査
   [4] private_issue_monitor_serviceのバグ特定と修正
  *[5] My Custom Session Name

[Up/Down] Move  [Enter] Resume  [S] Re-summarize  [N] Name  [Q] Quit
```

Sessions with custom names are marked with `*`.

## Features

### Parallel AI Title Generation (New!)
- Automatically generates descriptive titles for recent sessions
- Uses Claude Haiku for speed (~5 seconds per session)
- Processes up to 15 sessions in parallel (~10 seconds total)
- Results cached for instant display on subsequent runs

### Smart Session Filtering
- Filters out empty "(no content)" sessions
- Excludes warmup and initialization sessions
- Removes garbled/corrupted session entries
- Skips hook-generated auto-processing sessions
- Deduplicates by session ID

### Manual Controls
| Key | Action |
|-----|--------|
| Up/Down | Navigate sessions |
| Enter | Resume selected session |
| S | Re-generate AI summary |
| N | Manually name session |
| Q | Quit |

## Installation

### Requirements
- Windows PowerShell 5.1+
- Claude Code CLI installed (`claude` command available)

### Option 1: Slash Command (Recommended)

```powershell
# Download session manager
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/session-manager.ps1" -OutFile "$env:USERPROFILE\.claude\session-manager.ps1"

# Create slash command directory
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\commands" -Force

# Download slash command
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/commands/sessions.md" -OutFile "$env:USERPROFILE\.claude\commands\sessions.md"
```

Then use `/sessions` in Claude Code!

### Option 2: Direct Execution

```powershell
# Download to Claude config directory
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/session-manager.ps1" -OutFile "$env:USERPROFILE\.claude\session-manager.ps1"

# Run directly
& "$env:USERPROFILE\.claude\session-manager.ps1"
```

### Option 3: Clone Repository

```powershell
git clone https://github.com/tenormusica2024/claude-session-manager.git
cd claude-session-manager
Copy-Item session-manager.ps1 "$env:USERPROFILE\.claude\"
Copy-Item -Recurse commands "$env:USERPROFILE\.claude\"
```

## Usage

### As Slash Command
```
/sessions
```

### Direct Execution
```powershell
& "$env:USERPROFILE\.claude\session-manager.ps1"
```

### List Mode
```powershell
& "$env:USERPROFILE\.claude\session-manager.ps1" -Command list
```

## How It Works

1. **Scans** `~/.claude/projects/` for session files (`.jsonl`)
2. **Filters** out empty, warmup, and garbled sessions
3. **Deduplicates** by session ID (keeps newest)
4. **Validates titles** for top 15 sessions using Haiku (parallel)
5. **Caches results** in `session-titles-cache.json`
6. **Displays** interactive TUI with arrow navigation
7. **Resumes** selected session via `claude -r <session-id>`

### Performance

| Phase | Time |
|-------|------|
| Scan & filter | ~2 seconds |
| AI title validation (15 sessions) | ~10 seconds |
| Subsequent runs (cached) | ~2 seconds |

### File Locations

```
~/.claude/
├── session-manager.ps1      # Main script
├── session-names.json       # Custom names storage
├── session-titles-cache.json # AI-generated titles cache
├── commands/
│   └── sessions.md          # Slash command definition
└── projects/
    └── */
        └── *.jsonl          # Session files
```

## Configuration

Edit the script to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| AI validation limit | 15 | Sessions to validate with AI |
| Display limit | 15 | Max sessions shown in TUI |
| Summary length | 60 chars | Max title length |

## Troubleshooting

### "claude.exe not found"
The script auto-detects claude.exe in common locations:
- `~/.bun/bin/claude.exe` (bun install)
- `%APPDATA%/npm/claude.cmd` (npm install)
- System PATH

If not found, install Claude Code CLI:
```bash
npm install -g @anthropic-ai/claude-code
```

### Garbled/corrupted sessions
These are automatically filtered out. If you see them, they were likely created by encoding bugs and can be safely ignored.

### Slow first run
The first run validates session titles with AI (~10 seconds). Subsequent runs use cached titles and are much faster (~2 seconds).

## License

MIT License

## Author

Created with Claude Code
