Attribute VB_Name = "basScript"
Option Explicit

Public DownloadAborted(1 To 99) As Boolean
Public DownloadInUse(1 To 99) As Boolean
Public DownloadDone(1 To 99) As Boolean
Public DownloadResults(1 To 99) As String

Public GetKeyWaiting(1 To 4) As Integer
Public GetAsciiWaiting(1 To 4) As Integer
Public WaitingForInput(1 To 4) As Boolean
Public WaitingForInputReturn(1 To 4) As String

Public CancelScript(1 To 4) As Boolean

Public Function Run_Script_Code(tmpAll As String, ByVal consoleID As Integer, ScriptParameters() As String, ScriptFrom As String, Optional FileKey As String, Optional IsRoot As Boolean = False)
    If consoleID < 1 Then
        consoleID = 1
    End If
    If consoleID > 4 Then
        consoleID = 4
    End If
    Dim OldPath As String
    OldPath = cPath(consoleID)

    CancelScript(consoleID) = False

    Dim s As New ScriptControl
    s.AllowUI = False
    s.Timeout = 100
    s.UseSafeSubset = True
    s.Language = "VBScript"

    Dim G As clsScriptFunctions
    Set G = New clsScriptFunctions
    G.Configure consoleID, ScriptFrom, False, s, ScriptParameters, FileKey
    s.AddObject "DSO", G, True

    New_Console_Line_InProgress consoleID
    On Error GoTo EvalError
    s.AddCode tmpAll
    On Error GoTo 0

    GoTo ScriptEnd
    Exit Function
EvalError:
    If Err.Number = 9001 Then
        GoTo ScriptCancelled
    End If
    If Err.Number = 9002 Then
        GoTo ScriptEnd
    End If
    SAY consoleID, "Error processing script: " & Err.Description & " (" & Str(Err.Number) & ") {red}", False
    GoTo ScriptEnd

ScriptCancelled:
    If IsRoot Then
        SAY consoleID, "Script Stopped by User (CTRL + C){orange}", False
    End If
ScriptEnd:
    G.CleanupScriptTasks
    New_Console_Line consoleID
    cPath(consoleID) = OldPath
End Function

Public Function Run_Script(filename As String, ByVal consoleID As Integer, ScriptParameters() As String, ScriptFrom As String, Optional FileKey As String, Optional IsRoot As Boolean = False)
    If ScriptParameters(0) = "" Then
        ScriptParameters(0) = filename
    End If

    If Right(Trim(filename), 1) = ">" Then Exit Function
    If Trim(filename) = "." Or Trim(filename) = ".." Then Exit Function
    If InStr(filename, Chr(34) & Chr(34)) Then Exit Function
    
    DoEvents

    Dim ShortFileName As String
    'file name should be from local dir, i.e: \system\startup.ds
    ShortFileName = filename
    filename = App.Path & "\user" & filename
    'make sure it is not a directory
    If DirExists(filename) = True Then Exit Function

    If FileExists(filename) = False Then
        SayCOMM "File Not Found: " & filename
        Exit Function
    End If
    
    Dim FF As Long
    Dim tmpS As String
    Dim tmpAll As String
    tmpAll = ""
    FF = FreeFile
    Open filename For Input As #FF
        Do Until EOF(FF)
            tmpS = ""
            Line Input #FF, tmpS
            tmpAll = tmpAll & Trim(tmpS) & vbCrLf
        Loop
    Close #FF

    Run_Script_Code tmpAll, consoleID, ScriptParameters, ScriptFrom, FileKey, IsRoot
End Function

Public Function DownloadUserURL(ByVal VarVal As String, VarIndex As Integer, consoleID As Integer) As Integer
    DownloadUserURL = DownloadURL(VarVal, VarIndex, consoleID, True)
End Function

Public Function DownloadURL(ByVal VarVal As String, VarIndex As Integer, consoleID As Integer, Optional NoAuth As Boolean) As Integer
    Dim sUrl As String
    Dim PostData As String

    If InStr(Mid(VarVal, 1, 18), "(") > 0 Then
        VarVal = Mid(VarVal, InStr(VarVal, "(") + 1, Len(VarVal))
    End If

    sUrl = Trim(VarVal)
     
    sUrl = Trim(sUrl) & "***"
    sUrl = Replace(sUrl, ")***", "")
    sUrl = Replace(sUrl, "***", "")
    
    If InStr(sUrl, "?") > 0 Then
        PostData = Mid(sUrl, InStr(sUrl, "?") + 1, Len(sUrl))
        sUrl = Mid(sUrl, 1, InStr(sUrl, "?") - 1)
    Else
        PostData = ""
    End If
    PostData = Trim(PostData)
    sUrl = Trim(sUrl)
    
    Dim sDomain As String
    If InStr(sUrl, "/") > 0 Then
        sDomain = Mid(sUrl, 1, InStr(sUrl, "/") - 1)
    Else
        sDomain = sUrl
    End If
    

    DownloadURL = RunPage(sUrl, consoleID, True, PostData, VarIndex, NoAuth)
End Function

Public Function DeleteAFile(sFile As String)
    On Error Resume Next
    Kill sFile
End Function
