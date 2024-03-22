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


Public Function Run_Script_Code(tmpAll As String, ByVal ConsoleID As Integer, ScriptParameters() As String, ScriptFrom As String, FileKey As String, IsRoot As Boolean, RedirectOutput As Boolean, DisableOutput As Boolean, Optional Preamble As String) As String
    If ConsoleID < 1 Then
        ConsoleID = 1
    End If
    If ConsoleID > 4 Then
        ConsoleID = 4
    End If
    Dim OldPath As String
    OldPath = cPath(ConsoleID)

    CancelScript(ConsoleID) = False

    Dim s As New ScriptControl
    s.AllowUI = False
    s.Timeout = 100
    s.UseSafeSubset = True
    s.Language = "VBScript"

    Dim G As clsScriptFunctions
    Set G = New clsScriptFunctions
    G.Configure ConsoleID, ScriptFrom, False, s, ScriptParameters, FileKey, RedirectOutput, DisableOutput, IsRoot
    s.AddObject "DSO", G, True
    
    tmpAll = ParseCommandLineOptional(tmpAll, FileKey = "")

    New_Console_Line_InProgress ConsoleID
    On Error GoTo EvalError
    If Preamble <> "" Then
        s.AddCode Preamble
    End If
    s.AddCode tmpAll
    On Error GoTo 0

    GoTo ScriptEnd
    Exit Function
EvalError:
    If Err.Number = vbObjectError + 9002 Then
        GoTo ScriptEnd
    End If
    If Not IsRoot Then
        Err.Raise Err.Number, Err.Source, Err.Description, Err.HelpFile, Err.HelpContext
        Exit Function
    End If
    If Err.Number = vbObjectError + 9001 Then
        GoTo ScriptCancelled
    End If

    Dim ErrHelp As String
    ErrHelp = ""
    If Err.Number = 13 Then
        ErrHelp = "This error might mean a function you tried to use does not exist"
    End If
    SayRaw ConsoleID, "Error processing script: " & Err.Description & " (" & Str(Err.Number) & ") " & ErrHelp & " {red}"
    GoTo ScriptEnd

ScriptCancelled:
    SayRaw ConsoleID, "Script Stopped by User (CTRL + C){orange}"
ScriptEnd:
    Run_Script_Code = G.ScriptGetOutput()
    G.CleanupScriptTasks
    New_Console_Line ConsoleID
    cPath(ConsoleID) = OldPath
End Function

Public Function Run_Script(filename As String, ByVal ConsoleID As Integer, ScriptParameters() As String, ScriptFrom As String, FileKey As String, IsRoot As Boolean, RedirectOutput As Boolean, DisableOutput As Boolean) As String
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

    Run_Script = Run_Script_Code(tmpAll, ConsoleID, ScriptParameters, ScriptFrom, FileKey, IsRoot, RedirectOutput, DisableOutput)
End Function


Public Function DeleteAFile(sFile As String)
    On Error Resume Next
    Kill sFile
End Function
