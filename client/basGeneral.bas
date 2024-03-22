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

Public cPath(1 To 5) As String
Public cPath_tmp(1 To 4) As String

Public EditorFile_Short As String
Public EditorFile_Long As String
Public EditorRunFile As String
        
Public Declare Function GetForegroundWindow Lib "user32" () As Long
Public Declare Function GetWindowText Lib "user32" Alias "GetWindowTextA" (ByVal hWnd As Long, ByVal lpString As String, ByVal cch As Long) As Long
       
Public Declare Function StrFormatByteSize Lib "shlwapi" Alias "StrFormatByteSizeA" (ByVal dw As Long, ByVal pszBuf As String, ByRef cchBuf As Long) As String

Public Function VersionStr() As String
    If App.Minor > 0 Then
        VersionStr = App.Major & "." & App.Minor & "." & App.Revision
    Else
        VersionStr = App.Comments
    End If
End Function

Public Function GetFile(ByVal fn As String) As String
    On Error GoTo zxc
    
    Dim aFF As Long, tmpS As String, fullS As String
    aFF = FreeFile
    Open fn For Input As #aFF
        Do Until EOF(aFF)
            Line Input #aFF, tmpS
            fullS = fullS & tmpS & vbCrLf
        Loop
    Close #aFF

    GetFile = fullS

zxc:
    Err.Raise Err.Number, Err.Source, Err.Description, Err.HelpFile, Err.HelpContext
    Close #aFF
End Function


Function GetFileClean(ByVal filename As String) As String
    Dim Handle As Integer

    filename = SafePath(filename)
    
    ' ensure that the file exists
    If Len(Dir$(filename)) = 0 Then
        Err.Raise 53   ' File not found
    End If
    
    ' open in binary mode
    Handle = FreeFile
    Open filename$ For Binary As #Handle
    ' read the string and close the file
    GetFileClean = Space$(LOF(Handle))
    Get #Handle, , GetFileClean
    Close #Handle
End Function



Public Sub OpenURL(sUrl As String)
    On Error Resume Next
    Shell Environ("windir") & "\explorer.exe " & Chr(34) & sUrl & Chr(34), vbNormalFocus
    DoEvents
    'Unload frmMain
End Sub

Public Function GetFunctionPart(ByVal tmpS As String) As String
    If InStr(tmpS, "=") > 0 Then tmpS = Trim(Mid(tmpS, InStr(tmpS, "=") + 1, Len(tmpS)))
    If InStr(tmpS, "(") > 0 Then tmpS = Trim(Mid(tmpS, 1, InStr(tmpS, "(") - 1))
    GetFunctionPart = tmpS
End Function

Public Function CountCharInString(s As String, ByVal sToCount As String) As Integer
    sToCount = Trim(LCase(sToCount))
    CountCharInString = 0
    Dim n As Long
    For n = 1 To Len(s)
        If LCase(Mid(s, n, Len(sToCount))) = sToCount Then
            CountCharInString = CountCharInString + 1
        End If
    Next n
End Function


Public Function FlipCommas(ByVal s As String, ChangeSpacesToChars As Boolean)
    Dim n As Integer, isIn As Boolean
    isIn = False
    
    's = Replace(s, Chr(34) & " ,", Chr(34) & ", ")
    's = Replace(s, Chr(34) & ",", Chr(34) & ", ")
    
    
    If ChangeSpacesToChars = False Then
        FlipCommas = Trim(Replace(s, "-(c)-", ","))
            
            If Mid(FlipCommas, 1, 1) = Chr(34) Then
                FlipCommas = Mid(FlipCommas, 2, Len(FlipCommas)) & "mgkg"
                
                FlipCommas = Trim(Replace(FlipCommas, Chr(34) & " ," & "mgkg", ""))
                FlipCommas = Trim(Replace(FlipCommas, Chr(34) & "," & "mgkg", ""))
                FlipCommas = Trim(Replace(FlipCommas, "mgkg", ""))

            End If
            
        Exit Function
    End If
    
    For n = 1 To Len(s)
        If Mid(s, n, 1) = Chr(34) Then
            isIn = Not (isIn)
        End If
        
        If isIn = True Then
            If ChangeSpacesToChars = True Then
                FlipCommas = FlipCommas & Replace(Mid(s, n, 1), ",", "-(c)-")
            End If
        Else
            FlipCommas = FlipCommas & Mid(s, n, 1)
        End If
    Next n

End Function


Public Function i(ByVal s As String) As String
    i = Trim(LCase(s))
End Function

Public Function IU(s As String) As String
    IU = Trim(UCase(s))
End Function

Public Function FileExists(s As String) As Boolean
    On Error GoTo zxc
    Dim n As Long
    n = FileLen(s)
    FileExists = True
    Exit Function
zxc:
    FileExists = False
End Function

Public Function FileTitleOnly(ByVal s As String) As String
    Dim n As Integer
    
    s = Replace(s, "\", "/")
    
    For n = Len(s) To 1 Step -1
        If Mid(s, n, 1) = "/" Then
            GoTo zz
        Else
            FileTitleOnly = Mid(s, n, 1) & FileTitleOnly
        End If
    Next n
zz:
    FileTitleOnly = Trim(FileTitleOnly)
End Function

Public Function WriteFile(fn As String, s As String) As Boolean
    On Error GoTo zxc
    Dim FF As Long
    FF = FreeFile
    Open fn For Output As #FF
        Print #FF, s
        
    Close #FF
    WriteFile = True
    Exit Function
zxc:
    Close #FF
    WriteFile = False
End Function

Public Sub RegSave(sCat As String, sVal As String)
    SaveSetting App.Title, "Settings", i(sCat), sVal
End Sub

Public Function RegLoad(sCat As String, sDefault As String) As String
    RegLoad = Trim(GetSetting(App.Title, "Settings", i(sCat), sDefault))
End Function

Public Function ReverseString(s As String) As String
    Dim nLoop As Long
    For nLoop = Len(s) To 1 Step -1
        ReverseString = ReverseString & Mid(s, nLoop, 1)
    Next nLoop
End Function

Public Function ExistsInList(ByVal s As String, l As ListBox) As Boolean
    'checks if the specified item exists in a listbox
    Dim n As Long
    If l.ListCount = 0 Then
        ExistsInList = False
        Exit Function
    End If
    s = i(s)
    For n = 0 To l.ListCount - 1
        If s = i(l.List(n)) Then
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
    Dim Buffer As String
    Dim Result As String
    Buffer = Space$(255)
    Result = StrFormatByteSize(Amount, Buffer, _
    Len(Buffer))


    If InStr(Result, vbNullChar) > 1 Then


        FormatKB = Left$(Result, InStr(Result, _
            vbNullChar) - 1)
    End If
End Function

'this is like split but often easier
Public Function GetPart(ByVal s As String, ByVal part As Integer, ByVal theDivider As String) As String
    Dim sArray() As String
    part = part - 1
    sArray = Split(s, theDivider)
    GetPart = sArray(part)
End Function

Public Function KillBadDirChars(s As String) As String
    KillBadDirChars = s
    
    KillBadDirChars = Replace(KillBadDirChars, "|", "")
    KillBadDirChars = Replace(KillBadDirChars, "*", "")
    KillBadDirChars = Replace(KillBadDirChars, "/", "")
    KillBadDirChars = Replace(KillBadDirChars, "\", "")
    KillBadDirChars = Replace(KillBadDirChars, Chr(34), "")
    KillBadDirChars = Replace(KillBadDirChars, ":", "")
    KillBadDirChars = Replace(KillBadDirChars, "<", "")
    KillBadDirChars = Replace(KillBadDirChars, ">", "")
End Function

Public Function InvalidChars(ByVal s As String) As Boolean
    s = Trim(s)
    
    InvalidChars = False
    
    'If InStr(s, "\") > 0 Then InvalidChars = True
    'If InStr(s, "/") > 0 Then InvalidChars = True
    If InStr(s, " ") > 0 Then InvalidChars = True
    
    If InStr(s, "|") > 0 Then InvalidChars = True
    If InStr(s, "*") > 0 Then InvalidChars = True
    
    If InStr(s, Chr(34)) > 0 Then InvalidChars = True
    If InStr(s, ":") > 0 Then InvalidChars = True
    If InStr(s, "<") > 0 Then InvalidChars = True
    If InStr(s, ">") > 0 Then InvalidChars = True
    If InStr(s, ",") > 0 Then InvalidChars = True
End Function



Public Function DirExists(ByVal sDirName As String) As Boolean
    Dim s As String
    s = Trim(Replace(sDirName, "\", "/"))
    
    If Right(s, 1) <> "/" Then s = s & "/"
    
    If WriteFile(s & "testbqva.txt", "data here") = True Then
        Kill s & "testbqva.txt"
        DirExists = True
    Else
        DirExists = False
    End If
End Function


Public Function CountCharsInString(ByVal s As String, ByVal sFind As String) As Long
    Dim n As Long
    s = i(s)
    sFind = i(sFind)
    
    For n = 1 To Len(s)
        If Mid(s, n, Len(sFind)) = sFind Then
            CountCharsInString = CountCharsInString + 1
        End If
        
    Next n
End Function

Public Function DSOEncode(ByVal s As String) As String
    DSOEncode = s
End Function

Public Function DSODecode(ByVal s As String) As String
    DSODecode = s
End Function



