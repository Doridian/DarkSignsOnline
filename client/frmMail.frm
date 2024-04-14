VERSION 5.00
Begin VB.Form frmDSOMail 
   Caption         =   "DSO Mail"
   ClientHeight    =   5895
   ClientLeft      =   120
   ClientTop       =   420
   ClientWidth     =   9375
   FillStyle       =   0  'Solid
   BeginProperty Font 
      Name            =   "Lucida Console"
      Size            =   9
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   LinkTopic       =   "Form1"
   ScaleHeight     =   5895
   ScaleWidth      =   9375
   StartUpPosition =   3  'Windows Default
   Begin DSO.StatusBar StatusBar1 
      Align           =   2  'Align Bottom
      Height          =   300
      Left            =   0
      Top             =   5595
      Width           =   9375
      _ExtentX        =   16536
      _ExtentY        =   529
      Style           =   1
      InitPanels      =   "frmMail.frx":0000
   End
   Begin VB.CommandButton btnNew 
      Caption         =   "New"
      Height          =   375
      Left            =   120
      TabIndex        =   2
      Top             =   120
      Width           =   1215
   End
   Begin VB.CommandButton btnRefresh 
      Caption         =   "Refresh"
      Height          =   375
      Left            =   120
      TabIndex        =   1
      Top             =   600
      Width           =   1215
   End
   Begin DSO.ListView inbox 
      Height          =   5415
      Left            =   1440
      TabIndex        =   0
      Top             =   120
      Width           =   7815
      _ExtentX        =   13785
      _ExtentY        =   9551
      BackColor       =   -2147483633
      ForeColor       =   0
      View            =   3
      FullRowSelect   =   -1  'True
      HoverSelection  =   -1  'True
   End
End
Attribute VB_Name = "frmDSOMail"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Private Function keyExists(k As String) As Boolean
    Dim n As Long
    For n = 0 To inbox.ListItems.Count Step 1
        If n > 0 Then
            If inbox.ListItems(n).Key = k Then
                keyExists = True
            End If
        End If
    Next n
    keyExists = False
End Function


Public Sub reloadInbox()
    inbox.ListItems.Clear

    Dim tmpFile As String
    On Error GoTo NoEntries
    tmpFile = GetFileUnsafe(App.Path & "/mail.dat")
    On Error GoTo 0

    Dim AllResults() As String
    AllResults = Split(tmpFile, vbCrLf)

    Dim SubResults() As String

    Dim n As Long
    Dim Key As String

    For n = 0 To UBound(AllResults) Step 1
        SubResults = Split(AllResults(n), ":--:")
        If UBound(SubResults) = 5 Then
            Key = SubResults(1)
            inbox.ListItems.Add , Key, SubResults(2)
            inbox.ListItems(inbox.ListItems.Count).ListSubItems.Add , , DecodeBase64Str(SubResults(3))
            inbox.ListItems(inbox.ListItems.Count).ListSubItems.Add , , SubResults(5)
            
            If SubResults(0) = "1" Then
                inbox.ListItems(inbox.ListItems.Count).Bold = True
                inbox.ListItems(inbox.ListItems.Count).ListSubItems(1).Bold = True
                inbox.ListItems(inbox.ListItems.Count).ListSubItems(2).Bold = True
            End If
        End If
    Next n

NoEntries:
End Sub

Private Sub btnRefresh_Click()
    'Unload Me
    DisableAll
    StatusBar1.SimpleText = "Checking emails..."
    Dim last As String
    last = ""

    Dim tmpFile As String
    On Error GoTo NoEntries
    tmpFile = GetFileUnsafe(App.Path & "/mail.dat")
    On Error GoTo 0
    
    Dim AllResults() As String
    AllResults = Split(tmpFile, vbCrLf)
    For n = UBound(AllResults) To 0 Step -1
        SubResults = Split(AllResults(n), ":--:")
        'Mid(inbox.SelectedItem.key, 3)
        
        If UBound(SubResults) > 2 Then
            'MsgBox SubResults(0)
            If Left(SubResults(1), 2) = "X_" Then
                last = Mid(SubResults(1), 3)
                n = 0
            End If
        End If
    Next n
    

NoEntries:
    If last = "" Then
        last = "0"
    End If
    
    RunPage "dsmail.php?action=inbox&returnwith=7001&last=" & EncodeURLParameter(last), ConsoleID
End Sub

Private Sub Form_Resize()
    If Me.Width < 4000 Then
        Me.Width = 4000
    End If
    If Me.Height < 4000 Then
        Me.Height = 4000
    End If
    
    'MsgBox Me.Width - inbox.Width
    'MsgBox Me.Height - inbox.Height
    
    inbox.Width = Me.Width - 1800
    inbox.Height = Me.Height - 1020
End Sub

Public Sub EnableAll()
    inbox.Enabled = True
    btnNew.Enabled = True
    btnRefresh.Enabled = True
End Sub

Public Sub DisableAll()
    inbox.Enabled = False
    btnNew.Enabled = False
    btnRefresh.Enabled = False
End Sub

Private Sub Form_Load()
    
    Dim inboxWidth As Long
    inboxWidth = (Me.Width - 1650) / 100
    
    inbox.ColumnHeaders.Add 1, "kFrom", "From", inboxWidth * 30
    inbox.ColumnHeaders.Add 2, "kSubject", "Subject", inboxWidth * 45
    inbox.ColumnHeaders.Add 3, "kDate", "Date", inboxWidth * 20
    
    reloadInbox
    
End Sub

Private Sub inbox_DblClick()
    Dim SelectedIndex As Long
    SelectedIndex = 0
    On Error Resume Next
    SelectedIndex = inbox.SelectedItem.Index
    On Error GoTo 0
    
    If SelectedIndex <= 0 Then
        Exit Sub
    End If

    frmDSOMailRead.msgTo.Text = inbox.ListItems(SelectedIndex).Text
    frmDSOMailRead.msgSubject.Text = inbox.ListItems(SelectedIndex).ListSubItems(1).Text
    frmDSOMailRead.msgBody.Text = "ERROR LOADING MESSAGE BODY"
    
    inbox.ListItems(inbox.SelectedItem.Index).Bold = False
    inbox.ListItems(inbox.SelectedItem.Index).ListSubItems(1).Bold = False
    inbox.ListItems(inbox.SelectedItem.Index).ListSubItems(2).Bold = False

    Dim tmpFile As String
    tmpFile = ""
    On Error Resume Next
    tmpFile = GetFileUnsafe(App.Path & "/mail.dat")
    On Error GoTo 0
    
    Dim AllResults() As String
    AllResults = Split(tmpFile, vbCrLf)
    
    Dim SubResults() As String
    Dim n As Long
    Dim Key As String
    Key = inbox.ListItems(SelectedIndex).Key
    
    For n = 0 To UBound(AllResults) Step 1
        SubResults = Split(AllResults(n), ":--:")
       
        If UBound(SubResults) = 5 Then
            If SubResults(1) = Key Then
                frmDSOMailRead.msgBody.Text = DecodeBase64Str(SubResults(4))
                n = UBound(AllResults)
            End If
        End If
    Next n

    If inbox.ListItems(SelectedIndex).Bold = True Then
        markAsRead Key
    End If
    
    frmDSOMailRead.Show vbModal
End Sub

Private Sub markAsRead(k As String)
    Dim tmpFile As String
    On Error GoTo NoResults
    tmpFile = GetFileUnsafe(App.Path & "/mail.dat")
    On Error GoTo 0
    
    Dim AllResults() As String
    AllResults = Split(tmpFile, vbCrLf)
    For n = UBound(AllResults) To 0 Step -1
        SubResults = Split(AllResults(n), ":--:")
        'Mid(inbox.SelectedItem.key, 3)
        
        If UBound(SubResults) > 2 Then
            'MsgBox SubResults(0)
            If SubResults(1) = k Then
                AllResults(n) = "0" & Mid(AllResults(n), 2)
                'last = Mid(SubResults(1), 3)
                n = 0
            End If
        End If
    Next n
    
    WriteFileUnsafe App.Path & "/mail.dat", Join(AllResults, vbCrLf)
    
NoResults:
End Sub

Private Sub inbox_ColumnClick(ByVal ColumnHeader As LvwColumnHeader)
    With inbox '// change to the name of the list view
        Static iLast As Long, iCur As Long
        .Sorted = True
        iCur = ColumnHeader.Index - 1
        If iCur = iLast Then .SortOrder = IIf(.SortOrder = 1, 0, 1)
        .SortKey = iCur
        iLast = iCur
    End With
End Sub

Private Sub btnNew_Click()  'new
    frmDSOMailSend.Caption = "New Message"
    frmDSOMailSend.Show vbModal
End Sub
