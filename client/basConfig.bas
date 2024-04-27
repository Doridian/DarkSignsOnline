Attribute VB_Name = "basConfig"
Option Explicit

Private Type ConfigSetting
    name As String
    value As String
End Type
Private ConfigSettingsCache() As ConfigSetting

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

Public Sub ConfigSave(ByVal sCat As String, ByVal sVal As String)
    Dim X As Long
    X = FindConfigCacheSetting(sCat)
    If X <= 0 Then
        If UBound(ConfigSettingsCache) > 1024 Then
            Err.Raise vbObjectError + 9199, , "FATAL ERROR: Ran out of settings cache of size 1024 saving: " & sCat
        End If
        ReDim Preserve ConfigSettingsCache(0 To UBound(ConfigSettingsCache) + 1)
        X = UBound(ConfigSettingsCache)
    End If
    SaveSetting App.title, "Settings", sCat, sVal
    Dim NewSettings As ConfigSetting
    NewSettings.name = sCat
    NewSettings.value = sVal
    ConfigSettingsCache(X) = NewSettings
End Sub

Public Function ConfigLoad(ByVal sCat As String, ByVal sDefault As String) As String
    Dim X As Long
    X = FindConfigCacheSetting(sCat)
    If X > 0 Then
        ConfigLoad = ConfigSettingsCache(X).value
        Exit Function
    End If

NoSuchItem:
    ConfigLoad = GetSetting(App.title, "Settings", sCat, sDefault)
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

