VERSION 5.00
Begin VB.Form frmDSOMailSend 
   Caption         =   "Send"
   ClientHeight    =   4965
   ClientLeft      =   3105
   ClientTop       =   2610
   ClientWidth     =   6990
   LinkTopic       =   "Form1"
   MinButton       =   0   'False
   ScaleHeight     =   4965
   ScaleWidth      =   6990
   Begin VB.CommandButton btnSend 
      Caption         =   "Send"
      Height          =   315
      Left            =   5640
      TabIndex        =   5
      Top             =   4560
      Width           =   1215
   End
   Begin VB.TextBox msgBody 
      Height          =   3615
      Left            =   120
      MultiLine       =   -1  'True
      ScrollBars      =   2  'Vertical
      TabIndex        =   4
      Top             =   840
      Width           =   6735
   End
   Begin VB.TextBox msgSubject 
      Height          =   285
      Left            =   840
      MaxLength       =   64
      TabIndex        =   3
      Top             =   480
      Width           =   6015
   End
   Begin VB.TextBox msgTo 
      Height          =   285
      Left            =   840
      MaxLength       =   128
      TabIndex        =   0
      Top             =   120
      Width           =   6015
   End
   Begin VB.Label Label2 
      Caption         =   "Subject"
      Height          =   255
      Left            =   120
      TabIndex        =   2
      Top             =   480
      Width           =   855
   End
   Begin VB.Label Label1 
      Caption         =   "To"
      Height          =   255
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   375
   End
End
Attribute VB_Name = "frmDSOMailSend"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Private Sub btnSend_Click()
   'frmDSOMailSend
   
   Dim toSend As String

   
   toSend = "action=send&returnwith=7002&to=" & EncodeURLParameter(Me.msgTo) & _
        "&subject=" & EncodeURLParameter(Me.msgSubject) & _
        "&message=" & EncodeURLParameter(Me.msgBody.Text)

   RunPage "dsmail.php", consoleID, True, toSend
   
   DisableAll

   btnSend.Caption = "Sending..."
   Me.Enabled = False
End Sub

Public Sub DisableAll()
    msgBody.Enabled = False
    msgTo.Enabled = False
    msgSubject.Enabled = False
    btnSend.Enabled = False
End Sub

Public Sub EnableAll()
    msgBody.Enabled = True
    msgTo.Enabled = True
    msgSubject.Enabled = True
    btnSend.Enabled = True
End Sub

Private Sub Form_Resize()
    If Me.Width < 2000 Then
        Me.Width = 2000
    End If
    If Me.Height < 2000 Then
        Me.Height = 2000
    End If
    
    Me.msgTo.Width = Me.Width - 1215
    Me.msgSubject.Width = Me.Width - 1215
    Me.msgBody.Width = Me.Width - 495
    Me.btnSend.Left = Me.Width - 1590
    Me.btnSend.Top = Me.Height - 945
    Me.msgBody.Height = Me.Height - 1890
    'MsgBox Me.Width
    'MsgBox frmDSOMailSend.Width
    'MsgBox (Me.Height - Me.msgBody.Height)
    

End Sub
