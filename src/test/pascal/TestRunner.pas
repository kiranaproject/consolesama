// TestRunner.pas — console test runner for consolesama
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

program TestRunner;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpcunit, testregistry, consoletestrunner,
  ConsoleSama.Vt.Test,
  ConsoleSama.Keys.Test,
  ConsoleSama.Pty.Test,
  ConsoleSama.Window.Test;

var
  Application: TTestRunner;

begin
  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Run();
  finally
    Application.Free();
  end;
end.
