Attribute VB_Name = "basScriptCrypto"
Option Explicit

Private Function DSOSingleEncrypt(ByVal tmpS As String) As String
    If tmpS = "" Then
        DSOSingleEncrypt = "X"
        Exit Function
    End If
    Dim tmpB() As Byte
    Dim X As Long
    tmpB = StrConv(tmpS, vbFromUnicode)
    For X = LBound(tmpB) To UBound(tmpB)
        tmpB(X) = tmpB(X) Xor 42
    Next
    DSOSingleEncrypt = "1" & EncodeBase64Bytes(tmpB)
End Function

Private Function DSOSingleDecrypt(ByVal tmpS As String) As String
    Dim CryptoVer As String
    CryptoVer = Left(tmpS, 1)
    tmpS = Mid(tmpS, 2)
    Dim tmpB() As Byte
    Dim X As Long

    Select Case CryptoVer
        Case "0":
            DSOSingleDecrypt = DecodeBase64Str(tmpS)
        Case "1":
            tmpB = DecodeBase64Bytes(tmpS)
            For X = LBound(tmpB) To UBound(tmpB)
                tmpB(X) = tmpB(X) Xor 42
            Next
            DSOSingleDecrypt = StrConv(tmpB, vbUnicode)
        Case "N":
            DSOSingleDecrypt = tmpS
        Case "X":
            ' Empty part
            DSOSingleDecrypt = ""
        Case "H":
            ' Do nothing, header!
            DSOSingleDecrypt = ""
        Case Else:
            Err.Raise vbObjectError + 9343, , "Invalid crypto line " & CryptoVer & tmpS
    End Select
End Function

Public Function DSODecryptScript(ByVal Source As String) As String
    If UCase(Left(Source, 24)) <> "OPTION DSCRIPTCOMPILED" & vbCrLf Then
        DSODecryptScript = Source
        Exit Function
    End If

    DSODecryptScript = DSOSingleDecrypt(Mid(Source, 25))
End Function

Public Function DSOCompileScript(ByVal Source As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim ParsedSource As String
    ParsedSource = DSODecryptScript(Source)

    DSOCompileScript = "Option DScriptCompiled" & vbCrLf & DSOSingleEncrypt(ParsedSource)
End Function

