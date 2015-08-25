program SweeperBot;

uses
  Forms,
  robot in 'robot.pas' {Form1};

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'SweeperBot';
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
