# =============================================================================
# Line editor
# =============================================================================
# -MinimumVersion, not RequiredVersion, so PowerShell upgrades self-heal.
# Without it, Documents\PowerShell\Modules\PSReadLine\2.2.6 (2021) shadows the
# bundled 2.4.5, because the CurrentUser module path comes first in
# $env:PSModulePath.
#
# Do NOT "fix" that with Remove-Module PSReadLine. .NET never unloads
# assemblies, so that leaves the cmdlets on 2.4.5 while
# [Microsoft.PowerShell.PSConsoleReadLine] stays bound to 2.2.6.0 --
# Set-PSReadLineOption then silently does nothing. Pinning here works because a
# fresh session never loads 2.2.6 in the first place.
Import-Module PSReadLine -MinimumVersion 2.4.5
Invoke-Expression (&starship init powershell)

# Note: the parameter is -ViModeIndicator (it takes a ViModeStyle enum), and
# there is no -ViModeStyle parameter in 2.4.5.
Set-PSReadLineOption -EditMode Vi -ViModeIndicator Prompt `
    -HistoryNoDuplicates -Colors @{
    Command            = 'Magenta'
    Number             = 'DarkGray'
    Member             = 'DarkGray'
    Operator           = 'DarkMagenta'
    Type               = 'DarkCyan'
    Variable           = 'Green'
    Parameter          = 'DarkGreen'
    ContinuationPrompt = 'DarkGray'
}

# Prediction and ListView both need a VT-capable console host. Redirected output
# and `pwsh -c` are not VT-capable, and PSReadLine throws a *terminating* error
# there -- so -ErrorAction Ignore does not suppress it and it must be caught.
# Everything above has already applied; these two are cosmetic.
#
# InlineView, not ListView: with ListView, PSReadLine painted a <History(10)>
# multi-line suggestion tooltip over the top of the screen on every single line.
# That only became visible once PSReadLine 2.4.5 actually loaded (under 2.2.6
# the prediction settings never took effect), and it directly competes with
# Ctrl+r. Inline keeps a discreet grey suggestion you can take with RightArrow.
try {
    Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
}
catch {
    # not a VT-capable host; carry on
}

$global:__psrl_history = (Get-PSReadLineOption).HistorySavePath

# =============================================================================
# TUI launchers
# =============================================================================
# Aliases, not keybindings: in Vi mode no chord is free in both Insert and
# Command mode, and hunting for free ones is the opposite of a simple system.
# Chords below are reserved for things you do *while typing a line*.
Set-Alias -Name vim -Value nvim
Set-Alias -Name lzg -Value lazygit
Set-Alias -Name lzd -Value lazydocker
Set-Alias -Name gd  -Value 'G:\T\Tools\gh-dash.exe'

function global:yy {
    # yazi, then cd wherever it left the cursor.
    $cwdFile = [System.IO.Path]::GetTempFileName()
    try {
        yazi --cwd-file $cwdFile
        $target = if (Test-Path -LiteralPath $cwdFile) {
            (Get-Content -LiteralPath $cwdFile -Raw).Trim()
        } else { '' }
        if ($target) { Microsoft.PowerShell.Management\Set-Location -LiteralPath $target }
    }
    finally {
        Remove-Item -LiteralPath $cwdFile -Force -ErrorAction Ignore
    }
}

function global:psm {
    # psmux is not `ps` -- that alias belongs to Get-Process.
    psmux attach @args
}

# =============================================================================
# zoxide
# =============================================================================
# Hand-rolled replacement for the official init:
#
#   Invoke-Expression (& { (zoxide init powershell | Out-String) })
#
# That costs 65ms warm / 120ms cold *per pane* (native spawn plus a second
# parse of ~130 lines of PowerShell at runtime). The definitions below are part
# of this file's single parse, so they cost ~0. Semantics match the official
# init. If zoxide's behaviour ever changes, re-run the line above and drop these
# back in.

# zoxide/fd/rg emit UTF-8. Set the console encoding once, here, rather than
# reassigning it inside a helper. The helper this replaces (__zoxide_bin)
# reassigned it in a try/finally on every call, and that throws when PSReadLine
# invokes the function from its background thread -- which silently killed the
# Alt+c binding.
try { [Console]::OutputEncoding = [System.Text.Utf8Encoding]::new() } catch { }

function global:z {
    if ($args.Length -eq 0) {
        Microsoft.PowerShell.Management\Set-Location
        return
    }
    if ($args.Length -eq 1 -and (Microsoft.PowerShell.Management\Test-Path -LiteralPath $args[0])) {
        Microsoft.PowerShell.Management\Set-Location -LiteralPath $args[0]
        return
    }
    $result = zoxide query -- $args
    if ($LASTEXITCODE -eq 0 -and $result) {
        Microsoft.PowerShell.Management\Set-Location -LiteralPath $result
    }
}

# Interactive jump, usable as a command. Prefer Alt+c (__zoxide_pick) -- this
# is the same thing but entered as a command.
function global:zi {
    $result = zoxide query -i -- $args
    if ($LASTEXITCODE -eq 0 -and $result) {
        Microsoft.PowerShell.Management\Set-Location -LiteralPath $result
    }
}

# Records every visited directory in zoxide's frecency db. Runs from prompt,
# i.e. on the main runspace.
function global:__zoxide_hook {
    $loc = Microsoft.PowerShell.Management\Get-Location
    if ($loc.Provider.Name -ne 'FileSystem') { return }
    $path = $loc.ProviderPath
    if (-not $path) { return }
    if ($path -ne $global:__zoxide_pwd) {
        $global:__zoxide_pwd = $path
        $null = zoxide add -- $path
    }
}

$global:__zoxide_old_prompt = $function:prompt

function global:prompt {
    if ($null -ne $global:__zoxide_old_prompt) { & $global:__zoxide_old_prompt }
    $null = __zoxide_hook
}

$loc = Microsoft.PowerShell.Management\Get-Location
$global:__zoxide_pwd = if ($loc.Provider.Name -eq 'FileSystem') { $loc.ProviderPath } else { $null }

# =============================================================================
# fzf pickers
# =============================================================================
# Ctrl+r  history, recency first
# Ctrl+t  files under cwd, seeded with the last token on the line
# Alt+c   zoxide frecency jump
#
# Two rules make all three behave identically:
#
# 1. One launch path. Every picker goes through __fzf_pick, so the flags there
#    are the only thing that decides size, border, layout and prompt. Alt+c used
#    to delegate to zoxide's own fzf preset and came out a different size from
#    the other two.
#
# These run *inside* the PSReadLine handler, not via an AcceptLine'd helper
# command. That is deliberate, and it is the whole point:
#
#  - The read loop is live, so Replace() writes into the buffer you are actually
#    editing. The pick is left there to edit: no clipboard, no extra keystroke.
#
#  - Nothing is submitted. Ctrl+r and Ctrl+t only ever call Replace, never
#    AcceptLine, so picking a command out of history can never run it. An earlier
#    version routed them through AcceptLine + a helper command on the main
#    runspace; the text did land on the line, but it was auto-submitted with it,
#    so picking `rm -rf ...` would have executed it. Do not reintroduce that.
#
#  - Alt+c is the only one that submits, because a directory change has to take
#    effect on the main runspace. It fills in `z <path>` and AcceptLine()s it, so
#    the only thing that can ever run is a z jump.
#
#  - Every picker calls __fzf_repaint between closing fzf and writing the
#    buffer, or PSReadLine renders the pick at the wrong screen position. See
#    __fzf_repaint; do not drop it, and do not move it after the Replace.
#
# All three share __fzf_pick, so size, border, layout and prompt are identical.
#
# fzf is launched through System.Diagnostics.Process rather than `| & fzf`.
#
# PSFzf hit the same wall and left this note in its own source:
#   "--height doesn't work with Invoke-Expression - not sure why. Thus, we need
#    to use System.Diagnostics.Process"
# Whatever the underlying cause, going through PowerShell's native-command
# machinery made every picker fall back to a fullscreen window, while the same
# picker launched elsewhere (zoxide launches fzf itself, which is why the `zi`
# command has always rendered as a proper popup) stayed inline. The author's own
# "not sure why" is worth keeping in mind: this is a proven workaround, not a
# documented root cause.
#
# ArgumentList rather than a single Arguments string, so .NET handles quoting and
# prompts/queries containing spaces cannot break. PSFzf only uses ArgumentList's
# predecessor because it also integrates with the PowerShell pipeline; we build
# the item list ourselves, so no Add-Type/Roslyn JIT cost is needed either.
#
# --height is adaptive on purpose. With the '~' prefix fzf sizes the window to
# its content, so it fits both the 5-item zoxide list and the 12k-line history.
$script:__fzf_exe = (Get-Command fzf -ErrorAction Ignore).Source

function global:__fzf_pick {
    param([string[]]$Items, [string]$Prompt, [string]$Query = '', [switch]$Reverse, [switch]$NoSort)

    # --no-sort is opt-in, not shared. History and the zoxide list are handed to
    # us already ranked (newest first / by score) and must keep that order.
    # The file picker must NOT have it, or fzf cannot re-rank as you type and
    # every match stays buried at its position in fd's traversal order.
    $fzfArgs = @('--height=~50%', '--min-height=8', '--layout=reverse', '--border',
        '--info=inline', '--prompt', "$Prompt ")
    if ($NoSort) { $fzfArgs += '--no-sort' }
    if ($Reverse) { $fzfArgs += '--tac' }

    if (-not $script:__fzf_exe) { return }

    $start = [System.Diagnostics.ProcessStartInfo]::new($script:__fzf_exe)
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $location = Microsoft.PowerShell.Management\Get-Location
    if ($location.Provider.Name -eq 'FileSystem') { $start.WorkingDirectory = $location.ProviderPath }

    foreach ($arg in $fzfArgs) { [void]$start.ArgumentList.Add($arg) }
    [void]$start.ArgumentList.Add('--query')
    [void]$start.ArgumentList.Add($Query)

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void]$process.Start()

    # Write every item, then close stdin so fzf sees EOF and starts rendering.
    # Newline is written explicitly as LF rather than via WriteLine(), which would
    # emit CRLF and leave a stray \r on the end of every item.
    $writer = [System.IO.StreamWriter]::new(
        $process.StandardInput.BaseStream, [System.Text.UTF8Encoding]::new($false))
    foreach ($item in $Items) { $writer.Write($item + "`n") }
    $writer.Flush()
    $writer.Close()

    # Read before waiting, so a large selection cannot deadlock the pipe.
    $selected = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()

    # fzf terminates its output with a newline. Piping through `| & fzf` used to
    # split the output into lines and drop it for us; reading the stream directly
    # does not, so it has to go here. Left in place it ends up inside the input
    # line -- the pick renders across two lines, and Alt+c submits a malformed
    # `z '<path>'` followed by a newline.
    $selected.TrimEnd("`r", "`n")
}

# Force PSReadLine to recompute its screen coordinates after a picker closes.
#
# fzf draws its popup and then erases it again, which leaves PSReadLine still
# believing the prompt sits on its original row. The buffer content is correct
# but the render is corrupted: the start of the line is replaced by whitespace
# and the pick lands at the wrong column. Ctrl+l hides this, because ClearScreen
# forces the same kind of repaint.
#
# PSFzf works around precisely this in its InvokePromptHack (see PSFzf issue
# #71). Two details are load-bearing and both are copied from it:
#   * InvokePrompt() is called BEFORE the buffer is written. Doing it afterwards
#     redraws and discards the text you just inserted.
#   * Console.OutputEncoding is forced to UTF-8 around the call, or the redraw
#     can mangle non-ASCII characters.
function global:__fzf_repaint {
    $previousOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    try {
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    }
    finally {
        [Console]::OutputEncoding = $previousOutputEncoding
    }
}

function global:__fzf_history {
    $line = $null; $cursor = 0
    $null = [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    $items = @(Get-Content -LiteralPath $global:__psrl_history -ErrorAction Ignore |
        Where-Object { $_ -match '\S' })
    $selected = __fzf_pick -Items $items -Prompt 'history>' -Reverse -NoSort

    __fzf_repaint
    if ($selected) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $selected)
    }
}

function global:__fzf_files {
    $line = $null; $cursor = 0
    $null = [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # Only the last whitespace-separated token of the line is the partial path
    # being typed. Everything before it is the command and any earlier arguments,
    # which must survive untouched. Seeding fzf with the whole prefix (e.g. "cat ")
    # meant the query was a fuzzy match for "cat ", which 'scope.md' cannot
    # satisfy -- so the file you were obviously about to name was unfindable.
    $prefix = $line.Substring(0, $cursor)
    # [char[]] is required: passing two separate strings makes PowerShell bind
    # LastIndexOfAny(char[], int) instead, and the tab then lands in startIndex.
    $lastBreak = $prefix.LastIndexOfAny([char[]]@(' ', [char]9))
    $head = if ($lastBreak -ge 0) { $prefix.Substring(0, $lastBreak + 1) } else { '' }
    $token = if ($lastBreak -ge 0) { $prefix.Substring($lastBreak + 1) } else { $prefix }

    # Deliberately not sorted: a large tree (G:\ has ~120k entries) makes
    # Sort-Object cost a few hundred ms per keystroke. fzf does the ranking.
    $fdArgs = @('--type', 'f', '--type', 'd', '--hidden', '--exclude', '.git')
    $selected = __fzf_pick -Items @(& fd @fdArgs) -Prompt 'files>' -Query $token

    __fzf_repaint
    if ($selected) {
        # Quote on whitespace *or* a single quote -- "it's.ps1" has no space but
        # still cannot be pasted unquoted into PowerShell.
        $quoted = if ($selected -match "[\s']") {
            "'" + $selected.Replace("'", "''") + "'"
        } else { $selected }
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, ($head + $quoted))
    }
}

function global:__zoxide_pick {
    $line = $null; $cursor = 0
    $null = [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    $items = @(zoxide query --list 2>$null | Where-Object { $_ -match '\S' })
    $selected = __fzf_pick -Items $items -Prompt 'jump>' -NoSort
    __fzf_repaint
    if ($selected) {
        $quoted = "'" + $selected.Replace("'", "''") + "'"
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, ("z $quoted"))
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}

# Chord bindings. Binding a ScriptBlock over an existing chord replaces it, so no
# unbind pass is needed. -ViMode forces the ScriptBlock parameter set, so
# -Function is rejected there.
Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ViMode Insert -ScriptBlock { __fzf_history } `
    -BriefDescription 'fzf history'
Set-PSReadLineKeyHandler -Chord 'Ctrl+t' -ViMode Insert -ScriptBlock { __fzf_files } `
    -BriefDescription 'fzf files'
Set-PSReadLineKeyHandler -Chord 'Alt+c' -ViMode Insert -ScriptBlock { __zoxide_pick } `
    -BriefDescription 'zoxide jump'


# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a
# vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
# Inlining the template into the profile shaves off ~10ms (25%).
$script:__COREUTILS__ = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'arch', 'b2sum', 'base32', 'base64', 'basename',
        'basenc', 'cat', 'cksum', 'comm', 'cp',
        'csplit', 'cut', 'date', 'df', 'dirname',
        'du', 'echo', 'env', 'expr', 'factor',
        'false', 'find', 'fmt', 'fold', 'grep',
        'head', 'hostname', 'join', 'la', 'link',
        'ln', 'ls', 'md5sum', 'mkdir', 'mktemp',
        'mv', 'nl', 'nproc', 'numfmt', 'od',
        'pathchk', 'pr', 'printenv', 'printf', 'ptx',
        'pwd', 'readlink', 'realpath', 'rm', 'rmdir',
        'seq', 'sha1sum', 'sha224sum', 'sha256sum', 'sha384sum',
        'sha512sum', 'shuf', 'sleep', 'sort', 'split',
        'stat', 'sum', 'tac', 'tail', 'tee',
        'test', 'touch', 'tr', 'true', 'truncate',
        'tsort', 'unexpand', 'uniq', 'unlink', 'uptime',
        'wc', 'xargs', 'yes'
    ),
    [System.StringComparer]::OrdinalIgnoreCase
)

$script:__COREUTILS_FAST_SKIP__ = [regex]::new(
    '\b(?:' + ($script:__COREUTILS__ -join '|') + ')\b',
    [System.Text.RegularExpressions.RegexOptions]::Compiled -bor `
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

# Casting the scriptblock to Func<Ast,bool> once and reusing it avoids the
# per-FindAll scriptblock-to-delegate wrapping overhead (~1.7x faster).
$script:__COREUTILS_CMD_PREDICATE__ = [System.Func[System.Management.Automation.Language.Ast, bool]] {
    param($n) $n -is [System.Management.Automation.Language.CommandAst]
}

$script:__COREUTILS_ARG_SPECIAL__ = [char[]] @("'", '"', '`', '$')

# Wrap arguments into quotes. By being a function we can properly handle $variables.
# As per MSVCRT, any `\` before `"` must be doubled to escape them.
function global:__coreutils_q {
    param($s)
    '"' + (([string]$s) -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# PowerShell tokenizes `*"a"*` as [BareWord] instead of the expected [DoubleQuoted, BareWord, DoubleQuoted].
# To work around that we use... regex. Group 1 = 'single', 2 = "double", 3 = `escape, 4 = bare run.
$script:__COREUTILS_ARG_RX__ = [regex]::new(
    "'((?:[^']|'')*)'|""((?:[^""``]|""""|``.)*)""|``(.)|([^'""``]+)",
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)
$script:__COREUTILS_ARG_EVAL__ = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    if ($m.Groups[1].Success) {
        # Single-quoted: literal. PS '' -> ', then MSVCRT-quote.
        $body = $m.Groups[1].Value.Replace("''", "'")
        if ($body -match '^(.*?)(\\+)$') {
            return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
        }
        return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
    }
    if ($m.Groups[2].Success) {
        # Double-quoted: collapse PS quote-escapes to raw " / ', let ExpandString
        # resolve `n / `t / $var, then MSVCRT-quote.
        $body = $m.Groups[2].Value.
        Replace('`"', '"').
        Replace("``'", "'").
        Replace('""', '"')
        $body = $ExecutionContext.InvokeCommand.ExpandString($body)
        if ($body -match '^(.*?)(\\+)$') {
            return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
        }
        return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
    }
    if ($m.Groups[3].Success) {
        # Backtick-escaped char outside a string: " -> \"; everything else
        # becomes a one-char quoted region so glob metas stay literal.
        $c = $m.Groups[3].Value
        if ($c -eq '"') {
            return '\"'
        }
        return '"' + $c + '"'
    }
    # Bare run: passed through unquoted so coreutils can glob it; expand $vars.
    return $ExecutionContext.InvokeCommand.ExpandString($m.Groups[4].Value)
}

# PSConsoleHostReadLine override that rewrites coreutils command names to their
# .cmd equivalents after PSReadLine returns (history keeps the original).
#
# Why .cmd over .exe: PSNativeCommandArgumentPassing = 'Windows' results in a behavior
# where passing bare quotes to CreateProcess() is impossible. This prevents us from
# passing "*" as "*" to coreutils and instead will be given as a bare *.
# This causes it to treat it as a glob pattern. "*.cmd" files however are automatically
# treated as PSNativeCommandArgumentPassing = 'Legacy', which preserves quotes.
# It is the only possible workaround and the only way coreutils can work at all.
function PSConsoleHostReadLine {
    [System.Diagnostics.DebuggerHidden()]
    param()

    $lastRunStatus = $?
    Microsoft.PowerShell.Core\Set-StrictMode -Off
    $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($host.Runspace, $ExecutionContext, $lastRunStatus)

    # If the line contains no coreutils name, we don't need to parse the AST at all.
    if (-not $script:__COREUTILS_FAST_SKIP__.IsMatch($line)) {
        return $line
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$null, [ref]$null)
    $commands = $ast.FindAll($script:__COREUTILS_CMD_PREDICATE__, $true)

    # Process right-to-left so earlier offsets stay valid after each splice.
    # In-place reverse beats Sort-Object for the typical 1-command line.
    if ($commands.Count -gt 1) {
        $commands = [System.Collections.Generic.List[object]]::new($commands)
        $commands.Reverse()
    }

    foreach ($cmd in $commands) {
        $name = $cmd.GetCommandName()
        if (!$name) {
            continue
        }

        $baseName = $name
        if ($name.EndsWith('.exe') -or $name.EndsWith('.cmd')) {
            $baseName = $name.Substring(0, $name.Length - 4)
        }
        if (!$script:__COREUTILS__.Contains($baseName)) {
            continue
        }

        # ls/la get colour + listing flags injected; la also rewrites to ls.
        $cmdElement = $cmd.CommandElements[0]
        $start = $cmdElement.Extent.StartOffset
        $end = $cmdElement.Extent.EndOffset
        $replacement = "& 'C:\Program Files\coreutils\cmd\"

        switch ($baseName) {
            'la' { $replacement += "ls.cmd' --color=auto -AFhl" }
            'ls' { $replacement += "ls.cmd' --color=auto" }
            default { $replacement += "$baseName.cmd'" }
        }

        # Walk command elements, merging adjacent ones whose extents touch
        # (e.g. `'a'*` parses as [SingleQuoted, BareWord] but is one shell word).
        # The inverse case `*'a'*` parses as a single BareWord whose text
        # contains the embedded quotes, which is why AST-only analysis
        # isn't enough and we still need to re-tokenize the source span.
        $argsStart = $end
        $argsEnd = $cmd.Extent.EndOffset
        $rewrittenArgs = ''
        $elements = $cmd.CommandElements
        $count = $elements.Count
        $i = 1
        while ($i -lt $count) {
            $first = $elements[$i]
            $wordStart = $first.Extent.StartOffset
            $wordEnd = $first.Extent.EndOffset
            $merged = $false
            while ($i + 1 -lt $count -and $elements[$i + 1].Extent.StartOffset -eq $wordEnd) {
                $i++
                $wordEnd = $elements[$i].Extent.EndOffset
                $merged = $true
            }
            $source = $line.Substring($wordStart, $wordEnd - $wordStart)
            $rewrittenArgs += $line.Substring($argsStart, $wordStart - $argsStart)
            $argsStart = $wordEnd
            # IndexOfAny beats running the regex per arg.
            if ($source.IndexOfAny($script:__COREUTILS_ARG_SPECIAL__) -lt 0) {
                $rewrittenArgs += $source
                $i++
                continue
            }
            # A single un-merged PS expression that needs $var resolution
            # (bare $var, "...$var...", $x.Member, $($expr), etc.).
            # Defer evaluation to runtime so the value reaches coreutils as a literal arg.
            # This matches POSIX behaviour where variable expansions don't result in globbing.
            if (-not $merged -and
                ($first -is [System.Management.Automation.Language.VariableExpressionAst] -or
                $first -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
                $first -is [System.Management.Automation.Language.MemberExpressionAst])) {
                $rewrittenArgs += '(__coreutils_q ' + $source + ')'
                $i++
                continue
            }
            # Slow path: re-tokenise and re-emit as MSVCRT-style quoting,
            # then wrap in PS single quotes so PS hands the body verbatim.
            $windowsQuoted = $script:__COREUTILS_ARG_RX__.Replace($source, $script:__COREUTILS_ARG_EVAL__)
            $rewrittenArgs += "'" + $windowsQuoted.Replace("'", "''") + "'"
            $i++
        }
        $rewrittenArgs += $line.Substring($argsStart, $argsEnd - $argsStart)

        $line = $line.Substring(0, $start) + $replacement + $rewrittenArgs + $line.Substring($argsEnd)
    }

    return $line
}
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a
