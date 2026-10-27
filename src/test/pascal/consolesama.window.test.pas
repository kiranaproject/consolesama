// consolesama.window.test.pas — integration tests for application window and FTML
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Window.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ftpas, ftpas.api, ftpas.types,
  ConsoleSama.Ftml.Res,
  ConsoleSama.Window;

type
  TConsoleWindowTest = class(TTestCase)
  private
    FWindow: TConsoleSamaWindow;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestWindowCreation();
    procedure TestTabManagement();
  end;

implementation

procedure TConsoleWindowTest.SetUp();
begin
  if not FtIsLibLoaded() then
  begin
    if not FtLoadLib() then
      Fail('Could not load libft.so');
  end;

  try
    FtApp().Initialize();
  except
    on E: Exception do
      Fail('FtApp.Initialize failed: ' + E.Message);
  end;

  FWindow := TConsoleSamaWindow.Create();
end;

procedure TConsoleWindowTest.TearDown();
begin
  if FWindow <> nil then
    FreeAndNil(FWindow);
end;

procedure TConsoleWindowTest.TestWindowCreation();
begin
  AssertNotNull('Window should be created', FWindow);
  AssertNotNull('Notebook should be found from FTML', FWindow.Notebook);
  AssertTrue('Window should have at least 1 tab', FWindow.Notebook.PageCount >= 1);
end;

procedure TConsoleWindowTest.TestTabManagement();
begin
  AssertEquals('Initial tab count', 1, FWindow.Notebook.PageCount);
end;

initialization
  RegisterTest(TConsoleWindowTest);

end.
