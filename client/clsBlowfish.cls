VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsBlowfish"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

'Long(long integer)  4 bytes -2,147,483,648 to 2,147,483,647

Private Const MaxLong = 2147483647
Private Const MinLong = -2147483648#

Private mbIsInit As Boolean
Private Const strErrSrc = "clsBlowfish"

Private p(1 To 18) As Long
Private s(1 To 4, 0 To 255) As Long

'Types for extracting bytes from words
Private Type LongByteW
    w As Long
End Type

Private Const BFErr = 3400 + vbObjectError

Private Type LongByteB
    b4 As Byte
    b3 As Byte
    b2 As Byte
    b1 As Byte
End Type

Private Function fAddBytes(b1 As Byte, b2 As Byte) As Byte
    fAddBytes = CByte((CInt(b1) + CInt(b2)) Mod 256)
End Function

Private Function fAddLongs(L1 As Long, L2 As Long) As Long
    Dim curRes As Currency, c1 As Currency, c2 As Currency
    
    'This function allows you to add the longs without turning off the
    'integer overflow checking.  Thus it is slower, but works in the IDE
    'and with any project you wish to add this code to.
    
    c1 = L1
    c2 = L2
    
    curRes = c1 + c2
    
    If curRes > MaxLong Then
        curRes = curRes - MaxLong + MinLong - 1
    End If
    
    If curRes < MinLong Then
        curRes = curRes + MaxLong - MinLong + 1
    End If
    
    fAddLongs = CLng(curRes)
        
End Function

Public Sub sInitBF(strKey As String)
    Dim i As Integer
    Dim j As Integer
    Dim x As LongByteW      'For conversion
    Dim y As LongByteB      ' """"
    Dim intKeyLen As Integer
    Dim bytKey() As Byte
    Dim lngDataL As Long, lngDataR As Long
    
    intKeyLen = Len(strKey)
    ReDim bytKey(0 To intKeyLen - 1)
    
    Call sStringToByte(strKey, bytKey)
    

    Call sSetPSBoxLocal
    
    
    j = 0
    For i = 1 To 18
        y.b1 = bytKey(j)
        y.b2 = bytKey((j + 1) Mod intKeyLen)
        y.b3 = bytKey((j + 2) Mod intKeyLen)
        y.b4 = bytKey((j + 3) Mod intKeyLen)
        LSet x = y
        p(i) = p(i) Xor x.w
        j = (j + 4) Mod intKeyLen
    Next
    
    lngDataL = 0: lngDataR = 0

    For i = 1 To 17 Step 2
        Call BFEncipher(lngDataL, lngDataR)
        p(i) = lngDataL
        p(i + 1) = lngDataR
    Next
    
    For i = 1 To 4
        For j = 0 To 254 Step 2
            Call BFEncipher(lngDataL, lngDataR)
            s(i, j) = lngDataL
            s(i, j + 1) = lngDataR
        Next j
    Next i
    
    mbIsInit = True
    
End Sub

Private Function f(Word As Long) As Long
    Dim x As LongByteW
    Dim y As LongByteB

    x.w = Word
    
    LSet y = x
    'Debug.Print S(1, Y.b1), S(2, Y.b2)
    f = fAddLongs(fAddLongs(s(1, y.b1), s(2, y.b2)) Xor (s(3, y.b3)), s(4, y.b4))
    

End Function

Private Sub Round(xL As Long, xR As Long, intRound As Integer)
    'Debug.Print F(xR), xR
    xL = xL Xor (f(xR) Xor p(intRound))
End Sub

Private Sub BFEncipher(xL As Long, xR As Long)
    Dim lngTemp As Long
    Dim i As Integer
    xL = xL Xor p(1)
    'Call sFilePrintSP
    For i = 2 To 16 Step 2
        Call Round(xR, xL, i)
        Call Round(xL, xR, i + 1)
    Next
    
    xR = xR Xor p(18)
    
    'Swap left and right
    lngTemp = xR
    xR = xL
    xL = lngTemp


End Sub


Private Sub BFDecipher(xL As Long, xR As Long)
    Dim lngTemp As Long
    Dim i As Integer
    
    xL = xL Xor p(18)
    
    For i = 17 To 3 Step -2
        Call Round(xR, xL, i)
        Call Round(xL, xR, i - 1)
    Next
    
    xR = xR Xor p(1)
    
    'Swap left and right
    lngTemp = xR
    xR = xL
    xL = lngTemp


End Sub


'Private Sub sFilePrintSP()
''For debugging only.
'
'    Dim i As Integer
'
'    Open "C:\Windows\Desktop\SPWin.txt" For Output As #1
'
'    Print #1, ""
'    Print #1, "PBox"
'    Print #1, ""
'    For i = 1 To 15 Step 6
'        Print #1, p(i), p(i + 1), p(i + 2), p(i + 3), p(i + 4), p(i + 5)
'    Next
'    Print #1, ""
'    Print #1, "SBox"
'    Print #1, ""
'    For i = 0 To 252 Step 4
'        Print #1, s(1, i), s(1, i + 1), s(1, i + 2), s(1, i + 3)
'    Next
'    Close #1
'
'
'
'End Sub

Public Sub sEncrypt(bytToEncrypt() As Byte, bytEncrypted() As Byte)

'This Sub assumes you are passing a 64 bit divisible zero-based array of bytes to
'encode and a similarly sized array to hold the encrypted version.
'Todo:  Add error checking for these conditions

    Dim lngLenBStr As Long
    Dim xL As LongByteB, xR  As LongByteB
    Dim yL As LongByteW, yR  As LongByteW
    Dim i As Long
    Dim bytB As Byte
    
    'Check zero based
    bytB = bytToEncrypt(0)
    bytB = bytEncrypted(0)
    
    
    If UBound(bytToEncrypt) <> UBound(bytEncrypted) Then
        Err.Raise BFErr + 2, strErrSrc, "Need to pass two byte arrays the same size"
        Exit Sub
    End If
    
    If (UBound(bytToEncrypt) + 1) Mod 8 <> 0 Then
        Err.Raise BFErr + 3, strErrSrc, "Byte array must be sized divisible by 8."
        Exit Sub
    End If
    
    If Not mbIsInit Then
        Err.Raise BFErr + 1, strErrSrc, "Call sInitBF before calling this sub"
        Exit Sub
    End If
    
    lngLenBStr = UBound(bytToEncrypt) + 1
    
    For i = 0 To lngLenBStr - 8 Step 8
        xL.b1 = bytToEncrypt(i)
        xL.b2 = bytToEncrypt(i + 1)
        xL.b3 = bytToEncrypt(i + 2)
        xL.b4 = bytToEncrypt(i + 3)
        
        xR.b1 = bytToEncrypt(i + 4)
        xR.b2 = bytToEncrypt(i + 5)
        xR.b3 = bytToEncrypt(i + 6)
        xR.b4 = bytToEncrypt(i + 7)
        
        LSet yR = xR
        LSet yL = xL
        
'        Debug.Print Hex(yL.w), Hex(yR.w)
        
        Call BFEncipher(yL.w, yR.w)
        
'        Debug.Print Hex(yL.w), Hex(yR.w)
        
        LSet xR = yR
        LSet xL = yL
        
        bytEncrypted(i) = xL.b1
        bytEncrypted(i + 1) = xL.b2
        bytEncrypted(i + 2) = xL.b3
        bytEncrypted(i + 3) = xL.b4
        
        bytEncrypted(i + 4) = xR.b1
        bytEncrypted(i + 5) = xR.b2
        bytEncrypted(i + 6) = xR.b3
        bytEncrypted(i + 7) = xR.b4
        
        
    Next i
    

End Sub


Public Sub sDecrypt(bytToDecrypt() As Byte, bytUnencrypted() As Byte)

'This Sub assumes you are passing a 64 bit divisible zero-based array of bytes to
'encode and a similarly sized array to hold the encrypted version.
'Todo:  Add error checking for these conditions

    Dim lngLenStr As Long
    Dim lngLenBStr As Long
    Dim xL As LongByteB, xR  As LongByteB
    Dim yL As LongByteW, yR  As LongByteW
    Dim i As Long
    
    lngLenStr = UBound(bytToDecrypt) + 1
    lngLenBStr = lngLenStr
    
    If UBound(bytToDecrypt) <> UBound(bytUnencrypted) Then
        Err.Raise BFErr + 2, strErrSrc, "Need to pass two byte arrays the same size"
        Exit Sub
    End If
    
    'MsgBox UBound(bytToDecrypt) + 1
    If (UBound(bytToDecrypt) + 1) Mod 8 <> 0 Then
        Err.Raise BFErr + 3, strErrSrc, "Byte array must be sized divisible by 8."
        Exit Sub
    End If
    
    If Not mbIsInit Then
        Err.Raise BFErr + 1, strErrSrc, "Call sInitBF before calling this sub"
        Exit Sub
    End If

    
    For i = 0 To lngLenBStr - 8 Step 8
        xL.b1 = bytToDecrypt(i)
        xL.b2 = bytToDecrypt(i + 1)
        xL.b3 = bytToDecrypt(i + 2)
        xL.b4 = bytToDecrypt(i + 3)
        
        xR.b1 = bytToDecrypt(i + 4)
        xR.b2 = bytToDecrypt(i + 5)
        xR.b3 = bytToDecrypt(i + 6)
        xR.b4 = bytToDecrypt(i + 7)
        
        LSet yR = xR
        LSet yL = xL
        
'        Debug.Print Hex(yL.w), Hex(yR.w)
        
        Call BFDecipher(yL.w, yR.w)
        
'        Debug.Print Hex(yL.w), Hex(yR.w)
        
        LSet xR = yR
        LSet xL = yL
        
        bytUnencrypted(i) = xL.b1
        bytUnencrypted(i + 1) = xL.b2
        bytUnencrypted(i + 2) = xL.b3
        bytUnencrypted(i + 3) = xL.b4
        
        bytUnencrypted(i + 4) = xR.b1
        bytUnencrypted(i + 5) = xR.b2
        bytUnencrypted(i + 6) = xR.b3
        bytUnencrypted(i + 7) = xR.b4
        
        
    Next i


End Sub


Private Sub sSetPSBox()

    Dim strPath As String
    Dim hFile As Integer
    
    strPath = App.Path
    
    If Right$(strPath, 1) <> "\" Then
        strPath = strPath & "\"
    End If
'    Debug.Print strPath
    If Len(Dir(strPath & "bf.dat")) = 0 Then
        Err.Raise BFErr + 3, , "bf.dat not found"
        Exit Sub
    End If
    
    hFile = FreeFile
    Open strPath & "bf.dat" For Binary As hFile
    Get #hFile, , p
    Get #hFile, , s
    Close #hFile
    
End Sub

Public Sub sFileEncrypt(strFileSrc As String, strFileTrg As String)
    
    
    Dim lngLen As Long
    Dim lngLenB As Long
    Dim bytSource() As Byte
    Dim bytTarget() As Byte
    Dim sngTimer As Single
    Dim hFile As Integer
    
    If Not mbIsInit Then
        Err.Raise BFErr + 1, , "Call sInitBF before calling this sub"
        Exit Sub
    End If
    
    If Len(Dir(strFileSrc)) = 0 Then
        Err.Raise BFErr + 2, , "Source file is not found"
        Exit Sub
    End If
    
    sngTimer = Timer
    
    lngLen = FileLen(strFileSrc)
    ReDim bytSource(0 To lngLen - 1)
    
    hFile = FreeFile
    Open strFileSrc For Binary As #hFile
    Get #hFile, , bytSource
    Close #hFile
    
    'Need to pad the string with zeroes if not divisible by 64 bits
    If lngLen Mod 8 <> 0 Then
        lngLenB = lngLen + (8 - lngLen Mod 8)
    Else
        lngLenB = lngLen
    End If
    
'    Debug.Print lngLenB
    
    ReDim Preserve bytSource(0 To lngLenB - 1)
    ReDim bytTarget(0 To lngLenB - 1)
    
    
    Call sEncrypt(bytSource, bytTarget)
    
    If Len(Dir(strFileTrg)) <> 0 Then
        Kill strFileTrg
    End If
    
    
    
    hFile = FreeFile
    Open strFileTrg For Binary As #hFile
    'Save the original file length so that we know how much padding to remove.
    Put #hFile, , lngLen
    Put #hFile, , bytTarget
    Close #hFile
    
    Debug.Print Timer - sngTimer


End Sub

Public Sub sFileDecrypt(strFileSrc As String, strFileTrg As String)
    
    
    Dim lngLen As Long
    Dim lngLenB As Long
    Dim bytSource() As Byte
    Dim bytTarget() As Byte
    Dim sngTimer As Single
    Dim hFile As Integer
    
    If Not mbIsInit Then
        Err.Raise BFErr + 1, , "Call sInitBF before calling this sub"
        Exit Sub
    End If
    
    If Len(Dir(strFileSrc)) = 0 Then
        Err.Raise BFErr + 2, , "Source file is not found"
        Exit Sub
    End If

    sngTimer = Timer
    
    
    lngLenB = FileLen(strFileSrc) - 4
    
'    Debug.Print lngLenB
    
    ReDim bytSource(0 To lngLenB - 1)
    ReDim bytTarget(0 To lngLenB - 1)
    
    
    hFile = FreeFile
    Open strFileSrc For Binary As #hFile
    Get #hFile, , lngLen
    Get #hFile, , bytSource
    Close #hFile
    
   
    
    Call sDecrypt(bytSource, bytTarget)
    
    ReDim Preserve bytTarget(0 To lngLen - 1)
    
    If Len(Dir(strFileTrg)) <> 0 Then
        Kill strFileTrg
    End If
    
    hFile = FreeFile
    Open strFileTrg For Binary As #hFile
    Put #hFile, , bytTarget
    Close #hFile
    
    Debug.Print Timer - sngTimer

End Sub

Private Sub sStringToByte(strS As String, bytB() As Byte)


bytB = StrConv(strS, vbFromUnicode)

End Sub

Public Sub sStringEncrypt(strToEncrypt As String, strEncrypted As String)
    Dim bytToEncrypt() As Byte
    Dim bytEncrypted() As Byte
    Dim lngLenStr As Long
    Dim lngLenBStr As Long
    
    
    
    lngLenStr = Len(strToEncrypt)
    
    'MsgBox lngLenStr
    
    'Need to pad the string with zeroes if not divisible by 64 bits
    If lngLenStr Mod 8 <> 0 Then
        lngLenBStr = lngLenStr + (8 - lngLenStr Mod 8)
    Else
        lngLenBStr = lngLenStr
    End If
    
    
'    ReDim bytToEncrypt(0 To lngLenBStr - 1)
    
    Call sStringToByte(strToEncrypt, bytToEncrypt)
    ReDim Preserve bytToEncrypt(0 To lngLenBStr - 1)
    ReDim bytEncrypted(0 To lngLenBStr - 1)
    
    Call sEncrypt(bytToEncrypt, bytEncrypted)
    
    strEncrypted = StrConv(bytEncrypted, vbUnicode)



End Sub


Public Sub sStringDecrypt(strToDecrypt As String, strUnencrypted As String)
     Dim bytToDecrypt() As Byte
    Dim bytDecrypted() As Byte
    Dim lngLenStr As Long
    Dim i As Long
    
    lngLenStr = Len(strToDecrypt)
    'Should be divisible by 8
    'TODO:
    'Error checking on 64 bit boundary

    If lngLenStr Mod 8 <> 0 Then
        Err.Raise BFErr + 3, , "String to decrypt should be sized divisible by 8."
        Exit Sub
    
    End If
 
    Call sStringToByte(strToDecrypt, bytToDecrypt)
    ReDim bytDecrypted(0 To UBound(bytToDecrypt))
    
    Call sDecrypt(bytToDecrypt, bytDecrypted)
    
    strUnencrypted = StrConv(bytDecrypted, vbUnicode)
    i = InStr(1, strUnencrypted, Chr(0))
    If i > 1 Then
        strUnencrypted = Left$(strUnencrypted, i - 1)
    End If
    



End Sub

Private Sub sSetPSBoxLocal()
    'These are the standard P and S buffer initialization vectors,
    'based on the hex digits of pi.  You could also use random data,
    'as long as you use the same random sequence every time.
    'However, these will work with the test vectors

    p(1) = 608135816
    p(2) = -2052912941
    p(3) = 320440878
    p(4) = 57701188
    p(5) = -1542899678
    p(6) = 698298832
    p(7) = 137296536
    p(8) = -330404727
    p(9) = 1160258022
    p(10) = 953160567
    p(11) = -1101764913
    p(12) = 887688300
    p(13) = -1062458953
    p(14) = -914599715
    p(15) = 1065670069
    p(16) = -1253635817
    p(17) = -1843997223
    p(18) = -1988494565
    s(1, 0) = -785314906
    s(1, 1) = -1730169428
    s(1, 2) = 805139163
    s(1, 3) = -803545161
    s(1, 4) = -1193168915
    s(1, 5) = 1780907670
    s(1, 6) = -1166241723
    s(1, 7) = -248741991
    s(1, 8) = 614570311
    s(1, 9) = -1282315017
    s(1, 10) = 134345442
    s(1, 11) = -2054226922
    s(1, 12) = 1667834072
    s(1, 13) = 1901547113
    s(1, 14) = -1537671517
    s(1, 15) = -191677058
    s(1, 16) = 227898511
    s(1, 17) = 1921955416
    s(1, 18) = 1904987480
    s(1, 19) = -2112533778
    s(1, 20) = 2069144605
    s(1, 21) = -1034266187
    s(1, 22) = -1674521287
    s(1, 23) = 720527379
    s(1, 24) = -976113629
    s(1, 25) = 677414384
    s(1, 26) = -901678824
    s(1, 27) = -1193592593
    s(1, 28) = -1904616272
    s(1, 29) = 1614419982
    s(1, 30) = 1822297739
    s(1, 31) = -1340175810
    s(1, 32) = -686458943
    s(1, 33) = -1120842969
    s(1, 34) = 2024746970
    s(1, 35) = 1432378464
    s(1, 36) = -430627341
    s(1, 37) = -1437226092
    s(1, 38) = 1464375394
    s(1, 39) = 1676153920
    s(1, 40) = 1439316330
    s(1, 41) = 715854006
    s(1, 42) = -1261675468
    s(1, 43) = 289532110
    s(1, 44) = -1588296017
    s(1, 45) = 2087905683
    s(1, 46) = -1276242927
    s(1, 47) = 1668267050
    s(1, 48) = 732546397
    s(1, 49) = 1947742710
    s(1, 50) = -832815594
    s(1, 51) = -1685613794
    s(1, 52) = -1344882125
    s(1, 53) = 1814351708
    s(1, 54) = 2050118529
    s(1, 55) = 680887927
    s(1, 56) = 999245976
    s(1, 57) = 1800124847
    s(1, 58) = -994056165
    s(1, 59) = 1713906067
    s(1, 60) = 1641548236
    s(1, 61) = -81679983
    s(1, 62) = 1216130144
    s(1, 63) = 1575780402
    s(1, 64) = -276538019
    s(1, 65) = -377129551
    s(1, 66) = -601480446
    s(1, 67) = -345695352
    s(1, 68) = 596196993
    s(1, 69) = -745100091
    s(1, 70) = 258830323
    s(1, 71) = -2081144263
    s(1, 72) = 772490370
    s(1, 73) = -1534844924
    s(1, 74) = 1774776394
    s(1, 75) = -1642095778
    s(1, 76) = 566650946
    s(1, 77) = -152474470
    s(1, 78) = 1728879713
    s(1, 79) = -1412200208
    s(1, 80) = 1783734482
    s(1, 81) = -665571480
    s(1, 82) = -1777359064
    s(1, 83) = -1420741725
    s(1, 84) = 1861159788
    s(1, 85) = 326777828
    s(1, 86) = -1170476976
    s(1, 87) = 2130389656
    s(1, 88) = -1578015459
    s(1, 89) = 967770486
    s(1, 90) = 1724537150
    s(1, 91) = -2109534584
    s(1, 92) = -1930525159
    s(1, 93) = 1164943284
    s(1, 94) = 2105845187
    s(1, 95) = 998989502
    s(1, 96) = -529566248
    s(1, 97) = -2050940813
    s(1, 98) = 1075463327
    s(1, 99) = 1455516326
    s(1, 100) = 1322494562
    s(1, 101) = 910128902
    s(1, 102) = 469688178
    s(1, 103) = 1117454909
    s(1, 104) = 936433444
    s(1, 105) = -804646328
    s(1, 106) = -619713837
    s(1, 107) = 1240580251
    s(1, 108) = 122909385
    s(1, 109) = -2137449605
    s(1, 110) = 634681816
    s(1, 111) = -152510729
    s(1, 112) = -469872614
    s(1, 113) = -1233564613
    s(1, 114) = -1754472259
    s(1, 115) = 79693498
    s(1, 116) = -1045868618
    s(1, 117) = 1084186820
    s(1, 118) = 1583128258
    s(1, 119) = 426386531
    s(1, 120) = 1761308591
    s(1, 121) = 1047286709
    s(1, 122) = 322548459
    s(1, 123) = 995290223
    s(1, 124) = 1845252383
    s(1, 125) = -1691314900
    s(1, 126) = -863943356
    s(1, 127) = -1352745719
    s(1, 128) = -1092366332
    s(1, 129) = -567063811
    s(1, 130) = 1712269319
    s(1, 131) = 422464435
    s(1, 132) = -1060394921
    s(1, 133) = 1170764815
    s(1, 134) = -771006663
    s(1, 135) = -1177289765
    s(1, 136) = 1434042557
    s(1, 137) = 442511882
    s(1, 138) = -694091578
    s(1, 139) = 1076654713
    s(1, 140) = 1738483198
    s(1, 141) = -81812532
    s(1, 142) = -1901729288
    s(1, 143) = -617471240
    s(1, 144) = 1014306527
    s(1, 145) = -43947243
    s(1, 146) = 793779912
    s(1, 147) = -1392160085
    s(1, 148) = 842905082
    s(1, 149) = -48003232
    s(1, 150) = 1395751752
    s(1, 151) = 1040244610
    s(1, 152) = -1638115397
    s(1, 153) = -898659168
    s(1, 154) = 445077038
    s(1, 155) = -552113701
    s(1, 156) = -717051658
    s(1, 157) = 679411651
    s(1, 158) = -1402522938
    s(1, 159) = -1940957837
    s(1, 160) = 1767581616
    s(1, 161) = -1144366904
    s(1, 162) = -503340195
    s(1, 163) = -1192226400
    s(1, 164) = 284835224
    s(1, 165) = -48135240
    s(1, 166) = 1258075500
    s(1, 167) = 768725851
    s(1, 168) = -1705778055
    s(1, 169) = -1225243291
    s(1, 170) = -762426948
    s(1, 171) = 1274779536
    s(1, 172) = -505548070
    s(1, 173) = -1530167757
    s(1, 174) = 1660621633
    s(1, 175) = -823867672
    s(1, 176) = -283063590
    s(1, 177) = 913787905
    s(1, 178) = -797008130
    s(1, 179) = 737222580
    s(1, 180) = -1780753843
    s(1, 181) = -1366257256
    s(1, 182) = -357724559
    s(1, 183) = 1804850592
    s(1, 184) = -795946544
    s(1, 185) = -1345903136
    s(1, 186) = -1908647121
    s(1, 187) = -1904896841
    s(1, 188) = -1879645445
    s(1, 189) = -233690268
    s(1, 190) = -2004305902
    s(1, 191) = -1878134756
    s(1, 192) = 1336762016
    s(1, 193) = 1754252060
    s(1, 194) = -774901359
    s(1, 195) = -1280786003
    s(1, 196) = 791618072
    s(1, 197) = -1106372745
    s(1, 198) = -361419266
    s(1, 199) = -1962795103
    s(1, 200) = -442446833
    s(1, 201) = -1250986776
    s(1, 202) = 413987798
    s(1, 203) = -829824359
    s(1, 204) = -1264037920
    s(1, 205) = -49028937
    s(1, 206) = 2093235073
    s(1, 207) = -760370983
    s(1, 208) = 375366246
    s(1, 209) = -2137688315
    s(1, 210) = -1815317740
    s(1, 211) = 555357303
    s(1, 212) = -424861595
    s(1, 213) = 2008414854
    s(1, 214) = -950779147
    s(1, 215) = -73583153
    s(1, 216) = -338841844
    s(1, 217) = 2067696032
    s(1, 218) = -700376109
    s(1, 219) = -1373733303
    s(1, 220) = 2428461
    s(1, 221) = 544322398
    s(1, 222) = 577241275
    s(1, 223) = 1471733935
    s(1, 224) = 610547355
    s(1, 225) = -267798242
    s(1, 226) = 1432588573
    s(1, 227) = 1507829418
    s(1, 228) = 2025931657
    s(1, 229) = -648391809
    s(1, 230) = 545086370
    s(1, 231) = 48609733
    s(1, 232) = -2094660746
    s(1, 233) = 1653985193
    s(1, 234) = 298326376
    s(1, 235) = 1316178497
    s(1, 236) = -1287180854
    s(1, 237) = 2064951626
    s(1, 238) = 458293330
    s(1, 239) = -1705826027
    s(1, 240) = -703637697
    s(1, 241) = -1130641692
    s(1, 242) = 727753846
    s(1, 243) = -2115603456
    s(1, 244) = 146436021
    s(1, 245) = 1461446943
    s(1, 246) = -224990101
    s(1, 247) = 705550613
    s(1, 248) = -1235000031
    s(1, 249) = -407242314
    s(1, 250) = -13368018
    s(1, 251) = -981117340
    s(1, 252) = 1404054877
    s(1, 253) = -1449160799
    s(1, 254) = 146425753
    s(1, 255) = 1854211946
    s(2, 0) = 1266315497
    s(2, 1) = -1246549692
    s(2, 2) = -613086930
    s(2, 3) = -1004984797
    s(2, 4) = -1385257296
    s(2, 5) = 1235738493
    s(2, 6) = -1662099272
    s(2, 7) = -1880247706
    s(2, 8) = -324367247
    s(2, 9) = 1771706367
    s(2, 10) = 1449415276
    s(2, 11) = -1028546847
    s(2, 12) = 422970021
    s(2, 13) = 1963543593
    s(2, 14) = -1604775104
    s(2, 15) = -468174274
    s(2, 16) = 1062508698
    s(2, 17) = 1531092325
    s(2, 18) = 1804592342
    s(2, 19) = -1711849514
    s(2, 20) = -1580033017
    s(2, 21) = -269995787
    s(2, 22) = 1294809318
    s(2, 23) = -265986623
    s(2, 24) = 1289560198
    s(2, 25) = -2072974554
    s(2, 26) = 1669523910
    s(2, 27) = 35572830
    s(2, 28) = 157838143
    s(2, 29) = 1052438473
    s(2, 30) = 1016535060
    s(2, 31) = 1802137761
    s(2, 32) = 1753167236
    s(2, 33) = 1386275462
    s(2, 34) = -1214491899
    s(2, 35) = -1437595849
    s(2, 36) = 1040679964
    s(2, 37) = 2145300060
    s(2, 38) = -1904392980
    s(2, 39) = 1461121720
    s(2, 40) = -1338320329
    s(2, 41) = -263189491
    s(2, 42) = -266592508
    s(2, 43) = 33600511
    s(2, 44) = -1374882534
    s(2, 45) = 1018524850
    s(2, 46) = 629373528
    s(2, 47) = -603381315
    s(2, 48) = -779021319
    s(2, 49) = 2091462646
    s(2, 50) = -1808644237
    s(2, 51) = 586499841
    s(2, 52) = 988145025
    s(2, 53) = 935516892
    s(2, 54) = -927631820
    s(2, 55) = -1695294041
    s(2, 56) = -1455136442
    s(2, 57) = 265290510
    s(2, 58) = -322386114
    s(2, 59) = -1535828415
    s(2, 60) = -499593831
    s(2, 61) = 1005194799
    s(2, 62) = 847297441
    s(2, 63) = 406762289
    s(2, 64) = 1314163512
    s(2, 65) = 1332590856
    s(2, 66) = 1866599683
    s(2, 67) = -167115585
    s(2, 68) = 750260880
    s(2, 69) = 613907577
    s(2, 70) = 1450815602
    s(2, 71) = -1129346641
    s(2, 72) = -560302305
    s(2, 73) = -644675568
    s(2, 74) = -1282691566
    s(2, 75) = -590397650
    s(2, 76) = 1427272223
    s(2, 77) = 778793252
    s(2, 78) = 1343938022
    s(2, 79) = -1618686585
    s(2, 80) = 2052605720
    s(2, 81) = 1946737175
    s(2, 82) = -1130390852
    s(2, 83) = -380928628
    s(2, 84) = -327488454
    s(2, 85) = -612033030
    s(2, 86) = 1661551462
    s(2, 87) = -1000029230
    s(2, 88) = -283371449
    s(2, 89) = 840292616
    s(2, 90) = -582796489
    s(2, 91) = 616741398
    s(2, 92) = 312560963
    s(2, 93) = 711312465
    s(2, 94) = 1351876610
    s(2, 95) = 322626781
    s(2, 96) = 1910503582
    s(2, 97) = 271666773
    s(2, 98) = -2119403562
    s(2, 99) = 1594956187
    s(2, 100) = 70604529
    s(2, 101) = -677132437
    s(2, 102) = 1007753275
    s(2, 103) = 1495573769
    s(2, 104) = -225450259
    s(2, 105) = -1745748998
    s(2, 106) = -1631928532
    s(2, 107) = 504708206
    s(2, 108) = -2031925904
    s(2, 109) = -353800271
    s(2, 110) = -2045878774
    s(2, 111) = 1514023603
    s(2, 112) = 1998579484
    s(2, 113) = 1312622330
    s(2, 114) = 694541497
    s(2, 115) = -1712906993
    s(2, 116) = -2143385130
    s(2, 117) = 1382467621
    s(2, 118) = 776784248
    s(2, 119) = -1676627094
    s(2, 120) = -971698502
    s(2, 121) = -1797068168
    s(2, 122) = -1510196141
    s(2, 123) = 503983604
    s(2, 124) = -218673497
    s(2, 125) = 907881277
    s(2, 126) = 423175695
    s(2, 127) = 432175456
    s(2, 128) = 1378068232
    s(2, 129) = -149744970
    s(2, 130) = -340918674
    s(2, 131) = -356311194
    s(2, 132) = -474200683
    s(2, 133) = -1501837181
    s(2, 134) = -1317062703
    s(2, 135) = 26017576
    s(2, 136) = -1020076561
    s(2, 137) = -1100195163
    s(2, 138) = 1700274565
    s(2, 139) = 1756076034
    s(2, 140) = -288447217
    s(2, 141) = -617638597
    s(2, 142) = 720338349
    s(2, 143) = 1533947780
    s(2, 144) = 354530856
    s(2, 145) = 688349552
    s(2, 146) = -321042571
    s(2, 147) = 1637815568
    s(2, 148) = 332179504
    s(2, 149) = -345916010
    s(2, 150) = 53804574
    s(2, 151) = -1442618417
    s(2, 152) = -1250730864
    s(2, 153) = 1282449977
    s(2, 154) = -711025141
    s(2, 155) = -877994476
    s(2, 156) = -288586052
    s(2, 157) = 1617046695
    s(2, 158) = -1666491221
    s(2, 159) = -1292663698
    s(2, 160) = 1686838959
    s(2, 161) = 431878346
    s(2, 162) = -1608291911
    s(2, 163) = 1700445008
    s(2, 164) = 1080580658
    s(2, 165) = 1009431731
    s(2, 166) = 832498133
    s(2, 167) = -1071531785
    s(2, 168) = -1688990951
    s(2, 169) = -2023776103
    s(2, 170) = -1778935426
    s(2, 171) = 1648197032
    s(2, 172) = -130578278
    s(2, 173) = -1746719369
    s(2, 174) = 300782431
    s(2, 175) = 375919233
    s(2, 176) = 238389289
    s(2, 177) = -941219882
    s(2, 178) = -1763778655
    s(2, 179) = 2019080857
    s(2, 180) = 1475708069
    s(2, 181) = 455242339
    s(2, 182) = -1685863425
    s(2, 183) = 448939670
    s(2, 184) = -843904277
    s(2, 185) = 1395535956
    s(2, 186) = -1881585436
    s(2, 187) = 1841049896
    s(2, 188) = 1491858159
    s(2, 189) = 885456874
    s(2, 190) = -30872223
    s(2, 191) = -293847949
    s(2, 192) = 1565136089
    s(2, 193) = -396052509
    s(2, 194) = 1108368660
    s(2, 195) = 540939232
    s(2, 196) = 1173283510
    s(2, 197) = -1549095958
    s(2, 198) = -613658859
    s(2, 199) = -87339056
    s(2, 200) = -951913406
    s(2, 201) = -278217803
    s(2, 202) = 1699691293
    s(2, 203) = 1103962373
    s(2, 204) = -669091426
    s(2, 205) = -2038084153
    s(2, 206) = -464828566
    s(2, 207) = 1031889488
    s(2, 208) = -815619598
    s(2, 209) = 1535977030
    s(2, 210) = -58162272
    s(2, 211) = -1043876189
    s(2, 212) = 2132092099
    s(2, 213) = 1774941330
    s(2, 214) = 1199868427
    s(2, 215) = 1452454533
    s(2, 216) = 157007616
    s(2, 217) = -1390851939
    s(2, 218) = 342012276
    s(2, 219) = 595725824
    s(2, 220) = 1480756522
    s(2, 221) = 206960106
    s(2, 222) = 497939518
    s(2, 223) = 591360097
    s(2, 224) = 863170706
    s(2, 225) = -1919713727
    s(2, 226) = -698356495
    s(2, 227) = 1814182875
    s(2, 228) = 2094937945
    s(2, 229) = -873565088
    s(2, 230) = 1082520231
    s(2, 231) = -831049106
    s(2, 232) = -1509457788
    s(2, 233) = 435703966
    s(2, 234) = -386934699
    s(2, 235) = 1641649973
    s(2, 236) = -1452693590
    s(2, 237) = -989067582
    s(2, 238) = 1510255612
    s(2, 239) = -2146710820
    s(2, 240) = -1639679442
    s(2, 241) = -1018874748
    s(2, 242) = -36346107
    s(2, 243) = 236887753
    s(2, 244) = -613164077
    s(2, 245) = 274041037
    s(2, 246) = 1734335097
    s(2, 247) = -479771840
    s(2, 248) = -976997275
    s(2, 249) = 1899903192
    s(2, 250) = 1026095262
    s(2, 251) = -244449504
    s(2, 252) = 356393447
    s(2, 253) = -1884275382
    s(2, 254) = -421290197
    s(2, 255) = -612127241
    s(3, 0) = -381855128
    s(3, 1) = -1803468553
    s(3, 2) = -162781668
    s(3, 3) = -1805047500
    s(3, 4) = 1091903735
    s(3, 5) = 1979897079
    s(3, 6) = -1124832466
    s(3, 7) = -727580568
    s(3, 8) = -737663887
    s(3, 9) = 857797738
    s(3, 10) = 1136121015
    s(3, 11) = 1342202287
    s(3, 12) = 507115054
    s(3, 13) = -1759230650
    s(3, 14) = 337727348
    s(3, 15) = -1081374656
    s(3, 16) = 1301675037
    s(3, 17) = -1766485585
    s(3, 18) = 1895095763
    s(3, 19) = 1721773893
    s(3, 20) = -1078195732
    s(3, 21) = 62756741
    s(3, 22) = 2142006736
    s(3, 23) = 835421444
    s(3, 24) = -1762973773
    s(3, 25) = 1442658625
    s(3, 26) = -635090970
    s(3, 27) = -1412822374
    s(3, 28) = 676362277
    s(3, 29) = 1392781812
    s(3, 30) = 170690266
    s(3, 31) = -373920261
    s(3, 32) = 1759253602
    s(3, 33) = -683120384
    s(3, 34) = 1745797284
    s(3, 35) = 664899054
    s(3, 36) = 1329594018
    s(3, 37) = -393761396
    s(3, 38) = -1249058810
    s(3, 39) = 2062866102
    s(3, 40) = -1429332356
    s(3, 41) = -751345684
    s(3, 42) = -830954599
    s(3, 43) = 1080764994
    s(3, 44) = 553557557
    s(3, 45) = -638351943
    s(3, 46) = -298199125
    s(3, 47) = 991055499
    s(3, 48) = 499776247
    s(3, 49) = 1265440854
    s(3, 50) = 648242737
    s(3, 51) = -354183246
    s(3, 52) = 980351604
    s(3, 53) = -581221582
    s(3, 54) = 1749149687
    s(3, 55) = -898096901
    s(3, 56) = -83167922
    s(3, 57) = -654396521
    s(3, 58) = 1161844396
    s(3, 59) = -1169648345
    s(3, 60) = 1431517754
    s(3, 61) = 545492359
    s(3, 62) = -26498633
    s(3, 63) = -795437749
    s(3, 64) = 1437099964
    s(3, 65) = -1592419752
    s(3, 66) = -861329053
    s(3, 67) = -1713251533
    s(3, 68) = -1507177898
    s(3, 69) = 1060185593
    s(3, 70) = 1593081372
    s(3, 71) = -1876348548
    s(3, 72) = -34019326
    s(3, 73) = 69676912
    s(3, 74) = -2135222948
    s(3, 75) = 86519011
    s(3, 76) = -1782508216
    s(3, 77) = -456757982
    s(3, 78) = 1220612927
    s(3, 79) = -955283748
    s(3, 80) = 133810670
    s(3, 81) = 1090789135
    s(3, 82) = 1078426020
    s(3, 83) = 1569222167
    s(3, 84) = 845107691
    s(3, 85) = -711212847
    s(3, 86) = -222510705
    s(3, 87) = 1091646820
    s(3, 88) = 628848692
    s(3, 89) = 1613405280
    s(3, 90) = -537335645
    s(3, 91) = 526609435
    s(3, 92) = 236106946
    s(3, 93) = 48312990
    s(3, 94) = -1352249391
    s(3, 95) = -892239595
    s(3, 96) = 1797494240
    s(3, 97) = 859738849
    s(3, 98) = 992217954
    s(3, 99) = -289490654
    s(3, 100) = -2051890674
    s(3, 101) = -424014439
    s(3, 102) = -562951028
    s(3, 103) = 765654824
    s(3, 104) = -804095931
    s(3, 105) = -1783130883
    s(3, 106) = 1685915746
    s(3, 107) = -405998096
    s(3, 108) = 1414112111
    s(3, 109) = -2021832454
    s(3, 110) = -1013056217
    s(3, 111) = -214004450
    s(3, 112) = 172450625
    s(3, 113) = -1724973196
    s(3, 114) = 980381355
    s(3, 115) = -185008841
    s(3, 116) = -1475158944
    s(3, 117) = -1578377736
    s(3, 118) = -1726226100
    s(3, 119) = -613520627
    s(3, 120) = -964995824
    s(3, 121) = 1835478071
    s(3, 122) = 660984891
    s(3, 123) = -590288892
    s(3, 124) = -248967737
    s(3, 125) = -872349789
    s(3, 126) = -1254551662
    s(3, 127) = 1762651403
    s(3, 128) = 1719377915
    s(3, 129) = -824476260
    s(3, 130) = -1601057013
    s(3, 131) = -652910941
    s(3, 132) = -1156370552
    s(3, 133) = 1364962596
    s(3, 134) = 2073328063
    s(3, 135) = 1983633131
    s(3, 136) = 926494387
    s(3, 137) = -871278215
    s(3, 138) = -2144935273
    s(3, 139) = -198299347
    s(3, 140) = 1749200295
    s(3, 141) = -966120645
    s(3, 142) = 309677260
    s(3, 143) = 2016342300
    s(3, 144) = 1779581495
    s(3, 145) = -1215147545
    s(3, 146) = 111262694
    s(3, 147) = 1274766160
    s(3, 148) = 443224088
    s(3, 149) = 298511866
    s(3, 150) = 1025883608
    s(3, 151) = -488520759
    s(3, 152) = 1145181785
    s(3, 153) = 168956806
    s(3, 154) = -653464466
    s(3, 155) = -710153686
    s(3, 156) = 1689216846
    s(3, 157) = -628709281
    s(3, 158) = -1094719096
    s(3, 159) = 1692713982
    s(3, 160) = -1648590761
    s(3, 161) = -252198778
    s(3, 162) = 1618508792
    s(3, 163) = 1610833997
    s(3, 164) = -771914938
    s(3, 165) = -164094032
    s(3, 166) = 2001055236
    s(3, 167) = -684262196
    s(3, 168) = -2092799181
    s(3, 169) = -266425487
    s(3, 170) = -1333771897
    s(3, 171) = 1006657119
    s(3, 172) = 2006996926
    s(3, 173) = -1108824540
    s(3, 174) = 1430667929
    s(3, 175) = -1084739999
    s(3, 176) = 1314452623
    s(3, 177) = -220332638
    s(3, 178) = -193663176
    s(3, 179) = -2021016126
    s(3, 180) = 1399257539
    s(3, 181) = -927756684
    s(3, 182) = -1267338667
    s(3, 183) = 1190975929
    s(3, 184) = 2062231137
    s(3, 185) = -1960976508
    s(3, 186) = -2073424263
    s(3, 187) = -1856006686
    s(3, 188) = 1181637006
    s(3, 189) = 548689776
    s(3, 190) = -1932175983
    s(3, 191) = -922558900
    s(3, 192) = -1190417183
    s(3, 193) = -1149106736
    s(3, 194) = 296247880
    s(3, 195) = 1970579870
    s(3, 196) = -1216407114
    s(3, 197) = -525738999
    s(3, 198) = 1714227617
    s(3, 199) = -1003338189
    s(3, 200) = -396747006
    s(3, 201) = 166772364
    s(3, 202) = 1251581989
    s(3, 203) = 493813264
    s(3, 204) = 448347421
    s(3, 205) = 195405023
    s(3, 206) = -1584991729
    s(3, 207) = 677966185
    s(3, 208) = -591930749
    s(3, 209) = 1463355134
    s(3, 210) = -1578971493
    s(3, 211) = 1338867538
    s(3, 212) = 1343315457
    s(3, 213) = -1492745222
    s(3, 214) = -1610435132
    s(3, 215) = 233230375
    s(3, 216) = -1694987225
    s(3, 217) = 2000651841
    s(3, 218) = -1017099258
    s(3, 219) = 1638401717
    s(3, 220) = -266896856
    s(3, 221) = -1057650976
    s(3, 222) = 6314154
    s(3, 223) = 819756386
    s(3, 224) = 300326615
    s(3, 225) = 590932579
    s(3, 226) = 1405279636
    s(3, 227) = -1027467724
    s(3, 228) = -1144263082
    s(3, 229) = -1866680610
    s(3, 230) = -335774303
    s(3, 231) = -833020554
    s(3, 232) = 1862657033
    s(3, 233) = 1266418056
    s(3, 234) = 963775037
    s(3, 235) = 2089974820
    s(3, 236) = -2031914401
    s(3, 237) = 1917689273
    s(3, 238) = 448879540
    s(3, 239) = -744572676
    s(3, 240) = -313240200
    s(3, 241) = 150775221
    s(3, 242) = -667058989
    s(3, 243) = 1303187396
    s(3, 244) = 508620638
    s(3, 245) = -1318983944
    s(3, 246) = -1568336679
    s(3, 247) = 1817252668
    s(3, 248) = 1876281319
    s(3, 249) = 1457606340
    s(3, 250) = 908771278
    s(3, 251) = -574175177
    s(3, 252) = -677760460
    s(3, 253) = -1838972398
    s(3, 254) = 1729034894
    s(3, 255) = 1080033504
    s(4, 0) = 976866871
    s(4, 1) = -738527793
    s(4, 2) = -1413318857
    s(4, 3) = 1522871579
    s(4, 4) = 1555064734
    s(4, 5) = 1336096578
    s(4, 6) = -746444992
    s(4, 7) = -1715692610
    s(4, 8) = -720269667
    s(4, 9) = -1089506539
    s(4, 10) = -701686658
    s(4, 11) = -956251013
    s(4, 12) = -1215554709
    s(4, 13) = 564236357
    s(4, 14) = -1301368386
    s(4, 15) = 1781952180
    s(4, 16) = 1464380207
    s(4, 17) = -1131123079
    s(4, 18) = -962365742
    s(4, 19) = 1699332808
    s(4, 20) = 1393555694
    s(4, 21) = 1183702653
    s(4, 22) = -713881059
    s(4, 23) = 1288719814
    s(4, 24) = 691649499
    s(4, 25) = -1447410096
    s(4, 26) = -1399511320
    s(4, 27) = -1101077756
    s(4, 28) = -1577396752
    s(4, 29) = 1781354906
    s(4, 30) = 1676643554
    s(4, 31) = -1702433246
    s(4, 32) = -1064713544
    s(4, 33) = 1126444790
    s(4, 34) = -1524759638
    s(4, 35) = -1661808476
    s(4, 36) = -2084544070
    s(4, 37) = -1679201715
    s(4, 38) = -1880812208
    s(4, 39) = -1167828010
    s(4, 40) = 673620729
    s(4, 41) = -1489356063
    s(4, 42) = 1269405062
    s(4, 43) = -279616791
    s(4, 44) = -953159725
    s(4, 45) = -145557542
    s(4, 46) = 1057255273
    s(4, 47) = 2012875353
    s(4, 48) = -2132498155
    s(4, 49) = -2018474495
    s(4, 50) = -1693849939
    s(4, 51) = 993977747
    s(4, 52) = -376373926
    s(4, 53) = -1640704105
    s(4, 54) = 753973209
    s(4, 55) = 36408145
    s(4, 56) = -1764381638
    s(4, 57) = 25011837
    s(4, 58) = -774947114
    s(4, 59) = 2088578344
    s(4, 60) = 530523599
    s(4, 61) = -1376601957
    s(4, 62) = 1524020338
    s(4, 63) = 1518925132
    s(4, 64) = -534139791
    s(4, 65) = -535190042
    s(4, 66) = 1202760957
    s(4, 67) = -309069157
    s(4, 68) = -388774771
    s(4, 69) = 674977740
    s(4, 70) = -120232407
    s(4, 71) = 2031300136
    s(4, 72) = 2019492241
    s(4, 73) = -311074731
    s(4, 74) = -141160892
    s(4, 75) = -472686964
    s(4, 76) = 352677332
    s(4, 77) = -1997247046
    s(4, 78) = 60907813
    s(4, 79) = 90501309
    s(4, 80) = -1007968747
    s(4, 81) = 1016092578
    s(4, 82) = -1759044884
    s(4, 83) = -1455814870
    s(4, 84) = 457141659
    s(4, 85) = 509813237
    s(4, 86) = -174299397
    s(4, 87) = 652014361
    s(4, 88) = 1966332200
    s(4, 89) = -1319764491
    s(4, 90) = 55981186
    s(4, 91) = -1967506245
    s(4, 92) = 676427537
    s(4, 93) = -1039476232
    s(4, 94) = -1412673177
    s(4, 95) = -861040033
    s(4, 96) = 1307055953
    s(4, 97) = 942726286
    s(4, 98) = 933058658
    s(4, 99) = -1826555503
    s(4, 100) = -361066302
    s(4, 101) = -79791154
    s(4, 102) = 1361170020
    s(4, 103) = 2001714738
    s(4, 104) = -1464409218
    s(4, 105) = -1020707514
    s(4, 106) = 1222529897
    s(4, 107) = 1679025792
    s(4, 108) = -1565652976
    s(4, 109) = -580013532
    s(4, 110) = 1770335741
    s(4, 111) = 151462246
    s(4, 112) = -1281735158
    s(4, 113) = 1682292957
    s(4, 114) = 1483529935
    s(4, 115) = 471910574
    s(4, 116) = 1539241949
    s(4, 117) = 458788160
    s(4, 118) = -858652289
    s(4, 119) = 1807016891
    s(4, 120) = -576558466
    s(4, 121) = 978976581
    s(4, 122) = 1043663428
    s(4, 123) = -1129001515
    s(4, 124) = 1927990952
    s(4, 125) = -94075717
    s(4, 126) = -1922690386
    s(4, 127) = -1086558393
    s(4, 128) = -761535389
    s(4, 129) = 1412390302
    s(4, 130) = -1362987237
    s(4, 131) = -162634896
    s(4, 132) = 1947078029
    s(4, 133) = -413461673
    s(4, 134) = -126740879
    s(4, 135) = -1353482915
    s(4, 136) = 1077988104
    s(4, 137) = 1320477388
    s(4, 138) = 886195818
    s(4, 139) = 18198404
    s(4, 140) = -508558296
    s(4, 141) = -1785185763
    s(4, 142) = 112762804
    s(4, 143) = -831610808
    s(4, 144) = 1866414978
    s(4, 145) = 891333506
    s(4, 146) = 18488651
    s(4, 147) = 661792760
    s(4, 148) = 1628790961
    s(4, 149) = -409780260
    s(4, 150) = -1153795797
    s(4, 151) = 876946877
    s(4, 152) = -1601685023
    s(4, 153) = 1372485963
    s(4, 154) = 791857591
    s(4, 155) = -1608533303
    s(4, 156) = -534984578
    s(4, 157) = -1127755274
    s(4, 158) = -822013501
    s(4, 159) = -1578587449
    s(4, 160) = 445679433
    s(4, 161) = -732971622
    s(4, 162) = -790962485
    s(4, 163) = -720709064
    s(4, 164) = 54117162
    s(4, 165) = -963561881
    s(4, 166) = -1913048708
    s(4, 167) = -525259953
    s(4, 168) = -140617289
    s(4, 169) = 1140177722
    s(4, 170) = -220915201
    s(4, 171) = 668550556
    s(4, 172) = -1080614356
    s(4, 173) = 367459370
    s(4, 174) = 261225585
    s(4, 175) = -1684794075
    s(4, 176) = -85617823
    s(4, 177) = -826893077
    s(4, 178) = -1029151655
    s(4, 179) = 314222801
    s(4, 180) = -1228863650
    s(4, 181) = -486184436
    s(4, 182) = 282218597
    s(4, 183) = -888953790
    s(4, 184) = -521376242
    s(4, 185) = 379116347
    s(4, 186) = 1285071038
    s(4, 187) = 846784868
    s(4, 188) = -1625320142
    s(4, 189) = -523005217
    s(4, 190) = -744475605
    s(4, 191) = -1989021154
    s(4, 192) = 453669953
    s(4, 193) = 1268987020
    s(4, 194) = -977374944
    s(4, 195) = -1015663912
    s(4, 196) = -550133875
    s(4, 197) = -1684459730
    s(4, 198) = -435458233
    s(4, 199) = 266596637
    s(4, 200) = -447948204
    s(4, 201) = 517658769
    s(4, 202) = -832407089
    s(4, 203) = -851542417
    s(4, 204) = 370717030
    s(4, 205) = -47440635
    s(4, 206) = -2070949179
    s(4, 207) = -151313767
    s(4, 208) = -182193321
    s(4, 209) = -1506642397
    s(4, 210) = -1817692879
    s(4, 211) = 1456262402
    s(4, 212) = -1393524382
    s(4, 213) = 1517677493
    s(4, 214) = 1846949527
    s(4, 215) = -1999473716
    s(4, 216) = -560569710
    s(4, 217) = -2118563376
    s(4, 218) = 1280348187
    s(4, 219) = 1908823572
    s(4, 220) = -423180355
    s(4, 221) = 846861322
    s(4, 222) = 1172426758
    s(4, 223) = -1007518822
    s(4, 224) = -911584259
    s(4, 225) = 1655181056
    s(4, 226) = -1155153950
    s(4, 227) = 901632758
    s(4, 228) = 1897031941
    s(4, 229) = -1308360158
    s(4, 230) = -1228157060
    s(4, 231) = -847864789
    s(4, 232) = 1393639104
    s(4, 233) = 373351379
    s(4, 234) = 950779232
    s(4, 235) = 625454576
    s(4, 236) = -1170726756
    s(4, 237) = -146354570
    s(4, 238) = 2007998917
    s(4, 239) = 544563296
    s(4, 240) = -2050228658
    s(4, 241) = -1964470824
    s(4, 242) = 2058025392
    s(4, 243) = 1291430526
    s(4, 244) = 424198748
    s(4, 245) = 50039436
    s(4, 246) = 29584100
    s(4, 247) = -689184263
    s(4, 248) = -1865090967
    s(4, 249) = -1503863136
    s(4, 250) = 1057563949
    s(4, 251) = -1039604065
    s(4, 252) = -1219600078
    s(4, 253) = -831004069
    s(4, 254) = 1469046755
    s(4, 255) = 985887462


End Sub



Public Function fStringToHexCode(strText As String) As String
    Dim b() As Byte
    Dim i As Integer
    Dim strRet As String
    
    b = strText
    strRet = Space((UBound(b) + 1) * 2)
    For i = 0 To UBound(b)
        Mid$(strRet, (i * 2) + 1, 2) = IIf(b(i) < 16, "0", "") & Hex(b(i))
    Next
    fStringToHexCode = strRet
End Function

Public Function fHexCodeToString(strHex As String) As String
    Dim b() As Byte
    Dim i As Integer
    ReDim b((Len(strHex) / 2) - 1)
    
    For i = 0 To UBound(b)
        b(i) = CByte("&H" & Mid$(strHex, (i * 2) + 1, 2))
    Next
    fHexCodeToString = b
End Function


