param(
    [string]$Command = "interactive"
)

# Session names database
$NamesFile = "$env:USERPROFILE\.claude\session-names.json"
$ProjectsDir = "$env:USERPROFILE\.claude\projects"
$ClaudeExe = "$env:USERPROFILE\.bun\bin\claude.exe"

# Load session names
function Get-SessionNames {
    if (Test-Path $NamesFile) {
        try {
            $content = Get-Content $NamesFile -Raw -ErrorAction Stop
            return ($content | ConvertFrom-Json -ErrorAction Stop)
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

# Generate AI summary for a session
function Get-AISummary {
    param($sessionId)

    Write-Host ""
    Write-Host "Generating AI summary..." -ForegroundColor Yellow

    # Find session file
    $sessionFile = $null
    $projectDirs = Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue
    foreach ($projectDir in $projectDirs) {
        $files = Get-ChildItem -Path $projectDir.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $firstLine = Get-Content $file.FullName -TotalCount 1 -ErrorAction SilentlyContinue
            if ($firstLine) {
                $data = $firstLine | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($data.sessionId -eq $sessionId) {
                    $sessionFile = $file.FullName
                    break
                }
            }
        }
        if ($sessionFile) { break }
    }

    if (-not $sessionFile) {
        Write-Host "Session file not found" -ForegroundColor Red
        return $null
    }

    # Extract user messages (first 20 lines for summary)
    $lines = Get-Content $sessionFile -TotalCount 50 -ErrorAction SilentlyContinue
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
        Write-Host "No user messages found" -ForegroundColor Red
        return $null
    }

    # Create prompt for summarization
    $messagesText = ($userMessages | Select-Object -First 5) -join "`n---`n"
    $prompt = "Summarize this Claude Code session in 5-10 words (Japanese OK). Focus on the main task/topic. Just output the summary, nothing else:`n`n$messagesText"

    # Call claude -p for summarization
    try {
        $env:ANTHROPIC_API_KEY = ""  # Clear to use default auth
        $summary = & $ClaudeExe -p $prompt --dangerously-skip-permissions 2>$null
        if ($summary) {
            $summary = $summary.Trim()
            if ($summary.Length -gt 50) {
                $summary = $summary.Substring(0, 50)
            }
            Write-Host "Summary: $summary" -ForegroundColor Green
            return $summary
        }
    }
    catch {
        Write-Host "Error generating summary: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $null
}

Write-Host "=== Claude Session Manager ===" -ForegroundColor Cyan

# Load names database
$sessionNames = Get-SessionNames

# Get sessions
Write-Host "Scanning sessions..."
$sessions = @()

$projectDirs = Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue
Write-Host "Found $($projectDirs.Count) project dirs"

foreach ($projectDir in $projectDirs) {
    $jsonFiles = Get-ChildItem -Path $projectDir.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 15

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

            $sessions += [PSCustomObject]@{
                SessionId = $data.sessionId
                Summary = $displayName
                DefaultSummary = $defaultSummary
                LastModified = $jsonFile.LastWriteTime
                HasCustomName = $hasCustomName
                FilePath = $jsonFile.FullName
            }
        }
        catch {
            # Skip errors
        }
    }
}

# Remove duplicates and sort by LastModified
$sessions = $sessions | Sort-Object LastModified -Descending | Select-Object -Unique -Property SessionId, Summary, DefaultSummary, LastModified, HasCustomName, FilePath

Write-Host "Found $($sessions.Count) sessions" -ForegroundColor Green

if ($Command -eq "interactive" -and $sessions.Count -gt 0) {
    $selectedIndex = 0
    $maxDisplay = [Math]::Min(15, $sessions.Count)

    while ($true) {
        Clear-Host
        Write-Host "=== Claude Session Manager ===" -ForegroundColor Cyan
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
        Write-Host "[Up/Down] Move  [Enter] Resume  [S] AI Summary  [N] Name  [Q] Quit" -ForegroundColor Gray

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
            83 {  # S - AI Summary
                $selected = $sessions[$selectedIndex]
                $summary = Get-AISummary -sessionId $selected.SessionId
                if ($summary) {
                    # Save to names database
                    if (-not $sessionNames.sessions) {
                        $sessionNames.sessions = @{}
                    }
                    $sessionNames.sessions.($selected.SessionId) = @{
                        name = $summary
                        updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                        type = "ai"
                    }
                    Save-SessionNames -names $sessionNames

                    # Update display
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

                    # Save to names database
                    if (-not $sessionNames.sessions) {
                        $sessionNames.sessions = @{}
                    }
                    $sessionNames.sessions.($selected.SessionId) = @{
                        name = $newName
                        updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                        type = "manual"
                    }
                    Save-SessionNames -names $sessionNames

                    # Update display
                    $sessions[$selectedIndex].Summary = $newName
                    $sessions[$selectedIndex].HasCustomName = $true

                    Write-Host "Saved!" -ForegroundColor Green
                    Start-Sleep -Milliseconds 500
                }
            }
            81 { return }  # Q
            default {
                $char = $key.Character.ToString().ToLower()
                if ($char -eq 'q') { return }
                if ($char -eq 's') {
                    # Trigger S key action
                    $selected = $sessions[$selectedIndex]
                    $summary = Get-AISummary -sessionId $selected.SessionId
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
                    # Trigger N key action
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
