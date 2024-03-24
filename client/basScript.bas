Attribute VB_Name = "basScript"
Option Explicit

Public DownloadAborted(1 To 99) As Boolean
Public DownloadInUse(1 To 99) As Boolean
Public DownloadDone(1 To 99) As Boolean
Public DownloadResults(1 To 99) As String
Public DownloadCodes(1 To 99) As Integer

Public GetKeyWaiting(1 To 4) As Long
Public GetAsciiWaiting(1 To 4) As Long
Public WaitingForInput(1 To 4) As Boolean
Public WaitingForInputReturn(1 To 4) As String

Public CancelScript(1 To 4) As Boolean


Public Function Run_Script_Code(tmpAll As String, ByVal ConsoleID As Integer, ScriptParameters() As Variant, ScriptFrom As String, FileKey As String, ServerDomain As String, ServerPort As Long, IsRoot As Boolean, RedirectOutput As Boolean, DisableOutput As Boolean) As String
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
    s.Timeout = 1000
    s.UseSafeSubset = True
    s.Language = "VBScript"

    Dim G As clsScriptFunctions
    Set G = New clsScriptFunctions
    G.Configure ConsoleID, ScriptFrom, False, s, ScriptParameters, FileKey, ServerDomain, ServerPort, RedirectOutput, DisableOutput, IsRoot
    s.AddObject "DSO", G, True

    tmpAll = ParseCommandLineOptional(tmpAll, ServerPort <= 0)

    New_Console_Line_InProgress ConsoleID
    On Error GoTo EvalError
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

Public Function Run_Script(ByVal Filename As String, ByVal ConsoleID As Integer, ScriptParameters() As Variant, ByVal ScriptFrom As String, ByVal IsRoot As Boolean, ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean) As String
    If ScriptParameters(0) = "" Then
        ScriptParameters(0) = Filename
    End If
    
    DoEvents

    Dim ShortFileName As String
    'file name should be from local dir, i.e: /system/startup.ds
    ShortFileName = Filename

    Dim tmpAll As String
    tmpAll = GetFile(Filename)
    Run_Script = Run_Script_Code(tmpAll, ConsoleID, ScriptParameters, ScriptFrom, "", "", 0, IsRoot, RedirectOutput, DisableOutput)
End Function


Public Function DeleteAFile(sFile As String)
    On Error Resume Next
    Kill sFile
End Function
