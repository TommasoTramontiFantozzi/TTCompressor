unit szdnd;

{ Trascinamento verso l'esterno (file manager, desktop) con il protocollo
  XDS "Direct Save" (XdndDirectSave0): il file manager comunica la cartella di
  destinazione e TTCompressor vi estrae gli elementi scelti. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, gtk2, gdk2, glib2;

type
  TDropEvent = procedure(const DestDir: string) of object;

{ Prepara il widget (gia creato) a fungere da sorgente. }
procedure HookDragSource(Widget: PGtkWidget);

{ Avvia il trascinamento: AName e il nome mostrato al file manager, OnDrop
  viene chiamato (fuori dal contesto GTK) con la cartella di destinazione. }
procedure BeginExtractDrag(Widget: PGtkWidget; const AName: string; OnDrop: TDropEvent);

implementation

var
  CurName: string;
  CurDrop: TDropEvent;
  CurDest: string;
  Active: Boolean;

function UriDecode(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '%') and (i + 2 <= Length(S)) then
    begin
      Result := Result + Chr(StrToIntDef('$' + Copy(S, i + 1, 2), 63));
      Inc(i, 3);
    end
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

type
  TDropHelper = class
    procedure Run(Data: PtrInt);
  end;

var
  Helper: TDropHelper;

procedure TDropHelper.Run(Data: PtrInt);
begin
  if (CurDest <> '') and Assigned(CurDrop) then CurDrop(CurDest);
  CurDest := '';
end;

procedure DragBegin(Widget: PGtkWidget; Context: PGdkDragContext; Data: gpointer); cdecl;
begin
  if not Active then Exit;
  // nome del file "da salvare", letto dal file manager
  gdk_property_change(Context^.source_window, gdk_atom_intern('XdndDirectSave0', False),
    gdk_atom_intern('text/plain', False), 8, GDK_PROP_MODE_REPLACE,
    Pguchar(PChar(CurName)), Length(CurName));
end;

procedure DragDataGet(Widget: PGtkWidget; Context: PGdkDragContext;
  Sel: PGtkSelectionData; Info, Time: guint; Data: gpointer); cdecl;
var
  actType: TGdkAtom;
  actFmt, actLen: gint;
  buf: Pguchar;
  uri, reply: string;
begin
  if not Active then Exit;
  reply := 'E';
  buf := nil;
  if gdk_property_get(Context^.source_window, gdk_atom_intern('XdndDirectSave0', False),
       0, 0, 4096, 0, @actType, @actFmt, @actLen, @buf)
     and (buf <> nil) and (actLen > 0) then
  begin
    SetString(uri, PChar(buf), actLen);
    g_free(buf);
    if Copy(uri, 1, 7) = 'file://' then
    begin
      uri := UriDecode(Copy(uri, 8, MaxInt));
      // "file://host/percorso": scarta l'eventuale host
      if (uri <> '') and (uri[1] <> '/') then Delete(uri, 1, Pos('/', uri) - 1);
      CurDest := ExtractFilePath(uri);
      if CurDest <> '' then
      begin
        reply := 'S';
        Application.QueueAsyncCall(@Helper.Run, 0);
      end;
    end;
  end;
  gtk_selection_data_set(Sel, Sel^.target, 8, Pguchar(PChar(reply)), 1);
end;

procedure DragEnd(Widget: PGtkWidget; Context: PGdkDragContext; Data: gpointer); cdecl;
begin
  Active := False;
end;

procedure HookDragSource(Widget: PGtkWidget);
begin
  g_signal_connect(Widget, 'drag-begin', TGCallback(@DragBegin), nil);
  g_signal_connect(Widget, 'drag-data-get', TGCallback(@DragDataGet), nil);
  g_signal_connect(Widget, 'drag-end', TGCallback(@DragEnd), nil);
end;

procedure BeginExtractDrag(Widget: PGtkWidget; const AName: string; OnDrop: TDropEvent);
var
  Tgt: TGtkTargetEntry;
  TL: PGtkTargetList;
  Ev: PGdkEvent;
begin
  CurName := AName;
  CurDrop := OnDrop;
  CurDest := '';
  Active := True;
  Tgt.target := 'XdndDirectSave0';
  Tgt.flags := 0;
  Tgt.info := 1;
  TL := gtk_target_list_new(@Tgt, 1);
  Ev := gtk_get_current_event;
  gtk_drag_begin(Widget, TL, GDK_ACTION_COPY, 1, Ev);
  if Ev <> nil then gdk_event_free(Ev);
  gtk_target_list_unref(TL);
end;

initialization
  Helper := TDropHelper.Create;

end.
