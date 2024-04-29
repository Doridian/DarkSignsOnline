Attribute VB_Name = "basScriptCrypto"
Option Explicit

Public Const EncryptedHeader = "Option DSciptCompiled" & vbCrLf
Public Const EncryptedCanary = "Option DSciptCompiledLoaded" & vbCrLf
Public Const EncryptedLineLen = 140
Private Const EncryptedDefaultKey = "DSO$S3cur3_K3y!!111"

Public SHA256 As New clsSHA256

Public Function DeriveKeyFromPassword(baPass() As Byte, baSalt() As Byte) As Byte()
    Dim strPass As String, strSalt As String
    strPass = SHA256.SHA256bytes(baPass)
    strSalt = SHA256.SHA256bytes(baSalt)

    Dim X As Long
    Dim CurHash As String
    CurHash = "START"
    For X = 1 To 100
        If X Mod 3 = 0 Then
            CurHash = CurHash & strPass
        End If
        If X Mod 5 = 0 Then
            CurHash = strPass & CurHash
        End If
        If X Mod 7 = 0 Then
            CurHash = CurHash & strSalt
        End If
        If X Mod 11 = 0 Then
            CurHash = strSalt & CurHash
        End If
        CurHash = SHA256.SHA256string(CurHash)
    Next
    
    Dim baDerivedKey() As Byte
    ReDim baDerivedKey(0 To 15)
    For X = 0 To 15
        baDerivedKey(X) = Val("&H" & Mid(CurHash, 1 + (X * 2), 2))
    Next
    DeriveKeyFromPassword = baDerivedKey
End Function

Public Function DSOEncrypt(ByVal tmpS As String, ByVal Password As String, ByVal NoWrap As Boolean) As String
    If tmpS = "" Then
        DSOEncrypt = "X"
        Exit Function
    End If

    Dim CryptoVer As String
    Dim bRaw() As Byte, bProcessed() As Byte, bSalt() As Byte, bPass() As Byte
    Dim X As Long

    ' BEGIN encrypt
    CryptoVer = "7"

    bRaw = StrConv(tmpS, vbFromUnicode)
    If UBound(bRaw) > 128 Then
        If Not ZstdCompress(bRaw, bProcessed) Then
            Err.Raise vbObjectError + 9183, , "ZSTD compression error"
            Exit Function
        End If
    Else
        bProcessed = bRaw
        CryptoVer = "8"
    End If

    bSalt = AesGenSalt()
    bPass = StrConv(EncryptedDefaultKey & Password & vbNullString, vbFromUnicode)

    Dim bKey() As Byte
    bKey = DeriveKeyFromPassword(bPass, bSalt)

    Dim bAuxData() As Byte
    ReDim bAuxData(0 To 0)
    bAuxData(0) = 0

    Dim uCtx As CryptoAesGcmContext
    CryptoAesGcmInit uCtx, bKey, bSalt, bAuxData
    CryptoAesGcmEncrypt uCtx, bProcessed
    ' END encrypt

    tmpS = EncodeBase64Bytes(bSalt) & ":" & EncodeBase64Bytes(bProcessed)

    DSOEncrypt = ""
    If Not NoWrap Then
        While Len(tmpS) > EncryptedLineLen
            DSOEncrypt = DSOEncrypt & "_" & Mid(tmpS, 1, EncryptedLineLen) & vbCrLf
            tmpS = Mid(tmpS, EncryptedLineLen + 1)
        Wend
    End If
    DSOEncrypt = DSOEncrypt & CryptoVer & tmpS
End Function

Private Function DSOSingleDecrypt(ByVal CryptoVer As String, ByVal InputStr As String, ByVal Password As String) As String
    Dim sSplit() As String, bSalt() As Byte, bHMAC() As Byte, bHMACOut() As Byte, bPass() As Byte, bRaw() As Byte, bDecompressed() As Byte
    Dim X As Long

    Select Case CryptoVer
        Case "5", "6":
            sSplit = Split(InputStr, ":")
            bSalt = DecodeBase64Bytes(sSplit(0))
            bHMAC = DecodeBase64Bytes(sSplit(1))
            bRaw = DecodeBase64Bytes(sSplit(2))
            bPass = StrConv(EncryptedDefaultKey & Password & vbNullString, vbFromUnicode)

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

            If CryptoVer = "5" Then
                If Not ZstdDecompress(bRaw, bDecompressed) Then
                    Err.Raise vbObjectError + 9223, , "ZSTD decompression error"
                End If
            Else
                bDecompressed = bRaw
            End If
            DSOSingleDecrypt = StrConv(bDecompressed, vbUnicode)
        Case "7", "8":
            sSplit = Split(InputStr, ":")
            bSalt = DecodeBase64Bytes(sSplit(0))
            bRaw = DecodeBase64Bytes(sSplit(1))
            bPass = StrConv(EncryptedDefaultKey & Password & vbNullString, vbFromUnicode)

            Dim bKey() As Byte
            bKey = DeriveKeyFromPassword(bPass, bSalt)

            Dim bAuxData() As Byte
            ReDim bAuxData(0 To 0)
            bAuxData(0) = 0

            Dim uCtx As CryptoAesGcmContext
            CryptoAesGcmInit uCtx, bKey, bSalt, bAuxData
            CryptoAesGcmDecrypt uCtx, bRaw

            If CryptoVer = "7" Then
                If Not ZstdDecompress(bRaw, bDecompressed) Then
                    Err.Raise vbObjectError + 9223, , "ZSTD decompression error"
                End If
            Else
                bDecompressed = bRaw
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
    If ScriptKey = "" Then
        ScriptKey = "local"
    End If

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
        Err.Raise vbObjectError + 9878, , "Failed to parse header of compiled script"
    End If
    
    DSODecryptScript = DSODecryptLines(Lines, ScriptKey, 1)
End Function

Public Function DSODecrypt(ByVal Source As String, ByVal Password As String) As String
    Dim Lines() As String
    Lines = Split(Source, vbCrLf)
    DSODecrypt = DSODecryptLines(Lines, Password)
End Function

Private Function DSODecryptLines(Lines() As String, ByVal Password As String, Optional ByVal SkipLines As Long = 0) As String
    Dim X As Long, Line As String, LastLine As String
    LastLine = ""
    DSODecryptLines = ""

    For X = LBound(Lines) + SkipLines To UBound(Lines)
        Line = Lines(X)
        If Trim(Line) <> "" Then
            LastLine = LastLine & Mid(Line, 2)
        End If

        If Left(Line, 1) <> "_" Then
            If Trim(LastLine) <> "" Then
                If DSODecryptLines <> "" Then
                    DSODecryptLines = DSODecryptLines & vbCrLf
                End If
                DSODecryptLines = DSODecryptLines & DSOSingleDecrypt(Left(Line, 1), LastLine, Password)
            End If
            LastLine = ""
        End If
    Next
End Function

Public Function DSOCompileScript(ByVal Source As String, ByVal ScriptKey As String) As String
    If ScriptKey = "" Then
        ScriptKey = "local"
    End If

    Dim ParsedSource As String
    ParsedSource = DSODecryptScript(Source, "")

    ParsedSource = DSOEncrypt(ParsedSource, ScriptKey, True)
    DSOCompileScript = EncryptedHeader & DSOEncrypt(EncryptedCanary, ScriptKey, False) & vbCrLf & ParsedSource & vbCrLf
End Function

