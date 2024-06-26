Attribute VB_Name = "basScriptCrypto"
Option Explicit

Public Const EncryptedHeader = "Option DSciptCompiled" & vbCrLf
Public Const EncryptedCanary = "Option DSciptCompiledLoaded" & vbCrLf
Public Const EncryptedLineLen = 140
Private Const EncryptedDefaultKey = "DSO$S3cur3_K3y!!111"

Private Declare Function RtlGenRandom Lib "advapi32" Alias "SystemFunction036" (RandomBuffer As Any, ByVal RandomBufferLength As Long) As Long

Public SHA256 As New clsSHA256

Private LastBaPass As String, LastBaSalt As String, LastDerivedKey() As Byte

Public Function DeriveKeyFromPassword(baPass() As Byte, baSalt() As Byte) As Byte()
    Dim strPass As String, strSalt As String
    strPass = SHA256.SHA256bytes(baPass)
    strSalt = SHA256.SHA256bytes(baSalt)

    If strPass = LastBaPass And strSalt = LastBaSalt Then
        DeriveKeyFromPassword = LastDerivedKey
        Exit Function
    End If

    Dim x As Long
    Dim CurHash As String
    CurHash = "START"
    For x = 1 To 100
        If x Mod 3 = 0 Then
            CurHash = CurHash & strPass
        End If
        If x Mod 5 = 0 Then
            CurHash = strPass & CurHash
        End If
        If x Mod 7 = 0 Then
            CurHash = CurHash & strSalt
        End If
        If x Mod 11 = 0 Then
            CurHash = strSalt & CurHash
        End If
        CurHash = SHA256.SHA256string(CurHash)
    Next
    
    Dim baDerivedKey() As Byte
    ReDim baDerivedKey(0 To 15)
    For x = 0 To 15
        baDerivedKey(x) = Val("&H" & Mid(CurHash, 1 + (x * 2), 2))
    Next
    LastBaPass = strPass
    LastBaSalt = strSalt
    LastDerivedKey = baDerivedKey
    DeriveKeyFromPassword = baDerivedKey
End Function

Public Function DSOEncrypt(ByVal tmpS As String, ByVal Password As String, ByVal NoWrap As Boolean) As String
    If tmpS = "" Then
        DSOEncrypt = "X"
        Exit Function
    End If

    Dim CryptoVer As String
    Dim bRaw() As Byte, bProcessed() As Byte, bSalt() As Byte, bPass() As Byte
    Dim x As Long

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

    Dim bTagData() As Byte
    ReDim bTagData(0 To 15)

    Dim uCtx As CryptoAesGcmContext
    CryptoAesGcmInit uCtx, bKey, bSalt, bAuxData
    CryptoAesGcmEncrypt uCtx, bProcessed, TagSize:=16, Tag:=bTagData
    ' END encrypt

    tmpS = EncodeBase64Bytes(bSalt) & ":" & EncodeBase64Bytes(bTagData) & ":" & EncodeBase64Bytes(bProcessed)

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
    Dim sSplit() As String, bSalt() As Byte, bTag() As Byte, bPass() As Byte, bRaw() As Byte, bDecompressed() As Byte
    Dim x As Long

    Select Case CryptoVer
        Case "7", "8":
            sSplit = Split(InputStr, ":")
            bSalt = DecodeBase64Bytes(sSplit(0))
            bTag = DecodeBase64Bytes(sSplit(1))
            bRaw = DecodeBase64Bytes(sSplit(2))
            bPass = StrConv(EncryptedDefaultKey & Password & vbNullString, vbFromUnicode)

            Dim bKey() As Byte
            bKey = DeriveKeyFromPassword(bPass, bSalt)

            Dim bAuxData() As Byte
            ReDim bAuxData(0 To 0)
            bAuxData(0) = 0

            Dim uCtx As CryptoAesGcmContext
            CryptoAesGcmInit uCtx, bKey, bSalt, bAuxData
            If Not CryptoAesGcmDecrypt(uCtx, bRaw, Tag:=bTag) Then
                Err.Raise vbObjectError + 9224, , "AES decryption error"
            End If

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

Public Function DSOIsScriptCompiled(ByVal Source As String) As Boolean
    DSOIsScriptCompiled = (UCase(Left(Source, Len(EncryptedHeader))) = UCase(EncryptedHeader))
End Function

Public Function DSOCheckScriptKey(ByVal Source As String, ByVal ScriptKey As String) As Boolean
    DSOCheckScriptKey = True
    On Error GoTo EH
    DSODecryptScript Source, ScriptKey
    On Error GoTo 0
    Exit Function
EH:
    DSOCheckScriptKey = False
    Resume Next
End Function

Public Function DSODecryptScript(ByVal Source As String, ByVal ScriptKey As String) As String
    If ScriptKey = "" Then
        ScriptKey = "local"
    End If

    If Not DSOIsScriptCompiled(Source) Then
        DSODecryptScript = Source
        Exit Function
    End If

    Dim Lines() As String
    Lines = Split(Mid(Source, Len(EncryptedHeader) + 1), vbCrLf)
    DSODecryptScript = DSODecryptLines(Lines, ScriptKey)
    If UCase(Left(DSODecryptScript, Len(EncryptedCanary))) <> UCase(EncryptedCanary) Then
        DSODecryptScript = ""
        Err.Raise vbObjectError + 9878, , "Failed to parse header of compiled script"
    End If
    DSODecryptScript = Mid(DSODecryptScript, Len(EncryptedCanary) + 1)
End Function

Public Function DSODecrypt(ByVal Source As String, ByVal Password As String) As String
    Dim Lines() As String
    Lines = Split(Source, vbCrLf)
    DSODecrypt = DSODecryptLines(Lines, Password)
End Function

Private Function DSODecryptLines(Lines() As String, ByVal Password As String) As String
    Dim x As Long, Line As String, LastLine As String
    LastLine = ""
    DSODecryptLines = ""

    For x = LBound(Lines) To UBound(Lines)
        Line = Lines(x)
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

    Dim tmpS As String
    tmpS = EncryptedCanary & DSODecryptScript(Source, "")
    tmpS = DSOEncrypt(tmpS, ScriptKey, True)
    DSOCompileScript = EncryptedHeader & tmpS & vbCrLf
End Function

Private Function AesGenSalt() As Byte()
    AesGenSalt = SecureRandom(16)
End Function

Public Function SecureRandom(BLen As Long) As Byte()
    Dim Res() As Byte
    ReDim Res(0 To BLen - 1) As Byte
    Call RtlGenRandom(Res(0), BLen)
    SecureRandom = Res
End Function

