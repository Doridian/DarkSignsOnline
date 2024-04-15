Attribute VB_Name = "basScriptCrypto"
Option Explicit

Public Function DSOSingleEncrypt(ByVal tmpS As String) As String
    DSOSingleEncrypt = "0" & EncodeBase64Str(tmpS)
End Function

Public Function DSOSingleDecrypt(ByVal tmpS As String) As String
    Dim CryptoVer As String
    CryptoVer = Left(tmpS, 1)
    tmpS = Mid(tmpS, 2)
    Select Case CryptoVer
        Case "0":
            DSOSingleDecrypt = DecodeBase64Str(tmpS)
        Case "N":
            DSOSingleDecrypt = tmpS
        Case Else:
            Err.Raise vbObjectError + 9343, , "Invalid crypto method " & CryptoVer
    End Select
End Function

Public Function DSODecryptScript(ByVal Source As String) As String
    If LCase(Left(Source, 6)) = "^all" & vbCrLf Then
        Source = Mid(Source, 7)
    End If

    Dim Lines() As String
    Lines = Split(Source, vbCrLf)
    Dim X As Long, Line As String
    For X = LBound(Lines) To UBound(Lines)
        Line = Lines(X)
        If Left(Line, 2) = "^^" Then
            Lines(X) = DSOSingleDecrypt(Mid(Line, 3))
        ElseIf Left(Line, 1) = "^" Then
            Lines(X) = Mid(Line, 2)
        End If
    Next
    DSODecryptScript = Join(Lines, vbCrLf)
End Function

Public Function DSOCompileScript(ByVal Source As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim DefaultEncrypt As Boolean
    DefaultEncrypt = False
    If LCase(Left(Source, 6)) = "^all" & vbCrLf Then
        DefaultEncrypt = True
        Source = Mid(Source, 7)
    End If
    DSOCompileScript = ParseCommandLineOptional(Source, AllowCommands, True, DefaultEncrypt)
End Function

