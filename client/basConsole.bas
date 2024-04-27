Attribute VB_Name = "basConsole"
Option Explicit

'there are 4 consoles, the current console will be 1, 2, 3 or 4
Public ActiveConsole As Integer

Public ConsoleHistory(1 To 4, 1 To 9999) As ConsoleLine
Public Console(1 To 4, 0 To 299) As ConsoleLine
Public ConsoleScrollInt(1 To 4) As Integer

Public scrConsoleContext(1 To 4) As clsScriptFunctions

Public ConsolePaused(1 To 4) As Boolean

Public ConsoleWaitingOnRemote(1 To 4) As Boolean

Private Base64 As New clsBase64

Public Type ConsoleLineSegment
    Caption As String
    
    AlignTop As Boolean
    AlighBottom As Boolean
    VerticalOffset As Long
    VPos As Long
    HPos As Long

    FontColor As Long
    FontName As String
    FontSize As Long
    FontBold As Boolean
    FontItalic As Boolean
    FontStrikethru As Boolean
    FontUnderline As Boolean

    Flash As Boolean
    FlashFast As Boolean
    FlashSlow As Boolean

    Height As Long
    TotalWidth As Long
End Type

Public Type ConsoleDrawSegment
    Color As Long
    HPos As Long
End Type

Public Type ConsoleLine
    Segments() As ConsoleLineSegment

    Height As Long
    TotalWidth As Long

    PreSpace As Boolean

    Center As Boolean
    Right As Boolean

    Draw() As ConsoleDrawSegment
End Type

Public ConsoleInitialized(1 To 4) As Boolean
Public CurrentPromptInput(1 To 4) As String
Public CurrentPromptSelStart(1 To 4) As Long
Public CurrentPromptSelLength(1 To 4) As Long

Public RecentCommandsIndex(1 To 4) As Integer
Public RecentCommands(1 To 4, 0 To 99) As String

Public CurrentPromptVisible(1 To 4) As Boolean

Public yDiv As Integer  'the amount of vertical space between each console line
Public DisableFlashing As Boolean

Public Const DrawDividerWidth = 24
Public Const Max_Font_Size = 144
Public Const ConsoleXSpacing = 360
Public Const PreSpaceWidth = 600

Public ConsoleLastRenderFlash As Boolean

Public Property Get ConsoleInvisibleChar() As String
    ConsoleInvisibleChar = Chr(7)
End Property

Public Sub CalculateConsoleLine(ByRef CLine As ConsoleLine)
    Dim X As Integer, W As Long, H As Long

    CLine.Height = 0
    CLine.TotalWidth = 0
    For X = 0 To UBound(CLine.Segments)
        H = Font_Height(CLine.Segments(X))
        CLine.Segments(X).Height = H
        If H > CLine.Height Then
            CLine.Height = H
        End If

        W = Font_Width(CLine.Segments(X))
        CLine.TotalWidth = CLine.TotalWidth + W
        CLine.Segments(X).TotalWidth = W
    Next

    Dim HeightDiff As Long
    For X = 0 To UBound(CLine.Segments)
        HeightDiff = CLine.Height - CLine.Segments(X).Height
        Dim VPos As Long
        If CLine.Segments(X).AlighBottom Then
            VPos = HeightDiff
        ElseIf CLine.Segments(X).AlignTop Then
            VPos = 0
        Else
            VPos = HeightDiff / 2
        End If
        VPos = VPos + CLine.Segments(X).VerticalOffset
        If VPos > HeightDiff Then
            VPos = HeightDiff
        ElseIf VPos < 0 Then
            VPos = 0
        End If
        CLine.Segments(X).VPos = VPos

        If X = 0 Then
            W = ConsoleXSpacing
            If CLine.PreSpace Then
                W = W + PreSpaceWidth
            End If

            If CLine.Center Then
                W = (frmConsole.Width - CLine.TotalWidth) / 2
            ElseIf CLine.Right Then
                W = frmConsole.Width - (CLine.TotalWidth + W)
            End If
        Else
            W = CLine.Segments(X - 1).HPos + CLine.Segments(X - 1).TotalWidth
        End If
        CLine.Segments(X).HPos = W
    Next
End Sub

Public Sub SetDisableFlashing(ByVal NewValue As Boolean)
    DisableFlashing = NewValue
    If NewValue Then
        RegSave "DisableFlashing", "true"
    Else
        RegSave "DisableFlashing", "false"
    End If
End Sub

Public Sub AddToRecentCommands(ByVal s As String)
    If Trim(s) = "" Then Exit Sub
        
    If i(s) = RecentCommands(ActiveConsole, 1) Then GoTo SkipAddingIt
    

    Dim n As Integer
    For n = 99 To 2 Step -1
        RecentCommands(ActiveConsole, n) = RecentCommands(ActiveConsole, n - 1)
    Next n


SkipAddingIt:
    RecentCommands(ActiveConsole, 1) = Trim(s)
    RecentCommands(ActiveConsole, 0) = ""
    RecentCommandsIndex(ActiveConsole) = 0
End Sub

Public Sub RefreshCommandLinePromptInput(ByVal ConsoleID As Integer)
    If ConsoleID = ActiveConsole Then
        frmConsole.txtPromptInput.Text = CurrentPromptInput(ConsoleID)
        frmConsole.txtPromptInput.SelStart = CurrentPromptSelStart(ConsoleID)
        frmConsole.txtPromptInput.SelLength = CurrentPromptSelLength(ConsoleID)
    End If
End Sub

Public Sub RefreshCommandLinePrompt(ByVal ConsoleID As Integer)
    RefreshCommandLinePromptInput ConsoleID

    If Not CurrentPromptVisible(ConsoleID) Then
        Exit Sub
    End If

    Dim PromptStr As String
    If WaitingForInput(ConsoleID) Then
        PromptStr = cPrompt(ConsoleID)
    Else
        PromptStr = cPath(ConsoleID) & ">{{lblue}}{{|}}{{white}}"
    End If

    SayRaw ConsoleID, "{{noprespace}}" & PromptStr & " ", -1
    CurrentPromptVisible(ConsoleID) = True

    frmConsole.QueueConsoleRender
End Sub

Public Sub MoveUnderscoreToEnd(ByVal ConsoleID As Integer)
    CurrentPromptSelStart(ConsoleID) = Len(CurrentPromptInput(ConsoleID))
    CurrentPromptSelLength(ConsoleID) = 0
End Sub

Public Sub New_Console_Line(ByVal ConsoleID As Integer)
    Shift_Console_Lines ConsoleID

    CurrentPromptVisible(ConsoleID) = True
    CurrentPromptInput(ConsoleID) = ""
    CurrentPromptSelStart(ConsoleID) = 0
    CurrentPromptSelLength(ConsoleID) = 0
    RefreshCommandLinePrompt ConsoleID

    frmConsole.QueueConsoleRender
End Sub

Public Sub Shift_Console_Lines(ByVal ConsoleID As Integer)
    Dim n As Integer

    For n = 299 To 2 Step -1
        Console(ConsoleID, n) = Console(ConsoleID, n - 1)
    Next n

    Console(ConsoleID, 1) = Console_Line_Defaults
    Console(ConsoleID, 1).Segments(0).Caption = ""
    CalculateConsoleLine Console(ConsoleID, 1)

    frmConsole.QueueConsoleRender
End Sub

Public Sub Reset_Console(ByVal ConsoleID As Integer)
    Dim n As Integer
    For n = 1 To 299
        Console(ConsoleID, n) = Console_Line_Defaults
    Next n

    CurrentPromptInput(ConsoleID) = ""
    CurrentPromptSelStart(ConsoleID) = 0
    CurrentPromptSelLength(ConsoleID) = 0
    RefreshCommandLinePrompt ConsoleID

    ConsoleInitialized(ConsoleID) = True

    frmConsole.QueueConsoleRender
End Sub

Public Sub Print_Console()
    If Not ConsoleInitialized(ActiveConsole) Then
        Exit Sub
    End If

    Dim n As Integer, n2 As Integer, tmpY2 As Long, printHeight As Long

    frmConsole.Cls

    Dim UsedFlash As Boolean
    UsedFlash = False

    Dim addOn As Long, propertySpace As String
    addOn = ConsoleScrollInt(ActiveConsole) * 2400
    printHeight = frmConsole.Height - 840 + addOn
    frmConsole.CurrentY = printHeight

    frmConsole.FontBold = Console_Line_Defaults.Segments(0).FontBold
    frmConsole.FontItalic = Console_Line_Defaults.Segments(0).FontItalic
    frmConsole.FontUnderline = Console_Line_Defaults.Segments(0).FontUnderline
    frmConsole.FontStrikethru = Console_Line_Defaults.Segments(0).FontStrikethru
    frmConsole.FontSize = Console_Line_Defaults.Segments(0).FontSize
    frmConsole.FontName = Console_Line_Defaults.Segments(0).FontName
    frmConsole.ForeColor = Console_Line_Defaults.Segments(0).FontColor

    If ConsoleWaitingOnRemote(ActiveConsole) Then
        frmConsole.CurrentX = ConsoleXSpacing
        If LoadingSpinner < 1 Then
            LoadingSpinner = 1
        End If
        frmConsole.Print "Loading... " & Mid(LoadingSpinnerAnim, LoadingSpinner, 1)
        UsedFlash = True
    End If

    Dim ConsumedInputPrompt As Boolean
    ConsumedInputPrompt = False

    Dim Seg As Integer, SegMax As Integer
    Dim FontHeight As Long
    Dim LineBackColor As Long
    Dim Pos1 As Long, Pos2 As Long
    Dim HideLine As Boolean
    Dim DrawSegs() As ConsoleDrawSegment
    Dim SegVal As ConsoleLineSegment

    n = 0
    Do
        n = n + 1

        FontHeight = Console(ActiveConsole, n).Height + yDiv
        printHeight = printHeight - FontHeight

        LineBackColor = frmConsole.BackColor
        '--------------- DRAW ------------------------------------------
        '--------------- DRAW ------------------------------------------
        If LBound(Console(ActiveConsole, n).Draw) >= 0 Then
            tmpY2 = printHeight - (yDiv / 2)
            DrawSegs = Console(ActiveConsole, n).Draw

            Pos1 = 0
            For n2 = LBound(DrawSegs) To UBound(DrawSegs)
                Pos1 = DrawSegs(n2).HPos
                If Pos1 > frmConsole.Width Then
                    GoTo DrawSegmentOffScreen
                End If
                If DrawSegs(n2).Color >= 0 Then
                    LineBackColor = DrawSegs(n2).Color
                    If n2 = UBound(DrawSegs) Then
                        Pos2 = frmConsole.Width
                    Else
                        Pos2 = DrawSegs(n2 + 1).HPos
                        If Pos2 > frmConsole.Width Then
                            Pos2 = frmConsole.Width
                        End If
                    End If
                    frmConsole.Line (Pos1, tmpY2)-(Pos2, (tmpY2 + FontHeight)), LineBackColor, BF
                End If
            Next
DrawSegmentOffScreen:
        End If
        '--------------- DRAW ------------------------------------------
        '--------------- DRAW ------------------------------------------

        SegMax = UBound(Console(ActiveConsole, n).Segments)
        For Seg = 0 To SegMax
            SegVal = Console(ActiveConsole, n).Segments(Seg)

            frmConsole.FontBold = SegVal.FontBold
            frmConsole.FontItalic = SegVal.FontItalic
            frmConsole.FontUnderline = SegVal.FontUnderline
            frmConsole.FontStrikethru = SegVal.FontStrikethru
            frmConsole.FontSize = SegVal.FontSize
            frmConsole.FontName = SegVal.FontName
            frmConsole.ForeColor = SegVal.FontColor

            HideLine = False
            If Not DisableFlashing Then
                If SegVal.Flash Then HideLine = Flash: UsedFlash = True
                ElseIf SegVal.FlashFast Then HideLine = FlashFast: UsedFlash = True
                ElseIf SegVal.FlashSlow Then HideLine = FlashSlow: UsedFlash = True
            End If

            frmConsole.CurrentY = printHeight + SegVal.VPos

            If Seg = SegMax And n = 1 Then
                If CurrentPromptVisible(ActiveConsole) And Not frmConsole.ChatBox.Visible Then
                    frmConsole.txtPromptInput.top = frmConsole.CurrentY
                    frmConsole.txtPromptInput.Left = SegVal.HPos + SegVal.TotalWidth
                    frmConsole.txtPromptInput.Height = SegVal.Height
                    frmConsole.txtPromptInput.Width = frmConsole.Width - frmConsole.txtPromptInput.Left
                    frmConsole.txtPromptInput.FontSize = SegVal.FontSize
                    frmConsole.txtPromptInput.FontName = SegVal.FontName
                    frmConsole.txtPromptInput.ForeColor = SegVal.FontColor
                    frmConsole.txtPromptInput.BackColor = LineBackColor
                    frmConsole.txtPromptInput.Visible = True
                    frmConsole.txtPromptInput.SetFocus
                    ConsumedInputPrompt = True
                End If
            End If

            If Not HideLine Then
                frmConsole.CurrentX = SegVal.HPos
                frmConsole.Print SegVal.Caption
            End If
        Next
    Loop Until printHeight < 0 Or n >= 299
ExitLoop:
    If Not ConsumedInputPrompt Then
        frmConsole.txtPromptInput.Visible = False
    End If

    ConsoleLastRenderFlash = UsedFlash
End Sub

Public Function Console_Line_Defaults() As ConsoleLine
    ReDim Console_Line_Defaults.Segments(0 To 0)
    Console_Line_Defaults.Segments(0).Caption = ""
    Console_Line_Defaults.Segments(0).FontBold = RegLoad("Default_FontBold", "True")
    Console_Line_Defaults.Segments(0).FontItalic = RegLoad("Default_FontItalic", "False")
    Console_Line_Defaults.Segments(0).FontName = RegLoad("Default_FontName", "Verdana")
    Console_Line_Defaults.Segments(0).FontSize = RegLoad("Default_FontSize", "10")
    Console_Line_Defaults.Segments(0).FontUnderline = RegLoad("Default_FontUnderline", "False")
    Console_Line_Defaults.Segments(0).FontColor = RegLoad("Default_FontColor", RGB(255, 255, 255))
    Console_Line_Defaults.Segments(0).Flash = False
    Console_Line_Defaults.Segments(0).FlashFast = False
    Console_Line_Defaults.Segments(0).FlashSlow = False
    ReDim Console_Line_Defaults.Draw(-1 To -1)
    Console_Line_Defaults.Draw(-1).Color = -1
    Console_Line_Defaults.Center = False
    Console_Line_Defaults.Right = False
End Function

Private Sub SetupLFont(LineSeg As ConsoleLineSegment)
    frmConsole.lfont.FontName = LineSeg.FontName
    frmConsole.lfont.FontSize = LineSeg.FontSize
    frmConsole.lfont.FontBold = LineSeg.FontBold
    frmConsole.lfont.FontItalic = LineSeg.FontItalic
    frmConsole.lfont.FontUnderline = LineSeg.FontUnderline
    frmConsole.lfont.Caption = LineSeg.Caption
End Sub

Public Function Font_Height(LineSeg As ConsoleLineSegment) As Long
    SetupLFont LineSeg
    Font_Height = frmConsole.lfont.Height
End Function

Public Function Font_Width(LineSeg As ConsoleLineSegment) As Long
    SetupLFont LineSeg
    Font_Width = frmConsole.lfont.Width
End Function


Public Function StripAfterNewline(ByVal s As String) As String
    Dim CrPos As Long, LfPos As Long
    CrPos = InStr(s, vbCr)
    LfPos = InStr(s, vbLf)

    If CrPos > 0 Then
        If LfPos > 0 And LfPos < CrPos Then
            StripAfterNewline = Mid(s, 1, LfPos - 1)
        Else
            StripAfterNewline = Mid(s, 1, CrPos - 1)
        End If
    ElseIf LfPos > 0 Then
        StripAfterNewline = Mid(s, 1, LfPos - 1)
    Else
        StripAfterNewline = s
    End If
End Function

Public Function RenderPromptInput(ByVal ConsoleID As Integer)
    Dim Seg As Integer
    Seg = UBound(Console(ConsoleID, 1).Segments)
    Console(ConsoleID, 1).Segments(Seg).Caption = Console(ConsoleID, 1).Segments(Seg).Caption & Replace(CurrentPromptInput(ConsoleID), ConsoleInvisibleChar, "")
    CalculateConsoleLine Console(ConsoleID, 1)
    CurrentPromptSelStart(ConsoleID) = 0
    CurrentPromptSelLength(ConsoleID) = 0
    CurrentPromptInput(ConsoleID) = ""
    WaitingForInput(ConsoleID) = False
End Function

Public Function SayRaw(ByVal ConsoleID As Integer, ByVal s As String, Optional ByVal OverwriteLineIndex As Long = 0)
    If ConsoleID > 4 Then Exit Function
    If Len(s) > 32763 Then s = Mid(s, 1, 32763) ' 32764 would overflow

    If OverwriteLineIndex >= 0 Then
        Shift_Console_Lines ConsoleID
        OverwriteLineIndex = 1
    Else
        OverwriteLineIndex = (OverwriteLineIndex * -1)
    End If

    If OverwriteLineIndex = 1 Then ' No matter what we just killed the prompt
        CurrentPromptVisible(ConsoleID) = False
    End If

    Console(ConsoleID, OverwriteLineIndex) = Parse_Console_Line(Console(ConsoleID, OverwriteLineIndex), s)

    frmConsole.QueueConsoleRender
End Function

Public Function Parse_Console_Line(ByRef CLine As ConsoleLine, ByVal s As String) As ConsoleLine
    s = StripAfterNewline(s)

    Dim sSplit() As String
    sSplit = Split(s, "{{|}}")
    If UBound(sSplit) < 0 Then
        ReDim sSplit(0 To 0)
        sSplit(0) = ""
    End If

    Dim propertySpace As String, pSplit() As String

    CLine = Console_Line_Defaults
    CLine.PreSpace = True
    ReDim CLine.Segments(0 To UBound(sSplit))

    Dim Seg As Integer, CLineSeg As ConsoleLineSegment

    For Seg = 0 To UBound(sSplit)
        If Seg > 0 Then
            CLineSeg = CLine.Segments(Seg - 1)
        Else
            CLineSeg = Console_Line_Defaults.Segments(0)
        End If

        s = sSplit(Seg)

        If Has_Property_Space(s) Then
            propertySpace = i(Get_Property_Space(s))
            propertySpace = Replace(propertySpace, ",", " ")
            While InStr(propertySpace, "  ") > 0
                propertySpace = Replace(propertySpace, "  ", " ")
            Wend
            pSplit = Split(propertySpace, " ")

            Dim pIdx As Long, pCur As String
            For pIdx = 0 To UBound(pSplit)
                pCur = pSplit(pIdx)

                ' ==== FONTS ====
                If pCur = "arial" Then
                    CLineSeg.FontName = "Arial"
                ElseIf pCur = "arial_black" Then
                    CLineSeg.FontName = "Arial Black"
                ElseIf pCur = "comic_sans_ms" Then
                    CLineSeg.FontName = "Comic Sans MS"
                ElseIf pCur = "courier_new" Then
                    CLineSeg.FontName = "Courier New"
                ElseIf pCur = "georgia" Then
                    CLineSeg.FontName = "Georgia"
                ElseIf pCur = "impact" Then
                    CLineSeg.FontName = "Impact"
                ElseIf pCur = "lucida_console" Then
                    CLineSeg.FontName = "Lucida Console"
                ElseIf pCur = "tahoma" Then
                    CLineSeg.FontName = "Tahoma"
                ElseIf pCur = "times_new_roman" Then
                    CLineSeg.FontName = "Times New Roman"
                ElseIf pCur = "trebuchet_ms" Then
                    CLineSeg.FontName = "Trebuchet MS"
                ElseIf pCur = "verdana" Then
                    CLineSeg.FontName = "Verdana"
                ElseIf pCur = "wingdings" Then
                    CLineSeg.FontName = "Wingdings"
                ElseIf pCur = "webdings" Then
                    CLineSeg.FontName = "Webdings"
                ' ==== FONT ATTRIBUTES ====
                ElseIf pCur = "strikethrough" Or pCur = "strikethru" Then
                    CLineSeg.FontStrikethru = True
                ElseIf pCur = "nostrikethrough" Or pCur = "nostrikethru" Then
                    CLineSeg.FontStrikethru = False
                ElseIf pCur = "italic" Or pCur = "italics" Then
                    CLineSeg.FontItalic = True
                ElseIf pCur = "noitalic" Or pCur = "noitalics" Then
                    CLineSeg.FontItalic = False
                ElseIf pCur = "bold" Then
                    CLineSeg.FontBold = True
                ElseIf pCur = "nobold" Then
                    CLineSeg.FontBold = False
                ElseIf pCur = "underline" Or pCur = "underlined" Then
                    CLineSeg.FontUnderline = True
                ElseIf pCur = "nounderline" Or pCur = "nounderlined" Then
                    CLineSeg.FontUnderline = False
                ' ==== FLASHING ====
                ElseIf pCur = "noflash" Then
                    CLineSeg.Flash = False
                    CLineSeg.FlashFast = False
                    CLineSeg.FlashSlow = False
                ElseIf pCur = "flash" Then
                    CLineSeg.Flash = True
                    CLineSeg.FlashFast = False
                    CLineSeg.FlashSlow = False
                ElseIf pCur = "flashfast" Then
                    CLineSeg.FlashFast = True
                    CLineSeg.Flash = False
                    CLineSeg.FlashSlow = False
                ElseIf pCur = "flashslow" Then
                    CLineSeg.FlashSlow = True
                    CLineSeg.Flash = False
                    CLineSeg.FlashFast = False
                ' ==== VERTICAL ALIGNMENT ====
                ElseIf pCur = "middle" Then
                    CLineSeg.AlignTop = False
                    CLineSeg.AlighBottom = False
                ElseIf pCur = "top" Then
                    CLineSeg.AlignTop = True
                    CLineSeg.AlighBottom = False
                ElseIf pCur = "bottom" Then
                    CLineSeg.AlighBottom = True
                    CLineSeg.AlignTop = False
                ElseIf Left(pCur, 5) = "voff:" Then
                    CLineSeg.VerticalOffset = Mid(pSplit, 6)
                ElseIf IsNumeric(pCur) Then
                    CLineSeg.FontSize = pCur
                    If CLineSeg.FontSize < 8 Then
                        CLineSeg.FontSize = 8
                    ElseIf CLineSeg.FontSize > Max_Font_Size Then
                        CLineSeg.FontSize = Max_Font_Size
                    End If
                ' ==== COLORS ====
                ElseIf pCur = "white" Then
                    CLineSeg.FontColor = vbWhite
                ElseIf pCur = "black" Then
                    CLineSeg.FontColor = vbBlack + 1
                ElseIf pCur = "purple" Then
                    CLineSeg.FontColor = iPurple
                ElseIf pCur = "pink" Then
                    CLineSeg.FontColor = iPink
                ElseIf pCur = "orange" Then
                    CLineSeg.FontColor = iOrange
                ElseIf pCur = "lorange" Then
                    CLineSeg.FontColor = iLightOrange
                ElseIf pCur = "blue" Then
                    CLineSeg.FontColor = iBlue
                ElseIf pCur = "dblue" Then
                    CLineSeg.FontColor = iDarkBlue
                ElseIf pCur = "lblue" Then
                    CLineSeg.FontColor = iLightBlue
                ElseIf pCur = "green" Then
                    CLineSeg.FontColor = iGreen
                ElseIf pCur = "dgreen" Then
                    CLineSeg.FontColor = iDarkGreen
                ElseIf pCur = "lgreen" Then
                    CLineSeg.FontColor = iLightGreen
                ElseIf pCur = "gold" Then
                    CLineSeg.FontColor = iGold
                ElseIf pCur = "yellow" Then
                    CLineSeg.FontColor = iYellow
                ElseIf pCur = "lyellow" Then
                    CLineSeg.FontColor = iLightYellow
                ElseIf pCur = "dyellow" Then
                    CLineSeg.FontColor = iDarkYellow
                ElseIf pCur = "brown" Then
                    CLineSeg.FontColor = iBrown
                ElseIf pCur = "lbrown" Then
                    CLineSeg.FontColor = iLightBrown
                ElseIf pCur = "dbrown" Then
                    CLineSeg.FontColor = iDarkBrown
                ElseIf pCur = "maroon" Then
                    CLineSeg.FontColor = iMaroon
                ElseIf pCur = "grey" Then
                    CLineSeg.FontColor = iGrey
                ElseIf pCur = "dgrey" Then
                    CLineSeg.FontColor = iDarkGrey
                ElseIf pCur = "lgrey" Then
                    CLineSeg.FontColor = iLightGrey
                ElseIf pCur = "red" Then
                    CLineSeg.FontColor = iRed
                ElseIf pCur = "lred" Then
                    CLineSeg.FontColor = iLightRed
                ElseIf pCur = "dred" Then
                    CLineSeg.FontColor = iDarkRed
                ElseIf Left(pCur, 4) = "rgb:" Then
                    Dim Error As Boolean
                    Dim R As Long, G As Long, b As Long
                    Error = False
                    Dim pCurSplit() As String
                    pCurSplit = Split(pCur, ":")
            
                    If UBound(pCurSplit) < 3 Then
                        RGBSplit Trim(pCurSplit(1)), R, G, b
                    Else
                        R = Trim(pCurSplit(1))
                        G = Trim(pCurSplit(2))
                        b = Trim(pCurSplit(3))
                    End If

                    If R < 0 Or R > 255 Then
                        Error = True
                    End If

                    If G < 0 Or G > 255 Then
                        Error = True
                    End If

                    If b < 0 Or b > 255 Then
                        Error = True
                    End If

                    If Error = False Then
                        CLineSeg.FontColor = RGB(R, G, b)
                    End If
                ElseIf Seg = 0 Then
                    If pCur = "noprespace" Then
                        CLine.PreSpace = False
                    ElseIf pCur = "prespace" Then
                        CLine.PreSpace = True
                    ElseIf pCur = "center" Then
                        CLine.Center = True
                        CLine.Right = False
                    ElseIf pCur = "right" Then
                        CLine.Right = True
                        CLine.Center = False
                    ElseIf pCur = "left" Then
                        CLine.Right = False
                        CLine.Center = False
                    End If
                End If
            Next
        End If

        s = Remove_Property_Space(s)
        s = Replace(s, ConsoleInvisibleChar, "")
        CLineSeg.Caption = s
        CLine.Segments(Seg) = CLineSeg
    Next
    CalculateConsoleLine CLine
    Parse_Console_Line = CLine
End Function

Public Function Remove_Property_Space(ByVal s As String) As String
    Dim n As Integer
    Dim isOn As Boolean
    isOn = True

    For n = 1 To Len(s)
        If Mid(s, n, 2) = "{{" Then
            isOn = False
            n = n + 1
        End If
        If isOn = True Then
            Remove_Property_Space = Remove_Property_Space & Mid(s, n, 1)
        End If
        If Mid(s, n, 2) = "}}" Then
            isOn = True
            n = n + 1
        End If
    Next n
End Function

Public Function Get_Property_Space(ByVal s As String) As String
    Dim n As Integer
    Dim isOn As Boolean
    isOn = False

    For n = 1 To Len(s)
        If Mid(s, n, 2) = "}}" Then
            isOn = False
            n = n + 1
        End If
        If isOn = True Then
            Get_Property_Space = Get_Property_Space & Mid(s, n, 1)
        End If
        If Mid(s, n, 2) = "{{" Then
            Get_Property_Space = Get_Property_Space & " "
            isOn = True
            n = n + 1
        End If
    Next n
End Function

Public Function Kill_Property_Space(ByVal s As String) As String
    Dim n As Integer
    Dim isOn As Boolean
    isOn = False

    For n = 1 To Len(s)
        If Mid(s, n, 2) = "{{" Then
            isOn = True
            n = n + 1
        End If

        If isOn = False Then
            Kill_Property_Space = Kill_Property_Space & Mid(s, n, 1)
        End If
        
        If Mid(s, n, 2) = "}}" Then
            isOn = False
            n = n + 1
        End If
    Next n

    Kill_Property_Space = Replace(Kill_Property_Space, "{{", "")
    Kill_Property_Space = Replace(Kill_Property_Space, "}}", "")
End Function

Public Function Has_Property_Space(ByVal s As String) As Boolean
    If InStr(s, "{{") > 0 And InStr(s, "}}") > 0 Then
        Has_Property_Space = True
    Else
        Has_Property_Space = False
    End If
End Function

Public Function EncodeBase64Bytes(ByRef arrData() As Byte) As String
    If LBound(arrData) = UBound(arrData) Then
        EncodeBase64Bytes = ""
        Exit Function
    End If
    EncodeBase64Bytes = Base64.EncodeByteArray(arrData)
End Function

Public Function EncodeBase64Str(ByVal strData As String) As String
    If strData = "" Then
        EncodeBase64Str = ""
        Exit Function
    End If
    EncodeBase64Str = EncodeBase64Bytes(StrConv(strData, vbFromUnicode))
End Function

Public Function DecodeBase64Bytes(ByVal strData As String) As Byte()
    If strData = "" Then
        Dim EmptyData(0 To 0) As Byte
        DecodeBase64Bytes = EmptyData
        Exit Function
    End If
    DecodeBase64Bytes = Base64.DecodeToByteArray(strData)
End Function

Public Function DecodeBase64Str(ByVal strData As String) As String
    If strData = "" Then
        DecodeBase64Str = ""
        Exit Function
    End If
    DecodeBase64Str = StrConv(DecodeBase64Bytes(strData), vbUnicode)
End Function
