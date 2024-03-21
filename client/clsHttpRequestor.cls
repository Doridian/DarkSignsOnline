VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsHttpRequestor"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

Public Url As String
Public Method As String
Public UserName As String
Public Password As String
Public consoleID As Integer
Public IsCustomDownload As Integer
Public PostData As String

Private Done As Boolean
Private DoneForever As Boolean
Private Retries As Integer
Private WithEvents HttpRequest As cHttpRequest
Attribute HttpRequest.VB_VarHelpID = -1
Private ResponseSent As Boolean

Private Const HTTPREQUEST_SETCREDENTIALS_FOR_SERVER As Long = 0

Private Sub Class_Initialize()
    Set HttpRequest = Nothing
    Done = True
    DoneForever = False
    ResponseSent = False
    Retries = 0
End Sub

Public Function SafeToDelete() As Boolean
    SafeToDelete = DoneForever Or (HttpRequest Is Nothing)
End Function

Private Sub SetDoneForever()
    If Not ResponseSent Then
        If IsCustomDownload > 0 Then
            basWorld.Process "[error]", Url, consoleID, IsCustomDownload
        End If
        ResponseSent = True
    End If
    DoneForever = True
    Done = True
    basWorld.CleanHttpRequests
End Sub

Public Sub Abort()
    SetDoneForever
    Abort_
End Sub

Private Sub Abort_()
    If Done Then
        Exit Sub
    End If
    If Not (HttpRequest Is Nothing) Then
        HttpRequest.Abort
    End If
    Done = True
End Sub

Public Sub Send()
    If DoneForever Then
        SayCOMM "Request Send while DoneForever: " & Url
        Exit Sub
    End If

    Abort_
    Set HttpRequest = New cHttpRequest

    HttpRequest.SetTimeouts basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000
    Done = False

    HttpRequest.Open_ Method, Url, True
    If UserName <> "" And Password <> "" Then
        HttpRequest.SetCredentials UserName, Password, HTTPREQUEST_SETCREDENTIALS_FOR_SERVER
    End If

    HttpRequest.SetRequestHeader "User-Agent", "Mozilla/4.0 (compatible; Win32; VbAsyncSocket; Dark Signs Online " & VersionStr() & ")"

    If Method = "POST" Then
        HttpRequest.SetRequestHeader "Content-Type", "application/x-www-form-urlencoded"
        HttpRequest.Send PostData
    Else
        HttpRequest.Send
    End If
End Sub

Private Sub HttpRequest_OnError(ByVal ErrorNumber As Long, ByVal ErrorDescription As String)
    If Done Then
        SayCOMM "Request OnError while Done: " & Url
        Exit Sub
    End If
    Done = True
    
    ManageSockError "Socket error code " & Str(ErrorNumber) & " = " & ErrorDescription
End Sub

Private Sub HttpRequest_OnResponseFinished()
    If Done Then
        SayCOMM "Request OnResponseFinished while Done: " & Url
        Exit Sub
    End If
    Done = True

    If HttpRequest.Status < 200 Or HttpRequest.Status > 299 Then
        ManageSockError "HTTP Status " & Str(HttpRequest.Status)
        Exit Sub
    End If

    basWorld.Process HttpRequest.ResponseText, Url, consoleID, IsCustomDownload
    ResponseSent = True
    SetDoneForever
End Sub

Private Sub ManageSockError(Reason As String)
    If DoneForever Then
        SayCOMM "Request ManageSockError while DoneForever: " & Url
        Exit Sub
    End If

    Dim AllowRetry As Boolean
    AllowRetry = Retries < basWorld.MaxSockRetries
    If IsCustomDownload > 0 And DownloadAborted(IsCustomDownload) Then
        AllowRetry = False
    End If

    'on error consider retrying
    If AllowRetry Then
        Retries = Retries + 1
        
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents

        Send

        If InStr(i(Url), "z_online") > 0 Then Exit Sub 'don't show these errors
        If InStr(i(Url), "chat") > 0 Then Exit Sub 'don't show these errors
        SayCOMM "Connection failed to [" & Url & "] because of " & Reason & ". Retry " & Trim(Str(Retries)) & " of " & Trim(Str(basWorld.MaxSockRetries)) & "."
   Else
        SayCOMM "Connection failed to [" & Url & "] because of " & Reason & ". Retry count expired."
        SetDoneForever
   End If
End Sub

