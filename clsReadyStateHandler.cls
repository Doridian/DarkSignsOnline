VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsReadyStateHandler"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

Public Index As Integer

Public Sub OnReadyStateChange()
Attribute OnReadyStateChange.VB_UserMemId = 0
    Dim HttpRequest As basWorld.HttpRequest
    HttpRequest = basWorld.HttpRequests(Index)
    If HttpRequest.Http.readyState = 4 Then
        frmConsole.tmrTimeout(Index).Enabled = False
        If HttpRequest.Http.Status < 200 Or HttpRequest.Http.Status > 499 Then
            frmConsole.ManageSockError Index, "HTTP Status " & str(HttpRequest.Http.Status)
            Exit Sub
        End If

        basWorld.Process HttpRequest.Http.responseText, HttpRequest.Url, HttpRequest.consoleID, Index
        basWorld.HttpRequests(Index).InUse = False
    End If
End Sub
