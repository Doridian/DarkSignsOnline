Attribute VB_Name = "basScriptCrypto"
Option Explicit

Public Function DSOSingleEncrypt(ByVal tmpS As String) As String
    If tmpS = "" Then
        DSOSingleEncrypt = "X"
        Exit Function
    End If
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
        Case "X":
            ' Empty part
            DSOSingleDecrypt = ""
        Case "H":
            ' Do nothing, header!
            DSOSingleDecrypt = ""
        Case Else:
            Err.Raise vbObjectError + 9343, , "Invalid crypto method " & CryptoVer
    End Select
End Function

Public Function DSODecryptScript(ByVal Source As String) As String
    If UCase(Left(Source, 17)) <> "OPTION COMPILED" & vbCrLf Then
        DSODecryptScript = Source
        Exit Function
    End If

    Dim Lines() As String
    Lines = Split(Source, vbCrLf)
    Dim X As Long, Line As String
    For X = LBound(Lines) + 1 To UBound(Lines)
        Line = Lines(X)
        If Trim(Line) = "" Then
            Lines(X) = ""
        Else
            Lines(X) = DSOSingleDecrypt(Line)
        End If
    Next
    Lines(0) = "'" & Lines(0)
    DSODecryptScript = Join(Lines, vbCrLf)
End Function

Public Function DSOCompileScript(ByVal Source As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim ParsedSource As String
    ParsedSource = DSODecryptScript(Source)

    Dim Lines() As String
    Lines = Split(ParsedSource, vbCrLf)
    Dim X As Long, Line As String
    For X = LBound(Lines) To UBound(Lines)
        Line = Lines(X)
        If Trim(Line) = "" Then
            Lines(X) = ""
        Else
            Lines(X) = DSOSingleEncrypt(Line)
        End If
    Next

    DSOCompileScript = "Option Compiled" & vbCrLf & Join(Lines, vbCrLf)
End Function

