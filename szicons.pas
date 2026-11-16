unit szicons;

{ Icone associate dal sistema ai tipi di file.
  Estensione -> tipo MIME tramite il database freedesktop (shared-mime-info),
  tipo MIME -> icona tramite il tema icone GTK corrente. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, GraphType, IntfGraphics, FPImage,
  gtk2, gdk2pixbuf, glib2;

type
  TSysIcons = class
  private
    FSize: Integer;
    FList: TImageList;
    FGlobKeys: TStringList;   // "*.ext" o nome letterale -> indice in FGlobMimes
    FGlobMimes: TStringList;
    FGlobWeights: TList;
    FIconOf: TStringList;     // mime -> nome icona (file "icons")
    FGeneric: TStringList;    // mime -> nome icona generica
    FByMime: TStringList;     // mime -> indice immagine
    FByName: TStringList;     // nome icona -> indice immagine
    FFolder: Integer;
    FFile: Integer;
    FArchive: Integer;
    procedure LoadGlobs(const FileName: string);
    procedure LoadPairs(const FileName: string; Dest: TStringList);
    function MimeFor(const FileName: string): string;
    function AddByNames(const Names: array of string): Integer;
  public
    constructor Create(ASize: Integer);
    destructor Destroy; override;
    function IndexForFile(const FileName: string): Integer;
    property Images: TImageList read FList;
    property FolderIndex: Integer read FFolder;
    property FileIndex: Integer read FFile;
    property ArchiveIndex: Integer read FArchive;
  end;

{ Carica la prima icona esistente nel tema; nil se nessuna. Il chiamante libera. }
function ThemeBitmap(const Names: array of string; Size: Integer): TBitmap;

{ Centra sul rettangolo R le finestre GTK di primo livello appena comparse
  (avvisi, selettori di file) che non siano la finestra Main. Ognuna viene
  spostata una sola volta. }
procedure CenterToplevelsOver(const R: TRect; Main: Pointer);

implementation

procedure CenterToplevelsOver(const R: TRect; Main: Pointer);
var
  L, P: PGList;
  W: PGtkWidget;
  w1, h1, x, y, wtype: gint;
begin
  L := gtk_window_list_toplevels;
  P := L;
  while P <> nil do
  begin
    W := PGtkWidget(P^.data);
    P := P^.next;
    if (W = nil) or (W = PGtkWidget(Main)) then Continue;
    wtype := -1;
    g_object_get(PGObject(W), 'type', @wtype, nil);
    if wtype <> Ord(GTK_WINDOW_TOPLEVEL) then Continue;
    if not GTK_WIDGET_MAPPED(W) then Continue;
    if g_object_get_data(PGObject(W), 'lz-centered') <> nil then Continue;
    g_object_set_data(PGObject(W), 'lz-centered', Pointer(1));
    gtk_window_get_size(PGtkWindow(W), @w1, @h1);
    x := R.Left + ((R.Right - R.Left) - w1) div 2;
    y := R.Top + ((R.Bottom - R.Top) - h1) div 2;
    if x + w1 > R.Right then x := R.Right - w1;
    if y + h1 > R.Bottom then y := R.Bottom - h1;
    if x < R.Left then x := R.Left;
    if y < R.Top then y := R.Top;
    gtk_window_move(PGtkWindow(W), x, y);
  end;
  g_list_free(L);
end;

function PixbufToBitmap(pb: PGdkPixbuf): TBitmap;
var
  w, h, rs, nc, x, y: Integer;
  px, q: PByte;
  img: TLazIntfImage;
  c: TFPColor;
  hasA: Boolean;
begin
  w := gdk_pixbuf_get_width(pb);
  h := gdk_pixbuf_get_height(pb);
  rs := gdk_pixbuf_get_rowstride(pb);
  nc := gdk_pixbuf_get_n_channels(pb);
  hasA := gdk_pixbuf_get_has_alpha(pb);
  px := PByte(gdk_pixbuf_get_pixels(pb));
  img := TLazIntfImage.Create(w, h, [riqfRGB, riqfAlpha]);
  try
    for y := 0 to h - 1 do
      for x := 0 to w - 1 do
      begin
        q := px + y * rs + x * nc;
        c.Red := q[0] * 257;
        c.Green := q[1] * 257;
        c.Blue := q[2] * 257;
        if hasA then c.Alpha := q[3] * 257 else c.Alpha := $FFFF;
        img.Colors[x, y] := c;
      end;
    Result := TBitmap.Create;
    Result.LoadFromIntfImage(img);
  finally
    img.Free;
  end;
end;

function ThemeBitmapEx(const Names: array of string; Size: Integer;
  out Used: string): TBitmap;
var
  theme: PGtkIconTheme;
  i: Integer;
  pb: PGdkPixbuf;
begin
  Result := nil;
  Used := '';
  theme := gtk_icon_theme_get_default;
  if theme = nil then Exit;
  for i := Low(Names) to High(Names) do
    if gtk_icon_theme_has_icon(theme, PChar(Names[i])) then
    begin
      pb := gtk_icon_theme_load_icon(theme, PChar(Names[i]), Size,
        GTK_ICON_LOOKUP_FORCE_SIZE, nil);
      if pb <> nil then
      begin
        Result := PixbufToBitmap(pb);
        g_object_unref(pb);
        Used := Names[i];
        Exit;
      end;
    end;
end;

function ThemeBitmap(const Names: array of string; Size: Integer): TBitmap;
var
  used: string;
begin
  Result := ThemeBitmapEx(Names, Size, used);
end;

constructor TSysIcons.Create(ASize: Integer);
begin
  inherited Create;
  FSize := ASize;
  FList := TImageList.Create(nil);
  FList.Width := ASize;
  FList.Height := ASize;
  FGlobKeys := TStringList.Create;
  FGlobKeys.Sorted := True;
  FGlobKeys.Duplicates := dupIgnore;
  FGlobKeys.CaseSensitive := True;
  FGlobMimes := TStringList.Create;
  FGlobWeights := TList.Create;
  FIconOf := TStringList.Create;
  FIconOf.Sorted := True;
  FGeneric := TStringList.Create;
  FGeneric.Sorted := True;
  FByMime := TStringList.Create;
  FByMime.Sorted := True;
  FByName := TStringList.Create;
  FByName.Sorted := True;
  LoadGlobs('/usr/share/mime/globs2');
  LoadGlobs(GetUserDir + '.local/share/mime/globs2');
  LoadPairs('/usr/share/mime/icons', FIconOf);
  LoadPairs('/usr/share/mime/generic-icons', FGeneric);
  FFile := AddByNames(['text-x-generic', 'application-x-generic', 'unknown', 'gtk-file']);
  FFolder := AddByNames(['folder', 'inode-directory', 'gtk-directory']);
  FArchive := AddByNames(['package-x-generic', 'application-x-archive', 'application-x-compressed-tar']);
  if FArchive < 0 then FArchive := FFile;
end;

destructor TSysIcons.Destroy;
begin
  FList.Free;
  FGlobKeys.Free;
  FGlobMimes.Free;
  FGlobWeights.Free;
  FIconOf.Free;
  FGeneric.Free;
  FByMime.Free;
  FByName.Free;
  inherited Destroy;
end;

procedure TSysIcons.LoadGlobs(const FileName: string);
var
  L: TStringList;
  i, p1, p2, p3, w, idx, mi: Integer;
  s, mime, glob, flags: string;
begin
  if not FileExists(FileName) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for i := 0 to L.Count - 1 do
    begin
      s := L[i];
      if (s = '') or (s[1] = '#') then Continue;
      p1 := Pos(':', s);
      if p1 = 0 then Continue;
      p2 := Pos(':', Copy(s, p1 + 1, MaxInt));
      if p2 = 0 then Continue;
      p2 := p1 + p2;
      w := StrToIntDef(Copy(s, 1, p1 - 1), 50);
      mime := Copy(s, p1 + 1, p2 - p1 - 1);
      glob := Copy(s, p2 + 1, MaxInt);
      flags := '';
      p3 := Pos(':', glob);
      if p3 > 0 then
      begin
        flags := Copy(glob, p3 + 1, MaxInt);
        glob := Copy(glob, 1, p3 - 1);
      end;
      if flags = 'cs' then Continue;
      glob := LowerCase(glob);
      if mime = '' then Continue;
      if FGlobKeys.Find(glob, idx) then
      begin
        mi := PtrInt(FGlobKeys.Objects[idx]);
        if w >= PtrInt(FGlobWeights[mi]) then
        begin
          FGlobMimes[mi] := mime;
          FGlobWeights[mi] := Pointer(PtrInt(w));
        end;
      end
      else
      begin
        mi := FGlobMimes.Add(mime);
        FGlobWeights.Add(Pointer(PtrInt(w)));
        FGlobKeys.AddObject(glob, TObject(PtrInt(mi)));
      end;
    end;
  finally
    L.Free;
  end;
end;

procedure TSysIcons.LoadPairs(const FileName: string; Dest: TStringList);
var
  L: TStringList;
  i, p: Integer;
  s: string;
begin
  if not FileExists(FileName) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    for i := 0 to L.Count - 1 do
    begin
      s := L[i];
      p := Pos(':', s);
      if (p > 1) and (Dest.IndexOf(Copy(s, 1, p - 1)) < 0) then
        Dest.Values[Copy(s, 1, p - 1)] := Copy(s, p + 1, MaxInt);
    end;
  finally
    L.Free;
  end;
end;

function TSysIcons.MimeFor(const FileName: string): string;
var
  lower, key: string;
  i, idx: Integer;
begin
  Result := '';
  lower := LowerCase(FileName);
  if FGlobKeys.Find(lower, idx) then
    Exit(FGlobMimes[PtrInt(FGlobKeys.Objects[idx])]);
  for i := 1 to Length(lower) do
    if lower[i] = '.' then
    begin
      key := '*' + Copy(lower, i, MaxInt);
      if FGlobKeys.Find(key, idx) then
        Exit(FGlobMimes[PtrInt(FGlobKeys.Objects[idx])]);
    end;
end;

function TSysIcons.AddByNames(const Names: array of string): Integer;
var
  i, idx: Integer;
  bmp: TBitmap;
  used: string;
begin
  Result := -1;
  for i := Low(Names) to High(Names) do
  begin
    if Names[i] = '' then Continue;
    if FByName.Find(Names[i], idx) then
      Exit(PtrInt(FByName.Objects[idx]));
    bmp := ThemeBitmapEx([Names[i]], FSize, used);
    if bmp <> nil then
    begin
      try
        Result := FList.Add(bmp, nil);
      finally
        bmp.Free;
      end;
      FByName.AddObject(used, TObject(PtrInt(Result)));
      Exit;
    end;
  end;
end;

function TSysIcons.IndexForFile(const FileName: string): Integer;
var
  mime, dashed, top, ic, gen: string;
  idx, p: Integer;
  names: array of string;
begin
  mime := MimeFor(ExtractFileName(FileName));
  if mime = '' then Exit(FFile);
  if FByMime.Find(mime, idx) then
    Exit(PtrInt(FByMime.Objects[idx]));
  dashed := StringReplace(mime, '/', '-', [rfReplaceAll]);
  ic := FIconOf.Values[mime];
  gen := FGeneric.Values[mime];
  p := Pos('/', mime);
  top := Copy(mime, 1, p - 1);
  SetLength(names, 5);
  names[0] := dashed;
  if ic <> '' then names[1] := ic else names[1] := dashed;
  if gen <> '' then names[2] := gen else names[2] := top + '-x-generic';
  names[3] := top + '-x-generic';
  names[4] := 'text-x-generic';
  Result := AddByNames(names);
  if Result < 0 then Result := FFile;
  FByMime.AddObject(mime, TObject(PtrInt(Result)));
end;

end.
