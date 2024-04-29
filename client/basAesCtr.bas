Attribute VB_Name = "basAesCtr"
' Credit goes to: https://gist.github.com/wqweto/42a6c1de16cc87e9bab2ac9f3c9d8510#file-mdaesctr-bas
'--- mdAesCtr.bas
Option Explicit
DefObj A-Z

#Const HasPtrSafe = (VBA7 <> 0) Or (TWINBASIC <> 0)

'=========================================================================
' API
'=========================================================================

#If Win64 Then
    Private Const PTR_SIZE                  As Long = 8
#Else
    Private Const PTR_SIZE                  As Long = 4
#End If

#If HasPtrSafe Then
Private Declare PtrSafe Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (lpvDest As Any, lpvSource As Any, ByVal cbCopy As LongPtr)
Private Declare PtrSafe Function ArrPtr Lib "vbe7" Alias "VarPtr" (Ptr() As Any) As LongPtr
Private Declare PtrSafe Function htonl Lib "ws2_32" (ByVal hostlong As Long) As Long
Private Declare PtrSafe Function RtlGenRandom Lib "advapi32" Alias "SystemFunction036" (RandomBuffer As Any, ByVal RandomBufferLength As Long) As Long
'--- bcrypt
Private Declare PtrSafe Function BCryptOpenAlgorithmProvider Lib "bcrypt" (phAlgorithm As LongPtr, ByVal pszAlgId As LongPtr, ByVal pszImplementation As LongPtr, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptCloseAlgorithmProvider Lib "bcrypt" (ByVal hAlgorithm As LongPtr, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptGetProperty Lib "bcrypt" (ByVal hObject As LongPtr, ByVal pszProperty As LongPtr, pbOutput As Any, ByVal cbOutput As Long, cbResult As Long, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptSetProperty Lib "bcrypt" (ByVal hObject As LongPtr, ByVal pszProperty As LongPtr, ByVal pbInput As LongPtr, ByVal cbInput As Long, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptGenerateSymmetricKey Lib "bcrypt" (ByVal hAlgorithm As LongPtr, phKey As LongPtr, pbKeyObject As Any, ByVal cbKeyObject As Long, pbSecret As Any, ByVal cbSecret As Long, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptDestroyKey Lib "bcrypt" (ByVal hKey As LongPtr) As Long
Private Declare PtrSafe Function BCryptEncrypt Lib "bcrypt" (ByVal hKey As LongPtr, pbInput As Any, ByVal cbInput As Long, ByVal pPaddingInfo As LongPtr, ByVal pbIV As LongPtr, ByVal cbIV As Long, pbOutput As Any, ByVal cbOutput As Long, pcbResult As Long, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptDeriveKeyPBKDF2 Lib "bcrypt" (ByVal hPrf As LongPtr, pbPassword As Any, ByVal cbPassword As Long, pbSalt As Any, ByVal cbSalt As Long, ByVal cIterations As currency, pbDerivedKey As Any, ByVal cbDerivedKey As Long, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptCreateHash Lib "bcrypt" (ByVal hAlgorithm As LongPtr, phHash As LongPtr, ByVal pbHashObject As LongPtr, ByVal cbHashObject As Long, ByVal pbSecret As LongPtr, ByVal cbSecret As Long, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptDestroyHash Lib "bcrypt" (ByVal hHash As LongPtr) As Long
Private Declare PtrSafe Function BCryptHashData Lib "bcrypt" (ByVal hHash As LongPtr, pbInput As Any, ByVal cbInput As Long, ByVal dwFlags As Long) As Long
Private Declare PtrSafe Function BCryptFinishHash Lib "bcrypt" (ByVal hHash As LongPtr, pbOutput As Any, ByVal cbOutput As Long, ByVal dwFlags As Long) As Long
#Else
Private Enum LongPtr
    [_]
End Enum
Private Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (lpvDest As Any, lpvSource As Any, ByVal cbCopy As LongPtr)
Private Declare Function ArrPtr Lib "msvbvm60" Alias "VarPtr" (Ptr() As Any) As LongPtr
Private Declare Function htonl Lib "ws2_32" (ByVal hostlong As Long) As Long
Private Declare Function RtlGenRandom Lib "advapi32" Alias "SystemFunction036" (RandomBuffer As Any, ByVal RandomBufferLength As Long) As Long
'--- bcrypt
Private Declare Function BCryptOpenAlgorithmProvider Lib "bcrypt" (phAlgorithm As LongPtr, ByVal pszAlgId As LongPtr, ByVal pszImplementation As LongPtr, ByVal dwFlags As Long) As Long
Private Declare Function BCryptCloseAlgorithmProvider Lib "bcrypt" (ByVal hAlgorithm As LongPtr, ByVal dwFlags As Long) As Long
Private Declare Function BCryptGetProperty Lib "bcrypt" (ByVal hObject As LongPtr, ByVal pszProperty As LongPtr, pbOutput As Any, ByVal cbOutput As Long, cbResult As Long, ByVal dwFlags As Long) As Long
Private Declare Function BCryptSetProperty Lib "bcrypt" (ByVal hObject As LongPtr, ByVal pszProperty As LongPtr, ByVal pbInput As LongPtr, ByVal cbInput As Long, ByVal dwFlags As Long) As Long
Private Declare Function BCryptGenerateSymmetricKey Lib "bcrypt" (ByVal hAlgorithm As LongPtr, phKey As LongPtr, pbKeyObject As Any, ByVal cbKeyObject As Long, pbSecret As Any, ByVal cbSecret As Long, ByVal dwFlags As Long) As Long
Private Declare Function BCryptDestroyKey Lib "bcrypt" (ByVal hKey As LongPtr) As Long
Private Declare Function BCryptEncrypt Lib "bcrypt" (ByVal hKey As LongPtr, pbInput As Any, ByVal cbInput As Long, ByVal pPaddingInfo As LongPtr, ByVal pbIV As LongPtr, ByVal cbIV As Long, pbOutput As Any, ByVal cbOutput As Long, pcbResult As Long, ByVal dwFlags As Long) As Long
Private Declare Function BCryptDeriveKeyPBKDF2 Lib "bcrypt" (ByVal hPrf As LongPtr, pbPassword As Any, ByVal cbPassword As Long, pbSalt As Any, ByVal cbSalt As Long, ByVal cIterations As Currency, pbDerivedKey As Any, ByVal cbDerivedKey As Long, ByVal dwFlags As Long) As Long
Private Declare Function BCryptCreateHash Lib "bcrypt" (ByVal hAlgorithm As LongPtr, phHash As LongPtr, ByVal pbHashObject As LongPtr, ByVal cbHashObject As Long, ByVal pbSecret As LongPtr, ByVal cbSecret As Long, ByVal dwFlags As Long) As Long
Private Declare Function BCryptDestroyHash Lib "bcrypt" (ByVal hHash As LongPtr) As Long
Private Declare Function BCryptHashData Lib "bcrypt" (ByVal hHash As LongPtr, pbInput As Any, ByVal cbInput As Long, ByVal dwFlags As Long) As Long
Private Declare Function BCryptFinishHash Lib "bcrypt" (ByVal hHash As LongPtr, pbOutput As Any, ByVal cbOutput As Long, ByVal dwFlags As Long) As Long
#End If
#If Not ImplUseShared Then
    #If HasPtrSafe Then
    Private Declare PtrSafe Function CryptStringToBinary Lib "crypt32" Alias "CryptStringToBinaryW" (ByVal pszString As LongPtr, ByVal cchString As Long, ByVal dwFlags As Long, ByVal pbBinary As LongPtr, pcbBinary As Long, pdwSkip As Long, pdwFlags As Long) As Long
    Private Declare PtrSafe Function CryptBinaryToString Lib "crypt32" Alias "CryptBinaryToStringW" (ByVal pbBinary As LongPtr, ByVal cbBinary As Long, ByVal dwFlags As Long, ByVal pszString As LongPtr, pcchString As Long) As Long
    Private Declare PtrSafe Function WideCharToMultiByte Lib "kernel32" (ByVal CodePage As Long, ByVal dwFlags As Long, ByVal lpWideCharStr As LongPtr, ByVal cchWideChar As Long, lpMultiByteStr As Any, ByVal cchMultiByte As Long, ByVal lpDefaultChar As LongPtr, ByVal lpUsedDefaultChar As LongPtr) As Long
    Private Declare PtrSafe Function MultiByteToWideChar Lib "kernel32" (ByVal CodePage As Long, ByVal dwFlags As Long, lpMultiByteStr As Any, ByVal cchMultiByte As Long, ByVal lpWideCharStr As LongPtr, ByVal cchWideChar As Long) As Long
    Private Declare PtrSafe Function FormatMessage Lib "kernel32" Alias "FormatMessageA" (ByVal dwFlags As Long, ByVal lpSource As LongPtr, ByVal dwMessageId As Long, ByVal dwLanguageId As Long, ByVal lpBuffer As String, ByVal nSize As Long, ByVal Args As LongPtr) As Long
    #Else
    Private Declare Function CryptStringToBinary Lib "crypt32" Alias "CryptStringToBinaryW" (ByVal pszString As LongPtr, ByVal cchString As Long, ByVal dwFlags As Long, ByVal pbBinary As LongPtr, pcbBinary As Long, pdwSkip As Long, pdwFlags As Long) As Long
    Private Declare Function CryptBinaryToString Lib "crypt32" Alias "CryptBinaryToStringW" (ByVal pbBinary As LongPtr, ByVal cbBinary As Long, ByVal dwFlags As Long, ByVal pszString As LongPtr, pcchString As Long) As Long
    Private Declare Function WideCharToMultiByte Lib "kernel32" (ByVal CodePage As Long, ByVal dwFlags As Long, ByVal lpWideCharStr As LongPtr, ByVal cchWideChar As Long, lpMultiByteStr As Any, ByVal cchMultiByte As Long, ByVal lpDefaultChar As LongPtr, ByVal lpUsedDefaultChar As LongPtr) As Long
    Private Declare Function MultiByteToWideChar Lib "kernel32" (ByVal CodePage As Long, ByVal dwFlags As Long, lpMultiByteStr As Any, ByVal cchMultiByte As Long, ByVal lpWideCharStr As LongPtr, ByVal cchWideChar As Long) As Long
    Private Declare Function FormatMessage Lib "kernel32" Alias "FormatMessageA" (ByVal dwFlags As Long, ByVal lpSource As LongPtr, ByVal dwMessageId As Long, ByVal dwLanguageId As Long, ByVal lpBuffer As String, ByVal nSize As Long, ByVal Args As LongPtr) As Long
    #End If
#End If

'=========================================================================
' Constants and member variables
'=========================================================================


Private Const BCRYPT_ALG_HANDLE_HMAC_FLAG   As Long = 8
Private Const BCRYPT_SHA256_ALGORITHM  As String = "SHA256"
Private Const BCRYPT_SHA512_ALGORITHM  As String = "SHA512"

Private Const AES_BLOCK_SIZE        As Long = 16
Private Const AES_KEYLEN            As Long = 32                    '-- 32 -> AES-256, 24 -> AES-196, 16 -> AES-128
Private Const AES_IVLEN             As Long = AES_BLOCK_SIZE
Private Const KDF_SALTLEN           As Long = 8
Private Const KDF_ITER              As Long = 10000
Private Const KDF_HASH              As String = BCRYPT_SHA512_ALGORITHM
Private Const OPENSSL_MAGIC         As String = "Salted__"          '-- for openssl compatibility
Private Const OPENSSL_MAGICLEN      As Long = 8
Private Const ERR_UNSUPPORTED_ENCR  As String = "Unsupported encryption"
Private Const ERR_CHUNKED_NOT_INIT  As String = "AES chunked context not initialized"
Private Const HMAC_HASH             As String = BCRYPT_SHA256_ALGORITHM
Public Const HMAC_HASH_LEN          As Long = (256 / 8)

Private Const MS_PRIMITIVE_PROVIDER         As String = "Microsoft Primitive Provider"
Private Const WIN32_NULL As Long = 0&

Private Type UcsCryptoContextType
    hPbkdf2Alg          As LongPtr
    hHmacAlg            As LongPtr
    hHmacHash           As LongPtr
    hashLen             As Long
    hAesAlg             As LongPtr
    hAesKey             As LongPtr
    AesKeyObjData()     As Byte
    AesKeyObjLen        As Long
    Nonce(0 To 3)       As Long
    EncrData()          As Byte
    EncrPos             As Long
    LastError           As String
End Type

Private m_uChunkedCtx           As UcsCryptoContextType

'=========================================================================
' Functions
'=========================================================================
Public Function AesGenSalt() As Byte()
    AesGenSalt = SecureRandom(KDF_SALTLEN)
End Function

Public Function SecureRandom(BLen As Long) As Byte()
    Dim Res() As Byte
    ReDim Res(0 To BLen - 1) As Byte
    Call RtlGenRandom(Res(0), BLen)
    SecureRandom = Res
End Function

Public Function AesCryptArray( _
            baData() As Byte, _
            baPass() As Byte, _
            baSalt() As Byte, _
            baKey() As Byte, _
            Optional ByVal KeyLen As Long, _
            Optional Error As String, _
            Optional Hmac As Variant) As Boolean
    Const VT_BYREF      As Long = &H4000
    Dim uCtx            As UcsCryptoContextType
    Dim vErr            As Variant
    Dim bHashBefore     As Boolean
    Dim bHashAfter      As Boolean
    Dim baTemp()        As Byte
    Dim lPtr            As LongPtr
    
    On Error GoTo EH
    If IsArray(Hmac) Then
        bHashBefore = (Hmac(0) <= 0)
        bHashAfter = (Hmac(0) > 0)
    End If
    If KeyLen <= 0 Then
        KeyLen = AES_KEYLEN
    End If
    If Not pvCryptoAesCtrInit(uCtx, baPass, baSalt, baKey, KeyLen) Then
        Error = uCtx.LastError
        GoTo QH
    End If
    If Not pvCryptoAesCtrCrypt(uCtx, baData, HashBefore:=bHashBefore, HashAfter:=bHashAfter) Then
        Error = uCtx.LastError
        GoTo QH
    End If
    If IsArray(Hmac) Then
        baTemp = pvCryptoGetFinalHash(uCtx, UBound(Hmac) + 1)
        #If Win64 Then
            lPtr = PeekPtr(VarPtr(Hmac) + 8)
        #Else
            lPtr = PeekPtr((VarPtr(Hmac) Xor &H80000000) + 8 Xor &H80000000)
        #End If
        If (PeekPtr(VarPtr(Hmac)) And VT_BYREF) <> 0 Then
            lPtr = PeekPtr(lPtr)
        End If
        #If Win64 Then
            lPtr = PeekPtr(lPtr + 16)
        #Else
            lPtr = PeekPtr((lPtr Xor &H80000000) + 12 Xor &H80000000)
        #End If
        Call CopyMemory(ByVal lPtr, baTemp(0), UBound(baTemp) + 1)
    End If
    '--- success
    AesCryptArray = True
QH:
    pvCryptoAesCtrTerminate uCtx
    Exit Function
EH:
    vErr = Array(Err.Number, Err.Source, Err.Description)
    pvCryptoAesCtrTerminate uCtx
    Err.Raise vErr(0), vErr(1), vErr(2)
End Function

Public Function AesChunkedInit(Optional key As Variant, Optional ByVal KeyLen As Long) As Boolean
    Dim baEmpty()       As Byte
    Dim baKey()         As Byte
    
    pvCryptoAesCtrTerminate m_uChunkedCtx
    baEmpty = vbNullString
    If IsArray(key) Then
        baKey = key
    End If
    If KeyLen <= 0 Then
        KeyLen = AES_KEYLEN
    End If
    AesChunkedInit = pvCryptoAesCtrInit(m_uChunkedCtx, baEmpty, baEmpty, baKey, KeyLen)
End Function

Public Function AesChunkedCryptArray(baInput() As Byte, baOutput() As Byte, Optional ByVal Final As Boolean = True) As Boolean
    If m_uChunkedCtx.hAesAlg = 0 Then
        m_uChunkedCtx.LastError = ERR_CHUNKED_NOT_INIT
        Exit Function
    End If
    baOutput = baInput
    AesChunkedCryptArray = pvCryptoAesCtrCrypt(m_uChunkedCtx, baOutput)
    If Final Then
        pvCryptoAesCtrTerminate m_uChunkedCtx
    End If
End Function

Public Function AesChunkedGetLastError() As String
    AesChunkedGetLastError = m_uChunkedCtx.LastError
End Function

'= private ===============================================================

Private Function pvCryptoAesCtrInit(uCtx As UcsCryptoContextType, baPass() As Byte, baSalt() As Byte, baDerivedKey() As Byte, ByVal lKeyLen As Long) As Boolean
    Dim HResult         As Long
    
    With uCtx
        '--- init member vars
        .EncrData = vbNullString
        .EncrPos = 0
        .LastError = vbNullString
        ReDim Preserve baDerivedKey(0 To lKeyLen + AES_IVLEN - 1) As Byte
        If UBound(baPass) >= 0 Or UBound(baSalt) >= 0 Then
            '--- generate RFC 2898 based derived key
            On Error GoTo EH_Unsupported '--- PBKDF2 API missing on Vista
            HResult = BCryptOpenAlgorithmProvider(.hPbkdf2Alg, StrPtr(KDF_HASH), StrPtr(MS_PRIMITIVE_PROVIDER), BCRYPT_ALG_HANDLE_HMAC_FLAG)
            If HResult < 0 Then
                GoTo QH
            End If
            HResult = BCryptDeriveKeyPBKDF2(.hPbkdf2Alg, ByVal pvArrayPtr(baPass), pvArraySize(baPass), ByVal pvArrayPtr(baSalt), pvArraySize(baSalt), _
                    KDF_ITER / 10000@, baDerivedKey(0), UBound(baDerivedKey) + 1, 0)
            If HResult < 0 Then
                GoTo QH
            End If
            On Error GoTo 0
        End If
        '--- init AES key from first half of derived key
        On Error GoTo EH_Unsupported '--- CNG API missing on XP
        HResult = BCryptOpenAlgorithmProvider(.hAesAlg, StrPtr("AES"), StrPtr(MS_PRIMITIVE_PROVIDER), 0)
        If HResult < 0 Then
            GoTo QH
        End If
        On Error GoTo 0
        HResult = BCryptGetProperty(.hAesAlg, StrPtr("ObjectLength"), .AesKeyObjLen, 4, 0, 0)
        If HResult < 0 Then
            GoTo QH
        End If
        HResult = BCryptSetProperty(.hAesAlg, StrPtr("ChainingMode"), StrPtr("ChainingModeECB"), 30, 0)  ' 30 = LenB("ChainingModeECB")
        If HResult < 0 Then
            GoTo QH
        End If
        ReDim .AesKeyObjData(0 To .AesKeyObjLen - 1) As Byte
        HResult = BCryptGenerateSymmetricKey(.hAesAlg, .hAesKey, .AesKeyObjData(0), .AesKeyObjLen, baDerivedKey(0), lKeyLen, 0)
        If HResult < 0 Then
            GoTo QH
        End If
        '--- init AES IV from second half of derived key
        Call CopyMemory(.Nonce(0), baDerivedKey(lKeyLen), AES_IVLEN)
        '--- init HMAC key from last HashLen bytes of derived key
        HResult = BCryptOpenAlgorithmProvider(.hHmacAlg, StrPtr(HMAC_HASH), StrPtr(MS_PRIMITIVE_PROVIDER), BCRYPT_ALG_HANDLE_HMAC_FLAG)
        If HResult < 0 Then
            GoTo QH
        End If
        HResult = BCryptGetProperty(.hHmacAlg, StrPtr("HashDigestLength"), .hashLen, 4, 0, 0)
        If HResult < 0 Then
            GoTo QH
        End If
        HResult = BCryptCreateHash(.hHmacAlg, .hHmacHash, 0, 0, VarPtr(baDerivedKey(lKeyLen + AES_IVLEN - .hashLen)), .hashLen, 0)
        If HResult < 0 Then
            GoTo QH
        End If
    End With
    '--- success
    pvCryptoAesCtrInit = True
    Exit Function
QH:
    uCtx.LastError = GetSystemMessage(HResult)
    Exit Function
EH_Unsupported:
    uCtx.LastError = ERR_UNSUPPORTED_ENCR
End Function

Private Sub pvCryptoAesCtrTerminate(uCtx As UcsCryptoContextType)
    With uCtx
        If .hPbkdf2Alg <> 0 Then
            Call BCryptCloseAlgorithmProvider(.hPbkdf2Alg, 0)
            .hPbkdf2Alg = 0
        End If
        If .hHmacHash <> 0 Then
            Call BCryptDestroyHash(.hHmacHash)
            .hHmacHash = 0
        End If
        If .hHmacAlg <> 0 Then
            Call BCryptCloseAlgorithmProvider(.hHmacAlg, 0)
            .hHmacAlg = 0
        End If
        If .hAesKey <> 0 Then
            Call BCryptDestroyKey(.hAesKey)
            .hAesKey = 0
        End If
        If .hAesAlg <> 0 Then
            Call BCryptCloseAlgorithmProvider(.hAesAlg, 0)
            .hAesAlg = 0
        End If
    End With
End Sub

Private Function pvCryptoAesCtrCrypt( _
            uCtx As UcsCryptoContextType, _
            baData() As Byte, _
            Optional ByVal offset As Long, _
            Optional ByVal size As Long = -1, _
            Optional ByVal HashBefore As Boolean, _
            Optional ByVal HashAfter As Boolean) As Boolean
    Dim lIdx            As Long
    Dim lJdx            As Long
    Dim lPadSize        As Long
    Dim HResult         As Long
    
    With uCtx
        If size < 0 Then
            size = pvArraySize(baData) - offset
        End If
        If HashBefore Then
            HResult = BCryptHashData(.hHmacHash, ByVal pvArrayPtr(baData, offset), size, 0)
            If HResult < 0 Then
                GoTo QH
            End If
        End If
        '--- reuse .EncrData from prev call until next AES_BLOCK_SIZE boundary
        For lIdx = offset To offset + size - 1
            If (.EncrPos And (AES_BLOCK_SIZE - 1)) = 0 Then
                Exit For
            End If
            baData(lIdx) = baData(lIdx) Xor .EncrData(.EncrPos)
            .EncrPos = .EncrPos + 1
        Next
        If lIdx < offset + size Then
            '--- pad remaining input size to AES_BLOCK_SIZE
            lPadSize = (offset + size - lIdx + AES_BLOCK_SIZE - 1) And -AES_BLOCK_SIZE
            If UBound(.EncrData) + 1 < lPadSize Then
                ReDim .EncrData(0 To lPadSize - 1) As Byte
            End If
            '--- encrypt incremental Nonce in .EncrData
            For lJdx = 0 To lPadSize - 1 Step AES_BLOCK_SIZE
                Call CopyMemory(.EncrData(lJdx), .Nonce(0), AES_BLOCK_SIZE)
                If pvInc(.Nonce(3)) Then
                    If pvInc(.Nonce(2)) Then
                        If pvInc(.Nonce(1)) Then
                            If pvInc(.Nonce(0)) Then
                                '--- do nothing
                            End If
                        End If
                    End If
                End If
            Next
            ' TODO: This here crashes wine
            HResult = BCryptEncrypt(.hAesKey, .EncrData(0), lPadSize, 0, 0, 0, .EncrData(0), lPadSize, lJdx, 0)
            If HResult < 0 Then
                GoTo QH
            End If
            '--- XOR remaining input and leave anything extra in .EncrData for reuse
            For .EncrPos = 0 To offset + size - lIdx - 1
                baData(lIdx) = baData(lIdx) Xor .EncrData(.EncrPos)
                lIdx = lIdx + 1
            Next
        End If
        If HashAfter Then
            HResult = BCryptHashData(.hHmacHash, ByVal pvArrayPtr(baData, offset), size, 0)
            If HResult < 0 Then
                GoTo QH
            End If
        End If
    End With
    '--- success
    pvCryptoAesCtrCrypt = True
    Exit Function
QH:
    uCtx.LastError = GetSystemMessage(HResult)
End Function

Private Function pvCryptoGetFinalHash(uCtx As UcsCryptoContextType, ByVal lSize As Long) As Byte()
    Dim baResult()      As Byte
    
    ReDim baResult(0 To uCtx.hashLen - 1) As Byte
    Call BCryptFinishHash(uCtx.hHmacHash, baResult(0), uCtx.hashLen, 0)
    ReDim Preserve baResult(0 To lSize - 1) As Byte
    pvCryptoGetFinalHash = baResult
End Function

Private Function pvInc(lValue As Long) As Boolean
    lValue = htonl(lValue)
    If lValue = -1 Then
        lValue = 0
        '--- signal carry
        pvInc = True
    Else
        lValue = (lValue Xor &H80000000) + 1 Xor &H80000000
        lValue = htonl(lValue)
    End If
End Function

Private Property Get pvArrayPtr(baArray() As Byte, Optional ByVal index As Long) As LongPtr
    Dim lPtr            As LongPtr
    
    '--- peek long at ArrPtr(baArray)
    Call CopyMemory(lPtr, ByVal ArrPtr(baArray), PTR_SIZE)
    If lPtr <> 0 Then
        If 0 <= index And index <= UBound(baArray) - LBound(baArray) Then
            pvArrayPtr = VarPtr(baArray(LBound(baArray) + index))
        End If
    End If
End Property

Private Property Get pvArraySize(baArray() As Byte) As Long
    Dim lPtr            As LongPtr
    
    '--- peek long at ArrPtr(baArray)
    Call CopyMemory(lPtr, ByVal ArrPtr(baArray), PTR_SIZE)
    If lPtr <> 0 Then
        pvArraySize = UBound(baArray) + 1 - LBound(baArray)
    End If
End Property

Private Function ToHexByte(ByVal Data As Integer) As String
    Dim tmpS As String
    tmpS = Hex(Data)
    If Len(tmpS) = 1 Then
        ToHexByte = "0" & tmpS
    ElseIf Len(tmpS) = 0 Then
        ToHexByte = "00"
    Else
        ToHexByte = tmpS
    End If
End Function

' meow = 404cdd7bc109c432f8cc2443b45bcfe95980f5107215c645236e577929ac3e52
Public Function SHA256(ByVal Data As String) As String
    Dim HResult As Long
    Dim hashPtr As LongPtr
    Dim hashAlg As LongPtr
    Dim hashLen As Long
    hashPtr = 0
    hashAlg = 0
    hashLen = 0
    
    Dim bData() As Byte
    bData = StrConv(Data, vbFromUnicode)

    HResult = BCryptOpenAlgorithmProvider(hashAlg, StrPtr(BCRYPT_SHA256_ALGORITHM), StrPtr(MS_PRIMITIVE_PROVIDER), 0)
    If HResult < 0 Then
        GoTo QH
    End If
    HResult = BCryptGetProperty(hashAlg, StrPtr("HashDigestLength"), hashLen, 4, 0, 0)
    If HResult < 0 Then
        GoTo QH
    End If

    HResult = BCryptCreateHash(hashAlg, hashPtr, 0, 0, WIN32_NULL, 0, 0)
    If HResult < 0 Then
        GoTo QH
    End If

    HResult = BCryptHashData(hashPtr, ByVal pvArrayPtr(bData, 0), UBound(bData) + 1, 0)
    If HResult < 0 Then
        GoTo QH
    End If

    Dim baResult() As Byte
    ReDim baResult(0 To hashLen - 1) As Byte
    HResult = BCryptFinishHash(hashPtr, baResult(0), hashLen, 0)
    If HResult < 0 Then
        GoTo QH
    End If

    SHA256 = ""
    Dim X As Long
    For X = 0 To hashLen - 1
        SHA256 = SHA256 & LCase(ToHexByte(baResult(X)))
    Next

OnSHA256End:
    If hashPtr <> 0 Then
        Call BCryptDestroyHash(hashPtr)
    End If
    If hashAlg <> 0 Then
        Call BCryptCloseAlgorithmProvider(hashAlg, 0)
    End If
    Exit Function
QH:
    Err.Raise vbObjectError + 9191, , "SHA256 error: " & GetSystemMessage(HResult)
    GoTo OnSHA256End
End Function

Private Function GetSystemMessage(ByVal lLastDllError As Long) As String
    Const FORMAT_MESSAGE_FROM_SYSTEM    As Long = &H1000
    Const FORMAT_MESSAGE_IGNORE_INSERTS As Long = &H200
    Dim lSize            As Long
   
    GetSystemMessage = Space$(2000)
    lSize = FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM Or FORMAT_MESSAGE_IGNORE_INSERTS, 0, lLastDllError, 0, GetSystemMessage, Len(GetSystemMessage), 0)
    If lSize > 2 Then
        If Mid$(GetSystemMessage, lSize - 1, 2) = vbCrLf Then
            lSize = lSize - 2
        End If
    End If
    GetSystemMessage = Left$(GetSystemMessage, lSize) & " &H" & Hex(lLastDllError)
End Function

Private Function PeekPtr(ByVal lPtr As LongPtr) As LongPtr
    Call CopyMemory(PeekPtr, ByVal lPtr, PTR_SIZE)
End Function
