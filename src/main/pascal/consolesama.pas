// consolesama.pas — a MATE Terminal-style console for the Floria Toolkit
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

program consolesama;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  ftpas, ftpas.app, ftpas.types,
  ConsoleSama.Window;

var
  MainWindow: TConsoleSamaWindow;

function DebugRequested(): Boolean;
var
  i: Integer;
begin
  for i := 1 to ParamCount() do
    if (ParamStr(i) = '--debug') or (ParamStr(i) = '-d') then
      Exit(True);
  Result := False;
end;

begin
  MainWindow := TConsoleSamaWindow.Create(DebugRequested());
  try
    MainWindow.Show();
    FtApp().Run();
  finally
    MainWindow.Free();
  end;
end.
