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

Public Function ResolveCommand(consoleID As Integer, Command As String) As String
    If InStr(Command, "/") > 0 Or InStr(Command, "\") > 0 Or InStr(Command, ".") > 0 Then
        ResolveCommand = cPath(consoleID) & "/" & Command
        Exit Function
    End If
    ResolveCommand = "system/commands/" & Command & ".ds"
End Function


Public Function VBEscapeSimple(Str As String) As String
    VBEscapeSimple = Replace(Str, """", """""")
End Function


Public Function Run_Command(CLine As ConsoleLine, ByVal consoleID As Integer, Optional ScriptFrom As String, Optional FromScript As Boolean = True)
    If consoleID < 1 Then
        consoleID = 1
    End If
    If consoleID > 4 Then
        consoleID = 4
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
        New_Console_Line consoleID
        Exit Function
    End If

    CancelScript(consoleID) = False
    New_Console_Line_InProgress consoleID

    scrConsoleContext(consoleID).Aborted = False

    Dim CLIArgs() As String
    Dim CLIArgsQuoted() As Boolean
    ReDim CLIArgs(0 To 0)
    ReDim CLIArgsQuoted(0 To 0)
    Dim curArg As String
    Dim curC As String
    Dim InQuotes As String
    Dim X As Long
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
        Select Case curC
            Case " ":
                GoTo NextArg
            Case """", "'":
                InQuotes = curC
                GoTo CommandForNext
            Case ":", ",", ";", "(", ")", "|", "=", vbCr, vbLf: ' These mean the user likely intended VBScript and not CLI
                GoTo NotASimpleCommand
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
        If CLIArgs(UBound(CLIArgs)) <> "" Then
            ReDim Preserve CLIArgs(0 To UBound(CLIArgs) + 1)
            ReDim Preserve CLIArgsQuoted(0 To UBound(CLIArgs))
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

    ' If we arrive here, it means the user probably intended to run a CLI command!
    Dim Command As String
    Command = CLIArgs(0)
    
    ' First, check if there is a command for it in /system/commands
    Dim ResolvedCommand As String
    ResolvedCommand = ResolveCommand(consoleID, Command)
    If FileExists(App.Path & "/user/" & ResolvedCommand) Then
        On Error GoTo EvalError
        Run_Script ResolvedCommand, consoleID, CLIArgs, "CLI", "", False, False, False
        On Error GoTo 0
        GoTo ScriptEnd
    End If
    
    If CLIArgsQuoted(0) Then
        GoTo NotASimpleCommand
    End If

    ' Try running procedure with given name
    Dim RunStr As String
    RunStr = "Option Explicit : " & Command & "("
    For X = 1 To UBound(CLIArgs)
        If X > 1 Then
            RunStr = ", " & RunStr
        End If
        If Left(CLIArgs(X), 1) = "$" And Not CLIArgsQuoted(X) Then
            RunStr = RunStr & Mid(CLIArgs(X), 2)
        Else
            RunStr = RunStr & """" & VBEscapeSimple(CLIArgs(X)) & """"
        End If
    Next X
    RunStr = RunStr & ")"
    On Error GoTo EvalError
    scrConsole(consoleID).ExecuteStatement RunStr
    On Error GoTo 0

    GoTo ScriptEnd

NotASimpleCommand:
    On Error GoTo EvalError
    scrConsole(consoleID).AddCode tmpS
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
    SayRaw consoleID, "Error processing script: " & Err.Description & " (" & Str(Err.Number) & ") " & ErrHelp & " {red}"
    GoTo ScriptEnd

ScriptCancelled:
    SayRaw consoleID, "Script Stopped by User (CTRL + C){orange}"
ScriptEnd:
    scrConsoleContext(consoleID).CleanupScriptTasks
    New_Console_Line consoleID
End Function

' -y r g b mode
'  SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE
Public Sub DrawItUp(ByVal YPos As Long, ByVal R As Long, ByVal G As Long, ByVal b As Long, ByVal Mode As String, ByVal consoleID As Integer)
    Dim sColor As String
    Dim sMode As String
     
    Dim yIndex As Integer, n As Integer
    yIndex = (YPos * -1) + 1

    Console(consoleID, yIndex).DrawMode = Mode
    
    Select Case Mode
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
    SayCOMM "Downloading domain list..."
    RunPage "my_domains.php?type=domain", consoleID, False, "", 0
End Sub

Public Sub ListMySubDomains(ByVal Domain As String, ByVal consoleID As Integer)
    SayCOMM "Downloading subdomain list..."
    RunPage "my_domains.php?domain=" & EncodeURLParameter(Domain) & "&type=subdomain", consoleID, False, "", 0
End Sub

Public Sub ListMyIPs(ByVal consoleID As Integer)
    SayCOMM "Downloading IP list..."
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


Public Sub UploadToDomain(ByVal sDomain As String, ByVal sPort As Integer, ByVal sFilename As String, ByVal consoleID As Integer)
    Dim sFileData As String
    sFilename = fixPath(sFilename, consoleID)

    If FileExists(App.Path & "\user" & sFilename) = True Then
        Dim tempStrA As String

        sFileData = GetFileClean(App.Path & "\user" & sFilename)
        tempStrA = EncodeBase64(StrConv(sFileData, vbFromUnicode))

        RunPage "domain_upload.php", consoleID, True, _
        "port=" & EncodeURLParameter(Trim(sPort)) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(tempStrA)
        
        SayCOMM "Attempting to upload: " & UCase(sDomain) & ":" & i(sPort), consoleID
        
    Else
        SayError "File Not Found:" & sFilename, consoleID
        Exit Sub
    End If
End Sub

Public Sub CloseDomainPort(ByVal s As String, ByVal consoleID As Integer)
    Dim sDomain As String
    Dim sPort As String
    
    s = Trim(s)
    If InStr(s, " ") = 0 Then GoTo zxc
    
    
    sDomain = i(Mid(s, 1, InStr(s, " ")))
    
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    
    sPort = s
  
    RunPage "domain_close.php", consoleID, True, _
    "port=" & EncodeURLParameter(Trim(sPort)) & _
    "&d=" & EncodeURLParameter(sDomain)
        
    SayCOMM "Attempting to close port : " & UCase(sDomain) & ":" & i(sPort), consoleID
        
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
    
    s = Trim(Mid(s, InStr(s, " "), Len(s)))
    If InStr(s, " ") = 0 Then GoTo zxc
    
    sPort = i(Mid(s, 1, InStr(s, " ")))
    sFilename = Trim(Mid(s, InStr(s, " "), Len(s)))
    sFilename = fixPath(sFilename, consoleID)
    


        RunPage "domain_download.php", consoleID, True, _
        "returnwith=4400" & _
        "&port=" & EncodeURLParameter(Trim(sPort)) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filename=" & EncodeURLParameter(sFilename)
        
        SayCOMM "Attempting to download: " & UCase(sDomain) & ":" & i(sPort), consoleID
        
    

    
    Exit Sub
zxc:
    SayError "Invalid Parameters", consoleID
    ShowHelp "download", consoleID
    
End Sub


Public Sub SubOwners(ByVal s As String, ByVal consoleID As Integer)
    s = i(s)

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
           
            RunPage "domain_privileges.php", consoleID, True, _
            "returnwith=2001&list=" & EncodeURLParameter(Trim(sDomain))

    ElseIf Mid(i(s), 1, 4) = "add " Then
        sUsername = Trim(Mid(s, 5, Len(s)))
            
            RunPage "domain_privileges.php", consoleID, True, _
            "returnwith=2001&add=" & EncodeURLParameter(Trim(sDomain)) & "&username=" & EncodeURLParameter(sUsername)

    ElseIf Mid(i(s), 1, 7) = "remove " Then
        sUsername = Trim(Mid(s, 8, Len(s)))
        
             RunPage "domain_privileges.php", consoleID, True, _
            "returnwith=2001&remove=" & EncodeURLParameter(Trim(sDomain)) & "&username=" & EncodeURLParameter(sUsername)

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
        SayRaw consoleID, "A domain name should be in the following form: MYDOMAIN.COM{lorange}"
        SayRaw consoleID, "Subdomains should be in the form: BLOG.MYDOMAIN.COM{lorange}"
        SayRaw consoleID, "Valid domain name characters are:"
        SayRaw consoleID, "A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, -{grey 8}"
        Exit Sub
    End If
    
    SayRaw consoleID, "{green 10}A registration request has been sent for " & s & "."
    SayRaw consoleID, "{lgreen 10}The result will be posted to the COMM."
    
    
    'RunPage "domain_register.php?returnwith=2000&d=" & Trim(s), consoleID
    RunPage "domain_register.php", consoleID, True, "d=" & EncodeURLParameter(s)
    
End Sub

Public Sub UnRegisterDomain(ByVal s As String, ByVal consoleID As Integer)
    s = Trim(s)
    If s = "" Then
        SayError "The UNREGISTER command requires parameters.", consoleID
        ShowHelp "unregister", consoleID
        Exit Sub
    End If
    

    Dim sDomain As String
    Dim sPass As String
    
    If InStr(s, " ") > 0 Then
        sDomain = LCase(Trim(Mid(s, 1, InStr(s, " "))))
        sPass = Trim(Mid(s, InStr(s, " "), Len(s)))
    Else
        SayError "Your password is required as a final parameter.", consoleID
        ShowHelp "unregister", consoleID
        Exit Sub
    End If
    
    SayRaw consoleID, "{green 10}A unregistration request has been sent for " & sDomain & "."
    SayRaw consoleID, "{lgreen 10}The result will be posted to the COMM."

    
    RunPage "domain_unregister.php", consoleID, True, _
    "returnwith=2000&d=" & EncodeURLParameter(Trim(sDomain)) & "&pw=" & EncodeURLParameter(sPass)
End Sub

Public Sub ServerCommands(ByVal s As String, ByVal consoleID As Integer)
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
    
    sPostData = "append=" & EncodeURLParameter(sFilename) & _
        "&keycode=" & EncodeURLParameter(sKey) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(sFileData)
    
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
    
    sPostData = "write=" & EncodeURLParameter(sFilename) & _
        "&keycode=" & EncodeURLParameter(sKey) & _
        "&d=" & EncodeURLParameter(sDomain) & _
        "&filedata=" & EncodeURLParameter(sFileData)
        
    RunPage "domain_filesystem.php", consoleID, True, sPostData, 0

End Sub


Public Sub TransferMoney(ByVal s As String, ByVal consoleID As Integer)
    Dim sTo As String
    Dim sAmount As String
    Dim sDescription As String

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

    
        SayCOMM "Processing Payment...", consoleID
    
        RunPage "transfer.php", consoleID, True, _
        "returnwith=2000" & _
        "&to=" & EncodeURLParameter(Trim(sTo)) & _
        "&amount=" & EncodeURLParameter(Trim(sAmount)) & _
        "&description=" & EncodeURLParameter(Trim(sDescription))
    
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
    
    
    RunPage "lookup.php?returnwith=2000&d=" & EncodeURLParameter(Trim(s)), consoleID
    
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
    SayCOMM "Downloading stats..."
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
    
    SayRaw consoleID, "Dark Signs Keyboard Actions{gold 14}"
    
    SayRaw consoleID, "Page Up: Scroll the console up." & ss
    SayRaw consoleID, "Page Down: Scroll the console down." & ss
    
    SayRaw consoleID, "Shift + Page Up: Decrease size of the COMM." & ss
    SayRaw consoleID, "Shift + Page Down: Incease size of the COMM." & ss
    
    SayRaw consoleID, "F11: Toggle maximum console display." & ss
End Sub


Public Sub SetUsername(ByVal s As String, ByVal consoleID As Integer)
    If Authorized = True Then
        SayError "You are already logged in.", consoleID
        Exit Sub
    End If

    RegSave "myUsernameDev", s
    
    Dim Password As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
    SayRaw consoleID, "Your new details are shown below." & "{orange}"
    SayRaw consoleID, "Username: " & myUsername() & "{orange 16}"
    SayRaw consoleID, "Password: " & Password & "{orange 16}"
End Sub

Public Sub SetPassword(ByVal s As String, ByVal consoleID As Integer)
    If Authorized = True Then
        SayError "You are already logged in.", consoleID
        Exit Sub
    End If

    RegSave "myPasswordDev", s
    
    Dim Password As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
    SayRaw consoleID, "Your new details are shown below." & "{orange}"
    SayRaw consoleID, "Username: " & myUsername() & "{orange 16}"
    SayRaw consoleID, "Password: " & Password & "{orange 16}"
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
    
    If FileExists(App.Path & "\user" & s1) = False Then
        SayError "File Not Found: " & s1, consoleID
        Exit Sub
    End If
    
    'now move it or copy it
    If i(sTag) = "copyonly" Then
        If CopyAFile(App.Path & "\user" & s1, App.Path & "\user" & s2, consoleID) = False Then
            SayError "Invalid Destination File: " & s2, consoleID
            Exit Sub
        End If
    Else
        If MoveAFile(App.Path & "\user" & s1, App.Path & "\user" & s2, consoleID) = False Then
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
    
    
    DelFiles App.Path & "\user" & s, consoleID
    
    Exit Sub
    
errorDir:
    'say consoleID, "Directory Not Found: " & s & " {orange}", False
End Sub

Public Sub EditFile(ByVal s As String, ByVal consoleID As Integer)
    s = fixPath(s, consoleID)
    If s = "" Then
        Exit Sub
    End If

    EditorFile_Short = GetShortName(s)
    EditorFile_Long = s

    If FileExists(App.Path & "\user" & s) Then
    Else
        SayRaw consoleID, "{green}File Not Found, Creating: " & s
    End If
    
    frmEditor.Show vbModal
    
    If Trim(EditorRunFile) <> "" Then
        Shift_Console_Lines consoleID
        Dim EmptyArguments(0 To 0) As String
        Run_Script EditorRunFile, consoleID, EmptyArguments, "CONSOLE", "", True, False, False
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
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Sub
    End If
    
    
    're write it!
    WriteFile App.Path & "\user" & sFile, sFileData
    
    
       
    
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
    WriteFile App.Path & "\user" & sFile, s
    
    
       
    
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
                SayError "Invalid Parameter Value: " & Trim(Str(MaxLines)), consoleID
                Exit Sub
            End If
            If startLine < 1 Then
                SayError "Invalid Parameter Value: " & Trim(Str(MaxLines)), consoleID
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
    

    If FileExists(App.Path & "\user" & sFile) = False Then
        SayError "File Not Found: " & sFile, consoleID
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
                        SayRaw consoleID, Chr(34) & "   " & tmpS & Chr(34), , 1
                        CLinePrinted = CLinePrinted + 1
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
    
    If DirExists(App.Path & "\user" & s) = True Then
        'don't create it if it already exists
        If RemoveADir(App.Path & "\user" & s, consoleID) = False Then
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
    SayRaw consoleID, "Error - " & s & " {orange}"
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
    
    If DirExists(App.Path & "\user" & s) = True Then
        
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
    
    fixPath = fixPath & "\" & s
    
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
    
    sPath = App.Path & "\user" & cPath(consoleID)
    
    
    
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
                SayRaw consoleID, sAll & "{lyellow}"
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        SayRaw consoleID, sAll & "{lyellow}"
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
                SayRaw consoleID, sAll & "{}"
                sAll = ""
            End If
        End If
    Next n
    If sAll <> "" Then
        
        SayRaw consoleID, sAll & "{}"
    End If
NoFilesFound:
    sAll = ""
    
    SayRaw consoleID, Trim(Str(fCount)) & " file(s) and " & Trim(Str(dCount)) & " dir(s) found in " & cPath(consoleID) & " {green 10}"
    
    Exit Sub
zxc:
    SayError "Path Not Found: " & cPath(consoleID), consoleID
End Sub

Public Sub PauseConsole(s As String, ByVal consoleID As Integer)
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
        SayRaw consoleID, s
    Else
        SayRaw consoleID, s & "{lblue 10}"
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
    SayRaw consoleID, s & " (**" & s & "**) {" & s & " 8}"
End Sub

Public Sub ShowHelp(sP, ByVal consoleID As Integer)
    Dim props As String, propsforexamples As String
    props = "{green 12 underline}"
    propsforexamples = "{lgreen 12}"

    Select Case sP
    Case "help"
        SayRaw consoleID, props & "Command: HELP"
        SayRaw consoleID, "{lgrey}Display the available console commands."
    Case "restart"
        SayRaw consoleID, props & "Command: RESTART"
        SayRaw consoleID, "{lgrey}Restart the console immediately."
    Case "listcolors"
        SayRaw consoleID, props & "Command: LISTCOLORS"
        SayRaw consoleID, "{lgrey}Display the available colors and color codes in the console."
    Case "listkeys"
        SayRaw consoleID, props & "Command: LISTKEYS"
        SayRaw consoleID, "{lgrey}Display the available shortcut keys and their actions in the console."
    
    Case "time"
        SayRaw consoleID, props & "Command: TIME"
        SayRaw consoleID, "{lgrey}Display the current system time."
    Case "date"
        SayRaw consoleID, props & "Command: DATE"
        SayRaw consoleID, "{lgrey}Display the current system date."
    Case "now"
        SayRaw consoleID, props & "Command: NOW"
        SayRaw consoleID, "{lgrey}Display the current system date and time."
    Case "clear"
        SayRaw consoleID, props & "Command: CLEAR"
        SayRaw consoleID, "{lgrey}Clear the console screen."
    Case "stats"
        SayRaw consoleID, props & "Command: STATS"
        SayRaw consoleID, "{lgrey}Display active information about the Dark Signs Network."
        SayRaw consoleID, "{lorange}This information will be shown in the COMM window."
    
    Case "dir"
        
        SayRaw consoleID, props & "Command: DIR optional-filter"
        SayRaw consoleID, "{lgrey}Display files and folders in the active directory."
        SayRaw consoleID, "{lgrey}A filter can be appended to show only elements containing the filter keyword in their name."
        
    Case "pause"
        SayRaw consoleID, props & "Command: PAUSE optional-msg"
        SayRaw consoleID, propsforexamples & "Example #1: PAUSE Press a key!"
        SayRaw consoleID, "{lgrey}Pause the console interface until the user presses a key."
    Case "cd"
        SayRaw consoleID, props & "Command: CD directory-name"
        SayRaw consoleID, propsforexamples & "Example #1: CD myfiles"
        SayRaw consoleID, "{lgrey}Change the active path to the specified directory."
    Case "rd"
        SayRaw consoleID, props & "Command: RD directory-name"
        SayRaw consoleID, propsforexamples & "Example #1: RD myfiles"
        SayRaw consoleID, "{lgrey}Delete the directory with the specified name."
        SayRaw consoleID, "{lorange}The directory must be empty, or it will not be deleted."
    Case "del"
        SayRaw consoleID, props & "Command: DEL filename"
        SayRaw consoleID, propsforexamples & "Example #1: DEL file.ds"
        SayRaw consoleID, "{lgrey}Delete the specified file or files."
        SayRaw consoleID, "{lgrey}The wildcard symbol, *, can be used to delete multiple files at once."
        SayRaw consoleID, "{lorange}Files in the system directory cannot be deleted."
        SayRaw consoleID, "{orange}Be careful not to delete all of your files!"
        
    Case "md"
        SayRaw consoleID, props & "Command: MD directory-name"
        SayRaw consoleID, propsforexamples & "Example #1: MD myfiles"
        SayRaw consoleID, "{lgrey}Create a new empty directory with the specified name."
        SayRaw consoleID, "{lorange}The name of the directory should not contain space characters."
            
    Case "lookup"
        SayRaw consoleID, props & "Command: LOOKUP domain-or-username"
        SayRaw consoleID, propsforexamples & "Example #1: LOOKUP website.com"
        SayRaw consoleID, propsforexamples & "Example #2: LOOKUP jsmith"
        SayRaw consoleID, "{lgrey}View information about the specified domain name or user account."
        SayRaw consoleID, "{lgrey}This command can be used on both domain names and user accounts."
        SayRaw consoleID, "{lorange}Data will be returned in the COMM window."
                   
    Case "username"
        SayRaw consoleID, props & "Command: USERNAME your-username"
        SayRaw consoleID, propsforexamples & "Example #1: USERNAME jsmith"
        SayRaw consoleID, "{lgrey}Set or change your Dark Signs username."
        SayRaw consoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled."
        SayRaw consoleID, "{lorange}If you do not have an account, visit the website to create one."
    Case "password"
        SayRaw consoleID, props & "Command: PASSWORD your-password"
        SayRaw consoleID, propsforexamples & "Example #1: PASSWORD secret123"
        SayRaw consoleID, "{lgrey}Set or change your Dark Signs password."
        SayRaw consoleID, "{lorange}If your username and password are invalid or not set, the majority of features will be disabled."
        SayRaw consoleID, "{lorange}If you do not have an account, visit the website to create one."
    
    Case "ping"
        SayRaw consoleID, props & "Command: PING domain-or-ip-server"
        SayRaw consoleID, propsforexamples & "Example #1: PING birds.com"
        SayRaw consoleID, "{lgrey}Check if the specified server exist on the network."
        SayRaw consoleID, "{lorange}You can modify this command in the file \system\commands\ping.ds"
    
    Case "me"
        SayRaw consoleID, props & "Command: ME"
        SayRaw consoleID, propsforexamples & "Example #1: ME"
        SayRaw consoleID, "{lgrey}Do nothing at all!"
        SayRaw consoleID, "{lorange}This is a useless secret command."
    
    Case "pingport"
        SayRaw consoleID, props & "Command: PINGPORT domain-or-ip-server 80"
        SayRaw consoleID, propsforexamples & "Example #1: PINGPORT birds.com 80"
        SayRaw consoleID, "{lgrey}Check if a script is runnning on the server at the specified port number."
        SayRaw consoleID, "{lorange}You can modify this command in the file \system\commands\pingport.ds"
            
    Case "getip"
        SayRaw consoleID, props & "Command: GETIP domain-or-ip-server"
        SayRaw consoleID, propsforexamples & "Example #1: GETIP birds.com"
        SayRaw consoleID, "{lgrey}Get the IP address of the specified server."
        SayRaw consoleID, "{lorange}You can modify this command in the file \system\commands\getip.ds"
            
    Case "getdomain"
        SayRaw consoleID, props & "Command: GETDOMAIN domain-or-ip-server"
        SayRaw consoleID, propsforexamples & "Example #1: GETDOMAIN 12.55.192.111"
        SayRaw consoleID, "{lgrey}Get the domain name of the specified server."
        SayRaw consoleID, "{lorange}You can modify this command in the file \system\commands\getdomain.ds"
                            
    Case "connect"
        SayRaw consoleID, props & "Command: CONNECT server port-number [optional-parameters]"
        SayRaw consoleID, propsforexamples & "Example #1: CONNECT home.com 80"
        SayRaw consoleID, "{lgrey}Connect to a server domain name or IP address on the specified port."
        SayRaw consoleID, "{lgrey}If no port number is specified, the default port number is 80."
        SayRaw consoleID, "{lorange}You must specify the port number if you are including optional parameters."
 
        
            
    Case "move"
        SayRaw consoleID, props & "Command: MOVE source-file destination-file"
        SayRaw consoleID, propsforexamples & "Example #1: MOVE myoldfile.ds mynewfile.ds"
        SayRaw consoleID, propsforexamples & "Example #2: MOVE /home/myoldfile.ds  /home/dir2/mynewfile.ds"
        SayRaw consoleID, "{lgrey}Rename the specified file."
        SayRaw consoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2."
        SayRaw consoleID, "{lorange}File names should not contain space characters."
    Case "rename"
        SayRaw consoleID, props & "Command: RENAME source-file destination-file"
        SayRaw consoleID, propsforexamples & "Example #1: MD myoldfile.ds mynewfile.ds"
        SayRaw consoleID, propsforexamples & "Example #2: MD /home/myoldfile.ds  /home/dir2/mynewfile.ds"
        SayRaw consoleID, "{lgrey}Rename the specified file."
        SayRaw consoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2."
        SayRaw consoleID, "{lorange}File names should not contain space characters."
    Case "copy"
        SayRaw consoleID, props & "Command: COPY source-file destination-file"
        SayRaw consoleID, propsforexamples & "Example #1: COPY myoldfile.ds mynewfile.ds"
        SayRaw consoleID, propsforexamples & "Example #2: COPY /home/myoldfile.ds  /home/dir2/mynewfile.ds"
        SayRaw consoleID, "{lgrey}Create a copy of the specified file."
        SayRaw consoleID, "{lgrey}You can also move the file to a new directory, as shown in example #2."
        SayRaw consoleID, "{lorange}File names should not contain space characters."
    
    Case "saycomm"
        SayRaw consoleID, props & "Command: SAYCOMM text"
        SayRaw consoleID, propsforexamples & "Example #1: SAYCOMM Connected to server"
        SayRaw consoleID, "{lgrey}Display the specified text in the COMM window."
        
    Case "run"
        SayRaw consoleID, props & "Command: RUN file"
        SayRaw consoleID, propsforexamples & "Example #1: RUN myscript.ds"
        SayRaw consoleID, "{lgrey}Run the specified file as script in the console."
        SayRaw consoleID, "{lgrey}Files not designed to be run as scripts may cause random errors to be displayed."
            
    Case "edit"
        SayRaw consoleID, props & "Command: EDIT file"
        SayRaw consoleID, propsforexamples & "Example #1: EDIT myscript.ds"
        SayRaw consoleID, "{lgrey}Edit the specified file in the editing window. The console will pause while the editor is active."
        SayRaw consoleID, "{lorange}Files in the editor are saved automatically."
                
'    Case "wait"
'        SayRaw consoleID, props & "Command: WAIT milliseconds"
'        SayRaw consoleID, propsforexamples & "Example #1: WAIT 1000"
'        SayRaw consoleID, "{lgrey}Pause the console for the specific amount of time (between 1 and 60000 ms)."
'        SayRaw consoleID, "{lorange}1000 millisends is equal to 1 second."
'        SayRaw consoleID, "{orange}This command is only enabled in scripts."
                    
    Case "upload"
        SayRaw consoleID, props & "Command: UPLOAD server port-number file"
        SayRaw consoleID, propsforexamples & "Example #1: UPLOAD mywebsite.com 80 newscript.ds"
        SayRaw consoleID, "{lgrey}Upload a file to your domain name on the specified port."
        SayRaw consoleID, "{lgrey}This script will then become connectable to all players."
        SayRaw consoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own."
    
    Case "closeport"
        SayRaw consoleID, props & "Command: CLOSEPORT server port-number"
        SayRaw consoleID, propsforexamples & "Example #1: CLOSEPORT mywebsite.com 80"
        SayRaw consoleID, "{lgrey}Close port on the specified domain."
        SayRaw consoleID, "{lgrey}The script running on this port is deleted."
        SayRaw consoleID, "{lorange}You can only close ports on domain names (servers) which you own."
                                      
    Case "download"
        SayRaw consoleID, props & "Command: DOWNLOAD server port-number file"
        SayRaw consoleID, propsforexamples & "Example #1: DOWNLOAD mywebsite.com 80 thescript.ds"
        SayRaw consoleID, "{lgrey}Download a script file from a sever that you own."
        SayRaw consoleID, "{lorange}You can only upload and download scripts to domain names (servers) which you own."
                             
    Case "transfer"
        SayRaw consoleID, props & "Command: TRANSFER recipient-username amount description"
        SayRaw consoleID, propsforexamples & "Example #1: TRANSFER admin 5 A payment for you"
        SayRaw consoleID, "{lgrey}Transfer an amount of money (DS$) to the specified username."
        SayRaw consoleID, "{lorange}Each transfer requires manual authorization from the sender."
                                    
    Case "ydiv"
        SayRaw consoleID, props & "Command: YDIV height"
        SayRaw consoleID, propsforexamples & "Example #1: YDIV 240"
        SayRaw consoleID, "{lgrey}Change the default space between each console line."
        SayRaw consoleID, "{lorange}The default YDIV is set to 60."
                                           
    Case "display"
        SayRaw consoleID, props & "Command: DISPLAY file optional-start-line optional-max-lines"
        SayRaw consoleID, propsforexamples & "Example #1: DISPLAY myfile.txt 1 5"
        SayRaw consoleID, "{lgrey}Output the specified file to the console, without running as a script."
        SayRaw consoleID, "{lorange}In the example, the first five lines of myfile.txt will be displayed."
                                                   
    Case "append"
        SayRaw consoleID, props & "Command: APPEND file optional-START-or-END text"
        SayRaw consoleID, propsforexamples & "Example #1: APPEND myfile.txt new data"
        SayRaw consoleID, propsforexamples & "Example #2: APPEND myfile.txt START new data"
        SayRaw consoleID, "{lgrey}Append (add) text or data to the specified file."
        SayRaw consoleID, "{lgrey}Data will be added to the beginning of the file if the START keyword is used."
        SayRaw consoleID, "{lgrey}Data will be added to the end of the file if the END keyword is used."
        SayRaw consoleID, "{lorange}If the specified file doesn't exist, it will be created."
                                                           
    Case "write"
        SayRaw consoleID, props & "Command: WRITE file text"
        SayRaw consoleID, propsforexamples & "Example #1: WRITE myfile.txt new data"
        SayRaw consoleID, "{lgrey}Write text or data to the specified file."
        SayRaw consoleID, "{lorange}If the specified file already exists, it will be overwritten."
        SayRaw consoleID, "{lorange}Use APPEND to add data to an existing file."
        

    Case "register"
        SayRaw consoleID, props & "Command: REGISTER domain-name"
        SayRaw consoleID, propsforexamples & "Example #1: REGISTER mynewwebsite.com"
        SayRaw consoleID, "{lgrey}Register a domain name on the Dark Signs Network."
        SayRaw consoleID, "{lgrey}This command requires that you have the required amount of money (DS$) in your account."
        SayRaw consoleID, "-"
        SayRaw consoleID, "{center orange nobold 14}- Check the latest prices in the COMM window. -"
        RunPage "domain_register.php?returnwith=2000&prices=1", consoleID
        
         
    Case "unregister"
        SayRaw consoleID, props & "Command: UNREGISTER domain-name account-password"
        SayRaw consoleID, propsforexamples & "Example #1: UNREGISTER myoldwebsite.com secret123"
        SayRaw consoleID, "{lgrey}Unregister a domain name that you own on the Dark Signs Network."
        SayRaw consoleID, "{lorange}This command requires that you include your password for security."
        
            
    Case "login"
        SayRaw consoleID, props & "Command: LOGIN"
        SayRaw consoleID, "{lgrey}Attempt to log in to Dark Signs with your account username and password."
        SayRaw consoleID, "{lgrey}This is only necessary if your status is 'not logged in'."
        SayRaw consoleID, "{lorange}Use the USERNAME and PASSWORD commands to set or change your username or password."
        
    Case "logout"
        SayRaw consoleID, props & "Command: LOGOUT"
        SayRaw consoleID, "{lgrey}Log out of Dark Signs."
        SayRaw consoleID, "{lgrey}This can be helpful if you want to log in as another user, or if a rare error occurs."
            
    Case "mydomains"
        SayRaw consoleID, props & "Command: MYDOMAINS"
        SayRaw consoleID, "{lgrey}List the domain names currently registered to you."
   
    Case "mysubdomains"
        SayRaw consoleID, props & "Command: MYSUBDOMAINS"
        SayRaw consoleID, propsforexamples & "Example #1: MYSUBDOMAINS mySite.com"
        SayRaw consoleID, "{lgrey}List subdomains to a domain that is registed to you."
    
    Case "myips"
        SayRaw consoleID, props & "Command: MYIPS"
        SayRaw consoleID, "{lgrey}List all IP addresses registed to you."
     
    Case "music"
        SayRaw consoleID, props & "Command: MUSIC [parameter]"
        SayRaw consoleID, propsforexamples & "Example #1: MUSIC NEXT"
        SayRaw consoleID, "{lgrey}Music parameters are START, STOP, NEXT, and PREV."
        
    Case "say"
        SayRaw consoleID, props & "Command: SAY text (**optional-properties**)"
        SayRaw consoleID, propsforexamples & "Example #1: SAY consoleID, hello, this is green (**green**)"
        SayRaw consoleID, propsforexamples & "Example #2: SAY consoleID, this is bold and very large (**bold, 36**)"
        SayRaw consoleID, "{lgrey}Display the specified text in the console."
        SayRaw consoleID, "{lgrey}Text properties can be modified by adding any number of the following keywords in bewtween (** **), in any order."
        SayRaw consoleID, "{lgreen}Colors: Type SHOWCOLORS the display a list of colors."
        SayRaw consoleID, "{lgreen}Fonts: Arial, Arial Black, Comic Sans MS, Courier New, Georgia, Impact,"
        SayRaw consoleID, "{lgreen}Fonts: Lucida Console, Tahoma, Times New Roman, Trebuchet MS, Verdana, Wingdings."
        SayRaw consoleID, "{lgreen}Attributes: Bold, NoBold, Italic, NoItalic, Underline, NoUnderline, Strikethru, NoStrikethru."
        SayRaw consoleID, "{lgreen}Extras: Flash, Flashfast, FlashSlow."
        SayRaw consoleID, "{orange}Note: You cannot use SAY to display multiple lines of text."
        SayRaw consoleID, "{orange}For multiple lines, use SAYALL instead."
    
    Case "sayall"
        SayRaw consoleID, props & "Command: SAYALL text (**optional-properties**)"
        SayRaw consoleID, propsforexamples & "Example #1: SAYALL hello"
        SayRaw consoleID, "{lgrey}Same as the SAY command, except will display multiple lines."
        SayRaw consoleID, "{lorange}Type HELP SAY for more information."
             
    Case "sayline"
        SayRaw consoleID, props & "Command: SAYLINE text (**optional-properties**)"
        SayRaw consoleID, propsforexamples & "Example #1: SAYLINE hello"
        SayRaw consoleID, "{lgrey}Same as the SAY command, except text will be printed on the same line, without moving down."
        SayRaw consoleID, "{lorange}Type HELP SAY for more information."
           
    Case "remotedelete"
        SayRaw consoleID, props & "Command: REMOTEDELETE domain filename"
        SayRaw consoleID, propsforexamples & "Example #1: REMOTEDELETE matrix.com myfile.ds"
        SayRaw consoleID, "{lgrey}Delete the specified file from the remote server."
        SayRaw consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
    
    Case "remoteupload"
        SayRaw consoleID, props & "Command: REMOTEUPLOAD domain filename"
        SayRaw consoleID, propsforexamples & "Example #1: REMOTEUPLOAD matrix.com localfile.ds"
        SayRaw consoleID, "{lgrey}Upload a file from your local file system to your domain name file system."
        SayRaw consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
           
    Case "remotedir"
        SayRaw consoleID, props & "Command: REMOTEDIR domain"
        SayRaw consoleID, propsforexamples & "Example #1: REMOTEDIR matrix.com"
        SayRaw consoleID, "{lgrey}View files on the remote server."
        SayRaw consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
               
    Case "remoteview"
        SayRaw consoleID, props & "Command: REMOTEVIEW domain filename"
        SayRaw consoleID, propsforexamples & "Example #1: REMOTEVIEW google.com userlist.log"
        SayRaw consoleID, "{lgrey}Display the specified remote file in the console."
        SayRaw consoleID, "{lorange}You must own the domain, or have subowner privileges on the domain."
    
    Case "draw"
        SayRaw consoleID, props & "Command: DRAW -y Red(0-255) Green(0-255) Blue(0-255) mode"
        SayRaw consoleID, propsforexamples & "Example #1: DRAW -1 142 200 11 fadeout"
        SayRaw consoleID, "{lgrey}Print a background color stream to the console."
        SayRaw consoleID, "{lgrey}The first parameter, -y, defines the console line."
        SayRaw consoleID, "{lgrey}For example, -2 will draw to the second line up from the active line."
        SayRaw consoleID, "{lgrey}The Red, Green, and Blue must be values between 0 and 255."
        SayRaw consoleID, "{lorange}Available mode keywords: SOLID, FLOW, FADEIN, FADEOUT, FADECENTER, FADEINVERSE."
        SayRaw consoleID, "{orange}To use custom colors, use the DRAWCUSTOM command."
    
        
    
    Case "subowners"
        SayRaw consoleID, props & "Command: SUBOWNERS domain-name KEYWORD [optional-username]"
        SayRaw consoleID, propsforexamples & "Example #1: SUBOWNERS site.com LIST"
        SayRaw consoleID, propsforexamples & "Example #2: SUBOWNERS site.com ADD friendusername"
        SayRaw consoleID, propsforexamples & "Example #3: SUBOWNERS site.com REMOVE friendusername"
        SayRaw consoleID, "{lgrey}Add or remove other user privileges regarding your specified domain name."
        SayRaw consoleID, "{lgrey}You can add users to this list as subowners of your domain name."
        SayRaw consoleID, "{lorange}Subowners have permission to interact, upload, and download files from the domain."
        SayRaw consoleID, "{lorange}Subowners have no ability to unregister or modify the domain name  privileges."
        
        
        
    Case "lineup"
        SayRaw consoleID, props & "Command: LINEUP"
        SayRaw consoleID, "{lgrey}Move up an extra console line. Useful for some scripts."
        
     'Case "chatsend"
     '   SayRaw consoleID, props & "Command: CHATSEND Message to be sent to the chat."
     '   SayRaw consoleID, propsforexamples & "Example #1: CHATSEND Hello World!"
     '   SayRaw consoleID, "{lgrey}A simple way to send messages to the chat from your console."
       
    
    Case "chatview"
        SayRaw consoleID, props & "Command: CHATVIEW [parameter]"
        SayRaw consoleID, "{lgrey}If set to on, will display chat in the status window."
        SayRaw consoleID, "{lgrey}CHATVIEW parameters are ON and OFF"

    
    Case Else
        SayRaw consoleID, props & "Available Commands"
        SayRaw consoleID, "{lgrey 8}APPEND, CD, CLEAR, CLOSEPORT, CONNECT, COPY, DATE, DEL, DIR, DISPLAY, DOWNLOAD, DRAW, EDIT"
        SayRaw consoleID, "{lgrey 8}GETIP, GETDOMAIN, LINEUP, LISTCOLORS, LISTKEYS, LOGIN, LOGOUT, LOOKUP, MD, MOVE, MUSIC"
        SayRaw consoleID, "{lgrey 8}MYDOMAINS, MYIPS, MYSUBDOMAINS, NOW, PASSWORD, PAUSE, PING, PINGPORT, RD, RENAME, REGISTER"
        SayRaw consoleID, "{lgrey 8}REMOTEDELETE, REMOTEDIR, REMOTEUPLOAD, REMOTEVIEW, RESTART, RUN, SAY, SAYALL, SAYCOMM, STATS"
        SayRaw consoleID, "{lgrey 8}SUBOWNERS, TIME, TRANSFER, UNREGISTER, UPLOAD, USERNAME, WRITE, YDIV"
        SayRaw consoleID, "{grey}For more specific help on a command, type: HELP [command]"
    End Select
End Sub

