Attribute VB_Name = "basMusic"
Option Explicit

Const MM_MCINOTIFY = &H3B9
Const GWL_WNDPROC = -4

Private Declare Function mciSendString Lib "winmm" Alias "mciSendStringA" (ByVal _
    lpstrCommand As String, ByVal lpstrReturnString As String, _
    ByVal uReturnLength As Long, ByVal hwndCallback As Long) As Long
    
Private Declare Function SetWindowLong Lib "user32" Alias "SetWindowLongA" _
    (ByVal hWnd As Long, ByVal nIndex As Long, ByVal dwNewLong As Long) _
    As Long

Private Declare Function CallWindowProc Lib "user32" Alias "CallWindowProcA" _
    (ByVal lpPrevWndFunc As Long, ByVal hWnd As Long, ByVal Msg As Long, _
    ByVal wParam As Long, ByRef lParam As Long) As Long
    
Dim Playing As Boolean
Dim lastHWND As Long
Dim procOld As Long

Private MusicFiles() As String
Public MusicFileIndex As Long


Sub RegisterWindow(hWnd As Long)
    If lastHWND > 0 Then UnregisterWindow (lastHWND)
    lastHWND = hWnd
    procOld = SetWindowLong(hWnd, GWL_WNDPROC, AddressOf basMusic.wndProc)
End Sub

Sub UnregisterWindow(hWnd As Long)
    lastHWND = 0
    procOld = SetWindowLong(hWnd, GWL_WNDPROC, procOld)
End Sub

Public Function wndProc(ByVal hWnd As Long, ByVal iMsg As Long, ByVal wParam As Long, ByRef lParam As Long) As Long
    If hWnd = lastHWND & iMsg = MM_MCINOTIFY Then
        Playing = False
    End If
    wndProc = CallWindowProc(procOld, hWnd, iMsg, wParam, lParam)
End Function

Public Sub StopMusic()
    Playing = False
    mciSendString "close dsomusic", vbNullString, 0, 0
End Sub

Public Sub CheckMusic()
    If lastHWND <= 0 Then Exit Sub

    If i(RegLoad("music", "on") = "off") Then
        StopMusic
        Playing = False
        Exit Sub
    End If

    Dim FileFound As Boolean
    Dim curFile As String
    curFile = FileSystem.DIR(App.Path & "/user/home/music/")
    While curFile <> ""
        If LCase(Right(curFile, 4)) = ".mp3" Then
            If FileFound Then
                ReDim Preserve MusicFiles(0 To UBound(MusicFiles) + 1)
            Else
                ReDim Preserve MusicFiles(0 To 0)
                FileFound = True
            End If
            MusicFiles(UBound(MusicFiles)) = curFile
        End If
        curFile = FileSystem.DIR()
    Wend

    If Not FileFound Then Exit Sub

    If Not Playing Then
        NextMusicIndex
        
        Dim tmpFile As String
        Dim tmpFileName As String
        tmpFileName = MusicFiles(MusicFileIndex)
        tmpFile = App.Path & "/user/home/music/" & tmpFileName
        SayCOMM "Next track: " & tmpFileName

        StopMusic
        mciSendString "open """ & tmpFile & """ type mpegvideo alias dsomusic", vbNullString, 0, 0
        mciSendString "play dsomusic notify", vbNullString, 0, lastHWND
        Playing = True
        
        DoEvents
    End If
End Sub

Public Sub NextMusicIndex()
    MusicFileIndex = MusicFileIndex + 1

    If MusicFileIndex > UBound(MusicFiles) Then
        MusicFileIndex = 0
    End If
End Sub

Public Sub PrevMusicIndex()
    MusicFileIndex = MusicFileIndex - 1

    If MusicFileIndex < 0 Then
        MusicFileIndex = UBound(MusicFiles)
    End If
End Sub
