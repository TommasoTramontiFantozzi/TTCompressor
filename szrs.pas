unit szrs;

{ Dati di recupero Reed-Solomon "in coda" all'archivio.

  Formato (little-endian, blocchi da RS_BLOCK byte):

    [archivio originale, N byte][zeri fino a multiplo del blocco]   regione protetta, L = D*B
    [intestazione A]   parametri + CRC32 di ogni blocco (dati e parita) + CRC
    [blocchi di parita]
    [intestazione B]   copia di A
    [footer]           un blocco: parametri + CRC (permette di ritrovare le intestazioni)

  Codice: Reed-Solomon (matrice di Cauchy) su GF(2^8), a gruppi: ogni gruppo ha
  K blocchi dati e P blocchi di parita, con K+P = 255. I blocchi di un gruppo sono
  distanziati di G blocchi, cosi un danno contiguo si distribuisce su molti gruppi.
  Per ogni gruppo si recuperano fino a P blocchi persi (dati o parita); i blocchi
  danneggiati si riconoscono dal CRC32 salvato nell'intestazione.

  Riga di comando (usata da TTCompressor per mostrare l'avanzamento):
    --rs-create <file> <percentuale>   --rs-verify <file>   --rs-repair <file>
    --rs-strip <file>                  --rs-info <file>
  Codici di uscita: 0 ok, 1 danneggiato ma riparabile (verify), 2 errore / non riparabile. }

{$mode objfpc}{$H+}
{$R-}{$Q-}
{$OPTIMIZATION LEVEL2}

interface

uses
  Classes, SysUtils, crc, szlang;

const
  RS_BLOCK = 4096;

type
  TRSInfo = record
    N: Int64;       // dimensione dell'archivio originale
    D: Int64;       // blocchi dati
    G: Int64;       // gruppi
    K, P: Integer;  // dati / parita per gruppo
    Pct: Integer;   // percentuale di ridondanza richiesta
    HS: Int64;      // dimensione di ogni intestazione
  end;

{ Rileva velocemente (solo footer) i dati di recupero in coda. }
function RSDetect(const Path: string; out Info: TRSInfo): Boolean;
{ Linea di comando: restituisce il codice di uscita. }
function RunRecoveryCLI: Integer;

implementation

type
  TRSParams = packed record
    Magic: array[0..7] of AnsiChar;
    Version: LongWord;
    BlockSize: LongWord;
    N: QWord;
    D: QWord;
    K: LongWord;
    P: LongWord;
    G: QWord;
    Pct: LongWord;
    Reserved: LongWord;
    HS: QWord;
  end;

  TCRCTable = array of LongWord;
  TBadMap = array of Byte;

const
  MAGIC_HDR = 'LZRECHD1';
  MAGIC_FTR = 'LZRECFT1';
  MEM_BUDGET = 64 * 1024 * 1024;

var
  GFExp: array[0..511] of Byte;
  GFLog: array[0..255] of Byte;
  GFMul: array[0..255, 0..255] of Byte;
  GFReady: Boolean = False;
  LastPrint: QWord = 0;
  FS: TFormatSettings;

{ ---------- GF(256) ---------- }

procedure InitGF;
var
  i, x, a, b: Integer;
begin
  if GFReady then Exit;
  x := 1;
  for i := 0 to 254 do
  begin
    GFExp[i] := x;
    GFLog[x] := i;
    x := x shl 1;
    if x and $100 <> 0 then x := x xor $11d;
  end;
  for i := 255 to 511 do GFExp[i] := GFExp[i - 255];
  for a := 0 to 255 do
    for b := 0 to 255 do
      if (a = 0) or (b = 0) then GFMul[a, b] := 0
      else GFMul[a, b] := GFExp[GFLog[a] + GFLog[b]];
  GFReady := True;
end;

function GFInv(a: Integer): Integer;
begin
  Result := GFExp[255 - GFLog[a]];
end;

{ coefficiente di Cauchy della parita p per il blocco dati j }
function Coef(K, p, j: Integer): Integer;
begin
  Result := GFInv((K + p) xor j);
end;

procedure MulAdd(dst, src: PByte; n: Integer; tab: PByte);
var
  i: Integer;
begin
  for i := 0 to n - 1 do
    dst[i] := dst[i] xor tab[src[i]];
end;

{ ---------- output ---------- }

procedure Say(const S: string);
begin
  WriteLn(S);
  Flush(Output);
end;

procedure Progress(Frac: Double; const Lbl: string; Force: Boolean = False);
var
  t: QWord;
begin
  t := GetTickCount64;
  if (not Force) and (t - LastPrint < 250) then Exit;
  LastPrint := t;
  if Frac < 0 then Frac := 0;
  if Frac > 1 then Frac := 1;
  Write(FormatFloat('0.00', Frac * 100, FS), '% ', Lbl, #13);
  Flush(Output);
end;

{ ---------- struttura ---------- }

function Roundup(V: Int64): Int64;
begin
  Result := ((V + RS_BLOCK - 1) div RS_BLOCK) * RS_BLOCK;
end;

function HeaderSize(D, PB: Int64): Int64;
begin
  Result := Roundup(SizeOf(TRSParams) + 4 * (D + PB) + 4);
end;

function BlockCRC(P: PByte; n: Integer): LongWord;
begin
  Result := crc32(0, P, n);
end;

procedure FillParams(out Par: TRSParams; const Magic: string; N, D: Int64;
  K, P: Integer; G: Int64; Pct: Integer);
begin
  FillChar(Par, SizeOf(Par), 0);
  Move(Magic[1], Par.Magic[0], 8);
  Par.Version := 1;
  Par.BlockSize := RS_BLOCK;
  Par.N := N;
  Par.D := D;
  Par.K := K;
  Par.P := P;
  Par.G := G;
  Par.Pct := Pct;
  Par.HS := HeaderSize(D, Int64(P) * G);
end;

function ParamsSane(const Par: TRSParams; const Magic: string): Boolean;
var
  M: string;
begin
  SetString(M, PChar(@Par.Magic[0]), 8);
  Result := (M = Magic) and (Par.Version = 1) and (Par.BlockSize = RS_BLOCK) and
    (Par.P >= 1) and (Par.K >= 1) and (Par.K + Par.P <= 255) and (Par.G >= 1) and
    (Par.D >= 1) and (Par.D <= $7FFFFFFF) and (Par.G <= Par.D) and
    (Par.HS = QWord(HeaderSize(Par.D, Int64(Par.P) * Par.G)));
end;

{ parametri seguiti da CRC32 (usato dal footer) }
function ReadParamsCRC(S: TStream; Pos: Int64; const Magic: string;
  out Par: TRSParams): Boolean;
var
  buf: array[0..SizeOf(TRSParams) + 3] of Byte;
begin
  Result := False;
  FillChar(Par, SizeOf(Par), 0);
  if (Pos < 0) or (Pos + SizeOf(buf) > S.Size) then Exit;
  S.Position := Pos;
  S.ReadBuffer(buf, SizeOf(buf));
  Move(buf[0], Par, SizeOf(Par));
  if BlockCRC(@buf[0], SizeOf(TRSParams)) <> PLongWord(@buf[SizeOf(TRSParams)])^ then Exit;
  Result := ParamsSane(Par, Magic);
end;

{ legge un'intestazione completa; Table = CRC di tutti i blocchi }
function ReadHeader(S: TStream; Pos: Int64; out Par: TRSParams; out Table: TCRCTable): Boolean;
var
  T, len: Int64;
  buf: PByte;
begin
  Result := False;
  FillChar(Par, SizeOf(Par), 0);
  SetLength(Table, 0);
  if (Pos < 0) or (Pos + SizeOf(TRSParams) > S.Size) then Exit;
  S.Position := Pos;
  S.ReadBuffer(Par, SizeOf(Par));
  if not ParamsSane(Par, MAGIC_HDR) then Exit;
  T := Int64(Par.D) + Int64(Par.P) * Int64(Par.G);
  len := SizeOf(TRSParams) + 4 * T;
  if Pos + len + 4 > S.Size then Exit;
  GetMem(buf, len + 4);
  try
    S.Position := Pos;
    S.ReadBuffer(buf^, len + 4);
    if BlockCRC(buf, len) <> PLongWord(buf + len)^ then Exit;
    SetLength(Table, T);
    Move((buf + SizeOf(TRSParams))^, Table[0], 4 * T);
    Result := True;
  finally
    FreeMem(buf);
  end;
end;

function ParityStart(const Par: TRSParams): Int64;
begin
  Result := Int64(Par.D) * RS_BLOCK + Int64(Par.HS);
end;

function HeaderBPos(const Par: TRSParams): Int64;
begin
  Result := ParityStart(Par) + Int64(Par.P) * Int64(Par.G) * RS_BLOCK;
end;

{ Individua le intestazioni. Quick = solo footer, nessuna scansione. }
function Locate(S: TStream; Quick: Boolean; out Par: TRSParams; out Table: TCRCTable;
  out OkA, OkB, OkF: Boolean): Boolean;
var
  Pf, Pa, Pb: TRSParams;
  Ta, Tb: TCRCTable;
  size, pos: Int64;
  magic: array[0..7] of AnsiChar;
  m: string;
begin
  Result := False;
  OkA := False; OkB := False; OkF := False;
  FillChar(Par, SizeOf(Par), 0);
  size := S.Size;
  if size < 2 * RS_BLOCK then Exit;
  if ReadParamsCRC(S, size - RS_BLOCK, MAGIC_FTR, Pf) then
  begin
    OkF := True;
    Par := Pf;
    OkA := ReadHeader(S, Int64(Pf.D) * RS_BLOCK, Pa, Ta);
    OkB := ReadHeader(S, HeaderBPos(Pf), Pb, Tb);
    if OkA then begin Par := Pa; Table := Ta; end
    else if OkB then begin Par := Pb; Table := Tb; end;
    Result := OkA or OkB;
    if Result or Quick then Exit;
  end;
  if Quick then Exit;
  // footer perso: cerca un'intestazione a ritroso su posizioni allineate
  pos := (size div RS_BLOCK - 1) * RS_BLOCK;
  while pos >= 0 do
  begin
    S.Position := pos;
    if S.Read(magic, 8) = 8 then
    begin
      SetString(m, PChar(@magic[0]), 8);
      if (m = MAGIC_HDR) and ReadHeader(S, pos, Pa, Ta) then
      begin
        Par := Pa;
        Table := Ta;
        OkA := ReadHeader(S, Int64(Pa.D) * RS_BLOCK, Pb, Tb);
        OkB := ReadHeader(S, HeaderBPos(Pa), Pb, Tb);
        Result := True;
        Exit;
      end;
    end;
    Dec(pos, RS_BLOCK);
  end;
end;

function RSDetect(const Path: string; out Info: TRSInfo): Boolean;
var
  F: TFileStream;
  Par: TRSParams;
begin
  Result := False;
  FillChar(Info, SizeOf(Info), 0);
  if not FileExists(Path) then Exit;
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;
  try
    if F.Size >= 2 * RS_BLOCK then
      if ReadParamsCRC(F, F.Size - RS_BLOCK, MAGIC_FTR, Par) then
      begin
        Info.N := Par.N; Info.D := Par.D; Info.G := Par.G;
        Info.K := Par.K; Info.P := Par.P; Info.Pct := Par.Pct; Info.HS := Par.HS;
        Result := True;
      end;
  finally
    F.Free;
  end;
end;

{ ---------- scrittura intestazioni ---------- }

procedure WriteHeaders(F: TStream; const Par: TRSParams; const Table: TCRCTable;
  WriteA, WriteB, WriteF: Boolean);
var
  buf: PByte;
  T, len: Int64;
  Pf: TRSParams;
  c: LongWord;
begin
  T := Length(Table);
  len := SizeOf(TRSParams) + 4 * T;
  GetMem(buf, Par.HS);
  try
    FillChar(buf^, Par.HS, 0);
    Move(Par, buf^, SizeOf(Par));
    if T > 0 then Move(Table[0], (buf + SizeOf(TRSParams))^, 4 * T);
    c := BlockCRC(buf, len);
    PLongWord(buf + len)^ := c;
    if WriteA then
    begin
      F.Position := Int64(Par.D) * RS_BLOCK;
      F.WriteBuffer(buf^, Par.HS);
    end;
    if WriteB then
    begin
      F.Position := HeaderBPos(Par);
      F.WriteBuffer(buf^, Par.HS);
    end;
  finally
    FreeMem(buf);
  end;
  if WriteF then
  begin
    GetMem(buf, RS_BLOCK);
    try
      FillChar(buf^, RS_BLOCK, 0);
      Pf := Par;
      Move(MAGIC_FTR[1], Pf.Magic[0], 8);
      Move(Pf, buf^, SizeOf(Pf));
      PLongWord(buf + SizeOf(Pf))^ := BlockCRC(buf, SizeOf(Pf));
      F.Position := HeaderBPos(Par) + Int64(Par.HS);
      F.WriteBuffer(buf^, RS_BLOCK);
    finally
      FreeMem(buf);
    end;
  end;
end;

{ ---------- rimozione ---------- }

function DoStrip(const Path: string): Boolean;
var
  F: TFileStream;
  Par: TRSParams;
  T: TCRCTable;
  a, b, c: Boolean;
begin
  Result := False;
  F := TFileStream.Create(Path, fmOpenReadWrite or fmShareDenyWrite);
  try
    // solo footer (veloce): un archivio normale non va scandito per intero
    Locate(F, True, Par, T, a, b, c);
    if c and (Par.N > 0) and (Int64(Par.N) <= F.Size) then
    begin
      F.Size := Par.N;
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

{ ---------- creazione ---------- }

function DoCreate(const Path: string; Pct: Integer): Integer;
var
  F: TFileStream;
  Par: TRSParams;
  N, D, G, PB, Tn, PS, L, i0, gb, done, i, q: Int64;
  K, P, Pd, p1, j, t, n1, cnt, Gb2: Integer;
  r: Double;
  Table: TCRCTable;
  acc, rowbuf, blk: PByte;
  coefs: array of Byte;
  zero: array[0..RS_BLOCK - 1] of Byte;
  T0: QWord;
begin
  Result := 2;
  InitGF;
  T0 := GetTickCount64;
  if Pct < 1 then Pct := 1;
  if Pct > 50 then Pct := 50;
  // se esiste gia un blocco di recupero lo si sostituisce
  DoStrip(Path);
  F := TFileStream.Create(Path, fmOpenReadWrite or fmShareDenyWrite);
  try
    N := F.Size;
    if N = 0 then
    begin
      Say(Tr('ERROR: file vuoto.'));
      Exit;
    end;
    D := (N + RS_BLOCK - 1) div RS_BLOCK;
    L := D * RS_BLOCK;
    r := Pct / 100;
    P := Trunc(255 * r / (1 + r) + 0.999999);
    Pd := Trunc(D * Pct / 100 + 0.999999);
    if Pd < 1 then Pd := 1;
    if Pd < P then P := Pd;
    if P < 1 then P := 1;
    K := 255 - P;
    G := (D + K - 1) div K;
    PB := Int64(P) * G;
    Tn := D + PB;
    FillParams(Par, MAGIC_HDR, N, D, K, P, G, Pct);
    PS := L + Par.HS;
    SetLength(Table, Tn);
    SetLength(coefs, P * K);
    for p1 := 0 to P - 1 do
      for j := 0 to K - 1 do
        coefs[p1 * K + j] := Coef(K, p1, j);

    // zeri di riempimento fino al multiplo del blocco
    FillChar(zero, SizeOf(zero), 0);
    if L > N then
    begin
      F.Position := N;
      F.WriteBuffer(zero, L - N);
    end;

    Gb2 := MEM_BUDGET div (P * RS_BLOCK);
    if Gb2 < 1 then Gb2 := 1;
    if Gb2 > G then Gb2 := G;
    GetMem(acc, Int64(P) * Gb2 * RS_BLOCK);
    GetMem(rowbuf, Int64(Gb2) * RS_BLOCK);
    try
      done := 0;
      gb := 0;
      while gb < G do
      begin
        cnt := Gb2;
        if gb + cnt > G then cnt := G - gb;
        FillChar(acc^, Int64(P) * cnt * RS_BLOCK, 0);
        for j := 0 to K - 1 do
        begin
          i0 := Int64(j) * G + gb;
          if i0 >= D then Break;
          n1 := cnt;
          if i0 + n1 > D then n1 := D - i0;
          F.Position := i0 * RS_BLOCK;
          F.ReadBuffer(rowbuf^, Int64(n1) * RS_BLOCK);
          for t := 0 to n1 - 1 do
          begin
            blk := rowbuf + Int64(t) * RS_BLOCK;
            Table[i0 + t] := BlockCRC(blk, RS_BLOCK);
            for p1 := 0 to P - 1 do
              MulAdd(acc + (Int64(p1) * cnt + t) * RS_BLOCK, blk, RS_BLOCK,
                @GFMul[coefs[p1 * K + j]][0]);
          end;
          Inc(done, n1);
          Progress(done / D, Tr('dati di recupero: calcolo'));
        end;
        for p1 := 0 to P - 1 do
        begin
          q := Int64(p1) * G + gb;
          F.Position := PS + q * RS_BLOCK;
          F.WriteBuffer((acc + Int64(p1) * cnt * RS_BLOCK)^, Int64(cnt) * RS_BLOCK);
          for t := 0 to cnt - 1 do
            Table[D + q + t] := BlockCRC(acc + (Int64(p1) * cnt + t) * RS_BLOCK, RS_BLOCK);
        end;
        Inc(gb, cnt);
      end;
    finally
      FreeMem(acc);
      FreeMem(rowbuf);
    end;
    Progress(1, Tr('dati di recupero: scrittura intestazioni'), True);
    WriteHeaders(F, Par, Table, True, True, True);
  finally
    F.Free;
  end;
  Say('');
  Say(Format(Tr('Dati di recupero creati: %d blocchi di parita per %d blocchi dati (%d%%), ') +
    Tr('gruppi: %d, tempo: %d s.'), [PB, D, Pct, G, (GetTickCount64 - T0) div 1000]));
  Result := 0;
end;

{ ---------- verifica / riparazione ---------- }

procedure ScanBlocks(F: TFileStream; const Par: TRSParams; const Table: TCRCTable;
  var Bad: TBadMap; out nBadD, nBadP: Int64; const Lbl: string);
const
  CH = 256;
var
  buf: PByte;
  D, PB, Tn, PS, i, got: Int64;
  n, t: Integer;
begin
  D := Par.D;
  PB := Int64(Par.P) * Par.G;
  Tn := D + PB;
  PS := ParityStart(Par);
  SetLength(Bad, Tn);
  FillChar(Bad[0], Tn, 0);
  nBadD := 0;
  nBadP := 0;
  GetMem(buf, CH * RS_BLOCK);
  try
    i := 0;
    while i < Tn do
    begin
      // i indice globale: 0..D-1 dati, D..Tn-1 parita
      n := CH;
      if i < D then
      begin
        if i + n > D then n := D - i;
        F.Position := i * RS_BLOCK;
      end
      else
      begin
        if i + n > Tn then n := Tn - i;
        F.Position := PS + (i - D) * RS_BLOCK;
      end;
      got := F.Read(buf^, Int64(n) * RS_BLOCK);
      for t := 0 to n - 1 do
        if ((t + 1) * Int64(RS_BLOCK) > got) or
           (BlockCRC(buf + Int64(t) * RS_BLOCK, RS_BLOCK) <> Table[i + t]) then
        begin
          Bad[i + t] := 1;
          if i + t < D then Inc(nBadD) else Inc(nBadP);
        end;
      Inc(i, n);
      Progress(i / Tn, Lbl);
    end;
  finally
    FreeMem(buf);
  end;
end;

{ matrice e x e su GF(256): inversione di Gauss-Jordan; False se singolare }
function InvertMatrix(var M: array of Byte; e: Integer): Boolean;
var
  aug: array of Byte;
  w, c, r, k2, piv: Integer;
  f, iv: Integer;
  tmp: Byte;
begin
  Result := False;
  w := 2 * e;
  SetLength(aug, e * w);
  FillChar(aug[0], e * w, 0);
  for r := 0 to e - 1 do
  begin
    for c := 0 to e - 1 do aug[r * w + c] := M[r * e + c];
    aug[r * w + e + r] := 1;
  end;
  for c := 0 to e - 1 do
  begin
    piv := -1;
    for r := c to e - 1 do
      if aug[r * w + c] <> 0 then begin piv := r; Break; end;
    if piv < 0 then Exit;
    if piv <> c then
      for k2 := 0 to w - 1 do
      begin
        tmp := aug[c * w + k2];
        aug[c * w + k2] := aug[piv * w + k2];
        aug[piv * w + k2] := tmp;
      end;
    iv := GFInv(aug[c * w + c]);
    for k2 := 0 to w - 1 do aug[c * w + k2] := GFMul[iv, aug[c * w + k2]];
    for r := 0 to e - 1 do
      if (r <> c) and (aug[r * w + c] <> 0) then
      begin
        f := aug[r * w + c];
        for k2 := 0 to w - 1 do
          aug[r * w + k2] := aug[r * w + k2] xor GFMul[f, aug[c * w + k2]];
      end;
  end;
  for r := 0 to e - 1 do
    for c := 0 to e - 1 do M[r * e + c] := aug[r * w + e + c];
  Result := True;
end;

function RepairGroup(F: TFileStream; const Par: TRSParams; const Table: TCRCTable;
  grp: Int64; const Bad: TBadMap): Boolean;
var
  K, P, j, p1, e, s, t, nAvail: Integer;
  D, G, PS, i, q: Int64;
  blk, rhs: PByte;
  miss: array of Boolean;
  md, sp: array of Integer;
  M: array of Byte;
begin
  Result := False;
  K := Par.K; P := Par.P; D := Par.D; G := Par.G;
  PS := ParityStart(Par);
  GetMem(blk, Int64(K + P) * RS_BLOCK);
  rhs := nil;
  try
    FillChar(blk^, Int64(K + P) * RS_BLOCK, 0);
    SetLength(miss, K + P);
    SetLength(md, K);
    e := 0;
    for j := 0 to K - 1 do
    begin
      miss[j] := False;
      i := Int64(j) * G + grp;
      if i >= D then Continue;
      if Bad[i] <> 0 then
      begin
        miss[j] := True;
        md[e] := j;
        Inc(e);
      end
      else
      begin
        F.Position := i * RS_BLOCK;
        F.ReadBuffer((blk + Int64(j) * RS_BLOCK)^, RS_BLOCK);
      end;
    end;
    nAvail := 0;
    SetLength(sp, P);
    for p1 := 0 to P - 1 do
    begin
      q := Int64(p1) * G + grp;
      miss[K + p1] := Bad[D + q] <> 0;
      if not miss[K + p1] then
      begin
        F.Position := PS + q * RS_BLOCK;
        F.ReadBuffer((blk + Int64(K + p1) * RS_BLOCK)^, RS_BLOCK);
        sp[nAvail] := p1;
        Inc(nAvail);
      end;
    end;
    if e > nAvail then Exit;

    if e > 0 then
    begin
      SetLength(M, e * e);
      for s := 0 to e - 1 do
        for t := 0 to e - 1 do
          M[s * e + t] := Coef(K, sp[s], md[t]);
      if not InvertMatrix(M, e) then Exit;
      GetMem(rhs, Int64(e) * RS_BLOCK);
      for s := 0 to e - 1 do
      begin
        Move((blk + Int64(K + sp[s]) * RS_BLOCK)^, (rhs + Int64(s) * RS_BLOCK)^, RS_BLOCK);
        for j := 0 to K - 1 do
          if (not miss[j]) and (Int64(j) * G + grp < D) then
            MulAdd(rhs + Int64(s) * RS_BLOCK, blk + Int64(j) * RS_BLOCK, RS_BLOCK,
              @GFMul[Coef(K, sp[s], j)][0]);
      end;
      for t := 0 to e - 1 do
        for s := 0 to e - 1 do
          MulAdd(blk + Int64(md[t]) * RS_BLOCK, rhs + Int64(s) * RS_BLOCK, RS_BLOCK,
            @GFMul[M[t * e + s]][0]);
      for t := 0 to e - 1 do
        if BlockCRC(blk + Int64(md[t]) * RS_BLOCK, RS_BLOCK) <> Table[Int64(md[t]) * G + grp] then
          Exit;
    end;
    // parita mancanti: si ricalcolano da tutti i dati
    for p1 := 0 to P - 1 do
      if miss[K + p1] then
      begin
        FillChar((blk + Int64(K + p1) * RS_BLOCK)^, RS_BLOCK, 0);
        for j := 0 to K - 1 do
          if Int64(j) * G + grp < D then
            MulAdd(blk + Int64(K + p1) * RS_BLOCK, blk + Int64(j) * RS_BLOCK, RS_BLOCK,
              @GFMul[Coef(K, p1, j)][0]);
        q := Int64(p1) * G + grp;
        if BlockCRC(blk + Int64(K + p1) * RS_BLOCK, RS_BLOCK) <> Table[D + q] then Exit;
      end;
    // scrittura dei blocchi ricostruiti
    for t := 0 to e - 1 do
    begin
      F.Position := (Int64(md[t]) * G + grp) * RS_BLOCK;
      F.WriteBuffer((blk + Int64(md[t]) * RS_BLOCK)^, RS_BLOCK);
    end;
    for p1 := 0 to P - 1 do
      if miss[K + p1] then
      begin
        F.Position := PS + (Int64(p1) * G + grp) * RS_BLOCK;
        F.WriteBuffer((blk + Int64(K + p1) * RS_BLOCK)^, RS_BLOCK);
      end;
    Result := True;
  finally
    FreeMem(blk);
    if rhs <> nil then FreeMem(rhs);
  end;
end;

{ Mode: 0 = verifica, 1 = ripara }
function DoVerifyRepair(const Path: string; Repair: Boolean): Integer;
var
  F: TFileStream;
  Par: TRSParams;
  Table: TCRCTable;
  Bad: TBadMap;
  okA, okB, okF: Boolean;
  nD, nP, i, q, G, D: Int64;
  gcount: array of Integer;
  gi, nGroupsBad, nUnrec, nFixed, doneG: Int64;
  P: Integer;
begin
  Result := 2;
  InitGF;
  F := TFileStream.Create(Path, fmOpenReadWrite or fmShareDenyWrite);
  try
    if not Locate(F, False, Par, Table, okA, okB, okF) then
    begin
      Say(Tr('ERROR: dati di recupero non trovati o intestazioni illeggibili.'));
      Exit;
    end;
    D := Par.D; G := Par.G; P := Par.P;
    ScanBlocks(F, Par, Table, Bad, nD, nP, Tr('verifica blocchi'));
    SetLength(gcount, G);
    for i := 0 to D - 1 do
      if Bad[i] <> 0 then Inc(gcount[i mod G]);
    for q := 0 to Int64(P) * G - 1 do
      if Bad[D + q] <> 0 then Inc(gcount[q mod G]);
    nGroupsBad := 0;
    nUnrec := 0;
    for gi := 0 to G - 1 do
      if gcount[gi] > 0 then
      begin
        Inc(nGroupsBad);
        if gcount[gi] > P then Inc(nUnrec);
      end;
    Say('');
    Say(Format(Tr('Blocchi dati danneggiati: %d su %d'), [nD, D]));
    Say(Format(Tr('Blocchi di parita danneggiati: %d su %d'), [nP, Int64(P) * G]));
    Say(Format(Tr('Gruppi con danni: %d, non recuperabili: %d'), [nGroupsBad, nUnrec]));
    if not (okA and okB and okF) then
      if Repair then
        Say(Tr('Intestazioni dei dati di recupero parzialmente danneggiate (verranno ripristinate).'))
      else
        Say(Tr('Intestazioni dei dati di recupero parzialmente danneggiate.'));

    if not Repair then
    begin
      if (nD + nP = 0) and okA and okB and okF then
      begin
        Say(Tr('Archivio integro.'));
        Result := 0;
      end
      else if nUnrec = 0 then
      begin
        Say(Tr('Danni riparabili con i dati di recupero.'));
        Result := 1;
      end
      else
      begin
        Say(Tr('Danni NON interamente riparabili.'));
        Result := 2;
      end;
      Exit;
    end;

    nFixed := 0;
    doneG := 0;
    for gi := 0 to G - 1 do
      if gcount[gi] > 0 then
      begin
        if gcount[gi] <= P then
        begin
          if RepairGroup(F, Par, Table, gi, Bad) then Inc(nFixed)
          else Inc(nUnrec);
        end;
        Inc(doneG);
        Progress(doneG / nGroupsBad, 'riparazione');
      end;
    // intestazioni e footer
    WriteHeaders(F, Par, Table, not okA, not okB, not okF);
    // le intestazioni valide non vanno riscritte, ma il footer si
    Say('');
    Say(Format(Tr('Gruppi riparati: %d'), [nFixed]));
    if nUnrec > 0 then
    begin
      // il conteggio include i gruppi con troppi danni
      Say(Format(Tr('Gruppi NON riparabili: %d'), [nUnrec]));
      Result := 2;
    end
    else
    begin
      Say('Everything is Ok');
      Result := 0;
    end;
  finally
    F.Free;
  end;
end;

function DoInfo(const Path: string): Integer;
var
  Info: TRSInfo;
begin
  if RSDetect(Path, Info) then
  begin
    Say(Format(Tr('Dati di recupero in coda: %d%% (%d blocchi dati, gruppi da %d+%d, ') +
      Tr('archivio originale %d byte)'), [Info.Pct, Info.D, Info.K, Info.P, Info.N]));
    Result := 0;
  end
  else
  begin
    Say(Tr('Nessun dato di recupero in coda.'));
    Result := 2;
  end;
end;

function RunRecoveryCLI: Integer;
var
  cmd, path: string;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  cmd := ParamStr(1);
  path := ParamStr(2);
  Result := 2;
  try
    if cmd = '--rs-create' then
      Result := DoCreate(path, StrToIntDef(ParamStr(3), 5))
    else if cmd = '--rs-verify' then
      Result := DoVerifyRepair(path, False)
    else if cmd = '--rs-repair' then
      Result := DoVerifyRepair(path, True)
    else if cmd = '--rs-strip' then
    begin
      if DoStrip(path) then Say(Tr('Dati di recupero rimossi.'))
      else Say(Tr('Nessun dato di recupero da rimuovere.'));
      Result := 0;
    end
    else if cmd = '--rs-info' then
      Result := DoInfo(path)
    else
      Say(Tr('ERROR: comando sconosciuto ') + cmd);
  except
    on E: Exception do
    begin
      Say('ERROR: ' + E.Message);
      Result := 2;
    end;
  end;
end;

end.
