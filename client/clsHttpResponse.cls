VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsHttpResponse"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

Public Response As String
Public Code As Integer

Public Function IsSuccess() As Boolean
    IsSuccess = Code >= 200 And Code <= 299
End Function

Public Function RaiseForStatus()
    If Not IsSuccess() Then
        Err.Raise vbObjectError + 6000 + Code, "DSO", "HTTP error " & Code & ": " & StripAfterNewline(Response)
    End If
End Function
