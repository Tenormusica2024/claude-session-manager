param(
    [string]$Command = "interactive",
    [switch]$NoAutoSummary  # Skip auto-summarization
)

# Session names database
$NamesFile = "$env:USERPROFILE\.claude\session-names.json"
$ProjectsDir = "$env:USERPROFILE\.claude\projects"

# Auto-detect claude.exe location
function Find-ClaudeExe {
    $candidates = @(
        "$env:USERPROFILE\.bun\bin\claude.exe",
        "$env:USERPROFILE\.claude\local\claude.exe",
        "$env:APPDATA\npm\claude.cmd",
        "$env:LOCALAPPDATA\Programs\claude\claude.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    $whereResult = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($whereResult) { return $whereResult.Source }
    return $null
}

$ClaudeExe = Find-ClaudeExe
if (-not $ClaudeExe) {
    Write-Host "ERROR: claude.exe not found. Please install Claude Code CLI first." -ForegroundColor Red
    Write-Host "Install: npm install -g @anthropic-ai/claude-code" -ForegroundColor Yellow
    exit 1
}

# Test Claude CLI connectivity
function Test-ClaudeConnection {
    try {
        $testResult = & $ClaudeExe --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

$script:claudeConnected = Test-ClaudeConnection
if (-not $script:claudeConnected) {
    Write-Host "[WARN] Claude CLI not responding - AI features disabled" -ForegroundColor Yellow
}

# Global: Track duplicate files for cleanup
$script:duplicateFiles = @()

# Load session names (convert PSCustomObject to hashtable for dynamic property addition)
function Get-SessionNames {
    if (Test-Path $NamesFile) {
        try {
            $content = Get-Content $NamesFile -Raw -Encoding UTF8 -ErrorAction Stop
            $json = $content | ConvertFrom-Json -ErrorAction Stop

            # Convert sessions PSCustomObject to hashtable
            $sessionsHash = @{}
            if ($json.sessions) {
                $json.sessions.PSObject.Properties | ForEach-Object {
                    $sessionsHash[$_.Name] = @{
                        name = $_.Value.name
                        updatedAt = $_.Value.updatedAt
                        type = $_.Value.type
                    }
                }
            }
            return @{ sessions = $sessionsHash }
        }
        catch {
            return @{ sessions = @{} }
        }
    }
    return @{ sessions = @{} }
}

# Save session names
function Save-SessionNames {
    param($names)
    $names | ConvertTo-Json -Depth 10 | Set-Content $NamesFile -Encoding UTF8
}

# Get display name for session
function Get-SessionDisplayName {
    param($sessionId, $defaultSummary, $names)

    $sessionData = $names.sessions.$sessionId
    if ($sessionData -and $sessionData.name -and $sessionData.type -ne "ai-hook") {
        return $sessionData.name
    }
    return $defaultSummary
}

# Extract meaningful session title from conversation rallies (no API call - instant)
function Get-QuickTitle {
    param($filePath)

    # Read first 30 lines (fast) + last 50 lines (need to seek)
    $firstLines = @()
    $lastLines = @()
    
    try {
        # First 30 lines - fast
        $firstLines = Get-Content $filePath -TotalCount 30 -Encoding UTF8 -ErrorAction Stop
        
        # Last 50 lines - use tail-like approach for large files
        $fileInfo = Get-Item $filePath
        if ($fileInfo.Length -gt 50KB) {
            # File > 50KB: read last 50KB and extract lines
            $stream = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $seekPos = [Math]::Max(0, $stream.Length - 50KB)
            $stream.Seek($seekPos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $tailContent = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
            $lastLines = ($tailContent -split "`n") | Select-Object -Last 50
        } else {
            # Small file: read all and take last 50
            $allContent = Get-Content $filePath -Encoding UTF8 -ErrorAction Stop
            $lastLines = $allContent | Select-Object -Last 50
        }
    }
    catch {
        try {
            $firstLines = Get-Content $filePath -TotalCount 30 -ErrorAction SilentlyContinue
            $lastLines = $firstLines
        }
        catch { return $null }
    }
    
    if (-not $lastLines -or $lastLines.Count -eq 0) { return $null }
    $allLines = $lastLines

    # Helper: Check if text is meaningful as a title
    function Test-MeaningfulTitle {
        param($text)
        if (-not $text -or $text.Length -lt 8) { return $false }

        # Skip patterns - not meaningful as titles
        $skipPatterns = @(
            # Status/completion
            "^(完了|了解|承知|はい|OK|おっけ|報告|確認|修正|対応|実行|テスト完了|チェック)",
            "^(Done|Fixed|Completed|OK|Sure|Yes|No|Got it|Thanks|Thank you)",
            # Greetings/conversational
            "^(Hi|Hello|そうだね|なるほど|いいね|ありがと|お疲れ|よし|では|test|テスト$)",
            # System/error messages
            "^(Caveat|Generated by|Note:|Warning:|Error:|Invalid|Please run|Failed)",
            "(API key|api key|apikey|token expired|unauthorized|forbidden)",
            # URLs
            "^https?://",
            # Just emojis or markers
            "^[✅📊🔥🎯💡🚨⚠️]",
            # Just headers without context
            "^(導入済み|実装した|完成した|インストールした|レビュー結果|サマリー)",
            # Dates/times only
            "^\d{4}年\d{1,2}月\d{1,2}日",
            "^\d{1,2}/\d{1,2}/\d{4}",
            # Code/commands
            "^(```|import |const |var |let |function |class |def |npm |pip |git |cd |ls )",
            "^[A-Z_]+\s*=",  # ENV vars
            # File paths
            "^(C:\\|/Users/|~/|\./|http)",
            # Questions that are too generic
            "^(確認していい|これでいい|どう思う|何か|ある？)$",
            "^This session is being continued",
            "^<user-prompt-submit-hook>",
            "^Claude Auto-Mode loaded",
            "^<system-reminder>",
            "^(Summarize this|Create a short title)",
            "^(Focus on the main|Output ONLY the title|The conversation is summarized)",
            "^(Just output the summary|Example outputs:|Initial Context)",
            "(Summarize this Claude Code session|5-10 words)",
            "^\d+\] \[ERROR\]",
            "^(Session content:|Session ID:)",
            "\.com/[a-zA-Z]",
            "/status/\d+",
            "^claude\\\\projects\\\\",
            "^jsonl",
            "permission_mode",
            "^@\{",
            "^<task-notification>",
            "^Initial Request:",
            "^dev/tenormusica/",
            "^com/[A-Za-z]",
            "^<output",
            "^The task was to",
            "^output<",
            "^md.+with a new",
            "^</summary>",
            "^Skill Definition:",
            "_monitor_service$",
            "^Read the output",
            "claude\\\\skills\\\\",
            "claude.skills.",
            "^py ",
            "^File Reading:",
            "^- First attempted",
            "^Web Searches Performed:",
            "5-20",
            "^File Edits:",
            "[\uFF61-\uFF9F]",
            "^S \{",
            '^"session_id":',
            "session_id",
            "^セッション終了を検知",
            "^Is this a meaningful session title",
            "^Archive Creation:",
            "^md``",
            "^Error Encountered:"
        )

        foreach ($pattern in $skipPatterns) {
            if ($text -match $pattern) { return $false }
        }

        # Skip if contains file extensions (likely a file reference)
        if ($text -match "\.(png|jpg|jpeg|gif|md|ps1|json|txt|ts|js|py)") { return $false }

        # Skip if garbled (>1/3 unusual chars)
        # Also skip if contains Shift-JIS mojibake patterns (half-width katakana)
        $cleanChars = ($text -replace "[a-zA-Z0-9\u3040-\u30FF\u4E00-\u9FFF\s\-\.\,\!\?\(\)\:：、。「」]", "")
        if ($cleanChars.Length -gt ($text.Length / 3)) { return $false }

        # Skip if mostly punctuation/symbols
        if (($text -replace "[\w\u3040-\u30FF\u4E00-\u9FFF]", "").Length -gt ($text.Length / 2)) { return $false }

        return $true
    }

    # Helper: Extract clean text from message content
    function Get-CleanText {
        param($content)
        if (-not $content) { return $null }

        $text = $content -replace "`n", " " -replace "`r", "" -replace "\s+", " "
        $text = $text.Trim()

        # Remove markdown formatting
        $text = $text -replace '\*\*(.+?)\*\*', '$1'  # bold
        $text = $text -replace '```[\s\S]*?```', ''  # code blocks
        $text = $text -replace '^\s*[-*]\s*', ''  # list markers
        $text = $text -replace '^#+\s*', ''  # headers

        return $text.Trim()
    }

    # Collect all messages in order (newest first)
    $messages = @()
    foreach ($line in $allLines) {
        try {
            $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($entry.message -and $entry.message.role -and $entry.message.content) {
                $content = if ($entry.message.content -is [array]) {
                    ($entry.message.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1).text
                } else { $entry.message.content }

                if ($content -and $content.Length -gt 5) {
                    $messages += @{
                        role = $entry.message.role
                        content = $content
                    }
                }
            }
        }
        catch { }
    }

    # Reverse to get newest first
    [array]::Reverse($messages)

    # Strategy 1: Look for topic description in recent USER messages
    # (What did the user ask for? That's usually the best title)
    $userCount = 0
    foreach ($msg in $messages) {
        if ($msg.role -ne "user") { continue }
        $userCount++
        if ($userCount -gt 15) { break }  # Check up to 15 recent user messages

        $text = Get-CleanText -content $msg.content

        # Take first meaningful sentence
        $sentences = $text -split "[。\.\!\?]" | Where-Object { $_.Trim().Length -gt 5 }
        foreach ($sentence in $sentences) {
            $sentence = $sentence.Trim()
            if ($sentence.Length -gt 55) {
                $sentence = $sentence.Substring(0, 55)
                $lastSpace = $sentence.LastIndexOf(" ")
                if ($lastSpace -gt 35) { $sentence = $sentence.Substring(0, $lastSpace) }
                $sentence = $sentence + "..."
            }

            if (Test-MeaningfulTitle -text $sentence) {
                return $sentence
            }
        }
    }

    # Strategy 2: Look for descriptive headers in assistant responses
    foreach ($msg in $messages) {
        if ($msg.role -ne "assistant") { continue }

        # Look for meaningful headers (## Something specific)
        if ($msg.content -match "##\s+([^#\n]+)") {
            $header = $matches[1].Trim()
            # Remove emojis from start
            $header = $header -replace "^[✅📊🔥🎯💡🚨⚠️\s]+", ""
            if ($header.Length -gt 5 -and $header.Length -lt 50) {
                if (Test-MeaningfulTitle -text $header) {
                    return $header
                }
            }
        }
    }

    # Strategy 3: First user message as last resort
    foreach ($line in $allLines | Select-Object -First 20) {
        try {
            $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($entry.message -and $entry.message.role -eq "user" -and $entry.message.content) {
                $text = Get-CleanText -content $entry.message.content
                if ($text.Length -gt 55) {
                    $text = $text.Substring(0, 55) + "..."
                }
                if (Test-MeaningfulTitle -text $text) {
                    return $text
                }
            }
        }
        catch { }
    }

    return $null
}

# Fix garbled text (Shift-JIS misencoded as UTF-8)
function Repair-GarbledText {
    param([string]$text)
    
    # Check if text looks garbled (contains typical mojibake patterns)
    if ($text -match "縺|繧|繝|邵|郢|驛") {
        try {
            $sjis = [System.Text.Encoding]::GetEncoding("shift_jis")
            $utf8 = [System.Text.Encoding]::UTF8
            $bytes = $sjis.GetBytes($text)
            $fixed = $utf8.GetString($bytes)
            # Return fixed if it looks more like Japanese
            if ($fixed -match "[あ-んア-ン一-龯]" -and $fixed -notmatch "縺|繧|繝") {
                return $fixed
            }
        } catch { }
    }
    return $text
}

# Generate AI summary for a session (used by manual S key only)
function Get-AISummaryQuiet {
    param($sessionId, $filePath)

    # Extract user messages
    $lines = Get-Content $filePath -TotalCount 50 -Encoding UTF8 -ErrorAction SilentlyContinue
    $userMessages = @()
    foreach ($line in $lines) {
        try {
            $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($entry.message -and $entry.message.role -eq "user" -and $entry.message.content) {
                $content = $entry.message.content
                if ($content -is [string] -and $content.Length -gt 0) {
                    $userMessages += $content
                }
            }
        }
        catch { }
    }

    if ($userMessages.Count -eq 0) {
        return $null
    }

    # Create prompt for summarization - strict title-only format
    $messagesText = ($userMessages | Select-Object -First 3) -join " | "
    if ($messagesText.Length -gt 500) {
        $messagesText = $messagesText.Substring(0, 500)
    }

    # Japanese prompt for better readability
    $prompt = "このコーディングセッションの短いタイトルを日本語で作成して。5-20文字程度で、何をやってるか一目でわかるように。タイトルのみ出力、説明不要。例：'GitHub Actions設定' 'Reactコンポーネント修正' 'SE通知hookデバッグ' 'Firebase認証実装'。セッション内容: $messagesText"

    try {
        $env:ANTHROPIC_API_KEY = ""
        $result = & $ClaudeExe -p $prompt --model haiku --dangerously-skip-permissions --setting-sources "local" 2>$null
        if ($result) {
            $summary = ($result -split "`n")[0].Trim().Trim('"').Trim("'")
            if ($summary.Length -gt 55) {
                $summary = $summary.Substring(0, 55)
            }
            if ($summary.Length -gt 5 -and -not ($summary -match "^(I |This |The |Here |Let me|Sorry|申し訳|ただいま)")) {
                return $summary
            }
        }
    }
    catch { }

    return $null
}

# AI-based title validation and generation (called during session list build)
function Get-ValidatedTitle {
    param($filePath, $quickTitle)
    
    $ClaudeExe = "$env:USERPROFILE\.bun\bin\claude.exe"
    
    # If no quick title, generate from scratch
    if (-not $quickTitle -or $quickTitle -eq "(no content)") {
        return Get-AIGeneratedTitle -filePath $filePath
    }
    
    # Validate if quick title is meaningful using AI
    $validationPrompt = "Is this a meaningful session title that describes what work was done? Answer only YES or NO. Title: `"$quickTitle`""
    
    try {
        $env:ANTHROPIC_API_KEY = ""
        $result = & $ClaudeExe -p $validationPrompt --model haiku --dangerously-skip-permissions --setting-sources "local" 2>$null
        $answer = ($result -split "`n")[0].Trim().ToUpper()
        
        if ($answer -match "^YES") {
            return $quickTitle
        }
        
        # Title rejected, generate new one
        return Get-AIGeneratedTitle -filePath $filePath
    }
    catch {
        # On error, return quick title as fallback
        return $quickTitle
    }
}

# Generate title from session content using AI (reads latest + first messages)
function Get-AIGeneratedTitle {
    param($filePath)
    
    $ClaudeExe = "$env:USERPROFILE\.bun\bin\claude.exe"
    
    # Extract messages from latest content (priority) + first content (fallback)
    $userMessages = @()
    
    try {
        $fileInfo = Get-Item $filePath
        
        # Read last 50KB for latest messages
        if ($fileInfo.Length -gt 50KB) {
            $stream = [System.IO.File]::Open($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $seekPos = [Math]::Max(0, $stream.Length - 50KB)
            $stream.Seek($seekPos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $tailContent = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
            $lastLines = ($tailContent -split "`n") | Select-Object -Last 30
        } else {
            $lastLines = Get-Content $filePath -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last 30
        }
        
        # Extract user messages from latest content
        foreach ($line in $lastLines) {
            try {
                $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($entry.message -and $entry.message.role -eq "user" -and $entry.message.content) {
                    $content = $entry.message.content
                    if ($content -is [string] -and $content.Length -gt 10 -and $content.Length -lt 500) {
                        $userMessages += $content
                        if ($userMessages.Count -ge 2) { break }
                    }
                }
            }
            catch { }
        }
        
        # If no good messages from latest, try first 20 lines
        if ($userMessages.Count -eq 0) {
            $firstLines = Get-Content $filePath -TotalCount 20 -Encoding UTF8 -ErrorAction SilentlyContinue
            foreach ($line in $firstLines) {
                try {
                    $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($entry.message -and $entry.message.role -eq "user" -and $entry.message.content) {
                        $content = $entry.message.content
                        if ($content -is [string] -and $content.Length -gt 10 -and $content.Length -lt 500) {
                            $userMessages += $content
                            if ($userMessages.Count -ge 2) { break }
                        }
                    }
                }
                catch { }
            }
        }
    }
    catch { }
    
    if ($userMessages.Count -eq 0) {
        return "(no content)"
    }
    
    $messagesText = ($userMessages -join " | ")
    if ($messagesText.Length -gt 400) {
        $messagesText = $messagesText.Substring(0, 400)
    }
    
    $prompt = "Create a short title (10-30 chars) in Japanese describing what this coding session is about. Output ONLY the title, no explanation. Session content: $messagesText"
    
    try {
        $env:ANTHROPIC_API_KEY = ""
        $result = & $ClaudeExe -p $prompt --model haiku --dangerously-skip-permissions --setting-sources "local" 2>$null
        if ($result) {
            $title = ($result -split "`n")[0].Trim().Trim('"').Trim("'")
            if ($title.Length -gt 50) { $title = $title.Substring(0, 50) }
            if ($title.Length -gt 3 -and -not ($title -match "^(I |This |The |Here |Sorry)")) {
                return $title
            }
        }
    }
    catch { }
    
    return "(no content)"
}


# Parallel AI title generation for multiple sessions (fast)
function Get-AITitlesParallel {
    param($sessionInfos)  # Array of @{Index; FilePath; Prompt; ContextText}
    
    if ($sessionInfos.Count -eq 0) { return @{} }
    
    $TempDir = "$env:TEMP\claude-session-manager"
    if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir -Force | Out-Null }
    $results = @{}
    
    # Write context files first (file I/O approach to avoid encoding issues)
    $contextFiles = @{}
    foreach ($info in $sessionInfos) {
        $contextFile = "$TempDir\context_$($info.Index).txt"
        # Write as UTF-8 with BOM for reliable encoding
        [System.IO.File]::WriteAllText($contextFile, $info.ContextText, [System.Text.Encoding]::UTF8)
        $contextFiles[$info.Index] = $contextFile
    }
    
    # Start all jobs in parallel
    $jobs = @()
    foreach ($info in $sessionInfos) {
        $contextFile = $contextFiles[$info.Index]
        $job = Start-Job -ScriptBlock {
            param($exe, $contextFile, $idx)
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $env:ANTHROPIC_API_KEY = ""
            # Read context from file (preserves encoding)
            $context = [System.IO.File]::ReadAllText($contextFile, [System.Text.Encoding]::UTF8)
            $prompt = "TASK: Generate a coding session title (20-40 chars).

RULES:
1. Describe the USER'S GOAL or PROBLEM (not what Claude said)
2. Be SPECIFIC - mention languages, frameworks, tools, or features
3. Output ONLY the title - no quotes, no explanation
4. If session has no real work (just greetings, testing, auto-reports), output: SKIP
5. NEVER copy-paste user messages - ALWAYS summarize in your own words
6. Title must be 20-40 chars. Longer = INVALID
7. Match the language of session content (Japanese/English)

BAD TITLES (output SKIP instead):
- Greetings or thanks
- Copy-paste of user message (even partial)
- Sentences longer than 50 chars
- Meta-comments about session itself
- Vague titles without specific context

GOOD TITLES (concise, summarized):
- 'React authentication bug fix'
- 'Django REST API pagination'
- 'TypeScript型定義エラーの修正'
- 'Docker compose設定の最適化'
- 'GitHub Actions CI/CD構築'
- 'PostgreSQLクエリ最適化'

SESSION:
$context"
            $result = & $exe -p $prompt --model sonnet --dangerously-skip-permissions --setting-sources "local" 2>$null
            # Return as Base64 to avoid encoding issues, with index prefix
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($result))
            "$idx|$encoded"
        } -ArgumentList $ClaudeExe, $contextFile, $info.Index
        $jobs += $job
    }
    
    # Wait for all jobs with timeout (max 2 minutes total)
    $timeoutSeconds = 120
    $completed = $jobs | Wait-Job -Timeout $timeoutSeconds
    
    # Check for timed out jobs
    $timedOut = $jobs | Where-Object { $_.State -eq 'Running' }
    if ($timedOut.Count -gt 0) {
        Write-Host "  [WARN] $($timedOut.Count) AI title job(s) timed out" -ForegroundColor Yellow
        $timedOut | Stop-Job
    }
    
    # Get results from completed jobs, handle errors
    $rawResults = @()
    foreach ($job in $completed) {
        try {
            if ($job.State -eq 'Completed') {
                $rawResults += Receive-Job -Job $job -ErrorAction Stop
            } elseif ($job.State -eq 'Failed') {
                Write-Host "  [WARN] Job failed: $($job.ChildJobs[0].JobStateInfo.Reason.Message)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [WARN] Error receiving job result: $_" -ForegroundColor Yellow
        }
    }
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    
    # Cleanup temp files
    foreach ($file in $contextFiles.Values) {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
    
    # Parse results
    foreach ($raw in $rawResults) {
        if ($raw -match "^(\d+)\|(.+)$") {
            $idx = [int]$matches[1]
            $encoded = $matches[2]
            try {
                $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
                $title = ($decoded -split "`n")[0].Trim().Trim('"').Trim("'")
                if ($title.Length -gt 50) { $title = $title.Substring(0, 50) }
                if ($title.Length -gt 3 -and -not ($title -match "^(I |This |The |Here |Sorry)")) {
                    $results[$idx] = $title
                }
            }
            catch { }
        }
    }
    
    return $results
}

# Generate AI summary (verbose mode for manual trigger)
function Get-AISummary {
    param($sessionId, $filePath)

    Write-Host ""
    Write-Host "Generating AI summary (Haiku)..." -ForegroundColor Yellow

    $summary = Get-AISummaryQuiet -sessionId $sessionId -filePath $filePath

    if ($summary) {
        Write-Host "Summary: $summary" -ForegroundColor Green
    }
    else {
        Write-Host "Failed to generate summary" -ForegroundColor Red
    }

    return $summary
}

# Cleanup duplicate session files
function Remove-DuplicateFiles {
    param($duplicates)

    if ($duplicates.Count -eq 0) {
        Write-Host "No duplicate files to clean up." -ForegroundColor Yellow
        return 0
    }

    Write-Host ""
    Write-Host "Found $($duplicates.Count) duplicate files to remove:" -ForegroundColor Yellow
    foreach ($file in $duplicates) {
        Write-Host "  - $($file.Name) ($(($file.LastWriteTime).ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Delete these files? [Y/N]: " -NoNewline -ForegroundColor Cyan
    $confirm = Read-Host

    if ($confirm -match "^[Yy]") {
        $deleted = 0
        foreach ($file in $duplicates) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction Stop
                $deleted++
            }
            catch {
                Write-Host "  Failed to delete: $($file.Name)" -ForegroundColor Red
            }
        }
        Write-Host "Deleted $deleted files." -ForegroundColor Green
        return $deleted
    }
    else {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return 0
    }
}

Write-Host "=== Claude Session Manager ===" -ForegroundColor Cyan

# Load names database
$sessionNames = Get-SessionNames

# Get sessions
Write-Host "Scanning sessions..."
$allSessions = @()

$projectDirs = Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue
Write-Host "Found $($projectDirs.Count) project dirs"

foreach ($projectDir in $projectDirs) {
    $jsonFiles = Get-ChildItem -Path $projectDir.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending

    foreach ($jsonFile in $jsonFiles) {
        try {
            $firstLine = Get-Content $jsonFile.FullName -TotalCount 1 -Encoding UTF8 -ErrorAction Stop
            if (-not $firstLine) { continue }

            $data = $firstLine | ConvertFrom-Json -ErrorAction Stop

            # Skip compact_boundary files (session continuation markers)
            if ($data.type -eq "system" -and $data.subtype -eq "compact_boundary") {
                continue
            }

            # Get session ID (from first line or filename for compacted sessions)
            $sessionId = $null
            if ($data.sessionId) {
                $sessionId = $data.sessionId
            } else {
                $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($jsonFile.Name)
            }
            if (-not $sessionId) { continue }

            # Get default summary - prefer compacted session summary first
            $defaultSummary = $null
            if ($data.type -eq "summary" -and $data.summary) {
                $len = [Math]::Min(50, $data.summary.Length)
                $defaultSummary = $data.summary.Substring(0, $len)
            }
            if (-not $defaultSummary) {
                $defaultSummary = Get-QuickTitle -filePath $jsonFile.FullName
            }
            if (-not $defaultSummary) {
                $defaultSummary = "(no content)"
            }
            # Skip warmup, empty, and AI prompt sessions
            if ($defaultSummary -match "^(no content|Warmup|\(no content\)|Create a short title|このコーディングセッション)") {
                continue
            }
            
            # Skip garbled sessions (created by headless -p mode encoding bug)
            if ($defaultSummary -match "医N繧|縺薙・繧|繧ｳ繝ｼ繝|郢ｧ・ｳ|邵ｺ阮") {
                continue
            }
            
            # Skip hook/skill auto-generated sessions
            if ($defaultSummary -match "(Base directory|this skill|GitHub Issue|報告しました|報告したよ|報告完了|セッション終了|セッション完了|サマリー|了解です|セッションの概要)") {
                continue
            }

            # Skip very small sessions (likely warmup or AI prompt sessions)
            if ($jsonFile.Length -lt 5000) {
                continue
            }

            # Skip AI skill session directories
            if ($projectDir.Name -match "(ai-buzz-extractor|claude-skills-test|note-auto-article)") {
                continue
            }

            # Get display name (custom name or default)
            $displayName = Get-SessionDisplayName -sessionId $sessionId -defaultSummary $defaultSummary -names $sessionNames

            # Check if has custom name (ignore ai-hook type - those are auto-generated garbage)
            $hasCustomName = $false
            if ($sessionNames.sessions.$sessionId -and $sessionNames.sessions.$sessionId.name) {
                $nameType = $sessionNames.sessions.$sessionId.type
                if ($nameType -ne "ai-hook") {
                    $hasCustomName = $true
                }
            }

            $allSessions += [PSCustomObject]@{
                SessionId = $sessionId
                Summary = $displayName
                DefaultSummary = $defaultSummary
                LastModified = $jsonFile.LastWriteTime
                HasCustomName = $hasCustomName
                FilePath = $jsonFile.FullName
                FileInfo = $jsonFile
            }
        }
        catch {
            # Skip errors
        }
    }
}

# Proper deduplication by SessionId - keep only the most recent
$grouped = $allSessions | Group-Object SessionId
$sessions = @()
$script:duplicateFiles = @()

foreach ($group in $grouped) {
    $sorted = $group.Group | Sort-Object LastModified -Descending
    # Keep the newest
    $sessions += $sorted[0]
    # Track older duplicates for potential cleanup
    if ($sorted.Count -gt 1) {
        $script:duplicateFiles += $sorted[1..($sorted.Count-1)] | ForEach-Object { $_.FileInfo }
    }
}

# Sort final list by LastModified
$sessions = $sessions | Sort-Object LastModified -Descending

# Load cached AI titles
$titleCachePath = "$env:USERPROFILE\.claude\session-titles-cache.json"
$titleCache = @{}
if (Test-Path $titleCachePath) {
    try {
        $titleCache = Get-Content $titleCachePath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    } catch { $titleCache = @{} }
}

# Apply cached titles first, filter out SKIP entries
$sessionsToRemove = @()
foreach ($session in $sessions) {
    $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($session.FilePath)
    if ($titleCache.ContainsKey($sessionId)) {
        if ($titleCache[$sessionId] -eq "SKIP") {
            $sessionsToRemove += $session
        } else {
            $session.Summary = $titleCache[$sessionId]
        }
    }
}
$sessions = $sessions | Where-Object { $_ -notin $sessionsToRemove }

# AI title validation: prioritize sessions without cached titles
$maxValidate = 15
$sessionsToValidate = @()
$validatedCount = 0

for ($i = 0; $i -lt $sessions.Count -and $validatedCount -lt $maxValidate; $i++) {
    $session = $sessions[$i]
    if ($session.HasCustomName) { continue }
    
    # Skip if already has cached title
    $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($session.FilePath)
    if ($titleCache.ContainsKey($sessionId)) { continue }
    
    $validatedCount++
    
    # Extract first 30 + last 30 lines for context
    $contextText = ""
    try {
        $allLines = Get-Content $session.FilePath -Encoding UTF8 -ErrorAction SilentlyContinue
        $firstLines = $allLines | Select-Object -First 30
        $lastLines = $allLines | Select-Object -Last 30
        $combinedLines = @($firstLines) + @($lastLines) | Select-Object -Unique
        
        foreach ($line in $combinedLines) {
            try {
                $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($entry.isMeta) { continue }
                if ($entry.message -and $entry.message.content) {
                    $content = $entry.message.content
                    $textContent = ""
                    if ($content -is [string]) {
                        if ($content -notmatch "tool_result|tool_use_id|This session is being continued from a previous conversation") {
                            $textContent = $content
                        }
                    } elseif ($content -is [array]) {
                        foreach ($item in $content) {
                            if ($item.type -eq "text" -and $item.text -and $item.text.Length -gt 10) {
                                if ($item.text -notmatch "^Base directory for|ARGUMENTS:|user-prompt-submit-hook|This session is being continued from a previous conversation") {
                                    $textContent = $item.text
                                    break
                                }
                            }
                        }
                    }
                    if ($textContent.Length -gt 10 -and $textContent.Length -lt 300) {
                        # Fix garbled text if detected
                        $textContent = Repair-GarbledText -text $textContent
                        $contextText += " $textContent"
                        if ($contextText.Length -gt 600) { break }
                    }
                }
            }
            catch { }
        }
    }
    catch { }
    
    if ($contextText.Length -gt 20) {
        # Check if content is just session end/hook related
        if ($contextText -match "^[\s]*(セッション(が|を)?(終了|開始)|報告(完了|を)|GitHub Issue|Stop|hook)" -and $contextText.Length -lt 200) {
            $sessions[$i].Summary = "(Hook自動処理)"
            $titleCache[$sessionId] = "(Hook自動処理)"
        } else {
            if ($contextText.Length -gt 500) { $contextText = $contextText.Substring(0, 500) }
            $currentTitle = $session.Summary
            $sessionsToValidate += @{ Index = $i; FilePath = $session.FilePath; ContextText = $contextText; CurrentTitle = $currentTitle }
        }
    } else {
        # Very little content - mark as SKIP if default summary looks like copy-paste
        $lineCount = (Get-Content $session.FilePath -Encoding UTF8 -ErrorAction SilentlyContinue).Count
        if ($lineCount -lt 20) {
            $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($session.FilePath)
            $titleCache[$sessionId] = "SKIP"
            $sessions[$i].Summary = "SKIP"
            $cacheUpdated = $true
        }
    }
}

# Also filter out sessions with bad default summaries (copy-paste detection)
$badSummaryPatterns = @(
    "^画面表示",
    "^実行が必須",
    "^お、",
    "^もう記事",
    "^GitHub Task",
    "^Bash Hooks",
    "^\w+\.\w+ AI",
    "^AI News Research",
    "^[A-Z][a-z]+ [A-Z][a-z]+ (and|with|for)",
    "✅.*✅"
)
foreach ($session in $sessions) {
    $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($session.FilePath)
    if (-not $titleCache.ContainsKey($sessionId)) {
        foreach ($pattern in $badSummaryPatterns) {
            if ($session.Summary -match $pattern) {
                $titleCache[$sessionId] = "SKIP"
                $session.Summary = "SKIP"
                $cacheUpdated = $true
                break
            }
        }
    }
}

if ($sessionsToValidate.Count -gt 0 -and $script:claudeConnected) {
    Write-Host "  Validating $($sessionsToValidate.Count) session titles with AI..." -ForegroundColor Yellow
    try {
        $aiResults = Get-AITitlesParallel -sessionInfos $sessionsToValidate
    } catch {
        Write-Host "  [WARN] AI title generation failed: $_" -ForegroundColor Yellow
        $aiResults = @{}
    }
    $cacheUpdated = $false
    $skipIndices = @()
    foreach ($idx in $aiResults.Keys) {
        $result = $aiResults[$idx]
        # If AI says SKIP, mark for removal
        if ($result -match "^SKIP") {
            $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($sessions[$idx].FilePath)
            $titleCache[$sessionId] = "SKIP"
            $skipIndices += $idx
            $cacheUpdated = $true
            continue
        }
        # Truncate if too long (allow up to 60 chars for more descriptive titles)
        if ($result.Length -gt 60) { $result = $result.Substring(0, 60) }
        # Only use if it's a reasonable title
        if ($result.Length -gt 5 -and $result -notmatch "(セッション概要|Session|タイトル|title|現在|OK|了解|申し訳|すみません|#|##|\*\*|セッション終了|セッション完了|コーディング作業が|タスクは完了していません|作成することができません|記録されていない|待機中|準備完了|指示待ち|依頼待ち|Base directory|this skill|GitHub Issue|報告しました|報告したよ|報告完了|サマリー)") {
            $sessions[$idx].Summary = $result
            $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($sessions[$idx].FilePath)
            $titleCache[$sessionId] = $result
            $cacheUpdated = $true
            Write-Host "  -> Session $idx`: $result" -ForegroundColor Cyan
        }
    }
    # Remove skipped sessions from list
    if ($skipIndices.Count -gt 0) {
        $sessions = $sessions | Where-Object { $sessions.IndexOf($_) -notin $skipIndices }
    }
    # Save updated cache
    if ($cacheUpdated) {
        $titleCache | ConvertTo-Json | Set-Content $titleCachePath -Encoding UTF8
    }
}

# Also save cache if hook sessions were detected
if ($titleCache.Count -gt 0) {
    $titleCache | ConvertTo-Json | Set-Content $titleCachePath -Encoding UTF8
}

# Final filter: remove all SKIP sessions from display
$sessions = $sessions | Where-Object { 
    $sid = [System.IO.Path]::GetFileNameWithoutExtension($_.FilePath)
    -not ($titleCache.ContainsKey($sid) -and $titleCache[$sid] -eq "SKIP") -and $_.Summary -ne "SKIP"
}

$duplicateCount = $script:duplicateFiles.Count
if ($duplicateCount -gt 0) {
    Write-Host "Found $($sessions.Count) unique sessions ($duplicateCount duplicates detected)" -ForegroundColor Green
}
else {
    Write-Host "Found $($sessions.Count) sessions" -ForegroundColor Green
}

# Note: Auto-titling disabled for fast startup
# Stop hook handles automatic naming after each response
# Use S key to manually summarize unnamed sessions

# List mode for Claude Code slash command (no TUI, just output)
if ($Command -eq "interactive" -and $sessions.Count -gt 0) {
    $maxDisplay = [Math]::Min(15, $sessions.Count)
    
    Write-Host ""
    Write-Host "=== Recent Sessions ===" -ForegroundColor Cyan
    Write-Host ""
    
    for ($i = 0; $i -lt $maxDisplay; $i++) {
        $session = $sessions[$i]
        $star = if ($session.HasCustomName) { "*" } else { " " }
        $num = ($i + 1).ToString().PadLeft(2)
        $display = " $star[$num] $($session.Summary)"
        if ($display.Length -gt 75) { $display = $display.Substring(0, 75) + "..." }
        Write-Host $display
    }
    
    Write-Host ""
    Write-Host "To resume a session, run: claude -r <session-id>" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Session IDs:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $maxDisplay; $i++) {
        $session = $sessions[$i]
        Write-Host "  [$($i+1)] $($session.SessionId)"
    }
}
elseif ($Command -eq "list") {
    Write-Host ""
    $sessions | Select-Object -First 20 | ForEach-Object {
        $star = if ($_.HasCustomName) { "*" } else { " " }
        Write-Host " $star$($_.SessionId.Substring(0,8))... | $($_.Summary)"
    }
}