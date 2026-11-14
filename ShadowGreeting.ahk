#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================
;  EDIT ME  -  the display name
;  This is the ONLY place the name is written in this script. Every
;  greeting, the tray menu label and the tray tooltip read it from here
;  (greeting lines use the {name} placeholder).
;  Change the value below, then reload/restart the widget.
; =====================================================================
global UserName := "ZIA"

; ---- DPI: use physical pixels so layered-window coordinates are consistent ----
DllCall("SetProcessDPIAware")

; ===================== CONFIG (same look/feel as Shadow Clock) =====================

global W := 600
global H := 248
global BottomMargin := 120     ; ~half an inch higher again (about 1 inch off the bottom)

; Single soft fade applied to every element (text, outline, icon, divider).
; Shadow Clock uses per-element alpha; this multiplies those alphas by one value.
global FadeAll := 0.87

; fonts
global GreetingFont  := "Arial"
global GreetingStyle := 1      ; GDI+ FontStyleBold
global WeatherFont   := "Steelfish Rg"
global QuoteFont     := "Steelfish Rg"

; sizes in POINTS (GDI+ unit Point matches Rainmeter)
global GreetingSize := 84      ; auto-shrinks to the largest size that fits
global TempSize     := 42
global CondSize     := 22
global FeelsSize    := 15
global QuoteSize    := 25
global AuthorSize   := 17

; element positions (pixels) - compact vertical layout
global GreetingY   := 2
; greeting glyph height target (px) and where its top edge should sit
; (uppercase has no descenders, so the target is slightly larger to keep ~96 px of caps)
global GreetingTargetH := 104
global GreetingTop     := 8
global WeatherY    := 100
global WeatherRowH := 64
global DividerY    := 168
global QuoteY      := 176

; ---- greetings: time-of-day pools plus anytime (prayer / blessing) lines ----
; {name} is replaced with the user's name, the whole line is uppercased.
global GreetingPools    := Map()
global GreetingText     := ""     ; time-of-day greeting currently showing
global GreetingLastPick := ""     ; avoids repeating the same line twice in a row
global GreetingAlt      := ""     ; temporary line shown after a click
global GreetingClickSecs := 5     ; seconds the click greeting stays up
global GreetingRotateMs  := 10 * 60 * 1000
global GreetingHitBottom := 108   ; y of the clickable greeting band

; Weather line: click cycles through these attributes, then falls back to the
; first one (temperature) a few seconds after the last click.
global WeatherAttrKeys  := ["temp", "location", "precip", "uv", "wind", "humidity", "feels", "gust", "pressure", "cloud", "visibility"]
global WeatherAttrIndex := 1      ; 1 = temperature (default view)
global WeatherClickSecs := 5      ; idle seconds before reverting to temperature
global WeatherHitTop    := 109    ; clickable weather band (below the greeting)
global WeatherHitBottom := 167    ; down to the divider

; alpha (255=solid, lower=more transparent) - same per-element scheme as the clock
; (FadeAll below multiplies each value by 0.87, so the stored number is ~15% higher
;  than what you see; the trailing comment is the visible opacity)
global GreetingAlpha := 117    ; ~40%
global WeatherAlpha  := 132    ; ~45%  big value
global CondAlpha     := 117    ; ~40%  attribute label
global FeelsAlpha    := 88     ; ~30%  detail line
global QuoteAlpha    := 102    ; ~35%
global AuthorAlpha   := 102    ; ~35%

; red text outline, identical to Shadow Clock
global UseBorder    := true
global BorderColor  := 0xE53935
global BorderAlpha  := 150
global BorderWidth  := 1.5

; thin divider between weather and quote
global DividerColor := 0xFF5A5A
global DividerAlpha := 55
global DividerInset := 130

; weather row spacing
global IconSize    := 64
global IconGap     := 14
global InfoGap     := 18

; ---- temperature settings (tray menu) ----
global TempUnit      := "C"     ; "C" or "F"
global ShowFeelsLike := true

; ---- quote settings (tray menu) ----
global ShowQuote       := true
global ShowQuoteAuthor := true
global QuoteIntervalSec := 15 * 60   ; auto quote change: 15 minutes
global QuoteMaxLen     := 60

; ---- live weather settings ----
global WeatherRefreshMs := 10 * 60 * 1000
global LocationLat := ""
global LocationLon := ""
global LocationCity := ""
global LocationMenuLabel := "Auto"

; chosen location (and auto/manual mode) survives restarts and reboots
global SettingsDir  := A_AppData "\ShadowGreeting"
global SettingsFile := SettingsDir "\settings.ini"

; window position + drag lock (also saved in the same INI, section [Window])
global Draggable := true

; GDI+ default StringFormat pads each string by ~9.4px per side
global PAD := 9.4
; ====================================================================================

; ===================== FALLBACK QUOTES =====================
; Used only if the quote API is unreachable; the live API replaces this list.
global FallbackQuotes := [
    Map("text", "The only way to do great work is to love what you do.", "author", "Steve Jobs"),
    Map("text", "Simplicity is the ultimate sophistication.",            "author", "Leonardo da Vinci"),
    Map("text", "Stay hungry, stay foolish.",                            "author", "Steve Jobs"),
    Map("text", "What we think, we become.",                             "author", "Buddha"),
    Map("text", "Well done is better than well said.",                   "author", "Benjamin Franklin"),
    Map("text", "The best way out is always through.",                   "author", "Robert Frost"),
    Map("text", "Dream big and dare to fail.",                           "author", "Norman Vaughan"),
    Map("text", "Everything you can imagine is real.",                   "author", "Pablo Picasso"),
    Map("text", "Turn your wounds into wisdom.",                         "author", "Oprah Winfrey"),
    Map("text", "Be yourself; everyone else is already taken.",          "author", "Oscar Wilde"),
    Map("text", "Action is the foundational key to all success.",        "author", "Pablo Picasso"),
    Map("text", "The journey of a thousand miles begins with one step.", "author", "Lao Tzu")
]
; ===========================================================

global Quotes := FallbackQuotes
global QuoteIndex := 1
global Weather := Map("condition", "Loading", "tempC", "", "feelsC", "",
    "precipMm", "", "precipProb", "", "uv", "", "windKph", "", "windDeg", "",
    "gustKph", "", "humidity", "", "pressureHpa", "", "cloudPct", "",
    "visibilityKm", "", "dewC", "")
global WeatherLive := false

; ---- bottom-center placement inside the taskbar-free work area ----
screenW := DllCall("GetSystemMetrics", "int", 0)
screenH := DllCall("GetSystemMetrics", "int", 1)
work := Buffer(16, 0)
DllCall("SystemParametersInfoW", "uint", 0x0030, "uint", 0, "ptr", work, "uint", 0)
workX := NumGet(work, 0, "int")
workY := NumGet(work, 4, "int")
workW := NumGet(work, 8, "int") - workX
workH := NumGet(work, 12, "int") - workY
if (workW <= 0 || workH <= 0) {
    workX := 0
    workY := 0
    workW := screenW
    workH := screenH
}
PosX := workX + (workW - W) // 2
PosY := workY + workH - H - BottomMargin

; ---- GDI+ startup (Buffer out-params: this AHK build drops "*" write-backs) ----
; Retry until GDI+ initializes successfully (it can transiently fail at login/boot).
loop {
    tokBuf := Buffer(A_PtrSize, 0)
    si := Buffer(16, 0)
    NumPut("uint", 1, si, 0)
    gdipRet := DllCall("gdiplus\GdiplusStartup", "ptr", tokBuf, "ptr", si, "ptr", 0)
    if gdipRet == 0
        break
    Sleep(1000)
}

; ---- layered, non-topmost window ----
WS_EX_LAYERED := 0x80000
WS_EX_TOOLWINDOW := 0x80
WS_EX_NOACTIVATE := 0x08000000
WS_POPUP := 0x80000000
WS_VISIBLE := 0x10000000

hWnd := DllCall("CreateWindowExW"
    , "uint", WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
    , "str", "Static"
    , "str", "ShadowGreeting"
    , "uint", WS_POPUP | WS_VISIBLE
    , "int", PosX, "int", PosY, "int", W, "int", H
    , "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0)

; The default "Static" window proc answers WM_NCHITTEST with HTTRANSPARENT, so
; every click fell through to the desktop. Report HTCLIENT instead so the whole
; widget can be clicked and dragged.
global WndProcCallback := CallbackCreate(ShadowWndProc, "Fast", 4)
global OldWndProc := DllCall("SetWindowLongPtrW", "ptr", hWnd, "int", -4, "ptr", WndProcCallback, "ptr")

; restore the last dragged position and the drag lock before anything is drawn
LoadWindowSettings()

ShadowWndProc(h, m, w, l) {
    global OldWndProc
    if (m = 0x0084)                     ; WM_NCHITTEST
        return 1                        ; HTCLIENT
    return DllCall("CallWindowProcW", "ptr", OldWndProc, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
}

; ---- dragging (manual: HTCAPTION drag doesn't work with WS_EX_NOACTIVATE) ----
; A press on the greeting band that never turns into a drag counts as a click.
global dragging := false
global dragDX := 0, dragDY := 0
global dragMoved := false
global downX := 0, downY := 0
global downOnGreeting := false
global downOnWeather := false
OnMessage(0x0201, WM_LBUTTONDOWN)
OnMessage(0x0200, WM_MOUSEMOVE)
OnMessage(0x0202, WM_LBUTTONUP)

WM_LBUTTONDOWN(wParam, lParam, msg, h) {
    global dragging, dragDX, dragDY, hWnd, dragMoved, downX, downY, downOnGreeting, downOnWeather
    global GreetingHitBottom, WeatherHitTop, WeatherHitBottom, Draggable
    if (h != hWnd)
        return
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    mx := NumGet(pt, 0, "int")
    my := NumGet(pt, 4, "int")
    wr := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", hWnd, "ptr", wr)
    wl := NumGet(wr, 0, "int")
    wt := NumGet(wr, 4, "int")
    dragDX := mx - wl
    dragDY := my - wt
    downX := mx
    downY := my
    dragMoved := false
    yRel := my - wt
    downOnGreeting := (yRel <= GreetingHitBottom)
    downOnWeather := (yRel >= WeatherHitTop && yRel <= WeatherHitBottom)
    ; when the drag lock is on, presses still count as clicks but never move it
    dragging := Draggable
    if (Draggable)
        DllCall("SetCapture", "ptr", hWnd)
}
WM_MOUSEMOVE(wParam, lParam, msg, h) {
    global dragging, dragDX, dragDY, hWnd, dragMoved, downX, downY
    if (h != hWnd || !dragging)
        return
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    mx := NumGet(pt, 0, "int")
    my := NumGet(pt, 4, "int")
    if (!dragMoved) {
        ; stay put until the pointer really moves, so a click doesn't nudge the widget
        if (Abs(mx - downX) <= 4 && Abs(my - downY) <= 4)
            return
        dragMoved := true
    }
    DllCall("SetWindowPos", "ptr", hWnd, "ptr", 0, "int", mx - dragDX, "int", my - dragDY, "int", 0, "int", 0, "uint", 0x0004)
}
WM_LBUTTONUP(wParam, lParam, msg, h) {
    global dragging, dragMoved, downOnGreeting, downOnWeather, hWnd
    if (h != hWnd)
        return
    dragged := dragging && dragMoved
    dragging := false
    DllCall("ReleaseCapture")
    if (dragged)
        SaveWindowSettings()
    else if (!dragMoved && downOnGreeting)
        ShowGreetingAlt()
    else if (!dragMoved && downOnWeather)
        WeatherAttrNext()
}

; ---- tray menu ----
A_TrayMenu.Delete()
A_TrayMenu.Add("Set Name (" UserName ")", SetName)
A_TrayMenu.Add("Set Location (" LocationMenuLabel ")", SetLocation)
A_TrayMenu.Add("Refresh Weather Now", RefreshWeather)
A_TrayMenu.Add("New Greeting", RollGreeting)
A_TrayMenu.Add("Draggable (" (Draggable ? "On" : "Off") ")", ToggleDraggable)
A_TrayMenu.Add()
A_TrayMenu.Add("Temperature Unit (" Chr(176) TempUnit ")", ToggleUnit)
A_TrayMenu.Add("Show Feels Like (" (ShowFeelsLike ? "On" : "Off") ")", ToggleFeelsLike)
A_TrayMenu.Add()
A_TrayMenu.Add("Quotes (" (ShowQuote ? "On" : "Off") ")", ToggleQuotes)
A_TrayMenu.Add("Show Quote Author (" (ShowQuoteAuthor ? "On" : "Off") ")", ToggleAuthor)
A_TrayMenu.Add("New Quote", NewQuote)
A_TrayMenu.Add("Refresh Quotes", LoadQuotes)
A_TrayMenu.Add()
A_TrayMenu.Add("Toggle Border (" (UseBorder ? "On" : "Off") ")", ToggleBorder)
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_IconTip := "Shadow Greeting"

; ---- helpers ----
; Vertical-only stretch for the greeting: taller glyphs, same width.
; k scales Y, shift moves the result up/down in pixels (applied before scaling).
ApplyGreetingStretch(g, k, shift) {
    bMat := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateMatrix", "ptr", bMat)
    pMat := NumGet(bMat, 0, "ptr")
    DllCall("gdiplus\GdipScaleMatrix", "ptr", pMat, "float", 1.0, "float", k, "int", 0)
    DllCall("gdiplus\GdipTranslateMatrix", "ptr", pMat, "float", 0, "float", shift, "int", 0)
    DllCall("gdiplus\GdipSetWorldTransform", "ptr", g, "ptr", pMat)
    DllCall("gdiplus\GdipDeleteMatrix", "ptr", pMat)
}

ColorARGB(alpha, rgb) {
    global FadeAll
    a := Round(alpha * FadeAll)
    if (a < 0)
        a := 0
    if (a > 255)
        a := 255
    return ((a & 0xFF) << 24) | (rgb & 0xFFFFFF)
}

GetFont(family, size, style := 0) {
    static cache := Map()
    key := family "|" size "|" style
    if cache.Has(key)
        return cache[key]
    bFam := Buffer(A_PtrSize, 0)
    if DllCall("gdiplus\GdipCreateFontFamilyFromName", "str", family, "ptr", 0, "ptr", bFam) != 0
        DllCall("gdiplus\GdipGetGenericFontFamilySansSerif", "ptr", bFam)
    pFamily := NumGet(bFam, 0, "ptr")
    bFont := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateFont", "ptr", pFamily, "float", size, "int", style, "int", 3, "ptr", bFont)
    pFont := NumGet(bFont, 0, "ptr")
    DllCall("gdiplus\GdipDeleteFontFamily", "ptr", pFamily)
    cache[key] := pFont
    return pFont
}

BuildTextPath(g, famName, emSizePt, text, rect, fmt, style := 0) {
    bDpi := Buffer(4, 0)
    DllCall("gdiplus\GdipGetDpiX", "ptr", g, "ptr", bDpi)
    dpi := NumGet(bDpi, 0, "float")
    emSize := emSizePt * dpi / 72
    bFam := Buffer(A_PtrSize, 0)
    if DllCall("gdiplus\GdipCreateFontFamilyFromName", "str", famName, "ptr", 0, "ptr", bFam) != 0
        DllCall("gdiplus\GdipGetGenericFontFamilySansSerif", "ptr", bFam)
    pFamily := NumGet(bFam, 0, "ptr")
    bPath := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr", bPath)
    pPath := NumGet(bPath, 0, "ptr")
    DllCall("gdiplus\GdipAddPathString", "ptr", pPath, "str", text, "int", -1, "ptr", pFamily, "int", style, "float", emSize, "ptr", rect, "ptr", fmt)
    DllCall("gdiplus\GdipDeleteFontFamily", "ptr", pFamily)
    return pPath
}

OutlineTextAt(g, famName, emSizePt, text, rect, fmt, color, fillAlpha, fillColor, style := 0) {
    global BorderAlpha, BorderWidth
    ; stroke AND fill the SAME path so the red outline and the text itself are
    ; pixel-aligned (text via GdipDrawString is grid-fitted and shifts a few px).
    pPath := BuildTextPath(g, famName, emSizePt, text, rect, fmt, style)
    bPen := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreatePen1", "uint", ColorARGB(BorderAlpha, color), "float", BorderWidth, "int", 2, "ptr", bPen)
    pPen := NumGet(bPen, 0, "ptr")
    DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pPen, "ptr", pPath)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
    bBrush := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", ColorARGB(fillAlpha, fillColor), "ptr", bBrush)
    pBrush := NumGet(bBrush, 0, "ptr")
    DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", pBrush, "ptr", pPath)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
}

DrawTextCentered(g, pFont, text, y, alpha, offsetX := 0, offsetY := 0, alignX := 1, famName := "", emSize := 0, outlineColor := 0, fillColor := 0xFFFFFF, style := 0) {
    global W, H
    bFmt := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr", bFmt)
    fmt := NumGet(bFmt, 0, "ptr")
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", alignX)   ; 0=Near,1=Center,2=Far
    rect := Buffer(16, 0)
    NumPut("float", offsetX, rect, 0)
    NumPut("float", y + offsetY, rect, 4)
    NumPut("float", W, rect, 8)
    NumPut("float", H - (y + offsetY), rect, 12)
    if (outlineColor && famName != "") {
        OutlineTextAt(g, famName, emSize, text, rect, fmt, outlineColor, alpha, fillColor, style)
    } else {
        bBrush := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdipCreateSolidFill", "uint", ColorARGB(alpha, fillColor), "ptr", bBrush)
        pBrush := NumGet(bBrush, 0, "ptr")
        DllCall("gdiplus\GdipDrawString", "ptr", g, "str", text, "int", -1, "ptr", pFont, "ptr", rect, "ptr", fmt, "ptr", pBrush)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    }
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
}

DrawStringRect(g, pFont, text, x, y, w, h, alpha, color, align := 0, outlineColor := 0, famName := "", emSize := 0, style := 0) {
    bFmt := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr", bFmt)
    fmt := NumGet(bFmt, 0, "ptr")
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", align)
    rect := Buffer(16, 0)
    NumPut("float", x, rect, 0)
    NumPut("float", y, rect, 4)
    NumPut("float", w, rect, 8)
    NumPut("float", h, rect, 12)
    if (outlineColor && famName != "") {
        OutlineTextAt(g, famName, emSize, text, rect, fmt, outlineColor, alpha, color, style)
    } else {
        bBrush := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdipCreateSolidFill", "uint", ColorARGB(alpha, color), "ptr", bBrush)
        pBrush := NumGet(bBrush, 0, "ptr")
        DllCall("gdiplus\GdipDrawString", "ptr", g, "str", text, "int", -1, "ptr", pFont, "ptr", rect, "ptr", fmt, "ptr", pBrush)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    }
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
}

MeasureString(g, pFont, text) {
    bFmt := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr", bFmt)
    fmt := NumGet(bFmt, 0, "ptr")
    layout := Buffer(16, 0)
    NumPut("float", 0, layout, 0)
    NumPut("float", 0, layout, 4)
    NumPut("float", 10000, layout, 8)
    NumPut("float", 10000, layout, 12)
    box := Buffer(16, 0)
    DllCall("gdiplus\GdipMeasureString", "ptr", g, "str", text, "int", -1, "ptr", pFont, "ptr", layout, "ptr", fmt, "ptr", box, "ptr", 0, "ptr", 0)
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
    return [NumGet(box, 8, "float"), NumGet(box, 4, "float")]   ; [width, top]
}

FitSize(g, famName, text, startSize, maxWidth, style := 0) {
    global PAD
    size := startSize
    while (size > 10) {
        f := GetFont(famName, size, style)
        if (MeasureString(g, f, text)[1] - 2 * PAD <= maxWidth)
            break
        size -= 2
    }
    return size
}

GetWrappedLines(g, pFont, text, maxWidth) {
    global PAD
    words := StrSplit(text, " ")
    lines := []
    cur := ""
    for , word in words {
        if (word = "")
            continue
        candidate := (cur = "") ? word : cur " " word
        if (MeasureString(g, pFont, candidate)[1] - 2 * PAD <= maxWidth) {
            cur := candidate
        } else {
            if (cur != "")
                lines.Push(cur)
            cur := word
        }
    }
    if (cur != "")
        lines.Push(cur)
    return lines
}

DrawLineAt(g, x1, y1, x2, y2, alpha, rgb, width) {
    bPen := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreatePen1", "uint", ColorARGB(alpha, rgb), "float", width, "int", 2, "ptr", bPen)
    pPen := NumGet(bPen, 0, "ptr")
    DllCall("gdiplus\GdipDrawLine", "ptr", g, "ptr", pPen, "float", x1, "float", y1, "float", x2, "float", y2)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
}

; ---- weather icon primitives (coordinates are normalized to a 64x64 box) ----
IconEllipse(g, ox, oy, s, nx, ny, nw, nh, alpha, rgb) {
    bBrush := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", ColorARGB(alpha, rgb), "ptr", bBrush)
    pBrush := NumGet(bBrush, 0, "ptr")
    DllCall("gdiplus\GdipFillEllipse", "ptr", g, "ptr", pBrush
        , "float", ox + nx * s, "float", oy + ny * s
        , "float", nw * s, "float", nh * s)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
}

IconLine(g, ox, oy, s, x1, y1, x2, y2, alpha, rgb, width) {
    DrawLineAt(g, ox + x1 * s, oy + y1 * s, ox + x2 * s, oy + y2 * s, alpha, rgb, width)
}

DrawSunIcon(g, ox, oy, s, cx, cy, r) {
    IconEllipse(g, ox, oy, s, cx - r, cy - r, r * 2, r * 2, 245, 0xFFC857)
    loop 8 {
        ang := A_Index * 3.141592653589793 / 4
        x1 := cx + Cos(ang) * (r + 4)
        y1 := cy + Sin(ang) * (r + 4)
        x2 := cx + Cos(ang) * (r + 9)
        y2 := cy + Sin(ang) * (r + 9)
        IconLine(g, ox, oy, s, x1, y1, x2, y2, 210, 0xFFC857, 2.2)
    }
}

DrawCloudIconAt(g, ox, oy, s, dx, dy, alpha, rgb) {
    ; overlapping ellipses make a flat-bottomed cloud silhouette
    IconEllipse(g, ox, oy, s, dx + 10, dy + 34, 46, 16, alpha, rgb)
    IconEllipse(g, ox, oy, s, dx + 14, dy + 28, 20, 20, alpha, rgb)
    IconEllipse(g, ox, oy, s, dx + 24, dy + 21, 24, 24, alpha, rgb)
    IconEllipse(g, ox, oy, s, dx + 38, dy + 29, 18, 18, alpha, rgb)
}

IconRing(g, ox, oy, s, nx, ny, nw, nh, alpha, rgb, width) {
    bPen := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreatePen1", "uint", ColorARGB(alpha, rgb), "float", width * s, "int", 2, "ptr", bPen)
    pPen := NumGet(bPen, 0, "ptr")
    DllCall("gdiplus\GdipDrawEllipse", "ptr", g, "ptr", pPen
        , "float", ox + nx * s, "float", oy + ny * s, "float", nw * s, "float", nh * s)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
}

IconPolygon(g, ox, oy, s, pts, alpha, rgb) {
    n := pts.Length // 2
    buf := Buffer(n * 8, 0)
    loop n {
        NumPut("float", ox + pts[2 * A_Index - 1] * s, buf, (A_Index - 1) * 8)
        NumPut("float", oy + pts[2 * A_Index] * s, buf, (A_Index - 1) * 8 + 4)
    }
    bBrush := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", ColorARGB(alpha, rgb), "ptr", bBrush)
    pBrush := NumGet(bBrush, 0, "ptr")
    DllCall("gdiplus\GdipFillPolygon", "ptr", g, "ptr", pBrush, "ptr", buf, "int", n, "int", 0)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
}

DrawDropIcon(g, ox, oy, s, alpha, rgb) {
    IconPolygon(g, ox, oy, s, [32, 8, 21, 33, 43, 33], alpha, rgb)
    IconEllipse(g, ox, oy, s, 21, 24, 22, 22, alpha, rgb)
}

DrawThermometerIcon(g, ox, oy, s) {
    IconLine(g, ox, oy, s, 32, 12, 32, 40, 235, 0xE9EDF5, 5.0)
    IconEllipse(g, ox, oy, s, 22, 34, 20, 20, 245, 0xFF6B6B)
}

DrawWindIcon(g, ox, oy, s, alpha) {
    IconLine(g, ox, oy, s, 10, 22, 44, 22, alpha, 0xE9EDF5, 3.0)
    IconLine(g, ox, oy, s, 44, 22, 49, 17, alpha, 0xE9EDF5, 2.0)
    IconLine(g, ox, oy, s, 16, 32, 54, 32, alpha - 20, 0xE9EDF5, 3.0)
    IconLine(g, ox, oy, s, 54, 32, 58, 27, alpha - 20, 0xE9EDF5, 2.0)
    IconLine(g, ox, oy, s, 10, 42, 38, 42, alpha - 40, 0xE9EDF5, 3.0)
}

DrawGaugeIcon(g, ox, oy, s) {
    IconRing(g, ox, oy, s, 8, 8, 48, 48, 230, 0xE9EDF5, 4.0)
    IconLine(g, ox, oy, s, 32, 32, 45, 18, 245, 0xFF6B6B, 3.0)
    IconEllipse(g, ox, oy, s, 28, 28, 8, 8, 245, 0xE9EDF5)
}

DrawEyeIcon(g, ox, oy, s) {
    IconRing(g, ox, oy, s, 6, 21, 52, 22, 230, 0xE9EDF5, 3.0)
    IconEllipse(g, ox, oy, s, 26, 26, 12, 12, 245, 0xE9EDF5)
    IconEllipse(g, ox, oy, s, 30, 30, 4, 4, 255, 0x1B1B1B)
}

DrawPinIcon(g, ox, oy, s) {
    ; map pin: tapered tail behind a round head, with a dark hole
    IconPolygon(g, ox, oy, s, [22, 26, 42, 26, 32, 57], 240, 0xFF6B6B)
    IconEllipse(g, ox, oy, s, 20, 6, 24, 24, 245, 0xFF6B6B)
    IconEllipse(g, ox, oy, s, 27, 13, 10, 10, 245, 0x1B1B1B)
}

; Icon follows the attribute being shown, so the logo always matches the value.
DrawAttrIcon(g, ox, oy, s, key, condition) {
    switch key {
        case "temp":
            DrawWeatherIcon(g, ox, oy, s, condition)
        case "location":
            DrawPinIcon(g, ox, oy, s)
        case "feels":
            DrawThermometerIcon(g, ox, oy, s)
        case "precip":
            DrawCloudIconAt(g, ox, oy, s, 0, -3, 240, 0xD7DDE8)
            DrawDropIcon(g, ox + 14 * s, oy + 26 * s, s * 0.55, 240, 0x6FB3FF)
            DrawDropIcon(g, ox + 30 * s, oy + 30 * s, s * 0.45, 210, 0x6FB3FF)
        case "uv":
            DrawSunIcon(g, ox, oy, s, 32, 32, 13)
        case "wind":
            DrawWindIcon(g, ox, oy, s, 240)
        case "gust":
            DrawWindIcon(g, ox, oy, s, 250)
        case "humidity":
            DrawDropIcon(g, ox, oy, s, 245, 0x6FB3FF)
        case "pressure":
            DrawGaugeIcon(g, ox, oy, s)
        case "cloud":
            DrawCloudIconAt(g, ox, oy, s, 0, 0, 240, 0xE9EDF5)
        case "visibility":
            DrawEyeIcon(g, ox, oy, s)
        default:
            DrawWeatherIcon(g, ox, oy, s, condition)
    }
}

DrawWeatherIcon(g, ox, oy, s, condition) {
    switch condition {
        case "Clear":
            DrawSunIcon(g, ox, oy, s, 32, 30, 12)
        case "Partly Cloudy":
            DrawSunIcon(g, ox, oy, s, 40, 21, 9)
            DrawCloudIconAt(g, ox, oy, s, 0, 0, 240, 0xE9EDF5)
        case "Cloudy":
            DrawCloudIconAt(g, ox, oy, s, -4, -7, 190, 0xC3CAD6)
            DrawCloudIconAt(g, ox, oy, s, 2, 3, 245, 0xE9EDF5)
        case "Rain":
            DrawCloudIconAt(g, ox, oy, s, 0, 0, 240, 0xD7DDE8)
            IconLine(g, ox, oy, s, 22, 53, 20, 61, 235, 0x6FB3FF, 3.0)
            IconLine(g, ox, oy, s, 32, 53, 30, 61, 235, 0x6FB3FF, 3.0)
            IconLine(g, ox, oy, s, 42, 53, 40, 61, 235, 0x6FB3FF, 3.0)
        case "Thunderstorm":
            DrawCloudIconAt(g, ox, oy, s, 0, -2, 245, 0x9AA5B8)
            IconLine(g, ox, oy, s, 36, 50, 30, 57, 255, 0xFFD43B, 3.5)
            IconLine(g, ox, oy, s, 30, 57, 35, 57, 255, 0xFFD43B, 3.5)
            IconLine(g, ox, oy, s, 35, 57, 29, 64, 255, 0xFFD43B, 3.5)
            IconLine(g, ox, oy, s, 20, 53, 18, 60, 210, 0x6FB3FF, 2.5)
            IconLine(g, ox, oy, s, 44, 53, 42, 60, 210, 0x6FB3FF, 2.5)
        case "Snow":
            DrawCloudIconAt(g, ox, oy, s, 0, 0, 240, 0xE9EDF5)
            IconEllipse(g, ox, oy, s, 20, 54, 4, 4, 245, 0xFFFFFF)
            IconEllipse(g, ox, oy, s, 30, 59, 4, 4, 245, 0xFFFFFF)
            IconEllipse(g, ox, oy, s, 40, 54, 4, 4, 245, 0xFFFFFF)
        case "Fog":
            IconLine(g, ox, oy, s, 12, 28, 52, 28, 210, 0xC8CDD6, 4.0)
            IconLine(g, ox, oy, s, 17, 39, 47, 39, 190, 0xC8CDD6, 4.0)
            IconLine(g, ox, oy, s, 12, 50, 44, 50, 210, 0xC8CDD6, 4.0)
        default:
            DrawCloudIconAt(g, ox, oy, s, 0, 0, 240, 0xE9EDF5)
    }
}

; ---- HTTP + minimal JSON parser ----
HttpGet(url) {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.Open("GET", url, false)
    whr.SetTimeouts(5000, 5000, 5000, 10000)
    whr.SetRequestHeader("User-Agent", "ShadowGreeting/1.0 (AutoHotkey)")
    whr.Send()
    if (whr.Status < 200 || whr.Status >= 300)
        throw Error("HTTP " whr.Status)
    return whr.ResponseText
}

JsonParse(text) {
    p := {t: text, i: 1}
    if (SubStr(p.t, 1, 1) = Chr(0xFEFF))
        p.i := 2
    return JsonReadValue(p)
}

JsonSkipWs(p) {
    while (p.i <= StrLen(p.t)) {
        ch := SubStr(p.t, p.i, 1)
        if (ch != " " && ch != "`t" && ch != "`r" && ch != "`n")
            break
        p.i++
    }
}

JsonReadValue(p) {
    JsonSkipWs(p)
    ch := SubStr(p.t, p.i, 1)
    if (ch = "{")
        return JsonReadObject(p)
    if (ch = "[")
        return JsonReadArray(p)
    if (ch = Chr(34))
        return JsonReadString(p)
    if (ch = "t") {
        p.i += 4
        return true
    }
    if (ch = "f") {
        p.i += 5
        return false
    }
    if (ch = "n") {
        p.i += 4
        return ""
    }
    return JsonReadNumber(p)
}

JsonReadObject(p) {
    obj := Map()
    p.i++
    JsonSkipWs(p)
    if (SubStr(p.t, p.i, 1) = "}") {
        p.i++
        return obj
    }
    loop {
        JsonSkipWs(p)
        key := JsonReadString(p)
        JsonSkipWs(p)
        if (SubStr(p.t, p.i, 1) = ":")
            p.i++
        JsonSkipWs(p)
        obj[key] := JsonReadValue(p)
        JsonSkipWs(p)
        ch := SubStr(p.t, p.i, 1)
        p.i++
        if (ch = "}")
            break
    }
    return obj
}

JsonReadArray(p) {
    arr := []
    p.i++
    JsonSkipWs(p)
    if (SubStr(p.t, p.i, 1) = "]") {
        p.i++
        return arr
    }
    loop {
        arr.Push(JsonReadValue(p))
        JsonSkipWs(p)
        ch := SubStr(p.t, p.i, 1)
        p.i++
        if (ch = "]")
            break
    }
    return arr
}

JsonReadString(p) {
    p.i++
    out := ""
    len := StrLen(p.t)
    while (p.i <= len) {
        ch := SubStr(p.t, p.i, 1)
        if (ch = Chr(34)) {
            p.i++
            break
        }
        if (ch = "\") {
            p.i++
            esc := SubStr(p.t, p.i, 1)
            if (esc = "u") {
                hex := SubStr(p.t, p.i + 1, 4)
                out .= Chr(Integer("0x" hex))
                p.i += 5
                continue
            }
            if (esc = Chr(34))
                out .= Chr(34)
            else if (esc = "\")
                out .= "\"
            else if (esc = "/")
                out .= "/"
            else if (esc = "b")
                out .= Chr(8)
            else if (esc = "f")
                out .= Chr(12)
            else if (esc = "n")
                out .= "`n"
            else if (esc = "r")
                out .= "`r"
            else if (esc = "t")
                out .= "`t"
            else
                out .= esc
            p.i++
            continue
        }
        out .= ch
        p.i++
    }
    return out
}

JsonReadNumber(p) {
    start := p.i
    len := StrLen(p.t)
    while (p.i <= len) {
        ch := SubStr(p.t, p.i, 1)
        if (!InStr("0123456789+-.eE", ch))
            break
        p.i++
    }
    n := SubStr(p.t, start, p.i - start)
    if (InStr(n, ".") || InStr(n, "e") || InStr(n, "E"))
        return Float(n)
    return Integer(n)
}

JGet(obj, key, default := "") {
    if (obj.Has(key))
        return obj[key]
    return default
}

UriEncode(s) {
    out := ""
    Loop Parse s {
        ch := A_LoopField
        if (RegExMatch(ch, "^[A-Za-z0-9._~-]$")) {
            out .= ch
        } else {
            size := StrPut(ch, "UTF-8")
            buf := Buffer(size)
            StrPut(ch, buf, "UTF-8")
            loop size - 1
                out .= Format("%{:02X}", NumGet(buf, A_Index - 1, "UChar"))
        }
    }
    return out
}

; ---- live data ----
CodeToCondition(code) {
    if (code = 0)
        return "Clear"
    if (code = 1 || code = 2)
        return "Partly Cloudy"
    if (code = 3)
        return "Cloudy"
    if (code = 45 || code = 48)
        return "Fog"
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
        return "Rain"
    if ((code >= 71 && code <= 77) || code = 85 || code = 86)
        return "Snow"
    if (code >= 95)
        return "Thunderstorm"
    return "Cloudy"
}

GetAutoLocation() {
    ; ipwho.is: no key, free. ipapi.co is a fallback.
    try {
        d := JsonParse(HttpGet("https://ipwho.is/"))
        lat := JGet(d, "latitude", "")
        lon := JGet(d, "longitude", "")
        if (JGet(d, "success", false) = true && lat != "" && lon != "")
            return Map("lat", lat, "lon", lon, "city", JGet(d, "city", ""), "country", JGet(d, "country", ""))
    } catch {
    }
    try {
        d := JsonParse(HttpGet("https://ipapi.co/json/"))
        lat := JGet(d, "latitude", "")
        lon := JGet(d, "longitude", "")
        if (lat != "" && lon != "")
            return Map("lat", lat, "lon", lon, "city", JGet(d, "city", ""), "country", JGet(d, "country_name", ""))
    } catch {
    }
    return 0
}

UpdateLocationMenu(label) {
    global LocationMenuLabel
    A_IconTip := "Shadow Greeting (" label ")"
    if (label = LocationMenuLabel)
        return
    old := "Set Location (" LocationMenuLabel ")"
    LocationMenuLabel := label
    try A_TrayMenu.Rename(old, "Set Location (" LocationMenuLabel ")")
}

RefreshWeather(*) {
    global LocationLat, LocationLon, LocationCity, Weather, WeatherLive
    try {
        if (LocationLat = "" || LocationLon = "") {
            loc := GetAutoLocation()
            if (!loc)
                throw Error("Location unavailable")
            LocationLat := loc["lat"]
            LocationLon := loc["lon"]
            LocationCity := loc["city"]
            autoLabel := "Auto"
            if (LocationCity != "") {
                autoLabel := "Auto: " LocationCity
                country := loc["country"]
                if (country != "")
                    autoLabel .= ", " country
            }
            UpdateLocationMenu(autoLabel)
        }
        url := "https://api.open-meteo.com/v1/forecast?latitude=" LocationLat
            . "&longitude=" LocationLon
            . "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day"
            . ",precipitation,weather_code,cloud_cover,pressure_msl"
            . ",wind_speed_10m,wind_direction_10m,wind_gusts_10m"
            . "&hourly=uv_index,precipitation_probability,visibility,dew_point_2m"
            . "&forecast_days=1&timezone=auto"
        d := JsonParse(HttpGet(url))
        cur := d["current"]
        hi := HourlyIndex(d, JGet(cur, "time", ""))
        visM := HourlyVal(d, hi, "visibility")
        Weather := Map(
            "condition", CodeToCondition(cur["weather_code"]),
            "tempC", JGet(cur, "temperature_2m"),
            "feelsC", JGet(cur, "apparent_temperature"),
            "humidity", JGet(cur, "relative_humidity_2m"),
            "precipMm", JGet(cur, "precipitation"),
            "precipProb", HourlyVal(d, hi, "precipitation_probability"),
            "uv", HourlyVal(d, hi, "uv_index"),
            "windKph", JGet(cur, "wind_speed_10m"),
            "windDeg", JGet(cur, "wind_direction_10m"),
            "gustKph", JGet(cur, "wind_gusts_10m"),
            "pressureHpa", JGet(cur, "pressure_msl"),
            "cloudPct", JGet(cur, "cloud_cover"),
            "visibilityKm", IsNumber(visM) ? visM / 1000 : "",
            "dewC", HourlyVal(d, hi, "dew_point_2m"),
            "isDay", JGet(cur, "is_day")
        )
        WeatherLive := true
    } catch {
        if (!WeatherLive)
            Weather := Map("condition", "Unavailable")
    }
    Render()
}

; Index of the current hour inside the hourly arrays (values are local time).
HourlyIndex(d, curTime) {
    try {
        h := d["hourly"]
        times := h["time"]
        key := SubStr(curTime, 1, 13)
        loop times.Length {
            if (SubStr(times[A_Index], 1, 13) = key)
                return A_Index
        }
    } catch {
    }
    return 0
}

HourlyVal(d, idx, key) {
    try {
        arr := d["hourly"][key]
        if (idx >= 1 && idx <= arr.Length)
            return arr[idx]
    } catch {
    }
    return ""
}

LoadQuotes(*) {
    global Quotes, QuoteIndex
    try {
        d := JsonParse(HttpGet("https://dummyjson.com/quotes?limit=100&select=quote,author"))
        arr := d["quotes"]
        short := []
        longer := []
        for item in arr {
            q := JGet(item, "quote", "")
            a := JGet(item, "author", "")
            if (q = "" || a = "")
                continue
            if (StrLen(q) >= 8 && StrLen(q) <= QuoteMaxLen)
                short.Push(Map("text", q, "author", a))
            if (StrLen(q) >= 8 && StrLen(q) <= 80)
                longer.Push(Map("text", q, "author", a))
        }
        list := (short.Length >= 5) ? short : longer
        if (list.Length > 0) {
            Quotes := list
            QuoteIndex := Random(1, Quotes.Length)
            Render()
        }
    } catch {
        ; keep fallback quotes
    }
}

; ---- formatting ----
; Greeting pools, grouped by part of the day, plus the mixed "extra" pool
; (prayers, compliments, general encouragement) that only appears when the
; greeting is clicked.
BuildGreetingPools() {
    global GreetingPools
    GreetingPools := Map()
    GreetingPools["morning"] := ["Good morning, {name}"]
    GreetingPools["afternoon"] := ["Good afternoon, {name}"]
    GreetingPools["evening"] := ["Good evening, {name}"]
    GreetingPools["night"] := ["Good night, {name}"]

    GreetingPools["extra"] := [
        ; prayers and blessings
        "Blessed day, {name}"
        , "Praying for you, {name}"
        , "Peace to you, {name}"
        , "God bless you, {name}"
        , "Blessings, {name}"
        , "Grace on you, {name}"
        , "Guided, {name}"
        , "Protected, {name}"
        , "Angels near, {name}"
        , "Faith over fear, {name}"
        , "Keep the faith, {name}"
        , "Stay blessed, {name}"
        ; compliments
        , "You are loved, {name}"
        , "You matter, {name}"
        , "You're amazing, {name}"
        , "So proud of you, {name}"
        , "You shine, {name}"
        , "Brilliant, {name}"
        , "Unstoppable, {name}"
        , "Strong soul, {name}"
        , "Kind heart, {name}"
        , "Pure gold, {name}"
        , "Fearless, {name}"
        , "One of a kind, {name}"
        ; general greetings and encouragement
        , "Hello, {name}"
        , "Hey there, {name}"
        , "Great to see you, {name}"
        , "Welcome back, {name}"
        , "Stay strong, {name}"
        , "You've got this, {name}"
        , "Keep going, {name}"
        , "Keep smiling, {name}"
        , "Breathe easy, {name}"
        , "Take care, {name}"
        , "Shine on, {name}"
        , "Believe in you, {name}"
        , "Onward, {name}"
    ]
}

GreetingPeriod(hour) {
    if (hour >= 5 && hour < 12)
        return "morning"
    if (hour >= 12 && hour < 17)
        return "afternoon"
    if (hour >= 17 && hour < 21)
        return "evening"
    return "night"
}

; Random line from a pool, avoiding the lines already on screen.
PickFromPool(pool, avoid1 := "", avoid2 := "") {
    pick := ""
    Loop 20 {
        pick := pool[Random(1, pool.Length)]
        if (pick != avoid1 && pick != avoid2)
            break
    }
    return pick
}

; Sets the greeting for the current part of the day: always a time-based line.
RollGreeting(*) {
    global GreetingPools, GreetingText, GreetingLastPick
    if (GreetingPools.Count = 0)
        BuildGreetingPools()
    period := GreetingPeriod(Integer(FormatTime(, "H")))
    GreetingText := PickFromPool(GreetingPools[period], GreetingLastPick)
    GreetingLastPick := GreetingText
    Render()
}

; Click on the greeting: show a random prayer / compliment / encouraging line
; for a few seconds, then fall back to the time-of-day greeting.
ShowGreetingAlt(*) {
    global GreetingPools, GreetingText, GreetingAlt, GreetingClickSecs
    if (GreetingPools.Count = 0)
        BuildGreetingPools()
    GreetingAlt := PickFromPool(GreetingPools["extra"], GreetingText, GreetingAlt)
    Render()
    SetTimer(ClearGreetingAlt, -GreetingClickSecs * 1000)
}

ClearGreetingAlt(*) {
    global GreetingAlt
    if (GreetingAlt = "")
        return
    GreetingAlt := ""
    Render()
}

; ---- weather attribute view ----
; Click the weather line: cycle temperature -> feels -> precipitation -> UV ->
; wind -> gusts -> humidity -> pressure -> cloud cover -> visibility.
WeatherAttrNext(*) {
    global WeatherAttrKeys, WeatherAttrIndex, WeatherClickSecs
    WeatherAttrIndex := Mod(WeatherAttrIndex, WeatherAttrKeys.Length) + 1
    Render()
    SetTimer(ResetWeatherAttr, -WeatherClickSecs * 1000)
}

ResetWeatherAttr(*) {
    global WeatherAttrIndex
    if (WeatherAttrIndex = 1)
        return
    WeatherAttrIndex := 1
    Render()
}

WGet(key) {
    global Weather
    return Weather.Has(key) ? Weather[key] : ""
}

WindUnitLabel() {
    global TempUnit
    return (TempUnit = "F") ? "mph" : "km/h"
}

ConvertWind(kph) {
    global TempUnit
    return (TempUnit = "F") ? kph * 0.621371 : kph
}

PrecipUnitLabel() {
    global TempUnit
    return (TempUnit = "F") ? "in" : "mm"
}

ConvertPrecip(mm) {
    global TempUnit
    return (TempUnit = "F") ? mm / 25.4 : mm
}

DistanceUnitLabel() {
    global TempUnit
    return (TempUnit = "F") ? "mi" : "km"
}

ConvertDistance(km) {
    global TempUnit
    return (TempUnit = "F") ? km * 0.621371 : km
}

UvLabel(v) {
    if (v < 3)
        return "Low"
    if (v < 6)
        return "Moderate"
    if (v < 8)
        return "High"
    if (v < 11)
        return "Very high"
    return "Extreme"
}

CompassDir(deg) {
    if (!IsNumber(deg))
        return ""
    dirs := ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE"
        , "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    return dirs[Mod(Round(deg / 22.5), 16) + 1]
}

VisibilityLabel(km) {
    if (km >= 10)
        return "Clear view"
    if (km >= 4)
        return "Good"
    if (km >= 1)
        return "Moderate"
    return "Poor"
}

; Text shown on the weather row for one attribute: icon key, big value, and the
; two small lines on the right.
WeatherDisplay(key) {
    global TempUnit, ShowFeelsLike, LocationCity, LocationMenuLabel
    cond := WGet("condition")

    ; Second click: which place the weather is actually coming from.
    if (key = "location") {
        label := LocationMenuLabel
        auto := (SubStr(label, 1, 4) = "Auto")
        city := LocationCity
        if (city = "")
            city := auto ? Trim(SubStr(label, 6)) : label
        sub := ""
        sep := InStr(label, ", ")
        if (auto) {
            rest := Trim(SubStr(label, 6))
            sub := InStr(rest, ", ") ? SubStr(rest, InStr(rest, ", ") + 2) : "Auto-detected"
        } else if (sep) {
            sub := SubStr(label, sep + 2)
        }
        return Map("main", city != "" ? city : "--", "top", "Location", "sub", sub)
    }

    if (key = "temp") {
        t := WGet("tempC")
        main := IsNumber(t) ? ConvertTemp(t) Chr(176) TempUnit : "--"
        sub := ""
        if (ShowFeelsLike) {
            f := WGet("feelsC")
            sub := IsNumber(f) ? "Feels like " ConvertTemp(f) Chr(176) TempUnit : "Feels like --"
        }
        return Map("main", main, "top", cond, "sub", sub)
    }

    if (key = "feels") {
        f := WGet("feelsC")
        main := IsNumber(f) ? ConvertTemp(f) Chr(176) TempUnit : "--"
        return Map("main", main, "top", "Feels Like", "sub", cond)
    }

    if (key = "precip") {
        p := WGet("precipMm")
        main := IsNumber(p) ? Format("{:.2f}", ConvertPrecip(p)) " " PrecipUnitLabel() : "--"
        pr := WGet("precipProb")
        sub := IsNumber(pr) ? "Chance " Round(pr) "%" : ""
        return Map("main", main, "top", "Precipitation", "sub", sub)
    }

    if (key = "uv") {
        u := WGet("uv")
        main := IsNumber(u) ? Format("{:.1f}", u) : "--"
        return Map("main", main, "top", "UV Index", "sub", IsNumber(u) ? UvLabel(u) : "")
    }

    if (key = "wind") {
        w := WGet("windKph")
        main := IsNumber(w) ? Format("{:.0f}", ConvertWind(w)) " " WindUnitLabel() : "--"
        d := CompassDir(WGet("windDeg"))
        return Map("main", main, "top", "Wind", "sub", d != "" ? "From " d : "")
    }

    if (key = "gust") {
        g := WGet("gustKph")
        main := IsNumber(g) ? Format("{:.0f}", ConvertWind(g)) " " WindUnitLabel() : "--"
        d := CompassDir(WGet("windDeg"))
        return Map("main", main, "top", "Wind Gusts", "sub", d != "" ? "From " d : "")
    }

    if (key = "humidity") {
        h := WGet("humidity")
        main := IsNumber(h) ? Round(h) "%" : "--"
        dw := WGet("dewC")
        sub := IsNumber(dw) ? "Dew point " ConvertTemp(dw) Chr(176) TempUnit : ""
        return Map("main", main, "top", "Humidity", "sub", sub)
    }

    if (key = "pressure") {
        p := WGet("pressureHpa")
        main := IsNumber(p) ? Round(p) " hPa" : "--"
        return Map("main", main, "top", "Pressure", "sub", "Sea level")
    }

    if (key = "cloud") {
        c := WGet("cloudPct")
        main := IsNumber(c) ? Round(c) "%" : "--"
        return Map("main", main, "top", "Cloud Cover", "sub", cond)
    }

    if (key = "visibility") {
        v := WGet("visibilityKm")
        main := IsNumber(v) ? Format("{:.1f}", ConvertDistance(v)) " " DistanceUnitLabel() : "--"
        return Map("main", main, "top", "Visibility", "sub", IsNumber(v) ? VisibilityLabel(v) : "")
    }

    return Map("main", "--", "top", "", "sub", "")
}

FormatGreeting() {
    global UserName, GreetingText, GreetingAlt
    line := (GreetingAlt != "") ? GreetingAlt : GreetingText
    if (line = "")
        line := "Hello, {name}"
    return StrUpper(StrReplace(line, "{name}", UserName))
}

ConvertTemp(celsius) {
    global TempUnit
    return (TempUnit = "F") ? Round(celsius * 9 / 5 + 32) : Round(celsius)
}

Render() {
    global W, H
    global UserName, GreetingFont, GreetingStyle, GreetingSize, WeatherFont, TempSize, CondSize, FeelsSize
    global QuoteFont, QuoteSize, AuthorSize
    global GreetingY, WeatherY, WeatherRowH, QuoteY, GreetingAlpha, WeatherAlpha, CondAlpha, FeelsAlpha, QuoteAlpha, AuthorAlpha
    global GreetingTargetH, GreetingTop
    global IconSize, IconGap, InfoGap, UseBorder, BorderColor
    global DividerColor, DividerAlpha, DividerY, DividerInset
    global ShowFeelsLike, ShowQuote, ShowQuoteAuthor, TempUnit
    global QuoteIndex, Quotes, Weather, PAD
    global WeatherAttrKeys, WeatherAttrIndex

    bBmp := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", W, "int", H, "int", 0, "int", 0x26200A, "ptr", 0, "ptr", bBmp)
    pBitmap := NumGet(bBmp, 0, "ptr")
    bG := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr", bG)
    pG := NumGet(bG, 0, "ptr")
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pG, "int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", pG, "int", 5)
    DllCall("gdiplus\GdipGraphicsClear", "ptr", pG, "uint", 0x00000000)

    ; Layered windows are click-through wherever a pixel's alpha is 0, so the
    ; empty areas would still swallow presses. Fill the surface with 2/255 alpha
    ; (visually imperceptible) so every pixel is hit-testable.
    bBase := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", 0x02000000, "ptr", bBase)
    pBase := NumGet(bBase, 0, "ptr")
    DllCall("gdiplus\GdipFillRectangle", "ptr", pG, "ptr", pBase, "float", 0, "float", 0, "float", W, "float", H)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBase)

    bCol := UseBorder ? BorderColor : 0

    ; ---- greeting ----
    greeting := FormatGreeting()
    greetSize := FitSize(pG, GreetingFont, greeting, GreetingSize, W - 40, GreetingStyle)
    fGreet := GetFont(GreetingFont, greetSize, GreetingStyle)
    ; stretch only vertically so the glyphs stay 96 px tall at any fitted size
    greetD := 10 * greetSize / 44
    greetK := GreetingTargetH * 44 / (56 * greetSize)
    greetShift := (GreetingTop - 2) / greetK - GreetingY - greetD
    ApplyGreetingStretch(pG, greetK, greetShift)
    DrawTextCentered(pG, fGreet, greeting, GreetingY, GreetingAlpha, 0, 0, 1, GreetingFont, greetSize, bCol, 0xFFFFFF, GreetingStyle)
    DllCall("gdiplus\GdipResetWorldTransform", "ptr", pG)

    ; ---- weather: icon | main value | attribute label + detail ----
    attrKey := WeatherAttrKeys[WeatherAttrIndex]
    disp := WeatherDisplay(attrKey)
    mainStr := disp["main"]
    topStr := disp["top"]
    subStr := disp["sub"]

    ; long place names get more room than a temperature before shrinking
    mainMax := (attrKey = "location") ? 220 : 150
    mainSize := FitSize(pG, WeatherFont, mainStr, TempSize, mainMax)
    fMain := GetFont(WeatherFont, mainSize)
    fTop := GetFont(WeatherFont, CondSize)
    fSub := GetFont(WeatherFont, FeelsSize)

    wMain := MeasureString(pG, fMain, mainStr)[1] - 2 * PAD
    wTop := MeasureString(pG, fTop, topStr)[1] - 2 * PAD
    wSub := (subStr = "") ? 0 : MeasureString(pG, fSub, subStr)[1] - 2 * PAD
    infoW := wTop
    if (wSub > infoW)
        infoW := wSub

    groupW := IconSize + IconGap + wMain + InfoGap + infoW
    gx := Round((W - groupW) / 2)
    iconX := gx
    iconY := Round(WeatherY + (WeatherRowH - IconSize) / 2)
    mainX := iconX + IconSize + IconGap
    infoX := mainX + wMain + InfoGap

    DrawAttrIcon(pG, iconX, iconY, IconSize / 64, attrKey, Weather["condition"])

    DrawStringRect(pG, fMain, mainStr, mainX - PAD, WeatherY, wMain + 2 * PAD + 10, 58, WeatherAlpha, 0xFFFFFF, 0, bCol, WeatherFont, mainSize)
    DrawStringRect(pG, fTop, topStr, infoX - PAD, WeatherY + 6, infoW + 2 * PAD + 10, 30, CondAlpha, 0xFFFFFF, 0, bCol, WeatherFont, CondSize)
    if (subStr != "")
        DrawStringRect(pG, fSub, subStr, infoX - PAD, WeatherY + 36, infoW + 2 * PAD + 10, 24, FeelsAlpha, 0xFFFFFF, 0, bCol, WeatherFont, FeelsSize)

    ; ---- quote ----
    if (ShowQuote) {
        DrawLineAt(pG, DividerInset, DividerY, W - DividerInset, DividerY, DividerAlpha, DividerColor, 1.0)

        quote := Quotes[QuoteIndex]
        quoteText := Chr(8220) quote["text"] Chr(8221)
        qSize := QuoteSize
        lines := []
        while (qSize >= 17) {
            fQ := GetFont(QuoteFont, qSize)
            lines := GetWrappedLines(pG, fQ, quoteText, W - 100)
            if (lines.Length <= 1)
                break
            qSize -= 1
        }
        fQuote := GetFont(QuoteFont, qSize)
        lineH := Round(qSize * 1.6)
        for i, line in lines {
            DrawTextCentered(pG, fQuote, line, QuoteY + (i - 1) * lineH, QuoteAlpha, 0, 0, 1, QuoteFont, qSize, bCol)
        }
        if (ShowQuoteAuthor) {
            fAuthor := GetFont(QuoteFont, AuthorSize)
            author := Chr(8212) " " quote["author"]
            authorY := QuoteY + lines.Length * lineH
            DrawTextCentered(pG, fAuthor, author, authorY, AuthorAlpha, 0, 0, 1, QuoteFont, AuthorSize, bCol)
        }
    }

    ; ---- push to layered window ----
    bHB := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", pBitmap, "ptr", bHB, "uint", 0)
    hBitmap := NumGet(bHB, 0, "ptr")
    hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
    obm := DllCall("SelectObject", "ptr", hdcMem, "ptr", hBitmap, "ptr")

    bf := Buffer(4, 0)
    NumPut("uchar", 0, bf, 0)
    NumPut("uchar", 0, bf, 1)
    NumPut("uchar", 255, bf, 2)
    NumPut("uchar", 1, bf, 3)

    size := Buffer(8, 0)
    NumPut("int", W, size, 0)
    NumPut("int", H, size, 4)
    ptSrc := Buffer(8, 0)
    ptDst := Buffer(8, 0)
    wr := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", hWnd, "ptr", wr)
    NumPut("int", NumGet(wr, 0, "int"), ptDst, 0)
    NumPut("int", NumGet(wr, 4, "int"), ptDst, 4)

    DllCall("UpdateLayeredWindow", "ptr", hWnd, "ptr", hdcScreen, "ptr", ptDst
        , "ptr", size, "ptr", hdcMem, "ptr", ptSrc, "uint", 0, "ptr", bf, "uint", 2)

    DllCall("SelectObject", "ptr", hdcMem, "ptr", obm, "ptr")
    DllCall("DeleteDC", "ptr", hdcMem)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)
    DllCall("DeleteObject", "ptr", hBitmap)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", pG)
}

; ---- tray actions ----
SetName(*) {
    global UserName
    ib := InputBox("Enter your name:", "Shadow Greeting", "w320 h130", UserName)
    if (ib.Result != "OK")
        return
    newName := Trim(ib.Value)
    if (newName = "" || newName = UserName)
        return
    oldLabel := "Set Name (" UserName ")"
    UserName := newName
    A_TrayMenu.Rename(oldLabel, "Set Name (" UserName ")")
    Render()
}

; ---- location: search dialog + persistence ----
; Opens a small search window: type a city, press Search, then pick the exact
; match from the list (city / region / country all visible).
SetLocation(*) {
    global LocationCity

    picker := Gui("+AlwaysOnTop +ToolWindow", "Shadow Greeting - Set Location")
    picker.SetFont("s10", "Segoe UI")
    picker.MarginX := 12
    picker.MarginY := 12

    picker.Add("Text", "x12 y12 w500", "Type a city name, then press Search:")
    ed := picker.Add("Edit", "x12 y34 w380 h26", LocationCity)
    btnSearch := picker.Add("Button", "x404 y33 w110 h28 Default", "Search")
    lv := picker.Add("ListView", "x12 y74 w502 h230 -Multi", ["City", "Region", "Country"])
    lv.ModifyCol(1, 170)
    lv.ModifyCol(2, 190)
    lv.ModifyCol(3, 130)
    btnUse := picker.Add("Button", "x12 y316 w130 h30", "Use Selected")
    btnAuto := picker.Add("Button", "x152 y316 w130 h30", "Auto (Detect)")
    btnCancel := picker.Add("Button", "x424 y316 w90 h30", "Cancel")
    status := picker.Add("Text", "x12 y354 w502 h34", "")

    results := []

    doSearch(*) {
        q := Trim(ed.Value)
        if (q = "") {
            status.Text := "Type a city name first."
            return
        }
        lv.Delete()
        results := []
        status.Text := "Searching..."
        try {
            found := SearchLocations(q)
        } catch {
            status.Text := "Could not reach the location search service. Check your connection."
            return
        }
        for r in found {
            results.Push(r)
            lv.Add(, r["city"], r["region"], r["country"])
        }
        if (results.Length = 0) {
            status.Text := "No matches for " Chr(8220) q Chr(8221) ". Try another spelling."
        } else {
            status.Text := results.Length " match(es) - select one and press Use Selected."
            lv.Modify(1, "Select Focus")
        }
    }

    useSelected(*) {
        row := lv.GetNext()
        if (!row) {
            status.Text := "Select a location from the list first."
            return
        }
        ApplyLocation(results[row])
        picker.Destroy()
    }

    useAuto(*) {
        ApplyAutoLocation()
        picker.Destroy()
    }

    ed.OnEvent("Change", (*) => (status.Text := ""))
    btnSearch.OnEvent("Click", doSearch)
    lv.OnEvent("DoubleClick", useSelected)
    btnUse.OnEvent("Click", useSelected)
    btnAuto.OnEvent("Click", useAuto)
    btnCancel.OnEvent("Click", (*) => picker.Destroy())
    picker.OnEvent("Escape", (*) => picker.Destroy())
    picker.OnEvent("Close", (*) => picker.Destroy())

    picker.Show("w526 h404")
    ed.Focus()
    if (Trim(ed.Value) != "")
        doSearch()
}

SearchLocations(q) {
    url := "https://geocoding-api.open-meteo.com/v1/search?name=" UriEncode(q)
        . "&count=10&language=en&format=json"
    d := JsonParse(HttpGet(url))
    out := []
    if (d.Has("results")) {
        for r in d["results"] {
            out.Push(Map(
                "city", JGet(r, "name", ""),
                "region", JGet(r, "admin1", ""),
                "country", JGet(r, "country", ""),
                "lat", JGet(r, "latitude", ""),
                "lon", JGet(r, "longitude", "")))
        }
    }
    return out
}

LocationLabel(city, region, country) {
    label := city
    if (region != "" && region != city)
        label .= ", " region
    if (country != "")
        label .= ", " country
    return label
}

ApplyLocation(r) {
    global LocationLat, LocationLon, LocationCity
    LocationLat := r["lat"]
    LocationLon := r["lon"]
    LocationCity := r["city"]
    UpdateLocationMenu(LocationLabel(r["city"], r["region"], r["country"]))
    SaveLocationSettings(false)
    RefreshWeather()
}

ApplyAutoLocation() {
    global LocationLat, LocationLon, LocationCity
    LocationLat := ""
    LocationLon := ""
    LocationCity := ""
    UpdateLocationMenu("Auto")
    SaveLocationSettings(true)
    RefreshWeather()
}

SaveLocationSettings(autoMode) {
    global SettingsDir, SettingsFile, LocationLat, LocationLon, LocationCity, LocationMenuLabel
    try {
        DirCreate(SettingsDir)
        IniWrite(autoMode ? "1" : "0", SettingsFile, "Location", "auto")
        IniWrite(autoMode ? "" : LocationLat, SettingsFile, "Location", "lat")
        IniWrite(autoMode ? "" : LocationLon, SettingsFile, "Location", "lon")
        IniWrite(autoMode ? "" : LocationCity, SettingsFile, "Location", "city")
        IniWrite(autoMode ? "" : LocationMenuLabel, SettingsFile, "Location", "label")
    } catch {
    }
}

LoadLocationSettings() {
    global SettingsFile, LocationLat, LocationLon, LocationCity
    if (!FileExist(SettingsFile))
        return
    if (IniRead(SettingsFile, "Location", "auto", "1") = "1")
        return
    lat := IniRead(SettingsFile, "Location", "lat", "")
    lon := IniRead(SettingsFile, "Location", "lon", "")
    city := IniRead(SettingsFile, "Location", "city", "")
    label := IniRead(SettingsFile, "Location", "label", "")
    if (lat = "" || lon = "")
        return
    LocationLat := lat
    LocationLon := lon
    LocationCity := city
    UpdateLocationMenu(label != "" ? label : city)
}

; ---- window position + drag lock (persist across restarts and reboots) ----
LoadWindowSettings() {
    global SettingsFile, Draggable, hWnd, W, H
    if (!FileExist(SettingsFile))
        return
    if (IniRead(SettingsFile, "Window", "draggable", "1") = "0")
        Draggable := false
    x := IniRead(SettingsFile, "Window", "x", "")
    y := IniRead(SettingsFile, "Window", "y", "")
    if (x = "" || y = "")
        return
    x := x + 0
    y := y + 0
    ; keep it reachable if the monitor layout changed since the last run
    vx := DllCall("GetSystemMetrics", "int", 76)
    vy := DllCall("GetSystemMetrics", "int", 77)
    vw := DllCall("GetSystemMetrics", "int", 78)
    vh := DllCall("GetSystemMetrics", "int", 79)
    if (vw > 0 && vh > 0) {
        if (x < vx)
            x := vx
        if (y < vy)
            y := vy
        if (x > vx + vw - W)
            x := vx + vw - W
        if (y > vy + vh - H)
            y := vy + vh - H
    }
    DllCall("SetWindowPos", "ptr", hWnd, "ptr", 0, "int", x, "int", y, "int", 0, "int", 0, "uint", 0x0004)
}

SaveWindowSettings(*) {
    global SettingsFile, SettingsDir, hWnd, Draggable
    try {
        DirCreate(SettingsDir)
        wr := Buffer(16, 0)
        DllCall("GetWindowRect", "ptr", hWnd, "ptr", wr)
        IniWrite(NumGet(wr, 0, "int"), SettingsFile, "Window", "x")
        IniWrite(NumGet(wr, 4, "int"), SettingsFile, "Window", "y")
        IniWrite(Draggable ? "1" : "0", SettingsFile, "Window", "draggable")
    } catch {
    }
}

ToggleDraggable(*) {
    global Draggable
    oldLabel := "Draggable (" (Draggable ? "On" : "Off") ")"
    Draggable := !Draggable
    A_TrayMenu.Rename(oldLabel, "Draggable (" (Draggable ? "On" : "Off") ")")
    SaveWindowSettings()
}

ToggleUnit(*) {
    global TempUnit
    oldLabel := "Temperature Unit (" Chr(176) TempUnit ")"
    TempUnit := (TempUnit = "C") ? "F" : "C"
    A_TrayMenu.Rename(oldLabel, "Temperature Unit (" Chr(176) TempUnit ")")
    Render()
}

ToggleFeelsLike(*) {
    global ShowFeelsLike
    oldLabel := "Show Feels Like (" (ShowFeelsLike ? "On" : "Off") ")"
    ShowFeelsLike := !ShowFeelsLike
    A_TrayMenu.Rename(oldLabel, "Show Feels Like (" (ShowFeelsLike ? "On" : "Off") ")")
    Render()
}

ToggleQuotes(*) {
    global ShowQuote
    oldLabel := "Quotes (" (ShowQuote ? "On" : "Off") ")"
    ShowQuote := !ShowQuote
    A_TrayMenu.Rename(oldLabel, "Quotes (" (ShowQuote ? "On" : "Off") ")")
    Render()
}

ToggleAuthor(*) {
    global ShowQuoteAuthor
    oldLabel := "Show Quote Author (" (ShowQuoteAuthor ? "On" : "Off") ")"
    ShowQuoteAuthor := !ShowQuoteAuthor
    A_TrayMenu.Rename(oldLabel, "Show Quote Author (" (ShowQuoteAuthor ? "On" : "Off") ")")
    Render()
}

NewQuote(*) {
    global QuoteIndex, Quotes
    newIndex := QuoteIndex
    while (Quotes.Length > 1 && newIndex = QuoteIndex)
        newIndex := Random(1, Quotes.Length)
    QuoteIndex := newIndex
    Render()
}

ToggleBorder(*) {
    global UseBorder
    oldLabel := "Toggle Border (" (UseBorder ? "On" : "Off") ")"
    UseBorder := !UseBorder
    A_TrayMenu.Rename(oldLabel, "Toggle Border (" (UseBorder ? "On" : "Off") ")")
    Render()
}

RotateQuote() {
    global ShowQuote
    if (!ShowQuote)
        return
    NewQuote()
}

InitRefresh(*) {
    RefreshWeather()
}

InitQuotes(*) {
    LoadQuotes()
}

; ---- main loop ----
BuildGreetingPools()
LoadLocationSettings()
RollGreeting()
Render()
SetTimer(Render, 1000)
SetTimer(RollGreeting, GreetingRotateMs)
SetTimer(RotateQuote, QuoteIntervalSec * 1000)
; load once, then keep each timer on a single cadence (a second SetTimer call
; on the same function replaces the first one, which would cancel the one-shot)
SetTimer(InitRefresh, -800)
SetTimer(InitQuotes, -1500)
SetTimer(RefreshWeather, WeatherRefreshMs)
SetTimer(LoadQuotes, 6 * 60 * 60 * 1000)
