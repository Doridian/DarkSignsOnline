Attribute VB_Name = "basGeneral"
Option Explicit

Public StatusItems(1 To 100) As String
Public StatusColors(1 To 100) As Long

Public Const iPurple = &HC000C0
Public Const iPink = &H8080FF
Public Const iOrange = &H80FF&
Public Const iLightOrange = &H80C0FF
Public Const iBlue = &HE99A9C
Public Const iDarkBlue = &HCE5B35
Public Const iLightBlue = &HFFFF00
Public Const iGreen = &H3DCF44
Public Const iDarkGreen = &H8000&
Public Const iLightGreen = &H7EE084
Public Const iBrown = &H5E7386
Public Const iLightBrown = &H8B9DAD
Public Const iDarkBrown = &H42505B
Public Const iGold = &H6C9F2
Public Const iYellow = &HFFFF&
Public Const iLightYellow = &H80FFFF
Public Const iDarkYellow = &HC0C0&
Public Const iMaroon = &H293C83
Public Const iRed = &HFF&
Public Const iLightRed = &H8080FF
Public Const iDarkRed = &HC0&
Public Const iGrey = &H808080
Public Const iDarkGrey = &H404040
Public Const iLightGrey = &HE0E0E0

Public FlashCounter As Long
Public FlashFast As Boolean
Public FlashSlow As Boolean
Public Flash As Boolean

Public LoadingSpinner As Integer
Public Const LoadingSpinnerAnim = "/-\|"

Public cPath(1 To 4) As String
Public cPrompt(1 To 4) As String

Public EditorFile_Short As String
Public EditorFile_Long As String
Public EditorRunFile As String
        
Public Declare Function GetForegroundWindow Lib "user32" () As Long
Public Declare Function GetWindowText Lib "user32" Alias "GetWindowTextA" (ByVal hWnd As Long, ByVal lpString As String, ByVal cch As Long) As Long
       
Public Declare Function StrFormatByteSize Lib "shlwapi" Alias "StrFormatByteSizeA" (ByVal dw As Long, ByVal pszBuf As String, ByRef cchBuf As Long) As String

Public Function IsWhitespaceOrNewline(ByVal InputStr As String) As Boolean
    IsWhitespaceOrNewline = (InputStr = vbCr) Or (InputStr = vbLf) Or (InputStr = vbTab) Or (InputStr = " ")
End Function

Public Function TrimWithNewline(ByVal InputStr As String) As String
    If InputStr = "" Then
        TrimWithNewline = ""
        Exit Function
    End If

    Dim StartCut As Long, EndCut As Long
    StartCut = 1
    While IsWhitespaceOrNewline(Mid(InputStr, StartCut, 1))
        StartCut = StartCut + 1
        If StartCut > Len(InputStr) Then
            TrimWithNewline = ""
            Exit Function
        End If
    Wend
    EndCut = Len(InputStr)
    While IsWhitespaceOrNewline(Mid(InputStr, EndCut, 1))
        EndCut = EndCut - 1
        If EndCut < StartCut Then
            TrimWithNewline = ""
            Exit Function
        End If
    Wend

    Dim CutLen As Long
    CutLen = (EndCut - StartCut) + 1
    TrimWithNewline = Mid(InputStr, StartCut, CutLen)
End Function

Public Function VersionStr() As String
    If App.Minor > 0 Then
        VersionStr = App.Major & "." & App.Minor & "." & App.Revision
    Else
        VersionStr = App.Comments
    End If
End Function

Public Function FileLenUnsafe(ByVal filename As String) As Long
    GetAttr filename
    
    Dim Handle As Long
    Handle = FreeFile
    Open filename$ For Binary Access Read As #Handle
        FileLenUnsafe = LOF(Handle)
    Close #Handle
End Function

Public Function GetFileUnsafe(ByVal filename As String) As String
    GetAttr filename

    Dim Handle As Long
    Handle = FreeFile
    Open filename$ For Binary Access Read As #Handle
        GetFileUnsafe = Space$(LOF(Handle))
        Get #Handle, , GetFileUnsafe
    Close #Handle
End Function

Public Sub WriteFileUnsafe(ByVal filename As String, ByVal Contents As String)
    On Error Resume Next
    Kill filename$
    On Error GoTo 0

    Dim Handle As Long
    Handle = FreeFile
    Open filename$ For Binary Access Write As #Handle
        Put #Handle, , Contents
    Close #Handle
End Sub

Public Sub AppendFileUnsafe(ByVal filename As String, ByVal Contents As String)
    Dim Handle As Long
    Handle = FreeFile
    Open filename For Binary Access Write As #Handle
        Seek #Handle, LOF(Handle) + 1
        Put #Handle, , Contents
    Close #Handle
End Sub

Public Sub WriteFile(ByVal filename As String, ByVal Contents As String, Optional ByVal Prefix As String = "")
    WriteFileUnsafe SafePath(filename, Prefix), Contents
End Sub

Public Sub AppendFile(ByVal filename As String, ByVal Contents As String, Optional ByVal Prefix As String = "")
    AppendFileUnsafe SafePath(filename, Prefix), Contents
End Sub

Public Function FileLen(ByVal filename As String, Optional ByVal Prefix As String = "") As Long
    FileLen = FileLenUnsafe(SafePath(filename, Prefix))
End Function

Public Function GetFile(ByVal filename As String, Optional ByVal Prefix As String = "") As String
    GetFile = GetFileUnsafe(SafePath(filename, Prefix))
End Function

Public Function GetFileBinaryUnsafe(ByVal filename As String, Optional ByVal Prefix As String = "") As Byte()
    Dim Handle As Long
    Handle = FreeFile
    Open filename$ For Binary Access Read As #Handle
        ReDim GetFileBinaryUnsafe(0 To LOF(Handle) - 1)
        Get #Handle, , GetFileBinaryUnsafe
    Close #Handle
End Function

Public Function GetFileBinary(ByVal filename As String, Optional ByVal Prefix As String = "") As Byte()
    GetFileBinary = GetFileBinaryUnsafe(SafePath(filename, Prefix))
End Function

Public Function i(ByVal S As String) As String
    i = Trim(LCase(S))
End Function

Public Function IU(S As String) As String
    IU = Trim(UCase(S))
End Function

Public Function FileExists(S As String) As Boolean
    On Error GoTo zxc
    GetAttr SafePath(S)
    FileExists = True
    Exit Function
zxc:
    FileExists = False
End Function

Public Function FileTitleOnly(ByVal S As String) As String
    Dim n As Integer
    
    S = Replace(S, "\", "/")
    
    For n = Len(S) To 1 Step -1
        If Mid(S, n, 1) = "/" Then
            GoTo zz
        Else
            FileTitleOnly = Mid(S, n, 1) & FileTitleOnly
        End If
    Next n
zz:
    FileTitleOnly = Trim(FileTitleOnly)
End Function

Public Function ReverseString(S As String) As String
    Dim nLoop As Long
    For nLoop = Len(S) To 1 Step -1
        ReverseString = ReverseString & Mid(S, nLoop, 1)
    Next nLoop
End Function

Public Function ExistsInList(ByVal S As String, l As ListBox) As Boolean
    'checks if the specified item exists in a listbox
    Dim n As Long
    If l.ListCount = 0 Then
        ExistsInList = False
        Exit Function
    End If
    S = i(S)
    For n = 0 To l.ListCount - 1
        If S = i(l.List(n)) Then
            ExistsInList = True
            Exit Function
        End If
    Next n
    ExistsInList = False
End Function

Public Function FormatKB(ByVal Amount As Long) _
    As String
    'changes bytes to KB if the amount is high enough,
    'KB to MB, etc, etc
    Dim buffer As String
    Dim Result As String
    buffer = Space$(255)
    Result = StrFormatByteSize(Amount, buffer, _
    Len(buffer))


    If InStr(Result, vbNullChar) > 1 Then


        FormatKB = Left$(Result, InStr(Result, _
            vbNullChar) - 1)
    End If
End Function

Public Function DirExists(ByVal sDirName As String) As Boolean
    Dim Attrs As Long
    On Error GoTo NotADir
    Attrs = GetAttr(SafePath(sDirName))
    On Error GoTo 0
    
    If (Attrs And vbDirectory) = vbDirectory Then
        DirExists = True
        Exit Function
    End If

NotADir:
    DirExists = False
End Function

Public Function EnsureValidFont(ByVal AttemptFont As String) As String
    Dim NewFont As String
    EnsureValidFont = frmConsole.lblFontTest.FontName
    On Error GoTo NotValidFont
    frmConsole.lblFontTest.FontName = AttemptFont
    On Error GoTo 0

    EnsureValidFont = frmConsole.lblFontTest.FontName

NotValidFont:
End Function
