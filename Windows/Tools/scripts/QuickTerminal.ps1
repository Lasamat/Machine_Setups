param(
    [string]$Profile = 'PowerShell',
    [bool]$ShownOnTop = $true
)

$ErrorActionPreference = 'Stop'
$GlazeWM = (Get-Command glazewm.exe -ErrorAction Stop).Source

function Get-GlazeWMData {
    param([string[]]$Arguments)

    $response = & $GlazeWM @Arguments | ConvertFrom-Json
    if (-not $response.success) {
        throw "glazewm failed: $($Arguments -join ' ')"
    }

    return $response.data
}

function Invoke-GlazeWMCommand {
    param([string[]]$Arguments)

    & $GlazeWM command @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "glazewm command failed: $($Arguments -join ' ')"
    }
}

function Get-TerminalWindowIds {
    $windows = (Get-GlazeWMData -Arguments @('query', 'windows')).windows
    return @($windows | Where-Object { $_.processName -eq 'WindowsTerminal' } | ForEach-Object { $_.id })
}

$focused = (Get-GlazeWMData -Arguments @('query', 'focused')).focused
$workspaces = (Get-GlazeWMData -Arguments @('query', 'workspaces')).workspaces

$currentWorkspaceId = switch ($focused.type) {
    'window' { $focused.parentId }
    'workspace' { $focused.id }
    default { ($workspaces | Where-Object { $_.hasFocus } | Select-Object -First 1).id }
}

$currentWorkspace = $workspaces | Where-Object { $_.id -eq $currentWorkspaceId } | Select-Object -First 1
if (-not $currentWorkspace) {
    throw 'Could not resolve the focused workspace.'
}

$terminalWorkspace = $workspaces | Where-Object { $_.name -eq '3' } | Select-Object -First 1
if (-not $terminalWorkspace) {
    throw 'Workspace 3 is not defined in GlazeWM.'
}

$existingWindowIds = Get-TerminalWindowIds

Start-Process -FilePath (Get-Command wt.exe -ErrorAction Stop).Source -ArgumentList @('-w', '-1', '-p', $Profile)

$newWindow = $null
$deadline = (Get-Date).AddSeconds(5)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 100
    $windows = (Get-GlazeWMData -Arguments @('query', 'windows')).windows
    $newWindow = $windows | Where-Object {
        $_.processName -eq 'WindowsTerminal' -and $_.id -notin $existingWindowIds
    } | Select-Object -First 1

    if ($newWindow) {
        break
    }
}

if (-not $newWindow) {
    throw 'The new Windows Terminal window did not appear.'
}

if ($currentWorkspace.name -ne $terminalWorkspace.name) {
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        $windows = (Get-GlazeWMData -Arguments @('query', 'windows')).windows
        $window = $windows | Where-Object { $_.id -eq $newWindow.id } | Select-Object -First 1

        if ($window -and $window.parentId -eq $terminalWorkspace.id) {
            break
        }

        Start-Sleep -Milliseconds 100
    }
}

$shownOnTopValue = $ShownOnTop.ToString().ToLowerInvariant()

Invoke-GlazeWMCommand -Arguments @('--id', $newWindow.id, 'move', '--workspace', $currentWorkspace.name)
Invoke-GlazeWMCommand -Arguments @('--id', $newWindow.id, 'set-floating', '--centered', "--shown-on-top=$shownOnTopValue")
Invoke-GlazeWMCommand -Arguments @('focus', '--container-id', $newWindow.id)
