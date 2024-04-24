Attribute VB_Name = "basMusic"
Option Explicit

Private Declare Function mciSendString Lib "winmm" Alias "mciSendStringA" (ByVal _
    lpstrCommand As String, ByVal lpstrReturnString As String, _
    ByVal uReturnLength As Long, ByVal hwndCallback As Long) As Long

Private MusicFiles() As String
Public MusicFileIndex As Long

Public Sub StopMusic()
    mciSendString "close dsomusic", vbNullString, 0, 0
End Sub

Public Sub CheckMusic()
    Dim MusicStatus As String * 128
    mciSendString "status dsomusic mode", MusicStatus, Len(MusicStatus), 0
    If LCase(Left(MusicStatus, 7)) = "playing" Then
        Exit Sub
    End If

    If i(RegLoad("music", "on") = "off") Then
        StopMusic
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
    
    Dim tmpFile As String
    Dim tmpFileName As String
    tmpFileName = MusicFiles(MusicFileIndex)
    tmpFile = App.Path & "/user/home/music/" & tmpFileName
    SayCOMM "Next track: " & tmpFileName

    StopMusic
    mciSendString "open """ & tmpFile & """ type mpegvideo alias dsomusic", vbNullString, 0, 0
    mciSendString "play dsomusic", vbNullString, 0, 0
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
