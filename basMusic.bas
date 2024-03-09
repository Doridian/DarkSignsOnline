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

Public MusicFileIndex As Integer


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
    
    On Error Resume Next
    
    If i(RegLoad("music", "on") = "off") Then
        StopMusic
        Playing = False
        Exit Sub
    End If
    
    On Error Resume Next
    With frmConsole
        MakeADir App.Path & "\user\home\mp3\"
        .FileMusic.Path = App.Path & "\user\home\mp3\"
        .FileMusic.Refresh
        
        If .FileMusic.ListCount < 1 Then Exit Sub
        
        Dim tmpFile As String
        
        'If MP.PlayState = mpStopped Or MP.PlayState = mpClosed Or MP.PlayState = mpWaiting Then
        If Not Playing Then
        
            NextMusicIndex
            
            tmpFile = .FileMusic.Path & "\" & .FileMusic.List(MusicFileIndex)
    
            StopMusic
            mciSendString "open """ & tmpFile & """ type mpegvideo alias dsomusic", vbNullString, 0, 0
            mciSendString "play dsomusic notify", vbNullString, 0, lastHWND
            Playing = True
            
            DoEvents
            
        End If
    End With
End Sub

Public Sub NextMusicIndex()
    MusicFileIndex = MusicFileIndex + 1
    
    If MusicFileIndex > (frmConsole.FileMusic.ListCount - 1) Then
        MusicFileIndex = 0
    End If
End Sub

Public Sub PrevMusicIndex()
    MusicFileIndex = MusicFileIndex - 1
    
    If MusicFileIndex < 0 Then
        MusicFileIndex = frmConsole.FileMusic.ListCount - 1
    End If
    
End Sub
