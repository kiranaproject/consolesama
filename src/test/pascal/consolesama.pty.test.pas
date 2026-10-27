// consolesama.pty.test.pas — unit tests for pseudo terminal session
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Pty.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ConsoleSama.Pty, ConsoleSama.Vt;

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
    procedure TestInteractiveBashResizePromptNoDuplication();
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

procedure TPtySessionTest.TestInteractiveBashResizePromptNoDuplication();
var
  screen: TTerminalEmulator;
  buf: array[0..2047] of Byte;
  promptCount: Integer;

  procedure PumpPty(ATimeoutMs: Integer);
  var
    t: QWord;
    bytesRead: Integer;
  begin
    t := GetTickCount64();
    while GetTickCount64() - t < ATimeoutMs do
    begin
      bytesRead := FPTY.ReadOutput(@buf[0], SizeOf(buf));
      if bytesRead > 0 then
        screen.Feed(@buf[0], bytesRead)
      else
        Sleep(10);
    end;
  end;

  function CountPromptInScreen(): Integer;
  var
    r: Integer;
    line: string;
  begin
    Result := 0;
    for r := 0 to screen.Rows - 1 do
    begin
      line := screen.ViewLineText(r);
      if Pos('UNIQUE_PROMPT$', line) > 0 then
        Inc(Result);
    end;
  end;

begin
  FPTY := TTerminalPTY.Create(80, 24, '/bin/bash');
  screen := TTerminalEmulator.Create(80, 24);
  try
    // Set custom prompt and clear screen
    FPTY.WriteInput('PS1="UNIQUE_PROMPT$ "'#10'clear'#10);
    PumpPty(500);

    promptCount := CountPromptInScreen();
    AssertEquals('Initial prompt count at 80 cols', 1, promptCount);

    // Resize down to 30 columns:
    screen.Resize(30, 24, False);
    FPTY.Resize(30, 24);
    PumpPty(200);

    promptCount := CountPromptInScreen();
    AssertEquals('Prompt count after resize to 30 cols must be exactly 1 (no duplicate)', 1, promptCount);

    // Resize down to 20 columns:
    screen.Resize(20, 24, False);
    FPTY.Resize(20, 24);
    PumpPty(200);

    promptCount := CountPromptInScreen();
    AssertEquals('Prompt count after resize to 20 cols must be exactly 1 (no triple)', 1, promptCount);

    // Resize back to 80 columns:
    screen.Resize(80, 24, False);
    FPTY.Resize(80, 24);
    PumpPty(200);

    promptCount := CountPromptInScreen();
    AssertEquals('Prompt count after resize back to 80 cols must be exactly 1', 1, promptCount);

    // Now test with active typed text on command line:
    FPTY.WriteInput('echo "testing active command line resize"');
    PumpPty(200);

    // Resize across multiple widths while command text is actively entered:
    screen.Resize(45, 24, False);
    FPTY.Resize(45, 24);
    PumpPty(200);
    promptCount := CountPromptInScreen();
    AssertEquals('Prompt count with typed command at 45 cols', 1, promptCount);

    screen.Resize(25, 24, False);
    FPTY.Resize(25, 24);
    PumpPty(200);
    promptCount := CountPromptInScreen();
    AssertEquals('Prompt count with typed command at 25 cols', 1, promptCount);

    screen.Resize(80, 24, False);
    FPTY.Resize(80, 24);
    PumpPty(200);
    promptCount := CountPromptInScreen();
    AssertEquals('Prompt count with typed command back at 80 cols', 1, promptCount);
  finally
    screen.Free();
  end;
end;

initialization
  RegisterTest(TPtySessionTest);

end.
