# Session Manager

Enhanced `/resume` alternative with AI-powered session titles.

Launch the interactive session manager to browse, search, and resume past sessions.

## Execution

```bash
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\session-manager.ps1"
```

## Controls

- **Up/Down**: Navigate sessions
- **Enter**: Resume selected session
- **S**: Re-generate AI summary
- **N**: Manually name session
- **Q**: Quit
