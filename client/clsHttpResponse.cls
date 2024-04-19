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

Public RawResponse As String
Public Code As Integer
Public ResponseType As String

Public Property Get Response() As Variant
    RaiseForStatus

    Select Case ResponseType
        Case "bool_1":
            Response = (Trim(RawResponse) = "1")
        Case "lines":
            Response = Split(RawResponse, vbCrLf)
        Case Else:
            Response = RawResponse
    End Select
End Property

Public Function IsSuccess() As Boolean
    IsSuccess = Code >= 200 And Code <= 299
End Function

Public Function RaiseForStatus()
    If Not IsSuccess() Then
        Err.Raise vbObjectError + 6000 + Code, , "HTTP error " & Code & ": " & StripAfterNewline(RawResponse)
    End If
End Function
