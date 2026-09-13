#requires -Version 5.1
[CmdletBinding()]
param()

# WPF requires a single-threaded apartment; relaunch under -STA if needed.
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
  $pwshExe = Join-Path $PSHOME 'pwsh.exe'
  if (-not (Test-Path -LiteralPath $pwshExe)) { $pwshExe = (Get-Process -Id $PID).Path }
  Start-Process -FilePath $pwshExe -ArgumentList @(
    '-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
  ) | Out-Null
  exit 0
}

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Xaml

$script:AllEntries = [System.Collections.Generic.List[object]]::new()
$brushConverter = New-Object System.Windows.Media.BrushConverter

# Load every drop-in source from sources\*.ps1 and parse the first existing
# path for each. Each source returns one object: Name / Color / Paths / Parse.
foreach ($file in (Get-ChildItem -Path (Join-Path $PSScriptRoot 'sources') -Filter '*.ps1' | Sort-Object Name)) {
  $src = . $file.FullName
  if (-not $src -or -not $src.Paths -or -not $src.Parse) { continue }

  foreach ($path in $src.Paths) {
    if (-not (Test-Path -LiteralPath $path)) { continue }

    $color = if ($src.Color) { $src.Color } else { '#7A7A85' }
    foreach ($entry in (& $src.Parse $path)) {
      if (-not $entry -or -not $entry.Keys) { continue }
      $searchText = ("$($src.Name) $($entry.Mode) $($entry.Keys) $($entry.Action) $($entry.Description)")
      $script:AllEntries.Add([pscustomobject]@{
        Program     = $src.Name
        ProgramBrush = $brushConverter.ConvertFromString($color)
        Mode        = [string]$entry.Mode
        Keys        = [string]$entry.Keys
        Action      = [string]$entry.Action
        Description = [string]$entry.Description
        SearchText  = $searchText.ToLower()
      })
    }
    break
  }
}

if ($script:AllEntries.Count -eq 0) {
  Write-Error 'No keybinding entries were loaded from sources.'
  exit 1
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Keybindings"
        Width="820" Height="560"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        FontFamily="Segoe UI" FontSize="13" Foreground="#D8D8D8">
  <Window.Resources>
    <SolidColorBrush x:Key="PanelBrush" Color="#E6212128"/>
    <SolidColorBrush x:Key="PanelBorderBrush" Color="#5A3D3D49"/>
  </Window.Resources>

  <Border Margin="30" CornerRadius="12"
          Background="{StaticResource PanelBrush}"
          BorderBrush="{StaticResource PanelBorderBrush}"
          BorderThickness="1" SnapsToDevicePixels="True">
    <Border.Effect>
      <DropShadowEffect Color="#000000" BlurRadius="28" ShadowDepth="0" Opacity="0.55"/>
    </Border.Effect>

    <Grid Margin="16,14,16,14">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="10"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="#362B2B33" CornerRadius="8"
              BorderBrush="#4D4D4D5A" BorderThickness="1" Padding="10,6">
        <DockPanel>
          <TextBlock DockPanel.Dock="Right" x:Name="CountText" Text=""
                     VerticalAlignment="Center" Margin="8,0,0,0"
                     Foreground="#8A8A93" FontSize="12"/>
          <TextBox x:Name="FilterBox" Background="Transparent" BorderThickness="0"
                   Foreground="#E6E6E6" CaretBrush="#E6E6E6" FontSize="14"
                   VerticalContentAlignment="Center" Text=""/>
        </DockPanel>
      </Border>

      <ListView Grid.Row="2" x:Name="Results" BorderThickness="0"
                Background="Transparent"
                ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                ScrollViewer.VerticalScrollBarVisibility="Hidden">
        <ListView.ItemContainerStyle>
          <Style TargetType="ListViewItem">
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Margin" Value="0,0,0,3"/>
            <Setter Property="Focusable" Value="False"/>
          </Style>
        </ListView.ItemContainerStyle>
        <ListView.ItemTemplate>
          <DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="80"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*" MinWidth="150"/>
                <ColumnDefinition Width="Auto" MaxWidth="240"/>
              </Grid.ColumnDefinitions>

              <Border Grid.Column="0" CornerRadius="5" Padding="7,2"
                      Margin="0,3,8,3" VerticalAlignment="Stretch"
                      Background="{Binding ProgramBrush}">
                <TextBlock Text="{Binding Program}" Foreground="White"
                           FontWeight="SemiBold" FontSize="11"
                           VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
              </Border>

              <TextBlock Grid.Column="1" Text="{Binding Mode}" Foreground="#C58AF9"
                         Margin="0,0,12,0" VerticalAlignment="Center" FontSize="12"/>

              <Border Grid.Column="2" CornerRadius="4" Background="#1F1F27"
                      BorderBrush="#4A4A55" BorderThickness="1" Padding="7,2"
                      Margin="0,2,12,2" VerticalAlignment="Center">
                <TextBlock Text="{Binding Keys}" Foreground="#FFD166"
                           FontFamily="Cascadia Mono, Consolas" FontSize="12"
                           FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
              </Border>

              <TextBlock Grid.Column="3" Text="{Binding Description}" Foreground="#9AA0A6"
                         VerticalAlignment="Center" FontSize="12.5"
                         TextTrimming="CharacterEllipsis"/>

              <TextBlock Grid.Column="4" Text="{Binding Action}" Foreground="#7FD962"
                         FontFamily="Cascadia Mono, Consolas" FontSize="12"
                         VerticalAlignment="Center" TextTrimming="CharacterEllipsis"
                         ToolTip="{Binding Action}"/>
            </Grid>
          </DataTemplate>
        </ListView.ItemTemplate>
      </ListView>
    </Grid>
  </Border>
</Window>
'@

$script:Window = [System.Windows.Markup.XamlReader]::Parse($xaml)
$script:FilterBox = $script:Window.FindName('FilterBox')
$script:Results   = $script:Window.FindName('Results')
$script:CountText = $script:Window.FindName('CountText')

function Update-Results {
  $query = $script:FilterBox.Text.Trim().ToLower()
  $items = if ($query) {
    @($script:AllEntries | Where-Object { $_.SearchText.Contains($query) })
  }
  else {
    @($script:AllEntries)
  }

  $script:Results.ItemsSource = $items
  $script:CountText.Text = "$($items.Count) / $($script:AllEntries.Count)"
  $script:Results.SelectedIndex = if ($items.Count -gt 0) { 0 } else { -1 }
}

function Move-Selection {
  param([int]$Delta)

  if ($script:Results.Items.Count -eq 0) { return }
  $max = $script:Results.Items.Count - 1
  $newIndex = [Math]::Max(0, [Math]::Min($max, $script:Results.SelectedIndex + $Delta))
  $script:Results.SelectedIndex = $newIndex
  if ($newIndex -ge 0) { $script:Results.ScrollIntoView($script:Results.Items[$newIndex]) }
}

function Remove-LastWord {
  $text = $script:FilterBox.Text
  $caret = $script:FilterBox.CaretIndex
  if ([string]::IsNullOrEmpty($text) -or $caret -le 0) { return }

  # Skip trailing whitespace, then walk back to the start of the previous word.
  $i = $caret
  while ($i -gt 0 -and [char]::IsWhiteSpace($text[$i - 1])) { $i-- }
  $start = $i
  while ($start -gt 0 -and -not [char]::IsWhiteSpace($text[$start - 1])) { $start-- }

  if ($start -lt $caret) {
    $script:FilterBox.Select($start, $caret - $start)
    $script:FilterBox.SelectedText = ''
  }
}

$script:FilterBox.Add_TextChanged({ Update-Results })

$script:FilterBox.Add_PreviewKeyDown({
  param($sender, $e)
  if ($e.Key -eq [System.Windows.Input.Key]::W -and
      ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
    Remove-LastWord
    $e.Handled = $true
    return
  }

  switch ($e.Key) {
    'Escape' { $script:Window.Close() }
    'Down'   { Move-Selection -Delta 1;  $e.Handled = $true }
    'Up'     { Move-Selection -Delta -1; $e.Handled = $true }
    'Enter'  { $e.Handled = $true }
  }
})

# Close when the popup loses focus (e.g. clicking elsewhere).
$script:Window.Add_Deactivated({ $script:Window.Close() })

$script:Window.Add_ContentRendered({
  $script:FilterBox.Focus() | Out-Null
  [System.Windows.Input.Keyboard]::Focus($script:FilterBox) | Out-Null
})

Update-Results

# Test hook: point KEYBINDINGS_LOOKUP_TEST at a JSON file path to emit the
# loaded entries and exit without showing the UI.
if ($env:KEYBINDINGS_LOOKUP_TEST) {
  $debug = $script:Results.ItemsSource | ForEach-Object {
    [pscustomobject]@{
      Program     = $_.Program
      Mode        = $_.Mode
      Keys        = $_.Keys
      Action      = $_.Action
      Description = $_.Description
      SearchText  = $_.SearchText
    }
  }
  [pscustomobject]@{ Total = $script:AllEntries.Count; Entries = @($debug) } |
    ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $env:KEYBINDINGS_LOOKUP_TEST
  exit 0
}

# Center on the monitor under the cursor.
$cursorPos = [System.Windows.Forms.Cursor]::Position
$screen = [System.Windows.Forms.Screen]::FromPoint($cursorPos)
$wa = $screen.WorkingArea
$script:Window.Left = $wa.Left + (($wa.Width - $script:Window.Width) / 2)
$script:Window.Top  = $wa.Top  + (($wa.Height - $script:Window.Height) / 2)

$script:Window.ShowDialog() | Out-Null