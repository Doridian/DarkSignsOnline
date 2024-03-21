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

Private PrivRedirectOutput As Boolean
Private PrivOutput As String

Private PendingCustomDownloads() As Integer

Public Property Get UserName() As String
    UserName = myUsername
End Property

Public Property Let UserName(ByVal NewValue As String)
    AssertCLIOnly
    SetUsername NewValue, consoleID
End Property

Public Property Get Password() As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
End Property

Public Property Let Password(ByVal NewValue As String)
    AssertCLIOnly
    SetPassword NewValue, consoleID
End Property

Public Property Get consoleID() As String
    consoleID = PrivConsoleID
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
    Aborted = True
    Err.Raise 9006, "DSO", "Script tried to execute CLI only functionality"
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
    GetKeyWaiting(consoleID) = 0
    GetAsciiWaiting(consoleID) = 0
    WaitingForInput(consoleID) = False
    WaitingForInputReturn(consoleID) = ""
End Sub

Public Sub Quit()
    Aborted = True
    Err.Raise 9002, "DSO", "Script exited"
End Sub

Public Function ScriptGetOutput() As String
    ScriptGetOutput = PrivOutput
End Function


Public Function ReadLine(Prompt As String) As String
    If PrivRedirectOutput Then
        Exit Function
    End If

    cPath_tmp(consoleID) = cPath(consoleID)
    cPath(consoleID) = Prompt
    WaitingForInput(consoleID) = True
    
    New_Console_Line consoleID

    While WaitingForInput(consoleID)
        Yield
    Wend
    ReadLine = WaitingForInputReturn(consoleID)
End Function

Public Function GetKey() As Integer
    If PrivRedirectOutput Then
        Exit Function
    End If

    GetKeyWaiting(consoleID) = -1
    While GetKeyWaiting(consoleID) = -1
        Yield
    Wend
    GetKey = GetKeyWaiting(consoleID)
End Function

Public Function GetASCII() As Integer
    If PrivRedirectOutput Then
        Exit Function
    End If

    GetAsciiWaiting(consoleID) = -1
    While GetAsciiWaiting(consoleID) = -1
        Yield
    Wend
    GetASCII = GetAsciiWaiting(consoleID)
End Function

Public Sub Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean, NewScriptControl As ScriptControl, NewPrivParameters() As String, NewFileKey As String, NewRedirect As Boolean)
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
    PrivRedirectOutput = NewRedirect
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
        Err.Raise 9100, "DSO", "No free download slots"
        Exit Function
    End If

    DownloadInUse(ResIndex) = True
    DownloadDone(ResIndex) = False

    AddCustomDownload ResIndex

    RunPage Url, PrivConsoleID, UsePost, PostData, ResIndex, True
    Yield
End Function

Public Function WAITFOR(ResIndex As Variant) As String
    While Not DownloadDone(ResIndex)
        Yield
        If Not HasPendingCustomDownload(ResIndex) Then
            WAITFOR = "[invalid]"
            Exit Function
        End If
    Wend

    WAITFOR = DownloadResults(ResIndex)
    DownloadInUse(ResIndex) = False
    RemoveCustomDownload ResIndex
    Yield
End Function

Public Sub SayCOMM(s As String)
    basWorld.SayCOMM s, consoleID
    Yield
End Sub

Public Sub CD(dir As String)
    ChangeDir dir, PrivConsoleID
    Yield
End Sub

Public Sub SAY(s As String)
    If PrivRedirectOutput Then
        PrivOutput = PrivOutput & s & vbCrLf
        Exit Sub
    End If
    basConsole.SAY PrivConsoleID, s
    Yield
End Sub

Private Sub SayMultiline(ScriptOutput As String)
    Dim X As Integer
    If PrivRedirectOutput Then
        PrivOutput = PrivOutput & ScriptOutput
    Else
        Dim ScriptOutSplit() As String
        ScriptOutSplit = Split(ScriptOutput, vbCrLf)
        For X = LBound(ScriptOutSplit) To UBound(ScriptOutSplit)
            Yield
            basConsole.SAY PrivConsoleID, ScriptOutSplit(X)
        Next
    End If
End Sub

Public Function RUN(ParamArray XArr() As Variant) As String
    Dim X As Integer
    Dim Script As String
    Script = XArr(0)

    Dim SParamArr() As String
    ReDim SParamArr(0 To UBound(XArr))
    For X = 0 To UBound(XArr)
        SParamArr(X) = "" & XArr(X)
    Next

    Yield
    ' TODO: Add PATH resolution in /system/commands
    RUN = Run_Script(cPath(PrivConsoleID) & "/" & Script, PrivConsoleID, SParamArr, "RUN", "", False)
    SayMultiline RUN
    Yield
End Function

Public Function DOWNLOAD(Url As String) As Integer
     DOWNLOAD = DoDownload(Url, True, "", True)
End Function

Public Function DRAW(YPos As Variant, R As Variant, G As Variant, b As Variant, Mode As String)
    If PrivRedirectOutput Then
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
        Err.Raise 9999, "DSO", "Invalid Port Number: " & Port
        Exit Function
    End If

    basWorld.SayCOMM "Connecting to " & UCase(Domain) & ":" & Port & "..."
    basConsole.SAY consoleID, "{green}Connecting to " & UCase(Domain) & ":" & Port & "...", False

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
        SAY "Connection Failed.{orange}"
    Else
        Dim DomainSplit() As String
        DomainSplit = Split(DomainRequest, ":-:")
        ' 0 = domain
        ' 1 = port
        ' 2 = filekey
        ' 3 = code
        ' 4+ = params
    
        Dim DomainConnectParams() As String
        ReDim DomainConnectParams(0 To UBound(DomainSplit) - 3)

        Dim strDomain As String
        strDomain = DomainSplit(0)
        Dim strPort As String
        strPort = DomainSplit(1)
        Dim strFileKey As String
        strFileKey = DomainSplit(2)

        For X = 0 To UBound(DomainConnectParams)
            Dim b64decoded() As Byte
            b64decoded = basConsole.DecodeBase64(DomainSplit(X + 3))
            Dim newS As String
            DomainConnectParams(X) = StrConv(b64decoded, vbUnicode)
        Next

        Dim strCode As String
        strCode = DomainConnectParams(0)
        DomainConnectParams(0) = "dso://" & strDomain & ":" & strPort

        Connect = Run_Script_Code(strCode, consoleID, DomainConnectParams, DomainConnectParams(0), strFileKey, False)
        SayMultiline Connect
    End If

    Yield
End Function

Public Sub LOGIN()
    LoginNow PrivConsoleID
    Yield
End Sub

Public Sub LOGOUT()
    AssertCLIOnly
    LogoutNow PrivConsoleID
    Yield
End Sub

Public Sub UPLOAD(Domain As String, Port As Variant, filename As String)
    AssertCLIOnly
    Yield
    UploadToDomain Domain, Port, filename, consoleID
    Yield
End Sub


Public Function ArgC() As Integer
    ArgC = UBound(PrivParameters)
End Function

Public Function ArgV(Number As Variant) As String
    If Number < LBound(PrivParameters) Or Number > UBound(PrivParameters) Then
        ArgV = ""
        Exit Function
    End If

    ArgV = PrivParameters(Number)
End Function

Public Sub Yield()
    DoEvents
    If CancelScript(PrivConsoleID) Then
        Aborted = True
        Err.Raise 9001, "DSO", "Script canceled by Ctrl+C"
    End If
End Sub
