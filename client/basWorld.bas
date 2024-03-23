Attribute VB_Name = "basWorld"
Option Explicit

Public Const API_Server = "https://darksignsonline.com" 'e.g. "https://darksignsonline.com"
Public Const API_Path = "/api/" 'e.g. "/api/"

Public Const IRC_Server = "irc.libera.chat"
Public Const IRC_Port = "6697"

Public UsersOnline As String 'in the format of :user1::user2::user3:

Public Const MaxSockRetries = 3
Public Const TimeOutSeconds = 8

Public Authorized As Boolean

Public Comms(1 To 49) As String
Public HttpRequests() As clsHttpRequestor

Private Declare Function UrlEscape Lib "shlwapi" Alias "UrlEscapeW" (ByVal pszURL As Long, ByVal pszEscaped As Long, pcchEscaped As Long, ByVal dwFlags As Long) As Long
Private Const E_POINTER As Long = &H80004003
Private Const S_OK As Long = 0
Private Const INTERNET_MAX_URL_LENGTH As Long = 2048
Private Const URL_ESCAPE_PERCENT As Long = &H1000&

Private Type ProcessQueueEntry
    Data As String
    DataSource As String
    ConsoleID As Integer
    IsCustomDownload As Integer
    Code As Integer
End Type

Private ProcessQueue(1 To 30) As ProcessQueueEntry


Public Sub InitBasWorld()
    ReDim HttpRequests(0 To 0)
End Sub


Public Sub CleanHttpRequests()
    Dim X As Integer
    Dim Y As Integer
    Dim MadeChanges As Boolean
    Dim NewHttpRequests() As clsHttpRequestor

    If UBound(HttpRequests) < 1 Then
        Exit Sub
    End If

    ReDim NewHttpRequests(1 To UBound(HttpRequests))
    Y = 0
    For X = 1 To UBound(HttpRequests)
        If Not HttpRequests(X).SafeToDelete() Then
            Y = Y + 1
            Set NewHttpRequests(Y) = HttpRequests(X)
        Else
            MadeChanges = True
        End If
    Next

    'We did not do any cleanup, so don't redo the array for no reason
    If Not MadeChanges Then
        Exit Sub
    End If

    ReDim HttpRequests(0 To Y)
    For X = 1 To UBound(HttpRequests)
        Set HttpRequests(X) = NewHttpRequests(X)
    Next
End Sub


Public Function RunPage(ByVal sUrl As String, ByVal ConsoleID As Integer, Optional UsePost As Boolean, Optional PostData As String, Optional IsCustomDownload As Integer, Optional NoAuth As Boolean)
    If Not NoAuth And InStr(i(sUrl), "auth.php") = 0 And Not Authorized Then
        SayRaw ConsoleID, "You must be logged in to do that!{36 center orange impact nobold}"
        SayRaw ConsoleID, "Set your USERNAME and PASSWORD, then type LOGIN.{24 center white impact nobold}"

        If IsCustomDownload > 0 Then
            basWorld.Process "Not logged in", 401, sUrl, ConsoleID, IsCustomDownload
        End If
        Exit Function
    End If
 
    sUrl = Trim(Replace(sUrl, "&&", "&"))
    sUrl = Replace(sUrl, " ", "%20")

    Dim Requestor As New clsHttpRequestor
    Requestor.ConsoleID = ConsoleID
    Requestor.IsCustomDownload = IsCustomDownload

    If IsCustomDownload <= 0 Then
        sUrl = API_Server & API_Path & sUrl
    End If
    If NoAuth Then
        Requestor.UserName = ""
        Requestor.Password = ""
    Else
        Requestor.UserName = myUsername
        Requestor.Password = myPassword
    End If
    
    Requestor.Url = sUrl

    If UsePost = True Then
        Requestor.Method = "POST"
        Requestor.PostData = Trim(PostData)
    Else
        Requestor.Method = "GET"
        Requestor.PostData = ""
    End If
    
    ReDim Preserve HttpRequests(0 To UBound(HttpRequests) + 1)
    Set HttpRequests(UBound(HttpRequests)) = Requestor

    Requestor.Send
End Function

Public Function myUsername() As String
    myUsername = RegLoad("myUsernameDev", "")
End Function

Public Function myPassword() As String
    myPassword = RegLoad("myPasswordDev", "")
End Function

Public Sub SayCOMM(s As String, Optional ByVal ConsoleID As Integer)
    'send a message to the comm
    
    Dim n As Integer
    
    If Trim(s) <> "" Then
        
        For n = UBound(Comms) To 2 Step -1
            frmConsole.lComm(n).Caption = frmConsole.lComm(n - 1).Caption
            frmConsole.lCommTime(n).Caption = frmConsole.lCommTime(n - 1).Caption
        Next n
        Comms(1) = s
    
    End If
    
    Dim tmpY As Integer
    frmConsole.Comm.Cls
    tmpY = frmConsole.Comm.Height - 240
    
    
    For n = 1 To UBound(Comms)
        
        tmpY = tmpY - 210
        
        frmConsole.lComm(n).Top = tmpY
        frmConsole.lCommTime(n).Top = tmpY
        
        frmConsole.lComm(1).Caption = Comms(1)
        frmConsole.lCommTime(1).Caption = Format(Time, "h:mm AMPM")
        
        
        
           
        If tmpY < 0 Then
            frmConsole.lCommTime(n).Visible = False
            frmConsole.lComm(n).Visible = False
            'GoTo AllDone
        Else
            frmConsole.lCommTime(n).Visible = True
            frmConsole.lComm(n).Visible = True
        End If
    Next n
AllDone:
    
    frmConsole.CommLowerBorder.Move 0, frmConsole.Comm.Height - frmConsole.CommLowerBorder.Height, frmConsole.Comm.Width
End Sub

Public Sub Process(ByVal s As String, ByVal Code As Integer, sSource As String, ByVal ConsoleID As Integer, ByVal IsCustomDownload As Integer)
    Dim NewEntry As ProcessQueueEntry
    NewEntry.Data = s
    NewEntry.Code = Code
    NewEntry.DataSource = sSource
    NewEntry.ConsoleID = ConsoleID
    NewEntry.IsCustomDownload = IsCustomDownload

    Dim X As Integer
    For X = 1 To 30
        If frmConsole.tmrProcessQueue(X).Tag = "" Then
            frmConsole.tmrProcessQueue(X).Tag = "used"
            Exit For
        End If
    Next
    ProcessQueue(X) = NewEntry
    frmConsole.tmrProcessQueue(X).Enabled = True
End Sub

Public Sub OnLoginSuccess()
    Authorized = True
    frmConsole.lblUsername.Caption = "You are online as " & myUsername & "."
    frmConsole.Shape1.BackColor = iGreen: DoEvents
    SayCOMM "You have been authorized as " & myUsername & "."
    SayCOMM "Welcome to the Dark Signs Network!"
    SayCOMM "Dark Signs Online - Version " & VersionStr()
    
    Dim EmptyParams(0 To 0) As Variant
    EmptyParams(0) = ""
    Run_Script "/system/login-1.ds", 1, EmptyParams, "BOOT", True, False, False
    EmptyParams(0) = ""
    Run_Script "/system/login-2.ds", 2, EmptyParams, "BOOT", True, False, False
    EmptyParams(0) = ""
    Run_Script "/system/login-3.ds", 3, EmptyParams, "BOOT", True, False, False
    EmptyParams(0) = ""
    Run_Script "/system/login-4.ds", 4, EmptyParams, "BOOT", True, False, False
    
    If frmConsole.getConnected Then
        frmConsole.Send "QUIT :darksignsonline.com, Dark Signs Online"    'send the quit message
        frmConsole.lstUsers.Clear  'clear the list entries
        frmConsole.display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
        frmConsole.sockIRC.Close_   'close the connection
    End If

    frmConsole.ConnectIRC
End Sub

Public Sub OnLoginFailure()
    Authorized = False
    frmConsole.lblUsername.Caption = "Unable to log in."
    frmConsole.Shape1.BackColor = iOrange: DoEvents
    SayCOMM "Unable to log in. Please check your username and password."
        
    MsgBox "Your username and password was denied by the server." & vbCrLf & vbCrLf & "Username: " & myUsername & vbCrLf & "Password: [hidden]" & vbCrLf & vbCrLf & "If the information above is not correct, use the USERNAME command to change your username, or the PASSWORD command to change your password. Then type LOGIN again. Contact us if you continue to experience problems." & vbCrLf & vbCrLf & "https://darksignsonline.com", vbCritical, "Account Information"
End Sub


Public Sub ProcessQueueEntryRun(ByVal Index As Integer)
    Dim s As String
    Dim sSource As String
    Dim ConsoleID As Integer
    Dim IsCustomDownload As Integer
    Dim Code As Integer

    s = ProcessQueue(Index).Data
    Code = ProcessQueue(Index).Code
    sSource = ProcessQueue(Index).DataSource
    ConsoleID = ProcessQueue(Index).ConsoleID
    IsCustomDownload = ProcessQueue(Index).IsCustomDownload
    

    If IsCustomDownload > 0 Then
        'put the data into a variable!
        DownloadResults(IsCustomDownload) = s
        DownloadDone(IsCustomDownload) = True
        DownloadCodes(IsCustomDownload) = Code
        If DownloadAborted(IsCustomDownload) Then
            DownloadInUse(IsCustomDownload) = False
        End If
        Exit Sub
    End If

    If Code < 200 Or Code > 299 Then
        SayCOMM "Invalid HTTP code " & Code & " in response to internal request " & sSource
        Exit Sub
    End If

    Dim cCode As String
    'MsgBox s
    cCode = Mid(s, 1, 4)
    s = Mid(s, 5)

    Select Case cCode
        Case "0001" 'it's the user list
            LoadUserList s, ConsoleID

        Case "4300" 'file library upload complete
            frmLibrary.lStatus.Caption = s
            frmLibrary.UploadBox.Visible = False
        Case "4301" 'file library list category
            frmLibrary.AddListItems s
        Case "4302" 'file library existing scripts list for removal
            frmLibrary.AddtoRemoveList s
        Case "4303" 'file in the database was removed ok!
            frmLibrary.lStatus.Caption = s
            frmLibrary.LoadScriptsToRemove
        Case "4304" 'file has been downloaded
            Dim sF1 As String, sF2 As String
            If InStr(s, ":") > 0 Then
                sF1 = Trim(Mid(s, 1, InStr(s, ":") - 1))
                sF2 = Trim(Mid(s, InStr(s, ":") + 1, Len(s)))
                WriteFile "downloads/" & sF1, sF2
                frmLibrary.lStatus = "File downloaded ok: /downloads/" & sF1
            Else
                frmLibrary.lStatus = "File download error! (8234)"
            End If
        
        Case "4500"
            frmLibrary.tsl.Caption = s
            
        Case "4501"
            frmLibrary.TS.Text = s
            frmLibrary.tsl.Caption = "Loaded!"
        
        Case "7001" 'mail inbox
            frmDSOMail.EnableAll
            Dim emails() As String
            emails = Split(s, vbNewLine)
            Dim numEmails As Integer
            numEmails = UBound(emails)
            
            If numEmails < 0 Then
                numEmails = 0
            Else
                Dim n As Integer
                For n = 0 To UBound(emails) - 1 Step 1
                    emails(n) = "1" & Chr(7) & Trim(emails(n))
                Next n
                'AppendFile App.Path & "/mail.dat", Join(emails, vbNewLine)
                frmDSOMail.reloadInbox
            End If
            
            frmDSOMail.StatusBar1.SimpleText = "Current emails: ?" & vbTab & "New emails: " & numEmails
        Case "7002" ' Send msg.s
            If s = "success" Then
                frmDSOMailSend.EnableAll
                frmDSOMailSend.Hide
                frmDSOMailSend.btnSend.Caption = "Send"
                frmDSOMailSend.Enabled = True
                frmDSOMailSend.msgBody = ""
                frmDSOMailSend.msgSubject = ""
                frmDSOMailSend.msgTo = ""
            Else
                frmDSOMailSend.EnableAll
                frmDSOMailSend.btnSend.Caption = "Send"
                frmDSOMailSend.Enabled = True
                MsgBox "Mail failed to send." & vbNewLine & s
            End If

        Case Else

            If Trim(Replace(s, vbCrLf, "")) = "" Then Exit Sub
            If InStr(i(sSource), "z_online") > 0 Then Exit Sub
            If InStr(i(sSource), "chat") > 0 Then Exit Sub

            SayCOMM "The function [" & sSource & "] returned some strange data."
    End Select
    
    
End Sub


Public Sub SayCommMultiLines(ByVal s As String, ConsoleID As Integer)
    Dim sA() As String
    sA = Split(s, vbCrLf)

    Dim n As Integer
    For n = 0 To UBound(sA)
        SayCOMM sA(n), ConsoleID
    Next n
End Sub


Public Sub SayRawMultiLines(ByVal s As String, ConsoleID As Integer)
    Dim sA() As String
    sA = Split(s, vbCrLf)

    Dim n As Integer
    For n = 0 To UBound(sA)
        SayRaw ConsoleID, sA(n)
    Next n

    SayRaw ConsoleID, "{12 green}Line(s) Found: " & Trim(UBound(sA) + 1)
End Sub


Public Sub LoadUserList(ByVal s As String, ByVal ConsoleID As Integer)
    s = Replace(s, "::", ":")
    s = Replace(s, vbCr, ""): s = Replace(s, vbLf, "")
    
    
    
    
    
    frmConsole.ListOfUsers.Clear
    
    Dim tmpS As String, n As Integer
    
    For n = 1 To 200
        tmpS = Trim(GetPart(s, n, ":"))
        If Len(tmpS) > 2 Then
            frmConsole.ListOfUsers.AddItem tmpS
        End If
    Next n
    

    
    If frmConsole.ListOfUsers.ListCount = 0 Then Exit Sub
    
    
    For n = 0 To frmConsole.ListOfUsers.ListCount - 1
        tmpS = frmConsole.ListOfUsers.List(n)
    
        If Trim(UsersOnline) <> "" Then
        If InStr(i(UsersOnline), ":" & i(tmpS)) = 0 Then
            '----------------------------------------
            'this user just signed in!
            '----------------------------------------
            If i(tmpS) <> "admin" Then
                SayCOMM "User " & Trim(tmpS) & " has signed in.", ConsoleID
            End If
        End If
        End If
    

    Next n

    
    For n = 1 To 200
        tmpS = Trim(GetPart(UsersOnline, n, ":"))
        If Len(tmpS) > 2 Then
            If InStr(i(s), ":" & i(tmpS) & ":") = 0 Then
                '----------------------------------------
                'this user has been signed out!
                '----------------------------------------
                If i(tmpS) <> "admin" Then
                    SayCOMM "User " & Trim(tmpS) & " has signed out.", ConsoleID
                End If
            End If
        End If
    Next n
    
    
    
    UsersOnline = s
    
    
End Sub


Public Function EncodeURLParameter( _
    ByVal Url As String, _
    Optional ByVal SpacePlus As Boolean = True) As String
    
    Dim cchEscaped As Long
    Dim hResult As Long
    
    If Url = "" Then
        EncodeURLParameter = ""
        Exit Function
    End If
    
    If Len(Url) > INTERNET_MAX_URL_LENGTH Then
        Err.Raise &H8004D700, "URLUtility.URLEncode", _
                  "URL parameter too long"
    End If
    
    cchEscaped = Len(Url)
    
    EncodeURLParameter = String$(cchEscaped, 0)
    hResult = UrlEscape(StrPtr(Url), StrPtr(EncodeURLParameter), cchEscaped, URL_ESCAPE_PERCENT)
    If hResult = E_POINTER Then
        EncodeURLParameter = String$(cchEscaped, 0)
        hResult = UrlEscape(StrPtr(Url), StrPtr(EncodeURLParameter), cchEscaped, URL_ESCAPE_PERCENT)
    End If

    If hResult <> S_OK Then
        Err.Raise Err.LastDllError, "URLUtility.URLEncode", _
                  "System error"
    End If
    
    EncodeURLParameter = Left$(EncodeURLParameter, cchEscaped)
    If SpacePlus Then
        EncodeURLParameter = Replace$(EncodeURLParameter, "+", "%2B")
        EncodeURLParameter = Replace$(EncodeURLParameter, " ", "+")
    End If
End Function

