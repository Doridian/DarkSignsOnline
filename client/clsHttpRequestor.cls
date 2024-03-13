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
Public ConsoleID As Integer
Public IsCustomDownload As Integer
Public PostData As String

Private Aborted As Boolean
Private Retries As Integer
Private WithEvents HttpRequest As cHttpRequest
Attribute HttpRequest.VB_VarHelpID = -1

Private Sub Class_Initialize()
    Set HttpRequest = New cHttpRequest
    Aborted = False
    Retries = 0
End Sub

Public Sub Abort()
    Aborted = True
    HttpRequest.Abort
End Sub

Public Sub Send()
    Abort
    Set HttpRequest = New cHttpRequest
    HttpRequest.SetTimeouts basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000, basWorld.TimeOutSeconds * 1000
    Aborted = False

    HttpRequest.Open_ Method, Url, True
    HttpRequest.SetCredentials UserName, Password, 0

    If Method = "POST" Then
        HttpRequest.SetRequestHeader "Content-Type", "application/x-www-form-urlencoded"
        HttpRequest.Send PostData
    Else
        HttpRequest.Send
    End If
End Sub

Private Sub HttpRequest_OnError(ByVal ErrorNumber As Long, ByVal ErrorDescription As String)
    If Aborted Then
        Exit Sub
    End If
    Aborted = True
    
    ManageSockError "Socket error code " & str(ErrorNumber) & " = " & ErrorDescription
End Sub

Private Sub HttpRequest_OnResponseFinished()
    If Aborted Then
        Exit Sub
    End If
    Aborted = True

    If HttpRequest.Status < 200 Or HttpRequest.Status > 499 Then
        ManageSockError "HTTP Status " & str(HttpRequest.Status)
        Exit Sub
    End If

    basWorld.Process HttpRequest.ResponseText, Url, ConsoleID, IsCustomDownload
End Sub

Private Sub ManageSockError(Reason As String)
    'on error consider retrying
    If Retries < basWorld.MaxSockRetries Then
        Retries = Retries + 1
        
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents
        DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents: DoEvents

        Send

        If InStr(i(Url), "z_online") > 0 Then Exit Sub 'don't show these errors
        If InStr(i(Url), "chat") > 0 Then Exit Sub 'don't show these errors
        SayComm "Connection failed to [" & Url & "] because of " & Reason & ". Retry " & Trim(str(Retries)) & " of " & Trim(str(basWorld.MaxSockRetries)) & "."
   Else
        SayComm "Connection failed to [" & Url & "] because of " & Reason & ". Retry count expired."
   End If
End Sub

