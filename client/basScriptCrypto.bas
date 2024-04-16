Attribute VB_Name = "basScriptCrypto"
Option Explicit

Public Const EncryptedHeader = "Option DSciptCompiled" & vbCrLf
Public Const EncryptedCanary = "Option DSciptCompiledLoaded" & vbCrLf
Public Const EncryptedLineLen = 140
Private Const EncryptedDefaultKey = "DSO$S3cur3_K3y!!111"

Private Function DSOSingleEncrypt(ByVal tmpS As String, ByVal ScriptKey As String, ByVal NoWrap As Boolean) As String
    If tmpS = "" Then
        DSOSingleEncrypt = "X"
        Exit Function
    End If

    Dim CryptoVer As String
    Dim bRaw() As Byte, bProcessed() As Byte, bSalt() As Byte, bPass() As Byte
    Dim X As Long

    bRaw = StrConv(tmpS, vbFromUnicode)
    If Not ZstdCompress(bRaw, bProcessed) Then
        tmpS = "X"
        Exit Function
    End If

    ' BEGIN encrypt
    CryptoVer = "4"
    If ScriptKey = "" Then
        ScriptKey = EncryptedDefaultKey
    End If
    bSalt = AesGenSalt()
    bPass = StrConv(ScriptKey & vbNullString, vbFromUnicode)

    ' END encrypt
    Dim bUnused() As Byte
    Dim bHMAC() As Byte
    ReDim bHMAC(0 To HMAC_HASH_LEN - 1)
    bHMAC(0) = 1 ' encrypt-then-mac
    If Not AesCryptArray(bProcessed, bPass, bSalt, bUnused, Hmac:=bHMAC) Then
        Err.Raise vbObjectError + 9090, , "AES engine failure"
    End If
    tmpS = EncodeBase64Bytes(bSalt) & ":" & EncodeBase64Bytes(bHMAC) & ":" & EncodeBase64Bytes(bProcessed)

    DSOSingleEncrypt = ""
    If Not NoWrap Then
        While Len(tmpS) > EncryptedLineLen
            DSOSingleEncrypt = DSOSingleEncrypt & "_" & Mid(tmpS, 1, EncryptedLineLen) & vbCrLf
            tmpS = Mid(tmpS, EncryptedLineLen + 1)
        Wend
    End If
    DSOSingleEncrypt = DSOSingleEncrypt & CryptoVer & tmpS
End Function

Private Function DSOSingleDecrypt(ByVal CryptoVer As String, ByVal InputStr As String, ByVal ScriptKey As String) As String
    Dim X As Long

    Select Case CryptoVer
        Case "4":
            Dim sSplit() As String, bSalt() As Byte, bHMAC() As Byte, bHMACOut() As Byte, bPass() As Byte, bRaw() As Byte, bDecompressed() As Byte
            sSplit = Split(InputStr, ":")
            bSalt = DecodeBase64Bytes(sSplit(0))
            bHMAC = DecodeBase64Bytes(sSplit(1))
            bRaw = DecodeBase64Bytes(sSplit(2))
            If ScriptKey = "" Then
                ScriptKey = EncryptedDefaultKey
            End If
            bPass = StrConv(ScriptKey & vbNullString, vbFromUnicode)

            Dim bUnused() As Byte
            ReDim bHMACOut(0 To HMAC_HASH_LEN - 1)
            bHMACOut(0) = 0 ' hash then decrpyt
            If Not AesCryptArray(bRaw, bPass, bSalt, bUnused, Hmac:=bHMACOut) Then
                Err.Raise vbObjectError + 9090, , "AES engine failure"
            End If
            If UBound(bHMAC) <> UBound(bHMACOut) Or LBound(bHMAC) <> LBound(bHMACOut) Then
                Err.Raise vbObjectError + 9091, , "HMAC size failure"
            End If

            Dim Differences As Integer, Sames As Integer
            Sames = 0
            Differences = 0
            For X = LBound(bHMAC) To UBound(bHMAC)
                If bHMAC(X) <> bHMACOut(X) Then
                    Differences = Differences + 1
                Else
                    Sames = Sames + 1
                End If
            Next
            If Differences <> 0 Or Sames <> (1 + (UBound(bHMAC) - LBound(bHMAC))) Then
                Err.Raise vbObjectError + 9092, , "HMAC check failure"
            End If

            If Not ZstdDecompress(bRaw, bDecompressed) Then
                Err.Raise vbObjectError + 9223, , "ZSTD decompression error"
            End If
            DSOSingleDecrypt = StrConv(bDecompressed, vbUnicode)
        Case "X":
            ' Empty part
            DSOSingleDecrypt = ""
        Case "H":
            ' Do nothing, header!
            DSOSingleDecrypt = ""
        Case Else:
            Err.Raise vbObjectError + 9343, , "Invalid crypto line " & CryptoVer & InputStr
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

    ParsedSource = DSOSingleEncrypt(ParsedSource, ScriptKey, True)
    DSOCompileScript = EncryptedHeader & DSOSingleEncrypt(EncryptedCanary, ScriptKey, False) & vbCrLf & ParsedSource & vbCrLf
End Function

