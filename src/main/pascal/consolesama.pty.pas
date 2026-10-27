// consolesama.pty.pas — pseudo terminal (PTY) session management
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Pty;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, UnixType, ctypes;

type
  // TTerminalPTY — one shell process attached to one PTY master
  TTerminalPTY = class
  private
    FMaster: Integer;
    FSlaveName: string;
    FChildPid: TPid;
    FExited: Boolean;
    FExitStatus: Integer;
    FCols: Integer;
    FRows: Integer;
    FLastError: string;
    procedure SetWinsize(ACols, ARows: Integer);
    function  Spawn(const AShell: string; ACwd: string): Boolean;
  public
    constructor Create(ACols, ARows: Integer; const AShell: string = ''; ACwd: string = '');
    destructor Destroy(); override;

    // Read pending output: >0 bytes, 0 nothing available, -1 EOF / child closed.
    function  ReadOutput(ABuffer: PByte; AMaxBytes: Integer): Integer;
    // Write keyboard input to the shell.
    function  WriteInput(const AData: string): Integer;
    procedure Resize(ACols, ARows: Integer);
    function  PollAlive(): Boolean;
    procedure Terminate();

    property MasterFd: Integer read FMaster;
    property SlaveName: string read FSlaveName;
    property ChildPid: TPid read FChildPid;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property Exited: Boolean read FExited;
    property ExitStatus: Integer read FExitStatus;
    property LastError: string read FLastError;
  end;

implementation

const
  O_RDWR     = 2;
  O_NOCTTY   = $100;
  O_NONBLOCK = $800;
  TIOCSCTTY  = $540E;
  TIOCSWINSZ = $5414;
  SIG_HUP    = 1;
  SIG_KILL   = 9;
  WNOHANG    = 1;
  F_SETFL    = 4;

type
  TWinsize = record
    ws_row: Word;
    ws_col: Word;
    ws_xpixel: Word;
    ws_ypixel: Word;
  end;

function posix_openpt(flags: cint): cint; cdecl; external 'c';
function grantpt(fd: cint): cint; cdecl; external 'c';
function unlockpt(fd: cint): cint; cdecl; external 'c';
function ptsname_r(fd: cint; buf: PChar; buflen: size_t): cint; cdecl; external 'c';
function ioctl(fd: cint; request: culong; arg: Pointer): cint; cdecl; external 'c';
function execvp(file_: PChar; argv: PPChar): cint; cdecl; external 'c';
function setsid(): TPid; cdecl; external 'c';
function setenv(name, value: PChar; overwrite: cint): cint; cdecl; external 'c';
function fcntl(fd: cint; cmd: cint; arg: cint): cint; cdecl; external 'c';

constructor TTerminalPTY.Create(ACols, ARows: Integer; const AShell: string;
  ACwd: string);
var
  shell: string;
begin
  inherited Create();
  FMaster := -1;
  FChildPid := 0;
  FExited := False;
  FExitStatus := 0;
  FCols := ACols;
  FRows := ARows;
  FSlaveName := '';

  shell := AShell;
  if shell = '' then
    shell := GetEnvironmentVariable('SHELL');
  if (shell = '') or (not FileExists(shell)) then
  begin
    if FileExists('/bin/bash') then
      shell := '/bin/bash'
    else
      shell := '/bin/sh';
  end;

  if not Spawn(shell, ACwd) then
    WriteLn(StdErr, '[pty] failed to spawn ', shell, ': ', FLastError);
end;

destructor TTerminalPTY.Destroy();
begin
  Terminate();
  inherited Destroy();
end;

function TTerminalPTY.Spawn(const AShell: string; ACwd: string): Boolean;
var
  master: cint;
  nameBuf: array[0..255] of Char;
  argv: array[0..1] of PChar;
  pid: TPid;
  slaveFd: cint;
begin
  Result := False;
  master := posix_openpt(O_RDWR or O_NOCTTY);
  if master < 0 then
  begin
    FLastError := 'posix_openpt failed';
    Exit;
  end;

  if (grantpt(master) <> 0) or (unlockpt(master) <> 0) then
  begin
    FLastError := 'grantpt/unlockpt failed';
    fpClose(master);
    Exit;
  end;

  FillChar(nameBuf, SizeOf(nameBuf), 0);
  if ptsname_r(master, @nameBuf[0], SizeOf(nameBuf)) <> 0 then
  begin
    FLastError := 'ptsname_r failed';
    fpClose(master);
    Exit;
  end;
  FSlaveName := string(PChar(@nameBuf[0]));

  // Non-blocking master so the UI thread never stalls on an idle shell.
  fcntl(master, F_SETFL, O_NONBLOCK);

  pid := fpFork();
  if pid < 0 then
  begin
    FLastError := 'fork failed';
    fpClose(master);
    Exit;
  end;

  if pid = 0 then
  begin
    // Child: detach, attach the slave as controlling terminal, exec shell.
    setsid();
    slaveFd := fpOpen(PChar(FSlaveName), O_RDWR);
    if slaveFd < 0 then
      Halt(1);
    ioctl(slaveFd, TIOCSCTTY, nil);
    fpDup2(slaveFd, 0);
    fpDup2(slaveFd, 1);
    fpDup2(slaveFd, 2);
    if slaveFd > 2 then
      fpClose(slaveFd);

    setenv('TERM', 'xterm-256color', 1);
    setenv('COLORTERM', 'truecolor', 1);
    setenv('SHELL', PChar(AShell), 1);
    if ACwd <> '' then
      fpChDir(ACwd);

    argv[0] := PChar(AShell);
    argv[1] := nil;
    execvp(PChar(AShell), @argv[0]);
    Halt(127);
  end;

  // Parent process
  FMaster := master;
  FChildPid := pid;
  SetWinsize(FCols, FRows);
  Result := True;
end;

procedure TTerminalPTY.SetWinsize(ACols, ARows: Integer);
var
  ws: TWinsize;
begin
  if FMaster < 0 then Exit;
  if ACols < 1 then ACols := 1;
  if ARows < 1 then ARows := 1;
  ws.ws_col := Word(ACols);
  ws.ws_row := Word(ARows);
  ws.ws_xpixel := 0;
  ws.ws_ypixel := 0;
  ioctl(FMaster, TIOCSWINSZ, @ws);
end;

function TTerminalPTY.ReadOutput(ABuffer: PByte; AMaxBytes: Integer): Integer;
var
  n: TSSize;
  err: cint;
begin
  Result := 0;
  if (FMaster < 0) or FExited then Exit;
  n := fpRead(FMaster, PChar(ABuffer), AMaxBytes);
  if n > 0 then
    Result := Integer(n)
  else if n = 0 then
    Result := -1
  else
  begin
    err := fpGetErrno();
    if err = ESysEAGAIN then
      Result := 0
    else
      Result := -1;
  end;
end;

function TTerminalPTY.WriteInput(const AData: string): Integer;
var
  total, n, remaining: TSSize;
  p: PChar;
begin
  Result := -1;
  if FMaster < 0 then Exit;
  if AData = '' then Exit(0);

  total := 0;
  p := PChar(AData);
  remaining := Length(AData);
  while remaining > 0 do
  begin
    n := fpWrite(FMaster, p, remaining);
    if n < 0 then
    begin
      if fpGetErrno() = ESysEAGAIN then
        Continue
      else
        Exit(-1);
    end;
    Inc(total, n);
    Inc(p, n);
    Dec(remaining, n);
  end;
  Result := Integer(total);
end;

procedure TTerminalPTY.Resize(ACols, ARows: Integer);
begin
  if (ACols = FCols) and (ARows = FRows) then Exit;
  FCols := ACols;
  FRows := ARows;
  SetWinsize(ACols, ARows);
end;

function TTerminalPTY.PollAlive(): Boolean;
var
  status: cint;
  r: TPid;
begin
  Result := False;
  if FExited or (FChildPid <= 0) then Exit;
  status := 0;
  r := fpWaitPid(FChildPid, @status, WNOHANG);
  if r = FChildPid then
  begin
    FExited := True;
    FExitStatus := status;
    Exit(False);
  end;
  Result := True;
end;

procedure TTerminalPTY.Terminate();
begin
  if FMaster >= 0 then
  begin
    if (FChildPid > 0) and not FExited then
    begin
      fpKill(FChildPid, SIG_HUP);
      fpKill(FChildPid, SIG_KILL);
    end;
    fpClose(FMaster);
    FMaster := -1;
  end;
  if (FChildPid > 0) and not FExited then
    FExited := True;
end;

end.
