VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "Base64Class"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

Private Const Equals As Byte = 61    'Asc("=")

Private Const Mask1 As Byte = 3      '00000011
Private Const Mask2 As Byte = 15     '00001111
Private Const Mask3 As Byte = 63     '00111111
Private Const Mask4 As Byte = 192    '11000000
Private Const Mask5 As Byte = 240    '11110000
Private Const Mask6 As Byte = 252    '11111100

Private Const Shift2 As Byte = 4
Private Const Shift4 As Byte = 16
Private Const Shift6 As Byte = 64

Private Base64Lookup() As Byte
Private Base64Reverse() As Byte

Public Function EncodeString(Text As String) As String

   Dim Data() As Byte
   
   Data = StrConv(Text, vbFromUnicode)
   EncodeString = EncodeByteArray(Data)

End Function

Public Function EncodeByteArray(Data() As Byte) As String

   Dim EncodedData() As Byte

   Dim DataLength As Long
   Dim EncodedLength As Long

   Dim Data0 As Long
   Dim Data1 As Long
   Dim Data2 As Long

   Dim l As Long
   Dim m As Long

   Dim Index As Long

   Dim CharCount As Long

   DataLength = UBound(Data) + 1

   EncodedLength = (DataLength \ 3) * 4
   If DataLength Mod 3 > 0 Then EncodedLength = EncodedLength + 4
   EncodedLength = EncodedLength + ((EncodedLength \ 76) * 2)
   If EncodedLength Mod 78 = 0 Then EncodedLength = EncodedLength - 2
   ReDim EncodedData(EncodedLength - 1)

   m = (DataLength) Mod 3

   For l = 0 To UBound(Data) - m Step 3
      Data0 = Data(l)
      Data1 = Data(l + 1)
      Data2 = Data(l + 2)
      EncodedData(Index) = Base64Lookup(Data0 \ Shift2)
      EncodedData(Index + 1) = Base64Lookup(((Data0 And Mask1) * Shift4) Or (Data1 \ Shift4))
      EncodedData(Index + 2) = Base64Lookup(((Data1 And Mask2) * Shift2) Or (Data2 \ Shift6))
      EncodedData(Index + 3) = Base64Lookup(Data2 And Mask3)
      Index = Index + 4
      CharCount = CharCount + 4

      If CharCount = 76 And Index < EncodedLength Then
         EncodedData(Index) = 13
         EncodedData(Index + 1) = 10
         CharCount = 0
         Index = Index + 2
      End If
   Next

   If m = 1 Then
      Data0 = Data(l)
      EncodedData(Index) = Base64Lookup((Data0 \ Shift2))
      EncodedData(Index + 1) = Base64Lookup((Data0 And Mask1) * Shift4)
      EncodedData(Index + 2) = Equals
      EncodedData(Index + 3) = Equals
      Index = Index + 4
   ElseIf m = 2 Then
      Data0 = Data(l)
      Data1 = Data(l + 1)
      EncodedData(Index) = Base64Lookup((Data0 \ Shift2))
      EncodedData(Index + 1) = Base64Lookup(((Data0 And Mask1) * Shift4) Or (Data1 \ Shift4))
      EncodedData(Index + 2) = Base64Lookup((Data1 And Mask2) * Shift2)
      EncodedData(Index + 3) = Equals
      Index = Index + 4
   End If

   EncodeByteArray = StrConv(EncodedData, vbUnicode)

End Function

Public Function DecodeToString(EncodedText As String) As String

   Dim Data() As Byte
   
   Data = DecodeToByteArray(EncodedText)
   DecodeToString = StrConv(Data, vbUnicode)

End Function

Public Function DecodeToByteArray(EncodedText As String) As Byte()

   Dim Data() As Byte
   Dim EncodedData() As Byte

   Dim DataLength As Long
   Dim EncodedLength As Long

   Dim EncodedData0 As Long
   Dim EncodedData1 As Long
   Dim EncodedData2 As Long
   Dim EncodedData3 As Long

   Dim l As Long
   Dim m As Long

   Dim Index As Long

   Dim CharCount As Long

   EncodedData = StrConv(Replace$(Replace$(EncodedText, vbCrLf, ""), "=", ""), vbFromUnicode)

   EncodedLength = UBound(EncodedData) + 1
   DataLength = (EncodedLength \ 4) * 3

   m = EncodedLength Mod 4
   If m = 2 Then
      DataLength = DataLength + 1
   ElseIf m = 3 Then
      DataLength = DataLength + 2
   End If

   ReDim Data(DataLength - 1)

   For l = 0 To UBound(EncodedData) - m Step 4
      EncodedData0 = Base64Reverse(EncodedData(l))
      EncodedData1 = Base64Reverse(EncodedData(l + 1))
      EncodedData2 = Base64Reverse(EncodedData(l + 2))
      EncodedData3 = Base64Reverse(EncodedData(l + 3))
      Data(Index) = (EncodedData0 * Shift2) Or (EncodedData1 \ Shift4)
      Data(Index + 1) = ((EncodedData1 And Mask2) * Shift4) Or (EncodedData2 \ Shift2)
      Data(Index + 2) = ((EncodedData2 And Mask1) * Shift6) Or EncodedData3
      Index = Index + 3
   Next

   Select Case ((UBound(EncodedData) + 1) Mod 4)
   Case 2
      EncodedData0 = Base64Reverse(EncodedData(l))
      EncodedData1 = Base64Reverse(EncodedData(l + 1))
      Data(Index) = (EncodedData0 * Shift2) Or (EncodedData1 \ Shift4)
   Case 3
      EncodedData0 = Base64Reverse(EncodedData(l))
      EncodedData1 = Base64Reverse(EncodedData(l + 1))
      EncodedData2 = Base64Reverse(EncodedData(l + 2))
      Data(Index) = (EncodedData0 * Shift2) Or (EncodedData1 \ Shift4)
      Data(Index + 1) = ((EncodedData1 And Mask2) * Shift4) Or (EncodedData2 \ Shift2)
   End Select

   DecodeToByteArray = Data

End Function

Private Sub Class_Initialize()

   Dim l As Long
   
   ReDim Base64Reverse(255)
   
   Base64Lookup = StrConv("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", vbFromUnicode)
   
   For l = 0 To 63
      Base64Reverse(Base64Lookup(l)) = l
   Next
   
End Sub
