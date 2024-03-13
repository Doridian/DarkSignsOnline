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

Public Index As Integer
Public Url As String
Public ConsoleID As Integer

Private Aborted As Boolean

Public WithEvents HttpRequest As cHttpRequest
Attribute HttpRequest.VB_VarHelpID = -1

Private Sub Class_Initialize()
    Set HttpRequest = New cHttpRequest
    Aborted = False
End Sub

Public Sub Abort()
    Aborted = True
    HttpRequest.Abort
End Sub

Private Sub HttpRequest_OnResponseFinished()
    If Aborted Then
        Exit Sub
    End If
    frmConsole.tmrTimeout(Index).Enabled = False
    If HttpRequest.Status < 200 Or HttpRequest.Status > 499 Then
        frmConsole.ManageSockError Index, "HTTP Status " & str(HttpRequest.Status)
        Exit Sub
    End If

    basWorld.Process HttpRequest.ResponseText, Url, ConsoleID, Index
    basWorld.HttpRequests(Index).InUse = False
End Sub

