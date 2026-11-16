unit szdlg;

{ Dialoghi costruiti in codice: nuovo archivio ed estrazione. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Dialogs, Graphics, ExtCtrls, FileUtil, szlang;

type
  TNewArchiveOptions = record
    Path: string;          // percorso completo dell'archivio
    Fmt: string;           // chiave del formato: 7z, zip, tar, tar.gz, ...
    Level: Integer;        // 0..9
    Password: string;
    EncryptNames: Boolean;
    Solid: Boolean;
    RecMode: Integer;      // 0 nessuno, 1 in coda all'archivio, 2 file PAR2
    RecPct: Integer;       // percentuale di ridondanza
    Sources: TStringList;  // appartiene al chiamante
  end;

  TExtractOptions = record
    DestDir: string;
    OnlySelected: Boolean;
    KeepPaths: Boolean;
    Overwrite: Integer;    // 0 = rinomina, 1 = sovrascrivi, 2 = salta
    AllowLinks: Boolean;   // -snld: collegamenti simbolici fuori dalla cartella
  end;

const
  RecPercents: array[0..5] of Integer = (3, 5, 10, 15, 20, 30);
  FormatKeys: array[0..9] of string =
    ('7z', 'zip', 'tar', 'tar.gz', 'tar.bz2', 'tar.xz', 'wim', 'gz', 'bz2', 'xz');

function ArchiveFormatFromName(const FileName: string): string;
function StripArchiveExt(const FileName: string): string;
function ExecNewArchive(var Opt: TNewArchiveOptions): Boolean;
procedure ShowRecoveryHelp;
function ExecRecovery(var Mode, Pct: Integer; AllowTail, Replacing: Boolean): Boolean;
function ExecExtract(var Opt: TExtractOptions; SelCount: Integer): Boolean;

implementation

function ArchiveFormatFromName(const FileName: string): string;
var
  l: string;
  i: Integer;
begin
  l := LowerCase(FileName);
  Result := '';
  if (Pos('.tgz', l) = Length(l) - 3) and (Length(l) > 4) then Exit('tar.gz');
  if (Pos('.tbz2', l) = Length(l) - 4) and (Length(l) > 5) then Exit('tar.bz2');
  if (Pos('.txz', l) = Length(l) - 3) and (Length(l) > 4) then Exit('tar.xz');
  // dal piu lungo al piu corto
  for i := High(FormatKeys) downto 0 do
    if (Length(l) > Length(FormatKeys[i]) + 1) and
       (Copy(l, Length(l) - Length(FormatKeys[i]), MaxInt) = '.' + FormatKeys[i]) then
      if (Result = '') or (Length(FormatKeys[i]) > Length(Result)) then
        Result := FormatKeys[i];
end;

function StripArchiveExt(const FileName: string): string;
var
  f: string;
begin
  Result := FileName;
  f := ArchiveFormatFromName(FileName);
  if (f <> '') and (LowerCase(Copy(FileName, Length(FileName) - Length(f), MaxInt)) = '.' + f) then
    Result := Copy(FileName, 1, Length(FileName) - Length(f) - 1);
end;

type
  { Gestore degli eventi del dialogo "nuovo archivio" }
  TNewDlgHelper = class
    Form: TForm;
    EdPath: TEdit;
    CbFmt: TComboBox;
    EdPwd: TEdit;
    ChkNames: TCheckBox;
    ChkSolid: TCheckBox;
    ChkRec: TCheckBox;
    CbRecMode: TComboBox;
    CbRecPct: TComboBox;
    LbSrc: TListBox;
    procedure BrowseClick(Sender: TObject);
    procedure FmtChange(Sender: TObject);
    procedure AddFilesClick(Sender: TObject);
    procedure AddDirClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure RecToggle(Sender: TObject);
    procedure RecModeChange(Sender: TObject);
    procedure HelpClick(Sender: TObject);
  end;

procedure TNewDlgHelper.FmtChange(Sender: TObject);
var
  key: string;
begin
  key := FormatKeys[CbFmt.ItemIndex];
  if EdPath.Text <> '' then
    EdPath.Text := StripArchiveExt(EdPath.Text) + '.' + key;
  EdPwd.Enabled := (key = '7z') or (key = 'zip');
  ChkNames.Enabled := key = '7z';
  ChkSolid.Enabled := key = '7z';
  if (key <> '7z') and (CbRecMode.ItemIndex = 0) then
    CbRecMode.ItemIndex := 1;   // i dati in coda sono supportati solo per 7z
end;

procedure TNewDlgHelper.RecToggle(Sender: TObject);
begin
  CbRecMode.Enabled := ChkRec.Checked;
  CbRecPct.Enabled := ChkRec.Checked;
end;

procedure TNewDlgHelper.RecModeChange(Sender: TObject);
begin
  if (CbRecMode.ItemIndex = 0) and (FormatKeys[CbFmt.ItemIndex] <> '7z') then
  begin
    MessageDlg(Tr('I dati di recupero in coda sono disponibili solo per il formato 7z. ') +
      Tr('Per questo formato usare i file PAR2.'), mtInformation, [mbOK], 0);
    CbRecMode.ItemIndex := 1;
  end;
end;

procedure TNewDlgHelper.HelpClick(Sender: TObject);
begin
  ShowRecoveryHelp;
end;

procedure TNewDlgHelper.BrowseClick(Sender: TObject);
var
  D: TSaveDialog;
  i: Integer;
begin
  D := TSaveDialog.Create(Form);
  try
    D.Title := Tr('Nome del nuovo archivio');
    D.Options := D.Options + [ofOverwritePrompt];
    D.Filter := '7z (*.7z)|*.7z|zip (*.zip)|*.zip|tar (*.tar)|*.tar|' +
      'tar.gz (*.tar.gz)|*.tar.gz|tar.bz2 (*.tar.bz2)|*.tar.bz2|' +
      'tar.xz (*.tar.xz)|*.tar.xz|wim (*.wim)|*.wim|gz (*.gz)|*.gz|' +
      'bz2 (*.bz2)|*.bz2|xz (*.xz)|*.xz';
    D.FilterIndex := CbFmt.ItemIndex + 1;
    if EdPath.Text <> '' then
    begin
      D.InitialDir := ExtractFilePath(EdPath.Text);
      D.FileName := ExtractFileName(EdPath.Text);
    end;
    if D.Execute then
    begin
      i := D.FilterIndex - 1;
      EdPath.Text := D.FileName;
      if ArchiveFormatFromName(D.FileName) <> '' then
      begin
        for i := 0 to High(FormatKeys) do
          if FormatKeys[i] = ArchiveFormatFromName(D.FileName) then
            CbFmt.ItemIndex := i;
      end
      else
      begin
        CbFmt.ItemIndex := i;
        EdPath.Text := D.FileName + '.' + FormatKeys[i];
      end;
      FmtChange(nil);
    end;
  finally
    D.Free;
  end;
end;

procedure TNewDlgHelper.AddFilesClick(Sender: TObject);
var
  D: TOpenDialog;
  i: Integer;
begin
  D := TOpenDialog.Create(Form);
  try
    D.Title := Tr('Seleziona i file da aggiungere');
    D.Options := D.Options + [ofAllowMultiSelect, ofFileMustExist];
    if D.Execute then
      for i := 0 to D.Files.Count - 1 do
        if LbSrc.Items.IndexOf(D.Files[i]) < 0 then
          LbSrc.Items.Add(D.Files[i]);
  finally
    D.Free;
  end;
end;

procedure TNewDlgHelper.AddDirClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Form);
  try
    D.Title := Tr('Seleziona la cartella da aggiungere');
    if D.Execute then
      if LbSrc.Items.IndexOf(ExcludeTrailingPathDelimiter(D.FileName)) < 0 then
        LbSrc.Items.Add(ExcludeTrailingPathDelimiter(D.FileName));
  finally
    D.Free;
  end;
end;

procedure TNewDlgHelper.RemoveClick(Sender: TObject);
var
  i: Integer;
begin
  for i := LbSrc.Count - 1 downto 0 do
    if LbSrc.Selected[i] then LbSrc.Items.Delete(i);
end;

procedure TNewDlgHelper.OkClick(Sender: TObject);
begin
  if Trim(EdPath.Text) = '' then
  begin
    MessageDlg(Tr('Indicare il nome dell''archivio.'), mtWarning, [mbOK], 0);
    Exit;
  end;
  if LbSrc.Count = 0 then
  begin
    MessageDlg(Tr('Aggiungere almeno un file o una cartella.'), mtWarning, [mbOK], 0);
    Exit;
  end;
  if ChkRec.Checked and (CbRecMode.ItemIndex = 1) and
     (FindDefaultExecutablePath('par2') = '') then
  begin
    MessageDlg(Tr('Il programma "par2" non è installato.') + LineEnding +
      Tr('Installarlo con:  sudo apt install par2') + LineEnding +
      Tr('oppure scegliere i dati di recupero "in coda all''archivio".'), mtWarning, [mbOK], 0);
    Exit;
  end;
  Form.ModalResult := mrOK;
end;

function ExecNewArchive(var Opt: TNewArchiveOptions): Boolean;
var
  H: TNewDlgHelper;
  F: TForm;
  CbLevel: TComboBox;
  B: TButton;
  L: TLabel;
  i: Integer;
begin
  H := TNewDlgHelper.Create;
  F := TForm.CreateNew(nil);
  try
    H.Form := F;
    F.Caption := Tr('Crea nuovo archivio');
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 560;
    F.ClientHeight := 470;

    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 14; L.Caption := Tr('Archivio:');
    H.EdPath := TEdit.Create(F); H.EdPath.Parent := F;
    H.EdPath.SetBounds(90, 10, 400, 24);
    H.EdPath.Text := Opt.Path;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(496, 9, 52, 26);
    B.Caption := '...'; B.OnClick := @H.BrowseClick;

    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 48; L.Caption := Tr('Formato:');
    H.CbFmt := TComboBox.Create(F); H.CbFmt.Parent := F;
    H.CbFmt.SetBounds(90, 44, 150, 24);
    H.CbFmt.Style := csDropDownList;
    for i := 0 to High(FormatKeys) do H.CbFmt.Items.Add(FormatKeys[i]);
    H.CbFmt.ItemIndex := 0;
    for i := 0 to High(FormatKeys) do
      if FormatKeys[i] = Opt.Fmt then H.CbFmt.ItemIndex := i;
    H.CbFmt.OnChange := @H.FmtChange;

    L := TLabel.Create(F); L.Parent := F; L.Left := 270; L.Top := 48; L.Caption := Tr('Compressione:');
    CbLevel := TComboBox.Create(F); CbLevel.Parent := F;
    CbLevel.SetBounds(370, 44, 178, 24);
    CbLevel.Style := csDropDownList;
    CbLevel.Items.Add(Tr('Nessuna (0)'));
    CbLevel.Items.Add(Tr('Velocissima (1)'));
    CbLevel.Items.Add(Tr('Veloce (3)'));
    CbLevel.Items.Add(Tr('Normale (5)'));
    CbLevel.Items.Add(Tr('Massima (7)'));
    CbLevel.Items.Add(Tr('Ultra (9)'));
    CbLevel.ItemIndex := 3;

    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 82; L.Caption := Tr('Password:');
    H.EdPwd := TEdit.Create(F); H.EdPwd.Parent := F;
    H.EdPwd.SetBounds(90, 78, 200, 24);
    H.EdPwd.PasswordChar := '*';
    H.ChkNames := TCheckBox.Create(F); H.ChkNames.Parent := F;
    H.ChkNames.SetBounds(310, 80, 240, 22);
    H.ChkNames.Caption := Tr('Cifra anche i nomi dei file (7z)');

    H.ChkSolid := TCheckBox.Create(F); H.ChkSolid.Parent := F;
    H.ChkSolid.SetBounds(12, 108, 536, 22);
    H.ChkSolid.Caption := Tr('Archivio solido (compressione migliore, senza dim. compressa per file)');
    H.ChkSolid.Hint := Tr('7z non fornisce la dimensione compressa dei singoli file di un blocco solido');
    H.ChkSolid.ShowHint := True;

    H.ChkRec := TCheckBox.Create(F); H.ChkRec.Parent := F;
    H.ChkRec.SetBounds(12, 140, 150, 22);
    H.ChkRec.Caption := Tr('Dati di recupero:');
    H.ChkRec.OnChange := @H.RecToggle;
    H.CbRecMode := TComboBox.Create(F); H.CbRecMode.Parent := F;
    H.CbRecMode.SetBounds(165, 138, 225, 24);
    H.CbRecMode.Style := csDropDownList;
    H.CbRecMode.Items.Add(Tr('In coda all''archivio (solo 7z)'));
    H.CbRecMode.Items.Add(Tr('File PAR2 separati'));
    H.CbRecMode.ItemIndex := 0;
    H.CbRecMode.OnChange := @H.RecModeChange;
    L := TLabel.Create(F); L.Parent := F; L.Left := 400; L.Top := 142; L.Caption := Tr('Ridondanza:');
    H.CbRecPct := TComboBox.Create(F); H.CbRecPct.Parent := F;
    H.CbRecPct.SetBounds(475, 138, 73, 24);
    H.CbRecPct.Style := csDropDownList;
    for i := 0 to 5 do
      H.CbRecPct.Items.Add(IntToStr(RecPercents[i]) + '%');
    H.CbRecPct.ItemIndex := 2;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(12, 168, 330, 24);
    B.Caption := Tr('Quale tipo di dati di recupero scegliere?...'); B.OnClick := @H.HelpClick;
    H.RecToggle(nil);

    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 206; L.Caption := Tr('Contenuto dell''archivio:');
    H.LbSrc := TListBox.Create(F); H.LbSrc.Parent := F;
    H.LbSrc.SetBounds(12, 226, 424, 190);
    H.LbSrc.MultiSelect := True;
    if Opt.Sources <> nil then H.LbSrc.Items.Assign(Opt.Sources);

    B := TButton.Create(F); B.Parent := F; B.SetBounds(446, 226, 102, 28);
    B.Caption := Tr('Aggiungi file...'); B.OnClick := @H.AddFilesClick;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(446, 260, 102, 28);
    B.Caption := Tr('Cartella...'); B.OnClick := @H.AddDirClick;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(446, 294, 102, 28);
    B.Caption := Tr('Rimuovi'); B.OnClick := @H.RemoveClick;

    B := TButton.Create(F); B.Parent := F; B.SetBounds(358, 430, 90, 28);
    B.Caption := Tr('Crea'); B.Default := True; B.OnClick := @H.OkClick;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(458, 430, 90, 28);
    B.Caption := Tr('Annulla'); B.Cancel := True; B.ModalResult := mrCancel;

    H.FmtChange(nil);
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      Opt.Path := Trim(H.EdPath.Text);
      Opt.Fmt := FormatKeys[H.CbFmt.ItemIndex];
      case CbLevel.ItemIndex of
        0: Opt.Level := 0;
        1: Opt.Level := 1;
        2: Opt.Level := 3;
        3: Opt.Level := 5;
        4: Opt.Level := 7;
      else
        Opt.Level := 9;
      end;
      if H.EdPwd.Enabled then Opt.Password := H.EdPwd.Text else Opt.Password := '';
      if H.ChkRec.Checked then
      begin
        Opt.RecMode := H.CbRecMode.ItemIndex + 1;
        Opt.RecPct := RecPercents[H.CbRecPct.ItemIndex];
      end
      else
        Opt.RecMode := 0;
      Opt.Solid := H.ChkSolid.Enabled and H.ChkSolid.Checked;
      Opt.EncryptNames := H.ChkNames.Enabled and H.ChkNames.Checked and (Opt.Password <> '');
      if Opt.Sources = nil then Opt.Sources := TStringList.Create;
      Opt.Sources.Assign(H.LbSrc.Items);
    end;
  finally
    F.Free;
    H.Free;
  end;
end;

procedure ShowRecoveryHelp;
var
  F: TForm;
  M: TMemo;
  B: TButton;
begin
  F := TForm.CreateNew(nil);
  try
    F.Caption := Tr('Dati di recupero: quale scegliere?');
    F.Position := poScreenCenter;
    F.ClientWidth := 700;
    F.ClientHeight := 560;
    M := TMemo.Create(F);
    M.Parent := F;
    M.SetBounds(10, 10, 680, 500);
    M.Anchors := [akLeft, akTop, akRight, akBottom];
    M.ReadOnly := True;
    M.WordWrap := True;
    M.ScrollBars := ssAutoVertical;
    M.Lines.Text :=
      Tr('A COSA SERVONO') + LineEnding +
      Tr('I dati di recupero (codici Reed-Solomon) permettono di ricostruire un archivio quando ') +
      Tr('una parte del file si danneggia: settori illeggibili di un disco o di una chiavetta, ') +
      Tr('download corrotto, errori su supporti ottici. Maggiore è la percentuale di ridondanza, ') +
      Tr('maggiore è la quantità di danni recuperabili (e lo spazio occupato). ') +
      Tr('Non servono se il file viene cancellato o perso del tutto: per quello servono le copie di backup.') +
      LineEnding + LineEnding +
      Tr('1) IN CODA ALL''ARCHIVIO') + LineEnding +
      Tr('- I dati sono scritti alla fine dello stesso file: un solo file da conservare e copiare, ') +
      Tr('come il "recovery record" di WinRAR.') + LineEnding +
      Tr('- Disponibile solo per il formato 7z. L''archivio resta apribile da 7-Zip (che segnala soltanto ') +
      Tr('un avviso per i dati aggiuntivi), ma la riparazione si fa solo con TTCompressor.') + LineEnding +
      Tr('- Se l''archivio viene modificato con un altro programma, i dati in coda vanno persi; ') +
      Tr('se lo modifichi con TTCompressor (Aggiungi / Cancella) vengono rigenerati automaticamente.') + LineEnding +
      Tr('- Il danno può essere sparso o in un tratto continuo: i blocchi sono distribuiti in modo ') +
      Tr('che un danno contiguo grande quanto circa la percentuale scelta sia ancora recuperabile.') + LineEnding +
      Tr('- Se vengono danneggiate sia le intestazioni sia il footer del blocco di recupero non si recupera nulla ') +
      Tr('(esistono due copie delle intestazioni e un footer per ridurre il rischio).') + LineEnding + LineEnding +
      Tr('2) FILE PAR2 SEPARATI') + LineEnding +
      Tr('- Vengono creati accanto all''archivio alcuni file .par2 (standard diffuso, ') +
      Tr('leggibile anche da altri programmi come par2cmdline, MultiPar o QuickPar).') + LineEnding +
      Tr('- Funziona con qualsiasi formato (7z, zip, tar, ...), non tocca il file dell''archivio ') +
      Tr('e non influisce sulla compatibilità con altri programmi.') + LineEnding +
      Tr('- Per recuperare i dati servono anche i file .par2: vanno copiati e conservati insieme ') +
      Tr('all''archivio. Se si perdono, non c''è più protezione.') + LineEnding +
      Tr('- Richiede il programma "par2" (sudo apt install par2). Se modifichi l''archivio con ') +
      Tr('TTCompressor i file .par2 vengono rigenerati; con altri programmi diventano non validi.') + LineEnding +
      Tr('- Più lento di quello in coda su archivi grandi.') + LineEnding + LineEnding +
      Tr('COME SCEGLIERE') + LineEnding +
      Tr('- Vuoi un solo file, formato 7z, e lo userai con TTCompressor: in coda.') + LineEnding +
      Tr('- Altri formati, oppure vuoi uno standard leggibile da altri strumenti, oppure vuoi che ') +
      Tr('l''archivio resti identico: PAR2.') + LineEnding +
      Tr('- Per dati importanti conviene comunque tenere una copia di backup su un altro supporto: ') +
      Tr('i dati di recupero proteggono da danni parziali, non da perdite totali.') + LineEnding + LineEnding +
      Tr('COME SI USANO') + LineEnding +
      Tr('- "Verifica integrità" controlla l''archivio e, se presenti, anche i dati di recupero.') + LineEnding +
      Tr('- "Archivio > Ripara archivio" ricostruisce le parti danneggiate. Funziona anche con ') +
      Tr('archivi che non si riescono più ad aprire.') + LineEnding +
      Tr('- Percentuali tipiche: 3-5% per danni occasionali, 10% o più per supporti inaffidabili.');
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(600, 520, 90, 28);
    B.Anchors := [akRight, akBottom];
    B.Caption := Tr('Chiudi');
    B.Default := True;
    B.ModalResult := mrOK;
    // deve stare dentro la finestra principale
    if Application.MainForm <> nil then
    begin
      if F.Width > Application.MainForm.Width - 20 then
        F.Width := Application.MainForm.Width - 20;
      if F.Height > Application.MainForm.Height - 20 then
        F.Height := Application.MainForm.Height - 20;
    end;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

type
  TRecDlgHelper = class
    procedure HelpClick(Sender: TObject);
  end;

procedure TRecDlgHelper.HelpClick(Sender: TObject);
begin
  ShowRecoveryHelp;
end;

{ Mode: 1 in coda all'archivio, 2 file PAR2 }
function ExecRecovery(var Mode, Pct: Integer; AllowTail, Replacing: Boolean): Boolean;
var
  H: TRecDlgHelper;
  F: TForm;
  L: TLabel;
  B: TButton;
  CbMode, CbPct: TComboBox;
  i: Integer;
begin
  H := TRecDlgHelper.Create;
  F := TForm.CreateNew(nil);
  try
    F.Caption := Tr('Aggiungi dati di recupero');
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 440;
    F.ClientHeight := 150;
    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 16; L.Caption := Tr('Tipo:');
    CbMode := TComboBox.Create(F); CbMode.Parent := F;
    CbMode.SetBounds(110, 12, 318, 24);
    CbMode.Style := csDropDownList;
    CbMode.Items.Add(Tr('In coda all''archivio (solo 7z)'));
    CbMode.Items.Add(Tr('File PAR2 separati'));
    if AllowTail then CbMode.ItemIndex := 0
    else
    begin
      CbMode.ItemIndex := 1;
      CbMode.Enabled := False;
    end;
    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 52; L.Caption := Tr('Ridondanza:');
    CbPct := TComboBox.Create(F); CbPct.Parent := F;
    CbPct.SetBounds(110, 48, 90, 24);
    CbPct.Style := csDropDownList;
    for i := 0 to High(RecPercents) do
      CbPct.Items.Add(IntToStr(RecPercents[i]) + '%');
    CbPct.ItemIndex := 2;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(212, 46, 90, 28);
    B.Caption := Tr('Quale?'); B.OnClick := @H.HelpClick;
    if Replacing then
    begin
      L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 86;
      L.Caption := Tr('I dati di recupero esistenti verranno sostituiti.');
    end;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(238, 110, 90, 28);
    B.Caption := Tr('Genera'); B.Default := True; B.ModalResult := mrOK;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(338, 110, 90, 28);
    B.Caption := Tr('Annulla'); B.Cancel := True; B.ModalResult := mrCancel;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      Mode := CbMode.ItemIndex + 1;
      Pct := RecPercents[CbPct.ItemIndex];
    end;
  finally
    F.Free;
    H.Free;
  end;
end;

type
  TExtractDlgHelper = class
    EdDir: TEdit;
    procedure BrowseClick(Sender: TObject);
  end;

procedure TExtractDlgHelper.BrowseClick(Sender: TObject);
var
  D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(nil);
  try
    D.Title := Tr('Cartella di destinazione');
    D.InitialDir := EdDir.Text;
    if D.Execute then EdDir.Text := D.FileName;
  finally
    D.Free;
  end;
end;

function ExecExtract(var Opt: TExtractOptions; SelCount: Integer): Boolean;
var
  H: TExtractDlgHelper;
  F: TForm;
  L: TLabel;
  B: TButton;
  RbSel, RbAll: TRadioButton;
  ChkPaths, ChkLinks: TCheckBox;
  CbOver: TComboBox;
begin
  H := TExtractDlgHelper.Create;
  F := TForm.CreateNew(nil);
  try
    F.Caption := Tr('Estrai nella cartella');
    F.Position := poScreenCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 520;
    F.ClientHeight := 266;

    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 16; L.Caption := Tr('Cartella:');
    H.EdDir := TEdit.Create(F); H.EdDir.Parent := F;
    H.EdDir.SetBounds(80, 12, 360, 24);
    H.EdDir.Text := Opt.DestDir;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(448, 11, 60, 26);
    B.Caption := '...'; B.OnClick := @H.BrowseClick;

    RbSel := TRadioButton.Create(F); RbSel.Parent := F;
    RbSel.SetBounds(12, 52, 400, 22);
    RbSel.Caption := Format(Tr('Solo gli elementi selezionati (%d)'), [SelCount]);
    RbSel.Enabled := SelCount > 0;
    RbAll := TRadioButton.Create(F); RbAll.Parent := F;
    RbAll.SetBounds(12, 78, 400, 22);
    RbAll.Caption := Tr('Tutto l''archivio');
    if SelCount > 0 then RbSel.Checked := True else RbAll.Checked := True;

    ChkPaths := TCheckBox.Create(F); ChkPaths.Parent := F;
    ChkPaths.SetBounds(12, 112, 400, 22);
    ChkPaths.Caption := Tr('Mantieni la struttura delle cartelle');
    ChkPaths.Checked := Opt.KeepPaths;

    L := TLabel.Create(F); L.Parent := F; L.Left := 12; L.Top := 148; L.Caption := Tr('Se il file esiste:');
    CbOver := TComboBox.Create(F); CbOver.Parent := F;
    CbOver.SetBounds(130, 144, 250, 24);
    CbOver.Style := csDropDownList;
    CbOver.Items.Add(Tr('Rinomina automaticamente il nuovo'));
    CbOver.Items.Add(Tr('Sovrascrivi'));
    CbOver.Items.Add(Tr('Salta'));
    CbOver.ItemIndex := Opt.Overwrite;

    ChkLinks := TCheckBox.Create(F); ChkLinks.Parent := F;
    ChkLinks.SetBounds(12, 182, 490, 22);
    ChkLinks.Caption := Tr('Consenti collegamenti simbolici fuori dalla cartella');
    ChkLinks.Hint := Tr('Di default 7z ignora i collegamenti simbolici che puntano fuori ') +
      Tr('dalla cartella di destinazione. Attivare solo per archivi di cui ci si fida.');
    ChkLinks.ShowHint := True;
    ChkLinks.Checked := Opt.AllowLinks;

    B := TButton.Create(F); B.Parent := F; B.SetBounds(312, 226, 90, 28);
    B.Caption := Tr('Estrai'); B.Default := True; B.ModalResult := mrOK;
    B := TButton.Create(F); B.Parent := F; B.SetBounds(412, 226, 90, 28);
    B.Caption := Tr('Annulla'); B.Cancel := True; B.ModalResult := mrCancel;

    Result := F.ShowModal = mrOK;
    if Result then
    begin
      Opt.AllowLinks := ChkLinks.Checked;
      Opt.DestDir := Trim(H.EdDir.Text);
      Opt.OnlySelected := RbSel.Checked;
      Opt.KeepPaths := ChkPaths.Checked;
      Opt.Overwrite := CbOver.ItemIndex;
      if Opt.DestDir = '' then Result := False;
    end;
  finally
    F.Free;
    H.Free;
  end;
end;

end.
