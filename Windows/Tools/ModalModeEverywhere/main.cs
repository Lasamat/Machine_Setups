// --- .NET 10 Native Script Directives ---
#:sdk Microsoft.NET.Sdk
#:property TargetFramework=net10.0-windows
#:property UseWindowsForms=true
#:property PublishAot=false
#:property AssemblyName=ModalModeEverywhere

using System.Diagnostics;
using System.Runtime.InteropServices;

// --- DYNAMIC STATE CONFIGURATION ---
Dictionary<string, KeybindingNode> appMaps = new(StringComparer.OrdinalIgnoreCase);
KeybindingNode? activeMap = null;
KeybindingNode? currentTrieNode = null;
string currentSequenceBuffer = "";
bool isLeaderActive = false;

// --- VISUAL WINDOW COMPONENT VARIABLES ---
OverlayForm? overlayWindow = null;
WhichKeyPanel? whichKeyPanel = null;
SynchronizationContext? uiSyncContext = null;

// --- WHICH-KEY LOOKUP STATE ---
const int WHICH_KEY_DELAY_MS = 500;
object whichKeyLock = new();
System.Threading.Timer? whichKeyTimer = null;
int whichKeyGeneration = 0;
bool whichKeyPanelVisible = false;
IntPtr whichKeyTargetWindow = IntPtr.Zero;

// --- WINDOWS INPUT CONSTANTS ---
const uint MAPVK_VK_TO_VSC = 0;
const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
const uint KEYEVENTF_KEYUP = 0x0002;
const uint KEYEVENTF_SCANCODE = 0x0008;
const uint LLKHF_LOWER_IL_INJECTED = 0x02;
const uint LLKHF_INJECTED = 0x10;

// --- ENGINE INITIALIZATION PIPELINE ---
Console.WriteLine(Environment.ProcessPath);
string? scriptDir = AppContext.GetData("EntryPointFileDirectoryPath") as string;
string configPath = scriptDir is not null
    ? Path.Combine(scriptDir, "shortcuts.txt")
    : Path.GetFullPath("./shortcuts.txt");
LoadFromTextFile(configPath);

Thread guiThread = new(StartOverlayWindowContext);
guiThread.SetApartmentState(ApartmentState.STA);
guiThread.Start();

while (uiSyncContext == null) { Thread.Sleep(10); }

IntPtr hookID = SetHook(HookCallback);

Console.WriteLine($"[Engine] Modal Engine Initialized successfully from: {Path.GetFileName(configPath)}");
Console.WriteLine("[Engine] Listening for Ctrl+G inside mapped applications...");
Application.Run();

UnhookWindowsHookEx(hookID);

// --- PLAIN TEXT PARSER MODULE ---
void LoadFromTextFile(string filePath)
{
    if (!File.Exists(filePath))
    {
        Console.WriteLine($"[Warning] Config file not found at: {filePath}. Generating empty fallback.");
        File.WriteAllText(filePath, "# Format: process_name | chord | macro_output | documentation_comment\n");
        return;
    }

    int loadedCount = 0;
    foreach (var rawLine in File.ReadLines(filePath))
    {
        string line = rawLine.Trim();
        if (string.IsNullOrEmpty(line) || line.StartsWith('#')) continue;

        var tokens = line.Split('|');
        if (tokens.Length < 3) continue;

        // Sanitize spaces so "Super Productivity" and "SuperProductivity" match cleanly
        string app = NormalizeProcessName(tokens[0]);
        string seq = tokens[1].Trim().ToLower();
        string keysStr = tokens[2].Trim();
        string description = tokens.Length >= 4 ? string.Join('|', tokens[3..]).Trim() : "";

        var vkList = new List<ushort>();
        foreach (var key in keysStr.Split(','))
        {
            ushort vk = StringToVk(key.Trim());
            if (vk != 0) vkList.Add(vk);
        }

        if (vkList.Count > 0 && !string.IsNullOrEmpty(seq))
        {
            if (!appMaps.TryGetValue(app, out var appMap))
            {
                appMap = new KeybindingNode();
                appMaps[app] = appMap;
            }
            appMap.AddSequence(seq, new KeyboardAction([.. vkList]) { Description = description });
            loadedCount++;
        }
    }
    Console.WriteLine($"[Parser] Successfully mapped {loadedCount} shortcuts across {appMaps.Count} unique apps.");
}

string NormalizeProcessName(string name) => name.Trim().Replace(" ", "");

ushort StringToVk(string name)
{
    return name.Trim().ToUpperInvariant() switch
    {
        "SHIFT" => 0x10,
        "CONTROL" => 0x11,
        "CTRL" => 0x11,
        "ALT" => 0x12,
        "ESCAPE" => 0x1B,
        "SPACE" => 0x20,
        "ENTER" => 0x0D,
        "BACK" => 0x08,
        "BACKSPACE" => 0x08,

        "LEFT" => 0x25,
        "UP" => 0x26,
        "RIGHT" => 0x27,
        "DOWN" => 0x28,

        var s when s.Length == 1 && s[0] >= 'A' && s[0] <= 'Z' => s[0],
        var s when s.Length == 1 && s[0] >= '0' && s[0] <= '9' => s[0],
        _ => 0x00
    };
}

// --- THREADED HUD OVERLAY ENGINE ---
void StartOverlayWindowContext()
{
    overlayWindow = new OverlayForm
    {
        FormBorderStyle = FormBorderStyle.None,
        BackColor = Color.FromArgb(22, 22, 22),
        Size = new Size(450, 45),
        StartPosition = FormStartPosition.Manual,
        TopMost = true,
        ShowInTaskbar = false,
        WindowState = FormWindowState.Normal
    };

    Rectangle screenBounds = Screen.PrimaryScreen!.Bounds;
    overlayWindow.Location = new Point((screenBounds.Width - overlayWindow.Width) / 2, screenBounds.Height - 120);

    whichKeyPanel = new WhichKeyPanel
    {
        Dock = DockStyle.Fill
    };
    overlayWindow.Controls.Add(whichKeyPanel);

    overlayWindow.HandleCreated += (s, e) =>
    {
        IntPtr handle = overlayWindow.Handle;
        IntPtr wl = GetWindowLong(handle, -20);
        SetWindowLong(handle, -20, wl | 0x80000 | 0x20 | 0x80 | 0x08000000);
    };

    IntPtr forceHandle = overlayWindow.Handle;
    uiSyncContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
    Application.Run(new ApplicationContext());
}

// --- WHICH-KEY LOOKUP ENGINE ---
string BuildWhichKeyHeader() =>
    currentSequenceBuffer.Length == 0 ? "[NORMAL]" : $"[NORMAL] {currentSequenceBuffer}";

List<WhichKeyEntry> BuildWhichKeyEntries(KeybindingNode node)
{
    return node.Children
        .OrderBy(kv => kv.Key)
        .Select(kv => new WhichKeyEntry(
            char.ToUpperInvariant(kv.Key).ToString(),
            kv.Value.Action?.Description is { Length: > 0 } description
                ? description
                : (kv.Value.Children.Count > 0 ? "more" : ""),
            kv.Value.Children.Count > 0))
        .ToList();
}

void RefreshWhichKey()
{
    int generation = CancelWhichKeyTimer();

    if (currentTrieNode == null)
    {
        HideWhichKeyUI();
        return;
    }

    List<WhichKeyEntry> entries = BuildWhichKeyEntries(currentTrieNode);
    if (entries.Count == 0)
    {
        HideWhichKeyUI();
        return;
    }

    string header = BuildWhichKeyHeader();

    // If the panel is already open, update it immediately so it never shows stale keys.
    if (whichKeyPanelVisible)
    {
        ShowWhichKeyUI(header, entries, whichKeyTargetWindow, generation);
        return;
    }

    IntPtr targetWindow = whichKeyTargetWindow;
    lock (whichKeyLock)
    {
        whichKeyTimer?.Dispose();
        whichKeyTimer = new System.Threading.Timer(_ =>
        {
            lock (whichKeyLock)
            {
                if (generation != whichKeyGeneration) return;
            }
            ShowWhichKeyUI(header, entries, targetWindow, generation);
        }, null, WHICH_KEY_DELAY_MS, Timeout.Infinite);
    }
}

int CancelWhichKeyTimer()
{
    lock (whichKeyLock)
    {
        whichKeyGeneration++;
        whichKeyTimer?.Dispose();
        whichKeyTimer = null;
        return whichKeyGeneration;
    }
}

void ShowWhichKeyUI(string header, List<WhichKeyEntry> entries, IntPtr targetWindow, int generation)
{
    uiSyncContext?.Post(_ =>
    {
        lock (whichKeyLock)
        {
            if (generation != whichKeyGeneration) return;
        }

        if (!isLeaderActive || overlayWindow == null || whichKeyPanel == null) return;

        Screen screen;
        try
        {
            screen = targetWindow != IntPtr.Zero
                ? Screen.FromHandle(targetWindow)
                : Screen.PrimaryScreen!;
        }
        catch
        {
            screen = Screen.PrimaryScreen!;
        }

        whichKeyPanel.SetMaxPanelWidth(Math.Max(320, (int)(screen.WorkingArea.Width * 0.9)));
        whichKeyPanel.SetContent(header, entries);

        Size panelSize = whichKeyPanel.GetPreferredSize(Size.Empty);
        overlayWindow.ClientSize = panelSize;

        Rectangle workingArea = screen.WorkingArea;
        int x = workingArea.Left + (workingArea.Width - overlayWindow.Width) / 2;
        int y = workingArea.Bottom - overlayWindow.Height - 48;
        overlayWindow.Location = new Point(x, Math.Max(workingArea.Top, y));

        if (!overlayWindow.Visible) overlayWindow.Show();
        overlayWindow.Invalidate(true);
        overlayWindow.Update();
        whichKeyPanelVisible = true;
    }, null);
}

void HideWhichKeyUI()
{
    whichKeyPanelVisible = false;
    uiSyncContext?.Post(_ =>
    {
        overlayWindow?.Hide();
        whichKeyPanelVisible = false;
    }, null);
}

IntPtr SetHook(LowLevelKeyboardProc proc)
{
    using Process curProcess = Process.GetCurrentProcess();
    using ProcessModule? curModule = curProcess.MainModule;
    IntPtr moduleHandle = curModule != null ? GetModuleHandle(curModule.ModuleName) : IntPtr.Zero;
    return SetWindowsHookEx(13, proc, moduleHandle, 0);
}

IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
{
    if (nCode >= 0 && wParam == 0x0100) // 0x0100 = WM_KEYDOWN
    {
        KBDLLHOOKSTRUCT hookStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);

        // Explicitly intercept our own simulated SendInput events to avoid infinite hook looping
        bool isInjected = (hookStruct.flags & LLKHF_INJECTED) != 0 ||
                          (hookStruct.flags & LLKHF_LOWER_IL_INJECTED) != 0 ||
                          hookStruct.dwExtraInfo == new UIntPtr(0x1337);

        if (isInjected)
        {
            return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
        }

        int vkCode = (int)hookStruct.vkCode;
        Keys key = (Keys)vkCode;

        string activeApp = NormalizeProcessName(GetActiveProcessName());
        // Console.WriteLine(activeApp);
        bool isTargetApp = appMaps.ContainsKey(activeApp);

        // --- STATE 1: STANDARD TYPING INTERACTION ---
        if (!isLeaderActive)
        {
            if (key == Keys.G && Control.ModifierKeys == Keys.Control && isTargetApp)
            {
                isLeaderActive = true;
                activeMap = appMaps[activeApp];
                currentTrieNode = activeMap;
                currentSequenceBuffer = "";
                whichKeyTargetWindow = GetForegroundWindow();
                RefreshWhichKey();
                return 1;
            }
        }
        // --- STATE 2: PERSISTENT MODAL TUNNEL LOCKED ---
        else
        {
            if (activeMap == null)
            {
                isLeaderActive = false;
                currentTrieNode = null;
                currentSequenceBuffer = "";
                CancelWhichKeyTimer();
                HideWhichKeyUI();
                return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
            }

            if (key == Keys.Escape)
            {
                isLeaderActive = false;
                activeMap = null;
                currentTrieNode = null;
                currentSequenceBuffer = "";
                CancelWhichKeyTimer();
                HideWhichKeyUI();
                return 1;
            }

            char inputChar = KeyCodeToChar(key);
            if (inputChar != '\0')
            {
                currentSequenceBuffer += inputChar;

                if (currentTrieNode != null && currentTrieNode.Children.TryGetValue(inputChar, out var nextNode))
                {
                    currentTrieNode = nextNode;

                    if (currentTrieNode.Action != null)
                    {
                        ExecuteKeyboardAction(currentTrieNode.Action);

                        // Reset loop state to root to allow continuous repeating within the mode
                        currentTrieNode = activeMap;
                        currentSequenceBuffer = "";
                    }

                    RefreshWhichKey();
                    return 1;
                }
                else
                {
                    // Fallback to direct root execution logic to prevent dropped strokes on repeated navigation
                    if (activeMap.Children.TryGetValue(inputChar, out var rootMatchNode) && rootMatchNode.Action != null)
                    {
                        ExecuteKeyboardAction(rootMatchNode.Action);
                    }

                    currentTrieNode = activeMap;
                    currentSequenceBuffer = "";
                    RefreshWhichKey();
                    return 1;
                }
            }

            // Let non-alphanumeric keys pass through so they aren't swallowed accidentally
            return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
        }
    }
    return CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
}

char KeyCodeToChar(Keys key)
{
    // Fix: Maps the physical hardware key range cleanly to lowercase characters used in the tree mapping layout
    if (key >= Keys.A && key <= Keys.Z) return (char)('a' + (key - Keys.A));
    if (key >= Keys.D0 && key <= Keys.D9) return (char)('0' + (key - Keys.D0));
    return '\0';
}

string GetActiveProcessName()
{
    IntPtr hwnd = GetForegroundWindow();
    _ = GetWindowThreadProcessId(hwnd, out uint pid);
    try
    {
        using Process proc = Process.GetProcessById((int)pid);
        return proc.ProcessName;
    }
    catch { return ""; }
}

void ExecuteKeyboardAction(KeyboardAction action)
{
    int keyCount = action.VirtualKeys.Count;
    UIntPtr customSignature = new(0x1337);

    // Resolve the layout of the window that will receive the injected input. Chromium
    // derives KeyboardEvent.code from the scan code, so it must match the target layout.
    IntPtr foregroundWindow = GetForegroundWindow();
    uint foregroundThreadId = GetWindowThreadProcessId(foregroundWindow, out _);
    IntPtr keyboardLayout = GetKeyboardLayout(foregroundThreadId);

    // Track modifiers that are currently held down physically so we can lift them
    bool ctrlHeld = (GetKeyState(0x11) & 0x8000) != 0;
    bool shiftHeld = (GetKeyState(0x10) & 0x8000) != 0;
    bool altHeld = (GetKeyState(0x12) & 0x8000) != 0;

    List<INPUT> inputList = [];

    // Step A: Temporarily release physical modifiers so they don't corrupt the macro output
    if (ctrlHeld) inputList.Add(BuildKeyInput(0x11, true, customSignature, keyboardLayout));
    if (shiftHeld) inputList.Add(BuildKeyInput(0x10, true, customSignature, keyboardLayout));
    if (altHeld) inputList.Add(BuildKeyInput(0x12, true, customSignature, keyboardLayout));

    // Step B: Inject Macro Key Press Events (Down)
    for (int i = 0; i < keyCount; i++)
    {
        inputList.Add(BuildKeyInput(action.VirtualKeys[i], false, customSignature, keyboardLayout));
    }

    // Step C: Inject Macro Key Release Events (Up, in reverse order)
    for (int i = keyCount - 1; i >= 0; i--)
    {
        inputList.Add(BuildKeyInput(action.VirtualKeys[i], true, customSignature, keyboardLayout));
    }

    // Step D: Restore the modifiers back to their physical states
    if (ctrlHeld) inputList.Add(BuildKeyInput(0x11, false, customSignature, keyboardLayout));
    if (shiftHeld) inputList.Add(BuildKeyInput(0x10, false, customSignature, keyboardLayout));
    if (altHeld) inputList.Add(BuildKeyInput(0x12, false, customSignature, keyboardLayout));

    INPUT[] inputs = [.. inputList];
    uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());

    if (sent == 0)
    {
        Console.WriteLine($"[Warning] SendInput failed. Win32 Error Code: {Marshal.GetLastWin32Error()}");
    }
}

INPUT BuildKeyInput(ushort vk, bool keyUp, UIntPtr signature, IntPtr keyboardLayout)
{
    // Scan-code injection is required for Chromium/Electron apps: they derive
    // KeyboardEvent.code from the scan code, not from the virtual-key code.
    uint scanCode = MapVirtualKeyEx(vk, MAPVK_VK_TO_VSC, keyboardLayout);

    if (scanCode != 0)
    {
        uint flags = KEYEVENTF_SCANCODE;
        if (keyUp) flags |= KEYEVENTF_KEYUP;
        if (IsExtendedKey(vk)) flags |= KEYEVENTF_EXTENDEDKEY;

        return new INPUT
        {
            Type = 1,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = 0,
                    wScan = (ushort)scanCode,
                    dwFlags = flags,
                    dwExtraInfo = signature
                }
            }
        };
    }

    // Fallback for keys the current layout cannot translate to a scan code
    return new INPUT
    {
        Type = 1,
        U = new InputUnion
        {
            ki = new KEYBDINPUT
            {
                wVk = vk,
                wScan = 0,
                dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                dwExtraInfo = signature
            }
        }
    };
}

bool IsExtendedKey(ushort vk) => vk switch
{
    0x21 or 0x22 or 0x23 or 0x24 or 0x25 or 0x26 or 0x27 or 0x28 => true, // PageUp/PageDown/End/Home/Arrows
    0x2C or 0x2D or 0x2E => true,                                           // PrintScreen/Insert/Delete
    0x5B or 0x5C or 0x5D => true,                                           // LeftWin/RightWin/Apps
    0x6F => true,                                                           // Numpad Divide
    0x90 => true,                                                           // NumLock
    0xA3 or 0xA5 => true,                                                   // RightCtrl/RightAlt
    _ => false
};

// --- WIN32 SYSTEM INTEGRATIONS INTEROP ---
[DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
[DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint idThread);
[DllImport("user32.dll", EntryPoint = "MapVirtualKeyExW")] static extern uint MapVirtualKeyEx(uint uCode, uint uMapType, IntPtr dwhkl);
[DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
[DllImport("user32.dll", SetLastError = true)][return: MarshalAs(UnmanagedType.Bool)] static extern bool UnhookWindowsHookEx(IntPtr hhk);
[DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
[DllImport("kernel32.dll", CharSet = CharSet.Auto)] static extern IntPtr GetModuleHandle(string? lpModuleName);
[DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
[DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern IntPtr GetWindowLong(IntPtr hWnd, int nIndex);
[DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern IntPtr SetWindowLong(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
[DllImport("user32.dll")] static extern short GetKeyState(int nVirtKey);

delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
public class KeyboardAction
{
    public List<ushort> VirtualKeys { get; set; } = [];
    public string Description { get; set; } = "";
    public KeyboardAction(params ushort[] keys) => VirtualKeys.AddRange(keys);
}
public class KeybindingNode
{
    public Dictionary<char, KeybindingNode> Children { get; set; } = [];
    public KeyboardAction? Action { get; set; }
    public void AddSequence(string seq, KeyboardAction act)
    {
        var cur = this;
        foreach (char c in seq)
        {
            if (!cur.Children.ContainsKey(c)) cur.Children[c] = new KeybindingNode();
            cur = cur.Children[c];
        }
        cur.Action = act;
    }
}
[StructLayout(LayoutKind.Sequential)]
struct KBDLLHOOKSTRUCT
{
    public uint vkCode;
    public uint scanCode;
    public uint flags;
    public uint time;
    public UIntPtr dwExtraInfo;
}

[StructLayout(LayoutKind.Sequential)]
struct INPUT
{
    public uint Type;
    public InputUnion U;
}

[StructLayout(LayoutKind.Explicit)]
struct InputUnion
{
    [FieldOffset(0)] public KEYBDINPUT ki;
    [FieldOffset(0)] public HARDWAREINPUT hi; // Ensures proper padding alignment on x64
    [FieldOffset(0)] public MOUSEINPUT mi;
}

[StructLayout(LayoutKind.Sequential)]
struct KEYBDINPUT
{
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
}

// Dummy alignment structures to satisfy the Win32 layout subsystem
[StructLayout(LayoutKind.Sequential)]
struct MOUSEINPUT
{
    public int dx;
    public int dy;
    public uint mouseData;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
}

[StructLayout(LayoutKind.Sequential)]
struct HARDWAREINPUT
{
    public uint uMsg;
    public ushort wParamL;
    public ushort wParamH;
}

public sealed record WhichKeyEntry(string Key, string Description, bool IsGroup);

public sealed class WhichKeyPanel : Panel
{
    private const int PaddingSize = 14;
    private const int KeyGap = 14;
    private const int DescriptionGap = 10;
    private const int HeaderGap = 8;
    private const int RowGap = 4;

    private readonly Font headerFont = new("Consolas", 11.5f, FontStyle.Bold);
    private readonly Font keyFont = new("Consolas", 11f, FontStyle.Bold);
    private readonly Font descriptionFont = new("Consolas", 11f, FontStyle.Regular);
    private Size cachedPreferredSize = Size.Empty;

    public string Header { get; private set; } = "[NORMAL]";
    public List<WhichKeyEntry> Entries { get; private set; } = [];
    private int MaxPanelWidth { get; set; } = 1000;

    public WhichKeyPanel()
    {
        DoubleBuffered = true;
        BackColor = Color.FromArgb(22, 22, 22);
        ForeColor = Color.FromArgb(201, 209, 217);
    }

    public void SetMaxPanelWidth(int width)
    {
        MaxPanelWidth = width;
        cachedPreferredSize = Size.Empty;
    }

    public void SetContent(string header, List<WhichKeyEntry> entries)
    {
        Header = header;
        Entries = entries;
        cachedPreferredSize = Size.Empty;
        Invalidate();
    }

    public override Size GetPreferredSize(Size proposedSize)
    {
        if (cachedPreferredSize == Size.Empty)
        {
            cachedPreferredSize = CalculateLayout(out _, out _, out _, out _, out _);
        }

        return cachedPreferredSize;
    }

    private Size CalculateLayout(out int columns, out int rows, out int keyWidth, out int descriptionWidth, out int lineHeight)
    {
        Size headerSize = TextRenderer.MeasureText(Header, headerFont);
        lineHeight = Math.Max(TextRenderer.MeasureText("Ag", keyFont).Height, 18) + RowGap;

        columns = 1;
        rows = Math.Max(1, Entries.Count);
        keyWidth = 0;
        descriptionWidth = 0;

        if (Entries.Count == 0)
        {
            return new Size(PaddingSize * 2 + headerSize.Width, PaddingSize * 2 + headerSize.Height);
        }

        keyWidth = Entries.Max(entry => TextRenderer.MeasureText(GetKeyText(entry), keyFont).Width) + KeyGap;

        int maxDescriptionWidth = Math.Max(80, MaxPanelWidth - PaddingSize * 2 - keyWidth);
        int measuredDescriptionWidth = Entries.Max(entry => TextRenderer.MeasureText(entry.Description, descriptionFont).Width) + DescriptionGap;
        descriptionWidth = Math.Min(measuredDescriptionWidth, maxDescriptionWidth);

        int columnWidth = keyWidth + descriptionWidth;
        int availableWidth = Math.Max(columnWidth, MaxPanelWidth - PaddingSize * 2);
        columns = Math.Clamp(availableWidth / columnWidth, 1, Entries.Count);
        rows = (Entries.Count + columns - 1) / columns;

        int width = PaddingSize * 2 + columns * columnWidth;
        int height = PaddingSize * 2 + headerSize.Height + HeaderGap + rows * lineHeight;

        return new Size(width, height);
    }

    private static string GetKeyText(WhichKeyEntry entry) => entry.IsGroup ? $"{entry.Key} +" : entry.Key;

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        Graphics g = e.Graphics;
        g.Clear(BackColor);

        using (Pen border = new(Color.FromArgb(58, 58, 58)))
        {
            g.DrawRectangle(border, 0, 0, Width - 1, Height - 1);
        }

        TextRenderer.DrawText(
            g, Header, headerFont,
            new Point(PaddingSize, PaddingSize),
            Color.Lime,
            TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);

        Size headerSize = TextRenderer.MeasureText(Header, headerFont);
        CalculateLayout(out _, out int rows, out int keyWidth, out int descriptionWidth, out int lineHeight);

        int startY = PaddingSize + headerSize.Height + HeaderGap;
        int columnWidth = keyWidth + descriptionWidth;

        const TextFormatFlags entryFlags =
            TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine |
            TextFormatFlags.VerticalCenter | TextFormatFlags.Left;

        for (int i = 0; i < Entries.Count; i++)
        {
            WhichKeyEntry entry = Entries[i];
            int column = i / rows;
            int row = i % rows;
            int x = PaddingSize + column * columnWidth;
            int y = startY + row * lineHeight;

            Color keyColor = entry.IsGroup
                ? Color.FromArgb(240, 180, 41)
                : Color.FromArgb(126, 231, 135);

            TextRenderer.DrawText(
                g, GetKeyText(entry), keyFont,
                new Rectangle(x, y, keyWidth, lineHeight),
                keyColor, entryFlags);

            if (entry.Description.Length > 0)
            {
                TextRenderer.DrawText(
                    g, entry.Description, descriptionFont,
                    new Rectangle(x + keyWidth, y, descriptionWidth, lineHeight),
                    ForeColor,
                    entryFlags | TextFormatFlags.EndEllipsis);
            }
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            headerFont.Dispose();
            keyFont.Dispose();
            descriptionFont.Dispose();
        }

        base.Dispose(disposing);
    }
}

public sealed class OverlayForm : Form
{
    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams createParams = base.CreateParams;
            createParams.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            return createParams;
        }
    }
}
