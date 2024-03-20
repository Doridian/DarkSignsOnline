Attribute VB_Name = "basWorld"
Option Explicit

Public Const API_Server = "https://darksignsonline.com" 'e.g. "https://darksignsonline.com"
Public Const API_Path = "/api/" 'e.g. "/api/"

Public Const IRC_Server = "irc.libera.chat"
Public Const IRC_Port = "6697"

Public userIP As String
Public referals(0 To 3) As String

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

Public Sub LoginNow(ByVal ConsoleID As Integer)
    Dim isBad As Boolean
    isBad = False

    If Authorized = True Then
        SAY ConsoleID, "You are already logged in and authorized as " & myUsername & ".{green}", False
        Exit Sub
    Else
        If myUsername = "" Then
            SAY ConsoleID, "{14, orange,  center}Your username is not right - type: USERNAME [username] to set it."
            isBad = True
        End If
        If myPassword = "" Then
            SAY ConsoleID, "{14, orange, center}Your password is not right - type: PASSWORD [password] to set it."
            isBad = True
        End If
        
        If isBad = True Then
            SAY ConsoleID, "Warning - You are not logged in!{16 center underline}"
            SAY ConsoleID, "Once you have set your USERNAME and PASSWORD, type LOGIN.{14 center}"
            Exit Sub
        End If
    
        
        SayCOMM "Logging in..."

        RunPage "auth.php", ConsoleID, True, ""
    End If
End Sub

Public Sub LogoutNow(ByVal ConsoleID As Integer)
    Authorized = False
    frmConsole.Shape1.BackColor = vbRed
    frmConsole.lblUsername.Caption = "You have been logged out."
    SayCOMM "You have been logged out."
    
    If frmConsole.getConnected Then
        frmConsole.Send "QUIT :darksignsonline.com, Dark Signs Online"    'send the quit message
        frmConsole.lstUsers.Clear  'clear the list entries
        frmConsole.display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
        frmConsole.sockIRC.Close_   'close the connection
        frmConsole.setConnected False
    End If
End Sub


Public Function RunPage(ByVal sUrl As String, ByVal ConsoleID As Integer, Optional UsePost As Boolean, Optional PostData As String, Optional IsCustomDownload As Integer, Optional NoAuth As Boolean)
    If InStr(i(sUrl), "auth.php") = 0 And Authorized = False Then
        SAY ConsoleID, "You must be logged in to do that!{36 center orange impact nobold}", False
        SAY ConsoleID, "Set your USERNAME and PASSWORD, then type LOGIN.{24 center white impact nobold}", False
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

Public Sub SayCOMM(S As String, Optional ByVal ConsoleID As Integer)
    'send a message to the comm
    
    Dim n As Integer
    
    If Trim(S) <> "" Then
        
        For n = UBound(Comms) To 2 Step -1
            frmConsole.lComm(n).Caption = frmConsole.lComm(n - 1).Caption
            frmConsole.lCommTime(n).Caption = frmConsole.lCommTime(n - 1).Caption
        Next n
        Comms(1) = S
    
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

Public Sub Process(ByVal S As String, sSource As String, ByVal ConsoleID As Integer, ByVal IsCustomDownload As Integer)
    Dim NewEntry As ProcessQueueEntry
    NewEntry.Data = S
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

Public Sub ProcessQueueEntry(ByVal Index As Integer)
    Dim S As String
    Dim sSource As String
    Dim ConsoleID As Integer
    Dim IsCustomDownload As Integer

    S = ProcessQueue(Index).Data
    sSource = ProcessQueue(Index).DataSource
    ConsoleID = ProcessQueue(Index).ConsoleID
    IsCustomDownload = ProcessQueue(Index).IsCustomDownload
    

    'process incoming data that winhttp download
    S = Trim(S)

    If IsCustomDownload > 0 Then
        'put the data into a variable!
        Vars(IsCustomDownload).VarValue = Bracketize(S, True)
        Exit Sub
    End If
    
    Dim cCode As String
    'MsgBox s
    cCode = Mid(S, 1, 4)
    S = Replace(S, cCode, "")
    
    Select Case cCode
        Case "0000" 'do nothing with the data
        
        Case "0001" 'it's the user list
            LoadUserList S, ConsoleID
        
        Case "1001" 'login ok
            userIP = S
            referals(0) = S
            referals(1) = S
            referals(2) = S
            referals(3) = S
            
            
            Authorized = True
            frmConsole.lblUsername.Caption = "You are online as " & myUsername & "."
            frmConsole.Shape1.BackColor = iGreen: DoEvents
            SayCOMM "You have been authorized as " & myUsername & "."
            SayCOMM "Welcome to the Dark Signs Network!"
            SayCOMM "Dark Signs Online - PreRelease Build 1337"
            If Command <> "" Then
                Dim CLine As ConsoleLine
                CLine = Console_Line_Defaults
                CLine.Caption = Command
                New_Console_Line ConsoleID
            End If
            
            Run_Script "\system\login-1.ds", 1, "", "BOOT"
            Run_Script "\system\login-2.ds", 2, "", "BOOT"
            Run_Script "\system\login-3.ds", 3, "", "BOOT"
            Run_Script "\system\login-4.ds", 4, "", "BOOT"
            
            
            If frmConsole.getConnected Then
                frmConsole.Send "QUIT :darksignsonline.com, Dark Signs Online"    'send the quit message
                frmConsole.lstUsers.Clear  'clear the list entries
                frmConsole.display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
                frmConsole.sockIRC.Close_   'close the connection
            End If
            
            
            frmConsole.ConnectIRC
            'get stats
            'RunPage "get_user_stats.php?returnwith=2000&fromlogin", consoleID
            'get recent chat data
            'RunPage "chat.php?get=1", ActiveConsole
            'mark as online
            'frmConsole.KeepOnline
            
            
        Case "1002" 'bad username or password
            
            Authorized = False
            frmConsole.lblUsername.Caption = "Unable to log in."
            frmConsole.Shape1.BackColor = iOrange: DoEvents
            SayCOMM "Unable to log in. Please check your username and password."
                
            MsgBox "Your username and password was denied by the server." & vbCrLf & vbCrLf & "Username: " & myUsername & vbCrLf & "Password: [hidden]" & vbCrLf & vbCrLf & "If the information above is not correct, use the USERNAME command to change your username, or the PASSWORD command to change your password. Then type LOGIN again. Contact us if you continue to experience problems." & vbCrLf & vbCrLf & "https://darksignsonline.com", vbCritical, "Account Information"
                
        
        Case "1003" 'account disabled
            
            Authorized = False
            frmConsole.lblUsername.Caption = "Access Denied."
            frmConsole.Shape1.BackColor = iOrange: DoEvents
            SayCOMM "Sorry, your account (" & myUsername & ") is disabled."
            MsgBox "Sorry, your account (" & myUsername & ") is disabled." & vbCrLf & vbCrLf & "This probably means that your account has expired." & vbCrLf & vbCrLf & "Please visit the website to renew your account, or contact us if you believe this is an error." & vbCrLf & vbCrLf & "https://darksignsonline.com", vbCritical, "Account Information"
        
        
        '2000 is just a general show in the comm, all purpose
        Case "2000":
            'MsgBox s
            SayCommMultiLines S, ConsoleID
            
        Case "2001":
            'MsgBox s
            SayMultiLines S, ConsoleID
        
        Case "2003":
            If (S = "success") Then
                SayCOMM "Upload Successful.", ConsoleID
            Else
                MsgBox S
                SayCOMM "Upload Failed.", ConsoleID
            End If
            
            
        Case "2004": ' Domain querys.
            SayMultiLines S, ConsoleID
        
        Case "3001": 'update chat
            
            
'            Dim sMessages As String, sTimes As String
'            sTimes = GetPart(s, 1, "*!*!*!*!*")
'            sMessages = GetPart(s, 2, "*!*!*!*!*")
'
'            UpdateChat sTimes, sMessages
            
        Case "4100":
            

            If Len(S) < 20 And InStr(i(S), "not found") > 0 Then
                SAY ConsoleID, "Connection Failed.{orange}", False
                New_Console_Line ActiveConsole
            Else
                Dim sParameters As String
                If InStr(S, "::") > 0 Then
                    sParameters = Mid(S, 1, InStr(S, "::") - 1)
                    S = Mid(S, InStr(S, "::") + 2, Len(S))
                End If
            
                Dim b64decoded() As Byte
                b64decoded = basConsole.DecodeBase64(S)
                Dim newS As String
                newS = StrConv(b64decoded, vbUnicode)

                WriteClean App.Path & "\user\system\temp.dat", newS
                Run_Script "\system\temp.dat", ConsoleID, sParameters, Left(sParameters, InStr(sParameters, "_") - 1)
            End If
            
        Case "4300" 'file library upload complete
            frmLibrary.lStatus.Caption = S
            frmLibrary.UploadBox.Visible = False
        Case "4301" 'file library list category
            frmLibrary.AddListItems S
        Case "4302" 'file library existing scripts list for removal
            frmLibrary.AddtoRemoveList S
        Case "4303" 'file in the database was removed ok!
            frmLibrary.lStatus.Caption = S
            frmLibrary.LoadScriptsToRemove
        Case "4304" 'file has been downloaded
            Dim sF1 As String, sF2 As String
            If InStr(S, ":") > 0 Then
                sF1 = Trim(Mid(S, 1, InStr(S, ":") - 1))
                sF2 = Trim(Mid(S, InStr(S, ":") + 1, Len(S)))
                WriteFile App.Path & "\user\downloads\" & sF1, sF2
                frmLibrary.lStatus = "File downloaded ok: \downloads\" & sF1
            Else
                frmLibrary.lStatus = "File download error! (8234)"
            End If
        
        Case "4400" 'file to write from the DOWNLOAD function
        
        
            If Mid(i(S), 1, 5) = "error" Then
                SayCommMultiLines S, ConsoleID
                Exit Sub
            End If
        
            Dim ffname As String
            If InStr(S, ":") > 0 Then
                ffname = Trim(Mid(S, 1, InStr(S, ":") - 1))
                ffname = Replace(ffname, "\\", "\")
                S = Mid(S, InStr(S, ":") + 1, Len(S))
                WriteFile App.Path & "\user" & ffname, S
                SayCOMM "Download Complete: " & ffname
            Else
                SayCommMultiLines S, ConsoleID
            End If
        
        Case "4500"
            frmLibrary.tsl.Caption = S
            
        Case "4501"
            frmLibrary.TS.Text = S
            frmLibrary.tsl.Caption = "Loaded!"
        
        Case "7001" 'mail inbox
            frmDSOMail.EnableAll
            Dim emails() As String
            emails = Split(S, vbNewLine)
            Dim numEmails As Integer
            numEmails = UBound(emails)
            
            If numEmails < 0 Then
                numEmails = 0
            Else
                Dim n As Integer
                For n = 0 To UBound(emails) - 1 Step 1
                    emails(n) = "1" & Chr(7) & Trim(emails(n))
                Next n
                AppendFile App.Path & "\mail.dat", Join(emails, vbNewLine)
                frmDSOMail.reloadInbox
            End If
            
            frmDSOMail.StatusBar1.SimpleText = "Current emails: ?" & vbTab & "New emails: " & numEmails
        Case "7002" ' Send msg.s
            If S = "success" Then
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
                MsgBox "Mail failed to send." & vbNewLine & S
            End If
            
            
            
           ' MsgBox s
        
        Case Else

            If Trim(Replace(S, vbCrLf, "")) = "" Then Exit Sub
            If InStr(i(sSource), "z_online") > 0 Then Exit Sub
            If InStr(i(sSource), "chat") > 0 Then Exit Sub

            SayCOMM S
            MsgBox S
            SayCOMM "The function [" & sSource & "] returned some strange data."

        
    End Select
    
    
End Sub


Public Sub SayCommMultiLines(ByVal S As String, ConsoleID As Integer)

        Dim p1 As String, p2 As String, p3 As String, p4 As String, p5 As String
        Dim p6 As String, p7 As String, p8 As String, p9 As String, p10 As String
        
        'this can be sent data divided with the string "newline" (without quotes)
        'and it wil be shown properly up to 10 lines
        
        p1 = GetPart(S, 1, "newline"): p2 = GetPart(S, 2, "newline"):
        p3 = GetPart(S, 3, "newline"): p4 = GetPart(S, 4, "newline")
        p5 = GetPart(S, 5, "newline"): p6 = GetPart(S, 6, "newline")
        p7 = GetPart(S, 7, "newline"): p8 = GetPart(S, 8, "newline")
        p9 = GetPart(S, 9, "newline"): p10 = GetPart(S, 10, "newline")
        If Trim(p1) <> "" Then SayCOMM p1: If Trim(p2) <> "" Then SayCOMM p2
        If Trim(p3) <> "" Then SayCOMM p3: If Trim(p4) <> "" Then SayCOMM p4
        If Trim(p5) <> "" Then SayCOMM p5: If Trim(p6) <> "" Then SayCOMM p6
        If Trim(p7) <> "" Then SayCOMM p7: If Trim(p8) <> "" Then SayCOMM p8
        If Trim(p9) <> "" Then SayCOMM p9: If Trim(p10) <> "" Then SayCOMM p10

End Sub


Public Sub SayMultiLines(ByVal S As String, ConsoleID As Integer)

        Dim sA() As String
        sA = Split(S, "$newline")
        Dim iCount As Integer
        
        Dim n As Integer, tmpS As String
        For n = 0 To UBound(sA)
            tmpS = Trim(sA(n))
            If tmpS <> "" Then
                iCount = iCount + 1
                SAY ConsoleID, tmpS, False
                
                If iCount Mod 20 = 0 Then PauseConsole "", ConsoleID
            End If
        Next n
        
        SAY ConsoleID, "{12 green}Line(s) Found: " & Trim(Str(iCount)), False
        
        New_Console_Line ConsoleID

End Sub


Public Sub LoadUserList(ByVal S As String, ByVal ConsoleID As Integer)
    S = Replace(S, "::", ":")
    S = Replace(S, vbCr, ""): S = Replace(S, vbLf, "")
    
    
    
    
    
    frmConsole.ListOfUsers.Clear
    
    Dim tmpS As String, n As Integer
    
    For n = 1 To 200
        tmpS = Trim(GetPart(S, n, ":"))
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
            If InStr(i(S), ":" & i(tmpS) & ":") = 0 Then
                '----------------------------------------
                'this user has been signed out!
                '----------------------------------------
                If i(tmpS) <> "admin" Then
                    SayCOMM "User " & Trim(tmpS) & " has signed out.", ConsoleID
                End If
            End If
        End If
    Next n
    
    
    
    UsersOnline = S
    
    
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

