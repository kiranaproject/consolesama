// consolesama.vt.test.pas — unit tests for terminal emulator core
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Vt.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ConsoleSama.Vt;

type
  TVtEmulatorTest = class(TTestCase)
  private
    FScreen: TTerminalEmulator;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestInitAndDefaults();
    procedure TestFeedAsciiText();
    procedure TestCursorMovement();
    procedure TestAutoWrap();
    procedure TestSgrFormatting();
    procedure TestEraseInLineAndDisplay();
    procedure TestScrollbackAndScrollView();
    procedure TestAlternateScreen();
    procedure TestOscTitle();
    procedure TestBracketedPaste();
  end;

implementation

procedure TVtEmulatorTest.SetUp();
begin
  FScreen := TTerminalEmulator.Create(80, 24);
end;

procedure TVtEmulatorTest.TearDown();
begin
  FreeAndNil(FScreen);
end;

procedure TVtEmulatorTest.TestInitAndDefaults();
begin
  AssertEquals('Default Cols should be 80', 80, FScreen.Cols);
  AssertEquals('Default Rows should be 24', 24, FScreen.Rows);
  AssertEquals('Initial CursorX', 0, FScreen.CursorX);
  AssertEquals('Initial CursorY', 0, FScreen.CursorY);
  AssertTrue('Cursor should be visible', FScreen.CursorVisible);
  AssertFalse('AltScreen should be off', FScreen.AltScreen);
  AssertFalse('BracketedPaste should be off', FScreen.BracketedPaste);
end;

procedure TVtEmulatorTest.TestFeedAsciiText();
begin
  FScreen.Feed('Hello, consolesama!');
  AssertEquals('CursorX should advance', 19, FScreen.CursorX);
  AssertEquals('CursorY should stay 0', 0, FScreen.CursorY);
  AssertEquals('Rendered line text', 'Hello, consolesama!', FScreen.ViewLineText(0));
end;

procedure TVtEmulatorTest.TestCursorMovement();
begin
  // Move to line 5, col 10 (1-based ANSI CUP: \e[5;10H)
  FScreen.Feed(#27'[5;10H');
  AssertEquals('CursorX after CUP', 9, FScreen.CursorX);
  AssertEquals('CursorY after CUP', 4, FScreen.CursorY);

  // Cursor Up 2 (\e[2A)
  FScreen.Feed(#27'[2A');
  AssertEquals('CursorY after CUU', 2, FScreen.CursorY);

  // Cursor Down 3 (\e[3B)
  FScreen.Feed(#27'[3B');
  AssertEquals('CursorY after CUD', 5, FScreen.CursorY);

  // Cursor Forward 5 (\e[5C)
  FScreen.Feed(#27'[5C');
  AssertEquals('CursorX after CUF', 14, FScreen.CursorX);

  // Cursor Backward 4 (\e[4D)
  FScreen.Feed(#27'[4D');
  AssertEquals('CursorX after CUB', 10, FScreen.CursorX);
end;

procedure TVtEmulatorTest.TestAutoWrap();
var
  i: Integer;
  s: string;
begin
  // Fill line 0 completely (80 chars)
  s := StringOfChar('A', 80);
  FScreen.Feed(s);
  AssertEquals('CursorX at margin', 79, FScreen.CursorX);
  AssertEquals('CursorY before wrap', 0, FScreen.CursorY);

  // One more character triggers autowrap to next row
  FScreen.Feed('B');
  AssertEquals('CursorX after wrap', 1, FScreen.CursorX);
  AssertEquals('CursorY after wrap', 1, FScreen.CursorY);
  AssertEquals('Line 1 starts with B', 'B', FScreen.ViewLineText(1));
end;

procedure TVtEmulatorTest.TestSgrFormatting();
var
  cell: TTermCell;
begin
  // Bold (1), Underline (4), Red foreground (31)
  FScreen.Feed(#27'[1;4;31mBoldRed'#27'[0m');
  cell := FScreen.ViewCell(0, 0);
  AssertTrue('Cell should be Bold', cell.Attr.Bold);
  AssertTrue('Cell should be Underlined', cell.Attr.Underline);
  AssertEquals('FG color should be indexed', Ord(tckIndexed), Ord(cell.Attr.FG.Kind));
  AssertEquals('FG color should be red (1)', 1, cell.Attr.FG.Value);

  // Reset character (cell 7)
  cell := FScreen.ViewCell(0, 7);
  AssertFalse('After reset should not be bold', cell.Attr.Bold);
  AssertFalse('After reset should not be underline', cell.Attr.Underline);
end;

procedure TVtEmulatorTest.TestEraseInLineAndDisplay();
begin
  FScreen.Feed('ABCDEFGHIJ');
  // Move back to col 5 and erase to end of line (\e[K)
  FScreen.Feed(#27'[1;5H'#27'[K');
  AssertEquals('Line text after EL', 'ABCD', FScreen.ViewLineText(0));

  // Erase whole display (\e[2J)
  FScreen.Feed(#27'[2J');
  AssertEquals('Line text after ED', '', FScreen.ViewLineText(0));
end;

procedure TVtEmulatorTest.TestScrollbackAndScrollView();
var
  i: Integer;
begin
  // Feed 40 lines into a 24-row screen
  for i := 1 to 40 do
  begin
    if i < 40 then
      FScreen.Feed(Format('Line %d'#13#10, [i]))
    else
      FScreen.Feed(Format('Line %d', [i]));
  end;

  // Live bottom should show Line 40 on row 23
  AssertTrue('Bottom line contains Line 40', Pos('Line 40', FScreen.ViewLineText(23)) > 0);

  // Scroll view up into history by 10 lines
  FScreen.ScrollView(10);
  AssertEquals('ScrollOffset should be 10', 10, FScreen.ScrollOffset());

  // Scroll back to bottom
  FScreen.ScrollToBottom();
  AssertEquals('ScrollOffset should reset to 0', 0, FScreen.ScrollOffset());
end;

procedure TVtEmulatorTest.TestAlternateScreen();
begin
  FScreen.Feed('Primary Screen Text');
  // Enter alt screen (\e[?1049h)
  FScreen.Feed(#27'[?1049h');
  AssertTrue('AltScreen should be active', FScreen.AltScreen);
  AssertEquals('Alt screen starts clean', '', FScreen.ViewLineText(0));

  FScreen.Feed('Alt Screen Content');
  AssertEquals('Alt line has content', 'Alt Screen Content', FScreen.ViewLineText(0));

  // Leave alt screen (\e[?1049l)
  FScreen.Feed(#27'[?1049l');
  AssertFalse('AltScreen should be inactive', FScreen.AltScreen);
  AssertEquals('Primary text restored', 'Primary Screen Text', FScreen.ViewLineText(0));
end;

procedure TVtEmulatorTest.TestOscTitle();
begin
  FScreen.Feed(#27']0;Samarinda Shell'#7);
  AssertEquals('Title parsed from OSC', 'Samarinda Shell', FScreen.Title);

  // Also support ST terminator (\e\)
  FScreen.Feed(#27']2;Kirana Console'#27'\');
  AssertEquals('Title parsed with ST terminator', 'Kirana Console', FScreen.Title);
end;

procedure TVtEmulatorTest.TestBracketedPaste();
begin
  FScreen.Feed(#27'[?2004h');
  AssertTrue('Bracketed paste enabled', FScreen.BracketedPaste);

  FScreen.Feed(#27'[?2004l');
  AssertFalse('Bracketed paste disabled', FScreen.BracketedPaste);
end;

initialization
  RegisterTest(TVtEmulatorTest);

end.
