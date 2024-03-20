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

        Set scrConsoleContext(X) = New clsScriptFunctions
        scrConsoleContext(X).Configure X, "", True, scrConsole(X)

        scrConsole(X).AddObject "DSO", scrConsoleContext(X), True
    Next
End Sub

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

    CancelScript(ConsoleID) = False
    New_Console_Line_InProgress ConsoleID

    On Error GoTo EvalError
    scrConsole(ConsoleID).AddCode Trim(tmpS)
    On Error GoTo 0

    GoTo ScriptEnd
    Exit Function
EvalError:
    If Err.Number = 9001 Then
        GoTo ScriptCancelled
    End If
    If Err.Number = 9002 Then
        GoTo ScriptEnd
    End If
    SAY ConsoleID, "Error processing script: " & Err.Description & " (" & Str(Err.Number) & ") {red}", False
    GoTo ScriptEnd

ScriptCancelled:
    SAY ConsoleID, "Script Stopped by User (CTRL + C){orange}", False
ScriptEnd:
    New_Console_Line ConsoleID
    Exit Function

    Dim n As Integer, tmpS2 As String
    
    Dim sC As String 'the main command
    Dim sP As String 'any parameters

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
        If FromScript = True Then 'then don't allow it
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
        Case "time": SAY ConsoleID, Format(Time, "h:mm AMPM"), False
        Case "date": SAY ConsoleID, Date, False
        Case "now": SAY ConsoleID, Now, False
        Case "restart": frmConsole.Start_Console ConsoleID: Exit Function
        Case "say": SAY ConsoleID, sP, False, FromScript
        Case "sayall": SayAll ConsoleID, sP, False, FromScript
        Case "sayline":
            'Shift_Console_Lines_Reverse (consoleID)
            
            SAY ConsoleID, sP, False, FromScript
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
        
        Case "server": If FromScript = True Then ServerCommands sP, ConsoleID
        
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
        
        
        Case "hello": SAY ConsoleID, "I am your console, not your friend! {green 24 georgia}", False
        Case "hi": SAY ConsoleID, "Hello to you as well! {green 24 georgia}", False
        Case "why": SAY ConsoleID, "That is a question that I cannot answer. {blue 24 georgia}", False
        Case "wow": SAY ConsoleID, "Yeah...{blue 18 georgia}", False: SAY ConsoleID, "it's pretty good...{blue 18 georgia center}", False: SAY ConsoleID, ":){blue 18 georgia right}", False:: SAY ConsoleID, "w00t!{center blue 24 bold georgia}", False
        Case "fuck": SAY ConsoleID, "I object to that sort of thing. {grey 24 georgia}", False
        Case "lol": SAY ConsoleID, UCase("j") & "{wingdings 144 center green}", False
        Case "ok":  SAY ConsoleID, "That's not a real command!{red impact 48 center nobold}", False
                    SAY ConsoleID, "What's wrong with you!?{red impact 48 center nobold}", False
        

        
        Case Else:
        

            'other alternatives!
            If Mid(sC, 1, 1) = "$" And Len(sC) > 1 Then
                'it's a variable being set
                
                SetVariable sC, sP, ConsoleID, ScriptFrom
                
                If FromScript = True Then
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
    New_Console_Line ConsoleID
End Function

Public Sub DrawItUp(ByVal S As String, ByVal ConsoleID As Integer)
    S = Trim(S)
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", ConsoleID
        ShowHelp "draw", ConsoleID
        Exit Sub
    End If
    
    Dim yPos As Long
    Dim R As Long, G As Long, b As Long
    Dim sColor As String
    Dim sMode As String
    
    yPos = Trim(Mid(S, 1, InStr(S, " ")))
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", ConsoleID
        ShowHelp "draw", ConsoleID
        Exit Sub
    End If
    
    R = Val(Trim(Mid(S, 1, InStr(S, " "))))
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", ConsoleID
        Exit Sub
    End If
    
    G = Val(Trim(Mid(S, 1, InStr(S, " "))))
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters", ConsoleID
        ShowHelp "draw", ConsoleID
        Exit Sub
    End If
    
    b = Val(Trim(Mid(S, 1, InStr(S, " "))))
    sMode = Trim(Mid(S, InStr(S, " "), Len(S)))
     
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

Public Sub SetYDiv(S As String)
    On Error GoTo zxc
    
    S = Trim(Replace(S, "=", ""))
    If S = "" Then Exit Sub
    
    Dim n As Integer
    n = Val(S)
    
    If n < 0 Then n = 0
    If n > 720 Then n = 720
    
    yDiv = n
    
zxc:
End Sub

Public Sub ConnectToDomain(ByVal S As String, ByVal ConsoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    Dim sFilename As String
    Dim sFileData As String
    Dim sParams As String
    
    'If IsFromScript = False Then
    '    referals(ActiveConsole) = "A"
    'End If
    
    S = Replace(S, ":", " ")
    S = Trim(S)
    
    If S = "" Then GoTo zxc
    
    If InStr(S, " ") > 0 Then
        sDomain = i(Mid(S, 1, InStr(S, " ")))
    Else
        sDomain = i(S)
    End If
    
    If InStr(S, " ") > 0 Then
        sPort = Trim(Mid(S, InStr(S, " "), Len(S)))
        S = Trim(Mid(S, InStr(S, " "), Len(S)))
        If InStr(sPort, " ") > 0 Then sPort = Trim(Mid(sPort, 1, InStr(sPort, " ")))
        
        If InStr(S, " ") > 0 Then
            'there are parameters
            sParams = Trim(Mid(S, InStr(S, " "), Len(S)))
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
    SAY ConsoleID, "{green}Connecting to " & UCase(sDomain) & ":" & sPort & "...", False
    
    RunPage "domain_connect.php?params=" & EncodeURLParameter(sParams) & _
    "&d=" & EncodeURLParameter(sDomain) & _
    "&port=" & EncodeURLParameter(sPort), ConsoleID
    


    
    Exit Sub
zxc:
    SayError "Invalid Parameters", ConsoleID
    ShowHelp "connect", ConsoleID
    
End Sub

Public Sub UploadToDomain(ByVal S As String, ByVal ConsoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    Dim sFilename As String
    Dim sFileData As String
    
    S = Trim(S)
    If InStr(S, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(S, 1, InStr(S, " ")))

    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    If InStr(S, " ") = 0 Then GoTo zxc
    
    sPort = i(Mid(S, 1, InStr(S, " ")))
    sFilename = Trim(Mid(S, InStr(S, " "), Len(S)))
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

Public Sub CloseDomainPort(ByVal S As String, ByVal ConsoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    
    S = Trim(S)
    If InStr(S, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(S, 1, InStr(S, " ")))
    
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    sPort = S
  
    RunPage "domain_close.php", ConsoleID, True, _
    "port=" & EncodeURLParameter(Trim(sPort)) & _
    "&d=" & EncodeURLParameter(sDomain)
        
    SayCOMM "Attempting to close port : " & UCase(sDomain) & ":" & i(sPort), ConsoleID
        
    Exit Sub
zxc:
    SayError "Invalid Parameters", ConsoleID
    ShowHelp "closeport", ConsoleID
    
End Sub


Public Sub DownloadFromDomain(ByVal S As String, ByVal ConsoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    Dim sFilename As String
    Dim sFileData As String
    
    S = Trim(S)
    If InStr(S, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(S, 1, InStr(S, " ")))
    
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    If InStr(S, " ") = 0 Then GoTo zxc
    
    sPort = i(Mid(S, 1, InStr(S, " ")))
    sFilename = Trim(Mid(S, InStr(S, " "), Len(S)))
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


Public Sub SubOwners(ByVal S As String, ByVal ConsoleID As Integer)
    S = i(S)

    Dim sDomain As String, sUsername As String
    
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "subowners", ConsoleID
        Exit Sub
    End If
    
    sDomain = Trim(Mid(S, 1, InStr(S, " ")))
    S = Trim(Mid(S, InStr(S, " ") + 1, Len(S)))
    
    If i(Mid(S, 1, 4)) = "list" Then
        'list the domain names
           
            RunPage "domain_privileges.php", ConsoleID, True, _
            "returnwith=2001&list=" & EncodeURLParameter(Trim(sDomain))

    ElseIf Mid(i(S), 1, 4) = "add " Then
        sUsername = Trim(Mid(S, 5, Len(S)))
            
            RunPage "domain_privileges.php", ConsoleID, True, _
            "returnwith=2001&add=" & EncodeURLParameter(Trim(sDomain)) & "&username=" & EncodeURLParameter(sUsername)

    ElseIf Mid(i(S), 1, 7) = "remove " Then
        sUsername = Trim(Mid(S, 8, Len(S)))
        
             RunPage "domain_privileges.php", ConsoleID, True, _
            "returnwith=2001&remove=" & EncodeURLParameter(Trim(sDomain)) & "&username=" & EncodeURLParameter(sUsername)

    Else
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "subowners", ConsoleID
        Exit Sub
    End If
    
    

    
End Sub

Public Sub RegisterDomain(ByVal S As String, ByVal ConsoleID As Integer)
    S = i(S)
    S = Trim(S)
    
    If S = "" Then
        SayError "The REGISTER command requires a parameter.", ConsoleID
        ShowHelp "register", ConsoleID
        Exit Sub
    End If
    
    If CountCharInString(S, ".") < 1 Or CountCharInString(S, ".") > 3 Or HasBadDomainChar(S) = True Or Len(S) < 5 Or Left(S, 1) = "." Or Right(S, 1) = "." Then
        SayError "The domain name you specified is invalid or contains bad characters.{orange}", ConsoleID
        SAY ConsoleID, "A domain name should be in the following form: MYDOMAIN.COM{lorange}", False
        SAY ConsoleID, "Subdomains should be in the form: BLOG.MYDOMAIN.COM{lorange}", False
        SAY ConsoleID, "Valid domain name characters are:", False
        SAY ConsoleID, "A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -{grey 8}", False
        Exit Sub
    End If
    
    SAY ConsoleID, "{green 10}A registration request has been sent for " & S & ".", False
    SAY ConsoleID, "{lgreen 10}The result will be posted to the COMM.", False
    
    
    'RunPage "domain_register.php?returnwith=2000&d=" & Trim(s), consoleID
    RunPage "domain_register.php", ConsoleID, True, "d=" & EncodeURLParameter(S)
    
End Sub

Public Sub UnRegisterDomain(ByVal S As String, ByVal ConsoleID As Integer)
    S = Trim(S)
    If S = "" Then
        SayError "The UNREGISTER command requires parameters.", ConsoleID
        ShowHelp "unregister", ConsoleID
        Exit Sub
    End If
    

    Dim sDomain As String
    Dim sPass As String
    
    If InStr(S, " ") > 0 Then
        sDomain = LCase(Trim(Mid(S, 1, InStr(S, " "))))
        sPass = Trim(Mid(S, InStr(S, " "), Len(S)))
    Else
        SayError "Your password is required as a final parameter.", ConsoleID
        ShowHelp "unregister", ConsoleID
        Exit Sub
    End If
    
    SAY ConsoleID, "{green 10}A unregistration request has been sent for " & sDomain & ".", False
    SAY ConsoleID, "{lgreen 10}The result will be posted to the COMM.", False

    
    RunPage "domain_unregister.php", ConsoleID, True, _
    "returnwith=2000&d=" & EncodeURLParameter(Trim(sDomain)) & "&pw=" & EncodeURLParameter(sPass)
End Sub

Public Sub ServerCommands(ByVal S As String, ByVal ConsoleID As Integer)
    Dim sCommand As String
    Dim sDomain As String
    Dim sKey As String
    

    'check for a keycode, if it doesn't have one, its from a local script (so exit)
    

    If InStr(S, ":----:") = 0 Then Exit Sub
    
    'SERVER KEY:---:DOMAIN:----:WRITE
    
    sKey = Trim(Mid(S, 1, InStr(S, ":----:") - 1))
    sDomain = Trim(Mid(sKey, InStr(sKey, ":---:") + 5, Len(sKey)))
    sKey = Mid(sKey, 1, InStr(sKey, ":---:") - 1)
    
    
    sCommand = Trim(Mid(S, InStr(S, ":----:") + 6, Len(S)))
    
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

Public Sub ServerCommand_Append(S As String, sKey As String, sDomain As String, ByVal ConsoleID As Integer)

    Dim sPostData As String
    Dim sFilename As String
    Dim sFileData As String
    
    S = Trim(S)
    If InStr(S, " ") = 0 Then Exit Sub
    sFilename = Trim(Mid(S, 1, InStr(S, " ")))
    sFileData = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    sPostData = "append=" & EncodeURLParameter(sFilename) & _
        "&keycode=" & EncodeURLParameter(sKey) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(sFileData)
    
    RunPage "domain_filesystem.php", ConsoleID, True, sPostData, 0

End Sub


Public Sub ServerCommand_Write(S As String, sKey As String, sDomain As String, ByVal ConsoleID As Integer)

    Dim sPostData As String
    Dim sFilename As String
    Dim sFileData As String
    
    S = Trim(S)
    If InStr(S, " ") = 0 Then Exit Sub
    sFilename = Trim(Mid(S, 1, InStr(S, " ")))
    sFileData = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    sPostData = "write=" & EncodeURLParameter(sFilename) & _
        "&keycode=" & EncodeURLParameter(sKey) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(sFileData)
        
    RunPage "domain_filesystem.php", ConsoleID, True, sPostData, 0

End Sub


Public Sub TransferMoney(ByVal S As String, ByVal ConsoleID As Integer)
    Dim sTo As String
    Dim sAmount As String
    Dim sDescription As String

    S = Trim(S)
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "transfer", ConsoleID
        Exit Sub
    End If
    
    sTo = Trim(Mid(S, 1, InStr(S, " ")))
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters.", ConsoleID
        ShowHelp "transfer", ConsoleID
        Exit Sub
    End If
    
    sAmount = Trim(Mid(S, 1, InStr(S, " ")))
    sDescription = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    
    
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

Public Sub Lookup(ByVal S As String, ByVal ConsoleID As Integer)
    S = i(S)
    S = Trim(S)
    If S = "" Then
        SayError "The LOOKUP command requires a parameter.", ConsoleID
        ShowHelp "lookup", ConsoleID
        Exit Sub
    End If
    
    
    RunPage "lookup.php?returnwith=2000&d=" & EncodeURLParameter(Trim(S)), ConsoleID
    
End Sub

Public Sub f_Compile(ByVal S As String, ByVal ConsoleID As Integer)
    SayError "Compilation has been removed.", ConsoleID
End Sub


Public Function HasBadDomainChar(ByVal S As String) As Boolean
    HasBadDomainChar = False
    
    If InStr(S, "!") > 0 Then HasBadDomainChar = True
    If InStr(S, "@") > 0 Then HasBadDomainChar = True
    If InStr(S, "#") > 0 Then HasBadDomainChar = True
    If InStr(S, "$") > 0 Then HasBadDomainChar = True
    If InStr(S, "%") > 0 Then HasBadDomainChar = True
    If InStr(S, "^") > 0 Then HasBadDomainChar = True
    If InStr(S, "&") > 0 Then HasBadDomainChar = True
    If InStr(S, "*") > 0 Then HasBadDomainChar = True
    If InStr(S, "(") > 0 Then HasBadDomainChar = True
    If InStr(S, ")") > 0 Then HasBadDomainChar = True
    If InStr(S, "_") > 0 Then HasBadDomainChar = True
    If InStr(S, "+") > 0 Then HasBadDomainChar = True
    If InStr(S, "=") > 0 Then HasBadDomainChar = True
    If InStr(S, "~") > 0 Then HasBadDomainChar = True
    If InStr(S, "`") > 0 Then HasBadDomainChar = True
    If InStr(S, "[") > 0 Then HasBadDomainChar = True
    If InStr(S, "]") > 0 Then HasBadDomainChar = True
    If InStr(S, "{") > 0 Then HasBadDomainChar = True
    If InStr(S, "}") > 0 Then HasBadDomainChar = True
    If InStr(S, "\") > 0 Then HasBadDomainChar = True
    If InStr(S, "|") > 0 Then HasBadDomainChar = True
    If InStr(S, ";") > 0 Then HasBadDomainChar = True
    If InStr(S, Chr(34)) > 0 Then HasBadDomainChar = True
    If InStr(S, "'") > 0 Then HasBadDomainChar = True
    If InStr(S, ":") > 0 Then HasBadDomainChar = True
    If InStr(S, ",") > 0 Then HasBadDomainChar = True
    If InStr(S, "<") > 0 Then HasBadDomainChar = True
    If InStr(S, ">") > 0 Then HasBadDomainChar = True
    If InStr(S, "/") > 0 Then HasBadDomainChar = True
    If InStr(S, "?") > 0 Then HasBadDomainChar = True
    
    
End Function

Public Sub ShowStats(ByVal ConsoleID As Integer)
    
    SayCOMM "Downloading stats..."
    RunPage "get_user_stats.php?returnwith=2000", ConsoleID

End Sub


Public Sub MusicCommand(ByVal sX As String)
    
    
    Dim S As String
    If InStr(sX, " ") > 0 Then
        S = Mid(sX, 1, InStr(sX, " "))
    Else
        S = sX
    End If
    Select Case i(S)
    
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
    
    SAY ConsoleID, "Dark Signs Keyboard Actions{gold 14}", False
    
    SAY ConsoleID, "Page Up: Scroll the console up." & ss, False
    SAY ConsoleID, "Page Down: Scroll the console down." & ss, False
    
    SAY ConsoleID, "Shift + Page Up: Decrease size of the COMM." & ss, False
    SAY ConsoleID, "Shift + Page Down: Incease size of the COMM." & ss, False
    
    SAY ConsoleID, "F11: Toggle maximum console display." & ss, False
    
    
    
End Sub


Public Sub SetUsername(ByVal S As String, ByVal ConsoleID As Integer)

    
    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If
    
    
    If Trim(S) <> "" Then RegSave "myusernamedev", Trim(S)
    
        
    Dim tmpU As String, tmpP As String
    If Trim(myUsername) = "" Then tmpU = "[not specified]" Else tmpU = myUsername
    
    SAY ConsoleID, "Your new details are shown below." & "{orange}", False
    SAY ConsoleID, "Username: " & tmpU & "{orange 16}", False
    SAY ConsoleID, "Password: " & "[hidden]" & "{orange 16}", False
    

End Sub

Public Sub SetPassword(ByVal S As String, ByVal ConsoleID As Integer)


    If Authorized = True Then
        SayError "You are already logged in.", ConsoleID
        Exit Sub
    End If
    
    S = Trim(S)
    RegSave "mypassworddev", S
    
    Dim tmpU As String, tmpP As String
    If Trim(myUsername) = "" Then tmpU = "[not specified]" Else tmpU = myUsername
    
    SAY ConsoleID, "Your new details are shown below." & "{orange}", False
    SAY ConsoleID, "Username: " & tmpU & "{orange 16}", False
    SAY ConsoleID, "Password: " & "[hidden]" & "{orange 16}", False


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
    
    Dim S As String
    S = Mid(cPath(ConsoleID), 1, Len(cPath(ConsoleID)) - 1)
    S = ReverseString(S)
    S = Mid(S, InStr(S, "\"), Len(S))
    S = ReverseString(S)
    
    
    cPath(ConsoleID) = S
zxc:
End Sub

Public Sub MakeDir(ByVal S As String, ByVal ConsoleID As Integer)
    
    If InvalidChars(S) = True Then
        SayError "Invalid Directory Name: " & S, ConsoleID
        Exit Sub
    End If
    
    If Trim(S) = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(S, "..") > 0 Then
        GoTo errorDir
    End If

    S = fixPath(S, ConsoleID)
    
    If DirExists(App.Path & "\user" & S) = True Then
        'don't create it if it already exists
        GoTo errorDir
    Else
        MakeADir App.Path & "\user" & S
    End If
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub


Public Sub MoveRename(ByVal S As String, ByVal ConsoleID As Integer, Optional sTag As String)

    Dim s1 As String, s2 As String
    S = Trim(S)
    S = Replace(S, "/", "\")
    If InStr(S, " ") = 0 Then Exit Sub
    
    s1 = Trim(Mid(S, 1, InStr(S, " ")))
    s2 = Trim(Mid(S, InStr(S, " "), Len(S)))

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

Public Sub DeleteFiles(ByVal S As String, ByVal ConsoleID As Integer)
    
    If Trim(S) = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(S, "..") > 0 Then
        GoTo errorDir
    End If

    S = fixPath(S, ConsoleID)
    
    If InStr(i(S), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Sub
    End If
    
    
    DelFiles App.Path & "\user" & S, ConsoleID
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub EditFile(ByVal S As String, ByVal ConsoleID As Integer)
    
    S = Trim(fixPath(S, ConsoleID))
    
    If Len(S) < 2 Then
        SayError "The EDIT command requires a parameter.", ConsoleID
        ShowHelp "edit", ConsoleID
        Exit Sub
    End If
    
    EditorFile_Short = GetShortName(S)
    EditorFile_Long = S
        
    If FileExists(App.Path & "\user" & S) Then

    Else
        SAY ConsoleID, "{green}File Not Found, Creating: " & S
    
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

Public Sub ShowMail(ByVal S As String, ByVal ConsoleID As Integer)
    
    S = Trim(fixPath(S, ConsoleID))
    
    frmDSOMail.Show vbModal
     
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub AppendAFile(ByVal S As String, ByVal ConsoleID As Integer)
    S = Trim(S)
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters: APPEND " & S, ConsoleID
        Exit Sub
    End If
    
    Dim sFile As String
    Dim sData As String
    Dim sFileData As String
    Dim AppendToStartOfFile As Boolean
    
    sFile = Trim(fixPath(Mid(S, 1, InStr(S, " ")), ConsoleID))
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    If Mid(i(S), 1, 6) = "start " Then
        AppendToStartOfFile = True
        S = Trim(Mid(S, 7, Len(S)))
    ElseIf Mid(i(S), 1, 4) = "end " Then
        AppendToStartOfFile = False
        S = Trim(Mid(S, 5, Len(S)))
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
        sFileData = S & vbCrLf & sFileData
    Else
        sFileData = sFileData & vbCrLf & S
    End If
    
    
        
    If InStr(i(sFile), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Sub
    End If
    
    
    're write it!
    WriteFile App.Path & "\user" & sFile, sFileData
    
    
       
    
End Sub

Public Sub WriteAFile(ByVal S As String, ByVal ConsoleID As Integer, ByVal ScriptFrom As String)
    S = Trim(S)
    If InStr(S, " ") = 0 Then
        SayError "Invalid Parameters: WRITE " & S, ConsoleID
        Exit Sub
    End If
    
    Dim sFile As String
    Dim sData As String
    Dim sFileData As String

    
    sFile = Trim(fixPath(Mid(S, 1, InStr(S, " ")), ConsoleID))
    'If ScriptFrom <> "CONSOLE" Or ScriptFrom <> "BOOT" Then
            
    '    If DirExists(App.Path & "\user\temp") = False Then
    '        MsgBox "A"
    '        MakeADir App.Path & "\user\temp"
    '    End If
        
        
    
    
    
    '    sFile = "\temp\" & ScriptFrom & sFile
    'End If
   ' MsgBox sFile
    
    S = Trim(Mid(S, InStr(S, " "), Len(S)))
    
    If InStr(i(sFile), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", ConsoleID
        Exit Sub
    End If
    
    

    're write it!
    WriteFile App.Path & "\user" & sFile, S
    
    
       
    
End Sub

Public Sub DisplayFile(ByVal S As String, ByVal ConsoleID As Integer)
    
    Dim sFile As String
    Dim startLine As Integer
    Dim MaxLines As Integer
    
    S = Trim(S)
    
    
    If InStr(S, " ") Then
        'file start and end lines are specified
        sFile = Trim(fixPath(Mid(S, 1, InStr(S, " ")), ConsoleID))
        
        S = Trim(Mid(S, InStr(S, " "), Len(S)))
        
        If InStr(S, " ") Then
            'both the start and amount of lines are specific
            startLine = Val(Mid(S, 1, InStr(S, " ")))
            MaxLines = Val(Trim(Mid(S, InStr(S, " "), Len(S))))
            
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
            startLine = Val(S)
            MaxLines = 29999
        End If
    Else
        'its just the filename
        sFile = Trim(fixPath(S, ConsoleID))
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
                        SAY ConsoleID, Chr(34) & "   " & tmpS & Chr(34), False, , 1
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

Public Function GetShortName(ByVal S As String) As String
    S = ReverseString(S)
    S = Replace(S, "/", "\")
    
    If InStr(S, "\") > 0 Then
    
        S = Mid(S, 1, InStr(S, "\") - 1)
        
    End If
    
    GetShortName = Trim(ReverseString(S))
End Function

Public Sub WaitNow(ByVal S As String, ByVal ConsoleID As Integer)
   S = Trim(S)

    
    's is ms
    Dim iMS As Long
    iMS = Val(S)
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

Public Sub RunFileAsScript(ByVal S As String, ByVal ConsoleID As Integer)
    Dim sParams As String
    S = Trim(S)
    If InStr(S, " ") > 0 Then
        sParams = Trim(Mid(S, InStr(S, " "), Len(S)))
        S = Trim(Mid(S, 1, InStr(S, " ")))
    End If
    
    S = fixPath(S, ConsoleID)
    

    If FileExists(App.Path & "\user" & S) Then
        'run it as a script
        
        Shift_Console_Lines ConsoleID
        Run_Script S, ConsoleID, sParams, "CONSOLE"
        
    Else
        SayError "File Not Found: " & S, ConsoleID
    End If
    
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub DelFiles(sFiles As String, ByVal ConsoleID As Integer)
    On Error Resume Next
    Kill sFiles
End Sub

Public Sub RemoveDir(ByVal S As String, ByVal ConsoleID As Integer)
    
    If Trim(S) = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(S, "..") > 0 Then
        GoTo errorDir
    End If

    S = fixPath(S, ConsoleID)
    
    If DirExists(App.Path & "\user" & S) = True Then
        'don't create it if it already exists
        If RemoveADir(App.Path & "\user" & S, ConsoleID) = False Then
            SayError "Directory Not Empty: " & S, ConsoleID
            Exit Sub
        End If
    Else
        'nothing to delete
    End If
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Function SayError(S As String, ByVal ConsoleID As Integer)
    SAY ConsoleID, "Error - " & S & " {orange}", False
End Function

Public Function RemoveADir(S As String, cosoleID As Integer) As Boolean
    On Error GoTo zxc
    RmDir S
    RemoveADir = True
    Exit Function
zxc:
    RemoveADir = False
End Function

Public Sub MakeADir(S As String)
    On Error Resume Next
    MkDir S
End Sub

Public Sub ChangeDir(ByVal S As String, ByVal ConsoleID As Integer)
    If InvalidChars(S) = True Then
        SayError "Invalid Directory Name: " & S, ConsoleID
        Exit Sub
    End If

    If S = ".." Then DownADir ConsoleID: Exit Sub
    If InStr(S, "..") > 0 Then
        GoTo errorDir
    End If
    S = Replace(S, "/", "\")
    If S = "." Then Exit Sub
    If InStr(S, ".\") > 0 Then Exit Sub
    If InStr(S, "\.") > 0 Then Exit Sub

    S = fixPath(S, ConsoleID)
    
    If DirExists(App.Path & "\user" & S) = True Then
        
        S = Replace(S, "\\", "\")
        S = S & "\"
        S = Replace(S, "\\", "\")
        
        cPath(ConsoleID) = S
    Else
        GoTo errorDir
    End If
    
    Exit Sub
errorDir:
    SayError "Directory Not Found: " & S, ConsoleID
End Sub

Public Function fixPath(ByVal S As String, ByVal ConsoleID As Integer) As String
    'file.s will come out as -> /file.s
    '/file.s will come out as -> /file.s
    'system/file.s will come out as -> /system/file.s
    'etc
    
    S = Trim(S)
    
    If Mid(S, 1, 1) = "/" Then S = "\" & Mid(S, 2, Len(S))
    
    If Mid(S, 1, 1) = "\" Then
        fixPath = S
    Else
        
        cPath(ConsoleID) = Replace(cPath(ConsoleID), "/", "\")
        
        If Right(cPath(ConsoleID), 1) = "\" Then
            fixPath = Mid(cPath(ConsoleID), 1, Len(cPath(ConsoleID)) - 1)
        End If
    End If
    
    fixPath = fixPath & "\" & S
    
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
                SAY ConsoleID, sAll & "{lyellow}", False
                'DrawItUp "0 0 0 0 solid", consoleID
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        SAY ConsoleID, sAll & "{lyellow}", False
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
                SAY ConsoleID, sAll & "{}", False
                'DrawItUp "0 12 12 12 solid", consoleID
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        
        SAY ConsoleID, sAll & "{}", False
        'DrawItUp "0 12 12 12 solid", consoleID
    End If
NoFilesFound:
    sAll = ""
    
    SAY ConsoleID, Trim(Str(fCount)) & " file(s) and " & Trim(Str(dCount)) & " dir(s) found in " & cPath(ConsoleID) & " {green 10}", False
    
    Exit Sub
zxc:
    SayError "Path Not Found: " & cPath(ConsoleID), ConsoleID
End Sub


Public Sub PauseConsole(S As String, ByVal ConsoleID As Integer)
    If Data_For_Run_Function_Enabled(ConsoleID) = 1 Then Exit Sub
    
    ConsolePaused(ConsoleID) = True
    
    Dim propSpace As String
    
    If Trim(Kill_Property_Space(S)) = "" Then
        propSpace = "{" & Trim(Get_Property_Space(S)) & "}"
        
        If Len(propSpace) > 3 Then
            S = propSpace & "Press any key to continue..."
        Else
            S = "Press any key to continue..."
        End If
    
    End If
    


    If Has_Property_Space(S) = True Then
        SAY ConsoleID, S, False
    Else
        'include the default property space
        SAY ConsoleID, S & "{lblue 10}", False
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

Sub ShowCol(ByVal S As String, ByVal ConsoleID As Integer)
    SAY ConsoleID, S & " (**" & S & "**) {" & S & " 8}", False
End Sub

Public Sub ShowHelp(sP, ByVal ConsoleID As Integer)
    Dim props As String, propsforexamples As String
    props = "{green 12 underline}"
    propsforexamples = "{lgreen 12}"

    Select Case sP
    Case "help"
        SAY ConsoleID, props & "Command: HELP", False
        SAY ConsoleID, "{lgrey}Display the available console commands.", False
    Case "restart"
        SAY ConsoleID, props & "Command: RESTART", False
        SAY ConsoleID, "{lgrey}Restart the console immediately.", False
    Case "listcolors"
        SAY ConsoleID, props & "Command: LISTCOLORS", False
        SAY ConsoleID, "{lgrey}Display the available colors and color codes in the console.", False
    Case "listkeys"
        SAY ConsoleID, props & "Command: LISTKEYS", False
        SAY ConsoleID, "{lgrey}Display the available shortcut keys and their actions in the console.", False
    
    Case "time"
        SAY ConsoleID, props & "Command: TIME", False
        SAY ConsoleID, "{lgrey}Display the current system time.", False
    Case "date"
        SAY ConsoleID, props & "Command: DATE", False
        SAY ConsoleID, "{lgrey}Display the current system date.", False
    Case "now"
        SAY ConsoleID, props & "Command: NOW", False
        SAY ConsoleID, "{lgrey}Display the current system date and time.", False
    Case "clear"
        SAY ConsoleID, props & "Command: CLEAR", False
        SAY ConsoleID, "{lgrey}Clear the console screen.", False
    Case "stats"
        SAY ConsoleID, props & "Command: STATS", False
        SAY ConsoleID, "{lgrey}Display active information about the Dark Signs Network.", False
        SAY ConsoleID, "{lorange}This information will be shown in the COMM window.", False
    
    Case "dir"
        
        SAY ConsoleID, props & "Command: DIR optional-filter", False
        SAY ConsoleID, "{lgrey}Display files and folders in the active directory.", False
        SAY ConsoleID, "{lgrey}A filter can be appended to show only elements containing the filter keyword in their name.", False
        
    Case "pause"
        SAY ConsoleID, props & "Command: PAUSE optional-msg", False
        SAY ConsoleID, propsforexamples & "Example #1: PAUSE Press a key!", False
        SAY ConsoleID, "{lgrey}Pause the console interface until the user presses a key.", False
    Case "cd"
        SAY ConsoleID, props & "Command: CD directory-name", False
        SAY ConsoleID, propsforexamples & "Example #1: CD myfiles", False
        SAY ConsoleID, "{lgrey}Change the active path to the specified directory.", False
    Case "rd"
        SAY ConsoleID, props & "Command: RD directory-name", False
        SAY ConsoleID, propsforexamples & "Example #1: RD myfiles", False
        SAY ConsoleID, "{lgrey}Delete the directory with the specified name.", False
        SAY ConsoleID, "{lorange}The directory must be empty, or it will not be deleted.", False
    Case "del"
        SAY ConsoleID, props & "Command: DEL filename", False
        SAY ConsoleID, propsforexamples & "Example #1: DEL file.ds", False
        SAY ConsoleID, "{lgrey}Delete the specified file or files.", False
        SAY ConsoleID, "{lgrey}The wildcard symbol, *, can be used to delete multiple files at once.", False
        SAY ConsoleID, "{lorange}Files in the system directory cannot be deleted.", False
        SAY ConsoleID, "{orange}Be careful not to delete all of your files!", False
        
    Case "md"
        SAY ConsoleID, props & "Command: MD directory-name", False
        SAY ConsoleID, propsforexamples & "Example #1: MD myfiles", False
        SAY ConsoleID, "{lgrey}Create a new empty directory with the specified name.", False
        SAY ConsoleID, "{lorange}The name of the directory should not contain space characters.", False
            
    Case "lookup"
        SAY ConsoleID, props & "Command: LOOKUP domain-or-username", False
        SAY ConsoleID, propsforexamples & "Example #1: LOOKUP website.com", False
        SAY ConsoleID, propsforexamples & "Example #2: LOOKUP jsmith", False
        SAY ConsoleID, "{lgrey}View information about the specified domain name or user account.", False
        SAY ConsoleID, "{lgrey}This command can be used on both domain names and user accounts.", False
        SAY ConsoleID, "{lorange}Data will be returned in the COMM window.", False
                   
    Case "username"
        SAY ConsoleID, props & "Command: USERNAME your-username", False
        SAY ConsoleID, propsforexamples & "Example #1: USERNAME jsmith", False
        SAY ConsoleID, "{lgrey}Set or change your Dark Signs username.", False
        SAY ConsoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled.", False
        SAY ConsoleID, "{lorange}If you do not have an account, visit the website to create one.", False
    Case "password"
        SAY ConsoleID, props & "Command: PASSWORD your-password", False
        SAY ConsoleID, propsforexamples & "Example #1: PASSWORD secret123", False
        SAY ConsoleID, "{lgrey}Set or change your Dark Signs password.", False
        SAY ConsoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled.", False
        SAY ConsoleID, "{lorange}If you do not have an account, visit the website to create one.", False
    
    Case "ping"
        SAY ConsoleID, props & "Command: PING domain-or-ip-server", False
        SAY ConsoleID, propsforexamples & "Example #1: PING birds.com", False
        SAY ConsoleID, "{lgrey}Check if the specified server exist on the network.", False
        SAY ConsoleID, "{lorange}You can modify this command in the file \system\commands\ping.ds", False
    
    Case "me"
        SAY ConsoleID, props & "Command: ME", False
        SAY ConsoleID, propsforexamples & "Example #1: ME", False
        SAY ConsoleID, "{lgrey}Do nothing at all!", False
        SAY ConsoleID, "{lorange}This is a useless secret command.", False
    
    Case "pingport"
        SAY ConsoleID, props & "Command: PINGPORT domain-or-ip-server 80", False
        SAY ConsoleID, propsforexamples & "Example #1: PINGPORT birds.com 80", False
        SAY ConsoleID, "{lgrey}Check if a script is runnning on the server at the specified port number.", False
        SAY ConsoleID, "{lorange}You can modify this command in the file \system\commands\pingport.ds", False
            
    Case "getip"
        SAY ConsoleID, props & "Command: GETIP domain-or-ip-server", False
        SAY ConsoleID, propsforexamples & "Example #1: GETIP birds.com", False
        SAY ConsoleID, "{lgrey}Get the IP address of the specified server.", False
        SAY ConsoleID, "{lorange}You can modify this command in the file \system\commands\getip.ds", False
            
    Case "getdomain"
        SAY ConsoleID, props & "Command: GETDOMAIN domain-or-ip-server", False
        SAY ConsoleID, propsforexamples & "Example #1: GETDOMAIN 12.55.192.111", False
        SAY ConsoleID, "{lgrey}Get the domain name of the specified server.", False
        SAY ConsoleID, "{lorange}You can modify this command in the file \system\commands\getdomain.ds", False
                            
    Case "connect"
        SAY ConsoleID, props & "Command: CONNECT server port-number [optional-parameters]", False
        SAY ConsoleID, propsforexamples & "Example #1: CONNECT home.com 80", False
        SAY ConsoleID, "{lgrey}Connect to a server domain name or IP address on the specified port.", False
        SAY ConsoleID, "{lgrey}If no port number is specified, the default port number is 80.", False
        SAY ConsoleID, "{lorange}You must specify the port number if you are including optional parameters.", False
 
        
            
    Case "move"
        SAY ConsoleID, props & "Command: MOVE source-file destination-file", False
        SAY ConsoleID, propsforexamples & "Example #1: MOVE myoldfile.ds mynewfile.ds", False
        SAY ConsoleID, propsforexamples & "Example #2: MOVE /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        SAY ConsoleID, "{lgrey}Rename the specified file.", False
        SAY ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        SAY ConsoleID, "{lorange}File names should not contain space characters.", False
    Case "rename"
        SAY ConsoleID, props & "Command: RENAME source-file destination-file", False
        SAY ConsoleID, propsforexamples & "Example #1: MD myoldfile.ds mynewfile.ds", False
        SAY ConsoleID, propsforexamples & "Example #2: MD /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        SAY ConsoleID, "{lgrey}Rename the specified file.", False
        SAY ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        SAY ConsoleID, "{lorange}File names should not contain space characters.", False
    Case "copy"
        SAY ConsoleID, props & "Command: COPY source-file destination-file", False
        SAY ConsoleID, propsforexamples & "Example #1: COPY myoldfile.ds mynewfile.ds", False
        SAY ConsoleID, propsforexamples & "Example #2: COPY /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        SAY ConsoleID, "{lgrey}Create a copy of the specified file.", False
        SAY ConsoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        SAY ConsoleID, "{lorange}File names should not contain space characters.", False
    
    Case "saycomm"
        SAY ConsoleID, props & "Command: SAYCOMM text", False
        SAY ConsoleID, propsforexamples & "Example #1: SAYCOMM Connected to server", False
        SAY ConsoleID, "{lgrey}Display the specified text in the COMM window.", False
        
    Case "run"
        SAY ConsoleID, props & "Command: RUN file", False
        SAY ConsoleID, propsforexamples & "Example #1: RUN myscript.ds", False
        SAY ConsoleID, "{lgrey}Run the specified file as script in the console.", False
        SAY ConsoleID, "{lgrey}Files not designed to be run as scripts may cause random errors to be displayed.", False
            
    Case "edit"
        SAY ConsoleID, props & "Command: EDIT file", False
        SAY ConsoleID, propsforexamples & "Example #1: EDIT myscript.ds", False
        SAY ConsoleID, "{lgrey}Edit the specified file in the editing window. The console will pause while the editor is active.", False
        SAY ConsoleID, "{lorange}Files in the editor are saved automatically.", False
                
'    Case "wait"
'        Say consoleID, props & "Command: WAIT milliseconds", False
'        Say consoleID, propsforexamples & "Example #1: WAIT 1000", False
'        Say consoleID, "{lgrey}Pause the console for the specific amount of time (between 1 and 60000 ms).", False
'        Say consoleID, "{lorange}1000 millisends is equal to 1 second.", False
'        Say consoleID, "{orange}This command is only enabled in scripts.", False
                    
    Case "upload"
        SAY ConsoleID, props & "Command: UPLOAD server port-number file", False
        SAY ConsoleID, propsforexamples & "Example #1: UPLOAD mywebsite.com 80 newscript.ds", False
        SAY ConsoleID, "{lgrey}Upload a file to your domain name on the specified port.", False
        SAY ConsoleID, "{lgrey}This script will then become connectable to all players.", False
        SAY ConsoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own.", False
    
    Case "closeport"
        SAY ConsoleID, props & "Command: CLOSEPORT server port-number", False
        SAY ConsoleID, propsforexamples & "Example #1: CLOSEPORT mywebsite.com 80", False
        SAY ConsoleID, "{lgrey}Close port on the specified domain.", False
        SAY ConsoleID, "{lgrey}The script running on this port is deleted.", False
        SAY ConsoleID, "{lorange}You can only close ports on domain names (servers) which you own.", False
                                      
    Case "download"
        SAY ConsoleID, props & "Command: DOWNLOAD server port-number file", False
        SAY ConsoleID, propsforexamples & "Example #1: DOWNLOAD mywebsite.com 80 thescript.ds", False
        SAY ConsoleID, "{lgrey}Download a script file from a sever that you own.", False
        SAY ConsoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own.", False
                             
    Case "transfer"
        SAY ConsoleID, props & "Command: TRANSFER recipient-username amount description", False
        SAY ConsoleID, propsforexamples & "Example #1: TRANSFER admin 5 A payment for you", False
        SAY ConsoleID, "{lgrey}Transfer an amount of money (DS$) to the specified username.", False
        SAY ConsoleID, "{lorange}Each transfer requires manual authorization from the sender.", False
                                    
    Case "ydiv"
        SAY ConsoleID, props & "Command: YDIV height", False
        SAY ConsoleID, propsforexamples & "Example #1: YDIV 240", False
        SAY ConsoleID, "{lgrey}Change the default space between each console line.", False
        SAY ConsoleID, "{lorange}The default YDIV is set to 60.", False
                                           
    Case "display"
        SAY ConsoleID, props & "Command: DISPLAY file optional-start-line optional-max-lines", False
        SAY ConsoleID, propsforexamples & "Example #1: DISPLAY myfile.txt 1 5", False
        SAY ConsoleID, "{lgrey}Output the specified file to the console, without running as a script.", False
        SAY ConsoleID, "{lorange}In the example, the first five lines of myfile.txt will be displayed.", False
                                                   
    Case "append"
        SAY ConsoleID, props & "Command: APPEND file optional-START-or-END text", False
        SAY ConsoleID, propsforexamples & "Example #1: APPEND myfile.txt new data", False
        SAY ConsoleID, propsforexamples & "Example #2: APPEND myfile.txt START new data", False
        SAY ConsoleID, "{lgrey}Append (add) text or data to the specified file.", False
        SAY ConsoleID, "{lgrey}Data will be added to the beginning of the file if the START keyword is used.", False
        SAY ConsoleID, "{lgrey}Data will be added to the end of the file if the END keyword is used.", False
        SAY ConsoleID, "{lorange}If the specified file doesn't exist, it will be created.", False
                                                           
    Case "write"
        SAY ConsoleID, props & "Command: WRITE file text", False
        SAY ConsoleID, propsforexamples & "Example #1: WRITE myfile.txt new data", False
        SAY ConsoleID, "{lgrey}Write text or data to the specified file.", False
        SAY ConsoleID, "{lorange}If the specified file already exists, it will be overwritten.", False
        SAY ConsoleID, "{lorange}Use APPEND to add data to an existing file.", False
        

    Case "register"
        SAY ConsoleID, props & "Command: REGISTER domain-name", False
        SAY ConsoleID, propsforexamples & "Example #1: REGISTER mynewwebsite.com", False
        SAY ConsoleID, "{lgrey}Register a domain name on the Dark Signs Network.", False
        SAY ConsoleID, "{lgrey}This command requires that you have the required amount of money (DS$) in your account.", False
        SAY ConsoleID, "-", False
        SAY ConsoleID, "{center orange nobold 14}- Check the latest prices in the COMM window. -", False
        'say consoleID, "-", False
        RunPage "domain_register.php?returnwith=2000&prices=1", ConsoleID
        
         
    Case "unregister"
        SAY ConsoleID, props & "Command: UNREGISTER domain-name account-password", False
        SAY ConsoleID, propsforexamples & "Example #1: UNREGISTER myoldwebsite.com secret123", False
        SAY ConsoleID, "{lgrey}Unregister a domain name that you own on the Dark Signs Network.", False
        SAY ConsoleID, "{lorange}This command requires that you include your password for security.", False
        
            
    Case "login"
        SAY ConsoleID, props & "Command: LOGIN", False
        SAY ConsoleID, "{lgrey}Attempt to log in to Dark Signs with your account username and password.", False
        SAY ConsoleID, "{lgrey}This is only necessary if your status is 'not logged in'.", False
        SAY ConsoleID, "{lorange}Use the USERNAME and PASSWORD commands to set or change your username or password.", False
        
    Case "logout"
        SAY ConsoleID, props & "Command: LOGOUT", False
        SAY ConsoleID, "{lgrey}Log out of Dark Signs.", False
        SAY ConsoleID, "{lgrey}This can be helpful if you want to log in as another user, or if a rare error occurs.", False
            
    Case "mydomains"
        SAY ConsoleID, props & "Command: MYDOMAINS", False
        SAY ConsoleID, "{lgrey}List the domain names currently registered to you.", False
   
    Case "mysubdomains"
        SAY ConsoleID, props & "Command: MYSUBDOMAINS", False
        SAY ConsoleID, propsforexamples & "Example #1: MYSUBDOMAINS mySite.com", False
        SAY ConsoleID, "{lgrey}List subdomains to a domain that is registed to you.", False
    
    Case "myips"
        SAY ConsoleID, props & "Command: MYIPS", False
        SAY ConsoleID, "{lgrey}List all IP addresses registed to you.", False
     
    Case "music"
        SAY ConsoleID, props & "Command: MUSIC [parameter]", False
        SAY ConsoleID, propsforexamples & "Example #1: MUSIC NEXT", False
        SAY ConsoleID, "{lgrey}Music parameters are START, STOP, NEXT, and PREV.", False
        
    Case "say"
        SAY ConsoleID, props & "Command: SAY text (**optional-properties**)", False
        SAY ConsoleID, propsforexamples & "Example #1: SAY consoleID, hello, this is green (**green**)", False
        SAY ConsoleID, propsforexamples & "Example #2: SAY consoleID, this is bold and very large (**bold, 36**)", False
        SAY ConsoleID, "{lgrey}Display the specified text in the console.", False
        SAY ConsoleID, "{lgrey}Text properties can be modified by adding any number of the following keywords in bewtween (** **), in any order.", False
        SAY ConsoleID, "{lgreen}Colors: Type SHOWCOLORS the display a list of colors.", False
        SAY ConsoleID, "{lgreen}Fonts: Arial, Arial Black, Comic Sans MS, Courier New, Georgia, Impact,", False
        SAY ConsoleID, "{lgreen}Fonts: Lucida Console, Tahoma, Times New Roman, Trebuchet MS, Verdana, Wingdings.", False
        SAY ConsoleID, "{lgreen}Attributes: Bold, NoBold, Italic, NoItalic, Underline, NoUnderline, Strikethru, NoStrikethru.", False
        SAY ConsoleID, "{lgreen}Extras: Flash, Flashfast, FlashSlow.", False
        SAY ConsoleID, "{orange}Note: You cannot use SAY to display multiple lines of text.", False
        SAY ConsoleID, "{orange}For multiple lines, use SAYALL instead.", False
    
    Case "sayall"
        SAY ConsoleID, props & "Command: SAYALL text (**optional-properties**)", False
        SAY ConsoleID, propsforexamples & "Example #1: SAYALL hello", False
        SAY ConsoleID, "{lgrey}Same as the SAY command, except will display multiple lines.", False
        SAY ConsoleID, "{lorange}Type HELP SAY for more information.", False
             
    Case "sayline"
        SAY ConsoleID, props & "Command: SAYLINE text (**optional-properties**)", False
        SAY ConsoleID, propsforexamples & "Example #1: SAYLINE hello", False
        SAY ConsoleID, "{lgrey}Same as the SAY command, except text will be printed on the same line, without moving down.", False
        SAY ConsoleID, "{lorange}Type HELP SAY for more information.", False
           
    Case "remotedelete"
        SAY ConsoleID, props & "Command: REMOTEDELETE domain filename", False
        SAY ConsoleID, propsforexamples & "Example #1: REMOTEDELETE matrix.com myfile.ds", False
        SAY ConsoleID, "{lgrey}Delete the specified file from the remote server.", False
        SAY ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
    
    Case "remoteupload"
        SAY ConsoleID, props & "Command: REMOTEUPLOAD domain filename", False
        SAY ConsoleID, propsforexamples & "Example #1: REMOTEUPLOAD matrix.com localfile.ds", False
        SAY ConsoleID, "{lgrey}Upload a file from your local file system to your domain name file system.", False
        SAY ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
           
    Case "remotedir"
        SAY ConsoleID, props & "Command: REMOTEDIR domain", False
        SAY ConsoleID, propsforexamples & "Example #1: REMOTEDIR matrix.com", False
        SAY ConsoleID, "{lgrey}View files on the remote server.", False
        SAY ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
               
    Case "remoteview"
        SAY ConsoleID, props & "Command: REMOTEVIEW domain filename", False
        SAY ConsoleID, propsforexamples & "Example #1: REMOTEVIEW google.com userlist.log", False
        SAY ConsoleID, "{lgrey}Display the specified remote file in the console.", False
        SAY ConsoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
    
    Case "draw"
        SAY ConsoleID, props & "Command: DRAW -y Red(0-255) Green(0-255) Blue(0-255) mode", False
        SAY ConsoleID, propsforexamples & "Example #1: DRAW -1 142 200 11 fadeout", False
        SAY ConsoleID, "{lgrey}Print a background color stream to the console.", False
        SAY ConsoleID, "{lgrey}The first parameter, -y, defines the console line.", False
        SAY ConsoleID, "{lgrey}For example, -2 will draw to the second line up from the active line.", False
        SAY ConsoleID, "{lgrey}The Red, Green, and Blue must be values between 0 and 255.", False
        SAY ConsoleID, "{lorange}Available mode keywords: SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE.", False
        SAY ConsoleID, "{orange}To use custom colors, use the DRAWCUSTOM command.", False
    
        
    
    Case "subowners"
        SAY ConsoleID, props & "Command: SUBOWNERS domain-name KEYWORD [optional-username]", False
        SAY ConsoleID, propsforexamples & "Example #1: SUBOWNERS site.com LIST", False
        SAY ConsoleID, propsforexamples & "Example #2: SUBOWNERS site.com ADD friendusername", False
        SAY ConsoleID, propsforexamples & "Example #3: SUBOWNERS site.com REMOVE friendusername", False
        SAY ConsoleID, "{lgrey}Add or remove other user privileges regarding your specified domain name.", False
        SAY ConsoleID, "{lgrey}You can add users to this list as subowners of your domain name.", False
        SAY ConsoleID, "{lorange}Subowners have permission to interact, upload, and download files from the domain.", False
        SAY ConsoleID, "{lorange}Subowners have no ability to unregister or modify the domain name  privileges.", False
        
        
        
    Case "lineup"
        SAY ConsoleID, props & "Command: LINEUP", False
        SAY ConsoleID, "{lgrey}Move up an extra console line. Useful for some scripts.", False
        
     'Case "chatsend"
     '   Say consoleID, props & "Command: CHATSEND Message to be sent to the chat.", False
     '   Say consoleID, propsforexamples & "Example #1: CHATSEND Hello World!", False
     '   Say consoleID, "{lgrey}A simple way to send messages to the chat from your console.", False
       
    
    Case "chatview"
        SAY ConsoleID, props & "Command: CHATVIEW [parameter]", False
        SAY ConsoleID, "{lgrey}If set to on, will display chat in the status window.", False
        SAY ConsoleID, "{lgrey}CHATVIEW parameters are ON and OFF", False

    
    Case Else
        SAY ConsoleID, props & "Available Commands", False
        'DrawItUp "0 0 0 0 solid", consoleID
        SAY ConsoleID, "{lgrey 8}APPEND, CD, CLEAR, CLOSEPORT, CONNECT, COPY, DATE, DEL, DIR, DISPLAY, DOWNLOAD, DRAW, EDIT", False
        SAY ConsoleID, "{lgrey 8}GETIP, GETDOMAIN, LINEUP, LISTCOLORS, LISTKEYS, LOGIN, LOGOUT, LOOKUP, MD, MOVE, MUSIC", False
        SAY ConsoleID, "{lgrey 8}MYDOMAINS, MYIPS, MYSUBDOMAINS, NOW, PASSWORD, PAUSE, PING, PINGPORT, RD, RENAME, REGISTER", False
        SAY ConsoleID, "{lgrey 8}REMOTEDELETE, REMOTEDIR, REMOTEUPLOAD, REMOTEVIEW, RESTART, RUN, SAY, SAYALL, SAYCOMM, STATS", False
        SAY ConsoleID, "{lgrey 8}SUBOWNERS, TIME, TRANSFER, UNREGISTER, UPLOAD, USERNAME, WRITE, YDIV", False
        SAY ConsoleID, "{grey}For more specific help on a command, type: HELP [command]", False
    End Select
End Sub

