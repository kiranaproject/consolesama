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
    procedure TestWideCharactersOccupyTwoCells();
    procedure TestCombiningMarksKeepBaseWidth();
    procedure TestRtlCodePointClassification();
    procedure TestDecSpecialGraphicsCharset();
    procedure TestBlockElementWidth();
    procedure TestBoxDrawingCodePoints();
    procedure TestCursorMovement();
    procedure TestAutoWrap();
    procedure TestSgrFormatting();
    procedure TestEraseInLineAndDisplay();
    procedure TestScrollbackAndScrollView();
    procedure TestAlternateScreen();
    procedure TestOscTitle();
    procedure TestBracketedPaste();
    procedure TestResizeWidthReflow();
    procedure TestResizeHeightShrinkAndExpandPreservation();
    procedure TestPromptResizeNoDuplicateOrJumpingCursor();
    procedure TestLiveShellResizeKeepsActiveLineStable();
    procedure TestLiveShellResizeRestoresRowsAbovePrompt();
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

procedure TVtEmulatorTest.TestWideCharactersOccupyTwoCells();
begin
  // Chinese: 4 characters => 8 cells
  FScreen.Feed('你好世界');
  AssertEquals('Chinese takes 2 cells each', 8, FScreen.CursorX);
  AssertEquals('Chinese line text', '你好世界', FScreen.ViewLineText(0));

  FScreen.Feed(#27'[2J'#27'[H');
  // Japanese hiragana
  FScreen.Feed('こんにちは');
  AssertEquals('Hiragana takes 2 cells each', 10, FScreen.CursorX);

  FScreen.Feed(#27'[2J'#27'[H');
  // Korean hangul
  FScreen.Feed('안녕');
  AssertEquals('Hangul takes 2 cells each', 4, FScreen.CursorX);

  FScreen.Feed(#27'[2J'#27'[H');
  // Emoji (astral plane)
  FScreen.Feed('🚀🎉');
  AssertEquals('Emoji takes 2 cells each', 4, FScreen.CursorX);

  FScreen.Feed(#27'[2J'#27'[H');
  // Fullwidth Latin
  FScreen.Feed('ＡＢＣ');
  AssertEquals('Fullwidth latin takes 2 cells each', 6, FScreen.CursorX);

  FScreen.Feed(#27'[2J'#27'[H');
  // Mixed narrow and wide
  FScreen.Feed('a中b文c');
  AssertEquals('Mixed narrow/wide width', 7, FScreen.CursorX);
  AssertEquals('Mixed line text', 'a中b文c', FScreen.ViewLineText(0));

  FScreen.Feed(#27'[2J'#27'[H');
  // Single-cell scripts stay one cell per character
  FScreen.Feed('Привет');
  AssertEquals('Cyrillic stays narrow', 6, FScreen.CursorX);
end;

procedure TVtEmulatorTest.TestCombiningMarksKeepBaseWidth();
var
  cell: TTermCell;
begin
  // e + combining acute accent: two code points, one cell
  FScreen.Feed('e' + #$CC#$81);
  AssertEquals('Combining mark does not advance', 1, FScreen.CursorX);
  cell := FScreen.ViewCell(0, 0);
  AssertEquals('Base character stored', Ord('e'), Integer(cell.Code));
  AssertEquals('One combining mark attached', 1, Integer(cell.CombCount));
  AssertEquals('Cell text keeps the mark', 'e' + #$CC#$81, FScreen.CellText(cell));

  // Two marks on one base still occupy a single cell
  FScreen.Feed(#27'[2J'#27'[H');
  FScreen.Feed('e' + #$CC#$82 + #$CC#$81 + 'x');
  AssertEquals('Two marks then x occupies 2 cells', 2, FScreen.CursorX);

  // Marks must not leak into a cell that is written again
  FScreen.Feed(#27'[2J'#27'[H');
  FScreen.Feed('e' + #$CC#$81);
  FScreen.Feed(#13'x');
  cell := FScreen.ViewCell(0, 0);
  AssertEquals('Rewritten cell holds x', Ord('x'), Integer(cell.Code));
  AssertEquals('Rewritten cell has no stale marks', 0, Integer(cell.CombCount));
end;

procedure TVtEmulatorTest.TestRtlCodePointClassification();
begin
  // Arabic letters and their presentation forms
  AssertTrue('Arabic alef is RTL', TTerminalEmulator.IsRtlCodePoint($0627));
  AssertTrue('Arabic meem is RTL', TTerminalEmulator.IsRtlCodePoint($0645));
  AssertTrue('Arabic presentation form is RTL', TTerminalEmulator.IsRtlCodePoint($FEE0));
  // Hebrew
  AssertTrue('Hebrew alef is RTL', TTerminalEmulator.IsRtlCodePoint($05D0));
  AssertTrue('Hebrew tav is RTL', TTerminalEmulator.IsRtlCodePoint($05EA));
  // Everything else used by the terminal stays LTR
  AssertFalse('Latin is not RTL', TTerminalEmulator.IsRtlCodePoint(Ord('a')));
  AssertFalse('CJK is not RTL', TTerminalEmulator.IsRtlCodePoint($4E2D));
  AssertFalse('Cyrillic is not RTL', TTerminalEmulator.IsRtlCodePoint($0410));
  AssertFalse('Thai is not RTL', TTerminalEmulator.IsRtlCodePoint($0E2A));

  // RTL text still occupies one cell per character
  FScreen.Feed('مرحبا');
  AssertEquals('Arabic keeps cell-per-character layout', 5, FScreen.CursorX);
end;

procedure TVtEmulatorTest.TestDecSpecialGraphicsCharset();
var
  cell: TTermCell;
begin
  // ESC ( 0 selects DEC Special Graphics for G0: ASCII letters become
  // line-drawing glyphs. TUI programs (the Free Pascal IDE, ncurses apps)
  // rely on this to draw boxes.
  FScreen.Feed(#27'(0');
  FScreen.Feed('l');            // upper left corner
  cell := FScreen.ViewCell(0, 0);
  AssertEquals('DEC l maps to box drawing corner', $250C, Integer(cell.Code));

  FScreen.Feed('q');            // horizontal line
  cell := FScreen.ViewCell(0, 1);
  AssertEquals('DEC q maps to horizontal line', $2500, Integer(cell.Code));

  FScreen.Feed('x');            // vertical line
  cell := FScreen.ViewCell(0, 2);
  AssertEquals('DEC x maps to vertical line', $2502, Integer(cell.Code));

  // Back to ASCII
  FScreen.Feed(#27'(B');
  FScreen.Feed('l');
  cell := FScreen.ViewCell(0, 3);
  AssertEquals('ESC ( B restores ASCII', Ord('l'), Integer(cell.Code));

  // Shift Out / Shift In select G1 and back
  FScreen.Feed(#27')0');
  FScreen.Feed(#14);            // SO -> G1 (special)
  FScreen.Feed('q');
  cell := FScreen.ViewCell(0, 4);
  AssertEquals('SO selects G1 special graphics', $2500, Integer(cell.Code));
  FScreen.Feed(#15);            // SI -> G0 (ASCII)
  FScreen.Feed('q');
  cell := FScreen.ViewCell(0, 5);
  AssertEquals('SI returns to G0 ASCII', Ord('q'), Integer(cell.Code));

  // Width stays one cell per character
  AssertEquals('Special graphics stay single width', 6, FScreen.CursorX);
end;

procedure TVtEmulatorTest.TestBlockElementWidth();
var
  codes: array[0..5] of LongWord = ($2580, $2584, $2588, $258C, $2590, $2593);
  i: Integer;
  cell: TTermCell;
begin
  // Block elements are single-cell glyphs; drawing them as rectangles is what
  // makes adjacent blocks tile without seams.
  for i := Low(codes) to High(codes) do
  begin
    FScreen.Feed(#27'[1;1H');
    FScreen.Feed(#27'[2J');
    // Feed the code point as UTF-8
    if codes[i] < $800 then
      FScreen.Feed(Chr($C0 or (codes[i] shr 6)) + Chr($80 or (codes[i] and $3F)))
    else
      FScreen.Feed(Chr($E0 or (codes[i] shr 12)) +
        Chr($80 or ((codes[i] shr 6) and $3F)) +
        Chr($80 or (codes[i] and $3F)));
    cell := FScreen.ViewCell(0, 0);
    AssertEquals(Format('U+%.4x stored', [codes[i]]), codes[i], cell.Code);
    AssertEquals(Format('U+%.4x is one cell', [codes[i]]), 1, FScreen.CursorX);
    AssertFalse(Format('U+%.4x is not wide', [codes[i]]), cfWideLead in cell.Flags);
  end;
end;

procedure TVtEmulatorTest.TestBoxDrawingCodePoints();
var
  cell: TTermCell;
begin
  // Box drawing must survive the VT layer intact; the renderer paints them as
  // geometry so runs join across cell boundaries.
  FScreen.Feed(#27'[2J'#27'[H');
  FScreen.Feed(#$E2#$94#$8C);           // U+250C ┌
  cell := FScreen.ViewCell(0, 0);
  AssertEquals('U+250C stored', $250C, Integer(cell.Code));
  AssertEquals('Box drawing is single width', 1, FScreen.CursorX);

  FScreen.Feed(#$E2#$95#$90);           // U+2550 ═
  cell := FScreen.ViewCell(0, 1);
  AssertEquals('U+2550 stored', $2550, Integer(cell.Code));

  // Geometric square used by fp as the dialog icon
  FScreen.Feed(#27'[2J'#27'[H');
  FScreen.Feed(#$E2#$96#$A0);           // U+25A0 ■
  cell := FScreen.ViewCell(0, 0);
  AssertEquals('U+25A0 stored', $25A0, Integer(cell.Code));
  AssertEquals('U+25A0 is single width', 1, FScreen.CursorX);
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

procedure TVtEmulatorTest.TestResizeWidthReflow();
var
  originalText: string;
  i: Integer;
begin
  // Construct 100 characters of pattern '0123456789...'
  originalText := '';
  for i := 0 to 99 do
    originalText := originalText + Chr(Ord('0') + (i mod 10));

  FScreen.Feed(originalText);
  // On 80 cols: row 0 has first 80 chars, row 1 has remaining 20 chars
  AssertEquals('Row 0 text at 80 cols', Copy(originalText, 1, 80), FScreen.ViewLineText(0));
  AssertEquals('Row 1 text at 80 cols', Copy(originalText, 81, 20), FScreen.ViewLineText(1));

  // Resize width down to 50 cols:
  FScreen.Resize(50, 24);
  AssertEquals('Cols after resize', 50, FScreen.Cols);
  AssertEquals('Row 0 text at 50 cols', Copy(originalText, 1, 50), FScreen.ViewLineText(0));
  AssertEquals('Row 1 text at 50 cols', Copy(originalText, 51, 50), FScreen.ViewLineText(1));
  AssertEquals('Row 2 text at 50 cols should be blank', '', FScreen.ViewLineText(2));

  // Resize width up to 120 cols: line unwraps back to a single line!
  FScreen.Resize(120, 24);
  AssertEquals('Cols after widen', 120, FScreen.Cols);
  AssertEquals('Row 0 text unwrapped at 120 cols', originalText, FScreen.ViewLineText(0));
  AssertEquals('Row 1 text at 120 cols should be blank', '', FScreen.ViewLineText(1));
end;

procedure TVtEmulatorTest.TestResizeHeightShrinkAndExpandPreservation();
var
  i: Integer;
begin
  // Feed 30 lines on an 80x24 terminal
  for i := 1 to 30 do
  begin
    if i < 30 then
      FScreen.Feed(Format('Output line %.2d'#13#10, [i]))
    else
      FScreen.Feed(Format('Output line %.2d', [i]));
  end;

  // Initial state: cursor on line 30 at row 23
  AssertEquals('Initial TotalLines', 30, FScreen.TotalLines());
  AssertEquals('Initial CursorY', 23, FScreen.CursorY);
  AssertEquals('Visible top line (row 0)', 'Output line 07', FScreen.ViewLineText(0));
  AssertEquals('Visible bottom line (row 23)', 'Output line 30', FScreen.ViewLineText(23));

  // Shrink height from 24 down to 12 rows:
  FScreen.Resize(80, 12);
  AssertEquals('Rows after shrink', 12, FScreen.Rows);
  AssertEquals('Total lines must be preserved on shrink', 30, FScreen.TotalLines());
  AssertEquals('CursorY shifted to bottom row', 11, FScreen.CursorY);
  AssertEquals('Visible bottom line at 12 rows', 'Output line 30', FScreen.ViewLineText(11));
  AssertEquals('Visible top line at 12 rows', 'Output line 19', FScreen.ViewLineText(0));

  // Expand height from 12 back to 24 rows:
  FScreen.Resize(80, 24);
  AssertEquals('Rows after restore', 24, FScreen.Rows);
  AssertEquals('Total lines preserved after restore', 30, FScreen.TotalLines());
  AssertEquals('CursorY restored to row 23', 23, FScreen.CursorY);
  AssertEquals('Visible bottom line restored', 'Output line 30', FScreen.ViewLineText(23));
  AssertEquals('Top lines 07..18 returned to screen', 'Output line 07', FScreen.ViewLineText(0));

  // Scroll up 6 lines into scrollback to verify line 01 is intact
  FScreen.ScrollView(6);
  AssertEquals('Scrollback line 01 intact', 'Output line 01', FScreen.ViewLineText(0));
  FScreen.ScrollToBottom();

  // Expand height to 35 rows: all 30 lines now fit on screen!
  FScreen.Resize(80, 35);
  AssertEquals('Rows at 35', 35, FScreen.Rows);
  AssertEquals('CursorY at row 29', 29, FScreen.CursorY);
  AssertEquals('Top line at row 0 is line 01 without scrolling', 'Output line 01', FScreen.ViewLineText(0));
  AssertEquals('Line at row 29 is line 30', 'Output line 30', FScreen.ViewLineText(29));
  AssertEquals('Row 30 is blank', '', FScreen.ViewLineText(30));

  // Shrink back to 24:
  FScreen.Resize(80, 24);
  AssertEquals('Total lines still 30', 30, FScreen.TotalLines());
  AssertEquals('Visible bottom line at row 23', 'Output line 30', FScreen.ViewLineText(23));
  AssertEquals('Visible top line at row 0', 'Output line 07', FScreen.ViewLineText(0));
end;

procedure TVtEmulatorTest.TestPromptResizeNoDuplicateOrJumpingCursor();
var
  promptStr: string;
begin
  // Set up typical bash prompt with ANSI color escapes:
  // "user@box:~/projects/kirana/consolesama$ " (40 printable chars)
  promptStr := #27'[01;32muser@box'#27'[00m:'#27'[01;34m~/projects/kirana/consolesama'#27'[00m$ ';
  FScreen.Feed(promptStr);

  AssertEquals('Initial cursor row', 0, FScreen.CursorY);
  AssertEquals('Initial cursor col', 40, FScreen.CursorX);
  AssertEquals('Rendered prompt text', 'user@box:~/projects/kirana/consolesama$', FScreen.ViewLineText(0));

  // Narrow width from 80 down to 30 columns (where 40 chars wraps across 2 rows)
  FScreen.Resize(30, 24);

  // Line 0 should contain the first 30 chars
  AssertEquals('Line 0 has first 30 chars', Copy('user@box:~/projects/kirana/consolesama$', 1, 30), FScreen.ViewLineText(0));
  // Line 1 should contain remaining 10 chars, cursor after the 10th char
  AssertEquals('Line 1 has wrapped remainder', Copy('user@box:~/projects/kirana/consolesama$', 31, 100), FScreen.ViewLineText(1));
  AssertEquals('Line 2 is empty', '', FScreen.ViewLineText(2));
  AssertEquals('Cursor row after wrapped prompt', 1, FScreen.CursorY);
  AssertEquals('Cursor col after wrapped prompt', 10, FScreen.CursorX);

  // Expand width back up to 80 cols: unwraps back to single line
  FScreen.Resize(80, 24);

  AssertEquals('Line 0 fully restored on single line', 'user@box:~/projects/kirana/consolesama$', FScreen.ViewLineText(0));
  AssertEquals('Line 1 is empty after restore', '', FScreen.ViewLineText(1));
  AssertEquals('Cursor row back to 0', 0, FScreen.CursorY);
  AssertEquals('Cursor col back to 40', 40, FScreen.CursorX);

  // Test boundary transitions: 74 vs 75 columns with typed input
  // Type 34 chars so total length is 74 chars
  FScreen.Feed('0123456789012345678901234567890123');
  AssertEquals('Cursor at col 74 on 80 cols', 74, FScreen.CursorX);
  AssertEquals('Cursor at row 0 on 80 cols', 0, FScreen.CursorY);

  // Resize to 75 cols: 74 chars fits completely on row 0, cursor at col 74
  FScreen.Resize(75, 24);
  AssertEquals('Row 0 on 75 cols', 0, FScreen.CursorY);
  AssertEquals('Col 74 on 75 cols', 74, FScreen.CursorX);

  // Resize to 74 cols: 74 chars fills line 0 (cols 0..73), cursor wraps to row 1 col 0
  // Crucially: cursor must NOT be clamped to col 73 (overwriting the last char)!
  FScreen.Resize(74, 24);
  AssertEquals('Row 1 on 74 cols', 1, FScreen.CursorY);
  AssertEquals('Col 0 on 74 cols', 0, FScreen.CursorX);

  // Resize back to 75 cols: line unwraps cleanly back to row 0, col 74
  FScreen.Resize(75, 24);
  AssertEquals('Row 0 restored on 75 cols', 0, FScreen.CursorY);
  AssertEquals('Col 74 restored on 75 cols', 74, FScreen.CursorX);
end;

procedure TVtEmulatorTest.TestLiveShellResizeKeepsActiveLineStable();
var
  text: string;
begin
  // A live shell repaints its own input line on SIGWINCH. Reflowing the
  // visible rows underneath it desyncs readline's cursor-up bookkeeping, so
  // shell-mode resize must keep the physical row layout intact.
  text := StringOfChar('x', 160);
  FScreen.Feed(text);
  AssertEquals('Row 0 holds 80 chars', Copy(text, 1, 80), FScreen.ViewLineText(0));
  AssertEquals('Row 1 holds remaining 80 chars', Copy(text, 81, 80), FScreen.ViewLineText(1));
  AssertEquals('Cursor on row 1', 1, FScreen.CursorY);
  AssertEquals('Cursor at col 79', 79, FScreen.CursorX);

  // Narrow with the shell policy: rows keep their positions and are only
  // clamped; no extra rows are created for the wrapped line.
  FScreen.Resize(30, 24, False);
  AssertEquals('Row 0 clamped to new width', Copy(text, 1, 30), FScreen.ViewLineText(0));
  AssertEquals('Row 1 keeps its own content', Copy(text, 81, 30), FScreen.ViewLineText(1));
  AssertEquals('Cursor stays on row 1', 1, FScreen.CursorY);
  AssertEquals('Cursor col clamped to 29', 29, FScreen.CursorX);
  AssertEquals('No reflowed third row', '', FScreen.ViewLineText(2));
end;

procedure TVtEmulatorTest.TestLiveShellResizeRestoresRowsAbovePrompt();
var
  text: string;
begin
  // Rows that have scrolled above the prompt are not owned by readline, so
  // their full content is kept and restored when the grid widens again.
  text := StringOfChar('x', 160);
  FScreen.Feed(text + #13#10 + 'prompt> ');
  AssertEquals('Cursor on prompt row', 2, FScreen.CursorY);
  AssertEquals('Cursor after prompt', 8, FScreen.CursorX);

  FScreen.Resize(30, 24, False);
  AssertEquals('Previous row 0 clamped', Copy(text, 1, 30), FScreen.ViewLineText(0));
  AssertEquals('Previous row 1 clamped', Copy(text, 81, 30), FScreen.ViewLineText(1));
  AssertEquals('Prompt row preserved', 'prompt>', FScreen.ViewLineText(2));
  AssertEquals('Cursor row preserved', 2, FScreen.CursorY);
  AssertEquals('Cursor col preserved', 8, FScreen.CursorX);
  AssertEquals('No extra row', '', FScreen.ViewLineText(3));

  FScreen.Resize(80, 24, False);
  AssertEquals('Previous row 0 restored', Copy(text, 1, 80), FScreen.ViewLineText(0));
  AssertEquals('Previous row 1 restored', Copy(text, 81, 80), FScreen.ViewLineText(1));
  AssertEquals('Prompt row still intact', 'prompt>', FScreen.ViewLineText(2));
  AssertEquals('Cursor still on prompt row', 2, FScreen.CursorY);
  AssertEquals('Cursor still after prompt', 8, FScreen.CursorX);
end;

initialization
  RegisterTest(TVtEmulatorTest);

end.
