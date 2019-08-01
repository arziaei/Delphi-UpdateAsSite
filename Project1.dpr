program Project1;

uses
  Forms,
  Unit_MainUpdate in 'Unit_MainUpdate.pas' {Form_MainUpdate};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm_MainUpdate, Form_MainUpdate);
  Application.Run;
end.
