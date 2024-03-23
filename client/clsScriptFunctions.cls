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

Private PrivConsoleID As Integer
Private PrivParameters() As String
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

Private PendingCustomDownloads() As Integer

Public Property Get UserName() As Variant
    UserName = myUsername
End Property

Public Property Let UserName(ByVal NewValue As Variant)
    AssertCLIOnly

    SetUsername NewValue, ConsoleID
End Property

Public Property Get Password() As Variant
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
End Property

Public Property Let Password(ByVal NewValue As Variant)
    AssertCLIOnly

    SetPassword NewValue, ConsoleID
End Property

Public Property Get CWD() As Variant
    AssertLocalOnly

    CWD = cPath(PrivConsoleID)
End Property

Public Property Let CWD(ByVal NewValue As Variant)
    AssertLocalOnly

    cPath(PrivConsoleID) = ResolvePath(CWD)
End Property

Public Property Get ConsoleID() As String
    ConsoleID = PrivConsoleID
End Property

Public Property Get TimeStr() As String
    TimeStr = DateTime.Time$
End Property

Public Property Get DateStr() As String
    DateStr = DateTime.Date$
End Property

Private Sub AssertCLIOnly()
    If IsCLIInput Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9006, "DSO", "CLI only functionality"
End Sub

Private Sub AssertLocalOnly()
    If FileKey = "" Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9007, "DSO", "local only functionality"
End Sub

Private Sub Class_Initialize()
    ReDim PendingCustomDownloads(0 To 0)
    IsConfigured = False
    Aborted = False
    PrivOutput = ""
End Sub

Public Sub CleanupScriptTasks()
    If UBound(PendingCustomDownloads) > 0 Then
        Dim X As Integer
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

Public Function ReadLine(Prompt As Variant) As String
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

Public Function GetKey() As Integer
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

Public Function GetASCII() As Integer
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

Public Sub Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean, NewScriptControl As ScriptControl, NewPrivParameters() As String, NewFileKey As String, NewRedirect As Boolean, NewDisableOutput As Boolean, NewIsRoot As Boolean)
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
End Sub

Private Sub AddCustomDownload(ByVal ResIndex As Integer)
    ReDim Preserve PendingCustomDownloads(0 To UBound(PendingCustomDownloads) + 1)
    PendingCustomDownloads(UBound(PendingCustomDownloads)) = ResIndex
End Sub

Private Function HasPendingCustomDownload(ByVal ResIndex As Integer) As Boolean
    HasPendingCustomDownload = False
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Function
    End If

    Dim X As Integer
    
    For X = 1 To UBound(PendingCustomDownloads)
        If PendingCustomDownloads(X) = ResIndex Then
            HasPendingCustomDownload = True
            Exit Function
        End If
    Next
End Function

Private Sub RemoveCustomDownload(ByVal ResIndex As Integer)
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Sub
    End If

    Dim NewPendingCustomDownloads() As Integer
    ReDim NewPendingCustomDownloads(1 To UBound(PendingCustomDownloads))
    
    Dim X As Integer
    Dim Y As Integer
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

Private Function DoDownload(Url As String, UsePost As Boolean, PostData As String, NoAuth As Boolean) As Integer
    Dim ResIndex As Integer
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

Public Function WAITFOR(ResIndex As Variant) As String
    While Not DownloadDone(ResIndex)
        Yield
        If Not HasPendingCustomDownload(ResIndex) Then
            Err.Raise vbObjectError + 9300, "DSO", "Invalid WaitFor Index " & ResIndex
            Exit Function
        End If
    Wend

    WAITFOR = DownloadResults(ResIndex)
    DownloadInUse(ResIndex) = False
    RemoveCustomDownload ResIndex
    Yield
End Function

Public Sub SayCOMM(ParamArray params() As Variant)
    Dim X As Integer
    Dim sStr As String
    For X = LBound(params) To UBound(params)
        If sStr <> "" Then
            sStr = sStr & " "
        End If
        sStr = sStr & params(X)
    Next X

    basWorld.SayCOMM sStr, ConsoleID
    Yield
End Sub

Public Sub CD(DIR As Variant)
    AssertLocalOnly

    cPath(PrivConsoleID) = ResolvePath(DIR)
    Yield
End Sub

Public Function ReadDir(RawPath As Variant) As Variant()
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

Public Sub EDIT(file As Variant)
    AssertCLIOnly

    Yield
    EditFile ResolvePath(file), PrivConsoleID
End Sub

Public Sub SayLine(s As Variant)
    If PrivRedirectOutput Then
        PrivOutput = PrivOutput & vbCr & s & vbCrLf
        Yield
    End If
    If PrivDisableOutput Then
        Yield
        Exit Sub
    End If
    basConsole.SayRaw PrivConsoleID, "" & s, False
End Sub

Public Sub Say(ParamArray params() As Variant)
    Dim X As Integer
    Dim sStr As String
    For X = LBound(params) To UBound(params)
        If sStr <> "" Then
            sStr = sStr & " "
        End If
        sStr = sStr & params(X)
    Next X

    Dim ScriptOutSplit() As String
    ScriptOutSplit = Split(sStr, vbCrLf)
    For X = LBound(ScriptOutSplit) To UBound(ScriptOutSplit)
        Yield
        basConsole.SayRaw PrivConsoleID, ScriptOutSplit(X)
    Next
End Sub

Public Sub CLIParse(Src As Variant, Dest As Variant)
    AssertLocalOnly

    Dim SrcStr As String
    SrcStr = GetFile(ResolvePath(Src))

    Dim DestStr As String
    DestStr = ParseCommandLineOptional(SrcStr)

    WriteFile ResolvePath(Dest), DestStr
End Sub

Public Function ResolveCommand(ByVal Command As Variant) As String
    ResolveCommand = basCommands.ResolveCommand(PrivConsoleID, Command)
End Function

Public Function ResolvePath(ByVal Path As Variant) As String
    ResolvePath = basCommands.ResolvePath(PrivConsoleID, Path)
End Function

Public Sub RUN(ParamArray XArr() As Variant)
    AssertLocalOnly

    Dim Script As String
    Script = XArr(0)
    Dim X As Integer
    Dim SParamArr() As String
    ReDim SParamArr(0 To UBound(XArr))
    For X = 0 To UBound(XArr)
        SParamArr(X) = "" & XArr(X)
    Next

    Yield
    Run_Script ResolveCommand(Script), PrivConsoleID, SParamArr, "RUN", "", False, False, False
    Yield
End Sub

Public Function CallScript(ParamArray XArr() As Variant) As String
    AssertLocalOnly

    Dim X As Integer
    Dim Script As String
    Script = XArr(0)

    Dim SParamArr() As String
    ReDim SParamArr(0 To UBound(XArr))
    For X = 0 To UBound(XArr)
        SParamArr(X) = "" & XArr(X)
    Next

    Yield
    CallScript = Run_Script(ResolveCommand(Script), PrivConsoleID, SParamArr, "CALL", "", False, True, Not PrivIsRoot)
    Yield
End Function

Public Function DOWNLOAD(Url As Variant) As Integer
     DOWNLOAD = DoDownload("" & Url, True, "", True)
End Function

Public Function DRAW(YPos As Variant, R As Variant, G As Variant, b As Variant, Mode As Variant)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    DrawItUp YPos, R, G, b, Mode, PrivConsoleID
    Yield
End Function

Public Function Connect(ParamArray XArr() As Variant) As String
    Dim Domain As String
    Domain = XArr(0)
    Dim Port As Integer
    Port = XArr(1)

    Yield

    If Port < 1 Or Port > 65535 Then
        Err.Raise vbObjectError + 9999, "DSO", "Invalid Port Number: " & Port
        Exit Function
    End If

    basWorld.SayCOMM "Connecting to " & UCase(Domain) & ":" & Port & "..."
    If Not PrivDisableOutput Then
        basConsole.SayRaw ConsoleID, "{green}Connecting to " & UCase(Domain) & ":" & Port & "..."
    End If

    Dim PostData As String
    PostData = "ver=2"
    If UBound(XArr) >= 2 Then
        Dim X As Integer
        For X = 2 To UBound(XArr)
            PostData = PostData & "&params[]=" & EncodeURLParameter(XArr(X))
        Next
    End If
    
    Dim DomainRequestIdx As Integer
    DomainRequestIdx = DoDownload(API_Server & API_Path & "domain_connect.php?d=" & EncodeURLParameter(Domain) & _
            "&port=" & EncodeURLParameter(Port), True, PostData, False)
    Dim DomainRequest As String
    DomainRequest = WAITFOR(DomainRequestIdx)

    If DomainRequest = "not found" Then
        Say "Connection Failed.{orange}"
    Else
        Dim DomainSplit() As String
        DomainSplit = Split(DomainRequest, ":-:")
        ' 0 = domain
        ' 1 = port
        ' 2 = filekey
        ' 3 = preamble
        ' 4 = code
        ' 5+ = params
    
        Dim DomainConnectParams() As String
        ReDim DomainConnectParams(0 To UBound(DomainSplit) - 4)

        Dim strDomain As String
        strDomain = DomainSplit(0)
        Dim strPort As String
        strPort = DomainSplit(1)
        Dim strFileKey As String
        strFileKey = DomainSplit(2)

        Dim b64decoded() As Byte
        b64decoded = basConsole.DecodeBase64(DomainSplit(3))
        Dim strPreamble As String
        strPreamble = StrConv(b64decoded, vbUnicode)

        For X = 0 To UBound(DomainConnectParams)
            b64decoded = basConsole.DecodeBase64(DomainSplit(X + 4))
            DomainConnectParams(X) = StrConv(b64decoded, vbUnicode)
        Next

        Dim strCode As String
        strCode = DomainConnectParams(0)
        DomainConnectParams(0) = "dso://" & strDomain & ":" & strPort
        
        If strFileKey = "" Then
            strFileKey = "EMPTY"
        End If
        Connect = Run_Script_Code(strCode, ConsoleID, DomainConnectParams, DomainConnectParams(0), strFileKey, False, True, Not PrivIsRoot, strPreamble)
    End If

    Yield
End Function

Public Sub LOGIN()
    AssertLocalOnly
    
    LoginNow PrivConsoleID
    Yield
End Sub

Public Sub LOGOUT()
    AssertLocalOnly
    
    LogoutNow PrivConsoleID
    Yield
End Sub

Public Sub UPLOAD(Domain As Variant, Port As Variant, Filename As Variant)
    AssertCLIOnly
    
    Yield

    Dim sFileData As String
    sFileData = GetFile(ResolvePath(Filename))

    Dim tempStrA As String

    tempStrA = EncodeBase64(StrConv(sFileData, vbFromUnicode))

    Dim PostData As String
    PostData = "ver=2&port=" & EncodeURLParameter("" & Port) & _
    "&d=" & EncodeURLParameter(Domain) & _
    "&filedata=" & EncodeURLParameter(tempStrA)
    
    SayCOMM "Attempting to upload: " & UCase(Domain) & ":" & Port

    Dim DomainRequestIdx As Integer
    DomainRequestIdx = DoDownload(API_Server & API_Path & "domain_upload.php", True, PostData, False)
    Dim DomainRequest As String
    DomainRequest = WAITFOR(DomainRequestIdx)

    Yield

    If Left(DomainRequest, 1) = "!" Then
        Err.Raise vbObjectError + 9666, "DSO", "Could not upload file to " & UCase(Domain) & ":" & Port
    End If

    SayCOMM "Upload OK: " & UCase(Domain) & ":" & Port
End Sub


Public Function ArgC() As Integer
    Yield
    ArgC = UBound(PrivParameters)
End Function

Public Function ArgV(Number As Variant) As String
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
