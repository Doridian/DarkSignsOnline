VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsHttpScriptRequest"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

Public ResIndex As Long
Public RaiseForStatus As Boolean

Private Sub Class_Initialize()
    ' Nothing
End Sub

Public Function ToString() As String
Attribute ToString.VB_UserMemId = 0
    ToString = "[HTTP requerst " & ResIndex & "]"
End Function
