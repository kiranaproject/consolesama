// consolesama.terminal.pas — terminal view widget
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Terminal;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process,
  ftpas, ftpas.types, ftpas.app, ftpas.creative, ftpas.canvas, ftpas.font, ftpas.widget, ftpas.controls,
  Floria.Unicode.BiDi,
  ConsoleSama.Pty, ConsoleSama.Vt, ConsoleSama.Keys;

const
  DefaultFontFamily = 'Ubuntu Mono';
  DefaultFontSize   = 13;
  DefaultFontDesc   = 'Ubuntu Mono 13';
  // Extra room below the baseline. Fallback fonts (Arabic, Thai, Devanagari)
  // draw descenders deeper than the primary monospace font reports.
  CellBottomPadding = 3;

function  GetDefaultTerminalFont(): string;
procedure ParseTerminalFontDesc(const ADesc: string; out AFamily: string; out ASize: Integer);
function  MakeRGB(AValue: LongWord): TTermColor;
function  MakeIndexed(AValue: LongWord): TTermColor;
function  MakeDefaultColor(): TTermColor;

type
  TTerminalTitleEvent = procedure(Sender: TObject; const ATitle: string) of object;
  TTerminalExitEvent  = procedure(Sender: TObject) of object;
  TTerminalShortcutEvent = function(Sender: TObject; AKeySym, AState: LongWord): Boolean of object;

  // TConsoleTerminalView
  TConsoleTerminalView = class(TFtDrawingArea)
  private
    FPTY: TTerminalPTY;
    FScreen: TTerminalEmulator;
    FFont: TFtFontRef;
    FFontFamily: string;
    FFontDesc: string;
    FFontSize: Integer;
    FBaseFontSize: Integer;
    FCols: Integer;
    FRows: Integer;
    FCellW: Double;
    FCellH: Double;
    FAscent: Double;
    FDescent: Double;
    FSelActive: Boolean;
    FSelecting: Boolean;
    FSelStartX, FSelStartY: Integer;
    FSelEndX, FSelEndY: Integer;
    FOnTitle: TTerminalTitleEvent;
    FOnExit: TTerminalExitEvent;
    FOnShortcut: TTerminalShortcutEvent;
    FBlinkOn: Boolean;
    FLastPumpTick: QWord;
    FLastTitle: string;
    FDefaultFg: TTermColor;
    FDefaultBg: TTermColor;
    FIsDark: Boolean;
    FScrollBar: TFtScrollBar;

    procedure MeasureFont();
    procedure RecomputeGrid();
    function  CellRect(ACol, ARow: Integer): TFtRect;
    function  CellSpan(const ACell: TTermCell): Integer;
    // Baseline that centres the painted glyphs inside a cell.
    function  TextBaseline(const ARect: TFtRect): Double;
    // Block elements must tile the cell exactly; drawing them as font glyphs
    // leaves gaps, which shreds images built from them (e.g. the fp logo).
    function  DrawBlockElement(ACanvas: TFtCanvas; const ARect: TFtRect;
      ACode: LongWord; const AFg: TFtColor): Boolean;
    procedure DrawCellBackground(ACanvas: TFtCanvas; ACol, ARow: Integer;
      const ACell: TTermCell);
    procedure DrawCellGlyph(ACanvas: TFtCanvas; ACol, ARow: Integer;
      const ACell: TTermCell);
    procedure DrawCell(ACanvas: TFtCanvas; ACol, ARow: Integer; const ACell: TTermCell);
    function  RowNeedsBidi(ARow: Integer): Boolean;
    procedure DrawRowBidi(ACanvas: TFtCanvas; ARow: Integer);
    function  VisualColumnFor(ARow, ALogicalCol: Integer): Integer;
    procedure DrawCursor(ACanvas: TFtCanvas);
    procedure DrawSelection(ACanvas: TFtCanvas);
    function  PaletteColor(const AColor: TTermColor; AIsBackground: Boolean): TFtColor;
    procedure HandlePaint(Sender: TFtDrawingArea; ACanvas: TFtCanvas);
    procedure HandleWheel(Sender: TFtDrawingArea; AX, AY, ADeltaX, ADeltaY: Integer);
    procedure HandleResized(Sender: TFtDrawingArea; ANewWidth, ANewHeight: Integer);
    procedure HandleScrollBarScroll(Sender: TFtWidget; Value: Double);
    procedure SetScrollBar(AValue: TFtScrollBar);
    procedure SendInput(const AData: string);
    procedure PumpOutput();
    function  CellAt(AX, AY: Integer; out ACol, ARow: Integer): Boolean;
    procedure SelectionNormalized(out ALine1, ACol1, ALine2, ACol2: Integer);
  public
    constructor Create(AParent: TFtWidget; AX, AY, AW, AH: Integer;
      const AFontDesc: string = DefaultFontDesc); reintroduce;
    destructor Destroy(); override;

    procedure HandleKeyDown(Sender: TFtDrawingArea; AKeySym, AState: LongWord);
    procedure HandleMouseDown(Sender: TFtDrawingArea; AX, AY, AButton: Integer);
    procedure HandleMouseMove(Sender: TFtDrawingArea; AX, AY: Integer);
    procedure HandleMouseUp(Sender: TFtDrawingArea; AX, AY, AButton: Integer);

    procedure StartShell(const AShell: string = ''; const ACwd: string = '');
    procedure Pump();
    procedure CopySelection();
    procedure PasteFromClipboard();
    procedure ClearSelection();
    procedure SelectAll();
    procedure ScrollPage(ADelta: Integer);
    procedure ScrollToEnd();
    procedure Zoom(ADelta: Integer);
    procedure ResetZoom();
    procedure ShowExited();
    procedure RefreshThemeColors();
    procedure SetBounds(AX, AY, AW, AH: Integer); override;
    procedure UpdateScrollBar();

    property ScrollBar: TFtScrollBar read FScrollBar write SetScrollBar;
    property IsDark: Boolean read FIsDark;
    property DefaultForeground: TTermColor read FDefaultFg;
    property DefaultBackground: TTermColor read FDefaultBg;
    property PTY: TTerminalPTY read FPTY;
    property Screen: TTerminalEmulator read FScreen;
    property FontRef: TFtFontRef read FFont;
    property FontFamily: string read FFontFamily;
    property FontDesc: string read FFontDesc;
    property FontSize: Integer read FFontSize;
    property BaseFontSize: Integer read FBaseFontSize;
    property TermCols: Integer read FCols;
    property TermRows: Integer read FRows;
    property CellWidth: Double read FCellW;
    property CellHeight: Double read FCellH;
    property HasSelection: Boolean read FSelActive;
    property Selecting: Boolean read FSelecting;

    property OnTitle: TTerminalTitleEvent read FOnTitle write FOnTitle;
    property OnExit: TTerminalExitEvent read FOnExit write FOnExit;
    property OnShortcut: TTerminalShortcutEvent read FOnShortcut write FOnShortcut;
  end;

implementation

var
  GDefaultForeground: TTermColor;
  GDefaultBackground: TTermColor;

const
  // ANSI colours keep their conventional light/dark relationship in both
  // themes: index 0 is dark, 7 is light and 15 is near-white. Only the default
  // foreground/background follow the theme. Inverting 7/15 (as an earlier
  // "readable on white" tweak did) breaks every program that paints with
  // explicit ANSI colours -- e.g. fp's dialogs use bg 47 / fg 30 and came out
  // dark-on-grey instead of dark-on-white.
  BasePaletteLight: array[0..15] of LongWord = (
    $001E293B, // 0: Black (Deep Slate)
    $00DC2626, // 1: Red
    $0016A34A, // 2: Green
    $00D97706, // 3: Yellow (Amber)
    $002563EB, // 4: Blue
    $009333EA, // 5: Magenta
    $000891B2, // 6: Cyan
    $00CBD5E1, // 7: White / Light Gray
    $0064748B, // 8: Bright Black (Muted Slate)
    $00EF4444, // 9: Bright Red
    $0022C55E, // 10: Bright Green
    $00F59E0B, // 11: Bright Yellow (Amber 500)
    $003B82F6, // 12: Bright Blue
    $00A855F7, // 13: Bright Magenta
    $0006B6D4, // 14: Bright Cyan
    $00F8FAFC  // 15: Bright White
  );

  BasePaletteDark: array[0..15] of LongWord = (
    $00171A21, // 0: Black
    $00CC6666, // 1: Red
    $00B5BD68, // 2: Green
    $00F0C674, // 3: Yellow
    $0081A2BE, // 4: Blue
    $00B294BB, // 5: Magenta
    $008ABEB4, // 6: Cyan
    $00C5C8C6, // 7: White
    $004B4B4B, // 8: Bright Black
    $00D54E53, // 9: Bright Red
    $00B9CA4A, // 10: Bright Green
    $00E7C547, // 11: Bright Yellow
    $007AA6DA, // 12: Bright Blue
    $00C397D8, // 13: Bright Magenta
    $0070C0B0, // 14: Bright Cyan
    $00EAEAEA  // 15: Bright White
  );

function MakeRGB(AValue: LongWord): TTermColor;
begin
  Result.Kind := tckRGB;
  Result.Value := AValue and $FFFFFF;
end;

function MakeIndexed(AValue: LongWord): TTermColor;
begin
  Result.Kind := tckIndexed;
  Result.Value := AValue;
end;

function MakeDefaultColor(): TTermColor;
begin
  Result.Kind := tckDefault;
  Result.Value := 0;
end;

function GetDefaultTerminalFont(): string;
var
  outStr: string;
begin
  outStr := '';
  if RunCommand('gsettings', ['get', 'org.gnome.desktop.interface', 'monospace-font-name'], outStr) then
  begin
    outStr := Trim(outStr);
    if (Length(outStr) >= 2) and (outStr[1] in ['''', '"']) and (outStr[Length(outStr)] = outStr[1]) then
      outStr := Copy(outStr, 2, Length(outStr) - 2);
    if outStr <> '' then
      Exit(outStr);
  end;

  if RunCommand('gsettings', ['get', 'org.mate.interface', 'monospace-font-name'], outStr) then
  begin
    outStr := Trim(outStr);
    if (Length(outStr) >= 2) and (outStr[1] in ['''', '"']) and (outStr[Length(outStr)] = outStr[1]) then
      outStr := Copy(outStr, 2, Length(outStr) - 2);
    if outStr <> '' then
      Exit(outStr);
  end;

  if FileExists('/usr/share/fonts/truetype/ubuntu/UbuntuMono[wght].ttf') or
     FileExists('/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf') then
    Exit('Ubuntu Mono 13');

  Result := DefaultFontDesc;
end;

procedure ParseTerminalFontDesc(const ADesc: string; out AFamily: string; out ASize: Integer);
var
  lastSpace, val: Integer;
  sizePart: string;
begin
  AFamily := DefaultFontFamily;
  ASize := DefaultFontSize;
  if ADesc = '' then Exit;

  lastSpace := LastDelimiter(' ', ADesc);
  if lastSpace > 0 then
  begin
    sizePart := Copy(ADesc, lastSpace + 1, Length(ADesc));
    if TryStrToInt(sizePart, val) and (val > 0) then
    begin
      AFamily := Trim(Copy(ADesc, 1, lastSpace - 1));
      ASize := val;
      Exit;
    end;
  end;
  AFamily := ADesc;
end;

constructor TConsoleTerminalView.Create(AParent: TFtWidget; AX, AY, AW, AH: Integer;
  const AFontDesc: string);
begin
  inherited Create(AParent, AX, AY, AW, AH);
  if AFontDesc <> '' then
    FFontDesc := AFontDesc
  else
    FFontDesc := GetDefaultTerminalFont();

  ParseTerminalFontDesc(FFontDesc, FFontFamily, FFontSize);
  FBaseFontSize := FFontSize;
  FFont := TFtFontRef.Create(FFontDesc);
  FScreen := TTerminalEmulator.Create(80, 24);
  FPTY := nil;
  FCols := 80;
  FRows := 24;
  FSelActive := False;
  FSelecting := False;
  FBlinkOn := True;
  FLastPumpTick := 0;
  FLastTitle := '';

  RefreshThemeColors();

  Focusable := True;
  AcceptsTab := True;
  Cursor := ftcIBeam;

  OnPaint := @HandlePaint;
  OnKeyDown := @HandleKeyDown;
  OnMouseDown := @HandleMouseDown;
  OnMouseMove := @HandleMouseMove;
  OnMouseUp := @HandleMouseUp;
  OnMouseWheel := @HandleWheel;
  OnResize := @HandleResized;

  MeasureFont();
  RecomputeGrid();
end;

destructor TConsoleTerminalView.Destroy();
begin
  if FScrollBar <> nil then
    FScrollBar.OnScroll := nil;
  FScrollBar := nil;
  FreeAndNil(FPTY);
  FreeAndNil(FScreen);
  FreeAndNil(FFont);
  inherited Destroy();
end;

type
  TStringArrayLocal = array of string;

procedure TConsoleTerminalView.MeasureFont();
var
  asc, desc, h, adv: Double;
begin
  FFont.GetMetrics(asc, desc, h, adv);
  if (adv <= 0.0) or (h <= 0.0) then
  begin
    adv := 8.0;
    h := 16.0;
    asc := 12.0;
    desc := 4.0;
  end;
  FAscent := asc;
  FDescent := desc;
  FCellW := Ceil(adv);
  // Leave room under the baseline for fallback-font descenders.
  FCellH := Ceil(h) + CellBottomPadding;
  if FCellW < 4 then FCellW := 8;
  if FCellH < 8 then FCellH := 16;
end;

procedure TConsoleTerminalView.RecomputeGrid();
var
  cols, rows: Integer;
begin
  cols := Max(1, Floor(Width / FCellW));
  rows := Max(1, Floor(Height / FCellH));
  if (cols = FCols) and (rows = FRows) then
  begin
    UpdateScrollBar();
    Exit;
  end;
  FCols := cols;
  FRows := rows;
  // A live shell repaints its own line on SIGWINCH, so leave the visible
  // screen's row layout alone; scrollback above it is still reflowed.
  FScreen.Resize(FCols, FRows, FPTY = nil);
  if FPTY <> nil then
    FPTY.Resize(FCols, FRows);
  UpdateScrollBar();
  Invalidate();
end;

procedure TConsoleTerminalView.SetBounds(AX, AY, AW, AH: Integer);
begin
  inherited SetBounds(AX, AY, AW, AH);
  RecomputeGrid();
end;

procedure TConsoleTerminalView.SetScrollBar(AValue: TFtScrollBar);
begin
  if FScrollBar = AValue then Exit;
  if FScrollBar <> nil then
    FScrollBar.OnScroll := nil;
  FScrollBar := AValue;
  if FScrollBar <> nil then
  begin
    FScrollBar.OnScroll := @HandleScrollBarScroll;
    FScrollBar.Step := 1.0;
    UpdateScrollBar();
  end;
end;

procedure TConsoleTerminalView.HandleScrollBarScroll(Sender: TFtWidget; Value: Double);
var
  histCount, newOffset: Integer;
begin
  if FScreen = nil then Exit;
  histCount := FScreen.HistoryCount();
  newOffset := Round(histCount - Value);
  if newOffset < 0 then newOffset := 0;
  if newOffset > histCount then newOffset := histCount;
  FScreen.SetScrollOffset(newOffset);
  Invalidate();
end;

procedure TConsoleTerminalView.UpdateScrollBar();
var
  histCount: Integer;
  curVal: Double;
begin
  if (FScrollBar = nil) or (FScreen = nil) then Exit;
  histCount := FScreen.HistoryCount();
  FScrollBar.SetRange(0.0, histCount, FRows);
  curVal := histCount - FScreen.ScrollOffset();
  if Abs(FScrollBar.Value - curVal) > 0.001 then
    FScrollBar.Value := curVal;
  FScrollBar.Invalidate();
end;

function TConsoleTerminalView.CellRect(ACol, ARow: Integer): TFtRect;
begin
  Result.Left := X + Round(ACol * FCellW);
  Result.Top := Y + Round(ARow * FCellH);
  Result.Width := Round(FCellW) + 1;
  Result.Height := Round(FCellH) + 1;
end;

// A wide character occupies two cells: the lead cell carries the glyph and
// the tail cell is a blank continuation. Rectangles for wide leads must span
// both so backgrounds, underlines and the cursor cover the whole glyph.
function TConsoleTerminalView.CellSpan(const ACell: TTermCell): Integer;
begin
  if cfWideLead in ACell.Flags then
    Result := 2
  else
    Result := 1;
end;

// Baseline that centres the glyphs inside a cell.
//
// The font reports an ascent that includes internal leading, so centring the
// reported ascent/descent box leaves the visible ink about 20% too low. The
// constants below shrink the box to the part the glyphs actually paint, which
// keeps capital letters and descenders optically centred.
function TConsoleTerminalView.TextBaseline(const ARect: TFtRect): Double;
const
  InkAscentScale  = 0.78;  // measured cap height / reported ascent
  InkDescentScale = 0.95;  // measured descender depth / reported descent
var
  inkAscent, inkDescent, inkHeight: Double;
begin
  inkAscent := FAscent * InkAscentScale;
  inkDescent := FDescent * InkDescentScale;
  inkHeight := inkAscent + inkDescent;
  Result := ARect.Top + (ARect.Height - inkHeight) / 2.0 + inkAscent;
end;

// Renders U+2580..U+259F as filled rectangles so neighbouring blocks touch.
// Drawing them as font glyphs leaves hairline gaps between cells, which shreds
// any image built out of them (the Free Pascal IDE logo is one).
// Returns False when the code point is not a block element.
function TConsoleTerminalView.DrawBlockElement(ACanvas: TFtCanvas;
  const ARect: TFtRect; ACode: LongWord; const AFg: TFtColor): Boolean;
var
  bx, by, bw, bh: Integer;

  procedure Fill(AX, AY, AW, AH: Integer; AAlpha: Double = 1.0);
  begin
    if (AW <= 0) or (AH <= 0) then Exit;
    ACanvas.DrawRect(AX, AY, AW, AH, AFg.R, AFg.G, AFg.B, AAlpha);
  end;

begin
  Result := True;
  bx := ARect.Left;
  by := ARect.Top;
  // Round the cell size once so all fractions land on the same grid and
  // adjacent blocks share an edge exactly.
  bw := Round(FCellW);
  bh := Round(FCellH);

  case ACode of
    $2580: Fill(bx, by, bw, bh div 2);                        // upper half
    $2581: Fill(bx, by + bh * 7 div 8, bw, bh div 8);         // lower 1/8
    $2582: Fill(bx, by + bh * 6 div 8, bw, bh * 2 div 8);
    $2583: Fill(bx, by + bh * 5 div 8, bw, bh * 3 div 8);
    $2584: Fill(bx, by + bh * 4 div 8, bw, bh * 4 div 8);     // lower half
    $2585: Fill(bx, by + bh * 3 div 8, bw, bh * 5 div 8);
    $2586: Fill(bx, by + bh * 2 div 8, bw, bh * 6 div 8);
    $2587: Fill(bx, by + bh * 1 div 8, bw, bh * 7 div 8);
    $2588: Fill(bx, by, bw, bh);                              // full block
    $2589: Fill(bx, by, bw * 7 div 8, bh);                    // left 7/8
    $258A: Fill(bx, by, bw * 6 div 8, bh);
    $258B: Fill(bx, by, bw * 5 div 8, bh);
    $258C: Fill(bx, by, bw * 4 div 8, bh);                    // left half
    $258D: Fill(bx, by, bw * 3 div 8, bh);
    $258E: Fill(bx, by, bw * 2 div 8, bh);
    $258F: Fill(bx, by, bw * 1 div 8, bh);
    $2590: Fill(bx + bw div 2, by, bw div 2, bh);             // right half
    $2591: Fill(bx, by, bw, bh, 0.25);                        // 25% shade
    $2592: Fill(bx, by, bw, bh, 0.50);                        // 50% shade
    $2593: Fill(bx, by, bw, bh, 0.75);                        // 75% shade
    $2594: Fill(bx, by, bw, bh div 8);                        // upper 1/8
    $2595: Fill(bx + bw * 7 div 8, by, bw div 8, bh);         // right 1/8
    $2596: Fill(bx, by + bh div 2, bw div 2, bh div 2);       // lower left
    $2597: Fill(bx + bw div 2, by + bh div 2, bw div 2, bh div 2);  // lower right
    $2598: Fill(bx, by, bw div 2, bh div 2);                  // upper left
    $2599: begin                                              // left + lower right
        Fill(bx, by, bw div 2, bh);
        Fill(bx + bw div 2, by + bh div 2, bw div 2, bh div 2);
      end;
    $259A: begin                                              // upper left + lower right
        Fill(bx, by, bw div 2, bh div 2);
        Fill(bx + bw div 2, by + bh div 2, bw div 2, bh div 2);
      end;
    $259B: begin                                              // left + lower right
        Fill(bx, by, bw div 2, bh);
        Fill(bx + bw div 2, by + bh div 2, bw div 2, bh div 2);
      end;
    $259C: begin                                              // top half + lower right
        Fill(bx, by, bw, bh div 2);
        Fill(bx + bw div 2, by + bh div 2, bw div 2, bh div 2);
      end;
    $259D: Fill(bx + bw div 2, by, bw div 2, bh div 2);       // upper right
    $259E: begin                                              // upper right + lower left
        Fill(bx + bw div 2, by, bw div 2, bh div 2);
        Fill(bx, by + bh div 2, bw div 2, bh div 2);
      end;
    $259F: begin                                              // right half + lower left
        Fill(bx + bw div 2, by, bw div 2, bh);
        Fill(bx, by + bh div 2, bw div 2, bh div 2);
      end;
  else
    Result := False;
  end;
end;

procedure TConsoleTerminalView.RefreshThemeColors();
begin
  FIsDark := FtApp().DarkMode;
  if FIsDark then
  begin
    FDefaultFg := MakeRGB($00D8DEE9);
    FDefaultBg := MakeRGB($00171A21);
  end
  else
  begin
    FDefaultFg := MakeRGB($001E293B);
    FDefaultBg := MakeRGB($00FFFFFF);
  end;
  GDefaultForeground := FDefaultFg;
  GDefaultBackground := FDefaultBg;
  Invalidate();
end;

function TConsoleTerminalView.PaletteColor(const AColor: TTermColor;
  AIsBackground: Boolean): TFtColor;
var
  v: LongWord;
  idx: Integer;
begin
  if AColor.Kind = tckDefault then
  begin
    if AIsBackground then
      v := FDefaultBg.Value
    else
      v := FDefaultFg.Value;
  end
  else if AColor.Kind = tckRGB then
    v := AColor.Value
  else
  begin
    idx := AColor.Value and $FF;
    if idx < 16 then
    begin
      if FIsDark then
        v := BasePaletteDark[idx]
      else
        v := BasePaletteLight[idx];
    end
    else if idx < 232 then
    begin
      Dec(idx, 16);
      v := (LongWord((idx div 36) * 51) shl 16) or
           (LongWord(((idx div 6) mod 6) * 51) shl 8) or
           LongWord((idx mod 6) * 51);
    end
    else
    begin
      idx := (idx - 232) * 10 + 8;
      v := (LongWord(idx) shl 16) or (LongWord(idx) shl 8) or LongWord(idx);
    end;
  end;
  Result.R := ((v shr 16) and $FF) / 255.0;
  Result.G := ((v shr 8) and $FF) / 255.0;
  Result.B := (v and $FF) / 255.0;
end;

procedure TConsoleTerminalView.DrawCellBackground(ACanvas: TFtCanvas;
  ACol, ARow: Integer; const ACell: TTermCell);
var
  r: TFtRect;
  bg: TFtColor;
  span: Integer;
begin
  span := CellSpan(ACell);
  bg := PaletteColor(ACell.Attr.BG, True);
  if ACell.Attr.Reverse then
    bg := PaletteColor(ACell.Attr.FG, True);
  if (bg.R <= 0.001) and (bg.G <= 0.001) and (bg.B <= 0.001) then Exit;

  r := CellRect(ACol, ARow);
  if span > 1 then
    r.Width := Round(span * FCellW) + 1;
  ACanvas.DrawRect(r.Left, r.Top, r.Width, r.Height, bg.R, bg.G, bg.B);
end;

procedure TConsoleTerminalView.DrawCellGlyph(ACanvas: TFtCanvas;
  ACol, ARow: Integer; const ACell: TTermCell);
var
  r: TFtRect;
  fg: TFtColor;
  attr: TTermAttr;
  txt: string;
  span: Integer;
begin
  if cfWideTail in ACell.Flags then Exit;
  if ACell.Code = 0 then Exit;

  txt := FScreen.CellText(ACell);
  if txt = '' then Exit;

  attr := ACell.Attr;
  fg := PaletteColor(attr.FG, False);
  if attr.Reverse then
    fg := PaletteColor(attr.BG, False);
  if attr.Bold and (attr.FG.Kind = tckIndexed) then
    fg := PaletteColor(MakeIndexed(attr.FG.Value or 8), False);

  span := CellSpan(ACell);
  r := CellRect(ACol, ARow);
  if span > 1 then
    r.Width := Round(span * FCellW) + 1;

  // Block elements are geometry, not glyphs: only exact rectangles tile.
  if DrawBlockElement(ACanvas, r, ACell.Code, fg) then Exit;

  ACanvas.DrawText(r.Left, TextBaseline(r), txt, fg.R, fg.G, fg.B, FFont.Handle);

  if attr.Underline then
    ACanvas.DrawRect(r.Left, r.Top + Round(FCellH) - 2, r.Width, 1, fg.R, fg.G, fg.B);
  if attr.Strike then
    ACanvas.DrawRect(r.Left, r.Top + Round(FCellH / 2), r.Width, 1, fg.R, fg.G, fg.B);
end;

procedure TConsoleTerminalView.DrawCell(ACanvas: TFtCanvas; ACol, ARow: Integer;
  const ACell: TTermCell);
begin
  DrawCellBackground(ACanvas, ACol, ARow, ACell);
  DrawCellGlyph(ACanvas, ACol, ARow, ACell);
end;

// True when the row holds right-to-left text, which must be laid out through
// the bidi pipeline instead of cell by cell.
function TConsoleTerminalView.RowNeedsBidi(ARow: Integer): Boolean;
var
  c: Integer;
begin
  Result := False;
  for c := 0 to FCols - 1 do
    if FScreen.IsRtlCodePoint(FScreen.ViewCell(ARow, c).Code) then
      Exit(True);
end;

// Draw a row containing RTL text: split it into visual runs, then paint each
// run as one string so the shaper can join Arabic letters. Runs are clipped to
// their own cells so proportional fallback glyphs cannot bleed into neighbours.
procedure TConsoleTerminalView.DrawRowBidi(ACanvas: TFtCanvas; ARow: Integer);
var
  c, i, k, lastNonBlank, visCol: Integer;
  cell: TTermCell;
  logicalText: string;
  runs: TFloriaBiDiRunArray;
  logicalChars: TStringArrayLocal;
  logicalSpan: array of Integer;
  fg: TFtColor;
  r: TFtRect;
  attr: TTermAttr;
  cellsInRun: Integer;
begin
  // Collect the row in logical order, dropping the continuation cells of wide
  // characters and everything after the last visible character. The span of
  // each entry is kept so wide characters reserve two columns.
  SetLength(logicalChars, 0);
  SetLength(logicalSpan, 0);
  lastNonBlank := -1;
  for c := 0 to FCols - 1 do
  begin
    cell := FScreen.ViewCell(ARow, c);
    if cfWideTail in cell.Flags then Continue;
    SetLength(logicalChars, Length(logicalChars) + 1);
    SetLength(logicalSpan, Length(logicalSpan) + 1);
    logicalChars[High(logicalChars)] := FScreen.CellText(cell);
    logicalSpan[High(logicalSpan)] := CellSpan(cell);
    if (cell.Code <> 0) and (cell.Code <> 32) then
      lastNonBlank := High(logicalChars);
  end;
  if lastNonBlank < 0 then Exit;
  SetLength(logicalChars, lastNonBlank + 1);
  SetLength(logicalSpan, lastNonBlank + 1);

  logicalText := '';
  for i := 0 to High(logicalChars) do
    logicalText := logicalText + logicalChars[i];

  runs := TFloriaBiDi.GetVisualRuns(logicalText);

  // Paint each run as a single string: the font can then join the cursive
  // Arabic forms. Runs are clipped to the cells they own, so a proportional
  // fallback font cannot bleed into the neighbouring run.
  visCol := 0;
  for k := 0 to High(runs) do
  begin
    if runs[k].CharCount <= 0 then Continue;

    // Count the grid cells this run covers, honouring wide characters.
    cellsInRun := 0;
    for i := runs[k].StartChar to runs[k].StartChar + runs[k].CharCount - 1 do
      if (i >= 0) and (i <= High(logicalSpan)) then
        Inc(cellsInRun, logicalSpan[i]);
    if cellsInRun < 1 then cellsInRun := 1;

    attr := FScreen.ViewCell(ARow, visCol).Attr;
    fg := PaletteColor(attr.FG, False);
    if attr.Reverse then
      fg := PaletteColor(attr.BG, False);
    if attr.Bold and (attr.FG.Kind = tckIndexed) then
      fg := PaletteColor(MakeIndexed(attr.FG.Value or 8), False);

    r := CellRect(visCol, ARow);
    r.Width := Round(cellsInRun * FCellW) + 1;
    ACanvas.PushClipRect(r.Left, r.Top, r.Width, Round(FCellH));
    try
      // Proportional fallback glyphs are narrower than the cell box; start at
      // the run's first cell so the text lines up with its neighbours.
      ACanvas.DrawText(r.Left, TextBaseline(r),
        runs[k].Text, fg.R, fg.G, fg.B, FFont.Handle);
    finally
      ACanvas.PopClipRect();
    end;

    Inc(visCol, cellsInRun);
  end;
end;

// Map a logical column to the column it is painted at. Only rows containing
// RTL text need this; every other row maps identically.
function TConsoleTerminalView.VisualColumnFor(ARow, ALogicalCol: Integer): Integer;
var
  c, i, logicalIdx, charIdx, lastNonBlank: Integer;
  cell: TTermCell;
  logical: string;
  runs: TFloriaBiDiRunArray;
  visualCol: Integer;
  charSpan: array of Integer;
begin
  Result := ALogicalCol;
  if not RowNeedsBidi(ARow) then Exit;

  // Build the logical string and remember the grid width of each character so
  // column indices can be converted to character indices.
  logical := '';
  SetLength(charSpan, 0);
  lastNonBlank := -1;
  for c := 0 to FCols - 1 do
  begin
    cell := FScreen.ViewCell(ARow, c);
    if cfWideTail in cell.Flags then Continue;
    SetLength(charSpan, Length(charSpan) + 1);
    charSpan[High(charSpan)] := CellSpan(cell);
    logical := logical + FScreen.CellText(cell);
    if (cell.Code <> 0) and (cell.Code <> 32) then
      lastNonBlank := High(charSpan);
  end;
  if lastNonBlank < 0 then Exit;
  SetLength(charSpan, lastNonBlank + 1);

  // Locate the character occupying the requested column.
  charIdx := -1;
  c := 0;
  for i := 0 to High(charSpan) do
  begin
    if (ALogicalCol >= c) and (ALogicalCol < c + charSpan[i]) then
    begin
      charIdx := i;
      Break;
    end;
    Inc(c, charSpan[i]);
  end;
  if charIdx < 0 then Exit;

  runs := TFloriaBiDi.GetVisualRuns(logical);
  visualCol := 0;
  for i := 0 to High(runs) do
  begin
    if (charIdx >= runs[i].StartChar) and
       (charIdx < runs[i].StartChar + runs[i].CharCount) then
    begin
      logicalIdx := charIdx - runs[i].StartChar;
      if runs[i].Direction = fbdRTL then
        logicalIdx := runs[i].CharCount - 1 - logicalIdx;
      // Advance over the characters painted before this one in the run.
      for c := 0 to logicalIdx - 1 do
      begin
        if runs[i].Direction = fbdRTL then
          Inc(visualCol, charSpan[runs[i].StartChar + runs[i].CharCount - 1 - c])
        else
          Inc(visualCol, charSpan[runs[i].StartChar + c]);
      end;
      Result := visualCol;
      Exit;
    end;
    for c := runs[i].StartChar to runs[i].StartChar + runs[i].CharCount - 1 do
      if (c >= 0) and (c <= High(charSpan)) then
        Inc(visualCol, charSpan[c]);
  end;
end;

procedure TConsoleTerminalView.DrawCursor(ACanvas: TFtCanvas);
var
  r: TFtRect;
  cx, cy: Integer;
  cell: TTermCell;
  fg: TFtColor;
  txt: string;
  span: Integer;
begin
  if (not FScreen.CursorVisible) or (not FBlinkOn) then Exit;
  if FScreen.ScrollOffset() <> 0 then Exit;
  if not Focused then Exit;

  cx := FScreen.CursorX;
  cy := FScreen.CursorY;

  // On an RTL row the cursor's logical column is painted at a different
  // visual column, so translate before placing the rectangle.
  if RowNeedsBidi(cy) then
  begin
    cx := VisualColumnFor(cy, cx);
    if cx < 0 then cx := 0;
    if cx >= FCols then cx := FCols - 1;
  end;

  cell := FScreen.ViewCell(cy, cx);

  // Never park the cursor on the trailing half of a wide character.
  if cfWideTail in cell.Flags then
  begin
    if cx > 0 then
    begin
      Dec(cx);
      cell := FScreen.ViewCell(cy, cx);
    end;
  end;

  span := CellSpan(cell);
  r := CellRect(cx, cy);
  if span > 1 then
    r.Width := Round(span * FCellW) + 1;

  if FIsDark then
    ACanvas.DrawRect(r.Left, r.Top, r.Width, r.Height, 0.55, 0.75, 0.95)
  else
    ACanvas.DrawRect(r.Left, r.Top, r.Width, r.Height, 0.15, 0.39, 0.92);

  if cell.Code <> 0 then
  begin
    txt := FScreen.CellText(cell);
    if FIsDark then
      fg := PaletteColor(FDefaultBg, True)
    else
    begin
      fg.R := 1.0;
      fg.G := 1.0;
      fg.B := 1.0;
    end;
    ACanvas.DrawText(r.Left, TextBaseline(r), txt, fg.R, fg.G, fg.B, FFont.Handle);
  end;
end;

procedure TConsoleTerminalView.SelectionNormalized(out ALine1, ACol1, ALine2, ACol2: Integer);
begin
  ALine1 := FSelStartY;
  ACol1 := FSelStartX;
  ALine2 := FSelEndY;
  ACol2 := FSelEndX;
  if (ALine1 > ALine2) or ((ALine1 = ALine2) and (ACol1 > ACol2)) then
  begin
    ALine1 := FSelEndY;
    ACol1 := FSelEndX;
    ALine2 := FSelStartY;
    ACol2 := FSelStartX;
  end;
end;

procedure TConsoleTerminalView.DrawSelection(ACanvas: TFtCanvas);
var
  l1, c1, l2, c2, row, x1, x2, col: Integer;
  r: TFtRect;
  cell: TTermCell;
  txt: string;
begin
  if not FSelActive then Exit;
  SelectionNormalized(l1, c1, l2, c2);
  if (l1 = l2) and (c1 = c2) then Exit;
  for row := l1 to l2 do
  begin
    if row = l1 then x1 := c1 else x1 := 0;
    if row = l2 then x2 := c2 else x2 := FCols - 1;
    r := CellRect(x1, row);
    if FIsDark then
      ACanvas.DrawRect(r.Left, r.Top, Round((x2 - x1 + 1) * FCellW), Round(FCellH), 0.20, 0.31, 0.48)
    else
      ACanvas.DrawRect(r.Left, r.Top, Round((x2 - x1 + 1) * FCellW), Round(FCellH), 0.70, 0.83, 0.99);

    for col := x1 to x2 do
    begin
      cell := FScreen.ViewCell(row, col);
      if cell.Code <> 0 then
      begin
        txt := FScreen.CellText(cell);
        if txt <> '' then
        begin
          r := CellRect(col, row);
          if FIsDark then
            ACanvas.DrawText(r.Left, TextBaseline(r), txt, 0.95, 0.95, 0.95, FFont.Handle)
          else
            ACanvas.DrawText(r.Left, TextBaseline(r), txt, 0.05, 0.10, 0.20, FFont.Handle);
        end;
      end;
    end;
  end;
end;

procedure TConsoleTerminalView.HandlePaint(Sender: TFtDrawingArea; ACanvas: TFtCanvas);
var
  px, py: Integer;
  cell: TTermCell;
  bg: TFtColor;
begin
  bg := PaletteColor(MakeDefaultColor(), True);
  ACanvas.DrawRect(X, Y, Width, Height, bg.R, bg.G, bg.B);

  // Backgrounds first, glyphs second: a descender that reaches into the row
  // below must not be painted over by that row's background.
  for py := 0 to FRows - 1 do
    for px := 0 to FCols - 1 do
    begin
      cell := FScreen.ViewCell(py, px);
      if (cell.Code = 0) and (cell.Attr.BG.Kind = tckDefault) then
        Continue;
      DrawCellBackground(ACanvas, px, py, cell);
    end;

  for py := 0 to FRows - 1 do
  begin
    if RowNeedsBidi(py) then
      DrawRowBidi(ACanvas, py)
    else
      for px := 0 to FCols - 1 do
        DrawCellGlyph(ACanvas, px, py, FScreen.ViewCell(py, px));
  end;

  DrawSelection(ACanvas);
  DrawCursor(ACanvas);
end;

procedure TConsoleTerminalView.SendInput(const AData: string);
begin
  if (FPTY <> nil) and (AData <> '') then
    FPTY.WriteInput(AData);
end;

procedure TConsoleTerminalView.HandleKeyDown(Sender: TFtDrawingArea;
  AKeySym, AState: LongWord);
var
  data: string;
begin
  if Assigned(FOnShortcut) and FOnShortcut(Self, AKeySym, AState) then
    Exit;

  // Shift+PageUp / Shift+PageDown scroll viewport history
  if (AKeySym = XK_Page_Up) and IsShiftPressed(AState) then
  begin
    ScrollPage(1);
    Exit;
  end;
  if (AKeySym = XK_Page_Down) and IsShiftPressed(AState) then
  begin
    ScrollPage(-1);
    Exit;
  end;

  // Clear any active selection upon typing
  if FSelActive and not FSelecting then
    FSelActive := False;

  // Any other key returns the view to the live bottom.
  FScreen.ScrollToBottom();
  UpdateScrollBar();

  data := KeySymToTerminalInput(AKeySym, AState, FScreen.AppCursorKeys,
    FScreen.AppKeypad);
  SendInput(data);
  FBlinkOn := True;
  Invalidate();
end;

function TConsoleTerminalView.CellAt(AX, AY: Integer; out ACol, ARow: Integer): Boolean;
begin
  ACol := Floor(AX / FCellW);
  ARow := Floor(AY / FCellH);
  Result := (ACol >= 0) and (ACol < FCols) and (ARow >= 0) and (ARow < FRows);
  if not Result then
  begin
    ACol := Max(0, Min(FCols - 1, ACol));
    ARow := Max(0, Min(FRows - 1, ARow));
  end;
end;

procedure TConsoleTerminalView.HandleMouseDown(Sender: TFtDrawingArea;
  AX, AY, AButton: Integer);
var
  c, r: Integer;
begin
  if AButton = 1 then
  begin
    CellAt(AX, AY, c, r);
    FSelStartX := c;
    FSelStartY := r;
    FSelEndX := c;
    FSelEndY := r;
    FSelecting := True;
    if FSelActive then
    begin
      FSelActive := False;
      Invalidate();
    end;
    SetFocus();
  end
  else if AButton = 3 then
  begin
    PasteFromClipboard();
  end;
end;

procedure TConsoleTerminalView.HandleMouseMove(Sender: TFtDrawingArea; AX, AY: Integer);
var
  c, r: Integer;
begin
  if not FSelecting then Exit;
  CellAt(AX, AY, c, r);
  if (c <> FSelEndX) or (r <> FSelEndY) then
  begin
    FSelEndX := c;
    FSelEndY := r;
    FSelActive := (FSelStartX <> FSelEndX) or (FSelStartY <> FSelEndY);
    Invalidate();
  end;
end;

procedure TConsoleTerminalView.HandleMouseUp(Sender: TFtDrawingArea;
  AX, AY, AButton: Integer);
begin
  if AButton = 1 then
  begin
    if FSelecting then
    begin
      CellAt(AX, AY, FSelEndX, FSelEndY);
      FSelActive := (FSelStartX <> FSelEndX) or (FSelStartY <> FSelEndY);
      FSelecting := False;
      Invalidate();
    end;
  end;
end;

procedure TConsoleTerminalView.HandleWheel(Sender: TFtDrawingArea;
  AX, AY, ADeltaX, ADeltaY: Integer);
begin
  FScreen.ScrollView(ADeltaY * 3);
  UpdateScrollBar();
  Invalidate();
end;

procedure TConsoleTerminalView.HandleResized(Sender: TFtDrawingArea;
  ANewWidth, ANewHeight: Integer);
begin
  RecomputeGrid();
  Invalidate();
end;

procedure TConsoleTerminalView.PumpOutput();
var
  buf: array[0..65535] of Byte;
  n: Integer;
  beforeOffset: Integer;

begin
  if FPTY = nil then Exit;
  beforeOffset := FScreen.ScrollOffset();

  repeat
    n := FPTY.ReadOutput(@buf[0], SizeOf(buf));
    if n > 0 then
    begin
      FScreen.Feed(@buf[0], n);
      FBlinkOn := True;
    end;
  until n <= 0;

  if beforeOffset = 0 then
    FScreen.ScrollToBottom();

  if FPTY.PollAlive() = False then
  begin
    if Assigned(FOnExit) then
      FOnExit(Self);
    // The owner may close this tab (and free this view) in response.
    Exit;
  end;

  if FScreen.Title <> FLastTitle then
  begin
    FLastTitle := FScreen.Title;
    if Assigned(FOnTitle) then
      FOnTitle(Self, FLastTitle);
  end;

  if (n = -1) or (FScreen.TakeChanged()) or (beforeOffset <> FScreen.ScrollOffset()) then
  begin
    UpdateScrollBar();
    Invalidate();
  end;
end;

procedure TConsoleTerminalView.Pump();
begin
  PumpOutput();
end;

procedure TConsoleTerminalView.StartShell(const AShell: string; const ACwd: string);
begin
  FreeAndNil(FPTY);
  FPTY := TTerminalPTY.Create(FCols, FRows, AShell, ACwd);
  if FPTY.LastError <> '' then
    WriteLn(StdErr, '[terminal] ', FPTY.LastError);
  Invalidate();
end;

procedure TConsoleTerminalView.ClearSelection();
begin
  if FSelActive or FSelecting then
  begin
    FSelActive := False;
    FSelecting := False;
    Invalidate();
  end;
end;

procedure TConsoleTerminalView.CopySelection();
var
  l1, c1, l2, c2: Integer;
  text: string;
begin
  if not FSelActive then Exit;
  SelectionNormalized(l1, c1, l2, c2);
  if (l1 = l2) and (c1 = c2) then Exit;
  text := FScreen.SelectedText(l1, c1, l2, c2);
  if text <> '' then
    FtApp().ClipboardText := text;
end;

procedure TConsoleTerminalView.PasteFromClipboard();
var
  text: string;
begin
  text := FtApp().ClipboardText;
  if text = '' then Exit;
  if FScreen.BracketedPaste then
    SendInput(#27'[200~' + text + #27'[201~')
  else
    SendInput(text);
end;

procedure TConsoleTerminalView.SelectAll();
begin
  FSelecting := False;
  FSelActive := True;
  FSelStartX := 0;
  FSelStartY := 0;
  FSelEndX := FCols - 1;
  FSelEndY := FRows - 1;
  Invalidate();
end;

procedure TConsoleTerminalView.ScrollToEnd();
begin
  FScreen.ScrollToBottom();
  UpdateScrollBar();
  Invalidate();
end;

procedure TConsoleTerminalView.ShowExited();
begin
  FScreen.Feed(#13#10 + RawByteString('[process exited]') + #13#10);
  UpdateScrollBar();
  Invalidate();
end;

procedure TConsoleTerminalView.ScrollPage(ADelta: Integer);
begin
  FScreen.ScrollView(ADelta * FRows);
  UpdateScrollBar();
  Invalidate();
end;

procedure TConsoleTerminalView.Zoom(ADelta: Integer);
begin
  FFontSize := Max(6, Min(36, FFontSize + ADelta));
  FFontDesc := Format('%s %d', [FFontFamily, FFontSize]);
  FreeAndNil(FFont);
  FFont := TFtFontRef.Create(FFontDesc);
  MeasureFont();
  RecomputeGrid();
  Invalidate();
end;

procedure TConsoleTerminalView.ResetZoom();
begin
  if FFontSize <> FBaseFontSize then
  begin
    FFontSize := FBaseFontSize;
    FFontDesc := Format('%s %d', [FFontFamily, FFontSize]);
    FreeAndNil(FFont);
    FFont := TFtFontRef.Create(FFontDesc);
    MeasureFont();
    RecomputeGrid();
    Invalidate();
  end;
end;

initialization
  GDefaultForeground := MakeRGB($001E293B);
  GDefaultBackground := MakeRGB($00FFFFFF);

end.
