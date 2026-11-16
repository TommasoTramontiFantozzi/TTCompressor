unit szmodel;

{ Modello dati dell'archivio: parsing dell'output di "7z l -slt -ba" e
  costruzione dell'albero delle cartelle. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TFolder = class;

  TArcEntry = class
    Name: string;          // ultimo componente del percorso
    Path: string;          // percorso completo (separatore '/')
    IsDir: Boolean;
    Size: Int64;
    PackSize: Int64;
    PackKnown: Boolean;  // 7z in un blocco solido riporta il packed solo sul primo file
    Block: Integer;
    MTime: string;
    Ext: string;           // estensione minuscola, senza punto
    Folder: TFolder;       // cartella che lo contiene
  end;

  TFolder = class
    Name: string;
    Path: string;
    Parent: TFolder;
    Children: TFPList;     // TFolder
    FileList: TFPList;     // TArcEntry (solo file)
    MTime: string;
    TotSize: Int64;
    TotPacked: Int64;
    TotPackKnown: Boolean;
    FileCount: Integer;
    KnownCount: Integer;
    constructor Create(const AName, APath: string; AParent: TFolder);
    destructor Destroy; override;
  end;

  TArcModel = class
  private
    FEntries: TFPList;
    FFolders: TFPList;
    FLastPath: string;     // cache dell'ultima cartella cercata (le voci sono quasi sempre consecutive)
    FLastFolder: TFolder;
    FCur: TArcEntry;       // voce in lettura (parsing di "7z l -slt")
    FHave: Boolean;
    FCount: Integer;
    FIgnorePacked: Boolean;
    procedure FlushCur;
    procedure ParseLine(P: PChar; Len: Integer);
    procedure FinishParse;
    procedure AddEntry(E: TArcEntry);
    procedure Totals(F: TFolder);
    procedure DropSolidPacked;
  public
    Root: TFolder;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { Interpreta le righe di "7z l -slt -ba". Restituisce il numero di voci. }
    function ParseSlt(Lines: TStrings; IgnorePacked: Boolean = False): Integer;
    { Come ParseSlt, ma da un unico testo (righe separate da #10). }
    function ParseSltText(const Text: string; IgnorePacked: Boolean = False): Integer;
    function FindFolder(const APath: string; CreateIt: Boolean): TFolder;
    property Entries: TFPList read FEntries;
  end;

implementation

constructor TFolder.Create(const AName, APath: string; AParent: TFolder);
begin
  inherited Create;
  Name := AName;
  Path := APath;
  Parent := AParent;
  Children := TFPList.Create;
  FileList := TFPList.Create;
end;

destructor TFolder.Destroy;
begin
  Children.Free;
  FileList.Free;
  inherited Destroy;
end;

constructor TArcModel.Create;
begin
  inherited Create;
  FEntries := TFPList.Create;
  FFolders := TFPList.Create;
  Root := TFolder.Create('', '', nil);
  FFolders.Add(Root);
end;

destructor TArcModel.Destroy;
begin
  Clear;
  Root.Free;
  FEntries.Free;
  FFolders.Free;
  inherited Destroy;
end;

procedure TArcModel.Clear;
var
  i: Integer;
begin
  FLastFolder := nil;
  FLastPath := '';
  for i := 0 to FEntries.Count - 1 do
    TObject(FEntries[i]).Free;
  FEntries.Clear;
  for i := FFolders.Count - 1 downto 1 do
    TObject(FFolders[i]).Free;
  FFolders.Clear;
  FFolders.Add(Root);
  Root.Children.Clear;
  Root.FileList.Clear;
end;

function TArcModel.FindFolder(const APath: string; CreateIt: Boolean): TFolder;
var
  p, start, i: Integer;
  part, acc: string;
  Next: TFolder;
begin
  Result := Root;
  if APath = '' then Exit;
  acc := '';
  start := 1;
  p := 1;
  while p <= Length(APath) + 1 do
  begin
    if (p > Length(APath)) or (APath[p] = '/') then
    begin
      part := Copy(APath, start, p - start);
      start := p + 1;
      if part <> '' then
      begin
        if acc = '' then acc := part else acc := acc + '/' + part;
        Next := nil;
        for i := 0 to Result.Children.Count - 1 do
          if TFolder(Result.Children[i]).Name = part then
          begin
            Next := TFolder(Result.Children[i]);
            Break;
          end;
        if Next = nil then
        begin
          if not CreateIt then
          begin
            Result := nil;
            Exit;
          end;
          Next := TFolder.Create(part, acc, Result);
          Result.Children.Add(Next);
          FFolders.Add(Next);
        end;
        Result := Next;
      end;
    end;
    Inc(p);
  end;
end;

procedure TArcModel.AddEntry(E: TArcEntry);
var
  p: Integer;
  parentPath: string;
  F: TFolder;
begin
  while (Length(E.Path) > 0) and (E.Path[Length(E.Path)] = '/') do
    SetLength(E.Path, Length(E.Path) - 1);
  while (Length(E.Path) > 1) and (Copy(E.Path, 1, 2) = './') do
    Delete(E.Path, 1, 2);
  if (E.Path = '') or (E.Path = '.') then   // "." e la radice dei tar (es. data.tar dei .deb)
  begin
    E.Free;
    Exit;
  end;
  p := LastDelimiter('/', E.Path);
  if p > 0 then
  begin
    parentPath := Copy(E.Path, 1, p - 1);
    E.Name := Copy(E.Path, p + 1, MaxInt);
  end
  else
  begin
    parentPath := '';
    E.Name := E.Path;
  end;
  if E.IsDir then
  begin
    F := FindFolder(E.Path, True);
    F.MTime := E.MTime;
    FEntries.Add(E);
    E.Folder := F.Parent;
    Exit;
  end;
  p := LastDelimiter('.', E.Name);
  if (p > 1) then E.Ext := LowerCase(Copy(E.Name, p + 1, MaxInt)) else E.Ext := '';
  if (FLastFolder <> nil) and (parentPath = FLastPath) then
    F := FLastFolder
  else
  begin
    F := FindFolder(parentPath, True);
    FLastPath := parentPath;
    FLastFolder := F;
  end;
  E.Folder := F;
  F.FileList.Add(E);
  FEntries.Add(E);
end;

{ Legge un numero (decimale) da P[From..Len-1]. }
function NumAt(P: PChar; From, Len: Integer; Def: Int64): Int64;
var
  i: Integer;
begin
  i := From;
  if (i >= Len) or not (P[i] in ['0'..'9']) then Exit(Def);
  Result := 0;
  while (i < Len) and (P[i] in ['0'..'9']) do
  begin
    Result := Result * 10 + (Ord(P[i]) - 48);
    Inc(i);
  end;
end;

function KeyIs(P: PChar; KeyLen: Integer; const Key: string): Boolean; inline;
begin
  Result := (KeyLen = Length(Key)) and (CompareByte(P^, Key[1], KeyLen) = 0);
end;

procedure TArcModel.FlushCur;
begin
  if (FCur <> nil) and FHave and (FCur.Path <> '') then
  begin
    AddEntry(FCur);
    Inc(FCount);
  end
  else
    FCur.Free;
  FCur := nil;
  FHave := False;
end;

{ Una riga di "7z l -slt": P[0..Len-1], senza terminatore. }
procedure TArcModel.ParseLine(P: PChar; Len: Integer);
var
  p1, kl, vs, i: Integer;
  path: string;
begin
  if (Len > 0) and (P[Len - 1] = #13) then Dec(Len);
  if Len = 0 then
  begin
    if FCur <> nil then FlushCur;
    Exit;
  end;
  // " = " separa chiave e valore
  p1 := -1;
  for i := 0 to Len - 3 do
    if (P[i] = ' ') and (P[i + 1] = '=') and (P[i + 2] = ' ') then
    begin
      p1 := i;
      Break;
    end;
  if p1 < 0 then
  begin
    // "Key =" con valore vuoto
    if (Len > 2) and (P[Len - 2] = ' ') and (P[Len - 1] = '=') then
    begin
      kl := Len - 2;
      vs := Len;
    end
    else
    begin
      // riga di soli spazi: separa le voci
      i := 0;
      while (i < Len) and (P[i] in [' ', #9]) do Inc(i);
      if (i = Len) and (FCur <> nil) then FlushCur;
      Exit;
    end;
  end
  else
  begin
    kl := p1;
    vs := p1 + 3;
  end;
  if KeyIs(P, kl, 'Path') then
  begin
    if FCur <> nil then FlushCur;
    FCur := TArcEntry.Create;
    FCur.Block := -1;
    FCur.PackSize := 0;
    FCur.PackKnown := False;
    SetString(path, P + vs, Len - vs);
    if Pos('\', path) > 0 then
      path := StringReplace(path, '\', '/', [rfReplaceAll]);
    FCur.Path := path;
    FHave := True;
  end
  else if FCur <> nil then
  begin
    case P[0] of
      'S':
        if KeyIs(P, kl, 'Size') then FCur.Size := NumAt(P, vs, Len, 0);
      'P':
        if KeyIs(P, kl, 'Packed Size') then
        begin
          if (vs < Len) and not FIgnorePacked then
          begin
            FCur.PackSize := NumAt(P, vs, Len, 0);
            FCur.PackKnown := True;
          end;
        end;
      'M':
        if KeyIs(P, kl, 'Modified') then SetString(FCur.MTime, P + vs, Len - vs);
      'B':
        if KeyIs(P, kl, 'Block') then FCur.Block := Integer(NumAt(P, vs, Len, -1));
      'F':
        if KeyIs(P, kl, 'Folder') then FCur.IsDir := (vs < Len) and (P[vs] = '+');
      'A':
        if KeyIs(P, kl, 'Attributes') then
          if (vs < Len) and (P[vs] = 'D') then FCur.IsDir := True;
    end;
  end;
end;

procedure TArcModel.FinishParse;
begin
  if FCur <> nil then FlushCur;
  DropSolidPacked;
  Totals(Root);
end;

function TArcModel.ParseSlt(Lines: TStrings; IgnorePacked: Boolean): Integer;
var
  i: Integer;
  s: string;
begin
  FCount := 0;
  FCur := nil;
  FHave := False;
  FIgnorePacked := IgnorePacked;
  for i := 0 to Lines.Count - 1 do
  begin
    s := Lines[i];
    if s = '' then ParseLine(nil, 0) else ParseLine(PChar(s), Length(s));
  end;
  FinishParse;
  Result := FCount;
end;

function TArcModel.ParseSltText(const Text: string; IgnorePacked: Boolean): Integer;
var
  P, Q, E: PChar;
begin
  FCount := 0;
  FCur := nil;
  FHave := False;
  FIgnorePacked := IgnorePacked;
  P := PChar(Text);
  E := P + Length(Text);
  while P < E do
  begin
    Q := P;
    while (Q < E) and (Q^ <> #10) do Inc(Q);
    ParseLine(P, Q - P);
    P := Q + 1;
  end;
  FinishParse;
  Result := FCount;
end;

procedure TArcModel.Totals(F: TFolder);
var
  i: Integer;
  C: TFolder;
  A: TArcEntry;
begin
  F.TotSize := 0;
  F.TotPacked := 0;
  F.FileCount := 0;
  F.KnownCount := 0;
  for i := 0 to F.FileList.Count - 1 do
  begin
    A := TArcEntry(F.FileList[i]);
    Inc(F.TotSize, A.Size);
    Inc(F.FileCount);
    if A.PackKnown then
    begin
      Inc(F.TotPacked, A.PackSize);
      Inc(F.KnownCount);
    end;
  end;
  for i := 0 to F.Children.Count - 1 do
  begin
    C := TFolder(F.Children[i]);
    Totals(C);
    Inc(F.TotSize, C.TotSize);
    Inc(F.TotPacked, C.TotPacked);
    Inc(F.FileCount, C.FileCount);
    Inc(F.KnownCount, C.KnownCount);
  end;
  // la dimensione compressa di una cartella e nota solo se lo e per tutti i suoi file
  F.TotPackKnown := (F.FileCount > 0) and (F.KnownCount = F.FileCount);
end;

procedure TArcModel.DropSolidPacked;
var
  i, mx: Integer;
  A: TArcEntry;
  counts: array of Integer;
begin
  // In un blocco solido 7z riporta la dimensione compressa dell'intero blocco
  // sul primo file: per i singoli file non e un dato valido.
  mx := -1;
  for i := 0 to FEntries.Count - 1 do
  begin
    A := TArcEntry(FEntries[i]);
    if (not A.IsDir) and (A.Block > mx) then mx := A.Block;
  end;
  if mx < 0 then Exit;
  SetLength(counts, mx + 1);
  for i := 0 to FEntries.Count - 1 do
  begin
    A := TArcEntry(FEntries[i]);
    if A.IsDir or (A.Block < 0) then Continue;
    Inc(counts[A.Block]);
  end;
  for i := 0 to FEntries.Count - 1 do
  begin
    A := TArcEntry(FEntries[i]);
    if A.IsDir or (A.Block < 0) then Continue;
    if counts[A.Block] > 1 then A.PackKnown := False;
  end;
end;

end.
