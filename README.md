# Resume Plus

`/resume` with AI-powered session titles.

A session manager for Claude Code that replaces UUID-based session lists with automatically generated descriptive titles.

## What it does

- Generates descriptive session titles using Claude Sonnet
- Automatically skips meaningless sessions (greetings, auto-reports)
- Filters out empty and corrupted sessions
- Interactive number-key selection for instant resume
- Caches titles for fast subsequent launches
- **NEW**: Early completion strategy for AI processing (30s batches)
- **NEW**: File read caching to eliminate duplicate I/O

## Screenshot

```
=== Claude Session Manager ===
Found 105 sessions

>  [1] AI最新ニュースと技術動向の24時間レポート作成
   [2] Claude Desktop連携プログラムの誤報告問題の調査
   [3] ココナラAI関連サービスの競合価格調査
   [4] ブログ記事のLLM性能比較内容の拡充
  *[5] My Custom Session Name

Select a session to resume (1-15), or press Enter to cancel:
```

## Installation

Requires Claude Code CLI.

### Option 1: Terminal Execution (Recommended)

```powershell
# Download files
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tenormusica2024/claude-session-manager/master/session-manager-interactive.ps1" -OutFile "$env:USERPROFILE\.claude\session-manager-interactive.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Tenormusica2024/claude-session-manager/master/resume-plus.cmd" -OutFile "$env:USERPROFILE\.claude\resume-plus.cmd"

# Run from any terminal
resume-plus
```

### Option 2: Direct PowerShell

```powershell
& "$env:USERPROFILE\.claude\session-manager-interactive.ps1"
```

### Option 3: Claude Code Skill

Copy `skills/resume-plus/` to your `.claude/skills/` directory:

```powershell
Copy-Item -Path "claude-session-manager\skills\resume-plus" -Destination "$env:USERPROFILE\.claude\skills\resume-plus" -Recurse
```

Then use inside Claude Code: `/resume-plus`

## Controls

| Key | Action |
|-----|--------|
| 1-15 | Resume session by number |
| Enter | Cancel |

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
| First run (with AI) | ~10 seconds (improved with early completion) |
| Subsequent runs | ~1.5 seconds (file read caching) |

## v2 Improvements

- **Early Completion Strategy**: AI results processed in 30s batches instead of waiting for all jobs
- **File Read Caching**: Eliminated duplicate file I/O operations
- **Unified SKIP Logic**: Consolidated pattern matching and line count checks

## Troubleshooting

**claude.exe not found**: Install Claude Code CLI via `npm install -g @anthropic-ai/claude-code`

**Slow first run**: AI title generation runs once and results are cached.

## License

MIT
