unit szabout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics;

procedure ShowAboutDialog(AOwner: TForm);

implementation

uses szlang;

{$I szgpl.inc}

procedure ShowAboutDialog(AOwner: TForm);
var
  F: TForm;
  L: TLabel;
  M: TMemo;
  B: TButton;
  P: TPanel;
begin
  F := TForm.CreateNew(AOwner);
  try
    F.Caption := StringReplace(Tr('&Informazioni su TTCompressor'), '&', '', []);
    F.Position := poOwnerFormCenter;
    F.BorderStyle := bsSizeable;
    F.Width := 640;
    F.Height := 520;
    F.Constraints.MinWidth := 420;
    F.Constraints.MinHeight := 320;

    P := TPanel.Create(F);
    P.Parent := F;
    P.Align := alBottom;
    P.Height := 44;
    P.BevelOuter := bvNone;
    B := TButton.Create(F);
    B.Parent := P;
    B.Caption := 'OK';
    B.ModalResult := mrOk;
    B.Default := True;
    B.Cancel := True;
    B.Width := 90;
    B.Anchors := [akTop, akRight];
    B.Left := P.Width - B.Width - 12;
    B.Top := 8;

    L := TLabel.Create(F);
    L.Parent := F;
    L.Align := alTop;
    L.BorderSpacing.Around := 12;
    L.WordWrap := True;
    L.Caption := 'TTCompressor' + LineEnding + LineEnding +
      Tr('Interfaccia grafica per 7z.') + LineEnding +
      Tr('Formati supportati: tutti quelli di 7z (lettura e scrittura dove 7z lo consente).') +
      LineEnding + Tr('Dati di recupero: Reed-Solomon in coda all''archivio (7z) oppure file PAR2.') +
      LineEnding + LineEnding +
      'Author: Tommaso Tramonti Fantozzi, Vibe Coded with Claude Sonnet 5.5' + LineEnding +
      'License: GPL 3.0' + LineEnding + LineEnding +
      Tr('Questo programma è software libero, distribuito secondo i termini della GNU General Public License versione 3. Il testo della licenza è riportato qui sotto.');

    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    M.BorderSpacing.Around := 12;
    M.ReadOnly := True;
    M.ScrollBars := ssAutoBoth;
    M.WordWrap := False;
    M.Font.Name := 'Monospace';
    M.Text := GPL3Text;
    M.SelStart := 0;
    M.SelLength := 0;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
