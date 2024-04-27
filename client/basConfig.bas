Attribute VB_Name = "basConfig"
Option Explicit

Private Type ConfigSetting
    name As String
    value As String
End Type
Private ConfigSettingsCache() As ConfigSetting

Private Declare Function GetPrivateProfileString Lib "kernel32" Alias "GetPrivateProfileStringA" (ByVal lpApplicationName As String, ByVal lpKeyName As Any, ByVal lpDefault As String, ByVal lpReturnedString As String, ByVal nSize As Long, ByVal lpFileName As String) As Long
Private Declare Function WritePrivateProfileString Lib "kernel32" Alias "WritePrivateProfileStringA" (ByVal lpApplicationName As String, ByVal lpKeyName As Any, ByVal lpString As Any, ByVal lpFileName As String) As Long

Private Sub EnsureConfigCacheIntact()
    On Error GoTo RedimConfigCache
    Dim X As Long
    X = UBound(ConfigSettingsCache)
    On Error GoTo 0
    If X >= 0 Then
        Exit Sub
    End If
RedimConfigCache:
    ReDim ConfigSettingsCache(0 To 0)
    ConfigSettingsCache(0).name = ""
    ConfigSettingsCache(0).value = ""
End Sub

Private Function FindConfigCacheSetting(ByVal sCat As String) As Long
    FindConfigCacheSetting = 0

    EnsureConfigCacheIntact
    If UBound(ConfigSettingsCache) <= 0 Then
        Exit Function
    End If

    Dim X As Long
    For X = 1 To UBound(ConfigSettingsCache)
        If ConfigSettingsCache(X).name = sCat Then
            FindConfigCacheSetting = X
            Exit Function
        End If
    Next
End Function

Public Sub ConfigSave(ByVal sCat As String, ByVal sVal As String, ByVal Encoded As Boolean)
    Dim X As Long
    X = FindConfigCacheSetting(sCat)
    If X <= 0 Then
        If UBound(ConfigSettingsCache) > 1024 Then
            Err.Raise vbObjectError + 9199, , "FATAL ERROR: Ran out of settings cache of size 1024 saving: " & sCat
        End If
        ReDim Preserve ConfigSettingsCache(0 To UBound(ConfigSettingsCache) + 1)
        X = UBound(ConfigSettingsCache)
    End If
    
    Dim sValEnc As String
    If Encoded Then
        sValEnc = EncodeBase64Str(sVal)
    Else
        sValEnc = sVal
    End If
    WritePrivateProfileString "config", sCat, sValEnc, App.Path & "/dso.ini"

    Dim NewSettings As ConfigSetting
    NewSettings.name = sCat
    NewSettings.value = sVal
    ConfigSettingsCache(X) = NewSettings
End Sub

Public Function ConfigLoad(ByVal sCat As String, ByVal sDefault As String, ByVal Encoded As Boolean) As String
    Dim X As Long
    X = FindConfigCacheSetting(sCat)
    If X > 0 Then
        ConfigLoad = ConfigSettingsCache(X).value
        Exit Function
    End If

NoSuchItem:
    Dim Result As String * 4096
    Dim ResultLen As Long
    
    If Encoded Then
        sDefault = EncodeBase64Str(sDefault)
    End If
    ResultLen = GetPrivateProfileString("config", sCat, sDefault, Result, 4096, App.Path & "/dso.ini")
    ConfigLoad = Left(Result, ResultLen)
    If Encoded Then
        ConfigLoad = DecodeBase64Str(ConfigLoad)
    End If

    If UBound(ConfigSettingsCache) > 1024 Then
        Err.Raise vbObjectError + 9199, , "FATAL ERROR: Ran out of settings cache of size 1024 loading: " & sCat
    End If
    ReDim Preserve ConfigSettingsCache(0 To UBound(ConfigSettingsCache) + 1)
    X = UBound(ConfigSettingsCache)
    Dim NewSettings As ConfigSetting
    NewSettings.name = sCat
    NewSettings.value = ConfigLoad
    ConfigSettingsCache(X) = NewSettings
End Function
