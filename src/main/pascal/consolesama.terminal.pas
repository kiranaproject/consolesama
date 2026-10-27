// consolesama.terminal.pas — terminal view widget
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Terminal;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  ftpas, ftpas.types, ftpas.creative, ftpas.canvas, ftpas.font, ftpas.widget,
  ConsoleSama.Pty, ConsoleSama.Vt, ConsoleSama.Keys;

const
  DefaultFontDesc = 'Monospace 12';

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
    FFontDesc: string;
    FFontSize: Integer;
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

    procedure MeasureFont();
    procedure RecomputeGrid();
    function  CellRect(ACol, ARow: Integer): TFtRect;
    procedure DrawCell(ACanvas: TFtCanvas; ACol, ARow: Integer; const ACell: TTermCell);
    procedure DrawCursor(ACanvas: TFtCanvas);
    procedure DrawSelection(ACanvas: TFtCanvas);
    function  PaletteColor(const AColor: TTermColor; AIsBackground: Boolean): TFtColor;
    procedure HandlePaint(Sender: TFtDrawingArea; ACanvas: TFtCanvas);
    procedure HandleWheel(Sender: TFtDrawingArea; AX, AY, ADeltaX, ADeltaY: Integer);
    procedure HandleResized(Sender: TFtDrawingArea; ANewWidth, ANewHeight: Integer);
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
    procedure ShowExited();

    property PTY: TTerminalPTY read FPTY;
    property Screen: TTerminalEmulator read FScreen;
    property FontRef: TFtFontRef read FFont;
    property FontDesc: string read FFontDesc;
    property FontSize: Integer read FFontSize;
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
  DefaultForeground: TTermColor;
  DefaultBackground: TTermColor;

const
  BasePalette: array[0..15] of LongWord = (
    $00171A21, $00CC6666, $00B5BD68, $00F0C674,
    $0081A2BE, $00B294BB, $008ABEB4, $00C5C8C6,
    $004B4B4B, $00D54E53, $00B9CA4A, $00E7C547,
    $007AA6DA, $00C397D8, $0070C0B0, $00EAEAEA
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

constructor TConsoleTerminalView.Create(AParent: TFtWidget; AX, AY, AW, AH: Integer;
  const AFontDesc: string);
begin
  inherited Create(AParent, AX, AY, AW, AH);
  FFontDesc := AFontDesc;
  FFontSize := 12;
  FFont := TFtFontRef.Create(AFontDesc);
  FScreen := TTerminalEmulator.Create(80, 24);
  FPTY := nil;
  FCols := 80;
  FRows := 24;
  FSelActive := False;
  FSelecting := False;
  FBlinkOn := True;
  FLastPumpTick := 0;
  FLastTitle := '';

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
  if (cols = FCols) and (rows = FRows) then Exit;
  FCols := cols;
  FRows := rows;
  FScreen.Resize(FCols, FRows);
  if FPTY <> nil then
    FPTY.Resize(FCols, FRows);
  Invalidate();
end;

function TConsoleTerminalView.CellRect(ACol, ARow: Integer): TFtRect;
begin
  Result.Left := X + Round(ACol * FCellW);
  Result.Top := Y + Round(ARow * FCellH);
  Result.Width := Round(FCellW) + 1;
  Result.Height := Round(FCellH) + 1;
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
      v := DefaultBackground.Value
    else
      v := DefaultForeground.Value;
  end
  else if AColor.Kind = tckRGB then
    v := AColor.Value
  else
  begin
    idx := AColor.Value and $FF;
    if idx < 16 then
      v := BasePalette[idx]
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
begin
  r := CellRect(ACol, ARow);
  attr := ACell.Attr;

  if cfWideTail in ACell.Flags then
    Exit;

  fg := PaletteColor(attr.FG, False);
  bg := PaletteColor(attr.BG, True);
  if attr.Reverse then
  begin
    fg := PaletteColor(attr.BG, False);
    bg := PaletteColor(attr.FG, True);
    if attr.BG.Kind = tckDefault then
    begin
      bg.R := 0.85;
      bg.G := 0.87;
      bg.B := 0.91;
    end;
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
begin
  if (not FScreen.CursorVisible) or (not FBlinkOn) then Exit;
  if FScreen.ScrollOffset() <> 0 then Exit;
  if not Focused then Exit;

  cx := FScreen.CursorX;
  cy := FScreen.CursorY;
  cell := FScreen.ViewCell(cy, cx);
  r := CellRect(cx, cy);

  ACanvas.DrawRect(r.Left, r.Top, r.Width, r.Height, 0.55, 0.75, 0.95);

  if cell.Code <> 0 then
  begin
    txt := FScreen.CellText(cell);
    fg := PaletteColor(DefaultBackground, True);
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
  l1, c1, l2, c2, row, x1, x2: Integer;
  r: TFtRect;
begin
  if not FSelActive then Exit;
  SelectionNormalized(l1, c1, l2, c2);
  if (l1 = l2) and (c1 = c2) then Exit;
  for row := l1 to l2 do
  begin
    if row = l1 then x1 := c1 else x1 := 0;
    if row = l2 then x2 := c2 else x2 := FCols - 1;
    r := CellRect(x1, row);
    ACanvas.DrawRect(r.Left, r.Top, Round((x2 - x1 + 1) * FCellW), Round(FCellH), 0.30, 0.42, 0.60);
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

  FScreen.ScrollToBottom();

  if FPTY.PollAlive() = False then
  begin
    if Assigned(FOnExit) then
      FOnExit(Self);
  end;

  if FScreen.Title <> FLastTitle then
  begin
    FLastTitle := FScreen.Title;
    if Assigned(FOnTitle) then
      FOnTitle(Self, FLastTitle);
  end;

  if (n = -1) or (FScreen.TakeChanged()) or (beforeOffset <> FScreen.ScrollOffset()) then
    Invalidate();
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
  Invalidate();
end;

procedure TConsoleTerminalView.ShowExited();
begin
  FScreen.Feed(#13#10 + RawByteString('[process exited]') + #13#10);
  Invalidate();
end;

procedure TConsoleTerminalView.ScrollPage(ADelta: Integer);
begin
  FScreen.ScrollView(ADelta * FRows);
  Invalidate();
end;

procedure TConsoleTerminalView.Zoom(ADelta: Integer);
begin
  FFontSize := Max(6, Min(36, FFontSize + ADelta));
  FFontDesc := Format('Monospace %d', [FFontSize]);
  FreeAndNil(FFont);
  FFont := TFtFontRef.Create(FFontDesc);
  MeasureFont();
  RecomputeGrid();
  Invalidate();
end;

initialization
  DefaultForeground := MakeRGB($00D8DEE9);
  DefaultBackground := MakeRGB($00171A21);

end.
