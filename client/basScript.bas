Attribute VB_Name = "basScript"
Option Explicit

Public Vars(1 To 9999) As Var
Public VariableLengths(1 To 24) As String

Public GetKeyWaiting(1 To 4) As String
Public GetAsciiWaiting(1 To 4) As String

Public CancelScript(1 To 4) As Boolean
Public WaitingForInput(1 To 4) As Boolean
Public WaitingForInput_Message(1 To 4) As String 'i.e. Enter an IP Address
Public WaitingForInput_VarIndex(1 To 4) As Integer 'var index that will be assigned the input

Public Data_For_Run_Function_Enabled(1 To 4) As Integer
Public Data_For_Run_Function(1 To 4) As String

Public FunctionList(1 To 99) As String

Public Type Var
    VarName As String
    VarValue As String
End Type

Public Type FunctionTemp
    Before_String As String
    After_String As String
    functionParameters As String
    tmpS As String
    S As String
End Type

Public Type NextFunction
    StartPos As Long
    FunctionName As String
End Type

Public Function Run_Script(filename As String, ByVal ConsoleID As Integer, ScriptParameters As String, ScriptFrom As String)
    If ConsoleID < 1 Then
        ConsoleID = 1
    End If
    If ConsoleID > 4 Then
        ConsoleID = 4
    End If
    Dim OldPath As String
    OldPath = cPath(ConsoleID)

    If Right(Trim(filename), 1) = ">" Then Exit Function
    If Trim(filename) = "." Or Trim(filename) = ".." Then Exit Function
    If InStr(filename, Chr(34) & Chr(34)) Then Exit Function
    
    DoEvents

    Dim ShortFileName As String
    'file name should be from local dir, i.e: \system\startup.ds
    ShortFileName = filename
    filename = App.Path & "\user" & filename
    'make sure it is not a directory
    If DirExists(filename) = True Then Exit Function

    If FileExists(filename) = False Then
        SayCOMM "File Not Found: " & filename
        Exit Function
    End If
    
    Dim FF As Long
    Dim tmpS As String
    Dim tmpAll As String
    tmpAll = ""
    FF = FreeFile
    Open filename For Input As #FF
        Do Until EOF(FF)
            tmpS = ""
            Line Input #FF, tmpS
            tmpAll = tmpAll & Trim(tmpS) & vbCrLf
        Loop
    Close #FF

    Dim S As New ScriptControl
    S.AllowUI = False
    S.Timeout = 0
    S.UseSafeSubset = True
    S.Language = "VBScript"

    Dim G As clsScriptFunctions
    Set G = New clsScriptFunctions
    G.ConsoleID = ConsoleID
    G.ScriptFrom = ScriptFrom
    S.AddObject "DSO", G, True

    On Error GoTo EvalError
    S.AddCode tmpAll
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
    cPath(ConsoleID) = OldPath
End Function


Public Sub ScriptLog(S As String, lineNum As Integer)
    'AppendFile App.Path & "\script.log", "Line " & Format(lineNum, "000") & ", " & s
End Sub

Public Function SetVariable(ByVal VarName As String, ByVal VarVal As String, ByVal ConsoleID As Integer, ByVal ScriptFrom As String)
    
    'these strings can be used to divide varval for functions like "transfer("
    Dim s1 As String, s2 As String, s3 As String, s4 As String, s5 As String

    
    Dim tmpS As String
    tmpS = VarName & " " & VarVal
    
    If InStr(tmpS, "=") = 0 Then
        'if no equals sign, assign the value a blank value
        VarName = tmpS
        VarVal = ""
    Else
        VarName = Mid(tmpS, 1, InStr(tmpS, "=") - 1)
        VarVal = Mid(tmpS, InStr(tmpS, "=") + 1, Len(tmpS))
    End If
    
    'just in case (this is required AGAIN sometimes, long story...)
    VarVal = ReplaceVariables(VarVal, ConsoleID)
    
    'does the variable name contain []? is it an array?
    VarName = ReplaceArrayIndex(VarName, ConsoleID)
    
    
    VarName = Trim(Replace(VarName, "$", ""))
    If Len(VarName) < 1 Then Exit Function
    
    Dim sockIndex As Integer
    Dim VarIndex As Integer
    
    VarIndex = VariableIndex(VarName)
    
    If VarIndex = 0 Then
        'its a new variable
        VarIndex = NextEmptyVariable
        'add to the variable lengths table so it can be replaced efficiently later
        VariableLengths(Len(VarName)) = VariableLengths(Len(VarName)) & Trim(Str(VarIndex)) & ":"
        
    End If
    
    VarVal = Trim(VarVal)
    
    
    
    'check if the value is a function
    If Mid(i(VarVal), 1, 7) = "getkey(" Then
        GetKeyWaiting(ConsoleID) = "1"
        Do
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            If CancelScript(ConsoleID) = True Then GoTo zz1
        Loop Until GetKeyWaiting(ConsoleID) <> "1"
zz1:
        VarVal = GetKeyWaiting(ConsoleID)
        GetKeyWaiting(ConsoleID) = "0"
    ElseIf Mid(i(VarVal), 1, 9) = "getascii(" Then
        GetAsciiWaiting(ConsoleID) = "1"
        Do
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            If CancelScript(ConsoleID) = True Then GoTo zz2
        Loop Until GetAsciiWaiting(ConsoleID) <> "1"
zz2:
        VarVal = GetAsciiWaiting(ConsoleID)
        GetAsciiWaiting(ConsoleID) = "0"
    ElseIf Mid(i(VarVal), 1, 6) = "input(" Then
        cPath_tmp(ConsoleID) = cPath(ConsoleID)
        cPath(ConsoleID) = Mid(VarVal, 7, Len(VarVal))
        If Right(cPath(ConsoleID), 1) = ")" Then cPath(ConsoleID) = Mid(cPath(ConsoleID), 1, Len(cPath(ConsoleID)) - 1)
        
        WaitingForInput(ConsoleID) = True
        WaitingForInput_VarIndex(ConsoleID) = VarIndex
        WaitingForInput_Message(ConsoleID) = cPath(ConsoleID)
        
        Shift_Console_Lines_Reverse ConsoleID
    ElseIf Mid(i(VarVal), 1, 9) = "download(" Then
        Dim VarVal2 As String
        VarVal2 = KillDirectFunctionSides(VarVal)
        VarVal = "[loading]"
        sockIndex = DownloadUserURL(VarVal2, VarIndex, ConsoleID)
    ElseIf Mid(i(VarVal), 1, 5) = "ping(" Then '--------- doing 1
        VarVal = KillDirectFunctionSides(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "ping.php?port=0&domain=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 9) = "pingport(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "ping.php?port=" & EncodeURLParameter(GetPart(VarVal, 2, " ")) & "&domain=" & EncodeURLParameter(SumUp(GetPart(VarVal, 1, " "), ConsoleID)), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 9) = "transfer(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")

        GetFirstAndShortenRemaining s1, VarVal, " "
        GetFirstAndShortenRemaining s2, VarVal, " "
        s3 = VarVal
        
        Print_Console True
        DoEvents
        
        AuthorizePayment = False
        frmPayment.lAmount = "$" & s2 & ".00"
        frmPayment.lDescription = s3
        frmPayment.lTo = s1
        frmPayment.Show vbModal
        

        If AuthorizePayment = True And Val(s2) > 0 Then
            sockIndex = DownloadURL(API_Server & API_Path & "transfer.php?to=" & EncodeURLParameter(s1) & "&amount=" & EncodeURLParameter(s2) & "&description=" & EncodeURLParameter(s3), VarIndex, ConsoleID)
            VarVal = "[loading]"
        Else
            VarVal = "Payment Not Sent"
        End If
    ElseIf Mid(i(VarVal), 1, 15) = "transferstatus(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "transfer_info.php?status=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 15) = "transferamount(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "transfer_info.php?amount=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 20) = "transferdescription(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "transfer_info.php?description=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 19) = "transfertousername(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "transfer_info.php?to_username=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 21) = "transferfromusername(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "transfer_info.php?from_username=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 13) = "transferdate(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "transfer_info.php?date=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 13) = "transfertime(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "transfer_info.php?time=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 16) = "serverfilecount(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem_meta.php?count=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 15) = "serverfilename(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem_meta.php?name=" & EncodeURLParameter(GetPart(VarVal, 1, " ")) & "&fileindex=" & EncodeURLParameter(GetPart(VarVal, 2, " ")), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 17) = "serverfiledelete(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem_meta.php?delete=" & EncodeURLParameter(GetPart(VarVal, 1, " ")) & "&filename=" & EncodeURLParameter(GetPart(VarVal, 2, " ")), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 19) = "serverfiledownload(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem_meta.php?download=" & EncodeURLParameter(GetPart(VarVal, 1, " ")) & "&filename=" & EncodeURLParameter(GetPart(VarVal, 2, " ")), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 17) = "serverfileupload(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = EncodeURLParameter(VarVal)
        s2 = GetPart(VarVal, 2, " ") 'filename
        s2 = EncodeURLParameter(GetFile(App.Path & "\user" & fixPath(s2, ConsoleID)))

        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem_meta.php?upload=" & EncodeURLParameter(GetPart(VarVal, 1, " ")) & "&filename=" & EncodeURLParameter(GetPart(VarVal, 2, " ")) & "&filedata=" & EncodeURLParameter(s2), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 12) = "servertoken(" Then
        VarVal = KillDirectFunctionSides(VarVal)
        If ScriptFrom = "" Then
            VarVal = "not from a script"
        Else
            VarVal = "[loading]"
            sockIndex = DownloadURL(API_Server & API_Path & "domain_token.php?d=" & EncodeURLParameter(ScriptFrom), VarIndex, ConsoleID)
        End If
    ElseIf Mid(i(VarVal), 1, 12) = "urlencode(" Then
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = EncodeURLParameter(VarVal)
    ElseIf Mid(i(VarVal), 1, 6) = "getip(" Then '--------- doing 3
        VarVal = KillDirectFunctionSides(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "domain_meta.php?getip=" & EncodeURLParameter(SumUp(VarVal, ConsoleID)), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 10) = "getdomain(" Then '--------- doing 4
        VarVal = KillDirectFunctionSides(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "domain_meta.php?getdomain=" & EncodeURLParameter(VarVal), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 13) = "filedownload(" Then '--------- doing 2
        'file download is for people getting any files from their own domain name
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem.php?d=" & EncodeURLParameter(GetPart(VarVal, 1, " ")) & "&downloadfile=" & EncodeURLParameter(GetPart(VarVal, 2, " ")), VarIndex, ConsoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 11) = "fileserver(" Then '--------- doing 2
        'fileserver is for people getting part of a file on a server
        'e.g. $v = fileserver($domainname, $file, $startline, $endline)
        
        
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Replace(VarVal, "  ", " ")
        
        If InStr(Mid(VarVal, 1, 18), "(") > 0 Then VarVal = Mid(VarVal, InStr(VarVal, "(") + 1, Len(VarVal))

        'MsgBox VarVal
        
        s1 = DSOEncode(Trim(GetPart(VarVal, 1, " ")))
        '------------------------------------

        '------------------------------------
        
        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem.php?" & _
        "keycode=" & EncodeURLParameter(s1) & _
        "&d=" & EncodeURLParameter(GetPart(VarVal, 2, " ")) & _
        "&fileserver=" & EncodeURLParameter(RemoveSurroundingQuotes(GetPart(VarVal, 3, " "))) & _
        "&startline=" & EncodeURLParameter(GetPart(VarVal, 4, " ")) & _
        "&maxlines=" & EncodeURLParameter(GetPart(VarVal, 5, " ")), VarIndex, ConsoleID)
        
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 8) = "dirlist(" Then
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = RemoveSurroundingQuotes(VarVal)
        VarVal = Trim(VarVal)
        Dim sFilter As String, sPath As String, n As Integer, sAll As String, dCount As Integer
        sFilter = Trim(Replace(sFilter, "*", ""))
    
        sPath = App.Path & "\user" & cPath(ConsoleID)
        
        'directories
        frmConsole.Dir1.Path = sPath
        frmConsole.Dir1.Refresh
        dCount = 0
        For n = 0 To frmConsole.Dir1.ListCount - 1
            tmpS = UCase(Replace(frmConsole.Dir1.List(n), sPath, ""))
            
            If InStr(tmpS, UCase(sFilter)) > 0 Then
                dCount = dCount + 1
                sAll = sAll & tmpS & "|"
            End If
        Next n
        
        If (dCount > 0) Then
            VarVal = dCount & "|" & sAll
        Else
            VarVal = 0
        End If
    ElseIf Mid(i(VarVal), 1, 9) = "filelist(" Then
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = RemoveSurroundingQuotes(VarVal)
        VarVal = Trim(VarVal)
        'Dim sFilter As String, sPath As String, n As Integer, sAll As String, dCount As Integer
        'sFilter = Trim(Replace(VarVal, "*", ""))
        'MsgBox VarVal
        sFilter = Trim(Replace(VarVal, "*", ""))
        'cd MsgBox sFilter
        'sFilter = "*"
        sPath = App.Path & "\user" & cPath(ConsoleID)
    
        'files
        frmConsole.File1.Pattern = "*"
        frmConsole.File1.Path = sPath
        frmConsole.File1.Refresh
        dCount = 0
        'say consoleID, fileMsg, False
        If frmConsole.File1.ListCount > 1 Then
            
            For n = 0 To frmConsole.File1.ListCount - 1
                tmpS = Trim(Replace(frmConsole.File1.List(n), sPath, ""))
                'MsgBox InStr(tmpS), UCase(sFilter))
                If InStr(UCase(tmpS), UCase(sFilter)) > 0 Then
                    dCount = dCount + 1
                    sAll = sAll & tmpS & "|"
                End If
            Next n
            If dCount = 0 Then
                VarVal = 0
            Else
                VarVal = dCount & "|" & sAll
            End If
        Else
            VarVal = 0
        End If
    'ElseIf Mid(i(VarVal), 1, 9) = "filehash(" Then
    '
    '    VarVal = KillDirectFunctionSides(VarVal)
    '    'MsgBox VarVal
    '    VarVal = RemoveSurroundingQuotes(VarVal)
    '
    '    VarVal = f_File(VarVal & ", 1", consoleID)
    '    VarVal = Trim(VarVal)
    '    If VarVal <> "*FILE-ERROR*" Then
    '        VarVal = MD5_string(VarVal)
    '    End If
    ElseIf Mid(i(VarVal), 1, 6) = "time()" Then '--------- doing 4
        sockIndex = DownloadURL(API_Server & API_Path & "time.php", VarIndex, ConsoleID)
        VarVal = "[loading]"
    Else
        VarVal = SumUp(VarVal, ConsoleID)
    End If
    
    
    
    If Left(VarVal, 1) = Chr(34) And Right(VarVal, 1) = Chr(34) Then
        'if the string is encased in quotes, remove them
        VarVal = Mid(VarVal, 2, Len(VarVal))
        VarVal = Mid(VarVal, 1, Len(VarVal) - 1)
    End If
    
    
    Vars(VarIndex).VarName = Trim(VarName)
    Vars(VarIndex).VarValue = VarVal
    
    
    
    Msgbux "indx(" & Trim(Str(VarIndex)) & ")" & " name(" & VarName & ")= val(" & VarVal & ")"
    
End Function
Public Function DownloadUserURL(ByVal VarVal As String, VarIndex As Integer, ConsoleID As Integer) As Integer
    DownloadUserURL = DownloadURL(VarVal, VarIndex, ConsoleID, True)
End Function

Public Function DownloadURL(ByVal VarVal As String, VarIndex As Integer, ConsoleID As Integer, Optional NoAuth As Boolean) As Integer
    Dim sUrl As String
    Dim PostData As String

    VarVal = RemoveSurroundingQuotes(VarVal)

    If InStr(Mid(VarVal, 1, 18), "(") > 0 Then
        VarVal = Mid(VarVal, InStr(VarVal, "(") + 1, Len(VarVal))
    End If

    sUrl = Trim(VarVal)
     
    sUrl = Trim(sUrl) & "***"
    sUrl = Replace(sUrl, ")***", "")
    sUrl = Replace(sUrl, "***", "")
    
    If InStr(sUrl, "?") > 0 Then
        PostData = Mid(sUrl, InStr(sUrl, "?") + 1, Len(sUrl))
        sUrl = Mid(sUrl, 1, InStr(sUrl, "?") - 1)
    Else
        PostData = ""
    End If
    PostData = Trim(PostData)
    sUrl = Trim(sUrl)
    
    Dim sDomain As String
    If InStr(sUrl, "/") > 0 Then
        sDomain = Mid(sUrl, 1, InStr(sUrl, "/") - 1)
    Else
        sDomain = sUrl
    End If
    

    DownloadURL = RunPage(sUrl, ConsoleID, True, PostData, VarIndex, NoAuth)
End Function

Public Sub GetFirstAndShortenRemaining(s1 As String, sFullString As String, dividerChar As String)
    's1 should be a variable that you want to be sent the first part of sFullString
    'sFullString should be like  thing1 thing2 thing3
    'then s1 will return thing1, and sFullString will return thing2 thing3
    
    If InStr(sFullString, dividerChar) > 0 Then
        s1 = Trim(Mid(sFullString, 1, InStr(sFullString, dividerChar) - 1))
        sFullString = Trim(Mid(sFullString, Len(s1) + 1, Len(sFullString)))
    Else
        s1 = Trim(sFullString)
        sFullString = ""
    End If
    
End Sub

Public Function KillDirectFunctionSides(ByVal S As String) As String
    'this replaces something like  run(blah yah)  with just blah yah
    
    If Right(S, 1) = ")" Then
        S = Mid(S, 1, Len(S) - 1)
        
        If InStr(Mid(S, 1, 24), "(") > 0 Then
            S = Mid(S, InStr(S, "(") + 1, Len(S))
        End If
        
    End If
    
    KillDirectFunctionSides = S
End Function

Public Function ReplaceArrayIndex(ByVal VarName As String, ConsoleID As Integer) As String

    ReplaceArrayIndex = VarName
    
    If InStr(VarName, "[") > 0 And InStr(VarName, "]") > 0 Then
        If InStr(VarName, "[") < InStr(VarName, "]") Then
        
            If Mid(VarName, 1, 1) = "$" Then
                ReplaceArrayIndex = "$" & ReplaceVariables(Mid(VarName, 2, Len(VarName)), ConsoleID)
            End If
        End If
    
    End If
End Function

Public Function VariableIndex(ByVal VarName As String) As Integer
    VarName = Trim(Replace(VarName, "$", ""))
    If Len(VarName) < 1 Then VariableIndex = 0: Exit Function
    
    Dim n As Long
    For n = 1 To UBound(Vars)
        If Vars(n).VarName = VarName Then
            VariableIndex = n
            Exit Function
        End If
        If Vars(n).VarName = "" Then GoTo AllDone
    Next n
AllDone:
    
    
    'it's a new variable! index not found
    VariableIndex = 0
    
End Function

Public Function NextEmptyVariable() As Integer
    Dim n As Long
    For n = 1 To UBound(Vars)
        If Trim(Vars(n).VarName) = "" Then
            NextEmptyVariable = n
            Exit Function
        End If
    Next n
    
    NextEmptyVariable = Int(Rnd * UBound(Vars)) + 1
    MsgBox "Error - your variable space is empty. Please restart as soon as possible.", vbCritical, "Error"
End Function

Public Function ReplaceVariables(ByVal S As String, ByVal ConsoleID As Integer) As String

    
        
    'global variables
    S = Replace(S, "$time", Format(Time, "h:mm AMPM"))
    S = Replace(S, "$date", Date)
    S = Replace(S, "$now", Now)
    S = Replace(S, "$username", Trim(myUsername))
    S = Replace(S, "$consoleid", Trim(Str(ConsoleID)))
    S = Replace(S, "$dir", cPath(ConsoleID))
    S = Replace(S, "$newline", vbCrLf)
    S = Replace(S, "$tab", Chr(vbKeyTab))
    
    
        
    If InStr(S, "$") = 0 Or Trim(S) = "" Then
        If Has_Functions(S) = False Then
            ReplaceVariables = S
            Exit Function
        End If
    End If
    
    

    
    'better check for variables
    Dim nLen As Integer, n As Integer, nA() As String, tmpS As String
    
    'first, replace variable indexes...
    'note how tmps is generated with a [ and ] on each side
    For nLen = 12 To 1 Step -1
        If Trim(VariableLengths(nLen)) <> "" Then
            nA = Split(VariableLengths(nLen), ":")
            For n = 0 To UBound(nA)
                If IsNumeric(nA(n)) = True Then
                    tmpS = "[$" & Vars(Val(nA(n))).VarName & "]"
                    S = Replace(S, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
                    
                    'do it some more, with spaces aruond the [ and ], just in case
                    tmpS = "[ $" & Vars(Val(nA(n))).VarName & " ]"
                    S = Replace(S, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
                    tmpS = "[ $" & Vars(Val(nA(n))).VarName & "]"
                    S = Replace(S, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
                    tmpS = "[$" & Vars(Val(nA(n))).VarName & " ]"
                    S = Replace(S, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
                End If
            Next n
        End If
    Next nLen
        
    'now replace general variables
    For nLen = 24 To 1 Step -1
        If Trim(VariableLengths(nLen)) <> "" Then
            nA = Split(VariableLengths(nLen), ":")
            For n = 0 To UBound(nA)
                If IsNumeric(nA(n)) = True Then
                    tmpS = "$" & Vars(Val(nA(n))).VarName
                    S = Replace(S, tmpS, Vars(Val(nA(n))).VarValue)
                End If
            Next n
        End If
    Next nLen
    

    'now check for functions like mid(), left(), etc

    
    If Has_Functions(S) = True Then
    '   MsgBox s
        S = Bracketize(S, False) 'prepare inside brackets
        S = Convert_Functions(S, ConsoleID)
        S = UnBracketize(S) 'fix inside bracks to original state
    End If
    
   
    ReplaceVariables = S

End Function

Public Function FunctionData(ByVal S As String, n As Integer, sFunction As String) As FunctionTemp
    
'    '-------------------------------------
'    'this part is so that other brackets like () won't interfere with function edges.
'    'it's not perfect, but it will have to do, because it is the best idea I have.
'    Dim t1 As String, t2 As String
'    t1 = Mid(s, n, Len(s))
'    If InStr(t1, "(") > 0 Then t1 = Mid(t1, InStr(t1, "(") + 1, Len(t1))
'    If InStr(t1, ")") > 0 And InStr(t1, "(") > 0 Then
'        If InStr(t1, ")") > InStr(t1, "(") Then
'            'kill the next (, and then the next )
'
'
'            t2 = Mid(t1, 1, InStr(t1, "(") - 1) & "[[" & _
'            Mid(t1, InStr(t1, "(") + 1, Len(t1))
'
'            t2 = Mid(t2, 1, InStr(t2, ")") - 1) & "]]" & Mid(t2, InStr(t2, ")") + 1, Len(t2))


'
'
'        End If
'    End If
'    '-------------------------------------
'



    FunctionData.Before_String = Mid(S, 1, n - 1)
    FunctionData.functionParameters = Mid(S, n + Len(sFunction) + 1, 999)
    
    If InStr(FunctionData.functionParameters, ")") > 0 Then
        FunctionData.functionParameters = Mid(FunctionData.functionParameters, 1, InStr(FunctionData.functionParameters, ")") - 1)
    End If
    
    FunctionData.functionParameters = UnBracketize(FunctionData.functionParameters)
    
    FunctionData.tmpS = Mid(S, Len(FunctionData.Before_String) + 1, Len(S))
    FunctionData.After_String = Mid(S, InStr(S, ")") + 1, Len(S))
                

End Function

Public Function Convert_Functions(ByVal S As String, ConsoleID As Integer) As String



    Dim NextFunctionPos As NextFunction
    Dim sParameters As String, sFunctionResult As String
    
    Dim isForAvariable As Boolean
    
    S = Trim(S)
    If Left(S, 1) = "=" Then
        isForAvariable = True
        S = Trim(Mid(S, 2, Len(S)))
    Else
        isForAvariable = False
    End If

    
    NextFunctionPos = NextFunctionPosition(S)
    
    
    Do While NextFunctionPos.StartPos > 0
        
        
        sParameters = Mid(S, NextFunctionPos.StartPos + Len(NextFunctionPos.FunctionName), Len(S))
        
        If InStr(sParameters, ")") > 0 Then sParameters = Mid(sParameters, 1, InStr(sParameters, ")"))
        sParameters = Trim(sParameters)
        
        
        
        
        'WriteFile App.Path & "\zparams.txt", sParameters
        
        DoEvents
        
        sFunctionResult = RunFunction(NextFunctionPos.FunctionName, sParameters, ConsoleID)
        S = Mid(S, 1, NextFunctionPos.StartPos - 1) & sFunctionResult & Mid(S, NextFunctionPos.StartPos + Len(sParameters) + Len(NextFunctionPos.FunctionName), Len(S))
        
        NextFunctionPos = NextFunctionPosition(S)
    Loop
    
    
    If isForAvariable = True Then
        S = "= " & S
    End If
    
    Convert_Functions = S


End Function

Public Function RunFunction(ByVal sFunctionName As String, ByVal sParameters As String, ConsoleID As Integer) As String
    
    
    sParameters = RemoveSurroundingBrackets(sParameters)
    
'    'failsafe
'    If InStr(Mid(sParameters, 1, 3), "(") > 0 Then
'        sParameters = Trim(Mid(sParameters, InStr(sParameters, "(") + 1, Len(sParameters)))
'    End If

    
    Select Case i(sFunctionName)
        'IMPORTANT!!!!!!!!!!!!!!!
        'make sure you also add new functions to the other list (the array!)
        Case "chr": RunFunction = f_Chr(sParameters)
        Case "asc": RunFunction = f_Asc(sParameters)
        Case "lcase": RunFunction = f_LCase(sParameters)
        Case "ucase": RunFunction = f_UCase(sParameters)
        Case "len": RunFunction = Len(sParameters)
        Case "left": RunFunction = f_Left(sParameters)
        Case "right": RunFunction = f_Right(sParameters)
        Case "mid": RunFunction = f_Mid(sParameters)
        Case "reverse": f_Reverse (sParameters)
        Case "random": RunFunction = f_Random(sParameters)
        Case "randomtext": RunFunction = f_RandomText(sParameters)
        Case "instr": RunFunction = f_Instr(sParameters)
        Case "replace": RunFunction = f_Replace(sParameters)
        Case "trim": RunFunction = Trim(sParameters)
        Case "killquotes": RunFunction = f_KillQuotes(sParameters)
        Case "fixquotes": RunFunction = f_FixQuotes(sParameters)
        Case "file": RunFunction = f_File(sParameters, ConsoleID)
        Case "run": RunFunction = f_Run(sParameters, ConsoleID)
        Case "fileexists": RunFunction = f_FileExists(sParameters, ConsoleID)
        Case "direxists": RunFunction = f_DirExists(sParameters, ConsoleID)
        'IMPORTANT!!!!!!!!!!!!!!!
        'make sure you also add new functions to the other list (the array!)
    End Select
    
End Function

Public Function NextFunctionPosition(ByVal S As String) As NextFunction
    Dim n As Integer
    Dim iPos As Long
    Dim sFind As String
    S = i(S)
    
    NextFunctionPosition.StartPos = 99999
    
    For n = 1 To UBound(FunctionList)
        sFind = FunctionList(n) & "("
        If Trim(FunctionList(n)) <> "" Then
            iPos = InStr(S, sFind)
            If iPos <> 0 Then
                'the string exists
                If iPos < NextFunctionPosition.StartPos Then
                    NextFunctionPosition.StartPos = iPos
                    NextFunctionPosition.FunctionName = FunctionList(n)
                End If
            End If
        End If
    Next n
    
    
    If NextFunctionPosition.StartPos = 99999 Then
        NextFunctionPosition.StartPos = 0
        NextFunctionPosition.FunctionName = ""
    End If
    
End Function



Public Sub LoadFunctionArray()
    'make sure these are all lower case
    'make sure these are all lower case
    'make sure these are all lower case

    
    FunctionList(1) = "chr"
    FunctionList(2) = "asc"
    FunctionList(3) = "lcase"
    FunctionList(5) = "ucase"
    FunctionList(6) = "len"
    FunctionList(7) = "left"
    FunctionList(8) = "right"
    FunctionList(9) = "mid"
    FunctionList(10) = "reverse"
    FunctionList(11) = "random"
    FunctionList(12) = "instr"
    FunctionList(13) = "replace"
    FunctionList(14) = "trim"
    FunctionList(15) = "killquotes"
    FunctionList(16) = "fixquotes"
    FunctionList(17) = "file"
    FunctionList(18) = "run"
    FunctionList(19) = "fileexists"
    FunctionList(20) = "direxists"
    FunctionList(21) = "randomtext"
    FunctionList(22) = ""
    FunctionList(23) = ""
    FunctionList(24) = ""
    
End Sub

Public Function f_Run(ByVal S As String, ConsoleID As Integer) As String
    On Error GoTo zxc
    Dim tmpLine As ConsoleLine
    ' Add stuff here to detect various bad functions, and prompt user to allow or deny action.
    S = Trim(S)
    tmpLine.Caption = S
    
    'If InStr(s, "CHATSEND ") > 0 Then GoTo zxc
    If InStr(LimitedCommandString, ":" & i(S) & ":") > 0 Then GoTo zxc

    Data_For_Run_Function_Enabled(ConsoleID) = 1
    Data_For_Run_Function(ConsoleID) = ""
    Run_Command tmpLine, ConsoleID, False
    Data_For_Run_Function_Enabled(ConsoleID) = 0
    
    If Left(Data_For_Run_Function(ConsoleID), 2) = vbCrLf Then
        Data_For_Run_Function(ConsoleID) = Mid(Data_For_Run_Function(ConsoleID), 3, Len(Data_For_Run_Function(ConsoleID)))
    End If
    
    f_Run = Data_For_Run_Function(ConsoleID)
    Data_For_Run_Function(ConsoleID) = ""
    
    
    
Exit Function
zxc:
    f_Run = "*RUN-ERROR*"
End Function


Public Function f_File(ByVal S As String, ConsoleID As Integer) As String
    'MsgBox s
    'filename, start line, max lines
    S = Trim(Replace(S, ",", " "))
    
    If InStr(S, " ") = 0 Then GoTo zxc
    
    Dim sFile As String
    Dim sStart As Long
    Dim sLinesToGet As Long
    
    sFile = Trim(fixPath(Mid(S, 1, InStr(S, " ")), ConsoleID))
    S = Trim(Mid(S, InStr(S, " "), Len(S)))

    
    If InStr(S, " ") = 0 Then
        sStart = Val(S)
        sLinesToGet = 29999
    Else
        sStart = Val(Mid(S, 1, InStr(S, " ")))
        sLinesToGet = Val(Trim(Mid(S, InStr(S, " "), Len(S))))
    End If
    
    

    If FileExists(App.Path & "\user" & sFile) = False Then
        GoTo zxc
        Exit Function
    End If
    
    Dim FF As Long, CLine As Integer, CLinePrinted As Integer, tmpJuice As String, tmpS As String
    FF = FreeFile
    
    Open App.Path & "\user" & sFile For Input As #FF
        Do Until EOF(FF)
            Line Input #FF, tmpS
            CLine = CLine + 1
            
            If CLine >= sStart Then
                If CLinePrinted < sLinesToGet Then
                    If Trim(tmpS) <> "" Then
                        tmpJuice = tmpJuice & vbCrLf & tmpS
                        CLinePrinted = CLinePrinted + 1
                    End If
                End If
            End If
        Loop
    Close #FF
    
    f_File = Mid(tmpJuice, 3, Len(tmpJuice))
    
       
    
Exit Function
zxc:
    f_File = "*FILE-ERROR*"
End Function

Public Function f_KillQuotes(ByVal S As String) As String
    f_KillQuotes = Replace(S, Chr(34), "")
End Function

Public Function f_FileExists(ByVal S As String, ByVal ConsoleID As Integer) As String
    S = Trim(S)
    S = fixPath(S, ConsoleID)
    
    If FileExists(App.Path & "\user" & S) = True Then
        f_FileExists = "1"
    Else
        f_FileExists = "0"
    End If
End Function


Public Function f_DirExists(ByVal S As String, ByVal ConsoleID As Integer) As String
    S = Trim(S)
    S = fixPath(S, ConsoleID)
    
    If DirExists(App.Path & "\user" & S) = True Then
        f_DirExists = "1"
    Else
        f_DirExists = "0"
    End If
End Function


Public Function f_FixQuotes(ByVal S As String) As String
    f_FixQuotes = Replace(S, Chr(34), "'")
End Function


Public Function f_Replace(ByVal S As String) As String
    
    On Error GoTo zxc
    
'  MsgBox s
S = ReverseString(S)

     
    S = Trim(S)
    If Mid(S, 1, 1) <> Chr(34) Then GoTo zxc
    S = Mid(S, 2, Len(S))
    Dim s1 As String, s2 As String, s3 As String
    If InStr(S, Chr(34)) = 0 Then GoTo zxc
    
    s1 = Mid(S, 1, InStr(S, Chr(34)) - 1)
    S = Mid(S, Len(s1), Len(S))
    
 
    
    If InStr(S, Chr(34)) = 0 Then GoTo zxc
    S = Trim(Mid(S, InStr(S, Chr(34)) + 1, Len(S)))
    
   
    If Mid(S, 1, 1) = Chr(34) Then S = Mid(S, 2, Len(S))
    If Mid(S, 1, 1) = "," Then S = Mid(S, 2, Len(S))
    S = Trim(S)
    If Mid(S, 1, 1) = Chr(34) Then S = Mid(S, 2, Len(S))
    If Mid(S, 1, 1) = "," Then S = Mid(S, 2, Len(S))
     
    
     
    s2 = Mid(S, 1, InStr(S, Chr(34)) - 1)
    
    S = Trim(Mid(S, InStr(S, Chr(34)) + 1, Len(S)))
    
    If Mid(S, 1, 1) = Chr(34) Then S = Mid(S, 2, Len(S))
    If Mid(S, 1, 1) = "," Then S = Mid(S, 2, Len(S))
    S = Trim(S)
    If Mid(S, 1, 1) = Chr(34) Then S = Mid(S, 2, Len(S))
    If Mid(S, 1, 1) = "," Then S = Mid(S, 2, Len(S))
    
    s3 = Replace(S, Chr(34), "")
    
    

    'MsgBux s & vbCrLf & "-" & s1 & "-" & vbCrLf & "-" & s2 & "-" & vbCrLf & "-" & s3 & "-"
    
    s1 = ReverseString(s1)
    s2 = ReverseString(s2)
    s3 = ReverseString(s3)
    
    
    f_Replace = Replace(s3, s2, s1)
     
Exit Function
zxc:
    f_Replace = "*REPLACE-USE-DOUBLE-QUOTES-ERROR*"
End Function


Public Function f_Instr(ByVal S As String) As String
    
    On Error GoTo zxc
    S = Trim(S)
     
    If Mid(S, 1, 1) <> Chr(34) Then GoTo zxc
    S = Mid(S, 2, Len(S))
    
    Dim s1 As String, s2 As String
    If InStr(S, Chr(34)) = 0 Then GoTo zxc
    
    s1 = Mid(S, 1, InStr(S, Chr(34)) - 1)
    
    S = Mid(S, Len(s1), Len(S))
    If InStr(S, Chr(34)) = 0 Then GoTo zxc
    
    S = Trim(Mid(S, InStr(S, Chr(34)) + 1, Len(S)))
    If Mid(S, 1, 1) = Chr(34) Then S = Mid(S, 2, Len(S))
    If Mid(S, 1, 1) = "," Then S = Mid(S, 2, Len(S))
    S = Trim(S)
    If Mid(S, 1, 1) = Chr(34) Then S = Mid(S, 2, Len(S))
    If Mid(S, 1, 1) = "," Then S = Mid(S, 2, Len(S))
     
    s2 = Replace(S, Chr(34), "")
    
    
    f_Instr = InStr(LCase(s1), LCase(s2))
     
     
Exit Function
zxc:
    f_Instr = "*INSTR-USE-DOUBLE-QUOTES-ERROR*"
End Function



Public Function f_Mid(ByVal S As String) As String
    Dim tmpLen As String, tmpStart As String
    

    'On Error GoTo zxc
    

    tmpLen = Trim(ReverseString(Replace(S, ",", " ")))

'    MsgBox tmpLen

    If InStr(tmpLen, " ") = 0 Then GoTo zxc
    tmpLen = ReverseString(Trim(Mid(tmpLen, 1, InStr(tmpLen, " "))))
    S = Mid(S, 1, Len(S) - Len(tmpLen) - 1)
    If Right(S, 1) = " " Then S = Mid(S, 1, Len(S) - 1)
    
    
    tmpStart = Trim(ReverseString(Replace(S, ",", " ")))
    If InStr(tmpStart, " ") = 0 Then GoTo zxc
    tmpStart = ReverseString(Trim(Mid(tmpStart, 1, InStr(tmpStart, " "))))
    S = Mid(S, 1, Len(S) - Len(tmpStart) - 1)
    If Right(S, 1) = " " Then S = Mid(S, 1, Len(S) - 1)
    
    f_Mid = Mid(S, Val(tmpStart), Val(tmpLen))
     
     
     
Exit Function
zxc:
    f_Mid = "*MID-ERROR*"
End Function

Public Function f_Right(ByVal S As String) As String
    Dim tmpS As String
    On Error GoTo zxc
    
    tmpS = Trim(ReverseString(Replace(S, ",", " ")))
    tmpS = Trim(ReverseString(Replace(S, "  ", " "))) ' added space support
    If InStr(tmpS, " ") = 0 Then GoTo zxc
    
    tmpS = ReverseString(Trim(Mid(tmpS, 1, InStr(tmpS, " "))))
    
    's = Mid(s, 1, Len(s) - Len(tmpS) - 1) This is the old var, hope I fixed it right (bigbob85)
    S = Mid(S, 1, Len(S) - Len(tmpS) - 2)
    If Right(S, 1) = " " Then S = Mid(S, 1, Len(S) - 1)
    
    f_Right = Right(S, Val(tmpS))
     
Exit Function
zxc:
    f_Right = "*RIGHT-ERROR*"
End Function


Public Function f_Reverse(ByVal S As String) As String
    
    On Error GoTo zxc
    
    If i(S) = "true" Then
        f_Reverse = "False"
        
    ElseIf i(S) = "false" Then
        f_Reverse = "True"

    ElseIf i(S) = "0" Then
        f_Reverse = "1"
        
    ElseIf i(S) = "1" Then
        f_Reverse = "0"
        
    Else
        f_Reverse = ReverseString(S)
    End If
    
    
     
Exit Function
zxc:
    f_Reverse = "*REVERSE-ERROR*"
End Function

Public Function f_Random(ByVal S As String) As String
    
    On Error GoTo zxc
    
    S = Trim(S)
    S = Replace(S, ",", " ")
    S = Replace(S, "  ", " ") ' add in case of space after comma
    
    If InStr(S, " ") = 0 Then GoTo zxc
    If InStr(S, "%") <> 0 Then GoTo zxc ' added to prevent crash
    
        
    
    
    Dim s1 As String, s2 As String
    Dim iDiff As Long
    
    s1 = Trim(Mid(S, 1, InStr(S, " ")))
    s2 = Trim(Mid(S, InStr(S, " "), Len(S)))
    If Val(s2) < Val(s1) Then GoTo zxc 's2 must be more than s1
    
    iDiff = (Val(s2) - Val(s1)) + 1
    
    Randomize
    f_Random = Trim(Str(Int(Rnd * iDiff) + Val(s1)))
       
    
     
Exit Function
zxc:
    f_Random = "*RANDOM-ERROR*"
End Function

Public Function f_RandomText(ByVal S As String) As String
    
    On Error GoTo zxc
    
    S = Trim(S)

    
    Dim n As Long, tmpS As String, rndInt As Integer
    
    If Val(S) < 1 Then S = "1"
    
    For n = 1 To Val(S)
        Randomize
        rndInt = Int(Rnd * 62)
        
        If rndInt < 26 Then
        
            'it's upper case
            tmpS = tmpS & Chr(rndInt + 65)
            
        ElseIf rndInt > 25 And rndInt < 52 Then
        
            'it's lower case
            rndInt = rndInt - 26
            tmpS = tmpS & Chr(rndInt + 97)
        
        Else
            'its a number
            Select Case rndInt
                Case 52: tmpS = tmpS & "0"
                Case 53: tmpS = tmpS & "1"
                Case 54: tmpS = tmpS & "2"
                Case 55: tmpS = tmpS & "3"
                Case 56: tmpS = tmpS & "4"
                Case 57: tmpS = tmpS & "5"
                Case 58: tmpS = tmpS & "6"
                Case 59: tmpS = tmpS & "7"
                Case 60: tmpS = tmpS & "8"
                Case 61: tmpS = tmpS & "9"
            End Select
            
        End If
        
    Next n
    


    f_RandomText = tmpS
       
    
     
Exit Function
zxc:
    f_RandomText = "*RANDOMTEXT-ERROR*"
End Function

Public Function f_Left(ByVal S As String) As String
    Dim tmpS As String
    On Error GoTo zxc
    
    tmpS = Trim(ReverseString(Replace(S, ",", " ")))
    If InStr(tmpS, " ") = 0 Then GoTo zxc
    
    tmpS = ReverseString(Trim(Mid(tmpS, 1, InStr(tmpS, " "))))
    S = Mid(S, 1, Len(S) - Len(tmpS) - 1)
    If Right(S, 1) = " " Then S = Mid(S, 1, Len(S) - 1)
    
    f_Left = Left(S, Val(tmpS))
    
    
Exit Function
zxc:
    f_Left = "*LEFT-ERROR*"
End Function

Public Function f_UCase(ByVal S As String) As String
    On Error GoTo zxc
    
    f_UCase = UCase(S)
Exit Function
zxc:
    f_UCase = "*UCASE-ERROR*"
End Function

Public Function f_LCase(ByVal S As String) As String
    On Error GoTo zxc
    
    f_LCase = LCase(S)
Exit Function
zxc:
    f_LCase = "*LCASE-ERROR*"
End Function

Public Function f_Chr(ByVal S As String) As String
    On Error GoTo zxc
    
    f_Chr = Chr(Val(S))
Exit Function
zxc:
    f_Chr = "*CHR-ERROR*"
End Function

Public Function f_Len(ByVal S As String) As String
    On Error GoTo zxc
    
    f_Len = Trim(Str(Len(S)))
Exit Function
zxc:
    f_Len = "*LEN-ERROR*"
End Function


Public Function f_Asc(ByVal S As String) As String
    On Error GoTo zxc
    f_Asc = Asc(Trim(S))
Exit Function
zxc:
    f_Asc = "*ASC-ERROR*"
End Function


Public Function Has_Functions(ByVal S As String) As Boolean

    If InStr(S, "(") > 0 And InStr(S, ")") > 0 Then
        Has_Functions = True
    Else
        Has_Functions = False
    End If
End Function

Public Function Msgbux(ByVal S As String)
    frmConsole.List1.AddItem S, 0
End Function

Public Function Pipe_Commands(ByVal S As String, ByVal ConsoleID As Integer)
    Dim n As Integer, tmpS As String
    
    Dim CLine As ConsoleLine
    CLine = Console_Line_Defaults
    
    For n = 1 To 10
        tmpS = Trim(GetPart(S, n, "|"))
        
        If tmpS <> "" Then
            CLine.Caption = tmpS
            Run_Command CLine, ConsoleID
        End If
    Next n
End Function

Public Function CompareIF(ByVal s1 As String, ByVal s2 As String, ByVal sOperator As String, ByVal ConsoleID As Integer) As Boolean
    
    s1 = ReplaceVariables(s1, ConsoleID)
    s2 = ReplaceVariables(s2, ConsoleID)
    
    s1 = RemoveSurroundingQuotes(s1)
    s2 = RemoveSurroundingQuotes(s2)
    
    'compare without new lines! - saves people trouble
    s1 = Replace(s1, vbCrLf, "")
    s1 = Replace(s1, vbCr, "")
    s1 = Replace(s1, vbLf, "")
    s2 = Replace(s2, vbCrLf, "")
    s2 = Replace(s2, vbCr, "")
    s2 = Replace(s2, vbLf, "")
    
    
    
    Select Case Trim(sOperator)
    
    Case "=":
        If i(s1) = i(s2) Then
            CompareIF = True
        Else
            CompareIF = False
        End If
        Exit Function
            
    
    Case "!":
        If i(s1) = i(s2) Then
            CompareIF = False
        Else
            CompareIF = True
        End If
        Exit Function
        
    Case ">=":
        If Val(s1) >= Val(s2) Then
            CompareIF = True
        Else
            CompareIF = False
        End If
        Exit Function
    
    Case "<=":
        If Val(s1) <= Val(s2) Then
            CompareIF = True
        Else
            CompareIF = False
        End If
        Exit Function
    
    Case ">":
        If Val(s1) > Val(s2) Then
            CompareIF = True
        Else
            CompareIF = False
        End If
        Exit Function
                
    Case "<":
        If Val(s1) < Val(s2) Then
            CompareIF = True
        Else
            CompareIF = False
        End If
        Exit Function
    
                
    Case "^": 'contains
        If InStr(i(s1), i(s2)) > 0 Then
            CompareIF = True
        Else
            CompareIF = False
        End If
        Exit Function
    
                    
    Case "~": 'doesn't contain
        If InStr(i(s1), i(s2)) = 0 Then
            CompareIF = True
        Else
            CompareIF = False
        End If
        Exit Function
    
    End Select
    
End Function

Public Sub ScriptError(ByVal qTmp As String, sCommand As String, scriptSource As String, LineNumber As Integer, ByVal ConsoleID As Integer)
    
    qTmp = " * Warning * > " & Trim(qTmp) & " in " & _
    IU(FileTitleOnly(scriptSource)) & " > Line " & _
    Trim(Str(LineNumber)) & " > " & sCommand
    
    SayError qTmp, ConsoleID
    
End Sub


Public Function GetOperator(ByVal S As String) As String



    GetOperator = ""
    
    'not equal
    If InStr(S, "!") > 0 Then GetOperator = "!": Exit Function
    
    'greater than or equals to
    If InStr(S, ">=") > 0 Then GetOperator = ">=": Exit Function
    
    'less than or equals to
    If InStr(S, "<=") > 0 Then GetOperator = "<=": Exit Function
    
    'greater than
    If InStr(S, ">") > 0 Then GetOperator = ">": Exit Function
    
    'less than
    If InStr(S, "<") > 0 Then GetOperator = "<": Exit Function
    
   
    'equals
    If InStr(S, "=") > 0 Then GetOperator = "=": Exit Function
    
    'contains
    If InStr(S, "^") > 0 Then GetOperator = "^": Exit Function

    'doesn't contain
    If InStr(S, "~") > 0 Then GetOperator = "~": Exit Function
    

End Function

Public Function Mask(ByVal S As String) As String
    Dim inQuotes As Boolean
    Dim tmpS As String
    inQuotes = False
    
    Dim n As Integer
    For n = 1 To Len(S)
        
        If Mid(S, n, 1) = Chr(34) Then inQuotes = Not (inQuotes)
        
        If inQuotes = True Then
            If Mid(S, n, 1) = "=" Then
                tmpS = tmpS & Chr(240)
            ElseIf Mid(S, n, 1) = ">" Then
                tmpS = tmpS & Chr(241)
            ElseIf Mid(S, n, 1) = "<" Then
                tmpS = tmpS & Chr(242)
            ElseIf Mid(S, n, 1) = "^" Then
                tmpS = tmpS & Chr(243)
            ElseIf Mid(S, n, 1) = "~" Then
                tmpS = tmpS & Chr(244)
            ElseIf Mid(S, n, 1) = ">=" Then
                tmpS = tmpS & Chr(245)
            ElseIf Mid(S, n, 1) = "<=" Then
                tmpS = tmpS & Chr(246)
            Else
                tmpS = tmpS & Mid(S, n, 1)
            End If
        Else
            tmpS = tmpS & Mid(S, n, 1)
        End If
        
    Next n
    
    Mask = tmpS
    
End Function

Public Function UnMask(ByVal S As String) As String
    
    S = Replace(S, Chr(240), "=")
    S = Replace(S, Chr(241), ">")
    S = Replace(S, Chr(242), "<")
    S = Replace(S, Chr(243), "^")
    S = Replace(S, Chr(244), "~")
    S = Replace(S, Chr(245), ">=")
    S = Replace(S, Chr(246), "<=")
    
    
    UnMask = S
End Function


Public Function SumUp(sValue As String, ByVal ConsoleID As Integer) As String
    
    SumUp = sValue

    If InStr(SumUp, "*") > 0 Or InStr(SumUp, "-") > 0 Or InStr(SumUp, "^") > 0 Or _
        InStr(SumUp, "/") > 0 Or InStr(SumUp, "+") > 0 Or InStr(SumUp, "%") > 0 Then
        SumUp = ReplaceVariables(SumUp, ConsoleID)
        If IsNumeric(Mid(SumUp, 1, NextEmptyOperator(SumUp) - 1)) Or Val(SumUp) < 0 Then
            SumUp = Trim(Str(sumProcess(SumUp)))
        End If
    End If
End Function

Public Function KillOps(S As String) As String
    KillOps = S
    KillOps = Replace(KillOps, "+", "")
    KillOps = Replace(KillOps, "-", "")
    KillOps = Replace(KillOps, "/", "")
    KillOps = Replace(KillOps, "*", "")
    KillOps = Replace(KillOps, "^", "")
    KillOps = Replace(KillOps, "%", "")
End Function


Public Function NextEmptyOperator(S As String) As Long
    NextEmptyOperator = 9999

    If InStr(S, "*") Then NextEmptyOperator = InStr(S, "*")
    
    If InStr(S, "+") And InStr(S, "+") < NextEmptyOperator Then
        NextEmptyOperator = InStr(S, "+")
    End If

    If InStr(S, "-") And InStr(S, "-") < NextEmptyOperator Then
        NextEmptyOperator = InStr(S, "-")
    End If

    If InStr(S, "/") And InStr(S, "/") < NextEmptyOperator Then
        NextEmptyOperator = InStr(S, "/")
    End If
    
    If InStr(S, "^") And InStr(S, "^") < NextEmptyOperator Then
        NextEmptyOperator = InStr(S, "^")
    End If
        
    If InStr(S, "%") And InStr(S, "%") < NextEmptyOperator Then
        NextEmptyOperator = InStr(S, "%")
    End If
    
    
    
    
    If NextEmptyOperator = 9999 Then NextEmptyOperator = 0
End Function

Public Function Bracketize(ByVal S As String, ReplaceLoosely As Boolean) As String
    Dim n As Long
    Dim BracketValue As Integer
    Dim tmpS As String, midString As String * 1
    
    If Len(S) > 32096 Then 'no more than 32kb - way too slow!
        SayCOMM "Warning: Processing large data may take a while... (" & FormatKB(Len(S)) & ")"
        DoEvents
        'Bracketize = s
        'Exit Function
    End If
    
    For n = 1 To Len(S)
    
        midString = Mid(S, n, 1)
    
        If midString = "(" Then
            BracketValue = BracketValue + 1
            
            If ReplaceLoosely = True Then
                tmpS = tmpS & "[{["
                GoTo NextOne
            Else
                If BracketValue > 1 Then
                    tmpS = tmpS & "[{["
                    GoTo NextOne
                End If
            End If
            
        End If
        
        If midString = ")" Then
            BracketValue = BracketValue - 1
            
            If ReplaceLoosely = True Then
                tmpS = tmpS & "]}]"
                GoTo NextOne
            Else
                If BracketValue > 0 Then
                    tmpS = tmpS & "]}]"
                    GoTo NextOne
                End If
            End If
            
            
        End If
        
        tmpS = tmpS & midString
        
NextOne:
    Next n
    
    Bracketize = tmpS
End Function

Public Function MaskSpacesInQuotes(ByVal S As String) As String
    Dim n As Long, tmpS As String
    Dim inQuotes As Boolean
    inQuotes = False
    
    For n = 1 To Len(S)
        If Mid(S, n, 1) = Chr(34) Then
            inQuotes = Not (inQuotes)
        End If
        
        If Mid(S, n, 1) = " " Then
            If inQuotes = True Then
                tmpS = tmpS & Chr(240)
            Else
                tmpS = tmpS & Mid(S, n, 1)
            End If
        Else
            tmpS = tmpS & Mid(S, n, 1)
        End If
    Next n
    
    MaskSpacesInQuotes = tmpS
End Function

Public Function MaskCharInQuotes(ByVal S As String, sCharToMask As String) As String
    Dim n As Long, tmpS As String
    Dim inQuotes As Boolean
    inQuotes = False
    
    For n = 1 To Len(S)
        If Mid(S, n, 1) = Chr(34) Then
            inQuotes = Not (inQuotes)
        End If
        
        If Mid(S, n, 1) = sCharToMask Then
            If inQuotes = True Then
                tmpS = tmpS & Chr(240)
            Else
                tmpS = tmpS & Mid(S, n, 1)
            End If
        Else
            tmpS = tmpS & Mid(S, n, 1)
        End If
    Next n
    
    MaskCharInQuotes = tmpS
End Function

Public Function UnBracketize(ByVal S As String) As String
    S = Replace(S, "[{[", "(")
    S = Replace(S, "]}]", ")")
    UnBracketize = S
End Function

Public Function RemoveSurroundingQuotes(ByVal S As String) As String
    S = Trim(S)
    
    If Right(S, 1) = Chr(34) And Left(S, 1) = Chr(34) Then
        S = Mid(S, 2, Len(S) - 2)
    End If
    
    RemoveSurroundingQuotes = S
End Function

Public Function RemoveSurroundingBrackets(ByVal S As String) As String
    S = Trim(S)
    
    If Right(S, 1) = ")" And Left(S, 1) = "(" Then
        S = Mid(S, 2, Len(S) - 2)
    End If
    
    If Mid(S, 1, 1) = "(" Then S = Mid(S, 2, Len(S))
    
    RemoveSurroundingBrackets = S
End Function

Public Function ConvertToNumbers(ByVal S As String) As String
    Dim n As Long, tChr As Integer
    
    For n = 1 To Len(S)
        tChr = Asc(Mid(S, n, 1))
        If tChr > 47 Then
            If tChr < 127 Then
                'ConvertToNumbers = ConvertToNumbers & tChr & "-"
                ConvertToNumbers = ConvertToNumbers & tChr
            End If
        End If
    Next n
End Function

Public Function DeleteAFile(sFile As String)
    On Error Resume Next
    Kill sFile
End Function
