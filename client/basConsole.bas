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

    FontColor As Long
    FontName As String
    FontSize As String
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

Public Type ConsoleLine
    Segments() As ConsoleLineSegment

    Height As Long
    TotalWidth As Long

    PreSpace As Boolean

    Center As Boolean
    Right As Boolean

    DrawEnabled As Boolean
    DrawColors(1 To 48) As Long
    DrawMode As String
    DrawR As Long
    DrawG As Long
    DrawB As Long
End Type

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
Public Const ConsoleXSpacingIndent = 960

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
    frmConsole.QueueConsoleRender
End Sub

Public Sub Print_Console()
    On Error Resume Next

    Dim sText As String * 255
    Dim n As Integer, n2 As Integer, tmpY2 As Long, printHeight As Long, tmpS As String
    n = 0

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

    frmConsole.CurrentX = ConsoleXSpacing
    n = 0
    Do
        n = n + 1

        Dim NextX As Long
        Dim FontHeight As Long
        FontHeight = Console(ActiveConsole, n).Height + yDiv
        printHeight = printHeight - FontHeight

        NextX = ConsoleXSpacing
        If Console(ActiveConsole, n).Center = True Then
            NextX = (frmConsole.Width / 2) - (Console(ActiveConsole, n).TotalWidth / 2)
        ElseIf Console(ActiveConsole, n).Right = True Then
            NextX = (frmConsole.Width) - (Console(ActiveConsole, n).TotalWidth) - ConsoleXSpacing
        ElseIf Console(ActiveConsole, n).PreSpace Then
            NextX = ConsoleXSpacingIndent
        End If

        SegMax = UBound(Console(ActiveConsole, n).Segments)
        For Seg = 0 To SegMax
            Dim HideLine As Boolean
            Dim SegVal As ConsoleLineSegment
            SegVal = Console(ActiveConsole, n).Segments(Seg)

            frmConsole.FontBold = SegVal.FontBold
            frmConsole.FontItalic = SegVal.FontItalic
            frmConsole.FontUnderline = SegVal.FontUnderline
            frmConsole.FontStrikethru = SegVal.FontStrikethru
    
            frmConsole.FontSize = SegVal.FontSize
            
            frmConsole.FontName = SegVal.FontName
            frmConsole.ForeColor = SegVal.FontColor

            frmConsole.CurrentY = printHeight

            Dim LineBackColor As Long
            LineBackColor = frmConsole.BackColor
    
            If Seg = 0 Then
                '--------------- DRAW ------------------------------------------
                '--------------- DRAW ------------------------------------------
                If Console(ActiveConsole, n).DrawEnabled = True Then
                    tmpY2 = printHeight - (yDiv / 2)

                    If i(Console(ActiveConsole, n).DrawMode) = "solid" Then
                        LineBackColor = Console(ActiveConsole, n).DrawColors(1)
                        'draw it all in one, much faster
                        frmConsole.Line _
                        (((frmConsole.Width / DrawDividerWidth) * 0), tmpY2)- _
                        ((frmConsole.Width / DrawDividerWidth) * _
                        (DrawDividerWidth), _
                        (tmpY2 + FontHeight)), _
                        LineBackColor, BF
                    Else
                        For n2 = 1 To DrawDividerWidth
                            frmConsole.Line _
                            (((frmConsole.Width / DrawDividerWidth) * (n2 - 1)), tmpY2)- _
                            ((frmConsole.Width / DrawDividerWidth) * _
                            (n2), _
                            (tmpY2 + FontHeight)), _
                            Console(ActiveConsole, n).DrawColors(n2), BF
                        Next n2
                    End If

                    frmConsole.CurrentY = printHeight
                End If
                '--------------- DRAW ------------------------------------------
                '--------------- DRAW ------------------------------------------
            End If
            tmpS = SegVal.Caption

            frmConsole.CurrentX = NextX
            NextX = NextX + SegVal.TotalWidth

            HideLine = False
            If Not DisableFlashing Then
                If SegVal.Flash Then HideLine = Flash: UsedFlash = True
                If SegVal.FlashFast Then HideLine = FlashFast: UsedFlash = True
                If SegVal.FlashSlow Then HideLine = FlashSlow: UsedFlash = True
            End If

            If SegVal.AlighBottom Then
                frmConsole.CurrentY = printHeight + (Console(ActiveConsole, n).Height - SegVal.Height)
            ElseIf SegVal.AlignTop Then
                frmConsole.CurrentY = printHeight
            Else
                frmConsole.CurrentY = printHeight + ((Console(ActiveConsole, n).Height - SegVal.Height) / 2)
            End If

            If Seg = SegMax And n = 1 And CurrentPromptVisible(ActiveConsole) And Not frmConsole.ChatBox.Visible Then
                frmConsole.txtPromptInput.top = frmConsole.CurrentY
                frmConsole.txtPromptInput.Left = NextX
                frmConsole.txtPromptInput.Height = frmConsole.lfont.Height
                frmConsole.txtPromptInput.Width = frmConsole.Width - frmConsole.txtPromptInput.Left
                frmConsole.txtPromptInput.FontSize = frmConsole.lfont.FontSize
                frmConsole.txtPromptInput.FontName = frmConsole.lfont.FontName
                frmConsole.txtPromptInput.ForeColor = SegVal.FontColor
                frmConsole.txtPromptInput.BackColor = LineBackColor
                frmConsole.txtPromptInput.Visible = True
                frmConsole.txtPromptInput.SetFocus
                ConsumedInputPrompt = True
            End If

            If Not HideLine Then
                frmConsole.Print tmpS
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

    Console_Line_Defaults.DrawEnabled = False
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

Public Function SayRaw(ByVal ConsoleID As Integer, ByVal s As String, Optional ByVal OverwriteLineIndex As Long = 0, Optional ByVal NoReset As Boolean = False)
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

    Console(ConsoleID, OverwriteLineIndex) = Parse_Console_Line(Console(ConsoleID, OverwriteLineIndex), s, NoReset)

    frmConsole.QueueConsoleRender
End Function

Public Function Array_Has(XArr() As String, ByVal XVal As String) As Boolean
    Array_Has = (Array_IndexOf(XArr, XVal) >= 0)
End Function

Public Function Array_IndexOf(XArr() As String, ByVal XVal As String, Optional MatchPrefix As Boolean = False) As Integer
    Dim X As Integer
    For X = LBound(XArr) To UBound(XArr)
        If XArr(X) = XVal Then
            Array_IndexOf = X
            Exit Function
        End If
        If MatchPrefix Then
            If Left(XArr(X), Len(XVal)) = XVal Then
                Array_IndexOf = X
                Exit Function
            End If
        End If
    Next
    Array_IndexOf = -1
End Function

Public Function Parse_Console_Line(ByRef CLine As ConsoleLine, ByVal s As String, Optional ByVal NoReset As Boolean = False) As ConsoleLine
    s = StripAfterNewline(s)

    Dim sSplit() As String
    sSplit = Split(s, "{{|}}")
    If UBound(sSplit) < 0 Then
        ReDim sSplit(0 To 0)
        sSplit(0) = ""
    End If

    Dim propertySpace As String, pSplit() As String

    Dim SegReinitAt As Integer
    If NoReset Then
        SegReinitAt = UBound(CLine.Segments) + 1
        ReDim Preserve CLine.Segments(0 To UBound(sSplit))
    Else
        CLine = Console_Line_Defaults
        CLine.PreSpace = True
        SegReinitAt = 0
        ReDim CLine.Segments(0 To UBound(sSplit))
    End If

    Dim Seg As Integer, BaseSeg As ConsoleLineSegment, CLineSeg As ConsoleLineSegment

    For Seg = 0 To UBound(sSplit)
        CLineSeg = CLine.Segments(Seg)
        If Seg >= SegReinitAt Then
            If Seg > 0 Then
                BaseSeg = CLine.Segments(Seg - 1)
            Else
                BaseSeg = Console_Line_Defaults.Segments(0)
            End If
            CLineSeg = BaseSeg
        Else
            BaseSeg = CLineSeg
        End If

        s = sSplit(Seg)

        If Has_Property_Space(s) Then
            propertySpace = i(Get_Property_Space(s))
            propertySpace = Replace(propertySpace, ",", " ")
            While InStr(propertySpace, "  ") > 0
                propertySpace = Replace(propertySpace, "  ", " ")
            Wend
            pSplit = Split(propertySpace, " ")
            CLineSeg.FontColor = propertySpace_Color(pSplit, BaseSeg)
            CLineSeg.FontSize = propertySpace_Size(pSplit, BaseSeg)
            CLineSeg.FontName = propertySpace_Name(pSplit, BaseSeg)
            CLineSeg.FontBold = propertySpace_Bold(pSplit, BaseSeg)
            CLineSeg.FontItalic = propertySpace_Italic(pSplit, BaseSeg)
            CLineSeg.FontUnderline = propertySpace_Underline(pSplit, BaseSeg)
            CLineSeg.FontStrikethru = propertySpace_Strikethru(pSplit, BaseSeg)
            If Array_Has(pSplit, "noflash") Then
                CLineSeg.Flash = False
                CLineSeg.FlashFast = False
                CLineSeg.FlashSlow = False
            End If
            If Array_Has(pSplit, "flash") Then CLineSeg.Flash = True
            If Array_Has(pSplit, "flashfast") Then CLineSeg.FlashFast = True
            If Array_Has(pSplit, "flashslow") Then CLineSeg.FlashSlow = True

            If Array_Has(pSplit, "middle") Then
                CLineSeg.AlignTop = False
                CLineSeg.AlighBottom = False
            End If
            If Array_Has(pSplit, "top") Then CLineSeg.AlignTop = True
            If Array_Has(pSplit, "bottom") Then CLineSeg.AlighBottom = True

            If Seg = 0 Then
                If Array_Has(pSplit, "noprespace") Then CLine.PreSpace = False
                If Array_Has(pSplit, "forceprespace") Then CLine.PreSpace = True
                If Array_Has(pSplit, "center") Then CLine.Center = True Else CLine.Center = False
                If Array_Has(pSplit, "right") Then CLine.Right = True Else CLine.Right = False
            End If
        End If

        s = Remove_Property_Space(s)
        s = Replace(s, ConsoleInvisibleChar, "")
        CLineSeg.Caption = s
        CLine.Segments(Seg) = CLineSeg
    Next
    CalculateConsoleLine CLine
    Parse_Console_Line = CLine
End Function

Public Function Is_Valid_Font(ByVal s As String) As Boolean
    'this shows the fonts that dark signs accepts as valid
    s = i(s)
    If _
    s = "arial" Or _
    s = "arial black" Or _
    s = "comic sans ms" Or _
    s = "courier new" Or _
    s = "georgia" Or _
    s = "impact" Or _
    s = "lucida console" Or _
    s = "tahoma" Or _
    s = "times new roman" Or _
    s = "trebuchet ms" Or _
    s = "verdana" Or _
    s = "wingdings" _
    Then
    
    
        Is_Valid_Font = True
    Else
        Is_Valid_Font = False
    End If
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

Public Function propertySpace_Name(s() As String, BaseSeg As ConsoleLineSegment) As String
    propertySpace_Name = BaseSeg.FontName

    If Array_Has(s, "arial") Then propertySpace_Name = "Arial"
    If Array_Has(s, "arial black") Then propertySpace_Name = "Arial Black"
    If Array_Has(s, "comic sans ms") Then propertySpace_Name = "Comic Sans MS"
    If Array_Has(s, "courier new") Then propertySpace_Name = "Courier New"
    If Array_Has(s, "georgia") Then propertySpace_Name = "Georgia"
    If Array_Has(s, "impact") Then propertySpace_Name = "Impact"
    If Array_Has(s, "lucida console") Then propertySpace_Name = "Lucida Console"
    If Array_Has(s, "tahoma") Then propertySpace_Name = "Tahoma"
    If Array_Has(s, "times new roman") Then propertySpace_Name = "Times New Roman"
    If Array_Has(s, "trebuchet ms") Then propertySpace_Name = "Trebuchet MS"
    If Array_Has(s, "verdana") Then propertySpace_Name = "Verdana"
    If Array_Has(s, "wingdings") Then propertySpace_Name = "Wingdings"
End Function

Public Function propertySpace_Bold(s() As String, BaseSeg As ConsoleLineSegment) As Boolean
    propertySpace_Bold = BaseSeg.FontBold

    If Array_Has(s, "bold") Then propertySpace_Bold = True
    If Array_Has(s, "nobold") Then propertySpace_Bold = False
End Function

Public Function propertySpace_Italic(s() As String, BaseSeg As ConsoleLineSegment) As Boolean
    propertySpace_Italic = BaseSeg.FontItalic

    If Array_Has(s, "italic") Then propertySpace_Italic = True
    If Array_Has(s, "noitalic") Then propertySpace_Italic = False
End Function

Public Function propertySpace_Strikethru(s() As String, BaseSeg As ConsoleLineSegment) As Boolean
    propertySpace_Strikethru = BaseSeg.FontStrikethru

    If Array_Has(s, "strikethru") Then propertySpace_Strikethru = True
    If Array_Has(s, "strikethrough") Then propertySpace_Strikethru = True
    If Array_Has(s, "nostrikethru") Then propertySpace_Strikethru = False
    If Array_Has(s, "nostrikethrough") Then propertySpace_Strikethru = False
End Function

Public Function propertySpace_Underline(s() As String, BaseSeg As ConsoleLineSegment) As Boolean
    propertySpace_Underline = BaseSeg.FontUnderline

    If Array_Has(s, "underline") Then propertySpace_Underline = True
    If Array_Has(s, "nounderline") Then propertySpace_Underline = False
End Function

Public Function propertySpace_Color(s() As String, BaseSeg As ConsoleLineSegment) As Long
    propertySpace_Color = BaseSeg.FontColor

    If Array_Has(s, "white") Then propertySpace_Color = vbWhite
    If Array_Has(s, "black") Then propertySpace_Color = vbBlack + 1
    
    If Array_Has(s, "purple") Then propertySpace_Color = iPurple
    If Array_Has(s, "pink") Then propertySpace_Color = iPink
    If Array_Has(s, "orange") Then propertySpace_Color = iOrange
    If Array_Has(s, "lorange") Then propertySpace_Color = iLightOrange
    
    If Array_Has(s, "blue") Then propertySpace_Color = iBlue
    If Array_Has(s, "dblue") Then propertySpace_Color = iDarkBlue
    If Array_Has(s, "lblue") Then propertySpace_Color = iLightBlue
    
    If Array_Has(s, "green") Then propertySpace_Color = iGreen
    If Array_Has(s, "dgreen") Then propertySpace_Color = iDarkGreen
    If Array_Has(s, "lgreen") Then propertySpace_Color = iLightGreen
    
    If Array_Has(s, "gold") Then propertySpace_Color = iGold
    If Array_Has(s, "yellow") Then propertySpace_Color = iYellow
    If Array_Has(s, "lyellow") Then propertySpace_Color = iLightYellow
    If Array_Has(s, "dyellow") Then propertySpace_Color = iDarkYellow
    
    If Array_Has(s, "brown") Then propertySpace_Color = iBrown
    If Array_Has(s, "lbrown") Then propertySpace_Color = iLightBrown
    If Array_Has(s, "dbrown") Then propertySpace_Color = iDarkBrown
    If Array_Has(s, "maroon") Then propertySpace_Color = iMaroon
    
    If Array_Has(s, "grey") Then propertySpace_Color = iGrey
    If Array_Has(s, "dgrey") Then propertySpace_Color = iDarkGrey
    If Array_Has(s, "lgrey") Then propertySpace_Color = iLightGrey
    
    If Array_Has(s, "red") Then propertySpace_Color = iRed
    If Array_Has(s, "lred") Then propertySpace_Color = iLightRed
    If Array_Has(s, "dred") Then propertySpace_Color = iDarkRed

    Dim ArrIdx As Integer
    ArrIdx = Array_IndexOf(s, "rgb:", True)
    If ArrIdx >= 0 Then
        Dim Error As Boolean
        Dim R As Long, G As Long, b As Long
        Error = False
        Dim sSplit() As String
        sSplit = Split(s(ArrIdx), ":")

        If UBound(sSplit) < 3 Then
            RGBSplit Trim(sSplit(1)), R, G, b
        Else
            R = Trim(sSplit(1))
            G = Trim(sSplit(2))
            b = Trim(sSplit(3))
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
            propertySpace_Color = RGB(R, G, b)
        End If
    End If
End Function

Public Function propertySpace_Size(s() As String, BaseSeg As ConsoleLineSegment) As String
    propertySpace_Size = BaseSeg.FontSize
    Dim n As Integer
    For n = 1 To 144
        If Array_Has(s, "" & n) Then
            propertySpace_Size = n
        End If
    Next n

    If propertySpace_Size < 8 Then propertySpace_Size = 8
    If propertySpace_Size > Max_Font_Size Then propertySpace_Size = Max_Font_Size
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
