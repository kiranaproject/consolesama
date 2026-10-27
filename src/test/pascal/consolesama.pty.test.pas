// consolesama.pty.test.pas — unit tests for pseudo terminal session
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Pty.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ConsoleSama.Pty;

type
  TPtySessionTest = class(TTestCase)
  private
    FPTY: TTerminalPTY;
  protected
    procedure TearDown(); override;
  published
    procedure TestPtySpawnAndAlive();
    procedure TestPtyWriteAndReadOutput();
    procedure TestPtyResize();
    procedure TestPtyTermination();
  end;

implementation

procedure TPtySessionTest.TearDown();
begin
  if FPTY <> nil then
    FreeAndNil(FPTY);
end;

procedure TPtySessionTest.TestPtySpawnAndAlive();
begin
  FPTY := TTerminalPTY.Create(80, 24, '/bin/sh');
  AssertTrue('Master FD should be valid', FPTY.MasterFd >= 0);
  AssertTrue('Child PID should be > 0', FPTY.ChildPid > 0);
  AssertTrue('Slave name should not be empty', FPTY.SlaveName <> '');
  AssertTrue('Process should be alive', FPTY.PollAlive());
end;

procedure TPtySessionTest.TestPtyWriteAndReadOutput();
var
  buf: array[0..1023] of Byte;
  n, total: Integer;
  received: string;
  startTick: QWord;
begin
  FPTY := TTerminalPTY.Create(80, 24, '/bin/sh');
  AssertTrue('Process should be alive', FPTY.PollAlive());

  // Send an echo command
  FPTY.WriteInput('echo PTY_TEST_OK'#10);

  received := '';
  startTick := GetTickCount64();
  while (GetTickCount64() - startTick < 1000) and (Pos('PTY_TEST_OK', received) = 0) do
  begin
    n := FPTY.ReadOutput(@buf[0], SizeOf(buf) - 1);
    if n > 0 then
    begin
      buf[n] := 0;
      received := received + string(PChar(@buf[0]));
    end
    else
      Sleep(10);
  end;

  AssertTrue('Output should contain PTY_TEST_OK', Pos('PTY_TEST_OK', received) > 0);
end;

procedure TPtySessionTest.TestPtyResize();
begin
  FPTY := TTerminalPTY.Create(80, 24, '/bin/sh');
  AssertEquals('Initial cols', 80, FPTY.Cols);
  AssertEquals('Initial rows', 24, FPTY.Rows);

  FPTY.Resize(120, 40);
  AssertEquals('Resized cols', 120, FPTY.Cols);
  AssertEquals('Resized rows', 40, FPTY.Rows);
end;

procedure TPtySessionTest.TestPtyTermination();
begin
  FPTY := TTerminalPTY.Create(80, 24, '/bin/sh');
  AssertTrue('Initially alive', FPTY.PollAlive());

  FPTY.Terminate();
  AssertEquals('Master closed', -1, FPTY.MasterFd);
  AssertTrue('Exited marked true', FPTY.Exited);
end;

initialization
  RegisterTest(TPtySessionTest);

end.
