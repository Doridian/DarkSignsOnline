Attribute VB_Name = "basCommands"
Option Explicit

Public AuthorizePayment As Boolean

Private scrConsole(1 To 4) As ScriptControl
Private scrConsoleContext(1 To 4) As clsScriptFunctions

Public Sub InitBasCommands()
    Dim X As Integer
    For X = 1 To 4
        Set scrConsole(X) = New ScriptControl
        scrConsole(X).AllowUI = False
        scrConsole(X).Timeout = 100
        scrConsole(X).UseSafeSubset = True
        scrConsole(X).Language = "VBScript"

        Dim CLIArguments(0 To 0) As String
        CLIArguments(0) = "/dev/tty" & X
        Set scrConsoleContext(X) = New clsScriptFunctions
        scrConsoleContext(X).Configure X, "", True, scrConsole(X), CLIArguments, "", False, False, True

        scrConsole(X).AddObject "DSO", scrConsoleContext(X), True
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
    Dim promptEndIdx As Integer
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
    RunStr = ParseCommandLine(tmpS)
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

Public Function ParseCommandLine(ByVal tmpS As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim OptionDScript As Boolean
    Dim OptionDScriptEverUsed As Boolean
    OptionDScript = True
    ParseCommandLine = ParseCommandLineInt2(tmpS, OptionDScript, OptionDScriptEverUsed, AllowCommands)
End Function

Public Function ParseCommandLineOptional(ByVal tmpS As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim OptionDScript As Boolean
    Dim OptionDScriptEverUsed As Boolean
    OptionDScript = False
    ParseCommandLineOptional = ParseCommandLineInt2(tmpS, OptionDScript, OptionDScriptEverUsed, AllowCommands)

    If Not OptionDScriptEverUsed Then
        ParseCommandLineOptional = tmpS
    End If
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
        ParseCommandLineInt = "Call RUN(""" & ResolvedCommand & """"
        CommandNeedFirstComma = True
    Else
        ' Try running procedure with given name
        ParseCommandLineInt = "Call " & Command & "("
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


Public Sub ListMyDomains(ByVal ConsoleID As Integer)
    SayCOMM "Downloading domain list..."
    RunPage "my_domains.php?type=domain", ConsoleID, False, "", 0
End Sub

Public Sub ListMySubDomains(ByVal Domain As String, ByVal ConsoleID As Integer)
    SayCOMM "Downloading subdomain list..."
    RunPage "my_domains.php?domain=" & EncodeURLParameter(Domain) & "&type=subdomain", ConsoleID, False, "", 0
End Sub

Public Sub ListMyIPs(ByVal ConsoleID As Integer)
    SayCOMM "Downloading IP list..."
    RunPage "my_domains.php?type=ip", ConsoleID, False, "", 0
End Sub

Public Sub SetYDiv(s As String)
    s = Trim(Replace(s, "=", ""))
    If s = "" Then Exit Sub
    
    Dim n As Integer
    n = Val(s)
    
    If n < 0 Then n = 0
    If n > 720 Then n = 720
    
    yDiv = n
End Sub

Public Sub CloseDomainPort(ByVal s As String, ByVal ConsoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(s, 1, InStr(s, " ")))
    
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    sPort = s
  
    RunPage "domain_close.php", ConsoleID, True, _
    "ver=2&port=" & EncodeURLParameter(Trim(sPort)) & _
    "&d=" & EncodeURLParameter(sDomain)
        
    SayCOMM "Attempting to close port : " & UCase(sDomain) & ":" & i(sPort), ConsoleID
        
    Exit Sub
zxc:
    SayError "Invalid Parameters", ConsoleID
    ShowHelp "closeport", ConsoleID
    
End Sub


Public Sub DownloadFromDomain(ByVal s As String, ByVal ConsoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    Dim sFilename As String
    Dim sFileData As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(s, 1, InStr(s, " ")))
    
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    If InStr(s, " ") = 0 Then GoTo zxc
    
    sPort = i(Mid(s, 1, InStr(s, " ")))
    sFilename = Trim(Mid(s, InStr(s, " "), Len(s)))

    RunPage "domain_download.php", ConsoleID, True, _
    "returnwith=4400" & _
    "&ver=2&port=" & EncodeURLParameter(Trim(sPort)) & _
    "&d=" & EncodeURLParameter(sDomain) & _
    "&filename=" & EncodeURLParameter(sFilename)
    
    SayCOMM "Attempting to download: " & UCase(sDomain) & ":" & i(sPort), ConsoleID

    Exit Sub
zxc:
    SayError "Invalid Parameters", ConsoleID
    ShowHelp "download", ConsoleID
    
End Sub


Public Sub SubOwners(ByVal s As String, ByVal ConsoleID As Integer)
    s = i(s)

    Dim sDomain As String, sUsername As String
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "subowners", ConsoleID
        Exit Sub
    End If
    
    sDomain = Trim(Mid(s, 1, InStr(s, " ")))
    s = Trim(Mid(s, InStr(s, " ") + 1, Len(s)))
    
    If i(Mid(s, 1, 4)) = "list" Then
        'list the domain names
           
            RunPage "domain_privileges.php", ConsoleID, True, _
            "returnwith=2001&list=" & EncodeURLParameter(Trim(sDomain))

    ElseIf Mid(i(s), 1, 4) = "add " Then
        sUsername = Trim(Mid(s, 5, Len(s)))
            
            RunPage "domain_privileges.php", ConsoleID, True, _
            "returnwith=2001&add=" & EncodeURLParameter(Trim(sDomain)) & "&username=" & EncodeURLParameter(sUsername)

    ElseIf Mid(i(s), 1, 7) = "remove " Then
        sUsername = Trim(Mid(s, 8, Len(s)))
        
             RunPage "domain_privileges.php", ConsoleID, True, _
            "returnwith=2001&remove=" & EncodeURLParameter(Trim(sDomain)) & "&username=" & EncodeURLParameter(sUsername)

    Else
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "subowners", ConsoleID
        Exit Sub
    End If
    
    

    
End Sub

Public Sub RegisterDomain(ByVal s As String, ByVal ConsoleID As Integer)
    s = i(s)
    s = Trim(s)
    
    If s = "" Then
        SayError "The REGISTER command requires a parameter.", ConsoleID
        ShowHelp "register", ConsoleID
        Exit Sub
    End If
    
    If CountCharInString(s, ".") < 1 Or CountCharInString(s, ".") > 3 Or HasBadDomainChar(s) = True Or Len(s) < 5 Or Left(s, 1) = "." Or Right(s, 1) = "." Then
        SayError "The domain name you specified is invalid or contains bad characters.{orange}", ConsoleID
        SayRaw ConsoleID, "A domain name should be in the following form: MYDOMAIN.COM{lorange}"
        SayRaw ConsoleID, "Subdomains should be in the form: BLOG.MYDOMAIN.COM{lorange}"
        SayRaw ConsoleID, "Valid domain name characters are:"
        SayRaw ConsoleID, "A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -{grey 8}"
        Exit Sub
    End If
    
    SayRaw ConsoleID, "{green 10}A registration request has been sent for " & s & "."
    SayRaw ConsoleID, "{lgreen 10}The result will be posted to the COMM."
    
    
    'RunPage "domain_register.php?returnwith=2000&d=" & Trim(s), ConsoleID
    RunPage "domain_register.php", ConsoleID, True, "d=" & EncodeURLParameter(s)
    
End Sub

Public Sub UnRegisterDomain(ByVal s As String, ByVal ConsoleID As Integer)
    s = Trim(s)
    If s = "" Then
        SayError "The UNREGISTER command requires parameters.", ConsoleID
        ShowHelp "unregister", ConsoleID
        Exit Sub
    End If
    

    Dim sDomain As String
    Dim sPass As String
    
    If InStr(s, " ") > 0 Then
        sDomain = LCase(Trim(Mid(s, 1, InStr(s, " "))))
        sPass = Trim(Mid(s, InStr(s, " "), Len(s)))
    Else
        SayError "Your password is required as a final parameter.", ConsoleID
        ShowHelp "unregister", ConsoleID
        Exit Sub
    End If
    
    SayRaw ConsoleID, "{green 10}A unregistration request has been sent for " & sDomain & "."
    SayRaw ConsoleID, "{lgreen 10}The result will be posted to the COMM."

    
    RunPage "domain_unregister.php", ConsoleID, True, _
    "returnwith=2000&d=" & EncodeURLParameter(Trim(sDomain)) & "&pw=" & EncodeURLParameter(sPass)
End Sub

Public Sub ServerCommands(ByVal s As String, ByVal ConsoleID As Integer)
    Dim sCommand As String
    Dim sDomain As String
    Dim sKey As String
    

    'check for a keycode, if it doesn't have one, its from a local script (so exit)
    

    If InStr(s, ":----:") = 0 Then Exit Sub
    
    'SERVER KEY:---:DOMAIN:----:WRITE
    
    sKey = Trim(Mid(s, 1, InStr(s, ":----:") - 1))
    sDomain = Trim(Mid(sKey, InStr(sKey, ":---:") + 5, Len(sKey)))
    sKey = Mid(sKey, 1, InStr(sKey, ":---:") - 1)
    
    
    sCommand = Trim(Mid(s, InStr(s, ":----:") + 6, Len(s)))
    
    'scommand is like: write birds.text hello
    'skey is like: 89302372367894
    'sdomain is like: birds.com
    
    
    Dim sC As String, sP As String
    
    If InStr(sCommand, " ") > 0 Then
        'it has parameters
        sC = Trim(Mid(sCommand, 1, InStr(sCommand, " ") - 1))
        sP = Mid(sCommand, InStr(sCommand, " ") + 1, Len(sCommand))
    Else
        'it has no parameters
        sC = Trim(sCommand)
        sP = ""
    End If

    sKey = DSOEncode(sKey)


    Select Case i(sC)
    Case "append"
        ServerCommand_Append sP, sKey, sDomain, ConsoleID
    Case "write"
        ServerCommand_Write sP, sKey, sDomain, ConsoleID
    End Select
End Sub

Public Sub ServerCommand_Append(s As String, sKey As String, sDomain As String, ByVal ConsoleID As Integer)

    Dim sPostData As String
    Dim sFilename As String
    Dim sFileData As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then Exit Sub
    sFilename = Trim(Mid(s, 1, InStr(s, " ")))
    sFileData = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    sPostData = "append=" & EncodeURLParameter(sFilename) & _
        "&keycode=" & EncodeURLParameter(sKey) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(sFileData)
    
    RunPage "domain_filesystem.php", ConsoleID, True, sPostData, 0

End Sub


Public Sub ServerCommand_Write(s As String, sKey As String, sDomain As String, ByVal ConsoleID As Integer)

    Dim sPostData As String
    Dim sFilename As String
    Dim sFileData As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then Exit Sub
    sFilename = Trim(Mid(s, 1, InStr(s, " ")))
    sFileData = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    sPostData = "write=" & EncodeURLParameter(sFilename) & _
        "&keycode=" & EncodeURLParameter(sKey) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(sFileData)
        
    RunPage "domain_filesystem.php", ConsoleID, True, sPostData, 0

End Sub


Public Sub TransferMoney(ByVal s As String, ByVal ConsoleID As Integer)
    Dim sTo As String
    Dim sAmount As String
    Dim sDescription As String

    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "transfer", ConsoleID
        Exit Sub
    End If
    
    sTo = Trim(Mid(s, 1, InStr(s, " ")))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "transfer", ConsoleID
        Exit Sub
    End If
    
    sAmount = Trim(Mid(s, 1, InStr(s, " ")))
    sDescription = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    
    
    AuthorizePayment = False
    frmPayment.lAmount = "$" & sAmount & ".00"
    frmPayment.lDescription = sDescription
    frmPayment.lTo = sTo
    
    frmPayment.Show vbModal

    If AuthorizePayment = True Then
    
    
    
            If Val(sAmount) < 1 Then
                SayError "Invalid Amount: $" & Trim(sAmount) & ".", ConsoleID
                Exit Sub
            End If

    
        SayCOMM "Processing Payment...", ConsoleID
    
        RunPage "transfer.php", ConsoleID, True, _
        "returnwith=2000" & _
        "&to=" & EncodeURLParameter(Trim(sTo)) & _
        "&amount=" & EncodeURLParameter(Trim(sAmount)) & _
        "&description=" & EncodeURLParameter(Trim(sDescription))
    
    End If
    
    

    
    
End Sub

Public Sub Lookup(ByVal s As String, ByVal ConsoleID As Integer)
    s = i(s)
    s = Trim(s)
    If s = "" Then
        SayError "The LOOKUP command requires a parameter.", ConsoleID
        ShowHelp "lookup", ConsoleID
        Exit Sub
    End If
    
    
    RunPage "lookup.php?returnwith=2000&d=" & EncodeURLParameter(Trim(s)), ConsoleID
    
End Sub

Public Function HasBadDomainChar(ByVal s As String) As Boolean
    HasBadDomainChar = False
    
    If InStr(s, "!") > 0 Then HasBadDomainChar = True
    If InStr(s, "@") > 0 Then HasBadDomainChar = True
    If InStr(s, "#") > 0 Then HasBadDomainChar = True
    If InStr(s, "$") > 0 Then HasBadDomainChar = True
    If InStr(s, "%") > 0 Then HasBadDomainChar = True
    If InStr(s, "^") > 0 Then HasBadDomainChar = True
    If InStr(s, "&") > 0 Then HasBadDomainChar = True
    If InStr(s, "*") > 0 Then HasBadDomainChar = True
    If InStr(s, "(") > 0 Then HasBadDomainChar = True
    If InStr(s, ")") > 0 Then HasBadDomainChar = True
    If InStr(s, "_") > 0 Then HasBadDomainChar = True
    If InStr(s, "+") > 0 Then HasBadDomainChar = True
    If InStr(s, "=") > 0 Then HasBadDomainChar = True
    If InStr(s, "~") > 0 Then HasBadDomainChar = True
    If InStr(s, "`") > 0 Then HasBadDomainChar = True
    If InStr(s, "[") > 0 Then HasBadDomainChar = True
    If InStr(s, "]") > 0 Then HasBadDomainChar = True
    If InStr(s, "{") > 0 Then HasBadDomainChar = True
    If InStr(s, "}") > 0 Then HasBadDomainChar = True
    If InStr(s, "\") > 0 Then HasBadDomainChar = True
    If InStr(s, "|") > 0 Then HasBadDomainChar = True
    If InStr(s, ";") > 0 Then HasBadDomainChar = True
    If InStr(s, Chr(34)) > 0 Then HasBadDomainChar = True
    If InStr(s, "'") > 0 Then HasBadDomainChar = True
    If InStr(s, ":") > 0 Then HasBadDomainChar = True
    If InStr(s, ",") > 0 Then HasBadDomainChar = True
    If InStr(s, "<") > 0 Then HasBadDomainChar = True
    If InStr(s, ">") > 0 Then HasBadDomainChar = True
    If InStr(s, "/") > 0 Then HasBadDomainChar = True
    If InStr(s, "?") > 0 Then HasBadDomainChar = True
    
    
End Function

Public Sub ShowStats(ByVal ConsoleID As Integer)
    SayCOMM "Downloading stats..."
    RunPage "get_user_stats.php?returnwith=2000", ConsoleID
End Sub


Public Sub MusicCommand(ByVal sX As String)
    
    
    Dim s As String
    If InStr(sX, " ") > 0 Then
        s = Mid(sX, 1, InStr(sX, " "))
    Else
        s = sX
    End If
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
        Dim FF As Long
        FF = FreeFile
        Open SafePath(s) For Output As #FF
        Close #FF
    End If

    frmEditor.Show vbModal
    
    If Trim(EditorRunFile) <> "" Then
        Shift_Console_Lines ConsoleID
        Dim EmptyArguments(0 To 0) As String
        Run_Script EditorRunFile, ConsoleID, EmptyArguments, "CONSOLE", "", True, False, False
    End If
    
    
    Exit Sub
errorDir:
    'say ConsoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub ShowMail(ByVal s As String, ByVal ConsoleID As Integer)
    
    frmDSOMail.Show vbModal
     
    
    Exit Sub
    
errorDir:
    'say ConsoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub DisplayFile(ByVal s As String, ByVal ConsoleID As Integer)
    
    Dim sFile As String
    Dim startLine As Integer
    Dim MaxLines As Integer
    
    s = Trim(s)
    
    
    Dim FF As Long, tmpS As String, CLine As Integer, CLinePrinted As Integer

    FF = FreeFile
    Open SafePath(sFile) For Input As #FF
        Do Until EOF(FF)
            Line Input #FF, tmpS
            CLine = CLine + 1
            
            If CLine >= startLine Then
                If CLinePrinted < MaxLines Then
                    If Trim(tmpS) <> "" Then
                        SayRaw ConsoleID, Chr(34) & "   " & tmpS & Chr(34), , 1
                        CLinePrinted = CLinePrinted + 1
                    End If
                End If
            End If
        Loop
    Close #FF
    Exit Sub
    
errorDir:
    'say ConsoleID, "Directory Not Found: " & s & " {orange}", False
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

Public Sub ListDirectoryContents(ByVal ConsoleID As Integer, Optional ByVal sFilter As String)
    sFilter = Trim(Replace(sFilter, "*", ""))
    
    Dim sPath As String, n As Integer, tmpS As String, sAll As String
    Dim dirMsg As String, fileMsg As String, fCount As Integer, dCount As Integer

    
    dirMsg = "Directory List {yellow 10}"
    fileMsg = "File List {yellow 10}"
    
    sPath = SafePath(cPath(ConsoleID))

    'directories
    frmConsole.Dir1.Path = sPath
    frmConsole.Dir1.Refresh
    'say ConsoleID, dirMsg, False
    dCount = 0
    For n = 0 To frmConsole.Dir1.ListCount - 1
        tmpS = "[" & UCase(Trim(Replace(frmConsole.Dir1.List(n), sPath, ""))) & "]"
        
        If InStr(tmpS, UCase(sFilter)) > 0 Then
            dCount = dCount + 1
            sAll = sAll & tmpS & "    "
            frmConsole.lfont.FontSize = RegLoad("Default_FontSize", "10")
            frmConsole.lfont.FontName = RegLoad("Default_FontName", "Verdana")
            frmConsole.lfont.Caption = sAll
            
            If frmConsole.lfont.Width > (frmConsole.Width - 4200) Then
                SayRaw ConsoleID, sAll & "{lyellow}"
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        SayRaw ConsoleID, sAll & "{lyellow}"
    End If
    
    sAll = ""

    'files
    frmConsole.File1.Pattern = "*"
    frmConsole.File1.Path = sPath
    frmConsole.File1.Refresh
    fCount = 0
    'say ConsoleID, fileMsg, False
    If frmConsole.File1.ListCount = 0 Then GoTo NoFilesFound
    For n = 0 To frmConsole.File1.ListCount - 1
        tmpS = Trim(Replace(frmConsole.File1.List(n), sPath, ""))
        
        If InStr(tmpS, UCase(sFilter)) > 0 Then
            fCount = fCount + 1
            sAll = sAll & tmpS & " (" & FormatKB(FileLen(sPath & "/" & tmpS)) & ")    "
            frmConsole.lfont.FontSize = RegLoad("Default_FontSize", "8")
            frmConsole.lfont.FontName = RegLoad("Default_FontName", "Verdana")
            frmConsole.lfont.Caption = sAll
            
            If frmConsole.lfont.Width > (frmConsole.Width - 4700) Then
                SayRaw ConsoleID, sAll & "{}"
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        
        SayRaw ConsoleID, sAll & "{}"
    End If
NoFilesFound:
    sAll = ""
    
    SayRaw ConsoleID, Trim(Str(fCount)) & " file(s) and " & Trim(Str(dCount)) & " dir(s) found in " & cPath(ConsoleID) & " {green 10}"
    
    Exit Sub
zxc:
    SayError "Path Not Found: " & cPath(ConsoleID), ConsoleID
End Sub

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

Public Sub ListColors(ByVal ConsoleID As Integer)
    
    ShowCol "lred", ConsoleID
    ShowCol "red", ConsoleID
    ShowCol "dred", ConsoleID
    
    ShowCol "purple", ConsoleID
    ShowCol "pink", ConsoleID
    ShowCol "lorange", ConsoleID
    ShowCol "orange", ConsoleID
    
    ShowCol "lblue", ConsoleID
    ShowCol "blue", ConsoleID
    ShowCol "dblue", ConsoleID
    
    ShowCol "lgreen", ConsoleID
    ShowCol "green", ConsoleID
    ShowCol "dgreen", ConsoleID
    
    ShowCol "lbrown", ConsoleID
    ShowCol "brown", ConsoleID
    ShowCol "dbrown", ConsoleID
    ShowCol "maroon", ConsoleID
    
    ShowCol "white", ConsoleID
    ShowCol "lgrey", ConsoleID
    ShowCol "grey", ConsoleID
    ShowCol "dgrey", ConsoleID
    
    ShowCol "gold", ConsoleID
    
    ShowCol "lyellow", ConsoleID
    ShowCol "yellow", ConsoleID
    ShowCol "dyellow", ConsoleID
    
    
End Sub

Sub ShowCol(ByVal s As String, ByVal ConsoleID As Integer)
    SayRaw ConsoleID, s & " (**" & s & "**) {" & s & " 8}"
End Sub

Public Sub ShowHelp(sP, ByVal ConsoleID As Integer)
    Dim props As String, propsforexamples As String
    props = "{green 12 underline}"
    propsforexamples = "{lgreen 12}"

    Select Case sP
    Case "help"
        SayRaw ConsoleID, props & "Command: HELP"
        SayRaw ConsoleID, "{lgrey}Display the available console commands."
    Case "restart"
        SayRaw ConsoleID, props & "Command: RESTART"
        SayRaw ConsoleID, "{lgrey}Restart the console immediately."
    Case "listcolors"
        SayRaw ConsoleID, props & "Command: LISTCOLORS"
        SayRaw ConsoleID, "{lgrey}Display the available colors and color codes in the console."
    Case "listkeys"
        SayRaw ConsoleID, props & "Command: LISTKEYS"
        SayRaw ConsoleID, "{lgrey}Display the available shortcut keys and their actions in the console."
    
    Case "time"
        SayRaw ConsoleID, props & "Command: TIME"
        SayRaw ConsoleID, "{lgrey}Display the current system time."
    Case "date"
        SayRaw ConsoleID, props & "Command: DATE"
        SayRaw ConsoleID, "{lgrey}Display the current system date."
    Case "now"
        SayRaw ConsoleID, props & "Command: NOW"
        SayRaw ConsoleID, "{lgrey}Display the current system date and time."
    Case "clear"
        SayRaw ConsoleID, props & "Command: CLEAR"
        SayRaw ConsoleID, "{lgrey}Clear the console screen."
    Case "stats"
        SayRaw ConsoleID, props & "Command: STATS"
        SayRaw ConsoleID, "{lgrey}Display active information about the Dark Signs Network."
        SayRaw ConsoleID, "{lorange}This information will be shown in the COMM window."
    
    Case "dir"
        
        SayRaw ConsoleID, props & "Command: DIR optional-filter"
        SayRaw ConsoleID, "{lgrey}Display files and folders in the active directory."
        SayRaw ConsoleID, "{lgrey}A filter can be appended to show only elements containing the filter keyword in their name."
        
    Case "pause"
        SayRaw ConsoleID, props & "Command: PAUSE optional-msg"
        SayRaw ConsoleID, propsforexamples & "Example #1: PAUSE Press a key!"
        SayRaw ConsoleID, "{lgrey}Pause the console interface until the user presses a key."
    Case "cd"
        SayRaw ConsoleID, props & "Command: CD directory-name"
        SayRaw ConsoleID, propsforexamples & "Example #1: CD myfiles"
        SayRaw ConsoleID, "{lgrey}Change the active path to the specified directory."
    Case "rd"
        SayRaw ConsoleID, props & "Command: RD directory-name"
        SayRaw ConsoleID, propsforexamples & "Example #1: RD myfiles"
        SayRaw ConsoleID, "{lgrey}Delete the directory with the specified name."
        SayRaw ConsoleID, "{lorange}The directory must be empty, or it will not be deleted."
    Case "del"
        SayRaw ConsoleID, props & "Command: DEL filename"
        SayRaw ConsoleID, propsforexamples & "Example #1: DEL file.ds"
        SayRaw ConsoleID, "{lgrey}Delete the specified file or files."
        SayRaw ConsoleID, "{lgrey}The wildcard symbol, *, can be used to delete multiple files at once."
        SayRaw ConsoleID, "{lorange}Files in the system directory cannot be deleted."
        SayRaw ConsoleID, "{orange}Be careful not to delete all of your files!"
        
    Case "md"
        SayRaw ConsoleID, props & "Command: MD directory-name"
        SayRaw ConsoleID, propsforexamples & "Example #1: MD myfiles"
        SayRaw ConsoleID, "{lgrey}Create a new empty directory with the specified name."
        SayRaw ConsoleID, "{lorange}The name of the directory should not contain space characters."
            
    Case "lookup"
        SayRaw ConsoleID, props & "Command: LOOKUP domain-or-username"
        SayRaw ConsoleID, propsforexamples & "Example #1: LOOKUP website.com"
        SayRaw ConsoleID, propsforexamples & "Example #2: LOOKUP jsmith"
        SayRaw ConsoleID, "{lgrey}View information about the specified domain name or user account."
        SayRaw ConsoleID, "{lgrey}This command can be used on both domain names and user accounts."
        SayRaw ConsoleID, "{lorange}Data will be returned in the COMM window."
                   
    Case "username"
        SayRaw ConsoleID, props & "Command: USERNAME your-username"
        SayRaw ConsoleID, propsforexamples & "Example #1: USERNAME jsmith"
        SayRaw ConsoleID, "{lgrey}Set or change your Dark Signs username."
        SayRaw ConsoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled."
        SayRaw ConsoleID, "{lorange}If you do not have an account, visit the website to create one."
    Case "password"
        SayRaw ConsoleID, props & "Command: PASSWORD your-password"
        SayRaw ConsoleID, propsforexamples & "Example #1: PASSWORD secret123"
        SayRaw ConsoleID, "{lgrey}Set or change your Dark Signs password."
        SayRaw ConsoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled."
        SayRaw ConsoleID, "{lorange}If you do not have an account, visit the website to create one."
    
    Case "ping"
        SayRaw ConsoleID, props & "Command: PING domain-or-ip-server"
        SayRaw ConsoleID, propsforexamples & "Example #1: PING birds.com"
        SayRaw ConsoleID, "{lgrey}Check if the specified server exist on the network."
        SayRaw ConsoleID, "{lorange}You can modify this command in the file /system/commands/ping.ds"
    
    Case "me"
        SayRaw ConsoleID, props & "Command: ME"
        SayRaw ConsoleID, propsforexamples & "Example #1: ME"
        SayRaw ConsoleID, "{lgrey}Do nothing at all!"
        SayRaw ConsoleID, "{lorange}This is a useless secret command."
    
    Case "pingport"
        SayRaw ConsoleID, props & "Command: PINGPORT domain-or-ip-server 80"
        SayRaw ConsoleID, propsforexamples & "Example #1: PINGPORT birds.com 80"
        SayRaw ConsoleID, "{lgrey}Check if a script is runnning on the server at the specified port number."
        SayRaw ConsoleID, "{lorange}You can modify this command in the file /system/commands/pingport.ds"
            
    Case "getip"
        SayRaw ConsoleID, props & "Command: GETIP domain-or-ip-server"
        SayRaw ConsoleID, propsforexamples & "Example #1: GETIP birds.com"
        SayRaw ConsoleID, "{lgrey}Get the IP address of the specified server."
        SayRaw ConsoleID, "{lorange}You can modify this command in the file /system/commands/getip.ds"
            
    Case "getdomain"
        SayRaw ConsoleID, props & "Command: GETDOMAIN domain-or-ip-server"
        SayRaw ConsoleID, propsforexamples & "Example #1: GETDOMAIN 12.55.192.111"
        SayRaw ConsoleID, "{lgrey}Get the domain name of the specified server."
        SayRaw ConsoleID, "{lorange}You can modify this command in the file /system/commands/getdomain.ds"
                            
    Case "connect"
        SayRaw ConsoleID, props & "Command: CONNECT server port-number [optional-parameters]"
        SayRaw ConsoleID, propsforexamples & "Example #1: CONNECT home.com 80"
        SayRaw ConsoleID, "{lgrey}Connect to a server domain name or IP address on the specified port."
        SayRaw ConsoleID, "{lgrey}If no port number is specified, the default port number is 80."
        SayRaw ConsoleID, "{lorange}You must specify the port number if you are including optional parameters."
 
        
            
    Case "move"
        SayRaw ConsoleID, props & "Command: MOVE source-file destination-file"
        SayRaw ConsoleID, propsforexamples & "Example #1: MOVE myoldfile.ds mynewfile.ds"
        SayRaw ConsoleID, propsforexamples & "Example #2: MOVE /home/myoldfile.ds  /home/dir2/mynewfile.ds"
        SayRaw ConsoleID, "{lgrey}Rename the specified file."
        SayRaw ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2."
        SayRaw ConsoleID, "{lorange}File names should not contain space characters."
    Case "rename"
        SayRaw ConsoleID, props & "Command: RENAME source-file destination-file"
        SayRaw ConsoleID, propsforexamples & "Example #1: MD myoldfile.ds mynewfile.ds"
        SayRaw ConsoleID, propsforexamples & "Example #2: MD /home/myoldfile.ds  /home/dir2/mynewfile.ds"
        SayRaw ConsoleID, "{lgrey}Rename the specified file."
        SayRaw ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2."
        SayRaw ConsoleID, "{lorange}File names should not contain space characters."
    Case "copy"
        SayRaw ConsoleID, props & "Command: COPY source-file destination-file"
        SayRaw ConsoleID, propsforexamples & "Example #1: COPY myoldfile.ds mynewfile.ds"
        SayRaw ConsoleID, propsforexamples & "Example #2: COPY /home/myoldfile.ds  /home/dir2/mynewfile.ds"
        SayRaw ConsoleID, "{lgrey}Create a copy of the specified file."
        SayRaw ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2."
        SayRaw ConsoleID, "{lorange}File names should not contain space characters."
    
    Case "saycomm"
        SayRaw ConsoleID, props & "Command: SAYCOMM text"
        SayRaw ConsoleID, propsforexamples & "Example #1: SAYCOMM Connected to server"
        SayRaw ConsoleID, "{lgrey}Display the specified text in the COMM window."
        
    Case "run"
        SayRaw ConsoleID, props & "Command: RUN file"
        SayRaw ConsoleID, propsforexamples & "Example #1: RUN myscript.ds"
        SayRaw ConsoleID, "{lgrey}Run the specified file as script in the console."
        SayRaw ConsoleID, "{lgrey}Files not designed to be run as scripts may cause random errors to be displayed."
            
    Case "edit"
        SayRaw ConsoleID, props & "Command: EDIT file"
        SayRaw ConsoleID, propsforexamples & "Example #1: EDIT myscript.ds"
        SayRaw ConsoleID, "{lgrey}Edit the specified file in the editing window. The console will pause while the editor is active."
        SayRaw ConsoleID, "{lorange}Files in the editor are saved automatically."
                
'    Case "wait"
'        SayRaw ConsoleID, props & "Command: WAIT milliseconds"
'        SayRaw ConsoleID, propsforexamples & "Example #1: WAIT 1000"
'        SayRaw ConsoleID, "{lgrey}Pause the console for the specific amount of time (between 1 and 60000 ms)."
'        SayRaw ConsoleID, "{lorange}1000 millisends is equal to 1 second."
'        SayRaw ConsoleID, "{orange}This command is only enabled in scripts."
                    
    Case "upload"
        SayRaw ConsoleID, props & "Command: UPLOAD server port-number file"
        SayRaw ConsoleID, propsforexamples & "Example #1: UPLOAD mywebsite.com 80 newscript.ds"
        SayRaw ConsoleID, "{lgrey}Upload a file to your domain name on the specified port."
        SayRaw ConsoleID, "{lgrey}This script will then become connectable to all players."
        SayRaw ConsoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own."
    
    Case "closeport"
        SayRaw ConsoleID, props & "Command: CLOSEPORT server port-number"
        SayRaw ConsoleID, propsforexamples & "Example #1: CLOSEPORT mywebsite.com 80"
        SayRaw ConsoleID, "{lgrey}Close port on the specified domain."
        SayRaw ConsoleID, "{lgrey}The script running on this port is deleted."
        SayRaw ConsoleID, "{lorange}You can only close ports on domain names (servers) which you own."
                                      
    Case "download"
        SayRaw ConsoleID, props & "Command: DOWNLOAD server port-number file"
        SayRaw ConsoleID, propsforexamples & "Example #1: DOWNLOAD mywebsite.com 80 thescript.ds"
        SayRaw ConsoleID, "{lgrey}Download a script file from a sever that you own."
        SayRaw ConsoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own."
                             
    Case "transfer"
        SayRaw ConsoleID, props & "Command: TRANSFER recipient-username amount description"
        SayRaw ConsoleID, propsforexamples & "Example #1: TRANSFER admin 5 A payment for you"
        SayRaw ConsoleID, "{lgrey}Transfer an amount of money (DS$) to the specified username."
        SayRaw ConsoleID, "{lorange}Each transfer requires manual authorization from the sender."
                                    
    Case "ydiv"
        SayRaw ConsoleID, props & "Command: YDIV height"
        SayRaw ConsoleID, propsforexamples & "Example #1: YDIV 240"
        SayRaw ConsoleID, "{lgrey}Change the default space between each console line."
        SayRaw ConsoleID, "{lorange}The default YDIV is set to 60."
                                           
    Case "display"
        SayRaw ConsoleID, props & "Command: DISPLAY file optional-start-line optional-max-lines"
        SayRaw ConsoleID, propsforexamples & "Example #1: DISPLAY myfile.txt 1 5"
        SayRaw ConsoleID, "{lgrey}Output the specified file to the console, without running as a script."
        SayRaw ConsoleID, "{lorange}In the example, the first five lines of myfile.txt will be displayed."
                                                   
    Case "append"
        SayRaw ConsoleID, props & "Command: APPEND file optional-START-or-END text"
        SayRaw ConsoleID, propsforexamples & "Example #1: APPEND myfile.txt new data"
        SayRaw ConsoleID, propsforexamples & "Example #2: APPEND myfile.txt START new data"
        SayRaw ConsoleID, "{lgrey}Append (add) text or data to the specified file."
        SayRaw ConsoleID, "{lgrey}Data will be added to the beginning of the file if the START keyword is used."
        SayRaw ConsoleID, "{lgrey}Data will be added to the end of the file if the END keyword is used."
        SayRaw ConsoleID, "{lorange}If the specified file doesn't exist, it will be created."
                                                           
    Case "write"
        SayRaw ConsoleID, props & "Command: WRITE file text"
        SayRaw ConsoleID, propsforexamples & "Example #1: WRITE myfile.txt new data"
        SayRaw ConsoleID, "{lgrey}Write text or data to the specified file."
        SayRaw ConsoleID, "{lorange}If the specified file already exists, it will be overwritten."
        SayRaw ConsoleID, "{lorange}Use APPEND to add data to an existing file."
        

    Case "register"
        SayRaw ConsoleID, props & "Command: REGISTER domain-name"
        SayRaw ConsoleID, propsforexamples & "Example #1: REGISTER mynewwebsite.com"
        SayRaw ConsoleID, "{lgrey}Register a domain name on the Dark Signs Network."
        SayRaw ConsoleID, "{lgrey}This command requires that you have the required amount of money (DS$) in your account."
        SayRaw ConsoleID, "-"
        SayRaw ConsoleID, "{center orange nobold 14}- Check the latest prices in the COMM window. -"
        RunPage "domain_register.php?returnwith=2000&prices=1", ConsoleID
        
         
    Case "unregister"
        SayRaw ConsoleID, props & "Command: UNREGISTER domain-name account-password"
        SayRaw ConsoleID, propsforexamples & "Example #1: UNREGISTER myoldwebsite.com secret123"
        SayRaw ConsoleID, "{lgrey}Unregister a domain name that you own on the Dark Signs Network."
        SayRaw ConsoleID, "{lorange}This command requires that you include your password for security."
        
            
    Case "login"
        SayRaw ConsoleID, props & "Command: LOGIN"
        SayRaw ConsoleID, "{lgrey}Attempt to log in to Dark Signs with your account username and password."
        SayRaw ConsoleID, "{lgrey}This is only necessary if your status is 'not logged in'."
        SayRaw ConsoleID, "{lorange}Use the USERNAME and PASSWORD commands to set or change your username or password."
        
    Case "logout"
        SayRaw ConsoleID, props & "Command: LOGOUT"
        SayRaw ConsoleID, "{lgrey}Log out of Dark Signs."
        SayRaw ConsoleID, "{lgrey}This can be helpful if you want to log in as another user, or if a rare error occurs."
            
    Case "mydomains"
        SayRaw ConsoleID, props & "Command: MYDOMAINS"
        SayRaw ConsoleID, "{lgrey}List the domain names currently registered to you."
   
    Case "mysubdomains"
        SayRaw ConsoleID, props & "Command: MYSUBDOMAINS"
        SayRaw ConsoleID, propsforexamples & "Example #1: MYSUBDOMAINS mySite.com"
        SayRaw ConsoleID, "{lgrey}List subdomains to a domain that is registed to you."
    
    Case "myips"
        SayRaw ConsoleID, props & "Command: MYIPS"
        SayRaw ConsoleID, "{lgrey}List all IP addresses registed to you."
     
    Case "music"
        SayRaw ConsoleID, props & "Command: MUSIC [parameter]"
        SayRaw ConsoleID, propsforexamples & "Example #1: MUSIC NEXT"
        SayRaw ConsoleID, "{lgrey}Music parameters are START, STOP, NEXT, and PREV."
        
    Case "say"
        SayRaw ConsoleID, props & "Command: SAY text (**optional-properties**)"
        SayRaw ConsoleID, propsforexamples & "Example #1: SAY ConsoleID, hello, this is green (**green**)"
        SayRaw ConsoleID, propsforexamples & "Example #2: SAY ConsoleID, this is bold and very large (**bold, 36**)"
        SayRaw ConsoleID, "{lgrey}Display the specified text in the console."
        SayRaw ConsoleID, "{lgrey}Text properties can be modified by adding any number of the following keywords in bewtween (** **), in any order."
        SayRaw ConsoleID, "{lgreen}Colors: Type SHOWCOLORS the display a list of colors."
        SayRaw ConsoleID, "{lgreen}Fonts: Arial, Arial Black, Comic Sans MS, Courier New, Georgia, Impact,"
        SayRaw ConsoleID, "{lgreen}Fonts: Lucida Console, Tahoma, Times New Roman, Trebuchet MS, Verdana, Wingdings."
        SayRaw ConsoleID, "{lgreen}Attributes: Bold, NoBold, Italic, NoItalic, Underline, NoUnderline, Strikethru, NoStrikethru."
        SayRaw ConsoleID, "{lgreen}Extras: Flash, Flashfast, FlashSlow."
        SayRaw ConsoleID, "{orange}Note: You cannot use SAY to display multiple lines of text."
        SayRaw ConsoleID, "{orange}For multiple lines, use SAYALL instead."
    
    Case "sayall"
        SayRaw ConsoleID, props & "Command: SAYALL text (**optional-properties**)"
        SayRaw ConsoleID, propsforexamples & "Example #1: SAYALL hello"
        SayRaw ConsoleID, "{lgrey}Same as the SAY command, except will display multiple lines."
        SayRaw ConsoleID, "{lorange}Type HELP SAY for more information."
             
    Case "sayline"
        SayRaw ConsoleID, props & "Command: SAYLINE text (**optional-properties**)"
        SayRaw ConsoleID, propsforexamples & "Example #1: SAYLINE hello"
        SayRaw ConsoleID, "{lgrey}Same as the SAY command, except text will be printed on the same line, without moving down."
        SayRaw ConsoleID, "{lorange}Type HELP SAY for more information."
           
    Case "remotedelete"
        SayRaw ConsoleID, props & "Command: REMOTEDELETE domain filename"
        SayRaw ConsoleID, propsforexamples & "Example #1: REMOTEDELETE matrix.com myfile.ds"
        SayRaw ConsoleID, "{lgrey}Delete the specified file from the remote server."
        SayRaw ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
    
    Case "remoteupload"
        SayRaw ConsoleID, props & "Command: REMOTEUPLOAD domain filename"
        SayRaw ConsoleID, propsforexamples & "Example #1: REMOTEUPLOAD matrix.com localfile.ds"
        SayRaw ConsoleID, "{lgrey}Upload a file from your local file system to your domain name file system."
        SayRaw ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
           
    Case "remotedir"
        SayRaw ConsoleID, props & "Command: REMOTEDIR domain"
        SayRaw ConsoleID, propsforexamples & "Example #1: REMOTEDIR matrix.com"
        SayRaw ConsoleID, "{lgrey}View files on the remote server."
        SayRaw ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
               
    Case "remoteview"
        SayRaw ConsoleID, props & "Command: REMOTEVIEW domain filename"
        SayRaw ConsoleID, propsforexamples & "Example #1: REMOTEVIEW google.com userlist.log"
        SayRaw ConsoleID, "{lgrey}Display the specified remote file in the console."
        SayRaw ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
    
    Case "draw"
        SayRaw ConsoleID, props & "Command: DRAW -y Red(0-255) Green(0-255) Blue(0-255) mode"
        SayRaw ConsoleID, propsforexamples & "Example #1: DRAW -1 142 200 11 fadeout"
        SayRaw ConsoleID, "{lgrey}Print a background color stream to the console."
        SayRaw ConsoleID, "{lgrey}The first parameter, -y, defines the console line."
        SayRaw ConsoleID, "{lgrey}For example, -2 will draw to the second line up from the active line."
        SayRaw ConsoleID, "{lgrey}The Red, Green, and Blue must be values between 0 and 255."
        SayRaw ConsoleID, "{lorange}Available mode keywords: SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE."
        SayRaw ConsoleID, "{orange}To use custom colors, use the DRAWCUSTOM command."
    
        
    
    Case "subowners"
        SayRaw ConsoleID, props & "Command: SUBOWNERS domain-name KEYWORD [optional-username]"
        SayRaw ConsoleID, propsforexamples & "Example #1: SUBOWNERS site.com LIST"
        SayRaw ConsoleID, propsforexamples & "Example #2: SUBOWNERS site.com ADD friendusername"
        SayRaw ConsoleID, propsforexamples & "Example #3: SUBOWNERS site.com REMOVE friendusername"
        SayRaw ConsoleID, "{lgrey}Add or remove other user privileges regarding your specified domain name."
        SayRaw ConsoleID, "{lgrey}You can add users to this list as subowners of your domain name."
        SayRaw ConsoleID, "{lorange}Subowners have permission to interact, upload, and download files from the domain."
        SayRaw ConsoleID, "{lorange}Subowners have no ability to unregister or modify the domain name  privileges."
        
        
        
    Case "lineup"
        SayRaw ConsoleID, props & "Command: LINEUP"
        SayRaw ConsoleID, "{lgrey}Move up an extra console line. Useful for some scripts."
        
     'Case "chatsend"
     '   SayRaw ConsoleID, props & "Command: CHATSEND Message to be sent to the chat."
     '   SayRaw ConsoleID, propsforexamples & "Example #1: CHATSEND Hello World!"
     '   SayRaw ConsoleID, "{lgrey}A simple way to send messages to the chat from your console."
       
    
    Case "chatview"
        SayRaw ConsoleID, props & "Command: CHATVIEW [parameter]"
        SayRaw ConsoleID, "{lgrey}If set to on, will display chat in the status window."
        SayRaw ConsoleID, "{lgrey}CHATVIEW parameters are ON and OFF"

    
    Case Else
        SayRaw ConsoleID, props & "Available Commands"
        SayRaw ConsoleID, "{lgrey 8}APPEND, CD, CLEAR, CLOSEPORT, CONNECT, COPY, DATE, DEL, DIR, DISPLAY, DOWNLOAD, DRAW, EDIT"
        SayRaw ConsoleID, "{lgrey 8}GETIP, GETDOMAIN, LINEUP, LISTCOLORS, LISTKEYS, LOGIN, LOGOUT, LOOKUP, MD, MOVE, MUSIC"
        SayRaw ConsoleID, "{lgrey 8}MYDOMAINS, MYIPS, MYSUBDOMAINS, NOW, PASSWORD, PAUSE, PING, PINGPORT, RD, RENAME, REGISTER"
        SayRaw ConsoleID, "{lgrey 8}REMOTEDELETE, REMOTEDIR, REMOTEUPLOAD, REMOTEVIEW, RESTART, RUN, SAY, SAYALL, SAYCOMM, STATS"
        SayRaw ConsoleID, "{lgrey 8}SUBOWNERS, TIME, TRANSFER, UNREGISTER, UPLOAD, USERNAME, WRITE, YDIV"
        SayRaw ConsoleID, "{grey}For more specific help on a command, type: HELP [command]"
    End Select
End Sub

