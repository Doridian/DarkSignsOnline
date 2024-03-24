Attribute VB_Name = "basCommands"
Option Explicit

Public AuthorizePayment As Boolean

Private scrConsole(1 To 4) As ScriptControl
Private scrConsoleContext(1 To 4) As clsScriptFunctions
Private scrConsoleDScript(1 To 4) As Boolean

Public Sub InitBasCommands()
    Dim X As Integer
    For X = 1 To 4
        Set scrConsole(X) = New ScriptControl
        scrConsole(X).AllowUI = False
        scrConsole(X).Timeout = 1000
        scrConsole(X).UseSafeSubset = True
        scrConsole(X).Language = "VBScript"

        Dim CLIArguments(0 To 0) As Variant
        CLIArguments(0) = "/dev/tty" & X
        Set scrConsoleContext(X) = New clsScriptFunctions
        scrConsoleContext(X).Configure X, "", True, scrConsole(X), CLIArguments, "", "", 0, False, False

        scrConsole(X).AddObject "DSO", scrConsoleContext(X), True

        scrConsoleDScript(X) = True
    Next
End Sub

Public Function SafePath(ByVal Path As String) As String
    Path = Replace(Path, "\", "/")
    If Path = ".." Or Left(Path, 3) = "../" Or Right(Path, 3) = "/.." Or InStr(Path, "/../") > 0 Then
        SafePath = App.Path & "/user/f/a/i/l/s/a/f/e.txt"
        Err.Raise vbObjectError + 9666, "DSO", "Invalid character in path"
        Exit Function
    End If

    SafePath = App.Path & "/user/" & Path
    While InStr(SafePath, "//") > 0
        SafePath = Replace(SafePath, "//", "/")
    Wend
    If Right(SafePath, 1) = "/" Then
        SafePath = Mid(SafePath, 1, Len(SafePath) - 1)
    End If
End Function

Public Function ResolvePath(ByVal ConsoleID As Integer, ByVal Path As String) As String
    If Path = "" Then
        If ConsoleID = 0 Then
            ResolvePath = ""
            Exit Function
        End If
        ResolvePath = cPath(ConsoleID)
        Exit Function
    End If

    If Left(Path, 1) = "/" Or Left(Path, 1) = "\" Or ConsoleID = 0 Then
        ResolvePath = Path
    Else
        ResolvePath = cPath(ConsoleID) & "/" & Path
    End If

    ResolvePath = Replace(ResolvePath, "\", "/")
    While InStr(ResolvePath, "//") > 0
        ResolvePath = Replace(ResolvePath, "//", "/")
    Wend

    If Left(ResolvePath, 1) = "/" Then
        ResolvePath = Mid(ResolvePath, 2)
    End If

    Dim ResolvePathSplit() As String
    ResolvePathSplit = Split(ResolvePath, "/")
    
    Dim ResolvePathSplitCut() As String
    ReDim ResolvePathSplitCut(0 To 0)

    Dim X As Long
    ResolvePath = ""
    Dim CurPath As String
    For X = LBound(ResolvePathSplit) To UBound(ResolvePathSplit)
        CurPath = ResolvePathSplit(X)
        If CurPath = "." Or CurPath = "" Then
            ' Don't do anything!
        ElseIf CurPath = ".." Then
            If UBound(ResolvePathSplitCut) > 0 Then
                ReDim Preserve ResolvePathSplitCut(0 To UBound(ResolvePathSplitCut) - 1)
            End If
        Else
            ReDim Preserve ResolvePathSplitCut(0 To UBound(ResolvePathSplitCut) + 1)
            ResolvePathSplitCut(UBound(ResolvePathSplitCut)) = CurPath
        End If
    Next X

    If UBound(ResolvePathSplitCut) = 0 Then
        ResolvePath = "/"
        Exit Function
    End If

    ResolvePathSplitCut(0) = ""
    ResolvePath = Join(ResolvePathSplitCut, "/")
End Function

Public Function ResolveCommand(ByVal ConsoleID As Integer, ByVal Command As String) As String
    If InStr(Command, "/") > 0 Or InStr(Command, "\") > 0 Then
        ResolveCommand = ResolvePath(ConsoleID, Command)
        Exit Function
    End If

    ResolveCommand = "/system/commands/" & Command & ".ds"
    If Not FileExists(ResolveCommand) Then
        ResolveCommand = ""
    End If
End Function


Public Function VBEscapeSimple(ByVal Str As String) As String
    VBEscapeSimple = Replace(Str, """", """""")
End Function


Public Function Run_Command(CLine As ConsoleLine, ByVal ConsoleID As Integer, Optional ScriptFrom As String, Optional FromScript As Boolean = True)
    If ConsoleID < 1 Then
        ConsoleID = 1
    End If
    If ConsoleID > 4 Then
        ConsoleID = 4
    End If
    Dim tmpS As String
    tmpS = CLine.Caption
    Dim promptEndIdx As Long
    promptEndIdx = InStr(tmpS, ">")
    If promptEndIdx > 0 Then
        tmpS = Mid(tmpS, promptEndIdx + 1)
    End If
    tmpS = Trim(tmpS)

    If tmpS = "" Then
        New_Console_Line ConsoleID
        Exit Function
    End If

    CancelScript(ConsoleID) = False
    New_Console_Line_InProgress ConsoleID

    scrConsoleContext(ConsoleID).Aborted = False

    Dim RunStr As String
    Dim OptionDScript As Boolean
    OptionDScript = scrConsoleDScript(ConsoleID)
    RunStr = ParseCommandLine(tmpS, OptionDScript)
    scrConsoleDScript(ConsoleID) = OptionDScript
    'SayCOMM "SHEXEC: " & RunStr, ConsoleID

    On Error GoTo EvalError
    scrConsole(ConsoleID).AddCode RunStr
    On Error GoTo 0
    GoTo ScriptEnd

EvalError:
    If Err.Number = vbObjectError + 9001 Then
        GoTo ScriptCancelled
    End If
    If Err.Number = vbObjectError + 9002 Then
        GoTo ScriptEnd
    End If
    Dim ErrHelp As String
    ErrHelp = ""
    If Err.Number = 13 Then
        ErrHelp = "This error might mean the command you tried to use does not exist"
    End If
    SayRaw ConsoleID, "Error processing script: " & Err.Description & " (" & Str(Err.Number) & ") " & ErrHelp & " {red}"
    GoTo ScriptEnd

ScriptCancelled:
    SayRaw ConsoleID, "Script Stopped by User (CTRL + C){orange}"
ScriptEnd:
    scrConsoleContext(ConsoleID).CleanupScriptTasks
    New_Console_Line ConsoleID
End Function

Public Function ParseCommandLineOptional(ByVal tmpS As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim OptionDScript As Boolean
    OptionDScript = False
    ParseCommandLineOptional = ParseCommandLine(tmpS, OptionDScript, AllowCommands)
End Function

Public Function ParseCommandLine(ByVal tmpS As String, ByRef OptionDScript As Boolean, Optional ByVal AllowCommands As Boolean = True) As String
    Dim OptionDScriptEverUsed As Boolean
    OptionDScriptEverUsed = OptionDScript
    ParseCommandLine = ParseCommandLineInt2(tmpS, OptionDScript, OptionDScriptEverUsed, AllowCommands)
End Function

Private Function ParseCommandLineInt2(ByVal tmpS As String, ByRef OptionDScript As Boolean, ByRef OpenDScriptEverUsed As Boolean, ByVal AllowCommands As Boolean) As String
    Dim OptionExplicit As Boolean
    OptionExplicit = True
    OpenDScriptEverUsed = Not Not OptionDScript
    Dim RestStart As Long
    RestStart = 1
    ParseCommandLineInt2 = ""
    While RestStart > 0
        tmpS = Mid(tmpS, RestStart)
        ParseCommandLineInt2 = ParseCommandLineInt2 & ParseCommandLineInt(tmpS, RestStart, OptionExplicit, OptionDScript, OpenDScriptEverUsed, AllowCommands)
    Wend

    If OptionExplicit Then
        ParseCommandLineInt2 = "Option Explicit : " & ParseCommandLineInt2
    End If
End Function

Private Function ParseCommandLineInt(ByVal tmpS As String, ByRef RestStart As Long, ByRef OptionExplicit As Boolean, ByRef OptionDScript As Boolean, ByRef OpenDScriptEverUsed As Boolean, ByVal AllowCommands As Boolean) As String
    Dim CLIArgs() As String
    Dim CLIArgsQuoted() As Boolean
    ReDim CLIArgs(0 To 0)
    ReDim CLIArgsQuoted(0 To 0)
    Dim curArg As String
    Dim curC As String
    Dim InQuotes As String
    Dim X As Long
    Dim IsSimpleCommand As Boolean
    IsSimpleCommand = True
    RestStart = -1
    Dim RestSplit As String
    Dim InComment As Boolean
    For X = 1 To Len(tmpS)
        curC = Mid(tmpS, X, 1)
        If InQuotes <> "" Then
            If curC <> InQuotes Then
                GoTo AddToArg
            End If

            If X < Len(tmpS) And Mid(tmpS, X + 1, 1) = curC Then 'Doubling quotes escapes them
                X = X + 1
                GoTo AddToArg
            End If
           
            GoTo NextArg
        End If
        
        If InComment And curC <> vbLf And curC <> vbCr Then
            GoTo CommandForNext
        End If

        Select Case curC
            Case " ":
                GoTo NextArg
            Case """":
                InQuotes = curC
                GoTo NextArg
            Case "'":
                If curArg <> "" Or CLIArgs(0) <> "" Then
                    RestSplit = " "
                    X = X - 1
                    GoTo RestStartSet
                End If
                InComment = True
                curArg = "'"
                GoTo NextArg
            Case ",", ";", "(", ")", "|", "=", "&", "<", ">": ' These mean the user likely intended VBScript and not CLI
                IsSimpleCommand = False
            Case "_":
                If curArg = "" And X < Len(tmpS) Then
                    Dim NextC As String
                    NextC = Mid(tmpS, X + 1, 1)
                    If NextC = vbLf Then
                        IsSimpleCommand = False
                        X = X + 1
                        GoTo CommandForNext
                    ElseIf NextC = vbCr Then
                        IsSimpleCommand = False
                        X = X + 1
                        If X < Len(tmpS) Then
                            NextC = Mid(tmpS, X + 1, 1)
                            If NextC = vbLf Then
                                X = X + 1
                            End If
                        End If
                        GoTo CommandForNext
                    End If
                End If
            Case vbCr:
                If X = Len(tmpS) Then
                    GoTo CommandForNext
                End If
                If Mid(tmpS, X + 1, 1) = vbLf Then
                    X = X + 1
                End If
                RestSplit = vbCrLf
                GoTo RestStartSet
            Case vbLf:
                RestSplit = vbCrLf
                GoTo RestStartSet
            Case ":":
                RestSplit = ":"
RestStartSet:
                RestStart = X + 1
                X = Len(tmpS) + 1
                GoTo NextArg
            'Case Else:
            '   GoTo AddToArg
        End Select
AddToArg:
    curArg = curArg & curC
    If X <> Len(tmpS) Then
        GoTo CommandForNext
    End If
NextArg:
    If curArg <> "" Or InQuotes <> "" Then
        If CLIArgs(UBound(CLIArgs)) <> "" Then ' Arg 1 and onward
            ReDim Preserve CLIArgs(0 To UBound(CLIArgs) + 1)
            ReDim Preserve CLIArgsQuoted(0 To UBound(CLIArgs))
        Else ' Arg 0
            If Trim(LCase(curArg)) = "rem" Then
                InComment = True
            End If
        End If
        CLIArgs(UBound(CLIArgs)) = curArg
        If InQuotes <> "" Then
            CLIArgsQuoted(UBound(CLIArgs)) = True
        Else
            CLIArgsQuoted(UBound(CLIArgs)) = False
        End If
        InQuotes = ""
        curArg = ""
    End If
CommandForNext:
    Next X

    If CLIArgsQuoted(0) Or Not IsSimpleCommand Then
        GoTo NotASimpleCommand
    End If

    If CLIArgs(0) = "" Then
        If RestStart < 0 Then
            Exit Function
        End If

        ParseCommandLineInt = ""
        Exit Function
    End If

    ' If we arrive here, it means the user probably intended to run a CLI command!
    Dim Command As String
    Command = Trim(LCase(CLIArgs(0)))
    
    Dim ArgStart As Long
    ArgStart = 1
    
    Select Case Command
        Case "for", "next", "while", "wend", "do", "loop", "until", _
                "if", "else", "elseif", "end", _
                "public", "private", "property", "dim", "sub", "function", _
                "const", "enum", "redim", "set", "goto", "type", _
                "throw", "catch", "try", "finally", "on":
            GoTo NotASimpleCommand
        Case "option":
            If UBound(CLIArgs) >= 1 Then
                Command = Trim(LCase(CLIArgs(1)))
                If Command = "dscript" Then
                    OpenDScriptEverUsed = True
                    OptionDScript = True
                ElseIf Command = "nodscript" Then
                    OpenDScriptEverUsed = True
                    OptionDScript = False
                Else
                    GoTo NotASimpleCommand
                End If
                ParseCommandLineInt = ""
                GoTo RunSplitCommand
            End If
            GoTo NotASimpleCommand
        Case "rem", "'":
            GoTo NotASimpleCommandButWithOE
        Case "wait":
            If UBound(CLIArgs) >= 1 And Trim(LCase(CLIArgs(1))) = "for" Then
                Command = "waitfor"
                ArgStart = 2
            End If
    End Select
    
    ' We don't want to actually parse anything if we're not opted in
    If Not OptionDScript Then
        GoTo NotASimpleCommand
    End If

    ' First, check if there is a command for it in /system/commands
    Dim ResolvedCommand As String
    Dim CommandNeedFirstComma As Boolean

    If AllowCommands Then
        ResolvedCommand = ResolveCommand(0, Command)
    Else
        ResolvedCommand = ""
    End If

    If ResolvedCommand <> "" Then
        ParseCommandLineInt = "Run(""" & ResolvedCommand & """"
        CommandNeedFirstComma = True
    Else
        ParseCommandLineInt = "Say " & Command & "("
        CommandNeedFirstComma = False
    End If

    For X = ArgStart To UBound(CLIArgs)
        If X > ArgStart Or CommandNeedFirstComma Then
            ParseCommandLineInt = ParseCommandLineInt & ", "
        End If
        If Left(CLIArgs(X), 1) = "$" And Not CLIArgsQuoted(X) Then
            ParseCommandLineInt = ParseCommandLineInt & Mid(CLIArgs(X), 2)
        Else
            ParseCommandLineInt = ParseCommandLineInt & """" & VBEscapeSimple(CLIArgs(X)) & """"
        End If
    Next X
    ParseCommandLineInt = ParseCommandLineInt & ")"
    GoTo RunSplitCommand

NotASimpleCommand:
    OptionExplicit = False
NotASimpleCommandButWithOE:
    ParseCommandLineInt = tmpS
    If RestStart > 0 Then
        ParseCommandLineInt = Left(ParseCommandLineInt, RestStart - 2)
    End If

RunSplitCommand:
    If RestStart < 0 Then
        Exit Function
    End If

    ParseCommandLineInt = ParseCommandLineInt & RestSplit
End Function

' -y r g b mode
'  SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE
Public Sub DrawItUp(ByVal YPos As Long, ByVal R As Long, ByVal G As Long, ByVal b As Long, ByVal Mode As String, ByVal ConsoleID As Integer)
    Dim sColor As String
    Dim sMode As String
     
    Dim yIndex As Integer, n As Integer
    yIndex = (YPos * -1) + 1

    Console(ConsoleID, yIndex).DrawMode = Mode
    
    Select Case Mode
    Case "fadecenter":
    
        Console(ConsoleID, yIndex).DrawEnabled = True
        Console(ConsoleID, yIndex).DrawR = R
        Console(ConsoleID, yIndex).DrawG = G
        Console(ConsoleID, yIndex).DrawB = b
        
        For n = ((DrawDividerWidth / 2) + 1) To DrawDividerWidth
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
        R = Console(ConsoleID, yIndex).DrawR
        G = Console(ConsoleID, yIndex).DrawG
        b = Console(ConsoleID, yIndex).DrawB
        
        For n = (DrawDividerWidth / 2) To 1 Step -1
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
    Case "fadeinverse":
    
        Console(ConsoleID, yIndex).DrawEnabled = True
        Console(ConsoleID, yIndex).DrawR = R
        Console(ConsoleID, yIndex).DrawG = G
        Console(ConsoleID, yIndex).DrawB = b
        
        For n = DrawDividerWidth To ((DrawDividerWidth / 2) + 1) Step -1
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
        R = Console(ConsoleID, yIndex).DrawR
        G = Console(ConsoleID, yIndex).DrawG
        b = Console(ConsoleID, yIndex).DrawB
        
        For n = 1 To (DrawDividerWidth / 2)
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
    
    
    Case "fadein":
    
        Console(ConsoleID, yIndex).DrawEnabled = True
        Console(ConsoleID, yIndex).DrawR = R
        Console(ConsoleID, yIndex).DrawG = G
        Console(ConsoleID, yIndex).DrawB = b
        
        For n = 1 To DrawDividerWidth
            R = R - 4
            G = G - 4
            b = b - 4
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n


    Case "fadeout":
    
    
        Console(ConsoleID, yIndex).DrawEnabled = True
        Console(ConsoleID, yIndex).DrawR = R
        Console(ConsoleID, yIndex).DrawG = G
        Console(ConsoleID, yIndex).DrawB = b
        
        For n = DrawDividerWidth To 1 Step -1
            R = R - 4
            G = G - 4
            b = b - 4
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n


    Case "flow":
    
    
        Console(ConsoleID, yIndex).DrawEnabled = True
        Console(ConsoleID, yIndex).DrawR = R
        Console(ConsoleID, yIndex).DrawG = G
        Console(ConsoleID, yIndex).DrawB = b
        
        For n = 1 To ((DrawDividerWidth / 4) * 1)
            R = R - 5
            G = G - 5
            b = b - 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
                
        For n = (((DrawDividerWidth / 4) * 1) + 1) To (((DrawDividerWidth / 4) * 2))
            R = R + 5
            G = G + 5
            b = b + 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
                
                
        For n = (((DrawDividerWidth / 4) * 2) + 1) To (((DrawDividerWidth / 4) * 3))
            R = R - 5
            G = G - 5
            b = b - 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
                        
                
        For n = (((DrawDividerWidth / 4) * 3) + 1) To (((DrawDividerWidth / 4) * 4))
            R = R + 5
            G = G + 5
            b = b + 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
        
        

    
    Case "solid":
        Console(ConsoleID, yIndex).DrawEnabled = True
        Console(ConsoleID, yIndex).DrawR = R
        Console(ConsoleID, yIndex).DrawG = G
        Console(ConsoleID, yIndex).DrawB = b
        
        
        For n = 1 To DrawDividerWidth
            Console(ConsoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
    End Select
    
End Sub

Public Sub SetYDiv(ByVal n As Integer)
    If n < 0 Then n = 0
    If n > 720 Then n = 720
    
    yDiv = n
End Sub

Public Sub MusicCommand(ByVal s As String)
    Select Case i(s)

    Case "start": RegSave "music", "on"
    Case "on": RegSave "music", "on"
        
    Case "stop": RegSave "music", "off"
    Case "off": RegSave "music", "off"
    
    Case "next": basMusic.StopMusic
        
    Case "prev":
        basMusic.PrevMusicIndex
        basMusic.PrevMusicIndex
        basMusic.StopMusic
    End Select
End Sub


Public Sub ListKeys(ByVal ConsoleID As Integer)
    Dim ss As String
    ss = "{gold}"
    
    SayRaw ConsoleID, "Dark Signs Keyboard Actions{gold 14}"
    
    SayRaw ConsoleID, "Page Up: Scroll the console up." & ss
    SayRaw ConsoleID, "Page Down: Scroll the console down." & ss
    
    SayRaw ConsoleID, "Shift + Page Up: Decrease size of the COMM." & ss
    SayRaw ConsoleID, "Shift + Page Down: Incease size of the COMM." & ss
    
    SayRaw ConsoleID, "F11: Toggle maximum console display." & ss
End Sub


Public Sub SetUsername(ByVal s As String, ByVal ConsoleID As Integer)
    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If

    RegSave "myUsernameDev", s
    
    Dim Password As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
    SayRaw ConsoleID, "Your new details are shown below." & "{orange}"
    SayRaw ConsoleID, "Username: " & myUsername() & "{orange 16}"
    SayRaw ConsoleID, "Password: " & Password & "{orange 16}"
End Sub

Public Sub SetPassword(ByVal s As String, ByVal ConsoleID As Integer)
    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If

    RegSave "myPasswordDev", s
    
    Dim Password As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
    SayRaw ConsoleID, "Your new details are shown below." & "{orange}"
    SayRaw ConsoleID, "Username: " & myUsername() & "{orange 16}"
    SayRaw ConsoleID, "Password: " & Password & "{orange 16}"
End Sub

Public Sub ClearConsole(ByVal ConsoleID As Integer)
    Console(ConsoleID, 1).Caption = "-"
    
    Dim n As Integer
    
    For n = 1 To 29
        Shift_Console_Lines ConsoleID
        Console(ConsoleID, 2).Caption = "-"
        Console(ConsoleID, 2).FontSize = 48
    Next n
End Sub


Public Sub EditFile(ByVal s As String, ByVal ConsoleID As Integer)
    If s = "" Then
        Exit Sub
    End If

    EditorFile_Short = GetShortName(s)
    EditorFile_Long = s

    If Not FileExists(s) Then
        SayRaw ConsoleID, "{green}File Not Found, Creating: " & s
        WriteFile s, ""
    End If

    frmEditor.Show vbModal
    
    If Trim(EditorRunFile) <> "" Then
        Shift_Console_Lines ConsoleID
        Dim EmptyArguments(0 To 0) As Variant
        EmptyArguments(0) = ""
        Run_Script EditorRunFile, ConsoleID, EmptyArguments, "CONSOLE", True, False, False
    End If
    
    
    Exit Sub
errorDir:
End Sub

Public Sub ShowMail(ByVal s As String, ByVal ConsoleID As Integer)
    frmDSOMail.Show vbModal
    Exit Sub
errorDir:
End Sub

Public Function GetShortName(ByVal s As String) As String
    s = ReverseString(s)
    s = Replace(s, "\", "/")
    
    If InStr(s, "/") > 0 Then
    
        s = Mid(s, 1, InStr(s, "/") - 1)
        
    End If
    
    GetShortName = Trim(ReverseString(s))
End Function

Public Function SayError(s As String, ByVal ConsoleID As Integer)
    SayRaw ConsoleID, "Error - " & s & " {orange}"
End Function


Public Sub PauseConsole(s As String, ByVal ConsoleID As Integer)
    ConsolePaused(ConsoleID) = True

    Dim propSpace As String

    If Trim(Kill_Property_Space(s)) = "" Then
        propSpace = "{" & Trim(Get_Property_Space(s)) & "}"

        If Len(propSpace) > 3 Then
            s = propSpace & "Press any key to continue..."
        Else
            s = "Press any key to continue..."
        End If

    End If

    If Has_Property_Space(s) = True Then
        SayRaw ConsoleID, s
    Else
        SayRaw ConsoleID, s & "{lblue 10}"
    End If

    Do
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
    Loop Until ConsolePaused(ConsoleID) = False
End Sub
