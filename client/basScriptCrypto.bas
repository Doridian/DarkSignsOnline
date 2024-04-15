Attribute VB_Name = "basScriptCrypto"
Option Explicit

Public Const EncryptedHeader = "Option DSciptCompiled" & vbCrLf
Public Const EncryptedCanary = "Option DSciptCompiledLoaded" & vbCrLf
Public Const EncryptedLineLen = 140

Private Function DSOSingleEncrypt(ByVal tmpS As String, ByVal ScriptKey As String, ByVal NoWrap As Boolean) As String
    If tmpS = "" Then
        DSOSingleEncrypt = "X"
        Exit Function
    End If

    Dim CryptoVer As String
    Dim tmpB() As Byte, tmpB2() As Byte, tmpK() As Byte, tmpK2() As Byte
    Dim X As Long, Y As Long, Z As Long

    tmpB = StrConv(tmpS, vbFromUnicode)
    If Not ZstdCompress(tmpB, tmpB2) Then
        tmpS = "X"
        Exit Function
    End If

    ' BEGIN encrypt
    ReDim tmpK(0 To 31)
    For X = 0 To 31
        tmpK(X) = Int((Rnd * 254) + 1)
    Next
    If ScriptKey = "" Then
        ReDim tmpK2(-1 To -1)
        tmpK2(-1) = 0
    Else
        tmpK2 = StrConv(ScriptKey, vbFromUnicode)
    End If
    CryptoVer = "3"

    Y = UBound(tmpK) + 1
    Z = UBound(tmpK2) + 1
    For X = 0 To UBound(tmpB2)
        tmpB2(X) = tmpB2(X) Xor 42 Xor tmpK(X Mod Y)
        If Z > 0 Then
             tmpB2(X) = tmpB2(X) Xor tmpK2(X Mod Z)
        End If
    Next
    ' END encrypt

    tmpS = EncodeBase64Bytes(tmpK) & ":" & EncodeBase64Bytes(tmpB2)

    DSOSingleEncrypt = ""
    If Not NoWrap Then
        While Len(tmpS) > EncryptedLineLen
            DSOSingleEncrypt = DSOSingleEncrypt & "_" & Mid(tmpS, 1, EncryptedLineLen) & vbCrLf
            tmpS = Mid(tmpS, EncryptedLineLen + 1)
        Wend
    End If
    DSOSingleEncrypt = DSOSingleEncrypt & CryptoVer & tmpS
End Function

Private Function DSOSingleDecrypt(ByVal CryptoVer As String, ByVal tmpS As String, ByVal ScriptKey As String) As String
    Dim tmpSA() As String
    Dim tmpB() As Byte, tmpB2() As Byte, tmpK() As Byte, tmpK2() As Byte
    Dim X As Long, Y As Long, Z As Long

    If ScriptKey = "" Then
        ReDim tmpK2(-1 To -1)
        tmpK2(-1) = 0
    Else
        tmpK2 = StrConv(ScriptKey, vbFromUnicode)
    End If

    Select Case CryptoVer
        Case "0":
            DSOSingleDecrypt = DecodeBase64Str(tmpS)
        Case "1":
            tmpB = DecodeBase64Bytes(tmpS)
            For X = 0 To UBound(tmpB)
                tmpB(X) = tmpB(X) Xor 42
            Next
            DSOSingleDecrypt = StrConv(tmpB, vbUnicode)
        Case "2", "3":
            tmpSA = Split(tmpS, ":")
            tmpK = DecodeBase64Bytes(tmpSA(0))
            tmpB2 = DecodeBase64Bytes(tmpSA(1))
            Y = UBound(tmpK) + 1
            Z = UBound(tmpK2) + 1
            For X = 0 To UBound(tmpB2)
                tmpB2(X) = tmpB2(X) Xor 42 Xor tmpK(X Mod Y)
                If Z > 0 Then
                     tmpB2(X) = tmpB2(X) Xor tmpK2(X Mod Z)
                End If
            Next
            If Not ZstdDecompress(tmpB2, tmpB) Then
                Err.Raise vbObjectError + 9223, , "ZSTD decompression error"
            End If
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

Public Function DSODecryptScript(ByVal Source As String, ByVal ScriptKey As String) As String
    If UCase(Left(Source, Len(EncryptedHeader))) <> UCase(EncryptedHeader) Then
        DSODecryptScript = Source
        Exit Function
    End If

    Dim Output As String
    Dim Lines() As String
    Lines = Split(Mid(Source, Len(EncryptedHeader) + 1), vbCrLf)
    Dim X As Long, Line As String, LastLine As String
    LastLine = Lines(LBound(Lines))
    Output = DSOSingleDecrypt(Left(LastLine, 1), Mid(LastLine, 2), ScriptKey)
    If Output <> EncryptedCanary Then
        Err.Raise vbObjectError + 9878, , "Failed to parse header ofcompiled script"
    End If

    LastLine = ""
    Output = ""
    For X = LBound(Lines) + 1 To UBound(Lines)
        Line = Lines(X)
        If Trim(Line) <> "" Then
            LastLine = LastLine & Mid(Line, 2)
        End If

        If Left(Line, 1) <> "_" Then
            If Trim(LastLine) <> "" Then
                If Output <> "" Then
                    Output = Output & vbCrLf
                End If
                Output = Output & DSOSingleDecrypt(Left(Line, 1), LastLine, ScriptKey)
            End If
            LastLine = ""
        End If
    Next

    DSODecryptScript = Output
End Function

Public Function DSOCompileScript(ByVal Source As String, ByVal ScriptKey As String, Optional ByVal AllowCommands As Boolean = True) As String
    Dim ParsedSource As String
    ParsedSource = DSODecryptScript(Source, "")

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

    ParsedSource = DSOSingleEncrypt(ParsedSource, ScriptKey, True)
    DSOCompileScript = EncryptedHeader & DSOSingleEncrypt(EncryptedCanary, ScriptKey, False) & vbCrLf & ParsedSource & vbCrLf
End Function

