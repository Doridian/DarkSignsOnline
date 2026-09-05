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

Public url As String
Public Method As String
Public UserName As String
Public Password As String
Public IsCustomDownload As Long
Public PostData As String

Private Done As Boolean
Private DoneForever As Boolean
Private Retries As Long
Private WithEvents HttpRequest As cHttpRequest
Attribute HttpRequest.VB_VarHelpID = -1
Private ResponseSent As Boolean

Private Const HTTPREQUEST_SETCREDENTIALS_FOR_SERVER As Long = 0

Private Declare Function GetTickCount Lib "kernel32" () As Long

Private Sub Class_Initialize()
    Set HttpRequest = New cHttpRequest
    HttpRequest.Option_(WinHttpRequestOption_EnableHttp1_1) = True
    HttpRequest.Option_(WinHttpRequestOption_UserAgentString) = "Mozilla/4.0 (compatible; Win32; VbAsyncSocket; DarkSignsOnline/" & VersionStr() & ")"
    HttpRequest.SetTimeouts basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000
    DoneForever = True
End Sub

Public Sub Rearm()
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
            basWorld.Process "[error]", 666, url, IsCustomDownload
        End If
        ResponseSent = True
    End If
    DoneForever = True
    Done = True
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
        SayCOMM "Request Send while DoneForever: " & url
        Exit Sub
    End If

    Abort_

    Done = False

    HttpRequest.Open_ Method, url, True
    If UserName <> "" And Password <> "" Then
        HttpRequest.SetCredentials UserName, Password, HTTPREQUEST_SETCREDENTIALS_FOR_SERVER
    End If

    HttpRequest.SetRequestHeader "DSO-Protocol-Version", "2"

    If Method = "POST" Then
        HttpRequest.SetRequestHeader "Content-Type", "application/x-www-form-urlencoded"
        HttpRequest.Send PostData
    Else
        HttpRequest.Send
    End If
End Sub

Private Sub HttpRequest_OnError(ByVal ErrorNumber As Long, ByVal ErrorDescription As String)
    If Done Then
        SayCOMM "Request OnError while Done: " & url
        Exit Sub
    End If
    Done = True
    
    ManageSockError "Socket error code " & ErrorNumber & " = " & ErrorDescription, True
End Sub

Private Function IsHTTPCodeRetry(Code As Long) As Boolean
    IsHTTPCodeRetry = False
    If Code >= 200 And Code <= 299 Then
        Exit Function
    End If
    If Code >= 400 And Code <= 499 Then
        Exit Function
    End If
    IsHTTPCodeRetry = True
End Function

Private Sub HttpRequest_OnResponseFinished()
    If Done Then
        SayCOMM "Request OnResponseFinished while Done: " & url
        Exit Sub
    End If
    Done = True

    If IsHTTPCodeRetry(HttpRequest.Status) Then
        If ManageSockError("HTTP Status " & HttpRequest.Status, False) Then
            Exit Sub
        End If
    End If

    basWorld.Process HttpRequest.ResponseText, HttpRequest.Status, url, IsCustomDownload
    ResponseSent = True
    SetDoneForever
End Sub

Private Function ManageSockError(ByVal Reason As String, ByVal AllowSetDoneForever As Boolean) As Boolean
    If DoneForever Then
        SayCOMM "Request ManageSockError while DoneForever: " & url
        Exit Function
    End If

    Dim ShowErrors As Boolean
    Dim AllowRetry As Boolean
    ShowErrors = True
    AllowRetry = Retries < basWorld.MaxSockRetries
    If IsCustomDownload > 0 Then
        If DownloadAborted(IsCustomDownload) Then
            AllowRetry = False
            ShowErrors = False
        End If
    End If
    ManageSockError = AllowRetry

    'on error consider retrying
    If AllowRetry Then
        Retries = Retries + 1
        
        Dim EndTime As Long
        EndTime = GetTickCount() + 1000
        While GetTickCount() < EndTime
            DoEvents
        Wend

        Send

        If ShowErrors Then
            SayCOMM "Connection failed to [" & url & "] because of " & Reason & ". Retry " & Trim(Str(Retries)) & " of " & Trim(Str(basWorld.MaxSockRetries)) & "."
        End If
   Else
        If ShowErrors Then
            SayCOMM "Connection failed to [" & url & "] because of " & Reason & ". Retry count expired."
        End If
        If AllowSetDoneForever Then SetDoneForever
   End If
End Function

