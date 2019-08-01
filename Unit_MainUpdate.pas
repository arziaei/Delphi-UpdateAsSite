﻿unit Unit_MainUpdate;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, DB, ADODB, StdCtrls, IdBaseComponent, IdComponent, IdTCPConnection,
  IdTCPClient, IdHTTP, ShellAPI, ComCtrls, ExtCtrls, IdIOHandler,
  IdIOHandlerSocket, IdIOHandlerStack, IdSSL, IdSSLOpenSSL;

type
  TDownloadEvent = procedure (bytes: int64) of object;

  TForm_MainUpdate = class(TForm)
    Button1: TButton;
    Memo1: TMemo;
    ADOConnection1: TADOConnection;
    Button2: TButton;
    ADOCommand1: TADOCommand;
    Button3: TButton;
    Button4: TButton;
    Edit1: TEdit;
    Label1: TLabel;
    Button5: TButton;
    Edit2: TEdit;
    Button6: TButton;
    Button7: TButton;
    Panel1: TPanel;
    Button_RunUpdate: TButton;
    Label2: TLabel;
    Memo2: TMemo;
    StaticText1: TStaticText;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Button6Click(Sender: TObject);
    procedure Button7Click(Sender: TObject);
    procedure Button_RunUpdateClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    SiteVer   : widestring;
    TotalSize : Int64;
    procedure DownloadEvent(bytes: int64);
  public
    function Connect: boolean;
    function CheckCharge: boolean;
    function RenFile: string;
    procedure UnRenFile(FName: string);
    function GetSP: boolean;
    function UpdateSP: boolean;
    function GetEXE: boolean;
    function UpdateEXE: boolean;
  end;

var
  Form_MainUpdate: TForm_MainUpdate;

implementation

uses WinInet, StrUtils, IdURI;

{$R *.dfm}

Const
  SP_CHECK = 'https://www.fekrgostar.ir/API/SpCheck.php';
  EXE_CHECK = 'https://www.fekrgostar.ir/API/ExeCheck.php';
  EXE_NAME = 'barayand.rar';
  EXE_LOCATION = 'https://www.fekrgostar.ir/API/Updates/' + EXE_NAME;
  RAR_NAME = 'rar.exe';
  GO_SEP = '!Go!';

Var
  SQLUID: string;
  COMPANY_NAME: string;

function GetSQLUID(ADOConnection: ADODB.TADOConnection): string;
begin
  Result := ADOConnection.Execute
      (
        'SELECT B.database_guid id ' +
        'FROM sys.databases A ' +
        '  JOIN sys.database_recovery_status B ON A.database_id = B.database_id ' +
        'WHERE A.name = DB_NAME()'
      ).Fields['id'].Value;
end;

function GetCompanyName(ADOConnection: TADOConnection): string;
begin
  Result := ADOConnection.Execute
      (
        'SELECT MAX(LTRIM(RTRIM(company))) co ' +
        'FROM dbo.Tbl_Company where autonumber='+ParamStr(4)
      ).Fields['co'].Value;
end;

function CheckDate(ADOConnection: TADOConnection; D1, D2: string): integer;
begin
  Result := ADOConnection.Execute
      (
       'SELECT CASE WHEN GETDATE() BETWEEN CAST(''' + D1 + ''' AS DATETIME) AND CAST(''' + D2 + ''' AS DATETIME) THEN 1 ELSE 0 END N'
      ).Fields['N'].Value;
end;

function FileVersion(const FileName: TFileName): String;
var
  VerInfoSize: Cardinal;
  VerValueSize: Cardinal;
  Dummy: Cardinal;
  PVerInfo: Pointer;
  PVerValue: PVSFixedFileInfo;
begin
  Result := '';
  VerInfoSize := GetFileVersionInfoSize(PChar(FileName), Dummy);
  GetMem(PVerInfo, VerInfoSize);
  try
    if GetFileVersionInfo(PChar(FileName), 0, VerInfoSize, PVerInfo) then
      if VerQueryValue(PVerInfo, '\', Pointer(PVerValue), VerValueSize) then
        with PVerValue^ do
          Result := Format('%d.%d.%d.%d', [
            HiWord(dwFileVersionMS), //Major
            LoWord(dwFileVersionMS), //Minor
            HiWord(dwFileVersionLS), //Release
            LoWord(dwFileVersionLS)]); //Build
  finally
    FreeMem(PVerInfo, VerInfoSize);
  end;
end;

function Internet_Get(URL: string): string;
var
  NetHandle: HINTERNET;
  UrlHandle: HINTERNET;
  Buffer: array[0..1024] of AnsiChar;
  BytesRead, TotalRead: dWord;
  i: integer;
begin
  Result := '';
  NetHandle := InternetOpen('Delphi 2010', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);

  if Assigned(NetHandle) then
  begin
    UrlHandle := InternetOpenUrl(NetHandle, PChar(Url), nil, 0, INTERNET_FLAG_RELOAD, 0);

    if Assigned(UrlHandle) then
      { UrlHandle valid? Proceed with download }
      begin
      TotalRead := 0;

      repeat
        FillChar(Buffer, SizeOf(Buffer), 0);
        InternetReadFile(UrlHandle, @Buffer, SizeOf(Buffer), BytesRead);
        TotalRead := TotalRead + BytesRead;

        for i := 0 to BytesRead - 1 do
          Result := Result + Buffer[i];

      until BytesRead = 0;

      InternetCloseHandle(UrlHandle);
      end

    else
      { UrlHandle is not valid. Raise an exception. }
      raise Exception.CreateFmt('Cannot open URL %s', [Url]);

    InternetCloseHandle(NetHandle);
  end
  else
    { NetHandle is not valid. Raise an exception }
    raise Exception.Create('Unable to initialize Wininet');
end;

function Internet_Download(URL, FileName: string; Event: TDownloadEvent): Boolean;
const
  BufferSize = 1024;
var
  hSession, hURL: HInternet;
  Buffer: array[1..BufferSize] of Byte;
  BufferLen: DWORD;
  F: File;
  total: int64;
begin
   Result := False;
   hSession := InternetOpen('', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0) ;

   // Establish the secure connection
   InternetConnect (
     hSession,
     PChar(URL),
     INTERNET_DEFAULT_HTTPS_PORT,
     '',
     '',
     INTERNET_SERVICE_HTTP,
     0,
     0
   );

  total := 0;
  try
    hURL := InternetOpenURL(hSession, PChar(URL), nil, 0, 0, 0) ;
    try
      AssignFile(f, FileName);
      Rewrite(f, 1);
      try
        repeat
          InternetReadFile(hURL, @Buffer, SizeOf(Buffer), BufferLen) ;
          BlockWrite(f, Buffer, BufferLen);

          inc(total, BufferLen);

          if Assigned(Event) then
            Event(total);

        until BufferLen = 0;
      finally
        CloseFile(f) ;
        Result := True;
      end;
    finally
      InternetCloseHandle(hURL)
    end
  finally
    InternetCloseHandle(hSession)
  end;
end;

procedure TForm_MainUpdate.Button1Click(Sender: TObject);
begin
  GetSP;
end;

procedure TForm_MainUpdate.Button2Click(Sender: TObject);
begin
  UpdateSP;
end;

function CompareVersion(Ver1, Ver2: string): integer;
var
  lst1, lst2: TStringList;
  i: integer;
begin
  Result := 0;

  lst1 := TStringList.Create;
  lst2 := TStringList.Create;

  lst1.Text := StringReplace(Ver1, '.', #13#10, [rfReplaceAll]);
  lst2.Text := StringReplace(Ver2, '.', #13#10, [rfReplaceAll]);

  if lst1.Count < 4 then Exit;
  if lst2.Count < 4 then Exit;

  for i := 0 to lst1.Count - 1 do
    lst1[i] := rightstr('0000' + lst1[i], 4);

  for i := 0 to lst2.Count - 1 do
    lst2[i] := rightstr('0000' + lst2[i], 4);

  if lst1[0] > lst2[0] then Result := 1
  else if lst1[0] < lst2[0] then Result := -1
  else if lst1[1] > lst2[1] then Result := 1
  else if lst1[1] < lst2[1] then Result := -1
  else if lst1[2] > lst2[2] then Result := 1
  else if lst1[2] < lst2[2] then Result := -1
  else if lst1[3] > lst2[3] then Result := 1
  else if lst1[3] < lst2[3] then Result := -1
  else Result := 0;

  lst1.Destroy;
  lst2.Destroy;
end;

procedure TForm_MainUpdate.Button3Click(Sender: TObject);
begin
  if GetEXE then
    ShowMessage('Exe download and unrar successfully');
end;

procedure TForm_MainUpdate.Button4Click(Sender: TObject);
begin
  if UpdateEXE then
    ;
end;

procedure TForm_MainUpdate.Button5Click(Sender: TObject);
begin
  if not Connect then
    ShowMessage('CONNECTION ERROR');
end;

procedure TForm_MainUpdate.Button6Click(Sender: TObject);
begin
  if RenFile = '' then
    ShowMessage('Please close all of running project in all clients first');
end;

procedure TForm_MainUpdate.Button7Click(Sender: TObject);
begin
  if CheckCharge then
    ShowMessage('Not charged')
  else
    ShowMessage('Charged');
end;

procedure TForm_MainUpdate.Button_RunUpdateClick(Sender: TObject);
var
  igo         ,
  CountSP     : integer;
  flag        : boolean;
  S1, S2  ,
  Pathrun     : string;
begin
  flag := true;
  Memo2.Lines.Add('*******************');

  if flag then
    begin
    Memo2.Lines.Add('');
    Memo2.Lines.Add('شروع ارتیاط');

    while not Connect do
      begin
      Caption := ADOConnection1.ConnectionString;
      flag := MessageDlg('ارتباط با پایگاه داده برقرار نشد. آیا مجدد سعی می کنید؟', mtWarning, [mbYes, mbNo], 0) = mrYes;

      if not flag then Break;
      end;

    if flag then
      Memo2.Lines.Add('ارتباط انجام شد');
    end;

  Application.ProcessMessages;

  if flag then
    begin
    Memo2.Lines.Add('');
    Memo2.Lines.Add('شروع تست شارژ');

    while not CheckCharge do
      begin
      flag := MessageDlg('شارژ شما به پایان رسیده است. آیا مجدد سعی می کنید؟', mtWarning, [mbYes, mbNo], 0) = mrYes;

      if not flag then Break;
      end;

    if flag then
      Memo2.Lines.Add('تست شارژ انجام شد');
    end;

  Application.ProcessMessages;

  if flag then
    begin
    Memo2.Lines.Add('');
    Memo2.Lines.Add('شروع دریافت آپدیت های بانک اطلاعاتی');

    while not GetSP do
      begin
      flag := MessageDlg('ارتباط با سرور برقرار نشد. آیا مجدد سعی می کنید؟',mtWarning, [mbYes, mbNo], 0) = mrYes;

      if not flag then
        Break;
    end;

    if flag then
      Memo2.Lines.Add('آپدیت ها دریافت شدند');
    end;

  Application.ProcessMessages;

  //شمارش تعداد آپدیتها

  S1 := Memo1.Lines.Text;
  S2 := StringReplace(S1, GO_SEP, GO_SEP + '!', [rfReplaceAll, rfIgnoreCase]);
  CountSP := Length(S2) - length(S1);

  if CountSP > 0 then
    if MessageDlg('تعداد '+IntToStr(CountSP)+' فایل بروز رسانی وجود دارد '
                +#13+' آیا میخواهید ادامه دهید',mtWarning,[mbYes, mbNo],0) = mrNo then
      Exit;

  Application.ProcessMessages;

  if flag then
    begin
    Memo2.Lines.Add('');
    Memo2.Lines.Add('شروع انجام آپدیت های بانک اطلاعاتی');

    while not UpdateSP do
     begin
      flag := MessageDlg('آپدیت انجام نشد. آیا مجدد سعی می کنید؟',mtWarning, [mbYes, mbNo], 0) = mrYes;

      if not flag then
        Break;
     end;

    if flag then
     begin
      Memo2.Lines.Add(' ');
      Memo2.Lines.Add('آپدیت ها انجام شدند');
     end;
    end;


  Application.ProcessMessages;

  if flag then
    begin
    Memo2.Lines.Add('');
    Memo2.Lines.Add('شروع دریافت برنامه');

    while not GetEXE do
      begin
      flag := MessageDlg('فایل دریافت نشد. آیا مجدد سعی می کنید؟',
        mtWarning, [mbYes, mbNo], 0) = mrYes;

      if not flag then
        Break;
      end;

    if flag then
      Memo2.Lines.Add('فرآیند بررسی و بروز رسانی فایل اجرایی انجام شد');
    end;

  Application.ProcessMessages;

  if flag then
   begin
    Memo2.Lines.Add('');
    Memo2.Lines.Add('شروع ثبت برنامه');

    while not UpdateEXE do
      begin
      flag := MessageDlg('فایل آپدیت ثبت نشد. آیا مجدد سعی می کنید؟',
        mtWarning, [mbYes, mbNo], 0) = mrYes;

      if not flag then
        Break;
      end;

    if flag then
      Memo2.Lines.Add('برنامه ثبت شد');
   end;

  if flag then
   begin
    ShowMessage('آپدیت سیستم با موفقیت انجام شد. چند لحظه منتظر بمانید تا برنامه به صورت هوشمند باز شود.');

    Pathrun:= Edit2.Text;
    ShellExecute(Handle, 'open', pwidechar(Pathrun) , nil, nil, SW_SHOWNORMAL);
    Close;
   end
  else
    ShowMessage('آپدیت کنسل شد، لطفا در نظر داشته باشید که آپدیت نیمه کاره ممکن است اشکالاتی در سیستم بوجود آورد. لطفا در این مورد با شرکت تماس بگیرید.');

  ShowMessage('لطفا به پیغام های باکس روند کار توجه کنید و در صورت لزوم برای رفع موارد با پشتیبانی نرم افزار برآیند تماس بگیرید.')
end;

function TForm_MainUpdate.CheckCharge: boolean;
var
  s: widestring;
  t1, t2: string;
  D1, D2: TDateTime;
begin
  s := Internet_Get(TIdURI.URLEncode(SP_CHECK + '?SQLUID=' + SQLUID + '&CompanyName=' + UTF8Encode(COMPANY_NAME) + '&Mode=-1'));

  if s <> '' then
    begin
    t1 := trim(Copy(s, 1, Pos(';', s) -1));
    Delete(s, 1, length(t1) +1);
    s := trim(s);

    t2 := trim(Copy(s, 1, Pos(';', s) -1));
    Delete(s, 1, length(t2) +1);
    s := trim(s);
    end;

  if (CheckDate(ADOConnection1, t1, t2) = 0) or (StrToIntDef(s, 0) = 0) then
    Result := false
  else
    Result := true;
end;

function TForm_MainUpdate.Connect: boolean;
begin
  try
    ADOConnection1.Close;
    ADOConnection1.ConnectionString := trim(Edit1.Text);
    ADOConnection1.Open;

    SQLUID := GetSQLUID(ADOConnection1);
    COMPANY_NAME := GetCompanyName(ADOConnection1);

    Caption := COMPANY_NAME;
    Result := true;
  except
    Result := false;
  end;
end;

procedure TForm_MainUpdate.DownloadEvent(bytes: int64);
begin
  StaticText1.Tag := StaticText1.Tag +1;
  if StaticText1.Tag > 100 then
    begin
    StaticText1.Caption := ' حجم دانلود شده: ' + FloatToStr(Round(bytes / 1024 / 1024)) + ' MB';
    StaticText1.Refresh;
    StaticText1.Tag := 0;
    end;
end;

procedure TForm_MainUpdate.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Memo2.Lines.SaveToFile('LogUpDateAsSite.txt');
  ExitProcess(0);
end;

procedure TForm_MainUpdate.FormCreate(Sender: TObject);
begin
  Edit1.Text := ParamStr(1);
  Edit2.Text := ParamStr(2);
end;

function TForm_MainUpdate.GetEXE: boolean;
var
  MyVer     : widestring;
  Pathrun   ,
  FName     ,
  FPath     ,
  NewFileName : string;
begin
  Memo2.Lines.Add('نسخه ارسالی از برنامه برآیند:'+ParamStr(3));
  Memo2.Lines.Add('MyVer before:'+MyVer);
  MyVer := ParamStr(3);
  Memo2.Lines.Add('MyVer next :'+MyVer);

  SiteVer := Internet_Get(EXE_CHECK);
  SiteVer := UTF8ToString(SiteVer);

  Memo2.Lines.Add('نسخه برنامه :'+MyVer);
  Memo2.Lines.Add('نسخه موجود در سایت :'+SiteVer);

  if CompareVersion(MyVer, SiteVer) > 0 then
   begin
    Memo2.Lines.Add('برنامه اجرایی برآیند بروز است');
    Result := true;

    Pathrun:= Edit2.Text;
    ShellExecute(Handle, 'open', pwidechar(Pathrun) , nil, nil, SW_SHOWNORMAL);

    Close;
   end;

  try
    Memo2.Lines.Add('');
    Memo2.Lines.Add('شروع تغییر نام برنامه قبلی');

    NewFileName := RenFile;

    if NewFileName = '' then
     begin
      MessageDlg('برنامه قادر به اجرای روند خود نیست، مطمئن شوید تمام کلاینت ها سیستم خود را بسته باشند. آیا مجدد سعی می کنید؟', mtWarning, [mbok], 0) ;

      Exit;
     end;

    Memo2.Lines.Add('تغییر نام انجام شد');

    Memo2.Lines.Add('شروع دانلود فایل اجرایی نرم افزار برآیند');

    FPath := ExtractFilePath(Edit2.Text);
    FName := ExtractFileName(Edit2.Text);

    Internet_Download(EXE_LOCATION, FPath + EXE_NAME, Form_MainUpdate.DownloadEvent);

    if not FileExists(RAR_NAME) then
     begin
      Memo2.Lines.Add('فایل Rar در مسیر جاری یافت نشد');
      Result := false;
      Exit;
     end;

    ShellExecute(Application.Handle, 'open', RAR_NAME, PWideChar('x ' + FPath + EXE_NAME), '', SW_HIDE);

    Result := true; //CopyFile(PWideChar(FName), PWideChar(FPath + FName), true);
  except
    Memo2.Lines.Add('خطا در دریافت فایل اجرایی از سایت');

    UnRenFile(NewFileName);

    Result := false;
  end;
end;

procedure BreakGo(var txt: widestring);
var
  i: integer;
  s, q1, q2: widestring;
begin
  if Length(txt) < 10 then
    Exit;

  s := UpperCase(txt);

  i := 0;

  repeat
    i := PosEx('GO', s, i +1);

    if i < 1 then
      Break;

    if not (s[i -1] in ['!', '0'..'9', 'A'..'Z', '@', '#', '_', '[', '"']) then
      if not (s[i +2] in ['!', '0'..'9', 'A'..'Z', '@', '#', '_', ']', '"']) then
        begin
        q1 := Copy(txt, 1, i -1);
        q2 := Copy(txt, i +2, Length(txt));

        txt := q1 + #13#10 + GO_SEP + #13#10 + q2;
        s := UpperCase(txt);
        end;

  until false;
end;

function TForm_MainUpdate.GetSP: boolean;
var
  s: widestring;
begin
  try
    s := TIdURI.URLEncode(SP_CHECK + '?SQLUID=' + SQLUID + '&CompanyName=' + UTF8Encode(COMPANY_NAME) + '&Mode=0');
    s := Internet_Get(s);
    s := UTF8ToString(s);

    BreakGo(s);

    Memo1.Lines.Text := trim(s);
    Result := true;
  Except
    Result := false;
  end;
end;

function TForm_MainUpdate.RenFile: string;
var
  NewName: string;
begin
  Result := '';

  NewName := Edit2.Text + '-' + DateToStr(Date);
  NewName := StringReplace(NewName, '/', '-', [rfReplaceAll]);

  if FileExists(Edit2.Text) then
    begin
    if FileExists(NewName) then
      DeleteFile(NewName);

    if RenameFile(Edit2.Text, NewName) then
      Result := NewName;
    end
  else
    Result := 'X';
end;

procedure TForm_MainUpdate.UnRenFile(FName: string);
var
  NewName: string;
begin
  if FName = 'X' then
    Exit;

  NewName := Edit2.Text;

  if FileExists(FName) then
    begin
    if FileExists(NewName) then
      DeleteFile(NewName);

    RenameFile(FName, NewName);
    end;
end;

function TForm_MainUpdate.UpdateEXE: boolean;
begin
  Memo2.Lines.Add('');
  Memo2.Lines.Add('نسخه برنامه جهت ارتقاء : '+SiteVer);

  ShellExecute(0, 'open', 'BarayandSetVersion.exe', PWideChar('"' + SiteVer + '"'), '', SW_NORMAL);
  Result:=True;
end;

function TForm_MainUpdate.UpdateSP: boolean;
var
  i: integer;
  s, t, n, lastn: string;
  w: widestring;
begin
  s := Memo1.Lines.Text;

  repeat
    i := Pos(GO_SEP, s);

    if i = 0 then
     begin
      Memo2.Lines.Add('بروز رسانی بانک اطلاعاتی وجود ندارد' );
      Break;
     end;

    t := trim(Copy(s, 1, i -1));
    Delete(s, 1, i +3);

    n := Copy(t, 1, Pos('~', t) -1);

    if StrToIntDef(n, 0) = 0 then
      n := lastn + '_' + inttostr(i)
    else
      begin
      Delete(t, 1, length(n) +1);
      lastn := n;
      end;

    t := trim(t);

    if t = '' then
      continue;

    try
//      t := 'exec(' + QuotedStr(t) + ')';
//      ADOCommand1.CommandText := t;
//      ADOCommand1.Execute;

      ADOConnection1.Execute(t);

      Memo2.Lines.Add('بروز رسانی بانک اطلاعاتی شماره' + n + ' انجام شد' );
    except
      on e: Exception do
        Memo2.Lines.Add('--> اشکال در اس پی شماره ' + n + #13#10 + '  >> ' + e.Message);
    end;
  until false;

  w := Internet_Get(TIdURI.URLEncode(SP_CHECK + '?SQLUID=' + SQLUID + '&CompanyName=' + UTF8Encode(COMPANY_NAME) + '&Mode=1'));
  Result := true;
end;

end.