// consolesama.window.test.pas — integration tests for application window and FTML
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Window.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  ftpas, ftpas.api, ftpas.types, ftpas.widget, ftpas.font,
  ConsoleSama.Ftml.Res,
  ConsoleSama.Terminal,
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
    procedure TestMainMenuPositionOnResize();
    procedure TestTerminalSelectionLifecycle();
    procedure TestTerminalFontConfiguration();
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

procedure TConsoleWindowTest.TestTerminalFontConfiguration();
var
  term: TConsoleTerminalView;
  advI, advW, advM: Double;
  initialSize: Integer;
begin
  term := FWindow.ActiveTerminal();
  AssertNotNull('Active terminal should exist', term);
  AssertTrue('Terminal font ref should be valid', term.FontRef.Valid);

  // Verify monospace font family contains 'Ubuntu Mono' or 'Mono'
  AssertTrue('Font family should be fixed-width mono: ' + term.FontFamily,
    (Pos('Mono', term.FontFamily) > 0) or (Pos('mono', term.FontFamily) > 0));

  // Verify fixed width: character advances for 'i', 'W', 'm' must be equal
  advI := term.FontRef.AsciiAdvance('i');
  advW := term.FontRef.AsciiAdvance('W');
  advM := term.FontRef.AsciiAdvance('m');

  AssertEquals('Monospace advance for i equals W', advI, advW, 0.001);
  AssertEquals('Monospace advance for m equals W', advM, advW, 0.001);
  AssertEquals('Cell width matches font advance', Ceil(advW), Round(term.CellWidth));

  // Test Zoom retention of font family
  initialSize := term.FontSize;
  term.Zoom(2);
  AssertEquals('Zoom in increments font size by 2', initialSize + 2, term.FontSize);
  AssertTrue('Font family preserved after zoom', (Pos('Mono', term.FontDesc) > 0));

  term.ResetZoom();
  AssertEquals('ResetZoom restores base font size', term.BaseFontSize, term.FontSize);
  AssertEquals('Font size restored to initial', initialSize, term.FontSize);
end;

procedure TConsoleWindowTest.TestMainMenuPositionOnResize();
var
  menuW: TFtWidget;
begin
  menuW := FWindow.FindWidget('menuBar');
  AssertNotNull('Menu bar widget should exist', menuW);
  AssertEquals('Menu bar initially pinned at X=0', 0, menuW.X);
  AssertEquals('Menu bar initially pinned at Y=0', 0, menuW.Y);

  // Resize window to different dimensions and offset coordinates
  FWindow.SetBounds(150, 120, 1024, 768);

  AssertEquals('Menu bar must stay at X=0 after window resize', 0, menuW.X);
  AssertEquals('Menu bar must stay at Y=0 after window resize', 0, menuW.Y);
end;

procedure TConsoleWindowTest.TestTerminalSelectionLifecycle();
var
  term: TConsoleTerminalView;
begin
  term := FWindow.ActiveTerminal();
  AssertNotNull('Active terminal should exist', term);

  // Initial state: no selection, not selecting
  AssertFalse('Initially not selecting', term.Selecting);
  AssertFalse('Initially no selection active', term.HasSelection);

  // 1. Single click (mouse down and release at same coordinate):
  // Must NOT activate selection and must NOT get stuck in selecting mode
  term.HandleMouseDown(nil, 60, 60, 1);
  AssertTrue('Selecting while button held down', term.Selecting);
  AssertFalse('No selection active before drag', term.HasSelection);

  term.HandleMouseUp(nil, 60, 60, 1);
  AssertFalse('Selecting false after release', term.Selecting);
  AssertFalse('No selection active after single click', term.HasSelection);

  // 2. Hovering mouse without button held:
  // Must NOT enter drag-select mode
  term.HandleMouseMove(nil, 240, 60);
  AssertFalse('Hover must not trigger selecting', term.Selecting);
  AssertFalse('Hover must not create selection', term.HasSelection);

  // 3. Drag select (mouse down, drag across columns, mouse up):
  term.HandleMouseDown(nil, 60, 60, 1);
  term.HandleMouseMove(nil, 240, 60);
  AssertTrue('Selecting is true while dragging', term.Selecting);
  AssertTrue('Selection is active while dragging', term.HasSelection);

  term.HandleMouseUp(nil, 240, 60, 1);
  AssertFalse('Selecting is false after mouse up', term.Selecting);
  AssertTrue('Selection remains active after drag release', term.HasSelection);

  // 4. Moving mouse after drag without button held:
  // Must NOT expand or alter the selection
  term.HandleMouseMove(nil, 400, 120);
  AssertFalse('Hover after drag must not be selecting', term.Selecting);
  AssertTrue('Selection stays active until cleared', term.HasSelection);

  // 5. Single click clears the previous selection:
  term.HandleMouseDown(nil, 300, 300, 1);
  AssertFalse('New click clears previous selection', term.HasSelection);
  term.HandleMouseUp(nil, 300, 300, 1);
  AssertFalse('After click release, no selection', term.HasSelection);
  AssertFalse('Not selecting', term.Selecting);
end;

initialization
  RegisterTest(TConsoleWindowTest);

end.
