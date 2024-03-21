VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsScriptFunctions"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

Private PrivConsoleID As Integer
Private ScriptFrom As String
Private IsCLIInput As Boolean
Private IsConfigured As Boolean
Private SControl As ScriptControl
Public Aborted As Boolean

Private PendingCustomDownloads() As Integer

Public Property Get UserName() As String
    UserName = myUsername
End Property

Public Property Let UserName(ByVal NewValue As String)
    AssertCLIOnly
    SetUsername NewValue, consoleID
End Property

Public Property Get Password() As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
End Property

Public Property Let Password(ByVal NewValue As String)
    AssertCLIOnly
    SetPassword NewValue, consoleID
End Property

Public Property Get consoleID() As String
    consoleID = PrivConsoleID
End Property

Public Property Get TimeStr() As String
    TimeStr = DateTime.Time$
End Property

Public Property Get DateStr() As String
    DateStr = DateTime.Date$
End Property

Private Sub AssertCLIOnly()
    If IsCLIInput Then
        Exit Sub
    End If
    Aborted = True
    Err.Raise 9006, "DSO", "Script tried to execute CLI only functionality"
End Sub

Private Sub Class_Initialize()
    ReDim PendingCustomDownloads(0 To 0)
    IsConfigured = False
    Aborted = False
End Sub

Public Sub CleanupScriptTasks()
    If UBound(PendingCustomDownloads) > 0 Then
        Dim X As Integer
        For X = 1 To UBound(PendingCustomDownloads)
            DownloadAborted(X) = True
        Next
    End If
    ReDim PendingCustomDownloads(0 To 0)
    Aborted = True
End Sub

Public Sub Quit()
    Aborted = True
    Err.Raise 9002, "DSO", "Script exited"
End Sub

Public Sub Configure(NewConsoleID As Integer, NewScriptFrom As String, NewIsCLIInput As Boolean, NewScriptControl As ScriptControl)
    If IsConfigured Then
        Exit Sub
    End If
    IsConfigured = True
    PrivConsoleID = NewConsoleID
    ScriptFrom = NewScriptFrom
    IsCLIInput = NewIsCLIInput
    Set SControl = NewScriptControl
End Sub

Private Sub AddCustomDownload(ResIndex As Integer)
    ReDim Preserve PendingCustomDownloads(0 To UBound(PendingCustomDownloads) + 1)
    PendingCustomDownloads(UBound(PendingCustomDownloads)) = ResIndex
End Sub

Private Function HasPendingCustomDownload(ResIndex As Integer) As Boolean
    HasPendingCustomDownload = False
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Function
    End If

    Dim X As Integer
    
    For X = 1 To UBound(PendingCustomDownloads)
        If PendingCustomDownloads(X) = ResIndex Then
            HasPendingCustomDownload = True
            Exit Function
        End If
    Next
End Function

Private Sub RemoveCustomDownload(ResIndex As Integer)
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Sub
    End If

    Dim NewPendingCustomDownloads() As Integer
    ReDim NewPendingCustomDownloads(1 To UBound(PendingCustomDownloads))
    
    Dim X As Integer
    Dim Y As Integer
    Y = 0

    Dim MadeChanges As Boolean

    For X = 1 To UBound(PendingCustomDownloads)
        If PendingCustomDownloads(X) = ResIndex Then
            MadeChanges = True
        Else
            Y = Y + 1
            NewPendingCustomDownloads(Y) = ResIndex
        End If
    Next
    
    If Not MadeChanges Then
        Exit Sub
    End If
    
    ReDim PendingCustomDownloads(0 To Y)
    For X = 1 To Y
        PendingCustomDownloads(X) = NewPendingCustomDownloads(X)
    Next
End Sub

Private Function DoDownload(Url As String, UsePost As Boolean, PostData As String, NoAuth As Boolean) As Integer
    Dim ResIndex As Integer
    DoDownload = 0
    For ResIndex = 1 To 99
        If Not DownloadInUse(ResIndex) Then
            DoDownload = ResIndex
            Exit For
        End If
    Next
    If DoDownload <= 0 Then
        Err.Raise 9100, "DSO", "No free download slots"
        Exit Function
    End If

    DownloadInUse(ResIndex) = True
    DownloadDone(ResIndex) = False

    AddCustomDownload ResIndex

    RunPage Url, PrivConsoleID, UsePost, PostData, ResIndex, True
    Yield
End Function

Public Function WAITFOR(ResIndexRaw As Variant) As String
    If VarType(ResIndexRaw) <> vbInteger Then
        WAITFOR = "[invalid]"
        Exit Function
    End If
    Dim ResIndex As Integer
    ResIndex = ResIndexRaw

    While Not DownloadDone(ResIndex)
        Yield
        If Not HasPendingCustomDownload(ResIndex) Then
            WAITFOR = "[invalid]"
            Exit Function
        End If
    Wend

    WAITFOR = DownloadResults(ResIndex)
    DownloadInUse(ResIndex) = False
    RemoveCustomDownload ResIndex
    Yield
End Function

Public Sub SayCOMM(s As String)
    basWorld.SayCOMM s
    Yield
End Sub

Public Sub CD(dir As String)
    ChangeDir dir, PrivConsoleID
    Yield
End Sub

Public Sub SAY(s As String)
    basConsole.SAY PrivConsoleID, s
    Yield
End Sub

Public Sub RUN(Script As String)
    Yield
    Run_Script cPath(PrivConsoleID) & "/" & Script, PrivConsoleID, "", "RUN"
    Yield
End Sub

Public Function DOWNLOAD(Url As String) As Integer
     DOWNLOAD = DoDownload(Url, True, "", True)
End Function

Public Function DRAW(YPos As Long, R As Long, G As Long, b As Long, Mode As String)
    DrawItUp YPos, R, G, b, Mode, PrivConsoleID
    Yield
End Function

Public Sub LOGIN()
    LoginNow PrivConsoleID
    Yield
End Sub

Public Sub LOGOUT()
    LogoutNow PrivConsoleID
    Yield
End Sub

Public Sub Yield()
    DoEvents
    If CancelScript(PrivConsoleID) Then
        Aborted = True
        Err.Raise 9001, "DSO", "Script canceled by Ctrl+C"
    End If
End Sub
