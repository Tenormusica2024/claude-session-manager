param(
    [string]$Command = "interactive"
)

Write-Host "=== Session Lite ===" -ForegroundColor Cyan
Write-Host "Command: $Command"

$ProjectsDir = "$env:USERPROFILE\.claude\projects"

# Get sessions (limited)
Write-Host "Scanning $ProjectsDir..."
$sessions = @()

$projectDirs = Get-ChildItem -Path $ProjectsDir -Directory -ErrorAction SilentlyContinue | Select-Object -First 2
Write-Host "Found $($projectDirs.Count) project dirs"

foreach ($projectDir in $projectDirs) {
    Write-Host "  Processing: $($projectDir.Name)"
    $jsonFiles = Get-ChildItem -Path $projectDir.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 10

    foreach ($jsonFile in $jsonFiles) {
        try {
            $firstLine = Get-Content $jsonFile.FullName -TotalCount 1 -ErrorAction Stop
            if (-not $firstLine) { continue }

            $data = $firstLine | ConvertFrom-Json -ErrorAction Stop
            if (-not $data.sessionId) { continue }

            $summary = "(no content)"
            if ($data.message -and $data.message.content -and $data.message.content -is [string]) {
                $len = [Math]::Min(40, $data.message.content.Length)
                $summary = $data.message.content.Substring(0, $len)
            }

            $sessions += [PSCustomObject]@{
                SessionId = $data.sessionId
                Summary = $summary -replace "`n", " "
                LastModified = $jsonFile.LastWriteTime
            }
        }
        catch {
            # Skip errors
        }
    }
}

Write-Host ""
Write-Host "Found $($sessions.Count) sessions" -ForegroundColor Green

if ($Command -eq "interactive" -and $sessions.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Select Session (Arrow keys + Enter) ===" -ForegroundColor Yellow

    $selectedIndex = 0
    $maxDisplay = [Math]::Min(10, $sessions.Count)

    while ($true) {
        Clear-Host
        Write-Host "=== Claude Session Manager ===" -ForegroundColor Cyan
        Write-Host ""

        for ($i = 0; $i -lt $maxDisplay; $i++) {
            $session = $sessions[$i]
            $marker = if ($i -eq $selectedIndex) { "> " } else { "  " }
            $color = if ($i -eq $selectedIndex) { "Green" } else { "White" }

            $display = "$marker[$($i+1)] $($session.Summary)"
            if ($display.Length -gt 60) { $display = $display.Substring(0, 60) + "..." }

            Write-Host $display -ForegroundColor $color
        }

        Write-Host ""
        Write-Host "[Up/Down] Move  [Enter] Resume  [Q] Quit" -ForegroundColor Gray

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { if ($selectedIndex -gt 0) { $selectedIndex-- } }  # Up
            40 { if ($selectedIndex -lt $maxDisplay - 1) { $selectedIndex++ } }  # Down
            13 {  # Enter
                $selected = $sessions[$selectedIndex]
                Write-Host ""
                Write-Host "Resuming session: $($selected.SessionId)" -ForegroundColor Green
                & "$env:USERPROFILE\.bun\bin\claude.exe" -r $selected.SessionId
                return
            }
            81 { return }  # Q
            default {
                if ($key.Character -eq 'q') { return }
            }
        }
    }
}
elseif ($Command -eq "list") {
    Write-Host ""
    $sessions | ForEach-Object {
        Write-Host "  $($_.SessionId.Substring(0,8))... | $($_.Summary)"
    }
}
