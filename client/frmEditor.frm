VERSION 5.00
Begin VB.Form frmEditor 
   BorderStyle     =   1  'Fixed Single
   Caption         =   "Editor"
   ClientHeight    =   9015
   ClientLeft      =   45
   ClientTop       =   330
   ClientWidth     =   11880
   BeginProperty Font 
      Name            =   "Verdana"
      Size            =   9.75
      Charset         =   0
      Weight          =   700
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   Icon            =   "frmEditor.frx":0000
   KeyPreview      =   -1  'True
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   9015
   ScaleWidth      =   11880
   StartUpPosition =   2  'CenterScreen
   Begin VB.PictureBox colortool 
      Appearance      =   0  'Flat
      BorderStyle     =   0  'None
      ForeColor       =   &H80000008&
      Height          =   2055
      Left            =   120
      ScaleHeight     =   2055
      ScaleWidth      =   2055
      TabIndex        =   7
      TabStop         =   0   'False
      Top             =   5760
      Width           =   2055
      Begin VB.HScrollBar HScroll3 
         Height          =   255
         Left            =   1320
         Max             =   255
         SmallChange     =   5
         TabIndex        =   18
         TabStop         =   0   'False
         Top             =   1080
         Value           =   1
         Width           =   615
      End
      Begin VB.HScrollBar HScroll2 
         Height          =   255
         Left            =   720
         Max             =   255
         SmallChange     =   5
         TabIndex        =   17
         TabStop         =   0   'False
         Top             =   1080
         Value           =   1
         Width           =   615
      End
      Begin VB.HScrollBar HScroll1 
         Height          =   255
         Left            =   120
         Max             =   255
         SmallChange     =   5
         TabIndex        =   16
         TabStop         =   0   'False
         Top             =   1080
         Value           =   1
         Width           =   615
      End
      Begin VB.PictureBox colorbox 
         Appearance      =   0  'Flat
         BackColor       =   &H80000005&
         BorderStyle     =   0  'None
         ForeColor       =   &H80000008&
         Height          =   495
         Left            =   0
         ScaleHeight     =   495
         ScaleWidth      =   2055
         TabIndex        =   12
         TabStop         =   0   'False
         Top             =   1440
         Width           =   2055
      End
      Begin VB.TextBox tB 
         Alignment       =   2  'Center
         Appearance      =   0  'Flat
         Height          =   360
         Left            =   1320
         MaxLength       =   3
         TabIndex        =   11
         TabStop         =   0   'False
         Text            =   "150"
         Top             =   720
         Width           =   615
      End
      Begin VB.TextBox tG 
         Alignment       =   2  'Center
         Appearance      =   0  'Flat
         Height          =   360
         Left            =   720
         MaxLength       =   3
         TabIndex        =   10
         TabStop         =   0   'False
         Text            =   "50"
         Top             =   720
         Width           =   615
      End
      Begin VB.TextBox tR 
         Alignment       =   2  'Center
         Appearance      =   0  'Flat
         Height          =   360
         Left            =   120
         MaxLength       =   3
         TabIndex        =   9
         TabStop         =   0   'False
         Text            =   "50"
         Top             =   720
         Width           =   615
      End
      Begin VB.Label Label4 
         Alignment       =   2  'Center
         BackStyle       =   0  'Transparent
         Caption         =   "B"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   8.25
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         ForeColor       =   &H00FF0000&
         Height          =   255
         Left            =   1320
         TabIndex        =   15
         Top             =   480
         Width           =   615
      End
      Begin VB.Label Label3 
         Alignment       =   2  'Center
         BackStyle       =   0  'Transparent
         Caption         =   "G"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   8.25
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         ForeColor       =   &H00008000&
         Height          =   255
         Left            =   720
         TabIndex        =   14
         Top             =   480
         Width           =   615
      End
      Begin VB.Label Label2 
         Alignment       =   2  'Center
         BackStyle       =   0  'Transparent
         Caption         =   "R"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   8.25
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         ForeColor       =   &H000000FF&
         Height          =   255
         Left            =   120
         TabIndex        =   13
         Top             =   480
         Width           =   615
      End
      Begin VB.Label Label1 
         BackStyle       =   0  'Transparent
         Caption         =   "Color Tool"
         ForeColor       =   &H00000000&
         Height          =   255
         Left            =   120
         TabIndex        =   8
         Top             =   120
         Width           =   1455
      End
   End
   Begin VB.PictureBox MBox 
      Appearance      =   0  'Flat
      BackColor       =   &H80000005&
      BorderStyle     =   0  'None
      ForeColor       =   &H80000008&
      Height          =   495
      Left            =   4560
      ScaleHeight     =   495
      ScaleWidth      =   5895
      TabIndex        =   3
      TabStop         =   0   'False
      Top             =   120
      Width           =   5895
      Begin VB.CommandButton Command2 
         BackColor       =   &H00E0E0E0&
         Cancel          =   -1  'True
         Caption         =   "Close and Save"
         Height          =   495
         Left            =   3120
         Style           =   1  'Graphical
         TabIndex        =   6
         TabStop         =   0   'False
         Top             =   0
         Width           =   2655
      End
      Begin VB.CommandButton Command1 
         BackColor       =   &H00E0E0E0&
         Caption         =   "Test Script"
         Height          =   495
         Left            =   360
         Style           =   1  'Graphical
         TabIndex        =   5
         TabStop         =   0   'False
         Top             =   0
         Width           =   2655
      End
   End
   Begin VB.ListBox List1 
      BackColor       =   &H00371311&
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
      Height          =   4980
      IntegralHeight  =   0   'False
      Left            =   120
      Sorted          =   -1  'True
      TabIndex        =   2
      TabStop         =   0   'False
      Top             =   720
      Width           =   2055
   End
   Begin VB.TextBox RT 
      BeginProperty Font 
         Name            =   "Courier New"
         Size            =   11.25
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   6255
      Left            =   2280
      MultiLine       =   -1  'True
      ScrollBars      =   3  'Both
      TabIndex        =   1
      Top             =   720
      Width           =   8655
   End
   Begin VB.Label lTitle 
      BackStyle       =   0  'Transparent
      Caption         =   "Editor"
      BeginProperty Font 
         Name            =   "Arial"
         Size            =   14.25
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   375
      Left            =   2280
      TabIndex        =   4
      Top             =   240
      Width           =   7815
   End
   Begin VB.Label lParam 
      BackStyle       =   0  'Transparent
      Caption         =   "Files will save automatically."
      Height          =   375
      Left            =   120
      TabIndex        =   0
      Top             =   8160
      Width           =   11535
   End
End
Attribute VB_Name = "frmEditor"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Dim DontAutoSave As Boolean
Dim lastTyped As String




Sub ExitAndTest()
    
    EditorRunFile = EditorFile_Long
    Unload Me

End Sub

Private Sub Command1_Click()
    ExitAndTest
End Sub

Private Sub Command2_Click()
    Unload Me
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    
    If KeyCode = vbKeyF5 Then ExitAndTest
    
    
End Sub

Sub SetColorBox()
    On Error Resume Next
    colorbox.BackColor = RGB(tR, tG, tB)
End Sub

Private Sub Form_Load()
  
    Me.Width = (Screen.Width / 7) * 6
    Me.Height = (Screen.Height / 6) * 5
  
    EditorRunFile = ""
    
    HScroll1.Value = tR
    HScroll2.Value = tG
    HScroll3.Value = tB
    
    
    SetColorBox
    
    
    
    List1.AddItem "APPEND" & Space(50) & "[file] [text-data]"
    List1.AddItem "CD" & Space(50) & "[directory]"
    List1.AddItem "CLEAR" & Space(50) & ""
    List1.AddItem "CONNECT" & Space(50) & "[server] [port-number]"
    List1.AddItem "COPY" & Space(50) & "[source-file] [destination-file]"
    List1.AddItem "DATE" & Space(50) & ""
    List1.AddItem "DEL" & Space(50) & "[file]"
    List1.AddItem "DIR" & Space(50) & "[optional-filter]"
    List1.AddItem "DOWNLOAD" & Space(50) & "[server] [port-number] [destination-file]"
    List1.AddItem "DRAW" & Space(50) & "[-y position] [red(0-255)] [green(0-255)] [blue(0-255)] mode"
    List1.AddItem "EDIT" & Space(50) & "[file]"
    List1.AddItem "GETDOMAIN" & Space(50) & "[server]"
    List1.AddItem "GETIP" & Space(50) & "[server]"
    List1.AddItem "HELP" & Space(50) & "[optional-command]"
    List1.AddItem "LISTCOLORS" & Space(50) & ""
    List1.AddItem "LISTKEYS" & Space(50) & ""
    List1.AddItem "LOGIN" & Space(50) & ""
    List1.AddItem "LOGOUT" & Space(50) & ""
    List1.AddItem "LOOKUP" & Space(50) & "[domain-or-username]"
    List1.AddItem "MD" & Space(50) & "[directory]"
    List1.AddItem "MOVE" & Space(50) & "[source-file] [destination-file]"
    List1.AddItem "NOW" & Space(50) & ""
    List1.AddItem "PAUSE" & Space(50) & "[optional-text]"
    List1.AddItem "PING" & Space(50) & "[server]"
    List1.AddItem "PINGPORT" & Space(50) & "[server] [port-number]"
    List1.AddItem "RD" & Space(50) & ""
    List1.AddItem "RENAME" & Space(50) & "[source-file] [destination-file]"
    List1.AddItem "REGISTER" & Space(50) & "[domain-name]"
    List1.AddItem "RESTART" & Space(50) & ""
    List1.AddItem "RUN" & Space(50) & "[script-file]"
    List1.AddItem "SAY" & Space(50) & "[text]"
    List1.AddItem "SAYALL" & Space(50) & "[text]"
    List1.AddItem "SAYCOMM" & Space(50) & "[text]"
    List1.AddItem "STATS" & Space(50) & ""
    List1.AddItem "TIME" & Space(50) & ""
    List1.AddItem "TRANSFER" & Space(50) & "[to-username] [$amount] [description]"
    List1.AddItem "UPLOAD" & Space(50) & "[server] [port-number] [source-file]"
    List1.AddItem "WRITE" & Space(50) & "[file] [text-data]"
    
    
    List1.AddItem "IF" & Space(50) & "[text-or-variable]  =  <  >  ^  ~  [text-or-variable] THEN"
    List1.AddItem "ELSE" & Space(50) & ""
    List1.AddItem "END IF" & Space(50) & ""
    List1.AddItem "ELSE IF" & Space(50) & "[text-or-variable]  =  <  >  ^  ~  [text-or-variable] THEN"
    List1.AddItem "FOR" & Space(50) & "[variable] = [text-or-variable] TO [text-or-variable] STEP [text-or-variable]"
    List1.AddItem "NEXT" & Space(50) & ""
    List1.AddItem "GOTO" & Space(50) & "[tag]"
    List1.AddItem "WAIT FOR" & Space(50) & "[variable]"
    List1.AddItem "ASC" & Space(50) & "[variable]"
    List1.AddItem "CHR" & Space(50) & "[variable]"
    List1.AddItem "FILE" & Space(50) & "[filename] [startline] [endline]"
    List1.AddItem "DIREXISTS" & Space(50) & "[directory path]"
    List1.AddItem "FILEEXISTS" & Space(50) & "[filename]"
    List1.AddItem "FIXQUOTES" & Space(50) & "[variable]"
    List1.AddItem "INSTR" & Space(50) & "[variable1] [variable2]"
    List1.AddItem "INPUT" & Space(50) & "[text]"
    List1.AddItem "KILLQUOTES" & Space(50) & "[variable]"
    List1.AddItem "LCASE" & Space(50) & "[variable]"
    List1.AddItem "LEFT" & Space(50) & "[variable]"
    List1.AddItem "LEN" & Space(50) & "[text]"
    List1.AddItem "MID" & Space(50) & "[text] [start] [stop]"
    List1.AddItem "PINGFILES" & Space(50) & "[server]"
    List1.AddItem "RANDOM" & Space(50) & "[low number] [high number]"
    List1.AddItem "RANDOMTEXT" & Space(50) & "[number]"
    List1.AddItem "REPLACE" & Space(50) & "[haystack] [needle] [hand]"
    List1.AddItem "REVERSE" & Space(50) & "[text]"
    List1.AddItem "RIGHT" & Space(50) & "[text] [length]"
    List1.AddItem "TRIM" & Space(50) & "[text]"
    List1.AddItem "UCASE" & Space(50) & "[text]"
    List1.AddItem "GETASCII" & Space(50) & "Gets ascii"
    List1.AddItem "GETKEY" & Space(50) & "Gets Key"
    List1.AddItem "SERVERFILECOUNT" & Space(50) & "[domain]"
    List1.AddItem "SERVERFILENAME" & Space(50) & "[filenumber]"
    List1.AddItem "SERVERFILEDELETE" & Space(50) & "[domain] [filename]"
    List1.AddItem "SERVERFILEDOWNLOAD" & Space(50) & "[domain] [filename]"
    List1.AddItem "SERVERFILEUPLOAD" & Space(50) & "[domain] [filename]"
    List1.AddItem "REMOTEUPLOAD" & Space(50) & "[filename]"
    List1.AddItem "REMOTEDIR" & Space(50) & "[domain]"
    List1.AddItem "REMOTEDELETE" & Space(50) & "[domain] [filename]"
    'List1.AddItem "CHATSEND" & Space(50) & "[message]"
    List1.AddItem "CHATVIEW" & Space(50) & "[on or off]"
    List1.AddItem "CLOSEPORT" & Space(50) & "[domain] [port]"
    List1.AddItem "SERVER WRITE" & Space(50) & "[filename] [data]"
    List1.AddItem "SERVER APPEND" & Space(50) & "[filename] [data]"
    List1.AddItem "FILESERVER" & Space(50) & "[file] [start] [end]"
    List1.AddItem "FILEDOWNLOAD" & Space(50) & "[server] [file]"
    List1.AddItem "SUBOWNERS" & Space(50) & "[domain] [action] [user]"
    List1.AddItem "EXIT" & Space(50) & "exits the script"
    
     
    
    
    
    DontAutoSave = True
  
    Me.Caption = "Editing " & EditorFile_Long
    RT.Text = GetFile(App.Path & "\user" & EditorFile_Long)
    
    lTitle.Caption = EditorFile_Long
    
    DoEvents
    DontAutoSave = False
    
End Sub

Sub AutoSave()
    If DontAutoSave = True Then Exit Sub
    
    WriteFile App.Path & "\user" & EditorFile_Long, RT.Text
    
End Sub

Sub FormatText()
    On Error Resume Next
    
    Dim s As String, AselStart As Integer
    
    AselStart = RT.SelStart
    s = vbCrLf & RT.Text
    
    Dim n As Integer, tmpCommandl As String, tmpCommandu As String, tmpCommandl2 As String, tmpCommandl3 As String
    For n = 0 To List1.ListCount - 1
        tmpCommandl = i(Mid(List1.List(n), 1, InStr(List1.List(n), " ")))
        tmpCommandu = Trim(UCase(Mid(List1.List(n), 1, InStr(List1.List(n), " "))))
        tmpCommandl2 = UCase(Mid(tmpCommandl, 1, 1)) & LCase(Mid(tmpCommandl, 2, 99))
        tmpCommandl3 = UCase(Mid(tmpCommandl, 1, 2)) & LCase(Mid(tmpCommandl, 3, 99))
        
        s = Replace(s, vbCrLf & tmpCommandl, vbCrLf & tmpCommandu)
        s = Replace(s, vbCrLf & tmpCommandl2, vbCrLf & tmpCommandu)
        s = Replace(s, vbCrLf & tmpCommandl3, vbCrLf & tmpCommandu)
        
    Next n
    
    
    RT.Text = Mid(s, 3, Len(s))
    RT.SelStart = AselStart
    
End Sub


Private Sub Form_Resize()
    On Error Resume Next
    
    RT.Move List1.Width + List1.Left + 120, 720, Me.Width - RT.Left - 240, Me.Height - 1560
    List1.Height = RT.Height - colortool.Height - 120
    colortool.Move List1.Left, List1.Top + List1.Height + 120
    
    MBox.BackColor = Me.BackColor
    MBox.Left = Me.Width - MBox.Width - 240
    
    lParam.Top = RT.Height + RT.Top + 100
    
End Sub





Private Sub HScroll1_Change()
    On Error Resume Next
    tR.Text = HScroll1.Value
End Sub

Private Sub HScroll2_Change()
    On Error Resume Next
    tG.Text = HScroll2.Value
End Sub

Private Sub HScroll3_Change()
    On Error Resume Next
    tB.Text = HScroll3.Value
End Sub

Private Sub List1_Click()
    Dim s As String
    s = List1.List(List1.ListIndex)
    
    Do Until InStr(s, "  ") = 0
        s = Replace(s, "  ", " ")
    Loop

    lParam.Caption = s

End Sub

Private Sub RT_Change()
    
    AutoSave
    
End Sub

Sub CheckLastTyped()
    On Error GoTo zxc

    Dim n As Integer
    Dim tmpCommand As String
    
    For n = 0 To List1.ListCount
        tmpCommand = i(Mid(List1.List(n), 1, InStr(List1.List(n), " ")))
        
        If Right(lastTyped, Len(tmpCommand)) = tmpCommand Then
            List1.ListIndex = n
            Exit Sub
        End If
        If Right(lastTyped, Len(tmpCommand)) & vbCrLf = tmpCommand Then
            List1.ListIndex = n
            Exit Sub
        End If
        
    Next n
    
zxc:
End Sub

Private Sub RT_KeyDown(KeyCode As Integer, Shift As Integer)
    
    lastTyped = lastTyped & i(Chr(KeyCode))
    
    If KeyCode = vbKeySpace Or KeyCode = vbKeyReturn Then
        FormatText
        CheckLastTyped
    End If

End Sub

Private Sub tR_Change()
SetColorBox
End Sub

Private Sub tg_Change()
SetColorBox
End Sub

Private Sub tb_Change()
SetColorBox
End Sub

