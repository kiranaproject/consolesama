// consolesama.window.test.pas — integration tests for application window and FTML
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Window.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  ftpas, ftpas.api, ftpas.types, ftpas.app, ftpas.widget, ftpas.controls, ftpas.layouts, ftpas.font,
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
    procedure TestStatusBarInitialPosition();
    procedure TestThemeColorAdaptation();
    procedure TestContainerAndPanelSeparation();
    procedure TestTerminalWidthFollowsWindowResize();
    procedure TestTerminalScrollBarLifecycle();
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

procedure TConsoleWindowTest.TestStatusBarInitialPosition();
var
  sb, st: TFtWidget;
begin
  sb := FWindow.FindWidget('statusBar');
  AssertNotNull('Status bar widget should exist', sb);
  st := FWindow.FindWidget('statusText');
  AssertNotNull('Status text widget should exist', st);

  // Status bar should be docked to the bottom from the very start, without any manual window resize
  AssertEquals('Status bar X is 0', 0, sb.X);
  AssertEquals('Status bar width fills window width', FWindow.Width, sb.Width);
  AssertEquals('Status bar bottom edge touches window bottom', FWindow.Height, sb.Y + sb.Height);

  // Status text should be vertically positioned inside the status bar
  AssertTrue('Status text Y is inside status bar: st.Y=' + IntToStr(st.Y) + ', sb.Y=' + IntToStr(sb.Y),
    st.Y >= sb.Y);
  AssertTrue('Status text bottom is within status bar: st.bottom=' + IntToStr(st.Y + st.Height) + ', sb.bottom=' + IntToStr(sb.Y + sb.Height),
    (st.Y + st.Height) <= (sb.Y + sb.Height));
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

procedure TConsoleWindowTest.TestThemeColorAdaptation();
var
  term: TConsoleTerminalView;
  origDark: Boolean;
begin
  term := FWindow.ActiveTerminal();
  AssertNotNull('Active terminal should exist', term);

  origDark := FtApp().DarkMode;
  try
    // 1. Light mode test
    FtApp().DarkMode := False;
    term.RefreshThemeColors();
    AssertFalse('Terminal should be in light mode', term.IsDark);
    AssertEquals('Light mode background is white', $00FFFFFF, term.DefaultBackground.Value);
    AssertEquals('Light mode foreground is slate', $001E293B, term.DefaultForeground.Value);

    // 2. Dark mode test
    FtApp().DarkMode := True;
    term.RefreshThemeColors();
    AssertTrue('Terminal should be in dark mode', term.IsDark);
    AssertEquals('Dark mode background is dark navy', $00171A21, term.DefaultBackground.Value);
    AssertEquals('Dark mode foreground is light slate', $00D8DEE9, term.DefaultForeground.Value);
  finally
    FtApp().DarkMode := origDark;
    term.RefreshThemeColors();
  end;
end;

procedure TConsoleWindowTest.TestContainerAndPanelSeparation();
var
  rootW, statusW: TFtWidget;
begin
  rootW := FWindow.FindWidget('root');
  AssertNotNull('Root container should exist', rootW);
  AssertTrue('Root is TFtContainer', rootW is TFtContainer);
  AssertFalse('Root is NOT TFtPanel', rootW is TFtPanel);

  statusW := FWindow.FindWidget('statusBar');
  AssertNotNull('Status bar widget should exist', statusW);
  AssertTrue('Status bar is TFtPanel', statusW is TFtPanel);
end;

procedure TConsoleWindowTest.TestTerminalWidthFollowsWindowResize();
var
  tab: TConsoleTab;
  initialW, initialCols: Integer;
begin
  tab := FWindow.ActiveTab();
  AssertNotNull('Active tab should exist', tab);
  AssertNotNull('Terminal view should exist', tab.View);

  initialW := tab.View.Width;
  initialCols := tab.View.TermCols;
  AssertTrue('Initial width > 800: ' + IntToStr(initialW), initialW >= 800);
  AssertTrue('Initial cols > 60: ' + IntToStr(initialCols), initialCols >= 60);

  // 1. Expand window width to 1400
  FWindow.SetBounds(0, 0, 1400, 700);

  AssertTrue('Terminal width expanded: ' + IntToStr(tab.View.Width),
    tab.View.Width > initialW + 300);
  AssertTrue('Terminal columns increased: ' + IntToStr(tab.View.TermCols),
    tab.View.TermCols > initialCols + 20);

  // 2. Shrink window width to 800
  FWindow.SetBounds(0, 0, 800, 600);

  AssertTrue('Terminal width shrunk: ' + IntToStr(tab.View.Width),
    tab.View.Width < initialW);
  AssertTrue('Terminal columns decreased: ' + IntToStr(tab.View.TermCols),
    tab.View.TermCols < initialCols);
end;

procedure TConsoleWindowTest.TestTerminalScrollBarLifecycle();
var
  tab: TConsoleTab;
  sb: TFtScrollBar;
  i: Integer;
begin
  tab := FWindow.ActiveTab();
  AssertNotNull('Active tab should exist', tab);
  AssertNotNull('Terminal view should exist', tab.View);
  sb := tab.ScrollBar;
  AssertNotNull('Scroll bar should exist', sb);
  AssertEquals('Scroll bar must be vertical', Ord(ftsboVertical), Ord(sb.Orientation));

  // Scrollbar must be pinned to the right edge of the terminal view
  AssertEquals('ScrollBar X is next to View X+W', tab.View.X + tab.View.Width, sb.X);
  AssertEquals('ScrollBar height matches View height', tab.View.Height, sb.Height);

  // Initially 0 history lines
  AssertEquals('Initially 0 history count', 0, tab.View.Screen.HistoryCount());
  AssertEquals('Scrollbar max is 0', 0.0, sb.Max, 0.001);

  // Feed 50 lines to generate scrollback history
  for i := 1 to 50 do
    tab.View.Screen.Feed('Line ' + IntToStr(i) + #13#10);

  tab.View.UpdateScrollBar();
  AssertTrue('History count should be > 0: ' + IntToStr(tab.View.Screen.HistoryCount()),
    tab.View.Screen.HistoryCount() > 0);
  AssertEquals('Scrollbar max matches history count', tab.View.Screen.HistoryCount(), Round(sb.Max));
  AssertEquals('Scrollbar value at bottom equals max', sb.Max, sb.Value, 0.001);

  // Test scrolling via scrollbar value
  sb.Value := 0.0; // scroll to top
  AssertTrue('Screen scroll offset changed after scrolling to top: ' + IntToStr(tab.View.Screen.ScrollOffset()),
    tab.View.Screen.ScrollOffset() > 0);

  // Scrolling to bottom
  tab.View.ScrollToEnd();
  AssertEquals('Scroll offset is 0 after ScrollToEnd', 0, tab.View.Screen.ScrollOffset());
  AssertEquals('Scrollbar value returned to max', sb.Max, sb.Value, 0.001);
end;

initialization
  RegisterTest(TConsoleWindowTest);

end.
