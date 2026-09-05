VERSION 5.00
Begin VB.Form frmPayment 
   BackColor       =   &H00000000&
   BorderStyle     =   0  'None
   Caption         =   "Form1"
   ClientHeight    =   5220
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   6660
   BeginProperty Font 
      Name            =   "Verdana"
      Size            =   9.75
      Charset         =   0
      Weight          =   700
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   Icon            =   "frmPayment.frx":0000
   LinkTopic       =   "Form1"
   ScaleHeight     =   5220
   ScaleWidth      =   6660
   ShowInTaskbar   =   0   'False
   StartUpPosition =   2  'CenterScreen
   Begin VB.CommandButton Command2 
      BackColor       =   &H00E0E0E0&
      Cancel          =   -1  'True
      Caption         =   "No, I do not accept this payment."
      Height          =   735
      Left            =   360
      Style           =   1  'Graphical
      TabIndex        =   8
      Top             =   4080
      Width           =   5895
   End
   Begin VB.CommandButton Command1 
      BackColor       =   &H00E0E0E0&
      Caption         =   "Yes, I accept this payment."
      Height          =   495
      Left            =   360
      Style           =   1  'Graphical
      TabIndex        =   7
      Top             =   3480
      Width           =   5895
   End
   Begin VB.Line Line1 
      BorderColor     =   &H00808080&
      X1              =   3240
      X2              =   3240
      Y1              =   1080
      Y2              =   1560
   End
   Begin VB.Label lDescription 
      Alignment       =   2  'Center
      BackStyle       =   0  'Transparent
      Caption         =   "This is the description."
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
      Height          =   975
      Left            =   480
      TabIndex        =   6
      Top             =   2040
      Width           =   5655
   End
   Begin VB.Label Label6 
      Alignment       =   1  'Right Justify
      BackStyle       =   0  'Transparent
      Caption         =   "Pay to"
      ForeColor       =   &H00FFFFFF&
      Height          =   255
      Left            =   2280
      TabIndex        =   5
      Top             =   1080
      Width           =   855
   End
   Begin VB.Label lTo 
      BackStyle       =   0  'Transparent
      Caption         =   "admin"
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H00FFFFFF&
      Height          =   255
      Left            =   3360
      TabIndex        =   4
      Top             =   1080
      Width           =   3615
   End
   Begin VB.Label Label4 
      Alignment       =   1  'Right Justify
      BackStyle       =   0  'Transparent
      Caption         =   "Amount"
      ForeColor       =   &H00FFFFFF&
      Height          =   255
      Left            =   2040
      TabIndex        =   3
      Top             =   1320
      Width           =   1095
   End
   Begin VB.Label lAmount 
      BackStyle       =   0  'Transparent
      Caption         =   "$50.00"
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H00FFFFFF&
      Height          =   255
      Left            =   3360
      TabIndex        =   2
      Top             =   1320
      Width           =   3735
   End
   Begin VB.Label Label2 
      Alignment       =   2  'Center
      BackStyle       =   0  'Transparent
      Caption         =   "If you are unsure, click no."
      ForeColor       =   &H000000FF&
      Height          =   255
      Left            =   600
      TabIndex        =   1
      Top             =   3000
      Width           =   5415
   End
   Begin VB.Label Label1 
      Alignment       =   2  'Center
      BackStyle       =   0  'Transparent
      Caption         =   "Would you like to make a payment?"
      ForeColor       =   &H00FFFFFF&
      Height          =   255
      Left            =   600
      TabIndex        =   0
      Top             =   360
      Width           =   5415
   End
   Begin VB.Shape Shape3 
      BackColor       =   &H00191919&
      BackStyle       =   1  'Opaque
      Height          =   1095
      Left            =   480
      Shape           =   4  'Rounded Rectangle
      Top             =   1800
      Width           =   5655
   End
   Begin VB.Shape bordr 
      BackColor       =   &H00000000&
      BorderColor     =   &H00C0C0C0&
      BorderWidth     =   3
      Height          =   255
      Left            =   120
      Top             =   1200
      Width           =   255
   End
End
Attribute VB_Name = "frmPayment"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Private Sub Command1_Click()
    AuthorizePayment = True
    Unload Me
End Sub

Private Sub Command2_Click()
    AuthorizePayment = False
    Unload Me
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    If KeyCode = vbKeyEscape Then
        AuthorizePayment = False
        Unload Me
    End If
End Sub

Private Sub Form_Load()
    ResizeMe
End Sub

Private Sub Form_Resize()
    ResizeMe
End Sub

Sub ResizeMe()
    bordr.Move 120, 120
    bordr.Width = Me.Width - 240
    bordr.Height = Me.Height - 240
End Sub

