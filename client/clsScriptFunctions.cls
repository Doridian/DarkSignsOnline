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

Private ConsoleID As Integer
Private ScriptFrom As String
Private IsCLIInput As Boolean
Private IsConfigured As Boolean
Private SControl As ScriptControl

Private Sub Class_Initialize()
    IsConfigured = False
End Sub

Public Sub Quit()
    Err.Raise 9002, "DSO", "Script exited"
    CancelScript(ConsoleID) = True
End Sub

Public Sub Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean, NewScriptControl As ScriptControl)
    If IsConfigured Then
        Exit Sub
    End If
    IsConfigured = True
    ConsoleID = NewConsoleID
    ScriptFrom = NewScriptFrom
    IsCLIInput = NewIsCLIInput
    Set SControl = NewScriptControl
End Sub

Public Sub SayCOMM(S As String)
    Yield
    basWorld.SayCOMM S
End Sub

Public Sub CD(dir As String)
    Yield
    ChangeDir dir, ConsoleID
End Sub

Public Sub SAY(S As String)
    Yield
    basConsole.SAY ConsoleID, S
End Sub

Public Sub RUN(Script As String)
    Yield
    Run_Script cPath(ConsoleID) & "/" & Script, ConsoleID, "", "RUN"
End Sub

Public Sub Yield()
    DoEvents
    If CancelScript(ConsoleID) Then
        Err.Raise 9001, "DSO", "Script canceled by Ctrl+C"
    End If
End Sub

