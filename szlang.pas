unit szlang;

{ Traduzione dell'interfaccia. Il testo nel codice e in italiano; se la lingua
  di sistema non e l'italiano, Tr() restituisce la versione inglese presa dalla
  tabella (szlang_en.inc). Una stringa non presente nella tabella resta com'e.
  Si puo forzare la lingua con la variabile d'ambiente TTCOMPRESSOR_LANG (it / en). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Menus, ComCtrls, Dialogs;

{ Traduce una stringa italiana (se la lingua e inglese) }
function Tr(const It: string): string;
{ True se l'interfaccia va mostrata in inglese }
function UseEnglish: Boolean;
{ Traduce didascalie, suggerimenti e titoli dei componenti definiti nel .lfm }
procedure TranslateComponent(C: TComponent);

implementation

var
  FDict: TStringList;
  FEn: array of string;
  FInit: Boolean;
  FEnglish: Boolean;

procedure Add(const It, En: string);
var
  n: Integer;
begin
  n := Length(FEn);
  SetLength(FEn, n + 1);
  FEn[n] := En;
  FDict.AddObject(It, TObject(PtrInt(n)));
end;

{$I szlang_en.inc}

function LangIsItalian: Boolean;
var
  v: string;
begin
  v := LowerCase(GetEnvironmentVariable('TTCOMPRESSOR_LANG'));
  if v <> '' then Exit(Copy(v, 1, 2) = 'it');
  v := GetEnvironmentVariable('LC_ALL');
  if v = '' then v := GetEnvironmentVariable('LC_MESSAGES');
  if v = '' then v := GetEnvironmentVariable('LANG');
  v := LowerCase(v);
  if (v = '') or (v = 'c') or (v = 'posix') then Exit(False);
  // LANGUAGE (elenco separato da ':') ha la precedenza se impostata
  if GetEnvironmentVariable('LANGUAGE') <> '' then
  begin
    v := LowerCase(GetEnvironmentVariable('LANGUAGE'));
    if Pos(':', v) > 0 then v := Copy(v, 1, Pos(':', v) - 1);
  end;
  Result := Copy(v, 1, 2) = 'it';
end;

procedure Init;
begin
  if FInit then Exit;
  FInit := True;
  FEnglish := not LangIsItalian;
  if FEnglish then
  begin
    FDict := TStringList.Create;
    FDict.CaseSensitive := True;
    FDict.Sorted := False;
    LoadTable;
    FDict.Sorted := True;
  end;
end;

function UseEnglish: Boolean;
begin
  Init;
  Result := FEnglish;
end;

function Tr(const It: string): string;
var
  i: Integer;
begin
  Init;
  Result := It;
  if (not FEnglish) or (It = '') then Exit;
  i := FDict.IndexOf(It);
  if i >= 0 then Result := FEn[PtrInt(FDict.Objects[i])];
end;

{ Traduce ogni segmento di un filtro "Etichetta|*.ext|Etichetta|*.ext" }
function TrFilter(const F: string): string;
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    L.Delimiter := '|';
    L.StrictDelimiter := True;
    L.DelimitedText := F;
    for i := 0 to L.Count - 1 do
      L[i] := Tr(L[i]);
    Result := L.DelimitedText;
  finally
    L.Free;
  end;
end;

procedure TranslateComponent(C: TComponent);
var
  i: Integer;
  K: TComponent;
begin
  Init;
  if not FEnglish then Exit;
  for i := 0 to C.ComponentCount - 1 do
  begin
    K := C.Components[i];
    if K is TMenuItem then
      TMenuItem(K).Caption := Tr(TMenuItem(K).Caption)
    else if K is TToolButton then
      TToolButton(K).Hint := Tr(TToolButton(K).Hint)
    else if K is TOpenDialog then
    begin
      TOpenDialog(K).Title := Tr(TOpenDialog(K).Title);
      TOpenDialog(K).Filter := TrFilter(TOpenDialog(K).Filter);
    end
    else if K is TSelectDirectoryDialog then
      TSelectDirectoryDialog(K).Title := Tr(TSelectDirectoryDialog(K).Title)
    else if K is TControl then
    begin
      TControl(K).Hint := Tr(TControl(K).Hint);
      TControl(K).Caption := Tr(TControl(K).Caption);
    end;
    TranslateComponent(K);
  end;
end;

end.
