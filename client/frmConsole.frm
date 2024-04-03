VERSION 5.00
Begin VB.Form frmConsole 
   AutoRedraw      =   -1  'True
   BackColor       =   &H001B1410&
   BorderStyle     =   0  'None
   Caption         =   "DSD Console"
   ClientHeight    =   9705
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   11475
   BeginProperty Font 
      Name            =   "Verdana"
      Size            =   9.75
      Charset         =   0
      Weight          =   700
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   ForeColor       =   &H80000001&
   Icon            =   "frmConsole.frx":0000
   KeyPreview      =   -1  'True
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   9705
   ScaleWidth      =   11475
   StartUpPosition =   3  'Windows Default
   Begin VB.Timer tmrProcessQueue 
      Enabled         =   0   'False
      Index           =   0
      Interval        =   1
      Left            =   9480
      Top             =   7320
   End
   Begin DSO.ctxWinsock sockIRC 
      Left            =   960
      Top             =   7080
      _ExtentX        =   847
      _ExtentY        =   847
      Protocol        =   2
   End
   Begin VB.PictureBox ChatBox 
      Appearance      =   0  'Flat
      BackColor       =   &H80000005&
      BorderStyle     =   0  'None
      ForeColor       =   &H80000008&
      Height          =   6855
      Left            =   360
      ScaleHeight     =   6855
      ScaleWidth      =   9855
      TabIndex        =   21
      TabStop         =   0   'False
      Top             =   -840
      Visible         =   0   'False
      Width           =   9855
      Begin VB.ListBox cList 
         Height          =   300
         Left            =   360
         TabIndex        =   29
         TabStop         =   0   'False
         Top             =   3480
         Visible         =   0   'False
         Width           =   165
      End
      Begin VB.TextBox txtStatus 
         Appearance      =   0  'Flat
         BackColor       =   &H001B1410&
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   8.25
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         ForeColor       =   &H0066E1FB&
         Height          =   1095
         Left            =   120
         Locked          =   -1  'True
         MultiLine       =   -1  'True
         ScrollBars      =   2  'Vertical
         TabIndex        =   28
         TabStop         =   0   'False
         Top             =   120
         Width           =   44695
      End
      Begin VB.TextBox txtChat 
         Appearance      =   0  'Flat
         BackColor       =   &H001B1410&
         ForeColor       =   &H00FFFFFF&
         Height          =   1215
         Left            =   120
         Locked          =   -1  'True
         MultiLine       =   -1  'True
         ScrollBars      =   2  'Vertical
         TabIndex        =   27
         TabStop         =   0   'False
         Top             =   1320
         Visible         =   0   'False
         Width           =   3375
      End
      Begin VB.ListBox lstUsers 
         Appearance      =   0  'Flat
         BackColor       =   &H003D2E27&
         ForeColor       =   &H0000FF00&
         Height          =   4590
         Left            =   9000
         Sorted          =   -1  'True
         TabIndex        =   26
         TabStop         =   0   'False
         Top             =   1440
         Width           =   1815
      End
      Begin VB.PictureBox TBox 
         Appearance      =   0  'Flat
         BackColor       =   &H00000000&
         BorderStyle     =   0  'None
         ForeColor       =   &H80000008&
         Height          =   495
         Left            =   360
         ScaleHeight     =   495
         ScaleWidth      =   8775
         TabIndex        =   23
         TabStop         =   0   'False
         Top             =   4680
         Width           =   8775
         Begin VB.CommandButton cmdChat 
            BackColor       =   &H00C0C0C0&
            Caption         =   "Chat"
            Default         =   -1  'True
            BeginProperty Font 
               Name            =   "Verdana"
               Size            =   8.25
               Charset         =   0
               Weight          =   700
               Underline       =   0   'False
               Italic          =   0   'False
               Strikethrough   =   0   'False
            EndProperty
            Height          =   375
            Left            =   7545
            Style           =   1  'Graphical
            TabIndex        =   25
            TabStop         =   0   'False
            Top             =   60
            Width           =   1335
         End
         Begin VB.TextBox txtChatMsg 
            BackColor       =   &H003D2E27&
            BorderStyle     =   0  'None
            ForeColor       =   &H00FFFFFF&
            Height          =   285
            Left            =   240
            TabIndex        =   24
            TabStop         =   0   'False
            Top             =   120
            Width           =   7215
         End
         Begin VB.Shape s3 
            BackColor       =   &H003D2E27&
            BackStyle       =   1  'Opaque
            BorderStyle     =   0  'Transparent
            Height          =   495
            Left            =   240
            Top             =   0
            Width           =   735
         End
      End
      Begin VB.PictureBox IRC 
         Appearance      =   0  'Flat
         AutoRedraw      =   -1  'True
         BackColor       =   &H001B1410&
         BorderStyle     =   0  'None
         ForeColor       =   &H00FFFFFF&
         Height          =   3015
         Left            =   480
         ScaleHeight     =   3015
         ScaleWidth      =   4815
         TabIndex        =   22
         TabStop         =   0   'False
         Top             =   1440
         Width           =   4815
      End
      Begin VB.Timer tmrPrintChat 
         Interval        =   500
         Left            =   9840
         Top             =   8160
      End
      Begin VB.Label cSize 
         AutoSize        =   -1  'True
         Caption         =   "Label7"
         Height          =   240
         Left            =   240
         TabIndex        =   30
         Top             =   3000
         Visible         =   0   'False
         Width           =   720
      End
   End
   Begin VB.Timer tmrMusic 
      Interval        =   2000
      Left            =   9480
      Top             =   6840
   End
   Begin VB.FileListBox FileMusic 
      Height          =   240
      Left            =   8760
      Pattern         =   "*.mp3"
      TabIndex        =   20
      TabStop         =   0   'False
      Top             =   64800
      Visible         =   0   'False
      Width           =   375
   End
   Begin VB.ListBox ListOfUsers 
      Height          =   540
      Left            =   2760
      Sorted          =   -1  'True
      TabIndex        =   18
      TabStop         =   0   'False
      Top             =   7800
      Visible         =   0   'False
      Width           =   735
   End
   Begin VB.Timer tmrKeepOnline 
      Interval        =   10000
      Left            =   6240
      Top             =   8040
   End
   Begin VB.PictureBox picsandstuff 
      Height          =   1215
      Left            =   2280
      ScaleHeight     =   1155
      ScaleWidth      =   4155
      TabIndex        =   16
      TabStop         =   0   'False
      Top             =   7680
      Visible         =   0   'False
      Width           =   4215
      Begin VB.Image MiniMenuA 
         Height          =   480
         Left            =   240
         Picture         =   "frmConsole.frx":1982
         Top             =   0
         Width           =   2370
      End
      Begin VB.Image MiniMenuB 
         Height          =   480
         Left            =   240
         Picture         =   "frmConsole.frx":5544
         Top             =   600
         Width           =   2370
      End
   End
   Begin VB.PictureBox MiniMenu 
      Appearance      =   0  'Flat
      AutoSize        =   -1  'True
      BackColor       =   &H00000000&
      BorderStyle     =   0  'None
      ForeColor       =   &H80000008&
      Height          =   480
      Left            =   2640
      Picture         =   "frmConsole.frx":9106
      ScaleHeight     =   480
      ScaleWidth      =   2370
      TabIndex        =   10
      TabStop         =   0   'False
      Top             =   6720
      Width           =   2370
      Begin VB.Label Label4 
         BackStyle       =   0  'Transparent
         Height          =   375
         Left            =   1980
         TabIndex        =   19
         Top             =   0
         Width           =   375
      End
      Begin VB.Label Label3 
         BackStyle       =   0  'Transparent
         Height          =   495
         Left            =   1480
         TabIndex        =   17
         Top             =   0
         Width           =   375
      End
      Begin VB.Label lFull 
         BackStyle       =   0  'Transparent
         Height          =   495
         Left            =   1050
         TabIndex        =   15
         Top             =   0
         Width           =   315
      End
      Begin VB.Label lConsole 
         BackStyle       =   0  'Transparent
         Height          =   375
         Index           =   4
         Left            =   720
         TabIndex        =   14
         Top             =   0
         Width           =   240
      End
      Begin VB.Label lConsole 
         BackStyle       =   0  'Transparent
         Height          =   375
         Index           =   3
         Left            =   480
         TabIndex        =   13
         Top             =   0
         Width           =   240
      End
      Begin VB.Label lConsole 
         BackStyle       =   0  'Transparent
         Height          =   375
         Index           =   2
         Left            =   240
         TabIndex        =   12
         Top             =   0
         Width           =   240
      End
      Begin VB.Label lConsole 
         BackStyle       =   0  'Transparent
         Height          =   375
         Index           =   1
         Left            =   0
         TabIndex        =   11
         Top             =   0
         Width           =   240
      End
      Begin VB.Shape consoleShape 
         BackStyle       =   1  'Opaque
         BorderStyle     =   0  'Transparent
         Height          =   135
         Left            =   2280
         Top             =   480
         Width           =   135
      End
   End
   Begin VB.Timer tmrPrint 
      Interval        =   1
      Left            =   5280
      Top             =   5280
   End
   Begin VB.Timer tmrFlash 
      Interval        =   150
      Left            =   6600
      Top             =   5280
   End
   Begin VB.Timer tmrStart 
      Interval        =   1000
      Left            =   4200
      Top             =   5280
   End
   Begin VB.PictureBox Stats 
      Appearance      =   0  'Flat
      BackColor       =   &H0047362C&
      BorderStyle     =   0  'None
      ForeColor       =   &H80000008&
      Height          =   495
      Left            =   0
      ScaleHeight     =   495
      ScaleWidth      =   8055
      TabIndex        =   2
      TabStop         =   0   'False
      Top             =   0
      Width           =   8055
      Begin VB.PictureBox ExitBox 
         Appearance      =   0  'Flat
         AutoSize        =   -1  'True
         BackColor       =   &H80000005&
         BorderStyle     =   0  'None
         ForeColor       =   &H80000008&
         Height          =   300
         Left            =   6720
         Picture         =   "frmConsole.frx":CCC8
         ScaleHeight     =   300
         ScaleWidth      =   930
         TabIndex        =   7
         TabStop         =   0   'False
         Top             =   120
         Width           =   930
         Begin VB.Label Label2 
            BackStyle       =   0  'Transparent
            Height          =   375
            Left            =   150
            TabIndex        =   9
            Top             =   0
            Width           =   375
         End
         Begin VB.Label Label1 
            BackStyle       =   0  'Transparent
            Height          =   375
            Left            =   570
            TabIndex        =   8
            Top             =   0
            Width           =   375
         End
      End
      Begin VB.Shape Shape1 
         BackColor       =   &H000000FF&
         BackStyle       =   1  'Opaque
         BorderStyle     =   0  'Transparent
         Height          =   255
         Left            =   120
         Shape           =   4  'Rounded Rectangle
         Top             =   120
         Width           =   120
      End
      Begin VB.Label lblUsername 
         BackColor       =   &H00644D3E&
         BackStyle       =   0  'Transparent
         Caption         =   "Not Connected."
         ForeColor       =   &H00E0E0E0&
         Height          =   255
         Left            =   360
         TabIndex        =   3
         Top             =   120
         Width           =   6375
      End
   End
   Begin VB.PictureBox Comm 
      Appearance      =   0  'Flat
      AutoRedraw      =   -1  'True
      BackColor       =   &H002D211C&
      BorderStyle     =   0  'None
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   8.25
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H00E99A9C&
      Height          =   1815
      Left            =   0
      ScaleHeight     =   1815
      ScaleWidth      =   7575
      TabIndex        =   1
      TabStop         =   0   'False
      Top             =   480
      Width           =   7575
      Begin VB.Image CommLowerBorder 
         Height          =   150
         Left            =   360
         Picture         =   "frmConsole.frx":DBBA
         Stretch         =   -1  'True
         Top             =   1680
         Width           =   300
      End
      Begin VB.Label lComm 
         BackStyle       =   0  'Transparent
         Caption         =   "Label1"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   8.25
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         ForeColor       =   &H0066E1FB&
         Height          =   255
         Index           =   0
         Left            =   1080
         TabIndex        =   6
         Top             =   1320
         Visible         =   0   'False
         Width           =   57750
      End
      Begin VB.Label lCommTime 
         Alignment       =   1  'Right Justify
         BackStyle       =   0  'Transparent
         Caption         =   "00:00"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   8.25
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         ForeColor       =   &H00FFFFFF&
         Height          =   255
         Index           =   0
         Left            =   -480
         TabIndex        =   5
         Top             =   1320
         Visible         =   0   'False
         Width           =   1455
      End
   End
   Begin VB.PictureBox Sidebar 
      AutoSize        =   -1  'True
      BackColor       =   &H00000000&
      BorderStyle     =   0  'None
      Height          =   2415
      Left            =   240
      ScaleHeight     =   2415
      ScaleWidth      =   615
      TabIndex        =   4
      TabStop         =   0   'False
      Top             =   2640
      Width           =   615
   End
   Begin VB.PictureBox MP 
      Height          =   3495
      Left            =   4320
      ScaleHeight     =   3435
      ScaleWidth      =   4275
      TabIndex        =   31
      TabStop         =   0   'False
      Top             =   4680
      Visible         =   0   'False
      Width           =   4335
   End
   Begin VB.Label lfont 
      AutoSize        =   -1  'True
      BackStyle       =   0  'Transparent
      Caption         =   "this is to check the height OF FONTS"
      ForeColor       =   &H007EE084&
      Height          =   240
      Left            =   5160
      TabIndex        =   0
      Top             =   3960
      Visible         =   0   'False
      Width           =   3915
   End
End
Attribute VB_Name = "frmConsole"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'Option Explicit -- leave this disabled on frmConsole

'--------------------------------------------------------------
'variables for IRC chat
Dim ircMsgs(49) As String
Dim curMsg As Integer

Dim chatToStatus As Boolean
Dim oldnick$    'the backup if the nick change failed
Dim nick$       'our global nickname var
Dim channel$    'our channel var
Dim Data$       'the var that will hold the data of a single command
Dim MyRandNum$
Dim connected As Boolean  'this var will be used to check if we timed out, and will be set to true if get connected
'--------------------------------------------------------------

Dim autoCompActive(1 To 4) As Boolean
Dim autoCompLast(1 To 4) As String
Dim autoILast(1 To 4) As Integer


Sub CommLarger()
    If Comm.Height < ((Me.Height / 3) * 2) Then
        Comm.Height = Comm.Height + 480
    End If
    
    SayCOMM ""
End Sub


Sub CommSmaller()
    If Comm.Height > 480 Then
        Comm.Height = Comm.Height - 480
    Else
        Comm.Height = 0
    End If
    
    SayCOMM ""
End Sub


Sub SetConsoleActive(ByVal ConsoleID As Integer)
    Print_Console

    consoleShape.Width = 120
    consoleShape.Height = 60
    consoleShape.Top = MiniMenu.Height - consoleShape.Height - 60
    
    Select Case ConsoleID
        Case 1: consoleShape.Left = 90
        Case 2: consoleShape.Left = 320
        Case 3: consoleShape.Left = 540
        Case 4: consoleShape.Left = 750
    End Select
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    If KeyCode = vbKeyEscape Then
        Unload Me
    End If
 
    If KeyCode = vbKeyPageDown And Shift = 1 Then CommLarger: Exit Sub
    If KeyCode = vbKeyPageUp And Shift = 1 Then CommSmaller: Exit Sub
    If KeyCode = vbKeyPageDown And Shift = 0 Then ScrollConsoleDown: Exit Sub
    If KeyCode = vbKeyPageUp And Shift = 0 Then ScrollConsoleUp: Exit Sub
    ConsoleScrollInt(ActiveConsole) = 0
    
    If KeyCode = vbKeyF1 Then ChatBox.Visible = False: ActiveConsole = 1: SetConsoleActive 1: Exit Sub
    If KeyCode = vbKeyF2 Then ChatBox.Visible = False: ActiveConsole = 2: SetConsoleActive 2: Exit Sub
    If KeyCode = vbKeyF3 Then ChatBox.Visible = False: ActiveConsole = 3: SetConsoleActive 3: Exit Sub
    If KeyCode = vbKeyF4 Then ChatBox.Visible = False: ActiveConsole = 4: SetConsoleActive 4: Exit Sub
    If KeyCode = vbKeyF5 Then ShowChat: Exit Sub
    
    If KeyCode = vbKeyF11 Then ToggleConsoleFull: Exit Sub
    
    If Shift = 2 And KeyCode = vbKeyC Then
        'cancel the running script
        CancelScript(ActiveConsole) = True
        Exit Sub
    End If
    
    
    autoCompActive(ActiveConsole) = False
    
    'it's getkey!
    If GetKeyWaiting(ActiveConsole) = -1 Then
        GetKeyWaiting(ActiveConsole) = KeyCode: Exit Sub
    End If
    If GetAsciiWaiting(ActiveConsole) = -1 Then Exit Sub
    'If GetAsciiWaiting(ActiveConsole) = "2" Then Exit Sub

    
    
    If ConsolePaused(ActiveConsole) = True Then
        ConsolePaused(ActiveConsole) = False
        New_Console_Line ActiveConsole
        Exit Sub
    End If
    
    
        
    If ChatBox.Visible = True Then
        If KeyCode = vbKeyDown Then
            If curMsg > 0 Then
                curMsg = curMsg - 1
                txtChatMsg.Text = ircMsgs(curMsg) & " "
                txtChatMsg.SelStart = Len(txtChatMsg.Text)
            Else
                txtChatMsg.Text = ""
            End If
            Exit Sub
        End If
        If KeyCode = vbKeyUp Then
           If curMsg < 48 And ircMsgs(curMsg + 1) <> "" Then
                curMsg = curMsg + 1
                txtChatMsg.Text = ircMsgs(curMsg) & " "
                txtChatMsg.SelStart = Len(txtChatMsg.Text)
           End If
           Exit Sub
        End If
    Else
        If KeyCode = vbKeyUp Or KeyCode = vbKeyDown Then
            Dim tmpS As String, tmpInputString As String
            If InStr(Console(ActiveConsole, 1).Caption, ">") > 0 Then
                tmpS = Mid(Console(ActiveConsole, 1).Caption, InStr(Console(ActiveConsole, 1).Caption, ">") + 1, Len(Console(ActiveConsole, 1).Caption))
                tmpInputString = Mid(Console(ActiveConsole, 1).Caption, 1, InStr(Console(ActiveConsole, 1).Caption, ">") + 1)
            Else
                tmpS = Console(ActiveConsole, 1).Caption
                tmpInputString = ""
            End If
            tmpS = Trim(Replace(tmpS, "_", ""))
            'don't exit sub here
        End If
    
        If KeyCode = vbKeyDown Then
            If RecentCommandsIndex(ActiveConsole) <= 0 Then Exit Sub
            RecentCommandsIndex(ActiveConsole) = RecentCommandsIndex(ActiveConsole) - 1
            Console(ActiveConsole, 1).Caption = tmpInputString & RecentCommands(ActiveConsole, RecentCommandsIndex(ActiveConsole)) & "_"
            Exit Sub
        End If
        If KeyCode = vbKeyUp Then
            If RecentCommandsIndex(ActiveConsole) >= 99 Then Exit Sub
            If Trim(RecentCommands(ActiveConsole, RecentCommandsIndex(ActiveConsole) + 1)) = "" Then Exit Sub
            RecentCommandsIndex(ActiveConsole) = RecentCommandsIndex(ActiveConsole) + 1
            If RecentCommandsIndex(ActiveConsole) = 1 Then RecentCommands(ActiveConsole, 0) = tmpS
            Console(ActiveConsole, 1).Caption = tmpInputString & RecentCommands(ActiveConsole, RecentCommandsIndex(ActiveConsole)) & "_"
            Exit Sub
        End If
    End If
    
    
    
    

    Add_Key KeyCode, Shift, ActiveConsole
    Print_Console

End Sub


Public Sub ToggleConsoleFull()
        Comm.Visible = Not (Comm.Visible)
        Stats.Visible = Not (Stats.Visible)
    
        If Stats.Visible = True Then
             ChatBox.Move 0, Stats.Height
             ChatBox.Height = Screen.Height - 600 - Stats.Height
            MiniMenu.Picture = MiniMenuA.Picture
        Else
            MiniMenu.Picture = MiniMenuB.Picture
            ChatBox.Height = Screen.Height - 600
            ChatBox.Move 0, 0
        End If
End Sub


Public Sub ScrollConsoleUp()
    If ConsoleScrollInt(ActiveConsole) > 9 Then ConsoleScrollInt(ActiveConsole) = 9
    ConsoleScrollInt(ActiveConsole) = ConsoleScrollInt(ActiveConsole) + 1
    
End Sub

Public Sub ScrollConsoleDown()
    ConsoleScrollInt(ActiveConsole) = ConsoleScrollInt(ActiveConsole) - 1
    If ConsoleScrollInt(ActiveConsole) < 1 Then ConsoleScrollInt(ActiveConsole) = 0
    
End Sub

Private Sub Form_KeyPress(KeyAscii As Integer)
    'it's getascii!
    If GetAsciiWaiting(ActiveConsole) = -1 Then
        GetAsciiWaiting(ActiveConsole) = KeyAscii
    End If
End Sub

Public Function getConnected()
    getConnected = connected
End Function

Public Sub setConnected(Value As Boolean)
    connected = Value
End Sub

Private Sub Form_Load()
    basCommands.InitBasCommands
    basWorld.InitBasWorld

    Dim X As Integer
    For X = 1 To 30
        Load tmrProcessQueue(X)
        tmrProcessQueue(X).Enabled = False
        tmrProcessQueue(X).Interval = 1
    Next

    curMsg = 0
    connected = False
    chatToStatus = RegLoad("ChatView", False)
    ActiveConsole = 1
    MusicFileIndex = -1
    

    Me.Move 0, 0, Screen.Width, Screen.Height
    
    cPath(1) = "/": cPath(2) = "/": cPath(3) = "/": cPath(4) = "/": cPath(5) = "/"
    Start_Comm
    
    Stats.Move 0, 0, Me.Width + 120
    Sidebar.Move 0, 0, 240, Me.Height
    ExitBox.Move Me.Width - ExitBox.Width - 120, 90
    MiniMenu.BackColor = frmConsole.BackColor
    MiniMenu.Move Me.Width - MiniMenu.Width - 240, Me.Height - MiniMenu.Height
    
    yDiv = 60
    Authorized = False
    ConsolePaused(ActiveConsole) = False
    WaitingForInput(1) = False: WaitingForInput(2) = False: WaitingForInput(3) = False: WaitingForInput(4) = False

    SetConsoleActive 1
    
    CheckMusic

    LoadIRC
   
    RegisterWindow Me.hWnd
End Sub

Sub ConnectIRC()
    sockIRC.Connect IRC_Server, IRC_Port, ucsSckSupportTls12 + ucsSckSupportTls13
End Sub

Sub LoadIRC()
    
    Randomize
    TBox.BackColor = Me.BackColor
    
    'Me.Width = (Screen.Width / 5) * 4
    'Me.Height = (Screen.Height / 5) * 4
    ChatBox.Width = Screen.Width
    ChatBox.Height = Screen.Height - 600 - Stats.Height
    ChatBox.Move 0, Stats.Height
    MyRandNum$ = (Int((99 - 10 + 1) * Rnd) + 10)
    'nick$ = MyIRCName 'fetch the nickname from the dialog
    channel$ = "#darksignsonline"  'fetch the channel form the dialog
    
    
    
    
    'txtNick.Text = MyIRCName     'set the nick text field to the nickname
    'txtChannel.Text = channel$ 'set the channel text field to the current channel
    
End Sub


Sub Start_Comm()
    Comm.Move 0, 480, Me.Width, (Screen.Height / 7)
    
    Dim n As Integer
    For n = 1 To UBound(Comms)
        Load lCommTime(n)
        Load lComm(n)
        
        lCommTime(n).Caption = ""
        lComm(n).Caption = ""
        
        lCommTime(n).Visible = True
        lComm(n).Visible = True
    Next n
    
    CommLowerBorder.Move 0, Comm.Height - CommLowerBorder.Height, Comm.Width
    
End Sub

Private Sub Form_Resize()
    IRCChatResize
End Sub

Sub IRCChatResize()
    On Error Resume Next
    
    ChatBox.BackColor = vbBlack
    TBox.BackColor = vbBlack
    
    lstUsers.Width = (Me.Width / 5) * 1
    
    txtChat.Width = ((Me.Width / 5) * 4) - 230
    
    txtChat.Left = 120
    lstUsers.Move txtChat.Left + txtChat.Width + 120, txtChat.Top
    
    txtChat.Height = Me.Height - txtChat.Top - 1200
    
    lstUsers.Height = txtChat.Height
    
    
    IRC.Move txtChat.Left, txtChat.Top, txtChat.Width, txtChat.Height
    IRC.Height = ChatBox.Height - TBox.Height - IRC.Top - 480
    
    TBox.Top = IRC.Top + IRC.Height + 120
    TBox.Left = IRC.Left
    
    TBox.Width = txtChat.Width
    cmdChat.Left = TBox.Width - cmdChat.Width - 120
    
    txtChatMsg.Left = 240
    txtChatMsg.Width = cmdChat.Left - 240 - txtChatMsg.Left
    
    s1.Move txtTarget.Left - 60, txtTarget.Top - 60, txtTarget.Width + 120, txtTarget.Height + 120
    s2.Move txtPrivMsg.Left - 60, txtPrivMsg.Top - 60, txtPrivMsg.Width + 120, txtPrivMsg.Height + 120
    
    s3.Move txtChatMsg.Left - 60, txtChatMsg.Top - 60, txtChatMsg.Width + 130, txtChatMsg.Height + 130
    
    
    
    
    
End Sub

Private Sub Form_Terminate()
    basMusic.StopMusic
    UnregisterWindow Me.hWnd
End Sub

Private Sub Form_Unload(Cancel As Integer)
    
    
    '------------------------------------------
    'for the chat
    If connected Then
        Response = MsgBox("Are you sure you want to disconnect and exit?", vbYesNo + vbQuestion, "Dark Signs Online")  'ask the user if he really wants to quit
        If Not (Response = vbYes) Then  'if he didn't want to quit
            Cancel = 1  'cancel the unload
            Exit Sub    'exit the sub
        End If
        Send "QUIT :darksignsonline.com, Dark Signs Online"    'send the quit message
        lstUsers.Clear  'clear the list entries
        display "XXXXXXxxxxxxxxx...... Disconnected"    'display a message
        sockIRC.Close_   'close the connection
    End If
    '------------------------------------------
    
    basMusic.StopMusic
    UnregisterWindow Me.hWnd
    
    End
End Sub


Private Sub IRC_MouseDown(Button As Integer, Shift As Integer, X As Single, Y As Single)
    On Error Resume Next
    txtChatMsg.SetFocus
End Sub

Private Sub Label1_Click()
    Unload Me
End Sub

Private Sub Label2_Click()
    
    Me.WindowState = vbMinimized
    'Me.WindowState = vbNormal
    
    
End Sub

Private Sub Label3_Click()
    
    ShowChat
    
    
    
End Sub

Sub ShowChat()
    
    ChatBox.Visible = True
    ChatBox.ZOrder 0
    
    
    consoleShape.Left = 1600
    
    DoEvents
    On Error Resume Next
    Me.txtChatMsg.SetFocus
    
End Sub



Private Sub Label4_Click()
    frmLibrary.Show vbModal
End Sub

Private Sub lblUsername_Click()
    If InStr(i(lblUsername), "log") > 0 Then
        MsgBox "Welcome to Dark Signs Online!" & vbCrLf & vbCrLf & _
        "Set your username by typing: USERNAME [username]" & vbCrLf & _
        "Set your password by typing: PASSWORD [password]" & vbCrLf & vbCrLf & _
        "Dark Signs requires that each user has their own account." & vbCrLf & vbCrLf & _
        "Visit darksignsonline.com to create a new account." _
        , vbInformation, "About"
        
    End If
End Sub

Private Sub lConsole_Click(Index As Integer)
    
    ChatBox.Visible = False
    
    ActiveConsole = Index
    
    SetConsoleActive Index
End Sub

Private Sub lFull_Click()
    ToggleConsoleFull
End Sub


Private Sub Stats_MouseDown(Button As Integer, Shift As Integer, X As Single, Y As Single)
    If X > (Stats.Width - 120) And Y < 60 Then
        Unload Me
    End If
End Sub


Private Sub tmrFlash_Timer()
    FlashCounter = FlashCounter + 1
    
    FlashFast = Not (FlashFast)
    If FlashCounter Mod 2 = 1 Then Flash = Not (Flash)
    If FlashCounter Mod 5 = 1 Then FlashSlow = Not (FlashSlow)

    frmConsole.QueueConsoleRender
End Sub


Private Sub tmrKeepOnline_Timer()
    'KeepOnline
    basWorld.CleanHttpRequests
End Sub

Public Sub KeepOnline()
    If Authorized = True Then
        RunPage "z_online.php?get=1", ActiveConsole
    End If
End Sub

Private Sub tmrMusic_Timer()
    basMusic.CheckMusic
End Sub

Public Sub QueueConsoleRender()
    tmrPrint.Enabled = True
End Sub

Private Sub tmrPrint_Timer()
    Print_Console
    tmrPrint.Enabled = False
End Sub

Private Sub tmrProcessQueue_Timer(Index As Integer)
    tmrProcessQueue(Index).Enabled = False
    basWorld.ProcessQueueEntryRun Index
    tmrProcessQueue(Index).Tag = ""
End Sub

Private Sub tmrStart_Timer()
    tmrStart = False
    
    Start_Console 1
    Start_Console 2
    Start_Console 3
    Start_Console 4
End Sub

Public Sub Start_Console(ByVal ConsoleID As Integer)
    Reset_Console ConsoleID

    Dim EmptyParams(0 To 0) As Variant
    EmptyParams(0) = ""
    If ConsoleID = 1 Then
        'run the primary startup script
        Run_Script "/system/startup.ds", ConsoleID, EmptyParams, "BOOT", True, False, False
    Else
        Run_Script "/system/newconsole.ds", ConsoleID, EmptyParams, "BOOT", True, False, False
    End If
End Sub

Private Sub tmrPrintChat_Timer()
    PrintAll
End Sub

Private Sub txtChatMsg_GotFocus()
    cmdChat.Default = True  'set the chat button as the default button
End Sub

Private Sub txtPrivMsg_GotFocus()
    cmdPriv.Default = True  'set the private button as the default button
End Sub

'Private Sub txtStatus_DblClick()
'    c$ = InputBox("Please enter a command (eg. PRIVMSG Bot :Hello bot)" + vbCrLf + vbCrLf + "Command:", "Custom command")
'        'let the user enter a command
'    c$ = Trim(c$)   'clear any leading whitespace characters
'    If c$ = "" Then Exit Sub    'if the user canceled exit...
'    If UCase(Left(c$, 4)) = "JOIN" Then 'if the user wants to join a channel:
'        send "PART " + channel$ 'leave the current channel
'        lstUsers.Clear  'clear the user list
'        send "JOIN " + processParam(processRest(c$))    'only join first channel supplied by the user
'        channel$ = processParam(processRest(c$))    'store the channel
'        txtChannel.Text = channel$  'change the channel text box
'    ElseIf UCase(Left(c$, 4)) = "PART" Then     'if the user wants to leave the channel
'        lstUsers.Clear  'clear the user list
'        send "PART " + channel$ 'leave the channel
'        channel$ = ""   'clear the channel holder
'        txtChannel = channel$   'clear the text box
'    ElseIf UCase(Left(c$, 4)) = "NICK" Then     'if the user want to change his nickname
'        MsgBox processParam(processRest(c$))
'        'txtNick.Text = processParam(processRest(c$))    'store the first parameter in the nick text field
'        '''cmdNick_Click   'make it click the change nick button
'    ElseIf UCase(Left(c$, 4)) = "QUIT" Then 'if the user wants to quit
'        display "<!> QUIT message canceled! Please click the X button in the bottom right corner of the window!"
'            'dont do it, just display this message
'    Else    'if its an innocent command :)
'        send c$     'send it
'    End If
'End Sub

Private Sub txtStatus_KeyPress(KeyAscii As Integer)
    KeyAscii = 0    'ignore the keypress
End Sub

Sub display(Msg$)   'display a message in the status field:
    txtStatus.Text = txtStatus.Text + Msg$ + vbCrLf   ' add the message to the status field
    txtStatus.SelStart = Len(txtStatus.Text)  'select the end of the message
    txtStatus.SelLength = 0                'make sure nothing is displayed as "selected"
End Sub

Sub displaychat(Msg$)   'display a message in the chat field:
    If chatToStatus = True Then
        SayCOMM Msg$
    End If
    txtChat.Text = txtChat.Text + Msg$ + vbCrLf   ' add the message to the chat field
    txtChat.SelStart = Len(txtChat.Text)  'select the end of the message
    txtChat.SelLength = 0                'make sure nothing is displayed as "selected"
End Sub

Sub Send(Msg$)  'send a message to the IRC server
On Error GoTo oops  'if an error occures, goto the oops label
    'display ">> " + msg$    ' display the text in the main field
    sockIRC.SendData Msg$ + vbCrLf  'send the data, along with a cariage return and a line feed
    Exit Sub    'skip the error handling section
oops:
    'MsgBox "An error has occured while trying to send data to the server." + vbCrLf + "You may have been disconnected!", vbInformation, "Error"
End Sub

Sub processCommand()
    


    ' the next line will reply to the PING message of the server
    ' preventing us from going idle and being kicked
    If InStr(Data$, "PING") > 0 Then
        Dim Params$    ' parameters that will be filtered from the pong message
        Params$ = Right$(Data$, Len(Data$) - (InStr(Data$, "PING") + 4))
            'take the paramaters from the right of the message starting from the first character after the PING message
        Send "PONG " + Params$   ' send the pong message to the server, together with the parameters
        display "PING? PONG!"
    End If
    
    'This section processes all other commands
    If Left$(Data$, 1) = ":" Then   'if the message starts with a colon (standard IRC message)
        Dim Pos%, pos2%    '2 position variables we need to extract the nickname of whoever that issued the command
        Dim from$, rest$    'these will hold the sender of the command and the rest of the message
        Dim Command$        'this will hold the type of the command (eg.: PRIVMSG)
        Params$ = ""        'and the parameters
        Pos% = InStr(Data$, " ")    'get the position of the first space character
        If Pos% > 0 Then    'if a space is found
            pos2% = InStr(Data$, "!")   'search for an exclamation mark
            If Pos% < pos2% Or pos2% <= 0 Then pos2% = Pos%   'if a space is found AFTER the space, it should not be used
            from$ = Mid$(Data$, 2, pos2% - 2)   'parse the sender, starting from the second character (after the ":")
            rest$ = Mid$(Data$, Pos% + 1, Len(Data$) - pos2%)  'parse the rest of the message starting from the first character AFTER the first space
            rest$ = Replace(rest$, Chr(2), "")
            
            'IMPORTANT: pos% is now used to hold the first space in (!) rest$ (!), *NOT* in data$
            Pos% = InStr(rest$, " ")   'get the position of the first space in rest$
            If Pos% > 0 Then    'if we found a space
                Command$ = Left$(rest$, Pos% - 1)   'the part before this space is the type of command
                Params$ = Right$(rest$, Len(rest$) - Pos%)   'the rest are parameters
                Select Case Command$    'base your actions on the type of command
                    Case "NOTICE"   'if it's a notice
                        displaychat ">> " + from$ + "  " + Params$ 'display it
                    Case "PRIVMSG"  'if it's a private message
                        
                        If processParam(Params$) = channel$ Then
                            tempStr = processParam(processRest(Params$))
                            If (Mid(tempStr, 2, 6) = "ACTION") Then
                                displaychat "* " + from$ + " " + Right(tempStr, Len(tempStr) - 8)   'display the message
                            Else
                                displaychat "<" + from$ + ">  " + processParam(processRest(Params$))     'display the message
                            End If
                                'if you want autoreplies, autoevents, ... , just add them here
                        ElseIf processParam(Params$) = nick$ Then
                            displaychat ">>" + from$ + "<<  " + processParam(processRest(Params$)) 'display the message
                                'if you want autoreplies, autoevents, ... , just add them here
                        Else
                            displaychat "(!!!) <" + from$ + "> " + Params$    'display it
                        End If
                    Case "JOIN" 'if someone joined
                        displaychat "** " + from$ + " has joined " + processParam(Params$) + " **"     'display it
                        'check if the user is already in the list
                        X% = -1  'start checking from the first user (-1 + 1 = 0)
                        Do
                            X% = X% + 1     'increase x% with 1
                            If X% = lstUsers.ListCount Then 'if the user is not found ...
                                X% = -1     'set the user to be removed to -1 (ERROR :-) )
                                Exit Do     'exit the loop
                            End If
                        Loop Until lstUsers.List(X%) = from$    'loop until we find the user
                        'if x% = -1, the user was not found in the list, so we can add him
                        If X% = -1 Then lstUsers.AddItem (from$)    'add this user to the user list
                        'lblCount.Caption = lstUsers.ListCount & " people in channel"    'update the user count
                    Case "QUIT" 'if someone disconnected
                        displaychat "** " + from$ + " has quit IRC (" + processParam(Params$) + ") **"    'display it
                        'check if the user is already in the list
                        X% = -1  'start checking from the first user (-1 + 1 = 0)
                        Do
                            X% = X% + 1     'increase x% with 1
                            If X% = lstUsers.ListCount Then 'if the user is not found ...
                                X% = -1     'set the user to be removed to -1 (ERROR :-) )
                                Exit Do     'exit the loop
                            End If
                        Loop Until lstUsers.List(X%) = from$    'loop until we find the user
                        If X% > -1 Then lstUsers.RemoveItem (X%)    'if we found a matching user in the list, remove it
                        'lblCount.Caption = lstUsers.ListCount & " people in channel"    'update the user count
                    Case "NICK" 'if someone changed his nickname
                        If from$ = nick$ Then
                            nick$ = processParam(Params$)
                            RegSave "ircName", nick$
                        End If
                        displaychat "** " + from$ + " changed his nickname to " + processParam(Params$) + " **"    'display it
                        'check if the user is already in the list
                        X% = -1  'start checking from the first user (-1 + 1 = 0)
                        Do
                            X% = X% + 1     'increase x% with 1
                            If X% = lstUsers.ListCount Then 'if the user is not found ...
                                X% = -1     'set the user to be removed to -1 (ERROR :-) )
                                Exit Do     'exit the loop
                            End If
                        Loop Until lstUsers.List(X%) = from$    'loop until we find the user
                        If X% > -1 Then
                            lstUsers.RemoveItem (X%)    'if we found a matching user in the list, remove it
                            lstUsers.AddItem (processParam(Params$))    'and add the new nick
                        End If
                        'lblCount.Caption = lstUsers.ListCount & " people in channel"    'update the user count
                    Case "PART" ' if someone left the channel
                        displaychat "** " + from$ + " has left " + Params$ + " **"    'display it
                        'check if the user is allready in the list
                        X% = -1  'start checking from the first user (-1 + 1 = 0)
                        Do
                            X% = X% + 1
                            If X% = lstUsers.ListCount Then 'if the user is not found ...
                                X% = -1     'set the user to be removed to -1 (ERROR :-) )
                                Exit Do     'exit the loop
                            End If
                        Loop Until lstUsers.List(X%) = from$    'loop until we find the user
                        If X% > -1 Then lstUsers.RemoveItem (X%)    'if we found a matching user in the list, remove it
                        'lblCount.Caption = lstUsers.ListCount & " people in channel"    'update the user count
                    Case "MODE"     'if someone sets the mode on someone
                        displaychat "** " + from$ + " sets mode " + processParam(processRest(Params$)) + " on " + processParam(Params$) + " **" 'display the mode change
                    Case "TOPIC"    'if the topic message is received
                        displaychat "TOPIC MESSAGE:"
                        displaychat processParam(Params$)             'Display the channel topic
                    Case "331"  'if you recieve a message saying "no topic set"
                        displaychat "No topic set in " + processParam(processRest(Params$)) 'display it
                            'by displaying the second parameter
                    Case "353"  'if we received the channel user list
                        display "<" + from$ + "> " + rest$ 'display the unprocessed message
                        Dim nick2$, othernicks$    'take one nick at a time
                        othernicks$ = processParam(processRest(processRest(processRest(Params$))))   'cut of the channel parameter, the nick parameter and the "="
                        Do
                            nick2$ = processParam(othernicks$)   'take one nick
                            othernicks$ = processRest(othernicks$)   'and take it out of the remaining nicks
                            'Do Until Left$(nick2$, 1) <> "@" And Left$(nick2$, 1) <> "+"  'cut of the @ and + flags at the beginning ...
                                'nick2$ = Right(nick2$, Len(nick2$) - 1) 'cut of the first character
                            'Loop
                            X% = -1  'start checking from the first user (-1 + 1 = 0)
                            Do
                                X% = X% + 1     'increase x% with 1
                                If X% = lstUsers.ListCount Then 'if the user is not found ...
                                    X% = -1     'set the user to be removed to -1 (ERROR :-) )
                                    Exit Do     'exit the loop
                                End If
                            Loop Until lstUsers.List(X%) = nick2$    'loop until we find the user
                            'if x% = -1, the user was not found in the list, so we can add him
                            If X% = -1 Then lstUsers.AddItem (nick2$)    'add this user to the user list
                        Loop Until othernicks$ = ""     'loop through all the received nicknames
                        'lblCount.Caption = lstUsers.ListCount & " people in channel"    'update the user count
                    Case "376"    'end of the motd
                        display "<" + from$ + "> " + rest$ 'display the unprocessed message
                        Send "JOIN " + channel$ 'join the channel
                    Case "431"  'if we failed to change the nickname
                        nick$ = oldnick$    'change it back to the old one
                        display "<!> Failed changing nickname (You have to supply a nickname)" 'let them know that it failed
                        txtNick.Text = nick$    'change the content of the nick text field back
                    Case "432"  'if we failed to change the nickname
                        nick$ = oldnick$    'change it back to the old one
                        display "<!> Failed changing nickname (The nickname you entered is not valid)" 'let them know that it failed
                        txtNick.Text = nick$    'change the content of the nick text field back
                    Case "433"  'if we failed to change the nickname
                        nick$ = oldnick$    'change it back to the old one
                        display "<!> Failed changing nickname (The nickname is already in use)" 'let them know that it failed
                        'this died for some reason txtNick.Text = nick$    'change the content of the nick text field back
                    Case Else   'if it's another message
                      display "<" + from$ + "> " + rest$ 'display the unprocessed message
                End Select
            Else   'if we failed
                display "<" + from$ + "> " + rest$ 'display the unprocessed message
            End If
        Else    'if we failed
            display "<" + from$ + "> " + rest$ 'display the unprocessed message
        End If
    End If
End Sub

Function processParam(Msg$) As String    'process a parameter (parse it from the other ones):
    If (Left$(Msg$, 1) = ":") Then  'if the parameter starts with a colon, the entire msg$ is a single parameter (containing spaces)
        processParam = Right$(Msg$, Len(Msg$) - 1)   'return the message, except for the colon
    Else    'if its not a multi word parameter
        If InStr(Msg$, " ") - 1 > 0 Then    'if there are any remaining parameters except the first one
            processParam = Mid$(Msg$, 1, InStr(Msg$, " ") - 1)    'return the part before the first space
        Else
            processParam = Msg$ 'if there is only one parameter in the string return it
        End If
    End If
End Function

Function processRest(Msg$) As String    'process the rest of the message:
    If (Left$(Msg$, 1) = ":") Then  'if the parameter starts with a colon, the entire msg$ is a single parameter (containing spaces)
        processRest = ""   'return nothing
    Else    'if its not a multi word parameter
        If InStr(Msg$, " ") > 0 Then
            processRest = Right$(Msg$, Len(Msg$) - InStr(Msg$, " "))   'return all parameters except the first one
        Else
            processRest = ""   'return nothing
        End If
    End If
End Function


Private Sub txtChannel_GotFocus()
    cmdChannel.Default = True   'set the channel "change" button as the default button
End Sub


Private Sub lstUsers_DblClick()
    txtChatMsg.SetFocus
    txtChatMsg.Text = "/msg " & lstUsers.Text & " "
    txtChatMsg.SelStart = Len(txtChatMsg.Text)
End Sub

Private Sub sockIRC_Connect()   'as soon as we're connected to the server:
    On Error Resume Next
    nick$ = RegLoad("ircName", "DSO_" & Trim(myUsername) & "_" & MyRandNum$)
    connected = True    'set connected to true (cancel the timeout procedure)
    display "> Connected to server !"
    
    Send "PASS none"    ' according to the rfc it's better to send this before sending a nick / user
    Send "NICK " + nick$    ' send the nick message
    Send "USER " & nick$ & " " & "127.0.0.1" & "DSO Game Player"   ' the user message
        ' USER <username>            <hostname>       <servername>    <real name>
End Sub

Private Sub sockIRC_DataArrival(ByVal bytesTotal As Long)
    Dim X As Long
    Dim ArrivedData$
    sockIRC.GetData ArrivedData$, vbString

    Dim temp$
    For X& = 1 To bytesTotal    'get every byte we received, but only one at a time
        temp$ = Mid(ArrivedData$, X, 1)
        If temp$ = Chr$(10) Then    'if we received a newline character (this is the end of the message)
            processCommand  'process the entire command
            Data$ = ""      'clear the data$
        'if we received a newline character or a carriage return, dont add them to the message
        ElseIf temp$ <> Chr$(13) Then
            Data$ = Data$ + temp$
        End If
    Next
End Sub
Private Sub IRCTxtList(newText As String)
    Dim i As Integer
    
    For i = 48 To 0 Step -1
        ircMsgs(i + 1) = ircMsgs(i)
    Next
    ircMsgs(0) = newText
    curMsg = -1
    'MsgBox newText
End Sub

Function MyIRCName() As String
    'MyIRCName = "DSO" & Trim(str(Int(Rnd * 31999)))
    'MyIRCName = "DSO_" & Trim(myUsername)
    MyIRCName = nick$
End Function

Private Sub cmdChat_Click()
    If Trim(txtChatMsg.Text) = "" Then Exit Sub  'if there's no message exit the sub
    If Left(Trim(txtChatMsg.Text), 1) = "/" Then
        If Left(Trim(txtChatMsg.Text), 2) = "//" Then
            IRCTxtList Trim(Mid(txtChatMsg.Text, 1))
            Send "PRIVMSG " + channel$ + " :" + Trim(Mid(txtChatMsg.Text, 2))    'send the message to the channel
            displaychat "<" + MyIRCName + ">  " + Trim(Mid(txtChatMsg.Text, 2)) 'display the message
        Else
            IRCCommand = LCase(Left(txtChatMsg.Text, InStr(txtChatMsg.Text, " ")))
            If IRCCommand = "/me " Then
                IRCTxtList "/me " + Trim(Mid(txtChatMsg.Text, 4))
                Send "PRIVMSG " + channel$ + " :" + Chr(1) + "ACTION " + Trim(Mid(txtChatMsg.Text, 4)) + Chr(1)
                displaychat "* " + MyIRCName + " " + Trim(Mid(txtChatMsg.Text, 4))
            ElseIf IRCCommand = "/nick " Then
                Msg = Trim(Mid(txtChatMsg.Text, 6))
                If Msg <> "" Then
                    Send "NICK " & Trim(Msg)
                    IRCTxtList "/nick" + Trim(Msg)
                Else
                    display "Error in syntax."
                    display "/nick <new nickname>"
                End If
            ElseIf IRCCommand = "/msg " Then
                Msg = Trim(Mid(txtChatMsg.Text, 5))
                PMName = Trim(Mid(Msg, 1, InStr(Msg, " ")))
                If PMName <> "" Then
                    PMMsg = Trim(Mid(Msg, InStr(Msg, " ")))
                    Send "PRIVMSG " & PMName & " :" & PMMsg
                    IRCTxtList "/msg " & PMName & " " & PMMsg
                    displaychat ">" + MyIRCName + "< " + PMMsg
                Else
                    display "Error in syntax."
                    display "/msg <nickname> <message>"
                End If
            Else
                display "Command not found."
            End If
        End If
    Else
        IRCTxtList Trim(txtChatMsg.Text)
        Send "PRIVMSG " + channel$ + " :" + Trim(txtChatMsg.Text)    'send the message to the channel
        displaychat "<" + MyIRCName + ">  " + Trim(txtChatMsg.Text) 'display the message
    End If
    
    
    txtChatMsg.Text = ""    'clear the field
    txtChatMsg.SetFocus     'give the focus back to the message field
End Sub


Private Sub cmdPriv_Click()
    If Trim(txtPrivMsg.Text) = "" Or Trim(txtTarget.Text) = "" Then Exit Sub    'if there is no target or message, exit
    displaychat "    <" + MyIRCName + "> (" + Trim(txtTarget.Text) + ")  " + Trim(txtPrivMsg.Text)
    Send "PRIVMSG " + Trim(txtTarget.Text) + " :" + Trim(txtPrivMsg.Text)   'send the message
    txtPrivMsg.Text = ""    'clear the field
    txtPrivMsg.SetFocus     'give the focus back to the message field
End Sub



Sub PrintAll()
    Dim ss() As String
    ss = Split(txtChat, vbCrLf)

    If UBound(ss) > 1 Then

    IRC.Cls

    Dim tmpY As Long
    tmpY = IRC.Height - 240

    Dim maxChatTextSize As Long
    Dim n As Long, n2 As Long, tmpS As String, s As String

    maxChatTextSize = IRC.Width - 840

    For n = UBound(ss) To 0 Step -1
        cList.Clear
        
        s = ss(n)
        s = Replace(s, vbCrLf, ""): s = Replace(s, vbCr, ""): s = Replace(s, vbLf, "")
        cSize.FontName = IRC.FontName
        cSize.FontSize = IRC.FontSize
CheckForLine:
        For n2 = 1 To Len(s)
            cSize.Caption = Mid(s, 1, n2)
            If cSize.Width > maxChatTextSize Then
                cList.AddItem cSize.Caption
                s = Mid(s, n2 + 1, Len(s))
                GoTo CheckForLine
            End If
        Next n2
    
        If Trim(s) <> "" Then
            cList.AddItem s
        End If
        

    
        
        If cList.ListCount > 0 Then
        For n2 = cList.ListCount - 1 To 0 Step -1
            tmpS = cList.List(n2)
            If Trim(tmpS) <> "" Then
            
                tmpY = tmpY - 240
                IRC.CurrentY = tmpY
                IRC.CurrentX = 240
            
                If InStr(i(tmpS), " has joined ") > 0 Then
                    IRC.ForeColor = iOrange
                ElseIf InStr(i(tmpS), "has quit irc ") > 0 Then
                    IRC.ForeColor = iOrange
                
                ElseIf Left(i(tmpS), 2) = "* " = True Then
                    IRC.ForeColor = iBlue
                ElseIf Left(i(tmpS), 3) = ">> " = True Then
                    IRC.ForeColor = iBrown
                ElseIf Left(i(tmpS), Len(MyIRCName) + 3) = ">" + LCase(MyIRCName) + "< " Then
                    IRC.ForeColor = iGreen
                ElseIf Left(i(tmpS), 2) = ">>" Then
                    IRC.ForeColor = iLightGreen
                Else
                    IRC.ForeColor = vbWhite
                End If

                IRC.Print tmpS
            
            End If
        Next n2
        End If
        If tmpY < 0 Then GoTo AllDone
    Next n
AllDone:
    End If
End Sub

Public Sub ChatSend(ByVal s As String)
    If Len(s) > 32763 Then s = Mid(s, 1, 32763) ' 32764 would overflow
    s = Trim(s)
    If Len(s) > 0 Then
        Send "PRIVMSG " + channel$ + " :" + s
        displaychat "<" + MyIRCName + ">  " + s
    End If
End Sub

Public Sub ChatView(ByVal Enable As Boolean)
    If Enable Then
        chatToStatus = True
        RegSave "CHATVIEW", "True"
        SayCOMM "Chatview is now enabled."
    Else
        chatToStatus = False
        RegSave "CHATVIEW", False
        SayCOMM "Chatview is now disabled."
    End If
End Sub
