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
        scrConsole(X).Timeout = 0
        scrConsole(X).UseSafeSubset = True
        scrConsole(X).Language = "VBScript"

        Set scrConsoleContext(X) = New clsScriptFunctions
        scrConsoleContext(X).ConsoleID = X

        scrConsole(X).AddObject "DSO", scrConsoleContext(X), True
    Next
End Sub

Public Function Run_Command(CLine As ConsoleLine, ByVal ConsoleID As Integer, Optional ScriptFrom As String, Optional FromScript As Boolean = True, Optional IsFromScript As Boolean)
    If ConsoleID < 1 Then
        ConsoleID = 1
    End If
    If ConsoleID > 4 Then
        ConsoleID = 4
    End If
    
    scrConsoleContext(ConsoleID).ScriptFrom = ScriptFrom

    Dim tmpS As String
    tmpS = CLine.Caption
    Dim promptEndIdx As Integer
    promptEndIdx = InStr(tmpS, ">")
    If promptEndIdx > 0 Then
        tmpS = Mid(tmpS, promptEndIdx + 1)
    End If

    On Error GoTo EvalError
    scrConsole(ConsoleID).AddCode Trim(tmpS)
    On Error GoTo 0

    GoTo ScriptEnd
    Exit Function
EvalError:
    Say ConsoleID, "Error processing script: " & Err.Description & " (" & Str(Err.Number) & ") {red}", False
    GoTo ScriptEnd

ScriptCancelled:
    Say ConsoleID, "Script Stopped by User (CTRL + C){orange}", False
ScriptEnd:
    New_Console_Line ConsoleID
    Exit Function

    Dim n As Integer, tmpS2 As String
    
    Dim sC As String 'the main command
    Dim sP As String 'any parameters
    
    tmpS = CLine.Caption
    'kill double spaces - MUST BE BEFORE REPLACES VARIABLES
    'tmpS = Replace(tmpS, "  ", " ")
    
    'tmpS2 = tmpS
    
    If InStr(tmpS, ">") > 0 And InStr(tmpS, "<") = 0 Then
    If InStr(i(tmpS), i(cPath(ConsoleID))) > 0 Then
        'get rid of the input string
        tmpS = Trim(Mid(tmpS, InStr(tmpS, ">") + 1, Len(tmpS)))
    End If
    End If
    


    
    
    'change $var=yes to $var =yes   (note the space!!)
    If Mid(tmpS, 1, 1) = "$" Then
        If InStr(tmpS, "=") > 0 Then
            tmpS = Mid(tmpS, 1, InStr(tmpS, "=") - 1) & " " & Mid(tmpS, InStr(tmpS, "="), Len(tmpS))
            tmpS = Replace(tmpS, "  = ", " = ")
        End If
    End If
    
    

    If InStr(tmpS, " ") > 0 Then
        
    
        'it has parameters
        sC = Trim(Mid(tmpS, 1, InStr(tmpS, " ") - 1))
        sP = Mid(tmpS, InStr(tmpS, " ") + 1, Len(tmpS))
        
        'MsgBox sC & vbCrLf & vbCrLf & sP
        
        
        'replace variables on the parameters only
        sP = ReplaceVariables(sP, ConsoleID)
        
        
    Else
        'it has no parameters
        sC = Trim(tmpS)
        sP = ""
    End If
    
    

    
    If Mid(sC, 1, 1) = "@" Then Exit Function
    
    'can it be run from a script?
    If Len(Trim(sC)) > 2 Then
    If InStr(LimitedCommandString, ":" & i(sC) & ":") > 0 Then
        'then it cannot be run
        If IsFromScript = True Then 'then don't allow it
            SayError "Command blocked by commands-security.dat: " & UCase(sC) & " " & sP, ConsoleID
            GoTo zzz
        End If
    End If
    End If
    
    Select Case i(sC)
    
        Case "draw": DrawItUp sP, ConsoleID ': Exit Function
    
        Case "dir": ListDirectoryContents ConsoleID, sP
        Case "ls": ListDirectoryContents ConsoleID, sP
        Case "cd": ChangeDir sP, ConsoleID
        Case "cd..": DownADir ConsoleID
        Case "md": MakeDir sP, ConsoleID
        Case "rd": RemoveDir sP, ConsoleID
        Case "del": DeleteFiles sP, ConsoleID
        Case "delete": DeleteFiles sP, ConsoleID
        Case "move": MoveRename sP, ConsoleID
        Case "rename": MoveRename sP, ConsoleID
        Case "copy": MoveRename sP, ConsoleID, "copyonly"
        
        Case "run": RunFileAsScript sP, ConsoleID
        Case "edit": EditFile sP, ConsoleID
        Case "mail": ShowMail sP, ConsoleID
        
        Case "display": DisplayFile sP, ConsoleID
        Case "cat": DisplayFile sP, ConsoleID
        Case "lineup": Shift_Console_Lines_Reverse ConsoleID
        Case "append": AppendAFile sP, ConsoleID
        Case "write": WriteAFile sP, ConsoleID, ScriptFrom
        
        Case "clear": ClearConsole ConsoleID
        Case "cls": ClearConsole ConsoleID
        Case "time": Say ConsoleID, Format(Time, "h:mm AMPM"), False
        Case "date": Say ConsoleID, Date, False
        Case "now": Say ConsoleID, Now, False
        Case "restart": frmConsole.Start_Console ConsoleID: Exit Function
        Case "say": Say ConsoleID, sP, False, FromScript
        Case "sayall": SayAll ConsoleID, sP, False, FromScript
        Case "sayline":
            'Shift_Console_Lines_Reverse (consoleID)
            
            Say ConsoleID, sP, False, FromScript
            If FromScript = True Then Exit Function
            
        Case "listcolors": ListColors ConsoleID
        Case "listkeys": ListKeys ConsoleID
        Case "music": MusicCommand sP
        Case "help": ShowHelp sP, ConsoleID
        Case "pause": PauseConsole sP, ConsoleID: Exit Function
        Case "saycomm": SayCOMM sP, ConsoleID
        Case "username": SetUsername sP, ConsoleID
        Case "password": SetPassword sP, ConsoleID
        Case "stats": ShowStats ConsoleID
        Case "login": LoginNow ConsoleID
        Case "logout": LogoutNow ConsoleID
        Case "wait": 'WaitNow sP, consoleID
        
        Case "connect": ConnectToDomain sP, ConsoleID
        Case "upload": UploadToDomain sP, ConsoleID
        Case "closeport": CloseDomainPort sP, ConsoleID 'Used to close server ports.
        Case "download": DownloadFromDomain sP, ConsoleID
        Case "register": RegisterDomain sP, ConsoleID
        Case "subowners": SubOwners sP, ConsoleID
        Case "unregister": UnRegisterDomain sP, ConsoleID
        Case "transfer": TransferMoney sP, ConsoleID
        Case "lookup": Lookup sP, ConsoleID
        Case "mydomains": ListMyDomains ConsoleID
        Case "mysubdomains": ListMySubDomains sP, ConsoleID
        Case "myips": ListMyIPs ConsoleID
        
        Case "server": If IsFromScript = True Then ServerCommands sP, ConsoleID
        
        'Case "chatsend": frmConsole.ChatSend sP, consoleID
        Case "chatview": frmConsole.ChatView sP, ConsoleID
        
        Case "ydiv": SetYDiv sP
        
    Case "."
    Case ".."
    Case "all"
    Case "exit"
    Case "for"
    Case "next"
    Case "goto"
    Case "if"
    Case "endif"
    Case "else"
    Case "elseif"
    Case "else if"
    Case "end if"
    Case "end"
    Case "me"
    Case "waitfor"
    Case "public"
    Case "private"
        
        ' Test func
        Case "compile": f_Compile sP, ConsoleID
        
        
        Case "hello": Say ConsoleID, "I am your console, not your friend! {green 24 georgia}", False
        Case "hi": Say ConsoleID, "Hello to you as well! {green 24 georgia}", False
        Case "why": Say ConsoleID, "That is a question that I cannot answer. {blue 24 georgia}", False
        Case "wow": Say ConsoleID, "Yeah...{blue 18 georgia}", False: Say ConsoleID, "it's pretty good...{blue 18 georgia center}", False: Say ConsoleID, ":){blue 18 georgia right}", False:: Say ConsoleID, "w00t!{center blue 24 bold georgia}", False
        Case "fuck": Say ConsoleID, "I object to that sort of thing. {grey 24 georgia}", False
        Case "lol": Say ConsoleID, UCase("j") & "{wingdings 144 center green}", False
        Case "ok":  Say ConsoleID, "That's not a real command!{red impact 48 center nobold}", False
                    Say ConsoleID, "What's wrong with you!?{red impact 48 center nobold}", False
        

        
        Case Else:
        

            'other alternatives!
            If Mid(sC, 1, 1) = "$" And Len(sC) > 1 Then
                'it's a variable being set
                
                SetVariable sC, sP, ConsoleID, ScriptFrom
                
                If IsFromScript = True Then
                    If InStr(sP, "(") = 0 Then
                        'only exit function if it doesn't have a function.
                        Exit Function
                    End If
                End If
            ElseIf FileExists(App.Path & "\user" & fixPath(sC, ConsoleID)) = True Then
            
                'it's a file - run it
                Shift_Console_Lines ConsoleID
                Run_Script fixPath(sC, ConsoleID), ConsoleID, sP, referals(ActiveConsole)
            ElseIf FileExists(App.Path & "\user\system\commands\" & sC) = True Then
                'it's a file - run it
                Shift_Console_Lines ConsoleID
                Run_Script "\system\commands\" & sC, ConsoleID, sP, referals(ActiveConsole)
            ElseIf FileExists(App.Path & "\user\system\commands\" & sC & ".ds") = True Then
                'it's a file - run it
                Shift_Console_Lines ConsoleID
                Run_Script "\system\commands\" & sC & ".ds", ConsoleID, sP, referals(ActiveConsole)
            ElseIf IsInCommandsSubdirectory(sC) <> "" Then
                Run_Script IsInCommandsSubdirectory(sC), ConsoleID, sP, referals(ActiveConsole)
            Else
                'it is unknown
                If Trim(sC) = "" Then
                Else
                    If Len(Trim(Replace(Replace(sC, vbCr, ""), vbLf, ""))) > 1 Then
                        
                        SayError "Unrecognized Command: " & sC, ConsoleID
                        
                    End If
                End If
            End If
    
    
            
    End Select
    
zzz:
    WriteErrorLog "Run_Command - " & sC & " - " & sP
    New_Console_Line ConsoleID
End Function

Public Sub DrawItUp(ByVal s As String, ByVal ConsoleID As Integer)
    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", ConsoleID
        ShowHelp "draw", ConsoleID
        Exit Sub
    End If
    
    Dim yPos As Long
    Dim R As Long, G As Long, b As Long
    Dim sColor As String
    Dim sMode As String
    
    yPos = Trim(Mid(s, 1, InStr(s, " ")))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", ConsoleID
        ShowHelp "draw", ConsoleID
        Exit Sub
    End If
    
    R = Val(Trim(Mid(s, 1, InStr(s, " "))))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", ConsoleID
        Exit Sub
    End If
    
    G = Val(Trim(Mid(s, 1, InStr(s, " "))))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters", ConsoleID
        ShowHelp "draw", ConsoleID
        Exit Sub
    End If
    
    b = Val(Trim(Mid(s, 1, InStr(s, " "))))
    sMode = Trim(Mid(s, InStr(s, " "), Len(s)))
     
    Dim yIndex As Integer, n As Integer
    yIndex = Val(Replace(yPos, "-", "")) + 1
    
    
    Console(ConsoleID, yIndex).DrawMode = i(sMode)
    
    Select Case i(sMode)
    
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

Public Sub ListMySubDomains(ByVal domain As String, ByVal ConsoleID As Integer)
    SayCOMM "Downloading subdomain list..."
    RunPage "my_domains.php?domain=" & EncodeURLParameter(domain) & "&type=subdomain", ConsoleID, False, "", 0
End Sub

Public Sub ListMyIPs(ByVal ConsoleID As Integer)
    SayCOMM "Downloading IP list..."
    RunPage "my_domains.php?type=ip", ConsoleID, False, "", 0
End Sub


Public Function IsInCommandsSubdirectory(ByVal sFile As String) As String
    
    IsInCommandsSubdirectory = ""
    
    frmConsole.Dir1.Path = App.Path & "\user\system\commands\"
    frmConsole.Dir1.Refresh
    
    sFile = Trim(sFile)
    If sFile = "" Then Exit Function
    
    Dim sPath As String
    Dim n As Integer
    
    For n = 0 To frmConsole.Dir1.ListCount - 1
        sPath = Replace(frmConsole.Dir1.List(n), App.Path & "\user", "")
        If sPath <> "" Then
        
        
            If FileExists(App.Path & "\user" & sPath & "\" & sFile) = True Then
                IsInCommandsSubdirectory = sPath & "\" & sFile
                Exit Function
            End If
            If FileExists(App.Path & "\user" & sPath & "\" & sFile & ".ds") = True Then
                IsInCommandsSubdirectory = sPath & "\" & sFile & ".ds"
                Exit Function
            End If
            
        
        End If
        
    Next n
End Function

Public Sub SetYDiv(s As String)
    On Error GoTo zxc
    
    s = Trim(Replace(s, "=", ""))
    If s = "" Then Exit Sub
    
    Dim n As Integer
    n = Val(s)
    
    If n < 0 Then n = 0
    If n > 720 Then n = 720
    
    yDiv = n
    
zxc:
End Sub

Public Sub ConnectToDomain(ByVal s As String, ByVal ConsoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    Dim sFilename As String
    Dim sFileData As String
    Dim sParams As String
    
    'If IsFromScript = False Then
    '    referals(ActiveConsole) = "A"
    'End If
    
    s = Replace(s, ":", " ")
    s = Trim(s)
    
    If s = "" Then GoTo zxc
    
    If InStr(s, " ") > 0 Then
        sDomain = i(Mid(s, 1, InStr(s, " ")))
    Else
        sDomain = i(s)
    End If
    
    If InStr(s, " ") > 0 Then
        sPort = Trim(Mid(s, InStr(s, " "), Len(s)))
        s = Trim(Mid(s, InStr(s, " "), Len(s)))
        If InStr(sPort, " ") > 0 Then sPort = Trim(Mid(sPort, 1, InStr(sPort, " ")))
        
        If InStr(s, " ") > 0 Then
            'there are parameters
            sParams = Trim(Mid(s, InStr(s, " "), Len(s)))
        Else
            sParams = ""
        End If
    End If
    

    If sPort = "" Then sPort = "80"
    
    If Val(sPort) < 1 Then
        SayError "Invalid Port Number: " & sPort, ConsoleID
        Exit Sub
    End If
    If Val(sPort) > 65536 Then
        SayError "Invalid Port Number: " & sPort, ConsoleID
        Exit Sub
    End If
    
    
    SayCOMM "Connecting to " & UCase(sDomain) & ":" & sPort & "..."
    Say ConsoleID, "{green}Connecting to " & UCase(sDomain) & ":" & sPort & "...", False
    
    RunPage "domain_connect.php?params=" & EncodeURLParameter(sParams) & _
    "&d=" & EncodeURLParameter(sDomain) & _
    "&port=" & EncodeURLParameter(sPort), ConsoleID
    


    
    Exit Sub
zxc:
    SayError "Invalid Parameters", ConsoleID
    ShowHelp "connect", ConsoleID
    
End Sub

Public Sub UploadToDomain(ByVal s As String, ByVal ConsoleID As Integer)
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
    sFilename = fixPath(sFilename, ConsoleID)
    

    
    If FileExists(App.Path & "\user" & sFilename) = True Then
        Dim tempStrA As String

        sFileData = GetFileClean(App.Path & "\user" & sFilename)
        tempStrA = EncodeBase64(StrConv(sFileData, vbFromUnicode))

        RunPage "domain_upload.php", ConsoleID, True, _
        "port=" & EncodeURLParameter(Trim(sPort)) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(tempStrA)
        
        SayCOMM "Attempting to upload: " & UCase(sDomain) & ":" & i(sPort), ConsoleID
        
    Else
        SayError "File Not Found:" & sFilename, ConsoleID
        Exit Sub
    End If

    Exit Sub
zxc:
    SayError "Invalid Parameters", ConsoleID
    ShowHelp "upload", ConsoleID
    
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
    "port=" & EncodeURLParameter(Trim(sPort)) & _
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
    sFilename = fixPath(sFilename, ConsoleID)
    


        RunPage "domain_download.php", ConsoleID, True, _
        "returnwith=4400" & _
        "&port=" & EncodeURLParameter(Trim(sPort)) & _
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
        Say ConsoleID, "A domain name should be in the following form: MYDOMAIN.COM{lorange}", False
        Say ConsoleID, "Subdomains should be in the form: BLOG.MYDOMAIN.COM{lorange}", False
        Say ConsoleID, "Valid domain name characters are:", False
        Say ConsoleID, "A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -{grey 8}", False
        Exit Sub
    End If
    
    Say ConsoleID, "{green 10}A registration request has been sent for " & s & ".", False
    Say ConsoleID, "{lgreen 10}The result will be posted to the COMM.", False
    
    
    'RunPage "domain_register.php?returnwith=2000&d=" & Trim(s), consoleID
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
    
    Say ConsoleID, "{green 10}A unregistration request has been sent for " & sDomain & ".", False
    Say ConsoleID, "{lgreen 10}The result will be posted to the COMM.", False

    
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

Public Sub f_Compile(ByVal s As String, ByVal ConsoleID As Integer)
    SayError "Compilation has been removed.", ConsoleID
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
        
    Case "set":
        If frmConsole.FileMusic.ListCount < 1 Then Exit Sub
        Dim tmpS As String, iTmp As Long
        tmpS = i(frmConsole.FileMusic.Path & "\" & Mid(sX, 5))
        If FileExists(tmpS) = True Then
            For iTmp = 0 To (frmConsole.FileMusic.ListCount - 1)
                If frmConsole.FileMusic.List(iTmp) = i(Mid(sX, 5)) Then
                    MusicFileIndex = iTmp
                    basMusic.PrevMusicIndex
                    basMusic.StopMusic
                End If
            Next iTmp
        End If
    End Select
    
End Sub


Public Sub ListKeys(ByVal ConsoleID As Integer)
    
    Dim ss As String
    ss = "{gold}"
    
    Say ConsoleID, "Dark Signs Keyboard Actions{gold 14}", False
    
    Say ConsoleID, "Page Up: Scroll the console up." & ss, False
    Say ConsoleID, "Page Down: Scroll the console down." & ss, False
    
    Say ConsoleID, "Shift + Page Up: Decrease size of the COMM." & ss, False
    Say ConsoleID, "Shift + Page Down: Incease size of the COMM." & ss, False
    
    Say ConsoleID, "F11: Toggle maximum console display." & ss, False
    
    
    
End Sub


Public Sub SetUsername(ByVal s As String, ByVal ConsoleID As Integer)

    
    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If
    
    
    If Trim(s) <> "" Then RegSave "myusernamedev", Trim(s)
    
        
    Dim tmpU As String, tmpP As String
    If Trim(myUsername) = "" Then tmpU = "[not specified]" Else tmpU = myUsername
    
    Say ConsoleID, "Your new details are shown below." & "{orange}", False
    Say ConsoleID, "Username: " & tmpU & "{orange 16}", False
    Say ConsoleID, "Password: " & "[hidden]" & "{orange 16}", False
    

End Sub

Public Sub SetPassword(ByVal s As String, ByVal ConsoleID As Integer)


    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If
    
    s = Trim(s)
    RegSave "mypassworddev", s
    
    Dim tmpU As String, tmpP As String
    If Trim(myUsername) = "" Then tmpU = "[not specified]" Else tmpU = myUsername
    
    Say ConsoleID, "Your new details are shown below." & "{orange}", False
    Say ConsoleID, "Username: " & tmpU & "{orange 16}", False
    Say ConsoleID, "Password: " & "[hidden]" & "{orange 16}", False


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


Public Sub DownADir(ByVal ConsoleID As Integer)
    On Error GoTo zxc
    
    If Len(cPath(ConsoleID)) < 2 Then Exit Sub
    
    Dim s As String
    s = Mid(cPath(ConsoleID), 1, Len(cPath(ConsoleID)) - 1)
    s = ReverseString(s)
    s = Mid(s, InStr(s, "\"), Len(s))
    s = ReverseString(s)
    
    
    cPath(ConsoleID) = s
zxc:
End Sub

Public Sub MakeDir(ByVal s As String, ByVal ConsoleID As Integer)
    
    If InvalidChars(s) = True Then
        SayError "Invalid Directory Name: " & s, ConsoleID
        Exit Sub
    End If
    
    If Trim(s) = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If

    s = fixPath(s, ConsoleID)
    
    If DirExists(App.Path & "\user" & s) = True Then
        'don't create it if it already exists
        GoTo errorDir
    Else
        MakeADir App.Path & "\user" & s
    End If
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub


Public Sub MoveRename(ByVal s As String, ByVal ConsoleID As Integer, Optional sTag As String)

    Dim s1 As String, s2 As String
    s = Trim(s)
    s = Replace(s, "/", "\")
    If InStr(s, " ") = 0 Then Exit Sub
    
    s1 = Trim(Mid(s, 1, InStr(s, " ")))
    s2 = Trim(Mid(s, InStr(s, " "), Len(s)))

    s1 = fixPath(s1, ConsoleID)
    s2 = fixPath(s2, ConsoleID)
    
    If InStr(i(s1), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Sub
    End If
    
    If FileExists(App.Path & "\user" & s1) = False Then
        SayError "File Not Found: " & s1, ConsoleID
        Exit Sub
    End If
    
    'now move it or copy it
    If i(sTag) = "copyonly" Then
        If CopyAFile(App.Path & "\user" & s1, App.Path & "\user" & s2, ConsoleID) = False Then
            SayError "Invalid Destination File: " & s2, ConsoleID
            Exit Sub
        End If
    Else
        If MoveAFile(App.Path & "\user" & s1, App.Path & "\user" & s2, ConsoleID) = False Then
            SayError "Invalid Destination File: " & s2, ConsoleID
            Exit Sub
        End If
    End If
    
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Function MoveAFile(Source As String, dest As String, ConsoleID As Integer) As Boolean
    On Error GoTo zxc

    
    If InStr(i(dest), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Function
    End If
    
    
    FileCopy Source, dest
    Kill Source

    MoveAFile = True
    Exit Function
zxc:
    MoveAFile = False
End Function

Public Function CopyAFile(Source As String, dest As String, ConsoleID As Integer) As Boolean
    On Error GoTo zxc
    
    If InStr(i(dest), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Function
    End If
    
    FileCopy Source, dest
    'Kill Source 'don't kill it, this is for copy

    CopyAFile = True
    Exit Function
zxc:
    CopyAFile = False
End Function

Public Sub DeleteFiles(ByVal s As String, ByVal ConsoleID As Integer)
    
    If Trim(s) = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If

    s = fixPath(s, ConsoleID)
    
    If InStr(i(s), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Sub
    End If
    
    
    DelFiles App.Path & "\user" & s, ConsoleID
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub EditFile(ByVal s As String, ByVal ConsoleID As Integer)
    
    s = Trim(fixPath(s, ConsoleID))
    
    If Len(s) < 2 Then
        SayError "The EDIT command requires a parameter.", ConsoleID
        ShowHelp "edit", ConsoleID
        Exit Sub
    End If
    
    EditorFile_Short = GetShortName(s)
    EditorFile_Long = s
        
    If FileExists(App.Path & "\user" & s) Then

    Else
        Say ConsoleID, "{green}File Not Found, Creating: " & s
    
    End If
    
    
    frmEditor.Show vbModal
    
    If Trim(EditorRunFile) <> "" Then
        Shift_Console_Lines ConsoleID
        Run_Script EditorRunFile, ConsoleID, "", "CONSOLE"
    End If
    
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub ShowMail(ByVal s As String, ByVal ConsoleID As Integer)
    
    s = Trim(fixPath(s, ConsoleID))
    
    frmDSOMail.Show vbModal
     
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub AppendAFile(ByVal s As String, ByVal ConsoleID As Integer)
    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters: APPEND " & s, ConsoleID
        Exit Sub
    End If
    
    Dim sFile As String
    Dim sData As String
    Dim sFileData As String
    Dim AppendToStartOfFile As Boolean
    
    sFile = Trim(fixPath(Mid(s, 1, InStr(s, " ")), ConsoleID))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If Mid(i(s), 1, 6) = "start " Then
        AppendToStartOfFile = True
        s = Trim(Mid(s, 7, Len(s)))
    ElseIf Mid(i(s), 1, 4) = "end " Then
        AppendToStartOfFile = False
        s = Trim(Mid(s, 5, Len(s)))
    Else
        AppendToStartOfFile = False
    End If
    
    If FileExists(App.Path & "\user" & sFile) = False Then
        'it will be created.
        sFileData = ""
    Else
        sFileData = GetFile(App.Path & "\user" & sFile)
    End If
    
    'add it to the data
    If AppendToStartOfFile = True Then
        sFileData = s & vbCrLf & sFileData
    Else
        sFileData = sFileData & vbCrLf & s
    End If
    
    
        
    If InStr(i(sFile), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Sub
    End If
    
    
    're write it!
    WriteFile App.Path & "\user" & sFile, sFileData
    
    
       
    
End Sub

Public Sub WriteAFile(ByVal s As String, ByVal ConsoleID As Integer, ByVal ScriptFrom As String)
    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters: WRITE " & s, ConsoleID
        Exit Sub
    End If
    
    Dim sFile As String
    Dim sData As String
    Dim sFileData As String

    
    sFile = Trim(fixPath(Mid(s, 1, InStr(s, " ")), ConsoleID))
    'If ScriptFrom <> "CONSOLE" Or ScriptFrom <> "BOOT" Then
            
    '    If DirExists(App.Path & "\user\temp") = False Then
    '        MsgBox "A"
    '        MakeADir App.Path & "\user\temp"
    '    End If
        
        
    
    
    
    '    sFile = "\temp\" & ScriptFrom & sFile
    'End If
   ' MsgBox sFile
    
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If InStr(i(sFile), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Sub
    End If
    
    

    're write it!
    WriteFile App.Path & "\user" & sFile, s
    
    
       
    
End Sub

Public Sub DisplayFile(ByVal s As String, ByVal ConsoleID As Integer)
    
    Dim sFile As String
    Dim startLine As Integer
    Dim MaxLines As Integer
    
    s = Trim(s)
    
    
    If InStr(s, " ") Then
        'file start and end lines are specified
        sFile = Trim(fixPath(Mid(s, 1, InStr(s, " ")), ConsoleID))
        
        s = Trim(Mid(s, InStr(s, " "), Len(s)))
        
        If InStr(s, " ") Then
            'both the start and amount of lines are specific
            startLine = Val(Mid(s, 1, InStr(s, " ")))
            MaxLines = Val(Trim(Mid(s, InStr(s, " "), Len(s))))
            
            If MaxLines < 1 Then
                SayError "Invalid Parameter Value: " & Trim(Str(MaxLines)), ConsoleID
                Exit Sub
            End If
            If startLine < 1 Then
                SayError "Invalid Parameter Value: " & Trim(Str(MaxLines)), ConsoleID
                Exit Sub
            End If
        Else
            'only the start line is specified
            startLine = Val(s)
            MaxLines = 29999
        End If
    Else
        'its just the filename
        sFile = Trim(fixPath(s, ConsoleID))
        startLine = 1
        MaxLines = 29999
    End If
    

    If FileExists(App.Path & "\user" & sFile) = False Then
        SayError "File Not Found: " & sFile, ConsoleID
        Exit Sub
    End If
    
    
    Dim FF As Long, tmpS As String, CLine As Integer, CLinePrinted As Integer

    FF = FreeFile
    Open App.Path & "\user" & sFile For Input As #FF
        Do Until EOF(FF)
            Line Input #FF, tmpS
            CLine = CLine + 1
            
            If CLine >= startLine Then
                If CLinePrinted < MaxLines Then
                    If Trim(tmpS) <> "" Then
                        Say ConsoleID, Chr(34) & "   " & tmpS & Chr(34), False, , 1
                        CLinePrinted = CLinePrinted + 1
                        If CLinePrinted Mod 24 = 0 Then PauseConsole "", ConsoleID
                    End If
                End If
            End If
        Loop
    Close #FF
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Function GetShortName(ByVal s As String) As String
    s = ReverseString(s)
    s = Replace(s, "/", "\")
    
    If InStr(s, "\") > 0 Then
    
        s = Mid(s, 1, InStr(s, "\") - 1)
        
    End If
    
    GetShortName = Trim(ReverseString(s))
End Function

Public Sub WaitNow(ByVal s As String, ByVal ConsoleID As Integer)
   s = Trim(s)

    
    's is ms
    Dim iMS As Long
    iMS = Val(s)
    If iMS < 1 Then iMS = 1
    If iMS > 60000 Then iMS = 60000
    
    'now set the wait timer with the ims interval
    
    frmConsole.tmrWait(ConsoleID).Enabled = False
    frmConsole.tmrWait(ConsoleID).Interval = iMS
    frmConsole.tmrWait(ConsoleID).Enabled = True
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub RunFileAsScript(ByVal s As String, ByVal ConsoleID As Integer)
    
    
    
    
    Dim sParams As String
    s = Trim(s)
    If InStr(s, " ") > 0 Then
        sParams = Trim(Mid(s, InStr(s, " "), Len(s)))
        s = Trim(Mid(s, 1, InStr(s, " ")))
    End If
    
    s = fixPath(s, ConsoleID)
    

    If FileExists(App.Path & "\user" & s) Then
        'run it as a script
        
        WriteErrorLog "RunFileAsScript"
        Shift_Console_Lines ConsoleID
        Run_Script s, ConsoleID, sParams, "CONSOLE"
        
    Else
        SayError "File Not Found: " & s, ConsoleID
    End If
    
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub DelFiles(sFiles As String, ByVal ConsoleID As Integer)
    On Error Resume Next
    Kill sFiles
End Sub

Public Sub RemoveDir(ByVal s As String, ByVal ConsoleID As Integer)
    
    If Trim(s) = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If

    s = fixPath(s, ConsoleID)
    
    If DirExists(App.Path & "\user" & s) = True Then
        'don't create it if it already exists
        If RemoveADir(App.Path & "\user" & s, ConsoleID) = False Then
            SayError "Directory Not Empty: " & s, ConsoleID
            Exit Sub
        End If
    Else
        'nothing to delete
    End If
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Function SayError(s As String, ByVal ConsoleID As Integer)
    Say ConsoleID, "Error - " & s & " {orange}", False
End Function

Public Function RemoveADir(s As String, cosoleID As Integer) As Boolean
    On Error GoTo zxc
    RmDir s
    RemoveADir = True
    Exit Function
zxc:
    RemoveADir = False
End Function

Public Sub MakeADir(s As String)
    On Error Resume Next
    MkDir s
End Sub

Public Sub ChangeDir(ByVal s As String, ByVal ConsoleID As Integer)
    s = Trim(s)
    
    If InvalidChars(s) = True Then
        SayError "Invalid Directory Name: " & s, ConsoleID
        Exit Sub
    End If
    
    If s = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If
    s = Replace(s, "/", "\")
    If s = "." Then Exit Sub
    If InStr(s, ".\") > 0 Then Exit Sub
    If InStr(s, "\.") > 0 Then Exit Sub
    

    s = fixPath(s, ConsoleID)
    
    'say consoleID, "path is " & s, False
    
    If DirExists(App.Path & "\user" & s) = True Then
        
        s = Replace(s, "\\", "\")
        s = s & "\"
        s = Replace(s, "\\", "\")
        
        cPath(ConsoleID) = s
    Else
        GoTo errorDir
    End If
    
    Exit Sub
errorDir:
    SayError "Directory Not Found: " & s, ConsoleID
End Sub

Public Function fixPath(ByVal s As String, ByVal ConsoleID As Integer) As String
    'file.s will come out as -> /file.s
    '/file.s will come out as -> /file.s
    'system/file.s will come out as -> /system/file.s
    'etc
    
    s = Trim(s)
    
    If Mid(s, 1, 1) = "/" Then s = "\" & Mid(s, 2, Len(s))
    
    If Mid(s, 1, 1) = "\" Then
        fixPath = s
    Else
        
        cPath(ConsoleID) = Replace(cPath(ConsoleID), "/", "\")
        
        If Right(cPath(ConsoleID), 1) = "\" Then
            fixPath = Mid(cPath(ConsoleID), 1, Len(cPath(ConsoleID)) - 1)
        End If
    End If
    
    fixPath = fixPath & "\" & s
    
    fixPath = Replace(fixPath, "../", "")
    fixPath = Replace(fixPath, "//", "/")
    fixPath = Replace(fixPath, "\\", "\")
    fixPath = Replace(fixPath, "..\", "")
    fixPath = Replace(fixPath, "/..", "")
    fixPath = Replace(fixPath, "\..", "")
    
    
End Function

Public Sub ListDirectoryContents(ByVal ConsoleID As Integer, Optional ByVal sFilter As String)
    On Error GoTo zxc

    sFilter = Trim(Replace(sFilter, "*", ""))
    
    Dim sPath As String, n As Integer, tmpS As String, sAll As String
    Dim dirMsg As String, fileMsg As String, fCount As Integer, dCount As Integer

    
    dirMsg = "Directory List {yellow 10}"
    fileMsg = "File List {yellow 10}"
    
    sPath = App.Path & "\user" & cPath(ConsoleID)
    
    
    
    'directories
    frmConsole.Dir1.Path = sPath
    frmConsole.Dir1.Refresh
    'say consoleID, dirMsg, False
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
                Say ConsoleID, sAll & "{lyellow}", False
                'DrawItUp "0 0 0 0 solid", consoleID
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        Say ConsoleID, sAll & "{lyellow}", False
        'DrawItUp "0 0 0 0 solid", consoleID
    End If
    
    sAll = ""

    
    


    'files
    frmConsole.File1.Pattern = "*"
    frmConsole.File1.Path = sPath
    frmConsole.File1.Refresh
    fCount = 0
    'say consoleID, fileMsg, False
    If frmConsole.File1.ListCount = 0 Then GoTo NoFilesFound
    For n = 0 To frmConsole.File1.ListCount - 1
        tmpS = Trim(Replace(frmConsole.File1.List(n), sPath, ""))
        
        If InStr(tmpS, UCase(sFilter)) > 0 Then
            fCount = fCount + 1
            sAll = sAll & tmpS & " (" & FormatKB(FileLen(sPath & "\" & tmpS)) & ")    "
            frmConsole.lfont.FontSize = RegLoad("Default_FontSize", "8")
            frmConsole.lfont.FontName = RegLoad("Default_FontName", "Verdana")
            frmConsole.lfont.Caption = sAll
            
            If frmConsole.lfont.Width > (frmConsole.Width - 4700) Then
                Say ConsoleID, sAll & "{}", False
                'DrawItUp "0 12 12 12 solid", consoleID
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        
        Say ConsoleID, sAll & "{}", False
        'DrawItUp "0 12 12 12 solid", consoleID
    End If
NoFilesFound:
    sAll = ""
    
    Say ConsoleID, Trim(Str(fCount)) & " file(s) and " & Trim(Str(dCount)) & " dir(s) found in " & cPath(ConsoleID) & " {green 10}", False
    
    Exit Sub
zxc:
    SayError "Path Not Found: " & cPath(ConsoleID), ConsoleID
End Sub


Public Sub PauseConsole(s As String, ByVal ConsoleID As Integer)
    If Data_For_Run_Function_Enabled(ConsoleID) = 1 Then Exit Sub
    
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
        Say ConsoleID, s, False
    Else
        'include the default property space
        Say ConsoleID, s & "{lblue 10}", False
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
    Say ConsoleID, s & " (**" & s & "**) {" & s & " 8}", False
End Sub

Public Sub ShowHelp(sP, ByVal ConsoleID As Integer)
    Dim props As String, propsforexamples As String
    props = "{green 12 underline}"
    propsforexamples = "{lgreen 12}"

    Select Case sP
    Case "help"
        Say ConsoleID, props & "Command: HELP", False
        Say ConsoleID, "{lgrey}Display the available console commands.", False
    Case "restart"
        Say ConsoleID, props & "Command: RESTART", False
        Say ConsoleID, "{lgrey}Restart the console immediately.", False
    Case "listcolors"
        Say ConsoleID, props & "Command: LISTCOLORS", False
        Say ConsoleID, "{lgrey}Display the available colors and color codes in the console.", False
    Case "listkeys"
        Say ConsoleID, props & "Command: LISTKEYS", False
        Say ConsoleID, "{lgrey}Display the available shortcut keys and their actions in the console.", False
    
    Case "time"
        Say ConsoleID, props & "Command: TIME", False
        Say ConsoleID, "{lgrey}Display the current system time.", False
    Case "date"
        Say ConsoleID, props & "Command: DATE", False
        Say ConsoleID, "{lgrey}Display the current system date.", False
    Case "now"
        Say ConsoleID, props & "Command: NOW", False
        Say ConsoleID, "{lgrey}Display the current system date and time.", False
    Case "clear"
        Say ConsoleID, props & "Command: CLEAR", False
        Say ConsoleID, "{lgrey}Clear the console screen.", False
    Case "stats"
        Say ConsoleID, props & "Command: STATS", False
        Say ConsoleID, "{lgrey}Display active information about the Dark Signs Network.", False
        Say ConsoleID, "{lorange}This information will be shown in the COMM window.", False
    
    Case "dir"
        
        Say ConsoleID, props & "Command: DIR optional-filter", False
        Say ConsoleID, "{lgrey}Display files and folders in the active directory.", False
        Say ConsoleID, "{lgrey}A filter can be appended to show only elements containing the filter keyword in their name.", False
        
    Case "pause"
        Say ConsoleID, props & "Command: PAUSE optional-msg", False
        Say ConsoleID, propsforexamples & "Example #1: PAUSE Press a key!", False
        Say ConsoleID, "{lgrey}Pause the console interface until the user presses a key.", False
    Case "cd"
        Say ConsoleID, props & "Command: CD directory-name", False
        Say ConsoleID, propsforexamples & "Example #1: CD myfiles", False
        Say ConsoleID, "{lgrey}Change the active path to the specified directory.", False
    Case "rd"
        Say ConsoleID, props & "Command: RD directory-name", False
        Say ConsoleID, propsforexamples & "Example #1: RD myfiles", False
        Say ConsoleID, "{lgrey}Delete the directory with the specified name.", False
        Say ConsoleID, "{lorange}The directory must be empty, or it will not be deleted.", False
    Case "del"
        Say ConsoleID, props & "Command: DEL filename", False
        Say ConsoleID, propsforexamples & "Example #1: DEL file.ds", False
        Say ConsoleID, "{lgrey}Delete the specified file or files.", False
        Say ConsoleID, "{lgrey}The wildcard symbol, *, can be used to delete multiple files at once.", False
        Say ConsoleID, "{lorange}Files in the system directory cannot be deleted.", False
        Say ConsoleID, "{orange}Be careful not to delete all of your files!", False
        
    Case "md"
        Say ConsoleID, props & "Command: MD directory-name", False
        Say ConsoleID, propsforexamples & "Example #1: MD myfiles", False
        Say ConsoleID, "{lgrey}Create a new empty directory with the specified name.", False
        Say ConsoleID, "{lorange}The name of the directory should not contain space characters.", False
            
    Case "lookup"
        Say ConsoleID, props & "Command: LOOKUP domain-or-username", False
        Say ConsoleID, propsforexamples & "Example #1: LOOKUP website.com", False
        Say ConsoleID, propsforexamples & "Example #2: LOOKUP jsmith", False
        Say ConsoleID, "{lgrey}View information about the specified domain name or user account.", False
        Say ConsoleID, "{lgrey}This command can be used on both domain names and user accounts.", False
        Say ConsoleID, "{lorange}Data will be returned in the COMM window.", False
                   
    Case "username"
        Say ConsoleID, props & "Command: USERNAME your-username", False
        Say ConsoleID, propsforexamples & "Example #1: USERNAME jsmith", False
        Say ConsoleID, "{lgrey}Set or change your Dark Signs username.", False
        Say ConsoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled.", False
        Say ConsoleID, "{lorange}If you do not have an account, visit the website to create one.", False
    Case "password"
        Say ConsoleID, props & "Command: PASSWORD your-password", False
        Say ConsoleID, propsforexamples & "Example #1: PASSWORD secret123", False
        Say ConsoleID, "{lgrey}Set or change your Dark Signs password.", False
        Say ConsoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled.", False
        Say ConsoleID, "{lorange}If you do not have an account, visit the website to create one.", False
    
    Case "ping"
        Say ConsoleID, props & "Command: PING domain-or-ip-server", False
        Say ConsoleID, propsforexamples & "Example #1: PING birds.com", False
        Say ConsoleID, "{lgrey}Check if the specified server exist on the network.", False
        Say ConsoleID, "{lorange}You can modify this command in the file \system\commands\ping.ds", False
    
    Case "me"
        Say ConsoleID, props & "Command: ME", False
        Say ConsoleID, propsforexamples & "Example #1: ME", False
        Say ConsoleID, "{lgrey}Do nothing at all!", False
        Say ConsoleID, "{lorange}This is a useless secret command.", False
    
    Case "pingport"
        Say ConsoleID, props & "Command: PINGPORT domain-or-ip-server 80", False
        Say ConsoleID, propsforexamples & "Example #1: PINGPORT birds.com 80", False
        Say ConsoleID, "{lgrey}Check if a script is runnning on the server at the specified port number.", False
        Say ConsoleID, "{lorange}You can modify this command in the file \system\commands\pingport.ds", False
            
    Case "getip"
        Say ConsoleID, props & "Command: GETIP domain-or-ip-server", False
        Say ConsoleID, propsforexamples & "Example #1: GETIP birds.com", False
        Say ConsoleID, "{lgrey}Get the IP address of the specified server.", False
        Say ConsoleID, "{lorange}You can modify this command in the file \system\commands\getip.ds", False
            
    Case "getdomain"
        Say ConsoleID, props & "Command: GETDOMAIN domain-or-ip-server", False
        Say ConsoleID, propsforexamples & "Example #1: GETDOMAIN 12.55.192.111", False
        Say ConsoleID, "{lgrey}Get the domain name of the specified server.", False
        Say ConsoleID, "{lorange}You can modify this command in the file \system\commands\getdomain.ds", False
                            
    Case "connect"
        Say ConsoleID, props & "Command: CONNECT server port-number [optional-parameters]", False
        Say ConsoleID, propsforexamples & "Example #1: CONNECT home.com 80", False
        Say ConsoleID, "{lgrey}Connect to a server domain name or IP address on the specified port.", False
        Say ConsoleID, "{lgrey}If no port number is specified, the default port number is 80.", False
        Say ConsoleID, "{lorange}You must specify the port number if you are including optional parameters.", False
 
        
            
    Case "move"
        Say ConsoleID, props & "Command: MOVE source-file destination-file", False
        Say ConsoleID, propsforexamples & "Example #1: MOVE myoldfile.ds mynewfile.ds", False
        Say ConsoleID, propsforexamples & "Example #2: MOVE /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        Say ConsoleID, "{lgrey}Rename the specified file.", False
        Say ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        Say ConsoleID, "{lorange}File names should not contain space characters.", False
    Case "rename"
        Say ConsoleID, props & "Command: RENAME source-file destination-file", False
        Say ConsoleID, propsforexamples & "Example #1: MD myoldfile.ds mynewfile.ds", False
        Say ConsoleID, propsforexamples & "Example #2: MD /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        Say ConsoleID, "{lgrey}Rename the specified file.", False
        Say ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        Say ConsoleID, "{lorange}File names should not contain space characters.", False
    Case "copy"
        Say ConsoleID, props & "Command: COPY source-file destination-file", False
        Say ConsoleID, propsforexamples & "Example #1: COPY myoldfile.ds mynewfile.ds", False
        Say ConsoleID, propsforexamples & "Example #2: COPY /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        Say ConsoleID, "{lgrey}Create a copy of the specified file.", False
        Say ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        Say ConsoleID, "{lorange}File names should not contain space characters.", False
    
    Case "saycomm"
        Say ConsoleID, props & "Command: SAYCOMM text", False
        Say ConsoleID, propsforexamples & "Example #1: SAYCOMM Connected to server", False
        Say ConsoleID, "{lgrey}Display the specified text in the COMM window.", False
        
    Case "run"
        Say ConsoleID, props & "Command: RUN file", False
        Say ConsoleID, propsforexamples & "Example #1: RUN myscript.ds", False
        Say ConsoleID, "{lgrey}Run the specified file as script in the console.", False
        Say ConsoleID, "{lgrey}Files not designed to be run as scripts may cause random errors to be displayed.", False
            
    Case "edit"
        Say ConsoleID, props & "Command: EDIT file", False
        Say ConsoleID, propsforexamples & "Example #1: EDIT myscript.ds", False
        Say ConsoleID, "{lgrey}Edit the specified file in the editing window. The console will pause while the editor is active.", False
        Say ConsoleID, "{lorange}Files in the editor are saved automatically.", False
                
'    Case "wait"
'        Say consoleID, props & "Command: WAIT milliseconds", False
'        Say consoleID, propsforexamples & "Example #1: WAIT 1000", False
'        Say consoleID, "{lgrey}Pause the console for the specific amount of time (between 1 and 60000 ms).", False
'        Say consoleID, "{lorange}1000 millisends is equal to 1 second.", False
'        Say consoleID, "{orange}This command is only enabled in scripts.", False
                    
    Case "upload"
        Say ConsoleID, props & "Command: UPLOAD server port-number file", False
        Say ConsoleID, propsforexamples & "Example #1: UPLOAD mywebsite.com 80 newscript.ds", False
        Say ConsoleID, "{lgrey}Upload a file to your domain name on the specified port.", False
        Say ConsoleID, "{lgrey}This script will then become connectable to all players.", False
        Say ConsoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own.", False
    
    Case "closeport"
        Say ConsoleID, props & "Command: CLOSEPORT server port-number", False
        Say ConsoleID, propsforexamples & "Example #1: CLOSEPORT mywebsite.com 80", False
        Say ConsoleID, "{lgrey}Close port on the specified domain.", False
        Say ConsoleID, "{lgrey}The script running on this port is deleted.", False
        Say ConsoleID, "{lorange}You can only close ports on domain names (servers) which you own.", False
                                      
    Case "download"
        Say ConsoleID, props & "Command: DOWNLOAD server port-number file", False
        Say ConsoleID, propsforexamples & "Example #1: DOWNLOAD mywebsite.com 80 thescript.ds", False
        Say ConsoleID, "{lgrey}Download a script file from a sever that you own.", False
        Say ConsoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own.", False
                             
    Case "transfer"
        Say ConsoleID, props & "Command: TRANSFER recipient-username amount description", False
        Say ConsoleID, propsforexamples & "Example #1: TRANSFER admin 5 A payment for you", False
        Say ConsoleID, "{lgrey}Transfer an amount of money (DS$) to the specified username.", False
        Say ConsoleID, "{lorange}Each transfer requires manual authorization from the sender.", False
                                    
    Case "ydiv"
        Say ConsoleID, props & "Command: YDIV height", False
        Say ConsoleID, propsforexamples & "Example #1: YDIV 240", False
        Say ConsoleID, "{lgrey}Change the default space between each console line.", False
        Say ConsoleID, "{lorange}The default YDIV is set to 60.", False
                                           
    Case "display"
        Say ConsoleID, props & "Command: DISPLAY file optional-start-line optional-max-lines", False
        Say ConsoleID, propsforexamples & "Example #1: DISPLAY myfile.txt 1 5", False
        Say ConsoleID, "{lgrey}Output the specified file to the console, without running as a script.", False
        Say ConsoleID, "{lorange}In the example, the first five lines of myfile.txt will be displayed.", False
                                                   
    Case "append"
        Say ConsoleID, props & "Command: APPEND file optional-START-or-END text", False
        Say ConsoleID, propsforexamples & "Example #1: APPEND myfile.txt new data", False
        Say ConsoleID, propsforexamples & "Example #2: APPEND myfile.txt START new data", False
        Say ConsoleID, "{lgrey}Append (add) text or data to the specified file.", False
        Say ConsoleID, "{lgrey}Data will be added to the beginning of the file if the START keyword is used.", False
        Say ConsoleID, "{lgrey}Data will be added to the end of the file if the END keyword is used.", False
        Say ConsoleID, "{lorange}If the specified file doesn't exist, it will be created.", False
                                                           
    Case "write"
        Say ConsoleID, props & "Command: WRITE file text", False
        Say ConsoleID, propsforexamples & "Example #1: WRITE myfile.txt new data", False
        Say ConsoleID, "{lgrey}Write text or data to the specified file.", False
        Say ConsoleID, "{lorange}If the specified file already exists, it will be overwritten.", False
        Say ConsoleID, "{lorange}Use APPEND to add data to an existing file.", False
        

    Case "register"
        Say ConsoleID, props & "Command: REGISTER domain-name", False
        Say ConsoleID, propsforexamples & "Example #1: REGISTER mynewwebsite.com", False
        Say ConsoleID, "{lgrey}Register a domain name on the Dark Signs Network.", False
        Say ConsoleID, "{lgrey}This command requires that you have the required amount of money (DS$) in your account.", False
        Say ConsoleID, "-", False
        Say ConsoleID, "{center orange nobold 14}- Check the latest prices in the COMM window. -", False
        'say consoleID, "-", False
        RunPage "domain_register.php?returnwith=2000&prices=1", ConsoleID
        
         
    Case "unregister"
        Say ConsoleID, props & "Command: UNREGISTER domain-name account-password", False
        Say ConsoleID, propsforexamples & "Example #1: UNREGISTER myoldwebsite.com secret123", False
        Say ConsoleID, "{lgrey}Unregister a domain name that you own on the Dark Signs Network.", False
        Say ConsoleID, "{lorange}This command requires that you include your password for security.", False
        
            
    Case "login"
        Say ConsoleID, props & "Command: LOGIN", False
        Say ConsoleID, "{lgrey}Attempt to log in to Dark Signs with your account username and password.", False
        Say ConsoleID, "{lgrey}This is only necessary if your status is 'not logged in'.", False
        Say ConsoleID, "{lorange}Use the USERNAME and PASSWORD commands to set or change your username or password.", False
        
    Case "logout"
        Say ConsoleID, props & "Command: LOGOUT", False
        Say ConsoleID, "{lgrey}Log out of Dark Signs.", False
        Say ConsoleID, "{lgrey}This can be helpful if you want to log in as another user, or if a rare error occurs.", False
            
    Case "mydomains"
        Say ConsoleID, props & "Command: MYDOMAINS", False
        Say ConsoleID, "{lgrey}List the domain names currently registered to you.", False
   
    Case "mysubdomains"
        Say ConsoleID, props & "Command: MYSUBDOMAINS", False
        Say ConsoleID, propsforexamples & "Example #1: MYSUBDOMAINS mySite.com", False
        Say ConsoleID, "{lgrey}List subdomains to a domain that is registed to you.", False
    
    Case "myips"
        Say ConsoleID, props & "Command: MYIPS", False
        Say ConsoleID, "{lgrey}List all IP addresses registed to you.", False
     
    Case "music"
        Say ConsoleID, props & "Command: MUSIC [parameter]", False
        Say ConsoleID, propsforexamples & "Example #1: MUSIC NEXT", False
        Say ConsoleID, "{lgrey}Music parameters are START, STOP, NEXT, and PREV.", False
        
    Case "say"
        Say ConsoleID, props & "Command: SAY text (**optional-properties**)", False
        Say ConsoleID, propsforexamples & "Example #1: SAY consoleID, hello, this is green (**green**)", False
        Say ConsoleID, propsforexamples & "Example #2: SAY consoleID, this is bold and very large (**bold, 36**)", False
        Say ConsoleID, "{lgrey}Display the specified text in the console.", False
        Say ConsoleID, "{lgrey}Text properties can be modified by adding any number of the following keywords in bewtween (** **), in any order.", False
        Say ConsoleID, "{lgreen}Colors: Type SHOWCOLORS the display a list of colors.", False
        Say ConsoleID, "{lgreen}Fonts: Arial, Arial Black, Comic Sans MS, Courier New, Georgia, Impact,", False
        Say ConsoleID, "{lgreen}Fonts: Lucida Console, Tahoma, Times New Roman, Trebuchet MS, Verdana, Wingdings.", False
        Say ConsoleID, "{lgreen}Attributes: Bold, NoBold, Italic, NoItalic, Underline, NoUnderline, Strikethru, NoStrikethru.", False
        Say ConsoleID, "{lgreen}Extras: Flash, Flashfast, FlashSlow.", False
        Say ConsoleID, "{orange}Note: You cannot use SAY to display multiple lines of text.", False
        Say ConsoleID, "{orange}For multiple lines, use SAYALL instead.", False
    
    Case "sayall"
        Say ConsoleID, props & "Command: SAYALL text (**optional-properties**)", False
        Say ConsoleID, propsforexamples & "Example #1: SAYALL hello", False
        Say ConsoleID, "{lgrey}Same as the SAY command, except will display multiple lines.", False
        Say ConsoleID, "{lorange}Type HELP SAY for more information.", False
             
    Case "sayline"
        Say ConsoleID, props & "Command: SAYLINE text (**optional-properties**)", False
        Say ConsoleID, propsforexamples & "Example #1: SAYLINE hello", False
        Say ConsoleID, "{lgrey}Same as the SAY command, except text will be printed on the same line, without moving down.", False
        Say ConsoleID, "{lorange}Type HELP SAY for more information.", False
           
    Case "remotedelete"
        Say ConsoleID, props & "Command: REMOTEDELETE domain filename", False
        Say ConsoleID, propsforexamples & "Example #1: REMOTEDELETE matrix.com myfile.ds", False
        Say ConsoleID, "{lgrey}Delete the specified file from the remote server.", False
        Say ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
    
    Case "remoteupload"
        Say ConsoleID, props & "Command: REMOTEUPLOAD domain filename", False
        Say ConsoleID, propsforexamples & "Example #1: REMOTEUPLOAD matrix.com localfile.ds", False
        Say ConsoleID, "{lgrey}Upload a file from your local file system to your domain name file system.", False
        Say ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
           
    Case "remotedir"
        Say ConsoleID, props & "Command: REMOTEDIR domain", False
        Say ConsoleID, propsforexamples & "Example #1: REMOTEDIR matrix.com", False
        Say ConsoleID, "{lgrey}View files on the remote server.", False
        Say ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
               
    Case "remoteview"
        Say ConsoleID, props & "Command: REMOTEVIEW domain filename", False
        Say ConsoleID, propsforexamples & "Example #1: REMOTEVIEW google.com userlist.log", False
        Say ConsoleID, "{lgrey}Display the specified remote file in the console.", False
        Say ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
    
    Case "draw"
        Say ConsoleID, props & "Command: DRAW -y Red(0-255) Green(0-255) Blue(0-255) mode", False
        Say ConsoleID, propsforexamples & "Example #1: DRAW -1 142 200 11 fadeout", False
        Say ConsoleID, "{lgrey}Print a background color stream to the console.", False
        Say ConsoleID, "{lgrey}The first parameter, -y, defines the console line.", False
        Say ConsoleID, "{lgrey}For example, -2 will draw to the second line up from the active line.", False
        Say ConsoleID, "{lgrey}The Red, Green, and Blue must be values between 0 and 255.", False
        Say ConsoleID, "{lorange}Available mode keywords: SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE.", False
        Say ConsoleID, "{orange}To use custom colors, use the DRAWCUSTOM command.", False
    
        
    
    Case "subowners"
        Say ConsoleID, props & "Command: SUBOWNERS domain-name KEYWORD [optional-username]", False
        Say ConsoleID, propsforexamples & "Example #1: SUBOWNERS site.com LIST", False
        Say ConsoleID, propsforexamples & "Example #2: SUBOWNERS site.com ADD friendusername", False
        Say ConsoleID, propsforexamples & "Example #3: SUBOWNERS site.com REMOVE friendusername", False
        Say ConsoleID, "{lgrey}Add or remove other user privileges regarding your specified domain name.", False
        Say ConsoleID, "{lgrey}You can add users to this list as subowners of your domain name.", False
        Say ConsoleID, "{lorange}Subowners have permission to interact, upload, and download files from the domain.", False
        Say ConsoleID, "{lorange}Subowners have no ability to unregister or modify the domain name  privileges.", False
        
        
        
    Case "lineup"
        Say ConsoleID, props & "Command: LINEUP", False
        Say ConsoleID, "{lgrey}Move up an extra console line. Useful for some scripts.", False
        
     'Case "chatsend"
     '   Say consoleID, props & "Command: CHATSEND Message to be sent to the chat.", False
     '   Say consoleID, propsforexamples & "Example #1: CHATSEND Hello World!", False
     '   Say consoleID, "{lgrey}A simple way to send messages to the chat from your console.", False
       
    
    Case "chatview"
        Say ConsoleID, props & "Command: CHATVIEW [parameter]", False
        Say ConsoleID, "{lgrey}If set to on, will display chat in the status window.", False
        Say ConsoleID, "{lgrey}CHATVIEW parameters are ON and OFF", False

    
    Case Else
        Say ConsoleID, props & "Available Commands", False
        'DrawItUp "0 0 0 0 solid", consoleID
        Say ConsoleID, "{lgrey 8}APPEND, CD, CLEAR, CLOSEPORT, CONNECT, COPY, DATE, DEL, DIR, DISPLAY, DOWNLOAD, DRAW, EDIT", False
        Say ConsoleID, "{lgrey 8}GETIP, GETDOMAIN, LINEUP, LISTCOLORS, LISTKEYS, LOGIN, LOGOUT, LOOKUP, MD, MOVE, MUSIC", False
        Say ConsoleID, "{lgrey 8}MYDOMAINS, MYIPS, MYSUBDOMAINS, NOW, PASSWORD, PAUSE, PING, PINGPORT, RD, RENAME, REGISTER", False
        Say ConsoleID, "{lgrey 8}REMOTEDELETE, REMOTEDIR, REMOTEUPLOAD, REMOTEVIEW, RESTART, RUN, SAY, SAYALL, SAYCOMM, STATS", False
        Say ConsoleID, "{lgrey 8}SUBOWNERS, TIME, TRANSFER, UNREGISTER, UPLOAD, USERNAME, WRITE, YDIV", False
        Say ConsoleID, "{grey}For more specific help on a command, type: HELP [command]", False
    End Select
End Sub

