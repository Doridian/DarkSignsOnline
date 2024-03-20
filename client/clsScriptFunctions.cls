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

Private Sub Class_Initialize()
    IsConfigured = False
End Sub

Public Sub Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean)
    If IsConfigured Then
        Exit Sub
    End If
    IsConfigured = True
    ConsoleID = NewConsoleID
    ScriptFrom = NewScriptFrom
    IsCLIInput = NewIsCLIInput
End Sub

Public Sub SayCOMM(S As String)
    basWorld.SayCOMM S
End Sub

Public Sub CD(dir As String)
    ChangeDir dir, ConsoleID
End Sub

Public Sub SAY(S As String)
    basConsole.SAY ConsoleID, S
End Sub

Public Sub RUN(Script As String)
    Run_Script cPath(ConsoleID) & "/" & Script, ConsoleID, "", "RUN"
End Sub
