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

Private consoleID As Integer
Private ScriptFrom As String
Private IsCLIInput As Boolean
Private IsConfigured As Boolean
Private SControl As ScriptControl

Private Sub Class_Initialize()
    IsConfigured = False
End Sub

Public Sub Quit()
    Err.Raise 9002, "DSO", "Script exited"
    CancelScript(consoleID) = True
End Sub

Public Sub Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean, NewScriptControl As ScriptControl)
    If IsConfigured Then
        Exit Sub
    End If
    IsConfigured = True
    consoleID = NewConsoleID
    ScriptFrom = NewScriptFrom
    IsCLIInput = NewIsCLIInput
    Set SControl = NewScriptControl
End Sub

Private Function DoDownload(Url As String, UsePost As Boolean, PostData As String, NoAuth As Boolean) As String
    Dim ResIndex As Integer
    For ResIndex = 1 To 99
        If Not DownloadInUse(ResIndex) Then
            Exit For
        End If
    Next
    DownloadInUse(ResIndex) = True
    DownloadDone(ResIndex) = False
    
    Yield
    RunPage Url, consoleID, UsePost, PostData, ResIndex, True
    
    While Not DownloadDone(ResIndex)
        DoEvents
        If CancelScript(consoleID) Then
            GoTo EndDownload
        End If
    Wend
    
    DoDownload = DownloadResults(ResIndex)
    DownloadInUse(ResIndex) = False

    Exit Function
EndDownload:
    DownloadAborted(ResIndex) = True
    Err.Raise 9001, "DSO", "Script canceled by Ctrl+C"
End Function

Public Sub SayCOMM(s As String)
    basWorld.SayCOMM s
    Yield
End Sub

Public Sub CD(dir As String)
    ChangeDir dir, consoleID
    Yield
End Sub

Public Sub SAY(s As String)
    basConsole.SAY consoleID, s
    Yield
End Sub

Public Sub RUN(Script As String)
    Yield
    Run_Script cPath(consoleID) & "/" & Script, consoleID, "", "RUN"
    Yield
End Sub

Public Function DOWNLOAD(Url As String) As String
     DOWNLOAD = DoDownload(Url, True, "", True)
End Function

Public Sub LOGIN()
    LoginNow consoleID
End Sub

Public Sub Yield()
    DoEvents
    If CancelScript(consoleID) Then
        Err.Raise 9001, "DSO", "Script canceled by Ctrl+C"
    End If
End Sub
