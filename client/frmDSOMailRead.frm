VERSION 5.00
Begin VB.Form frmDSOMailRead 
   Caption         =   "Mail"
   ClientHeight    =   4965
   ClientLeft      =   3105
   ClientTop       =   2610
   ClientWidth     =   6990
   LinkTopic       =   "Form1"
   MinButton       =   0   'False
   ScaleHeight     =   4965
   ScaleWidth      =   6990
   Begin VB.CommandButton btnReply 
      Caption         =   "Reply"
      Height          =   315
      Left            =   5640
      TabIndex        =   5
      Top             =   4560
      Width           =   1215
   End
   Begin VB.TextBox msgBody 
      Height          =   3495
      Left            =   120
      Locked          =   -1  'True
      MultiLine       =   -1  'True
      ScrollBars      =   2  'Vertical
      TabIndex        =   4
      Top             =   960
      Width           =   6735
   End
   Begin VB.TextBox msgSubject 
      Height          =   285
      Left            =   840
      Locked          =   -1  'True
      MaxLength       =   64
      TabIndex        =   3
      Top             =   480
      Width           =   6015
   End
   Begin VB.TextBox msgTo 
      Height          =   285
      Left            =   840
      Locked          =   -1  'True
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
Attribute VB_Name = "frmDSOMailRead"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False

Private Sub btnReply_Click()
   'frmDSOMailSend
   'MsgBox "Reply"
   frmDSOMailSend.msgTo = Me.msgTo
   frmDSOMailSend.msgSubject = "Re: " & Me.msgSubject
   frmDSOMailSend.msgBody = vbNewLine & vbNewLine & vbNewLine & "#From " & Me.msgTo & vbNewLine & "# Subject " & Me.msgSubject & vbNewLine & "#"
   
   Dim AllResults() As String
   AllResults = Split(Me.msgBody, vbNewLine)
   
   Dim n As Long
   For n = 0 To UBound(AllResults) Step 1
        frmDSOMailSend.msgBody = frmDSOMailSend.msgBody & vbNewLine & "#" & AllResults(n)
   Next n
   
   frmDSOMailSend.Caption = "Reply - " & Me.msgSubject
   Unload Me
   frmDSOMailSend.Show vbModal
  
End Sub

Private Sub Form_Resize()
   ' MsgBox Me.Width
    If Me.Width < 2000 Then
        Me.Width = 2000
    End If
    If Me.Height < 2000 Then
        Me.Height = 2000
    End If
    'MsgBox (Me.Height - Me.msgBody.Height)
    Me.msgTo.Width = Me.Width - 1215
    Me.msgSubject.Width = Me.Width - 1215
    Me.msgBody.Width = Me.Width - 495
    Me.btnReply.Left = Me.Width - 1590
    Me.btnReply.Top = Me.Height - 945
    Me.msgBody.Height = Me.Height - 2010
    'MsgBox Me.Width
    'MsgBox frmDSOMailSend.Width
    'MsgBox (Me.Height - Me.msgBody.Height)
    

End Sub
