// consolesama.vt.pas — VT100/xterm terminal emulator core
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Vt;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  DefaultScrollbackLines = 5000;

type
  TTermColorKind = (tckDefault, tckIndexed, tckRGB);

  TTermColor = record
    Kind: TTermColorKind;
    Value: LongWord;   // palette index or $00RRGGBB
  end;

  TTermAttr = record
    FG: TTermColor;
    BG: TTermColor;
    Bold, Dim, Italic, Underline, Blink, Reverse, Hidden, Strike: Boolean;
  end;

  TCellFlag = (cfWideLead, cfWideTail);

  TTermCell = record
    Code: LongWord;    // Unicode code point; 0 means blank
    Attr: TTermAttr;
    Flags: set of TCellFlag;
  end;

  TTermLine = array of TTermCell;

  TTermBellEvent = procedure(Sender: TObject) of object;
  TTermTitleEvent = procedure(Sender: TObject; const ATitle: string) of object;
  TTermClipboardEvent = procedure(Sender: TObject; const AText: string) of object;

  // TTerminalEmulator
  TTerminalEmulator = class
  private
    FCols: Integer;
    FRows: Integer;
    FMaxScrollback: Integer;
    // Main screen: the last FRows entries are the visible viewport; entries
    // before them are scrollback.
    FLines: array of TTermLine;
    FLinesWrapped: array of Boolean;
    FSavedLines: array of TTermLine;
    FSavedLinesWrapped: array of Boolean;
    FAltScreen: Boolean;
    FAltCursorX, FAltCursorY: Integer;

    FCursorX, FCursorY: Integer;
    FSavedCursorX, FSavedCursorY: Integer;
    FSavedPen: TTermAttr;
    FViewOffset: Integer;
    FCursorVisible: Boolean;
    FPen: TTermAttr;

    FScrollTop, FScrollBottom: Integer;  // 0-based inclusive
    FOriginMode: Boolean;
    FAutoWrap: Boolean;
    FWrapPending: Boolean;
    FInsertMode: Boolean;
    FAppCursorKeys: Boolean;
    FAppKeypad: Boolean;
    FBracketedPaste: Boolean;
    FNewLineMode: Boolean;
    FReverseVideo: Boolean;
    FTabStops: array of Boolean;

    FState: (stGround, stEscape, stCsi, stOsc, stOscEsc, stString, stStringEsc);
    FParams: array[0..31] of Integer;
    FParamCount: Integer;
    FParamDigits: Boolean;
    FPrivate: Char;      // '?' '>' '<' '=' or #0
    FIntermediates: string;
    FFinalByte: Char;
    FOSCBuf: string;

    FUtf8Code: LongWord;
    FUtf8Need: Integer;
    FUtf8Have: Integer;

    FTitle: string;
    FResponse: string;
    FBell: Boolean;
    FChanged: Boolean;

    FOnBell: TTermBellEvent;
    FOnTitle: TTermTitleEvent;
    FOnClipboard: TTermClipboardEvent;

    procedure AllocScreen(ACols, ARows: Integer);
    function  NewLine(): TTermLine;
    function  VisibleTop(): Integer;
    procedure ClearLine(ALine: TTermLine; AX1, AX2: Integer);
    procedure ClearScreenLines(AX1, AX2: Integer);
    procedure ResetPen();
    procedure ResetTabStops();
    function  GetScreenRow(AY: Integer): Integer;  // cursor row -> FLines index
    function  CursorLine(): TTermLine;
    procedure PutChar(AChar: LongWord);
    procedure PutString(const AText: string);
    procedure EraseCell(ACellIndex: Integer);
    procedure NewlineWithScroll();
    procedure ReverseIndex();
    procedure ScrollUpRegion(ACount: Integer);
    procedure ScrollDownRegion(ACount: Integer);
    procedure ScrollFullUp(ACount: Integer);
    procedure EnsureScrollable();
    procedure SetCursor(AX, AY: Integer);
    procedure SaveCursor();
    procedure RestoreCursor();
    procedure EnterAltScreen(AClear: Boolean);
    procedure LeaveAltScreen();
    procedure DoTab();
    procedure DoBackTab();
    procedure FeedByte(AByte: Byte);
    procedure HandleControl(AByte: Byte);
    procedure HandleEscape(AByte: Byte);
    procedure HandleCsiByte(AByte: Byte);
    procedure ExecuteCsi();
    procedure ExecuteSgr();
    procedure HandleOsc();
    procedure HandleOscDispatch();
    function  Param(AIndex, ADefault: Integer): Integer;
    procedure ApplySgrColor(AIsForeground: Boolean; ACodeIndex: Integer; out AUsed: Integer);
    procedure AddUtf8Byte(AByte: Byte);
    procedure Reset();
  public
    constructor Create(ACols, ARows: Integer; AMaxScrollback: Integer = DefaultScrollbackLines);
    destructor Destroy(); override;

    procedure Feed(ABuffer: PByte; ACount: Integer);
    procedure Feed(const AData: RawByteString);
    procedure Resize(ACols, ARows: Integer);
    procedure Clear();

    // View access (0-based; row 0 is the top visible row after scrolling).
    function  ViewCell(AViewRow, ACol: Integer): TTermCell;
    function  ViewLineText(AViewRow: Integer; ATrimRight: Boolean = True): string;
    function  CellText(const ACell: TTermCell): string;
    function  SelectedText(ALine1, ACol1, ALine2, ACol2: Integer): string;

    function  HistoryCount(): Integer;
    function  TotalLines(): Integer;
    function  ScrollOffset(): Integer;
    procedure ScrollView(ADelta: Integer);
    procedure ScrollToBottom();
    procedure SetScrollOffset(AOffset: Integer);
    property  ScrollbackUsed: Integer read FMaxScrollback;

    function  TakeResponse(): string;
    function  TakeBell(): Boolean;
    function  TakeChanged(): Boolean;

    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property CursorX: Integer read FCursorX;
    property CursorY: Integer read FCursorY;
    property CursorVisible: Boolean read FCursorVisible write FCursorVisible;
    property AppCursorKeys: Boolean read FAppCursorKeys;
    property AppKeypad: Boolean read FAppKeypad;
    property BracketedPaste: Boolean read FBracketedPaste;
    property AltScreen: Boolean read FAltScreen;
    property Title: string read FTitle;
    property ReverseVideo: Boolean read FReverseVideo;

    property OnBell: TTermBellEvent read FOnBell write FOnBell;
    property OnTitle: TTermTitleEvent read FOnTitle write FOnTitle;
    property OnClipboard: TTermClipboardEvent read FOnClipboard write FOnClipboard;
  end;

implementation

uses
  Math;

const
  MaxParams = 32;

function CodePointWidth(ACode: LongWord): Integer;
begin
  // Common East Asian wide and emoji ranges.
  if (ACode >= $1100) and (ACode <= $115F) then Exit(2);
  if (ACode >= $2E80) and (ACode <= $A4CF) then Exit(2);
  if (ACode >= $A960) and (ACode <= $A97F) then Exit(2);
  if (ACode >= $AC00) and (ACode <= $D7A3) then Exit(2);
  if (ACode >= $F900) and (ACode <= $FAFF) then Exit(2);
  if (ACode >= $FE10) and (ACode <= $FE19) then Exit(2);
  if (ACode >= $FE30) and (ACode <= $FE6F) then Exit(2);
  if (ACode >= $FF00) and (ACode <= $FF60) then Exit(2);
  if (ACode >= $FFE0) and (ACode <= $FFE6) then Exit(2);
  if (ACode >= $1F300) and (ACode <= $1F64F) then Exit(2);
  if (ACode >= $1F900) and (ACode <= $1F9FF) then Exit(2);
  if (ACode >= $20000) and (ACode <= $3FFFD) then Exit(2);
  Result := 1;
end;

constructor TTerminalEmulator.Create(ACols, ARows: Integer;
  AMaxScrollback: Integer);
begin
  inherited Create();
  FCols := Max(1, ACols);
  FRows := Max(1, ARows);
  FMaxScrollback := Max(0, AMaxScrollback);
  FOnBell := nil;
  FOnTitle := nil;
  FOnClipboard := nil;
  AllocScreen(FCols, FRows);
  Reset();
end;

destructor TTerminalEmulator.Destroy();
begin
  inherited Destroy();
end;

procedure TTerminalEmulator.ResetPen();
begin
  FillChar(FPen, SizeOf(FPen), 0);
  FPen.FG.Kind := tckDefault;
  FPen.BG.Kind := tckDefault;
end;

function TTerminalEmulator.NewLine(): TTermLine;
begin
  SetLength(Result, FCols);
end;

procedure TTerminalEmulator.AllocScreen(ACols, ARows: Integer);
var
  i: Integer;
begin
  SetLength(FLines, ARows);
  SetLength(FLinesWrapped, ARows);
  for i := 0 to ARows - 1 do
  begin
    FLines[i] := NewLine();
    FLinesWrapped[i] := False;
  end;
  SetLength(FSavedLines, 0);
  SetLength(FSavedLinesWrapped, 0);
  SetLength(FTabStops, ACols);
end;

procedure TTerminalEmulator.Reset();
var
  i: Integer;
begin
  SetLength(FLines, FRows);
  SetLength(FLinesWrapped, FRows);
  for i := 0 to FRows - 1 do
  begin
    FLines[i] := NewLine();
    FLinesWrapped[i] := False;
  end;
  FCursorX := 0;
  FCursorY := 0;
  FSavedCursorX := 0;
  FSavedCursorY := 0;
  FSavedPen := FPen;
  FViewOffset := 0;
  FCursorVisible := True;
  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  FOriginMode := False;
  FAutoWrap := True;
  FWrapPending := False;
  FInsertMode := False;
  FAppCursorKeys := False;
  FAppKeypad := False;
  FBracketedPaste := False;
  FNewLineMode := False;
  FReverseVideo := False;
  FAltScreen := False;
  FState := stGround;
  FParamCount := 0;
  FParamDigits := False;
  FPrivate := #0;
  FIntermediates := '';
  FOSCBuf := '';
  FUtf8Need := 0;
  FUtf8Have := 0;
  FTitle := '';
  FResponse := '';
  FBell := False;
  FChanged := True;
  ResetPen();
  ResetTabStops();
end;

procedure TTerminalEmulator.ResetTabStops();
var
  i: Integer;
begin
  SetLength(FTabStops, FCols);
  for i := 0 to FCols - 1 do
    FTabStops[i] := (i > 0) and ((i mod 8) = 0);
end;

procedure TTerminalEmulator.Clear();
begin
  Reset();
end;

function TTerminalEmulator.VisibleTop(): Integer;
begin
  Result := Length(FLines) - FRows;
  if Result < 0 then Result := 0;
end;

function TTerminalEmulator.GetScreenRow(AY: Integer): Integer;
begin
  Result := VisibleTop() + AY;
end;

function TTerminalEmulator.CursorLine(): TTermLine;
begin
  Result := FLines[GetScreenRow(FCursorY)];
end;

procedure TTerminalEmulator.ClearLine(ALine: TTermLine; AX1, AX2: Integer);
var
  i: Integer;
begin
  if AX1 < 0 then AX1 := 0;
  if AX2 >= FCols then AX2 := FCols - 1;
  for i := AX1 to AX2 do
  begin
    ALine[i].Code := 0;
    ALine[i].Attr := FPen;
    ALine[i].Flags := [];
    ALine[i].Attr.FG.Kind := tckDefault;
    ALine[i].Attr.FG.Value := 0;
    ALine[i].Attr.Bold := False;
    ALine[i].Attr.Italic := False;
    ALine[i].Attr.Underline := False;
    ALine[i].Attr.Reverse := False;
    ALine[i].Attr.Strike := False;
  end;
end;

procedure TTerminalEmulator.ClearScreenLines(AX1, AX2: Integer);
var
  y, top: Integer;
begin
  top := GetScreenRow(0);
  for y := 0 to FRows - 1 do
    ClearLine(FLines[top + y], AX1, AX2);
end;

procedure TTerminalEmulator.EnsureScrollable();
begin
  // The array is dynamic and viewport is anchored to the end.
end;

procedure TTerminalEmulator.NewlineWithScroll();
begin
  if FCursorY = FScrollBottom then
    ScrollUpRegion(1)
  else if FCursorY < FRows - 1 then
    Inc(FCursorY);
  FWrapPending := False;
end;

procedure TTerminalEmulator.ScrollUpRegion(ACount: Integer);
var
  i, j, topIdx, botIdx: Integer;
  blank: TTermLine;
begin
  if ACount <= 0 then Exit;
  if ACount > (FScrollBottom - FScrollTop + 1) then
    ACount := FScrollBottom - FScrollTop + 1;
  if (FScrollTop = 0) and (FScrollBottom = FRows - 1) and (FAltScreen = False) then
  begin
    // Full-screen scroll: move lines into scrollback by shifting the window.
    for i := 1 to ACount do
    begin
      blank := NewLine();
      if Length(FLines) > 0 then
      begin
        // Drop the oldest line when over the scrollback limit.
        if (Length(FLines) - FRows) >= FMaxScrollback then
        begin
          for j := 0 to Length(FLines) - 2 do
          begin
            FLines[j] := FLines[j + 1];
            FLinesWrapped[j] := FLinesWrapped[j + 1];
          end;
          FLines[Length(FLines) - 1] := blank;
          FLinesWrapped[Length(FLines) - 1] := False;
        end
        else
        begin
          SetLength(FLines, Length(FLines) + 1);
          SetLength(FLinesWrapped, Length(FLinesWrapped) + 1);
          FLines[Length(FLines) - 1] := blank;
          FLinesWrapped[Length(FLinesWrapped) - 1] := False;
        end;
      end;
    end;
    Exit;
  end;

  topIdx := GetScreenRow(FScrollTop);
  botIdx := GetScreenRow(FScrollBottom);
  for i := FScrollTop to FScrollBottom - ACount do
  begin
    FLines[GetScreenRow(i)] := FLines[GetScreenRow(i + ACount)];
    FLinesWrapped[GetScreenRow(i)] := FLinesWrapped[GetScreenRow(i + ACount)];
  end;
  for i := FScrollBottom - ACount + 1 to FScrollBottom do
  begin
    if i <= FScrollBottom then
    begin
      FLines[GetScreenRow(i)] := NewLine();
      FLinesWrapped[GetScreenRow(i)] := False;
    end;
  end;
  FChanged := True;
  if topIdx < 0 then topIdx := 0;
  if botIdx < 0 then botIdx := 0;
end;

procedure TTerminalEmulator.ScrollDownRegion(ACount: Integer);
var
  i: Integer;
begin
  if ACount <= 0 then Exit;
  if ACount > (FScrollBottom - FScrollTop + 1) then
    ACount := FScrollBottom - FScrollTop + 1;
  for i := FScrollBottom downto FScrollTop + ACount do
  begin
    FLines[GetScreenRow(i)] := FLines[GetScreenRow(i - ACount)];
    FLinesWrapped[GetScreenRow(i)] := FLinesWrapped[GetScreenRow(i - ACount)];
  end;
  for i := FScrollTop to FScrollTop + ACount - 1 do
  begin
    FLines[GetScreenRow(i)] := NewLine();
    FLinesWrapped[GetScreenRow(i)] := False;
  end;
  FChanged := True;
end;

procedure TTerminalEmulator.ScrollFullUp(ACount: Integer);
begin
  ScrollUpRegion(ACount);
end;

procedure TTerminalEmulator.ReverseIndex();
begin
  if FCursorY = FScrollTop then
    ScrollDownRegion(1)
  else if FCursorY > 0 then
    Dec(FCursorY);
  FWrapPending := False;
end;

procedure TTerminalEmulator.SetCursor(AX, AY: Integer);
begin
  if AX < 0 then AX := 0;
  if AX >= FCols then AX := FCols - 1;
  if AY < 0 then AY := 0;
  if AY >= FRows then AY := FRows - 1;
  FCursorX := AX;
  FCursorY := AY;
  FWrapPending := False;
  FChanged := True;
end;

procedure TTerminalEmulator.SaveCursor();
begin
  FSavedCursorX := FCursorX;
  FSavedCursorY := FCursorY;
  FSavedPen := FPen;
end;

procedure TTerminalEmulator.RestoreCursor();
begin
  FCursorX := FSavedCursorX;
  FCursorY := FSavedCursorY;
  if FCursorX >= FCols then FCursorX := FCols - 1;
  if FCursorY >= FRows then FCursorY := FRows - 1;
  FPen := FSavedPen;
  FWrapPending := False;
end;

procedure TTerminalEmulator.EraseCell(ACellIndex: Integer);
var
  line: TTermLine;
begin
  line := CursorLine();
  if (ACellIndex >= 0) and (ACellIndex < FCols) then
  begin
    line[ACellIndex].Code := 0;
    line[ACellIndex].Attr := FPen;
    line[ACellIndex].Flags := [];
  end;
end;

procedure TTerminalEmulator.PutChar(AChar: LongWord);
var
  line: TTermLine;
  w, x, y: Integer;
begin
  if not FAutoWrap then
    FWrapPending := False;

  if FWrapPending then
  begin
    if FAutoWrap then
    begin
      y := VisibleTop() + FCursorY;
      if (y >= 0) and (y < Length(FLinesWrapped)) then
        FLinesWrapped[y] := True;
      FCursorX := 0;
      NewlineWithScroll();
    end;
    FWrapPending := False;
  end;

  w := CodePointWidth(AChar);
  if w < 1 then w := 1;

  line := CursorLine();
  x := FCursorX;
  y := FCursorY;

  if FInsertMode and (x + w < FCols) then
  begin
    Move(line[x], line[x + w], (FCols - x - w) * SizeOf(TTermCell));
  end;

  if x + w > FCols then
  begin
    if FAutoWrap then
    begin
      y := VisibleTop() + FCursorY;
      if (y >= 0) and (y < Length(FLinesWrapped)) then
        FLinesWrapped[y] := True;
      FCursorX := 0;
      NewlineWithScroll();
      line := CursorLine();
      x := 0;
      y := FCursorY;
    end
    else
      x := FCols - w;
  end;

  line[x].Code := AChar;
  line[x].Attr := FPen;
  line[x].Flags := [cfWideLead];
  if w = 2 then
  begin
    line[x].Flags := [cfWideLead];
    if x + 1 < FCols then
    begin
      line[x + 1].Code := 0;
      line[x + 1].Attr := FPen;
      line[x + 1].Flags := [cfWideTail];
    end;
  end;

  Inc(x, w);
  if x >= FCols then
  begin
    x := FCols - 1;
    FWrapPending := True;
  end;
  FCursorX := x;
  FChanged := True;
end;

procedure TTerminalEmulator.PutString(const AText: string);
var
  i: Integer;
begin
  for i := 1 to Length(AText) do
    PutChar(Ord(AText[i]));
end;

procedure TTerminalEmulator.DoTab();
var
  x: Integer;
begin
  x := FCursorX + 1;
  while (x < FCols) and (not FTabStops[x]) do
    Inc(x);
  if x >= FCols then x := FCols - 1;
  FCursorX := x;
  FWrapPending := False;
end;

procedure TTerminalEmulator.DoBackTab();
var
  x: Integer;
begin
  x := FCursorX - 1;
  while (x > 0) and (not FTabStops[x]) do
    Dec(x);
  if x < 0 then x := 0;
  FCursorX := x;
  FWrapPending := False;
end;

function TTerminalEmulator.Param(AIndex, ADefault: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < FParamCount) then
  begin
    Result := FParams[AIndex];
    if Result = 0 then
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

procedure TTerminalEmulator.ApplySgrColor(AIsForeground: Boolean;
  ACodeIndex: Integer; out AUsed: Integer);
var
  mode, r, g, b, idx: Integer;
  col: TTermColor;
begin
  AUsed := 1;
  mode := Param(ACodeIndex + 1, 0);
  if mode = 2 then
  begin
    // 24-bit TrueColor: 38;2;R;G;B
    r := Param(ACodeIndex + 2, 0);
    g := Param(ACodeIndex + 3, 0);
    b := Param(ACodeIndex + 4, 0);
    col.Kind := tckRGB;
    col.Value := ((r and $FF) shl 16) or ((g and $FF) shl 8) or (b and $FF);
    AUsed := 5;
  end
  else if mode = 5 then
  begin
    // 256-color palette: 38;5;index
    idx := Param(ACodeIndex + 2, 0);
    col.Kind := tckIndexed;
    col.Value := idx and $FF;
    AUsed := 3;
  end
  else
  begin
    col.Kind := tckDefault;
    col.Value := 0;
    AUsed := 1;
  end;

  if AIsForeground then
    FPen.FG := col
  else
    FPen.BG := col;
end;

procedure TTerminalEmulator.ExecuteSgr();
var
  i, code, used: Integer;
begin
  if FParamCount = 0 then
  begin
    ResetPen();
    Exit;
  end;

  i := 0;
  while i < FParamCount do
  begin
    code := FParams[i];
    case code of
      0: ResetPen();
      1: FPen.Bold := True;
      2: FPen.Dim := True;
      3: FPen.Italic := True;
      4: FPen.Underline := True;
      5, 6: FPen.Blink := True;
      7: FPen.Reverse := True;
      8: FPen.Hidden := True;
      9: FPen.Strike := True;
      22: begin FPen.Bold := False; FPen.Dim := False; end;
      23: FPen.Italic := False;
      24: FPen.Underline := False;
      25: FPen.Blink := False;
      27: FPen.Reverse := False;
      28: FPen.Hidden := False;
      29: FPen.Strike := False;
      30..37:
        begin
          FPen.FG.Kind := tckIndexed;
          FPen.FG.Value := code - 30;
        end;
      38:
        begin
          ApplySgrColor(True, i, used);
          Inc(i, used - 1);
        end;
      39:
        begin
          FPen.FG.Kind := tckDefault;
          FPen.FG.Value := 0;
        end;
      40..47:
        begin
          FPen.BG.Kind := tckIndexed;
          FPen.BG.Value := code - 40;
        end;
      48:
        begin
          ApplySgrColor(False, i, used);
          Inc(i, used - 1);
        end;
      49:
        begin
          FPen.BG.Kind := tckDefault;
          FPen.BG.Value := 0;
        end;
      90..97:
        begin
          FPen.FG.Kind := tckIndexed;
          FPen.FG.Value := code - 90 + 8;
        end;
      100..107:
        begin
          FPen.BG.Kind := tckIndexed;
          FPen.BG.Value := code - 100 + 8;
        end;
    end;
    Inc(i);
  end;
end;

procedure TTerminalEmulator.ExecuteCsi();
var
  n, m, top, bot, y, x: Integer;
  line: TTermLine;
begin
  if FPrivate = '?' then
  begin
    // DEC Private Mode Set/Reset
    n := Param(0, 0);
    case FFinalByte of
      'h':
        case n of
          1: FAppCursorKeys := True;
          7: FAutoWrap := True;
          25: FCursorVisible := True;
          47, 1047, 1049: EnterAltScreen(n = 1049);
          2004: FBracketedPaste := True;
        end;
      'l':
        case n of
          1: FAppCursorKeys := False;
          7: FAutoWrap := False;
          25: FCursorVisible := False;
          47, 1047, 1049: LeaveAltScreen();
          2004: FBracketedPaste := False;
        end;
    end;
    Exit;
  end;

  case FFinalByte of
    '@': // ICH — Insert characters
      begin
        n := Param(0, 1);
        line := CursorLine();
        if FCursorX + n < FCols then
        begin
          Move(line[FCursorX], line[FCursorX + n], (FCols - FCursorX - n) * SizeOf(TTermCell));
          ClearLine(line, FCursorX, FCursorX + n - 1);
        end
        else
          ClearLine(line, FCursorX, FCols - 1);
      end;
    'A': // CUU — Cursor up
      SetCursor(FCursorX, FCursorY - Param(0, 1));
    'B', 'e': // CUD — Cursor down
      SetCursor(FCursorX, FCursorY + Param(0, 1));
    'C', 'a': // CUF — Cursor forward
      SetCursor(FCursorX + Param(0, 1), FCursorY);
    'D': // CUB — Cursor back
      SetCursor(FCursorX - Param(0, 1), FCursorY);
    'E': // CNL — Cursor next line
      SetCursor(0, FCursorY + Param(0, 1));
    'F': // CPL — Cursor preceding line
      SetCursor(0, FCursorY - Param(0, 1));
    'G', '`': // CHA — Cursor horizontal absolute
      SetCursor(Param(0, 1) - 1, FCursorY);
    'H', 'f': // CUP — Cursor position
      SetCursor(Param(1, 1) - 1, Param(0, 1) - 1);
    'I': // CHT — Cursor horizontal tab
      begin
        n := Param(0, 1);
        while n > 0 do
        begin
          DoTab();
          Dec(n);
        end;
      end;
    'J': // ED — Erase in display
      begin
        n := Param(0, 0);
        case n of
          0: // from cursor to end of screen
            begin
              ClearLine(CursorLine(), FCursorX, FCols - 1);
              top := GetScreenRow(0);
              for y := FCursorY + 1 to FRows - 1 do
                ClearLine(FLines[top + y], 0, FCols - 1);
            end;
          1: // from beginning to cursor
            begin
              top := GetScreenRow(0);
              for y := 0 to FCursorY - 1 do
                ClearLine(FLines[top + y], 0, FCols - 1);
              ClearLine(CursorLine(), 0, FCursorX);
            end;
          2, 3: // clear entire display
            ClearScreenLines(0, FCols - 1);
        end;
        FChanged := True;
      end;
    'K': // EL — Erase in line
      begin
        n := Param(0, 0);
        case n of
          0: ClearLine(CursorLine(), FCursorX, FCols - 1);
          1: ClearLine(CursorLine(), 0, FCursorX);
          2: ClearLine(CursorLine(), 0, FCols - 1);
        end;
        FChanged := True;
      end;
    'L': // IL — Insert lines
      begin
        n := Param(0, 1);
        if (FCursorY >= FScrollTop) and (FCursorY <= FScrollBottom) then
        begin
          top := FScrollTop;
          FScrollTop := FCursorY;
          ScrollDownRegion(n);
          FScrollTop := top;
        end;
      end;
    'M': // DL — Delete lines
      begin
        n := Param(0, 1);
        if (FCursorY >= FScrollTop) and (FCursorY <= FScrollBottom) then
        begin
          top := FScrollTop;
          FScrollTop := FCursorY;
          ScrollUpRegion(n);
          FScrollTop := top;
        end;
      end;
    'P': // DCH — Delete characters
      begin
        n := Param(0, 1);
        line := CursorLine();
        if FCursorX + n < FCols then
        begin
          Move(line[FCursorX + n], line[FCursorX], (FCols - FCursorX - n) * SizeOf(TTermCell));
          ClearLine(line, FCols - n, FCols - 1);
        end
        else
          ClearLine(line, FCursorX, FCols - 1);
        FChanged := True;
      end;
    'S': // SU — Scroll up
      ScrollUpRegion(Param(0, 1));
    'T': // SD — Scroll down
      ScrollDownRegion(Param(0, 1));
    'X': // ECH — Erase character
      begin
        n := Param(0, 1);
        ClearLine(CursorLine(), FCursorX, FCursorX + n - 1);
      end;
    'Z': // CBT — Cursor back tab
      begin
        n := Param(0, 1);
        while n > 0 do
        begin
          DoBackTab();
          Dec(n);
        end;
      end;
    'd': // VPA — Line position absolute
      SetCursor(FCursorX, Param(0, 1) - 1);
    'm': // SGR
      ExecuteSgr();
    'r': // DECSTBM — Set top and bottom margins
      begin
        top := Param(0, 1) - 1;
        bot := Param(1, FRows) - 1;
        if top < 0 then top := 0;
        if bot >= FRows then bot := FRows - 1;
        if top < bot then
        begin
          FScrollTop := top;
          FScrollBottom := bot;
          SetCursor(0, 0);
        end;
      end;
    's': // Save cursor
      SaveCursor();
    'u': // Restore cursor
      RestoreCursor();
    'c': // Device attributes
      FResponse := FResponse + #27'[?1;2c';
    'n': // DSR
      if Param(0, 0) = 6 then
        FResponse := FResponse + Format(#27'[%d;%dR', [FCursorY + 1, FCursorX + 1]);
  end;
end;

procedure TTerminalEmulator.HandleOscDispatch();
var
  semi: Integer;
  cmd, arg: string;
begin
  semi := Pos(';', FOSCBuf);
  if semi > 0 then
  begin
    cmd := Copy(FOSCBuf, 1, semi - 1);
    arg := Copy(FOSCBuf, semi + 1, MaxInt);
  end
  else
  begin
    cmd := FOSCBuf;
    arg := '';
  end;

  // OSC 0 / 2: set window/icon title
  if (cmd = '0') or (cmd = '2') then
  begin
    FTitle := arg;
    if Assigned(FOnTitle) then
      FOnTitle(Self, FTitle);
  end
  // OSC 52: clipboard
  else if (cmd = '52') and Assigned(FOnClipboard) then
    FOnClipboard(Self, arg);
end;

procedure TTerminalEmulator.HandleOsc();
begin
  HandleOscDispatch();
  FOSCBuf := '';
end;

procedure TTerminalEmulator.HandleControl(AByte: Byte);
begin
  case AByte of
    $07: // BEL
      begin
        FBell := True;
        if Assigned(FOnBell) then
          FOnBell(Self);
      end;
    $08: // BS
      if FCursorX > 0 then
      begin
        Dec(FCursorX);
        FWrapPending := False;
      end;
    $09: // HT
      DoTab();
    $0A, $0B, $0C: // LF, VT, FF
      begin
        NewlineWithScroll();
        if FNewLineMode then
          FCursorX := 0;
      end;
    $0D: // CR
      begin
        FCursorX := 0;
        FWrapPending := False;
      end;
    $0E: ; // SO
    $0F: ; // SI
  end;
end;

procedure TTerminalEmulator.HandleEscape(AByte: Byte);
begin
  case AByte of
    Ord('['):
      begin
        FState := stCsi;
        FParamCount := 0;
        FParamDigits := False;
        FPrivate := #0;
        FIntermediates := '';
        FillChar(FParams, SizeOf(FParams), 0);
      end;
    Ord(']'):
      begin
        FState := stOsc;
        FOSCBuf := '';
      end;
    Ord('='): // DECKPAM — Application Keypad
      begin
        FAppKeypad := True;
        FState := stGround;
      end;
    Ord('>'): // DECKPNM — Normal Keypad
      begin
        FAppKeypad := False;
        FState := stGround;
      end;
    Ord('7'): // DECSC — Save Cursor
      begin
        SaveCursor();
        FState := stGround;
      end;
    Ord('8'): // DECRC — Restore Cursor
      begin
        RestoreCursor();
        FState := stGround;
      end;
    Ord('M'): // RI — Reverse Index
      begin
        ReverseIndex();
        FState := stGround;
      end;
    Ord('E'): // NEL — Next Line
      begin
        FCursorX := 0;
        NewlineWithScroll();
        FState := stGround;
      end;
    Ord('c'): // RIS — Reset to Initial State
      begin
        Reset();
        FState := stGround;
      end;
    else
      FState := stGround;
  end;
end;

procedure TTerminalEmulator.HandleCsiByte(AByte: Byte);
var
  ch: Char;
begin
  ch := Chr(AByte);
  if (ch in ['0'..'9']) then
  begin
    if FParamCount = 0 then FParamCount := 1;
    FParams[FParamCount - 1] := FParams[FParamCount - 1] * 10 + (Ord(ch) - Ord('0'));
    FParamDigits := True;
  end
  else if ch = ';' then
  begin
    if FParamCount < MaxParams then
      Inc(FParamCount);
    FParamDigits := False;
  end
  else if (ch in ['?', '>', '<', '=']) and (FParamCount = 0) and (not FParamDigits) then
  begin
    FPrivate := ch;
  end
  else if (ch >= #$20) and (ch <= #$2F) then
  begin
    FIntermediates := FIntermediates + ch;
  end
  else if (ch >= #$40) and (ch <= #$7E) then
  begin
    FFinalByte := ch;
    ExecuteCsi();
    FState := stGround;
  end
  else
    FState := stGround;
end;

procedure TTerminalEmulator.AddUtf8Byte(AByte: Byte);
begin
  if FUtf8Need = 0 then
  begin
    if (AByte and $80) = 0 then
      PutChar(AByte)
    else if (AByte and $E0) = $C0 then
    begin
      FUtf8Code := AByte and $1F;
      FUtf8Need := 1;
      FUtf8Have := 0;
    end
    else if (AByte and $F0) = $E0 then
    begin
      FUtf8Code := AByte and $0F;
      FUtf8Need := 2;
      FUtf8Have := 0;
    end
    else if (AByte and $F8) = $F0 then
    begin
      FUtf8Code := AByte and $07;
      FUtf8Need := 3;
      FUtf8Have := 0;
    end;
  end
  else
  begin
    if (AByte and $C0) = $80 then
    begin
      FUtf8Code := (FUtf8Code shl 6) or (AByte and $3F);
      Inc(FUtf8Have);
      if FUtf8Have = FUtf8Need then
      begin
        PutChar(FUtf8Code);
        FUtf8Need := 0;
      end;
    end
    else
    begin
      // UTF-8 decoding error: drop pending and restart on current byte
      FUtf8Need := 0;
      AddUtf8Byte(AByte);
    end;
  end;
end;

procedure TTerminalEmulator.FeedByte(AByte: Byte);
begin
  case FState of
    stGround:
      begin
        if AByte = $1B then
        begin
          FState := stEscape;
          FIntermediates := '';
        end
        else if AByte < $20 then
          HandleControl(AByte)
        else if AByte = $7F then
        begin
          // ignore DEL
        end
        else
          AddUtf8Byte(AByte);
      end;
    stEscape:
      begin
        if (AByte = Ord('(')) or (AByte = Ord(')')) or (AByte = Ord('*'))
          or (AByte = Ord('+')) or (AByte = Ord('#')) then
          FIntermediates := Chr(AByte)
        else if FIntermediates <> '' then
        begin
          // Character set designation: ignore
          FState := stGround;
          FIntermediates := '';
        end
        else
          HandleEscape(AByte);
      end;
    stCsi:
      begin
        HandleCsiByte(AByte);
      end;
    stOsc:
      begin
        if AByte = $07 then
        begin
          HandleOsc();
          FState := stGround;
        end
        else if AByte = $1B then
          FState := stOscEsc
        else if Length(FOSCBuf) < 4096 then
          FOSCBuf := FOSCBuf + Chr(AByte);
      end;
    stOscEsc:
      begin
        if AByte = Ord('\') then
        begin
          HandleOsc();
          FState := stGround;
        end
        else
        begin
          FState := stGround;
          FeedByte(AByte);
        end;
      end;
  end;
end;

procedure TTerminalEmulator.Feed(ABuffer: PByte; ACount: Integer);
var
  i: Integer;
begin
  for i := 0 to ACount - 1 do
    FeedByte(ABuffer[i]);
end;

procedure TTerminalEmulator.Feed(const AData: RawByteString);
begin
  if Length(AData) > 0 then
    Feed(PByte(@AData[1]), Length(AData));
end;

procedure TTerminalEmulator.EnterAltScreen(AClear: Boolean);
var
  i: Integer;
begin
  if FAltScreen then Exit;
  FAltCursorX := FCursorX;
  FAltCursorY := FCursorY;
  SetLength(FSavedLines, Length(FLines));
  SetLength(FSavedLinesWrapped, Length(FLinesWrapped));
  for i := 0 to High(FLines) do
  begin
    FSavedLines[i] := Copy(FLines[i], 0, Length(FLines[i]));
    FSavedLinesWrapped[i] := FLinesWrapped[i];
  end;
  FLines := nil;
  FLinesWrapped := nil;
  SetLength(FLines, FRows);
  SetLength(FLinesWrapped, FRows);
  for i := 0 to FRows - 1 do
  begin
    FLines[i] := NewLine();
    FLinesWrapped[i] := False;
  end;
  FAltScreen := True;
  FCursorX := 0;
  FCursorY := 0;
  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  FViewOffset := 0;
  if AClear then
    ClearScreenLines(0, FCols - 1);
  FChanged := True;
end;

procedure TTerminalEmulator.LeaveAltScreen();
var
  i: Integer;
begin
  if not FAltScreen then Exit;
  FLines := nil;
  FLinesWrapped := nil;
  SetLength(FLines, Length(FSavedLines));
  SetLength(FLinesWrapped, Length(FSavedLinesWrapped));
  for i := 0 to High(FSavedLines) do
  begin
    FLines[i] := FSavedLines[i];
    FLinesWrapped[i] := FSavedLinesWrapped[i];
  end;
  SetLength(FSavedLines, 0);
  SetLength(FSavedLinesWrapped, 0);
  FAltScreen := False;
  FCursorX := FAltCursorX;
  FCursorY := FAltCursorY;
  if FCursorX >= FCols then FCursorX := FCols - 1;
  if FCursorY >= FRows then FCursorY := FRows - 1;
  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  FChanged := True;
end;

procedure TTerminalEmulator.Resize(ACols, ARows: Integer);
var
  i, idx: Integer;
  absCursorX, absCursorY: Integer;
  newCursorLine, newCursorCol: Integer;
  logicalCells: array of TTermCell;
  cellCount, chunkStart, chunkLen: Integer;
  cursorCharOffset, currentCellOffset: Integer;
  cursorFound: Boolean;
  newLines: array of TTermLine;
  newWrapped: array of Boolean;
  totalNew, bufTotalLines, availAfter, maxTrim, trimCount: Integer;
  logicalPhysicalLines, firstNewChunk: Integer;

  function LineContentLen(const ALine: TTermLine): Integer;
  var
    k: Integer;
  begin
    for k := High(ALine) downto 0 do
    begin
      if ALine[k].Code <> 0 then
        Exit(k + 1);
      if ALine[k].Attr.BG.Kind <> tckDefault then
        Exit(k + 1);
    end;
    Result := 0;
  end;

begin
  if ACols < 1 then ACols := 1;
  if ARows < 1 then ARows := 1;
  if (ACols = FCols) and (ARows = FRows) then Exit;

  // Alternate screen resize: TUI apps (vim, nano) manage their own screen cells.
  if FAltScreen then
  begin
    SetLength(newLines, ARows);
    SetLength(newWrapped, ARows);
    for i := 0 to ARows - 1 do
    begin
      SetLength(newLines[i], ACols);
      newWrapped[i] := False;
      if i < Length(FLines) then
      begin
        chunkLen := Min(ACols, Length(FLines[i]));
        if chunkLen > 0 then
          Move(FLines[i][0], newLines[i][0], chunkLen * SizeOf(TTermCell));
      end;
    end;
    FLines := newLines;
    FLinesWrapped := newWrapped;
    FCols := ACols;
    FRows := ARows;
    if FCursorX >= FCols then FCursorX := FCols - 1;
    if FCursorY >= FRows then FCursorY := FRows - 1;
    FScrollTop := 0;
    FScrollBottom := FRows - 1;
    ResetTabStops();
    FChanged := True;
    Exit;
  end;

  // Absolute cursor position in the buffer:
  absCursorX := FCursorX;
  absCursorY := VisibleTop() + FCursorY;
  if absCursorY < 0 then absCursorY := 0;
  if absCursorY >= Length(FLines) then absCursorY := Length(FLines) - 1;

  newCursorLine := -1;
  newCursorCol := -1;

  // Width reflow:
  if ACols <> FCols then
  begin
    SetLength(newLines, 0);
    SetLength(newWrapped, 0);
    idx := 0;
    while idx < Length(FLines) do
    begin
      SetLength(logicalCells, 0);
      cursorCharOffset := -1;
      cursorFound := False;
      logicalPhysicalLines := 0;
      firstNewChunk := Length(newLines);

      while idx < Length(FLines) do
      begin
        Inc(logicalPhysicalLines);
        if idx = absCursorY then
        begin
          cursorCharOffset := Length(logicalCells) + absCursorX;
          cursorFound := True;
        end;

        if (idx < Length(FLines) - 1) and (idx < Length(FLinesWrapped)) and FLinesWrapped[idx] then
        begin
          cellCount := Length(FLines[idx]);
        end
        else
        begin
          cellCount := LineContentLen(FLines[idx]);
        end;

        currentCellOffset := Length(logicalCells);
        if cellCount > 0 then
        begin
          SetLength(logicalCells, currentCellOffset + cellCount);
          Move(FLines[idx][0], logicalCells[currentCellOffset], cellCount * SizeOf(TTermCell));
        end;

        if (idx < Length(FLines) - 1) and (idx < Length(FLinesWrapped)) and FLinesWrapped[idx] then
          Inc(idx)
        else
        begin
          Inc(idx);
          Break;
        end;
      end;

      if Length(logicalCells) = 0 then
      begin
        totalNew := Length(newLines);
        SetLength(newLines, totalNew + 1);
        SetLength(newWrapped, totalNew + 1);
        SetLength(newLines[totalNew], ACols);
        newWrapped[totalNew] := False;
        if cursorFound then
        begin
          newCursorLine := totalNew;
          newCursorCol := Min(ACols - 1, absCursorX);
        end;
      end
      else
      begin
        chunkStart := 0;
        while chunkStart < Length(logicalCells) do
        begin
          chunkLen := Min(ACols, Length(logicalCells) - chunkStart);
          totalNew := Length(newLines);
          SetLength(newLines, totalNew + 1);
          SetLength(newWrapped, totalNew + 1);
          SetLength(newLines[totalNew], ACols);
          Move(logicalCells[chunkStart], newLines[totalNew][0], chunkLen * SizeOf(TTermCell));

          if chunkStart + chunkLen < Length(logicalCells) then
            newWrapped[totalNew] := True
          else
            newWrapped[totalNew] := False;

          if cursorFound and (newCursorLine < 0) then
          begin
            if (logicalPhysicalLines = 1) and (ACols < FCols) then
            begin
              newCursorLine := firstNewChunk;
              newCursorCol := Min(ACols - 1, absCursorX);
            end
            else if (cursorCharOffset >= chunkStart) and
               ((cursorCharOffset < chunkStart + chunkLen) or (chunkStart + chunkLen >= Length(logicalCells))) then
            begin
              newCursorLine := totalNew;
              newCursorCol := Min(ACols - 1, cursorCharOffset - chunkStart);
            end;
          end;

          chunkStart := chunkStart + chunkLen;
        end;
      end;
    end;

    FLines := newLines;
    FLinesWrapped := newWrapped;
    if newCursorLine < 0 then
    begin
      newCursorLine := Length(FLines) - 1;
      newCursorCol := 0;
    end;
  end
  else
  begin
    newCursorLine := absCursorY;
    newCursorCol := absCursorX;
  end;

  // Height adjustment on FLines:
  bufTotalLines := Length(FLines);
  if newCursorLine < 0 then newCursorLine := 0;
  if newCursorLine >= bufTotalLines then newCursorLine := bufTotalLines - 1;

  if bufTotalLines < ARows then
  begin
    SetLength(FLines, ARows);
    SetLength(FLinesWrapped, ARows);
    for i := bufTotalLines to ARows - 1 do
    begin
      SetLength(FLines[i], ACols);
      FLinesWrapped[i] := False;
    end;
    FCursorY := newCursorLine;
  end
  else
  begin
    availAfter := (bufTotalLines - 1) - newCursorLine;
    if availAfter > 0 then
    begin
      maxTrim := bufTotalLines - Max(ARows, newCursorLine + 1);
      trimCount := Min(availAfter, maxTrim);
      while (trimCount > 0) and (LineContentLen(FLines[bufTotalLines - 1]) = 0) do
      begin
        Dec(trimCount);
        Dec(bufTotalLines);
      end;
      SetLength(FLines, bufTotalLines);
      SetLength(FLinesWrapped, bufTotalLines);
    end;

    FCursorY := newCursorLine - (bufTotalLines - ARows);
    if FCursorY < 0 then
      FCursorY := 0
    else if FCursorY >= ARows then
      FCursorY := ARows - 1;
  end;

  FCursorX := Min(ACols - 1, Max(0, newCursorCol));
  FCols := ACols;
  FRows := ARows;
  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  FViewOffset := 0;
  FWrapPending := False;
  ResetTabStops();
  FChanged := True;
end;

function TTerminalEmulator.ViewCell(AViewRow, ACol: Integer): TTermCell;
var
  idx: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Attr.FG.Kind := tckDefault;
  Result.Attr.BG.Kind := tckDefault;
  idx := VisibleTop() - FViewOffset + AViewRow;
  if (idx < 0) or (idx >= Length(FLines)) then Exit;
  if (ACol < 0) or (ACol >= Length(FLines[idx])) then Exit;
  Result := FLines[idx][ACol];
end;

function TTerminalEmulator.CellText(const ACell: TTermCell): string;
begin
  if ACell.Code = 0 then
    Exit(' ');
  if ACell.Code < $80 then
    Result := Chr(ACell.Code)
  else
  begin
    if ACell.Code < $800 then
    begin
      SetLength(Result, 2);
      Result[1] := Chr($C0 or (ACell.Code shr 6));
      Result[2] := Chr($80 or (ACell.Code and $3F));
    end
    else if ACell.Code < $10000 then
    begin
      SetLength(Result, 3);
      Result[1] := Chr($E0 or (ACell.Code shr 12));
      Result[2] := Chr($80 or ((ACell.Code shr 6) and $3F));
      Result[3] := Chr($80 or (ACell.Code and $3F));
    end
    else
    begin
      SetLength(Result, 4);
      Result[1] := Chr($F0 or (ACell.Code shr 18));
      Result[2] := Chr($80 or ((ACell.Code shr 12) and $3F));
      Result[3] := Chr($80 or ((ACell.Code shr 6) and $3F));
      Result[4] := Chr($80 or (ACell.Code and $3F));
    end;
  end;
end;

function TTerminalEmulator.ViewLineText(AViewRow: Integer; ATrimRight: Boolean): string;
var
  c: Integer;
  cell: TTermCell;
  lastNonSpace: Integer;
begin
  Result := '';
  lastNonSpace := -1;
  for c := 0 to FCols - 1 do
  begin
    cell := ViewCell(AViewRow, c);
    if cfWideTail in cell.Flags then
      Continue;
    Result := Result + CellText(cell);
    if (cell.Code <> 0) and (cell.Code <> 32) then
      lastNonSpace := c;
  end;
  if ATrimRight then
  begin
    SetLength(Result, lastNonSpace + 1);
    while (Length(Result) > 0) and (Result[Length(Result)] = ' ') do
      Delete(Result, Length(Result), 1);
  end;
end;

function TTerminalEmulator.SelectedText(ALine1, ACol1, ALine2, ACol2: Integer): string;
var
  y, c, tmp: Integer;
  lineText: string;
  aLine, aCol: Integer;
begin
  Result := '';
  if ALine1 > ALine2 then
  begin
    tmp := ALine1; ALine1 := ALine2; ALine2 := tmp;
    tmp := ACol1; ACol1 := ACol2; ACol2 := tmp;
  end;
  for y := ALine1 to ALine2 do
  begin
    aLine := y;
    if y = ALine1 then
      aCol := ACol1
    else
      aCol := 0;
    lineText := '';
    for c := aCol to FCols - 1 do
    begin
      if (y = ALine2) and (c > ACol2) then
        Break;
      if cfWideTail in ViewCell(aLine, c).Flags then
        Continue;
      lineText := lineText + CellText(ViewCell(aLine, c));
    end;
    while (Length(lineText) > 0) and (lineText[Length(lineText)] = ' ') do
      Delete(lineText, Length(lineText), 1);
    Result := Result + lineText;
    if y < ALine2 then
      Result := Result + LineEnding;
  end;
end;

function TTerminalEmulator.HistoryCount(): Integer;
begin
  if FAltScreen then Exit(0);
  Result := Length(FLines) - FRows;
  if Result < 0 then Result := 0;
end;

function TTerminalEmulator.TotalLines(): Integer;
begin
  Result := Length(FLines);
end;

function TTerminalEmulator.ScrollOffset(): Integer;
begin
  Result := FViewOffset;
end;

procedure TTerminalEmulator.ScrollView(ADelta: Integer);
var
  maxOff: Integer;
begin
  if FAltScreen then Exit;
  maxOff := Length(FLines) - FRows;
  if maxOff < 0 then maxOff := 0;
  Inc(FViewOffset, ADelta);
  if FViewOffset < 0 then FViewOffset := 0;
  if FViewOffset > maxOff then FViewOffset := maxOff;
  FChanged := True;
end;

procedure TTerminalEmulator.SetScrollOffset(AOffset: Integer);
var
  maxOff: Integer;
begin
  if FAltScreen then Exit;
  maxOff := HistoryCount();
  if AOffset < 0 then AOffset := 0;
  if AOffset > maxOff then AOffset := maxOff;
  if FViewOffset <> AOffset then
  begin
    FViewOffset := AOffset;
    FChanged := True;
  end;
end;

procedure TTerminalEmulator.ScrollToBottom();
begin
  if FViewOffset <> 0 then
  begin
    FViewOffset := 0;
    FChanged := True;
  end;
end;

function TTerminalEmulator.TakeResponse(): string;
begin
  Result := FResponse;
  FResponse := '';
end;

function TTerminalEmulator.TakeBell(): Boolean;
begin
  Result := FBell;
  FBell := False;
end;

function TTerminalEmulator.TakeChanged(): Boolean;
begin
  Result := FChanged;
  FChanged := False;
end;

end.
