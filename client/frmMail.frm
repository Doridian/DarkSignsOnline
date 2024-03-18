VERSION 5.00
Object = "{831FDD16-0C5C-11D2-A9FC-0000F8754DA1}#2.1#0"; "MSCOMCTL.OCX"
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
   Begin MSComctlLib.StatusBar StatusBar1 
      Align           =   2  'Align Bottom
      Height          =   255
      Left            =   0
      TabIndex        =   3
      Top             =   5640
      Width           =   9375
      _ExtentX        =   16536
      _ExtentY        =   450
      Style           =   1
      _Version        =   393216
      BeginProperty Panels {8E3867A5-8586-11D1-B16A-00C0F0283628} 
         NumPanels       =   1
         BeginProperty Panel1 {8E3867AB-8586-11D1-B16A-00C0F0283628} 
         EndProperty
      EndProperty
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
   Begin MSComctlLib.ListView inbox 
      Height          =   5415
      Left            =   1440
      TabIndex        =   0
      Top             =   120
      Width           =   7815
      _ExtentX        =   13785
      _ExtentY        =   9551
      View            =   3
      LabelWrap       =   -1  'True
      HideSelection   =   -1  'True
      FullRowSelect   =   -1  'True
      HoverSelection  =   -1  'True
      _Version        =   393217
      ForeColor       =   0
      BackColor       =   -2147483633
      Appearance      =   0
      NumItems        =   0
   End
End
Attribute VB_Name = "frmDSOMail"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Private Function keyExists(k As String) As Boolean
    Dim n As Integer
    For n = 0 To inbox.ListItems.Count Step 1
        If n > 0 Then
            If inbox.ListItems(n).key = k Then
                keyExists = True
            End If
        End If
    Next n
    keyExists = False
End Function


Public Sub reloadInbox()
    inbox.ListItems.Clear
    
    Dim tmpFile As String
    tmpFile = GetFile(App.Path & "\mail.dat")
    
    Dim AllResults() As String
    AllResults = Split(tmpFile, vbNewLine)
    
    Dim SubResults() As String
    
    
    
    'MsgBox UBound(AllResults)
    Dim n As Integer
    Dim key As String
    
    For n = 0 To UBound(AllResults) Step 1
        SubResults = Split(AllResults(n), Chr(7))
        'MsgBox UBound(SubResults)
        'MsgBox SubResults(0)
        'MsgBox SubResults(1)
        'MsgBox SubResults(2)
        'MsgBox SubResults(3)
        'MsgBox SubResults(4)
        
        If UBound(SubResults) = 5 Then
            'If keyExists(SubResults(0)) = False Then
                key = SubResults(1)
                inbox.ListItems.Add , key, SubResults(2)
                inbox.ListItems(inbox.ListItems.Count).ListSubItems.Add , , SubResults(3)
                inbox.ListItems(inbox.ListItems.Count).ListSubItems.Add , , SubResults(5)
                
                If SubResults(0) = "1" Then
                    inbox.ListItems(inbox.ListItems.Count).Bold = True
                    inbox.ListItems(inbox.ListItems.Count).ListSubItems(1).Bold = True
                    inbox.ListItems(inbox.ListItems.Count).ListSubItems(2).Bold = True
                End If
            'End If
            
            'key = "X_" & SubResults(0)
            'key = SubResults(0)
            'inbox.ListItems.Add , key, SubResults(1)
            'inbox.ListItems(inbox.ListItems.Count).ListSubItems.Add , , SubResults(2)
            'inbox.ListItems(inbox.ListItems.Count).ListSubItems.Add , , SubResults(4)
        End If
        
    Next n
End Sub

Private Sub btnRefresh_Click()
    'Unload Me
    DisableAll
    StatusBar1.SimpleText = "Checking emails..."
    Dim last As String
    
    Dim tmpFile As String
    tmpFile = GetFile(App.Path & "\mail.dat")
    
    Dim AllResults() As String
    AllResults = Split(tmpFile, vbNewLine)
    For n = UBound(AllResults) To 0 Step -1
        SubResults = Split(AllResults(n), Chr(7))
        'Mid(inbox.SelectedItem.key, 3)
        
        If UBound(SubResults) > 2 Then
            'MsgBox SubResults(0)
            If Left(SubResults(1), 2) = "X_" Then
                last = Mid(SubResults(1), 3)
                n = 0
            End If
        End If
    Next n
    
    
    If last = "" Then
        last = "0"
    End If
    
    RunPage "dsmail.php?action=inbox&returnwith=7001&last=" & EncodeURLParameter(last), consoleID
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
    
    Dim inboxWidth As Integer
    inboxWidth = (Me.Width - 1650) / 100
    
    inbox.ColumnHeaders.Add 1, "kFrom", "From", inboxWidth * 30
    inbox.ColumnHeaders.Add 2, "kSubject", "Subject", inboxWidth * 45
    inbox.ColumnHeaders.Add 3, "kDate", "Date", inboxWidth * 20
    
    reloadInbox
    
End Sub

Private Sub inbox_DblClick()
    'MsgBox Mid(inbox.SelectedItem.key, 3)
    'MsgBox inbox.SelectedItem.Index
    'MsgBox inbox.ListItems(inbox.SelectedItem.Index).key
    
    ').Text
    frmDSOMailRead.msgTo.Text = inbox.ListItems(inbox.SelectedItem.Index).Text
    frmDSOMailRead.msgSubject.Text = inbox.ListItems(inbox.SelectedItem.Index).ListSubItems(1).Text
    frmDSOMailRead.msgBody.Text = "ERROR LOADING MESSAGE BODY"
    
    inbox.ListItems(inbox.SelectedItem.Index).Bold = False
    inbox.ListItems(inbox.SelectedItem.Index).ListSubItems(1).Bold = False
    inbox.ListItems(inbox.SelectedItem.Index).ListSubItems(2).Bold = False
            
    
    Dim tmpFile As String
    tmpFile = GetFile(App.Path & "\mail.dat")
    
    Dim AllResults() As String
    AllResults = Split(tmpFile, vbNewLine)
    
    Dim SubResults() As String
    Dim n As Integer
    Dim key As String
    key = inbox.ListItems(inbox.SelectedItem.Index).key
    
    For n = 0 To UBound(AllResults) Step 1
        SubResults = Split(AllResults(n), Chr(7))
       
        If UBound(SubResults) = 5 Then
            If SubResults(1) = key Then
                frmDSOMailRead.msgBody.Text = SubResults(4)
                n = UBound(AllResults)
            End If
        End If
    Next n
    
    frmDSOMailRead.msgBody.Text = Replace(frmDSOMailRead.msgBody.Text, Chr(6), vbNewLine)
    
    If inbox.ListItems(inbox.SelectedItem.Index).Bold = True Then
        markAsRead (key)
    End If
    
    frmDSOMailRead.Show vbModal
End Sub

Private Sub markAsRead(k As String)
    Dim tmpFile As String
    tmpFile = GetFile(App.Path & "\mail.dat")
    
    Dim AllResults() As String
    AllResults = Split(tmpFile, vbNewLine)
    For n = UBound(AllResults) To 0 Step -1
        SubResults = Split(AllResults(n), Chr(7))
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
    
    WriteFile App.Path & "\mail.dat", Join(AllResults, vbNewLine)
End Sub

Private Sub inbox_ColumnClick(ByVal ColumnHeader As MSComctlLib.ColumnHeader)
    With inbox '// change to the name of the list view
        Static iLast As Integer, iCur As Integer
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
