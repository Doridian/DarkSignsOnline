Attribute VB_Name = "basCommands"
Option Explicit

Public AuthorizePayment As Boolean

Private scrConsole(1 To 4) As ScriptControl
Private scrConsoleContext(1 To 4) As clsScriptFunctions
Private scrConsoleDScript(1 To 4) As Boolean

Private CLIPaths() As String

Public Const Pi As Double = 3.14159265358979

Public Sub InitBasCommands()
    Dim x As Integer
    For x = 1 To 4
        Set scrConsole(x) = New ScriptControl
        scrConsole(x).AllowUI = False
        scrConsole(x).Timeout = -1
        scrConsole(x).UseSafeSubset = True
        scrConsole(x).Language = "VBScript"

        Dim CLIArguments(0 To 0) As Variant
        CLIArguments(0) = "/dev/tty" & x
        Set scrConsoleContext(x) = New clsScriptFunctions
        scrConsoleContext(x).Configure x, True, scrConsole(x), CLIArguments, "", "", 0, False, False, True, "", "", ""

        scrConsole(x).AddObject "DSO", scrConsoleContext(x), True
        LoadBasicFunctions scrConsole(x)

        scrConsoleDScript(x) = True
    Next

    ReDim CLIPaths(0 To 1)
    CLIPaths(0) = "/system/commands"
    CLIPaths(1) = "."
End Sub

Public Function SafePath(ByVal Path As String, Optional ByVal Prefix As String = "") As String
    Path = Replace(Path, "\", "/")
    If Path = ".." Or Left(Path, 3) = "../" Or Right(Path, 3) = "/.." Or InStr(Path, "/../") > 0 Then
        SafePath = App.Path & "/user/f/a/i/l/s/a/f/e.txt"
        Err.Raise vbObjectError + 9666, , "Invalid character in path"
        Exit Function
    End If

    SafePath = App.Path & "/user/" & Prefix & Path
    While InStr(SafePath, "//") > 0
        SafePath = Replace(SafePath, "//", "/")
    Wend
    If Right(SafePath, 1) = "/" Then
        SafePath = Mid(SafePath, 1, Len(SafePath) - 1)
    End If

    SafePath = Replace(SafePath, "\", "/")
End Function

Public Function ResolvePath(ByVal ConsoleID As Integer, ByVal Path As String) As String
    If ConsoleID = 0 Then
        ResolvePath = ResolvePathRel(".", Path)
        Exit Function
    End If
    ResolvePath = ResolvePathRel(cPath(ConsoleID), Path)
End Function

Public Function ResolvePathRel(ByVal CCPath As String, ByVal Path As String) As String
    If Path = "" Then
        ResolvePathRel = CCPath
        Exit Function
    End If

    If Left(Path, 1) = "/" Or Left(Path, 1) = "\" Then
        ResolvePathRel = Path
    Else
        ResolvePathRel = CCPath & "/" & Path
    End If

    ResolvePathRel = Replace(ResolvePathRel, "\", "/")
    While InStr(ResolvePathRel, "//") > 0
        ResolvePathRel = Replace(ResolvePathRel, "//", "/")
    Wend

    Dim IsRelative As Boolean
    IsRelative = True
    If Left(ResolvePathRel, 1) = "/" Then
        ResolvePathRel = Mid(ResolvePathRel, 2)
        IsRelative = False
    End If

    Dim ResolvePathSplit() As String
    ResolvePathSplit = Split(ResolvePathRel, "/")
    
    Dim ResolvePathSplitCut() As String
    ReDim ResolvePathSplitCut(0 To 0)

    Dim x As Long
    ResolvePathRel = ""
    Dim CurPath As String
    For x = LBound(ResolvePathSplit) To UBound(ResolvePathSplit)
        CurPath = ResolvePathSplit(x)
        If CurPath = "" Or CurPath = "." Then
            ' Don't do anything!
        ElseIf CurPath = ".." Then
            If UBound(ResolvePathSplitCut) > 0 Then
                ReDim Preserve ResolvePathSplitCut(0 To UBound(ResolvePathSplitCut) - 1)
            End If
        Else
            ReDim Preserve ResolvePathSplitCut(0 To UBound(ResolvePathSplitCut) + 1)
            ResolvePathSplitCut(UBound(ResolvePathSplitCut)) = CurPath
        End If
    Next x

    If UBound(ResolvePathSplitCut) = 0 Then
        ResolvePathRel = "/"
        Exit Function
    End If

    If IsRelative Then
        ResolvePathSplitCut(0) = "."
    Else
        ResolvePathSplitCut(0) = ""
    End If
    ResolvePathRel = Join(ResolvePathSplitCut, "/")
End Function

Public Function ResolveCommand(ByVal ConsoleID As Integer, ByVal Command As String) As String
    If InStr(Command, "/") > 0 Or InStr(Command, "\") > 0 Then
        ResolveCommand = ResolvePath(ConsoleID, Command)
        Exit Function
    End If

    If LCase(Right(Command, 3)) <> ".ds" Then
        Command = Command & ".ds"
    End If

    Dim x As Long

    Dim tmpCommand As String
    For x = 0 To UBound(CLIPaths)
        ResolveCommand = ResolvePath(ConsoleID, CLIPaths(x) & "/" & Command)
        If Left(ResolveCommand, 1) <> "/" Then
            GoTo SkipThisPath
        End If

        If basGeneral.FileExists(ResolveCommand) Then
            Exit Function
        End If
SkipThisPath:
    Next

    ResolveCommand = ""
End Function


Public Function VBEscapeSimple(ByVal Str As String) As String
    VBEscapeSimple = Replace(Str, """", """""")
End Function

Public Function VBEscapeSimpleQuoted(ByVal Str As String, Optional ByVal ForceQuotes As Boolean = False) As String
    If Not ForceQuotes Then
        If IsKeyword(Str) Or IsNumeric(Str) Then
            VBEscapeSimpleQuoted = Str
            Exit Function
        End If
    End If
    VBEscapeSimpleQuoted = """" & Replace(Str, """", """""") & """"
End Function


Public Function Run_Command(ByVal tmpS As String, ByVal ConsoleID As Integer)
    If ConsoleID < 1 Then
        ConsoleID = 1
    End If
    If ConsoleID > 4 Then
        ConsoleID = 4
    End If

    If tmpS = "" Then
        Exit Function
    End If

    CancelScript(ConsoleID) = False

    Dim ErrNumber As Long
    Dim ErrDescription As String

    scrConsoleContext(ConsoleID).UnAbort
    scrConsole(ConsoleID).Error.Clear
    Err.Clear

    Dim RunStr As String
    Dim OptionDScript As Boolean
    OptionDScript = scrConsoleDScript(ConsoleID)

    Dim CodeFaulted As Boolean
    CodeFaulted = False
    On Error GoTo OnCodeFaulted

    RunStr = ParseCommandLine(tmpS, OptionDScript, False, ConsoleID, True)
    If CodeFaulted Then
        ErrDescription = "[PARSING CLI] " & ErrDescription
        GoTo SkipCommandProcessing
    End If
    scrConsoleDScript(ConsoleID) = OptionDScript
    scrConsole(ConsoleID).AddCode RunStr
    If CodeFaulted Then
        ErrDescription = "[RUNNING CLI] " & ErrDescription
        GoTo SkipCommandProcessing
    End If

SkipCommandProcessing:
    On Error GoTo 0
    If Not CodeFaulted Then
        GoTo ScriptEnd
    End If

    Dim ObjectErrNumber As Long
    ObjectErrNumber = ErrNumber - vbObjectError
    
    If ObjectErrNumber = 9001 Then
        GoTo ScriptCancelled
    End If
    If ObjectErrNumber = 9002 Then
        GoTo ScriptEnd
    End If
    Dim ErrHelp As String
    ErrHelp = ""
    If ErrNumber = 13 Then
        ErrHelp = "This error might mean the command you tried to use does not exist"
    End If
    
    Dim ErrNumberStr As String
    If ObjectErrNumber >= 0 And ObjectErrNumber <= 65535 Then
        ErrNumberStr = "(O#" & ObjectErrNumber & ")"
    Else
        ErrNumberStr = "(E#" & ErrNumber & ")"
    End If

    SayRaw ConsoleID, "Error: " & ConsoleEscape(ErrDescription) & " " & ErrNumberStr & " " & ConsoleEscape(ErrHelp) & "{{red}}"
    GoTo ScriptEnd

ScriptCancelled:
    SayRaw ConsoleID, "Script Stopped by User (CTRL + B){{orange}}"
ScriptEnd:
    scrConsoleContext(ConsoleID).CleanupScriptTasks
    Exit Function

OnCodeFaulted:
    ErrNumber = scrConsole(ConsoleID).Error.Number
    ErrDescription = scrConsole(ConsoleID).Error.Description
    If ErrNumber = 0 Or ErrDescription = "" Then
        ErrNumber = Err.Number
        ErrDescription = Err.Description
    End If

    CodeFaulted = True
    Resume Next
End Function

Public Function ConsoleEscape(ByVal tmpS As String) As String
    tmpS = Replace(tmpS, ConsoleInvisibleChar, "")
    tmpS = Replace(tmpS, "}}", "}" & ConsoleInvisibleChar & "}")
    tmpS = Replace(tmpS, "{{", "{" & ConsoleInvisibleChar & "{")
    ConsoleEscape = tmpS
End Function

Public Function ParseCommandLineOptional(ByVal tmpS As String, ByVal AutoVariablesFrom As Integer, Optional ByVal AllowCommands As Boolean = True) As String
    Dim OptionDScript As Boolean
    OptionDScript = False
    ParseCommandLineOptional = ParseCommandLine(tmpS, OptionDScript, True, AutoVariablesFrom, AllowCommands)
End Function

Public Function ParseCommandLine(ByVal tmpS As String, ByRef OptionDScript As Boolean, ByVal OptionExplicit As Boolean, ByVal AutoVariablesFrom As Integer, ByVal AllowCommands As Boolean) As String
    Dim RestStart As Long
    RestStart = 1
    ParseCommandLine = ""
    While RestStart > 0
        tmpS = Mid(tmpS, RestStart)
        ParseCommandLine = ParseCommandLine & ParseCommandLineInt(tmpS, RestStart, OptionExplicit, OptionDScript, AutoVariablesFrom, AllowCommands)
    Wend

    If OptionExplicit Then
        ParseCommandLine = "Option Explicit : " & ParseCommandLine
    End If
End Function

Public Function IsKeyword(ByVal Candidate As String) As Boolean
    Dim lCandidate As String
    lCandidate = LCase(Candidate)
    IsKeyword = (lCandidate = "true" Or lCandidate = "false" Or lCandidate = "null" Or lCandidate = "nothing")
End Function

Public Function IsValidVarName(ByVal Candidate As String) As Boolean
    If Candidate = "" Then
        IsValidVarName = False
        Exit Function
    End If

    If IsKeyword(Candidate) Then
        IsValidVarName = False
        Exit Function
    End If

    Dim lCandidate As String
    lCandidate = LCase(Candidate)
    If IsNumeric(Candidate) Then
        IsValidVarName = False
        Exit Function
    End If

    Dim x As Long, c As Integer
    For x = 1 To Len(lCandidate)
        c = Asc(Mid(lCandidate, x, 1))
        ' Only check lowercase as we use LCase'd string
        If c >= Asc("a") And c <= Asc("z") Then
            GoTo CIsValid
        End If
        If c >= Asc("0") And c <= Asc("9") Then
            GoTo CIsValid
        End If
        If c = Asc("_") Or c = Asc("(") Or c = Asc(")") Then
            GoTo CIsValid
        End If

        IsValidVarName = False
        Exit Function
CIsValid:
    Next

    IsValidVarName = True
End Function

Private Function ParseCommandLineInt(ByVal tmpS As String, ByRef RestStart As Long, ByRef OptionExplicit As Boolean, ByRef OptionDScript As Boolean, ByVal AutoVariablesFrom As Integer, ByVal AllowCommands As Boolean) As String
    Dim CLIArgs() As String
    Dim CLIArgsQuoted() As Boolean
    ReDim CLIArgs(0 To 0)
    ReDim CLIArgsQuoted(0 To 0)
    Dim curArg As String
    Dim curC As String
    Dim InQuotes As String
    Dim NextInQuotes As String
    Dim InjectYield As Boolean
    Dim IsSimpleCommand As Boolean
    Dim RestSplit As String
    Dim InComment As Boolean

    IsSimpleCommand = True
    RestStart = -1
    NextInQuotes = ""
    InjectYield = False

    Dim x As Long
    For x = 1 To Len(tmpS)
        curC = Mid(tmpS, x, 1)
        If InQuotes <> "" Then
            If curC <> InQuotes Then
                GoTo AddToArg
            End If

            If x < Len(tmpS) And Mid(tmpS, x + 1, 1) = curC Then 'Doubling quotes escapes them
                x = x + 1
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
                NextInQuotes = curC
                GoTo NextArg
            Case "'":
                If curArg <> "" Or CLIArgs(0) <> "" Then
                    RestSplit = " "
                    x = x - 1
                    GoTo RestStartSet
                End If
                InComment = True
                curArg = "'"
                GoTo NextArg
            Case ",", ";", "(", ")", "|", "=", "&", "<", ">": ' These mean the user likely intended VBScript and not CLI
                IsSimpleCommand = False
            Case "_":
                If curArg = "" And x < Len(tmpS) Then
                    Dim NextC As String
                    NextC = Mid(tmpS, x + 1, 1)
                    If NextC = vbLf Then
                        IsSimpleCommand = False
                        x = x + 1
                        GoTo CommandForNext
                    ElseIf NextC = vbCr Then
                        IsSimpleCommand = False
                        x = x + 1
                        If x < Len(tmpS) Then
                            NextC = Mid(tmpS, x + 1, 1)
                            If NextC = vbLf Then
                                x = x + 1
                            End If
                        End If
                        GoTo CommandForNext
                    End If
                End If
            Case vbCr:
                If x = Len(tmpS) Then
                    GoTo CommandForNext
                End If
                If Mid(tmpS, x + 1, 1) = vbLf Then
                    x = x + 1
                End If
                RestSplit = vbCrLf
                GoTo RestStartSet
            Case vbLf:
                RestSplit = vbCrLf
                GoTo RestStartSet
            Case ":":
                RestSplit = ":"
RestStartSet:
                RestStart = x + 1
                x = Len(tmpS) + 1
                GoTo NextArg
            'Case Else:
            '   GoTo AddToArg
        End Select
AddToArg:
    curArg = curArg & curC
    If x <> Len(tmpS) Then
        GoTo CommandForNext
    End If
    If InQuotes <> "" Then
        Err.Raise vbObjectError + 9302, , "Unclosed quote in command"
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
        curArg = ""
    End If
    InQuotes = NextInQuotes
    NextInQuotes = ""
CommandForNext:
    Next x

    Dim Command As String
    Command = Trim(LCase(CLIArgs(0)))
    If Command = "for" Or Command = "while" Or Command = "do" Then
        InjectYield = True
    End If

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
    
    Dim ArgStart As Long
    ArgStart = 1
    
    Select Case Command
        Case "next", "wend", "loop", "until", _
                "if", "else", "elseif", "end", _
                "public", "private", "property", "dim", "sub", "function", _
                "const", "enum", "redim", "set", "goto", "type", _
                "throw", "catch", "try", "finally", "on", _
                "for", "while", "do":
            GoTo NotASimpleCommand
        Case "option":
            If UBound(CLIArgs) >= 1 Then
                Command = Trim(LCase(CLIArgs(1)))
                If Command = "dscript" Then
                    OptionDScript = True
                ElseIf Command = "nodscript" Then
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
    Dim CommandNeedFirstComma As Boolean
    If AllowCommands And ((ResolveCommand(AutoVariablesFrom, Command) <> "") Or ((Not IsKeyword(Command)) And (Not IsValidVarName(Command)))) Then
        ParseCommandLineInt = "Call Run(""" & Command & """"
        CommandNeedFirstComma = True
    Else
        ParseCommandLineInt = "PrintVarSingleIfSet " & Command & "("
        CommandNeedFirstComma = False
    End If

    For x = ArgStart To UBound(CLIArgs)
        If x > ArgStart Or CommandNeedFirstComma Then
            ParseCommandLineInt = ParseCommandLineInt & ", "
        End If

        Dim ArgVal As String
        ArgVal = CLIArgs(x)
        If CLIArgsQuoted(x) Then
            GoTo ArgIsNotVar
        End If
        If Left(ArgVal, 1) = "%" And Right(ArgVal, 1) = "%" Then
            Dim ArgValStripped As String
            ArgValStripped = Mid(ArgVal, 2, Len(ArgVal) - 2)
            If Not IsValidVarName(ArgValStripped) Then
                GoTo ArgIsNotVar
            End If
            ParseCommandLineInt = ParseCommandLineInt & ArgValStripped
            GoTo NextCLIFor
        End If
        If Not IsValidVarName(ArgVal) Then
            GoTo ArgIsNotVar
        End If

        If FileExists("/system/commands/help/functions/" & ArgVal & ".ds") Then
            GoTo ArgIsNotVar
        End If

        Dim EvalFaulted As Boolean

        Dim RefFound As Boolean
        RefFound = False
        EvalFaulted = False
        On Error Resume Next
        RefFound = scrConsole(AutoVariablesFrom).Eval("Not (GetRef(" & VBEscapeSimpleQuoted(ArgVal, True) & ") Is Nothing)")
        On Error GoTo 0

        If RefFound Then
            GoTo ArgIsNotVar
        End If

        EvalFaulted = False
        On Error GoTo EvalErrorHandler
        scrConsole(AutoVariablesFrom).AddCode "Option Explicit : VarType " & ArgVal
        On Error GoTo 0


        If EvalFaulted Then
            GoTo ArgIsNotVar
        End If

        ParseCommandLineInt = ParseCommandLineInt & VBEscapeSimple(ArgVal)
        GoTo NextCLIFor
ArgIsNotVar:
        ParseCommandLineInt = ParseCommandLineInt & VBEscapeSimpleQuoted(ArgVal, CLIArgsQuoted(x))
NextCLIFor:
    Next x
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
    If InjectYield Then
        ParseCommandLineInt = ParseCommandLineInt & " : Yield : "
    End If

    If RestStart < 0 Then
        Exit Function
    End If

    ParseCommandLineInt = ParseCommandLineInt & RestSplit
    Exit Function
    
EvalErrorHandler:
    EvalFaulted = True
    Resume Next
End Function

Public Function RGBSplit(ByVal lColor As Long, ByRef R As Long, ByRef g As Long, ByRef b As Long)
    R = lColor And &HFF ' mask the low byte
    g = (lColor And &HFF00&) \ &H100 ' mask the 2nd byte and shift it to the low byte
    b = (lColor And &HFF0000) \ &H10000 ' mask the 3rd byte and shift it to the low byte
End Function

Public Function SinLerp(ByVal FromNum As Long, ByVal ToNum As Long, ByVal ValNum As Long) As Double
    If ToNum < FromNum Then
        ValNum = FromNum - ValNum
    Else
        ValNum = ValNum - FromNum
    End If

    ToNum = Math.Abs(ToNum - FromNum)

    If ValNum <= 0 Then
        SinLerp = 0
        Exit Function
    ElseIf ValNum >= ToNum Then
        SinLerp = 1
        Exit Function
    End If

    Dim SAng As Double
    SAng = ValNum
    SAng = SAng / ToNum

    SAng = SAng * Pi * 0.5

    SinLerp = Math.Sin(SAng)
    ' The edges here should always be caught above for performance
    Debug.Assert SinLerp > 0# And SinLerp < 1#
End Function

Private Sub LerpDrawSegments(ByVal ConsoleID As Integer, ByVal R As Integer, ByVal g As Integer, ByVal b As Integer, ByVal yIndex As Long, ByVal LoopA As Long, ByVal LoopB As Long)
    Dim StepVal As Long, n As Long, Mult As Double
    If LoopA > LoopB Then
        StepVal = -1
    Else
        StepVal = 1
    End If
    For n = LoopA To LoopB Step StepVal
        Mult = SinLerp(LoopA, LoopB, n)
        Console(ConsoleID, yIndex).Draw(n).Color = RGB(R * Mult, g * Mult, b * Mult)
    Next n
End Sub

' -y r g b mode
'  SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE
Public Sub DrawSimple(ByVal ConsoleID As Integer, ByVal YPos As Long, ByVal RGBVal As Long, Optional ByVal mode As String = "solid", Optional ByVal Segments As Long = 0)
    If YPos >= 0 Then
        Exit Sub
    End If

    If Segments <= 0 Then
        Segments = DrawDividerWidth
    End If
    
    Dim SegmentsHalf As Long, SegmentsQuarter As Long
    SegmentsQuarter = Segments \ 4
    SegmentsHalf = Segments \ 2

    mode = i(mode)

    Dim yIndex As Integer, n As Integer
    yIndex = (YPos * -1)

    If mode = "solid" Or mode = "" Then
        ReDim Console(ConsoleID, yIndex).Draw(1 To 1)
        Console(ConsoleID, yIndex).Draw(1).Color = RGBVal
        Console(ConsoleID, yIndex).Draw(1).HPos = 0
        CalculateConsoleDraw Console(ConsoleID, yIndex)
        frmConsole.QueueConsoleRender
        Exit Sub
    End If

    Dim R As Long, g As Long, b As Long
    RGBSplit RGBVal, R, g, b

    ReDim Console(ConsoleID, yIndex).Draw(1 To (Segments + 1))
    For n = 1 To Segments
        Console(ConsoleID, yIndex).Draw(n).HPos = (frmConsole.Width \ Segments) * (n - 1)
    Next
    Console(ConsoleID, yIndex).Draw(Segments + 1).Color = -1
    Console(ConsoleID, yIndex).Draw(Segments + 1).HPos = frmConsole.Width

    Select Case mode
        Case "fadecenter":
            LerpDrawSegments ConsoleID, R, g, b, yIndex, (SegmentsHalf + 1), Segments
            LerpDrawSegments ConsoleID, R, g, b, yIndex, SegmentsHalf, 1
        Case "fadeinverse":
            LerpDrawSegments ConsoleID, R, g, b, yIndex, Segments, (SegmentsHalf + 1)
            LerpDrawSegments ConsoleID, R, g, b, yIndex, 1, SegmentsHalf
        Case "fadein":
            LerpDrawSegments ConsoleID, R, g, b, yIndex, 1, Segments
        Case "fadeout":
            LerpDrawSegments ConsoleID, R, g, b, yIndex, Segments, 1
        Case "flow":
            LerpDrawSegments ConsoleID, R, g, b, yIndex, 1, SegmentsQuarter
            LerpDrawSegments ConsoleID, R, g, b, yIndex, (SegmentsQuarter * 2), (SegmentsQuarter + 1)
            LerpDrawSegments ConsoleID, R, g, b, yIndex, ((SegmentsQuarter * 2) + 1), (SegmentsQuarter * 3)
            LerpDrawSegments ConsoleID, R, g, b, yIndex, (SegmentsQuarter * 4), ((SegmentsQuarter * 3) + 1)
        Case Else:
            ReDim Console(ConsoleID, yIndex).Draw(-1 To -1)
            Err.Raise vbObjectError + 1393, , "Invalid draw mode: " & mode
    End Select

    CalculateConsoleDraw Console(ConsoleID, yIndex)
    frmConsole.QueueConsoleRender
End Sub

Public Sub SetYDiv(ByVal n As Integer)
    If n < 0 Then n = 0
    If n > 720 Then n = 720
    
    yDiv = n

    frmConsole.QueueConsoleRender
End Sub

Public Sub MusicCommand(ByVal S As String)
    Select Case i(S)
        Case "start", "on":
            ConfigSave "music", "on", False
        Case "stop", "off":
            ConfigSave "music", "off", False
            basMusic.StopMusic
        Case "next":
            basMusic.StopMusic
        Case "prev":
            basMusic.PrevMusicIndex
            basMusic.PrevMusicIndex
            basMusic.StopMusic
    End Select
End Sub


Public Sub SetUsername(ByVal S As String, ByVal ConsoleID As Integer)
    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If

    ConfigSave "username", S, True
    
    Dim Password As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
    SayRaw ConsoleID, "Your new details are shown below." & "{{orange}}"
    SayRaw ConsoleID, "Username: " & myUsername() & "{{orange 16}}"
    SayRaw ConsoleID, "Password: " & Password & "{{orange 16}}"
End Sub

Public Sub SetPassword(ByVal S As String, ByVal ConsoleID As Integer)
    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If

    ConfigSave "password", S, True

    Dim Password As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
    SayRaw ConsoleID, "Your new details are shown below." & "{{orange}}"
    SayRaw ConsoleID, "Username: " & myUsername() & "{{orange 16}}"
    SayRaw ConsoleID, "Password: " & Password & "{{orange 16}}"
End Sub

Public Sub ClearConsole(ByVal ConsoleID As Integer)
    Dim n As Integer
    For n = 1 To 299
        Console(ConsoleID, 1) = Console_Line_Defaults
    Next n
End Sub

Public Sub EditFile(ByVal S As String, ByVal ConsoleID As Integer)
    If S = "" Then
        Exit Sub
    End If

    If Not basGeneral.FileExists(S) Then
        SayRaw ConsoleID, "{{green}}File Not Found, Creating: " & S
        WriteFile S, ""
    End If

    Dim ExternalEditor As Boolean
    ExternalEditor = ConfigLoad("externaleditor", "false", False) = "true"

    If ExternalEditor Then
        SayRaw ConsoleID, "{{green}}Opening external editor for " & S
        frmConsole.OpenFileDefault S
        Exit Sub
    End If

    EditorFile_Short = GetShortName(S)
    EditorFile_Long = S

    frmEditor.Show vbModal
    
    If Trim(EditorRunFile) <> "" Then
        Shift_Console_Lines ConsoleID
        Dim EmptyArguments(0 To 0) As Variant
        EmptyArguments(0) = ""
        Run_Command EditorRunFile, ConsoleID
    End If

    Exit Sub
errorDir:
End Sub

Public Function GetShortName(ByVal S As String) As String
    S = ReverseString(S)
    S = Replace(S, "\", "/")

    If InStr(S, "/") > 0 Then
        S = Mid(S, 1, InStr(S, "/") - 1)
    End If

    GetShortName = Trim(ReverseString(S))
End Function

Public Function SayError(S As String, ByVal ConsoleID As Integer)
    SayRaw ConsoleID, "Error - " & S & " {{orange}}"
End Function
