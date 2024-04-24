Attribute VB_Name = "basMusic"
Option Explicit

Private MusicFiles() As String
Public MusicFileIndex As Long
Private BassChannel As Long
Private BassAllowPlay As Boolean

Public Sub LoadMusic()
    If BassAllowPlay Then
        Exit Sub
    End If
    BassAllowPlay = True
    BASS_Init -1, 44100, 0, frmConsole.hWnd, 0
    HandleBassError
End Sub

Public Sub UnloadMusic()
    BassAllowPlay = False
    StopMusic
End Sub

Public Sub StopMusic()
    If BassChannel <> 0 Then
        BASS_ChannelPause BassChannel
        BASS_ChannelStop BassChannel
        BassChannel = 0
    End If
End Sub

Private Sub HandleBassError()
    Dim BErr As Long
    BErr = BASS_ErrorGetCode()
    If BErr <> BASS_OK Then
        Err.Raise vbObjectError + 1313, , "BASS error code: " & BErr
    End If
End Sub

Public Sub CheckMusic()
    If (Not BassAllowPlay) Or BassChannel <> 0 Then
        Exit Sub
    End If

    If i(RegLoad("music", "on") = "off") Then
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

    NextMusicIndex

    Dim tmpFileName As String
    tmpFileName = MusicFiles(MusicFileIndex)
    SayCOMM "Next track: " & tmpFileName

    BassChannel = BASS_StreamCreateFile(False, StrPtr(SafePath("/home/music/" & tmpFileName)), 0, 0, BASS_ASYNCFILE + BASS_STREAM_AUTOFREE)
    HandleBassError
    BASS_ChannelSetSync BassChannel, BASS_SYNC_ONETIME + BASS_SYNC_FREE, 0, AddressOf OnMusicEnd, 0
    HandleBassError
    BASS_ChannelPlay BassChannel, False
    HandleBassError
End Sub

Public Sub OnMusicEnd(ByVal Handle As Long, ByVal Channel As Long, ByVal Data As Long, ByVal User As Long)
    If Handle = BassChannel Or Channel = BassChannel Then
        BassChannel = 0
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
