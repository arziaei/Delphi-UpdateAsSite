program BarayandUpdateFromTheSite;

uses
  Forms,
  Unit_MainUpdate in 'Unit_MainUpdate.pas' {Form_MainUpdate},
  Unit1 in 'Temp\Unit1.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm_MainUpdate, Form_MainUpdate);
  Application.Run;
end.
