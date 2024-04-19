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
Public PreParsedResponse As Variant

Public Property Get Response() As Variant
    RaiseForStatus

    Select Case ResponseType
        Case "bool_1":
            Response = (Trim(Response) = "1")
        Case "lines":
            Response = Split(Response, vbCrLf)
        Case "pre_parsed":
            Response = PreParsedResponse
        Case Else:
            Response = Response
    End Select
End Property

Public Function IsSuccess() As Boolean
    IsSuccess = Code >= 200 And Code <= 299
End Function

Public Function RaiseForStatus()
    If Not IsSuccess() Then
        Err.Raise vbObjectError + 6000 + Code, , "HTTP error " & Code & ": " & StripAfterNewline(Response)
    End If
End Function

Public Function ToString() As String
Attribute ToString.VB_UserMemId = 0
    If ResponseType = "pre_parsed" Then
        ToString = "[HTTP PreParsed]"
        Exit Function
    End If
    ToString = "[HTTP " & Code & "] " & RawResponse
End Function
