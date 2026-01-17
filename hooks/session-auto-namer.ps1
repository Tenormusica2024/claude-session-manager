# Session Auto-Namer Hook (Stop Hook)
# Runs after each Claude response to keep session name updated
# Uses Haiku for fast summarization (~1-2 seconds)

$NamesFile = "$env:USERPROFILE\.claude\session-names.json"
$ProjectsDir = "$env:USERPROFILE\.claude\projects"
$ClaudeExe = "$env:USERPROFILE\.bun\bin\claude.exe"

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

# Find most recent session file
function Get-MostRecentSession {
    $mostRecent = $null
    $mostRecentTime = [DateTime]::MinValue

    $projectDirs = Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue
    foreach ($projectDir in $projectDirs) {
        $jsonFiles = Get-ChildItem -Path $projectDir.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -First 1

        foreach ($jsonFile in $jsonFiles) {
            if ($jsonFile.LastWriteTime -gt $mostRecentTime) {
                $mostRecentTime = $jsonFile.LastWriteTime
                $mostRecent = $jsonFile
            }
        }
    }

    return $mostRecent
}

# Generate AI summary using Haiku for speed
function Get-AISummary {
    param($filePath)

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

    $messagesText = ($userMessages | Select-Object -First 5) -join "`n---`n"
    $prompt = "Summarize this Claude Code session in 5-10 words (Japanese OK). Focus on the main task/topic. Just output the summary, nothing else:`n`n$messagesText"

    try {
        $env:ANTHROPIC_API_KEY = ""
        # Use Haiku for fast summarization
        $summary = & $ClaudeExe -p $prompt --model haiku --dangerously-skip-permissions 2>$null
        if ($summary) {
            $summary = $summary.Trim()
            if ($summary.Length -gt 50) {
                $summary = $summary.Substring(0, 50)
            }
            return $summary
        }
    }
    catch { }

    return $null
}

# Main execution
try {
    $recentFile = Get-MostRecentSession
    if (-not $recentFile) {
        exit 0
    }

    # Check if recently modified (within last 2 minutes = likely current session)
    $timeSinceModified = (Get-Date) - $recentFile.LastWriteTime
    if ($timeSinceModified.TotalMinutes -gt 2) {
        exit 0
    }

    # Get session ID
    $firstLine = Get-Content $recentFile.FullName -TotalCount 1 -ErrorAction SilentlyContinue
    if (-not $firstLine) {
        exit 0
    }

    $data = $firstLine | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $data.sessionId) {
        exit 0
    }

    $sessionId = $data.sessionId

    # Always re-summarize to keep name current (task might have changed)
    $summary = Get-AISummary -filePath $recentFile.FullName
    if (-not $summary) {
        exit 0
    }

    # Load and save
    $sessionNames = Get-SessionNames
    if (-not $sessionNames.sessions) {
        $sessionNames.sessions = @{}
    }
    $sessionNames.sessions.$sessionId = @{
        name = $summary
        updatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        type = "ai-hook"
    }
    Save-SessionNames -names $sessionNames

    # Silent success - don't disrupt user workflow
}
catch {
    # Silently fail - don't disrupt user workflow
    exit 0
}
