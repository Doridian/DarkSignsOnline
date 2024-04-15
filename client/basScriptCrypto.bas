Attribute VB_Name = "basScriptCrypto"
Option Explicit

Private Function DSOSingleEncrypt(ByVal tmpS As String) As String
    If tmpS = "" Then
        DSOSingleEncrypt = "X"
        Exit Function
    End If

    Dim tmpB() As Byte, tmpK() As Byte
    Dim X As Long, Y As Long

    ReDim tmpK(0 To 31)
    For X = 0 To 31
        tmpK(X) = Int((Rnd * 254) + 1)
    Next

    tmpB = StrConv(tmpS, vbFromUnicode)
    Y = UBound(tmpK) + 1
    For X = 0 To UBound(tmpB)
        tmpB(X) = tmpB(X) Xor (42 Xor tmpK(LBound(tmpK) + (X Mod Y)))
    Next
    DSOSingleEncrypt = "2" & EncodeBase64Bytes(tmpK) & ":" & EncodeBase64Bytes(tmpB)
End Function

Private Function DSOSingleDecrypt(ByVal tmpS As String) As String
    Dim CryptoVer As String
    CryptoVer = Left(tmpS, 1)
    tmpS = Mid(tmpS, 2)
    Dim tmpSA() As String
    Dim tmpB() As Byte, tmpK() As Byte
    Dim X As Long, Y As Long

    Select Case CryptoVer
        Case "0":
            DSOSingleDecrypt = DecodeBase64Str(tmpS)
        Case "1":
            tmpB = DecodeBase64Bytes(tmpS)
            For X = 0 To UBound(tmpB)
                tmpB(X) = tmpB(X) Xor 42
            Next
            DSOSingleDecrypt = StrConv(tmpB, vbUnicode)
        Case "2":
            tmpSA = Split(tmpS, ":")
            tmpK = DecodeBase64Bytes(tmpSA(0))
            tmpB = DecodeBase64Bytes(tmpSA(1))
            Y = UBound(tmpK) + 1
            For X = 0 To UBound(tmpB)
                tmpB(X) = tmpB(X) Xor (42 Xor tmpK(X Mod Y))
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

    Dim Lines() As String
    Lines = Split(Mid(Source, 25), vbCrLf)
    Dim X As Long, Line As String
    For X = LBound(Lines) To UBound(Lines)
        Line = Lines(X)
        If Trim(Line) = "" Then
            Lines(X) = ""
        Else
            Lines(X) = DSOSingleDecrypt(Line)
        End If
    Next
    DSODecryptScript = Join(Lines, vbCrLf)
End Function

Public Function DSOCompileScript(ByVal Source As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim ParsedSource As String
    ParsedSource = DSODecryptScript(Source)

    'Line by line encryption is bad...
    'Dim Lines() As String
    'Lines = Split(ParsedSource, vbCrLf)
    'Dim X As Long, Line As String
    'For X = LBound(Lines) To UBound(Lines)
    '    Line = Lines(X)
    '    If Trim(Line) = "" Then
    '        Lines(X) = ""
    '    Else
    '        Lines(X) = DSOSingleEncrypt(Line)
    '    End If
    'Next
    'ParsedSource = Join(Lines, vbCrLf)

    ParsedSource = DSOSingleEncrypt(ParsedSource)

    DSOCompileScript = "Option DSciptCompiled" & vbCrLf & ParsedSource
End Function

