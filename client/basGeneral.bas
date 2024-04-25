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

Private Type RegSetting
    name As String
    Value As String
End Type
Private RegSettingsCache() As RegSetting

Public cPath(1 To 5) As String
Public cPath_tmp(1 To 4) As String

Public EditorFile_Short As String
Public EditorFile_Long As String
Public EditorRunFile As String
        
Public Declare Function GetForegroundWindow Lib "user32" () As Long
Public Declare Function GetWindowText Lib "user32" Alias "GetWindowTextA" (ByVal hWnd As Long, ByVal lpString As String, ByVal cch As Long) As Long
       
Public Declare Function StrFormatByteSize Lib "shlwapi" Alias "StrFormatByteSizeA" (ByVal dw As Long, ByVal pszBuf As String, ByRef cchBuf As Long) As String

Public Function GetFile(ByVal fn As String) As String
    
    'fn = Replace(fn, "/", "\")
    'fn = Replace(fn, "\\", "\")
    'fn = Replace(fn, "\\", "\")
    
    
    'get the contents of a file
    On Error GoTo zxc
    
    Dim aFF As Long, tmpS As String, fullS As String
    aFF = FreeFile
    Open fn For Input As #aFF
        Do Until EOF(aFF)
            Line Input #aFF, tmpS
            fullS = fullS & tmpS & vbCrLf
        Loop
    Close #aFF
    
    If Mid(fullS, Len(fullS) - 1, 2) = vbCrLf Then
        fullS = Mid(fullS, 1, Len(fullS) - 2)
    End If
    
    GetFile = fullS
    
zxc:
    Close #aFF
End Function


Function GetFileClean(ByVal filename As String) As String
    Dim Handle As Integer
    
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
    
    If Mid(GetFileClean, Len(GetFileClean) - 1, 2) = vbCrLf Then
        GetFileClean = Mid(GetFileClean, 1, Len(GetFileClean) - 2)
    End If
    
    
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

Public Function CountInstr(s As String, ByVal sToCount As String) As Integer
    sToCount = LCase(sToCount)
    CountInstr = 0
    Dim n As Long
    For n = 1 To Len(s)
        If LCase(Mid(s, n, Len(sToCount))) = sToCount Then
            CountInstr = CountInstr + 1
        End If
    Next n
End Function

Public Function MoveADirectory(sSource As String, sDest As String) As Boolean
        
    'home and system dirs cannot be moved
    If InStr(i(sSource) & "\", "\system\") > 0 Or InStr(i(sSource) & "\", "\home\") > 0 Then
        MoveADirectory = False
        Exit Function
    End If
    
    On Error GoTo zxc
    
    Name sSource As sDest
    
    MoveADirectory = True
    
    Exit Function
zxc:
    MoveADirectory = False
End Function

Public Function CopyAFile(sSource As String, sDest As String, consoleID As Integer) As Boolean
    On Error GoTo zxc
    
    
    If InStr(i(sDest), "\system\") > 0 Then
        SayError "Files in the main SYSTEM directory are protected.", consoleID
        Exit Function
    End If
    
    
    FileCopy sSource, sDest
    CopyAFile = True
    
    Exit Function
zxc:
    CopyAFile = False
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
    
    s = UnBracketize(s)
    
    's = Replace(s, vbCrLf, vbCr)
    's = Replace(s, vbLf, vbCr)
    's = Replace(s, vbCr, vbCrLf)
    
    'write to a file (don't append)
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

Public Function WriteClean(fn As String, s As String) As Boolean
    
    On Error GoTo zxc
    Dim FF As Long
    FF = FreeFile
    Open fn For Output As #FF
        Print #FF, s
        
    Close #FF
    WriteClean = True
    Exit Function
zxc:
    Close #FF
    WriteClean = False
End Function


Public Sub AppendFile(fn As String, s As String)
    'write to a file (append)
    On Error GoTo zxc
    Dim FF As Long
    FF = FreeFile
    Open fn For Append As #FF
        Print #FF, s
zxc:
    Close #FF
End Sub

Private Sub EnsureRegCacheIntact()
    On Error GoTo RedimRegCache
    Dim X As Long
    X = UBound(RegSettingsCache)
    On Error GoTo 0
    If X >= 0 Then
        Exit Sub
    End If
RedimRegCache:
    ReDim RegSettingsCache(0 To 0)
    RegSettingsCache(0).name = ""
    RegSettingsCache(0).Value = ""
End Sub

Private Function FindRegCacheSetting(ByVal sCat As String) As Long
    FindRegCacheSetting = 0

    EnsureRegCacheIntact
    If UBound(RegSettingsCache) <= 0 Then
        Exit Function
    End If

    Dim X As Long
    For X = 1 To UBound(RegSettingsCache)
        If RegSettingsCache(X).name = sCat Then
            FindRegCacheSetting = X
            Exit Function
        End If
    Next
End Function

Public Sub RegSave(ByVal sCat As String, ByVal sVal As String)
    EnsureRegCacheIntact

    Dim X As Long
    X = FindRegCacheSetting(sCat)
    If X <= 0 Then
        If UBound(RegSettingsCache) > 1024 Then
            Err.Raise vbObjectError + 9199, , "FATAL ERROR: Ran out of settings cache of size 1024 saving: " & sCat
        End If
        ReDim Preserve RegSettingsCache(0 To UBound(RegSettingsCache) + 1)
        X = UBound(RegSettingsCache)
    End If
    SaveSetting App.Title, "Settings", sCat, sVal
    Dim NewSettings As RegSetting
    NewSettings.name = sCat
    NewSettings.Value = sVal
    RegSettingsCache(X) = NewSettings
End Sub

Public Function RegLoad(ByVal sCat As String, ByVal sDefault As String) As String
    EnsureRegCacheIntact

    Dim X As Long
    X = FindRegCacheSetting(sCat)
    If X > 0 Then
        RegLoad = RegSettingsCache(X).Value
        Exit Function
    End If

NoSuchItem:
    RegLoad = GetSetting(App.Title, "Settings", sCat, sDefault)
    If UBound(RegSettingsCache) > 1024 Then
        Err.Raise vbObjectError + 9199, , "FATAL ERROR: Ran out of settings cache of size 1024 loading: " & sCat
    End If
    ReDim Preserve RegSettingsCache(0 To UBound(RegSettingsCache) + 1)
    X = UBound(RegSettingsCache)
    Dim NewSettings As RegSetting
    NewSettings.name = sCat
    NewSettings.Value = RegLoad
    RegSettingsCache(X) = NewSettings
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
    On Error GoTo zxc
    
    Dim sArray() As String
    part = part - 1
    sArray = Split(s, theDivider)
    GetPart = sArray(part)
    
    Exit Function
zxc:
    GetPart = ""
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
    

    s = Trim(Replace(sDirName, "/", "\"))
    
    If Right(s, 1) <> "\" Then s = s & "\"
    
    
    
    If WriteFile(s & "testbqva.txt", "data here") = True Then
        Kill s & "testbqva.txt"
        DirExists = True
    Else
        DirExists = False
    End If
End Function

Public Function sumProcess(s As String) As Double
    On Error Resume Next

    Dim tmpS As String, tmpS2 As String, tmpS3 As String
    Dim nextOp As Double, nextOpSymbol As String
    Dim nextOpSecond As Double, nextOpSymbolSecond As String
    Dim postVal As Double
    ''''''''''
    tmpS = s

    nextOp = NextEmptyOperator(tmpS)
    sumProcess = Val(Mid(tmpS, 1, nextOp - 1))
    
zStart:
    nextOp = NextEmptyOperator(tmpS)

    If nextOp = 0 Then GoTo zDone
        tmpS = Mid(tmpS, nextOp, Len(tmpS))
        nextOpSymbol = Mid(tmpS, 1, 1)

        nextOpSecond = NextEmptyOperator(Mid(tmpS, 2, Len(tmpS)))
        If nextOpSecond = 0 Then nextOpSecond = 9999
        
        tmpS2 = Mid(tmpS, 1, nextOpSecond)
        
        
        tmpS3 = Mid(tmpS, 1, nextOpSecond)
        tmpS2 = KillOps(tmpS2)
        postVal = Val(tmpS2)
        
        Select Case nextOpSymbol
        Case "+": sumProcess = sumProcess + postVal
        Case "-": sumProcess = sumProcess - postVal
        Case "*": sumProcess = sumProcess * postVal
        Case "/": sumProcess = sumProcess / postVal
        Case "^": sumProcess = sumProcess ^ postVal
        Case "%": sumProcess = sumProcess Mod postVal
        End Select
        
        tmpS = Mid(tmpS, Len(tmpS3) + 1, Len(tmpS))

    GoTo zStart
zDone:

    sumProcess = Int(sumProcess)

End Function


Public Function KillOps(s As String) As String
    KillOps = s
    KillOps = Replace(KillOps, "+", "")
    KillOps = Replace(KillOps, "-", "")
    KillOps = Replace(KillOps, "/", "")
    KillOps = Replace(KillOps, "*", "")
    KillOps = Replace(KillOps, "%", "")
    KillOps = Replace(KillOps, "^", "")
End Function


'Public Function NextEmptyOperator(s As String) As Long
'    NextEmptyOperator = 9999
'
'    If InStr(s, "*") Then NextEmptyOperator = InStr(s, "*")
'
'    If InStr(s, "+") And InStr(s, "+") < NextEmptyOperator Then
'        NextEmptyOperator = InStr(s, "+")
'    End If
'
'    If InStr(s, "-") And InStr(s, "-") < NextEmptyOperator Then
'        NextEmptyOperator = InStr(s, "-")
'    End If
'
'    If InStr(s, "/") And InStr(s, "/") < NextEmptyOperator Then
'        NextEmptyOperator = InStr(s, "/")
'    End If
'
'    If NextEmptyOperator = 9999 Then NextEmptyOperator = 0
'End Function

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



