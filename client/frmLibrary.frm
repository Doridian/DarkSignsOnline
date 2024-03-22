VERSION 5.00
Object = "{831FDD16-0C5C-11D2-A9FC-0000F8754DA1}#2.2#0"; "MSCOMCTL.OCX"
Begin VB.Form frmLibrary 
   BorderStyle     =   1  'Fixed Single
   Caption         =   "File Library"
   ClientHeight    =   8415
   ClientLeft      =   45
   ClientTop       =   330
   ClientWidth     =   11910
   BeginProperty Font 
      Name            =   "Verdana"
      Size            =   9.75
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   Icon            =   "frmLibrary.frx":0000
   KeyPreview      =   -1  'True
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   8415
   ScaleWidth      =   11910
   StartUpPosition =   2  'CenterScreen
   Begin VB.CommandButton Command3 
      BackColor       =   &H00E0E0E0&
      Caption         =   "Text Space"
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   495
      Left            =   240
      Style           =   1  'Graphical
      TabIndex        =   32
      Top             =   6600
      Width           =   2655
   End
   Begin VB.PictureBox ShareBox 
      BackColor       =   &H00FFFFFF&
      Height          =   6855
      Left            =   4440
      ScaleHeight     =   6795
      ScaleWidth      =   7035
      TabIndex        =   31
      Top             =   -600
      Visible         =   0   'False
      Width           =   7095
      Begin VB.CommandButton tsc 
         BackColor       =   &H00E0E0E0&
         Caption         =   "Save Changes"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   495
         Left            =   2520
         Style           =   1  'Graphical
         TabIndex        =   37
         Top             =   4800
         Width           =   2535
      End
      Begin VB.TextBox TS 
         BeginProperty Font 
            Name            =   "Courier New"
            Size            =   11.25
            Charset         =   0
            Weight          =   400
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   4215
         Left            =   2520
         MultiLine       =   -1  'True
         ScrollBars      =   2  'Vertical
         TabIndex        =   35
         Top             =   480
         Width           =   3615
      End
      Begin VB.ListBox List3 
         BackColor       =   &H007E5450&
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         ForeColor       =   &H00FFFFFF&
         Height          =   5100
         Left            =   120
         Sorted          =   -1  'True
         TabIndex        =   34
         Top             =   480
         Width           =   2295
      End
      Begin VB.Label tsl 
         BackStyle       =   0  'Transparent
         Caption         =   "Select a Channel"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   255
         Left            =   120
         TabIndex        =   36
         Top             =   5760
         Width           =   2535
      End
      Begin VB.Label Label11 
         BackStyle       =   0  'Transparent
         Caption         =   "Select a Channel"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   255
         Left            =   120
         TabIndex        =   33
         Top             =   120
         Width           =   2415
      End
   End
   Begin VB.CommandButton cDownload 
      BackColor       =   &H00E0E0E0&
      Caption         =   "Download File(s)"
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   495
      Left            =   240
      Style           =   1  'Graphical
      TabIndex        =   25
      Top             =   7320
      Width           =   3255
   End
   Begin VB.CommandButton Command2 
      BackColor       =   &H00E0E0E0&
      Caption         =   "Remove"
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   495
      Left            =   240
      Style           =   1  'Graphical
      TabIndex        =   23
      Top             =   6000
      Width           =   2655
   End
   Begin VB.CommandButton Command1 
      BackColor       =   &H00E0E0E0&
      Caption         =   "Upload"
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   495
      Left            =   240
      Style           =   1  'Graphical
      TabIndex        =   22
      Top             =   5400
      Width           =   2655
   End
   Begin VB.Timer tmrStart 
      Interval        =   300
      Left            =   2520
      Top             =   120
   End
   Begin VB.PictureBox RemoveBox 
      BackColor       =   &H00FFFFFF&
      Height          =   6735
      Left            =   3720
      ScaleHeight     =   6675
      ScaleWidth      =   8115
      TabIndex        =   17
      Top             =   -120
      Visible         =   0   'False
      Width           =   8175
      Begin VB.CommandButton Command6 
         Caption         =   "Refresh"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   495
         Left            =   240
         TabIndex        =   28
         Top             =   5280
         Width           =   1935
      End
      Begin VB.PictureBox Picture2 
         Appearance      =   0  'Flat
         BackColor       =   &H00C0C0C0&
         BorderStyle     =   0  'None
         ForeColor       =   &H80000008&
         Height          =   735
         Left            =   3360
         ScaleHeight     =   735
         ScaleWidth      =   4575
         TabIndex        =   21
         Top             =   5280
         Width           =   4575
         Begin VB.CommandButton Command8 
            Caption         =   "Remove"
            BeginProperty Font 
               Name            =   "Verdana"
               Size            =   9.75
               Charset         =   0
               Weight          =   700
               Underline       =   0   'False
               Italic          =   0   'False
               Strikethrough   =   0   'False
            EndProperty
            Height          =   495
            Left            =   2640
            TabIndex        =   30
            Top             =   0
            Width           =   1935
         End
         Begin VB.CommandButton Command7 
            Caption         =   "Cancel"
            BeginProperty Font 
               Name            =   "Verdana"
               Size            =   9.75
               Charset         =   0
               Weight          =   700
               Underline       =   0   'False
               Italic          =   0   'False
               Strikethrough   =   0   'False
            EndProperty
            Height          =   495
            Left            =   600
            TabIndex        =   29
            Top             =   0
            Width           =   1935
         End
      End
      Begin VB.ListBox List2 
         Height          =   3420
         Left            =   240
         TabIndex        =   19
         Top             =   1320
         Width           =   7455
      End
      Begin VB.Label Label10 
         BackStyle       =   0  'Transparent
         Caption         =   "You can remove files that you have previously uploaded to the library."
         Height          =   255
         Left            =   240
         TabIndex        =   20
         Top             =   840
         Width           =   8535
      End
      Begin VB.Label Label9 
         BackStyle       =   0  'Transparent
         Caption         =   "Remove a File"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   14.25
            Charset         =   0
            Weight          =   400
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   375
         Left            =   240
         TabIndex        =   18
         Top             =   240
         Width           =   3495
      End
   End
   Begin VB.PictureBox UploadBox 
      BackColor       =   &H00FFFFFF&
      Height          =   7935
      Left            =   3480
      ScaleHeight     =   7875
      ScaleWidth      =   7035
      TabIndex        =   7
      Top             =   120
      Visible         =   0   'False
      Width           =   7095
      Begin VB.PictureBox Picture1 
         Appearance      =   0  'Flat
         BackColor       =   &H00C0C0C0&
         BorderStyle     =   0  'None
         ForeColor       =   &H80000008&
         Height          =   735
         Left            =   240
         ScaleHeight     =   735
         ScaleWidth      =   4575
         TabIndex        =   16
         Top             =   6240
         Width           =   4575
         Begin VB.CommandButton Command5 
            Caption         =   "Upload..."
            BeginProperty Font 
               Name            =   "Verdana"
               Size            =   9.75
               Charset         =   0
               Weight          =   700
               Underline       =   0   'False
               Italic          =   0   'False
               Strikethrough   =   0   'False
            EndProperty
            Height          =   495
            Left            =   2640
            TabIndex        =   27
            Top             =   0
            Width           =   1935
         End
         Begin VB.CommandButton Command4 
            Caption         =   "Cancel"
            BeginProperty Font 
               Name            =   "Verdana"
               Size            =   9.75
               Charset         =   0
               Weight          =   700
               Underline       =   0   'False
               Italic          =   0   'False
               Strikethrough   =   0   'False
            EndProperty
            Height          =   495
            Left            =   480
            TabIndex        =   26
            Top             =   0
            Width           =   2055
         End
      End
      Begin VB.TextBox txtTitle 
         Height          =   375
         Left            =   240
         MaxLength       =   255
         TabIndex        =   2
         Top             =   2160
         Width           =   6015
      End
      Begin VB.TextBox txtDescription 
         Height          =   375
         Left            =   240
         MaxLength       =   255
         TabIndex        =   3
         Top             =   3000
         Width           =   6015
      End
      Begin VB.TextBox txtVersion 
         Height          =   360
         Left            =   5520
         MaxLength       =   9
         TabIndex        =   1
         Text            =   "1.0"
         Top             =   1200
         Width           =   1215
      End
      Begin VB.ComboBox txtFile 
         Height          =   360
         Left            =   240
         TabIndex        =   0
         Top             =   1200
         Width           =   5175
      End
      Begin VB.ListBox uplist 
         Height          =   2220
         Left            =   240
         Sorted          =   -1  'True
         TabIndex        =   4
         Top             =   3840
         Width           =   6015
      End
      Begin VB.Label Label8 
         BackStyle       =   0  'Transparent
         Caption         =   "Title"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   255
         Left            =   240
         TabIndex        =   14
         Top             =   1920
         Width           =   6495
      End
      Begin VB.Label Label7 
         BackStyle       =   0  'Transparent
         Caption         =   "File Description"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   255
         Left            =   240
         TabIndex        =   13
         Top             =   2760
         Width           =   6495
      End
      Begin VB.Label Label6 
         BackStyle       =   0  'Transparent
         Caption         =   "File Version"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   255
         Left            =   5520
         TabIndex        =   12
         Top             =   960
         Width           =   1575
      End
      Begin VB.Label Label5 
         BackStyle       =   0  'Transparent
         Caption         =   "Example: \directory\file.ds"
         Height          =   255
         Left            =   240
         TabIndex        =   11
         Top             =   1560
         Width           =   4215
      End
      Begin VB.Label Label4 
         BackStyle       =   0  'Transparent
         Caption         =   "What file would you like to upload?"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   255
         Left            =   240
         TabIndex        =   10
         Top             =   960
         Width           =   4695
      End
      Begin VB.Label Label3 
         BackStyle       =   0  'Transparent
         Caption         =   "What category would you like to upload to?"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   9.75
            Charset         =   0
            Weight          =   700
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   255
         Left            =   240
         TabIndex        =   9
         Top             =   3600
         Width           =   5295
      End
      Begin VB.Label Label2 
         BackStyle       =   0  'Transparent
         Caption         =   "Upload a File"
         BeginProperty Font 
            Name            =   "Verdana"
            Size            =   14.25
            Charset         =   0
            Weight          =   400
            Underline       =   0   'False
            Italic          =   0   'False
            Strikethrough   =   0   'False
         EndProperty
         Height          =   375
         Left            =   240
         TabIndex        =   8
         Top             =   240
         Width           =   3135
      End
   End
   Begin VB.ListBox List1 
      BackColor       =   &H00400000&
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H00FFFFFF&
      Height          =   4860
      Left            =   120
      Sorted          =   -1  'True
      TabIndex        =   5
      Top             =   480
      Width           =   2895
   End
   Begin MSComctlLib.ListView LV 
      Height          =   6375
      Left            =   3120
      TabIndex        =   24
      Top             =   480
      Width           =   7935
      _ExtentX        =   13996
      _ExtentY        =   11245
      View            =   3
      LabelWrap       =   -1  'True
      HideSelection   =   0   'False
      FullRowSelect   =   -1  'True
      GridLines       =   -1  'True
      _Version        =   393217
      ForeColor       =   0
      BackColor       =   16777215
      Appearance      =   0
      BeginProperty Font {0BE35203-8F91-11CE-9DE3-00AA004BB851} 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      NumItems        =   9
      BeginProperty ColumnHeader(1) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         Key             =   "result"
         Text            =   "sID"
         Object.Width           =   1306
      EndProperty
      BeginProperty ColumnHeader(2) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   1
         Key             =   "title"
         Text            =   "Title"
         Object.Width           =   6068
      EndProperty
      BeginProperty ColumnHeader(3) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   2
         Key             =   "author"
         Text            =   "Version"
         Object.Width           =   1765
      EndProperty
      BeginProperty ColumnHeader(4) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   3
         Text            =   "Size"
         Object.Width           =   2540
      EndProperty
      BeginProperty ColumnHeader(5) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   4
         Key             =   "description"
         Text            =   "Author"
         Object.Width           =   2540
      EndProperty
      BeginProperty ColumnHeader(6) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   5
         Text            =   "Filename"
         Object.Width           =   3246
      EndProperty
      BeginProperty ColumnHeader(7) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   6
         Key             =   "path"
         Text            =   "Description"
         Object.Width           =   4304
      EndProperty
      BeginProperty ColumnHeader(8) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   7
         Text            =   "Date"
         Object.Width           =   4304
      EndProperty
      BeginProperty ColumnHeader(9) {BDD1F052-858B-11D1-B16A-00C0F0283628} 
         SubItemIndex    =   8
         Text            =   "Time"
         Object.Width           =   2540
      EndProperty
   End
   Begin VB.Label lStatus 
      BackStyle       =   0  'Transparent
      Caption         =   "To begin, click on a category from the list."
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   255
      Left            =   240
      TabIndex        =   15
      Top             =   7920
      Width           =   6975
   End
   Begin VB.Label Label1 
      BackStyle       =   0  'Transparent
      Caption         =   "Select a category"
      BeginProperty Font 
         Name            =   "Verdana"
         Size            =   9.75
         Charset         =   0
         Weight          =   700
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   255
      Left            =   120
      TabIndex        =   6
      Top             =   120
      Width           =   2655
   End
   Begin VB.Shape Shape1 
      BackColor       =   &H00000000&
      BorderColor     =   &H00808080&
      BorderStyle     =   0  'Transparent
      Height          =   855
      Left            =   480
      Top             =   240
      Width           =   3975
   End
End
Attribute VB_Name = "frmLibrary"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Dim ScriptCategories(1 To 25) As String


Sub DownloadOne()
    Dim sID As String
    
    sID = Trim(LV.SelectedItem)
    
    If IsNumeric(sID) = False Then
        MsgBox "No item is selected!", vbCritical, "Error"
        Exit Sub
    End If
    lStatus.Caption = "Downloading to \downloads\" & Trim(KillBadDirChars(LV.SelectedItem.ListSubItems(4).Text)) & "..."
    RunPage "file_database.php?returnwith=4304&getfile=" & EncodeURLParameter(sID), 5, False, "", False
End Sub


Sub UploadIt()
    Dim sFile As String
    Dim sDescription As String
    Dim sCategory As String
    Dim sFileData As String
    Dim sTitle As String
    Dim PostData As String
    Dim sShortFileName As String
    
    sFile = SafePath(Trim(txtFile.Text))
    sDescription = Trim(txtDescription.Text)
    sCategory = Trim(uplist.Text)
    sTitle = Trim(txtTitle)
    
    If FileExists(App.Path & "\user" & sFile) = False Then
        MsgBox "The file does not exist! Check the file name." & vbCrLf & vbCrLf & sFile, vbCritical, "Error"
        Exit Sub
    End If
    
    If Len(sDescription) < 4 Then
        MsgBox "Please enter a longer description.", vbInformation, "Error"
        Exit Sub
    End If
    If Len(sTitle) < 3 Then
        MsgBox "Please enter a longer title.", vbInformation, "Error"
        Exit Sub
    End If
    If Trim(sCategory) = "" Then
        MsgBox "Please select a category.", vbInformation, "Error"
        Exit Sub
    End If

    sShortFileName = ReverseString(Replace(sFile, "/", "\"))
    sShortFileName = Replace(sShortFileName, InStr(sShortFileName, "\") - 1, Len(sShortFileName))
    sShortFileName = Trim(ReverseString(sShortFileName))
    sShortFileName = GetShortName(sShortFileName)

    sFileData = GetFile(App.Path & "\user" & sFile)
    
    
    PostData = _
    "returnwith=4300" & _
    "&category=" & EncodeURLParameter(sCategory) & _
    "&title=" & EncodeURLParameter(sTitle) & _
    "&filesize=" & Trim(Str(Len(sFileData))) & _
    "&version=" & Trim(EncodeURLParameter(txtVersion)) & _
    "&description=" & EncodeURLParameter(sDescription) & _
    "&shortfilename=" & EncodeURLParameter(sShortFileName) & _
    "&filedata=" & EncodeURLParameter(sFileData)


    lStatus.Caption = "Sending data..."


    RunPage "file_database.php", 5, True, PostData, False
End Sub

Private Sub cDownload_Click()
    DownloadOne
End Sub

Private Sub Command1_Click()
    On Error Resume Next
    
    UploadBox.Visible = True
    RemoveBox.Visible = False
    cDownload.Visible = False
    ShareBox.Visible = False
    DoEvents
    txtFile.SetFocus
    
End Sub

Private Sub Command2_Click()
    RemoveBox.Visible = True
    UploadBox.Visible = False
    cDownload.Visible = False
    ShareBox.Visible = False
End Sub



Private Sub Command3_Click()
    UploadBox.Visible = False
    RemoveBox.Visible = False
    ShareBox.Visible = True
    cDownload.Visible = False
End Sub

Private Sub Command4_Click()
    UploadBox.Visible = False
    RemoveBox.Visible = False
    ShareBox.Visible = False
    cDownload.Visible = True
End Sub

Private Sub Command5_Click()

    UploadIt

End Sub

Private Sub Command6_Click()
    LoadScriptsToRemove
End Sub

Private Sub Command7_Click()
    UploadBox.Visible = False
    RemoveBox.Visible = False
    ShareBox.Visible = False
    cDownload.Visible = True
End Sub

Private Sub Command8_Click()
    Dim sID As String
    sID = Trim(List2.Text)
    
    If sID = "" Then
        MsgBox "No file has been selected!", vbCritical, "Error"
        Exit Sub
    End If
    
    sID = Mid(sID, 1, InStr(sID, ":") - 1)
    
    RemoveBox.Visible = False
    lStatus.Caption = "Removing..."
    

    RunPage "file_database.php?returnwith=4303&removenow=" & EncodeURLParameter(sID), 5, False, "", False
    
End Sub

Private Sub Form_KeyDown(KeyCode As Integer, Shift As Integer)
    If KeyCode = vbKeyEscape Then
        Unload Me
    End If
End Sub

Public Sub AddListItems(ByVal s As String)
    
    
    
    Dim AllResults() As String
    AllResults = Split(s, ":--:--:")
    
    Dim SubResults() As String
    
    LV.ListItems.Clear
    
    Dim n As Integer
    For n = UBound(AllResults) To 0 Step -1
    If Len(AllResults(n)) > 5 Then
        
        
        SubResults = Split(AllResults(n), ":--:")
        
        LV.ListItems.Add , , SubResults(0)
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , SubResults(1)
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , SubResults(2)
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , FormatKB(SubResults(3))
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , SubResults(4)
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , SubResults(5)
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , SubResults(6)
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , SubResults(7)
        LV.ListItems(LV.ListItems.Count).ListSubItems.Add , , SubResults(8)
        
        
        
        
        
        
    End If
    Next n
    
    
    
    frmLibrary.lStatus = Trim(Str(LV.ListItems.Count)) & " results found."
            
End Sub

Private Sub Form_Load()
    
    
    
'
'    Me.Width = Screen.Width
'    Me.Height = Screen.Height - 480
'    Me.Move 0, 0

    Me.Width = (Screen.Width / 7) * 6
    Me.Height = (Screen.Height / 6) * 5
  
    ScriptCategories(1) = "Code Bits"
    ScriptCategories(2) = "Games"
    ScriptCategories(3) = "Tools (Hacking)"
    ScriptCategories(4) = "Tools (Misc)"
    ScriptCategories(5) = "Mystery Box"
    ScriptCategories(6) = "Operating Systems"
    ScriptCategories(7) = "Scanners"
    ScriptCategories(8) = "Templates"
    ScriptCategories(9) = "Temporary"
    ScriptCategories(10) = "Malware"
    ScriptCategories(11) = "Security"
    
    LoadCategoryList
    
    LoadScriptsToRemove

    Dim n As Integer
    For n = 1 To 999
        List3.AddItem "Channel " & Format(n, "000")
    
    Next n

End Sub

Sub LoadCategoryList()

    On Error GoTo zxc

    Dim n As Integer
    
    List1.Clear
    For n = 1 To UBound(ScriptCategories)
        If Trim(ScriptCategories(n)) <> "" Then
            List1.AddItem ScriptCategories(n)
        End If
    Next n
    
    uplist.Clear
    For n = 1 To UBound(ScriptCategories)
        If Trim(ScriptCategories(n)) <> "" Then
            uplist.AddItem ScriptCategories(n)
        End If
    Next n
    
    Exit Sub
zxc:
    MsgBox "There may have been an error (1123)", vbInformation, "?"
End Sub



Private Sub Form_Resize()
    On Error Resume Next
    
    LV.Width = Me.Width - LV.Left - 360
    LV.Height = Me.Height - LV.Top - 1200
    
    UploadBox.Move LV.Left, LV.Top, LV.Width, LV.Height
    RemoveBox.Move LV.Left, LV.Top, LV.Width, LV.Height
    ShareBox.Move LV.Left, LV.Top, LV.Width, LV.Height
    
    TS.Width = ShareBox.Width - TS.Left - 360
    TS.Height = ShareBox.Height - TS.Top - 960
    tsc.Move TS.Left, TS.Top + TS.Height + 120
    
    txtDescription.Width = UploadBox.Width - 720
    uplist.Width = txtDescription.Width
    
    List2.Width = uplist.Width
    
    Picture1.Left = UploadBox.Width - Picture1.Width - 480
    Picture2.Left = RemoveBox.Width - Picture2.Width - 480
    

    lStatus.Width = Me.Width
    lStatus.Move Me.LV.Left, LV.Top + LV.Height + 240
    
    Picture1.BackColor = UploadBox.BackColor
    Picture2.BackColor = UploadBox.BackColor
    
    cDownload.Move Me.Width - cDownload.Width - 240, LV.Top + LV.Height + 120
    
End Sub








Sub UpdateResults()

    Dim sCategory As String
    sCategory = Trim(List1.Text)
    If sCategory = "" Then Exit Sub
    
    LV.ListItems.Clear
    
    lStatus.Caption = "Updating..."
    
    RunPage "file_database.php?returnwith=4301&getcategory=" & EncodeURLParameter(sCategory), 5, False, "", False
    
    
End Sub



Sub LoadScriptsToRemove()
    On Error GoTo zxc
    
    List2.Clear
    RunPage "file_database.php?returnwith=4302&getforremoval=a", 5, False, "", False
    
    
    Exit Sub
zxc:
    MsgBox "There may have been an error (1124)", vbInformation, "?"
End Sub

Public Sub AddtoRemoveList(ByVal s As String)

    List2.Clear

    Dim sA() As String
    sA = Split(s, ":--:")
    
    Dim n As Integer
    For n = UBound(sA) To 0 Step -1
    
        If Trim(sA(n)) <> "" Then
        
            List2.AddItem sA(n)
        
        End If
    
    Next n

End Sub





Private Sub List1_Click()
    UpdateResults
End Sub

Private Sub List1_MouseDown(Button As Integer, Shift As Integer, X As Single, Y As Single)
    
    UploadBox.Visible = False
    RemoveBox.Visible = False
    ShareBox.Visible = False
    cDownload.Visible = True
    
End Sub

Private Sub List3_Click()
    LoadList3
End Sub

Sub LoadList3()
    Dim ss As String
    ss = Trim(List3.Text)
    
    If ss = "" Then Exit Sub
    
    TS.Text = "Loading..."
    tsl.Caption = ss & "..."
    
    RunPage "textspace.php?download=" & EncodeURLParameter(Trim(Mid(ss, InStr(ss, " "), 99))), ActiveConsole, False, "", False
    
End Sub

Private Sub LV_ColumnClick(ByVal ColumnHeader As MSComctlLib.ColumnHeader)
    With LV '// change to the name of the list view
        Static iLast As Integer, iCur As Integer
        .Sorted = True
        iCur = ColumnHeader.Index - 1
        If iCur = iLast Then .SortOrder = IIf(.SortOrder = 1, 0, 1)
        .SortKey = iCur
        iLast = iCur
    End With
End Sub

Private Sub tmrStart_Timer()
    On Error Resume Next
    tmrStart.Enabled = False
    
    Me.List1.ListIndex = 0
    UpdateResults
    
    Me.List3.ListIndex = 0
    LoadList3
End Sub

Private Sub tsc_Click()
    Dim ss As String
        
    ss = Trim(List3.Text)
    If ss = "" Then Exit Sub
    tsl.Caption = "Updating..."
    
    Dim PostData As String
    PostData = "upload=" & EncodeURLParameter(Trim(Mid(ss, InStr(ss, " "), 99))) & "&textdata=" & EncodeURLParameter(TS.Text)
    RunPage "textspace.php", ActiveConsole, True, PostData, False
End Sub
