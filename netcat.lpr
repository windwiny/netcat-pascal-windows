program netcat;

{$mode objfpc}{$longstrings on}


uses
 {$IFDEF UNIX}
  cthreads,
   {$ENDIF}
  Classes,
  SysUtils,
  CustApp,
  unitnet;

const
  VERSION = 'pascal source fake netcat, v1, by windwiny';

type

  { TMyApplication }

  TMyApplication = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
    procedure WriteVersion; virtual;
  end;

  { TMyApplication }

  procedure TMyApplication.DoRun;
  var
    ErrorMsg: string;
    hoststr, portstr: string;
    port: integer;
    mode: (server, client);
    proto: (tcp, udp);

  begin
    // quick check parameters
    ErrorMsg := CheckOptions('vhul:', 'help');
    if ErrorMsg <> '' then begin
      ShowException(Exception.Create(ErrorMsg));
      Terminate;
      Exit;
    end;

    // parse parameters
    if HasOption('h', 'help') then begin
      WriteHelp;
      Terminate;
      Exit;
    end;

    if HasOption('v', 'version') then begin
      WriteVersion;
      Terminate;
      Exit;
    end;

    if HasOption('u', 'udp') then
      proto := udp
    else
      proto := tcp;

    if HasOption('l', 'listen') then begin
      mode := server;
      portstr := GetOptionValue('l', 'listen');
    end else begin
      mode := client;
      if ParamCount < 2 then begin
        WriteHelp;
        Terminate;
        Exit;
      end else begin
        hoststr := ParamStr(ParamCount - 1);
        portstr := ParamStr(ParamCount);
      end;
    end;

    port := StrToIntDef(portstr, -1);
    if (port <= 0) or (port >= 65535) then begin
      WriteHelp;
      WriteLn(stderr, 'port must > 1025 and < 65535 ');
      Terminate;
      Exit;
    end;


    { add your program here }
    if mode = server then begin
      if proto = tcp then
        tcpserver(port)
      else
        udpserver(port);
    end else begin
      if proto = tcp then
        tcpclient(hoststr, port)
      else
        udpclient(hoststr, port);
    end;
    // stop program loop
    Terminate;
  end;

  constructor TMyApplication.Create(TheOwner: TComponent);
  begin
    inherited Create(TheOwner);
    StopOnException := True;
  end;

  destructor TMyApplication.Destroy;
  begin
    inherited Destroy;
  end;

  procedure TMyApplication.WriteHelp;
  begin
    writeln(stderr, 'Usage: ', ExeName, ' -h');
    WriteLn(stderr, ' server mode :   [ -u ]  -l  port');
    WriteLn(stderr, ' client mode :   [ -u ]  ip  port');
    WriteLn(stderr, '   -u | --udp     : udp protocol, default tcp');
    WriteLn(stderr, '   -l | --listen  : server listen port');
    WriteLn(stderr, '   send and client can redirect stdin/stdout: < file1 , > file2');
  end;

  procedure TMyApplication.WriteVersion;
  begin
    writeln(stderr, VERSION);
  end;

var
  Application: TMyApplication;
begin
  Application := TMyApplication.Create(nil);
  Application.Title := 'My Application';
  Application.Run;
  Application.Free;
end.
