# Drop-in source definition: GlazeWM (glzr.io).
# Parses the `keybindings` / `binding_modes` sections of the GlazeWM YAML
# config into unified keybinding entries.
#
# Contract (returned hashtable):
#   Name   = program name shown in the UI badge
#   Color  = accent color for the program badge
#   Paths  = ordered list of candidate config paths (first existing wins)
#   Parse  = scriptblock: param([string]$FilePath) -> array of entries
# Each entry is a hashtable/pscustomobject with:
#   Mode, Keys, Action, Description

function ConvertFrom-GlazeWmConfig {
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  $lines = Get-Content -LiteralPath $Path
  $entries = [System.Collections.Generic.List[object]]::new()

  $mode = 'default'
  $inBindingModes = $false
  $pendingDesc = ''
  $pendingCommands = $null

  foreach ($line in $lines) {
    $t = $line.Trim()

    if ($t -eq '') {
      $pendingDesc = ''
      continue
    }

    # Comment -> becomes the description of the following entry.
    if ($t.StartsWith('#')) {
      $text = $t.TrimStart('#').Trim()
      if ($pendingDesc) { $pendingDesc += ' ' + $text }
      else { $pendingDesc = $text }
      continue
    }

    # Section headers only count at column 0 (the `keybindings:` inside a
    # binding mode is indented and must not reset the mode).
    if ($line -match '^binding_modes:\s*$') {
      $inBindingModes = $true
      $pendingDesc = ''
      continue
    }
    if ($line -match '^keybindings:\s*$') {
      $inBindingModes = $false
      $mode = 'default'
      $pendingDesc = ''
      continue
    }

    # Binding mode name (single-quoted; workspace `- name: "1"` uses double quotes).
    if ($t -match "^- name:\s*'([^']+)'\s*$") {
      if ($inBindingModes) { $mode = $matches[1]; $pendingDesc = '' }
      continue
    }

    if ($t -match '^- commands:\s*\[(.*)\]\s*$') {
      $pendingCommands = [regex]::Matches($matches[1], "'([^']*)'") |
        ForEach-Object { $_.Groups[1].Value }
      continue
    }

    if ($t -match '^bindings:\s*\[(.*)\]\s*$') {
      $bindings = [regex]::Matches($matches[1], "'([^']*)'") |
        ForEach-Object { $_.Groups[1].Value }
      if ($pendingCommands -and $bindings.Count -gt 0) {
        $entries.Add([pscustomobject]@{
            Mode = $mode
            Keys = ($bindings -join ' / ')
            Action = ($pendingCommands -join ' ; ')
            Description = $pendingDesc
        })
      }
      $pendingCommands = $null
      $pendingDesc = ''
    }
  }

  return $entries
}

function Get-GlazeWmSource {
  @{
    Name  = 'GlazeWM'
    Color = '#F97316'
    Paths = @(
      (Join-Path $env:USERPROFILE '.glzr/glazewm/config.yaml'),
      (Join-Path $PSScriptRoot '../../../config/glazewm/config.yaml')
    )
    Parse = {
      param([string]$FilePath)
      ConvertFrom-GlazeWmConfig -Path $FilePath
    }
  }
}

Get-GlazeWmSource