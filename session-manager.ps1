param(
    [string]$Command = "interactive",
    [switch]$NoAutoSummary  # Skip auto-summarization
)

# Session names database
$NamesFile = "$env:USERPROFILE\.claude\session-names.json"
$ProjectsDir = "$env:USERPROFILE\.claude\projects"
$ClaudeExe = "$env:USERPROFILE\.bun\bin\claude.exe"

# Global: Track duplicate files for cleanup
$script:duplicateFiles = @()

# Load session names (convert PSCustomObject to hashtable for dynamic property addition)
function Get-SessionNames {
    if (Test-Path $NamesFile) {
        try {
            $content = Get-Content $NamesFile -Raw -ErrorAction Stop
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
    if ($sessionData -and $sessionData.name) {
        return $sessionData.name
    }
    return $defaultSummary
}

# Quick fallback title from assistant responses (no API call - instant)
# Looks at recent assistant responses which tend to summarize the topic better
function Get-QuickTitle {
    param($filePath)

    # Read last 100 lines to get recent messages
    $allLines = Get-Content $filePath -ErrorAction SilentlyContinue
    if (-not $allLines -or $allLines.Count -eq 0) { return $null }

    # Get last 100 lines (most recent)
    $recentLines = $allLines | Select-Object -Last 100

    # Collect assistant responses (in reverse order - newest first)
    $assistantResponses = @()
    for ($i = $recentLines.Count - 1; $i -ge 0; $i--) {
        try {
            $entry = $recentLines[$i] | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($entry.message -and $entry.message.role -eq "assistant" -and $entry.message.content) {
                $content = $entry.message.content
                # Handle array content (tool calls etc)
                if ($content -is [array]) {
                    foreach ($item in $content) {
                        if ($item.type -eq "text" -and $item.text) {
                            $assistantResponses += $item.text
                            break
                        }
                    }
                }
                elseif ($content -is [string] -and $content.Length -gt 10) {
                    $assistantResponses += $content
                }
            }
        }
        catch { }

        # Stop after collecting 3 assistant responses
        if ($assistantResponses.Count -ge 3) { break }
    }

    # Try to extract title from assistant responses
    foreach ($response in $assistantResponses) {
        # Clean up
        $text = $response -replace "`n", " " -replace "\s+", " "
        $text = $text.Trim()

        # Skip if too short or looks like just tool output
        if ($text.Length -lt 15) { continue }
        if ($text -match "^(\{|\[|<|```|Error|undefined)") { continue }

        # Take first meaningful sentence (up to 50 chars)
        $title = $text
        if ($title.Length -gt 50) {
            $title = $title.Substring(0, 50)
            # Try to break at word boundary
            $lastSpace = $title.LastIndexOf(" ")
            if ($lastSpace -gt 30) {
                $title = $title.Substring(0, $lastSpace)
            }
            $title = $title + "..."
        }

        # Skip if it's just greeting or generic
        if ($title -match "^(Hi|Hello|Sure|OK|はい|了解|承知)") { continue }

        return $title
    }

    # Fallback: first user message (last resort)
    foreach ($line in $allLines | Select-Object -First 5) {
        try {
            $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($entry.message -and $entry.message.role -eq "user" -and $entry.message.content) {
                $content = $entry.message.content
                if ($content -is [string] -and $content.Length -gt 5) {
                    $title = $content -replace "`n", " " -replace "\s+", " "
                    $title = $title.Trim()
                    # Skip URLs and code
                    if ($title -match "^(http|```|import |const |var |let |function )") { continue }
                    if ($title.Length -gt 40) {
                        $title = $title.Substring(0, 40) + "..."
                    }
                    return $title
                }
            }
        }
        catch { }
    }

    return $null
}

# Generate AI summary for a session (used by manual S key only)
function Get-AISummaryQuiet {
    param($sessionId, $filePath)

    # Extract user messages
    $lines = Get-Content $filePath -TotalCount 50 -ErrorAction SilentlyContinue
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

    $prompt = "Create a short title (3-8 words) for this coding session. Output ONLY the title, nothing else. No quotes, no explanation. Example outputs: 'GitHub Actions CI setup' or 'React component refactoring' or 'Firebase auth implementation'. Session content: $messagesText"

    try {
        $env:ANTHROPIC_API_KEY = ""
        $result = & $ClaudeExe -p $prompt --model haiku --dangerously-skip-permissions 2>$null
        if ($result) {
            $summary = ($result -split "`n")[0].Trim().Trim('"').Trim("'")
            if ($summary.Length -gt 40) {
                $summary = $summary.Substring(0, 40)
            }
            if ($summary.Length -gt 5 -and -not ($summary -match "^(I |This |The |Here |Let me|Sorry|申し訳|ただいま)")) {
                return $summary
            }
        }
    }
    catch { }

    return $null
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
            $firstLine = Get-Content $jsonFile.FullName -TotalCount 1 -ErrorAction Stop
            if (-not $firstLine) { continue }

            $data = $firstLine | ConvertFrom-Json -ErrorAction Stop
            if (-not $data.sessionId) { continue }

            # Get default summary from first message
            $defaultSummary = "(no content)"
            if ($data.message -and $data.message.content -and $data.message.content -is [string]) {
                $len = [Math]::Min(40, $data.message.content.Length)
                $defaultSummary = $data.message.content.Substring(0, $len) -replace "`n", " "
            }

            # Skip warmup and empty sessions
            if ($defaultSummary -match "^(no content|Warmup|\(no content\))") {
                continue
            }

            # Get display name (custom name or default)
            $displayName = Get-SessionDisplayName -sessionId $data.sessionId -defaultSummary $defaultSummary -names $sessionNames

            # Check if has custom name
            $hasCustomName = $false
            if ($sessionNames.sessions.($data.sessionId) -and $sessionNames.sessions.($data.sessionId).name) {
                $hasCustomName = $true
            }

            $allSessions += [PSCustomObject]@{
                SessionId = $data.sessionId
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

$duplicateCount = $script:duplicateFiles.Count
if ($duplicateCount -gt 0) {
    Write-Host "Found $($sessions.Count) unique sessions ($duplicateCount duplicates detected)" -ForegroundColor Green
}
else {
    Write-Host "Found $($sessions.Count) sessions" -ForegroundColor Green
}

# Auto-title unnamed sessions on startup (instant - no API calls)
# Sessions with hook-generated names are already handled
if (-not $NoAutoSummary -and $Command -eq "interactive") {
    $unnamedSessions = @($sessions | Where-Object { -not $_.HasCustomName } | Select-Object -First 20)

    if ($unnamedSessions.Count -gt 0) {
        Write-Host ""
        Write-Host "Auto-titling $($unnamedSessions.Count) unnamed sessions..." -ForegroundColor Yellow

        $count = 0
        $titled = 0
        foreach ($session in $unnamedSessions) {
            $count++

            # Use quick title extraction (no API call - instant)
            $title = Get-QuickTitle -filePath $session.FilePath

            if ($title) {
                # Save to names database
                if (-not $sessionNames.sessions) {
                    $sessionNames.sessions = @{}
                }
                $sessionNames.sessions.($session.SessionId) = @{
                    name = $title
                    updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                    type = "quick"
                }

                # Update session object
                $session.Summary = $title
                $session.HasCustomName = $true
                $titled++
            }
        }

        # Save all names at once
        Save-SessionNames -names $sessionNames

        Write-Host "Titled $titled sessions (instant)" -ForegroundColor Green
    }
}

if ($Command -eq "interactive" -and $sessions.Count -gt 0) {
    $selectedIndex = 0
    $maxDisplay = [Math]::Min(15, $sessions.Count)

    while ($true) {
        Clear-Host
        Write-Host "=== Claude Session Manager ===" -ForegroundColor Cyan
        if ($script:duplicateFiles.Count -gt 0) {
            Write-Host "($($script:duplicateFiles.Count) duplicate files - press D to clean up)" -ForegroundColor DarkYellow
        }
        Write-Host ""

        for ($i = 0; $i -lt $maxDisplay; $i++) {
            $session = $sessions[$i]
            $marker = if ($i -eq $selectedIndex) { "> " } else { "  " }
            $color = if ($i -eq $selectedIndex) { "Green" } else { "White" }

            # Add star for custom named sessions
            $star = if ($session.HasCustomName) { "*" } else { " " }

            $display = "$marker$star[$($i+1)] $($session.Summary)"
            if ($display.Length -gt 70) { $display = $display.Substring(0, 70) + "..." }

            Write-Host $display -ForegroundColor $color
        }

        Write-Host ""
        $helpText = "[Up/Down] Move  [Enter] Resume  [S] Re-summarize  [N] Name"
        if ($script:duplicateFiles.Count -gt 0) {
            $helpText += "  [D] Clean duplicates"
        }
        $helpText += "  [Q] Quit"
        Write-Host $helpText -ForegroundColor Gray

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { if ($selectedIndex -gt 0) { $selectedIndex-- } }  # Up
            40 { if ($selectedIndex -lt $maxDisplay - 1) { $selectedIndex++ } }  # Down
            13 {  # Enter - Resume
                $selected = $sessions[$selectedIndex]
                Write-Host ""
                Write-Host "Resuming session: $($selected.SessionId)" -ForegroundColor Green
                & $ClaudeExe -r $selected.SessionId
                return
            }
            83 {  # S - Re-summarize
                $selected = $sessions[$selectedIndex]
                $summary = Get-AISummary -sessionId $selected.SessionId -filePath $selected.FilePath
                if ($summary) {
                    if (-not $sessionNames.sessions) {
                        $sessionNames.sessions = @{}
                    }
                    $sessionNames.sessions.($selected.SessionId) = @{
                        name = $summary
                        updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                        type = "ai"
                    }
                    Save-SessionNames -names $sessionNames
                    $sessions[$selectedIndex].Summary = $summary
                    $sessions[$selectedIndex].HasCustomName = $true
                    Write-Host "Saved! Press any key..." -ForegroundColor Green
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
                else {
                    Write-Host "Press any key to continue..." -ForegroundColor Yellow
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            }
            78 {  # N - Manual Name
                $selected = $sessions[$selectedIndex]
                Write-Host ""
                Write-Host "Current: $($selected.Summary)" -ForegroundColor Yellow
                Write-Host "Enter new name (empty to cancel): " -NoNewline -ForegroundColor Cyan
                $newName = Read-Host

                if ($newName -and $newName.Trim().Length -gt 0) {
                    $newName = $newName.Trim()
                    if ($newName.Length -gt 50) {
                        $newName = $newName.Substring(0, 50)
                    }
                    if (-not $sessionNames.sessions) {
                        $sessionNames.sessions = @{}
                    }
                    $sessionNames.sessions.($selected.SessionId) = @{
                        name = $newName
                        updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                        type = "manual"
                    }
                    Save-SessionNames -names $sessionNames
                    $sessions[$selectedIndex].Summary = $newName
                    $sessions[$selectedIndex].HasCustomName = $true
                    Write-Host "Saved!" -ForegroundColor Green
                    Start-Sleep -Milliseconds 500
                }
            }
            68 {  # D - Clean duplicates
                if ($script:duplicateFiles.Count -gt 0) {
                    $deleted = Remove-DuplicateFiles -duplicates $script:duplicateFiles
                    if ($deleted -gt 0) {
                        $script:duplicateFiles = @()
                    }
                    Write-Host "Press any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            }
            81 { return }  # Q
            default {
                $char = $key.Character.ToString().ToLower()
                if ($char -eq 'q') { return }
                if ($char -eq 'd' -and $script:duplicateFiles.Count -gt 0) {
                    $deleted = Remove-DuplicateFiles -duplicates $script:duplicateFiles
                    if ($deleted -gt 0) {
                        $script:duplicateFiles = @()
                    }
                    Write-Host "Press any key to continue..." -ForegroundColor Gray
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
                if ($char -eq 's') {
                    $selected = $sessions[$selectedIndex]
                    $summary = Get-AISummary -sessionId $selected.SessionId -filePath $selected.FilePath
                    if ($summary) {
                        if (-not $sessionNames.sessions) {
                            $sessionNames.sessions = @{}
                        }
                        $sessionNames.sessions.($selected.SessionId) = @{
                            name = $summary
                            updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                            type = "ai"
                        }
                        Save-SessionNames -names $sessionNames
                        $sessions[$selectedIndex].Summary = $summary
                        $sessions[$selectedIndex].HasCustomName = $true
                        Write-Host "Saved! Press any key..." -ForegroundColor Green
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                    else {
                        Write-Host "Press any key to continue..." -ForegroundColor Yellow
                        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                }
                if ($char -eq 'n') {
                    $selected = $sessions[$selectedIndex]
                    Write-Host ""
                    Write-Host "Current: $($selected.Summary)" -ForegroundColor Yellow
                    Write-Host "Enter new name (empty to cancel): " -NoNewline -ForegroundColor Cyan
                    $newName = Read-Host

                    if ($newName -and $newName.Trim().Length -gt 0) {
                        $newName = $newName.Trim()
                        if ($newName.Length -gt 50) {
                            $newName = $newName.Substring(0, 50)
                        }
                        if (-not $sessionNames.sessions) {
                            $sessionNames.sessions = @{}
                        }
                        $sessionNames.sessions.($selected.SessionId) = @{
                            name = $newName
                            updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                            type = "manual"
                        }
                        Save-SessionNames -names $sessionNames
                        $sessions[$selectedIndex].Summary = $newName
                        $sessions[$selectedIndex].HasCustomName = $true
                        Write-Host "Saved!" -ForegroundColor Green
                        Start-Sleep -Milliseconds 500
                    }
                }
            }
        }
    }
}
elseif ($Command -eq "list") {
    Write-Host ""
    $sessions | Select-Object -First 20 | ForEach-Object {
        $star = if ($_.HasCustomName) { "*" } else { " " }
        Write-Host " $star$($_.SessionId.Substring(0,8))... | $($_.Summary)"
    }
}
