Attribute VB_Name = "basCommands"
Option Explicit

Public AuthorizePayment As Boolean

Public Function Run_Command(CLine As ConsoleLine, ByVal consoleID As Integer, Optional ScriptFrom As String, Optional fromScript As Boolean = True, Optional IsFromScript As Boolean)
    'does it need to be piped? BLAH THIS ALLOWS FOR EXPLOITS!!!!
    'If InStr(MaskCharInQuotes(CLine.Caption, "|"), "|") > 0 Then Pipe_Commands CLine.Caption, consoleID: Exit Function
    

    Dim tmpS As String, n As Integer, tmpS2 As String
    
    Dim sC As String 'the main command
    Dim sP As String 'any parameters
    
    tmpS = CLine.Caption
    'kill double spaces - MUST BE BEFORE REPLACES VARIABLES
    'tmpS = Replace(tmpS, "  ", " ")
    
    'tmpS2 = tmpS
    
    If InStr(tmpS, ">") > 0 And InStr(tmpS, "<") = 0 Then
    If InStr(i(tmpS), i(cPath(consoleID))) > 0 Then
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
        sP = ReplaceVariables(sP, consoleID)
        
        
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
            SayError "Command blocked by commands-security.dat: " & UCase(sC) & " " & sP, consoleID
            GoTo zzz
        End If
    End If
    End If
    
    Select Case i(sC)
    
        Case "draw": DrawItUp sP, consoleID ': Exit Function
    
        Case "dir": ListDirectoryContents consoleID, sP
        Case "ls": ListDirectoryContents consoleID, sP
        Case "cd": ChangeDir sP, consoleID
        Case "cd..": DownADir consoleID
        Case "md": MakeDir sP, consoleID
        Case "rd": RemoveDir sP, consoleID
        Case "del": DeleteFiles sP, consoleID
        Case "delete": DeleteFiles sP, consoleID
        Case "move": MoveRename sP, consoleID
        Case "rename": MoveRename sP, consoleID
        Case "copy": MoveRename sP, consoleID, "copyonly"
        
        Case "run": RunFileAsScript sP, consoleID
        Case "edit": EditFile sP, consoleID
        Case "mail": ShowMail sP, consoleID
        
        Case "display": DisplayFile sP, consoleID
        Case "cat": DisplayFile sP, consoleID
        Case "lineup": Shift_Console_Lines_Reverse consoleID
        Case "append": AppendAFile sP, consoleID
        Case "write": WriteAFile sP, consoleID, ScriptFrom
        
        Case "clear": ClearConsole consoleID
        Case "cls": ClearConsole consoleID
        Case "time": Say consoleID, Format(Time, "h:mm AMPM"), False
        Case "date": Say consoleID, Date, False
        Case "now": Say consoleID, Now, False
        Case "restart": frmConsole.Start_Console consoleID: Exit Function
        Case "say": Say consoleID, sP, False, fromScript
        Case "sayall": SayAll consoleID, sP, False, fromScript
        Case "sayline":
            'Shift_Console_Lines_Reverse (consoleID)
            
            Say consoleID, sP, False, fromScript
            If fromScript = True Then Exit Function
            
        Case "listcolors": ListColors consoleID
        Case "listkeys": ListKeys consoleID
        Case "music": MusicCommand sP
        Case "help": ShowHelp sP, consoleID
        Case "pause": PauseConsole sP, consoleID: Exit Function
        Case "saycomm": SayComm sP, consoleID
        Case "username": SetUsername sP, consoleID
        Case "password": SetPassword sP, consoleID
        Case "stats": ShowStats consoleID
        Case "login": LoginNow consoleID
        Case "logout": LogoutNow consoleID
        Case "wait": 'WaitNow sP, consoleID
        
        Case "connect": ConnectToDomain sP, consoleID
        Case "upload": UploadToDomain sP, consoleID
        Case "closeport": CloseDomainPort sP, consoleID 'Used to close server ports.
        Case "download": DownloadFromDomain sP, consoleID
        Case "register": RegisterDomain sP, consoleID
        Case "subowners": SubOwners sP, consoleID
        Case "unregister": UnRegisterDomain sP, consoleID
        Case "transfer": TransferMoney sP, consoleID
        Case "lookup": Lookup sP, consoleID
        Case "mydomains": ListMyDomains consoleID
        Case "mysubdomains": ListMySubDomains sP, consoleID
        Case "myips": ListMyIPs consoleID
        
        Case "server": If IsFromScript = True Then ServerCommands sP, consoleID
        
        'Case "chatsend": frmConsole.ChatSend sP, consoleID
        Case "chatview": frmConsole.ChatView sP, consoleID
        
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
        Case "compile": f_Compile sP, consoleID
        
        
        Case "hello": Say consoleID, "I am your console, not your friend! {green 24 georgia}", False
        Case "hi": Say consoleID, "Hello to you as well! {green 24 georgia}", False
        Case "why": Say consoleID, "That is a question that I cannot answer. {blue 24 georgia}", False
        Case "wow": Say consoleID, "Yeah...{blue 18 georgia}", False: Say consoleID, "it's pretty good...{blue 18 georgia center}", False: Say consoleID, ":){blue 18 georgia right}", False:: Say consoleID, "w00t!{center blue 24 bold georgia}", False
        Case "fuck": Say consoleID, "I object to that sort of thing. {grey 24 georgia}", False
        Case "lol": Say consoleID, UCase("j") & "{wingdings 144 center green}", False
        Case "ok":  Say consoleID, "That's not a real command!{red impact 48 center nobold}", False
                    Say consoleID, "What's wrong with you!?{red impact 48 center nobold}", False
        

        
        Case Else:
        

            'other alternatives!
            If Mid(sC, 1, 1) = "$" And Len(sC) > 1 Then
                'it's a variable being set
                
                SetVariable sC, sP, consoleID
                
                If IsFromScript = True Then
                    If InStr(sP, "(") = 0 Then
                        'only exit function if it doesn't have a function.
                        Exit Function
                    End If
                End If
            ElseIf FileExists(App.Path & "\user" & fixPath(sC, consoleID)) = True Then
            
                'it's a file - run it
                If Right(fixPath(sC, consoleID), 4) = ".dsc" Then
                    'its compiled, decompile before running.
                    Dim bf As clsBlowfish
                    Set bf = New clsBlowfish
                    Dim tempStrA As String
                    Dim tempStrB As String
                    
                    tempStrA = GetFile(App.Path & "\user" & fixPath(sC, consoleID))
                    bf.sInitBF "3f29c928jwf44fgv"
                    tempStrA = StrConv(DecodeBase64(tempStrA), vbUnicode)
                    bf.sStringDecrypt tempStrA, tempStrB
                                    
                    WriteFile App.Path & "\user\system\tempDec.dat", tempStrB
                    Shift_Console_Lines consoleID
                    Run_Script "\system\tempDec.dat", consoleID, sP, "COMPILED"
                    DeleteAFile App.Path & "\user\system\tempDec.dat"
                Else
                    Shift_Console_Lines consoleID
                    Run_Script fixPath(sC, consoleID), consoleID, sP, referals(ActiveConsole)
                End If
            ElseIf FileExists(App.Path & "\user\system\commands\" & sC) = True Then
                'it's a file - run it
                Shift_Console_Lines consoleID
                Run_Script "\system\commands\" & sC, consoleID, sP, referals(ActiveConsole)
            ElseIf FileExists(App.Path & "\user\system\commands\" & sC & ".ds") = True Then
                'it's a file - run it
                Shift_Console_Lines consoleID
                Run_Script "\system\commands\" & sC & ".ds", consoleID, sP, referals(ActiveConsole)
            ElseIf IsInCommandsSubdirectory(sC) <> "" Then
                Run_Script IsInCommandsSubdirectory(sC), consoleID, sP, referals(ActiveConsole)
            Else
                'it is unknown
                If Trim(sC) = "" Then
                Else
                    If Len(Trim(Replace(Replace(sC, vbCr, ""), vbLf, ""))) > 1 Then
                        
                        SayError "Unrecognized Command: " & sC, consoleID
                        
                    End If
                End If
            End If
    
    
            
    End Select
    
zzz:
    WriteErrorLog "Run_Command - " & sC & " - " & sP
    New_Console_Line consoleID
End Function

Public Sub DrawItUp(ByVal s As String, ByVal consoleID As Integer)
    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", consoleID
        ShowHelp "draw", consoleID
        Exit Sub
    End If
    
    Dim yPos As Long
    Dim R As Long, G As Long, b As Long
    Dim sColor As String
    Dim sMode As String
    
    yPos = Trim(Mid(s, 1, InStr(s, " ")))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", consoleID
        ShowHelp "draw", consoleID
        Exit Sub
    End If
    
    R = Val(Trim(Mid(s, 1, InStr(s, " "))))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters - Type HELP DRAW for more information.", consoleID
        Exit Sub
    End If
    
    G = Val(Trim(Mid(s, 1, InStr(s, " "))))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters", consoleID
        ShowHelp "draw", consoleID
        Exit Sub
    End If
    
    b = Val(Trim(Mid(s, 1, InStr(s, " "))))
    sMode = Trim(Mid(s, InStr(s, " "), Len(s)))
     
    Dim yIndex As Integer, n As Integer
    yIndex = Val(Replace(yPos, "-", "")) + 1
    
    
    Console(consoleID, yIndex).DrawMode = i(sMode)
    
    Select Case i(sMode)
    
    Case "fadecenter":
    
        Console(consoleID, yIndex).DrawEnabled = True
        Console(consoleID, yIndex).DrawR = R
        Console(consoleID, yIndex).DrawG = G
        Console(consoleID, yIndex).DrawB = b
        
        For n = ((DrawDividerWidth / 2) + 1) To DrawDividerWidth
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
        R = Console(consoleID, yIndex).DrawR
        G = Console(consoleID, yIndex).DrawG
        b = Console(consoleID, yIndex).DrawB
        
        For n = (DrawDividerWidth / 2) To 1 Step -1
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
    Case "fadeinverse":
    
        Console(consoleID, yIndex).DrawEnabled = True
        Console(consoleID, yIndex).DrawR = R
        Console(consoleID, yIndex).DrawG = G
        Console(consoleID, yIndex).DrawB = b
        
        For n = DrawDividerWidth To ((DrawDividerWidth / 2) + 1) Step -1
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
        R = Console(consoleID, yIndex).DrawR
        G = Console(consoleID, yIndex).DrawG
        b = Console(consoleID, yIndex).DrawB
        
        For n = 1 To (DrawDividerWidth / 2)
            R = R - (DrawDividerWidth / 2)
            G = G - (DrawDividerWidth / 2)
            b = b - (DrawDividerWidth / 2)
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
    
    
    Case "fadein":
    
        Console(consoleID, yIndex).DrawEnabled = True
        Console(consoleID, yIndex).DrawR = R
        Console(consoleID, yIndex).DrawG = G
        Console(consoleID, yIndex).DrawB = b
        
        For n = 1 To DrawDividerWidth
            R = R - 4
            G = G - 4
            b = b - 4
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n


    Case "fadeout":
    
    
        Console(consoleID, yIndex).DrawEnabled = True
        Console(consoleID, yIndex).DrawR = R
        Console(consoleID, yIndex).DrawG = G
        Console(consoleID, yIndex).DrawB = b
        
        For n = DrawDividerWidth To 1 Step -1
            R = R - 4
            G = G - 4
            b = b - 4
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
        
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n


    Case "flow":
    
    
        Console(consoleID, yIndex).DrawEnabled = True
        Console(consoleID, yIndex).DrawR = R
        Console(consoleID, yIndex).DrawG = G
        Console(consoleID, yIndex).DrawB = b
        
        For n = 1 To ((DrawDividerWidth / 4) * 1)
            R = R - 5
            G = G - 5
            b = b - 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
                
        For n = (((DrawDividerWidth / 4) * 1) + 1) To (((DrawDividerWidth / 4) * 2))
            R = R + 5
            G = G + 5
            b = b + 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
                
                
        For n = (((DrawDividerWidth / 4) * 2) + 1) To (((DrawDividerWidth / 4) * 3))
            R = R - 5
            G = G - 5
            b = b - 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
                        
                
        For n = (((DrawDividerWidth / 4) * 3) + 1) To (((DrawDividerWidth / 4) * 4))
            R = R + 5
            G = G + 5
            b = b + 5
            If R < 1 Then R = 0
            If G < 1 Then G = 0
            If b < 1 Then b = 0
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
        
        
        

    
    Case "solid":
        Console(consoleID, yIndex).DrawEnabled = True
        Console(consoleID, yIndex).DrawR = R
        Console(consoleID, yIndex).DrawG = G
        Console(consoleID, yIndex).DrawB = b
        
        
        For n = 1 To DrawDividerWidth
            Console(consoleID, yIndex).DrawColors(n) = RGB(R, G, b)
        Next n
    End Select
    
End Sub


Public Sub ListMyDomains(ByVal consoleID As Integer)
    SayComm "Downloading domain list..."
    RunPage "my_domains.php?type=domain", consoleID, False, "", 0
End Sub

Public Sub ListMySubDomains(ByVal domain As String, ByVal consoleID As Integer)
    SayComm "Downloading subdomain list..."
    RunPage "my_domains.php?domain=" & domain & "&type=subdomain", consoleID, False, "", 0
End Sub

Public Sub ListMyIPs(ByVal consoleID As Integer)
    SayComm "Downloading IP list..."
    RunPage "my_domains.php?type=ip", consoleID, False, "", 0
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
        sPath = Replace(frmConsole.Dir1.List(n), App.Path & "\user" & cPrefix(5), "")
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

Public Sub ConnectToDomain(ByVal s As String, ByVal consoleID As Integer)
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
    
    ' User Error..
    'If Left(sDomain, 4) = "www." Then sDomain = Mid(sDomain, 5, Len(sDomain))
    'sDomain = Replace(sDomain, "http://", "")
    
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
        SayError "Invalid Port Number: " & sPort, consoleID
        Exit Sub
    End If
    If Val(sPort) > 65536 Then
        SayError "Invalid Port Number: " & sPort, consoleID
        Exit Sub
    End If
    
    
    SayComm "Connecting to " & UCase(sDomain) & ":" & sPort & "..."
    Say consoleID, "{green}Connecting to " & UCase(sDomain) & ":" & sPort & "...", False
    
    RunPage "domain_connect.php?params=" & sParams & _
    "&d=" & sDomain & _
    "&port=" & sPort, consoleID
    


    
    Exit Sub
zxc:
    SayError "Invalid Parameters", consoleID
    ShowHelp "connect", consoleID
    
End Sub

Public Sub UploadToDomain(ByVal s As String, ByVal consoleID As Integer)
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
    sFilename = fixPath(sFilename, consoleID)
    

    
    If FileExists(App.Path & "\user" & cPrefix(consoleID) & sFilename) = True Then
            Dim bf As clsBlowfish
            Set bf = New clsBlowfish
            'MsgBox StrConv(DecodeBase64(strData), vbUnicode)
            Dim tempStrA As String
            Dim tempStrB As String
    
            sFileData = GetFileClean(App.Path & "\user" & cPrefix(consoleID) & sFilename)
            
            
            'tempStrA = GetFile(App.Path & "\user\" & s)
            bf.sInitBF "z123" & sDomain & "_" & sPort & "456"
            bf.sStringEncrypt sFileData, tempStrB
            WriteFile App.Path & "\user\system\tempUpEnc.dat", tempStrB
            tempStrA = EncodeBase64(StrConv(tempStrB, vbFromUnicode))
            WriteFile App.Path & "\user\system\tempUp64.dat", tempStrA
        
        
        
        'upload the freaking file!!
        'tempStrA = Replace(tempStrA, "=", "--equals--")
        RunPage "domain_upload.php", consoleID, True, _
        "port=" & Trim(sPort) & _
        "&d=" & sDomain & _
        "&filedata=" & tempStrA
        
        SayComm "Attempting to upload: " & UCase(sDomain) & ":" & i(sPort), consoleID
        
    Else
        SayError "File Not Found:" & sFilename, consoleID
        Exit Sub
    End If
    

    
    Exit Sub
zxc:
    SayError "Invalid Parameters", consoleID
    ShowHelp "upload", consoleID
    
End Sub

Public Sub CloseDomainPort(ByVal s As String, ByVal consoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(s, 1, InStr(s, " ")))
    If Left(sDomain, 4) = "www." Then sDomain = Mid(sDomain, 5, Len(sDomain))
    sDomain = Replace(sDomain, "http://", "")
    
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    sPort = s
  
    RunPage "domain_close.php", consoleID, True, _
    "port=" & Trim(sPort) & _
    "&d=" & sDomain
        
    SayComm "Attempting to close port : " & UCase(sDomain) & ":" & i(sPort), consoleID
        
    Exit Sub
zxc:
    SayError "Invalid Parameters", consoleID
    ShowHelp "closeport", consoleID
    
End Sub


Public Sub DownloadFromDomain(ByVal s As String, ByVal consoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    Dim sFilename As String
    Dim sFileData As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(s, 1, InStr(s, " ")))
    If Left(sDomain, 4) = "www." Then sDomain = Mid(sDomain, 5, Len(sDomain))
    sDomain = Replace(sDomain, "http://", "")
    
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    If InStr(s, " ") = 0 Then GoTo zxc
    
    sPort = i(Mid(s, 1, InStr(s, " ")))
    sFilename = Trim(Mid(s, InStr(s, " "), Len(s)))
    sFilename = fixPath(sFilename, consoleID)
    


        RunPage "domain_download.php", consoleID, True, _
        "returnwith=4400" & _
        "&port=" & Trim(sPort) & _
        "&d=" & sDomain & _
        "&filename=" & sFilename
        
        SayComm "Attempting to download: " & UCase(sDomain) & ":" & i(sPort), consoleID
        
    

    
    Exit Sub
zxc:
    SayError "Invalid Parameters", consoleID
    ShowHelp "download", consoleID
    
End Sub


Public Sub SubOwners(ByVal s As String, ByVal consoleID As Integer)
    s = i(s)
    s = Replace(s, "http://", ""): s = Replace(s, "www.", "")
    
    s = Trim(s)
    
    Dim sDomain As String, sUsername As String
    
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters.", consoleID
        ShowHelp "subowners", consoleID
        Exit Sub
    End If
    
    sDomain = Trim(Mid(s, 1, InStr(s, " ")))
    s = Trim(Mid(s, InStr(s, " ") + 1, Len(s)))
    
    If i(Mid(s, 1, 4)) = "list" Then
        'list the domain names
           
            RunPage "index.php", consoleID, True, _
            "returnwith=2001&listprivileges=" & Trim(sDomain)

    ElseIf Mid(i(s), 1, 4) = "add " Then
        sUsername = Trim(Mid(s, 5, Len(s)))
            
            RunPage "index.php", consoleID, True, _
            "returnwith=2001&addprivileges=" & Trim(sDomain) & "&username=" & sUsername

    ElseIf Mid(i(s), 1, 7) = "remove " Then
        sUsername = Trim(Mid(s, 8, Len(s)))
        
             RunPage "index.php", consoleID, True, _
            "returnwith=2001&removeprivileges=" & Trim(sDomain) & "&username=" & sUsername

    Else
        SayError "Invalid Parameters.", consoleID
        ShowHelp "subowners", consoleID
        Exit Sub
    End If
    
    

    
End Sub

Public Sub RegisterDomain(ByVal s As String, ByVal consoleID As Integer)
    s = i(s)
    s = Trim(s)
    
    If s = "" Then
        SayError "The REGISTER command requires a parameter.", consoleID
        ShowHelp "register", consoleID
        Exit Sub
    End If
    
    If CountCharInString(s, ".") < 1 Or CountCharInString(s, ".") > 3 Or HasBadDomainChar(s) = True Or Len(s) < 5 Or Left(s, 1) = "." Or Right(s, 1) = "." Then
        SayError "The domain name you specified is invalid or contains bad characters.{orange}", consoleID
        Say consoleID, "A domain name should be in the following form: MYDOMAIN.COM{lorange}", False
        Say consoleID, "Subdomains should be in the form: BLOG.MYDOMAIN.COM{lorange}", False
        Say consoleID, "Valid domain name characters are:", False
        Say consoleID, "A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -{grey 8}", False
        Exit Sub
    End If
    
    Say consoleID, "{green 10}A registration request has been sent for " & s & ".", False
    Say consoleID, "{lgreen 10}The result will be posted to the COMM.", False
    
    
    'RunPage "domain_register.php?returnwith=2000&d=" & Trim(s), consoleID
    RunPage "domain_register.php", consoleID, True, "d=" & s
    
End Sub

Public Sub UnRegisterDomain(ByVal s As String, ByVal consoleID As Integer)
    s = i(s)
    s = Replace(s, "http://", ""): s = Replace(s, "www.", "")
    
    s = Trim(s)
    If s = "" Then
        SayError "The UNREGISTER command requires parameters.", consoleID
        ShowHelp "unregister", consoleID
        Exit Sub
    End If
    

    Dim sDomain As String
    Dim sPass As String
    
    If InStr(s, " ") > 0 Then
        sDomain = Trim(Mid(s, 1, InStr(s, " ")))
        sPass = Trim(Mid(s, InStr(s, " "), Len(s)))
    Else
        SayError "Your password is required as a final parameter.", consoleID
        ShowHelp "unregister", consoleID
        Exit Sub
    End If
    
    Say consoleID, "{green 10}A unregistration request has been sent for " & sDomain & ".", False
    Say consoleID, "{lgreen 10}The result will be posted to the COMM.", False
    
    
    
    'MsgBox sDomain & vbCrLf & sPass
    
    
    RunPage "domain_register.php", consoleID, True, _
    "returnwith=2000&unregisterdomain=" & Trim(sDomain) & "&pw=" & sPass
    
End Sub

Public Sub ServerCommands(ByVal s As String, ByVal consoleID As Integer)
    Dim sCommand As String
    Dim sDomain As String
    Dim sKey As String
    

    'check for a keycode, if it doesn't have one, its from a local script (so exit)
    

    If InStr(s, ":----:") = 0 Then Exit Sub
    
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
    
    
    
    'encode, then reverse
    'sKey = Encode(sKey, encodeKey)
    'sKey = ReverseString(sKey)
    'replace ands
    'sKey = Replace(sKey, "&", "--and--")
    sKey = DSOEncode(sKey)


    Select Case i(sC)
    
    Case "append"
        
        ServerCommand_Append sP, sKey, sDomain, consoleID
        
    Case "write"
    
        ServerCommand_Write sP, sKey, sDomain, consoleID
        
    
    End Select
    
    
    


    
End Sub

Public Sub ServerCommand_Append(s As String, sKey As String, sDomain As String, ByVal consoleID As Integer)

    Dim sPostData As String
    Dim sFilename As String
    Dim sFileData As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then Exit Sub
    sFilename = Trim(Mid(s, 1, InStr(s, " ")))
    sFileData = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    sPostData = "append=" & sFilename & _
        "&keycode=" & sKey & _
        "&d=" & sDomain & _
        "&filedata=" & sFileData
    
    RunPage "domain_filesystem.php", consoleID, True, sPostData, 0

End Sub


Public Sub ServerCommand_Write(s As String, sKey As String, sDomain As String, ByVal consoleID As Integer)

    Dim sPostData As String
    Dim sFilename As String
    Dim sFileData As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then Exit Sub
    sFilename = Trim(Mid(s, 1, InStr(s, " ")))
    sFileData = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    sPostData = "write=" & sFilename & _
        "&keycode=" & sKey & _
        "&d=" & sDomain & _
        "&filedata=" & sFileData
        
    RunPage "domain_filesystem.php", consoleID, True, sPostData, 0

End Sub


Public Sub TransferMoney(ByVal s As String, ByVal consoleID As Integer)
    Dim sTo As String
    Dim sAmount As String
    Dim sDescription As String
    
    s = Replace(s, "http://", ""): s = Replace(s, "www.", "")
    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters.", consoleID
        ShowHelp "transfer", consoleID
        Exit Sub
    End If
    
    sTo = Trim(Mid(s, 1, InStr(s, " ")))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters.", consoleID
        ShowHelp "transfer", consoleID
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
                SayError "Invalid Amount: $" & Trim(sAmount) & ".", consoleID
                Exit Sub
            End If

    
        SayComm "Processing Payment...", consoleID
    
        RunPage "transfer.php", consoleID, True, _
        "returnwith=2000" & _
        "&to=" & Trim(sTo) & _
        "&amount=" & Trim(sAmount) & _
        "&description=" & Trim(sDescription)
    
    End If
    
    

    
    
End Sub

Public Sub Lookup(ByVal s As String, ByVal consoleID As Integer)
    s = i(s)
    s = Trim(s)
    If s = "" Then
        SayError "The LOOKUP command requires a parameter.", consoleID
        ShowHelp "lookup", consoleID
        Exit Sub
    End If
    
    
    RunPage "lookup.php?returnwith=2000&d=" & Trim(s), consoleID
    
End Sub

Public Sub f_Compile(ByVal s As String, ByVal consoleID As Integer)
    s = i(s)
    s = Trim(s)
    s = fixPath(s, consoleID)
   
    If FileExists(App.Path & "\user\" & s) = False Then
        SayError "File Not Found: " & s, consoleID
        Exit Sub
    End If
   
    If Right(s, 3) <> ".ds" Then
        SayError "Files must have a .ds extention to be compiled.", consoleID
        Exit Sub
    End If
    
    Dim bf As clsBlowfish
    Set bf = New clsBlowfish
    'MsgBox StrConv(DecodeBase64(strData), vbUnicode)
    Dim tempStrA As String
    Dim tempStrB As String
    
    tempStrA = GetFile(App.Path & "\user\" & s)
    bf.sInitBF "3f29c928jwf44fgv"
    bf.sStringEncrypt tempStrA, tempStrB
    tempStrA = EncodeBase64(StrConv(tempStrB, vbFromUnicode))

    WriteFile App.Path & "\user\" & s & "c", tempStrA
    'Encrypt the file and store it it in <file>.dsc
    'bf.sFileEncrypt App.Path & "\user\" & s, App.Path & "\user\" & s & "c"
    
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

Public Sub ShowStats(ByVal consoleID As Integer)
    
    SayComm "Downloading stats..."
    RunPage "get_user_stats.php?returnwith=2000", consoleID

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


Public Sub ListKeys(ByVal consoleID As Integer)
    
    Dim ss As String
    ss = "{gold}"
    
    Say consoleID, "Dark Signs Keyboard Actions{gold 14}", False
    
    Say consoleID, "Page Up: Scroll the console up." & ss, False
    Say consoleID, "Page Down: Scroll the console down." & ss, False
    
    Say consoleID, "Shift + Page Up: Decrease size of the COMM." & ss, False
    Say consoleID, "Shift + Page Down: Incease size of the COMM." & ss, False
    
    Say consoleID, "F11: Toggle maximum console display." & ss, False
    
    
    
End Sub


Public Sub SetUsername(ByVal s As String, ByVal consoleID As Integer)

    
    If Authorized = True Then
        SayError "You are already logged in.", consoleID
        Exit Sub
    End If
    
    
    If Trim(s) <> "" Then RegSave "myusernamedev", Trim(s)
    
        
    Dim tmpU As String, tmpP As String
    If Trim(myUsername) = "" Then tmpU = "[not specified]" Else tmpU = myUsername
    
    Say consoleID, "Your new details are shown below." & "{orange}", False
    Say consoleID, "Username: " & tmpU & "{orange 16}", False
    Say consoleID, "Password: " & "[hidden]" & "{orange 16}", False
    

End Sub

Public Sub SetPassword(ByVal s As String, ByVal consoleID As Integer)


    If Authorized = True Then
        SayError "You are already logged in.", consoleID
        Exit Sub
    End If
    
    s = Trim(s)
    RegSave "mypassworddev", s
    
    Dim tmpU As String, tmpP As String
    If Trim(myUsername) = "" Then tmpU = "[not specified]" Else tmpU = myUsername
    
    Say consoleID, "Your new details are shown below." & "{orange}", False
    Say consoleID, "Username: " & tmpU & "{orange 16}", False
    Say consoleID, "Password: " & "[hidden]" & "{orange 16}", False


End Sub

Public Sub ClearConsole(ByVal consoleID As Integer)
    
    Console(consoleID, 1).Caption = "-"
    
    
    Dim n As Integer
    
    For n = 1 To 29
    
        Shift_Console_Lines consoleID
        Console(consoleID, 2).Caption = "-"
        Console(consoleID, 2).FontSize = 48
    
    Next n
    
    
End Sub


Public Sub DownADir(ByVal consoleID As Integer)
    On Error GoTo zxc
    
    If Len(cPath(consoleID)) < 2 Then Exit Sub
    
    Dim s As String
    s = Mid(cPath(consoleID), 1, Len(cPath(consoleID)) - 1)
    s = ReverseString(s)
    s = Mid(s, InStr(s, "\"), Len(s))
    s = ReverseString(s)
    
    
    cPath(consoleID) = s
zxc:
End Sub

Public Sub MakeDir(ByVal s As String, ByVal consoleID As Integer)
    
    If InvalidChars(s) = True Then
        SayError "Invalid Directory Name: " & s, consoleID
        Exit Sub
    End If
    
    If Trim(s) = ".." Then DownADir consoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If

    s = fixPath(s, consoleID)
    
    If DirExists(App.Path & "\user" & cPrefix(consoleID) & s) = True Then
        'don't create it if it already exists
        GoTo errorDir
    Else
        MakeADir App.Path & "\user" & cPrefix(consoleID) & s
    End If
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub


Public Sub MoveRename(ByVal s As String, ByVal consoleID As Integer, Optional sTag As String)

    Dim s1 As String, s2 As String
    s = Trim(s)
    s = Replace(s, "/", "\")
    If InStr(s, " ") = 0 Then Exit Sub
    
    s1 = Trim(Mid(s, 1, InStr(s, " ")))
    s2 = Trim(Mid(s, InStr(s, " "), Len(s)))

    s1 = fixPath(s1, consoleID)
    s2 = fixPath(s2, consoleID)
    
    If InStr(i(s1), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Sub
    End If
    
    If FileExists(App.Path & "\user" & cPrefix(consoleID) & s1) = False Then
        SayError "File Not Found: " & s1, consoleID
        Exit Sub
    End If
    
    'now move it or copy it
    If i(sTag) = "copyonly" Then
        If CopyAFile(App.Path & "\user" & cPrefix(consoleID) & s1, App.Path & "\user" & cPrefix(consoleID) & s2, consoleID) = False Then
            SayError "Invalid Destination File: " & s2, consoleID
            Exit Sub
        End If
    Else
        If MoveAFile(App.Path & "\user" & cPrefix(consoleID) & s1, App.Path & "\user" & cPrefix(consoleID) & s2, consoleID) = False Then
            SayError "Invalid Destination File: " & s2, consoleID
            Exit Sub
        End If
    End If
    
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Function MoveAFile(Source As String, dest As String, consoleID As Integer) As Boolean
    On Error GoTo zxc

    
    If InStr(i(dest), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Function
    End If
    
    
    FileCopy Source, dest
    Kill Source

    MoveAFile = True
    Exit Function
zxc:
    MoveAFile = False
End Function

Public Function CopyAFile(Source As String, dest As String, consoleID As Integer) As Boolean
    On Error GoTo zxc
    
    If InStr(i(dest), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Function
    End If
    
    FileCopy Source, dest
    'Kill Source 'don't kill it, this is for copy

    CopyAFile = True
    Exit Function
zxc:
    CopyAFile = False
End Function

Public Sub DeleteFiles(ByVal s As String, ByVal consoleID As Integer)
    
    If Trim(s) = ".." Then DownADir consoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If

    s = fixPath(s, consoleID)
    
    If InStr(i(s), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Sub
    End If
    
    
    DelFiles App.Path & "\user" & cPrefix(consoleID) & s, consoleID
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub EditFile(ByVal s As String, ByVal consoleID As Integer)
    
    s = Trim(fixPath(s, consoleID))
    
    If Len(s) < 2 Then
        SayError "The EDIT command requires a parameter.", consoleID
        ShowHelp "edit", consoleID
        Exit Sub
    End If
    
    EditorFile_Short = GetShortName(s)
    EditorFile_Long = s
        
    If FileExists(App.Path & "\user" & cPrefix(consoleID) & s) Then

    Else
        Say consoleID, "{green}File Not Found, Creating: " & s
    
    End If
    
    
    frmEditor.Show vbModal
    
    If Trim(EditorRunFile) <> "" Then
        Shift_Console_Lines consoleID
        Run_Script EditorRunFile, consoleID, "", "CONSOLE"
    End If
    
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub ShowMail(ByVal s As String, ByVal consoleID As Integer)
    
    s = Trim(fixPath(s, consoleID))
    
    frmDSOMail.Show vbModal
     
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub AppendAFile(ByVal s As String, ByVal consoleID As Integer)
    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters: APPEND " & s, consoleID
        Exit Sub
    End If
    
    Dim sFile As String
    Dim sData As String
    Dim sFileData As String
    Dim AppendToStartOfFile As Boolean
    
    sFile = Trim(fixPath(Mid(s, 1, InStr(s, " ")), consoleID))
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
    
    If FileExists(App.Path & "\user" & cPrefix(consoleID) & sFile) = False Then
        'it will be created.
        sFileData = ""
    Else
        sFileData = GetFile(App.Path & "\user" & cPrefix(consoleID) & sFile)
    End If
    
    'add it to the data
    If AppendToStartOfFile = True Then
        sFileData = s & vbCrLf & sFileData
    Else
        sFileData = sFileData & vbCrLf & s
    End If
    
    
        
    If InStr(i(sFile), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Sub
    End If
    
    
    're write it!
    WriteFile App.Path & "\user" & cPrefix(consoleID) & sFile, sFileData
    
    
       
    
End Sub

Public Sub WriteAFile(ByVal s As String, ByVal consoleID As Integer, ByVal ScriptFrom As String)
    s = Trim(s)
    If InStr(s, " ") = 0 Then
        SayError "Invalid Parameters: WRITE " & s, consoleID
        Exit Sub
    End If
    
    Dim sFile As String
    Dim sData As String
    Dim sFileData As String

    
    sFile = Trim(fixPath(Mid(s, 1, InStr(s, " ")), consoleID))
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
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Sub
    End If
    
    

    're write it!
    WriteFile App.Path & "\user" & cPrefix(consoleID) & sFile, s
    
    
       
    
End Sub

Public Sub DisplayFile(ByVal s As String, ByVal consoleID As Integer)
    
    Dim sFile As String
    Dim startLine As Integer
    Dim MaxLines As Integer
    
    s = Trim(s)
    
    
    If InStr(s, " ") Then
        'file start and end lines are specified
        sFile = Trim(fixPath(Mid(s, 1, InStr(s, " ")), consoleID))
        
        s = Trim(Mid(s, InStr(s, " "), Len(s)))
        
        If InStr(s, " ") Then
            'both the start and amount of lines are specific
            startLine = Val(Mid(s, 1, InStr(s, " ")))
            MaxLines = Val(Trim(Mid(s, InStr(s, " "), Len(s))))
            
            If MaxLines < 1 Then
                SayError "Invalid Parameter Value: " & Trim(str(MaxLines)), consoleID
                Exit Sub
            End If
            If startLine < 1 Then
                SayError "Invalid Parameter Value: " & Trim(str(MaxLines)), consoleID
                Exit Sub
            End If
        Else
            'only the start line is specified
            startLine = Val(s)
            MaxLines = 29999
        End If
    Else
        'its just the filename
        sFile = Trim(fixPath(s, consoleID))
        startLine = 1
        MaxLines = 29999
    End If
    

    If FileExists(App.Path & "\user" & cPrefix(consoleID) & sFile) = False Then
        SayError "File Not Found: " & sFile, consoleID
        Exit Sub
    End If
    
    
    Dim FF As Long, tmpS As String, CLine As Integer, CLinePrinted As Integer

    FF = FreeFile
    Open App.Path & "\user" & cPrefix(consoleID) & sFile For Input As #FF
        Do Until EOF(FF)
            Line Input #FF, tmpS
            CLine = CLine + 1
            
            If CLine >= startLine Then
                If CLinePrinted < MaxLines Then
                    If Trim(tmpS) <> "" Then
                        Say consoleID, Chr(34) & "   " & tmpS & Chr(34), False, , 1
                        CLinePrinted = CLinePrinted + 1
                        If CLinePrinted Mod 24 = 0 Then PauseConsole "", consoleID
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

Public Sub WaitNow(ByVal s As String, ByVal consoleID As Integer)
   s = Trim(s)

    
    's is ms
    Dim iMS As Long
    iMS = Val(s)
    If iMS < 1 Then iMS = 1
    If iMS > 60000 Then iMS = 60000
    
    'now set the wait timer with the ims interval
    
    frmConsole.tmrWait(consoleID).Enabled = False
    frmConsole.tmrWait(consoleID).Interval = iMS
    frmConsole.tmrWait(consoleID).Enabled = True
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub RunFileAsScript(ByVal s As String, ByVal consoleID As Integer)
    
    
    
    
    Dim sParams As String
    s = Trim(s)
    If InStr(s, " ") > 0 Then
        sParams = Trim(Mid(s, InStr(s, " "), Len(s)))
        s = Trim(Mid(s, 1, InStr(s, " ")))
    End If
    
    s = fixPath(s, consoleID)
    

    If FileExists(App.Path & "\user" & cPrefix(consoleID) & s) Then
        'run it as a script
        
        WriteErrorLog "RunFileAsScript"
        Shift_Console_Lines consoleID
        Run_Script s, consoleID, sParams, "CONSOLE"
        
    Else
        SayError "File Not Found: " & s, consoleID
    End If
    
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub DelFiles(sFiles As String, ByVal consoleID As Integer)
    On Error Resume Next
    Kill sFiles
End Sub

Public Sub RemoveDir(ByVal s As String, ByVal consoleID As Integer)
    
    If Trim(s) = ".." Then DownADir consoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If

    s = fixPath(s, consoleID)
    
    If DirExists(App.Path & "\user" & cPrefix(consoleID) & s) = True Then
        'don't create it if it already exists
        If RemoveADir(App.Path & "\user" & cPrefix(consoleID) & s, consoleID) = False Then
            SayError "Directory Not Empty: " & s, consoleID
            Exit Sub
        End If
    Else
        'nothing to delete
    End If
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Function SayError(s As String, ByVal consoleID As Integer)
    Say consoleID, "Error - " & s & " {orange}", False
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

Public Sub ChangeDir(ByVal s As String, ByVal consoleID As Integer)
    s = Trim(s)
    
    If InvalidChars(s) = True Then
        SayError "Invalid Directory Name: " & s, consoleID
        Exit Sub
    End If
    
    If s = ".." Then DownADir consoleID: Exit Sub
    If InStr(s, "..") > 0 Then
        GoTo errorDir
    End If
    s = Replace(s, "/", "\")
    If s = "." Then Exit Sub
    If InStr(s, ".\") > 0 Then Exit Sub
    If InStr(s, "\.") > 0 Then Exit Sub
    

    s = fixPath(s, consoleID)
    
    'say consoleID, "path is " & s, False
    
    If DirExists(App.Path & "\user" & cPrefix(consoleID) & s) = True Then
        
        s = Replace(s, "\\", "\")
        s = s & "\"
        s = Replace(s, "\\", "\")
        
        cPath(consoleID) = s
    Else
        GoTo errorDir
    End If
    
    Exit Sub
errorDir:
    SayError "Directory Not Found: " & s, consoleID
End Sub

Public Function fixPath(ByVal s As String, ByVal consoleID As Integer) As String
    'file.s will come out as -> /file.s
    '/file.s will come out as -> /file.s
    'system/file.s will come out as -> /system/file.s
    'etc
    
    s = Trim(s)
    
    If Mid(s, 1, 1) = "/" Then s = "\" & Mid(s, 2, Len(s))
    
    If Mid(s, 1, 1) = "\" Then
        fixPath = s
    Else
        
        cPath(consoleID) = Replace(cPath(consoleID), "/", "\")
        
        If Right(cPath(consoleID), 1) = "\" Then
            fixPath = Mid(cPath(consoleID), 1, Len(cPath(consoleID)) - 1)
        End If
    End If
    
    fixPath = fixPath & cPrefix(consoleID) & "\" & s
    
    fixPath = Replace(fixPath, "../", "")
    fixPath = Replace(fixPath, "//", "/")
    fixPath = Replace(fixPath, "\\", "\")
    fixPath = Replace(fixPath, "..\", "")
    fixPath = Replace(fixPath, "/..", "")
    fixPath = Replace(fixPath, "\..", "")
    
    
End Function

Public Sub ListDirectoryContents(ByVal consoleID As Integer, Optional ByVal sFilter As String)
    On Error GoTo zxc

    sFilter = Trim(Replace(sFilter, "*", ""))
    
    Dim sPath As String, n As Integer, tmpS As String, sAll As String
    Dim dirMsg As String, fileMsg As String, fCount As Integer, dCount As Integer

    
    dirMsg = "Directory List {yellow 10}"
    fileMsg = "File List {yellow 10}"
    
    sPath = App.Path & "\user" & cPrefix(consoleID) & cPath(consoleID)
    
    
    
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
                Say consoleID, sAll & "{lyellow}", False
                'DrawItUp "0 0 0 0 solid", consoleID
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        Say consoleID, sAll & "{lyellow}", False
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
                Say consoleID, sAll & "{}", False
                'DrawItUp "0 12 12 12 solid", consoleID
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        
        Say consoleID, sAll & "{}", False
        'DrawItUp "0 12 12 12 solid", consoleID
    End If
NoFilesFound:
    sAll = ""
    
    Say consoleID, Trim(str(fCount)) & " file(s) and " & Trim(str(dCount)) & " dir(s) found in " & cPath(consoleID) & " {green 10}", False
    
    Exit Sub
zxc:
    SayError "Path Not Found: " & cPath(consoleID), consoleID
End Sub


Public Sub PauseConsole(s As String, ByVal consoleID As Integer)
    If Data_For_Run_Function_Enabled(consoleID) = 1 Then Exit Sub
    
    ConsolePaused(consoleID) = True
    
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
        Say consoleID, s, False
    Else
        'include the default property space
        Say consoleID, s & "{lblue 10}", False
    End If
    
    Do
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
    Loop Until ConsolePaused(consoleID) = False
    
End Sub

Public Sub ListColors(ByVal consoleID As Integer)
    
    ShowCol "lred", consoleID
    ShowCol "red", consoleID
    ShowCol "dred", consoleID
    
    ShowCol "purple", consoleID
    ShowCol "pink", consoleID
    ShowCol "lorange", consoleID
    ShowCol "orange", consoleID
    
    ShowCol "lblue", consoleID
    ShowCol "blue", consoleID
    ShowCol "dblue", consoleID
    
    ShowCol "lgreen", consoleID
    ShowCol "green", consoleID
    ShowCol "dgreen", consoleID
    
    ShowCol "lbrown", consoleID
    ShowCol "brown", consoleID
    ShowCol "dbrown", consoleID
    ShowCol "maroon", consoleID
    
    ShowCol "white", consoleID
    ShowCol "lgrey", consoleID
    ShowCol "grey", consoleID
    ShowCol "dgrey", consoleID
    
    ShowCol "gold", consoleID
    
    ShowCol "lyellow", consoleID
    ShowCol "yellow", consoleID
    ShowCol "dyellow", consoleID
    
    
End Sub

Sub ShowCol(ByVal s As String, ByVal consoleID As Integer)
    Say consoleID, s & " (**" & s & "**) {" & s & " 8}", False
End Sub

Public Sub ShowHelp(sP, ByVal consoleID As Integer)
    Dim props As String, propsforexamples As String
    props = "{green 12 underline}"
    propsforexamples = "{lgreen 12}"

    Select Case sP
    Case "help"
        Say consoleID, props & "Command: HELP", False
        Say consoleID, "{lgrey}Display the available console commands.", False
    Case "restart"
        Say consoleID, props & "Command: RESTART", False
        Say consoleID, "{lgrey}Restart the console immediately.", False
    Case "listcolors"
        Say consoleID, props & "Command: LISTCOLORS", False
        Say consoleID, "{lgrey}Display the available colors and color codes in the console.", False
    Case "listkeys"
        Say consoleID, props & "Command: LISTKEYS", False
        Say consoleID, "{lgrey}Display the available shortcut keys and their actions in the console.", False
    
    Case "time"
        Say consoleID, props & "Command: TIME", False
        Say consoleID, "{lgrey}Display the current system time.", False
    Case "date"
        Say consoleID, props & "Command: DATE", False
        Say consoleID, "{lgrey}Display the current system date.", False
    Case "now"
        Say consoleID, props & "Command: NOW", False
        Say consoleID, "{lgrey}Display the current system date and time.", False
    Case "clear"
        Say consoleID, props & "Command: CLEAR", False
        Say consoleID, "{lgrey}Clear the console screen.", False
    Case "stats"
        Say consoleID, props & "Command: STATS", False
        Say consoleID, "{lgrey}Display active information about the Dark Signs Network.", False
        Say consoleID, "{lorange}This information will be shown in the COMM window.", False
    
    Case "dir"
        
        Say consoleID, props & "Command: DIR optional-filter", False
        Say consoleID, "{lgrey}Display files and folders in the active directory.", False
        Say consoleID, "{lgrey}A filter can be appended to show only elements containing the filter keyword in their name.", False
        
    Case "pause"
        Say consoleID, props & "Command: PAUSE optional-msg", False
        Say consoleID, propsforexamples & "Example #1: PAUSE Press a key!", False
        Say consoleID, "{lgrey}Pause the console interface until the user presses a key.", False
    Case "cd"
        Say consoleID, props & "Command: CD directory-name", False
        Say consoleID, propsforexamples & "Example #1: CD myfiles", False
        Say consoleID, "{lgrey}Change the active path to the specified directory.", False
    Case "rd"
        Say consoleID, props & "Command: RD directory-name", False
        Say consoleID, propsforexamples & "Example #1: RD myfiles", False
        Say consoleID, "{lgrey}Delete the directory with the specified name.", False
        Say consoleID, "{lorange}The directory must be empty, or it will not be deleted.", False
    Case "del"
        Say consoleID, props & "Command: DEL filename", False
        Say consoleID, propsforexamples & "Example #1: DEL file.ds", False
        Say consoleID, "{lgrey}Delete the specified file or files.", False
        Say consoleID, "{lgrey}The wildcard symbol, *, can be used to delete multiple files at once.", False
        Say consoleID, "{lorange}Files in the system directory cannot be deleted.", False
        Say consoleID, "{orange}Be careful not to delete all of your files!", False
        
    Case "md"
        Say consoleID, props & "Command: MD directory-name", False
        Say consoleID, propsforexamples & "Example #1: MD myfiles", False
        Say consoleID, "{lgrey}Create a new empty directory with the specified name.", False
        Say consoleID, "{lorange}The name of the directory should not contain space characters.", False
            
    Case "lookup"
        Say consoleID, props & "Command: LOOKUP domain-or-username", False
        Say consoleID, propsforexamples & "Example #1: LOOKUP website.com", False
        Say consoleID, propsforexamples & "Example #2: LOOKUP jsmith", False
        Say consoleID, "{lgrey}View information about the specified domain name or user account.", False
        Say consoleID, "{lgrey}This command can be used on both domain names and user accounts.", False
        Say consoleID, "{lorange}Data will be returned in the COMM window.", False
                   
    Case "username"
        Say consoleID, props & "Command: USERNAME your-username", False
        Say consoleID, propsforexamples & "Example #1: USERNAME jsmith", False
        Say consoleID, "{lgrey}Set or change your Dark Signs username.", False
        Say consoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled.", False
        Say consoleID, "{lorange}If you do not have an account, visit the website to create one.", False
    Case "password"
        Say consoleID, props & "Command: PASSWORD your-password", False
        Say consoleID, propsforexamples & "Example #1: PASSWORD secret123", False
        Say consoleID, "{lgrey}Set or change your Dark Signs password.", False
        Say consoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled.", False
        Say consoleID, "{lorange}If you do not have an account, visit the website to create one.", False
    
    Case "ping"
        Say consoleID, props & "Command: PING domain-or-ip-server", False
        Say consoleID, propsforexamples & "Example #1: PING birds.com", False
        Say consoleID, "{lgrey}Check if the specified server exist on the network.", False
        Say consoleID, "{lorange}You can modify this command in the file \system\commands\ping.ds", False
    
    Case "me"
        Say consoleID, props & "Command: ME", False
        Say consoleID, propsforexamples & "Example #1: ME", False
        Say consoleID, "{lgrey}Do nothing at all!", False
        Say consoleID, "{lorange}This is a useless secret command.", False
    
    Case "pingport"
        Say consoleID, props & "Command: PINGPORT domain-or-ip-server 80", False
        Say consoleID, propsforexamples & "Example #1: PINGPORT birds.com 80", False
        Say consoleID, "{lgrey}Check if a script is runnning on the server at the specified port number.", False
        Say consoleID, "{lorange}You can modify this command in the file \system\commands\pingport.ds", False
            
    Case "getip"
        Say consoleID, props & "Command: GETIP domain-or-ip-server", False
        Say consoleID, propsforexamples & "Example #1: GETIP birds.com", False
        Say consoleID, "{lgrey}Get the IP address of the specified server.", False
        Say consoleID, "{lorange}You can modify this command in the file \system\commands\getip.ds", False
            
    Case "getdomain"
        Say consoleID, props & "Command: GETDOMAIN domain-or-ip-server", False
        Say consoleID, propsforexamples & "Example #1: GETDOMAIN 12.55.192.111", False
        Say consoleID, "{lgrey}Get the domain name of the specified server.", False
        Say consoleID, "{lorange}You can modify this command in the file \system\commands\getdomain.ds", False
                            
    Case "connect"
        Say consoleID, props & "Command: CONNECT server port-number [optional-parameters]", False
        Say consoleID, propsforexamples & "Example #1: CONNECT home.com 80", False
        Say consoleID, "{lgrey}Connect to a server domain name or IP address on the specified port.", False
        Say consoleID, "{lgrey}If no port number is specified, the default port number is 80.", False
        Say consoleID, "{lorange}You must specify the port number if you are including optional parameters.", False
 
        
            
    Case "move"
        Say consoleID, props & "Command: MOVE source-file destination-file", False
        Say consoleID, propsforexamples & "Example #1: MOVE myoldfile.ds mynewfile.ds", False
        Say consoleID, propsforexamples & "Example #2: MOVE /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        Say consoleID, "{lgrey}Rename the specified file.", False
        Say consoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        Say consoleID, "{lorange}File names should not contain space characters.", False
    Case "rename"
        Say consoleID, props & "Command: RENAME source-file destination-file", False
        Say consoleID, propsforexamples & "Example #1: MD myoldfile.ds mynewfile.ds", False
        Say consoleID, propsforexamples & "Example #2: MD /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        Say consoleID, "{lgrey}Rename the specified file.", False
        Say consoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        Say consoleID, "{lorange}File names should not contain space characters.", False
    Case "copy"
        Say consoleID, props & "Command: COPY source-file destination-file", False
        Say consoleID, propsforexamples & "Example #1: COPY myoldfile.ds mynewfile.ds", False
        Say consoleID, propsforexamples & "Example #2: COPY /home/myoldfile.ds  /home/dir2/mynewfile.ds", False
        Say consoleID, "{lgrey}Create a copy of the specified file.", False
        Say consoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2.", False
        Say consoleID, "{lorange}File names should not contain space characters.", False
    
    Case "saycomm"
        Say consoleID, props & "Command: SAYCOMM text", False
        Say consoleID, propsforexamples & "Example #1: SAYCOMM Connected to server", False
        Say consoleID, "{lgrey}Display the specified text in the COMM window.", False
        
    Case "run"
        Say consoleID, props & "Command: RUN file", False
        Say consoleID, propsforexamples & "Example #1: RUN myscript.ds", False
        Say consoleID, "{lgrey}Run the specified file as script in the console.", False
        Say consoleID, "{lgrey}Files not designed to be run as scripts may cause random errors to be displayed.", False
            
    Case "edit"
        Say consoleID, props & "Command: EDIT file", False
        Say consoleID, propsforexamples & "Example #1: EDIT myscript.ds", False
        Say consoleID, "{lgrey}Edit the specified file in the editing window. The console will pause while the editor is active.", False
        Say consoleID, "{lorange}Files in the editor are saved automatically.", False
                
'    Case "wait"
'        Say consoleID, props & "Command: WAIT milliseconds", False
'        Say consoleID, propsforexamples & "Example #1: WAIT 1000", False
'        Say consoleID, "{lgrey}Pause the console for the specific amount of time (between 1 and 60000 ms).", False
'        Say consoleID, "{lorange}1000 millisends is equal to 1 second.", False
'        Say consoleID, "{orange}This command is only enabled in scripts.", False
                    
    Case "upload"
        Say consoleID, props & "Command: UPLOAD server port-number file", False
        Say consoleID, propsforexamples & "Example #1: UPLOAD mywebsite.com 80 newscript.ds", False
        Say consoleID, "{lgrey}Upload a file to your domain name on the specified port.", False
        Say consoleID, "{lgrey}This script will then become connectable to all players.", False
        Say consoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own.", False
    
    Case "closeport"
        Say consoleID, props & "Command: CLOSEPORT server port-number", False
        Say consoleID, propsforexamples & "Example #1: CLOSEPORT mywebsite.com 80", False
        Say consoleID, "{lgrey}Close port on the specified domain.", False
        Say consoleID, "{lgrey}The script running on this port is deleted.", False
        Say consoleID, "{lorange}You can only close ports on domain names (servers) which you own.", False
                                      
    Case "download"
        Say consoleID, props & "Command: DOWNLOAD server port-number file", False
        Say consoleID, propsforexamples & "Example #1: DOWNLOAD mywebsite.com 80 thescript.ds", False
        Say consoleID, "{lgrey}Download a script file from a sever that you own.", False
        Say consoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own.", False
                             
    Case "transfer"
        Say consoleID, props & "Command: TRANSFER recipient-username amount description", False
        Say consoleID, propsforexamples & "Example #1: TRANSFER admin 5 A payment for you", False
        Say consoleID, "{lgrey}Transfer an amount of money (DS$) to the specified username.", False
        Say consoleID, "{lorange}Each transfer requires manual authorization from the sender.", False
                                    
    Case "ydiv"
        Say consoleID, props & "Command: YDIV height", False
        Say consoleID, propsforexamples & "Example #1: YDIV 240", False
        Say consoleID, "{lgrey}Change the default space between each console line.", False
        Say consoleID, "{lorange}The default YDIV is set to 60.", False
                                           
    Case "display"
        Say consoleID, props & "Command: DISPLAY file optional-start-line optional-max-lines", False
        Say consoleID, propsforexamples & "Example #1: DISPLAY myfile.txt 1 5", False
        Say consoleID, "{lgrey}Output the specified file to the console, without running as a script.", False
        Say consoleID, "{lorange}In the example, the first five lines of myfile.txt will be displayed.", False
                                                   
    Case "append"
        Say consoleID, props & "Command: APPEND file optional-START-or-END text", False
        Say consoleID, propsforexamples & "Example #1: APPEND myfile.txt new data", False
        Say consoleID, propsforexamples & "Example #2: APPEND myfile.txt START new data", False
        Say consoleID, "{lgrey}Append (add) text or data to the specified file.", False
        Say consoleID, "{lgrey}Data will be added to the beginning of the file if the START keyword is used.", False
        Say consoleID, "{lgrey}Data will be added to the end of the file if the END keyword is used.", False
        Say consoleID, "{lorange}If the specified file doesn't exist, it will be created.", False
                                                           
    Case "write"
        Say consoleID, props & "Command: WRITE file text", False
        Say consoleID, propsforexamples & "Example #1: WRITE myfile.txt new data", False
        Say consoleID, "{lgrey}Write text or data to the specified file.", False
        Say consoleID, "{lorange}If the specified file already exists, it will be overwritten.", False
        Say consoleID, "{lorange}Use APPEND to add data to an existing file.", False
        

    Case "register"
        Say consoleID, props & "Command: REGISTER domain-name", False
        Say consoleID, propsforexamples & "Example #1: REGISTER mynewwebsite.com", False
        Say consoleID, "{lgrey}Register a domain name on the Dark Signs Network.", False
        Say consoleID, "{lgrey}This command requires that you have the required amount of money (DS$) in your account.", False
        Say consoleID, "-", False
        Say consoleID, "{center orange nobold 14}- Check the latest prices in the COMM window. -", False
        'say consoleID, "-", False
        RunPage "domain_register.php?returnwith=2000&prices=1", consoleID
        
         
    Case "unregister"
        Say consoleID, props & "Command: UNREGISTER domain-name account-password", False
        Say consoleID, propsforexamples & "Example #1: UNREGISTER myoldwebsite.com secret123", False
        Say consoleID, "{lgrey}Unregister a domain name that you own on the Dark Signs Network.", False
        Say consoleID, "{lorange}This command requires that you include your password for security.", False
        
            
    Case "login"
        Say consoleID, props & "Command: LOGIN", False
        Say consoleID, "{lgrey}Attempt to log in to Dark Signs with your account username and password.", False
        Say consoleID, "{lgrey}This is only necessary if your status is 'not logged in'.", False
        Say consoleID, "{lorange}Use the USERNAME and PASSWORD commands to set or change your username or password.", False
        
    Case "logout"
        Say consoleID, props & "Command: LOGOUT", False
        Say consoleID, "{lgrey}Log out of Dark Signs.", False
        Say consoleID, "{lgrey}This can be helpful if you want to log in as another user, or if a rare error occurs.", False
            
    Case "mydomains"
        Say consoleID, props & "Command: MYDOMAINS", False
        Say consoleID, "{lgrey}List the domain names currently registered to you.", False
   
    Case "mysubdomains"
        Say consoleID, props & "Command: MYSUBDOMAINS", False
        Say consoleID, propsforexamples & "Example #1: MYSUBDOMAINS mySite.com", False
        Say consoleID, "{lgrey}List subdomains to a domain that is registed to you.", False
    
    Case "myips"
        Say consoleID, props & "Command: MYIPS", False
        Say consoleID, "{lgrey}List all IP addresses registed to you.", False
     
    Case "music"
        Say consoleID, props & "Command: MUSIC [parameter]", False
        Say consoleID, propsforexamples & "Example #1: MUSIC NEXT", False
        Say consoleID, "{lgrey}Music parameters are START, STOP, NEXT, and PREV.", False
        
    Case "say"
        Say consoleID, props & "Command: SAY text (**optional-properties**)", False
        Say consoleID, propsforexamples & "Example #1: SAY consoleID, hello, this is green (**green**)", False
        Say consoleID, propsforexamples & "Example #2: SAY consoleID, this is bold and very large (**bold, 36**)", False
        Say consoleID, "{lgrey}Display the specified text in the console.", False
        Say consoleID, "{lgrey}Text properties can be modified by adding any number of the following keywords in bewtween (** **), in any order.", False
        Say consoleID, "{lgreen}Colors: Type SHOWCOLORS the display a list of colors.", False
        Say consoleID, "{lgreen}Fonts: Arial, Arial Black, Comic Sans MS, Courier New, Georgia, Impact,", False
        Say consoleID, "{lgreen}Fonts: Lucida Console, Tahoma, Times New Roman, Trebuchet MS, Verdana, Wingdings.", False
        Say consoleID, "{lgreen}Attributes: Bold, NoBold, Italic, NoItalic, Underline, NoUnderline, Strikethru, NoStrikethru.", False
        Say consoleID, "{lgreen}Extras: Flash, Flashfast, FlashSlow.", False
        Say consoleID, "{orange}Note: You cannot use SAY to display multiple lines of text.", False
        Say consoleID, "{orange}For multiple lines, use SAYALL instead.", False
    
    Case "sayall"
        Say consoleID, props & "Command: SAYALL text (**optional-properties**)", False
        Say consoleID, propsforexamples & "Example #1: SAYALL hello", False
        Say consoleID, "{lgrey}Same as the SAY command, except will display multiple lines.", False
        Say consoleID, "{lorange}Type HELP SAY for more information.", False
             
    Case "sayline"
        Say consoleID, props & "Command: SAYLINE text (**optional-properties**)", False
        Say consoleID, propsforexamples & "Example #1: SAYLINE hello", False
        Say consoleID, "{lgrey}Same as the SAY command, except text will be printed on the same line, without moving down.", False
        Say consoleID, "{lorange}Type HELP SAY for more information.", False
           
    Case "remotedelete"
        Say consoleID, props & "Command: REMOTEDELETE domain filename", False
        Say consoleID, propsforexamples & "Example #1: REMOTEDELETE matrix.com myfile.ds", False
        Say consoleID, "{lgrey}Delete the specified file from the remote server.", False
        Say consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
    
    Case "remoteupload"
        Say consoleID, props & "Command: REMOTEUPLOAD domain filename", False
        Say consoleID, propsforexamples & "Example #1: REMOTEUPLOAD matrix.com localfile.ds", False
        Say consoleID, "{lgrey}Upload a file from your local file system to your domain name file system.", False
        Say consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
           
    Case "remotedir"
        Say consoleID, props & "Command: REMOTEDIR domain", False
        Say consoleID, propsforexamples & "Example #1: REMOTEDIR matrix.com", False
        Say consoleID, "{lgrey}View files on the remote server.", False
        Say consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
               
    Case "remoteview"
        Say consoleID, props & "Command: REMOTEVIEW domain filename", False
        Say consoleID, propsforexamples & "Example #1: REMOTEVIEW google.com userlist.log", False
        Say consoleID, "{lgrey}Display the specified remote file in the console.", False
        Say consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain.", False
    
    Case "draw"
        Say consoleID, props & "Command: DRAW -y Red(0-255) Green(0-255) Blue(0-255) mode", False
        Say consoleID, propsforexamples & "Example #1: DRAW -1 142 200 11 fadeout", False
        Say consoleID, "{lgrey}Print a background color stream to the console.", False
        Say consoleID, "{lgrey}The first parameter, -y, defines the console line.", False
        Say consoleID, "{lgrey}For example, -2 will draw to the second line up from the active line.", False
        Say consoleID, "{lgrey}The Red, Green, and Blue must be values between 0 and 255.", False
        Say consoleID, "{lorange}Available mode keywords: SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE.", False
        Say consoleID, "{orange}To use custom colors, use the DRAWCUSTOM command.", False
    
        
    
    Case "subowners"
        Say consoleID, props & "Command: SUBOWNERS domain-name KEYWORD [optional-username]", False
        Say consoleID, propsforexamples & "Example #1: SUBOWNERS site.com LIST", False
        Say consoleID, propsforexamples & "Example #2: SUBOWNERS site.com ADD friendusername", False
        Say consoleID, propsforexamples & "Example #3: SUBOWNERS site.com REMOVE friendusername", False
        Say consoleID, "{lgrey}Add or remove other user privileges regarding your specified domain name.", False
        Say consoleID, "{lgrey}You can add users to this list as subowners of your domain name.", False
        Say consoleID, "{lorange}Subowners have permission to interact, upload, and download files from the domain.", False
        Say consoleID, "{lorange}Subowners have no ability to unregister or modify the domain name  privileges.", False
        
        
        
    Case "lineup"
        Say consoleID, props & "Command: LINEUP", False
        Say consoleID, "{lgrey}Move up an extra console line. Useful for some scripts.", False
        
     'Case "chatsend"
     '   Say consoleID, props & "Command: CHATSEND Message to be sent to the chat.", False
     '   Say consoleID, propsforexamples & "Example #1: CHATSEND Hello World!", False
     '   Say consoleID, "{lgrey}A simple way to send messages to the chat from your console.", False
       
    
    Case "chatview"
        Say consoleID, props & "Command: CHATVIEW [parameter]", False
        Say consoleID, "{lgrey}If set to on, will display chat in the status window.", False
        Say consoleID, "{lgrey}CHATVIEW parameters are ON and OFF", False

    
    Case Else
        Say consoleID, props & "Available Commands", False
        'DrawItUp "0 0 0 0 solid", consoleID
        Say consoleID, "{lgrey 8}APPEND, CD, CLEAR, CLOSEPORT, CONNECT, COPY, DATE, DEL, DIR, DISPLAY, DOWNLOAD, DRAW, EDIT", False
        Say consoleID, "{lgrey 8}GETIP, GETDOMAIN, LINEUP, LISTCOLORS, LISTKEYS, LOGIN, LOGOUT, LOOKUP, MD, MOVE, MUSIC", False
        Say consoleID, "{lgrey 8}MYDOMAINS, MYIPS, MYSUBDOMAINS, NOW, PASSWORD, PAUSE, PING, PINGPORT, RD, RENAME, REGISTER", False
        Say consoleID, "{lgrey 8}REMOTEDELETE, REMOTEDIR, REMOTEUPLOAD, REMOTEVIEW, RESTART, RUN, SAY, SAYALL, SAYCOMM, STATS", False
        Say consoleID, "{lgrey 8}SUBOWNERS, TIME, TRANSFER, UNREGISTER, UPLOAD, USERNAME, WRITE, YDIV", False
        Say consoleID, "{grey}For more specific help on a command, type: HELP [command]", False
    End Select
End Sub

