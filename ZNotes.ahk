#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================
;  Z NOTES
;  A small dark desktop widget in the same style as ZGreeting /
;  ZClock: rounded corners, low opacity, red edge, no title bar.
;
;  Left  : the note list - click a row to open it, x on the row deletes
;  Right : the note itself - plain text, or a checklist
;
;  Drag any edge of the widget to move it. Everything auto-saves.
;  Close it from the tray icon (Show / Hide), reopen it from there too.
;
;  Data : %AppData%\ZNotes\notes\<id>.note   (plain text, one per note)
;         %AppData%\ZNotes\window.ini        (window position)
; =====================================================================

DllCall("SetProcessDPIAware")
CoordMode("Mouse", "Screen")        ; the widget does its maths in screen coords

; ----------------------------- config --------------------------------
global WIN_W        := 520
global WIN_H        := 300
global WidgetW      := WIN_W
global WidgetH      := WIN_H
global ACRYLIC_TINT_ALPHA := 90     ; a light tint over the active blur
global IDLE_ALPHA   := 26           ; about 10% opacity while inactive
global AUTOSAVE_MS  := 700          ; idle time before an edit is written

global C_BG     := 0x15171C         ; the one and only background colour
global C_LINE   := 0x2B303A
global C_TEXT   := 0xE6E6E6
global C_DIM    := 0x8C949E
global C_ACCENT := 0xE53935         ; same red as the greeting border
global C_SEL    := 0x24272E         ; the open row, a shade above the bg

global NotesRoot := A_AppData "\ZNotes"
global NotesDir  := NotesRoot "\notes"
global WinIni    := NotesRoot "\window.ini"

global BODY_MARK := "--body--"
global ITEM_MARK := "--items--"

; ----------------------------- layout --------------------------------
global LIST_X := 12, LIST_Y := 12, LIST_W := 150, LIST_H := 260
global NOTE_X := 182, NOTE_Y := 12, NOTE_W := 326, NOTE_H := 260
global CHECK_H := 212               ; checklist height, leaves room for the box
global ITEM_Y := 230                ; "new item" box in checklist mode
global ROW_XW := 26                 ; width of the per-row delete zone
global RAIL_W := 14                 ; width of the sidebar handle strip
global SIDE_X := 26                 ; note pane x when the list is put away
global EDGE := 12                   ; outer margin - also the drag ring
global BAR_H := 18                  ; height of the bottom link row
global BOT_PAD := 10                ; gap under the bottom link row
global ROW_GAP := 16                ; gap between the item box and the link row
global ITEM_H := 26                 ; height of the "new item" box
global GRIP := 14                   ; bottom corner resize grip
global MIN_W := 380
global MIN_H := 220

; ----------------------------- state ---------------------------------
global Notes := []                  ; array of note objects
global CurrentId := ""              ; id of the note in the editor
global ListRows := []               ; listview row -> note id
global Guard := false               ; suppress control events while rebuilding
global Dirty := false
global ListScrollable := true
global HoverLink := 0
global LinkBase := Map()            ; control hwnd -> base colour
global FocusTries := 0
global SidebarOn := true            ; is the notes list showing?
global ResizeOn := false            ; resize from the bottom corners?
global MovableOn := true            ; move from the widget edges?
global ResizeActive := false        ; a corner resize drag is in progress
global ResizeSide := 0
global RStartX := 0, RStartY := 0, RStartL := 0, RStartT := 0, RStartW := 0, RStartH := 0
global IsWidgetActive := -1         ; -1 = not applied yet (forces the first update)
global ListOld := Map()             ; listview hwnd -> previous window proc
global LinkOld := Map()             ; flat link hwnd -> previous window proc
global LinkAlign := Map()           ; flat link hwnd -> left/center/right
global LinkHandlers := Map()       ; flat link hwnd -> click handler
global LinkProcCB := 0
global AskResult := "", AskDone := false
global AskEditOld := 0, AskEditCB := 0

global g, lvNotes, lvCheck, edBody, edItem, ruleItem, divider
global lnkNew, lnkMode, lnkSide
global OldGuiProc, GuiProcCB, OldItemProc, ItemProcCB, OldBodyProc, BodyProcCB
global ListProcCB, NotesRowImages
global WheelHook := 0, WheelHookCB := 0

Hex(n) => Format("{:06X}", n)
BGR(c) => ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)

; =====================================================================
;  startup
; =====================================================================
DirCreate(NotesDir)
LoadUiPrefs()
BuildUi()
LoadAll()
ShowWindow()
InstallWheelHook()

A_TrayMenu.Delete()
A_TrayMenu.Add("Show / Hide", (*) => ToggleWindow())
A_TrayMenu.Add("New Note", (*) => (ShowWindow(), CreateNote()))
A_TrayMenu.Add()
A_TrayMenu.Add("Notes List Scrolling", ToggleListScrolling)
A_TrayMenu.Add("Resize Widget", ToggleResize)
A_TrayMenu.Add("Move Widget", ToggleMovability)
A_TrayMenu.Add()
A_TrayMenu.Add("Open Notes Folder", (*) => Run(NotesDir))
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show / Hide"
InitTrayChecks()
A_IconTip := "ZNotes"

#HotIf WinActive("ahk_id " g.Hwnd)
^s::SaveCurrent(true)
^n::CreateNote()
^w::HideWindow()
#HotIf

OnExit(SaveAndExit)
OnMessage(0x0200, OnMouseMove)      ; hover feedback for the flat links
OnMessage(0x0138, OnCtlColorStatic) ; keep flat links truly background-free
OnMessage(0x004E, OnNotify)         ; NM_CUSTOMDRAW -> rows drawn by us
OnMessage(0x0232, OnExitSizeMove)   ; WM_EXITSIZEMOVE -> remember the position
OnMessage(0x0006, OnActivate)       ; WM_ACTIVATE -> return to the desktop layer
SetTimer(UpdateWidgetAppearance, 200)

; =====================================================================
;  user interface
; =====================================================================
BuildUi() {
    global g, WIN_W, WIN_H
    global lvNotes, lvCheck, edBody, edItem, ruleItem, divider
    global lnkNew, lnkMode, lnkSide

    g := Gui("-Caption -AlwaysOnTop +ToolWindow +OwnDialogs +LastFound", "ZNotes")
    g.BackColor := Hex(C_BG)
    g.SetFont("s9", "Segoe UI")

    ; --- left column: the notes list ----------------------------------
    lvNotes := g.Add("ListView", "x" LIST_X " y" LIST_Y " w" LIST_W " h" LIST_H
                              " -Hdr -Multi -E0x200 Background" Hex(C_BG), ["Note"])
    lvNotes.SetFont("s9 c" Hex(C_TEXT), "Segoe UI")
    lvNotes.ModifyCol(1, LIST_W - 4)
    ThemeListView(lvNotes)
    ; A tall, blank small-image list gives report rows a little breathing room.
    ; It is kept globally because Windows owns only a reference to the image list.
    NotesRowImages := DllCall("comctl32\ImageList_Create", "int", 1, "int", 25,
                              "uint", 0x20, "int", 1, "int", 1, "ptr")
    SendMessage(0x1003, 1, NotesRowImages, lvNotes) ; LVM_SETIMAGELIST, LVSIL_SMALL
    lvNotes.OnEvent("ItemSelect", OnNoteSelect)
    lvNotes.OnEvent("DoubleClick", OnNoteDoubleClick)

    lnkNew := MakeLink("+ NEW", LIST_X, 276, 60, 18, (*) => CreateNote())

    divider := AddLine(170, LIST_Y, 1, LIST_H)

    ; --- right column: the note ---------------------------------------
    edBody := g.Add("Edit", "x" NOTE_X " y" NOTE_Y " w" NOTE_W " h" NOTE_H
                           " Background" Hex(C_BG) " c" Hex(C_TEXT)
                           " +Multi +WantReturn -VScroll -HScroll -E0x200")
    edBody.SetFont("s9", "Segoe UI")
    edBody.OnEvent("Change", OnBodyChange)

    lvCheck := g.Add("ListView", "x" NOTE_X " y" NOTE_Y " w" NOTE_W " h" CHECK_H
                                 " -Hdr -Multi -E0x200 Background" Hex(C_BG), ["Item"])
    lvCheck.SetFont("s9 c" Hex(C_TEXT), "Segoe UI")
    lvCheck.ModifyCol(1, NOTE_W - 4)
    ThemeListView(lvCheck)
    lvCheck.OnEvent("Click", OnCheckClick)
    lvCheck.OnEvent("DoubleClick", OnCheckDoubleClick)

    edItem := g.Add("Edit", "x" NOTE_X " y" ITEM_Y " w" NOTE_W " h26"
                            " Background" Hex(C_BG) " c" Hex(C_TEXT) " -E0x200")
    edItem.SetFont("s9", "Segoe UI")
    SetCue(edItem, "New item - Enter to add")
    ruleItem := AddLine(NOTE_X, ITEM_Y + 27, NOTE_W, 1)

    lnkMode := MakeLink("CHECKLIST", NOTE_X + NOTE_W - 96, 276, 96, 18,
                        (*) => ToggleMode(), "right")

    ; drawer handle, stuck to the left border
    lnkSide := MakeLink("<", 0, 124, RAIL_W, 56, (*) => ToggleSidebar(), "center")
    lnkSide.SetFont("s12 bold", "Segoe UI")
    lnkSide.Opt("+0x200")               ; SS_CENTERIMAGE - centre the glyph
    SetLinkColor(lnkSide, Hex(C_DIM))

    ; edges drag the window (the panels are real controls, so they keep clicks)
    SubclassHeader()
    ; Enter in the "new item" box adds the item
    SubclassItem()
    ; the note body has no scrollbar, so the wheel is handled here
    SubclassBody()
    ; ListView scrollbars stay hidden, so provide wheel scrolling ourselves
    ; and re-hide the bars whenever a list is shown, resized or refilled.
    SubclassLists()

    g.OnEvent("Close", (*) => HideWindow())
    g.OnEvent("Size", OnGuiSize)
}

; the note side grows into the space when the list is put away
ApplyLayout(cw := 0, ch := 0) {
    global g, SidebarOn, lvNotes, divider, lnkSide, lnkNew
    global edBody, lvCheck, edItem, ruleItem, lnkMode
    global WIN_W, WIN_H, LIST_X, LIST_Y, LIST_W, NOTE_Y, RAIL_W, SIDE_X, EDGE
    global BAR_H, BOT_PAD, ROW_GAP, ITEM_H, MIN_W, MIN_H
    if (cw <= 0 || ch <= 0) {
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "ptr", g.Hwnd, "ptr", rect)
        cw := NumGet(rect, 8, "int")
        ch := NumGet(rect, 12, "int")
    }
    if (cw <= 0)
        cw := WIN_W
    if (ch <= 0)
        ch := WIN_H
    cw := Max(MIN_W, cw)
    ch := Max(MIN_H, ch)

    ; vertical anchors, measured from the bottom of the widget
    itemY  := ch - BOT_PAD - BAR_H - ROW_GAP - ITEM_H
    ruleY  := itemY + ITEM_H + 1
    linkY  := ch - BOT_PAD - BAR_H
    listH  := Max(80, linkY - LIST_Y)
    checkH := Max(60, itemY - 6 - LIST_Y)

    ; left column
    lvNotes.Visible := SidebarOn
    divider.Visible := SidebarOn
    lnkNew.Visible := false
    lnkSide.Text := SidebarOn ? "<" : ">"
    lvNotes.Move(LIST_X, LIST_Y, LIST_W, listH)
    lnkNew.Move(LIST_X, linkY, 60, BAR_H)
    divider.Move(LIST_X + LIST_W + 8, LIST_Y, 1, listH)

    ; note column
    nx := SidebarOn ? LIST_X + LIST_W + 20 : SIDE_X
    nw := Max(160, cw - nx - EDGE)
    edBody.Move(nx, NOTE_Y, nw, listH)
    lvCheck.Move(nx, NOTE_Y, nw, checkH)
    lvCheck.ModifyCol(1, nw - 6)
    edItem.Move(nx, itemY, nw, ITEM_H)
    ruleItem.Move(nx, ruleY, nw, 1)
    lnkMode.Move(nx + nw - 96, linkY, 96, BAR_H)

    ; handle, vertically centred on the left border
    lnkSide.Move(0, Max(24, Floor((ch - 56) / 2)), RAIL_W, 56)

    ScheduleBarHide()
}

OnGuiSize(guiObj, minMax, width, height) {
    if (minMax != -1)
        ApplyLayout(width, height)
}

ToggleSidebar(*) {
    global SidebarOn, WinIni
    SidebarOn := !SidebarOn
    ApplyLayout()
    try IniWrite(SidebarOn ? 1 : 0, WinIni, "Ui", "list")
}

AddLine(x, y, w, h) {
    global g
    return g.Add("Text", "x" x " y" y " w" w " h" h " Background" Hex(C_LINE))
}

; Flat clickable label (native buttons are light-themed and clash).
MakeLink(text, x, y, w, h, handler, align := "") {
    global g
    opts := "x" x " y" y " w" w " h" h " BackgroundTrans"
    if (align != "")
        opts .= " " align
    c := g.Add("Text", opts, text)
    ; Make the transparency explicit as well as using BackgroundTrans in the
    ; options. This prevents the native static control from painting its own
    ; rectangle over the widget background.
    style := DllCall("GetWindowLongPtrW", "ptr", c.Hwnd, "int", -16, "ptr")
    DllCall("SetWindowLongPtrW", "ptr", c.Hwnd, "int", -16, "ptr", style | 0x20)
    exStyle := DllCall("GetWindowLongPtrW", "ptr", c.Hwnd, "int", -20, "ptr")
    DllCall("SetWindowLongPtrW", "ptr", c.Hwnd, "int", -20, "ptr", exStyle | 0x20)
    DllCall("RedrawWindow", "ptr", c.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x85)
    global LinkOld, LinkAlign, LinkProcCB
    if !LinkProcCB
        LinkProcCB := CallbackCreate(LinkProc, "Fast", 4)
    LinkOld[c.Hwnd] := DllCall("SetWindowLongPtrW", "ptr", c.Hwnd, "int", -4, "ptr", LinkProcCB, "ptr")
    LinkAlign[c.Hwnd] := (align = "" ? "left" : align)
    LinkHandlers[c.Hwnd] := handler
    ; Keep the native control only as a geometry/font holder. Child HWNDs can
    ; leave a composited rectangle on layered windows despite transparency.
    c.Visible := false
    c.SetFont("s9 bold", "Segoe UI")
    c.OnEvent("Click", handler)
    SetLinkColor(c, Hex(C_DIM))
    return c
}

SetLinkColor(ctrl, hex) {
    global LinkBase
    ctrl.SetFont("c" hex)
    LinkBase[ctrl.Hwnd] := hex
}

SetCue(ctrl, text) {
    SendMessage(0x1501, 0, StrPtr(text), ctrl)      ; EM_SETCUEBANNER
}

; ListView colours are per-control messages; lParam is a COLORREF (0xBBGGRR).
ThemeListView(lv) {
    global C_BG, C_TEXT
    PostMessage(0x1001, 0, BGR(C_BG), lv)                    ; LVM_SETBKCOLOR
    PostMessage(0x1024, 0, BGR(C_TEXT), lv)                  ; LVM_SETTEXTCOLOR
    PostMessage(0x1026, 0, BGR(C_BG), lv)                    ; LVM_SETTEXTBKCOLOR
    PostMessage(0x1036, 0x20 | 0x10000, 0x20 | 0x10000, lv)  ; FULLROWSELECT | DOUBLEBUFFER
    ; no visual theme: the themed list draws its own 2px frame, and we want a
    ; flat surface that sits directly on the widget background
    try DllCall("uxtheme\SetWindowTheme", "ptr", lv.Hwnd, "ptr", 0, "ptr", 0)
    ; the wheel still scrolls, but no bright system scrollbar is drawn
    ShowScrollBar(lv)
}

ShowScrollBar(lv) {
    try DllCall("ShowScrollBar", "ptr", lv.Hwnd, "int", 0, "int", 0)   ; SB_HORZ
    try DllCall("ShowScrollBar", "ptr", lv.Hwnd, "int", 1, "int", 0)   ; SB_VERT
}

; Windows re-creates a ListView's scroll bars whenever the control is shown,
; resized or refilled - even after ShowScrollBar. Ask again once the control
; has finished handling whatever re-created them.
HideBarsNow(*) {
    HideListScrollBars()
}

HideBarsLater(*) {
    HideListScrollBars()
}

ScheduleBarHide() {
    HideListScrollBars()                ; now, before anything can paint
    SetTimer(HideBarsNow, -1)           ; and again after the control settles
    SetTimer(HideBarsLater, -160)
}

; =====================================================================
;  window behaviour
; =====================================================================
SubclassHeader() {
    global g, OldGuiProc, GuiProcCB
    GuiProcCB := CallbackCreate(GuiProc, "Fast", 4)
    OldGuiProc := DllCall("SetWindowLongPtrW", "ptr", g.Hwnd, "int", -4, "ptr", GuiProcCB, "ptr")
}

SubclassItem() {
    global edItem, OldItemProc, ItemProcCB
    ItemProcCB := CallbackCreate(ItemProc, "Fast", 4)
    OldItemProc := DllCall("SetWindowLongPtrW", "ptr", edItem.Hwnd, "int", -4, "ptr", ItemProcCB, "ptr")
}

SubclassBody() {
    global edBody, OldBodyProc, BodyProcCB
    BodyProcCB := CallbackCreate(BodyProc, "Fast", 4)
    OldBodyProc := DllCall("SetWindowLongPtrW", "ptr", edBody.Hwnd, "int", -4, "ptr", BodyProcCB, "ptr")
}

SubclassLists() {
    global lvNotes, lvCheck, ListOld, ListProcCB
    ListProcCB := CallbackCreate(ListProc, "Fast", 4)
    for lv in [lvNotes, lvCheck]
        ListOld[lv.Hwnd] := DllCall("SetWindowLongPtrW", "ptr", lv.Hwnd, "int", -4, "ptr", ListProcCB, "ptr")
}

; Native static controls can still paint an opaque rectangle over a layered
; widget even when BackgroundTrans is set. Paint these three links ourselves:
; draw the label only and never erase/fill their client area.
LinkProc(h, m, w, l) {
    global LinkOld, LinkAlign, LinkBase, HoverLink, C_ACCENT
    if !LinkOld.Has(h)
        return 0
    old := LinkOld[h]
    if (m = 0x0014)                         ; WM_ERASEBKGND
        return 1
    if (m = 0x000F) {                       ; WM_PAINT
        ps := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
        hdc := DllCall("BeginPaint", "ptr", h, "ptr", ps, "ptr")
        if hdc {
            font := SendMessage(0x0031, 0, 0, h) ; WM_GETFONT
            oldFont := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
            DllCall("SetBkMode", "ptr", hdc, "int", 1) ; TRANSPARENT
            color := (HoverLink = h) ? C_ACCENT : Integer("0x" LinkBase[h])
            DllCall("SetTextColor", "ptr", hdc, "uint", BGR(color))
            rc := Buffer(16, 0)
            DllCall("GetClientRect", "ptr", h, "ptr", rc)
            ctrl := GuiCtrlFromHwnd(h)
            text := ctrl ? ctrl.Text : ""
            flags := 0x20 | 0x04 | 0x800       ; SINGLELINE|VCENTER|NOPREFIX
            if (LinkAlign[h] = "center")
                flags |= 0x1                    ; DT_CENTER
            else if (LinkAlign[h] = "right")
                flags |= 0x2                    ; DT_RIGHT
            DllCall("DrawTextW", "ptr", hdc, "wstr", text, "int", -1,
                    "ptr", rc, "uint", flags)
            if oldFont
                DllCall("SelectObject", "ptr", hdc, "ptr", oldFont)
            DllCall("EndPaint", "ptr", h, "ptr", ps)
        }
        return 0
    }
    return DllCall("CallWindowProcW", "ptr", old, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
}

BodyProc(h, m, w, l) {
    global OldBodyProc
    if (m = 0x020A) {                       ; WM_MOUSEWHEEL
        MouseGetPos(, , , &ctl, 2)
        if (ctl && ctl != h) {              ; wheel over a list scrolls that list
            SendMessage(0x020A, w, l, ctl)
            return 0
        }
        d := (w >> 16) & 0xFFFF
        if (d > 32767)
            d -= 65536
        SendMessage(0x00B6, 0, (d > 0 ? -3 : 3), h)     ; EM_LINESCROLL
        return 0
    }
    return DllCall("CallWindowProcW", "ptr", OldBodyProc, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
}

; Both lists share one window proc: the notes list gets our own wheel
; scrolling, and any list gets its scroll bars re-hidden after the messages
; that make Windows draw them again.
ListProc(h, m, w, l) {
    global ListOld, ListScrollable, lvNotes
    if !ListOld.Has(h)
        return 0
    old := ListOld[h]
    if (m = 0x020A) {                       ; WM_MOUSEWHEEL
        ; A ListView scrolls with the wheel only while its vertical scroll bar
        ; exists; ours are hidden, so the content is moved directly instead.
        if (h = lvNotes.Hwnd && !ListScrollable)
            return 0
        d := (w >> 16) & 0xFFFF
        if (d > 32767)
            d -= 65536
        ScrollListBy(h, (d > 0) ? -3 : 3)
        return 0
    }
    if (m = 0x0100 && (w = 0x21 || w = 0x22)) {  ; PgUp / PgDn
        if (h = lvNotes.Hwnd && !ListScrollable)
            return 0
        ScrollListBy(h, (w = 0x21) ? -8 : 8)
        return 0
    }
    ret := DllCall("CallWindowProcW", "ptr", old, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
    ; WM_SIZE, WM_NCCALCSIZE, WM_SHOWWINDOW, WM_H/VSCROLL, WM_KEYDOWN
    if (m = 0x0005 || m = 0x0083 || m = 0x0018 || m = 0x0114 || m = 0x0115 || m = 0x0100)
        ScheduleBarHide()
    return ret
}

; Scroll a ListView that has no scroll bar: LVM_SCROLL moves the content by
; pixels, and it keeps working where WM_VSCROLL needs a real scroll bar.
ScrollListBy(h, lines) {
    row := 20
    rc := Buffer(16, 0)
    NumPut("int", 0, rc, 0)                     ; left field selects the item
    NumPut("int", 1, rc, 4)                     ; top field = LVIR_BOUNDS
    if SendMessage(0x100E, 0, rc, h) {          ; LVM_GETITEMRECT, item 0
        v := NumGet(rc, 12, "int") - NumGet(rc, 4, "int")
        if (v >= 8 && v <= 200)
            row := v
    }
    SendMessage(0x1014, 0, lines * row, h)       ; LVM_SCROLL
    HideListScrollBars()
    SetTimer(HideBarsLater, -160)
}

ItemProc(h, m, w, l) {
    global OldItemProc
    ; Any of these means "Enter was pressed". A real key press sends key-down
    ; and then char; the box is already empty by the second one, so nothing
    ; is added twice.
    if ((m = 0x0100 || m = 0x0101 || m = 0x0102) && w = 0x0D) {
        AddCheckItem()
        return 0
    }
    return DllCall("CallWindowProcW", "ptr", OldItemProc, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
}

; The window has no caption, so the bare edges act as the drag handle.
GuiProc(h, m, w, l) {
    global OldGuiProc, LIST_Y, SidebarOn, ResizeOn, MovableOn, GRIP, EDGE, MIN_W, MIN_H
    global ResizeActive, lvCheck, lvNotes, edBody
    if (m = 0x00A3)                         ; WM_NCLBUTTONDBLCLK
        return 0                            ; never maximise
    if (m = 0x00A1) {                       ; WM_NCLBUTTONDOWN
        ; a captionless window has no sizing frame, so the two corner grips
        ; are resized here instead of by DefWindowProc
        if (ResizeOn && (w = 16 || w = 17)) {
            StartCornerResize(w)
            return 0
        }
    }
    if (ResizeActive) {
        if (m = 0x0200) {                   ; WM_MOUSEMOVE
            TrackCornerResize()
            return 0
        }
        if (m = 0x0202) {                   ; WM_LBUTTONUP
            EndCornerResize()
            return 0
        }
        if (m = 0x0215) {                   ; WM_CAPTURECHANGED
            ResizeActive := false
            return 0
        }
    }
    if (m = 0x000F) {                       ; WM_PAINT
        ret := DllCall("CallWindowProcW", "ptr", OldGuiProc, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
        DrawLinks(h)
        return ret
    }
    if (m = 0x0202) {                       ; WM_LBUTTONUP
        x := l & 0xFFFF
        y := (l >> 16) & 0xFFFF
        if (x > 32767)
            x -= 65536
        if (y > 32767)
            y -= 65536
        link := LinkAtPoint(x, y)
        if link {
            global LinkHandlers
            try LinkHandlers[link]()
            return 0
        }
    }
    if (m = 0x020A) {                       ; WM_MOUSEWHEEL
        ; The wheel lands on the focused window, but the user expects the list
        ; under the pointer to scroll - route it there.
        MouseGetPos(, , , &ctl, 2)
        if (ctl && (ctl = lvCheck.Hwnd || ctl = lvNotes.Hwnd || ctl = edBody.Hwnd)) {
            SendMessage(0x020A, w, l, ctl)
            return 0
        }
    }
    if (m = 0x0024) {                       ; WM_GETMINMAXINFO
        ; let Windows fill the defaults, then only shrink the minimum size
        DllCall("CallWindowProcW", "ptr", OldGuiProc, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
        NumPut("int", MIN_W, "int", MIN_H, l, 24) ; ptMinTrackSize.x / .y
        return 0
    }
    if (m = 0x0084) {                       ; WM_NCHITTEST
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "ptr", pt)
        DllCall("ScreenToClient", "ptr", h, "ptr", pt)
        x := NumGet(pt, 0, "int")
        y := NumGet(pt, 4, "int")
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "ptr", h, "ptr", rc)
        cw := NumGet(rc, 8, "int"), ch := NumGet(rc, 12, "int")
        if LinkAtPoint(x, y)
            return 1                        ; clickable painted link
        ; resizing is opt-in and only from the two bottom corners
        if (ResizeOn) {
            if (y >= ch - GRIP && x <= GRIP)
                return 16                    ; HTBOTTOMLEFT
            if (y >= ch - GRIP && x >= cw - GRIP)
                return 17                    ; HTBOTTOMRIGHT
        }
        gap := (SidebarOn && x > 160 && x < 182 && y > LIST_Y && y < ch - 40)
        if (MovableOn && (x < EDGE || y < EDGE || x > cw - EDGE || y > ch - EDGE || gap))
            return 2                        ; HTCAPTION
    }
    return DllCall("CallWindowProcW", "ptr", OldGuiProc, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
}

LinkAtPoint(x, y) {
    global lnkNew, lnkMode, lnkSide, SidebarOn
    for c in [lnkNew, lnkMode, lnkSide] {
        if (c = lnkNew && !SidebarOn)
            continue
        c.GetPos(&cx, &cy, &cw, &ch)
        if (x >= cx && y >= cy && x < cx + cw && y < cy + ch)
            return c.Hwnd
    }
    return 0
}

DrawLinks(h) {
    global lnkNew, lnkMode, lnkSide, SidebarOn, LinkAlign, LinkBase, HoverLink, C_ACCENT
    hdc := DllCall("GetDC", "ptr", h, "ptr")
    if !hdc
        return
    DllCall("SetBkMode", "ptr", hdc, "int", 1)
    for c in [lnkNew, lnkMode, lnkSide] {
        if (c = lnkNew && !SidebarOn)
            continue
        c.GetPos(&x, &y, &w, &ht)
        font := SendMessage(0x0031, 0, 0, c)
        oldFont := font ? DllCall("SelectObject", "ptr", hdc, "ptr", font, "ptr") : 0
        color := (HoverLink = c.Hwnd) ? C_ACCENT : Integer("0x" LinkBase[c.Hwnd])
        DllCall("SetTextColor", "ptr", hdc, "uint", BGR(color))
        rc := Buffer(16, 0)
        NumPut("int", x, "int", y, "int", x + w, "int", y + ht, rc)
        flags := 0x20 | 0x04 | 0x800       ; SINGLELINE|VCENTER|NOPREFIX
        if (LinkAlign[c.Hwnd] = "center")
            flags |= 0x1
        else if (LinkAlign[c.Hwnd] = "right")
            flags |= 0x2
        DllCall("DrawTextW", "ptr", hdc, "wstr", c.Text, "int", -1,
                "ptr", rc, "uint", flags)
        if oldFont
            DllCall("SelectObject", "ptr", hdc, "ptr", oldFont)
    }
    DllCall("ReleaseDC", "ptr", h, "ptr", hdc)
}

; ---- bottom corner resizing -----------------------------------------
StartCornerResize(side) {
    global g, ResizeActive, ResizeSide
    global RStartX, RStartY, RStartL, RStartT, RStartW, RStartH
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    RStartX := NumGet(pt, 0, "int")
    RStartY := NumGet(pt, 4, "int")
    WinGetPos(&x, &y, &w, &h, "ahk_id " g.Hwnd)
    RStartL := x, RStartT := y, RStartW := w, RStartH := h
    ResizeSide := side
    ResizeActive := true
    DllCall("SetCapture", "ptr", g.Hwnd)
}

TrackCornerResize() {
    global g, ResizeSide
    global RStartX, RStartY, RStartL, RStartT, RStartW, RStartH, MIN_W, MIN_H
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    dx := NumGet(pt, 0, "int") - RStartX
    dy := NumGet(pt, 4, "int") - RStartY
    if (ResizeSide = 16) {                  ; bottom-left: the left edge moves
        w := Max(MIN_W, RStartW - dx)
        h := Max(MIN_H, RStartH + dy)
        x := RStartL + (RStartW - w)
        y := RStartT
    } else {                                ; bottom-right: the right edge moves
        w := Max(MIN_W, RStartW + dx)
        h := Max(MIN_H, RStartH + dy)
        x := RStartL
        y := RStartT
    }
    DllCall("SetWindowPos", "ptr", g.Hwnd, "ptr", 0, "int", x, "int", y,
            "int", w, "int", h, "uint", 0x0014) ; NOZORDER | NOACTIVATE
    ; keep the diagonal cursor while the grip is being dragged
    DllCall("SetCursor", "ptr", DllCall("LoadCursorW", "ptr", 0, "ptr",
            ResizeSide = 16 ? 32643 : 32642, "ptr"))
}

EndCornerResize() {
    global g, ResizeActive
    ResizeActive := false
    DllCall("ReleaseCapture")
    SaveBounds()
}

ShowWindow() {
    global g, WIN_W, WIN_H, WidgetW, WidgetH, WinIni, IsWidgetActive, IDLE_ALPHA
    global MIN_W, MIN_H
    x := "", y := ""
    if FileExist(WinIni) {
        x := IniRead(WinIni, "Window", "x", "")
        y := IniRead(WinIni, "Window", "y", "")
        WidgetW := Max(MIN_W, IniRead(WinIni, "Window", "w", WIN_W) + 0)
        WidgetH := Max(MIN_H, IniRead(WinIni, "Window", "h", WIN_H) + 0)
    }
    ApplyLayout()
    onScreen := false
    if (x != "" && y != "") {
        x := x + 0
        y := y + 0
        onScreen := (x > -WidgetW + 200 && y > -1 && x < A_ScreenWidth - 200 && y < A_ScreenHeight - 100)
    }
    ; Start as the quiet desktop presence: no blur, idle opacity. Hovering or
    ; focusing it switches the blur on (see UpdateWidgetAppearance).
    SetAcrylicBackdrop(false)
    WinSetTransparent(IDLE_ALPHA, g.Hwnd)
    if onScreen
        g.Show("w" WidgetW " h" WidgetH " x" x " y" y " NoActivate")
    else
        g.Show("w" WidgetW " h" WidgetH " Center NoActivate")
    RoundCorners(g)
    ShowMode(CurrentNote() ? CurrentNote().mode : "text")
    IsWidgetActive := -1
    UpdateWidgetAppearance()            ; match the pointer if it is already over us
    SetTimer(HideBarsNow, -50)
    SetTimer(HideBarsLater, -320)
    SetTimer(KeepOnDesktop, -50)
}

HideWindow() {
    global g
    SaveCurrent(true)
    SaveBounds()
    g.Hide()
}

ToggleWindow() {
    global g
    if DllCall("IsWindowVisible", "ptr", g.Hwnd)
        HideWindow()
    else
        ShowWindow()
}

ToggleListScrolling(*) {
    global ListScrollable, WinIni
    ListScrollable := !ListScrollable
    try IniWrite(ListScrollable ? 1 : 0, WinIni, "Ui", "scroll")
    SetMenuCheck("Notes List Scrolling", ListScrollable)
}

ToggleResize(*) {
    global ResizeOn, WinIni
    ResizeOn := !ResizeOn
    try IniWrite(ResizeOn ? 1 : 0, WinIni, "Ui", "resize")
    SetMenuCheck("Resize Widget", ResizeOn)
}

ToggleMovability(*) {
    global MovableOn, WinIni
    MovableOn := !MovableOn
    try IniWrite(MovableOn ? 1 : 0, WinIni, "Ui", "move")
    SetMenuCheck("Move Widget", MovableOn)
}

SetMenuCheck(name, on) {
    try {
        if on
            A_TrayMenu.Check(name)
        else
            A_TrayMenu.Uncheck(name)
    }
}

InitTrayChecks() {
    global ListScrollable, ResizeOn, MovableOn
    SetMenuCheck("Notes List Scrolling", ListScrollable)
    SetMenuCheck("Resize Widget", ResizeOn)
    SetMenuCheck("Move Widget", MovableOn)
}

LoadUiPrefs() {
    global ListScrollable, ResizeOn, MovableOn, SidebarOn, WinIni
    if FileExist(WinIni) {
        SidebarOn := IniRead(WinIni, "Ui", "list", "1") = "1"
        ListScrollable := IniRead(WinIni, "Ui", "scroll", "1") = "1"
        ResizeOn := IniRead(WinIni, "Ui", "resize", "0") = "1"
        MovableOn := IniRead(WinIni, "Ui", "move", "1") = "1"
    }
}

RoundCorners(guiObj) {
    h := guiObj.Hwnd
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", h, "int", 33, "int*", 2, "int", 4)         ; rounded
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", h, "int", 34, "int*", 0x00E53935, "int", 4) ; red frame
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", h, "int", 20, "int*", 1, "int", 4)         ; dark
}

HideListScrollBars(*) {
    global lvNotes, lvCheck
    ShowScrollBar(lvNotes)
    ShowScrollBar(lvCheck)
}

OnActivate(*) {
    SetTimer(KeepOnDesktop, -10)
    UpdateWidgetAppearance()
}

KeepOnDesktop(*) {
    global g
    ; HWND_BOTTOM keeps the widget above the desktop but below normal windows.
    DllCall("SetWindowPos", "ptr", g.Hwnd, "ptr", 1, "int", 0, "int", 0,
            "int", 0, "int", 0, "uint", 0x213)
}

IsWidgetHovered() {
    global g
    ; Anywhere inside the widget counts as hover, including the empty margins
    ; between the controls (which have no child window of their own).
    MouseGetPos(&mx, &my)
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " g.Hwnd)
    return mx >= wx && my >= wy && mx < wx + ww && my < wy + wh
}

UpdateWidgetAppearance(*) {
    global g, IDLE_ALPHA, IsWidgetActive
    ; Hovering and editing are the same visual state: full acrylic.  All
    ; other times the widget is a quiet, blur-free 10% desktop presence.
    active := IsWidgetHovered() || WinActive("ahk_id " g.Hwnd)
    if (active = IsWidgetActive)
        return
    if active {
        SetAcrylicBackdrop(true)
        WinSetTransparent(255, g.Hwnd)
    } else {
        SetAcrylicBackdrop(false)
        WinSetTransparent(IDLE_ALPHA, g.Hwnd)
    }
    IsWidgetActive := active
}

SetAcrylicBackdrop(enabled) {
    global g, C_BG, ACRYLIC_TINT_ALPHA
    accent := Buffer(16, 0)
    NumPut("int", enabled ? 4 : 0, accent, 0) ; ACCENT_ENABLE_ACRYLICBLURBEHIND / disabled
    ; The acrylic tint carries the normal opacity; the window itself remains
    ; opaque while active so Windows can render the blur behind it.
    NumPut("uint", enabled ? ((ACRYLIC_TINT_ALPHA << 24) | BGR(C_BG)) : 0, accent, 8)
    data := Buffer(A_PtrSize = 8 ? 24 : 12, 0)
    NumPut("int", 19, data, 0)               ; WCA_ACCENT_POLICY
    NumPut("ptr", accent.Ptr, data, A_PtrSize = 8 ? 8 : 4)
    NumPut("uptr", accent.Size, data, A_PtrSize = 8 ? 16 : 8)
    try DllCall("user32\SetWindowCompositionAttribute", "ptr", g.Hwnd, "ptr", data)
}

SaveBounds(*) {
    global g, WinIni, NotesRoot, WidgetW, WidgetH
    try {
        WinGetPos(&x, &y, &WidgetW, &WidgetH, "ahk_id " g.Hwnd)
        if (x = "" || y = "")
            return
        DirCreate(NotesRoot)
        IniWrite(x, WinIni, "Window", "x")
        IniWrite(y, WinIni, "Window", "y")
        IniWrite(WidgetW, WinIni, "Window", "w")
        IniWrite(WidgetH, WinIni, "Window", "h")
    }
}

OnExitSizeMove(*) {
    SaveBounds()
}

SaveAndExit(*) {
    SaveCurrent(true)
    SaveBounds()
    RemoveWheelHook()
    return 0
}

; The widget never activates, so Windows sends the wheel to whichever app has
; focus. This low-level hook hands the wheel to the control under the pointer
; while it is over the widget.
InstallWheelHook() {
    global WheelHook, WheelHookCB
    if WheelHook
        return
    WheelHookCB := CallbackCreate(WheelHookProc, "Fast", 3)
    WheelHook := DllCall("SetWindowsHookExW", "int", 14, "ptr", WheelHookCB, "ptr", 0, "uint", 0, "ptr")
}

RemoveWheelHook(*) {
    global WheelHook
    if !WheelHook
        return
    DllCall("UnhookWindowsHookEx", "ptr", WheelHook)
    WheelHook := 0
}

WheelHookProc(nCode, wParam, lParam) {
    global g, lvCheck, lvNotes, edBody, edItem
    if (nCode < 0 || wParam != 0x020A)
        return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    x := NumGet(pt, 0, "int"), y := NumGet(pt, 4, "int")
    if !DllCall("IsWindowVisible", "ptr", g.Hwnd)
        return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " g.Hwnd)
    if (x < wx || y < wy || x >= wx + ww || y >= wy + wh)
        return DllCall("CallNextHookEx", "ptr", 0, "int", nCode, "ptr", wParam, "ptr", lParam)
    d := (NumGet(lParam, 8, "uint") >> 16) & 0xFFFF
    if (d > 32767)
        d -= 65536
    SendMessage(0x020A, d << 16, 0, ControlAtPoint(x, y))
    return 1
}

; Child windows of a layered window are invisible to WindowFromPoint, so the
; wheel target is picked by comparing the pointer with the controls' rectangles.
ControlAtPoint(x, y) {
    global g, lvCheck, lvNotes, edBody, edItem
    for c in [edBody, lvCheck, lvNotes, edItem] {
        if !c.Visible
            continue
        WinGetPos(&cx, &cy, &cw, &ch, "ahk_id " c.Hwnd)
        if (x >= cx && y >= cy && x < cx + cw && y < cy + ch)
            return c.Hwnd
    }
    return g.Hwnd
}

; ListViews are themed light by Windows and their selection colour is the
; system highlight. Paint the rows (and the little delete x) ourselves.
OnNotify(wParam, lParam, msg, hwnd) {
    global lvNotes, lvCheck, C_BG, C_SEL, C_TEXT, C_DIM, ROW_XW
    if (NumGet(lParam, A_PtrSize * 2, "int") != -12)        ; NM_CUSTOMDRAW
        return
    from := NumGet(lParam, 0, "ptr")
    if (from != lvNotes.Hwnd && from != lvCheck.Hwnd)
        return
    stage := NumGet(lParam, A_PtrSize * 3, "uint")
    if (stage = 0x1)                                        ; CDDS_PREPAINT
        return 0x20                                         ; CDRF_NOTIFYITEMDRAW
    if (stage != 0x10001)                                   ; CDDS_ITEMPREPAINT
        return
    lv := (from = lvNotes.Hwnd) ? lvNotes : lvCheck
    hdc := NumGet(lParam, A_PtrSize * 4, "ptr")
    item := NumGet(lParam, A_PtrSize * 7, "uptr")
    state := NumGet(lParam, A_PtrSize * 8, "uint")
    sel := (state & 0x1)
    rc := Buffer(16, 0)
    NumPut("int", NumGet(lParam, 40, "int") + 6, "int", NumGet(lParam, 44, "int"),
           "int", NumGet(lParam, 48, "int") - ROW_XW, "int", NumGet(lParam, 52, "int"), rc)
    fill := Buffer(16, 0)
    NumPut("int", NumGet(lParam, 40, "int"), "int", NumGet(lParam, 44, "int"),
           "int", NumGet(lParam, 48, "int"), "int", NumGet(lParam, 52, "int"), fill)
    ; Selection is tracked for navigation, but the list remains visually flat.
    bg := C_BG
    br := DllCall("CreateSolidBrush", "uint", BGR(bg), "ptr")
    DllCall("FillRect", "ptr", hdc, "ptr", fill, "ptr", br)
    DllCall("DeleteObject", "ptr", br)
    DllCall("SetBkMode", "ptr", hdc, "int", 1)               ; TRANSPARENT
    DllCall("SetTextColor", "ptr", hdc, "uint", BGR(C_TEXT))
    DllCall("DrawTextW", "ptr", hdc, "wstr", lv.GetText(item + 1), "int", -1,
           "ptr", rc, "uint", 0x8824)                        ; SINGLELINE|VCENTER|NOPREFIX|ELLIPSIS

    ; delete x on the right edge of the row
    xr := Buffer(16, 0)
    NumPut("int", NumGet(lParam, 48, "int") - 22, "int", NumGet(lParam, 44, "int"),
           "int", NumGet(lParam, 48, "int") - 8, "int", NumGet(lParam, 52, "int"), xr)
    DllCall("SetTextColor", "ptr", hdc, "uint", BGR(C_DIM))
    DllCall("DrawTextW", "ptr", hdc, "wstr", Chr(215), "int", -1,
           "ptr", xr, "uint", 0x8826)                        ; + RIGHT
    return 0x04                                              ; CDRF_SKIPDEFAULT
}

; =====================================================================
;  notes storage
; =====================================================================
NotePath(id) {
    global NotesDir
    return NotesDir "\" id ".note"
}

SafeLine(s) => StrReplace(StrReplace(s, "`r", " "), "`n", " ")

EmptyNote(id) {
    return {id: id, title: "", mode: "text", created: "", updated: "",
            body: "", items: [], seeded: false}
}

NewId() {
    global NotesDir
    base := FormatTime(, "yyyyMMddHHmmss")
    id := base
    n := 1
    while FileExist(NotesDir "\" id ".note") {
        n++
        id := base "-" n
    }
    return id
}

LoadAll() {
    global Notes, NotesDir, CurrentId
    Notes := []
    DirCreate(NotesDir)
    loop files, NotesDir "\*.note" {
        try
            Notes.Push(ReadNote(A_LoopFilePath))
    }
    SortNotes()
    if (Notes.Length = 0) {
        n := EmptyNote(NewId())
        n.created := FormatTime(, "yyyyMMddHHmmss")
        n.updated := n.created
        Notes.Push(n)
        WriteNote(n)
    }
    CurrentId := Notes[1].id
    RefreshList()
    LoadIntoEditor(Notes[1])
}

ReadNote(path) {
    global BODY_MARK, ITEM_MARK
    text := FileRead(path, "UTF-8")
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    id := RegExReplace(path, ".*[\\/](.+?)\.note$", "$1")
    n := EmptyNote(id)
    section := "head"
    body := []
    seenSeeded := false
    loop parse, text, "`n", "`r" {
        line := A_LoopField
        if (section = "head") {
            if (line = BODY_MARK) {
                section := "body"
                continue
            }
            if (line = ITEM_MARK) {
                section := "items"
                continue
            }
            if InStr(line, "=") {
                key := SubStr(line, 1, InStr(line, "=") - 1)
                val := SubStr(line, InStr(line, "=") + 1)
                if (key = "mode")
                    n.mode := val
                else if (key = "created")
                    n.created := val
                else if (key = "updated")
                    n.updated := val
                else if (key = "seeded") {
                    n.seeded := (val = "1")
                    seenSeeded := true
                }
            }
            continue
        }
        if (section = "body") {
            ; only the items marker ends the body; a body line that looks like
            ; one is stored with a leading backslash (see EscapeBodyLine)
            if (line = ITEM_MARK) {
                section := "items"
                continue
            }
            if (SubStr(line, 1, 1) = "\" && SubStr(line, 2) = ITEM_MARK)
                line := SubStr(line, 2)
            body.Push(line)
            continue
        }
        prefix := SubStr(line, 1, 2)
        txt := (prefix = "1|" || prefix = "0|") ? SubStr(line, 3) : line
        if (Trim(txt) != "")
            n.items.Push({text: txt, done: prefix = "1|"})
    }
    while (body.Length && body[body.Length] = "")
        body.RemoveAt(body.Length)
    for line in body
        n.body .= (n.body = "" ? "" : "`n") line
    if (n.mode != "text" && n.mode != "check")
        n.mode := "text"
    ; Notes written before the flag existed: an existing checklist has already
    ; been filled once, so it must not be filled again from its text.
    if (!seenSeeded && n.mode = "check")
        n.seeded := true
    return n
}

; A body line that looks like a section marker would cut the note short on the
; next read, so it is stored with one leading backslash (and unescaped again by
; ReadNote).  Only the items marker can end the body section.
EscapeBodyLine(line) {
    global ITEM_MARK
    bare := (SubStr(line, 1, 1) = "\") ? SubStr(line, 2) : line
    return (bare = ITEM_MARK) ? "\" line : line
}

EscapeBody(s) {
    out := ""
    loop parse, s, "`n", "`r"
        out .= (out = "" ? "" : "`n") EscapeBodyLine(A_LoopField)
    return out
}

WriteNote(n) {
    global NotesDir, BODY_MARK, ITEM_MARK
    DirCreate(NotesDir)
    path := NotesDir "\" n.id ".note"
    tmp := path ".tmp"
    try FileDelete(tmp)
    f := FileOpen(tmp, "w", "UTF-8-RAW")
    if !f
        throw Error("cannot write " n.id ".note")
    f.Write("title=" SafeLine(ListName(n)) "`n")
    f.Write("mode=" n.mode "`n")
    f.Write("created=" n.created "`n")
    f.Write("updated=" n.updated "`n")
    f.Write("seeded=" (n.seeded ? 1 : 0) "`n")
    f.Write(BODY_MARK "`n")
    if (n.body != "")
        f.Write(EscapeBody(n.body) "`n")
    f.Write(ITEM_MARK "`n")
    for it in n.items
        f.Write((it.done ? "1|" : "0|") SafeLine(it.text) "`n")
    f.Close()
    ; Write beside the note first, then swap it in: a crash or a full disk in
    ; the middle of a save cannot leave a half-written note behind.
    try FileMove(tmp, path, 1)
}

SortNotes() {
    global Notes
    loop Notes.Length - 1 {
        i := A_Index
        j := i + 1
        key := Notes[j]
        while (i >= 1 && Notes[i].updated < key.updated) {
            Notes[i + 1] := Notes[i]
            i--
        }
        Notes[i + 1] := key
    }
}

CurrentNote() {
    global Notes, CurrentId
    for n in Notes
        if (n.id = CurrentId)
            return n
    return 0
}

NoteById(id) {
    global Notes
    for n in Notes
        if (n.id = id)
            return n
    return 0
}

; a note has no title of its own - its name is the first thing in it
FirstLine(s) {
    loop parse, s, "`n", "`r"
        if (Trim(A_LoopField) != "")
            return Trim(A_LoopField)
    return ""
}

FirstItem(n) {
    for it in n.items
        if (Trim(it.text) != "")
            return Trim(it.text)
    return ""
}

Shorten(s, max) {
    s := Trim(RegExReplace(s, "\s+", " "))
    return (StrLen(s) > max) ? Substr(s, 1, max - 3) "..." : s
}

ListName(n) {
    s := (n.mode = "check") ? FirstItem(n) : FirstLine(n.body)
    return (s = "") ? "(empty note)" : Shorten(s, 24)
}

; =====================================================================
;  list + editor
; =====================================================================
RefreshList() {
    global lvNotes, ListRows, Guard, CurrentId, Notes
    Guard := true
    lvNotes.Delete()
    ListRows := []
    for n in Notes {
        lvNotes.Add(, ListName(n))
        ListRows.Push(n.id)
    }
    row := 0
    for i, id in ListRows
        if (id = CurrentId) {
            row := i
            break
        }
    if (row > 0)
        lvNotes.Modify(row, "Vis Focus")
    Guard := false
    ; The initial selection can be painted by the native ListView before its
    ; custom-draw pass runs. Force the whole list through that pass now so the
    ; current note never shows the system white selection background.
    DllCall("RedrawWindow", "ptr", lvNotes.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x85)
    ScheduleBarHide()
}

; keep the open row's label in step with the text being typed
SyncListName() {
    global lvNotes, ListRows, CurrentId, Guard
    n := CurrentNote()
    if !n
        return
    for i, id in ListRows {
        if (id = CurrentId) {
            Guard := true
            lvNotes.Modify(i, , ListName(n))
            Guard := false
            return
        }
    }
}

LoadIntoEditor(n) {
    global edBody, Guard
    Guard := true
    edBody.Value := n.body
    Guard := false
    ShowMode(n.mode)
    RefreshChecklist()
}

OpenNoteById(id) {
    global CurrentId
    n := NoteById(id)
    if !n
        return
    SaveCurrent()
    CurrentId := id
    LoadIntoEditor(n)
}

OnNoteSelect(*) {
    global lvNotes, Guard, ListRows, CurrentId
    if Guard
        return
    row := lvNotes.GetNext(0, "F")
    if (row < 1 || row > ListRows.Length)
        return
    if (ListRows[row] != CurrentId)
        OpenNoteById(ListRows[row])
    ; The note list is a flat navigation surface, not a selected-item list.
    ; Remove the native selection immediately so Windows cannot paint a white
    ; row behind the current note.
    Guard := true
    lvNotes.Modify(row, "-Select")
    Guard := false
}

OnNoteDoubleClick(*) {
    global lvNotes, Guard
    if Guard
        return
    row := RowAt(lvNotes)
    if (row < 1)
        return
    if OverRight(lvNotes)
        DeleteRowNote(row)
}

CreateNote(*) {
    global Notes, CurrentId, FocusTries
    SaveCurrent(true)
    n := EmptyNote(NewId())
    n.created := n.updated := FormatTime(, "yyyyMMddHHmmss")
    Notes.InsertAt(1, n)
    WriteNote(n)
    CurrentId := n.id
    RefreshList()
    LoadIntoEditor(n)
    FocusTries := 0
    SetTimer(FocusBody, -30)
}

; the click that started this finishes after the handler and would take the
; focus back, so try again on the next message passes until it sticks
FocusBody() {
    global g, edBody, FocusTries
    if (DllCall("GetFocus", "ptr") = edBody.Hwnd)
        return
    if !WinActive("ahk_id " g.Hwnd)
        WinActivate("ahk_id " g.Hwnd)
    edBody.Focus()
    if (DllCall("GetFocus", "ptr") != edBody.Hwnd && FocusTries < 15) {
        FocusTries++
        SetTimer(FocusBody, -30)
    }
}

DeleteRowNote(row) {
    global Notes, CurrentId, Dirty, ListRows
    if (row < 1 || row > ListRows.Length)
        return
    id := ListRows[row]
    n := NoteById(id)
    if !n
        return
    SaveCurrent(true)
    try FileDelete(NotePath(id))
    for i, x in Notes
        if (x.id = id) {
            Notes.RemoveAt(i)
            break
        }
    Dirty := false
    if (Notes.Length = 0) {
        CreateNote()
        return
    }
    if (id = CurrentId) {
        CurrentId := Notes[1].id
        LoadIntoEditor(Notes[1])
    }
    RefreshList()
}

OnBodyChange(*) {
    global edBody, Guard
    if Guard
        return
    n := CurrentNote()
    if !n
        return
    n.body := StrReplace(StrReplace(edBody.Value, "`r`n", "`n"), "`r", "`n")
    SyncListName()
    MarkDirty()
}

MarkDirty() {
    global Dirty, AUTOSAVE_MS
    Dirty := true
    SetTimer(SaveCurrent, -AUTOSAVE_MS)
}

SaveCurrent(force := false) {
    global Dirty
    n := CurrentNote()
    if !n
        return
    if (!Dirty && !force)
        return
    n.updated := FormatTime(, "yyyyMMddHHmmss")
    try WriteNote(n)
    Dirty := false
    SyncListName()
}

; =====================================================================
;  text / checklist
; =====================================================================
ShowMode(mode) {
    global edBody, lvCheck, edItem, ruleItem, lnkMode
    isText := (mode = "text")
    edBody.Visible := isText
    lvCheck.Visible := !isText
    edItem.Visible := !isText
    ruleItem.Visible := !isText
    lnkMode.Text := isText ? "CHECKLIST" : "TEXT"
    SetLinkColor(lnkMode, Hex(C_DIM))
    ; showing or hiding a control changes where the list sits and how tall it
    ; is, and Windows re-creates its scroll bars on every show: lay the pane
    ; out again and hide the bars afterwards
    ApplyLayout()
}

ToggleMode(*) {
    n := CurrentNote()
    if !n
        return
    SetMode(n.mode = "text" ? "check" : "text")
}

SetMode(mode) {
    global edBody
    n := CurrentNote()
    if (!n || n.mode = mode)
        return
    SaveCurrent()
    if (mode = "check") {
        ; Fill the checklist from the text once, and only while it is still
        ; empty.  The seeded flag means items the user deleted stay deleted.
        if (!n.seeded && n.items.Length = 0 && Trim(n.body) != "") {
            loop parse, n.body, "`n", "`r" {
                line := Trim(A_LoopField)
                if (line != "")
                    n.items.Push({text: line, done: false})
            }
            n.seeded := true
        }
    } else {
        ; seed the text from the checklist, only while it is still empty
        if (Trim(n.body) = "" && n.items.Length > 0) {
            parts := []
            for it in n.items
                parts.Push(it.text)
            n.body := JoinLines(parts)
            edBody.Value := n.body
        }
    }
    n.mode := mode
    ShowMode(mode)
    RefreshChecklist()
    SyncListName()
    MarkDirty()
}

JoinLines(arr) {
    out := ""
    for line in arr
        out .= (out = "" ? "" : "`n") line
    return out
}

RefreshChecklist() {
    global lvCheck, Guard
    Guard := true
    lvCheck.Delete()
    n := CurrentNote()
    if n {
        for it in n.items
            lvCheck.Add(, (it.done ? Chr(9745) : Chr(9744)) "   " it.text)
    }
    Guard := false
    ScheduleBarHide()
}

AddCheckItem(*) {
    global edItem, lvCheck
    n := CurrentNote()
    if !n
        return
    txt := Trim(edItem.Value)
    if (txt = "")
        return
    n.items.Push({text: txt, done: false})
    edItem.Value := ""
    RefreshChecklist()
    row := lvCheck.GetCount()
    if (row > 0)
        lvCheck.Modify(row, "Select Vis Focus")
    SyncListName()
    MarkDirty()
    edItem.Focus()
}

ToggleItemAt(row) {
    global lvCheck
    n := CurrentNote()
    if (!n || row < 1 || row > n.items.Length)
        return
    n.items[row].done := !n.items[row].done
    RefreshChecklist()
    lvCheck.Modify(row, "Select Vis Focus")
    SyncListName()
    MarkDirty()
}

RenameItemAt(row) {
    global lvCheck
    n := CurrentNote()
    if (!n || row < 1 || row > n.items.Length)
        return
    txt := AskText("Rename item", "ITEM TEXT", n.items[row].text)
    if (txt = "")
        return
    n.items[row].text := txt
    RefreshChecklist()
    lvCheck.Modify(row, "Select Vis Focus")
    SyncListName()
    MarkDirty()
}

; The stock InputBox is a light system dialog and clashes with the widget, so
; ask for the single line in our own colours.  Runs its own message loop until
; the little dialog is destroyed, then returns what was typed ("" = cancelled).
AskText(title, prompt, initial := "") {
    global C_BG, C_TEXT, C_DIM, C_ACCENT
    global AskResult, AskDone, AskEditOld, AskEditCB
    AskResult := "", AskDone := false
    dlg := Gui("-Caption +ToolWindow +OwnDialogs", title)
    dlg.BackColor := Hex(C_BG)
    dlg.SetFont("s9", "Segoe UI")
    tip := dlg.Add("Text", "x14 y12 w320 h16 BackgroundTrans", prompt)
    tip.SetFont("s9 c" Hex(C_DIM), "Segoe UI")
    ed := dlg.Add("Edit", "x14 y32 w320 h24 -E0x200"
                          " Background" Hex(C_BG) " c" Hex(C_TEXT), initial)
    ed.SetFont("s10", "Segoe UI")
    okl := dlg.Add("Text", "x250 y68 w40 h18 BackgroundTrans Right", "SAVE")
    okl.SetFont("s9 bold", "Segoe UI")
    SetLinkColor(okl, Hex(C_ACCENT))
    cnl := dlg.Add("Text", "x296 y68 w38 h18 BackgroundTrans Right", "CANCEL")
    cnl.SetFont("s9 bold", "Segoe UI")
    SetLinkColor(cnl, Hex(C_DIM))
    Save(*) {
        AskResult := Trim(ed.Value), AskDone := true
        dlg.Destroy()
    }
    Drop(*) {
        if !AskDone
            AskResult := ""
        dlg.Destroy()
    }
    okl.OnEvent("Click", Save)
    cnl.OnEvent("Click", Drop)
    dlg.OnEvent("Escape", Drop)
    dlg.OnEvent("Close", Drop)
    ; Enter in the field saves, exactly like the SAVE link
    AskEditCB := CallbackCreate(AskEditProc, "Fast", 4)
    AskEditOld := DllCall("SetWindowLongPtrW", "ptr", ed.Hwnd, "int", -4, "ptr", AskEditCB, "ptr")
    dlg.Show("w348 h96 Center")
    ed.Focus()
    SendMessage(0x00B1, 0, -1, ed)          ; EM_SETSEL - preselect the old text
    WinWaitClose("ahk_id " dlg.Hwnd)
    return AskResult
}

AskEditProc(h, m, w, l) {
    global AskEditOld, AskResult, AskDone
    if ((m = 0x0100 || m = 0x0101) && w = 0x0D) {
        c := GuiCtrlFromHwnd(h)
        if c
            AskResult := Trim(c.Value), AskDone := true
        ; close from the message loop, never from inside the field's own proc
        PostMessage(0x0010, 0, 0, DllCall("GetParent", "ptr", h, "ptr"))
        return 0
    }
    return DllCall("CallWindowProcW", "ptr", AskEditOld, "ptr", h, "uint", m, "ptr", w, "ptr", l, "ptr")
}

RemoveItemAt(row) {
    global lvCheck
    n := CurrentNote()
    if (!n || row < 1 || row > n.items.Length)
        return
    n.items.RemoveAt(row)
    RefreshChecklist()
    if (n.items.Length > 0)
        lvCheck.Modify(Min(row, n.items.Length), "Select Vis Focus")
    SyncListName()
    MarkDirty()
}

OnCheckClick(*) {
    global lvCheck, Guard
    if Guard
        return
    row := RowAt(lvCheck)
    if (row < 1)
        return
    if OverRight(lvCheck) {
        RemoveItemAt(row)
        return
    }
    if OverBox(lvCheck)
        ToggleItemAt(row)
}

OnCheckDoubleClick(*) {
    global lvCheck
    if OverRight(lvCheck)
        return
    row := RowAt(lvCheck)
    if (row >= 1)
        RenameItemAt(row)
}

; which row is actually under the mouse, -1 when it is empty space
RowAt(lv) {
    pt := ClientPoint(lv)
    hti := Buffer(24, 0)
    NumPut("int", NumGet(pt, 0, "int"), "int", NumGet(pt, 4, "int"), hti)
    ; LVM_SUBITEMHITTEST returns a zero-based native item index; Gui.ListView
    ; methods and the Notes/items arrays use one-based row numbers.
    item := DllCall("SendMessageW", "ptr", lv.Hwnd, "uint", 0x1039, "ptr", 0, "ptr", hti, "int")
    return item < 0 ? item : item + 1
}

; ---- hit testing, always in the list's own client space -------------
ClientPoint(lv) {
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)                      ; screen coords
    DllCall("ScreenToClient", "ptr", lv.Hwnd, "ptr", pt)
    return pt
}

; true when the click is on the checkbox glyph, not the row text
OverBox(lv) {
    pt := ClientPoint(lv)
    rx := NumGet(pt, 0, "int")
    ry := NumGet(pt, 4, "int")
    ; the row text starts at x = 6, so the tick zone must stop well before the
    ; text or clicking a word would tick the item
    return (rx >= 0 && rx <= 20 && ry >= 0 && ry <= ClientH(lv))
}

; true when the click is on the delete x at the right end of the row
OverRight(lv) {
    global ROW_XW
    pt := ClientPoint(lv)
    rx := NumGet(pt, 0, "int")
    ry := NumGet(pt, 4, "int")
    return (rx >= ClientW(lv) - ROW_XW && rx >= 0 && ry >= 0 && ry <= ClientH(lv))
}

ClientOf(lv) {
    cr := Buffer(16, 0)
    DllCall("GetClientRect", "ptr", lv.Hwnd, "ptr", cr)
    return cr
}

ClientW(lv) => NumGet(ClientOf(lv), 8, "int")
ClientH(lv) => NumGet(ClientOf(lv), 12, "int")

; =====================================================================
;  misc
; =====================================================================
OnCtlColorStatic(wParam, lParam, msg, hwnd) {
    global LinkBase
    if !LinkBase.Has(lParam)
        return
    ; WM_CTLCOLORSTATIC: transparent text plus the stock NULL_BRUSH means the
    ; parent/widget surface remains visible instead of a control rectangle.
    DllCall("SetBkMode", "ptr", wParam, "int", 1)
    return DllCall("GetStockObject", "int", 5, "ptr") ; NULL_BRUSH
}

OnMouseMove(wParam, lParam, msg, hwnd) {
    global HoverLink, LinkBase, C_ACCENT
    MouseGetPos(, , , &ctl)
    if (ctl = HoverLink)
        return
    if (HoverLink && LinkBase.Has(HoverLink)) {
        c := GuiCtrlFromHwnd(HoverLink)
        if c
            c.SetFont("c" LinkBase[HoverLink])
    }
    HoverLink := ctl
    if (ctl && LinkBase.Has(ctl)) {
        c := GuiCtrlFromHwnd(ctl)
        if c
            c.SetFont("c" Hex(C_ACCENT))
    }
}
