Run the session manager to list recent Claude Code sessions with AI-generated titles.

Execute this command using the Bash tool:
```
powershell -ExecutionPolicy Bypass -File "C:\Users\Tenormusica\.claude\session-manager-list.ps1"
```

After displaying the session list:
1. Show the user the session list output
2. Ask which session number they want to resume
3. When user provides a number, run: `claude -r <session-id>` using the corresponding session ID from the list
