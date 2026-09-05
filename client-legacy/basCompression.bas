Attribute VB_Name = "basCompression"
Option Explicit

Private Declare Function LoadLibrary Lib "kernel32" Alias "LoadLibraryA" (ByVal lpLibFileName As String) As Long
Private Declare Function ZSTD_compress Lib "zstd" (dst As Any, ByVal maxDstSize As Long, Src As Any, ByVal srcSize As Long, ByVal CompressionLevel As Long) As Long
Private Declare Function ZSTD_decompress Lib "zstd" (dst As Any, ByVal maxDstSize As Long, Src As Any, ByVal srcSize As Long) As Long
Public Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (Destination As Any, Source As Any, ByVal Length As Long)

Public Sub ZstdInit()
    On Error Resume Next
    Call LoadLibrary(App.Path & "\zstd.dll")
    Call LoadLibrary(App.Path & "\libs\runtime\zstd.dll")
    On Error GoTo 0
End Sub

Public Function ZstdCompress(baSrc() As Byte, baDst() As Byte, Optional ByVal CompressionLevel As Long = 5) As Boolean
    Dim lTemp As Long
    Dim lSize As Long

    lSize = 2 * (UBound(baSrc) + 1) + 4
    ReDim baDst(0 To lSize) As Byte
    lSize = ZSTD_compress(baDst(4), UBound(baDst) - 3, baSrc(0), UBound(baSrc) + 1, CompressionLevel)
    If lSize > 0 Then
        lTemp = UBound(baSrc) + 1
        Call CopyMemory(baDst(0), lTemp, 4)
        ReDim Preserve baDst(0 To lSize + 3)
        ZstdCompress = True
    End If
End Function

Public Function ZstdDecompress(baSrc() As Byte, baDst() As Byte) As Boolean
    Dim lSize As Long

    Call CopyMemory(lSize, baSrc(0), 4)
    If lSize > 0 Then
        ReDim baDst(0 To lSize - 1) As Byte
        lSize = ZSTD_decompress(baDst(0), lSize, baSrc(4), UBound(baSrc) - 3)
        ZstdDecompress = lSize > 0
    End If
End Function

