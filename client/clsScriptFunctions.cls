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
' 3) For Arguments that can't use ByVal (arrays etc), you must be Variant (Variant() does NOT work) and handle the types yourself
' 4) To return arrays, you must use Variant(), anything else can be returned as-is

Private PrivConsoleID As Integer
Private PrivParameters() As Variant
Private ScriptFrom As String
Private IsCLIInput As Boolean
Private IsConfigured As Boolean
Private SControl As ScriptControl
Private FileKey As String
Public Aborted As Boolean

Private PrivDisableOutput As Boolean
Private PrivRedirectOutput As Boolean
Private PrivOutput As String
Private PrivIsRoot As Boolean
Private PrivServerDomain As String
Private PrivServerPort As Long

Private PendingCustomDownloads() As Long

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
    AssertCLIOnly

    SetUsername NewValue, ConsoleID
End Property

Public Property Get Password() As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
End Property

Public Property Get IsRoot() As Boolean
    IsRoot = PrivIsRoot
End Property

Public Property Get IsOutputDisabled() As Boolean
    IsOutputDisabled = PrivDisableOutput
End Property

Public Property Get IsOutputRedirected() As Boolean
    IsOutputRedirected = PrivRedirectOutput
End Property

Public Property Let Password(ByVal NewValue As String)
    AssertCLIOnly

    SetPassword NewValue, ConsoleID
End Property

Public Property Get CWD() As String
    AssertLocalOnly

    CWD = cPath(PrivConsoleID)
End Property

Public Property Let CWD(ByVal NewValue As String)
    AssertLocalOnly

    cPath(PrivConsoleID) = ResolvePath(CWD)
End Property

Public Property Get ConsoleID() As String
    ConsoleID = PrivConsoleID
End Property

Private Sub CrashIfReached()
    Aborted = True
    While True: Wend
End Sub

Private Sub AssertCLIOnly()
    If IsCLIInput Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9006, "DSO", "CLI only functionality"
    CrashIfReached
End Sub

Private Sub AssertLocalOnly()
    If PrivServerPort <= 0 Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9007, "DSO", "local only functionality"
    CrashIfReached
End Sub

Private Sub Class_Initialize()
    ReDim PendingCustomDownloads(0 To 0)
    IsConfigured = False
    Aborted = False
    PrivOutput = ""
End Sub

Public Sub CleanupScriptTasks()
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
End Sub

Public Sub Quit()
    Aborted = True
    Err.Raise vbObjectError + 9002, "DSO", "Script exited"
End Sub

Public Function ScriptGetOutput() As String
    ScriptGetOutput = PrivOutput
End Function

Public Function ReadLine(ByVal Prompt As String) As String
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    cPath_tmp(ConsoleID) = cPath(ConsoleID)
    cPath(ConsoleID) = Prompt
    WaitingForInput(ConsoleID) = True
    
    New_Console_Line ConsoleID

    While WaitingForInput(ConsoleID)
        Yield
    Wend
    ReadLine = WaitingForInputReturn(ConsoleID)
End Function

Public Function GetKey() As Long
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    GetKeyWaiting(ConsoleID) = -1
    While GetKeyWaiting(ConsoleID) = -1
        Yield
    Wend
    GetKey = GetKeyWaiting(ConsoleID)
End Function

Public Function GetASCII() As Long
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    GetAsciiWaiting(ConsoleID) = -1
    While GetAsciiWaiting(ConsoleID) = -1
        Yield
    Wend
    GetASCII = GetAsciiWaiting(ConsoleID)
End Function

Public Sub Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean, NewScriptControl As ScriptControl, NewPrivParameters() As Variant, NewFileKey As String, NewServerDomain As String, NewServerPort As Long, NewRedirect As Boolean, NewDisableOutput As Boolean, NewIsRoot As Boolean)
    If IsConfigured Then
        Exit Sub
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
    PrivIsRoot = NewIsRoot
    PrivServerDomain = NewServerDomain
    PrivServerPort = NewServerPort
End Sub

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
        Err.Raise vbObjectError + 9100, "DSO", "No free download slots"
        Exit Function
    End If

    DownloadInUse(ResIndex) = True
    DownloadDone(ResIndex) = False

    AddCustomDownload ResIndex

    RunPage Url, PrivConsoleID, UsePost, PostData, ResIndex, NoAuth
    Yield
End Function

Public Function WAITFOR(ByVal ResIndex As Long) As clsHttpResponse
    While Not DownloadDone(ResIndex)
        Yield
        If Not HasPendingCustomDownload(ResIndex) Then
            Err.Raise vbObjectError + 9300, "DSO", "Invalid WaitFor Index " & ResIndex
            Exit Function
        End If
    Wend

    Dim Res As clsHttpResponse
    Set Res = New clsHttpResponse
    Res.Code = DownloadCodes(ResIndex)
    Res.Response = DownloadResults(ResIndex)
    Set WAITFOR = Res

    DownloadInUse(ResIndex) = False
    RemoveCustomDownload ResIndex
    Yield
End Function

Public Sub SayCOMM(ParamArray Params() As Variant)
    Dim X As Long
    Dim sStr As String
    For X = LBound(Params) To UBound(Params)
        If sStr <> "" Then
            sStr = sStr & " "
        End If
        sStr = sStr & Params(X)
    Next X

    Yield
    basWorld.SayCOMM sStr, ConsoleID
    Yield
End Sub

Public Sub CD(ByVal DIR As String)
    AssertLocalOnly

    cPath(PrivConsoleID) = ResolvePath(DIR)
    Yield
End Sub

Public Function ReadDir(ByVal RawPath As String) As Variant()
    AssertLocalOnly
    
    Dim Res() As Variant

    Dim Attr As Long
    Dim Filename As String
    Dim IsFirst As Boolean
    IsFirst = True

    Dim Path As String
    Path = ResolvePath(RawPath)
    Path = SafePath(Path)
    
    Attr = GetAttr(Path)
    If (Attr And vbDirectory) <> vbDirectory Then
        Err.Raise 9301, "DSO", "Can only list directories"
        Exit Function
    End If
    
    Path = Path & "/"
    
    Filename = FileSystem.DIR(Path, vbNormal + vbDirectory)
    While Filename <> ""
        If IsFirst Then
            ReDim Res(0 To 0)
            IsFirst = False
        Else
            ReDim Preserve Res(0 To UBound(Res) + 1)
        End If

        Attr = GetAttr(Path & Filename)
        If (Attr And vbDirectory) = vbDirectory Then
            Filename = Filename & "/"
        End If
        
        Res(UBound(Res)) = Filename
        Filename = FileSystem.DIR()
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

Public Sub EDIT(ByVal file As String)
    AssertCLIOnly

    Yield
    EditFile ResolvePath(file), PrivConsoleID
    Yield
End Sub

Public Sub SayLine(ByVal s As String)
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
        Exit Sub
    End If
    Yield
    basConsole.SayRaw PrivConsoleID, s, False
    Yield
End Sub

Public Sub Say(ParamArray Params() As Variant)
    Dim X As Long
    Dim sStr As String
    For X = LBound(Params) To UBound(Params)
        If sStr <> "" Then
            sStr = sStr & " "
        End If
        sStr = sStr & Params(X)
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
        Exit Sub
    End If

    Dim ScriptOutSplit() As String
    ScriptOutSplit = Split(sStr, vbCrLf)
    For X = LBound(ScriptOutSplit) To UBound(ScriptOutSplit)
        Yield
        basConsole.SayRaw PrivConsoleID, ScriptOutSplit(X)
        Yield
    Next
End Sub

Public Sub CLIParse(ByVal Src As String, ByVal Dest As String)
    AssertLocalOnly

    Dim SrcStr As String
    SrcStr = GetFile(ResolvePath(Src))

    Dim DestStr As String
    DestStr = ParseCommandLineOptional(SrcStr)

    WriteFile ResolvePath(Dest), DestStr
End Sub

Public Function ResolveCommand(ByVal Command As String) As String
    ResolveCommand = basCommands.ResolveCommand(PrivConsoleID, Command)
End Function

Public Function ResolvePath(ByVal Path As String) As String
    ResolvePath = basCommands.ResolvePath(PrivConsoleID, Path)
End Function

Public Sub RUN(ParamArray XArr() As Variant)
    AssertLocalOnly

    Dim Script As String
    Script = XArr(0)
    Dim X As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr))
    For X = 0 To UBound(XArr)
        SParamArr(X) = XArr(X)
    Next

    Yield
    Run_Script ResolveCommand(Script), PrivConsoleID, SParamArr, "RUN", False, False, False
    Yield
End Sub

Public Function CallScript(ParamArray XArr() As Variant) As String
    AssertLocalOnly

    Dim X As Long
    Dim Script As String
    Script = XArr(0)

    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr))
    For X = 0 To UBound(XArr)
        SParamArr(X) = XArr(X)
    Next

    Yield
    CallScript = Run_Script(ResolveCommand(Script), PrivConsoleID, SParamArr, "CALL", False, True, Not PrivIsRoot)
    Yield
End Function

Public Function DOWNLOAD(ByVal Url As String) As Integer
     DOWNLOAD = DoDownload(Url, True, "", True)
End Function

Public Function DRAW(ByVal YPos As Long, ByVal R As Long, ByVal G As Long, ByVal b As Long, ByVal Mode As String)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    DrawItUp YPos, R, G, b, Mode, PrivConsoleID
    Yield
End Function

' Params is an array
Public Function ConnectEX(ByVal Foreground As Boolean, ByVal Domain As String, ByVal Port As Long, Optional Params As Variant) As String
    If Foreground Then
        AssertLocalOnly
    End If
    Yield

    If Port < 1 Or Port > 65535 Then
        Err.Raise vbObjectError + 9999, "DSO", "Invalid Port Number: " & Port
        Exit Function
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
    DomainRequest.RaiseForStatus

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

    Dim b64decoded() As Byte
    Dim strCode As String
    b64decoded = basConsole.DecodeBase64(DomainSplit(3))
    strCode = StrConv(b64decoded, vbUnicode)
    
    Dim DisableOutput As Boolean
    DisableOutput = Not PrivIsRoot
    If Foreground = True Then
        DisableOutput = False
    End If

    Dim DomScript As String
    DomScript = "dso://" & strDomain & ":" & strPort
    DomainConnectParams(0) = DomScript
    ConnectEX = Run_Script_Code(strCode, ConsoleID, DomainConnectParams, DomScript, strFileKey, strDomain, strPort, False, True, DisableOutput)

    Yield
End Function

' Params is an array
Public Function Connect(ByVal Domain As String, ByVal Port As Long, Optional Params As Variant) As String
    Connect = ConnectEX(False, Domain, Port, Params)
End Function

Private Sub RaiseMiscError(ByVal Desc As String)
    Err.Raise vbObjectError + 9666, "DSO", Desc
End Sub

Public Sub LOGIN()
    AssertLocalOnly
    
    Dim isBad As Boolean
    isBad = False

    If basWorld.Authorized = True Then
        SayRaw ConsoleID, "You are already logged in and authorized as " & myUsername & ".{green}"
        Exit Sub
    End If

    If myUsername = "" Then
        SayRaw ConsoleID, "{14, orange,  center}Your username is not set - type: USERNAME [username] to set it."
        isBad = True
    End If
    If myPassword = "" Then
        SayRaw ConsoleID, "{14, orange, center}Your password is not set - type: PASSWORD [password] to set it."
        isBad = True
    End If

    If isBad = True Then
        SayRaw ConsoleID, "Warning - You are not logged in!{16 center underline}"
        SayRaw ConsoleID, "Once you have set your USERNAME and PASSWORD, type LOGIN.{14 center}"
        RaiseMiscError "Username and/or password not set"
        Exit Sub
    End If

    SayCOMM "Logging in..."

    Dim ResIndex As Long
    ResIndex = DoDownloadAPI("auth.php", True, "")
    Dim ResObj As clsHttpResponse
    Set ResObj = WAITFOR(ResIndex)

    If ResObj.IsSuccess() Then
        OnLoginSuccess
    Else
        OnLoginFailure
        RaiseMiscError "Login failed"
    End If

    ResObj.RaiseForStatus

    Yield
End Sub

Public Sub LOGOUT()
    AssertLocalOnly

    basWorld.Authorized = False
    frmConsole.Shape1.BackColor = vbRed
    frmConsole.lblUsername.Caption = "You have been logged out."
    SayCOMM "You have been logged out."
    
    If frmConsole.getConnected Then
        frmConsole.Send "QUIT :darksignsonline.com, Dark Signs Online"    'send the quit message
        frmConsole.lstUsers.Clear  'clear the list entries
        frmConsole.display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
        frmConsole.sockIRC.Close_   'close the connection
        frmConsole.setConnected False
    End If

    Yield
End Sub

Public Sub UPLOAD(ByVal Domain As String, ByVal Port As Long, ByVal Filename As String)
    AssertCLIOnly
    
    Yield

    Dim sFileData As String
    sFileData = GetFile(ResolvePath(Filename))

    Dim tempStrA As String

    tempStrA = EncodeBase64(StrConv(sFileData, vbFromUnicode))

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
End Sub

Public Sub Clear()
    ClearConsole PrivConsoleID
End Sub

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

Public Sub Yield()
    If CancelScript(PrivConsoleID) Or Aborted Then
        Aborted = True
        Err.Raise vbObjectError + 9001, "DSO", "Script canceled"
        Exit Sub
    End If

    DoEvents
End Sub
