# Resume Plus

`/resume` with AI-powered session titles.

A session manager for Claude Code that replaces UUID-based session lists with automatically generated descriptive titles.

## What it does

- Generates descriptive session titles using Claude Haiku
- Filters out empty and corrupted sessions
- Provides the same arrow-key navigation as `/resume`
- Caches titles for fast subsequent launches

## Screenshot

```
=== Claude Session Manager ===
Found 117 sessions

>  [1] GitHubイシューモニター処理の「complete」誤認問題調査
   [2] ココナラのAIエージェント競合サービス3件の説明文・特徴取得
   [3] ココナラAI相談サービスの競合調査
   [4] private_issue_monitor_serviceのバグ特定と修正
  *[5] My Custom Session Name

[Up/Down] Move  [Enter] Resume  [S] Re-summarize  [N] Name  [Q] Quit
```

## Installation

Requires Claude Code CLI.

### Option 1: Slash Command

```powershell
# Download files
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/session-manager.ps1" -OutFile "$env:USERPROFILE\.claude\session-manager.ps1"
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\commands" -Force
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/commands/resume-plus.md" -OutFile "$env:USERPROFILE\.claude\commands\resume-plus.md"
```

Then use `/resume-plus` in Claude Code.

### Option 2: Direct Execution

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/session-manager.ps1" -OutFile "$env:USERPROFILE\.claude\session-manager.ps1"
& "$env:USERPROFILE\.claude\session-manager.ps1"
```

## Controls

| Key | Action |
|-----|--------|
| Up/Down | Navigate |
| Enter | Resume session |
| S | Re-generate title |
| N | Set custom name |
| Q | Quit |

## How it works

1. Scans `~/.claude/projects/` for session files
2. Filters out empty and corrupted entries
3. Generates titles for recent sessions using Haiku (parallel, ~10 seconds)
4. Caches results for instant display on subsequent runs
5. Resumes selected session via `claude -r`

## Performance

| Phase | Time |
|-------|------|
| First run (with AI) | ~12 seconds |
| Subsequent runs | ~2 seconds |

## Troubleshooting

**claude.exe not found**: Install Claude Code CLI via `npm install -g @anthropic-ai/claude-code`

**Slow first run**: AI title generation runs once and results are cached.

## License

MIT
