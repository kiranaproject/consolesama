// consolesama.terminal.pas — terminal view widget
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Terminal;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process,
  ftpas, ftpas.types, ftpas.app, ftpas.creative, ftpas.canvas, ftpas.font, ftpas.widget, ftpas.controls,
  ConsoleSama.Pty, ConsoleSama.Vt, ConsoleSama.Keys;

const
  DefaultFontFamily = 'Ubuntu Mono';
  DefaultFontSize   = 13;
  DefaultFontDesc   = 'Ubuntu Mono 13';

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
    procedure DrawCell(ACanvas: TFtCanvas; ACol, ARow: Integer; const ACell: TTermCell);
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
  BasePaletteLight: array[0..15] of LongWord = (
    $001E293B, // 0: Black (Deep Slate)
    $00DC2626, // 1: Red
    $0016A34A, // 2: Green
    $00D97706, // 3: Yellow (Amber)
    $002563EB, // 4: Blue
    $009333EA, // 5: Magenta
    $000891B2, // 6: Cyan
    $0064748B, // 7: White / Gray (readable on white)
    $0094A3B8, // 8: Bright Black (Muted Slate)
    $00EF4444, // 9: Bright Red
    $0022C55E, // 10: Bright Green
    $00F59E0B, // 11: Bright Yellow (Amber 500)
    $003B82F6, // 12: Bright Blue
    $00A855F7, // 13: Bright Magenta
    $0006B6D4, // 14: Bright Cyan
    $000F172A  // 15: Bright White / Deep Slate
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
  FCellW := Ceil(adv);
  FCellH := Ceil(h);
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

procedure TConsoleTerminalView.DrawCell(ACanvas: TFtCanvas; ACol, ARow: Integer;
  const ACell: TTermCell);
var
  r: TFtRect;
  fg, bg: TFtColor;
  attr: TTermAttr;
  txt: string;
  span: Integer;
begin
  r := CellRect(ACol, ARow);
  attr := ACell.Attr;
  span := CellSpan(ACell);
  if span > 1 then
    r.Width := Round(span * FCellW) + 1;

  // Tail cells hold no glyph, but they still need their background painted so
  // a wide character's cell is filled completely.
  if cfWideTail in ACell.Flags then
  begin
    bg := PaletteColor(attr.BG, True);
    if attr.Reverse then
      bg := PaletteColor(attr.FG, True);
    if (bg.R > 0.001) or (bg.G > 0.001) or (bg.B > 0.001) then
      ACanvas.DrawRect(r.Left, r.Top, r.Width, r.Height, bg.R, bg.G, bg.B);
    Exit;
  end;

  fg := PaletteColor(attr.FG, False);
  bg := PaletteColor(attr.BG, True);
  if attr.Reverse then
  begin
    fg := PaletteColor(attr.BG, False);
    bg := PaletteColor(attr.FG, True);
  end;
  if attr.Bold then
  begin
    if attr.FG.Kind = tckIndexed then
      fg := PaletteColor(MakeIndexed(attr.FG.Value or 8), False);
  end;

  // Cell background
  if (bg.R > 0.001) or (bg.G > 0.001) or (bg.B > 0.001) then
    ACanvas.DrawRect(r.Left, r.Top, r.Width, r.Height, bg.R, bg.G, bg.B);

  if ACell.Code = 0 then Exit;

  txt := FScreen.CellText(ACell);
  if txt = '' then Exit;

  ACanvas.DrawText(r.Left, r.Top + FAscent, txt, fg.R, fg.G, fg.B, FFont.Handle);

  if attr.Underline then
    ACanvas.DrawRect(r.Left, r.Top + Round(FCellH) - 2, r.Width, 1, fg.R, fg.G, fg.B);
  if attr.Strike then
    ACanvas.DrawRect(r.Left, r.Top + Round(FCellH / 2), r.Width, 1, fg.R, fg.G, fg.B);
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
    ACanvas.DrawText(r.Left, r.Top + FAscent, txt, fg.R, fg.G, fg.B, FFont.Handle);
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
            ACanvas.DrawText(r.Left, r.Top + FAscent, txt, 0.95, 0.95, 0.95, FFont.Handle)
          else
            ACanvas.DrawText(r.Left, r.Top + FAscent, txt, 0.05, 0.10, 0.20, FFont.Handle);
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

  for py := 0 to FRows - 1 do
  begin
    for px := 0 to FCols - 1 do
    begin
      cell := FScreen.ViewCell(py, px);
      if (cell.Code = 0) and (cell.Attr.BG.Kind = tckDefault) then
        Continue;
      DrawCell(ACanvas, px, py, cell);
    end;
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
