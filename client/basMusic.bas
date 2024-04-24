Attribute VB_Name = "basMusic"
Option Explicit

Private MusicFiles() As String
Public MusicFileIndex As Long

Public Sub StopMusic()
    frmConsole.mmMusic.Command = "Stop"
    frmConsole.mmMusic.Command = "Close"
End Sub

Public Sub CheckMusic()
    If frmConsole.mmMusic.Mode = mciModePlay Then
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
    DoEvents
    frmConsole.mmMusic.FileName = tmpFile
    frmConsole.mmMusic.Command = "Open"
    frmConsole.mmMusic.Command = "Play"
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
