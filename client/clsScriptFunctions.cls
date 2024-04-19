VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsScriptFunctions"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

' Notices for declaring things for DScript to use
' 1) If DScript should be able to use it, it must be Public
' 2) Always use ByVal for arguments where possible
' 3) Always use Function, not Sub
' 4) For Arguments that can't use ByVal (arrays etc), you must be Variant (Variant() does NOT work) and handle the types yourself
' 5) To return arrays, you must use Variant(), anything else can be returned as-is

Private PrivConsoleID As Integer
Private PrivParameters() As Variant
Private ScriptFrom As String
Private IsCLIInput As Boolean
Private IsConfigured As Boolean
Private SControl As ScriptControl
Private FileKey As String

Private Aborted As Boolean
Private PrivAllowUnAbort As Boolean

Private PrivDisableOutput As Boolean
Private PrivRedirectOutput As Boolean
Private PrivOutput As String
Private PrivServerDomain As String
Private PrivServerPort As Long

Private PendingCustomDownloads() As Long

Private Declare Function GetTickCount Lib "KERNEL32" () As Long
Private Declare Function GetPrivateProfileString Lib "KERNEL32" Alias "GetPrivateProfileStringA" (ByVal lpApplicationName As String, ByVal lpKeyName As Any, ByVal lpDefault As String, ByVal lpReturnedString As String, ByVal nSize As Long, ByVal lpFileName As String) As Long
Private Declare Function WritePrivateProfileString Lib "KERNEL32" Alias "WritePrivateProfileStringA" (ByVal lpApplicationName As String, ByVal lpKeyName As Any, ByVal lpString As Any, ByVal lpFileName As String) As Long

Public Property Get UserName() As String
    UserName = myUsername
End Property

Public Property Get ServerDomain() As String
    ServerDomain = PrivServerDomain
End Property

Public Property Get ServerPort() As Long
    ServerPort = PrivServerPort
End Property

Public Property Let UserName(ByVal NewValue As String)
    AssertLocalOnly

    SetUsername NewValue, ConsoleID
End Property

Public Property Get Password() As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
End Property

Public Property Let Password(ByVal NewValue As String)
    AssertLocalOnly

    SetPassword NewValue, ConsoleID
End Property

Public Property Get CWD() As String
    AssertLocalOnly

    CWD = cPath(PrivConsoleID)
End Property

Public Property Let CWD(ByVal NewValue As String)
    AssertLocalOnly

    Dim RawDir As String
    RawDir = ResolvePath(NewValue)

    If Not DirExists(RawDir) Then
        Err.Raise 53, , "File not found"
        Exit Property
    End If

    cPath(PrivConsoleID) = RawDir
    Yield
End Property

Public Property Let ExternalEditor(ByVal NewValue As Boolean)
    AssertLocalOnly

    RegSave "externaleditor", "" & NewValue
End Property

Public Property Get ExternalEditor() As Boolean
    AssertLocalOnly

    ExternalEditor = RegLoad("externaleditor", False)
End Property

Public Property Get IsOutputDisabled() As Boolean
    IsOutputDisabled = PrivDisableOutput
End Property

Public Property Get IsOutputRedirected() As Boolean
    IsOutputRedirected = PrivRedirectOutput
End Property

Public Property Get ConsoleCursorChar() As String
    ConsoleCursorChar = basConsole.ConsoleCursorChar
End Property

Public Property Get ConsoleInvisibleChar() As String
    ConsoleInvisibleChar = basConsole.ConsoleInvisibleChar
End Property

Public Property Get ConsoleID() As String
    ConsoleID = PrivConsoleID
End Property

Private Sub CrashIfReached()
    Aborted = True
    While True: Wend
End Sub

Public Function IsLocal() As Boolean
    IsLocal = PrivServerPort <= 0
End Function

Private Sub AssertRemoteOnly()
    If Not IsLocal() Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9008, , "remote only functionality"
    CrashIfReached
End Sub

Private Sub AssertLocalOnly()
    If IsLocal() Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9007, , "local only functionality"
    CrashIfReached
End Sub

Private Sub Class_Initialize()
    ReDim PendingCustomDownloads(0 To 0)
    IsConfigured = False
    Aborted = False
    PrivOutput = ""
End Sub

Public Function CleanupScriptTasks()
    If UBound(PendingCustomDownloads) > 0 Then
        Dim X As Long
        For X = 1 To UBound(PendingCustomDownloads)
            DownloadAborted(X) = True
        Next
    End If
    ReDim PendingCustomDownloads(0 To 0)
    Aborted = True
    GetKeyWaiting(ConsoleID) = 0
    GetAsciiWaiting(ConsoleID) = 0
    WaitingForInput(ConsoleID) = False
    WaitingForInputReturn(ConsoleID) = ""
End Function

Public Function UnAbort()
    If PrivAllowUnAbort Then
        Aborted = False
    End If
End Function

Public Function Quit()
    Aborted = True
    Err.Raise vbObjectError + 9002, , "Script exited"
End Function

Public Function ScriptGetOutput() As String
    ScriptGetOutput = PrivOutput
End Function

Public Function ReadLine(ByVal Prompt As String) As String
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    cPrompt(ConsoleID) = Prompt
    CurrentPromptInput(ConsoleID) = ""
    WaitingForInput(ConsoleID) = True
    
    New_Console_Line ConsoleID

    While WaitingForInput(ConsoleID)
        If Not YieldSafe() Then GoTo ReadLineExit
    Wend
    ReadLine = WaitingForInputReturn(ConsoleID)
    Exit Function

ReadLineExit:
    ReadLine = ""
    CurrentPromptInput(ConsoleID) = ""
    WaitingForInput(ConsoleID) = False
    Yield
End Function

Public Function GetKey() As Long
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    GetKeyWaiting(ConsoleID) = -1
    While GetKeyWaiting(ConsoleID) = -1
        If Not YieldSafe() Then GoTo ExitGetKey
    Wend
    GetKey = GetKeyWaiting(ConsoleID)
    Exit Function

ExitGetKey:
    GetKeyWaiting(ConsoleID) = 0
    GetKey = 0
    Yield
End Function

Public Function GetASCII() As Long
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    GetAsciiWaiting(ConsoleID) = -1
    While GetAsciiWaiting(ConsoleID) = -1
        If Not YieldSafe() Then GoTo ExitGetASCII
    Wend
    GetASCII = GetAsciiWaiting(ConsoleID)
    Exit Function

ExitGetASCII:
    GetAsciiWaiting(ConsoleID) = 0
    GetASCII = 0
    Yield
End Function

Public Function Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean, NewScriptControl As ScriptControl, NewPrivParameters() As Variant, NewFileKey As String, NewServerDomain As String, NewServerPort As Long, NewRedirect As Boolean, NewDisableOutput As Boolean, NewAllowUnAbort As Boolean)
    If IsConfigured Then
        Exit Function
    End If
    IsConfigured = True
    PrivConsoleID = NewConsoleID
    ScriptFrom = NewScriptFrom
    IsCLIInput = NewIsCLIInput
    Set SControl = NewScriptControl
    PrivParameters = NewPrivParameters
    FileKey = NewFileKey
    PrivDisableOutput = NewDisableOutput
    PrivRedirectOutput = NewRedirect
    PrivServerDomain = NewServerDomain
    PrivServerPort = NewServerPort
    PrivAllowUnAbort = NewAllowUnAbort
End Function

Public Function Cls()
    Clear
End Function

Public Function Delete(ByVal File As String)
    Del File
End Function

Private Sub AddCustomDownload(ByVal ResIndex As Long)
    ReDim Preserve PendingCustomDownloads(0 To UBound(PendingCustomDownloads) + 1)
    PendingCustomDownloads(UBound(PendingCustomDownloads)) = ResIndex
End Sub

Private Function HasPendingCustomDownload(ByVal ResIndex As Long) As Boolean
    HasPendingCustomDownload = False
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Function
    End If

    Dim X As Long
    
    For X = 1 To UBound(PendingCustomDownloads)
        If PendingCustomDownloads(X) = ResIndex Then
            HasPendingCustomDownload = True
            Exit Function
        End If
    Next
End Function

Private Sub RemoveCustomDownload(ByVal ResIndex As Long)
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Sub
    End If

    Dim NewPendingCustomDownloads() As Long
    ReDim NewPendingCustomDownloads(1 To UBound(PendingCustomDownloads))
    
    Dim X As Long
    Dim Y As Long
    Y = 0

    Dim MadeChanges As Boolean

    For X = 1 To UBound(PendingCustomDownloads)
        If PendingCustomDownloads(X) = ResIndex Then
            MadeChanges = True
        Else
            Y = Y + 1
            NewPendingCustomDownloads(Y) = ResIndex
        End If
    Next
    
    If Not MadeChanges Then
        Exit Sub
    End If
    
    ReDim PendingCustomDownloads(0 To Y)
    For X = 1 To Y
        PendingCustomDownloads(X) = NewPendingCustomDownloads(X)
    Next
End Sub

Private Function DoDownloadAPI(ByVal Url As String, ByVal UsePost As Boolean, ByVal PostData As String) As Long
    DoDownloadAPI = DoDownload(API_Server & API_Path & Url, UsePost, PostData, False)
End Function

Private Function DoDownload(ByVal Url As String, ByVal UsePost As Boolean, ByVal PostData As String, ByVal NoAuth As Boolean) As Long
    Dim ResIndex As Long
    DoDownload = 0
    For ResIndex = 1 To 99
        If Not DownloadInUse(ResIndex) Then
            DoDownload = ResIndex
            Exit For
        End If
    Next
    If DoDownload <= 0 Then
        Err.Raise vbObjectError + 9100, , "No free download slots"
        Exit Function
    End If

    DownloadInUse(ResIndex) = True
    DownloadDone(ResIndex) = False

    AddCustomDownload ResIndex

    RunPage Url, PrivConsoleID, UsePost, PostData, ResIndex, NoAuth
    If NoAuth Then
        Yield
    End If
End Function

Public Function WAITFOR(ByVal ResIndex As Long, Optional ByVal NoYield As Boolean = False) As clsHttpResponse
    ConsoleWaitingOnRemote(PrivConsoleID) = True
    frmConsole.QueueConsoleRender
    
    If Not YieldSafe() Then GoTo WaitForExit

    While Not DownloadDone(ResIndex)
        If Not YieldSafe() Then GoTo WaitForExit
        If Not HasPendingCustomDownload(ResIndex) Then GoTo WaitForExit
    Wend

    Dim Res As clsHttpResponse
    Set Res = New clsHttpResponse
    Res.Code = DownloadCodes(ResIndex)
    Res.Response = DownloadResults(ResIndex)
    Set WAITFOR = Res

    DownloadInUse(ResIndex) = False
    RemoveCustomDownload ResIndex

WaitForExit:
    ConsoleWaitingOnRemote(PrivConsoleID) = False
    frmConsole.QueueConsoleRender
    If Not NoYield Then
        Yield
    End If
End Function

Public Function CD(ByVal DIR As String)
    CWD = DIR
End Function

Public Function ReadDir(ByVal RawPath As String) As Variant()
    AssertLocalOnly
    
    Dim Res() As Variant

    Dim Attr As Long
    Dim FileName As String
    Dim IsFirst As Boolean
    IsFirst = True

    Dim Path As String
    Path = ResolvePath(RawPath)
    Path = SafePath(Path)
    
    Attr = GetAttr(Path)
    If (Attr And vbDirectory) <> vbDirectory Then
        Err.Raise 9301, , "Can only list directories"
        Exit Function
    End If
    
    Path = Path & "/"
    
    FileName = FileSystem.DIR(Path, vbNormal + vbDirectory)
    While FileName <> ""
        If IsFirst Then
            ReDim Res(0 To 0)
            IsFirst = False
        Else
            ReDim Preserve Res(0 To UBound(Res) + 1)
        End If

        Attr = GetAttr(Path & FileName)
        If (Attr And vbDirectory) = vbDirectory Then
            FileName = FileName & "/"
        End If
        
        Res(UBound(Res)) = FileName
        FileName = FileSystem.DIR()
    Wend

    If IsFirst Then
        ReDim Res(-1 To -1)
        ReadDir = Res
        Yield
        Exit Function
    End If

    ReadDir = Res
    Yield
End Function

Public Function RESTART()
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    frmConsole.Start_Console PrivConsoleID
    Yield
End Function

Public Function EDIT(ByVal File As String)
    AssertLocalOnly

    Yield
    EditFile ResolvePath(File), PrivConsoleID
    Yield
End Function

Public Function SayLine(ByVal s As String, Optional ByVal YPos As Long = -1)
    If s = "" Then
        Yield
        Exit Function
    End If

    If PrivRedirectOutput Then
        If PrivOutput = "" Then
            PrivOutput = s
        Else
            PrivOutput = PrivOutput & vbCr & s
        End If
        Yield
    End If
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    Yield
    basConsole.SayRaw PrivConsoleID, s, YPos
    Yield
End Function

Public Function PrintVar(ParamArray Param() As Variant)
    If UBound(Param) < 0 Then
        Say "No arguments to print{{orange}}"
        Exit Function
    End If

    If LBound(Param) = UBound(Param) And VarType(Param(UBound(Param))) = vbString Then
        Say Param(UBound(Param))
        Exit Function
    End If

    Dim X As Long
    For X = LBound(Param) To UBound(Param)
        PrintVarInt Param(X), "", "ArgV(" & X & ") ", 0
    Next X
End Function

Public Function PrintVarSingleIfSet(Param As Variant)
    If VarType(Param) = vbEmpty Then
        Exit Function
    End If

    PrintVar Param
End Function

Private Sub PrintVarInt(Param As Variant, ByVal Prefix As String, ByVal Index As String, ByVal Depth As String)
    Dim TypeName As String

    Select Case (VarType(Param) And (Not vbArray))
        Case vbBoolean:
            TypeName = "Boolean"
        Case vbByte:
            TypeName = "Byte"
        Case vbCurrency:
            TypeName = "Currency"
        Case vbDataObject:
            TypeName = "DataObject"
        Case vbDate:
            TypeName = "Date"
        Case vbDecimal:
            TypeName = "Decimal"
        Case vbDouble:
            TypeName = "Double"
        Case vbEmpty:
            TypeName = "Empty"
        Case vbError:
            TypeName = "Error"
        Case vbInteger:
            TypeName = "Integer"
        Case vbLong:
            TypeName = "Long"
        Case vbNull:
            TypeName = "Null"
        Case vbObject:
            TypeName = "Object"
        Case vbSingle:
            TypeName = "Single"
        Case vbString:
            TypeName = "String"
        Case vbUserDefinedType:
            TypeName = "UserDefinedType"
        Case vbVariant:
            TypeName = "Variant"
    End Select
    
    Dim MainPrefix As String
    MainPrefix = Prefix
    If Index <> "" Then
        MainPrefix = MainPrefix & Index
    End If

    Yield
    If (VarType(Param) And vbArray) = vbArray Then
        Dim X As Long
        Dim XV As String
        Say MainPrefix & "{{yellow}}Array of element type " & TypeName & " from " & LBound(Param) & " to " & UBound(Param)
        Dim SubPrefix As String
        SubPrefix = "    " & Prefix
        For X = LBound(Param) To UBound(Param)
            Yield
            PrintVarInt Param(X), SubPrefix, "(" & X & ") ", Depth + 1
        Next X
    Else
        Dim StrParam As String
        StrParam = "" & Param
        Dim StrPos As Long
        Dim HadCut As Boolean
        HadCut = False
        StrPos = InStr(StrParam, vbCr)
        If StrPos > 0 Then
            StrParam = Left(StrParam, StrPos - 1)
            HadCut = True
        End If
        StrPos = InStr(StrParam, vbLf)
        If StrPos > 0 Then
            StrParam = Left(StrParam, StrPos - 1)
            HadCut = True
        End If

        If HadCut Then
            StrParam = StrParam & " [...]"
        End If

        Say MainPrefix & "{{blue}}Value of type " & TypeName & " = " & StrParam
    End If
    Yield
End Sub

Public Function LineUp()
    Say ""
End Function

Public Function Say(ParamArray Params() As Variant)
    Dim X As Long
    Dim sStr As String
    Dim XV As String
    For X = LBound(Params) To UBound(Params)
        XV = "" & Params(X)
        If XV <> "" Then
            If sStr <> "" Then
                sStr = sStr & " "
            End If
            sStr = sStr & XV
        End If
    Next X

    If PrivRedirectOutput Then
        If PrivOutput = "" Then
            PrivOutput = sStr
        Else
            PrivOutput = PrivOutput & vbCrLf & sStr
        End If
        Yield
    End If
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    
    If sStr = "" Then
        Yield
        basConsole.SayRaw PrivConsoleID, ""
        Yield
        Exit Function
    End If

    Dim ScriptOutSplit() As String
    ScriptOutSplit = Split(sStr, vbCrLf)
    For X = LBound(ScriptOutSplit) To UBound(ScriptOutSplit)
        Yield
        basConsole.SayRaw PrivConsoleID, ScriptOutSplit(X)
        Yield
    Next
End Function

Public Function SayCOMM(ParamArray Params() As Variant)
    Dim X As Long
    Dim sStr As String
    Dim XV As String
    For X = LBound(Params) To UBound(Params)
        XV = Params(X)
        If XV <> "" Then
            If sStr <> "" Then
                sStr = sStr & " "
            End If
            sStr = sStr & XV
        End If
    Next X

    Yield
    If sStr = "" Then
        Exit Function
    End If
    basWorld.SayCOMM sStr
    Yield
End Function

Public Function CLIParse(ByVal Src As String, ByVal Dest As String)
    AssertLocalOnly

    Dim SrcStr As String
    SrcStr = GetFile(ResolvePath(Src))

    Dim DestStr As String
    DestStr = ParseCommandLineOptional(SrcStr)

    WriteFile ResolvePath(Dest), DestStr
End Function

Public Function ResolveCommand(ByVal Command As String) As String
    ResolveCommand = basCommands.ResolveCommand(PrivConsoleID, Command)
End Function

Public Function ResolvePath(ByVal Path As String) As String
    ResolvePath = basCommands.ResolvePath(PrivConsoleID, Path)
End Function

Public Function HttpRequest(ByVal Url As String, Optional ByVal PostData As String = "") As Integer
     HttpRequest = DoDownload(Url, PostData <> "", PostData, True)
End Function

Public Function URLEncode(ByVal Param As String) As String
    URLEncode = basWorld.EncodeURLParameter(Param)
End Function

Public Function BoolToString(ByVal Param As String) As Boolean
    Param = LCase(Trim(Param))
    If Param = "on" Or Param = "true" Or Param = "yes" Then
        BoolToString = True
    ElseIf Param = "off" Or Param = "false" Or Param = "no" Then
        BoolToString = False
    Else
        RaiseMiscError "Invalid value for boolean: " & Param
    End If
End Function

Public Function DRAW(ByVal YPos As Long, ByVal R As Long, ByVal G As Long, ByVal b As Long, ByVal Mode As String)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    DrawItUp YPos, R, G, b, Mode, PrivConsoleID
    Yield
End Function

Private Sub RaiseMiscError(ByVal Desc As String)
    Err.Raise vbObjectError + 9666, , Desc
End Sub

Public Function TextWidth(ByVal FontName As String, ByVal FontSize As String, ByVal Text As String) As Long
    If FontName = "" Then
        FontName = basConsole.Console_Line_Defaults.FontName
    End If
    If FontSize = "" Then
        FontSize = basConsole.Console_Line_Defaults.FontSize
    End If

    frmConsole.lfont.FontName = FontName
    frmConsole.lfont.FontSize = FontSize
    frmConsole.lfont.Caption = Text
    TextWidth = frmConsole.lfont.Width
End Function

Public Function TextHeight(ByVal FontName As String, ByVal FontSize As String) As Long
    If FontName = "" Then
        FontName = basConsole.Console_Line_Defaults.FontName
    End If
    If FontSize = "" Then
        FontSize = basConsole.Console_Line_Defaults.FontSize
    End If
    TextHeight = Font_Height(FontName, FontSize)
End Function

Public Function ConsoleWidth() As Long
    ConsoleWidth = frmConsole.Width - (ConsoleXSpacing * 2)
End Function

Public Function FormatKB(ToConvert As Long) As String
    FormatKB = basGeneral.FormatKB(ToConvert)
End Function

Public Function Overwrite(ByVal File As String, ByVal Content As String)
    AssertLocalOnly

    basGeneral.WriteFile ResolvePath(File), Content
End Function

Public Function Append(ByVal File As String, ByVal Content As String)
    AssertLocalOnly

    AppendFile ResolvePath(File), Content
End Function

Public Function FileLen(ByVal File As String) As Long
    AssertLocalOnly

    FileLen = basGeneral.FileLen(ResolvePath(File))
End Function

Public Function Del(ByVal File As String)
    AssertLocalOnly

    Yield
    File = ResolvePath(File)
    Kill SafePath(File)
End Function

Public Function Copy(ByVal Source As String, ByVal Destination As String)
    AssertLocalOnly
    
    Yield
    Source = ResolvePath(Source)
    Destination = ResolvePath(Destination)
    
    FileCopy SafePath(Source), SafePath(Destination)
End Function

Public Function Rename(ByVal Source As String, ByVal Destination As String)
    Move Source, Destination
End Function

Public Function Move(ByVal Source As String, ByVal Destination As String)
    AssertLocalOnly
    
    Yield
    Source = ResolvePath(Source)
    Destination = ResolvePath(Destination)

    Name SafePath(Source) As SafePath(Destination)
End Function

Public Function MD(ByVal NewDir As String)
    AssertLocalOnly

    Yield
    NewDir = ResolvePath(NewDir)

    MkDir SafePath(NewDir)
End Function

Public Function RD(ByVal OldDir As String)
    AssertLocalOnly

    Yield
    OldDir = ResolvePath(OldDir)

    RmDir SafePath(OldDir)
End Function

Public Function Cat(ByVal File As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    Cat = Display(File, StartLine, MaxLines)
End Function

Public Function Display(ByVal File As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertLocalOnly

    File = ResolvePath(File)

    If StartLine < 1 Then
        StartLine = 1
    End If

    Dim EndLine As Long
    EndLine = StartLine + MaxLines

    Dim CurLine As Long
    CurLine = 0

    Dim Content As String
    Display = ""

    Dim FF As Long
    FF = FreeFile
    Open SafePath(File) For Input As #FF
        While Not EOF(FF)
            CurLine = CurLine + 1
            
            If MaxLines > 0 And CurLine >= EndLine Then
                GoTo AbortPrintDisplayLoop
            End If

            Line Input #FF, Content
            If CurLine < StartLine Then
                GoTo DontPrintDisplay
            End If

            Display = Display & Content & vbCrLf
DontPrintDisplay:
        Wend
AbortPrintDisplayLoop:
    Close #FF
End Function

Public Function MUSIC(ByVal Command As String)
    AssertLocalOnly

    Yield
    MusicCommand Command
    Yield
End Function

Public Function MAIL()
    AssertLocalOnly

    Yield
    frmDSOMail.Show vbModal
    Yield
End Function

Public Function yDiv(ByVal setValue As Integer)
    Yield
    If PrivDisableOutput Then
        Exit Function
    End If

    SetYDiv setValue
End Function

Public Function PAUSE(Optional ByVal Prompt As String = "")
    Yield
    If PrivDisableOutput Then
        Exit Function
    End If

    PauseConsole Prompt, PrivConsoleID
    Yield
End Function

Public Function LOGIN(Optional ByVal Silent As Boolean = False)
    AssertLocalOnly

    Dim PrintOutput As Boolean
    PrintOutput = (Not PrivDisableOutput) And (Not PrivRedirectOutput) And (Not Silent)

    While LoginInProgress
        Yield
    Wend

    If basWorld.Authorized = True Then
        If PrintOutput Then
            SayRaw ConsoleID, "You are already logged in and authorized as " & myUsername & ".{{green}}"
        End If
        Exit Function
    End If

    Dim isBad As Boolean
    isBad = False
    If myUsername = "" Then
        If PrintOutput Then
            SayRaw ConsoleID, "{{14, orange,  center}}Your username is not set - type: USERNAME = ""[username]"" to set it."
        End If
        isBad = True
    End If
    If myPassword = "" Then
        If PrintOutput Then
            SayRaw ConsoleID, "{{14, orange, center}}Your password is not set - type: PASSWORD = ""[password]"" to set it."
        End If
        isBad = True
    End If

    If isBad = True Then
        If PrintOutput Then
            SayRaw ConsoleID, "Warning - You are not logged in!{{16 center underline}}"
            SayRaw ConsoleID, "Once you have set your USERNAME and PASSWORD, type LOGIN.{{14 center}}"
        End If
        RaiseMiscError "Username and/or password not set"
    End If

    LoginInProgress = True
    SayCOMM "Logging in..."

    Dim ResIndex As Long
    ResIndex = DoDownloadAPI("auth.php", True, "")
    Dim ResObj As clsHttpResponse
    Set ResObj = WAITFOR(ResIndex, True)

    If ResObj.IsSuccess() Then
        OnLoginSuccess
        LoginInProgress = False
    Else
        OnLoginFailure
        LoginInProgress = False
        RaiseMiscError "Login failed"
    End If

    ResObj.RaiseForStatus

    Yield
End Function

Public Function LOGOUT()
    AssertLocalOnly

    basWorld.Authorized = False
    frmConsole.Shape1.BackColor = vbRed
    frmConsole.lblUsername.Caption = "You have been logged out."
    SayCOMM "You have been logged out."
    
    If frmConsole.getConnected Then
        frmConsole.Send "QUIT :darksignsonline.com, Dark Signs Online"    'send the quit message
        frmConsole.lstUsers.Clear  'clear the list entries
        frmConsole.Display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
        frmConsole.sockIRC.Close_   'close the connection
        frmConsole.setConnected False
    End If

    Yield
End Function

Public Function Stats(ByVal setValue As Integer) As String
    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("get_user_stats.php", False, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
    Stats = DomainRequest.Response
End Function

Public Function Lookup(ByVal Domain As String) As String
    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("lookup.php?d=" & EncodeURLParameter(Domain), False, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
    Lookup = DomainRequest.Response
End Function

Public Function GetDomain(ByVal IP As String) As String
    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_meta.php?getdomain=" & EncodeURLParameter(IP), False, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
    GetDomain = DomainRequest.Response
End Function

Public Function PingPort(ByVal Domain As String, ByVal Port As Integer) As Boolean
    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("ping.php?domain=" & EncodeURLParameter(Domain) & "&port=" & EncodeURLParameter(Port), False, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
    PingPort = Trim(DomainRequest.Response) = "1"
End Function

Public Function Ping(ByVal Domain As String) As Boolean
    Ping = PingPort(Domain, 0)
End Function

Public Function GetIP(ByVal Domain As String) As String
    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_meta.php?getip=" & EncodeURLParameter(Domain), False, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    GetIP = DomainRequest.Response
End Function

Public Function UPLOAD(ByVal Domain As String, ByVal Port As Long, ByVal sFileData As String)
    AssertLocalOnly
    
    Yield
    
    Domain = GetDomain(Domain)

    Dim tempStrA As String
    tempStrA = EncodeBase64Str(sFileData)

    Dim PostData As String
    PostData = "port=" & EncodeURLParameter(Port) & _
    "&d=" & EncodeURLParameter(Domain) & _
    "&filedata=" & EncodeURLParameter(tempStrA)

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_upload.php", True, PostData)
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
End Function

Public Function DOWNLOAD(ByVal Domain As String, ByVal Port As Long) As String
    AssertLocalOnly
    
    Yield

    Dim PostData As String
    PostData = "port=" & EncodeURLParameter(Port) & _
    "&d=" & EncodeURLParameter(Domain)

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_download.php", True, PostData)
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    DOWNLOAD = DomainRequest.Response

    Yield
End Function

Public Function Unregister(ByVal Domain As String)
    AssertLocalOnly
    
    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_unregister.php", True, "d=" & EncodeURLParameter(Domain))
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)

    SayCOMM DomainRequest.Response

    DomainRequest.RaiseForStatus

    Yield
End Function

Public Function Register(ByVal Domain As String)
    AssertLocalOnly

    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_register.php", True, "d=" & EncodeURLParameter(Domain))
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)

    SayCOMM DomainRequest.Response

    DomainRequest.RaiseForStatus

    Yield
End Function

Public Function RegisterPrices() As String
    AssertLocalOnly

    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_register.php?prices=true", False, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
    RegisterPrices = DomainRequest.Response
End Function

Public Function ClosePort(ByVal Domain As String, ByVal Port As Long)
    AssertLocalOnly
    
    Yield

    Dim PostData As String
    PostData = "port=" & EncodeURLParameter(Port) & _
    "&d=" & EncodeURLParameter(Domain)

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_close.php", True, PostData)
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
End Function

Private Function MyDomainsHelper(ByVal DomainType As String) As String
    AssertLocalOnly
    
    Yield

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("my_domains.php?type=" & EncodeURLParameter(DomainType), False, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
    MyDomainsHelper = DomainRequest.Response
End Function

Private Function DomainFilesystemHelper(ByVal Domain As String, ByVal PostData As String) As String
    Yield

    Dim IsLocalValue As String
    IsLocalValue = "false"
    If IsLocal() Then
        IsLocalValue = "true"
    End If
    
    PostData = "is_local_script=" & EncodeURLParameter(IsLocalValue) & _
                                        "&keycode=" & EncodeURLParameter(FileKey) & _
                                        "&d=" & EncodeURLParameter(Domain) & _
                                        "&" & PostData

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_filesystem.php", True, PostData)
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)
    DomainRequest.RaiseForStatus

    Yield
    DomainFilesystemHelper = DomainRequest.Response
End Function

Public Function RemoteWrite(ByVal Domain As String, ByVal FileName As String, ByVal Contents As String)
    AssertLocalOnly

    DomainFilesystemHelper Domain, "write=" & EncodeURLParameter(FileName) & "&filedata=" & EncodeURLParameter(Contents)
End Function

Public Function RemoteAppend(ByVal Domain As String, ByVal FileName As String, ByVal Contents As String)
    AssertLocalOnly

    DomainFilesystemHelper Domain, "append=" & EncodeURLParameter(FileName) & "&filedata=" & EncodeURLParameter(Contents)
End Function

Public Function RemoteSafeAppend(ByVal Domain As String, ByVal FileName As String, ByVal Line As String)
    AssertLocalOnly

    DomainFilesystemHelper Domain, "safeappend=" & EncodeURLParameter(FileName) & "&filedata=" & EncodeURLParameter(Line)
End Function

Public Function RemoteDelete(ByVal Domain As String, ByVal FileName As String)
    AssertLocalOnly
    
    DomainFilesystemHelper Domain, "delete=" & EncodeURLParameter(FileName)
End Function

Public Function RemoteDir(ByVal Domain As String) As Variant()
    AssertLocalOnly
    
    RemoteDir = Split(DomainFilesystemHelper(Domain, "dir=/"), vbCrLf)
End Function

Public Function RemoteView(ByVal Domain As String, ByVal FileName As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertLocalOnly
    
    RemoteView = DomainFilesystemHelper(Domain, "fileserver=" & EncodeURLParameter(FileName) & "&maxlines=" & EncodeURLParameter(MaxLines) & "&startline=" & EncodeURLParameter(StartLine))
End Function

Public Function ServerWrite(ByVal FileName As String, ByVal Contents As String)
    AssertRemoteOnly

    DomainFilesystemHelper ServerDomain, "write=" & EncodeURLParameter(FileName) & "&filedata=" & EncodeURLParameter(Contents)
End Function

Public Function ServerAppend(ByVal FileName As String, ByVal Contents As String)
    AssertRemoteOnly

    DomainFilesystemHelper ServerDomain, "append=" & EncodeURLParameter(FileName) & "&filedata=" & EncodeURLParameter(Contents)
End Function

Public Function ServerSafeAppend(ByVal FileName As String, ByVal Line As String)
    AssertRemoteOnly

    DomainFilesystemHelper ServerDomain, "safeappend=" & EncodeURLParameter(FileName) & "&filedata=" & EncodeURLParameter(Line)
End Function

Public Function ServerDelete(ByVal FileName As String)
    AssertRemoteOnly
    
    DomainFilesystemHelper ServerDomain, "delete=" & EncodeURLParameter(FileName)
End Function

Public Function ServerDir() As Variant()
    AssertRemoteOnly

    ServerDir = Split(DomainFilesystemHelper(ServerDomain, "dir=/"), vbCrLf)
End Function

Public Function ServerView(ByVal FileName As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertRemoteOnly
    
    ServerView = DomainFilesystemHelper(ServerDomain, "fileserver=" & EncodeURLParameter(FileName) & "&maxlines=" & EncodeURLParameter(MaxLines) & "&startline=" & EncodeURLParameter(StartLine))
End Function

Public Function FileServer(ByVal FileName As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    FileServer = ServerView(FileName, StartLine, MaxLines)
End Function

Public Function MyDomains() As String
    MyDomains = MyDomainsHelper("domain")
End Function

Public Function MySubdomains() As String
    MySubdomains = MyDomainsHelper("subdomain")
End Function

Public Function MyIPs() As String
    MyIPs = MyDomainsHelper("ip")
End Function

Public Function Transfer(ByVal Target As String, ByVal Amount As Long, ByVal Description As String) As String
    Yield

    Target = Trim(Target)
    Description = Trim(Description)

    If Amount < 1 Then
        RaiseMiscError "Invalid amount: $" & Amount & ".00!"
        Exit Function
    End If
    
    AuthorizePayment = False
    frmPayment.lAmount = "$" & Amount & ".00"
    frmPayment.lDescription = Description
    frmPayment.lTo = Target

    Yield
    frmPayment.Show vbModal
    Yield

    If AuthorizePayment = False Then
        RaiseMiscError "Payment declined by user"
        Exit Function
    End If

    SayCOMM "Processing Payment..."

    Yield

    Dim PostData As String
    PostData = "to=" & EncodeURLParameter(Target) & _
                "&amount=" & EncodeURLParameter(Amount) & _
                "&description=" & EncodeURLParameter(Description)

    Dim TransferRequestIndex As Long
    TransferRequestIndex = DoDownloadAPI("transfer.php", False, "")
    Dim TransferRequest As clsHttpResponse
    Set TransferRequest = WAITFOR(TransferRequestIndex)
    TransferRequest.RaiseForStatus

    SayCOMM "Paymenmt result was " & TransferRequest.Response

    Transfer = TransferRequest.Response
End Function

Public Function Wait(ByVal Milliseconds As Long)
    Dim EndTime As Long
    EndTime = GetTickCount() + Milliseconds
    
    While GetTickCount() < EndTime
        Yield
    Wend
End Function

Public Function Clear()
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    ClearConsole PrivConsoleID
    Yield
End Function

Public Function ArgC() As Long
    Yield
    ArgC = UBound(PrivParameters)
End Function

Public Function ArgV(ByVal Number As Long) As Variant
    Yield
    If Number < LBound(PrivParameters) Or Number > UBound(PrivParameters) Then
        ArgV = ""
        Exit Function
    End If
    ArgV = PrivParameters(Number)
End Function

Private Function YieldSafe() As Boolean
    YieldSafe = True

    If CancelScript(PrivConsoleID) Or Aborted Then
        Aborted = True
        YieldSafe = False
        Exit Function
    End If

    DoEvents
End Function

Public Function Yield()
    If Not YieldSafe() Then
        Err.Raise vbObjectError + 9001, , "Script canceled"
    End If
End Function


' RUN CODE FROM FILE

Private Function RawRunCaptureA(ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal Script As String, Optional XArr As Variant) As String
    AssertLocalOnly

    Dim X As Long
    
    Dim SParamArr() As Variant

    If (VarType(XArr) And vbArray) = vbArray Then
        ReDim SParamArr(0 To UBound(XArr) + 1)
        For X = 0 To UBound(XArr)
            SParamArr(X + 1) = XArr(X)
        Next
    Else
        ReDim SParamArr(0 To 0)
    End If

    SParamArr(0) = Script
    Yield
    RawRunCaptureA = Run_Script(ResolveCommand(Script), PrivConsoleID, SParamArr, "RUN", False, RedirectOutput, DisableOutput, "")
    Yield
End Function

Public Function CaptureA(ByVal Script As String, Optional XArr As Variant) As String
    CaptureA = RawRunCaptureA(True, True, Script, XArr)
End Function

Public Function Capture(ParamArray XArr() As Variant) As String
    If UBound(XArr) < 0 Then
        RaiseMiscError "Capture needs at least one parameter (the script)"
    End If

    Dim Script As String
    Script = XArr(0)
    If UBound(XArr) = 0 Then
        Capture = CaptureA(Script)
        Exit Function
    End If

    Dim X As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For X = 0 To UBound(SParamArr)
        SParamArr(X) = XArr(X + 1)
    Next
    Capture = CaptureA(Script, SParamArr)
End Function

Public Function RunA(ByVal Script As String, Optional XArr As Variant)
    Dim Output As String
    Output = RawRunCaptureA(PrivDisableOutput And PrivRedirectOutput, PrivDisableOutput, Script, XArr)
    If PrivDisableOutput And PrivRedirectOutput Then
        Say Output
    End If
End Function

Public Function Include(ByVal Script As String)
    AssertLocalOnly

    Dim ScriptData As String
    ScriptData = GetFile(ResolvePath(Script))

    SControl.AddCode ScriptData
End Function

' This allows remote/domain calls on purpose!
Public Function DLOpen(ByVal Library As String)
    If InStr(Library, "/") > 0 Or InStr(Library, "\") > 0 Then
        Exit Function
    End If

    Include "/system/libs/" & Library & ".ds"
End Function

Public Function Run(ParamArray XArr() As Variant)
    If UBound(XArr) < 0 Then
        RaiseMiscError "Run needs at least one parameter (the script)"
    End If

    Dim Script As String
    Script = XArr(0)
    If UBound(XArr) = 0 Then
        RunA Script
        Exit Function
    End If

    Dim X As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For X = 0 To UBound(SParamArr)
        SParamArr(X) = XArr(X + 1)
    Next
    RunA Script, SParamArr
End Function

' IRC

Public Function ChatSend(ByVal Msg As String)
    AssertLocalOnly

    Yield
    frmConsole.ChatSend Msg
End Function

Public Function ChatView(ByVal Enabled As Boolean)
    AssertLocalOnly

    Yield
    frmConsole.ChatView Enabled
End Function


' RUN CODE FROM STRING

Private Function RawRunCaptureCodeA(ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal Code As String, Optional XArr As Variant) As String
    Dim X As Long
    
    Dim SParamArr() As Variant

    If (VarType(XArr) And vbArray) = vbArray Then
        ReDim SParamArr(0 To UBound(XArr) + 1)
        For X = 0 To UBound(XArr)
            SParamArr(X + 1) = XArr(X)
        Next
    Else
        ReDim SParamArr(0 To 0)
    End If

    SParamArr(0) = "inline://"
    Yield
    RawRunCaptureCodeA = Run_Script_Code(Code, PrivConsoleID, SParamArr, "RunCode", FileKey, PrivServerDomain, PrivServerPort, False, RedirectOutput, DisableOutput, "")
    Yield
End Function

Public Function CaptureCodeA(ByVal Code As String, Optional XArr As Variant) As String
    CaptureCodeA = RawRunCaptureCodeA(True, True, Code, XArr)
End Function

Public Function CaptureCode(ParamArray XArr() As Variant) As String
    If UBound(XArr) < 0 Then
        RaiseMiscError "CaptureCode needs at least one parameter (the code)"
    End If

    Dim Script As String
    Script = XArr(0)
    If UBound(XArr) = 0 Then
        CaptureCode = CaptureCodeA(Script)
        Exit Function
    End If

    Dim X As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For X = 0 To UBound(SParamArr)
        SParamArr(X) = XArr(X + 1)
    Next
    CaptureCode = CaptureCodeA(Script, SParamArr)
End Function

Public Function RunCodeA(ByVal Code As String, Optional XArr As Variant)
    Dim Output As String
    Output = RawRunCaptureCodeA(PrivDisableOutput And PrivRedirectOutput, PrivDisableOutput, Code, XArr)
    If PrivDisableOutput And PrivRedirectOutput Then
        Say Output
    End If
End Function

Public Function RunCode(ParamArray XArr() As Variant)
    If UBound(XArr) < 0 Then
        RaiseMiscError "RunCode needs at least one parameter (the code)"
    End If

    Dim Script As String
    Script = XArr(0)
    If UBound(XArr) = 0 Then
        RunCodeA Script
        Exit Function
    End If

    Dim X As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For X = 0 To UBound(SParamArr)
        SParamArr(X) = XArr(X + 1)
    Next
    RunCodeA Script, SParamArr
End Function

Public Function IncludeCode(ByVal Code As String)
    SControl.AddCode Code
End Function

' RUN CODE FROM DSO DOMAIN

Public Function Fetch(ParamArray Params() As Variant) As String
    If UBound(Params) < 1 Then
        RaiseMiscError "Fetch needs at least two parameters (domain and port)"
    End If

    Dim Domain As String
    Dim Port As Long
    Domain = Params(0)
    Port = Params(1)
    If UBound(Params) <= 1 Then
        Fetch = ConnectRaw(False, True, True, Domain, Port)
        Exit Function
    End If

    Dim DParams() As Variant
    ReDim DParams(0 To UBound(Params) - 2)
    Dim X As Long
    For X = 0 To UBound(DParams)
        DParams(X) = Params(X + 2)
    Next
    Fetch = ConnectRaw(False, True, True, Domain, Port, DParams)
End Function

' Params is an array
Public Function FetchA(ByVal Domain As String, ByVal Port As Long, Optional Params As Variant) As String
    FetchA = ConnectRaw(False, True, True, Domain, Port, Params)
End Function

Public Function Connect(ParamArray Params() As Variant)
    If UBound(Params) < 1 Then
        RaiseMiscError "Connect needs at least two parameters (domain and port)"
    End If

    Dim Res As String

    Dim Domain As String
    Dim Port As Long
    Domain = Params(0)
    Port = Params(1)
    If UBound(Params) <= 1 Then
        Res = ConnectRaw(True, PrivRedirectOutput And PrivDisableOutput, PrivDisableOutput, Domain, Port)
        GoTo HandleRes
    End If

    Dim DParams() As Variant
    ReDim DParams(0 To UBound(Params) - 2)
    Dim X As Long
    For X = 0 To UBound(DParams)
        DParams(X) = Params(X + 2)
    Next

    Res = ConnectRaw(True, PrivRedirectOutput And PrivDisableOutput, PrivDisableOutput, Domain, Port, DParams)
HandleRes:
    If PrivRedirectOutput And PrivDisableOutput Then
        Say Res
    End If
End Function

' Params is an array
Public Function ConnectA(ByVal Domain As String, ByVal Port As Long, Optional Params As Variant)
    Dim Res As String
    Res = ConnectRaw(True, PrivRedirectOutput And PrivDisableOutput, PrivDisableOutput, Domain, Port, Params)
    If PrivRedirectOutput And PrivDisableOutput Then
        Say Res
    End If
End Function

Private Function ConnectRaw(ByVal Verbose As Boolean, RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal Domain As String, ByVal Port As Long, Optional Params As Variant) As String
    Yield
    If Port < 1 Or Port > 65535 Then
        Err.Raise vbObjectError + 9999, , "Invalid Port Number: " & Port
        Exit Function
    End If

    If Verbose Then
        Say "{{green}}Connecting to " & UCase(Domain) & ":" & Port & "..."
    End If

    Dim X As Long
    Dim DomainConnectParams() As Variant
    If (VarType(Params) And vbArray) = vbArray Then
        ReDim DomainConnectParams(0 To UBound(Params) + 1)
        For X = 1 To UBound(DomainConnectParams)
            DomainConnectParams(X) = Params(X - 1)
        Next
    Else
        ReDim DomainConnectParams(0 To 0)
    End If

    Dim DomainRequestIdx As Long
    DomainRequestIdx = DoDownloadAPI("domain_connect.php?d=" & EncodeURLParameter(Domain) & _
            "&port=" & EncodeURLParameter(Port), True, "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WAITFOR(DomainRequestIdx)

    Select Case DomainRequest.Code
        Case 404:
            RaiseMiscError "Could not connect to" & UCase(Domain) & ":" & Port & " -> Not found"
        Case 403:
            RaiseMiscError "Could not connect to" & UCase(Domain) & ":" & Port & " -> Access denied"
        Case Else:
            DomainRequest.RaiseForStatus
    End Select

    Dim DomainSplit() As String
    DomainSplit = Split(DomainRequest.Response, ":-:")
    ' 0 = domain
    ' 1 = port
    ' 2 = filekey
    ' 3 = code

    Dim strDomain As String
    strDomain = DomainSplit(0)
    Dim strPort As Long
    strPort = Val(DomainSplit(1))
    If strPort <= 0 Then
        strPort = 99999
    End If
    Dim strFileKey As String
    strFileKey = DomainSplit(2)

    Dim strCode As String
    strCode = DecodeBase64Str(DomainSplit(3))

    Dim DomScript As String
    DomScript = "dso://" & strDomain & ":" & strPort
    DomainConnectParams(0) = DomScript
    ConnectRaw = Run_Script_Code(strCode, ConsoleID, DomainConnectParams, DomScript, strFileKey, strDomain, strPort, False, RedirectOutput, DisableOutput, DomScript)

    Yield
End Function

Public Function CompileScript(ByVal Source As String, Optional ByVal FileKey As String = "", Optional ByVal AllowCommands As Boolean = True) As String
    CompileScript = DSOCompileScript(Source, FileKey, AllowCommands)
End Function

' Encoding helpers
Public Function EncodeBase64Bytes(arrData As Variant) As String
    Dim typedArrData() As Byte
    Dim X As Long

    ReDim typedArrData(LBound(arrData) To UBound(arrData))
    For X = LBound(arrData) To UBound(arrData)
        typedArrData(X) = arrData(X)
    Next
    EncodeBase64Bytes = basConsole.EncodeBase64Bytes(typedArrData)
End Function

Public Function EncodeBase64Str(ByVal strData As String) As String
    EncodeBase64Str = basConsole.EncodeBase64Str(strData)
End Function

Public Function DecodeBase64Bytes(ByVal strData As String) As Variant()
    Dim Res() As Byte
    Dim ResVar() As Variant
    Dim X As Long

    Res = basConsole.DecodeBase64Bytes(strData)
    ReDim ResVar(LBound(Res) To UBound(Res))
    For X = LBound(Res) To UBound(Res)
        ResVar(X) = Res(X)
    Next
    DecodeBase64Bytes = ResVar
End Function

Public Function DecodeBase64Str(ByVal strData As String) As String
    DecodeBase64Str = basConsole.DecodeBase64Str(strData)
End Function

' Mission progress indicators
Private Function GetMissionFile(ByVal MissionID As String) As String
    MissionID = Replace(MissionID, "/", "_")
    MissionID = Replace(MissionID, "\", "_")
    
    GetMissionFile = "/system/missions/" & MissionID & ".ini"
End Function

Public Function SetMissionProgress(ByVal MissionID As String, ByVal Key As String, ByVal Value As String)
    WritePrivateProfileString "progress", Key, Value, SafePath(GetMissionFile(MissionID))
End Function

Public Function GetMissionProgress(ByVal MissionID As String, ByVal Key As String)
    Dim Result As String * 4096
    Dim ResultLen As Long
    ResultLen = GetPrivateProfileString("progress", Key, "", Result, 4096, SafePath(GetMissionFile(MissionID)))
    GetMissionProgress = Left(Result, ResultLen)
End Function

