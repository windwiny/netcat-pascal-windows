unit unitnet;

{$mode ObjFPC}{$longstrings on}
{$assertions on}

interface

procedure tcpserver(const port: integer);
procedure tcpclient(const hoststr: string; const port: integer);
procedure udpserver(const port: integer);
procedure udpclient(const hoststr: string; const port: integer);


implementation

uses
  Classes, SysUtils, Sockets;

var
  input_b: file of char;

procedure perror(const msg: string);
begin
  writeln(stderr, msg, SocketError);
  //halt(100);
end;

function ArrayCharToAnsiString(arroc: array of char; const len2: longint): ansistring;
var
  i: integer;
begin
  Result := '';
  for i := 0 to len2 - 1 do
    Result += arroc[i];
end;

type
  ptsocklen = ^tsocklen;
  plongint = ^longint;

  pmytcpds = ^mytcpds;

  mytcpds = record
    pSC: ptsocklen;
    pC, pS: plongint;
    othertid: ^TThreadID;
    otherts: pmytcpds;
  end;



procedure recv_and_write(SC: ptsocklen; recv_count, recv_char_sum: plongint);
const
  BASE = 1;
  MAX_MSG_LEN = 4096;
var
  buffer: array[BASE..MAX_MSG_LEN] of char;
  len: longint = 0;
begin
  while True do begin
    len := fprecv(SC^, @buffer, MAX_MSG_LEN, 0);
    if (len = -1) then begin
      perror('fprecv err ');
      exit;
    end;
    if (len = 0) then begin
      writeln(stderr, 'recv remote closed': 20);
      break;
    end;

    InterlockedIncrement(recv_count^);
    recv_char_sum^ += len;

    Write(Output, buffer[BASE..len]);
    Flush(Output);
  end;
end;

function recv_and_write_t(p: pointer): ptrint;
var
  v: mytcpds;
  tr: qword;
begin
  v := pmytcpds(p)^;

  tr := GetTickCount64;
  recv_and_write(v.psc, v.pc, v.ps);
  writeln(stderr, 'recv_count ': 20, v.pc^, ' recv_char_sum: ', v.ps^);
  writeln(stderr, 'recv used  ': 20, GetTickCount64 - tr, ' ms');
  fpshutdown(v.psc^, 0);

  { first recv finished will close connection

    FIXME close(input_b) can not quit other thread blockread from stdin
    check  other thread read stdin count=0 then
      killthread
  }
  //if v.pc^ > 0 then
  begin

    Close(input_b);
    fpshutdown(v.psc^, 1);
    //if v.otherts^.pc^ = 0 then
    KillThread(v.othertid^);
  end;
  Result := 0;
end;

procedure read_and_send(SC: ptsocklen; send_count, send_char_sum: plongint);
const
  BASE = 1;
  MAX_MSG_LEN = 4096;
var
  buffer: array[BASE..MAX_MSG_LEN] of char;
  len: longint = 0;
  len_st, len_sc: longint;
begin

  while True do begin
{$I-}
    BlockRead(input_b, buffer, MAX_MSG_LEN, len);
    if IOResult <> 0 then break;
{$I+}
    if len = 0 then break;

    len_st := 0;
    while len_st < len do begin
      len_sc := fpsend(SC^, @buffer[BASE + len_st], len - len_st, 0);
      if len_sc = -1 then begin
        perror('Client : fpSend err ');
        Exit;
      end;
      len_st += len_sc;
      InterlockedIncrement(send_count^);
      send_char_sum^ += len_st;
    end;
  end;
end;

function read_and_send_t(p: pointer): ptrint;
var
  v: mytcpds;
  ts: QWord;
begin
  v := pmytcpds(p)^;

  ts := GetTickCount64;
  read_and_send(v.psc, v.pc, v.ps);
  writeln(stderr, 'send_count ': 20, v.pc^, ' send_char_sum: ', v.ps^);
  writeln(stderr, 'send used  ': 20, GetTickCount64 - ts, ' ms');
  fpshutdown(v.psc^, 1);
  if v.pc^ > 0 then begin
    fpshutdown(v.psc^, 0);
  end;
  Result := 0;
end;

procedure tcpserver(const port: integer);
var
  SS, SC: tsocklen;
  SAddr: sockaddr;
  len: longint;
  send_count, send_char_sum: longint;
  tids: tthreadid;
  recv_count, recv_char_sum: longint;
  tidr: tthreadid;
  vs: mytcpds;
  vr: mytcpds;
begin
  send_count := 0;
  send_char_sum := 0;
  recv_count := 0;
  recv_char_sum := 0;

  SS := fpSocket(AF_INET, SOCK_STREAM, 0);
  if SocketError <> 0 then begin
    Perror('Server : fpSocket err ');
    Halt(100);
  end;
  SAddr.sin_family := AF_INET;
  SAddr.sin_port := htons(port);
  SAddr.sin_addr.s_addr := 0;   // sin_addr := StrToNetAddr('0.0.0.0');
  if fpBind(SS, @SAddr, sizeof(saddr)) = -1 then begin
    PError('Server : fpBind err ');
    Halt(100);
  end;
  if fpListen(SS, 1) = -1 then begin
    PError('Server : fpListen err ');
    Halt(100);
  end;
  Writeln(stderr, 'Waiting for Connect from Client');

  len := sizeof(SAddr);
  FillChar(SAddr, len, 0);
  SC := fpaccept(SS, @SAddr, @len);
  if (SC = -1) then begin
    PError('fpServer : fpAccept err ');
    Halt(100);
  end;
  CloseSocket(SS);

  writeln(stderr, 'Server : fpaccept ' + NetAddrToStr(SAddr.sin_addr) +
    ':' + IntToStr(NToHs(SAddr.sin_port)));

  with vr do begin
    psc := @SC;
    pc := @recv_count;
    ps := @recv_char_sum;
    othertid := @tids;
    otherts := @vs;
  end;
  with vs do begin
    psc := @SC;
    pc := @send_count;
    ps := @send_char_sum;
    othertid := @tidr;
    otherts := @vr;
  end;
  tidr := BeginThread(@recv_and_write_t, @vr);
  tids := BeginThread(@read_and_send_t, @vs);
  WaitForThreadTerminate(tidr, 0);
  WaitForThreadTerminate(tids, 0);

end;


procedure tcpclient(const hoststr: string; const port: integer);
var
  SC: tsocklen;
  SAddr: sockaddr;
  len: longint;
  send_count, send_char_sum: longint;
  tids: tthreadid;
  recv_count, recv_char_sum: longint;
  tidr: tthreadid;
  vs: mytcpds;
  vr: mytcpds;
begin
  send_count := 0;
  send_char_sum := 0;
  recv_count := 0;
  recv_char_sum := 0;

  SC := fpSocket(AF_INET, SOCK_STREAM, 0);
  if SocketError <> 0 then begin
    Perror('Client : fpSocket err ');
    Halt(100);
  end;
  SAddr.sin_family := AF_INET;
  SAddr.sin_port := htons(port);
  SAddr.sin_addr := StrToNetAddr(hoststr);
  len := sizeof(SAddr);
  if fpconnect(SC, @SAddr, len) = -1 then begin
    PError('Client : fpConnect err ');
    Halt(100);
  end;

  writeln(stderr, 'Client : fpconnect ' + NetAddrToStr(SAddr.sin_addr) +
    ':' + IntToStr(NToHs(SAddr.sin_port)));

  with vr do begin
    psc := @SC;
    pc := @recv_count;
    ps := @recv_char_sum;
    othertid := @tids;
    otherts := @vs;
  end;
  with vs do begin
    psc := @SC;
    pc := @send_count;
    ps := @send_char_sum;
    othertid := @tidr;
    otherts := @vr;
  end;
  tidr := BeginThread(@recv_and_write_t, @vr);
  tids := BeginThread(@read_and_send_t, @vs);
  WaitForThreadTerminate(tidr, 0);
  WaitForThreadTerminate(tids, 0);
end;


type
  pmyudpdss = ^myudpdss;
  pmyudpdsr = ^myudpdsr;

  myudpdss = record
    cs: TRTLCriticalSection;
    pSC: ^tsocklen;
    pRemoteAddr: ^sockaddr;
    pC, pS: ^longint;
    recvtid: ^TThreadID;
  end;

  myudpdsr = record
    cs: TRTLCriticalSection;
    pSC: ^tsocklen;
    pLastClientAddr: ^sockaddr;
    pC, pS: ^longint;
    sendtid: ^TThreadID;
  end;

function udp_recv(p: pointer): ptrint;
const
  BASE = 1;
  UDP_MAX_MSG_LEN = 500;
var
  v: pmyudpdsr;
  res: dword;
  tr: QWord;
  len, lenrd: longint;
  buf: array[BASE..UDP_MAX_MSG_LEN] of char;
  addr2: sockaddr;
begin
  v := pmyudpdsr(p);

  while True do begin
    len := sizeof(addr2);
    FillChar(addr2, len, 0);
    fpgetsockname(v^.pSC^, @addr2, @len);

    { currnet SC is client, not assign port }
    if NToHs(addr2.sin_port) = 0 then begin
      Sleep(100);
      Continue;
    end;

    break;
  end;

  tr := GetTickCount64;
  while True do begin
    len := sizeof(addr2);
    FillChar(addr2, len, 0);

    lenrd := fprecvfrom(v^.pSC^, @buf[BASE], UDP_MAX_MSG_LEN, 0, @addr2, @len);
    if (lenrd = -1) then begin
      perror('UDP Server : recvfrom err ');
      break;
    end;

    { save last client addr }
    if v^.pLastClientAddr <> nil then
      try
        EnterCriticalSection(v^.cs);
        v^.pLastClientAddr^ := addr2;
      finally
        LeaveCriticalSection(v^.cs);
      end;

    v^.pC^ += 1;
    v^.pS^ += lenrd;
    Write(Output, buf[BASE..lenrd]);
    //Flush(Output);                { }

    if (lenrd > 0) and (lenrd < UDP_MAX_MSG_LEN) and (v^.pS^ > UDP_MAX_MSG_LEN) and
      (v^.pS^ mod UDP_MAX_MSG_LEN = lenrd) then begin
      writeln(stderr, 'UDP recv recv_count: ', v^.pC^, ', recv_char_sum: ', v^.pS^,
        '. Press Ctrl-Z break ..');
      Flush(Output);
    end;
  end;

  if v^.sendtid <> nil then begin
    Sleep(100);
    res := KillThread(v^.sendtid^);
    writeln(stderr, 'UDP recv thread end, kill send thread stat ', res);
  end;
  writeln(stderr, 'UDP recv used  ': 20, GetTickCount64 - tr, ' ms');
  Flush(Output);
  Result := 0;
end;


function udp_send(p: pointer): ptrint;
const
  BASE = 1;
  UDP_MAX_MSG_LEN = 500;
var
  v: pmyudpdss;
  buffer: array[BASE..UDP_MAX_MSG_LEN] of char;
  len, lensd: longint;
  addr_t: sockaddr;
  res: dword;
  ts: QWord;
begin
  v := pmyudpdss(p);

  while True do begin
    try
      EnterCriticalSection(v^.cs);
      addr_t := v^.pRemoteAddr^;
    finally
      LeaveCriticalSection(v^.cs);
    end;
      { unknow remote addr, then not to read stdin
        waiting for recv thread set lastClientAddr
      }
    if NToHs(addr_t.sin_port) = 0 then begin
      Sleep(100);
      continue;
    end;

    break;
  end;

  lensd := fpsendto(v^.pSC^, @buffer[BASE], 0, 0, @addr_t, sizeof(addr_t));
  writeln(stderr, 'UDP send init empty ', lensd, ' bytes');

  ts := GetTickCount64;
  while True do begin
    try
      EnterCriticalSection(v^.cs);
      addr_t := v^.pRemoteAddr^;
    finally
      LeaveCriticalSection(v^.cs);
    end;

{$I-}
    BlockRead(input_b, buffer, UDP_MAX_MSG_LEN, len);
    if IOResult <> 0 then break;
{$I+}
    if len = 0 then break;

    lensd := fpsendto(v^.pSC^, @buffer[BASE], len, 0, @addr_t, sizeof(addr_t));
    if lensd = -1 then begin
      writeln(stderr, 'UDP send fail, quit send thread.');
      break;
    end;

    v^.pC^ += 1;
    v^.pS^ += lensd;
    sleep(1); { maybe recvfrom slower then sendto, sleep 1+ms  }
  end;

  if v^.recvtid <> nil then begin
    Sleep(100);
    res := KillThread(v^.recvtid^);
    writeln(stderr, 'UDP send thread end, kill recv thread stat ', res);
  end;
  writeln(stderr, 'UDP send used ': 20, GetTickCount64 - ts, ' ms');
  Result := 0;
end;


procedure udpserver(const port: integer);
var
  mycs: TRTLCriticalSection;
  vr: myudpdsr;
  vs: myudpdss;
  SS: tsocklen;
  SAddr, CAddr: sockaddr;
  tidr, tids: TThreadID;
  send_count, send_char_sum: longint;
  recv_count, recv_char_sum: longint;
begin
  recv_count := 0;
  recv_char_sum := 0;
  send_count := 0;
  send_char_sum := 0;

  SS := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if SocketError <> 0 then begin
    Perror('UDP Server : Socket : ');
    Halt(100);
  end;
  SAddr.sin_family := AF_INET;
  SAddr.sin_port := htons(port);
  SAddr.sin_addr.s_addr := 0;   // sin_addr := StrToNetAddr('0.0.0.0');

  if fpbind(SS, @Saddr, sizeof(SAddr)) = -1 then begin
    PError('UDP Server : fpbind : ');
    Halt(100);
  end;
  Writeln(stderr, 'UDP Server : Waiting for Connect from Client');

  FillChar(CAddr, sizeof(CAddr), 0);
  InitCriticalSection(mycs);
  with vs do begin
    cs := mycs;
    pSC := @SS;
    pRemoteAddr := @CAddr;
    pC := @send_count;
    pS := @send_char_sum;
    recvtid := @tidr;
  end;
  with vr do begin
    cs := mycs;
    pSC := @SS;
    pLastClientAddr := @CAddr;
    pC := @recv_count;
    pS := @recv_char_sum;
    sendtid := @tids;
  end;
  tidr := BeginThread(@udp_recv, @vr);
  tids := BeginThread(@udp_send, @vs);
  WaitForThreadTerminate(tids, 0);
  WaitForThreadTerminate(tidr, 0); { when send thread ended, will kill recv thread }
  DoneCriticalSection(mycs);

  writeln(stderr, 'UDP Client : send_count ', send_count, ' send_char_sum: ',
    send_char_sum);
  writeln(stderr, 'UDP Client : recv_count ', recv_count, ' recv_char_sum: ',
    recv_char_sum);
  CloseSocket(SS);
end;

procedure udpclient(const hoststr: string; const port: integer);
var
  mycs: TRTLCriticalSection;
  vr: myudpdsr;
  vs: myudpdss;
  SC: tsocklen;
  tidr, tids: TThreadID;
  Saddr: sockaddr;
  send_count, send_char_sum: longint;
  recv_count, recv_char_sum: longint;
begin
  recv_count := 0;
  recv_char_sum := 0;
  send_count := 0;
  send_char_sum := 0;
  SC := fpSocket(AF_INET, SOCK_DGRAM, 0);
  if SocketError <> 0 then begin
    Perror('UDP Client : Socket err ');
    Halt(100);
  end;
  Saddr.sin_family := AF_INET;
  Saddr.sin_port := htons(port);
  Saddr.sin_addr := StrToNetAddr(hoststr);

  InitCriticalSection(mycs);
  with vs do begin
    cs := mycs;
    pSC := @SC;
    pRemoteAddr := @Saddr;
    pC := @send_count;
    pS := @send_char_sum;
    recvtid := @tidr;
  end;
  with vr do begin
    cs := mycs;
    pSC := @SC;
    pLastClientAddr := nil;
    pC := @recv_count;
    pS := @recv_char_sum;
    sendtid := @tids;
  end;
  writeln(stderr, 'UDP Client : sddr= ', NetAddrToStr(Saddr.sin_addr), ':',
    NToHs(Saddr.sin_port));
  tidr := BeginThread(@udp_recv, @vr);
  tids := BeginThread(@udp_send, @vs);
  WaitForThreadTerminate(tids, 0);
  WaitForThreadTerminate(tidr, 0);
  DoneCriticalSection(mycs);

  writeln(stderr, 'UDP Client : send_count ', send_count, ' send_char_sum: ',
    send_char_sum);
  writeln(stderr, 'UDP Client : recv_count ', recv_count, ' recv_char_sum: ',
    recv_char_sum);
  CloseSocket(SC);

end;

initialization
  begin
    Assign(input_b, ''); { reset stdin can read binary data  }
    filemode := 0;
    reset(input_b, 1);
  end;

end.
