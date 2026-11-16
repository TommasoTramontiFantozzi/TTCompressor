unit szrun;

{ Esecuzione di 7z in un thread, con lettura continua dell'output e
  interpretazione della percentuale di avanzamento.

  Il 7z fornito stampa la percentuale ("NN.N% [n] + nomefile") separando gli
  aggiornamenti con backspace; qui ogni token delimitato da #8, #13 o #10 viene
  analizzato e, se inizia con un numero seguito da '%', aggiorna lo stato. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, BaseUnix, SyncObjs;

type
  TArcJob = class(TThread)
  private
    FLock: TCriticalSection;
    FProc: TProcess;
    FExe: string;
    FParams: TStringList;
    FWorkDir: string;
    FParse: Boolean;
    FKeepAll: Boolean;
    FRaw: TMemoryStream;   // KeepAll: righe di dati dell'elenco, senza una stringa per riga
    FPart: string;
    FPercent: Double;
    FPercText: string;
    FHasPercent: Boolean;
    FCurFile: string;
    FLastChange: QWord;
    FTokens: QWord;
    FLines: TStringList;
    FExitCode: Integer;
    FMarkCode: Integer;
    FFinished: Boolean;
    FCancelled: Boolean;
    FStarted: QWord;
    FError: string;
    procedure Feed(const Buf; Count: Integer);
    procedure FeedKeep(const Buf; Count: Integer);
    procedure KeepLine(P: PChar; Len: Integer);
    procedure Token(const S: string);
    procedure ParseProgress(const T: string);
  protected
    procedure Execute; override;
  public
    { Parse = True : modalita "operazione" (progress + log dei messaggi);
      Parse = False: modalita "cattura" (righe grezze, spezzate solo su #10). }
    constructor Create(const AExe: string; AParams: TStrings;
      const AWorkDir: string; AParse: Boolean);
    destructor Destroy; override;
    procedure Cancel;
    procedure GetState(out Percent: Double; out PercText: string;
      out HasPercent: Boolean; out CurFile: string; out SinceChange: QWord;
      out Elapsed: QWord);
    { Da chiamare solo a job terminato }
    procedure CopyLines(Dest: TStrings);
    { KeepAll: il testo delle righe di dati (Path = ... ecc.), da chiamare a job terminato }
    function RawText: string;
    property Finished: Boolean read FFinished;
    property Cancelled: Boolean read FCancelled;
    property ExitCode: Integer read FExitCode;
    property ErrorMsg: string read FError;
    { Con Parse = True: tiene tutte le righe (senza limite e senza Trim) e
      spezza solo su #10; le righe di sola percentuale aggiornano lo stato.
      Serve per gli elenchi: avanzamento + output completo. }
    property KeepAll: Boolean read FKeepAll write FKeepAll;
  end;

{ Quoting per la shell POSIX }
function ShQuote(const S: string): string;

implementation

function ShQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
end;

constructor TArcJob.Create(const AExe: string; AParams: TStrings;
  const AWorkDir: string; AParse: Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FLock := TCriticalSection.Create;
  FParams := TStringList.Create;
  FParams.Assign(AParams);
  FLines := TStringList.Create;
  FRaw := TMemoryStream.Create;
  FExe := AExe;
  FWorkDir := AWorkDir;
  FParse := AParse;
  FStarted := GetTickCount64;
  FLastChange := FStarted;
  FExitCode := -1;
  FMarkCode := -1;
end;

destructor TArcJob.Destroy;
begin
  FProc.Free;
  FParams.Free;
  FLines.Free;
  FRaw.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TArcJob.Cancel;
begin
  FCancelled := True;
  if (FProc <> nil) and FProc.Running then
  begin
    // il processo e capogruppo (poNewProcessGroup): termina anche la pipeline
    FpKill(-FProc.ProcessID, SIGTERM);
    FpKill(FProc.ProcessID, SIGTERM);
  end;
end;

procedure TArcJob.GetState(out Percent: Double; out PercText: string;
  out HasPercent: Boolean; out CurFile: string; out SinceChange: QWord;
  out Elapsed: QWord);
var
  nowT: QWord;
begin
  nowT := GetTickCount64;
  FLock.Enter;
  try
    Percent := FPercent;
    PercText := FPercText;
    HasPercent := FHasPercent;
    CurFile := FCurFile;
    SinceChange := nowT - FLastChange;
    Elapsed := nowT - FStarted;
  finally
    FLock.Leave;
  end;
end;

procedure TArcJob.CopyLines(Dest: TStrings);
begin
  FLock.Enter;
  try
    Dest.Assign(FLines);
  finally
    FLock.Leave;
  end;
end;

function TArcJob.RawText: string;
begin
  SetString(Result, PChar(FRaw.Memory), FRaw.Size);
end;

{ true se la riga e una riga di dati di "7z l -slt -slc" }
function IsDataLine(P: PChar; Len: Integer): Boolean;
  function Has(const K: string): Boolean;
  begin
    Result := (Len >= Length(K)) and (CompareByte(P^, K[1], Length(K)) = 0);
  end;
begin
  case P[0] of
    'P': Result := Has('Path = ') or Has('Packed Size = ');
    'S': Result := Has('Size = ');
    'M': Result := Has('Modified = ');
    'A': Result := Has('Attributes = ');
    'B': Result := Has('Block = ');
    'F': Result := Has('Folder = ');
  else
    Result := False;
  end;
end;

procedure TArcJob.KeepLine(P: PChar; Len: Integer);
var
  S, T: string;
  i: Integer;
  NL: Byte;
begin
  NL := 10;
  if Len = 0 then
  begin
    FRaw.WriteBuffer(NL, 1);
    Exit;
  end;
  if IsDataLine(P, Len) then
  begin
    FRaw.WriteBuffer(P^, Len);
    FRaw.WriteBuffer(NL, 1);
    Exit;
  end;
  SetString(S, P, Len);
  if P[0] in ['0'..'9', ' '] then
  begin
    T := Trim(S);
    i := 1;
    while (i <= Length(T)) and (T[i] in ['0'..'9', '.']) do Inc(i);
    if (i > 1) and (i <= Length(T)) and (T[i] = '%') then
    begin
      ParseProgress(T);
      Exit;
    end;
  end;
  Token(S);
end;

procedure TArcJob.FeedKeep(const Buf; Count: Integer);
var
  P: PChar;
  ls, le: Integer;
  S: string;
begin
  P := @Buf;
  ls := 0;
  while ls < Count do
  begin
    le := IndexByte(P[ls], Count - ls, 10);
    if le < 0 then
    begin
      SetString(S, P + ls, Count - ls);
      FPart := FPart + S;
      Exit;
    end;
    le := ls + le;
    if FPart <> '' then
    begin
      SetString(S, P + ls, le - ls);
      S := FPart + S;
      FPart := '';
      if S = '' then KeepLine(nil, 0) else KeepLine(PChar(S), Length(S));
    end
    else
      KeepLine(P + ls, le - ls);
    ls := le + 1;
  end;
end;

procedure TArcJob.ParseProgress(const T: string);
var
  p, q: Integer;
  numS, rest: string;
  v: Double;
  fs: TFormatSettings;
begin
  // T inizia con cifre e '.' fino a '%'
  p := Pos('%', T);
  numS := Copy(T, 1, p - 1);
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(numS, v, fs) then
    Exit;
  rest := Trim(Copy(T, p + 1, MaxInt));
  // opzionale: numero di file elaborati
  q := 1;
  while (q <= Length(rest)) and (rest[q] in ['0'..'9']) do Inc(q);
  if (q > 1) and ((q > Length(rest)) or (rest[q] = ' ')) then
    rest := Trim(Copy(rest, q, MaxInt));
  // opzionale: operazione (+ - = U R . ...)
  if (Length(rest) >= 2) and (rest[2] = ' ') and (rest[1] in ['+', '-', '=', 'U', 'R', '.', '!', 'T', 'D', 'A']) then
    rest := Copy(rest, 3, MaxInt);
  FLock.Enter;
  try
    if (not FHasPercent) or (v <> FPercent) then
      FLastChange := GetTickCount64;
    FPercent := v;
    FPercText := numS;
    FHasPercent := True;
    if rest <> '' then FCurFile := rest;
    Inc(FTokens);
  finally
    FLock.Leave;
  end;
end;

procedure TArcJob.Token(const S: string);
var
  T: string;
  i: Integer;
begin
  // il wrapper sh stampa il codice di uscita reale del programma
  if Pos('__LZEXIT__=', S) = 1 then
  begin
    FMarkCode := StrToIntDef(Trim(Copy(S, 12, MaxInt)), -1);
    Exit;
  end;
  if FKeepAll then
  begin
    if (S <> '') and (S[1] in ['0'..'9', ' ']) then
    begin
      T := Trim(S);
      i := 1;
      while (i <= Length(T)) and (T[i] in ['0'..'9', '.']) do Inc(i);
      if (i > 1) and (i <= Length(T)) and (T[i] = '%') then
      begin
        ParseProgress(T);
        Exit;
      end;
    end;
    FLock.Enter;
    try
      FLines.Add(S);
    finally
      FLock.Leave;
    end;
    Exit;
  end;
  if not FParse then
  begin
    FLock.Enter;
    try
      FLines.Add(S);
    finally
      FLock.Leave;
    end;
    Exit;
  end;
  T := Trim(S);
  if T = '' then Exit;
  // formato di par2: 'Constructing: 12.5%' / 'Repairing: 40.0%'
  if (T[Length(T)] = '%') and (T[1] in ['A'..'Z', 'a'..'z']) then
  begin
    i := Length(T) - 1;
    while (i >= 1) and (T[i] in ['0'..'9', '.']) do Dec(i);
    if (i >= 1) and (i < Length(T) - 1) and (T[i] in [' ', ':']) then
    begin
      ParseProgress(Copy(T, i + 1, MaxInt) + ' ' + Trim(StringReplace(Copy(T, 1, i), ':', '', [rfReplaceAll])));
      Exit;
    end;
  end;
  i := 1;
  while (i <= Length(T)) and (T[i] in ['0'..'9', '.']) do Inc(i);
  if (i > 1) and (i <= Length(T)) and (T[i] = '%') then
  begin
    ParseProgress(T);
    Exit;
  end;
  FLock.Enter;
  try
    if FLines.Count < 5000 then FLines.Add(T);
  finally
    FLock.Leave;
  end;
end;

procedure TArcJob.Feed(const Buf; Count: Integer);
var
  P: PChar;
  i, st: Integer;
  c: Char;
  split8: Boolean;
  S: string;
begin
  if FKeepAll then
  begin
    FeedKeep(Buf, Count);
    Exit;
  end;
  P := @Buf;
  st := 0;
  split8 := FParse and not FKeepAll;
  for i := 0 to Count - 1 do
  begin
    c := P[i];
    if (c = #10) or (split8 and ((c = #8) or (c = #13))) then
    begin
      if i > st then
      begin
        SetString(S, P + st, i - st);
        if FPart <> '' then S := FPart + S;
      end
      else
        S := FPart;
      FPart := '';
      Token(S);
      st := i + 1;
    end;
  end;
  if st < Count then
  begin
    SetString(S, P + st, Count - st);
    FPart := FPart + S;
  end;
end;

procedure TArcJob.Execute;
var
  Buf: array[0..65535] of Byte;
  n: LongInt;
begin
  try
    FProc := TProcess.Create(nil);
    // Il codice di uscita restituito da TProcess non e affidabile in questa
    // applicazione: lo si ricava da un marcatore stampato da sh.
    FProc.Executable := '/bin/sh';
    FProc.Parameters.Add('-c');
    FProc.Parameters.Add('"$@"; r=$?; echo; echo "__LZEXIT__=$r"');
    FProc.Parameters.Add('lz');
    FProc.Parameters.Add(FExe);
    FProc.Parameters.AddStrings(FParams);
    if FWorkDir <> '' then FProc.CurrentDirectory := FWorkDir;
    FProc.Options := [poUsePipes, poStderrToOutput, poNewProcessGroup];
    FProc.Execute;
    FProc.CloseInput;  // nessun prompt interattivo: 7z riceve EOF
    repeat
      n := FProc.Output.Read(Buf, SizeOf(Buf));
      if n > 0 then Feed(Buf, n);
    until n <= 0;
    if FPart <> '' then
    begin
      if FKeepAll then KeepLine(PChar(FPart), Length(FPart)) else Token(FPart);
    end;
    FProc.WaitOnExit;
    if FMarkCode >= 0 then FExitCode := FMarkCode else FExitCode := FProc.ExitCode;
  except
    on E: Exception do
    begin
      FError := E.Message;
      FExitCode := 255;
    end;
  end;
  FFinished := True;
end;

end.
