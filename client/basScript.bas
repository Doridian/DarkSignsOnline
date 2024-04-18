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


Public Function Run_Script_Code(ByVal tmpAll As String, ByVal ConsoleID As Integer, ScriptParameters() As Variant, ByVal ScriptFrom As String, ByVal FileKey As String, ByVal ServerDomain As String, ByVal ServerPort As Long, ByVal ErrorHandling As Boolean, ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal ScriptKey As String) As String
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
    s.Timeout = -1
    s.UseSafeSubset = True
    s.Language = "VBScript"

    Dim G As clsScriptFunctions
    Set G = New clsScriptFunctions
    G.Configure ConsoleID, ScriptFrom, False, s, ScriptParameters, FileKey, ServerDomain, ServerPort, RedirectOutput, DisableOutput, False
    s.AddObject "DSO", G, True

    tmpAll = DSODecryptScript(tmpAll, ScriptKey)
    tmpAll = ParseCommandLineOptional(tmpAll, ServerPort <= 0)

    On Error GoTo EvalError
    s.AddCode tmpAll
    On Error GoTo 0

    GoTo ScriptEnd
    Exit Function
EvalError:
    Dim ErrNumber As Long
    Dim ErrDescription As String
    ErrNumber = Err.Number
    ErrDescription = s.Error.Description
    If s.Error.Number = 0 Or ErrDescription = "" Then
        ErrNumber = Err.Number
        ErrDescription = Err.Description
    End If

    s.Error.Clear
    Err.Clear
    On Error GoTo 0

    Dim ObjectErrNumber As Long
    ObjectErrNumber = ErrNumber - vbObjectError

    If ObjectErrNumber = 9002 Then
        GoTo ScriptEnd
    End If
    If Not ErrorHandling Then
        Err.Raise ErrNumber, , ErrDescription
        Exit Function
    End If
    If ObjectErrNumber = 9001 Then
        GoTo ScriptCancelled
    End If
    
    Dim ErrNumberStr As String
    If ObjectErrNumber >= 0 And ObjectErrNumber <= 65535 Then
        ErrNumberStr = "(O#" & ObjectErrNumber & ")"
    Else
        ErrNumberStr = "(E#" & ErrNumber & ")"
    End If

    Dim ErrHelp As String
    ErrHelp = ""
    If ErrNumber = 13 Then
        ErrHelp = "This error might mean a function you tried to use does not exist"
    End If
    SayRaw ConsoleID, "Error processing script: " & ErrDescription & " " & ErrNumberStr & " " & ErrHelp & " {red}"
    GoTo ScriptEnd

ScriptCancelled:
    SayRaw ConsoleID, "Script Stopped by User (CTRL + C){orange}"
ScriptEnd:
    Run_Script_Code = G.ScriptGetOutput()
    G.CleanupScriptTasks
    cPath(ConsoleID) = OldPath
End Function

Public Function Run_Script(ByVal FileName As String, ByVal ConsoleID As Integer, ScriptParameters() As Variant, ByVal ScriptFrom As String, ByVal ErrorHandling As Boolean, ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal ScriptKey As String) As String
    If ScriptParameters(0) = "" Then
        ScriptParameters(0) = FileName
    End If
    
    DoEvents

    Dim ShortFileName As String
    'file name should be from local dir, i.e: /system/startup.ds
    ShortFileName = FileName

    Dim tmpAll As String
    tmpAll = GetFile(FileName)
    Run_Script = Run_Script_Code(tmpAll, ConsoleID, ScriptParameters, ScriptFrom, "", "", 0, ErrorHandling, RedirectOutput, DisableOutput, ScriptKey)
End Function


Public Function DeleteAFile(sFile As String)
    On Error Resume Next
    Kill sFile
End Function
