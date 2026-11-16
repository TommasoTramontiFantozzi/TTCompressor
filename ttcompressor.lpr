program ttcompressor;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, Unit1, szrs
  { you can add units after this };

{$R *.res}

begin
  // modalita' riga di comando per i dati di recupero (senza interfaccia grafica)
  if (ParamCount >= 2) and (Copy(ParamStr(1), 1, 5) = '--rs-') then
    Halt(RunRecoveryCLI);
  RequireDerivedFormResource:=True;
  Application.Title:='TTCompressor';
  Application.Scaled:=True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar:=True;
  {$POP}
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

