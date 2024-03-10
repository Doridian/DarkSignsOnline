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
    s As String
End Type

Public Type NextFunction
    StartPos As Long
    FunctionName As String
End Type

Public Function Run_Script(filename As String, ByVal consoleID As Integer, ScriptParameters As String, ScriptFrom As String)
    cPrefix(5) = cPrefix(consoleID)
    Dim OldPath As String
    OldPath = cPath(consoleID)
    
    If cPrefix(consoleID) <> "" Then
     cPath(consoleID) = "\"
    End If

    If Right(Trim(filename), 1) = ">" Then Exit Function
    If Trim(filename) = "." Or Trim(filename) = ".." Then Exit Function
    If InStr(filename, Chr(34) & Chr(34)) Then Exit Function
    
    DoEvents
    CancelScript(consoleID) = False
    
    Dim sParams() As String, n As Integer, n2 As Integer
    ScriptParameters = Trim(ScriptParameters)
    
    Dim args As Integer
    args = 0
    
        'for $1, $2, $3, etc
        ScriptParameters = Trim(MaskSpacesInQuotes(ScriptParameters))
        sParams = Split(ScriptParameters & "       ")
        For n = 0 To UBound(sParams)
            sParams(n) = Trim(Replace(sParams(n), Chr(240), " "))
            sParams(n) = RemoveSurroundingQuotes(sParams(n))
            If sParams(n) <> "" Then args = args + 1
        Next n
             
        

    Dim WaitForVariables() As String, WaitN As Integer, VarIndex As Integer
    
    Dim GotoEnabled As Boolean: GotoEnabled = False
    Dim GotoString As String
    
    Dim ForEnabled As Boolean: ForEnabled = False
    Dim ForLine As String
    Dim ForStart As Long: ForStart = 1
    Dim ForEnd As Long: ForEnd = 5
    Dim ForStep As Long: ForStep = 1
    Dim ForVariable As String
    Dim ForVariableIndex As Integer
    Dim ForStartLine As Integer
    
    Dim IFIndex As Integer
    Dim IFa(1 To 19) As String
    Dim IFb(1 To 19) As String
    Dim IFOperator(1 To 19) As String
    Dim IFTrue(1 To 19) As Boolean
    Dim IFHasBeenTrue(1 To 19) As Boolean
    Dim qTmp As String
    
    For n = 1 To UBound(IFHasBeenTrue)
        IFHasBeenTrue(n) = False
    Next n

    Dim ShortFileName As String
    'file name should be from local dir, i.e: \system\startup.ds
    ShortFileName = filename
    filename = App.Path & "\user" & filename
    'make sure it is not a directory
    If DirExists(filename) = True Then Exit Function
    
    If FileExists(filename) = False Then
        SayComm "File Not Found": Exit Function
    End If
    
    
    Dim Script(1 To 9999) As String, EncryptedScript() As String, FF As Long, MaxLines As Integer, tmpS As String, tmpS2 As String
    FF = FreeFile
    

        Open filename For Input As #FF
            Do Until EOF(FF)
                Line Input #FF, tmpS
                tmpS = Trim(tmpS)
                tmpS = Replace(tmpS, "$referal", ScriptFrom)
                tmpS = Replace(tmpS, "$args", args)
                'replace $1, $2, $3, etc, with the passed parameter values
                For n = 1 To 19
                    If UBound(sParams) >= n Then

                        ' Added to prevent crash bug with ^< on a single line.
                        If InStr(tmpS, "^<") = 1 Then tmpS = Replace(tmpS, "^<", "^ <")
                        
                        If Left(tmpS, 1) = "^" And IsNumeric(Mid(tmpS, 2, Len(tmpS))) = True Then
                            tmpS = Mid(tmpS, 2, Len(tmpS))
                            tmpS = DSODecode(tmpS)
                            tmpS = Replace(tmpS, "$" & Trim(str(n)), sParams(n - 1))
                            tmpS = Replace(tmpS, "$p" & Trim(str(n)), sParams(n - 1))
                            tmpS = "^" & DSOEncode(tmpS)
                        Else
                            tmpS = Replace(tmpS, "$" & Trim(str(n)), sParams(n - 1))
                            tmpS = Replace(tmpS, "$p" & Trim(str(n)), sParams(n - 1))
                        End If
                        
                        
                    End If
                    
                Next n
    
                tmpS = Replace(tmpS, Chr(9), "") 'replace TABS in case code is indented
                If tmpS <> "" Then
                    MaxLines = MaxLines + 1: Script(MaxLines) = tmpS
                End If
            Loop
        Close #FF

    DeleteAFile App.Path & "\user\system\temp.dat"
    
    Dim myLine As ConsoleLine
    
    For n = 1 To MaxLines
Beginning:

        Do
            If CancelScript(consoleID) = True Then GoTo ScriptCancelled
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        Loop Until frmConsole.tmrWait(consoleID).Enabled = False

        
        myLine = Console_Line_Defaults
        myLine.Caption = Trim(Script(n))
        
        If Left(myLine.Caption, 1) = "^" Then
            If IsNumeric(Mid(myLine.Caption, 2, Len(myLine.Caption))) = True Then
                'decode the line, if it is marked with ^, it is encoded
                myLine.Caption = Mid(myLine.Caption, 2, Len(myLine.Caption))
                myLine.Caption = DSODecode(myLine.Caption)
            Else
                myLine.Caption = Mid(myLine.Caption, 2, Len(myLine.Caption))
            End If
        End If
        
        
        
        'is it a comment?
        tmpS = Mid(Trim(myLine.Caption), 1, 1)
        If tmpS = "'" Or tmpS = "/" Or tmpS = "\" Then GoTo NextLine
        
        'kill illegal chars if its not an IF statement
        'myLine.Caption = Replace(myLine.Caption, ">", "-")
        
        tmpS = myLine.Caption
        
        
        ScriptLog tmpS, n
        
        
  
        
            '------------------------------------------------------------
            'FOR LOOPS
            If ForEnabled = True Then
                If n < ForStartLine Then GoTo NextLine
                If Mid(i(tmpS), 1, 4) = "next" Then
                    tmpS = i(Replace(i(tmpS), "next", ""))
                    'If tmpS <> I(Variables(ForVariableIndex, 1)) Then GoTo NextLine
                    Vars(ForVariableIndex).VarValue = Val(Vars(ForVariableIndex).VarValue) + ForStep
                    
                    If ForStep > 0 And Val(Vars(ForVariableIndex).VarValue) > ForEnd Then
                        ForEnabled = False
                        GoTo NextLine
                    ElseIf ForStep < 0 And Val(Vars(ForVariableIndex).VarValue) < ForEnd Then
                        ForEnabled = False
                        GoTo NextLine
                    Else
                        n = 1
                        GoTo Beginning
                    End If
                    
                End If
            End If
            If Mid(i(tmpS), 1, 4) = "for " Then
                
                'start a FOR loop'---------------???????????
                'If GotoEnabled = True Then
                '    ForEnabled = True
                '    GoTo NextLine
                'End If


                If ForLine = i(tmpS) Then GoTo NextLine

                ForLine = i(tmpS)
                tmpS = Trim(Replace(tmpS, "for ", "")): tmpS = Trim(Replace(tmpS, "FOR ", "")): tmpS = Trim(Replace(tmpS, "For ", ""))
                If InStr(tmpS, "=") = 0 Then GoTo NextLine
                
                
                tmpS = Replace(tmpS, " TO ", " to "): tmpS = Replace(tmpS, " To ", " to "): tmpS = Replace(tmpS, " tO ", " to ")
                If InStr(tmpS, " to ") = 0 Then GoTo NextLine

                ForVariable = Trim(Mid(tmpS, 1, InStr(tmpS, "=") - 1))
                
                tmpS = i(Mid(tmpS, InStr(tmpS, "=") + 1, Len(tmpS)))
                    
                    If InStr(tmpS, "step") > 0 Then
                        ForStep = Val(Trim(Mid(tmpS, InStr(tmpS, "step") + 4, Len(tmpS))))
                        tmpS = i(Mid(tmpS, 1, InStr(tmpS, "step") - 2))
                    Else: ForStep = 1
                    End If
                

                ForStart = Val(ReplaceVariables(Mid(tmpS, 1, InStr(tmpS, "to") - 1), consoleID))
                ForEnd = Val(ReplaceVariables(Mid(tmpS, InStr(tmpS, "to") + 2, Len(tmpS)), consoleID))
                
               
                
                'If ForStart > ForEnd Then GoTo NextLine
                ForVariableIndex = VariableIndex(ForVariable)
                
                If ForVariableIndex = 0 Then
                    SetVariable ForVariable, "= " & ForStart, consoleID
                    ForVariableIndex = VariableIndex(ForVariable)
                Else
                    Vars(ForVariableIndex).VarValue = ForStart
                End If

                ForStartLine = n
                ForEnabled = True
                n = 1
                GoTo Beginning
            End If
            '------------------------------------------------------------
            
            
            
            '------------------------------------------------------------
            'IF STATEMENTS
            
            If Mid(i(tmpS), 1, 3) = "if " Then
                IFIndex = IFIndex + 1
                IFHasBeenTrue(IFIndex) = False
                
                If IFIndex > 1 Then
                    If IFTrue(IFIndex - 1) = False Then
                        GoTo AfterRun
                    End If
                End If

            
                qTmp = Trim(tmpS)
                If Trim(Right(i(qTmp), 5)) = "then" Then qTmp = Trim(Mid(qTmp, 1, Len(qTmp) - 5))
                qTmp = Trim(Mid(qTmp, 3, Len(qTmp)))
                qTmp = Mask(qTmp)
                
               
                IFOperator(IFIndex) = GetOperator(qTmp)

                If IFOperator(IFIndex) = "" Then
                    ScriptError "Invalid Operator in IF Statement", Trim(tmpS), ShortFileName, n, consoleID
                    GoTo AfterRun
                End If
                
                IFa(IFIndex) = Trim(Mid(qTmp, 1, InStr(qTmp, IFOperator(IFIndex)) - 1))
                IFb(IFIndex) = Trim(Mid(qTmp, InStr(qTmp, IFOperator(IFIndex)) + Len(IFOperator(IFIndex)), Len(qTmp)))
                
                IFa(IFIndex) = UnMask(IFa(IFIndex))
                IFb(IFIndex) = UnMask(IFb(IFIndex))
                
                'remove surrounding quotes
                If Right(IFa(IFIndex), 1) = Chr(34) And Left(IFa(IFIndex), 1) = Chr(34) Then IFa(IFIndex) = Replace(IFa(IFIndex), Chr(34), "")
                If Right(IFb(IFIndex), 1) = Chr(34) And Left(IFb(IFIndex), 1) = Chr(34) Then IFb(IFIndex) = Replace(IFb(IFIndex), Chr(34), "")
                
                'qTmp = UnMask(qTmp)
                
                
                
                IFTrue(IFIndex) = CompareIF(IFa(IFIndex), IFb(IFIndex), IFOperator(IFIndex), consoleID)
                
                If IFTrue(IFIndex) = True Then
                    IFHasBeenTrue(IFIndex) = True
                Else
                    IFHasBeenTrue(IFIndex) = False
                End If
                


                GoTo AfterRun
                
            ElseIf Mid(i(tmpS), 1, 7) = "elseif " Or Mid(i(tmpS), 1, 8) = "else if " Then
                
                If IFIndex > 1 Then
                    If IFTrue(IFIndex - 1) = False Then
                        GoTo AfterRun
                    End If
                End If
                
                If IFHasBeenTrue(IFIndex) = True Then
                    IFTrue(IFIndex) = False
                    GoTo AfterRun
                End If
                

                
                qTmp = Trim(tmpS)
                If Trim(Right(i(qTmp), 5)) = "then" Then qTmp = Trim(Mid(qTmp, 1, Len(qTmp) - 5))
                qTmp = Trim(Mid(qTmp, 8, Len(qTmp)))
                qTmp = Mask(qTmp)
                
 
                                
                IFOperator(IFIndex) = GetOperator(qTmp)
                
                
                If IFOperator(IFIndex) = "" Then
                    ScriptError "Invalid Operator in ELSE IF Statement", Trim(tmpS), ShortFileName, n, consoleID
                    GoTo AfterRun
                End If
                IFa(IFIndex) = Trim(Mid(qTmp, 1, InStr(qTmp, IFOperator(IFIndex)) - 1))
                IFb(IFIndex) = Trim(Mid(qTmp, InStr(qTmp, IFOperator(IFIndex)) + 1, Len(qTmp)))
                IFTrue(IFIndex) = CompareIF(IFa(IFIndex), IFb(IFIndex), IFOperator(IFIndex), consoleID)
                

                If IFTrue(IFIndex) = True Then
                    IFHasBeenTrue(IFIndex) = True
                Else
                    IFHasBeenTrue(IFIndex) = False
                End If
                
                GoTo AfterRun
            End If
            
            If Mid(i(tmpS), 1, 5) = "endif" Or Mid(i(tmpS), 1, 6) = "end if" Then
                IFHasBeenTrue(IFIndex) = True
                IFTrue(IFIndex) = False
                IFIndex = IFIndex - 1
                
                If IFIndex < 0 Then
                    ScriptError "END IF detected that is not required or out of order", Trim(tmpS), ShortFileName, n, consoleID
                    IFIndex = 0
                End If
                
                GoTo AfterRun:
            End If
            
            If Mid(i(tmpS), 1, 4) = "else" Then
                            
                If IFIndex > 1 Then
                    If IFTrue(IFIndex - 1) = False Then
                        GoTo AfterRun
                    End If
                End If
                
                If IFHasBeenTrue(IFIndex) = True Then
                    IFTrue(IFIndex) = False
                    GoTo AfterRun
                End If
                
                If IFHasBeenTrue(IFIndex) = False Then
                    IFTrue(IFIndex) = True
                    GoTo AfterRun
                End If
                
            End If
AfterIf:
            '------------------------------------------------------------
            
            
            '------------------------------------------------------------
            'IS THE SCRIPT INSIDE AN IF STATEMENT?
            If IFIndex > 0 Then
                If IFTrue(IFIndex) = False Then GoTo AfterRun
            End If
            '------------------------------------------------------------
            myLine.Caption = tmpS
            
            
            
            
            
        
        
        
        
        
RunACommand:
            '-----------------
            'GOTO
            If GotoEnabled = True Then
                'the commented line is replacing variables, not necessary really, too slow
                If Trim(Left(myLine.Caption, 1)) = "@" Then
                    'If i(myLine.Caption) = "@" & i(GotoString) Or i(myLine.Caption) = "@ " & i(GotoString) Then
                    If i(ReplaceVariables(myLine.Caption, consoleID)) = "@" & i(GotoString) Or i(ReplaceVariables(myLine.Caption, consoleID)) = "@ " & i(GotoString) Then
                        GotoString = ""
                        GotoEnabled = False
                    Else
                        GoTo NextLine
                    End If
                End If
                GoTo NextLine
            End If
            If Mid(i(myLine.Caption), 1, 5) = "goto " Then
                'GotoString = i(Mid(i(myLine.Caption), 5, Len(myLine.Caption)))
                GotoString = i(Mid(i(myLine.Caption), 5, Len(myLine.Caption)))
                GotoString = i(ReplaceVariables(GotoString, consoleID))
                If Left(GotoString, 1) = "@" Then GotoString = Mid(GotoString, 2, Len(GotoString))
                If GotoString <> "" Then
                    GotoEnabled = True
                    n = 0:
                    IFIndex = 0 'also reset the IF statements index
                    For n2 = 1 To 19
                        IFTrue(n2) = False
                        IFHasBeenTrue(n2) = False
                    Next n2
                    ForEnabled = False ': ForStart = 1: ForEnd = 5: ForStep = 1 'reset FOR
                    ForLine = ""
                    GoTo NextLine
                End If
            End If
            '-----------------
        
        
        
           
        'WATFOR $var1, $var2, etc (wait for remote commands)
        If Mid(i(myLine.Caption), 1, 9) = "wait for " Or Mid(i(myLine.Caption), 1, 8) = "waitfor " Then
            tmpS = Trim(Mid(myLine.Caption, 10, Len(myLine.Caption)))
            tmpS = Replace(tmpS, " ", ",")
            tmpS = Replace(tmpS, ",,", ","): tmpS = Replace(tmpS, ",,", ","): tmpS = Replace(tmpS, ",,", ",")
            WaitForVariables = Split(tmpS, ",")
            
            For WaitN = 0 To UBound(WaitForVariables)
                
                tmpS = Trim(WaitForVariables(WaitN))
                
                If tmpS <> "" Then
                    
                    
                    VarIndex = VariableIndex(tmpS)
                    If VarIndex = 0 Then GoTo NextWaitFor

                    Do
                        If CancelScript(consoleID) = True Then GoTo ScriptCancelled
                        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
                        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
                    Loop Until i(Vars(VarIndex).VarValue) <> "[loading]"
                
                End If
NextWaitFor:
            Next
            GoTo AfterRun
        End If
        
        If i(myLine.Caption) = "noprefix" Then myLine.Caption = "setprefix \"
        
        If Mid(i(myLine.Caption), 1, 10) = "setprefix " Then
            If Len(i(myLine.Caption)) > 10 Then
             tmpS = Replace(i(Mid(myLine.Caption, 10, Len(myLine.Caption))), "/", "\")
            Else
             tmpS = ""
            End If
            If Mid(tmpS, 1, 1) <> "\" Then tmpS = "\" & tmpS
            If Mid(tmpS, Len(tmpS), 1) = "\" Then tmpS = Mid(tmpS, 1, Len(tmpS) - 1)
            If cPrefix(consoleID) = tmpS Then GoTo AfterRun
            If Not DirExists(App.Path & "\user" & tmpS) Then
                Say consoleID, "New Prefix directory not found!{orange}"
                GoTo AfterRun
            End If
            If cPrefix(consoleID) <> "" And MsgBox("The script wants to chnage its prefix from """ & cPrefix(consoleID) & """ to """ & tmpS & """?" & vbCrLf & "Do you want to accept this?" & vbCrLf & "ONLY ACCEPT WHEN YOU REALYY TRUST THIS SCRIPT!", vbQuestion + vbYesNo) = vbNo Then
                Say consoleID, "Prefix Change forbidden!{red}"
                GoTo AfterRun
            End If
            Say consoleID, "Prefix changed to """ & tmpS & """{green}"
            If tmpS = "\" Then tmpS = ""
            cPrefix(consoleID) = tmpS
            cPrefix(5) = tmpS
            GoTo AfterRun
        End If
        
        If i(myLine.Caption) = "exit" Then GoTo ScriptEnd
    
    

        Run_Command myLine, consoleID, ScriptFrom, True, True
        
        Do
            DoEvents: DoEvents: DoEvents: DoEvents
            
            If CancelScript(consoleID) = True Then
                Add_Key vbKeyReturn, False, consoleID
                GoTo ScriptCancelled
            End If
        Loop While WaitingForInput(consoleID) = True
        
AfterRun:


        
NextLine:
    Next n
    
    If GotoEnabled = True Then
        ScriptError "GOTO Tag Not Found: " & GotoString, Trim(tmpS), ShortFileName, n, consoleID
    End If
    
    cPath(consoleID) = OldPath
    Exit Function
ScriptCancelled:
    Say consoleID, "Script Stopped by User (CTRL + C){orange}", False
ScriptEnd:
    New_Console_Line consoleID
    cPath(consoleID) = OldPath
End Function


Public Sub ScriptLog(s As String, lineNum As Integer)
    'AppendFile App.Path & "\script.log", "Line " & Format(lineNum, "000") & ", " & s
End Sub

Public Function SetVariable(ByVal VarName As String, ByVal VarVal As String, ByVal consoleID As Integer)
    
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
    VarVal = ReplaceVariables(VarVal, consoleID)
    
    'does the variable name contain []? is it an array?
    VarName = ReplaceArrayIndex(VarName, consoleID)
    
    
    VarName = Trim(Replace(VarName, "$", ""))
    If Len(VarName) < 1 Then Exit Function
    
    Dim sockIndex As Integer
    Dim VarIndex As Integer
    
    VarIndex = VariableIndex(VarName)
    
    If VarIndex = 0 Then
        'its a new variable
        VarIndex = NextEmptyVariable
        'add to the variable lengths table so it can be replaced efficiently later
        VariableLengths(Len(VarName)) = VariableLengths(Len(VarName)) & Trim(str(VarIndex)) & ":"
        
    End If
    
    VarVal = Trim(VarVal)
    
    
    
    'check if the value is a function
    If Mid(i(VarVal), 1, 7) = "getkey(" Then
        GetKeyWaiting(consoleID) = "1"
        Do
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            If CancelScript(consoleID) = True Then GoTo zz1
        Loop Until GetKeyWaiting(consoleID) <> "1"
zz1:
        VarVal = GetKeyWaiting(consoleID)
        GetKeyWaiting(consoleID) = "0"
    ElseIf Mid(i(VarVal), 1, 9) = "getascii(" Then
        GetAsciiWaiting(consoleID) = "1"
        Do
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
            If CancelScript(consoleID) = True Then GoTo zz2
        Loop Until GetAsciiWaiting(consoleID) <> "1"
zz2:
        VarVal = GetAsciiWaiting(consoleID)
        GetAsciiWaiting(consoleID) = "0"
    ElseIf Mid(i(VarVal), 1, 6) = "input(" Then
        cPath_tmp(consoleID) = cPath(consoleID)
        cPath(consoleID) = Mid(VarVal, 7, Len(VarVal))
        If Right(cPath(consoleID), 1) = ")" Then cPath(consoleID) = Mid(cPath(consoleID), 1, Len(cPath(consoleID)) - 1)
        
        WaitingForInput(consoleID) = True
        WaitingForInput_VarIndex(consoleID) = VarIndex
        WaitingForInput_Message(consoleID) = cPath(consoleID)
        
        Shift_Console_Lines_Reverse consoleID
    ElseIf Mid(i(VarVal), 1, 9) = "download(" Then
        Dim VarVal2 As String
        VarVal2 = KillDirectFunctionSides(VarVal)
        VarVal = "[loading]"
        sockIndex = DownloadURL(VarVal2, VarIndex, consoleID)
    ElseIf Mid(i(VarVal), 1, 5) = "ping(" Then '--------- doing 1
        VarVal = KillDirectFunctionSides(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "ping.php?port=0&domain=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 9) = "pingport(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "ping.php?port=" & GetPart(VarVal, 2, " ") & "&domain=" & SumUp(GetPart(VarVal, 1, " "), consoleID) & Credentials, VarIndex, consoleID)
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
            sockIndex = DownloadURL(API_Server & API_Path & "index.php?transfer=" & s1 & "&amount=" & s2 & "&description=" & s3 & Credentials, VarIndex, consoleID)
            VarVal = "[loading]"
        Else
            VarVal = "Payment Not Sent"
        End If
    ElseIf Mid(i(VarVal), 1, 15) = "transferstatus(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?transferstatus=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 15) = "transferamount(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?transferamount=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 20) = "transferdescription(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?transferdescription=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 19) = "transfertousername(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?transfertousername=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 21) = "transferfromusername(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?transferfromusername=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 13) = "transferdate(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?transferdate=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 13) = "transfertime(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?transfertime=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 16) = "serverfilecount(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        VarVal = Trim(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?serverfilecount=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 15) = "serverfilename(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?serverfilename=" & GetPart(VarVal, 1, " ") & "&fileindex=" & GetPart(VarVal, 2, " ") & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 17) = "serverfiledelete(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?serverfiledelete=" & GetPart(VarVal, 1, " ") & "&filename=" & GetPart(VarVal, 2, " ") & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 19) = "serverfiledownload(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?serverfiledownload=" & GetPart(VarVal, 1, " ") & "&filename=" & GetPart(VarVal, 2, " ") & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 17) = "serverfileupload(" Then '--------- doing 2
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        s2 = GetPart(VarVal, 2, " ") 'filename
        s2 = MaskAnd(GetFile(App.Path & "\user" & fixPath(s2, consoleID)))

        sockIndex = DownloadURL(API_Server & API_Path & "index.php?serverfileupload=" & GetPart(VarVal, 1, " ") & "&filename=" & GetPart(VarVal, 2, " ") & "&filedata=" & s2 & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    
    
    ElseIf Mid(i(VarVal), 1, 6) = "getip(" Then '--------- doing 3
        VarVal = KillDirectFunctionSides(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?getip=" & SumUp(VarVal, consoleID) & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 10) = "getdomain(" Then '--------- doing 4
        VarVal = KillDirectFunctionSides(VarVal)
        sockIndex = DownloadURL(API_Server & API_Path & "index.php?getdomain=" & VarVal & Credentials, VarIndex, consoleID)
        VarVal = "[loading]"
    ElseIf Mid(i(VarVal), 1, 13) = "filedownload(" Then '--------- doing 2
        'file download is for people getting any files from their own domain name
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = Replace(VarVal, ",", " "): VarVal = Replace(VarVal, "  ", " "): VarVal = Replace(VarVal, "  ", " ")
        sockIndex = DownloadURL(API_Server & API_Path & "domain_filesystem.php?d=" & GetPart(VarVal, 1, " ") & "&downloadfile=" & GetPart(VarVal, 2, " ") & Credentials, VarIndex, consoleID)
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
        "keycode=" & s1 & _
        "&d=" & GetPart(VarVal, 2, " ") & _
        "&fileserver=" & RemoveSurroundingQuotes(GetPart(VarVal, 3, " ")) & _
        "&startline=" & GetPart(VarVal, 4, " ") & _
        "&maxlines=" & GetPart(VarVal, 5, " ") & _
        Credentials, VarIndex, consoleID)
        
        VarVal = "[loading]"
    'ElseIf Mid(i(VarVal), 1, 5) = "hash(" Then
    '    VarVal = KillDirectFunctionSides(VarVal)
    '    VarVal = RemoveSurroundingQuotes(VarVal)
    '    VarVal = Trim(VarVal)
    '    VarVal = MD5_string(VarVal)
    ElseIf Mid(i(VarVal), 1, 8) = "dirlist(" Then
        VarVal = KillDirectFunctionSides(VarVal)
        VarVal = RemoveSurroundingQuotes(VarVal)
        VarVal = Trim(VarVal)
        Dim sFilter As String, sPath As String, n As Integer, sAll As String, dCount As Integer
        sFilter = Trim(Replace(sFilter, "*", ""))
    
        sPath = App.Path & "\user" & cPrefix(consoleID) & cPath(consoleID)
        
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
        sPath = App.Path & "\user" & cPrefix(consoleID) & cPath(consoleID)
    
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
        sockIndex = DownloadURL(API_Server & API_Path & "time.php", VarIndex, consoleID)
        VarVal = "[loading]"
    Else
        VarVal = SumUp(VarVal, consoleID)
    End If
    
    
    
    If Left(VarVal, 1) = Chr(34) And Right(VarVal, 1) = Chr(34) Then
        'if the string is encased in quotes, remove them
        VarVal = Mid(VarVal, 2, Len(VarVal))
        VarVal = Mid(VarVal, 1, Len(VarVal) - 1)
    End If
    
    
    Vars(VarIndex).VarName = Trim(VarName)
    Vars(VarIndex).VarValue = VarVal
    
    
    
    Msgbux "indx(" & Trim(str(VarIndex)) & ")" & " name(" & VarName & ")= val(" & VarVal & ")"
    
End Function

Public Function DownloadURL(ByVal VarVal As String, VarIndex As Integer, consoleID As Integer) As Integer
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
    
    sUrl = Replace(sUrl, "http://", "")
    sUrl = Replace(sUrl, "Http://", "")
    sUrl = Replace(sUrl, "HTTP://", "")
    
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
    
    If sDomain = "darksignsonline.com" Or sDomain = "www.darksignsonline.com" Then
        VarVal = "No direct API access using download!"
    End If
    
    'MsgBox sUrl & vbCrLf & vbCrLf & PostData
    
    
    DownloadURL = RunPage(sUrl, consoleID, True, PostData, VarIndex)
    
    
    
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

Public Function KillDirectFunctionSides(ByVal s As String) As String
    'this replaces something like  run(blah yah)  with just blah yah
    
    If Right(s, 1) = ")" Then
        s = Mid(s, 1, Len(s) - 1)
        
        If InStr(Mid(s, 1, 24), "(") > 0 Then
            s = Mid(s, InStr(s, "(") + 1, Len(s))
        End If
        
    End If
    
    KillDirectFunctionSides = s
End Function

Public Function ReplaceArrayIndex(ByVal VarName As String, consoleID As Integer) As String

    ReplaceArrayIndex = VarName
    
    If InStr(VarName, "[") > 0 And InStr(VarName, "]") > 0 Then
        If InStr(VarName, "[") < InStr(VarName, "]") Then
        
            If Mid(VarName, 1, 1) = "$" Then
                ReplaceArrayIndex = "$" & ReplaceVariables(Mid(VarName, 2, Len(VarName)), consoleID)
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

Public Function ReplaceVariables(ByVal s As String, ByVal consoleID As Integer) As String

    
        
    'global variables
    s = Replace(s, "$time", Format(Time, "h:mm AMPM"))
    s = Replace(s, "$date", Date)
    s = Replace(s, "$now", Now)
    s = Replace(s, "$username", Trim(myUsername))
    s = Replace(s, "$consoleid", Trim(str(consoleID)))
    s = Replace(s, "$dir", cPath(consoleID))
    s = Replace(s, "$prefix", cPrefix(consoleID))
    s = Replace(s, "$newline", vbCrLf)
    s = Replace(s, "$tab", Chr(vbKeyTab))
    
    
        
    If InStr(s, "$") = 0 Or Trim(s) = "" Then
        If Has_Functions(s) = False Then
            ReplaceVariables = s
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
                    s = Replace(s, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
                    
                    'do it some more, with spaces aruond the [ and ], just in case
                    tmpS = "[ $" & Vars(Val(nA(n))).VarName & " ]"
                    s = Replace(s, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
                    tmpS = "[ $" & Vars(Val(nA(n))).VarName & "]"
                    s = Replace(s, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
                    tmpS = "[$" & Vars(Val(nA(n))).VarName & " ]"
                    s = Replace(s, tmpS, "[" & Vars(Val(nA(n))).VarValue & "]")
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
                    s = Replace(s, tmpS, Vars(Val(nA(n))).VarValue)
                End If
            Next n
        End If
    Next nLen
    

    'now check for functions like mid(), left(), etc

    
    If Has_Functions(s) = True Then
    '   MsgBox s
        s = Bracketize(s, False) 'prepare inside brackets
        s = Convert_Functions(s, consoleID)
        s = UnBracketize(s) 'fix inside bracks to original state
    End If
    
   
    ReplaceVariables = s

End Function

Public Function FunctionData(ByVal s As String, n As Integer, sFunction As String) As FunctionTemp
    
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



    FunctionData.Before_String = Mid(s, 1, n - 1)
    FunctionData.functionParameters = Mid(s, n + Len(sFunction) + 1, 999)
    
    If InStr(FunctionData.functionParameters, ")") > 0 Then
        FunctionData.functionParameters = Mid(FunctionData.functionParameters, 1, InStr(FunctionData.functionParameters, ")") - 1)
    End If
    
    FunctionData.functionParameters = UnBracketize(FunctionData.functionParameters)
    
    FunctionData.tmpS = Mid(s, Len(FunctionData.Before_String) + 1, Len(s))
    FunctionData.After_String = Mid(s, InStr(s, ")") + 1, Len(s))
                

End Function

Public Function Convert_Functions(ByVal s As String, consoleID As Integer) As String



    Dim NextFunctionPos As NextFunction
    Dim sParameters As String, sFunctionResult As String
    
    Dim isForAvariable As Boolean
    
    s = Trim(s)
    If Left(s, 1) = "=" Then
        isForAvariable = True
        s = Trim(Mid(s, 2, Len(s)))
    Else
        isForAvariable = False
    End If

    
    NextFunctionPos = NextFunctionPosition(s)
    
    
    Do While NextFunctionPos.StartPos > 0
        
        
        sParameters = Mid(s, NextFunctionPos.StartPos + Len(NextFunctionPos.FunctionName), Len(s))
        
        If InStr(sParameters, ")") > 0 Then sParameters = Mid(sParameters, 1, InStr(sParameters, ")"))
        sParameters = Trim(sParameters)
        
        
        
        
        'WriteFile App.Path & "\zparams.txt", sParameters
        
        DoEvents
        
        sFunctionResult = RunFunction(NextFunctionPos.FunctionName, sParameters, consoleID)
        s = Mid(s, 1, NextFunctionPos.StartPos - 1) & sFunctionResult & Mid(s, NextFunctionPos.StartPos + Len(sParameters) + Len(NextFunctionPos.FunctionName), Len(s))
        
        NextFunctionPos = NextFunctionPosition(s)
    Loop
    
    
    If isForAvariable = True Then
        s = "= " & s
    End If
    
    Convert_Functions = s


End Function

Public Function RunFunction(ByVal sFunctionName As String, ByVal sParameters As String, consoleID As Integer) As String
    
    
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
        Case "file": RunFunction = f_File(sParameters, consoleID)
        Case "run": RunFunction = f_Run(sParameters, consoleID)
        Case "fileexists": RunFunction = f_FileExists(sParameters, consoleID)
        Case "direxists": RunFunction = f_DirExists(sParameters, consoleID)
        'IMPORTANT!!!!!!!!!!!!!!!
        'make sure you also add new functions to the other list (the array!)
    End Select
    
End Function

Public Function NextFunctionPosition(ByVal s As String) As NextFunction
    Dim n As Integer
    Dim iPos As Long
    Dim sFind As String
    s = i(s)
    
    NextFunctionPosition.StartPos = 99999
    
    For n = 1 To UBound(FunctionList)
        sFind = FunctionList(n) & "("
        If Trim(FunctionList(n)) <> "" Then
            iPos = InStr(s, sFind)
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

Public Function f_Run(ByVal s As String, consoleID As Integer) As String
    On Error GoTo zxc
    Dim tmpLine As ConsoleLine
    ' Add stuff here to detect various bad functions, and prompt user to allow or deny action.
    s = Trim(s)
    tmpLine.Caption = s
    
    'If InStr(s, "CHATSEND ") > 0 Then GoTo zxc
    If InStr(LimitedCommandString, ":" & i(s) & ":") > 0 Then GoTo zxc

    Data_For_Run_Function_Enabled(consoleID) = 1
    Data_For_Run_Function(consoleID) = ""
    Run_Command tmpLine, consoleID, False
    Data_For_Run_Function_Enabled(consoleID) = 0
    
    If Left(Data_For_Run_Function(consoleID), 2) = vbCrLf Then
        Data_For_Run_Function(consoleID) = Mid(Data_For_Run_Function(consoleID), 3, Len(Data_For_Run_Function(consoleID)))
    End If
    
    f_Run = Data_For_Run_Function(consoleID)
    Data_For_Run_Function(consoleID) = ""
    
    
    
Exit Function
zxc:
    f_Run = "*RUN-ERROR*"
End Function


Public Function f_File(ByVal s As String, consoleID As Integer) As String
    'MsgBox s
    'filename, start line, max lines
    s = Trim(Replace(s, ",", " "))
    
    If InStr(s, " ") = 0 Then GoTo zxc
    
    Dim sFile As String
    Dim sStart As Long
    Dim sLinesToGet As Long
    
    sFile = Trim(fixPath(Mid(s, 1, InStr(s, " ")), consoleID))
    s = Trim(Mid(s, InStr(s, " "), Len(s)))

    
    If InStr(s, " ") = 0 Then
        sStart = Val(s)
        sLinesToGet = 29999
    Else
        sStart = Val(Mid(s, 1, InStr(s, " ")))
        sLinesToGet = Val(Trim(Mid(s, InStr(s, " "), Len(s))))
    End If
    
    

    If FileExists(App.Path & "\user" & cPrefix(consoleID) & sFile) = False Then
        GoTo zxc
        Exit Function
    End If
    
    Dim FF As Long, CLine As Integer, CLinePrinted As Integer, tmpJuice As String, tmpS As String
    FF = FreeFile
    
    Open App.Path & "\user" & cPrefix(consoleID) & sFile For Input As #FF
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

Public Function f_KillQuotes(ByVal s As String) As String
    f_KillQuotes = Replace(s, Chr(34), "")
End Function

Public Function f_FileExists(ByVal s As String, ByVal consoleID As Integer) As String
    s = Trim(s)
    s = fixPath(s, consoleID)
    
    If FileExists(App.Path & "\user" & cPrefix(consoleID) & s) = True Then
        f_FileExists = "1"
    Else
        f_FileExists = "0"
    End If
End Function


Public Function f_DirExists(ByVal s As String, ByVal consoleID As Integer) As String
    s = Trim(s)
    s = fixPath(s, consoleID)
    
    If DirExists(App.Path & "\user" & cPrefix(consoleID) & s) = True Then
        f_DirExists = "1"
    Else
        f_DirExists = "0"
    End If
End Function


Public Function f_FixQuotes(ByVal s As String) As String
    f_FixQuotes = Replace(s, Chr(34), "'")
End Function


Public Function f_Replace(ByVal s As String) As String
    
    On Error GoTo zxc
    
'  MsgBox s
s = ReverseString(s)

     
    s = Trim(s)
    If Mid(s, 1, 1) <> Chr(34) Then GoTo zxc
    s = Mid(s, 2, Len(s))
    Dim s1 As String, s2 As String, s3 As String
    If InStr(s, Chr(34)) = 0 Then GoTo zxc
    
    s1 = Mid(s, 1, InStr(s, Chr(34)) - 1)
    s = Mid(s, Len(s1), Len(s))
    
 
    
    If InStr(s, Chr(34)) = 0 Then GoTo zxc
    s = Trim(Mid(s, InStr(s, Chr(34)) + 1, Len(s)))
    
   
    If Mid(s, 1, 1) = Chr(34) Then s = Mid(s, 2, Len(s))
    If Mid(s, 1, 1) = "," Then s = Mid(s, 2, Len(s))
    s = Trim(s)
    If Mid(s, 1, 1) = Chr(34) Then s = Mid(s, 2, Len(s))
    If Mid(s, 1, 1) = "," Then s = Mid(s, 2, Len(s))
     
    
     
    s2 = Mid(s, 1, InStr(s, Chr(34)) - 1)
    
    s = Trim(Mid(s, InStr(s, Chr(34)) + 1, Len(s)))
    
    If Mid(s, 1, 1) = Chr(34) Then s = Mid(s, 2, Len(s))
    If Mid(s, 1, 1) = "," Then s = Mid(s, 2, Len(s))
    s = Trim(s)
    If Mid(s, 1, 1) = Chr(34) Then s = Mid(s, 2, Len(s))
    If Mid(s, 1, 1) = "," Then s = Mid(s, 2, Len(s))
    
    s3 = Replace(s, Chr(34), "")
    
    

    'MsgBux s & vbCrLf & "-" & s1 & "-" & vbCrLf & "-" & s2 & "-" & vbCrLf & "-" & s3 & "-"
    
    s1 = ReverseString(s1)
    s2 = ReverseString(s2)
    s3 = ReverseString(s3)
    
    
    f_Replace = Replace(s3, s2, s1)
     
Exit Function
zxc:
    f_Replace = "*REPLACE-USE-DOUBLE-QUOTES-ERROR*"
End Function


Public Function f_Instr(ByVal s As String) As String
    
    On Error GoTo zxc
    s = Trim(s)
     
    If Mid(s, 1, 1) <> Chr(34) Then GoTo zxc
    s = Mid(s, 2, Len(s))
    
    Dim s1 As String, s2 As String
    If InStr(s, Chr(34)) = 0 Then GoTo zxc
    
    s1 = Mid(s, 1, InStr(s, Chr(34)) - 1)
    
    s = Mid(s, Len(s1), Len(s))
    If InStr(s, Chr(34)) = 0 Then GoTo zxc
    
    s = Trim(Mid(s, InStr(s, Chr(34)) + 1, Len(s)))
    If Mid(s, 1, 1) = Chr(34) Then s = Mid(s, 2, Len(s))
    If Mid(s, 1, 1) = "," Then s = Mid(s, 2, Len(s))
    s = Trim(s)
    If Mid(s, 1, 1) = Chr(34) Then s = Mid(s, 2, Len(s))
    If Mid(s, 1, 1) = "," Then s = Mid(s, 2, Len(s))
     
    s2 = Replace(s, Chr(34), "")
    
    
    f_Instr = InStr(LCase(s1), LCase(s2))
     
     
Exit Function
zxc:
    f_Instr = "*INSTR-USE-DOUBLE-QUOTES-ERROR*"
End Function



Public Function f_Mid(ByVal s As String) As String
    Dim tmpLen As String, tmpStart As String
    

    'On Error GoTo zxc
    

    tmpLen = Trim(ReverseString(Replace(s, ",", " ")))

'    MsgBox tmpLen

    If InStr(tmpLen, " ") = 0 Then GoTo zxc
    tmpLen = ReverseString(Trim(Mid(tmpLen, 1, InStr(tmpLen, " "))))
    s = Mid(s, 1, Len(s) - Len(tmpLen) - 1)
    If Right(s, 1) = " " Then s = Mid(s, 1, Len(s) - 1)
    
    
    tmpStart = Trim(ReverseString(Replace(s, ",", " ")))
    If InStr(tmpStart, " ") = 0 Then GoTo zxc
    tmpStart = ReverseString(Trim(Mid(tmpStart, 1, InStr(tmpStart, " "))))
    s = Mid(s, 1, Len(s) - Len(tmpStart) - 1)
    If Right(s, 1) = " " Then s = Mid(s, 1, Len(s) - 1)
    
    f_Mid = Mid(s, Val(tmpStart), Val(tmpLen))
     
     
     
Exit Function
zxc:
    f_Mid = "*MID-ERROR*"
End Function

Public Function f_Right(ByVal s As String) As String
    Dim tmpS As String
    On Error GoTo zxc
    
    tmpS = Trim(ReverseString(Replace(s, ",", " ")))
    tmpS = Trim(ReverseString(Replace(s, "  ", " "))) ' added space support
    If InStr(tmpS, " ") = 0 Then GoTo zxc
    
    tmpS = ReverseString(Trim(Mid(tmpS, 1, InStr(tmpS, " "))))
    
    's = Mid(s, 1, Len(s) - Len(tmpS) - 1) This is the old var, hope I fixed it right (bigbob85)
    s = Mid(s, 1, Len(s) - Len(tmpS) - 2)
    If Right(s, 1) = " " Then s = Mid(s, 1, Len(s) - 1)
    
    f_Right = Right(s, Val(tmpS))
     
Exit Function
zxc:
    f_Right = "*RIGHT-ERROR*"
End Function


Public Function f_Reverse(ByVal s As String) As String
    
    On Error GoTo zxc
    
    If i(s) = "true" Then
        f_Reverse = "False"
        
    ElseIf i(s) = "false" Then
        f_Reverse = "True"

    ElseIf i(s) = "0" Then
        f_Reverse = "1"
        
    ElseIf i(s) = "1" Then
        f_Reverse = "0"
        
    Else
        f_Reverse = ReverseString(s)
    End If
    
    
     
Exit Function
zxc:
    f_Reverse = "*REVERSE-ERROR*"
End Function

Public Function f_Random(ByVal s As String) As String
    
    On Error GoTo zxc
    
    s = Trim(s)
    s = Replace(s, ",", " ")
    s = Replace(s, "  ", " ") ' add in case of space after comma
    
    If InStr(s, " ") = 0 Then GoTo zxc
    If InStr(s, "%") <> 0 Then GoTo zxc ' added to prevent crash
    
        
    
    
    Dim s1 As String, s2 As String
    Dim iDiff As Long
    
    s1 = Trim(Mid(s, 1, InStr(s, " ")))
    s2 = Trim(Mid(s, InStr(s, " "), Len(s)))
    If Val(s2) < Val(s1) Then GoTo zxc 's2 must be more than s1
    
    iDiff = (Val(s2) - Val(s1)) + 1
    
    Randomize
    f_Random = Trim(str(Int(Rnd * iDiff) + Val(s1)))
       
    
     
Exit Function
zxc:
    f_Random = "*RANDOM-ERROR*"
End Function

Public Function f_RandomText(ByVal s As String) As String
    
    On Error GoTo zxc
    
    s = Trim(s)

    
    Dim n As Long, tmpS As String, rndInt As Integer
    
    If Val(s) < 1 Then s = "1"
    
    For n = 1 To Val(s)
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

Public Function f_Left(ByVal s As String) As String
    Dim tmpS As String
    On Error GoTo zxc
    
    tmpS = Trim(ReverseString(Replace(s, ",", " ")))
    If InStr(tmpS, " ") = 0 Then GoTo zxc
    
    tmpS = ReverseString(Trim(Mid(tmpS, 1, InStr(tmpS, " "))))
    s = Mid(s, 1, Len(s) - Len(tmpS) - 1)
    If Right(s, 1) = " " Then s = Mid(s, 1, Len(s) - 1)
    
    f_Left = Left(s, Val(tmpS))
    
    
Exit Function
zxc:
    f_Left = "*LEFT-ERROR*"
End Function

Public Function f_UCase(ByVal s As String) As String
    On Error GoTo zxc
    
    f_UCase = UCase(s)
Exit Function
zxc:
    f_UCase = "*UCASE-ERROR*"
End Function

Public Function f_LCase(ByVal s As String) As String
    On Error GoTo zxc
    
    f_LCase = LCase(s)
Exit Function
zxc:
    f_LCase = "*LCASE-ERROR*"
End Function

Public Function f_Chr(ByVal s As String) As String
    On Error GoTo zxc
    
    f_Chr = Chr(Val(s))
Exit Function
zxc:
    f_Chr = "*CHR-ERROR*"
End Function

Public Function f_Len(ByVal s As String) As String
    On Error GoTo zxc
    
    f_Len = Trim(str(Len(s)))
Exit Function
zxc:
    f_Len = "*LEN-ERROR*"
End Function


Public Function f_Asc(ByVal s As String) As String
    On Error GoTo zxc
    f_Asc = Asc(Trim(s))
Exit Function
zxc:
    f_Asc = "*ASC-ERROR*"
End Function


Public Function Has_Functions(ByVal s As String) As Boolean

    If InStr(s, "(") > 0 And InStr(s, ")") > 0 Then
        Has_Functions = True
    Else
        Has_Functions = False
    End If
End Function

Public Function Msgbux(ByVal s As String)
    frmConsole.List1.AddItem s, 0
End Function

Public Function Pipe_Commands(ByVal s As String, ByVal consoleID As Integer)
    Dim n As Integer, tmpS As String
    
    Dim CLine As ConsoleLine
    CLine = Console_Line_Defaults
    
    For n = 1 To 10
        tmpS = Trim(GetPart(s, n, "|"))
        
        If tmpS <> "" Then
            CLine.Caption = tmpS
            Run_Command CLine, consoleID
        End If
    Next n
End Function

Public Function CompareIF(ByVal s1 As String, ByVal s2 As String, ByVal sOperator As String, ByVal consoleID As Integer) As Boolean
    
    s1 = ReplaceVariables(s1, consoleID)
    s2 = ReplaceVariables(s2, consoleID)
    
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

Public Sub ScriptError(ByVal qTmp As String, sCommand As String, scriptSource As String, LineNumber As Integer, ByVal consoleID As Integer)
    
    qTmp = " * Warning * > " & Trim(qTmp) & " in " & _
    IU(FileTitleOnly(scriptSource)) & " > Line " & _
    Trim(str(LineNumber)) & " > " & sCommand
    
    SayError qTmp, consoleID
    
End Sub


Public Function GetOperator(ByVal s As String) As String



    GetOperator = ""
    
    'not equal
    If InStr(s, "!") > 0 Then GetOperator = "!": Exit Function
    
    'greater than or equals to
    If InStr(s, ">=") > 0 Then GetOperator = ">=": Exit Function
    
    'less than or equals to
    If InStr(s, "<=") > 0 Then GetOperator = "<=": Exit Function
    
    'greater than
    If InStr(s, ">") > 0 Then GetOperator = ">": Exit Function
    
    'less than
    If InStr(s, "<") > 0 Then GetOperator = "<": Exit Function
    
   
    'equals
    If InStr(s, "=") > 0 Then GetOperator = "=": Exit Function
    
    'contains
    If InStr(s, "^") > 0 Then GetOperator = "^": Exit Function

    'doesn't contain
    If InStr(s, "~") > 0 Then GetOperator = "~": Exit Function
    

End Function

Public Function Mask(ByVal s As String) As String
    Dim inQuotes As Boolean
    Dim tmpS As String
    inQuotes = False
    
    Dim n As Integer
    For n = 1 To Len(s)
        
        If Mid(s, n, 1) = Chr(34) Then inQuotes = Not (inQuotes)
        
        If inQuotes = True Then
            If Mid(s, n, 1) = "=" Then
                tmpS = tmpS & Chr(240)
            ElseIf Mid(s, n, 1) = ">" Then
                tmpS = tmpS & Chr(241)
            ElseIf Mid(s, n, 1) = "<" Then
                tmpS = tmpS & Chr(242)
            ElseIf Mid(s, n, 1) = "^" Then
                tmpS = tmpS & Chr(243)
            ElseIf Mid(s, n, 1) = "~" Then
                tmpS = tmpS & Chr(244)
            ElseIf Mid(s, n, 1) = ">=" Then
                tmpS = tmpS & Chr(245)
            ElseIf Mid(s, n, 1) = "<=" Then
                tmpS = tmpS & Chr(246)
            Else
                tmpS = tmpS & Mid(s, n, 1)
            End If
        Else
            tmpS = tmpS & Mid(s, n, 1)
        End If
        
    Next n
    
    Mask = tmpS
    
End Function

Public Function UnMask(ByVal s As String) As String
    
    s = Replace(s, Chr(240), "=")
    s = Replace(s, Chr(241), ">")
    s = Replace(s, Chr(242), "<")
    s = Replace(s, Chr(243), "^")
    s = Replace(s, Chr(244), "~")
    s = Replace(s, Chr(245), ">=")
    s = Replace(s, Chr(246), "<=")
    
    
    UnMask = s
End Function


Public Function SumUp(sValue As String, ByVal consoleID As Integer) As String
    
    SumUp = sValue

    If InStr(SumUp, "*") > 0 Or InStr(SumUp, "-") > 0 Or InStr(SumUp, "^") > 0 Or _
        InStr(SumUp, "/") > 0 Or InStr(SumUp, "+") > 0 Or InStr(SumUp, "%") > 0 Then
        SumUp = ReplaceVariables(SumUp, consoleID)
        If IsNumeric(Mid(SumUp, 1, NextEmptyOperator(SumUp) - 1)) Or Val(SumUp) < 0 Then
            SumUp = Trim(str(sumProcess(SumUp)))
        End If
    End If
End Function

Public Function KillOps(s As String) As String
    KillOps = s
    KillOps = Replace(KillOps, "+", "")
    KillOps = Replace(KillOps, "-", "")
    KillOps = Replace(KillOps, "/", "")
    KillOps = Replace(KillOps, "*", "")
    KillOps = Replace(KillOps, "^", "")
    KillOps = Replace(KillOps, "%", "")
End Function


Public Function NextEmptyOperator(s As String) As Long
    NextEmptyOperator = 9999

    If InStr(s, "*") Then NextEmptyOperator = InStr(s, "*")
    
    If InStr(s, "+") And InStr(s, "+") < NextEmptyOperator Then
        NextEmptyOperator = InStr(s, "+")
    End If

    If InStr(s, "-") And InStr(s, "-") < NextEmptyOperator Then
        NextEmptyOperator = InStr(s, "-")
    End If

    If InStr(s, "/") And InStr(s, "/") < NextEmptyOperator Then
        NextEmptyOperator = InStr(s, "/")
    End If
    
    If InStr(s, "^") And InStr(s, "^") < NextEmptyOperator Then
        NextEmptyOperator = InStr(s, "^")
    End If
        
    If InStr(s, "%") And InStr(s, "%") < NextEmptyOperator Then
        NextEmptyOperator = InStr(s, "%")
    End If
    
    
    
    
    If NextEmptyOperator = 9999 Then NextEmptyOperator = 0
End Function

Public Function Bracketize(ByVal s As String, ReplaceLoosely As Boolean) As String
    Dim n As Long
    Dim BracketValue As Integer
    Dim tmpS As String, midString As String * 1
    
    If Len(s) > 32096 Then 'no more than 32kb - way too slow!
        SayComm "Warning: Processing large data may take a while... (" & FormatKB(Len(s)) & ")"
        DoEvents
        'Bracketize = s
        'Exit Function
    End If
    
    For n = 1 To Len(s)
    
        midString = Mid(s, n, 1)
    
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

Public Function MaskSpacesInQuotes(ByVal s As String) As String
    Dim n As Long, tmpS As String
    Dim inQuotes As Boolean
    inQuotes = False
    
    For n = 1 To Len(s)
        If Mid(s, n, 1) = Chr(34) Then
            inQuotes = Not (inQuotes)
        End If
        
        If Mid(s, n, 1) = " " Then
            If inQuotes = True Then
                tmpS = tmpS & Chr(240)
            Else
                tmpS = tmpS & Mid(s, n, 1)
            End If
        Else
            tmpS = tmpS & Mid(s, n, 1)
        End If
    Next n
    
    MaskSpacesInQuotes = tmpS
End Function

Public Function MaskCharInQuotes(ByVal s As String, sCharToMask As String) As String
    Dim n As Long, tmpS As String
    Dim inQuotes As Boolean
    inQuotes = False
    
    For n = 1 To Len(s)
        If Mid(s, n, 1) = Chr(34) Then
            inQuotes = Not (inQuotes)
        End If
        
        If Mid(s, n, 1) = sCharToMask Then
            If inQuotes = True Then
                tmpS = tmpS & Chr(240)
            Else
                tmpS = tmpS & Mid(s, n, 1)
            End If
        Else
            tmpS = tmpS & Mid(s, n, 1)
        End If
    Next n
    
    MaskCharInQuotes = tmpS
End Function

Public Function UnBracketize(ByVal s As String) As String
    s = Replace(s, "[{[", "(")
    s = Replace(s, "]}]", ")")
    UnBracketize = s
End Function

Public Function URLFormat(ByVal s As String) As String
    
    s = Replace(s, "+", "--plus--")
    s = Replace(s, "&", "--and--")
    s = Replace(s, "#", "--hash--")
    
    URLFormat = s
    
End Function

Public Function RemoveSurroundingQuotes(ByVal s As String) As String
    s = Trim(s)
    
    If Right(s, 1) = Chr(34) And Left(s, 1) = Chr(34) Then
        s = Mid(s, 2, Len(s) - 2)
    End If
    
    RemoveSurroundingQuotes = s
End Function

Public Function RemoveSurroundingBrackets(ByVal s As String) As String
    s = Trim(s)
    
    If Right(s, 1) = ")" And Left(s, 1) = "(" Then
        s = Mid(s, 2, Len(s) - 2)
    End If
    
    If Mid(s, 1, 1) = "(" Then s = Mid(s, 2, Len(s))
    
    RemoveSurroundingBrackets = s
End Function

Public Function ConvertToNumbers(ByVal s As String) As String
    Dim n As Long, tChr As Integer
    
    For n = 1 To Len(s)
        tChr = Asc(Mid(s, n, 1))
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
