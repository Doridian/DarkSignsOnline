Attribute VB_Name = "basConsole"
Option Explicit

'there are 4 consoles, the current console will be 1, 2, 3 or 4
Public ActiveConsole As Integer

Public ConsoleHistory(1 To 4, 1 To 9999) As ConsoleLine
Public Console(1 To 4, 0 To 299) As ConsoleLine
Public CurrentLine(1 To 4) As Integer
Public ConsoleScrollInt(1 To 4) As Integer

Public scrConsoleContext(1 To 4) As clsScriptFunctions

Public ConsolePaused(1 To 4) As Boolean

Private Base64 As New clsBase64

Public Type ConsoleLine
    Caption As String
    
    FontColor As Long
    FontName As String
    FontSize As String
    FontBold As Boolean
    FontItalic As Boolean
    FontStrikeThru As Boolean
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

Public RecentCommandsIndex(1 To 4) As Integer
Public RecentCommands(1 To 4, 0 To 99) As String

Public LimitedCommandString As String

Public yDiv As Integer  'the amount of vertical space between each console line

Public Const DrawDividerWidth = 24
Public Const Max_Font_Size = 144
Public Const PreSpace = "-->" 'this will indent the text


Public Sub Add_Key(ByVal KeyCode As Integer, ByVal Shift As Integer, ByVal ConsoleID As Integer)
    If frmConsole.ChatBox.Visible = True Then Exit Sub
    
    Dim tmpS As String
    
    If KeyCode = vbKeySpace Then Insert_Char " ", ConsoleID: Exit Sub
    If KeyCode = vbKeyBack Then RemLastKey ConsoleID: Exit Sub
    If KeyCode = vbKeyDelete Then RemNextKey ConsoleID: Exit Sub
    If KeyCode = vbKeyHome Then MoveUnderscoreToHome ConsoleID: Exit Sub
    If KeyCode = vbKeyEnd Then MoveUnderscoreToEnd ConsoleID: Exit Sub
    If KeyCode = vbKeyLeft Then MoveUnderscoreLeft ConsoleID: Exit Sub
    If KeyCode = vbKeyRight Then MoveUnderscoreRight ConsoleID: Exit Sub
    
    If KeyCode = vbKeyReturn Then

        RecentCommandsIndex(ConsoleID) = 0
        'kill the no longer required underscore
        Console(ConsoleID, CurrentLine(ConsoleID)).Caption = Replace(Console(ConsoleID, CurrentLine(ConsoleID)).Caption, "_", "")
        'save in recent typed commands
        AddToRecentCommands Console(ConsoleID, CurrentLine(ConsoleID)).Caption
        
        'process the command, unless it is input
        If WaitingForInput(ConsoleID) = True Then
            tmpS = ""
            tmpS = Trim(Console(ConsoleID, CurrentLine(ConsoleID)).Caption)
            If InStr(tmpS, ">") > 0 Then tmpS = Mid(tmpS, InStr(tmpS, ">") + 1, Len(tmpS))
            If Left(tmpS, 1) = " " Then tmpS = Mid(tmpS, 2, Len(tmpS))
            Vars(WaitingForInput_VarIndex(ConsoleID)).VarValue = tmpS
            cPath(ConsoleID) = cPath_tmp(ConsoleID)
            WaitingForInput(ConsoleID) = False
            Shift_Console_Lines ConsoleID
            Console(ConsoleID, CurrentLine(ConsoleID)).Caption = Console_Prompt(True, ConsoleID)
            Console(ConsoleID, CurrentLine(ConsoleID)) = Console_Line_Defaults
        Else
            
            Run_Command Console(ConsoleID, CurrentLine(ConsoleID)), ConsoleID, False
            
        End If

        Exit Sub
    End If
    
    
    'letters upper case ascii codes
    If KeyCode >= 65 And KeyCode <= 90 Then
        If Shift = 1 Then
            Insert_Char UCase(Chr(KeyCode)), ConsoleID
        Else
            Insert_Char LCase(Chr(KeyCode)), ConsoleID
            GoTo End_Function
        End If
    End If
    'letters lower case ascii codes
'    If KeyCode >= 97 And KeyCode <= 122 Then
'        If Shift = 1 Then Insert_Char UCase(Chr(KeyCode)) Else: Insert_Char LCase(Chr(KeyCode))
'        GoTo End_Function
'    End If
    'numbers
    If KeyCode >= 48 And KeyCode <= 57 Then
        Select Case KeyCode
        Case 48: If Shift = 1 Then Insert_Char ")", ConsoleID Else Insert_Char "0", ConsoleID
        Case 49: If Shift = 1 Then Insert_Char "!", ConsoleID Else Insert_Char "1", ConsoleID
        Case 50: If Shift = 1 Then Insert_Char "@", ConsoleID Else Insert_Char "2", ConsoleID
        Case 51: If Shift = 1 Then Insert_Char "#", ConsoleID Else Insert_Char "3", ConsoleID
        Case 52: If Shift = 1 Then Insert_Char "$", ConsoleID Else Insert_Char "4", ConsoleID
        Case 53: If Shift = 1 Then Insert_Char "%", ConsoleID Else Insert_Char "5", ConsoleID
        Case 54: If Shift = 1 Then Insert_Char "^", ConsoleID Else Insert_Char "6", ConsoleID
        Case 55: If Shift = 1 Then Insert_Char "&", ConsoleID Else Insert_Char "7", ConsoleID
        Case 56: If Shift = 1 Then Insert_Char "*", ConsoleID Else Insert_Char "8", ConsoleID
        Case 57: If Shift = 1 Then Insert_Char "(", ConsoleID Else Insert_Char "9", ConsoleID
        End Select
        GoTo End_Function
    End If
    'everything else
    Select Case KeyCode
        Case "192": If Shift = 1 Then Insert_Char "~", ConsoleID Else Insert_Char "`", ConsoleID
        Case "189": If Shift = 1 Then Insert_Char "-", ConsoleID Else Insert_Char "-", ConsoleID
        Case "187": If Shift = 1 Then Insert_Char "+", ConsoleID Else Insert_Char "=", ConsoleID
        Case "219": If Shift = 1 Then Insert_Char "{", ConsoleID Else Insert_Char "[", ConsoleID
        Case "221": If Shift = 1 Then Insert_Char "}", ConsoleID Else Insert_Char "]", ConsoleID
        Case "220": If Shift = 1 Then Insert_Char "|", ConsoleID Else Insert_Char "\", ConsoleID
        Case "186": If Shift = 1 Then Insert_Char ":", ConsoleID Else Insert_Char ";", ConsoleID
        Case "222": If Shift = 1 Then Insert_Char Chr(34), ConsoleID Else Insert_Char "'", ConsoleID
        Case "188": If Shift = 1 Then Insert_Char "<", ConsoleID Else Insert_Char ",", ConsoleID
        Case "190": If Shift = 1 Then Insert_Char ".", ConsoleID Else Insert_Char ".", ConsoleID
        Case "191": If Shift = 1 Then Insert_Char "?", ConsoleID Else Insert_Char "/", ConsoleID
        'numpad below
        Case "110": Insert_Char ".", ConsoleID
        Case "111": Insert_Char "/", ConsoleID
        Case "106": Insert_Char "*", ConsoleID
        Case "109": Insert_Char "-", ConsoleID
        Case "107": Insert_Char "+", ConsoleID
        
        
        'Case 33: If Shift = 1 Then Insert_Char "!" , consoleID Else Insert_Char "1", consoleID
        'Case 34: If Shift = 1 Then Insert_Char Chr(34) , consoleID Else Insert_Char "'", consoleID
        Case 35: If Shift = 1 Then Insert_Char "#", ConsoleID Else Insert_Char "3", ConsoleID
        Case 36: If Shift = 1 Then Insert_Char "$", ConsoleID Else Insert_Char "4", ConsoleID
        'Case 37: If Shift = 1 Then Insert_Char "%", consoleID  Else Insert_Char "5", consoleID
        'Case 38: If Shift = 1 Then Insert_Char "&", consoleID  Else Insert_Char "7", consoleID
        'Case 39: If Shift = 1 Then Insert_Char Chr(34), consoleID Else Insert_Char "'", consoleID
        'Case 40: If Shift = 1 Then Insert_Char "(" , consoleID Else Insert_Char "9", consoleID
        Case 41: If Shift = 1 Then Insert_Char ")", ConsoleID Else Insert_Char "0", ConsoleID
        Case 42: If Shift = 1 Then Insert_Char "*", ConsoleID Else Insert_Char "8", ConsoleID
        Case 43: If Shift = 1 Then Insert_Char "+", ConsoleID Else Insert_Char "=", ConsoleID
        Case 44: If Shift = 1 Then Insert_Char "<", ConsoleID Else Insert_Char ",", ConsoleID
        'Case 45: If Shift = 1 Then Insert_Char "-", consoleID  Else Insert_Char "-", consoleID
        Case 46: If Shift = 1 Then Insert_Char ".", ConsoleID Else Insert_Char ".", ConsoleID
        Case 47: If Shift = 1 Then Insert_Char "?", ConsoleID Else Insert_Char "/", ConsoleID
        Case 58: If Shift = 1 Then Insert_Char ":", ConsoleID Else Insert_Char ";", ConsoleID
        Case 59: If Shift = 1 Then Insert_Char ":", ConsoleID Else Insert_Char ";", ConsoleID
        Case 60: If Shift = 1 Then Insert_Char "<", ConsoleID Else Insert_Char ",", ConsoleID
        Case 61: If Shift = 1 Then Insert_Char "+", ConsoleID Else Insert_Char "=", ConsoleID
        Case 62: If Shift = 1 Then Insert_Char ".", ConsoleID Else Insert_Char ".", ConsoleID
        Case 63: If Shift = 1 Then Insert_Char "?", ConsoleID Else Insert_Char "/", ConsoleID
        Case 64: If Shift = 1 Then Insert_Char "@", ConsoleID Else Insert_Char "2", ConsoleID
        
        'numpad stuff
        Case 96: Insert_Char "0", ConsoleID
        Case 97: Insert_Char "1", ConsoleID
        Case 98: Insert_Char "2", ConsoleID
        Case 99: Insert_Char "3", ConsoleID
        Case 100: Insert_Char "4", ConsoleID
        Case 101: Insert_Char "5", ConsoleID
        Case 102: Insert_Char "6", ConsoleID
        Case 103: Insert_Char "7", ConsoleID
        Case 104: Insert_Char "8", ConsoleID
        Case 105: Insert_Char "9", ConsoleID
        
        
        
        
    End Select
    
    
End_Function:
End Sub



Public Sub AddToRecentCommands(ByVal S As String)
    If InStr(S, ">") > 0 Then S = Mid(S, InStr(S, ">") + 1, Len(S))
    If Trim(S) = "" Then Exit Sub
        
    If i(S) = RecentCommands(ActiveConsole, 1) Then GoTo SkipAddingIt
    

    Dim n As Integer
    For n = 99 To 2 Step -1
        RecentCommands(ActiveConsole, n) = RecentCommands(ActiveConsole, n - 1)
    Next n


SkipAddingIt:
    RecentCommands(ActiveConsole, 1) = Trim(S)
    RecentCommands(ActiveConsole, 0) = ""
    RecentCommandsIndex(ActiveConsole) = 0
End Sub

Public Sub MoveUnderscoreRight(ByVal ConsoleID As Integer)
    On Error GoTo zxc
    Dim part1 As String, part2 As String, S As String
    
    S = Console(ConsoleID, CurrentLine(ConsoleID)).Caption
    If Right(S, 1) = "_" Then Exit Sub
    
    If InStr(S, "_") = 0 Then Exit Sub
    part1 = Mid(S, 1, InStr(S, "_") + 1)
    part2 = Mid(S, InStr(S, "_") + 2, Len(S))
    
    S = Replace(part1, "_", "") & "_" & part2
    

    'If InStr(s, "_") < Len(Console_Prompt(True)) Then Exit Sub
    
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = S
zxc:
End Sub

Public Sub MoveUnderscoreToHome(ByVal ConsoleID As Integer)
    On Error GoTo zxc
    Dim S As String
    S = Console(ConsoleID, CurrentLine(ConsoleID)).Caption
    If InStr(S, "_") = 0 Then Exit Sub
    

    S = Console_Prompt(False, ConsoleID) & "_" & Trim(Replace(Mid(S, Len(Console_Prompt(False, ConsoleID)), 999), "_", ""))

    
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = S
zxc:
End Sub

Public Sub MoveUnderscoreToEnd(ByVal ConsoleID As Integer)
    On Error GoTo zxc
    Dim S As String
    S = Console(ConsoleID, CurrentLine(ConsoleID)).Caption
    
    S = Replace(S, "_", "") & "_"

    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = S
zxc:
End Sub

Public Sub MoveUnderscoreLeft(ByVal ConsoleID As Integer)
    On Error GoTo zxc
    Dim part1 As String, part2 As String, S As String
    
    S = Console(ConsoleID, CurrentLine(ConsoleID)).Caption
    If InStr(S, "_") = 0 Then Exit Sub
    part1 = Mid(S, 1, InStr(S, "_") - 2)
    part2 = Mid(S, InStr(S, "_") - 1, Len(S))
    
    S = part1 & "_" & Replace(part2, "_", "")
    
    If InStr(S, "_") < Len(Console_Prompt(True, ConsoleID)) Then Exit Sub
    
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = S
zxc:
End Sub

Public Sub Insert_Char(ByVal sChar As String, ByVal ConsoleID As Integer)
    Dim tmpS As String
    
    tmpS = Replace(Console(ConsoleID, CurrentLine(ConsoleID)).Caption, "_", sChar + "_")
    
    
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = tmpS
    
    DoEvents
End Sub

Public Sub New_Console_Line_InProgress(ByVal ConsoleID As Integer)
    Shift_Console_Lines ConsoleID
    
    Console(ConsoleID, CurrentLine(ConsoleID)) = Console_Line_Defaults
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = " "
End Sub

Public Sub New_Console_Line(ByVal ConsoleID As Integer)
    Shift_Console_Lines ConsoleID
    
    Console(ConsoleID, CurrentLine(ConsoleID)) = Console_Line_Defaults
    'add the standard prompt if required
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = Console_Prompt(True, ConsoleID)
End Sub

Public Sub Shift_Console_Lines(ByVal ConsoleID As Integer)


    Dim n As Integer
    For n = 299 To 2 Step -1
        Console(ConsoleID, n) = Console(ConsoleID, n - 1)
    Next n
    
    '--------------------------------------------------
    ' if the line is just something like "/> _" , it should be blanked
    If InStr(Console(ConsoleID, 2).Caption, ">") > 0 Then
        If Trim(Mid(Console(ConsoleID, 2).Caption, InStr(Console(ConsoleID, 2).Caption, ">") + 1, 99)) = "_" Then
            Console(ConsoleID, 2).Caption = ""
        End If
    End If
    '--------------------------------------------------
    
    DoEvents
End Sub

Public Sub Shift_Console_Lines_Reverse(ByVal ConsoleID As Integer)
    
        
    Dim n As Integer
    For n = 0 To 298
        Console(ConsoleID, n) = Console(ConsoleID, n + 1)
    Next n
    
    DoEvents
End Sub

Public Sub RemLastKey(ByVal ConsoleID As Integer)
    On Error GoTo zxc
    
    'backspace
    Dim tmpS As String
    tmpS = Console(ConsoleID, CurrentLine(ConsoleID)).Caption
    
    'tmpS = Remove_Property_Space(tmpS) 'this was causing the backspace error
    
    
    If InStr(tmpS, "_") = 0 Then Exit Sub 'no underscore found = error -> exit
    
    Dim part1 As String, part2 As String
    part1 = Mid(tmpS, 1, InStr(tmpS, "_") - 2)
    part2 = Mid(tmpS, InStr(tmpS, "_") + 1, Len(tmpS))
    

    tmpS = part1 & "_" & part2
    
    If Len(part1) < Len(Console_Prompt(False, ConsoleID)) Then Exit Sub
    
    
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = tmpS
zxc:
End Sub

Public Sub RemNextKey(ByVal ConsoleID As Integer)
    On Error GoTo zxc
    
    'backspace
    Dim tmpS As String
    tmpS = Console(ConsoleID, CurrentLine(ConsoleID)).Caption
    If InStr(tmpS, "_") = 0 Then Exit Sub 'no underscore found = error -> exit
    
    Dim part1 As String, part2 As String
    part1 = Mid(tmpS, 1, InStr(tmpS, "_") - 1)
    part2 = Mid(tmpS, InStr(tmpS, "_") + 2, Len(tmpS))
    


    tmpS = part1 & "_" & part2
    
    
        'it's regular input, don't allow it to backspace beyond the input string
        If Len(part1) < Len(Console_Prompt(False, ConsoleID)) Then Exit Sub

    
    
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = tmpS
zxc:
End Sub

Public Sub Reset_Console(ByVal ConsoleID As Integer)
    
    Dim n As Integer
    For n = 1 To 299
        Console(ConsoleID, n) = Console_Line_Defaults
    Next n

    CurrentLine(ConsoleID) = 1
    
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = Console_Prompt(True, ConsoleID)
    
End Sub

Public Sub Print_Console(Optional ForcePrintConsole As Boolean = False)
    
    On Error Resume Next
    
    If ForcePrintConsole = True Then GoTo zzz

     
    Dim sText As String * 255

    If i(Left$(sText, GetWindowText(GetForegroundWindow, ByVal sText, 255))) = i(frmConsole.Caption) Then
    Else
        'save RESOURCES!!!!!!!! YAY!!!!!!!!!!
        'exit sub - don't print if frmConsole is NOT the active window
        'save RESOURCES!!!!!!!! YAY!!!!!!!!!!
        Exit Sub
    End If
    
    
    
    
    
zzz:
    Dim n As Integer, n2 As Integer, tmpY As Long, tmpY2 As Long, printHeight As Long, tmpS As String, isAligned As Boolean
    n = 0
    
    
    frmConsole.Cls
    
    Dim addOn As Long, propertySpace As String
    addOn = ConsoleScrollInt(ActiveConsole) * 2400
    printHeight = frmConsole.Height - 840 + addOn 'Font_Height(Console_FontName(1), Console_FontSize(1)) - 360
    frmConsole.CurrentY = printHeight
    



    n = 0
    Do
        n = n + 1
    

    
        If Trim(Console(ActiveConsole, n).Caption) <> "" Then
                        
            'does a new property space need to be set?
            If InStr(Console(ActiveConsole, n).Caption, "{") > 0 And WaitingForInput(ActiveConsole) = True Then
                If Has_Property_Space(Console(ActiveConsole, n).Caption) = True Then
                    propertySpace = Get_Property_Space(Console(ActiveConsole, n).Caption)
                    Console(ActiveConsole, n) = Load_Property_Space(propertySpace, Console(ActiveConsole, n).Caption)
                    
                    Console(ActiveConsole, n).Caption = Remove_Property_Space(Console(ActiveConsole, n).Caption)
                    cPath(ActiveConsole) = Remove_Property_Space(cPath(ActiveConsole))
                End If
            End If

            
            
            printHeight = printHeight - Font_Height(Console_FontName(n, ActiveConsole), Console_FontSize(n, ActiveConsole))
            

            
            frmConsole.CurrentY = printHeight
            
            
            
            
            '--------------- DRAW ------------------------------------------
            '--------------- DRAW ------------------------------------------
                If Console(ActiveConsole, n).DrawEnabled = True Then
                    tmpY = frmConsole.CurrentY
                    tmpY2 = tmpY - (yDiv / 2)
                    
                    frmConsole.CurrentY = tmpY
                    
                    If i(Console(ActiveConsole, n).DrawMode) = "solid" Then
                            'draw it all in one, much faster
                            frmConsole.Line _
                            (((frmConsole.Width / DrawDividerWidth) * 0), tmpY2)- _
                            ((frmConsole.Width / DrawDividerWidth) * _
                            (DrawDividerWidth), _
                            (tmpY2 + Font_Height(Console_FontName(n, ActiveConsole), Console_FontSize(n, ActiveConsole)))), _
                            Console(ActiveConsole, n).DrawColors(1), BF
                    Else
                        For n2 = 1 To DrawDividerWidth
                            frmConsole.Line _
                            (((frmConsole.Width / DrawDividerWidth) * (n2 - 1)), tmpY2)- _
                            ((frmConsole.Width / DrawDividerWidth) * _
                            (n2), _
                            (tmpY2 + Font_Height(Console_FontName(n, ActiveConsole), Console_FontSize(n, ActiveConsole)))), _
                            Console(ActiveConsole, n).DrawColors(n2), BF
                        Next n2
                    End If
                
                    frmConsole.CurrentY = tmpY
                End If
DontDraw:
            '--------------- DRAW ------------------------------------------
            '--------------- DRAW ------------------------------------------
            
            
               
               
               
            
            
            
            frmConsole.FontBold = Console(ActiveConsole, n).FontBold
            frmConsole.FontItalic = Console(ActiveConsole, n).FontItalic
            frmConsole.FontUnderline = Console(ActiveConsole, n).FontUnderline
            frmConsole.FontStrikeThru = Console(ActiveConsole, n).FontStrikeThru
            
            
            frmConsole.FontSize = Console_FontSize(n, ActiveConsole)
            
            frmConsole.FontName = Console_FontName(n, ActiveConsole)
            frmConsole.ForeColor = Console_FontColor(n, ActiveConsole)
            
            tmpS = Console(ActiveConsole, n).Caption
            
   
   
            
            If Trim(tmpS) = "-" Or Trim(tmpS) = PreSpace & "-" Then
                frmConsole.Print "  " 'new line
            Else
                frmConsole.CurrentX = 360
            
                If Console(ActiveConsole, n).Flash = True And Flash = True Then GoTo SkipPrint
                If Console(ActiveConsole, n).FlashFast = True And FlashFast = True Then GoTo SkipPrint
                If Console(ActiveConsole, n).FlashSlow = True And FlashSlow = True Then GoTo SkipPrint
                
                'make underscore flash
                If n = 1 And Flash = True Then If Right(tmpS, 1) = "_" Then tmpS = Replace(tmpS, "_", " ")
                
                isAligned = False
                
                If Console(ActiveConsole, n).Center = True Then
                    frmConsole.lfont.FontSize = Console(ActiveConsole, n).FontSize: frmConsole.lfont.FontName = Console(ActiveConsole, n).FontName: frmConsole.lfont.Caption = Trim(Replace(Console(ActiveConsole, n).Caption, PreSpace, ""))
                    frmConsole.CurrentX = (frmConsole.Width / 2) - (frmConsole.lfont.Width / 2)
                    isAligned = True
                End If
                If Console(ActiveConsole, n).Right = True Then
                    frmConsole.lfont.FontSize = Console(ActiveConsole, n).FontSize: frmConsole.lfont.FontName = Console(ActiveConsole, n).FontName: frmConsole.lfont.Caption = Replace(Console(ActiveConsole, n).Caption, PreSpace, "")
                    frmConsole.CurrentX = (frmConsole.Width) - (frmConsole.lfont.Width) - 360
                    isAligned = True
                End If
                
                If InStr(tmpS, "**") > 0 Then tmpS = Replace(tmpS, "(**", "{"): tmpS = Replace(tmpS, "**)", "}")
                
                
                
                'frmConsole.CurrentY = frmConsole.CurrentY + (ConsoleScrollInt * (2400))
                
 
                
                If InStr(tmpS, PreSpace) > 0 Then
                    If isAligned <> True Then frmConsole.CurrentX = 960
                    tmpS = Replace(tmpS, PreSpace, "")
                   
                   
                    frmConsole.Print tmpS
                    
'                    If Console(ActiveConsole, n).DrawEnabled = True Then
'                        DoEvents
'                        DoEvents
'                        MsgBox tmpS
'                    End If
                Else
                    frmConsole.Print tmpS
                End If
            
                
                
                GoTo NextOne
SkipPrint:
                frmConsole.Print "  "
            End If
NextOne:

        End If
        
        
        If n >= 299 Then GoTo ExitLoop

    Loop Until printHeight < 0
ExitLoop:
    
End Sub


Public Function Console_FontSize(ByVal consoleIndex As Integer, ByVal ConsoleID As Integer) As String
    Console_FontSize = Trim(Console(ConsoleID, consoleIndex).FontSize)
    
    'if not specified, get the defaul
    If Console_FontSize = "" Then
        Console_FontSize = RegLoad("Default_FontSize", "10")
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
        Console_FontColor = RegLoad("Default_FontColor", RGB(255, 255, 255))
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
        Console_FontName = RegLoad("Default_FontName", "Verdana")
    End If
    
End Function

Public Function Console_Prompt(ByVal includeUnderscore As Boolean, ByVal ConsoleID As Integer) As String
    'get the console prompt that asks the user to enter information
    Dim ext As String
    If includeUnderscore = True Then ext = "_" Else ext = ""
    
    Console_Prompt = cPath(ConsoleID) & ">" & " " & ext
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
    

    
    'Randomize
    'Console_Line_Defaults.FontSize = (Rnd * 14) + 10
    
    
End Function

Public Function Font_Height(theFontName As String, theFontSize As String) As Integer
    frmConsole.lfont.FontName = theFontName
    frmConsole.lfont.FontSize = theFontSize
    Font_Height = frmConsole.lfont.Height + yDiv
End Function

Public Sub SayAll(ByVal ConsoleID As Integer, S As String, Optional withNewLineAfter As Boolean = True, Optional FromScript As Boolean = False, Optional SkipPropertySpace As Integer)
    Dim sA() As String
    S = Replace(S, "$newilne", vbCrLf)
    sA = Split(S, vbCrLf)
    
    
    Dim n As Long, rc As Long
    For n = 0 To UBound(sA)
        
        SAY ConsoleID, sA(n), withNewLineAfter, FromScript, SkipPropertySpace
        
    
        
        rc = rc + 1
        If rc Mod 20 = 0 Then
            PauseConsole "", ConsoleID
            
        Else
            If n < UBound(sA) Then
                If FromScript = True Then
                    Shift_Console_Lines ConsoleID
                End If
            End If
        End If
    Next n
    
    
End Sub

Public Function SAY(ByVal ConsoleID As Integer, S As String, Optional withNewLineAfter As Boolean = True, Optional FromScript As Boolean = False, Optional SkipPropertySpace As Integer)
    

    If ConsoleID > 4 Then Exit Function
    If Len(S) > 32763 Then S = Mid(S, 1, 32763) ' 32764 would overflow
    

    Dim tmpLine As ConsoleLine, propertySpace As String
    'save the current line
    
    If Data_For_Run_Function_Enabled(ConsoleID) = 1 Then
        Data_For_Run_Function(ConsoleID) = Data_For_Run_Function(ConsoleID) & vbCrLf & S
        Exit Function
    End If
    
    tmpLine = Console(ConsoleID, CurrentLine(ConsoleID))
    
    S = RemoveSurroundingQuotes(S)
    
    If withNewLineAfter = False And FromScript = False Then
        Shift_Console_Lines ConsoleID
        Console(ConsoleID, 1) = Console_Line_Defaults
    End If
    
    'If withNewLineAfter = False Then
    S = PreSpace & S
        
        
    
If SkipPropertySpace = 1 Then
    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = S
    GoTo SkipPropertySpaceNow
End If

    If Has_Property_Space(S) = True Then
        propertySpace = i(Get_Property_Space(S)) & " "
        propertySpace = Replace(propertySpace, ",", " ")
        Console(ConsoleID, CurrentLine(ConsoleID)).FontColor = propertySpace_Color(propertySpace)
        Console(ConsoleID, CurrentLine(ConsoleID)).FontSize = propertySpace_Size(propertySpace)
        Console(ConsoleID, CurrentLine(ConsoleID)).FontName = propertySpace_Name(propertySpace)
        Console(ConsoleID, CurrentLine(ConsoleID)).FontBold = propertySpace_Bold(propertySpace)
        Console(ConsoleID, CurrentLine(ConsoleID)).FontItalic = propertySpace_Italic(propertySpace)
        Console(ConsoleID, CurrentLine(ConsoleID)).FontUnderline = propertySpace_Underline(propertySpace)
        Console(ConsoleID, CurrentLine(ConsoleID)).FontStrikeThru = propertySpace_Strikethru(propertySpace)
        If InStr(propertySpace, "flash ") > 0 Then Console(ConsoleID, CurrentLine(ConsoleID)).Flash = True Else Console(ConsoleID, CurrentLine(ConsoleID)).Flash = False
        If InStr(propertySpace, "flashfast ") > 0 Then Console(ConsoleID, CurrentLine(ConsoleID)).FlashFast = True Else Console(ConsoleID, CurrentLine(ConsoleID)).FlashFast = False
        If InStr(propertySpace, "flashslow ") > 0 Then Console(ConsoleID, CurrentLine(ConsoleID)).FlashSlow = True Else Console(ConsoleID, CurrentLine(ConsoleID)).FlashSlow = False
        If InStr(propertySpace, "center ") > 0 Then Console(ConsoleID, CurrentLine(ConsoleID)).Center = True Else Console(ConsoleID, CurrentLine(ConsoleID)).Center = False
        If InStr(propertySpace, "right ") > 0 Then Console(ConsoleID, CurrentLine(ConsoleID)).Right = True Else Console(ConsoleID, CurrentLine(ConsoleID)).Right = False
    End If
    

    Console(ConsoleID, CurrentLine(ConsoleID)).Caption = Remove_Property_Space(S)

DoEvents


SkipPropertySpaceNow:

    
    'don't allow multiple lines!
    If InStr(Console(ConsoleID, CurrentLine(ConsoleID)).Caption, vbCr) > 0 Then
        'this prevents each say line from being more than one line, stops corruption in console
        Console(ConsoleID, CurrentLine(ConsoleID)).Caption = Mid(Console(ConsoleID, CurrentLine(ConsoleID)).Caption, 1, InStr(Console(ConsoleID, CurrentLine(ConsoleID)).Caption, vbCr) - 1)
        Console(ConsoleID, CurrentLine(ConsoleID)).Caption = Console(ConsoleID, CurrentLine(ConsoleID)).Caption  '& "   --- only the first line is shown ---"
    End If
    
    
    
    If withNewLineAfter = True Then
        'go to the next line
        New_Console_Line ConsoleID
        
        'put the current line back at the next line
        Console(ConsoleID, CurrentLine(ConsoleID)) = tmpLine
    Else
       
       
    End If
    
    DoEvents
End Function

Public Function Load_Property_Space(ByVal propertySpace As String, sCaption As String) As ConsoleLine

    

        propertySpace = " " & Replace(propertySpace, ",", " ") & " "
        
        Load_Property_Space.Caption = sCaption
        Load_Property_Space.FontColor = propertySpace_Color(propertySpace)
        Load_Property_Space.FontSize = propertySpace_Size(propertySpace)
        Load_Property_Space.FontName = propertySpace_Name(propertySpace)
        Load_Property_Space.FontBold = propertySpace_Bold(propertySpace)
        Load_Property_Space.FontItalic = propertySpace_Italic(propertySpace)
        Load_Property_Space.FontUnderline = propertySpace_Underline(propertySpace)
        Load_Property_Space.FontStrikeThru = propertySpace_Strikethru(propertySpace)
        If InStr(propertySpace, "flash ") > 0 Then Load_Property_Space.Flash = True Else Load_Property_Space.Flash = False
        If InStr(propertySpace, "flashfast ") > 0 Then Load_Property_Space.FlashFast = True Else Load_Property_Space.FlashFast = False
        If InStr(propertySpace, "flashslow ") > 0 Then Load_Property_Space.FlashSlow = True Else Load_Property_Space.FlashSlow = False
        If InStr(propertySpace, "center ") > 0 Then Load_Property_Space.Center = True Else Load_Property_Space.Center = False
        If InStr(propertySpace, "right ") > 0 Then Load_Property_Space.Right = True Else Load_Property_Space.Right = False
    
    
End Function

Public Function Is_Valid_Font(ByVal S As String) As Boolean
    'this shows the fonts that dark signs accepts as valid
    S = i(S)
    If _
    S = "arial" Or _
    S = "arial black" Or _
    S = "comic sans ms" Or _
    S = "courier new" Or _
    S = "georgia" Or _
    S = "impact" Or _
    S = "lucida console" Or _
    S = "tahoma" Or _
    S = "times new roman" Or _
    S = "trebuchet ms" Or _
    S = "verdana" Or _
    S = "wingdings" _
    Then
    
    
        Is_Valid_Font = True
    Else
        Is_Valid_Font = False
    End If
End Function

Public Function Remove_Property_Space(ByVal S As String) As String
    Dim n As Integer
    Dim isOn As Boolean
    isOn = True

    For n = 1 To Len(S)
        If Mid(S, n, 1) = "{" Then
            isOn = False
        End If
        If isOn = True Then
            Remove_Property_Space = Remove_Property_Space & Mid(S, n, 1)
        End If
        If Mid(S, n, 1) = "}" Then
            isOn = True
        End If
    Next n
End Function

Public Function Get_Property_Space(ByVal S As String) As String
    Dim n As Integer
    Dim isOn As Boolean
    isOn = False

    For n = 1 To Len(S)
        If Mid(S, n, 1) = "}" Then
            isOn = False
        End If
        If isOn = True Then
            Get_Property_Space = Get_Property_Space & Mid(S, n, 1)
        End If
        If Mid(S, n, 1) = "{" Then
            isOn = True
        End If
    Next n
End Function

Public Function Kill_Property_Space(ByVal S As String) As String
    Dim n As Integer
    Dim isOn As Boolean
    isOn = False

    For n = 1 To Len(S)
        If Mid(S, n, 1) = "{" Then
            isOn = False
        End If
        
        If isOn = True Then
            Kill_Property_Space = Kill_Property_Space & Mid(S, n, 1)
        End If
        
        If Mid(S, n, 1) = "}" Then
            isOn = True
        End If
    Next n
    
    Kill_Property_Space = Replace(Kill_Property_Space, "{", "")
    Kill_Property_Space = Replace(Kill_Property_Space, "}", "")
End Function

Public Function Has_Property_Space(ByVal S As String) As Boolean
    If InStr(S, "{") > 0 And InStr(S, "}") > 0 Then
        If InStr(S, "{") < InStr(S, "}") Then
            Has_Property_Space = True
        Else
            Has_Property_Space = False
        End If
    Else
        Has_Property_Space = False
    End If
End Function

Public Function propertySpace_Name(ByVal S As String) As String
    propertySpace_Name = RegLoad("Default_FontName", "Verdana")
    S = i(S)
    
    If InStr(S, "arial") > 0 Then propertySpace_Name = "Arial"
    If InStr(S, "arial black") > 0 Then propertySpace_Name = "Arial Black"
    If InStr(S, "comic sans ms") > 0 Then propertySpace_Name = "Comic Sans MS"
    If InStr(S, "courier new") > 0 Then propertySpace_Name = "Courier New"
    If InStr(S, "georgia") > 0 Then propertySpace_Name = "Georgia"
    If InStr(S, "impact") > 0 Then propertySpace_Name = "Impact"
    If InStr(S, "lucida console") > 0 Then propertySpace_Name = "Lucida Console"
    If InStr(S, "tahoma") > 0 Then propertySpace_Name = "Tahoma"
    If InStr(S, "times new roman") > 0 Then propertySpace_Name = "Times New Roman"
    If InStr(S, "trebuchet ms") > 0 Then propertySpace_Name = "Trebuchet MS"
    If InStr(S, "verdana") > 0 Then propertySpace_Name = "Verdana"
    If InStr(S, "wingdings") > 0 Then propertySpace_Name = "Wingdings"
    

End Function

Public Function propertySpace_Bold(ByVal S As String) As Boolean
    propertySpace_Bold = True
    S = i(S)
    
    If InStr(S, "bold") > 0 Then propertySpace_Bold = True
    If InStr(S, "nobold") > 0 Then propertySpace_Bold = False
End Function

Public Function propertySpace_Italic(ByVal S As String) As Boolean
    propertySpace_Italic = False
    S = i(S)
    
    If InStr(S, "italic") > 0 Then propertySpace_Italic = True
    If InStr(S, "noitalic") > 0 Then propertySpace_Italic = False
End Function

Public Function propertySpace_Strikethru(ByVal S As String) As Boolean
    propertySpace_Strikethru = False
    S = i(S)
    
    If InStr(S, "strikethru") > 0 Then propertySpace_Strikethru = True
    If InStr(S, "strikethrough") > 0 Then propertySpace_Strikethru = True
    If InStr(S, "nostrikethru") > 0 Then propertySpace_Strikethru = False
    If InStr(S, "nostrikethrough") > 0 Then propertySpace_Strikethru = False
    
End Function

Public Function propertySpace_Underline(ByVal S As String) As Boolean
    propertySpace_Underline = False
    S = i(S)
    
    If InStr(S, "underline") > 0 Then propertySpace_Underline = True
    If InStr(S, "nounderline") > 0 Then propertySpace_Underline = False
End Function

Public Function propertySpace_Color(ByVal S As String) As Long
    propertySpace_Color = 777
    S = i(S)
    
    If InStr(S, "white") Then propertySpace_Color = vbWhite
    If InStr(S, "black") Then propertySpace_Color = vbBlack + 1
    
    If InStr(S, "purple") Then propertySpace_Color = iPurple
    If InStr(S, "pink") Then propertySpace_Color = iPink
    If InStr(S, "orange") Then propertySpace_Color = iOrange
    If InStr(S, "lorange") Then propertySpace_Color = iLightOrange
    
    If InStr(S, "blue") Then propertySpace_Color = iBlue
    If InStr(S, "dblue") Then propertySpace_Color = iDarkBlue
    If InStr(S, "lblue") Then propertySpace_Color = iLightBlue
    
    If InStr(S, "green") Then propertySpace_Color = iGreen
    If InStr(S, "dgreen") Then propertySpace_Color = iDarkGreen
    If InStr(S, "lgreen") Then propertySpace_Color = iLightGreen
    
    If InStr(S, "gold") Then propertySpace_Color = iGold
    If InStr(S, "yellow") Then propertySpace_Color = iYellow
    If InStr(S, "lyellow") Then propertySpace_Color = iLightYellow
    If InStr(S, "dyellow") Then propertySpace_Color = iDarkYellow
    
    If InStr(S, "brown") Then propertySpace_Color = iBrown
    If InStr(S, "lbrown") Then propertySpace_Color = iLightBrown
    If InStr(S, "dbrown") Then propertySpace_Color = iDarkBrown
    If InStr(S, "maroon") Then propertySpace_Color = iMaroon
    
    If InStr(S, "grey") Then propertySpace_Color = iGrey
    If InStr(S, "dgrey") Then propertySpace_Color = iDarkGrey
    If InStr(S, "lgrey") Then propertySpace_Color = iLightGrey
    
    If InStr(S, "red") Then propertySpace_Color = iRed
    If InStr(S, "lred") Then propertySpace_Color = iLightRed
    If InStr(S, "dred") Then propertySpace_Color = iDarkRed
    
    If InStr(S, "rgb:") Then
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

        S = Replace(S, ",", " ")
        sTmp = Mid(S, InStr(S, "rgb:"), Len(S))
        sTmp = Replace(sTmp, ":", " :") & " "
        
        R = Trim(GetPart(sTmp, 2, ":"))
        G = Trim(GetPart(sTmp, 3, ":"))
        b = Replace(Trim(GetPart(sTmp, 4, " ")), ":", "")

        
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
    
    If propertySpace_Color = 777 Then propertySpace_Color = RegLoad("Default_FontColor", RGB(255, 255, 255))
End Function

Public Function propertySpace_Size(ByVal S As String) As String
    propertySpace_Size = 777
    S = Replace(S, "{", " "): S = Replace(S, "}", " ")
    S = " " & i(Replace(S, ",", " ")) & " "
    
    Dim n As Integer
    For n = 1 To 144
        If InStr(S, " " & Trim(Str(n)) & " ") > 0 Then
            propertySpace_Size = Trim(Str(n))
        End If
    Next n
    

    If propertySpace_Size = 777 Then propertySpace_Size = RegLoad("Default_FontSize", "10")
    
    If propertySpace_Size < 8 Then propertySpace_Size = 8
    If propertySpace_Size > Max_Font_Size Then propertySpace_Size = Max_Font_Size
End Function

Public Sub LoadLimitedCommands()
    LimitedCommandString = ":" & i(GetFile(App.Path & "\user\system\commands-security.dat")) & ":"
End Sub

Public Function EncodeBase64(ByRef arrData() As Byte) As String
    If LBound(arrData) = UBound(arrData) Then
        EncodeBase64 = ""
        Exit Function
    End If
    EncodeBase64 = Base64.EncodeByteArray(arrData)
End Function

Public Function DecodeBase64(ByVal strData As String) As Byte()
    If Len(strData) = 0 Then
        Dim EmptyData(0 To 0) As Byte
        DecodeBase64 = EmptyData
        Exit Function
    End If
    DecodeBase64 = Base64.DecodeToByteArray(strData)
End Function
