// consolesama.pas — a MATE Terminal-style console for the Floria Toolkit
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

program consolesama;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  ftpas, ftpas.app, ftpas.types,
  ConsoleSama.Ftml.Res,
  ConsoleSama.Window;

var
  MainWindow: TConsoleSamaWindow;
begin
  MainWindow := TConsoleSamaWindow.Create();
  try
    MainWindow.Show();
    FtApp().Run();
  finally
    MainWindow.Free();
  end;
end.
