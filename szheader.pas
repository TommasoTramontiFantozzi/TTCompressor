unit szheader;

{ Intestazione di colonne disegnata e gestita direttamente (senza l'header di
  VirtualTreeView, che si disegna e ridimensiona in modo diverso da un sistema
  all'altro). La colonna 0 occupa lo spazio che resta; il bordo destro di una
  colonna i >= 1 ridimensiona quella colonna, il bordo della colonna 0 sposta
  il confine con la colonna 1. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Types, LCLType;

type
  TSzHeaderClick = procedure(Sender: TObject; Column: Integer) of object;

  TSzHeader = class(TCustomControl)
  private
    FTitles: TStringList;
    FWidths: array of Integer;   // la larghezza della colonna 0 e calcolata
    FRight: array of Boolean;
    FSortCol: Integer;
    FSortAsc: Boolean;
    FEdge: Integer;              // spazio a destra non occupato (barra di scorrimento)
    FMinW: Integer;
    FDragCol: Integer;           // confine in trascinamento (colonna a sinistra del bordo)
    FDragX: Integer;
    FDragW0, FDragW1: Integer;
    FPressCol: Integer;
    FHotCol: Integer;
    FOnClickCol: TSzHeaderClick;
    FOnChanged: TNotifyEvent;
    function GetCount: Integer;
    function GetWidth(i: Integer): Integer;
    procedure SetWidth(i: Integer; V: Integer);
    procedure SetEdge(V: Integer);
    procedure Normalize;
    function ColLeft(i: Integer): Integer;
    function ColAt(X: Integer): Integer;
    function DividerAt(X: Integer): Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddColumn(const Title: string; W: Integer; RightAligned: Boolean);
    procedure SetSort(Col: Integer; Asc: Boolean);
    property Count: Integer read GetCount;
    property Widths[i: Integer]: Integer read GetWidth write SetWidth;
    property Edge: Integer read FEdge write SetEdge;
    property OnColumnClick: TSzHeaderClick read FOnClickCol write FOnClickCol;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

const
  GRIP = 4;

constructor TSzHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTitles := TStringList.Create;
  FSortCol := -1;
  FSortAsc := True;
  FMinW := 40;
  FDragCol := -1;
  FPressCol := -1;
  FHotCol := -1;
  ControlStyle := ControlStyle + [csOpaque];
  Height := 24;
  Align := alTop;
end;

destructor TSzHeader.Destroy;
begin
  FTitles.Free;
  inherited Destroy;
end;

function TSzHeader.GetCount: Integer;
begin
  Result := FTitles.Count;
end;

function TSzHeader.GetWidth(i: Integer): Integer;
begin
  Result := FWidths[i];
end;

procedure TSzHeader.AddColumn(const Title: string; W: Integer; RightAligned: Boolean);
begin
  FTitles.Add(Title);
  SetLength(FWidths, FTitles.Count);
  SetLength(FRight, FTitles.Count);
  FWidths[FTitles.Count - 1] := W;
  FRight[FTitles.Count - 1] := RightAligned;
  Normalize;
  Invalidate;
end;

{ Riporta le larghezze in modo che la colonna 0 riempia lo spazio disponibile. }
procedure TSzHeader.Normalize;
var
  i, rest, avail, over: Integer;
begin
  if Length(FWidths) = 0 then Exit;
  avail := ClientWidth - FEdge;
  rest := 0;
  for i := 1 to High(FWidths) do
  begin
    if FWidths[i] < FMinW then FWidths[i] := FMinW;
    Inc(rest, FWidths[i]);
  end;
  // se non c'e spazio per la colonna 0, restringi le altre da destra
  over := rest + FMinW - avail;
  i := High(FWidths);
  while (over > 0) and (i >= 1) do
  begin
    if FWidths[i] > FMinW then
    begin
      if FWidths[i] - FMinW >= over then
      begin
        Dec(FWidths[i], over);
        over := 0;
      end
      else
      begin
        Dec(over, FWidths[i] - FMinW);
        FWidths[i] := FMinW;
      end;
    end;
    Dec(i);
  end;
  rest := 0;
  for i := 1 to High(FWidths) do Inc(rest, FWidths[i]);
  FWidths[0] := avail - rest;
  if FWidths[0] < FMinW then FWidths[0] := FMinW;
end;

procedure TSzHeader.SetWidth(i: Integer; V: Integer);
begin
  if (i < 1) or (i > High(FWidths)) then Exit;
  FWidths[i] := V;
  Normalize;
  Invalidate;
end;

procedure TSzHeader.SetEdge(V: Integer);
begin
  if V < 0 then V := 0;
  if V = FEdge then Exit;
  FEdge := V;
  Normalize;
  Invalidate;
end;

procedure TSzHeader.SetSort(Col: Integer; Asc: Boolean);
begin
  FSortCol := Col;
  FSortAsc := Asc;
  Invalidate;
end;

function TSzHeader.ColLeft(i: Integer): Integer;
var
  k: Integer;
begin
  Result := 0;
  for k := 0 to i - 1 do Inc(Result, FWidths[k]);
end;

function TSzHeader.ColAt(X: Integer): Integer;
var
  i, l: Integer;
begin
  Result := -1;
  l := 0;
  for i := 0 to High(FWidths) do
  begin
    if (X >= l) and (X < l + FWidths[i]) then Exit(i);
    Inc(l, FWidths[i]);
  end;
end;

{ Colonna il cui bordo destro e vicino a X (-1 se nessuna). L'ultimo bordo e
  il margine della finestra e non si trascina. }
function TSzHeader.DividerAt(X: Integer): Integer;
var
  i, r: Integer;
begin
  Result := -1;
  r := 0;
  for i := 0 to High(FWidths) - 1 do
  begin
    Inc(r, FWidths[i]);
    if Abs(X - r) <= GRIP then Exit(i);
  end;
end;

procedure TSzHeader.Paint;
var
  i, l, w, tw, ty, cx, cy: Integer;
  R: TRect;
  s: string;
  pressed: Boolean;
begin
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(0, 0, Width, Height);
  Canvas.Font.Assign(Font);
  l := 0;
  for i := 0 to High(FWidths) do
  begin
    w := FWidths[i];
    pressed := (i = FPressCol) and (FDragCol < 0);
    R := Rect(l, 0, l + w, Height);
    if pressed then Canvas.Brush.Color := clBtnShadow
    else if i = FHotCol then Canvas.Brush.Color := clBtnHighlight
    else Canvas.Brush.Color := clBtnFace;
    if pressed then Canvas.Brush.Color := clSilver;
    Canvas.FillRect(R);
    // separatore verticale e filetto inferiore
    Canvas.Pen.Color := clBtnShadow;
    Canvas.Line(l + w - 1, 3, l + w - 1, Height - 3);
    Canvas.Line(l, Height - 1, l + w, Height - 1);
    // testo
    s := FTitles[i];
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := clBtnText;
    tw := Canvas.TextWidth(s);
    ty := (Height - Canvas.TextHeight('Ag')) div 2;
    cx := 0;
    if i = FSortCol then cx := 16;     // spazio per la freccia
    while (tw > w - 12 - cx) and (Length(s) > 1) do
    begin
      SetLength(s, Length(s) - 1);
      tw := Canvas.TextWidth(s + '...');
    end;
    if s <> FTitles[i] then s := s + '...';
    tw := Canvas.TextWidth(s);
    if FRight[i] then
      Canvas.TextOut(l + w - 6 - cx - tw, ty, s)
    else
      Canvas.TextOut(l + 6, ty, s);
    Canvas.Brush.Style := bsSolid;
    // freccia di ordinamento
    if i = FSortCol then
    begin
      if FRight[i] then cx := l + w - 6 - 9
      else cx := l + 6 + tw + 8;
      cy := Height div 2;
      Canvas.Brush.Color := clGrayText;
      Canvas.Pen.Color := clGrayText;
      if FSortAsc then
        Canvas.Polygon([Point(cx - 4, cy + 2), Point(cx + 4, cy + 2), Point(cx, cy - 3)])
      else
        Canvas.Polygon([Point(cx - 4, cy - 2), Point(cx + 4, cy - 2), Point(cx, cy + 3)]);
    end;
    Inc(l, w);
  end;
  // zona a destra non occupata dalle colonne
  if l < Width then
  begin
    Canvas.Brush.Color := clBtnFace;
    Canvas.FillRect(l, 0, Width, Height);
    Canvas.Pen.Color := clBtnShadow;
    Canvas.Line(l, Height - 1, Width, Height - 1);
  end;
end;

procedure TSzHeader.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FDragCol := DividerAt(X);
  if FDragCol >= 0 then
  begin
    FDragX := X;
    FDragW0 := FWidths[FDragCol];
    FDragW1 := FWidths[FDragCol + 1];
    FPressCol := -1;
  end
  else
    FPressCol := ColAt(X);
  Invalidate;
end;

procedure TSzHeader.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  d, hot: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FDragCol >= 0 then
  begin
    d := X - FDragX;
    if FDragCol = 0 then
    begin
      // il bordo della colonna 0 si sposta, la colonna 1 cede/prende spazio
      // e la colonna 0 (che riempie) si adegua: gli altri bordi restano fermi
      if FDragW1 - d < FMinW then d := FDragW1 - FMinW;
      if FDragW0 + d < FMinW then d := FMinW - FDragW0;
      FWidths[1] := FDragW1 - d;
    end
    else
    begin
      // la colonna a sinistra del bordo e quella a destra si dividono lo spazio
      if FDragW0 + d < FMinW then d := FMinW - FDragW0;
      if FDragW1 - d < FMinW then d := FDragW1 - FMinW;
      FWidths[FDragCol] := FDragW0 + d;
      FWidths[FDragCol + 1] := FDragW1 - d;
    end;
    Normalize;
    Invalidate;
    if Assigned(FOnChanged) then FOnChanged(Self);
    Exit;
  end;
  if DividerAt(X) >= 0 then Cursor := crHSplit else Cursor := crDefault;
  hot := ColAt(X);
  if hot <> FHotCol then
  begin
    FHotCol := hot;
    Invalidate;
  end;
end;

procedure TSzHeader.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  c, p: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  c := ColAt(X);
  p := FPressCol;
  FPressCol := -1;
  FDragCol := -1;
  Invalidate;
  if (p >= 0) and (c = p) and Assigned(FOnClickCol) then FOnClickCol(Self, c);
end;

procedure TSzHeader.MouseLeave;
begin
  inherited MouseLeave;
  if FHotCol <> -1 then
  begin
    FHotCol := -1;
    Invalidate;
  end;
end;

procedure TSzHeader.Resize;
begin
  inherited Resize;
  Normalize;
  Invalidate;
  if Assigned(FOnChanged) then FOnChanged(Self);
end;

end.
