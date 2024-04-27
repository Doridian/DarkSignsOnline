Attribute VB_Name = "basMusic"
Option Explicit

Private MusicFiles() As String
Public MusicFileIndex As Long
Private BassChannel As Long
Private BassAllowPlay As Boolean
Private BassInitialized As Boolean

Private Declare Sub CopyMemory Lib "kernel32" Alias "RtlMoveMemory" (Destination As Any, Source As Any, ByVal length As Long)

Public Sub LoadMusic()
    If BassAllowPlay Then
        Exit Sub
    End If
    BassAllowPlay = True
End Sub

Public Sub UnloadMusic()
    BassAllowPlay = False
    StopMusic
    BASS_Pause
    BASS_Stop
    BASS_Free
End Sub

Public Sub StopMusic()
    If BassChannel <> 0 Then
        BASS_ChannelPause BassChannel
        BASS_ChannelStop BassChannel
        BassChannel = 0
    End If
End Sub

Private Sub HandleBassError(Optional ByVal IgnoreAlready As Boolean = False)
    Dim BErr As Long
    BErr = BASS_ErrorGetCode()
    If BErr = BASS_ERROR_ALREADY And IgnoreAlready Then
        Exit Sub
    End If
    If BErr <> BASS_OK Then
        Err.Raise vbObjectError + 1313, , "BASS error code: " & BErr
    End If
End Sub

Public Sub CheckMusic()
    If (Not BassAllowPlay) Or BassChannel <> 0 Then
        Exit Sub
    End If

    If i(ConfigLoad("music", "on") = "off") Then
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

    If Not BassInitialized Then
        BASS_Init -1, 44100, 0, frmConsole.hWnd, 0
        HandleBassError True
        BassInitialized = True
    End If

    BassChannel = BASS_StreamCreateFile(False, StrPtr(SafePath("/home/music/" & tmpFileName)), 0, 0, BASS_ASYNCFILE + BASS_STREAM_AUTOFREE)
    HandleBassError
    Dim TrackTitle As String, TrackArtist As String
    TrackTitle = ""
    TrackArtist = ""

    Dim TagPtr As Long
    TagPtr = BASS_ChannelGetTags(BassChannel, BASS_TAG_ID3)
    If TagPtr <> 0 Then
        Dim TagStruct As TAG_ID3
        Call CopyMemory(TagStruct, ByVal TagPtr, Len(TagStruct))
        TrackTitle = FixCStr(TagStruct.title)
        TrackArtist = FixCStr(TagStruct.artist)
    End If

    Dim SongName As String
    If TrackTitle <> "" Then
        If TrackArtist <> "" Then
            SongName = TrackTitle & " - " & TrackArtist
        Else
            SongName = TrackTitle
        End If
    Else
        SongName = "Unknown"
    End If

    SayCOMM "Next track: " & SongName & " (" & tmpFileName & ")"

    BASS_ChannelSetSync BassChannel, BASS_SYNC_ONETIME + BASS_SYNC_FREE, 0, AddressOf OnMusicEnd, 0
    HandleBassError
    BASS_ChannelPlay BassChannel, False
    HandleBassError
End Sub

Private Function FixCStr(ByVal InputStr As String) As String
    Dim StrLen As Long
    StrLen = InStr(InputStr, Chr(0))
    If StrLen <= 0 Then
        FixCStr = InputStr
        Exit Function
    End If
    FixCStr = Left(InputStr, StrLen - 1)
End Function

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
