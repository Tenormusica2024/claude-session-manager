Run the session manager PowerShell script using Bash tool.

Execute this exact command:
```
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\session-manager.ps1"
```

This is an interactive TUI - wait for user to select a session with arrow keys and press Enter.
Do not interpret the output. Just run the command and let the user interact with it.
