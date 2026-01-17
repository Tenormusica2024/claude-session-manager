# Claude Session Manager - Development Guidelines

## Core Design Principles

### 1. Session Title Generation Strategy

**Priority Order for Information Extraction:**
1. **Latest conversation first** - Most recent messages contain the most relevant context
2. **First message as fallback** - May contain main instructions but also bulk code paste
3. **Sequential scan from newest** - If above fails, scan backwards for meaningful content

**Rationale:**
- First message might be bulk code paste (not useful for title)
- Latest conversation reflects current work context
- Avoid NG pattern approach - use LLM semantic judgment instead

### 2. Title Validation Approach

**DO NOT use NG pattern matching for title quality**
- NG patterns are fragile and require constant maintenance
- Instead: Use LLM (Haiku) to semantically judge if title is meaningful
- LLM can understand context and determine if text describes actual work

**Implementation:**
1. Extract candidate title using quick heuristics
2. Call LLM to validate: "Is this a meaningful session title? YES/NO"
3. If NO, ask LLM to generate title from session content
4. Cache results in session-names.json

### 3. Performance Requirements

- **Target: < 1 minute per session for AI validation**
- Scan phase: No API calls, pure text extraction
- Validation phase: Only for top 15 displayed sessions
- Use Haiku model for speed (fastest Claude model)

### 4. File Reading Strategy

- Read last N lines first (newest content)
- If no good title found, read first N lines
- Never read entire file (performance)
- Target: 50 lines max per direction

## Technical Notes

### Session Files Location
- `$env:USERPROFILE\.claude\projects\*\*.jsonl`

### Custom Names Storage
- `$env:USERPROFILE\.claude\session-names.json`

### Claude CLI Headless Mode
```powershell
$env:ANTHROPIC_API_KEY = ""
& claude.exe -p "prompt" --model haiku --dangerously-skip-permissions
```

## Change Log

### 2026-01-17
- Document created with core design principles
- Emphasis on LLM-based title validation over NG patterns
- Latest conversation priority established
