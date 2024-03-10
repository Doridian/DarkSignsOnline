Attribute VB_Name = "basWorld"
Option Explicit

Public Const API_Server = "https://darksignsonline.com" 'e.g. "www.darksignsonline.com"
Public Const API_Path = "/api/" 'e.g. "/api/"

'Public Const IRC_Server = "irc.dal.net"
'Public Const IRC_Server = "irc.chatchannel.org"
'Public Const IRC_Server = "irc.tacoz.net"
Public Const IRC_Server = "irc.freenode.net"
Public Const IRC_Port = "6667"

Public userIP As String
Public referals(0 To 3) As String

Public UsersOnline As String 'in the format of :user1::user2::user3:

Public Const MaxSockRetries = 3
Public Const TimeOutSeconds = 8

Public Authorized As Boolean

Public Type HttpRequest
    Http As New MSXML2.XMLHTTP60
    InUse As Boolean
    consoleID As Integer
    IsCustomDownload As Integer

    Retries As Integer
    
    Method As String
    Url As String
    PostData As String
    
    Username As String
    Password As String
End Type

Public HttpRequests(1 To 30) As HttpRequest

Public Comms(1 To 49) As String

Public Sub LoginNow(ByVal consoleID As Integer)
    Dim isBad As Boolean
    isBad = False

    If Authorized = True Then
        Say consoleID, "You are already logged in and authorized as " & myUsername & ".{green}", False
        Exit Sub
    Else
        If myUsername = "" Then
            Say consoleID, "{14, orange,  center}Your username is not right - type: USERNAME [username] to set it."
            isBad = True
        End If
        If myPassword = "" Then
            Say consoleID, "{14, orange, center}Your password is not right - type: PASSWORD [password] to set it."
            isBad = True
        End If
        
        If isBad = True Then
            Say consoleID, "Warning - You are not logged in!{16 center underline}"
            Say consoleID, "Once you have set your USERNAME and PASSWORD, type LOGIN.{14 center}"
            Exit Sub
        End If
    
        
        SayComm "Logging in..."

        RunPage "auth.php", consoleID, True, ""
    End If
End Sub

Public Sub LogoutNow(ByVal consoleID As Integer)
    Authorized = False
    frmConsole.Shape1.BackColor = vbRed
    frmConsole.lblUsername.Caption = "You have been logged out."
    SayComm "You have been logged out."
    
    If frmConsole.getConnected Then
        frmConsole.send "QUIT :www.darksignsonline.com, Dark Signs Online"    'send the quit message
        frmConsole.lstUsers.Clear  'clear the list entries
        frmConsole.display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
        frmConsole.sockIRC.Close   'close the connection
        frmConsole.setConnected False
    End If
End Sub


Public Function RunPage(ByVal sUrl As String, ByVal consoleID As Integer, Optional UsePost As Boolean, Optional PostData As String, Optional IsCustomDownload As Integer) As Integer
    If InStr(i(sUrl), "auth.php") = 0 And Authorized = False Then
        Say consoleID, "You must be logged in to do that!{36 center orange impact nobold}", False
        Say consoleID, "Set your USERNAME and PASSWORD, then type LOGIN.{24 center white impact nobold}", False
        RunPage = 0
        Exit Function
    End If
    
    Dim sockIndex As Integer
    sockIndex = -1
    Dim n As Integer
    For n = 1 To UBound(HttpRequests)
        If Not HttpRequests(n).InUse Then
            sockIndex = n
            Exit For
        End If
    Next
    frmConsole.tmrTimeout(sockIndex).Enabled = False
    HttpRequests(sockIndex).InUse = True
 
    sUrl = Trim(Replace(sUrl, "&&", "&"))
    sUrl = Replace(sUrl, " ", "%20")

    HttpRequests(sockIndex).Retries = 0
    HttpRequests(sockIndex).consoleID = consoleID
    HttpRequests(sockIndex).IsCustomDownload = IsCustomDownload
    HttpRequests(sockIndex).Username = myUsername
    HttpRequests(sockIndex).Password = myPassword

    Dim Http As New MSXML2.XMLHTTP60
    Dim HttpMethod As String
    Set HttpRequests(sockIndex).Http = Http

    Dim StateHandler As clsReadyStateHandler
    Set StateHandler = New clsReadyStateHandler
    StateHandler.Index = sockIndex
    Http.OnReadyStateChange = StateHandler

    If IsCustomDownload <= 0 Then
        sUrl = API_Server + API_Path + sUrl
    End If
    
    If UsePost = True Then
        HttpMethod = "POST"
    Else
        HttpMethod = "GET"
    End If
    HttpRequests(sockIndex).Method = HttpMethod
    HttpRequests(sockIndex).Url = sUrl

    Http.open HttpMethod, sUrl, True, myUsername, myPassword

    If HttpMethod = "POST" Then
        PostData = Trim(PostData)
        PostData = Replace(PostData, " ", "%20")
        PostData = Replace(PostData, "+", "--plus--")
        'PostData = Replace(PostData, "&", "--and--") 'this one screws up URL
        HttpRequests(sockIndex).PostData = PostData
        Http.setRequestHeader "Content-Type", "application/x-www-form-urlencoded"
        Http.send PostData
    Else
        HttpRequests(sockIndex).PostData = ""
        Http.send
    End If
    'SockPort(sockIndex) = 80

    frmConsole.tmrTimeout(sockIndex).Interval = TimeOutSeconds * 1000
    frmConsole.tmrTimeout(sockIndex).Enabled = True
    
    'If Right(SockServer(sockIndex), 1) = "?" Then
    '    SockServer(sockIndex) = Mid(SockServer(sockIndex), 1, Len(SockServer(sockIndex)) - 1)
    'End If
    
    
    'If InStr(frmConsole.Sock(sockIndex).Tag, ".php?") And Len(SockPostData(sockIndex)) > 2 Then
    '    SockPostData(sockIndex) = Mid(frmConsole.Sock(sockIndex).Tag, InStr(frmConsole.Sock(sockIndex).Tag, "?") + 1, Len(frmConsole.Sock(sockIndex).Tag))
    '    frmConsole.Sock(sockIndex).Tag = Mid(frmConsole.Sock(sockIndex).Tag, 1, InStr(frmConsole.Sock(sockIndex).Tag, "?") - 1)
    '    SockPostOrGet(sockIndex) = "POST"
    'End If
        
    'MsgBox SockServer(sockIndex) & vbCrLf & vbCrLf & SockPort(sockIndex) & _
    'vbCrLf & vbCrLf & SockPath(sockIndex), , sockIndex

    'MsgBox SockServer(sockIndex) & vbCrLf & vbCrLf & _
    'frmConsole.Sock(sockIndex).Tag & vbCrLf & vbCrLf & SockPostData(sockIndex)

    RunPage = n
End Function

Public Function myUsername() As String
    myUsername = RegLoad("myUsernameDev", "")
End Function

Public Function myPassword() As String
    myPassword = RegLoad("myPasswordDev", "")
End Function

Public Sub SayComm(s As String, Optional ByVal consoleID As Integer)
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


Public Sub Process(ByVal s As String, sSource As String, ByVal consoleID As Integer, ByVal Index As Integer)
    
 
    'process incoming data that winhttp download
    s = Replace(s, "<end>", "")
    s = Trim(s)

    'don't replace this if data is encrypted
    If InStr(Mid(i(s), 1, 20), "encrypted") = 0 Then
        s = Replace(s, vbCr, vbCrLf)
        s = Replace(s, vbLf, vbCrLf)
        s = Replace(s, "*- -*", vbCrLf) 'replace the new lines (DSO in some places uses *- -* for new lines that should be replaced
        s = Replace(s, "--plus--", "+")
        s = Replace(s, "--and--", "&")
        s = Replace(s, "--hash--", "#")
    Else
        'it's encrypted, don't screw up the data
    End If
        
    
    

    Dim IsCustomDownload As Integer
    IsCustomDownload = basWorld.HttpRequests(Index).IsCustomDownload
    If IsCustomDownload > 0 Then
        'put the data into a variable!
        Vars(IsCustomDownload).VarValue = Bracketize(s, True)
        Exit Sub
    End If
    
    Dim cCode As String
    'MsgBox s
    cCode = Mid(s, 1, 4)
    s = Replace(s, cCode, "")
    
    
    Select Case cCode
        
        Case "0000" 'do nothing with the data
        
        Case "0001" 'it's the user list
            LoadUserList s, consoleID
        
        Case "1001" 'login ok
            userIP = s
            referals(0) = s
            referals(1) = s
            referals(2) = s
            referals(3) = s
            
            
            Authorized = True
            frmConsole.lblUsername.Caption = "You are online as " & myUsername & "."
            frmConsole.Shape1.BackColor = iGreen: DoEvents
            SayComm "You have been authorized as " & myUsername & "."
            SayComm "Welcome to the Dark Signs Network!"
            SayComm "Dark Signs Online - PreRelease Build 1337"
            If command <> "" Then
                Dim CLine As ConsoleLine
                CLine = Console_Line_Defaults
                CLine.Caption = command
                Run_Command CLine, consoleID
            End If
            
            Run_Script "\system\login-1.ds", 1, "", "BOOT"
            Run_Script "\system\login-2.ds", 2, "", "BOOT"
            Run_Script "\system\login-3.ds", 3, "", "BOOT"
            Run_Script "\system\login-4.ds", 4, "", "BOOT"
            
            
            If frmConsole.getConnected Then
                frmConsole.send "QUIT :www.darksignsonline.com, Dark Signs Online"    'send the quit message
                frmConsole.lstUsers.Clear  'clear the list entries
                frmConsole.display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
                frmConsole.sockIRC.Close   'close the connection
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
            SayComm "Unable to log in. Please check your username and password."
                
            MsgBox "Your username and password was denied by the server." & vbCrLf & vbCrLf & "Username: " & myUsername & vbCrLf & "Password: " & myPassword & vbCrLf & vbCrLf & "If the information above is not correct, use the USERNAME command to change your username, or the PASSWORD command to change your password. Then type LOGIN again. Contact us if you continue to experience problems." & vbCrLf & vbCrLf & "http://www.darksignsonline.com", vbCritical, "Account Information"
                
        
        Case "1003" 'account disabled
            
            Authorized = False
            frmConsole.lblUsername.Caption = "Access Denied."
            frmConsole.Shape1.BackColor = iOrange: DoEvents
            SayComm "Sorry, your account (" & myUsername & ") is disabled."
            MsgBox "Sorry, your account (" & myUsername & ") is disabled." & vbCrLf & vbCrLf & "This probably means that your account has expired." & vbCrLf & vbCrLf & "Please visit the website to renew your account, or contact us if you believe this is an error." & vbCrLf & vbCrLf & "http://www.darksignsonline.com", vbCritical, "Account Information"
        
        
        '2000 is just a general show in the comm, all purpose
        Case "2000":
            'MsgBox s
            SayCommMultiLines s, consoleID
            
        Case "2001":
            'MsgBox s
            SayMultiLines s, consoleID
        
        Case "2003":
            If (s = "success") Then
                SayComm "Upload Successful.", consoleID
            Else
                MsgBox s
                SayComm "Upload Failed.", consoleID
            End If
            
            
        Case "2004": ' Domain querys.
            SayMultiLines s, consoleID
        
        Case "3001": 'update chat
            
            
'            Dim sMessages As String, sTimes As String
'            sTimes = GetPart(s, 1, "*!*!*!*!*")
'            sMessages = GetPart(s, 2, "*!*!*!*!*")
'
'            UpdateChat sTimes, sMessages
            
        Case "4100":
            

            If Len(s) < 20 And InStr(i(s), "not found") > 0 Then
                Say consoleID, "Connection Failed.{orange}", False
                New_Console_Line ActiveConsole
            Else
                Dim sParameters As String
                If InStr(s, "::") > 0 Then
                    sParameters = Mid(s, 1, InStr(s, "::") - 1)
                    'MsgBox sParameters
                    s = Mid(s, InStr(s, "::") + 2, Len(s))
                End If
                
                's = Replace(s, "--equals--", "=")
                
                'MsgBox s
                
                'Dim EncodedText As String
            
                
                WriteClean App.Path & "\user\system\tempDown64.dat", s
                's = StrConv(DecodeBase64(s), vbFromUnicode)
                Dim b64 As Base64Class
                Set b64 = New Base64Class
                Dim b64decoded() As Byte
                b64decoded = b64.DecodeToByteArray(s)
             '  Set b64 = Nothing
                
                
                'Dim strKey As String
                Dim bf As clsBlowfish
                Dim newB() As Byte
                ReDim newB(0 To UBound(b64decoded))
                Dim newS As String
                Set bf = New clsBlowfish
                bf.sInitBF "z123" & sParameters & "456"
                bf.sDecrypt b64decoded, newB
                newS = StrConv(newB, vbUnicode)

                WriteClean App.Path & "\user\system\temp.dat", newS
                'bf.sInitBF "secretkey"
                'MsgBox Left(sParameters, InStr(sParameters, "_") - 1)
                'bf.sFileDecrypt App.Path & "\user\system\temp.dat", App.Path & "\user\system\tempD.dat"
                'Run_Script "\system\temp.dat", consoleID, sParameters, referals(ActiveConsole)
                cPrefix(consoleID) = "\web"
                Run_Script "\system\temp.dat", consoleID, sParameters, Left(sParameters, InStr(sParameters, "_") - 1)
                cPrefix(consoleID) = ""
                cPrefix(5) = ""
            End If
            
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
                WriteFile App.Path & "\user\downloads\" & sF1, sF2
                frmLibrary.lStatus = "File downloaded ok: \downloads\" & sF1
            Else
                frmLibrary.lStatus = "File download error! (8234)"
            End If
        
        Case "4400" 'file to write from the DOWNLOAD function
        
        
            If Mid(i(s), 1, 5) = "error" Then
                SayCommMultiLines s, consoleID
                Exit Sub
            End If
        
            Dim ffname As String
            If InStr(s, ":") > 0 Then
                ffname = Trim(Mid(s, 1, InStr(s, ":") - 1))
                ffname = Replace(ffname, "\\", "\")
                s = Mid(s, InStr(s, ":") + 1, Len(s))
                WriteFile App.Path & "\user" & cPrefix(consoleID) & ffname, s
                SayComm "Download Complete: " & ffname
            Else
                SayCommMultiLines s, consoleID
            End If
        
        Case "4500"
            frmLibrary.tsl.Caption = s
            
        Case "4501"
            frmLibrary.TS.Text = s
            frmLibrary.tsl.Caption = "Loaded!"
        
        Case "7001" 'mail inbox
            MsgBox s
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
                    emails(n) = "1" & Chr(7) & emails(n)
                Next n
                AppendFile App.Path & "\mail.dat", Join(emails, vbNewLine)
                frmDSOMail.reloadInbox
            End If
            
            frmDSOMail.StatusBar1.SimpleText = "Current emails: " & 2 & vbTab & "New emails: " & numEmails
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
            
            
            
           ' MsgBox s
        
        Case Else

            If Trim(Replace(s, vbCrLf, "")) = "" Then Exit Sub
            If InStr(i(sSource), "z_online") > 0 Then Exit Sub
            If InStr(i(sSource), "chat") > 0 Then Exit Sub

            SayComm s
            MsgBox s
            SayComm "The function [" & sSource & "] returned some strange data."

        
    End Select
    
    
End Sub


Public Sub SayCommMultiLines(ByVal s As String, consoleID As Integer)

        Dim p1 As String, p2 As String, p3 As String, p4 As String, p5 As String
        Dim p6 As String, p7 As String, p8 As String, p9 As String, p10 As String
        
        'this can be sent data divided with the string "newline" (without quotes)
        'and it wil be shown properly up to 10 lines
        
        p1 = GetPart(s, 1, "newline"): p2 = GetPart(s, 2, "newline"):
        p3 = GetPart(s, 3, "newline"): p4 = GetPart(s, 4, "newline")
        p5 = GetPart(s, 5, "newline"): p6 = GetPart(s, 6, "newline")
        p7 = GetPart(s, 7, "newline"): p8 = GetPart(s, 8, "newline")
        p9 = GetPart(s, 9, "newline"): p10 = GetPart(s, 10, "newline")
        If Trim(p1) <> "" Then SayComm p1: If Trim(p2) <> "" Then SayComm p2
        If Trim(p3) <> "" Then SayComm p3: If Trim(p4) <> "" Then SayComm p4
        If Trim(p5) <> "" Then SayComm p5: If Trim(p6) <> "" Then SayComm p6
        If Trim(p7) <> "" Then SayComm p7: If Trim(p8) <> "" Then SayComm p8
        If Trim(p9) <> "" Then SayComm p9: If Trim(p10) <> "" Then SayComm p10

End Sub


Public Sub SayMultiLines(ByVal s As String, consoleID As Integer)

        Dim sA() As String
        sA = Split(s, "$newline")
        Dim iCount As Integer
        
        Dim n As Integer, tmpS As String
        For n = 0 To UBound(sA)
            tmpS = Trim(sA(n))
            If tmpS <> "" Then
                iCount = iCount + 1
                Say consoleID, tmpS, False
                
                If iCount Mod 20 = 0 Then PauseConsole "", consoleID
            End If
        Next n
        
        Say consoleID, "{12 green}Line(s) Found: " & Trim(str(iCount)), False
        
        New_Console_Line consoleID

End Sub


Public Sub LoadUserList(ByVal s As String, ByVal consoleID As Integer)
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
                SayComm "User " & Trim(tmpS) & " has signed in.", consoleID
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
                    SayComm "User " & Trim(tmpS) & " has signed out.", consoleID
                End If
            End If
        End If
    Next n
    
    
    
    UsersOnline = s
    
    
End Sub



Public Function MaskAnd(ByVal s As String) As String
    MaskAnd = Replace(s, "&", "--and--")
End Function

