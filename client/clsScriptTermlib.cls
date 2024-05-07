VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "clsScriptTermlib"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

Private IsConf As Boolean
Private GSF As clsScriptFunctions

' VBNODOC
Public Sub SetGSF(NewGSF As clsScriptFunctions)
    If IsConf Then
        Exit Sub
    End If
    Set GSF = NewGSF
    IsConf = True
End Sub

Private Sub Class_Initialize()
    IsConf = False
End Sub

Public Property Get TwipsPerPixelX() As Long
    TwipsPerPixelX = Screen.TwipsPerPixelX
End Property

Public Property Get TwipsPerPixelY() As Long
    TwipsPerPixelY = Screen.TwipsPerPixelY
End Property

' Just like "Say", except you can pass a background color for the line
Public Sub SayWithBGColor(ByVal RGBVal As Long, ByVal Str As String)
    GSF.Say Str
    GSF.Draw -1, RGBVal, "solid"
End Sub

Public Sub SaySlowWithBGColor(ByVal RGBVal As Long, ByVal Delay As Long, ByVal Str As String, ByVal Style As String)
    If GSF.IsOutputDisabled Then
        GSF.Say Str & Style
        Exit Sub
    End If

    Dim X As Long
    Style = "{{" & Replace(Replace(Style, "{", ""), "}", "") & "}}"
    GSF.Say Left(Str, 1) & Style
    If RGBVal >= 0 Then
        GSF.Draw -1, RGBVal, "solid"
    End If
    For X = 2 To Len(Str)
        If Mid(Str, X, 1) = ConsoleInvisibleChar Then
            X = X + 1
        End If
        GSF.Wait Delay
        GSF.SayLine Mid(Str, 1, X), -1
        If RGBVal >= 0 Then
            GSF.Draw -1, RGBVal, "solid"
        End If
    Next
End Sub

Public Sub SaySlow(ByVal Delay As Long, ByVal Str As String, ByVal Style As String)
    SaySlowWithBGColor -1, Delay, Str, Style
End Sub

Public Function GetAsciiWithCPromptBG(ByVal RGBVal As Long, ByVal Prompt As String) As Long
    GSF.Say "{{noprespace}}" & Prompt & "> [_]"
    If RGBVal >= 0 Then
        GSF.Draw -1, RGBVal, "solid"
    End If
    Dim Choice As Long
    Choice = GSF.GetASCII()
    GSF.SayLine "{{noprespace}}" & Prompt & "> [" & Chr(Choice) & "]", -1
    If RGBVal >= 0 Then
        GSF.Draw -1, RGBVal, "solid"
    End If
    GetAsciiWithCPromptBG = Choice
End Function

Public Function GetAsciiWithCPrompt(ByVal Prompt As String) As Long
    GetAsciiWithCPrompt = GetAsciiWithCPromptBG(-1, Prompt)
End Function

Public Function GetAsciiWithPrompt() As Long
    GetAsciiWithPrompt = GetAsciiWithCPrompt("")
End Function

Public Sub SetMissionProgress(ByVal MissionID As String, ByVal key As String, ByVal value As String)
    GSF.SetMissionData MissionID, "progress", key, value
End Sub

Public Function GetMissionProgress(ByVal MissionID As String, ByVal key As String) As String
    GetMissionProgress = GSF.GetMissionData(MissionID, "progress", key)
End Function

Public Function IntMissionProgress(ByVal MissionID As String, ByVal key As String) As Long
    Dim Val As String
    Val = GetMissionProgress(MissionID, key)
    If Val = "" Then
        IntMissionProgress = 0
    Else
        IntMissionProgress = CInt(Val)
    End If
End Function

Public Sub IncMissionProgress(ByVal MissionID As String, ByVal key As String)
    Dim Val As String
    Val = IntMissionProgress(MissionID, key)
    SetMissionProgress MissionID, key, (Val + 1)
End Sub

Public Function BoolMissionProgress(ByVal MissionID As String, ByVal key As String) As Boolean
    BoolMissionProgress = (GetMissionProgress(MissionID, key) = "1")
End Function

Public Sub BoolSetMissionProgress(ByVal MissionID As String, ByVal key As String)
    SetMissionProgress MissionID, key, "1"
End Sub

Public Sub BoolClearMissionProgress(ByVal MissionID As String, ByVal key As String)
    SetMissionProgress MissionID, key, "0"
End Sub

Public Function QReadLine(ByVal Prompt As String) As String
    QReadLine = LCase(Trim(GSF.ReadLine(Prompt)))
End Function

Public Function QReadLineBG(ByVal RGBVal As Long, ByVal Prompt As String) As String
    QReadLineBG = LCase(Trim(GSF.ReadLine(Prompt, RGBVal)))
End Function
