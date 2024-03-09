Attribute VB_Name = "basEncode"
Option Explicit

Option Base 0

Public Const encodeKey5 = "nirz"
Public Const encodeKey4 = "husw"
Public Const encodeKey = "0kmm399sj"
Public Const encodeKey2 = "apl4fzz9gf2apw8an"
Public Const encodeKey3 = "anrrl2"

Private Const MD5_BLK_LEN As Long = 64
Private Const S11 As Long = 7
Private Const S12 As Long = 12
Private Const S13 As Long = 17
Private Const S14 As Long = 22
Private Const S21 As Long = 5
Private Const S22 As Long = 9
Private Const S23 As Long = 14
Private Const S24 As Long = 20
Private Const S31 As Long = 4
Private Const S32 As Long = 11
Private Const S33 As Long = 16
Private Const S34 As Long = 23
Private Const S41 As Long = 6
Private Const S42 As Long = 10
Private Const S43 As Long = 15
Private Const S44 As Long = 21
Private Const OFFSET_4 = 4294967296#
Private Const MAXINT_4 = 2147483647

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
' Copyright ©1996-2007 VBnet, Randy Birch, All Rights Reserved.
' Some pages may also contain other copyrights by the author.
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
' Distribution: You can freely use this code in your own
'               applications, but you may not reproduce
'               or publish this code on any web site,
'               online service, or distribute as source
'               on any media without express permission.
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

Private Const MAX_PATH                   As Long = 260
Private Const ERROR_SUCCESS              As Long = 0

'Treat entire URL param as one URL segment
Private Const URL_ESCAPE_SEGMENT_ONLY    As Long = &H2000
Private Const URL_ESCAPE_PERCENT         As Long = &H1000
Private Const URL_UNESCAPE_INPLACE       As Long = &H100000

'escape #'s in paths
Private Const URL_INTERNAL_PATH          As Long = &H800000
Private Const URL_DONT_ESCAPE_EXTRA_INFO As Long = &H2000000
Private Const URL_ESCAPE_SPACES_ONLY     As Long = &H4000000
Private Const URL_DONT_SIMPLIFY          As Long = &H8000000

'Converts unsafe characters,
'such as spaces, into their
'corresponding escape sequences.
Private Declare Function UrlEscape Lib "shlwapi" _
   Alias "UrlEscapeA" _
  (ByVal pszURL As String, _
   ByVal pszEscaped As String, _
   pcchEscaped As Long, _
   ByVal dwFlags As Long) As Long

'Converts escape sequences back into
'ordinary characters.
Private Declare Function UrlUnescape Lib "shlwapi" _
   Alias "UrlUnescapeA" _
  (ByVal pszURL As String, _
   ByVal pszUnescaped As String, _
   pcchUnescaped As Long, _
   ByVal dwFlags As Long) As Long


'
'
'Private Sub Command1_Click()
'
'   Dim sUrl As String
'   Dim buff As String
'
'  'use the original string in Text1 for
'  'demo, and show encoded results in Text2
'   sUrl = Text1.Text
'   buff = EncodeUrl(sUrl)
'
'   Text2.Text = buff
'
'
'End Sub
'
'
'Private Sub Command2_Click()
'
'   Dim sUrl As String
'   Dim buff As String
'
'  'use the encoded string in text2 for
'  'demo, and show decoded results in Text3
'   sUrl = Text2.Text
'   buff = DecodeUrl(sUrl)
'
'   Text3.Text = buff
'
'End Sub


Private Function EncodeUrl(ByVal sUrl As String) As String

   Dim buff As String
   Dim dwSize As Long
   Dim dwFlags As Long
   
   If Len(sUrl) > 0 Then
      
      buff = Space$(MAX_PATH)
      dwSize = Len(buff)
      dwFlags = URL_DONT_SIMPLIFY
      
      If UrlEscape(sUrl, _
                   buff, _
                   dwSize, _
                   dwFlags) = ERROR_SUCCESS Then
                   
         EncodeUrl = Left$(buff, dwSize)
      
      End If  'UrlEscape
   End If  'Len(sUrl)

End Function


Private Function DecodeUrl(ByVal sUrl As String) As String

   Dim buff As String
   Dim dwSize As Long
   Dim dwFlags As Long
   
   If Len(sUrl) > 0 Then
      
      buff = Space$(MAX_PATH)
      dwSize = Len(buff)
      dwFlags = URL_DONT_SIMPLIFY
      
      If UrlUnescape(sUrl, _
                   buff, _
                   dwSize, _
                   dwFlags) = ERROR_SUCCESS Then
                   
         DecodeUrl = Left$(buff, dwSize)
      
      End If  'UrlUnescape
   End If  'Len(sUrl)

End Function


Public Function Encode(ByVal eString As String) As String

Dim Key As String
Key = encodeKey & encodeKey2 & encodeKey3 & encodeKey4 & encodeKey5


Dim Res As String
Dim Key1 As String
Dim m As String
Dim temp As String
temp = eString
Key1 = binmd5(Key)
While Len(temp)
    If Len(temp) > 16 Then
        m = Left(temp, 16)
        temp = Right(temp, Len(temp) - 16)
    Else
        m = temp
        temp = ""
    End If
    Res = Res & ByteXor(m, Key1, Len(m))
    Key1 = binmd5(Key & Key1 & m)
Wend
Encode = Res
End Function

Public Function Decode(ByVal eString As String) As String

Dim Key As String
Key = encodeKey & encodeKey2 & encodeKey3 & encodeKey4 & encodeKey5

Dim Res As String
Dim Key1 As String
Dim m As String
Dim temp As String
temp = eString
Key1 = binmd5(Key)
While Len(temp)
    If Len(temp) > 16 Then
        m = Left(temp, 16)
        temp = Right(temp, Len(temp) - 16)
    Else
        m = temp
        temp = ""
    End If
    m = ByteXor(m, Key1, Len(m))
    Res = Res & m
    Key1 = binmd5(Key & Key1 & m)
Wend
Decode = Res
End Function

Private Function binmd5(ByVal Val As String) As String
binmd5 = Pack(MD5_string(Val))
End Function

Private Function Pack(ByVal Value As String) As String
Dim Val As String
Dim Int1 As Integer
Dim Int2 As Integer
Dim temp As String
Val = Value
While Len(Val)
    Int1 = GetHexVal(Left(Val, 1))
    Val = Right(Val, Len(Val) - 1)
    Int2 = GetHexVal(Left(Val, 1))
    Val = Right(Val, Len(Val) - 1)
    temp = temp & Chr((Int1 * 16) + Int2)
Wend
Pack = temp
End Function

Public Function GetHexVal(ByVal Value As String) As Integer
If IsNumeric(Value) Then
    GetHexVal = Value
Else
    GetHexVal = Asc(UCase(Value)) - 55
End If
End Function

Public Function ByteXor(ByVal A As String, ByVal b As String, ByVal length As String) As String
Dim c As String
Dim x As Integer
For x = 0 To length - 1
    c = c & Chr((Asc(A) Or Asc(b)) - (Asc(A) And Asc(b)))
    A = Right(A, Len(A) - 1)
    b = Right(b, Len(b) - 1)
Next
ByteXor = c
End Function


Public Function MD5_string(ByVal strMessage As String) As String
' Returns 32-char hex string representation of message digest
' Input as a string (max length 2^29-1 bytes)
    Dim abMessage() As Byte
    Dim mLen As Long
    ' Cope with the empty string
    If Len(strMessage) > 0 Then
        abMessage = StrConv(strMessage, vbFromUnicode)
        ' Compute length of message in bytes
        mLen = UBound(abMessage) - LBound(abMessage) + 1
    End If
    MD5_string = MD5_bytes(abMessage, mLen)
End Function

Public Function MD5_bytes(abMessage() As Byte, mLen As Long) As String
' Returns 32-char hex string representation of message digest
' Input as an array of bytes of length mLen bytes

    Dim nBlks As Long
    Dim nBits As Long
    Dim block(MD5_BLK_LEN - 1) As Byte
    Dim state(3) As Long
    Dim wb(3) As Byte
    Dim sHex As String
    Dim Index As Long
    Dim partLen As Long
    Dim i As Long
    Dim j As Long
    
    ' Catch length too big for VB arithmetic (268 million!)
    If mLen >= &HFFFFFFF Then Error 6     ' overflow
    
    ' Initialise
    ' Number of complete 512-bit/64-byte blocks to process
    nBlks = mLen \ MD5_BLK_LEN
    
    ' Load magic initialization constants
    state(0) = &H67452301
    state(1) = &HEFCDAB89
    state(2) = &H98BADCFE
    state(3) = &H10325476
    
    ' Main loop for each complete input block of 64 bytes
    Index = 0
    For i = 0 To nBlks - 1
        Call md5_transform(state, abMessage, Index)
        Index = Index + MD5_BLK_LEN
    Next
    
    ' Construct final block(s) with padding
    partLen = mLen Mod MD5_BLK_LEN
    Index = nBlks * MD5_BLK_LEN
    For i = 0 To partLen - 1
        block(i) = abMessage(Index + i)
    Next
    block(partLen) = &H80
    ' Make sure padding (and bit-length) set to zero
    For i = partLen + 1 To MD5_BLK_LEN - 1
        block(i) = 0
    Next
    ' Two cases: partLen is < or >= 56
    If partLen >= MD5_BLK_LEN - 8 Then
        ' Need two blocks
        Call md5_transform(state, block, 0)
        For i = 0 To MD5_BLK_LEN - 1
            block(i) = 0
        Next
    End If
    ' Append number of bits in little-endian order
    nBits = mLen * 8
    block(MD5_BLK_LEN - 8) = nBits And &HFF
    block(MD5_BLK_LEN - 7) = nBits \ &H100 And &HFF
    block(MD5_BLK_LEN - 6) = nBits \ &H10000 And &HFF
    block(MD5_BLK_LEN - 5) = nBits \ &H1000000 And &HFF
    ' (NB we don't try to cope with number greater than 2^31)
    
    ' Final padded block with bit length
    Call md5_transform(state, block, 0)
    
    ' Decode 4 x 32-bit words into 16 bytes with LSB first each time
    ' and return result as a hex string
    MD5_bytes = ""
    For i = 0 To 3
        Call uwSplit(state(i), wb(3), wb(2), wb(1), wb(0))
        For j = 0 To 3
            If wb(j) < 16 Then
                sHex = "0" & Hex(wb(j))
            Else
                sHex = Hex(wb(j))
            End If
            MD5_bytes = MD5_bytes & sHex
        Next
    Next
    
End Function

' INTERNAL FUNCTIONS...

Private Sub md5_transform(state() As Long, buf() As Byte, ByVal Index As Long)
' Updates 4 x 32-bit values in state
' Input: the next 64 bytes in buf starting at offset index
' Assumes at least 64 bytes are present after offset index
    Dim A As Long
    Dim b As Long
    Dim c As Long
    Dim d As Long
    Dim j As Integer
    Dim x(15) As Long
    
    A = state(0)
    b = state(1)
    c = state(2)
    d = state(3)
    
    ' Decode the next 64 bytes into 16 words with LSB first
    For j = 0 To 15
        x(j) = uwJoin(buf(Index + 3), buf(Index + 2), buf(Index + 1), buf(Index))
        Index = Index + 4
    Next
    
    ' Round 1
    A = FF(A, b, c, d, x(0), S11, &HD76AA478)   ' 1
    d = FF(d, A, b, c, x(1), S12, &HE8C7B756)   ' 2
    c = FF(c, d, A, b, x(2), S13, &H242070DB)   ' 3
    b = FF(b, c, d, A, x(3), S14, &HC1BDCEEE)   ' 4
    A = FF(A, b, c, d, x(4), S11, &HF57C0FAF)   ' 5
    d = FF(d, A, b, c, x(5), S12, &H4787C62A)   ' 6
    c = FF(c, d, A, b, x(6), S13, &HA8304613)   ' 7
    b = FF(b, c, d, A, x(7), S14, &HFD469501)   ' 8
    A = FF(A, b, c, d, x(8), S11, &H698098D8)   ' 9
    d = FF(d, A, b, c, x(9), S12, &H8B44F7AF)   ' 10
    c = FF(c, d, A, b, x(10), S13, &HFFFF5BB1)  ' 11
    b = FF(b, c, d, A, x(11), S14, &H895CD7BE)  ' 12
    A = FF(A, b, c, d, x(12), S11, &H6B901122)  ' 13
    d = FF(d, A, b, c, x(13), S12, &HFD987193)  ' 14
    c = FF(c, d, A, b, x(14), S13, &HA679438E)  ' 15
    b = FF(b, c, d, A, x(15), S14, &H49B40821)  ' 16
    
    ' Round 2
    A = GG(A, b, c, d, x(1), S21, &HF61E2562)   ' 17
    d = GG(d, A, b, c, x(6), S22, &HC040B340)   ' 18
    c = GG(c, d, A, b, x(11), S23, &H265E5A51)  ' 19
    b = GG(b, c, d, A, x(0), S24, &HE9B6C7AA)   ' 20
    A = GG(A, b, c, d, x(5), S21, &HD62F105D)   ' 21
    d = GG(d, A, b, c, x(10), S22, &H2441453)   ' 22
    c = GG(c, d, A, b, x(15), S23, &HD8A1E681)  ' 23
    b = GG(b, c, d, A, x(4), S24, &HE7D3FBC8)   ' 24
    A = GG(A, b, c, d, x(9), S21, &H21E1CDE6)   ' 25
    d = GG(d, A, b, c, x(14), S22, &HC33707D6)  ' 26
    c = GG(c, d, A, b, x(3), S23, &HF4D50D87)   ' 27
    b = GG(b, c, d, A, x(8), S24, &H455A14ED)   ' 28
    A = GG(A, b, c, d, x(13), S21, &HA9E3E905)  ' 29
    d = GG(d, A, b, c, x(2), S22, &HFCEFA3F8)   ' 30
    c = GG(c, d, A, b, x(7), S23, &H676F02D9)   ' 31
    b = GG(b, c, d, A, x(12), S24, &H8D2A4C8A)  ' 32
    
    ' Round 3
    A = HH(A, b, c, d, x(5), S31, &HFFFA3942)   ' 33
    d = HH(d, A, b, c, x(8), S32, &H8771F681)   ' 34
    c = HH(c, d, A, b, x(11), S33, &H6D9D6122)  ' 35
    b = HH(b, c, d, A, x(14), S34, &HFDE5380C)  ' 36
    A = HH(A, b, c, d, x(1), S31, &HA4BEEA44)   ' 37
    d = HH(d, A, b, c, x(4), S32, &H4BDECFA9)   ' 38
    c = HH(c, d, A, b, x(7), S33, &HF6BB4B60)   ' 39
    b = HH(b, c, d, A, x(10), S34, &HBEBFBC70)  ' 40
    A = HH(A, b, c, d, x(13), S31, &H289B7EC6)  ' 41
    d = HH(d, A, b, c, x(0), S32, &HEAA127FA)   ' 42
    c = HH(c, d, A, b, x(3), S33, &HD4EF3085)   ' 43
    b = HH(b, c, d, A, x(6), S34, &H4881D05)    ' 44
    A = HH(A, b, c, d, x(9), S31, &HD9D4D039)   ' 45
    d = HH(d, A, b, c, x(12), S32, &HE6DB99E5)  ' 46
    c = HH(c, d, A, b, x(15), S33, &H1FA27CF8)  ' 47
    b = HH(b, c, d, A, x(2), S34, &HC4AC5665)   ' 48
    
    ' Round 4
    A = II(A, b, c, d, x(0), S41, &HF4292244)   ' 49
    d = II(d, A, b, c, x(7), S42, &H432AFF97)   ' 50
    c = II(c, d, A, b, x(14), S43, &HAB9423A7)  ' 51
    b = II(b, c, d, A, x(5), S44, &HFC93A039)   ' 52
    A = II(A, b, c, d, x(12), S41, &H655B59C3)  ' 53
    d = II(d, A, b, c, x(3), S42, &H8F0CCC92)   ' 54
    c = II(c, d, A, b, x(10), S43, &HFFEFF47D)  ' 55
    b = II(b, c, d, A, x(1), S44, &H85845DD1)   ' 56
    A = II(A, b, c, d, x(8), S41, &H6FA87E4F)   ' 57
    d = II(d, A, b, c, x(15), S42, &HFE2CE6E0)  ' 58
    c = II(c, d, A, b, x(6), S43, &HA3014314)   ' 59
    b = II(b, c, d, A, x(13), S44, &H4E0811A1)  ' 60
    A = II(A, b, c, d, x(4), S41, &HF7537E82)   ' 61
    d = II(d, A, b, c, x(11), S42, &HBD3AF235)  ' 62
    c = II(c, d, A, b, x(2), S43, &H2AD7D2BB)   ' 63
    b = II(b, c, d, A, x(9), S44, &HEB86D391)   ' 64
    
    state(0) = uwAdd(state(0), A)
    state(1) = uwAdd(state(1), b)
    state(2) = uwAdd(state(2), c)
    state(3) = uwAdd(state(3), d)

End Sub

' FF, GG, HH, and II transformations for rounds 1, 2, 3, and 4

Private Function AddRotAdd(f As Long, A As Long, b As Long, x As Long, s As Integer, ac As Long) As Long
' Common routine for FF, GG, HH and II
' #define AddRotAdd(f, a, b, c, d, x, s, ac) { \
'  (a) += f + (x) + (UINT4)(ac); \
'  (a) = ROTATE_LEFT ((a), (s)); \
'  (a) += (b); \
'  }
    Dim temp As Long
    temp = uwAdd(A, f)
    temp = uwAdd(temp, x)
    temp = uwAdd(temp, ac)
    temp = uwRol(temp, s)
    AddRotAdd = uwAdd(temp, b)
End Function

Private Function FF(A As Long, b As Long, c As Long, d As Long, x As Long, s As Integer, ac As Long) As Long
' Returns new value of a
' #define F(x, y, z) (((x) & (y)) | ((~x) & (z)))
' #define FF(a, b, c, d, x, s, ac) { \
'  (a) += F ((b), (c), (d)) + (x) + (UINT4)(ac); \
'  (a) = ROTATE_LEFT ((a), (s)); \
'  (a) += (b); \
'  }
    Dim t As Long
    Dim t2 As Long
    ' F ((b), (c), (d)) = (((b) & (c)) | ((~b) & (d)))
    t = b And c
    t2 = (Not b) And d
    t = t Or t2
    FF = AddRotAdd(t, A, b, x, s, ac)
End Function

Private Function GG(A As Long, b As Long, c As Long, d As Long, x As Long, s As Integer, ac As Long) As Long
' #define G(b, c, d) (((b) & (d)) | ((c) & (~d)))
    Dim t As Long
    Dim t2 As Long
    t = b And d
    t2 = c And (Not d)
    t = t Or t2
    GG = AddRotAdd(t, A, b, x, s, ac)
End Function

Private Function HH(A As Long, b As Long, c As Long, d As Long, x As Long, s As Integer, ac As Long) As Long
' #define H(b, c, d) ((b) ^ (c) ^ (d))
    Dim t As Long
    t = b Xor c Xor d
    HH = AddRotAdd(t, A, b, x, s, ac)
End Function

Private Function II(A As Long, b As Long, c As Long, d As Long, x As Long, s As Integer, ac As Long) As Long
' #define I(b, c, d) ((c) ^ ((b) | (~d)))
    Dim t As Long
    t = b Or (Not d)
    t = c Xor t
    II = AddRotAdd(t, A, b, x, s, ac)
End Function

' Unsigned 32-bit word functions suitable for VB/VBA

Private Function uwRol(w As Long, s As Integer) As Long
' Return 32-bit word w rotated left by s bits
' avoiding problem with VB sign bit
    Dim i As Integer
    Dim t As Long
    
    uwRol = w
    For i = 1 To s
        t = uwRol And &H3FFFFFFF
        t = t * 2
        If (uwRol And &H40000000) <> 0 Then
            t = t Or &H80000000
        End If
        If (uwRol And &H80000000) <> 0 Then
            t = t Or &H1
        End If
        uwRol = t
    Next
End Function

Private Function uwJoin(A As Byte, b As Byte, c As Byte, d As Byte) As Long
' Join 4 x 8-bit bytes into one 32-bit word a.b.c.d
    uwJoin = ((A And &H7F) * &H1000000) Or (b * &H10000) Or (CLng(c) * &H100) Or d
    If A And &H80 Then
        uwJoin = uwJoin Or &H80000000
    End If
End Function

Private Sub uwSplit(ByVal w As Long, A As Byte, b As Byte, c As Byte, d As Byte)
' Split 32-bit word w into 4 x 8-bit bytes
    A = CByte(((w And &HFF000000) \ &H1000000) And &HFF)
    b = CByte(((w And &HFF0000) \ &H10000) And &HFF)
    c = CByte(((w And &HFF00) \ &H100) And &HFF)
    d = CByte((w And &HFF) And &HFF)
End Sub

Private Function uwAdd(wordA As Long, wordB As Long) As Long
' Adds words A and B avoiding overflow
    Dim myUnsigned As Double
    
    myUnsigned = LongToUnsigned(wordA) + LongToUnsigned(wordB)
    ' Cope with overflow
    If myUnsigned > OFFSET_4 Then
        myUnsigned = myUnsigned - OFFSET_4
    End If
    uwAdd = UnsignedToLong(myUnsigned)
    
End Function

'****************************************************
' These two functions from Microsoft Article Q189323
' "HOWTO: convert between Signed and Unsigned Numbers"

Private Function UnsignedToLong(Value As Double) As Long
    If Value < 0 Or Value >= OFFSET_4 Then Error 6 ' Overflow
    If Value <= MAXINT_4 Then
        UnsignedToLong = Value
    Else
        UnsignedToLong = Value - OFFSET_4
    End If
End Function

Private Function LongToUnsigned(Value As Long) As Double
    If Value < 0 Then
        LongToUnsigned = Value + OFFSET_4
    Else
        LongToUnsigned = Value
    End If
End Function

' End of Microsoft-article functions
'****************************************************

