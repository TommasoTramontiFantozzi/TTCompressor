unit Unit1;

{ TTCompressor - frontend grafico per 7z. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls, ExtCtrls,
  Menus, StdCtrls, ImgList, LCLType, LCLIntf, FileUtil, LazFileUtils, LazUTF8, Masks,
  Math, Process, laz.VirtualTrees, szmodel, szrun, szicons, szdlg, szrs, szdnd, szheader, szlang, szabout, gtk2, BaseUnix;

type
  TJobKind = (jkList, jkListNested, jkExtract, jkTest, jkAdd, jkCreate,
    jkDelete, jkOpenFile, jkRecCheck, jkRepair, jkRecAdd);

  TRecKind = (rkNone, rkTail, rkPar2);

  { TForm1 }

  TForm1 = class(TForm)
    AddDirDialog: TSelectDirectoryDialog;
    AddFilesDialog: TOpenDialog;
    btnCancel: TButton;
    ImageListTool: TImageList;
    tbBack, tbForward, tbUp, tbSep1: TToolButton;
    miGo, miBack, miForward, miUp: TMenuItem;
    lblFile: TLabel;
    lblProgress: TLabel;
    lblTime: TLabel;
    MainMenu1: TMainMenu;
    miAdd: TMenuItem;
    miArchive: TMenuItem;
    miDelete: TMenuItem;
    miEdit: TMenuItem;
    miExtract: TMenuItem;
    miFind: TMenuItem;
    miNew: TMenuItem;
    miOpen: TMenuItem;
    miQuit: TMenuItem;
    miRepair: TMenuItem;
    miAddRec: TMenuItem;
    miHelp: TMenuItem;
    miHelpRecovery: TMenuItem;
    miAbout: TMenuItem;
    miSelectAll: TMenuItem;
    miSep1: TMenuItem;
    miSep2: TMenuItem;
    miTest: TMenuItem;
    OpenArchiveDialog: TOpenDialog;
    PanelProgress: TPanel;
    pmAddDir: TMenuItem;
    pmAddFiles: TMenuItem;
    pmDelete: TMenuItem;
    pmExtract: TMenuItem;
    pmSelectAll: TMenuItem;
    pmTest: TMenuItem;
    PopupAdd: TPopupMenu;
    PopupFiles: TPopupMenu;
    ProgressBar1: TProgressBar;
    Splitter1: TSplitter;
    StatusBar1: TStatusBar;
    tbAdd: TToolButton;
    tbDelete: TToolButton;
    tbExtract: TToolButton;
    tbFind: TToolButton;
    tbNew: TToolButton;
    tbTest: TToolButton;
    TimerJob: TTimer;
    ToolBar1: TToolBar;
    TreeFiles: TLazVirtualStringTree;
    TreeFolders: TLazVirtualStringTree;
    procedure actAddExecute(Sender: TObject);
    procedure actDeleteExecute(Sender: TObject);
    procedure actExtractExecute(Sender: TObject);
    procedure actFindExecute(Sender: TObject);
    procedure actNewExecute(Sender: TObject);
    procedure actTestExecute(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure FormShow(Sender: TObject);
    procedure miOpenClick(Sender: TObject);
    procedure actBackExecute(Sender: TObject);
    procedure actForwardExecute(Sender: TObject);
    procedure actUpExecute(Sender: TObject);
    procedure miRepairClick(Sender: TObject);
    procedure miAddRecClick(Sender: TObject);
    procedure miHelpRecoveryClick(Sender: TObject);
    procedure miAboutClick(Sender: TObject);
    procedure miQuitClick(Sender: TObject);
    procedure miSelectAllClick(Sender: TObject);
    procedure pmAddDirClick(Sender: TObject);
    procedure pmAddFilesClick(Sender: TObject);
    procedure TimerJobTimer(Sender: TObject);
    procedure TreeFilesResize(Sender: TObject);
    procedure TreeFoldersResize(Sender: TObject);
  private
    FSevenZip: string;
    FModel: TArcModel;
    FIcons: TSysIcons;
    FArcPath: string;
    FNested: Boolean;
    FDebCtl, FDebFmt: string;           // .deb: membro control.tar.* e relativo formato
    FPendDebCtl, FPendDebFmt: string;
    FHdr: TSzHeader;
    FListRaw: string;     // righe di dati dell'ultimo elenco (job con KeepAll)
    FFastList: Boolean;   // il 7z supporta -slc (elenco compatto) e la percentuale in apertura
    FRightPanel: TPanel;
    FPassword: string;
    FPendingPath: string;
    FPendingNested: Boolean;
    FItems: TFPList;
    FCurFolder: TFolder;
    FHist: TStringList;     // cronologia delle cartelle visitate (percorsi)
    FHistPos: Integer;
    FNavigating: Boolean;
    FDlgTimer: TTimer;
    FDragTree: TLazVirtualStringTree;
    FDragNode: PVirtualNode;
    FDragStart: TPoint;
    FDragPaths: TStringList;   // elementi da estrarre al rilascio
    FFindMode: Boolean;
    FFindText: string;
    FSortCol: Integer;
    FSortAsc: Boolean;
    FTempDir: string;
    FTempCount: Integer;
    FOpenAfter: string;
    FLastExtractDir: string;
    FExtractOpt: TExtractOptions;
    // job in corso
    FJob: TArcJob;
    FKind: TJobKind;
    FTitle: string;
    FSpecExe: string;
    FSpecParams: TStringList;
    FSpecWork: string;
    FSpecParse: Boolean;
    FJobTicks: Integer;
    FBounce: Integer;
    FBounceDir: Integer;
    FPwdTries: Integer;
    FCreateDest: string;
    FCreatePwd: string;
    FCreateNested: Boolean;
    FCreateRec: Integer;
    FRecKind: TRecKind;
    FRecPct: Integer;
    FTestMsg: string;
    FRepairPath: string;
    // alberi
    function NodeObj(Tree: TBaseVirtualTree; Node: PVirtualNode): TObject;
    procedure SetNodeObj(Tree: TBaseVirtualTree; Node: PVirtualNode; Obj: TObject);
    procedure TreeFoldersInitNode(Sender: TBaseVirtualTree; ParentNode,
      Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
    procedure TreeFoldersGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure TreeFoldersGetImageIndex(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
      var Ghosted: Boolean; var ImageIndex: LongInt);
    procedure TreeFoldersChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure TreeFilesInitNode(Sender: TBaseVirtualTree; ParentNode,
      Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
    procedure TreeFilesGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure TreeFilesGetImageIndex(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
      var Ghosted: Boolean; var ImageIndex: LongInt);
    procedure HdrColumnClick(Sender: TObject; Column: Integer);
    procedure HdrChanged(Sender: TObject);
    procedure SyncColumns;
    procedure TreeFilesNodeDblClick(Sender: TBaseVirtualTree;
      const HitInfo: THitInfo);
    procedure TreeFilesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure OpenItem(O: TObject);
    procedure AsyncNew(Data: PtrInt);
    procedure AsyncOpen(Data: PtrInt);
    procedure TreeDragMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TreeDragMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure DropExtract(const Dest: string);
    procedure TreeFilesDragAllowed(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; var Allowed: Boolean);
    function FindTreeNode(PNode: PVirtualNode; F: TFolder): PVirtualNode;
    procedure SelectFolder(F: TFolder);
    procedure ShowFolder(F: TFolder);
    procedure GoHistory(NewPos: Integer);
    procedure DlgTimerTick(Sender: TObject);
    procedure BuildItems;
    procedure SortItems;
    procedure CollectSelected(Paths: TStrings);
    procedure ItemInfo(O: TObject; out AName, APath: string; out IsDir: Boolean;
      out Size, Pk: Int64; out PkKnown: Boolean; out MT: string);
    procedure SortFolderTree(F: TFolder);
    // interfaccia
    procedure BuildToolbarIcons;
    procedure UpdateButtons;
    procedure UpdateStatus;
    procedure SetBusy(Busy: Boolean);
    // archivio
    procedure OpenArchive(const APath: string);
    procedure ReloadArchive;
    procedure StartList(const APath: string; Nested: Boolean);
    function DebControl(const APath: string; out Member, Fmt: string): Boolean;
    function CtlPipe(const Arc, Member, Fmt: string): string;
    function TarListFile(Items: TStrings): string;
    procedure HandleList(Lines: TStrings; ExitCode: Integer; Nested: Boolean);
    procedure SetModel(M: TArcModel; Nested: Boolean);
    function RequireArchive: Boolean;
    function CanModify: Boolean;
    procedure DoNewArchive(Initial: TStrings);
    procedure DoAdd(Names: TStrings);
    procedure DoExtractTo(const Dest: string; Sel: TStrings; Keep: Boolean;
      Overwrite: Integer; AKind: TJobKind; Flat: Boolean = False);
    function FlatCmd(const Cmd, Dest, Tmp: string; Sel: TStrings): string;
    function NewTempFile(const Prefix: string): string;
    function SrcListFile(const Dir: string; Names: TStrings): string;
    function TempSubDir(const Prefix: string): string;
    function SrcArg(const Dir, Full: string): string;
    // job
    procedure StartJob(AKind: TJobKind; const ATitle: string;
      AParams: TStrings; const AWorkDir: string; AParse: Boolean);
    procedure StartShellJob(AKind: TJobKind; const ATitle, Cmd, AWorkDir: string;
      AParse: Boolean);
    procedure LaunchSpec;
    procedure UpdateProgress;
    procedure FinishJob;
    procedure ShowJobError(const Title: string; Lines: TStrings);
    function NeedsPassword(Lines: TStrings): Boolean;
    function OnlyIgnoredLinks(Lines: TStrings): Boolean;
    function FmtTime(Ms: QWord): string;
    function Z: string;
    function CheckExecutable(const Exe: string): Boolean;
    procedure AsyncCheckExe(Data: PtrInt);
    // dati di recupero
    function DetectRec(const APath: string; out Pct: Integer): TRecKind;
    function QCmd(const Exe: string; P: TStrings): string;
    function RecCreateCmd(const Arc: string; Kind: TRecKind; Pct: Integer): string;
    function RecWrapModify(const Core: string): string;
    function Par2Exe: string;
    procedure StartExeJob(AKind: TJobKind; const ATitle, AExe: string;
      AParams: TStrings; const AWorkDir: string; AParse: Boolean);
    procedure StartRecCheck;
    procedure StartRepair(const APath: string; Kind: TRecKind);
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

const
  SPIN: array[0..3] of string = ('|', '/', '-', '\');

var
  GSortCol: Integer = 0;
  GSortAsc: Boolean = True;

function FmtNum(N: Int64): string;
begin
  Result := FormatFloat('#,##0', N);
end;

{ ---------- ordinamento elementi della lista ---------- }

procedure InfoOf(O: TObject; out IsDir: Boolean; out AName: string;
  out Size, Pk: Int64; out MT: string);
begin
  if O is TFolder then
  begin
    IsDir := True;
    AName := TFolder(O).Name;
    Size := TFolder(O).TotSize;
    if TFolder(O).TotPackKnown then Pk := TFolder(O).TotPacked else Pk := -1;
    MT := TFolder(O).MTime;
  end
  else
  begin
    IsDir := TArcEntry(O).IsDir;
    AName := TArcEntry(O).Name;
    Size := TArcEntry(O).Size;
    if TArcEntry(O).PackKnown then Pk := TArcEntry(O).PackSize else Pk := -1;
    MT := TArcEntry(O).MTime;
  end;
end;

function RatioOf(Size, Pk: Int64): Double;
begin
  if (Pk < 0) or (Size <= 0) then Result := -1
  else Result := Pk / Size;
end;

function CompareItems(A, B: Pointer): Integer;
var
  da, db: Boolean;
  na, nb, ma, mb: string;
  sa, sb, pa, pb: Int64;
  ra, rb: Double;
begin
  InfoOf(TObject(A), da, na, sa, pa, ma);
  InfoOf(TObject(B), db, nb, sb, pb, mb);
  if da <> db then
  begin
    if da then Result := -1 else Result := 1;
    Exit;
  end;
  case GSortCol of
    1: Result := CompareValue(sa, sb);
    2: Result := CompareValue(pa, pb);
    3:
      begin
        ra := RatioOf(sa, pa);
        rb := RatioOf(sb, pb);
        Result := CompareValue(ra, rb);
      end;
    4: Result := CompareStr(ma, mb);
  else
    Result := UTF8CompareText(na, nb);
  end;
  if Result = 0 then Result := UTF8CompareText(na, nb);
  if not GSortAsc then Result := -Result;
end;

function CompareFolders(A, B: Pointer): Integer;
begin
  Result := UTF8CompareText(TFolder(A).Name, TFolder(B).Name);
end;

{ ---------- form ---------- }

{ Il file esiste ma non ha il permesso di esecuzione (succede con i file
  scaricati da internet o copiati da una chiavetta): lo si dice chiaramente. }
function TForm1.CheckExecutable(const Exe: string): Boolean;
var
  nm: string;
begin
  Result := FpAccess(Exe, X_OK) = 0;
  if Result then Exit;
  nm := ExtractFileName(Exe);
  MessageDlg(Tr('Il programma "') + nm + Tr('" non ha il permesso di esecuzione:') + LineEnding +
    Exe + LineEnding + LineEnding +
    Tr('Per abilitarlo apri un terminale e digita:') + LineEnding +
    '    chmod +x ' + ShQuote(Exe) + LineEnding + LineEnding +
    Tr('(oppure chmod 755, o chmod 777). Succede di solito quando il file è stato ') +
    Tr('scaricato da internet o copiato da una chiavetta USB.') + LineEnding +
    Tr('Se la cartella si trova su un disco montato senza permesso di esecuzione ') +
    Tr('(per esempio una chiavetta FAT/exFAT), copia TTCompressor in una cartella della ') +
    Tr('tua home e riprova.'), mtError, [mbOK], 0);
end;

procedure TForm1.AsyncCheckExe(Data: PtrInt);
begin
  if (FSevenZip <> '') and FileExists(FSevenZip) then CheckExecutable(FSevenZip);
end;

function TForm1.Z: string;
begin
  Result := FSevenZip;
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  C: TVirtualTreeColumn;
  hlp: string;
begin
  TranslateComponent(Self);   // menu e suggerimenti definiti nel .lfm
  FSevenZip := ExtractFilePath(Application.ExeName) + '7z';
  if not FileExists(FSevenZip) then
    FSevenZip := FindDefaultExecutablePath('7zz');
  if FSevenZip = '' then FSevenZip := FindDefaultExecutablePath('7z');
  // il 7z modificato accetta -slc (elenco con le sole proprieta necessarie) e
  // stampa l'avanzamento dell'apertura dell'archivio
  FFastList := False;
  if FSevenZip <> '' then
    try
      if RunCommand(FSevenZip, ['-h'], hlp) then
        FFastList := Pos('-slc', hlp) > 0;
    except
      FFastList := False;
    end;
  FItems := TFPList.Create;
  FHist := TStringList.Create;
  FDragPaths := TStringList.Create;
  FHistPos := -1;
  FDlgTimer := TTimer.Create(Self);
  FDlgTimer.Interval := 40;
  FDlgTimer.OnTimer := @DlgTimerTick;
  FSpecParams := TStringList.Create;
  FSortAsc := True;
  FExtractOpt.KeepPaths := True;
  FExtractOpt.Overwrite := 0;
  FExtractOpt.AllowLinks := False;
  FTempDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'ttcompressor-' +
    IntToStr(GetProcessID);

  FIcons := TSysIcons.Create(16);
  BuildToolbarIcons;

  // albero delle cartelle
  TreeFolders.NodeDataSize := SizeOf(Pointer);
  TreeFolders.Images := FIcons.Images;
  TreeFolders.Header.Options := TreeFolders.Header.Options - [hoVisible];
  TreeFolders.TreeOptions.PaintOptions :=
    TreeFolders.TreeOptions.PaintOptions - [toShowTreeLines] + [toShowRoot, toShowButtons];
  TreeFolders.TreeOptions.SelectionOptions :=
    TreeFolders.TreeOptions.SelectionOptions + [toFullRowSelect];
  TreeFolders.OnInitNode := @TreeFoldersInitNode;
  TreeFolders.OnGetText := @TreeFoldersGetText;
  TreeFolders.OnGetImageIndex := @TreeFoldersGetImageIndex;
  TreeFolders.OnChange := @TreeFoldersChange;

  // elenco dei file
  TreeFiles.NodeDataSize := SizeOf(Pointer);
  TreeFiles.Images := FIcons.Images;
  // intestazione delle colonne disegnata e ridimensionata da noi (szheader):
  // quella di VirtualTreeView e nascosta, le sue colonne seguono le nostre larghezze
  FRightPanel := TPanel.Create(Self);
  FRightPanel.Parent := Self;
  FRightPanel.BevelOuter := bvNone;
  FRightPanel.Align := alClient;
  FRightPanel.TabOrder := 5;
  TreeFiles.Parent := FRightPanel;
  TreeFiles.Align := alClient;
  FHdr := TSzHeader.Create(Self);
  FHdr.Parent := FRightPanel;
  FHdr.Align := alTop;
  FHdr.OnColumnClick := @HdrColumnClick;
  FHdr.OnChanged := @HdrChanged;
  TreeFiles.Header.Options := TreeFiles.Header.Options - [hoVisible, hoColumnResize,
    hoAutoResize, hoDrag, hoShowSortGlyphs];
  TreeFiles.TreeOptions.SelectionOptions :=
    TreeFiles.TreeOptions.SelectionOptions + [toMultiSelect, toFullRowSelect,
    toRightClickSelect];
  TreeFiles.TreeOptions.MiscOptions :=
    TreeFiles.TreeOptions.MiscOptions - [toToggleOnDblClick];
  TreeFiles.TreeOptions.PaintOptions :=
    TreeFiles.TreeOptions.PaintOptions - [toShowRoot, toShowTreeLines, toShowButtons];
  TreeFiles.Header.Columns.Clear;
  FHdr.AddColumn(Tr('Nome'), 330, False);
  FHdr.AddColumn(Tr('Dimensione'), 110, True);
  FHdr.AddColumn(Tr('Dim. compressa'), 120, True);
  FHdr.AddColumn(Tr('Rapporto'), 80, True);
  FHdr.AddColumn(Tr('Modificato'), 140, False);
  FHdr.SetSort(0, True);
  C := TreeFiles.Header.Columns.Add;
  C.Text := Tr('Nome');
  C.Width := 330;
  C := TreeFiles.Header.Columns.Add;
  C.Text := Tr('Dimensione');
  C.Width := 110;
  C.Alignment := taRightJustify;
  C := TreeFiles.Header.Columns.Add;
  C.Text := Tr('Dim. compressa');
  C.Width := 120;
  C.Alignment := taRightJustify;
  C := TreeFiles.Header.Columns.Add;
  C.Text := Tr('Rapporto');
  C.Width := 80;
  C.Alignment := taRightJustify;
  C := TreeFiles.Header.Columns.Add;
  C.Text := Tr('Modificato');
  C.Width := 140;
  TreeFiles.Header.MainColumn := 0;
  TreeFiles.Header.AutoSizeIndex := -1;
  TreeFiles.Header.SortColumn := 0;
  TreeFiles.Header.SortDirection := sdAscending;
  TreeFiles.OnInitNode := @TreeFilesInitNode;
  TreeFiles.OnGetText := @TreeFilesGetText;
  TreeFiles.OnGetImageIndex := @TreeFilesGetImageIndex;
  TreeFiles.OnNodeDblClick := @TreeFilesNodeDblClick;
  TreeFiles.OnKeyDown := @TreeFilesKeyDown;
  // trascinamento verso il file manager
  TreeFiles.OnDragAllowed := @TreeFilesDragAllowed;
  TreeFiles.TreeOptions.MiscOptions := TreeFiles.TreeOptions.MiscOptions + [toFullRowDrag];
  DragManager.DragThreshold := 100000;   // il trascinamento interno dell'albero non serve
  TreeFiles.OnMouseDown := @TreeDragMouseDown;
  TreeFiles.OnMouseMove := @TreeDragMouseMove;
  TreeFolders.OnMouseDown := @TreeDragMouseDown;
  TreeFolders.OnMouseMove := @TreeDragMouseMove;
  HookDragSource(PGtkWidget(TreeFiles.Handle));
  HookDragSource(PGtkWidget(TreeFolders.Handle));

  miOpen.ShortCut := ShortCut(Ord('O'), [ssCtrl]);
  miNew.ShortCut := ShortCut(Ord('N'), [ssCtrl]);
  miFind.ShortCut := ShortCut(Ord('F'), [ssCtrl]);
  miQuit.ShortCut := ShortCut(Ord('Q'), [ssCtrl]);
  UpdateButtons;
  UpdateStatus;
end;

procedure TForm1.AsyncNew(Data: PtrInt);
var
  L: TStringList;
begin
  L := TStringList(Data);
  try
    DoNewArchive(L);
  finally
    L.Free;
  end;
end;

procedure TForm1.FormShow(Sender: TObject);
var
  L: TStringList;
  i: Integer;
begin
  // larghezze colonne: impostate ora che il layout e definitivo
  FHdr.Widths[1] := 110;
  FHdr.Widths[2] := 120;
  FHdr.Widths[3] := 80;
  FHdr.Widths[4] := 140;
  SyncColumns;
  OnShow := nil;
  if ParamCount < 1 then
  begin
    Application.QueueAsyncCall(@AsyncCheckExe, 0);
    Exit;
  end;
  if (ParamStr(1) = '--new') or (ParamStr(1) = '-n') then
  begin
    // ttcompressor --new file1 dir2 ... : apre il dialogo di creazione con questi elementi
    L := TStringList.Create;
    try
      for i := 2 to ParamCount do L.Add(ExpandFileName(ParamStr(i)));
      Application.QueueAsyncCall(@AsyncNew, PtrInt(L));
    except
      L.Free;
      raise;
    end;
  end
  else if FileExists(ParamStr(1)) and (FModel = nil) then
    OpenArchive(ExpandFileName(ParamStr(1)));
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FDlgTimer.Enabled := False;
  FHist.Free;
  FDragPaths.Free;
  TreeFiles.Clear;
  TreeFolders.Clear;
  FModel.Free;
  FIcons.Free;
  FItems.Free;
  FSpecParams.Free;
  if DirectoryExists(FTempDir) then DeleteDirectory(FTempDir, False);
end;

procedure TForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FJob <> nil then
  begin
    if MessageDlg(Tr('Un''operazione è in corso. Interromperla e uscire?'),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    begin
      CanClose := False;
      Exit;
    end;
    FJob.Cancel;
    FJob.WaitFor;
    FreeAndNil(FJob);
    TimerJob.Enabled := False;
  end;
end;

procedure TForm1.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  L: TStringList;
  i: Integer;
begin
  if FJob <> nil then Exit;
  if (FModel = nil) and (Length(FileNames) = 1) and FileExists(FileNames[0]) then
  begin
    OpenArchive(FileNames[0]);
    Exit;
  end;
  L := TStringList.Create;
  try
    for i := 0 to High(FileNames) do L.Add(FileNames[i]);
    if FModel = nil then
      DoNewArchive(L)
    else if MessageDlg(Format(Tr('Aggiungere %d elementi all''archivio?'), [L.Count]),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      DoAdd(L);
  finally
    L.Free;
  end;
end;

{ ---------- icone della toolbar ---------- }

procedure TForm1.BuildToolbarIcons;
const
  Fallback: array[0..8] of string = ('N', '+', 'E', 'V', 'X', '?', '<', '>', '^');
var
  Names: array[0..8] of array of string;
  i: Integer;
  bmp: TBitmap;
begin
  SetLength(Names[0], 4);
  Names[0][0] := 'document-new'; Names[0][1] := 'archive-new';
  Names[0][2] := 'filenew'; Names[0][3] := 'gtk-new';
  SetLength(Names[1], 4);
  Names[1][0] := 'archive-insert'; Names[1][1] := 'list-add';
  Names[1][2] := 'gtk-add'; Names[1][3] := 'add';
  SetLength(Names[2], 5);
  Names[2][0] := 'archive-extract'; Names[2][1] := 'extract-archive';
  Names[2][2] := 'document-save-as'; Names[2][3] := 'go-down';
  Names[2][4] := 'gtk-save-as';
  SetLength(Names[3], 5);
  Names[3][0] := 'security-high'; Names[3][1] := 'emblem-ok';
  Names[3][2] := 'dialog-ok'; Names[3][3] := 'gtk-apply';
  Names[3][4] := 'object-select';
  SetLength(Names[4], 4);
  Names[4][0] := 'edit-delete'; Names[4][1] := 'list-remove';
  Names[4][2] := 'gtk-delete'; Names[4][3] := 'user-trash';
  SetLength(Names[5], 4);
  Names[5][0] := 'edit-find'; Names[5][1] := 'system-search';
  Names[5][2] := 'gtk-find'; Names[5][3] := 'search';
  SetLength(Names[6], 3);
  Names[6][0] := 'go-previous'; Names[6][1] := 'gtk-go-back'; Names[6][2] := 'back';
  SetLength(Names[7], 3);
  Names[7][0] := 'go-next'; Names[7][1] := 'gtk-go-forward'; Names[7][2] := 'forward';
  SetLength(Names[8], 3);
  Names[8][0] := 'go-up'; Names[8][1] := 'gtk-go-up'; Names[8][2] := 'up';
  ImageListTool.Clear;
  for i := 0 to 8 do
  begin
    bmp := ThemeBitmap(Names[i], 32);
    if bmp = nil then
    begin
      // fallback: quadrato con una lettera
      bmp := TBitmap.Create;
      bmp.SetSize(32, 32);
      bmp.Canvas.Brush.Color := clSilver;
      bmp.Canvas.Pen.Color := clGray;
      bmp.Canvas.RoundRect(2, 2, 30, 30, 6, 6);
      bmp.Canvas.Font.Size := 12;
      bmp.Canvas.Font.Style := [fsBold];
      bmp.Canvas.TextOut(16 - bmp.Canvas.TextWidth(Fallback[i]) div 2,
        16 - bmp.Canvas.TextHeight(Fallback[i]) div 2, Fallback[i]);
    end;
    try
      ImageListTool.Add(bmp, nil);
    finally
      bmp.Free;
    end;
  end;
end;

procedure TForm1.UpdateButtons;
var
  hasArc, idle: Boolean;
begin
  idle := FJob = nil;
  hasArc := (FModel <> nil) and idle;
  tbNew.Enabled := idle;
  tbAdd.Enabled := idle;
  tbExtract.Enabled := hasArc;
  tbTest.Enabled := hasArc;
  tbDelete.Enabled := hasArc;
  tbFind.Enabled := hasArc;
  tbBack.Enabled := hasArc and (FHistPos > 0);
  tbForward.Enabled := hasArc and (FHistPos >= 0) and (FHistPos < FHist.Count - 1);
  tbUp.Enabled := hasArc and (FCurFolder <> nil) and (FCurFolder.Parent <> nil);
  miBack.Enabled := tbBack.Enabled;
  miForward.Enabled := tbForward.Enabled;
  miUp.Enabled := tbUp.Enabled;
  miNew.Enabled := idle;
  miOpen.Enabled := idle;
  miAdd.Enabled := idle;
  miRepair.Enabled := idle;
  miAddRec.Enabled := hasArc and idle;
  miExtract.Enabled := hasArc;
  miTest.Enabled := hasArc;
  miDelete.Enabled := hasArc;
  miFind.Enabled := hasArc;
  PopupFiles.Items.Enabled := hasArc;
end;

procedure TForm1.UpdateStatus;
var
  n: Integer;
  s: string;
begin
  if FModel = nil then
  begin
    StatusBar1.SimpleText := Tr('Nessun archivio aperto. Usare "Archivio > Apri" o trascinare qui un archivio.');
    Caption := 'TTCompressor';
    Exit;
  end;
  n := FModel.Entries.Count;
  s := ExtractFileName(FArcPath) + ' - ' + IntToStr(n) + Tr(' elementi');
  if FFindMode then
    s := s + ' - ' + IntToStr(FItems.Count) + Tr(' risultati per "') + FFindText + '"'
  else
    s := s + ' - ' + IntToStr(FItems.Count) + Tr(' elementi nella cartella');
  s := s + Tr(' - dimensione totale ') + FmtNum(FModel.Root.TotSize) + Tr(' byte');
  case FRecKind of
    rkTail: s := s + Tr(' - dati di recupero: in coda (') + IntToStr(FRecPct) + '%)';
    rkPar2: s := s + Tr(' - dati di recupero: PAR2 (circa ') + IntToStr(FRecPct) + '%)';
  end;
  StatusBar1.SimpleText := s;
  if FJob = nil then Caption := ExtractFileName(FArcPath) + ' - TTCompressor';
end;

{ ---------- alberi ---------- }

function TForm1.NodeObj(Tree: TBaseVirtualTree; Node: PVirtualNode): TObject;
var
  P: PPointer;
begin
  Result := nil;
  if Node = nil then Exit;
  P := PPointer(Tree.GetNodeData(Node));
  if P <> nil then Result := TObject(P^);
end;

procedure TForm1.SetNodeObj(Tree: TBaseVirtualTree; Node: PVirtualNode; Obj: TObject);
var
  P: PPointer;
begin
  P := PPointer(Tree.GetNodeData(Node));
  if P <> nil then P^ := Pointer(Obj);
end;

procedure TForm1.TreeFoldersInitNode(Sender: TBaseVirtualTree; ParentNode,
  Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
var
  F: TFolder;
begin
  if FModel = nil then Exit;
  if ParentNode = nil then
    F := FModel.Root
  else
    F := TFolder(TFolder(NodeObj(Sender, ParentNode)).Children[Node^.Index]);
  SetNodeObj(Sender, Node, F);
  if F.Children.Count > 0 then
    Sender.ChildCount[Node] := F.Children.Count;
  if ParentNode = nil then Include(InitialStates, ivsExpanded);
end;

procedure TForm1.TreeFoldersGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
var
  F: TFolder;
begin
  F := TFolder(NodeObj(Sender, Node));
  if F = nil then Exit;
  if F.Parent = nil then
    CellText := ExtractFileName(FArcPath)
  else
    CellText := F.Name;
end;

procedure TForm1.TreeFoldersGetImageIndex(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: LongInt);
var
  F: TFolder;
begin
  if not (Kind in [ikNormal, ikSelected]) then Exit;
  F := TFolder(NodeObj(Sender, Node));
  if F = nil then Exit;
  if F.Parent = nil then ImageIndex := FIcons.ArchiveIndex
  else ImageIndex := FIcons.FolderIndex;
end;

procedure TForm1.TreeFoldersChange(Sender: TBaseVirtualTree; Node: PVirtualNode);
var
  F: TFolder;
begin
  if Node = nil then Exit;
  F := TFolder(NodeObj(Sender, Node));
  if (F <> nil) and ((F <> FCurFolder) or FFindMode) then ShowFolder(F);
end;

function TForm1.FindTreeNode(PNode: PVirtualNode; F: TFolder): PVirtualNode;
var
  N: PVirtualNode;
  C: TFolder;
begin
  Result := nil;
  N := TreeFolders.GetFirstChild(PNode);
  while N <> nil do
  begin
    C := TFolder(NodeObj(TreeFolders, N));
    if C = F then Exit(N);
    if (C <> nil) and (Pos(C.Path + '/', F.Path + '/') = 1) then
    begin
      TreeFolders.Expanded[N] := True;
      Result := FindTreeNode(N, F);
      if Result <> nil then Exit;
    end;
    N := TreeFolders.GetNextSibling(N);
  end;
end;

procedure TForm1.SelectFolder(F: TFolder);
var
  N: PVirtualNode;
begin
  if F.Parent = nil then
    N := TreeFolders.GetFirst
  else
    N := FindTreeNode(TreeFolders.GetFirst, F);
  if N = nil then Exit;
  TreeFolders.ClearSelection;
  TreeFolders.FocusedNode := N;
  TreeFolders.Selected[N] := True;
  TreeFolders.ScrollIntoView(N, False);
  ShowFolder(F);
end;

procedure TForm1.ItemInfo(O: TObject; out AName, APath: string; out IsDir: Boolean;
  out Size, Pk: Int64; out PkKnown: Boolean; out MT: string);
begin
  if O is TFolder then
  begin
    AName := TFolder(O).Name;
    APath := TFolder(O).Path;
    IsDir := True;
    Size := TFolder(O).TotSize;
    Pk := TFolder(O).TotPacked;
    PkKnown := TFolder(O).TotPackKnown;
    MT := TFolder(O).MTime;
  end
  else
  begin
    AName := TArcEntry(O).Name;
    APath := TArcEntry(O).Path;
    IsDir := TArcEntry(O).IsDir;
    Size := TArcEntry(O).Size;
    Pk := TArcEntry(O).PackSize;
    PkKnown := TArcEntry(O).PackKnown;
    MT := TArcEntry(O).MTime;
  end;
end;

procedure TForm1.TreeFilesInitNode(Sender: TBaseVirtualTree; ParentNode,
  Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
begin
  if Integer(Node^.Index) < FItems.Count then
    SetNodeObj(Sender, Node, TObject(FItems[Node^.Index]));
end;

procedure TForm1.TreeFilesGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
var
  O: TObject;
  nm, pth, mt: string;
  isDir, pkKnown: Boolean;
  sz, pk: Int64;
begin
  O := NodeObj(Sender, Node);
  CellText := '';
  if O = nil then Exit;
  ItemInfo(O, nm, pth, isDir, sz, pk, pkKnown, mt);
  case Column of
    0: if FFindMode then CellText := pth else CellText := nm;
    1: CellText := FmtNum(sz);
    2: if pkKnown then CellText := FmtNum(pk);
    3: if pkKnown and (sz > 0) then
         CellText := FormatFloat('0.0', pk / sz * 100) + ' %';
    4: CellText := Copy(mt, 1, 16);
  end;
end;

procedure TForm1.TreeFilesGetImageIndex(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: LongInt);
var
  O: TObject;
begin
  if (Column <> 0) or not (Kind in [ikNormal, ikSelected]) then Exit;
  O := NodeObj(Sender, Node);
  if O = nil then Exit;
  if O is TFolder then
    ImageIndex := FIcons.FolderIndex
  else if TArcEntry(O).IsDir then
    ImageIndex := FIcons.FolderIndex
  else
    ImageIndex := FIcons.IndexForFile(TArcEntry(O).Name);
end;

procedure TForm1.HdrColumnClick(Sender: TObject; Column: Integer);
begin
  if Column < 0 then Exit;
  if FSortCol = Column then
    FSortAsc := not FSortAsc
  else
  begin
    FSortCol := Column;
    FSortAsc := True;
  end;
  FHdr.SetSort(FSortCol, FSortAsc);
  BuildItems;
end;

{ Le colonne di VirtualTreeView seguono le larghezze dell'intestazione. }
procedure TForm1.SyncColumns;
var
  i, sb: Integer;
begin
  if (FHdr = nil) or (TreeFiles.Header.Columns.Count < FHdr.Count) then Exit;
  // spazio occupato a destra dalla barra di scorrimento verticale
  sb := TreeFiles.Width - TreeFiles.ClientWidth;
  if sb < 0 then sb := 0;
  FHdr.Edge := sb;
  for i := 0 to FHdr.Count - 1 do
    if TreeFiles.Header.Columns[i].Width <> FHdr.Widths[i] then
      TreeFiles.Header.Columns[i].Width := FHdr.Widths[i];
end;

procedure TForm1.HdrChanged(Sender: TObject);
begin
  SyncColumns;
end;

procedure TForm1.OpenItem(O: TObject);
var
  F: TFolder;
  A: TArcEntry;
  L: TStringList;
  tmp: string;
begin
  if (FJob <> nil) or (O = nil) then Exit;
  if O is TFolder then
    SelectFolder(TFolder(O))
  else
  begin
    A := TArcEntry(O);
    if A.IsDir then
    begin
      F := FModel.FindFolder(A.Path, False);
      if F <> nil then SelectFolder(F);
    end
    else
    begin
      // estrae in una cartella temporanea e apre con l'applicazione di sistema
      L := TStringList.Create;
      try
        L.Add(A.Path);
        tmp := TempSubDir('open');
        FOpenAfter := tmp + PathDelim + A.Path;
        DoExtractTo(tmp, L, True, 1, jkOpenFile);
      finally
        L.Free;
      end;
    end;
  end;
end;

procedure TForm1.TreeFilesNodeDblClick(Sender: TBaseVirtualTree;
  const HitInfo: THitInfo);
begin
  // OpenItem ricostruisce la lista: va fatto dopo che l'albero ha finito di
  // gestire il doppio clic, altrimenti usa un nodo gia distrutto
  if HitInfo.HitNode <> nil then
    Application.QueueAsyncCall(@AsyncOpen, PtrInt(NodeObj(Sender, HitInfo.HitNode)));
end;

procedure TForm1.TreeDragMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragNode := nil;
  if (Button <> mbLeft) or ([ssShift, ssCtrl] * Shift <> []) then Exit;
  FDragTree := TLazVirtualStringTree(Sender);
  FDragNode := FDragTree.GetNodeAt(X, Y);
  FDragStart := Point(X, Y);
end;

procedure TForm1.TreeDragMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  O: TObject;
  nm: string;
begin
  if (FDragNode = nil) or not (ssLeft in Shift) or (FModel = nil) or (FJob <> nil) then
  begin
    if not (ssLeft in Shift) then FDragNode := nil;
    Exit;
  end;
  if (Abs(X - FDragStart.X) < 8) and (Abs(Y - FDragStart.Y) < 8) then Exit;
  FDragPaths.Clear;
  if FDragTree = TreeFiles then
  begin
    if not (vsSelected in FDragNode^.States) then
    begin
      TreeFiles.ClearSelection;
      TreeFiles.Selected[FDragNode] := True;
    end;
    CollectSelected(FDragPaths);
    if FDragPaths.Count = 1 then nm := ExtractFileName(FDragPaths[0])
    else nm := StripArchiveExt(ExtractFileName(FArcPath));
  end
  else
  begin
    O := NodeObj(TreeFolders, FDragNode);
    if (O is TFolder) and (TFolder(O).Parent <> nil) then
    begin
      FDragPaths.Add(TFolder(O).Path);
      nm := TFolder(O).Name;
    end
    else
      nm := StripArchiveExt(ExtractFileName(FArcPath));   // radice: tutto l'archivio
  end;
  FDragNode := nil;
  if nm = '' then nm := Tr('estratti');
  BeginExtractDrag(PGtkWidget(FDragTree.Handle), nm, @DropExtract);
end;

procedure TForm1.TreeFilesDragAllowed(Sender: TBaseVirtualTree; Node: PVirtualNode;
  Column: TColumnIndex; var Allowed: Boolean);
begin
  // serve solo perche l'albero conservi la selezione multipla al clic su un
  // elemento selezionato: il trascinamento vero e proprio e gestito da noi
  Allowed := True;
end;

procedure TForm1.DropExtract(const Dest: string);
begin
  if (FModel = nil) or (FJob <> nil) then Exit;
  FExtractOpt.DestDir := Dest;
  DoExtractTo(Dest, FDragPaths, True, 0, jkExtract, True);
end;

procedure TForm1.AsyncOpen(Data: PtrInt);
begin
  OpenItem(TObject(Data));
end;

procedure TForm1.TreeFilesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_DELETE then
  begin
    Key := 0;
    actDeleteExecute(nil);
  end
  else if Key = VK_RETURN then
  begin
    Key := 0;
    OpenItem(NodeObj(TreeFiles, TreeFiles.FocusedNode));
  end;
end;

procedure TForm1.SortFolderTree(F: TFolder);
var
  i: Integer;
begin
  F.Children.Sort(@CompareFolders);
  for i := 0 to F.Children.Count - 1 do
    SortFolderTree(TFolder(F.Children[i]));
end;

procedure TForm1.ShowFolder(F: TFolder);
begin
  FCurFolder := F;
  FFindMode := False;
  if not FNavigating then
    if (FHistPos < 0) or (FHist[FHistPos] <> F.Path) then
    begin
      while FHist.Count > FHistPos + 1 do FHist.Delete(FHist.Count - 1);
      FHist.Add(F.Path);
      FHistPos := FHist.Count - 1;
    end;
  BuildItems;
  UpdateButtons;
end;

procedure TForm1.GoHistory(NewPos: Integer);
var
  F: TFolder;
begin
  if (FModel = nil) or (FJob <> nil) then Exit;
  if (NewPos < 0) or (NewPos >= FHist.Count) then Exit;
  F := FModel.FindFolder(FHist[NewPos], False);
  if F = nil then Exit;
  FNavigating := True;
  try
    FHistPos := NewPos;
    SelectFolder(F);
  finally
    FNavigating := False;
  end;
  UpdateButtons;
end;

procedure TForm1.actBackExecute(Sender: TObject);
begin
  GoHistory(FHistPos - 1);
end;

procedure TForm1.actForwardExecute(Sender: TObject);
begin
  GoHistory(FHistPos + 1);
end;

procedure TForm1.actUpExecute(Sender: TObject);
begin
  if (FJob <> nil) or (FCurFolder = nil) or (FCurFolder.Parent = nil) then Exit;
  SelectFolder(FCurFolder.Parent);
end;

procedure TForm1.DlgTimerTick(Sender: TObject);
begin
  // gli avvisi e i dialoghi dei file sono finestre GTK che il sistema
  // posiziona al centro dello schermo: li riportiamo dentro questa finestra
  if Visible and (WindowState <> wsMinimized) then
    CenterToplevelsOver(BoundsRect, Pointer(Handle));
end;

procedure TForm1.BuildItems;
var
  i: Integer;
  A: TArcEntry;
  mask: string;
  wild: Boolean;
begin
  FItems.Clear;
  if FModel <> nil then
  begin
    if FFindMode then
    begin
      wild := (Pos('*', FFindText) > 0) or (Pos('?', FFindText) > 0);
      mask := UTF8LowerCase(FFindText);
      for i := 0 to FModel.Entries.Count - 1 do
      begin
        A := TArcEntry(FModel.Entries[i]);
        if wild then
        begin
          if MatchesMask(UTF8LowerCase(A.Name), mask) then FItems.Add(A);
        end
        else if Pos(mask, UTF8LowerCase(A.Name)) > 0 then
          FItems.Add(A);
      end;
    end
    else if FCurFolder <> nil then
    begin
      for i := 0 to FCurFolder.Children.Count - 1 do
        FItems.Add(FCurFolder.Children[i]);
      for i := 0 to FCurFolder.FileList.Count - 1 do
        FItems.Add(FCurFolder.FileList[i]);
    end;
  end;
  SortItems;
  TreeFiles.BeginUpdate;
  try
    TreeFiles.Clear;
    TreeFiles.RootNodeCount := FItems.Count;
  finally
    TreeFiles.EndUpdate;
  end;
  SyncColumns;
  UpdateStatus;
end;

procedure TForm1.SortItems;
begin
  GSortCol := FSortCol;
  GSortAsc := FSortAsc;
  FItems.Sort(@CompareItems);
end;

procedure TForm1.CollectSelected(Paths: TStrings);
var
  N: PVirtualNode;
  O: TObject;
begin
  Paths.Clear;
  N := TreeFiles.GetFirstSelected;
  while N <> nil do
  begin
    O := NodeObj(TreeFiles, N);
    if O is TFolder then Paths.Add(TFolder(O).Path)
    else if O is TArcEntry then Paths.Add(TArcEntry(O).Path);
    N := TreeFiles.GetNextSelected(N);
  end;
end;

procedure TForm1.miSelectAllClick(Sender: TObject);
begin
  TreeFiles.SelectAll(False);
end;

{ ---------- temporanei ---------- }

function TForm1.NewTempFile(const Prefix: string): string;
begin
  ForceDirectories(FTempDir);
  Inc(FTempCount);
  Result := FTempDir + PathDelim + Prefix + IntToStr(FTempCount) + '.txt';
end;

function TForm1.TempSubDir(const Prefix: string): string;
begin
  Inc(FTempCount);
  Result := FTempDir + PathDelim + Prefix + IntToStr(FTempCount);
  ForceDirectories(Result);
end;

{ ---------- gestione job ---------- }

function TForm1.FmtTime(Ms: QWord): string;
var
  s: QWord;
begin
  s := Ms div 1000;
  if s >= 3600 then
    Result := Format('%d:%.2d:%.2d', [s div 3600, (s div 60) mod 60, s mod 60])
  else
    Result := Format('%d:%.2d', [s div 60, s mod 60]);
end;

procedure TForm1.SetBusy(Busy: Boolean);
begin
  PanelProgress.Visible := Busy;
  TimerJob.Enabled := Busy;
  TreeFolders.Enabled := not Busy;
  TreeFiles.Enabled := not Busy;
  UpdateButtons;
end;

procedure TForm1.StartJob(AKind: TJobKind; const ATitle: string;
  AParams: TStrings; const AWorkDir: string; AParse: Boolean);
begin
  StartExeJob(AKind, ATitle, Z, AParams, AWorkDir, AParse);
end;

procedure TForm1.StartExeJob(AKind: TJobKind; const ATitle, AExe: string;
  AParams: TStrings; const AWorkDir: string; AParse: Boolean);
begin
  if FJob <> nil then Exit;
  FKind := AKind;
  FTitle := ATitle;
  FSpecExe := AExe;
  FSpecParams.Assign(AParams);
  FSpecWork := AWorkDir;
  FSpecParse := AParse;
  FPwdTries := 0;
  LaunchSpec;
end;

procedure TForm1.StartShellJob(AKind: TJobKind; const ATitle, Cmd, AWorkDir: string;
  AParse: Boolean);
var
  P: TStringList;
begin
  P := TStringList.Create;
  try
    P.Add('-c');
    P.Add(Cmd);
    if FJob <> nil then Exit;
    FKind := AKind;
    FTitle := ATitle;
    FSpecExe := '/bin/sh';
    FSpecParams.Assign(P);
    FSpecWork := AWorkDir;
    FSpecParse := AParse;
    FPwdTries := 0;
    LaunchSpec;
  finally
    P.Free;
  end;
end;

procedure TForm1.LaunchSpec;
var
  P: TStringList;
  i: Integer;
  s: string;
begin
  if (FSpecExe = '') or not FileExists(FSpecExe) then
  begin
    MessageDlg(Tr('Programma 7z non trovato (atteso accanto a TTCompressor).'), mtError, [mbOK], 0);
    Exit;
  end;
  if not CheckExecutable(FSpecExe) then Exit;
  P := TStringList.Create;
  try
    for i := 0 to FSpecParams.Count - 1 do
    begin
      s := FSpecParams[i];
      if s = '@PWD@' then
      begin
        if FPassword <> '' then P.Add('-p' + FPassword);
      end
      else if Pos('@PWD@', s) > 0 then
      begin
        if FPassword <> '' then
          s := StringReplace(s, '@PWD@', ShQuote('-p' + FPassword), [rfReplaceAll])
        else
          s := StringReplace(s, '@PWD@', '', [rfReplaceAll]);
        P.Add(s);
      end
      else
        P.Add(s);
    end;
    FJob := TArcJob.Create(FSpecExe, P, FSpecWork, FSpecParse);
    FJob.KeepAll := FSpecParse and (FKind in [jkList, jkListNested]);
  finally
    P.Free;
  end;
  FJobTicks := 0;
  FBounce := 0;
  FBounceDir := 1;
  ProgressBar1.Position := 0;
  lblProgress.Caption := FTitle + ' ...';
  lblFile.Caption := '';
  lblTime.Caption := '';
  SetBusy(True);
  FJob.Start;
end;

procedure TForm1.btnCancelClick(Sender: TObject);
begin
  if FJob <> nil then
  begin
    FJob.Cancel;
    btnCancel.Enabled := False;
    lblProgress.Caption := Tr('Annullamento ...');
  end;
end;

procedure TForm1.TimerJobTimer(Sender: TObject);
begin
  if FJob = nil then
  begin
    TimerJob.Enabled := False;
    Exit;
  end;
  if FJob.Finished then
    FinishJob
  else
    UpdateProgress;
end;

procedure TForm1.TreeFilesResize(Sender: TObject);
begin
  SyncColumns;
end;

procedure TForm1.TreeFoldersResize(Sender: TObject);
begin
end;

procedure TForm1.UpdateProgress;
var
  pct: Double;
  ptxt, cur, eta, stale: string;
  has: Boolean;
  since, elapsed: QWord;
  remain: QWord;
begin
  Inc(FJobTicks);
  FJob.GetState(pct, ptxt, has, cur, since, elapsed);
  if has then
  begin
    ProgressBar1.Position := Round(Min(100, Max(0, pct)) * 1000);
    lblProgress.Caption := SPIN[FJobTicks mod 4] + '  ' + FTitle + '   ' + ptxt + ' %';
    Caption := ptxt + ' % - TTCompressor';
    if cur <> '' then lblFile.Caption := cur;
  end
  else
  begin
    // nessuna percentuale ancora: barra "rimbalzante"
    Inc(FBounce, 2500 * FBounceDir);
    if FBounce >= 100000 then FBounceDir := -1;
    if FBounce <= 0 then FBounceDir := 1;
    FBounce := Max(0, Min(100000, FBounce));
    ProgressBar1.Position := FBounce;
    lblProgress.Caption := SPIN[FJobTicks mod 4] + '  ' + FTitle + ' ...';
  end;
  eta := '';
  if has and (pct >= 1) and (pct < 100) and (elapsed > 2000) then
  begin
    remain := Round(elapsed * (100 - pct) / pct);
    eta := Tr('   -   rimanente circa ') + FmtTime(remain);
  end;
  stale := '';
  if since > 4000 then
    stale := Tr('   (nessun aggiornamento da ') + IntToStr(since div 1000) + Tr(' s, elaborazione in corso)');
  lblTime.Caption := Tr('Trascorso ') + FmtTime(elapsed) + eta + stale;
end;

function TForm1.OnlyIgnoredLinks(Lines: TStrings): Boolean;
var
  i, n: Integer;
begin
  // 7z termina con codice 2 se ignora un link simbolico "pericoloso", ma
  // tutto il resto viene estratto: in quel caso e solo un avviso.
  n := 0;
  Result := True;
  for i := 0 to Lines.Count - 1 do
    if Pos('ERROR:', Lines[i]) > 0 then
    begin
      Inc(n);
      if Pos('Dangerous symbolic link', Lines[i]) = 0 then Result := False;
    end;
  if n = 0 then Result := False;
end;

function TForm1.NeedsPassword(Lines: TStrings): Boolean;
var
  i: Integer;
  l: string;
begin
  Result := False;
  for i := 0 to Lines.Count - 1 do
  begin
    l := LowerCase(Lines[i]);
    if (Pos('enter password', l) > 0) or (Pos('wrong password', l) > 0) then
      Exit(True);
  end;
end;

procedure TForm1.ShowJobError(const Title: string; Lines: TStrings);
var
  i, from: Integer;
  S: string;
begin
  from := Max(0, Lines.Count - 12);
  S := '';
  for i := from to Lines.Count - 1 do
    if Trim(Lines[i]) <> '' then S := S + Lines[i] + LineEnding;
  if S = '' then S := Tr('Operazione non riuscita.');
  MessageDlg(Title, S, mtError, [mbOK], 0);
end;

procedure TForm1.FinishJob;
var
  J: TArcJob;
  Lines: TStringList;
  code: Integer;
  cancelled: Boolean;
  kind: TJobKind;
  pwd: string;
  i: Integer;
  okLine: Boolean;
  msg: string;
begin
  J := FJob;
  J.WaitFor;
  Lines := TStringList.Create;
  try
    J.CopyLines(Lines);
    FListRaw := J.RawText;
    code := J.ExitCode;
    cancelled := J.Cancelled;
    if J.ErrorMsg <> '' then Lines.Add(J.ErrorMsg);
    FJob := nil;
    J.Free;
    SetBusy(False);
    btnCancel.Enabled := True;
    kind := FKind;
    Caption := 'TTCompressor';

    if cancelled then
    begin
      StatusBar1.SimpleText := Tr('Operazione annullata.');
      if kind in [jkAdd, jkCreate, jkDelete] then
        if FModel <> nil then ReloadArchive;
      UpdateStatus;
      Exit;
    end;

    // archivio protetto da password: chiedi e riprova
    if (code >= 2) and NeedsPassword(Lines) and
       (kind in [jkList, jkListNested, jkExtract, jkTest, jkAdd, jkDelete, jkOpenFile]) then
    begin
      pwd := PasswordBox(Tr('Password richiesta'), Tr('L''archivio è cifrato. Inserire la password:'));
      if pwd <> '' then
      begin
        FPassword := pwd;
        LaunchSpec;
        Exit;
      end;
      StatusBar1.SimpleText := Tr('Password non fornita.');
      UpdateStatus;
      Exit;
    end;

    case kind of
      jkList, jkListNested:
        HandleList(Lines, code, kind = jkListNested);
      jkExtract:
        begin
          if (code >= 2) and OnlyIgnoredLinks(Lines) then
          begin
            ShowMessage(Tr('Estrazione completata, ma alcuni collegamenti simbolici ') +
              Tr('sono stati ignorati da 7z perché puntano fuori dalla cartella di ') +
              Tr('destinazione (potenzialmente pericolosi).'));
            code := 1;
          end;
          if code >= 2 then ShowJobError(Tr('Estrazione non riuscita'), Lines)
          else if code = 1 then
            StatusBar1.SimpleText := Tr('Estrazione completata con avvisi.')
          else
            StatusBar1.SimpleText := Tr('Estrazione completata in ') + FExtractOpt.DestDir;
        end;
      jkOpenFile:
        begin
          if code >= 2 then ShowJobError(Tr('Impossibile estrarre il file'), Lines)
          else if FileExists(FOpenAfter) then OpenDocument(FOpenAfter);
        end;
      jkTest:
        begin
          okLine := False;
          for i := 0 to Lines.Count - 1 do
            if Pos('Everything is Ok', Lines[i]) > 0 then okLine := True;
          if (code = 0) and okLine then
          begin
            msg := Tr('Nessun errore: l''archivio è integro.');
            for i := 0 to Lines.Count - 1 do
              if (Pos('Files:', Lines[i]) = 1) or (Pos('Size:', Lines[i]) = 1) or
                 (Pos('Folders:', Lines[i]) = 1) or (Pos('Compressed:', Lines[i]) = 1) then
                msg := msg + LineEnding + Lines[i];
            if FRecKind <> rkNone then
            begin
              // controlla anche i dati di recupero
              FTestMsg := msg;
              StartRecCheck;
            end
            else
              MessageDlg(Tr('Verifica integrità'), msg, mtInformation, [mbOK], 0);
          end
          else
          begin
            ShowJobError(Tr('Verifica integrità: errori rilevati'), Lines);
            if FRecKind <> rkNone then
              if MessageDlg(Tr('L''archivio ha dati di recupero. Controllarli e tentare la riparazione?'),
                mtConfirmation, [mbYes, mbNo], 0) = mrYes then
              begin
                FTestMsg := '';
                StartRecCheck;
              end;
          end;
        end;
      jkRecCheck:
        begin
          if code = 0 then
          begin
            if FTestMsg <> '' then FTestMsg := FTestMsg + LineEnding + LineEnding;
            MessageDlg(Tr('Verifica integrità'), FTestMsg +
              Tr('Dati di recupero: archivio integro, nessun danno rilevato.'), mtInformation, [mbOK], 0);
          end
          else if code = 1 then
          begin
            if MessageDlg(Tr('Verifica integrità'), FTestMsg +
              Tr('Rilevati danni all''archivio, ma i dati di recupero bastano a ripararli.') +
              LineEnding + Tr('Riparare ora?'), mtWarning, [mbYes, mbNo], 0) = mrYes then
              StartRepair(FArcPath, FRecKind);
          end
          else
            ShowJobError(Tr('Verifica dati di recupero: danni non riparabili'), Lines);
        end;
      jkRepair:
        begin
          if code = 0 then
          begin
            msg := '';
            for i := Max(0, Lines.Count - 4) to Lines.Count - 1 do
              if Trim(Lines[i]) <> '' then msg := msg + Lines[i] + LineEnding;
            MessageDlg(Tr('Riparazione'), Tr('Riparazione completata.') + LineEnding + LineEnding + msg,
              mtInformation, [mbOK], 0);
            if (FModel <> nil) and SameFileName(FArcPath, FRepairPath) then
              ReloadArchive
            else
              OpenArchive(FRepairPath);
          end
          else
            ShowJobError(Tr('Riparazione non riuscita'), Lines);
        end;
      jkRecAdd:
        begin
          if code >= 2 then ShowJobError(Tr('Generazione dati di recupero non riuscita'), Lines);
          if FModel <> nil then ReloadArchive;
        end;
      jkCreate, jkAdd, jkDelete:
        begin
          if code >= 2 then
          begin
            ShowJobError(Tr('Operazione non riuscita'), Lines);
            if (kind = jkCreate) and FileExists(FCreateDest) and (FModel = nil) then
              OpenArchive(FCreateDest)
            else if FModel <> nil then
              ReloadArchive;
          end
          else if kind = jkCreate then
          begin
            FPassword := FCreatePwd;
            OpenArchive(FCreateDest);
            FPassword := FCreatePwd;
          end
          else
            ReloadArchive;
        end;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---------- archivio ---------- }

function TForm1.RequireArchive: Boolean;
begin
  Result := (FModel <> nil) and (FJob = nil);
  if (FModel = nil) and (FJob = nil) then
    MessageDlg(Tr('Aprire prima un archivio.'), mtInformation, [mbOK], 0);
end;

function TForm1.CanModify: Boolean;
begin
  Result := True;
  if FNested then
  begin
    MessageDlg(Tr('Gli archivi compressi tipo tar.gz / tar.bz2 / tar.xz non si possono ') +
      Tr('modificare direttamente: estrarre, modificare e creare un nuovo archivio.'),
      mtInformation, [mbOK], 0);
    Result := False;
  end;
end;

procedure TForm1.miOpenClick(Sender: TObject);
begin
  if FJob <> nil then Exit;
  if OpenArchiveDialog.Execute then OpenArchive(OpenArchiveDialog.FileName);
end;

procedure TForm1.miQuitClick(Sender: TObject);
begin
  Close;
end;

procedure TForm1.OpenArchive(const APath: string);
begin
  if FJob <> nil then Exit;
  FPassword := '';
  StartList(APath, False);
end;

procedure TForm1.ReloadArchive;
begin
  if FArcPath = '' then Exit;
  StartList(FArcPath, FNested);
end;

{ .deb / .udeb: trova il membro control.tar.* e il formato con cui e compresso. }
function TForm1.DebControl(const APath: string; out Member, Fmt: string): Boolean;
var
  ext, outp, ln, e: string;
  L: TStringList;
  i: Integer;
begin
  Result := False;
  Member := '';
  Fmt := '';
  ext := LowerCase(ExtractFileExt(APath));
  if (ext <> '.deb') and (ext <> '.udeb') then Exit;
  try
    if not RunCommand(Z, ['l', '-tAr', '-slt', '-ba', APath], outp) then Exit;
  except
    Exit;
  end;
  L := TStringList.Create;
  try
    L.Text := outp;
    for i := 0 to L.Count - 1 do
    begin
      ln := Trim(L[i]);
      if Pos('Path = control.tar', ln) <> 1 then Continue;
      Member := Copy(ln, 8, MaxInt);
      e := LowerCase(ExtractFileExt(Member));
      if e = '.zst' then Fmt := 'zstd'
      else if e = '.xz' then Fmt := 'xz'
      else if e = '.gz' then Fmt := 'gzip'
      else if e = '.bz2' then Fmt := 'bzip2'
      else if e = '.lzma' then Fmt := 'lzma'
      else if e = '.tar' then Fmt := ''
      else
      begin
        Member := '';
        Exit;
      end;
      Result := True;
      Exit;
    end;
  finally
    L.Free;
  end;
end;

{ Comando che scrive su stdout il tar dei metadati di un .deb. }
function TForm1.CtlPipe(const Arc, Member, Fmt: string): string;
begin
  Result := ShQuote(Z) + ' x -tAr -so -bso0 -bsp0 -bse2 -y ' + ShQuote(Arc) + ' ' +
    ShQuote(Member);
  if Fmt <> '' then
    Result := Result + ' | ' + ShQuote(Z) + ' x -so -si -t' + Fmt +
      ' -bso0 -bsp0 -bse2 -y';
end;

{ File di elenco per l'estrazione da un tar: i nomi nel modello non hanno il
  "./" iniziale che 7z invece trova nei tar, quindi si elencano entrambe le forme. }
function TForm1.TarListFile(Items: TStrings): string;
var
  L: TStringList;
  i: Integer;
begin
  Result := NewTempFile('tlist');
  L := TStringList.Create;
  try
    for i := 0 to Items.Count - 1 do
    begin
      L.Add(Items[i]);
      L.Add('./' + Items[i]);
    end;
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;

procedure TForm1.StartList(const APath: string; Nested: Boolean);
var
  P: TStringList;
  Cmd, SlcOpt: string;
begin
  FPendingPath := APath;
  FPendingNested := Nested;
  FPendDebCtl := '';
  FPendDebFmt := '';
  if Nested then DebControl(APath, FPendDebCtl, FPendDebFmt);
  if not Nested then
  begin
    P := TStringList.Create;
    try
      if FFastList then
        P.AddStrings(['l', '-slt', '-slc', '-ba', '-sccUTF-8', '-bso1', '-bse1', '-bsp1',
          '-y', '@PWD@', APath])
      else
        P.AddStrings(['l', '-slt', '-ba', '-sccUTF-8', '-bso1', '-bse1', '-bsp0',
          '-y', '@PWD@', APath]);
      StartJob(jkList, Tr('Lettura archivio'), P, '', FFastList);
    finally
      P.Free;
    end;
  end
  else
  begin
    if FFastList then
      Cmd := ShQuote(Z) + ' x -so -bsp2 -bso0 -bse2 -y -sccUTF-8 @PWD@ ' + ShQuote(APath) +
        ' | ' + ShQuote(Z) + ' l -slt -slc -ba -si -ttar -sccUTF-8 -bso1 -bse1 -bsp0 -y'
    else
      Cmd := ShQuote(Z) + ' x -so -bsp0 -bso0 -bse2 -y -sccUTF-8 @PWD@ ' + ShQuote(APath) +
        ' | ' + ShQuote(Z) + ' l -slt -ba -si -ttar -sccUTF-8 -bso1 -bse1 -bsp0 -y';
    SlcOpt := '';
    if FFastList then SlcOpt := '-slc ';
    if FPendDebCtl <> '' then
    begin
      // pacchetto .deb: i metadati (control.tar.*) compaiono come cartella DEBIAN
      Cmd := Cmd + '; r=$?; ' + CtlPipe(APath, FPendDebCtl, FPendDebFmt) + ' | ' + ShQuote(Z) +
        ' l -slt ' + SlcOpt +
        '-ba -si -ttar -sccUTF-8 -bso1 -bse1 -bsp0 -y 2>/dev/null' +
        ' | sed -e ''s|^Path = \./|Path = DEBIAN/|'' -e ''s|^Path = \.$|Path = DEBIAN|''' +
        '; exit $r';
    end;
    StartShellJob(jkListNested, Tr('Lettura archivio'), Cmd, '', FFastList);
  end;
end;

procedure TForm1.HandleList(Lines: TStrings; ExitCode: Integer; Nested: Boolean);
var
  M: TArcModel;
  n, pc: Integer;
  E: TArcEntry;
  k: TRecKind;
begin
  M := TArcModel.Create;
  // in un tar compresso (tar.gz ...) la dimensione compressa per singolo file non esiste
  if FListRaw <> '' then
  begin
    n := M.ParseSltText(FListRaw, Nested);
    FListRaw := '';
  end
  else
    n := M.ParseSlt(Lines, Nested);
  // .deb, .tar.zst ...: 7z apre il contenitore ma l'unico elemento (il tar
  // compresso) non ha un nome: si elenca il tar estraendolo con una pipe
  if (ExitCode < 2) and (n = 0) and (not Nested) then
  begin
    M.Free;
    StartList(FPendingPath, True);
    Exit;
  end;
  if (ExitCode >= 2) and (n = 0) then
  begin
    M.Free;
    ShowJobError(Tr('Impossibile aprire l''archivio'), Lines);
    UpdateStatus;
    k := DetectRec(FPendingPath, pc);
    if k <> rkNone then
      if MessageDlg(Tr('L''archivio contiene dati di recupero. Provare a ripararlo?'),
        mtConfirmation, [mbYes, mbNo], 0) = mrYes then
        StartRepair(FPendingPath, k);
    Exit;
  end;
  // file singolo compresso che contiene un tar (tar.gz, tgz, tar.xz ...)
  if (not Nested) and (n = 1) then
  begin
    E := TArcEntry(M.Entries[0]);
    if (not E.IsDir) and (LowerCase(ExtractFileExt(E.Path)) = '.tar') and
       (LowerCase(ExtractFileExt(FPendingPath)) <> '.tar') then
    begin
      M.Free;
      StartList(FPendingPath, True);
      Exit;
    end;
  end;
  SetModel(M, Nested);
end;

procedure TForm1.SetModel(M: TArcModel; Nested: Boolean);
var
  Old: TArcModel;
  N: PVirtualNode;
  keepPath: string;
  F: TFolder;
begin
  keepPath := '';
  if (FCurFolder <> nil) and (FPendingPath = FArcPath) then keepPath := FCurFolder.Path;
  if FPendingPath <> FArcPath then
  begin
    FHist.Clear;
    FHistPos := -1;
  end;
  TreeFiles.Clear;
  TreeFolders.Clear;
  FItems.Clear;
  FCurFolder := nil;
  FFindMode := False;
  Old := FModel;
  FModel := M;
  Old.Free;
  FArcPath := FPendingPath;
  FNested := Nested;
  FDebCtl := FPendDebCtl;
  FDebFmt := FPendDebFmt;
  FRecKind := DetectRec(FArcPath, FRecPct);
  SortFolderTree(FModel.Root);
  TreeFolders.RootNodeCount := 1;
  N := TreeFolders.GetFirst;
  if N <> nil then
  begin
    TreeFolders.Expanded[N] := True;
    F := FModel.FindFolder(keepPath, False);
    if F = nil then F := FModel.Root;
    SelectFolder(F);
  end;
  UpdateButtons;
  UpdateStatus;
end;

{ ---------- dati di recupero ---------- }

{ Percentuale di ridondanza dei file PAR2: blocchi di recupero (somma dei +N nei
  nomi dei file .vol) / blocchi sorgente (dimensione file / dimensione slice). }
function Par2Percent(const Arc: string): Integer;
var
  L: TStringList;
  i, p, q, n: Integer;
  rec, src, slice: Int64;
  fs: TFileStream;
  buf: array[0..8191] of Byte;
  got, k: Integer;
  nm: string;
begin
  Result := 5;
  rec := 0;
  L := FindAllFiles(ExtractFilePath(Arc), ExtractFileName(Arc) + '.vol*.par2', False);
  try
    for i := 0 to L.Count - 1 do
    begin
      nm := ExtractFileName(L[i]);
      p := LastDelimiter('+', nm);
      q := Pos('.par2', Copy(nm, p, MaxInt));
      if (p > 0) and (q > 1) then
      begin
        n := StrToIntDef(Copy(nm, p + 1, q - 2), 0);
        Inc(rec, n);
      end;
    end;
  finally
    L.Free;
  end;
  slice := 0;
  try
    fs := TFileStream.Create(Arc + '.par2', fmOpenRead or fmShareDenyNone);
    try
      got := fs.Read(buf, SizeOf(buf));
      // pacchetto "Main": tipo a offset 48 dell'intestazione, slice size a offset 64
      for k := 0 to got - 80 do
        if (buf[k] = Ord('P')) and (buf[k + 1] = Ord('A')) and (buf[k + 2] = Ord('R')) and
           (buf[k + 3] = Ord(' ')) and (buf[k + 4] = Ord('2')) and (buf[k + 5] = Ord('.')) and
           (buf[k + 6] = Ord('0')) and (buf[k + 8] = Ord('M')) and (buf[k + 9] = Ord('a')) and
           (buf[k + 10] = Ord('i')) and (buf[k + 11] = Ord('n')) and (k >= 48) then
        begin
          slice := PInt64(@buf[k - 48 + 64])^;
          Break;
        end;
    finally
      fs.Free;
    end;
  except
    slice := 0;
  end;
  if (slice > 0) and (rec > 0) then
  begin
    src := (FileSize(Arc) + slice - 1) div slice;
    if src > 0 then Result := Max(1, Round(100 * rec / src));
  end;
end;


function TForm1.Par2Exe: string;
begin
  Result := FindDefaultExecutablePath('par2');
end;

function TForm1.DetectRec(const APath: string; out Pct: Integer): TRecKind;
var
  Info: TRSInfo;
begin
  Pct := 0;
  Result := rkNone;
  if RSDetect(APath, Info) then
  begin
    Pct := Info.Pct;
    Exit(rkTail);
  end;
  if FileExists(APath + '.par2') then
  begin
    Result := rkPar2;
    Pct := Par2Percent(APath);
  end;
end;

function TForm1.QCmd(const Exe: string; P: TStrings): string;
var
  i: Integer;
begin
  Result := ShQuote(Exe);
  for i := 0 to P.Count - 1 do
    if P[i] = '@PWD@' then Result := Result + ' @PWD@'
    else Result := Result + ' ' + ShQuote(P[i]);
end;

function TForm1.RecCreateCmd(const Arc: string; Kind: TRecKind; Pct: Integer): string;
begin
  if Kind = rkTail then
    Result := ShQuote(Application.ExeName) + ' --rs-create ' + ShQuote(Arc) + ' ' + IntToStr(Pct)
  else
    Result := ShQuote(Par2Exe) + ' create -r' + IntToStr(Pct) + ' ' +
      ShQuote(Arc + '.par2') + ' ' + ShQuote(Arc);
end;

{ Avvolge un comando che modifica l'archivio: i dati di recupero vengono
  rimossi prima e rigenerati dopo. }
function TForm1.RecWrapModify(const Core: string): string;
begin
  case FRecKind of
    rkTail:
      Result := ShQuote(Application.ExeName) + ' --rs-strip ' + ShQuote(FArcPath) +
        ' && ' + Core + ' && ' + RecCreateCmd(FArcPath, rkTail, FRecPct);
    rkPar2:
      Result := Core + ' && rm -f -- ' + ShQuote(FArcPath + '.par2') + ' ' +
        ShQuote(FArcPath + '.vol') + '*' + ShQuote('.par2') + ' && ' +
        RecCreateCmd(FArcPath, rkPar2, FRecPct);
  else
    Result := Core;
  end;
end;

procedure TForm1.StartRecCheck;
var
  P: TStringList;
begin
  P := TStringList.Create;
  try
    if FRecKind = rkTail then
    begin
      P.AddStrings(['--rs-verify', FArcPath]);
      StartExeJob(jkRecCheck, Tr('Verifica dati di recupero'), Application.ExeName, P, '', True);
    end
    else
    begin
      if Par2Exe = '' then
      begin
        MessageDlg(Tr('Il programma "par2" non è installato.') + LineEnding +
          Tr('Installarlo con: sudo apt install par2'), mtWarning, [mbOK], 0);
        Exit;
      end;
      P.AddStrings(['verify', FArcPath + '.par2']);
      StartExeJob(jkRecCheck, Tr('Verifica dati di recupero'), Par2Exe, P, '', True);
    end;
  finally
    P.Free;
  end;
end;

procedure TForm1.StartRepair(const APath: string; Kind: TRecKind);
var
  P: TStringList;
begin
  FRepairPath := APath;
  P := TStringList.Create;
  try
    if Kind = rkPar2 then
    begin
      if Par2Exe = '' then
      begin
        MessageDlg(Tr('Il programma "par2" non è installato.') + LineEnding +
          Tr('Installarlo con: sudo apt install par2'), mtWarning, [mbOK], 0);
        Exit;
      end;
      P.AddStrings(['repair', APath + '.par2']);
      StartExeJob(jkRepair, Tr('Riparazione'), Par2Exe, P, '', True);
    end
    else
    begin
      P.AddStrings(['--rs-repair', APath]);
      StartExeJob(jkRepair, Tr('Riparazione'), Application.ExeName, P, '', True);
    end;
  finally
    P.Free;
  end;
end;

procedure TForm1.miRepairClick(Sender: TObject);
var
  path: string;
  k: TRecKind;
  pc: Integer;
begin
  if FJob <> nil then Exit;
  if FModel <> nil then
    path := FArcPath
  else
  begin
    OpenArchiveDialog.Title := Tr('Archivio da riparare');
    if not OpenArchiveDialog.Execute then Exit;
    path := OpenArchiveDialog.FileName;
    OpenArchiveDialog.Title := Tr('Apri archivio');
  end;
  k := DetectRec(path, pc);
  if k = rkNone then
  begin
    if MessageDlg(Tr('Riparazione'), Tr('Non ho trovato dati di recupero riconoscibili per questo archivio ') +
      Tr('(né file .par2, né blocco in coda).') + LineEnding +
      Tr('Se l''archivio contiene dati in coda con il footer danneggiato posso tentare una ') +
      Tr('ricerca approfondita (può richiedere tempo). Procedere?'),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    k := rkTail;
  end;
  StartRepair(path, k);
end;

procedure TForm1.miAddRecClick(Sender: TObject);
var
  mode, pct: Integer;
  Cmd: string;
begin
  if not RequireArchive then Exit;
  mode := 1;
  pct := 10;
  if not ExecRecovery(mode, pct, ArchiveFormatFromName(FArcPath) = '7z',
    FRecKind <> rkNone) then Exit;
  if (mode = 2) and (Par2Exe = '') then
  begin
    MessageDlg(Tr('Il programma "par2" non è installato.') + LineEnding +
      Tr('Installarlo con: sudo apt install par2') + LineEnding +
      Tr('oppure scegliere i dati di recupero "in coda all''archivio".'), mtWarning, [mbOK], 0);
    Exit;
  end;
  Cmd := '';
  case FRecKind of
    rkTail:
      Cmd := ShQuote(Application.ExeName) + ' --rs-strip ' + ShQuote(FArcPath) + ' && ';
    rkPar2:
      Cmd := 'rm -f -- ' + ShQuote(FArcPath + '.par2') + ' ' +
        ShQuote(FArcPath + '.vol') + '*' + ShQuote('.par2') + ' && ';
  end;
  Cmd := Cmd + RecCreateCmd(FArcPath, TRecKind(mode), pct);
  StartShellJob(jkRecAdd, Tr('Generazione dati di recupero'), Cmd, '', True);
end;

procedure TForm1.miHelpRecoveryClick(Sender: TObject);
begin
  ShowRecoveryHelp;
end;

procedure TForm1.miAboutClick(Sender: TObject);
begin
  ShowAboutDialog(Self);
end;

{ ---------- nuovo archivio ---------- }

function TForm1.SrcArg(const Dir, Full: string): string;
begin
  if SameFileName(ExtractFilePath(ExcludeTrailingPathDelimiter(Full)), Dir) then
    Result := ExtractFileName(ExcludeTrailingPathDelimiter(Full))
  else
    Result := ExcludeTrailingPathDelimiter(Full);
  if (Result <> '') and (Result[1] in ['-', '@']) then Result := './' + Result;
end;

function TForm1.SrcListFile(const Dir: string; Names: TStrings): string;
var
  L: TStringList;
  i: Integer;
begin
  // i nomi vanno in un file @elenco: la riga di comando ha un limite di
  // dimensione (ARG_MAX) che con molti file verrebbe superato
  Result := NewTempFile('src');
  L := TStringList.Create;
  try
    for i := 0 to Names.Count - 1 do
      L.Add(SrcArg(Dir, Names[i]));
    L.SaveToFile(Result);
  finally
    L.Free;
  end;
end;

procedure TForm1.DoNewArchive(Initial: TStrings);
var
  Opt: TNewArchiveOptions;
  P: TStringList;
  Dir, Cmd, comp, inner, fmtType, base, lvl: string;
  i: Integer;
begin
  if FJob <> nil then Exit;
  FillChar(Opt, SizeOf(Opt), 0);
  Opt.Sources := TStringList.Create;
  try
    if Initial <> nil then Opt.Sources.Assign(Initial);
    Opt.Fmt := '7z';
    if Opt.Sources.Count > 0 then
      Opt.Path := ExtractFilePath(ExcludeTrailingPathDelimiter(Opt.Sources[0])) +
        ExtractFileName(ExcludeTrailingPathDelimiter(Opt.Sources[0])) + '.7z'
    else
      Opt.Path := IncludeTrailingPathDelimiter(GetUserDir) + Tr('archivio') + '.7z';
    if not ExecNewArchive(Opt) then Exit;

    if FileExists(Opt.Path) then
    begin
      if MessageDlg(Tr('Il file esiste già. Sovrascriverlo?'), mtConfirmation,
        [mbYes, mbNo], 0) <> mrYes then Exit;
      DeleteFile(Opt.Path);
    end;
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Opt.Sources[0]));
    FCreateDest := Opt.Path;
    FCreatePwd := Opt.Password;
    FCreateNested := Pos('tar.', Opt.Fmt) = 1;
    FCreateRec := Opt.RecMode;
    FPassword := Opt.Password;
    lvl := IntToStr(Opt.Level);
    if FCreateNested then
    begin
      if Opt.Fmt = 'tar.gz' then comp := 'gzip'
      else if Opt.Fmt = 'tar.bz2' then comp := 'bzip2'
      else comp := 'xz';
      base := StripArchiveExt(ExtractFileName(Opt.Path));
      inner := base + '.tar';
      Cmd := ShQuote(Z) + ' a -ttar -so -bsp2 -bso0 -bse2 -y -sccUTF-8 ' +
        ShQuote(inner);
      Cmd := Cmd + ' -scsUTF-8 ' + ShQuote('@' + SrcListFile(Dir, Opt.Sources));
      Cmd := Cmd + ' | ' + ShQuote(Z) + ' a -t' + comp + ' ' + ShQuote('-si' + inner) +
        ' -mx=' + lvl + ' -bso0 -bsp0 -bse2 -y ' + ShQuote(Opt.Path);
      if Opt.RecMode > 0 then
        Cmd := Cmd + ' && ' + RecCreateCmd(Opt.Path, TRecKind(Opt.RecMode), Opt.RecPct);
      StartShellJob(jkCreate, Tr('Compressione'), Cmd, Dir, True);
    end
    else
    begin
      if Opt.Fmt = 'gz' then fmtType := 'gzip'
      else if Opt.Fmt = 'bz2' then fmtType := 'bzip2'
      else fmtType := Opt.Fmt;
      P := TStringList.Create;
      try
        P.AddStrings(['a', '-t' + fmtType, '-bsp1', '-bso1', '-bse1', '-y', '-sccUTF-8']);
        if Opt.Fmt <> 'tar' then P.Add('-mx=' + lvl);
        if (Opt.Fmt = '7z') and not Opt.Solid then P.Add('-ms=off');
        if Opt.Password <> '' then
        begin
          P.Add('@PWD@');
          if Opt.EncryptNames then P.Add('-mhe=on');
        end;
        P.Add(Opt.Path);
        P.Add('-scsUTF-8');
        P.Add('@' + SrcListFile(Dir, Opt.Sources));
        if Opt.RecMode > 0 then
          StartShellJob(jkCreate, Tr('Compressione'),
            QCmd(Z, P) + ' && ' + RecCreateCmd(Opt.Path, TRecKind(Opt.RecMode), Opt.RecPct),
            Dir, True)
        else
          StartJob(jkCreate, Tr('Compressione'), P, Dir, True);
      finally
        P.Free;
      end;
    end;
  finally
    Opt.Sources.Free;
  end;
end;

procedure TForm1.actNewExecute(Sender: TObject);
begin
  DoNewArchive(nil);
end;

{ ---------- aggiungi ---------- }

procedure TForm1.actAddExecute(Sender: TObject);
begin
  if FJob <> nil then Exit;
  if FModel = nil then
  begin
    DoNewArchive(nil);
    Exit;
  end;
  if not CanModify then Exit;
  PopupAdd.PopUp;
end;

procedure TForm1.pmAddFilesClick(Sender: TObject);
begin
  if AddFilesDialog.Execute then DoAdd(AddFilesDialog.Files);
end;

procedure TForm1.pmAddDirClick(Sender: TObject);
var
  L: TStringList;
begin
  if AddDirDialog.Execute then
  begin
    L := TStringList.Create;
    try
      L.Add(ExcludeTrailingPathDelimiter(AddDirDialog.FileName));
      DoAdd(L);
    finally
      L.Free;
    end;
  end;
end;

procedure TForm1.DoAdd(Names: TStrings);
var
  P, Staged: TStringList;
  Dir, Stage: string;
  i, p1: Integer;
begin
  if (FModel = nil) or (FJob <> nil) or (Names.Count = 0) then Exit;
  if not CanModify then Exit;
  Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Names[0]));
  Staged := nil;
  // dentro una cartella dell'archivio: gli elementi vanno aggiunti li, non
  // nella radice. 7z non ha un'opzione per la cartella di destinazione, quindi
  // si prepara una struttura temporanea con collegamenti agli originali
  if (FCurFolder <> nil) and (FCurFolder.Path <> '') then
  begin
    Stage := TempSubDir('add');
    ForceDirectories(Stage + PathDelim + FCurFolder.Path);
    Staged := TStringList.Create;
    for i := 0 to Names.Count - 1 do
      FpSymlink(PChar(ExcludeTrailingPathDelimiter(Names[i])),
        PChar(Stage + PathDelim + FCurFolder.Path + PathDelim +
          ExtractFileName(ExcludeTrailingPathDelimiter(Names[i]))));
    p1 := Pos('/', FCurFolder.Path);
    if p1 > 0 then Staged.Add(Copy(FCurFolder.Path, 1, p1 - 1))
    else Staged.Add(FCurFolder.Path);
    Dir := IncludeTrailingPathDelimiter(Stage);
    Names := Staged;
  end;
  P := TStringList.Create;
  try
    P.AddStrings(['a', '-bsp1', '-bso1', '-bse1', '-y', '-sccUTF-8', '@PWD@', FArcPath]);
    P.Add('-scsUTF-8');
    P.Add('@' + SrcListFile(Dir, Names));
    if FRecKind = rkNone then
      StartJob(jkAdd, Tr('Aggiunta all''archivio'), P, Dir, True)
    else if (FRecKind = rkPar2) and (Par2Exe = '') then
      MessageDlg(Tr('Il programma "par2" non è installato: non posso aggiornare i dati di recupero.') +
        LineEnding + Tr('Installarlo con: sudo apt install par2'), mtWarning, [mbOK], 0)
    else
      StartShellJob(jkAdd, Tr('Aggiunta all''archivio'), RecWrapModify(QCmd(Z, P)), Dir, True);
  finally
    P.Free;
    Staged.Free;
  end;
end;

{ ---------- estrai ---------- }

function TForm1.FlatCmd(const Cmd, Dest, Tmp: string; Sel: TStrings): string;
var
  d, mv, one: string;
  i: Integer;
begin
  // estrae in una cartella nascosta dentro la destinazione e sposta poi gli
  // elementi scelti direttamente nella destinazione (senza i percorsi
  // intermedi dell'archivio); se il nome esiste gia ne sceglie uno libero
  d := ShQuote(ExcludeTrailingPathDelimiter(Dest));
  one := 'b=${f##*/}; t=' + d + '/"$b"; i=2; ' +
    'while [ -e "$t" ]; do t=' + d + '/"$b ($i)"; i=$((i+1)); done; mv "$f" "$t"; ';
  mv := '';
  if (Sel <> nil) and (Sel.Count > 0) then
    for i := 0 to Sel.Count - 1 do
      mv := mv + 'f=' + ShQuote(ExcludeTrailingPathDelimiter(Tmp)) + '/' + ShQuote(Sel[i]) + '; ' + one
  else
    mv := 'for f in ' + ShQuote(ExcludeTrailingPathDelimiter(Tmp)) + '/* ' +
      ShQuote(ExcludeTrailingPathDelimiter(Tmp)) + '/.[!.]*; do [ -e "$f" ] || continue; ' +
      one + 'done; ';
  // si sposta quanto estratto anche se 7z termina con un avviso o un errore parziale
  Result := Cmd + '; r=$?; { ' + mv + '} 2>/dev/null; rm -rf ' + ShQuote(Tmp) + '; exit $r';
end;

procedure TForm1.DoExtractTo(const Dest: string; Sel: TStrings; Keep: Boolean;
  Overwrite: Integer; AKind: TJobKind; Flat: Boolean);
var
  P: TStringList;
  ovr, cmdLetter, lst, Cmd, tmpDir, target, cmdD, cmdC: string;
  L, dataSel, ctlSel: TStringList;
  needData, needCtl, dataAll, ctlAll: Boolean;
  i: Integer;
begin
  if FModel = nil then Exit;
  case Overwrite of
    1: ovr := '-aoa';
    2: ovr := '-aos';
  else
    ovr := '-aou';
  end;
  if Keep then cmdLetter := 'x' else cmdLetter := 'e';
  lst := '';
  if (Sel <> nil) and (Sel.Count > 0) then
  begin
    lst := NewTempFile('list');
    L := TStringList.Create;
    try
      L.Assign(Sel);
      L.SaveToFile(lst);
    finally
      L.Free;
    end;
  end;
  ForceDirectories(Dest);
  target := Dest;
  tmpDir := '';
  if Flat then
  begin
    Inc(FTempCount);
    tmpDir := IncludeTrailingPathDelimiter(Dest) + '.ttcompressor-' +
      IntToStr(GetProcessID) + '-' + IntToStr(FTempCount);
    target := tmpDir;
    Keep := True;
  end;
  if not FNested then
  begin
    P := TStringList.Create;
    try
      P.AddStrings([cmdLetter, '-bsp1', '-bso1', '-bse1', '-y', '-sccUTF-8',
        '-scsUTF-8', ovr, '-o' + target, '@PWD@', FArcPath]);
      if (AKind = jkExtract) and FExtractOpt.AllowLinks then P.Add('-snld');
      if lst <> '' then P.Add('@' + lst);
      if Flat then
        StartShellJob(AKind, Tr('Estrazione'), FlatCmd(QCmd(Z, P), Dest, tmpDir, Sel), '', True)
      else
        StartJob(AKind, Tr('Estrazione'), P, '', True);
    finally
      P.Free;
    end;
  end
  else
  begin
    // archivio tar compresso (tar.gz ...) o .deb: si estrae con una pipe.
    // Per un .deb la cartella DEBIAN viene dal membro control.tar.*
    dataSel := TStringList.Create;
    ctlSel := TStringList.Create;
    try
      needData := True;
      needCtl := FDebCtl <> '';
      dataAll := True;
      ctlAll := True;
      if (Sel <> nil) and (Sel.Count > 0) then
      begin
        dataAll := False;
        ctlAll := False;
        for i := 0 to Sel.Count - 1 do
          if (FDebCtl <> '') and ((Sel[i] = 'DEBIAN') or (Pos('DEBIAN/', Sel[i]) = 1)) then
          begin
            if Sel[i] = 'DEBIAN' then ctlAll := True
            else ctlSel.Add(Copy(Sel[i], 8, MaxInt));
          end
          else
            dataSel.Add(Sel[i]);
        needData := dataSel.Count > 0;
        needCtl := needCtl and (ctlAll or (ctlSel.Count > 0));
      end;
      cmdD := '';
      cmdC := '';
      if needData then
      begin
        cmdD := ShQuote(Z) + ' x -so -bsp2 -bso0 -bse2 -y -sccUTF-8 @PWD@ ' + ShQuote(FArcPath) +
          ' | ' + ShQuote(Z) + ' ' + cmdLetter + ' -si -ttar -bso0 -bsp0 -bse2 -y ' +
          '-sccUTF-8 -scsUTF-8 ' + ovr + ' ' + ShQuote('-o' + target);
        if not dataAll then cmdD := cmdD + ' ' + ShQuote('@' + TarListFile(dataSel));
      end;
      if needCtl then
      begin
        cmdC := CtlPipe(FArcPath, FDebCtl, FDebFmt) + ' | ' + ShQuote(Z) + ' ' + cmdLetter +
          ' -si -ttar -bso0 -bsp0 -bse2 -y -sccUTF-8 -scsUTF-8 ' + ovr + ' ' +
          ShQuote('-o' + IncludeTrailingPathDelimiter(target) + 'DEBIAN');
        if not ctlAll then cmdC := cmdC + ' ' + ShQuote('@' + TarListFile(ctlSel));
      end;
      if (cmdD <> '') and (cmdC <> '') then
        Cmd := '( ' + cmdD + '; r=$?; ' + cmdC + '; s=$?; [ $r -eq 0 ] && r=$s; exit $r )'
      else if cmdD <> '' then
        Cmd := cmdD
      else
        Cmd := cmdC;
    finally
      dataSel.Free;
      ctlSel.Free;
    end;
    if Flat then Cmd := FlatCmd(Cmd, Dest, tmpDir, Sel);
    StartShellJob(AKind, Tr('Estrazione'), Cmd, '', True);
  end;
end;

procedure TForm1.actExtractExecute(Sender: TObject);
var
  Sel: TStringList;
begin
  if not RequireArchive then Exit;
  Sel := TStringList.Create;
  try
    CollectSelected(Sel);
    if FExtractOpt.DestDir = '' then
      FExtractOpt.DestDir := ExtractFilePath(FArcPath) + StripArchiveExt(ExtractFileName(FArcPath));
    if not ExecExtract(FExtractOpt, Sel.Count) then Exit;
    if not FExtractOpt.OnlySelected then Sel.Clear;
    DoExtractTo(FExtractOpt.DestDir, Sel, FExtractOpt.KeepPaths,
      FExtractOpt.Overwrite, jkExtract);
  finally
    Sel.Free;
  end;
end;

{ ---------- verifica ---------- }

procedure TForm1.actTestExecute(Sender: TObject);
var
  P: TStringList;
begin
  if not RequireArchive then Exit;
  P := TStringList.Create;
  try
    P.AddStrings(['t', '-bsp1', '-bso1', '-bse1', '-y', '-sccUTF-8', '@PWD@', FArcPath]);
    StartJob(jkTest, Tr('Verifica integrità'), P, '', True);
  finally
    P.Free;
  end;
end;

{ ---------- cancella ---------- }

procedure TForm1.actDeleteExecute(Sender: TObject);
var
  Sel: TStringList;
  P: TStringList;
  lst: string;
  i: Integer;
begin
  if not RequireArchive then Exit;
  if not CanModify then Exit;
  Sel := TStringList.Create;
  try
    CollectSelected(Sel);
    if Sel.Count = 0 then
    begin
      MessageDlg(Tr('Selezionare i file o le cartelle da cancellare.'), mtInformation, [mbOK], 0);
      Exit;
    end;
    for i := 0 to Sel.Count - 1 do
      if (Pos('*', Sel[i]) > 0) or (Pos('?', Sel[i]) > 0) then
      begin
        MessageDlg(Tr('Le voci con i caratteri * o ? nel nome non possono essere cancellate ') +
          Tr('in modo sicuro da questa interfaccia.'), mtWarning, [mbOK], 0);
        Exit;
      end;
    if MessageDlg(Tr('Cancellare ') + IntToStr(Sel.Count) +
      Tr(' elementi dall''archivio? L''operazione non è reversibile.'),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    lst := NewTempFile('del');
    Sel.SaveToFile(lst);
    P := TStringList.Create;
    try
      P.AddStrings(['d', '-bsp1', '-bso1', '-bse1', '-y', '-sccUTF-8', '-scsUTF-8',
        '@PWD@', FArcPath, '@' + lst]);
      if FRecKind = rkNone then
        StartJob(jkDelete, Tr('Cancellazione'), P, '', True)
      else if (FRecKind = rkPar2) and (Par2Exe = '') then
        MessageDlg(Tr('Il programma "par2" non è installato: non posso aggiornare i dati di recupero.') +
          LineEnding + Tr('Installarlo con: sudo apt install par2'), mtWarning, [mbOK], 0)
      else
        StartShellJob(jkDelete, Tr('Cancellazione'), RecWrapModify(QCmd(Z, P)), '', True);
    finally
      P.Free;
    end;
  finally
    Sel.Free;
  end;
end;

{ ---------- trova ---------- }

procedure TForm1.actFindExecute(Sender: TObject);
var
  s: string;
begin
  if not RequireArchive then Exit;
  s := FFindText;
  if not InputQuery(Tr('Trova file'), Tr('Nome (o parte del nome; ammessi * e ?). Vuoto = annulla la ricerca:'), s) then
    Exit;
  FFindText := Trim(s);
  if FFindText = '' then
  begin
    FFindMode := False;
    if FCurFolder <> nil then ShowFolder(FCurFolder);
  end
  else
  begin
    FFindMode := True;
    BuildItems;
  end;
end;

end.
