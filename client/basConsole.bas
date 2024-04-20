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

Public Type ConsoleLine
    Caption As String
    PreSpace As Boolean
    
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

Public Const DrawDividerWidth = 24
Public Const Max_Font_Size = 144
Public Const ConsoleXSpacing = 360
Public Const ConsoleXSpacingIndent = 960

Public Property Get ConsoleInvisibleChar() As String
    ConsoleInvisibleChar = Chr(7)
End Property

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

    Console(ConsoleID, 1).PreSpace = False

    Dim PromptStr As String
    If WaitingForInput(ConsoleID) Then
        If Has_Property_Space(cPrompt(ConsoleID)) Then
            Console(ConsoleID, 1) = Load_Property_Space(Get_Property_Space(cPrompt(ConsoleID)), Remove_Property_Space(cPrompt(ConsoleID)) & " ")
            frmConsole.QueueConsoleRender
            Exit Sub
        End If
        PromptStr = cPrompt(ConsoleID)
    Else
        PromptStr = cPath(ConsoleID) & ">"
    End If
    
    PromptStr = Replace(PromptStr, ConsoleInvisibleChar, "")

    Console(ConsoleID, 1) = Console_Line_Defaults
    Console(ConsoleID, 1).Caption = PromptStr & " "

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
    Console(ConsoleID, 1).Caption = ""

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
    Dim n As Integer, n2 As Integer, tmpY As Long, tmpY2 As Long, printHeight As Long, tmpS As String, isAligned As Boolean
    n = 0

    frmConsole.Cls

    Dim addOn As Long, propertySpace As String
    addOn = ConsoleScrollInt(ActiveConsole) * 2400
    printHeight = frmConsole.Height - 840 + addOn
    frmConsole.CurrentY = printHeight

    frmConsole.FontBold = Console_Line_Defaults.FontBold
    frmConsole.FontItalic = Console_Line_Defaults.FontItalic
    frmConsole.FontUnderline = Console_Line_Defaults.FontUnderline
    frmConsole.FontStrikethru = Console_Line_Defaults.FontStrikethru
    frmConsole.FontSize = Console_Line_Defaults.FontSize
    frmConsole.FontName = Console_Line_Defaults.FontName
    frmConsole.ForeColor = Console_Line_Defaults.FontColor

    If ConsoleWaitingOnRemote(ActiveConsole) Then
        frmConsole.CurrentX = ConsoleXSpacing
        If LoadingSpinner < 1 Then
            LoadingSpinner = 1
        End If
        frmConsole.Print "Loading... " & Mid(LoadingSpinnerAnim, LoadingSpinner, 1)
    End If
    
    Dim ConsumedInputPrompt As Boolean
    ConsumedInputPrompt = False

    frmConsole.CurrentX = ConsoleXSpacing
    n = 0
    Do
        n = n + 1

        frmConsole.FontBold = Console(ActiveConsole, n).FontBold
        frmConsole.FontItalic = Console(ActiveConsole, n).FontItalic
        frmConsole.FontUnderline = Console(ActiveConsole, n).FontUnderline
        frmConsole.FontStrikethru = Console(ActiveConsole, n).FontStrikethru

        frmConsole.FontSize = Console_FontSize(n, ActiveConsole)
        
        frmConsole.FontName = Console_FontName(n, ActiveConsole)
        frmConsole.ForeColor = Console_FontColor(n, ActiveConsole)

        Dim FontHeight As Long
        FontHeight = Font_Height(Console_FontName(n, ActiveConsole), Console_FontSize(n, ActiveConsole))

        printHeight = printHeight - FontHeight

        frmConsole.CurrentY = printHeight

        Dim LineBackColor As Long
        LineBackColor = frmConsole.BackColor

        '--------------- DRAW ------------------------------------------
        '--------------- DRAW ------------------------------------------
        If Console(ActiveConsole, n).DrawEnabled = True Then
            tmpY = frmConsole.CurrentY
            tmpY2 = tmpY - (yDiv / 2)
            
            frmConsole.CurrentY = tmpY
            
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
        
            frmConsole.CurrentY = tmpY
        End If
DontDraw:
        '--------------- DRAW ------------------------------------------
        '--------------- DRAW ------------------------------------------

        tmpS = Console(ActiveConsole, n).Caption

        Dim HideLine As Boolean
        HideLine = False
        If Console(ActiveConsole, n).Flash = True And Flash = True Then HideLine = True
        If Console(ActiveConsole, n).FlashFast = True And FlashFast = True Then HideLine = True
        If Console(ActiveConsole, n).FlashSlow = True And FlashSlow = True Then HideLine = True
        If HideLine Then
            frmConsole.Print "  "
            GoTo NextOne
        End If

        frmConsole.CurrentX = ConsoleXSpacing

        isAligned = False
        
        frmConsole.lfont.FontSize = Console_FontName(n, ActiveConsole)
        frmConsole.lfont.FontName = Console_FontSize(n, ActiveConsole)
        frmConsole.lfont.Caption = tmpS
        If Console(ActiveConsole, n).Center = True Then
            frmConsole.CurrentX = (frmConsole.Width / 2) - (frmConsole.lfont.Width / 2)
            isAligned = True
        End If
        If Console(ActiveConsole, n).Right = True Then
            frmConsole.CurrentX = (frmConsole.Width) - (frmConsole.lfont.Width) - ConsoleXSpacing
            isAligned = True
        End If
        
        If Console(ActiveConsole, n).PreSpace Then
            If isAligned <> True Then frmConsole.CurrentX = ConsoleXSpacingIndent
        End If

        If n = 1 And CurrentPromptVisible(ActiveConsole) Then
            frmConsole.txtPromptInput.Top = frmConsole.CurrentY
            frmConsole.txtPromptInput.Left = frmConsole.CurrentX + frmConsole.lfont.Width
            frmConsole.txtPromptInput.Height = frmConsole.lfont.Height
            frmConsole.txtPromptInput.Width = frmConsole.Width - frmConsole.txtPromptInput.Left
            frmConsole.txtPromptInput.FontSize = frmConsole.lfont.FontSize
            frmConsole.txtPromptInput.FontName = frmConsole.lfont.FontName
            frmConsole.txtPromptInput.ForeColor = Console_FontColor(n, ActiveConsole)
            frmConsole.txtPromptInput.BackColor = LineBackColor
            frmConsole.txtPromptInput.Visible = True
            frmConsole.txtPromptInput.SetFocus
            ConsumedInputPrompt = True
        End If

        frmConsole.Print tmpS
NextOne:
    Loop Until printHeight < 0 Or n >= 299
ExitLoop:
    If Not ConsumedInputPrompt Then
        frmConsole.txtPromptInput.Visible = False
    End If
End Sub


Public Function Console_FontSize(ByVal consoleIndex As Integer, ByVal ConsoleID As Integer) As String
    Console_FontSize = Trim(Console(ConsoleID, consoleIndex).FontSize)
    
    'if not specified, get the defaul
    If Console_FontSize = "" Then
        Console_FontSize = Console_Line_Defaults.FontSize
        Exit Function
    End If
    
    'don't allow a smaller font size than 8
    If Console_FontSize < 8 Then Console_FontSize = 8
    
    'don't allow a larger font size than Max_Font_Size
    If Console_FontSize > Max_Font_Size Then Console_FontSize = Max_Font_Size
End Function

Public Function Console_FontColor(ByVal consoleIndex As Integer, ByVal ConsoleID As Integer) As Long
    Console_FontColor = Trim(Console(ConsoleID, consoleIndex).FontColor)
    
    If Console_FontColor = 0 Then
        'if no color is specified, make it white
        Console_FontColor = Console_Line_Defaults.FontColor
    End If

End Function

Public Function Console_FontName(ByVal consoleIndex As Integer, ByVal ConsoleID As Integer) As String
    Console_FontName = Trim(Console(ConsoleID, consoleIndex).FontName)
    
    'only allow certain fonts that exist on all computers
    If Is_Valid_Font(Console_FontName) = True Then
        'the font name is ok
        Console_FontName = Trim(Console_FontName)
        Exit Function
    Else
        Console_FontName = Console_Line_Defaults.FontName
    End If
End Function

Public Function Console_Line_Defaults() As ConsoleLine
    Console_Line_Defaults.Caption = ""
    Console_Line_Defaults.FontBold = RegLoad("Default_FontBold", "True")
    Console_Line_Defaults.FontItalic = RegLoad("Default_FontItalic", "False")
    Console_Line_Defaults.FontName = RegLoad("Default_FontName", "Verdana")
    Console_Line_Defaults.FontSize = RegLoad("Default_FontSize", "10")
    Console_Line_Defaults.FontUnderline = RegLoad("Default_FontUnderline", "False")
    Console_Line_Defaults.FontColor = RegLoad("Default_FontColor", RGB(255, 255, 255))
    Console_Line_Defaults.DrawEnabled = False
    Console_Line_Defaults.Flash = False
    Console_Line_Defaults.FlashFast = False
    Console_Line_Defaults.FlashSlow = False
    Console_Line_Defaults.Center = False
    Console_Line_Defaults.Right = False
End Function

Public Function Font_Height(ByVal theFontName As String, ByVal theFontSize As String) As Long
    frmConsole.lfont.FontName = theFontName
    frmConsole.lfont.FontSize = theFontSize
    frmConsole.lfont.Caption = "this is to check the height OF FONTS"
    Font_Height = frmConsole.lfont.Height + yDiv
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
    Console(ConsoleID, 1).Caption = Console(ConsoleID, 1).Caption & Replace(CurrentPromptInput(ConsoleID), ConsoleInvisibleChar, "")
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

    s = StripAfterNewline(s)
    s = Replace(s, ConsoleInvisibleChar, "")

    Dim propertySpace As String

    If Not NoReset Then
        Console(ConsoleID, OverwriteLineIndex) = Console_Line_Defaults
        Console(ConsoleID, OverwriteLineIndex).PreSpace = True
    End If

    If Has_Property_Space(s) = True Then
        propertySpace = i(Get_Property_Space(s)) & " "
        propertySpace = Replace(propertySpace, ",", " ")
        If InStr(propertySpace, "noprespace") > 0 Then Console(ConsoleID, OverwriteLineIndex).PreSpace = False
        If InStr(propertySpace, "forceprespace") > 0 Then Console(ConsoleID, OverwriteLineIndex).PreSpace = True
        Console(ConsoleID, OverwriteLineIndex).FontColor = propertySpace_Color(propertySpace)
        Console(ConsoleID, OverwriteLineIndex).FontSize = propertySpace_Size(propertySpace)
        Console(ConsoleID, OverwriteLineIndex).FontName = propertySpace_Name(propertySpace)
        Console(ConsoleID, OverwriteLineIndex).FontBold = propertySpace_Bold(propertySpace)
        Console(ConsoleID, OverwriteLineIndex).FontItalic = propertySpace_Italic(propertySpace)
        Console(ConsoleID, OverwriteLineIndex).FontUnderline = propertySpace_Underline(propertySpace)
        Console(ConsoleID, OverwriteLineIndex).FontStrikethru = propertySpace_Strikethru(propertySpace)
        If InStr(propertySpace, "flash ") > 0 Then Console(ConsoleID, 1).Flash = True Else Console(ConsoleID, 1).Flash = False
        If InStr(propertySpace, "flashfast ") > 0 Then Console(ConsoleID, 1).FlashFast = True Else Console(ConsoleID, 1).FlashFast = False
        If InStr(propertySpace, "flashslow ") > 0 Then Console(ConsoleID, 1).FlashSlow = True Else Console(ConsoleID, 1).FlashSlow = False
        If InStr(propertySpace, "center ") > 0 Then Console(ConsoleID, 1).Center = True Else Console(ConsoleID, 1).Center = False
        If InStr(propertySpace, "right ") > 0 Then Console(ConsoleID, 1).Right = True Else Console(ConsoleID, 1).Right = False
    End If

    Console(ConsoleID, OverwriteLineIndex).Caption = Remove_Property_Space(s)

    frmConsole.QueueConsoleRender
    DoEvents
End Function

Public Function Load_Property_Space(ByVal propertySpace As String, sCaption As String) As ConsoleLine
    propertySpace = " " & Replace(propertySpace, ",", " ") & " "

    Load_Property_Space = Console_Line_Defaults
    Load_Property_Space.Caption = sCaption
    If InStr(propertySpace, "noprespace") > 0 Then Load_Property_Space.PreSpace = False
    If InStr(propertySpace, "forceprespace") > 0 Then Load_Property_Space.PreSpace = True
    Load_Property_Space.FontColor = propertySpace_Color(propertySpace)
    Load_Property_Space.FontSize = propertySpace_Size(propertySpace)
    Load_Property_Space.FontName = propertySpace_Name(propertySpace)
    Load_Property_Space.FontBold = propertySpace_Bold(propertySpace)
    Load_Property_Space.FontItalic = propertySpace_Italic(propertySpace)
    Load_Property_Space.FontUnderline = propertySpace_Underline(propertySpace)
    Load_Property_Space.FontStrikethru = propertySpace_Strikethru(propertySpace)
    If InStr(propertySpace, "flash ") > 0 Then Load_Property_Space.Flash = True Else Load_Property_Space.Flash = False
    If InStr(propertySpace, "flashfast ") > 0 Then Load_Property_Space.FlashFast = True Else Load_Property_Space.FlashFast = False
    If InStr(propertySpace, "flashslow ") > 0 Then Load_Property_Space.FlashSlow = True Else Load_Property_Space.FlashSlow = False
    If InStr(propertySpace, "center ") > 0 Then Load_Property_Space.Center = True Else Load_Property_Space.Center = False
    If InStr(propertySpace, "right ") > 0 Then Load_Property_Space.Right = True Else Load_Property_Space.Right = False
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

Public Function propertySpace_Name(ByVal s As String) As String
    propertySpace_Name = Console_Line_Defaults.FontName
    s = i(s)
    
    If InStr(s, "arial") > 0 Then propertySpace_Name = "Arial"
    If InStr(s, "arial black") > 0 Then propertySpace_Name = "Arial Black"
    If InStr(s, "comic sans ms") > 0 Then propertySpace_Name = "Comic Sans MS"
    If InStr(s, "courier new") > 0 Then propertySpace_Name = "Courier New"
    If InStr(s, "georgia") > 0 Then propertySpace_Name = "Georgia"
    If InStr(s, "impact") > 0 Then propertySpace_Name = "Impact"
    If InStr(s, "lucida console") > 0 Then propertySpace_Name = "Lucida Console"
    If InStr(s, "tahoma") > 0 Then propertySpace_Name = "Tahoma"
    If InStr(s, "times new roman") > 0 Then propertySpace_Name = "Times New Roman"
    If InStr(s, "trebuchet ms") > 0 Then propertySpace_Name = "Trebuchet MS"
    If InStr(s, "verdana") > 0 Then propertySpace_Name = "Verdana"
    If InStr(s, "wingdings") > 0 Then propertySpace_Name = "Wingdings"
    

End Function

Public Function propertySpace_Bold(ByVal s As String) As Boolean
    propertySpace_Bold = True
    s = i(s)
    
    If InStr(s, "bold") > 0 Then propertySpace_Bold = True
    If InStr(s, "nobold") > 0 Then propertySpace_Bold = False
End Function

Public Function propertySpace_Italic(ByVal s As String) As Boolean
    propertySpace_Italic = False
    s = i(s)
    
    If InStr(s, "italic") > 0 Then propertySpace_Italic = True
    If InStr(s, "noitalic") > 0 Then propertySpace_Italic = False
End Function

Public Function propertySpace_Strikethru(ByVal s As String) As Boolean
    propertySpace_Strikethru = False
    s = i(s)
    
    If InStr(s, "strikethru") > 0 Then propertySpace_Strikethru = True
    If InStr(s, "strikethrough") > 0 Then propertySpace_Strikethru = True
    If InStr(s, "nostrikethru") > 0 Then propertySpace_Strikethru = False
    If InStr(s, "nostrikethrough") > 0 Then propertySpace_Strikethru = False
    
End Function

Public Function propertySpace_Underline(ByVal s As String) As Boolean
    propertySpace_Underline = False
    s = i(s)
    
    If InStr(s, "underline") > 0 Then propertySpace_Underline = True
    If InStr(s, "nounderline") > 0 Then propertySpace_Underline = False
End Function

Public Function propertySpace_Color(ByVal s As String) As Long
    propertySpace_Color = 777
    s = i(s)
    
    If InStr(s, "white") Then propertySpace_Color = vbWhite
    If InStr(s, "black") Then propertySpace_Color = vbBlack + 1
    
    If InStr(s, "purple") Then propertySpace_Color = iPurple
    If InStr(s, "pink") Then propertySpace_Color = iPink
    If InStr(s, "orange") Then propertySpace_Color = iOrange
    If InStr(s, "lorange") Then propertySpace_Color = iLightOrange
    
    If InStr(s, "blue") Then propertySpace_Color = iBlue
    If InStr(s, "dblue") Then propertySpace_Color = iDarkBlue
    If InStr(s, "lblue") Then propertySpace_Color = iLightBlue
    
    If InStr(s, "green") Then propertySpace_Color = iGreen
    If InStr(s, "dgreen") Then propertySpace_Color = iDarkGreen
    If InStr(s, "lgreen") Then propertySpace_Color = iLightGreen
    
    If InStr(s, "gold") Then propertySpace_Color = iGold
    If InStr(s, "yellow") Then propertySpace_Color = iYellow
    If InStr(s, "lyellow") Then propertySpace_Color = iLightYellow
    If InStr(s, "dyellow") Then propertySpace_Color = iDarkYellow
    
    If InStr(s, "brown") Then propertySpace_Color = iBrown
    If InStr(s, "lbrown") Then propertySpace_Color = iLightBrown
    If InStr(s, "dbrown") Then propertySpace_Color = iDarkBrown
    If InStr(s, "maroon") Then propertySpace_Color = iMaroon
    
    If InStr(s, "grey") Then propertySpace_Color = iGrey
    If InStr(s, "dgrey") Then propertySpace_Color = iDarkGrey
    If InStr(s, "lgrey") Then propertySpace_Color = iLightGrey
    
    If InStr(s, "red") Then propertySpace_Color = iRed
    If InStr(s, "lred") Then propertySpace_Color = iLightRed
    If InStr(s, "dred") Then propertySpace_Color = iDarkRed
    
    If InStr(s, "rgb:") Then
        Dim Error, R, G, b
        
        Error = False
        
        'Dim sTmp As String

        's = Replace(s, ",", " ")
        'sTmp = Mid(s, InStr(s, "rgb:"), Len(s))
        'sTmp = Replace(sTmp, ":", " ") & " "
        

        'R = Trim(GetPart(sTmp, 2, " "))
        'G = Trim(GetPart(sTmp, 3, " "))
        'B = Trim(GetPart(sTmp, 4, " "))
        
           Dim sTmp As String

        s = Replace(s, ",", " ")
        sTmp = Mid(s, InStr(s, "rgb:"), Len(s))
        sTmp = Replace(sTmp, ":", " :") & " "
        
        Dim sSplit() As String
        sSplit = Split(sTmp, ":")
        
        R = Trim(sSplit(1))
        G = Trim(sSplit(2))
        b = Trim(sSplit(3))

        If IsNumeric(R) And IsNumeric(G) And IsNumeric(b) Then
            R = CInt(R)
            G = CInt(G)
            b = CInt(b)
        
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
    End If
    
    If propertySpace_Color = 777 Then propertySpace_Color = Console_Line_Defaults.FontColor
End Function

Public Function propertySpace_Size(ByVal s As String) As String
    propertySpace_Size = 777
    s = Replace(s, "{{", " "): s = Replace(s, "}}", " ")
    s = " " & i(Replace(s, ",", " ")) & " "
    
    Dim n As Integer
    For n = 1 To 144
        If InStr(s, " " & Trim(Str(n)) & " ") > 0 Then
            propertySpace_Size = Trim(Str(n))
        End If
    Next n
    

    If propertySpace_Size = 777 Then propertySpace_Size = Console_Line_Defaults.FontSize

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
