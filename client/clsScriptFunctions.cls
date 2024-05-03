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

' Notices for declaring things for DScript to use
' 1) If DScript should be able to use it, it must be Public
' 2) Always use ByVal for arguments where possible
' 3) Always use Function, not Sub
' 4) For Arguments that can't use ByVal (arrays etc), you must be Variant (Variant() does NOT work) and handle the types yourself
' 5) To return arrays, you must use Variant(), anything else can be returned as-is

Private PrivConsoleID As Integer
Private PrivParameters() As Variant
Private IsCLIInput As Boolean
Private IsConfigured As Boolean
Private SControl As ScriptControl
Private FileKey As String
Private PrivScriptOwner As String
Private PrivTermlibObject As clsScriptTermlib

Private Aborted As Boolean
Private PrivAllowUnAbort As Boolean

Private PrivDisableOutput As Boolean
Private PrivRedirectOutput As Boolean
Private PrivOutput As String
Private PrivServerDomain As String
Private PrivServerIP As String
Private PrivServerConnectingIP As String
Private PrivServerPort As Long
Private PrivSpoofedLocalConnectingIP As String

Private PendingCustomDownloads() As Long

Private Declare Function GetTickCount Lib "kernel32" () As Long
Private Declare Function GetPrivateProfileString Lib "kernel32" Alias "GetPrivateProfileStringA" (ByVal lpApplicationName As String, ByVal lpKeyName As Any, ByVal lpDefault As String, ByVal lpReturnedString As String, ByVal nSize As Long, ByVal lpFileName As String) As Long
Private Declare Function WritePrivateProfileString Lib "kernel32" Alias "WritePrivateProfileStringA" (ByVal lpApplicationName As String, ByVal lpKeyName As Any, ByVal lpString As Any, ByVal lpFileName As String) As Long

Public Property Get UserName() As String
    UserName = myUsername
End Property

Public Property Get ServerDomain() As String
    ServerDomain = PrivServerDomain
End Property

Public Property Get ServerIP() As String
    ServerIP = PrivServerIP
End Property

Public Property Get ServerPort() As Long
    ServerPort = PrivServerPort
End Property

Public Property Get ConnectingIP() As String
    ConnectingIP = PrivServerConnectingIP
End Property

Public Property Let UserName(ByVal NewValue As String)
    AssertLocalOnly

    SetUsername NewValue, ConsoleID
End Property

Public Property Get Password() As String
    If myPassword = "" Then
        Password = ""
    Else
        Password = "[hidden]"
    End If
End Property

Public Property Let Password(ByVal NewValue As String)
    AssertLocalOnly

    SetPassword NewValue, ConsoleID
End Property

Public Property Get CWD() As String
    AssertLocalOnly

    CWD = cPath(PrivConsoleID)
End Property

Public Property Let CWD(ByVal NewValue As String)
    AssertLocalOnly

    Dim RawDir As String
    RawDir = ResolvePath(NewValue)

    If Not DirExists(RawDir) Then
        Err.Raise 53, , "File not found"
        Exit Property
    End If

    cPath(PrivConsoleID) = RawDir
    Yield
End Property

Public Property Let ExternalEditor(ByVal NewValue As Boolean)
    AssertLocalOnly

    If NewValue Then
        ConfigSave "externaleditor", "true", False
    Else
        ConfigSave "externaleditor", "false", False
    End If
End Property

Public Property Get ExternalEditor() As Boolean
    AssertLocalOnly

    ExternalEditor = (ConfigLoad("externaleditor", False, False) = "true")
End Property

Public Property Let DisableFlashing(ByVal NewValue As Boolean)
    AssertLocalOnly

    SayCOMM "Setting disable flashing = " & NewValue
    SetDisableFlashing NewValue
End Property

Public Property Get DisableFlashing() As Boolean
    DisableFlashing = basConsole.DisableFlashing
End Property

Public Property Get IsOutputDisabled() As Boolean
    IsOutputDisabled = PrivDisableOutput
End Property

Public Property Get IsOutputRedirected() As Boolean
    IsOutputRedirected = PrivRedirectOutput
End Property

Public Property Get ConsoleInvisibleChar() As String
    ConsoleInvisibleChar = basConsole.ConsoleInvisibleChar
End Property

Public Property Get ConsoleID() As String
    ConsoleID = PrivConsoleID
End Property

Private Sub CrashIfReached()
    Aborted = True
    While True: Wend
End Sub

Public Function IsLocal() As Boolean
    IsLocal = PrivServerPort <= 0
End Function

Private Sub AssertRemoteOnly()
    If Not IsLocal() Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9008, , "remote only functionality"
    CrashIfReached
End Sub

Private Sub AssertLocalOnly()
    If IsLocal() Then
        Exit Sub
    End If
    Err.Raise vbObjectError + 9007, , "local only functionality"
    CrashIfReached
End Sub

Private Sub Class_Initialize()
    ReDim PendingCustomDownloads(0 To 0)
    IsConfigured = False
    Aborted = False
    PrivOutput = ""
End Sub

Public Sub CleanupScriptTasks()
    If UBound(PendingCustomDownloads) > 0 Then
        Dim x As Long, y As Long
        For x = 1 To UBound(PendingCustomDownloads)
            y = PendingCustomDownloads(x)
            DownloadAborted(y) = True
            If DownloadDone(y) Then
                DownloadInUse(y) = False
            End If
        Next
    End If
    ReDim PendingCustomDownloads(0 To 0)
    Aborted = True
    GetKeyWaiting(ConsoleID) = 0
    GetAsciiWaiting(ConsoleID) = 0
    WaitingForInput(ConsoleID) = False
    WaitingForInputReturn(ConsoleID) = ""
End Sub

Public Sub UnAbort()
    If PrivAllowUnAbort Then
        Aborted = False
    End If
End Sub

Public Function Quit()
    Aborted = True
    Err.Raise vbObjectError + 9002, , "Script exited"
End Function

Public Function ScriptGetOutput() As String
    ScriptGetOutput = PrivOutput
End Function

Public Function ReadLine(ByVal Prompt As String, Optional ByVal RGBVal As Long = -1) As String
    If PrivDisableOutput Then
        ReadLine = ""
        Yield
        Exit Function
    End If

    cPrompt(PrivConsoleID) = Prompt
    CurrentPromptInput(PrivConsoleID) = ""
    CurrentPromptSelStart(PrivConsoleID) = 0
    CurrentPromptSelLength(PrivConsoleID) = 0
    WaitingForInput(PrivConsoleID) = True

    New_Console_Line PrivConsoleID
    If RGBVal >= 0 Then
        Draw -1, RGBVal, "solid"
    End If

    While WaitingForInput(ConsoleID)
        If Not YieldSafe() Then GoTo ReadLineExit
    Wend
    ReadLine = WaitingForInputReturn(PrivConsoleID)
    Exit Function

ReadLineExit:
    ReadLine = ""
    RenderPromptInput PrivConsoleID
    frmConsole.QueueConsoleRender
    Yield
End Function

Public Function GetKey() As Long
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    GetKeyWaiting(ConsoleID) = -1
    While GetKeyWaiting(ConsoleID) = -1
        If Not YieldSafe() Then GoTo ExitGetKey
    Wend
    GetKey = GetKeyWaiting(ConsoleID)
    Exit Function

ExitGetKey:
    GetKeyWaiting(ConsoleID) = 0
    GetKey = 0
    Yield
End Function

Public Function GetASCII() As Long
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    GetAsciiWaiting(ConsoleID) = -1
    While GetAsciiWaiting(ConsoleID) = -1
        If Not YieldSafe() Then GoTo ExitGetASCII
    Wend
    GetASCII = GetAsciiWaiting(ConsoleID)
    Exit Function

ExitGetASCII:
    GetAsciiWaiting(ConsoleID) = 0
    GetASCII = 0
    Yield
End Function

Public Sub Configure(ByVal NewConsoleID As Integer, ByVal NewIsCLIInput As Boolean, NewScriptControl As ScriptControl, NewPrivParameters() As Variant, ByVal NewFileKey As String, ByVal NewServerDomain As String, ByVal NewServerPort As Long, ByVal NewRedirect As Boolean, NewDisableOutput As Boolean, ByVal NewAllowUnAbort As Boolean, ByVal NewScriptOwner As String, ByVal NewServerIP As String, ByVal NewServerConnectingIP As String)
    If IsConfigured Then
        Exit Sub
    End If
    IsConfigured = True
    PrivConsoleID = NewConsoleID
    IsCLIInput = NewIsCLIInput
    Set SControl = NewScriptControl
    PrivParameters = NewPrivParameters
    FileKey = NewFileKey

    PrivServerDomain = NewServerDomain
    PrivServerPort = NewServerPort
    PrivAllowUnAbort = NewAllowUnAbort
    PrivScriptOwner = NewScriptOwner
    PrivServerIP = NewServerIP
    PrivServerConnectingIP = NewServerConnectingIP
    PrivSpoofedLocalConnectingIP = PrivServerConnectingIP

    PrivDisableOutput = NewDisableOutput
    PrivRedirectOutput = NewRedirect
End Sub

Public Function Cls()
    Clear
End Function

Public Function Delete(ByVal file As String)
    Del file
End Function

Private Sub AddCustomDownload(ByVal ResIndex As Long)
    ReDim Preserve PendingCustomDownloads(0 To UBound(PendingCustomDownloads) + 1)
    PendingCustomDownloads(UBound(PendingCustomDownloads)) = ResIndex
End Sub

Private Function HasPendingCustomDownload(ByVal ResIndex As Long) As Boolean
    HasPendingCustomDownload = False
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Function
    End If

    Dim x As Long
    
    For x = 1 To UBound(PendingCustomDownloads)
        If PendingCustomDownloads(x) = ResIndex Then
            HasPendingCustomDownload = True
            Exit Function
        End If
    Next
End Function

Private Sub RemoveCustomDownload(ByVal ResIndex As Long)
    If UBound(PendingCustomDownloads) < 1 Then
        Exit Sub
    End If

    Dim NewPendingCustomDownloads() As Long
    ReDim NewPendingCustomDownloads(1 To UBound(PendingCustomDownloads))
    
    Dim x As Long
    Dim y As Long
    y = 0

    Dim MadeChanges As Boolean

    For x = 1 To UBound(PendingCustomDownloads)
        If PendingCustomDownloads(x) = ResIndex Then
            MadeChanges = True
        Else
            y = y + 1
            NewPendingCustomDownloads(y) = PendingCustomDownloads(x)
        End If
    Next
    
    If Not MadeChanges Then
        Exit Sub
    End If
    
    ReDim PendingCustomDownloads(0 To y)
    For x = 1 To y
        PendingCustomDownloads(x) = NewPendingCustomDownloads(x)
    Next
End Sub

' VBTYPE: _RETURN=HTTPRequest
Private Function DoDownloadAPI(ByVal url As String, ByVal UsePost As Boolean, ByVal PostData As String, ByVal ResponseType As String) As String
    If UserName = "" Or Password = "" And url <> "auth.php" Then
        basConsole.SayRaw PrivConsoleID, "You must be logged in to do that!{{36 center orange impact nobold}}"
        basConsole.SayRaw PrivConsoleID, "Set your USERNAME and PASSWORD, then type LOGIN.{{24 center white impact nobold}}"
        RaiseMiscError "User not logged in"
        Exit Function
    End If

    DoDownloadAPI = DoDownload(API_Server & url, UsePost, PostData, False, ResponseType)
End Function

' VBTYPE: _RETURN=HTTPRequest
Private Function DoDownload(ByVal url As String, ByVal UsePost As Boolean, ByVal PostData As String, ByVal NoAuth As Boolean, ByVal ResponseType As String) As String
    Dim ResIndex As Long
    DoDownload = ""
    For ResIndex = 1 To 50
        If Not DownloadInUse(ResIndex) Then
            DoDownload = "HTTPRequest" & ConsoleInvisibleChar & "(" & ResIndex & ")"
            Exit For
        End If
    Next
    If DoDownload = "" Then
        Err.Raise vbObjectError + 9100, , "No free download slots"
        Exit Function
    End If

    DownloadAborted(ResIndex) = False
    DownloadInUse(ResIndex) = True
    DownloadDone(ResIndex) = False
    DownloadResponseTypes(ResIndex) = ResponseType

    AddCustomDownload ResIndex

    RunPage url, UsePost, PostData, ResIndex, NoAuth
    If NoAuth Then
        Yield
    End If
End Function

Private Function ParseReqIDStr(ByVal Req As String) As Long
    If Left(Req, 13) <> "HTTPRequest" & ConsoleInvisibleChar & "(" Or Right(Req, 1) <> ")" Then
        ParseReqIDStr = -1
        Exit Function
    End If

    On Error GoTo InvalidNumber
    ParseReqIDStr = Mid(Req, 14, Len(Req) - 14)
    On Error GoTo 0
    Exit Function

InvalidNumber:
    ParseReqIDStr = -1
End Function

' VBTYPE: Req=HTTPRequest
Public Function WaitFor(ByVal Req As String) As String
    Dim Resp As clsHttpResponse
    Set Resp = WaitFor_Internal(Req)
    If Resp Is Nothing Then
        WaitFor = Req
        Exit Function
    End If
    WaitFor = Resp.Response
End Function

' VBTYPE: Req=HTTPRequest
' VBTYPE: _RETURN=Variant(Long, String)
Public Function WaitForRaw(ByVal Req As String) As Variant()
    Dim Resp As clsHttpResponse
    Set Resp = WaitFor_Internal(Req)

    Dim Res() As Variant
    ReDim Res(0 To 1)
    Res(0) = Resp.Code
    Res(1) = Resp.RawResponse
    WaitForRaw = Res
End Function

' VBTYPE: ReqS=HTTPRequest
Private Function WaitFor_Internal(ByVal ReqS As String, Optional ByVal NoYield As Boolean = False) As clsHttpResponse
    Set WaitFor_Internal = Nothing

    Dim Req As Long
    Req = ParseReqIDStr(ReqS)
    If Req < 0 Then
        Exit Function
    End If

    ConsoleWaitingOnRemote(PrivConsoleID) = True
    frmConsole.QueueConsoleRender

    If Not YieldSafe() Then GoTo WaitForExit

    While Not DownloadDone(Req)
        If Not YieldSafe() Then GoTo WaitForExit
        If Not HasPendingCustomDownload(Req) Then GoTo WaitForExit
    Wend

    Dim Res As clsHttpResponse
    Set Res = New clsHttpResponse
    Res.Code = DownloadCodes(Req)
    Res.RawResponse = DownloadResults(Req)
    Res.ResponseType = DownloadResponseTypes(Req)
    'Res.ResponseType = Req.ResponseType
    'If Req.RaiseForStatus Then
    '    Res.RaiseForStatus
    'End If

    Set WaitFor_Internal = Res

    DownloadInUse(Req) = False
    RemoveCustomDownload Req

WaitForExit:
    ConsoleWaitingOnRemote(PrivConsoleID) = False
    frmConsole.QueueConsoleRender
    If Not NoYield Then
        Yield
    End If
End Function

Public Function CD(ByVal DIR As String)
    AssertLocalOnly

    CWD = DIR
End Function

' VBTYPE: _RETURN=String()
Public Function ReadDir(ByVal RawPath As String) As Variant()
    AssertLocalOnly
    
    Dim Res() As Variant

    Dim Attr As Long
    Dim filename As String
    Dim IsFirst As Boolean
    IsFirst = True

    Dim Path As String
    Path = ResolvePath(RawPath)
    Path = SafePath(Path)
    
    Attr = GetAttr(Path)
    If (Attr And vbDirectory) <> vbDirectory Then
        Err.Raise vbObjectError + 9301, , "Can only list directories"
        Exit Function
    End If
    
    Path = Path & "/"
    
    filename = FileSystem.DIR(Path, vbNormal + vbDirectory)
    While filename <> ""
        If IsFirst Then
            ReDim Res(0 To 0)
            IsFirst = False
        Else
            ReDim Preserve Res(0 To UBound(Res) + 1)
        End If

        Attr = GetAttr(Path & filename)
        If (Attr And vbDirectory) = vbDirectory Then
            filename = filename & "/"
        End If
        
        Res(UBound(Res)) = filename
        filename = FileSystem.DIR()
    Wend

    If IsFirst Then
        ReDim Res(-1 To -1)
        ReadDir = Res
        Yield
        Exit Function
    End If

    ReadDir = Res
    Yield
End Function

Public Function restart()
    AssertLocalOnly

    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    frmConsole.Start_Console PrivConsoleID
    Yield
End Function

Public Function EDIT(ByVal file As String)
    AssertLocalOnly

    Yield
    EditFile ResolvePath(file), PrivConsoleID
    Yield
End Function

Public Function SayLine(ByVal S As String, Optional ByVal YPos As Long = -1)
    S = StripAfterNewline(S)
    If S = "" Then
        Yield
        Exit Function
    End If

    If PrivRedirectOutput Then
        If PrivOutput = "" Then
            PrivOutput = S
        Else
            PrivOutput = PrivOutput & vbCrLf & S
        End If
        Yield
    End If
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    Yield
    basConsole.SayRaw PrivConsoleID, S, YPos
    Yield
End Function

Public Function PrintVar(ParamArray param() As Variant)
    If UBound(param) < 0 Then
        Say "No arguments to print{{orange}}"
        Exit Function
    End If

    If LBound(param) = UBound(param) And VarType(param(UBound(param))) = vbString Then
        Dim StrParam As String
        StrParam = param(LBound(param))
        Dim PossibleReqIndex As Long
        PossibleReqIndex = ParseReqIDStr(StrParam)
        If PossibleReqIndex >= 0 Then
            PrintVar WaitFor(StrParam)
        Else
            Say StrParam
        End If
        Exit Function
    End If

    Dim x As Long
    For x = LBound(param) To UBound(param)
        PrintVarInt param(x), "", "ArgV(" & x & ") ", 0
    Next x
End Function

Public Function PrintVarSingleIfSet(param As Variant)
    If VarType(param) = vbEmpty Then
        Exit Function
    End If

    PrintVar param
End Function

Private Sub PrintVarInt(param As Variant, ByVal Prefix As String, ByVal index As String, ByVal Depth As String)
    Dim TypeName As String

    Select Case (VarType(param) And (Not vbArray))
        Case vbBoolean:
            TypeName = "Boolean"
        Case vbByte:
            TypeName = "Byte"
        Case vbCurrency:
            TypeName = "Currency"
        Case vbDataObject:
            TypeName = "DataObject"
        Case vbDate:
            TypeName = "Date"
        Case vbDecimal:
            TypeName = "Decimal"
        Case vbDouble:
            TypeName = "Double"
        Case vbEmpty:
            TypeName = "Empty"
        Case vbError:
            TypeName = "Error"
        Case vbInteger:
            TypeName = "Integer"
        Case vbLong:
            TypeName = "Long"
        Case vbNull:
            TypeName = "Null"
        Case vbObject:
            TypeName = "Object"
        Case vbSingle:
            TypeName = "Single"
        Case vbString:
            TypeName = "String"
        Case vbUserDefinedType:
            TypeName = "UserDefinedType"
        Case vbVariant:
            TypeName = "Variant"
    End Select
    
    Dim MainPrefix As String
    MainPrefix = Prefix
    If index <> "" Then
        MainPrefix = MainPrefix & index
    End If

    Yield
    If (VarType(param) And vbArray) = vbArray Then
        Dim x As Long
        Dim XV As String
        Say MainPrefix & "{{yellow}}Array of element type " & TypeName & " from " & LBound(param) & " to " & UBound(param)
        Dim SubPrefix As String
        SubPrefix = "    " & Prefix
        For x = LBound(param) To UBound(param)
            Yield
            PrintVarInt param(x), SubPrefix, "(" & x & ") ", Depth + 1
        Next x
    Else
        Dim StrParam As String
        StrParam = "" & param
        Dim StrPos As Long
        Dim HadCut As Boolean
        HadCut = False
        StrPos = InStr(StrParam, vbCr)
        If StrPos > 0 Then
            StrParam = Left(StrParam, StrPos - 1)
            HadCut = True
        End If
        StrPos = InStr(StrParam, vbLf)
        If StrPos > 0 Then
            StrParam = Left(StrParam, StrPos - 1)
            HadCut = True
        End If

        If HadCut Then
            StrParam = StrParam & " [...]"
        End If

        Say MainPrefix & "{{blue}}Value of type " & TypeName & " = " & StrParam
    End If
    Yield
End Sub

Public Function LineUp()
    Say ""
End Function

Public Function Say(ParamArray Params() As Variant)
    Dim x As Long
    Dim sStr As String
    Dim XV As String
    For x = LBound(Params) To UBound(Params)
        XV = "" & Params(x)
        If XV <> "" Then
            If sStr <> "" Then
                sStr = sStr & " "
            End If
            sStr = sStr & XV
        End If
    Next x

    If PrivRedirectOutput Then
        If PrivOutput = "" Then
            PrivOutput = sStr
        Else
            PrivOutput = PrivOutput & vbCrLf & sStr
        End If
        Yield
    End If
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    
    If sStr = "" Then
        Yield
        basConsole.SayRaw PrivConsoleID, ""
        Yield
        Exit Function
    End If

    Dim ScriptOutSplit() As String
    ScriptOutSplit = Split(sStr, vbCrLf)
    For x = LBound(ScriptOutSplit) To UBound(ScriptOutSplit)
        Yield
        basConsole.SayRaw PrivConsoleID, ScriptOutSplit(x)
        Yield
    Next
End Function

Public Function SayCOMM(ParamArray Params() As Variant)
    Dim x As Long
    Dim sStr As String
    Dim XV As String
    For x = LBound(Params) To UBound(Params)
        XV = Params(x)
        If XV <> "" Then
            If sStr <> "" Then
                sStr = sStr & " "
            End If
            sStr = sStr & XV
        End If
    Next x

    Yield
    If sStr = "" Then
        Exit Function
    End If
    basWorld.SayCOMM sStr
    Yield
End Function

Public Function Coalesce(ParamArray VarValues() As Variant) As Variant
    Dim x As Long
    Dim VarValue As Variant
    For x = LBound(VarValues) To UBound(VarValues)
        VarValue = VarValues(x)
        If Not IsEmpty(VarValue) Then
            Coalesce = VarValue
            Exit Function
        End If
    Next
    Coalesce = Null
End Function

Public Function ResolveCommand(ByVal Command As String) As String
    AssertLocalOnly

    ResolveCommand = basCommands.ResolveCommand(PrivConsoleID, Command)
End Function

Public Function ResolvePath(ByVal Path As String) As String
    AssertLocalOnly

    ResolvePath = basCommands.ResolvePath(PrivConsoleID, Path)
End Function

Public Function ResolvePathRel(ByVal BasePath As String, ByVal Path As String) As String
    ResolvePathRel = basCommands.ResolvePathRel(BasePath, Path)
    If Right(ResolvePathRel, 1) = "/" And Len(ResolvePathRel) > 1 Then
        ResolvePathRel = Mid(ResolvePathRel, 1, Len(ResolvePathRel) - 1)
    End If
    If ResolvePathRel = "" Then
        ResolvePathRel = "/"
    End If
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function HttpRequest(ByVal url As String, Optional ByVal PostData As String = "") As String
     HttpRequest = DoDownload(url, PostData <> "", PostData, True, "")
End Function

Public Function URLEncode(ByVal param As String) As String
    URLEncode = basWorld.EncodeURLParameter(param)
End Function

Public Function BoolToString(ByVal param As String) As Boolean
    param = LCase(Trim(param))
    If param = "on" Or param = "true" Or param = "yes" Then
        BoolToString = True
    ElseIf param = "off" Or param = "false" Or param = "no" Then
        BoolToString = False
    Else
        RaiseMiscError "Invalid value for boolean: " & param
    End If
End Function

Public Function Draw(ByVal YPos As Long, ByVal RGBVal As Long, Optional ByVal mode As String = "solid", Optional ByVal Segments As Long = 0)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If
    DrawSimple PrivConsoleID, YPos, RGBVal, mode, Segments
    Yield
End Function

Public Function DrawCustom(ByVal YPos As Long, ParamArray WidthsAndColors() As Variant)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    Dim XArr() As Variant, x As Long
    ReDim XArr(LBound(WidthsAndColors) To UBound(WidthsAndColors))
    For x = LBound(XArr) To UBound(XArr)
        XArr(x) = WidthsAndColors(x)
    Next
    DrawCustomA YPos, XArr
End Function

Public Function DrawCustomA(ByVal YPos As Long, WidthsAndColors As Variant)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    Dim x As Long, y As Long, z As Long
    Dim DrawSegs() As ConsoleDrawSegment
    x = (UBound(WidthsAndColors) - LBound(WidthsAndColors)) + 1
    ReDim DrawSegs(1 To ((x \ 2) + 1))
    y = LBound(WidthsAndColors)
    z = 0
    For x = 1 To (UBound(DrawSegs) - 1)
        DrawSegs(x).HPos = z
        DrawSegs(x).Color = WidthsAndColors(y + 1)
        If WidthsAndColors(y) > 1 Then
            z = z + WidthsAndColors(y)
        Else
            z = z + 1
        End If
        y = y + 2
    Next
    DrawSegs(UBound(DrawSegs)).Color = -1
    DrawSegs(UBound(DrawSegs)).HPos = z

    Console(PrivConsoleID, YPos * -1).Draw = DrawSegs
    CalculateConsoleDraw Console(PrivConsoleID, YPos * -1)
    Yield
    frmConsole.QueueConsoleRender
End Function

Public Function DrawEven(ByVal YPos As Long, ParamArray Colors() As Variant)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    Dim XArr() As Variant, x As Long
    ReDim XArr(LBound(Colors) To UBound(Colors))
    For x = LBound(XArr) To UBound(XArr)
        XArr(x) = Colors(x)
    Next
    DrawEvenA YPos, XArr
End Function

Public Function DrawEvenA(ByVal YPos As Long, Colors As Variant)
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    If YPos >= 0 Then
        Exit Function
    End If

    Dim x As Long, PieceWidth As Long
    Dim DrawSegs() As ConsoleDrawSegment
    ReDim DrawSegs(LBound(Colors) To (UBound(Colors) + 1))
    PieceWidth = (frmConsole.Width / (1 + (UBound(Colors) - LBound(Colors))))
    For x = LBound(Colors) To UBound(Colors)
        DrawSegs(x).HPos = PieceWidth * (x - LBound(DrawSegs))
        DrawSegs(x).Color = Colors(x)
    Next
    DrawSegs(UBound(DrawSegs)).Color = -1
    DrawSegs(UBound(DrawSegs)).HPos = frmConsole.Width
    Console(PrivConsoleID, YPos * -1).Draw = DrawSegs
    CalculateConsoleDraw Console(PrivConsoleID, YPos * -1)
    Yield
    frmConsole.QueueConsoleRender
End Function

Private Sub RaiseMiscError(ByVal Desc As String)
    Err.Raise vbObjectError + 9666, , Desc
End Sub

Public Function TextWidth(ByVal Text As String) As Long
    Dim DummyCLine As ConsoleLine
    DummyCLine = Parse_Console_Line(DummyCLine, Text)
    TextWidth = DummyCLine.TotalWidth
End Function

Public Function TextHeight(ByVal Text As String) As Long
    Dim DummyCLine As ConsoleLine
    DummyCLine = Parse_Console_Line(DummyCLine, Text)
    TextHeight = DummyCLine.Height
End Function

Public Function ConsoleWidth() As Long
    ConsoleWidth = (frmConsole.Width - (ConsoleXSpacing * 2))
End Function

Public Function PreSpaceWidth() As Long
    PreSpaceWidth = basConsole.PreSpaceWidth
End Function

Public Function FormatKB(ToConvert As Long) As String
    FormatKB = basGeneral.FormatKB(ToConvert)
End Function

Public Function FileExists(ByVal TheFile As String) As Boolean
    AssertLocalOnly

    FileExists = basGeneral.FileExists(ResolvePath(TheFile))
End Function

Public Function DirExists(ByVal TheDir As String) As Boolean
    AssertLocalOnly

    DirExists = basGeneral.DirExists(ResolvePath(TheDir))
End Function

Public Function Overwrite(ByVal file As String, ByVal Content As String)
    AssertLocalOnly

    basGeneral.WriteFile ResolvePath(file), Content
End Function

Public Function Append(ByVal file As String, ByVal Content As String)
    AssertLocalOnly

    AppendFile ResolvePath(file), Content
End Function

Public Function FileLen(ByVal file As String) As Long
    AssertLocalOnly

    FileLen = basGeneral.FileLen(ResolvePath(file))
End Function

Public Function Del(ByVal file As String)
    AssertLocalOnly

    Yield
    file = ResolvePath(file)
    Kill SafePath(file)
End Function

Public Function Copy(ByVal Source As String, ByVal Destination As String)
    AssertLocalOnly
    
    Yield
    Source = ResolvePath(Source)
    Destination = ResolvePath(Destination)
    
    FileCopy SafePath(Source), SafePath(Destination)
End Function

Public Function Rename(ByVal Source As String, ByVal Destination As String)
    AssertLocalOnly

    Move Source, Destination
End Function

Public Function Move(ByVal Source As String, ByVal Destination As String)
    AssertLocalOnly
    
    Yield
    Source = ResolvePath(Source)
    Destination = ResolvePath(Destination)

    Name SafePath(Source) As SafePath(Destination)
End Function

Public Function MD(ByVal NewDir As String)
    AssertLocalOnly

    Yield
    NewDir = ResolvePath(NewDir)

    MkDir SafePath(NewDir)
End Function

Public Function RD(ByVal OldDir As String)
    AssertLocalOnly

    Yield
    OldDir = ResolvePath(OldDir)

    RmDir SafePath(OldDir)
End Function

Public Function Cat(ByVal file As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertLocalOnly

    Cat = Display(file, StartLine, MaxLines)
End Function

Public Function Display(ByVal file As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertLocalOnly

    file = ResolvePath(file)

    If StartLine < 1 Then
        StartLine = 1
    End If

    Dim EndLine As Long
    EndLine = StartLine + MaxLines

    Dim CurLine As Long
    CurLine = 0

    Dim Content As String
    Display = ""

    Dim FF As Long
    FF = FreeFile
    Open SafePath(file) For Input As #FF
        While Not EOF(FF)
            CurLine = CurLine + 1
            
            If MaxLines > 0 And CurLine >= EndLine Then
                GoTo AbortPrintDisplayLoop
            End If

            Line Input #FF, Content
            If CurLine < StartLine Then
                GoTo DontPrintDisplay
            End If

            Display = Display & Content & vbCrLf
DontPrintDisplay:
        Wend
AbortPrintDisplayLoop:
    Close #FF
End Function

Public Function MUSIC(ByVal Command As String)
    AssertLocalOnly

    Yield
    MusicCommand Command
    Yield
End Function

Public Function MAIL()
    AssertLocalOnly

    Yield
    frmDSOMail.Show vbModal
    Yield
End Function

Public Function yDiv(ByVal setValue As Integer)
    Yield
    If PrivDisableOutput Then
        Exit Function
    End If

    SetYDiv setValue
End Function

Public Function PAUSE(Optional ByVal Prompt As String = "", Optional ByVal RGBVal As Long = -1)
    Yield
    If PrivDisableOutput Then
        Exit Function
    End If

    Dim propSpace As String
    If Not Has_Property_Space(Prompt) Then
        propSpace = "lblue 10 noprespace"
    Else
        propSpace = Get_Property_Space(Prompt)
    End If
    Prompt = Kill_Property_Space(Prompt)

    If Trim(Prompt) = "" Then
        Prompt = "Press any key to continue..."
    End If

    Prompt = "{{" & propSpace & "}}" & Prompt
    Say Prompt
    If RGBVal >= 0 Then
        Draw -1, RGBVal
    End If

    GetKey
End Function

Public Function LOGIN(Optional ByVal Silent As Boolean = False)
    AssertLocalOnly

    Dim PrintOutput As Boolean
    PrintOutput = (Not PrivDisableOutput) And (Not PrivRedirectOutput) And (Not Silent)

    While LoginInProgress
        Yield
    Wend

    If basWorld.Authorized = True Then
        If PrintOutput Then
            SayRaw ConsoleID, "You are already logged in and authorized as " & myUsername & ".{{green}}"
        End If
        Exit Function
    End If

    Dim isBad As Boolean
    isBad = False
    If myUsername = "" Then
        If PrintOutput Then
            SayRaw ConsoleID, "{{14, orange,  center}}Your username is not set - type: USERNAME = ""[username]"" to set it."
        End If
        isBad = True
    End If
    If myPassword = "" Then
        If PrintOutput Then
            SayRaw ConsoleID, "{{14, orange, center}}Your password is not set - type: PASSWORD = ""[password]"" to set it."
        End If
        isBad = True
    End If

    If isBad = True Then
        If PrintOutput Then
            SayRaw ConsoleID, "Warning - You are not logged in!{{16 center underline}}"
            SayRaw ConsoleID, "Once you have set your USERNAME and PASSWORD, type LOGIN.{{14 center}}"
        End If
        RaiseMiscError "Username and/or password not set"
    End If

    LoginInProgress = True
    SayCOMM "Logging in..."

    Dim ResIndex As String
    ResIndex = DoDownloadAPI("auth.php", True, "", "")
    Dim ResObj As clsHttpResponse
    Set ResObj = WaitFor_Internal(ResIndex, True)

    If ResObj.IsSuccess() Then
        OnLoginSuccess
        LoginInProgress = False
    Else
        OnLoginFailure
        LoginInProgress = False
        RaiseMiscError "Login failed"
    End If

    ResObj.RaiseForStatus

    Yield
End Function

Public Function LOGOUT()
    AssertLocalOnly

    basWorld.Authorized = False
    frmConsole.Shape1.BackColor = vbRed
    frmConsole.lblUsername.Caption = "You have been logged out."
    SayCOMM "You have been logged out."
    
    If frmConsole.getConnected Then
        frmConsole.Send "QUIT :darksignsonline.com, Dark Signs Online"    'send the quit message
        frmConsole.lstUsers.Clear  'clear the list entries
        frmConsole.Display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
        frmConsole.sockIRC.Close_   'close the connection
        frmConsole.setConnected False
    End If

    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function Stats() As String
    Yield
    Stats = DoDownloadAPI("get_user_stats.php", False, "", "")
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function Lookup(ByVal Domain As String) As String
    Yield
    Lookup = DoDownloadAPI("lookup.php?d=" & EncodeURLParameter(Domain), False, "", "")
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function GetDomain(ByVal IP As String) As String
    Yield
    GetDomain = DoDownloadAPI("domain_meta.php?getdomain=" & EncodeURLParameter(IP), False, "", "")
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function IsPortOpen(ByVal Domain As String, ByVal Port As Integer) As String
    Yield
    IsPortOpen = DoDownloadAPI("ping.php?domain=" & EncodeURLParameter(Domain) & "&port=" & EncodeURLParameter(Port), False, "", "bool_1")
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function IsDomainOnline(ByVal Domain As String) As String
    IsDomainOnline = IsPortOpen(Domain, 0)
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function GetIP(ByVal Domain As String) As String
    Yield
    GetIP = DoDownloadAPI("domain_meta.php?getip=" & EncodeURLParameter(Domain), False, "", "")
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function UploadStr(ByVal Domain As String, ByVal Port As Long, ByVal sFileData As String) As String
    AssertLocalOnly

    Yield

    Dim tempStrA As String
    If DSOIsScriptCompiled(sFileData) Then
        tempStrA = DSOCompileScript(sFileData, "dso://" & LCase(Domain) & ":" & Port)
    Else
        tempStrA = sFileData
    End If
    tempStrA = EncodeBase64Str(tempStrA)

    Dim PostData As String
    PostData = "port=" & EncodeURLParameter(Port) & _
    "&d=" & EncodeURLParameter(Domain) & _
    "&filedata=" & EncodeURLParameter(tempStrA)

    UploadStr = DoDownloadAPI("domain_upload.php", True, PostData, "")

    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function DownloadStr(ByVal Domain As String, ByVal Port As Long) As String
    AssertLocalOnly
    
    Yield

    Dim PostData As String
    PostData = "port=" & EncodeURLParameter(Port) & _
    "&d=" & EncodeURLParameter(Domain)

    DownloadStr = DoDownloadAPI("domain_download.php", True, PostData, "")

    If DSOIsScriptCompiled(DownloadStr) Then
        DownloadStr = ""
        Yield
        RaiseMiscError "Can not download compiled script from server"
        Exit Function
    End If

    Yield
End Function

Public Function Unregister(ByVal Domain As String)
    AssertLocalOnly
    
    Yield

    Dim DomainRequestIdx As String
    DomainRequestIdx = DoDownloadAPI("domain_unregister.php", True, "d=" & EncodeURLParameter(Domain), "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WaitFor_Internal(DomainRequestIdx)

    SayCOMM DomainRequest.RawResponse

    DomainRequest.RaiseForStatus

    Yield
End Function

Public Function Register(ByVal Domain As String)
    AssertLocalOnly

    Yield

    Dim DomainRequestIdx As String
    DomainRequestIdx = DoDownloadAPI("domain_register.php", True, "d=" & EncodeURLParameter(Domain), "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WaitFor_Internal(DomainRequestIdx)

    SayCOMM DomainRequest.RawResponse

    DomainRequest.RaiseForStatus

    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function RegisterPrices() As String
    AssertLocalOnly

    Yield
    RegisterPrices = DoDownloadAPI("domain_register.php?prices=true", False, "", "lines")
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function ClosePort(ByVal Domain As String, ByVal Port As Long) As String
    AssertLocalOnly

    Yield

    Dim PostData As String
    PostData = "port=" & EncodeURLParameter(Port) & _
    "&d=" & EncodeURLParameter(Domain)

    ClosePort = DoDownloadAPI("domain_close.php", True, PostData, "")

    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Private Function MyDomainsHelper(ByVal DomainType As String) As String
    Yield
    MyDomainsHelper = DoDownloadAPI("my_domains.php?type=" & EncodeURLParameter(DomainType), False, "", "lines")
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Private Function DomainFilesystemHelper(ByVal Domain As String, ByVal PostData As String, Optional ByVal ResponseType As String = "") As String
    Yield

    Dim IsLocalValue As String
    IsLocalValue = "false"
    If IsLocal() Then
        IsLocalValue = "true"
    End If
    
    PostData = "is_local_script=" & EncodeURLParameter(IsLocalValue) & _
                                        "&keycode=" & EncodeURLParameter(FileKey) & _
                                        "&d=" & EncodeURLParameter(Domain) & _
                                        "&" & PostData

    DomainFilesystemHelper = DoDownloadAPI("domain_filesystem.php", True, PostData, ResponseType)
    Yield
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function RemoteWrite(ByVal Domain As String, ByVal filename As String, ByVal Contents As String) As String
    AssertLocalOnly

    RemoteWrite = DomainFilesystemHelper(Domain, "write=" & EncodeURLParameter(filename) & "&filedata=" & EncodeURLParameter(Contents))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function RemoteAppend(ByVal Domain As String, ByVal filename As String, ByVal Contents As String) As String
    AssertLocalOnly

    RemoteAppend = DomainFilesystemHelper(Domain, "append=" & EncodeURLParameter(filename) & "&filedata=" & EncodeURLParameter(Contents))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function RemoteSafeAppend(ByVal Domain As String, ByVal filename As String, ByVal Line As String) As String
    AssertLocalOnly

    RemoteSafeAppend = DomainFilesystemHelper(Domain, "safeappend=" & EncodeURLParameter(filename) & "&filedata=" & EncodeURLParameter(Line))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function RemoteDelete(ByVal Domain As String, ByVal filename As String) As String
    AssertLocalOnly
    
    RemoteDelete = DomainFilesystemHelper(Domain, "delete=" & EncodeURLParameter(filename))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function RemoteDir(ByVal Domain As String) As String
    AssertLocalOnly
    
    RemoteDir = DomainFilesystemHelper(Domain, "dir=/", "lines")
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function RemoteView(ByVal Domain As String, ByVal filename As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertLocalOnly

    RemoteView = DomainFilesystemHelper(Domain, "fileserver=" & EncodeURLParameter(filename) & "&maxlines=" & EncodeURLParameter(MaxLines) & "&startline=" & EncodeURLParameter(StartLine))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function ServerWrite(ByVal filename As String, ByVal Contents As String) As String
    AssertRemoteOnly

    ServerWrite = DomainFilesystemHelper(ServerDomain, "write=" & EncodeURLParameter(filename) & "&filedata=" & EncodeURLParameter(Contents))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function ServerAppend(ByVal filename As String, ByVal Contents As String) As String
    AssertRemoteOnly

    ServerAppend = DomainFilesystemHelper(ServerDomain, "append=" & EncodeURLParameter(filename) & "&filedata=" & EncodeURLParameter(Contents))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function ServerSafeAppend(ByVal filename As String, ByVal Line As String) As String
    AssertRemoteOnly

    ServerSafeAppend = DomainFilesystemHelper(ServerDomain, "safeappend=" & EncodeURLParameter(filename) & "&filedata=" & EncodeURLParameter(Line))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function ServerDelete(ByVal filename As String) As String
    AssertRemoteOnly
    
    ServerDelete = DomainFilesystemHelper(ServerDomain, "delete=" & EncodeURLParameter(filename))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function ServerDir() As String
    AssertRemoteOnly

    ServerDir = DomainFilesystemHelper(ServerDomain, "dir=/", "lines")
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function ServerView(ByVal filename As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertRemoteOnly
    
    ServerView = DomainFilesystemHelper(ServerDomain, "fileserver=" & EncodeURLParameter(filename) & "&maxlines=" & EncodeURLParameter(MaxLines) & "&startline=" & EncodeURLParameter(StartLine))
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function FileServer(ByVal filename As String, Optional ByVal StartLine As Long = 0, Optional ByVal MaxLines As Long = 0) As String
    AssertRemoteOnly

    FileServer = ServerView(filename, StartLine, MaxLines)
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function MyDomains() As String
    AssertLocalOnly

    MyDomains = MyDomainsHelper("domain")
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function MySubdomains() As String
    AssertLocalOnly

    MySubdomains = MyDomainsHelper("subdomain")
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function MyIPs() As String
    AssertLocalOnly

    MyIPs = MyDomainsHelper("ip")
End Function

' VBTYPE: _RETURN=HTTPRequest
Public Function Transfer(ByVal Target As String, ByVal Amount As Long, ByVal Description As String) As String
    Yield

    Target = Trim(Target)
    Description = Trim(Description)

    If Amount < 1 Then
        RaiseMiscError "Invalid amount: $" & Amount & ".00!"
        Exit Function
    End If
    
    AuthorizePayment = False
    frmPayment.lAmount = "$" & Amount & ".00"
    frmPayment.lDescription = Description
    frmPayment.lTo = Target

    Yield
    frmPayment.Show vbModal
    Yield

    If AuthorizePayment = False Then
        RaiseMiscError "Payment declined by user"
        Exit Function
    End If

    SayCOMM "Processing Payment..."

    Yield

    Dim PostData As String
    PostData = "to=" & EncodeURLParameter(Target) & _
                "&amount=" & EncodeURLParameter(Amount) & _
                "&description=" & EncodeURLParameter(Description)

    Transfer = DoDownloadAPI("transfer.php", False, "", "")

    'SayCOMM "Paymenmt result was " & TransferRequest.Response
End Function

Public Function Wait(ByVal Milliseconds As Long)
    Dim EndTime As Long
    EndTime = GetTickCount() + Milliseconds
    
    While GetTickCount() < EndTime
        Yield
    Wend
End Function

Public Function Clear()
    If PrivDisableOutput Then
        Yield
        Exit Function
    End If

    ClearConsole PrivConsoleID
    Yield
End Function

Public Function ArgC() As Long
    Yield
    ArgC = UBound(PrivParameters)
End Function

Public Function ArgV(ByVal Number As Long) As Variant
    Yield
    If Number < LBound(PrivParameters) Or Number > UBound(PrivParameters) Then
        ArgV = ""
        Exit Function
    End If
    ArgV = PrivParameters(Number)
End Function

Private Function YieldSafe() As Boolean
    YieldSafe = True

    If CancelScript(PrivConsoleID) Or Aborted Then
        Aborted = True
        YieldSafe = False
        Exit Function
    End If

    DoEvents
End Function

Public Function Yield()
    If Not YieldSafe() Then
        Err.Raise vbObjectError + 9001, , "Script canceled"
    End If
End Function


' RUN CODE FROM FILE

' VBTYPE: XArr=Variant()
Private Function RawRunCaptureA(ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal Script As String, Optional XArr As Variant) As String
    AssertLocalOnly

    Dim x As Long, ResolvedScript As String
    
    Dim SParamArr() As Variant

    If (VarType(XArr) And vbArray) = vbArray Then
        ReDim SParamArr(0 To UBound(XArr) + 1)
        For x = 0 To UBound(XArr)
            SParamArr(x + 1) = XArr(x)
        Next
    Else
        ReDim SParamArr(0 To 0)
    End If

    ResolvedScript = basCommands.ResolveCommand(PrivConsoleID, Script)
    SParamArr(0) = ResolvedScript
    Yield
    If ResolvedScript = "" Then
        RaiseMiscError "Could not find script to run for command """ & Script & """"
        Exit Function
    End If
    RawRunCaptureA = Run_Script(ResolvedScript, PrivConsoleID, SParamArr, RedirectOutput, DisableOutput, "", PrivSpoofedLocalConnectingIP)
    Yield
End Function

' VBTYPE: XArr=Variant()
Public Function CaptureA(ByVal Script As String, Optional XArr As Variant) As String
    CaptureA = RawRunCaptureA(True, True, Script, XArr)
End Function

Public Function Capture(ParamArray XArr() As Variant) As String
    If UBound(XArr) < 0 Then
        RaiseMiscError "Capture needs at least one parameter (the script)"
    End If

    Dim Script As String
    Script = XArr(0)
    If UBound(XArr) = 0 Then
        Capture = CaptureA(Script)
        Exit Function
    End If

    Dim x As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For x = 0 To UBound(SParamArr)
        SParamArr(x) = XArr(x + 1)
    Next
    Capture = CaptureA(Script, SParamArr)
End Function

' VBTYPE: XArr=Variant()
Public Function RunA(ByVal Script As String, Optional XArr As Variant)
    AssertLocalOnly
    
    Dim Output As String
    Output = RawRunCaptureA(PrivDisableOutput And PrivRedirectOutput, PrivDisableOutput, Script, XArr)
    If PrivDisableOutput And PrivRedirectOutput Then
        Say Output
    End If
End Function

Public Function Include(ByVal Script As String)
    AssertLocalOnly

    Script = ResolvePath(Script)
    Dim ScriptData As String
    ScriptData = GetFile(Script)
    IncludeCode_Internal ScriptData, Script
End Function

' This allows remote/domain calls on purpose!
Public Function DLOpen(ByVal Library As String)
    If LCase(Trim(Library)) = "termlib" Then
        If PrivTermlibObject Is Nothing Then
            Set PrivTermlibObject = New clsScriptTermlib
            PrivTermlibObject.SetGSF Me
            SControl.AddObject "termlib", PrivTermlibObject, True
        End If
        Exit Function
    End If

    If InStr(Library, "/") > 0 Or InStr(Library, "\") > 0 Then
        Exit Function
    End If

    Dim SData As String
    SData = GetFile("/system/libs/" & Library & ".ds")
    IncludeCode_Internal SData, "dlopen://by-name/" & Library
End Function

Public Function Run(ParamArray XArr() As Variant)
    If UBound(XArr) < 0 Then
        RaiseMiscError "Run needs at least one parameter (the script)"
    End If

    Dim Script As String
    Script = XArr(0)

    If UBound(XArr) = 0 Then
        RunA Script
        Exit Function
    End If

    Dim x As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For x = 0 To UBound(SParamArr)
        SParamArr(x) = XArr(x + 1)
    Next
    
    RunA Script, SParamArr
End Function

' IRC

Public Function ChatSend(ByVal Msg As String)
    AssertLocalOnly

    Yield
    frmConsole.ChatSend Msg
End Function

Public Function ChatView(ByVal Enabled As Boolean)
    AssertLocalOnly

    Yield
    frmConsole.ChatView Enabled
End Function

' RUN CODE FROM STRING

' VBTYPE: XArr=Variant()
Private Function RawRunCaptureCodeA(ByVal RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal Code As String, Optional XArr As Variant) As String
    Dim x As Long
    
    Dim SParamArr() As Variant

    If (VarType(XArr) And vbArray) = vbArray Then
        ReDim SParamArr(0 To UBound(XArr) + 1)
        For x = 0 To UBound(XArr)
            SParamArr(x + 1) = XArr(x)
        Next
    Else
        ReDim SParamArr(0 To 0)
    End If

    SParamArr(0) = "sys://mem"
    Yield
    RawRunCaptureCodeA = Run_Script_Code(Code, PrivConsoleID, SParamArr, FileKey, PrivServerDomain, PrivServerPort, PrivServerIP, PrivServerConnectingIP, RedirectOutput, DisableOutput, "", "local")
    Yield
End Function

' VBTYPE: XArr=Variant()
Public Function CaptureCodeA(ByVal Code As String, Optional XArr As Variant) As String
    CaptureCodeA = RawRunCaptureCodeA(True, True, Code, XArr)
End Function

Public Function CaptureCode(ParamArray XArr() As Variant) As String
    If UBound(XArr) < 0 Then
        RaiseMiscError "CaptureCode needs at least one parameter (the code)"
    End If

    Dim Script As String
    Script = XArr(0)
    If UBound(XArr) = 0 Then
        CaptureCode = CaptureCodeA(Script)
        Exit Function
    End If

    Dim x As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For x = 0 To UBound(SParamArr)
        SParamArr(x) = XArr(x + 1)
    Next
    CaptureCode = CaptureCodeA(Script, SParamArr)
End Function

' VBTYPE: XArr=Variant()
Public Function RunCodeA(ByVal Code As String, Optional XArr As Variant)
    Dim Output As String
    Output = RawRunCaptureCodeA(PrivDisableOutput And PrivRedirectOutput, PrivDisableOutput, Code, XArr)
    If PrivDisableOutput And PrivRedirectOutput Then
        Say Output
    End If
End Function

Public Function RunCode(ParamArray XArr() As Variant)
    If UBound(XArr) < 0 Then
        RaiseMiscError "RunCode needs at least one parameter (the code)"
    End If

    Dim Script As String
    Script = XArr(0)
    If UBound(XArr) = 0 Then
        RunCodeA Script
        Exit Function
    End If

    Dim x As Long
    Dim SParamArr() As Variant
    ReDim SParamArr(0 To UBound(XArr) - 1)
    For x = 0 To UBound(SParamArr)
        SParamArr(x) = XArr(x + 1)
    Next
    RunCodeA Script, SParamArr
End Function

Private Sub IncludeCode_Internal(ByVal Code As String, ByVal SegName As String)
    Dim CodeFaulted As Boolean, ErrNumber As Long, ErrDescription As String
    CodeFaulted = False

    On Error GoTo OnCodeFaulted
    Code = DSODecryptScript(Code, "")
    If CodeFaulted Then
        ErrDescription = "[DECODE " & SegName & "] " & ErrDescription
        GoTo SkipScriptInclusion
    End If
    Code = ParseCommandLineOptional(Code, PrivConsoleID, IsLocal())
    If CodeFaulted Then
        ErrDescription = "[PARSE " & SegName & "] " & ErrDescription
        GoTo SkipScriptInclusion
    End If
    SControl.AddCode Code
    If CodeFaulted Then
        ErrDescription = "[RUN " & SegName & "] " & ErrDescription
        GoTo SkipScriptInclusion
    End If
SkipScriptInclusion:
    On Error GoTo 0
    If CodeFaulted Then
        Err.Raise ErrNumber, , ErrDescription
    End If
    Exit Sub

OnCodeFaulted:
    CodeFaulted = True
    ErrNumber = Err.Number
    ErrDescription = Err.Description
    Resume Next
End Sub

Public Function IncludeCode(ByVal Code As String)
    IncludeCode_Internal Code, "sys://mem"
End Function

' RUN CODE FROM DSO DOMAIN

' VBTYPE: _RETURN=HTTPRequest
Public Function Fetch(ParamArray Params() As Variant) As String
    If UBound(Params) < 1 Then
        RaiseMiscError "Fetch needs at least two parameters (domain and port)"
    End If

    Dim Domain As String
    Dim Port As Long
    Domain = Params(0)
    Port = Params(1)
    If UBound(Params) <= 1 Then
        Fetch = ConnectRaw(False, True, True, Domain, Port)
        Exit Function
    End If

    Dim DParams() As Variant
    ReDim DParams(0 To UBound(Params) - 2)
    Dim x As Long
    For x = 0 To UBound(DParams)
        DParams(x) = Params(x + 2)
    Next
    Fetch = ConnectRaw(False, True, True, Domain, Port, DParams)
End Function

' VBTYPE: XArr=Variant()
' VBTYPE: _RETURN=HTTPRequest
Public Function FetchA(ByVal Domain As String, ByVal Port As Long, Optional XArr As Variant) As String
    FetchA = ConnectRaw(False, True, True, Domain, Port, XArr)
End Function

Public Function Connect(ParamArray Params() As Variant)
    If UBound(Params) < 1 Then
        RaiseMiscError "Connect needs at least two parameters (domain and port)"
    End If

    Dim Res As String

    Dim Domain As String
    Dim Port As Long
    Domain = Params(0)
    Port = Params(1)
    If UBound(Params) <= 1 Then
        Res = ConnectRaw(True, PrivRedirectOutput And PrivDisableOutput, PrivDisableOutput, Domain, Port)
        GoTo HandleRes
    End If

    Dim DParams() As Variant
    ReDim DParams(0 To UBound(Params) - 2)
    Dim x As Long
    For x = 0 To UBound(DParams)
        DParams(x) = Params(x + 2)
    Next

    Res = ConnectRaw(True, PrivRedirectOutput And PrivDisableOutput, PrivDisableOutput, Domain, Port, DParams)
HandleRes:
    If PrivRedirectOutput And PrivDisableOutput Then
        Say Res
    End If
End Function

' VBTYPE: XArr=Variant()
Public Function ConnectA(ByVal Domain As String, ByVal Port As Long, Optional XArr As Variant)
    Dim Res As String
    Res = ConnectRaw(True, PrivRedirectOutput And PrivDisableOutput, PrivDisableOutput, Domain, Port, XArr)
    If PrivRedirectOutput And PrivDisableOutput Then
        Say Res
    End If
End Function

' VBTYPE: _RETURN=HTTPRequest
Private Function ConnectRaw(ByVal Verbose As Boolean, RedirectOutput As Boolean, ByVal DisableOutput As Boolean, ByVal Domain As String, ByVal Port As Long, Optional Params As Variant) As String
    Yield
    If Port < 1 Or Port > 65535 Then
        Err.Raise vbObjectError + 9999, , "Invalid Port Number: " & Port
        Exit Function
    End If

    If Verbose Then
        Say "{{green}}Connecting to " & UCase(Domain) & ":" & Port & "..."
    End If

    Dim x As Long
    Dim DomainConnectParams() As Variant
    If (VarType(Params) And vbArray) = vbArray Then
        ReDim DomainConnectParams(0 To UBound(Params) + 1)
        For x = 1 To UBound(DomainConnectParams)
            DomainConnectParams(x) = Params(x - 1)
        Next
    Else
        ReDim DomainConnectParams(0 To 0)
    End If

    Dim DomainRequestIdx As String
    DomainRequestIdx = DoDownloadAPI("domain_connect.php?d=" & EncodeURLParameter(Domain) & _
            "&port=" & EncodeURLParameter(Port), True, "", "")
    Dim DomainRequest As clsHttpResponse
    Set DomainRequest = WaitFor_Internal(DomainRequestIdx)

    Select Case DomainRequest.Code
        Case 404:
            RaiseMiscError "Could not connect to" & UCase(Domain) & ":" & Port & " -> Not found"
        Case 403:
            RaiseMiscError "Could not connect to" & UCase(Domain) & ":" & Port & " -> Access denied"
        Case Else:
            DomainRequest.RaiseForStatus
    End Select

    Dim DomainSplit() As String
    DomainSplit = Split(DomainRequest.Response, ":-:")
    ' 0 = domain
    ' 1 = port
    ' 2 = ip
    ' 3 = owner
    ' 4 = filekey
    ' 5 = code

    Dim strDomain As String
    strDomain = DomainSplit(0)
    Dim strPort As Long
    strPort = Val(DomainSplit(1))
    If strPort <= 0 Then
        strPort = 99999
    End If
    Dim strIP As String
    strIP = DomainSplit(2)
    Dim strOwner As String
    strOwner = DomainSplit(3)
    Dim strFileKey As String
    strFileKey = DomainSplit(4)

    If strOwner = "" Then
        strOwner = "unknown"
    End If

    Dim strCode As String
    strCode = DecodeBase64Str(DomainSplit(5))

    Dim DomScript As String
    DomScript = "dso://" & LCase(strDomain) & ":" & strPort
    Dim ScriptKey As String
    ScriptKey = DomScript
    If Not DSOCheckScriptKey(strCode, ScriptKey) Then
        ScriptKey = "dso://" & LCase(strIP) & ":" & strPort
    End If
    DomainConnectParams(0) = DomScript
    ConnectRaw = Run_Script_Code(strCode, ConsoleID, DomainConnectParams, strFileKey, strDomain, strPort, strIP, PrivServerIP, RedirectOutput, DisableOutput, ScriptKey, strOwner)

    Yield
End Function

Public Function CompileStr(ByVal Source As String, Optional ByVal FileKey As String = "") As String
    CompileStr = DSOCompileScript(Source, FileKey)
End Function

' Encoding helpers

' VBTYPE: XArr=Byte()
Public Function EncodeBase64Bytes(XArr As Variant) As String
    Dim typedArrData() As Byte
    Dim x As Long

    ReDim typedArrData(LBound(XArr) To UBound(XArr))
    For x = LBound(XArr) To UBound(XArr)
        typedArrData(x) = XArr(x)
    Next
    EncodeBase64Bytes = basConsole.EncodeBase64Bytes(typedArrData)
End Function

Public Function EncodeBase64Str(ByVal strData As String) As String
    EncodeBase64Str = basConsole.EncodeBase64Str(strData)
End Function

' VBTYPE: _RETURN=Byte()
Public Function DecodeBase64Bytes(ByVal strData As String) As Variant()
    Dim Res() As Byte
    Dim ResVar() As Variant
    Dim x As Long

    Res = basConsole.DecodeBase64Bytes(strData)
    ReDim ResVar(LBound(Res) To UBound(Res))
    For x = LBound(Res) To UBound(Res)
        ResVar(x) = Res(x)
    Next
    DecodeBase64Bytes = ResVar
End Function

Public Function DecodeBase64Str(ByVal strData As String) As String
    DecodeBase64Str = basConsole.DecodeBase64Str(strData)
End Function

Private Function WriteINI_Internal(ByVal file As String, ByVal Section As String, ByVal key As String, ByVal value As String)
    Yield
    WritePrivateProfileString Section, key, value, SafePath(file)
    Yield
End Function

Private Function ReadINI_Internal(ByVal file As String, ByVal Section As String, ByVal key As String) As String
    Yield
    Dim Result As String * 4096
    Dim ResultLen As Long
    ResultLen = GetPrivateProfileString(Section, key, "", Result, 4096, SafePath(file))
    ReadINI_Internal = Left(Result, ResultLen)
    Yield
End Function

Public Function WriteINI(ByVal file As String, ByVal Section As String, ByVal key As String, ByVal value As String)
    AssertLocalOnly

    WriteINI_Internal ResolvePath(file), Section, key, value
End Function

Public Function ReadINI(ByVal file As String, ByVal Section As String, ByVal key As String, ByVal value As String) As String
    AssertLocalOnly

    ReadINI = ReadINI_Internal(ResolvePath(file), Section, key)
End Function

Public Function GetMissionFile(ByVal MissionID As String)
    MissionID = Replace(MissionID, "/", "_")
    MissionID = Replace(MissionID, "\", "_")

    GetMissionFile = "/system/missions/" & PrivScriptOwner & "_" & MissionID & ".ini"
End Function

Public Function GetMissionData(ByVal MissionID As String, ByVal Section As String, ByVal key As String) As String
    GetMissionData = ReadINI_Internal(GetMissionFile(MissionID), Section, key)
End Function

Public Function SetMissionData(ByVal MissionID As String, ByVal Section As String, ByVal key As String, ByVal value As String) As String
    WriteINI_Internal GetMissionFile(MissionID), Section, key, value
End Function

Public Function TrimWithNewline(ByVal InputStr As String) As String
    TrimWithNewline = basGeneral.TrimWithNewline(InputStr)
End Function

Public Function RequestReadFile() As String
    Yield
    If PrivServerPort > 0 Then
        Say "{{orange}}Server at " & PrivServerDomain & ":" & PrivServerPort & " is requesting to receive a file"
    Else
        Say "{{orange}}Local script is requesting to receive a file"
    End If

    While True
        Dim filename As String
        filename = Trim(ReadLine("Filename (empty to cancel)?"))
        If filename = "" Then
            RaiseMiscError "User cancelled file request"
            Exit Function
        End If
        filename = ResolvePath(filename)
        If Not basGeneral.FileExists(filename) Then
            Say "{{red}}File not found. Please choose an existing file."
        Else
            RequestReadFile = basGeneral.GetFile(filename)
            Exit Function
        End If
    Wend
End Function

Public Function RequestWriteFile(ByVal Data As String)
    Yield
    If PrivServerPort > 0 Then
        Say "{{orange}}Server at " & PrivServerDomain & ":" & PrivServerPort & " is requesting to send a file"
    Else
        Say "{{orange}}Local script is requesting to send a file"
    End If

    While True
        Dim filename As String
        filename = Trim(ReadLine("Filename (empty to cancel)?"))
        If filename = "" Then
            RaiseMiscError "User cancelled file request"
            Exit Function
        End If
        filename = ResolvePath(filename)
        If basGeneral.FileExists(filename) Then
            Say "{{red}}File already exists. Please choose a different filename."
        Else
            basGeneral.WriteFile filename, Data
            Exit Function
        End If
    Wend
End Function

Public Function SHA256(ByVal Data As String) As String
    SHA256 = basScriptCrypto.SHA256.SHA256string(Data)
End Function

' VBTYPE: XArr=Long()
Public Function RGBJoin(ByVal XArr As Variant) As Long
    RGBJoin = RGB(XArr(0), XArr(1), XArr(2))
End Function

' VBTYPE: _RETURN=Long()
Public Function RGBSplit(ByVal lColor As Long) As Variant()
    Dim Ret() As Variant
    ReDim Ret(0 To 2)
    Ret(0) = lColor And &HFF ' mask the low byte
    Ret(1) = (lColor And &HFF00&) \ &H100 ' mask the 2nd byte and shift it to the low byte
    Ret(2) = (lColor And &HFF0000) \ &H10000 ' mask the 3rd byte and shift it to the low byte
    RGBSplit = Ret
End Function

Public Function Encrypt(ByVal Data As String, ByVal Password As String, Optional ByVal NoWrap As Boolean = False) As String
    Encrypt = DSOEncrypt(Data, "dsoscript_" & Password, NoWrap)
End Function

Public Function Decrypt(ByVal Data As String, ByVal Password As String) As String
    Decrypt = DSODecrypt(Data, "dsoscript_" & Password)
End Function

Public Function SpoofLocalConnectingIP(ByVal NewValue As String)
    If Not IsLocal() Then
        Exit Function
    End If

    If NewValue = "" Then
        NewValue = PrivServerConnectingIP
    End If
    PrivSpoofedLocalConnectingIP = NewValue
End Function

Public Function SendMailToUser(ByVal sFrom As String, ByVal sSubject As String, ByVal sMessage As String)
    Dim ReqIdx As String
    ReqIdx = DoDownloadAPI("dsmail.php", True, "action=script_send_to_self" & _
                                                "&server=" & EncodeURLParameter(PrivServerIP) & _
                                                "&from=" & EncodeURLParameter(sFrom) & _
                                                "&subject=" & EncodeURLParameter(sSubject) & _
                                                "&message=" & EncodeURLParameter(sMessage), "")
    WaitFor ReqIdx
    SayCOMM "You got a new DSMail from " & sFrom
End Function

Public Function ConsoleEscape(ByVal tmpS As String) As String
    ConsoleEscape = basCommands.ConsoleEscape(tmpS)
End Function
 
Public Function ConsoleUnescape(ByVal tmpS As String) As String
    ConsoleUnescape = Replace(tmpS, ConsoleInvisibleChar, "")
End Function

Public Function IsHex(ByVal HASH As String) As Boolean
    Dim Chr0 As Integer, Chr9 As Integer, ChrA As Integer, ChrF As Integer
    Chr0 = Asc("0")
    Chr9 = Asc("9")
    ChrA = Asc("A")
    ChrF = Asc("F")

    Dim x As Long
    HASH = UCase(HASH)
    For x = 1 To Len(HASH)
        Dim c As Integer
        c = Asc(Mid(HASH, x, 1))
        If c >= Chr0 And c <= Chr9 Then
        ElseIf c >= ChrA And c <= ChrF Then
        Else
            IsHex = False
            Exit Function
        End If
    Next
    IsHex = True
End Function

Public Function DLOpenHash(ByVal HASH As String)
    If Not IsHex(HASH) Then
        RaiseMiscError "Invalid hash"
        Exit Function
    End If
    HASH = LCase(HASH)
    Dim FName As String
    FName = "/system/libs/hash_" & HASH & ".ds"
    
    Dim FData As String
    FData = ""
    On Error Resume Next
    FData = GetFile(FName)
    On Error GoTo 0
    If SHA256(FData) <> HASH Then
        On Error Resume Next
        Kill SafePath(FName)
        On Error GoTo 0
        
        Dim DomReq As String
        DomReq = DoDownloadAPI("libraries.php", True, "get=" & URLEncode(HASH), "")
        FData = WaitFor(DomReq)
        If SHA256(FData) <> HASH Then
            RaiseMiscError "Could not download hash library correctly :("
        End If
        WriteFile FName, FData
    End If
    
    Yield

    IncludeCode_Internal FData, "dlopen://by-hash/" & HASH
End Function

Public Function DLPutHash(ByVal HASH As String, ByVal Data As String)
    AssertLocalOnly

    If Not IsHex(HASH) Then
        RaiseMiscError "Invalid hash"
        Exit Function
    End If
    HASH = LCase(HASH)
    
    Dim DomReq As String
    DomReq = DoDownloadAPI("libraries.php", True, "put=" & URLEncode(HASH) & "&data=" & URLEncode(Data), "")
    WaitFor DomReq
End Function

 
' TODO: Synchronize mission from server first time it is read or written after client launch
' TODO: Synchronize mission to server whenever it is written (after the potential read from the server)
' maybe use client launch time VS file modify time?

