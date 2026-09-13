# Drop-in source definition: Yazi (>= v25).
# Parses the seeded/default `keymap.toml` (and any user override at
# %APPDATA%\yazi\config\keymap.toml) into unified keybinding entries.
#
# Default keymap format:
#   [mgr]
#   keymap = [
#     { on = "k", run = "arrow prev", desc = "Previous file" },
#     { on = [ "g", "g" ], run = "arrow top", desc = "Go to top" },
#     { on = "<Space>", run = [ "toggle", "arrow next" ], desc = "..." },
#   ]
#
# Contract: see sources/glazewm.ps1 header.

$script:YaziSectionNames = @{
  'mgr' = 'Manager'
  'manager' = 'Manager'
  'tasks' = 'Tasks'
  'spot' = 'Spot'
  'pick' = 'Picker'
  'input' = 'Input'
  'confirm' = 'Confirm'
  'cmp' = 'Completion'
  'help' = 'Help'
}

function ConvertFrom-YaziEntry {
  param(
    [string]$Text,
    [string]$Section
  )

  $on = ''
  if ($Text -match 'on\s*=\s*("(?<v>[^"]*)"|\[(?<a>.*?)\])') {
    if ($matches['a']) {
      $parts = [regex]::Matches($matches['a'], '"(?<k>[^"]*)"') |
        ForEach-Object { $_.Groups['k'].Value }
      $on = ($parts -join ' ')
    }
    else { $on = $matches['v'] }
  }

  $run = ''
  if ($Text -match 'run\s*=\s*("(?<v>[^"]*)"|\[(?<a>.*?)\])') {
    if ($matches['a']) {
      $parts = [regex]::Matches($matches['a'], '"(?<k>[^"]*)"') |
        ForEach-Object { $_.Groups['k'].Value }
      $run = ($parts -join ' ; ')
    }
    else { $run = $matches['v'] }
  }

  $desc = ''
  if ($Text -match 'desc\s*=\s*"([^"]*)"') { $desc = $matches[1] }

  if (-not $on -or -not $run) { return $null }

  $modeName = if ($script:YaziSectionNames.ContainsKey($Section)) {
    $script:YaziSectionNames[$Section]
  }
  else { $Section }

  [pscustomobject]@{
    Mode = $modeName
    Keys = $on
    Action = $run
    Description = $desc
  }
}

function ConvertFrom-YaziKeymap {
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  $entries = [System.Collections.Generic.List[object]]::new()
  $lines = Get-Content -LiteralPath $Path
  $section = ''
  $i = 0

  while ($i -lt $lines.Count) {
    $t = $lines[$i].Trim()

    if ($t -match '^\[([^\]\s]+)\]') {
      $section = $matches[1]
      $i++
      continue
    }

    if ($t.StartsWith('{')) {
      $buffer = $t
      while ($i -lt $lines.Count) {
        $clean = $buffer.Trim().TrimEnd(',')
        if ($clean.EndsWith('}')) { break }
        $i++
        if ($i -lt $lines.Count) { $buffer += ' ' + $lines[$i].Trim() }
      }

      $entry = ConvertFrom-YaziEntry -Text $buffer -Section $section
      if ($entry) { $entries.Add($entry) }
    }

    $i++
  }

  return $entries
}

function Get-YaziSource {
  @{
    Name  = 'Yazi'
    Color = '#38BDF8'
    Paths = @(
      (Join-Path $env:APPDATA 'yazi/config/keymap.toml'),
      (Join-Path $PSScriptRoot 'yazi/keymap.toml')
    )
    Parse = {
      param([string]$FilePath)
      ConvertFrom-YaziKeymap -Path $FilePath
    }
  }
}

Get-YaziSource