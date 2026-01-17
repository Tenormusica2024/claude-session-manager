# Resume Plus

`/resume` with AI-powered session titles.

A session manager for Claude Code that replaces UUID-based session lists with automatically generated descriptive titles.

## What it does

- Generates descriptive session titles using Claude Sonnet
- Automatically skips meaningless sessions (greetings, auto-reports)
- Filters out empty and corrupted sessions
- Provides the same arrow-key navigation as `/resume`
- Caches titles for fast subsequent launches

## Screenshot

```
=== Claude Session Manager ===
Found 105 sessions

>  [1] AI最新ニュースと技術動向の24時間レポート作成
   [2] Claude Desktop連携プログラムの誤報告問題の調査
   [3] ココナラAI関連サービスの競合価格調査
   [4] ブログ記事のLLM性能比較内容の拡充
  *[5] My Custom Session Name

[Up/Down] Move  [Enter] Resume  [S] Re-summarize  [N] Name  [Q] Quit
```

## Installation

Requires Claude Code CLI.

### Option 1: Terminal Execution (Recommended)

```powershell
# Download files
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/session-manager.ps1" -OutFile "$env:USERPROFILE\.claude\session-manager.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tenormusica2024/claude-session-manager/main/resume-plus.cmd" -OutFile "$env:USERPROFILE\.claude\resume-plus.cmd"

# Run from any terminal
resume-plus
```

### Option 2: Direct PowerShell

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
3. Generates titles for recent sessions using Sonnet (parallel, ~15 sessions)
4. Automatically skips meaningless sessions (greetings, auto-reports)
5. Caches results for instant display on subsequent runs
6. Resumes selected session via `claude -r`

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
