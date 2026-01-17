# Resume Plus

`/resume` with AI-powered session titles.

Browse and resume past sessions with automatically generated descriptive titles instead of UUIDs.

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
