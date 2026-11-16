#Requires AutoHotkey v2.0
#SingleInstance Force

; ---- DPI: use physical pixels so layered-window coordinates are consistent ----
DllCall("SetProcessDPIAware")

; ===================== CONFIG (matches ZClock - 12H - With Border) =====================
global Mode := "12H"          ; "12H" or "24H"
global UseBorder := true      ; red outline around time, weekday, date text
global W := 600
global H := 330
global TimeFont := "Steelfish Rg"
global WeekdayFont := "la Compagnie des Ombres"
global DateFont := "Steelfish Rg"

; sizes in POINTS (Rainmeter uses points; GDI+ unit Point matches it exactly)
global TimeSize := 160
global WeekdaySize := 90
global DateSize := 55

; element positions (pixels, shifted +30 so the time's top sits at y=0)
global TimeY := 1
global WeekdayY := 175
global DateY := 225

; alpha (255=solid, lower=more transparent)
global TimeAlpha := 130
global WeekdayAlpha := 255
global DateAlpha := 90

; AM/PM indicator (small, placed tightly right after the time)
global AMPMSize := 20
global AMPMColor := 0xFF5A5A
global AMPMAlpha := 100   ; red, more transparent than the superscript
global AMPMGap := 6

; red text outline around the time, weekday, and date
global BorderColor := 0xFF5A5A
global BorderAlpha := 150
global BorderWidth := 1.5

; superscript "th" - red, semi-transparent
global SupColor := 0xFF5A5A
global SupAlpha := 150

; GDI+ default StringFormat pads each string by ~9.4px per side
global PAD := 9.4
; ==========================================================================================

screenW := DllCall("GetSystemMetrics", "int", 0)
screenH := DllCall("GetSystemMetrics", "int", 1)
PosX := (screenW - W) // 2
PosY := Round(screenH * 0.10)

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
    , "str", "ZClock"
    , "uint", WS_POPUP | WS_VISIBLE
    , "int", PosX, "int", PosY, "int", W, "int", H
    , "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0)

; ---- dragging (manual: HTCAPTION drag doesn't work with WS_EX_NOACTIVATE) ----
global dragging := false
global dragDX := 0, dragDY := 0
OnMessage(0x0201, WM_LBUTTONDOWN)
OnMessage(0x0200, WM_MOUSEMOVE)
OnMessage(0x0202, WM_LBUTTONUP)
Debug(msg, note := "") {
    global hWnd
}
WM_LBUTTONDOWN(wParam, lParam, msg, h) {
    global dragging, dragDX, dragDY, hWnd
    Debug(msg, "LDOWN h=" h)
    if (h != hWnd)
        return
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    mx := NumGet(pt, 0, "int")
    my := NumGet(pt, 4, "int")
    wr := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", hWnd, "ptr", wr)
    dragDX := mx - NumGet(wr, 0, "int")
    dragDY := my - NumGet(wr, 4, "int")
    dragging := true
    DllCall("SetCapture", "ptr", hWnd)
}
WM_MOUSEMOVE(wParam, lParam, msg, h) {
    global dragging, dragDX, dragDY, hWnd
    if (h != hWnd || !dragging)
        return
    Debug(msg, "MMOVE h=" h)
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    mx := NumGet(pt, 0, "int")
    my := NumGet(pt, 4, "int")
    DllCall("SetWindowPos", "ptr", hWnd, "ptr", 0, "int", mx - dragDX, "int", my - dragDY, "int", 0, "int", 0, "uint", 0x0004)
}
WM_LBUTTONUP(wParam, lParam, msg, h) {
    global dragging
    if (h != hWnd)
        return
    Debug(msg, "LUP h=" h)
    dragging := false
    DllCall("ReleaseCapture")
}

; ---- tray menu ----
A_TrayMenu.Delete()
A_TrayMenu.Add("Toggle 12/24H (" Mode ")", ToggleMode)
A_TrayMenu.Add("Toggle Border (" (UseBorder ? "On" : "Off") ")", ToggleBorder)
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_IconTip := "ZClock"

; ---- helpers ----
GetFont(family, size) {
    static cache := Map()
    key := family "|" size
    if cache.Has(key)
        return cache[key]
    bFam := Buffer(A_PtrSize, 0)
    if DllCall("gdiplus\GdipCreateFontFamilyFromName", "str", family, "ptr", 0, "ptr", bFam) != 0
        DllCall("gdiplus\GdipGetGenericFontFamilySansSerif", "ptr", bFam)
    pFamily := NumGet(bFam, 0, "ptr")
    bFont := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateFont", "ptr", pFamily, "float", size, "int", 0, "int", 3, "ptr", bFont)
    pFont := NumGet(bFont, 0, "ptr")
    DllCall("gdiplus\GdipDeleteFontFamily", "ptr", pFamily)
    cache[key] := pFont
    return pFont
}

BuildTextPath(g, famName, emSizePt, text, rect, fmt) {
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
    DllCall("gdiplus\GdipAddPathString", "ptr", pPath, "str", text, "int", -1, "ptr", pFamily, "int", 0, "float", emSize, "ptr", rect, "ptr", fmt)
    DllCall("gdiplus\GdipDeleteFontFamily", "ptr", pFamily)
    return pPath
}

OutlineTextAt(g, famName, emSizePt, text, rect, fmt, color, fillAlpha, fillColor) {
    global BorderAlpha, BorderWidth
    ; stroke AND fill the SAME path so the red outline and the text itself are
    ; pixel-aligned (text via GdipDrawString is grid-fitted and shifts a few px).
    pPath := BuildTextPath(g, famName, emSizePt, text, rect, fmt)
    bPen := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreatePen1", "uint", (BorderAlpha << 24) | (color & 0xFFFFFF), "float", BorderWidth, "int", 2, "ptr", bPen)
    pPen := NumGet(bPen, 0, "ptr")
    DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pPen, "ptr", pPath)
    DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
    bBrush := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", (fillAlpha << 24) | (fillColor & 0xFFFFFF), "ptr", bBrush)
    pBrush := NumGet(bBrush, 0, "ptr")
    DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", pBrush, "ptr", pPath)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
}

DrawTextCentered(g, pFont, text, y, alpha, offsetX := 0, offsetY := 0, alignX := 1, famName := "", emSize := 0, outlineColor := 0, fillColor := 0xFFFFFF) {
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
        ; stroke + fill the same path so outline and text are pixel-aligned
        OutlineTextAt(g, famName, emSize, text, rect, fmt, outlineColor, alpha, fillColor)
    } else {
        bBrush := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdipCreateSolidFill", "uint", (alpha << 24) | (fillColor & 0xFFFFFF), "ptr", bBrush)
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

; exact ink bounding box [left, top, right, bottom] of text laid out with rect+fmt
PathInkBounds(g, famName, sizePt, text, rect, fmt) {
    pPath := BuildTextPath(g, famName, sizePt, text, rect, fmt)
    bBnd := Buffer(16, 0)
    DllCall("gdiplus\GdipGetPathWorldBounds", "ptr", pPath, "ptr", bBnd)
    x := NumGet(bBnd, 0, "float")
    y := NumGet(bBnd, 4, "float")
    w := NumGet(bBnd, 8, "float")
    h := NumGet(bBnd, 12, "float")
    DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
    return [x, y, x + w, y + h]
}

DrawDateCentered(g, fDate, fSup, day, sup, rest, y, alpha, famName := "", dateSize := 0, supSize := 0, outlineColor := 0) {
    global W, H, PAD, SupColor, SupAlpha
    mDay := MeasureString(g, fDate, day)
    mSup := MeasureString(g, fSup, sup)
    mRest := MeasureString(g, fDate, rest)
    spaceW := MeasureString(g, fDate, " A")[1] - MeasureString(g, fDate, "A")[1]
    advDay := mDay[1] - 2 * PAD
    advSup := mSup[1] - 2 * PAD
    advRest := mRest[1] - 2 * PAD
    width := advDay + advSup + spaceW + advRest
    startX := (W - width) / 2 - PAD
    bFmt := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr", bFmt)
    fmt := NumGet(bFmt, 0, "ptr")
    bBrush := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", (alpha << 24) | 0xFFFFFF, "ptr", bBrush)
    pBrush := NumGet(bBrush, 0, "ptr")
    rect := Buffer(16, 0)
    ; day "14"
    NumPut("float", startX, rect, 0)
    NumPut("float", y, rect, 4)
    NumPut("float", mDay[1] + 4, rect, 8)
    NumPut("float", H - y, rect, 12)
    if (outlineColor && famName != "")
        OutlineTextAt(g, famName, dateSize, day, rect, fmt, outlineColor, alpha, 0xFFFFFF)
    else
        DllCall("gdiplus\GdipDrawString", "ptr", g, "str", day, "int", -1, "ptr", fDate, "ptr", rect, "ptr", fmt, "ptr", pBrush)
    ; superscript "th", tight after the day, raised
    supX := startX + advDay
    supY := y + (mDay[2] - mSup[2])
    NumPut("float", supX, rect, 0)
    NumPut("float", supY, rect, 4)
    NumPut("float", mSup[1] + 4, rect, 8)
    NumPut("float", H - supY, rect, 12)
    bSupBrush := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateSolidFill", "uint", (SupAlpha << 24) | SupColor, "ptr", bSupBrush)
    pSupBrush := NumGet(bSupBrush, 0, "ptr")
    ; AntiAlias (hint 4, no ClearType color fringing) so the small "th" has no dark/colored edges
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", g, "int", 4)
    DllCall("gdiplus\GdipDrawString", "ptr", g, "str", sup, "int", -1, "ptr", fSup, "ptr", rect, "ptr", fmt, "ptr", pSupBrush)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", g, "int", 5)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pSupBrush)
    ; rest "AUGUST, 2026" with one space before it
    restX := startX + advDay + advSup + spaceW
    NumPut("float", restX, rect, 0)
    NumPut("float", y, rect, 4)
    NumPut("float", mRest[1] + 4, rect, 8)
    NumPut("float", H - y, rect, 12)
    if (outlineColor && famName != "")
        OutlineTextAt(g, famName, dateSize, rest, rect, fmt, outlineColor, alpha, 0xFFFFFF)
    else
        DllCall("gdiplus\GdipDrawString", "ptr", g, "str", rest, "int", -1, "ptr", fDate, "ptr", rect, "ptr", fmt, "ptr", pBrush)
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
}

FormatClock() {
    global Mode
    if (Mode = "24H")
        time := FormatTime(, "HH:mm")
    else
        time := FormatTime(, "h:mm")      ; %I:%M - 12h, no AM/PM
    ampm := (Mode = "24H") ? "" : FormatTime(, "tt")   ; %p - AM/PM
    weekday := FormatTime(, "dddd")       ; %A
    day := FormatTime(, "d")              ; %#d
    suffix := (day = "1" || day = "21" || day = "31") ? "st"
            : (day = "2" || day = "22") ? "nd"
            : (day = "3" || day = "23") ? "rd"
            : "th"
    month := FormatTime(, "MMMM")         ; %B
    year := FormatTime(, "yyyy")          ; %Y
    ; "14th AUGUST, 2026"  ->  "14" + superscript "th" + "AUGUST, 2026"
    return [time, weekday, day, suffix, StrUpper(month ", " year), ampm]
}

Render() {
    global W, H
    global TimeFont, TimeSize, WeekdayFont, WeekdaySize, DateFont, DateSize
    global TimeY, WeekdayY, DateY, TimeAlpha, WeekdayAlpha, DateAlpha
    global UseBorder, BorderColor
    global AMPMSize, AMPMColor, AMPMAlpha, AMPMGap
    bBmp := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", W, "int", H, "int", 0, "int", 0x26200A, "ptr", 0, "ptr", bBmp)
    pBitmap := NumGet(bBmp, 0, "ptr")
    bG := Buffer(A_PtrSize, 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr", bG)
    pG := NumGet(bG, 0, "ptr")
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pG, "int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", pG, "int", 5)
    DllCall("gdiplus\GdipGraphicsClear", "ptr", pG, "uint", 0x00000000)

    parts := FormatClock()
    fTime := GetFont(TimeFont, TimeSize)
    fWeek := GetFont(WeekdayFont, WeekdaySize)
    fDate := GetFont(DateFont, DateSize)
    fSup := GetFont(DateFont, Round(DateSize * 0.6))
    bCol := UseBorder ? BorderColor : 0

    ; time (top) with red outline
    DrawTextCentered(pG, fTime, parts[1], TimeY, TimeAlpha, 0, 0, 1, TimeFont, TimeSize, bCol)

    ; date (bottom) with red outline
    DrawDateCentered(pG, fDate, fSup, parts[3], parts[4], parts[5], DateY, DateAlpha, DateFont, DateSize, Round(DateSize * 0.6), bCol)

    ; weekday (middle) with red outline
    DrawTextCentered(pG, fWeek, parts[2], WeekdayY, WeekdayAlpha, 0, 0, 1, WeekdayFont, WeekdaySize, bCol)

    ; AM/PM at the time's upper-right corner, tight against it (no border/outline)
    if (parts[6] != "") {
        try {
            fAMPM := GetFont(TimeFont, AMPMSize)
            ; exact ink bounds of the time, using the same centered rect/format as the fill
            bFmtT := Buffer(A_PtrSize, 0)
            DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr", bFmtT)
            fmtT := NumGet(bFmtT, 0, "ptr")
            DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmtT, "int", 1)
            rectT := Buffer(16, 0)
            NumPut("float", 0, rectT, 0)
            NumPut("float", TimeY, rectT, 4)
            NumPut("float", W, rectT, 8)
            NumPut("float", H - TimeY, rectT, 12)
            tb := PathInkBounds(pG, TimeFont, TimeSize, parts[1], rectT, fmtT)
            DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmtT)
            ; AM/PM ink bounds when near-aligned in a rect at (0,0,W,H)
            bFmtA := Buffer(A_PtrSize, 0)
            DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr", bFmtA)
            fmtA := NumGet(bFmtA, 0, "ptr")
            rectA := Buffer(16, 0)
            NumPut("float", 0, rectA, 0)
            NumPut("float", 0, rectA, 4)
            NumPut("float", W, rectA, 8)
            NumPut("float", H, rectA, 12)
            ab := PathInkBounds(pG, TimeFont, AMPMSize, parts[6], rectA, fmtA)
            DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmtA)
            ; X: right after the time's right edge; Y: top-aligned with the time (upper-right corner)
            ampmX := tb[3] + AMPMGap - ab[1]
            ampmY := tb[2] - ab[2]
            if (ampmY < 0)
                ampmY := 0
            ; hint 4 (AntiAlias) so the small text has no ClearType color fringes
            DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", pG, "int", 4)
            DrawTextCentered(pG, fAMPM, parts[6], ampmY, AMPMAlpha, ampmX, 0, 0, "", 0, 0, AMPMColor)
            DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", pG, "int", 5)
        } catch {
        }
    }

    ; push to layered window
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

    ulwRet := DllCall("UpdateLayeredWindow", "ptr", hWnd, "ptr", hdcScreen, "ptr", ptDst
        , "ptr", size, "ptr", hdcMem, "ptr", ptSrc, "uint", 0, "ptr", bf, "uint", 2)

    DllCall("SelectObject", "ptr", hdcMem, "ptr", obm, "ptr")
    DllCall("DeleteDC", "ptr", hdcMem)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)
    DllCall("DeleteObject", "ptr", hBitmap)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", pG)
}

ToggleMode(*) {
    global Mode
    Mode := (Mode = "24H") ? "12H" : "24H"
    A_TrayMenu.Rename("Toggle 12/24H (" (Mode = "24H" ? "12H" : "24H") ")", "Toggle 12/24H (" Mode ")")
    Render()
}

ToggleBorder(*) {
    global UseBorder
    UseBorder := !UseBorder
    A_TrayMenu.Rename("Toggle Border (" (UseBorder ? "Off" : "On") ")", "Toggle Border (" (UseBorder ? "On" : "Off") ")")
    Render()
}

; ---- main loop ----
Render()
SetTimer(Render, 1000)
