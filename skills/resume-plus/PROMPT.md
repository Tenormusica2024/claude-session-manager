# Resume Plus - Interactive Session Resumer

Display recent Claude Code sessions with AI-generated titles and allow interactive selection to resume.

## Execution

Run the following command using Bash tool:

```powershell
powershell -ExecutionPolicy Bypass -Command "& '$env:USERPROFILE\.claude\session-manager-interactive.ps1'"
```

## Features

- Lists up to 15 most recent sessions
- AI-generated titles (Japanese)
- Number-key selection for instant resume
- Automatic `claude -r <session-id>` execution

## User Interaction

After displaying the session list, ask the user:

```
Select a session to resume (1-15), or press Enter to cancel:
```

When user selects a number:
1. Get the corresponding session ID
2. Execute: `claude -r <session-id>`
3. Inform the user that the session is being resumed

## Output Format

```
=== Recent Sessions ===

 [1] [タイトル1]
 [2] [タイトル2]
 ...
[15] [タイトル15]

Select a session to resume (1-15), or press Enter to cancel:
```

## Error Handling

- If user enters invalid input, show error and prompt again
- If session file is missing, show warning and return to list
- Handle Ctrl+C gracefully
