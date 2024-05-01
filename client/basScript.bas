Attribute VB_Name = "basScript"
Option Explicit

Public DownloadAborted(1 To 99) As Boolean
Public DownloadInUse(1 To 99) As Boolean
Public DownloadDone(1 To 99) As Boolean
Public DownloadResults(1 To 99) As String
Public DownloadCodes(1 To 99) As Integer
Public DownloadResponseTypes(1 To 99) As String

Public GetKeyWaiting(1 To 4) As Long
Public GetAsciiWaiting(1 To 4) As Long
Public WaitingForInput(1 To 4) As Boolean
Public WaitingForInputReturn(1 To 4) As String

Public CancelScript(1 To 4) As Boolean


Public Function Run_Script_Code(ByVal tmpAll As String, ByVal ConsoleID As Integer, ScriptParameters() As Variant, ByVal ScriptFrom As String, ByVal FileKey As String, ByVal ServerDomain As String, ByVal ServerPort As Long, ByVal ServerIP As String, ByVal ConnectingIP As String, ByVal ErrorHandling As Boolean, ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal ScriptKey As String, ByVal ScriptOwner As String) As String
    If ConsoleID < 1 Then
        ConsoleID = 1
    End If
    If ConsoleID > 4 Then
        ConsoleID = 4
    End If
    Dim OldPath As String
    OldPath = cPath(ConsoleID)

    CancelScript(ConsoleID) = False

    Dim SCT As ScriptControl
    Set SCT = New ScriptControl
    SCT.AllowUI = False
    SCT.Timeout = -1
    SCT.UseSafeSubset = True
    SCT.Language = "VBScript"

    Dim g As clsScriptFunctions
    Set g = New clsScriptFunctions
    g.Configure ConsoleID, ScriptFrom, False, SCT, ScriptParameters, FileKey, ServerDomain, ServerPort, RedirectOutput, DisableOutput, False, ScriptOwner, ServerIP, ConnectingIP
    SCT.AddObject "DSO", g, True
    LoadBasicFunctions SCT

    tmpAll = DSODecryptScript(tmpAll, ScriptKey)
    tmpAll = ParseCommandLineOptional(tmpAll, ConsoleID, ServerPort <= 0)

    Dim ErrNumber As Long
    Dim ErrDescription As String

    Dim CodeFaulted As Boolean
    CodeFaulted = False
    On Error GoTo OnCodeFaulted
    SCT.AddCode tmpAll
    On Error GoTo 0
    If Not CodeFaulted Then
        GoTo ScriptEnd
    End If

    Dim ObjectErrNumber As Long
    ObjectErrNumber = ErrNumber - vbObjectError

    If ObjectErrNumber = 9002 Then
        GoTo ScriptEnd
    End If
    If Not ErrorHandling Then
        Run_Script_Code = g.ScriptGetOutput()
        g.CleanupScriptTasks
        cPath(ConsoleID) = OldPath
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
    SayRaw ConsoleID, "Error processing script: " & ConsoleEscape(ErrDescription) & " " & ErrNumberStr & " " & ErrHelp & "{{red}}"
    GoTo ScriptEnd

ScriptCancelled:
    SayRaw ConsoleID, "Script Stopped by User (CTRL + B){{orange}}"
ScriptEnd:
    Run_Script_Code = g.ScriptGetOutput()
    g.CleanupScriptTasks
    cPath(ConsoleID) = OldPath
    Exit Function

OnCodeFaulted:
    ErrNumber = SCT.Error.Number
    ErrDescription = SCT.Error.Description
    If ErrNumber = 0 Or ErrDescription = "" Then
        ErrNumber = Err.Number
        ErrDescription = Err.Description
    End If

    CodeFaulted = True
    Resume Next
End Function

Public Function Run_Script(ByVal filename As String, ByVal ConsoleID As Integer, ScriptParameters() As Variant, ByVal ScriptFrom As String, ByVal ErrorHandling As Boolean, ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal ScriptKey As String, ByVal ConnectingIP As String) As String
    If ScriptParameters(0) = "" Then
        ScriptParameters(0) = filename
    End If
    
    DoEvents

    Dim ShortFileName As String
    'file name should be from local dir, i.e: /system/startup.ds
    ShortFileName = filename

    Dim tmpAll As String
    tmpAll = GetFile(filename)
    Run_Script = Run_Script_Code(tmpAll, ConsoleID, ScriptParameters, ScriptFrom, "", "", 0, "", ConnectingIP, ErrorHandling, RedirectOutput, DisableOutput, ScriptKey, "local")
End Function

