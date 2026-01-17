Display recent Claude Code sessions with AI-generated titles.

Execute this command using the Bash tool:
```
powershell -ExecutionPolicy Bypass -Command "& \"$env:USERPROFILE\.claude\session-manager-list.ps1\""
```

After displaying the list, tell the user:
"To resume a session, copy the session ID and run `claude -r <session-id>` in a new terminal."

Do NOT ask "which session to resume" - this command is for viewing only.
For interactive session selection, use `resume-plus` command in Windows terminal instead.
