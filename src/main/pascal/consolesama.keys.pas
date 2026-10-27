// consolesama.keys.pas — X11 keysym translation for terminal input
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Keys;

{$mode objfpc}{$H+}

interface

const
  // X11 keysyms used by the terminal
  XK_BackSpace   = $FF08;
  XK_Tab         = $FF09;
  XK_Linefeed    = $FF0A;
  XK_Return      = $FF0D;
  XK_Pause       = $FF13;
  XK_Scroll_Lock = $FF14;
  XK_Sys_Req     = $FF15;
  XK_Escape      = $FF1B;
  XK_Delete      = $FFFF;

  XK_Home        = $FF50;
  XK_Left        = $FF51;
  XK_Up          = $FF52;
  XK_Right       = $FF53;
  XK_Down        = $FF54;
  XK_Page_Up     = $FF55;
  XK_Page_Down   = $FF56;
  XK_End         = $FF57;
  XK_Begin       = $FF58;
  XK_Insert      = $FF63;
  XK_Find        = $FF68;
  XK_Cancel      = $FF69;
  XK_Help        = $FF6A;

  XK_KP_Space     = $FF80;
  XK_KP_Tab       = $FF89;
  XK_KP_Enter     = $FF8D;
  XK_KP_Home      = $FF95;
  XK_KP_Left      = $FF96;
  XK_KP_Up        = $FF97;
  XK_KP_Right     = $FF98;
  XK_KP_Down      = $FF99;
  XK_KP_Page_Up   = $FF9A;
  XK_KP_Page_Down = $FF9B;
  XK_KP_End       = $FF9C;
  XK_KP_Begin     = $FF9D;
  XK_KP_Insert    = $FF9E;
  XK_KP_Delete    = $FF9F;
  XK_KP_Equal     = $FFBD;
  XK_KP_Multiply  = $FFAA;
  XK_KP_Add       = $FFAB;
  XK_KP_Separator = $FFAC;
  XK_KP_Subtract  = $FFAD;
  XK_KP_Decimal   = $FFAE;
  XK_KP_Divide    = $FFAF;
  XK_KP_0         = $FFB0;
  XK_KP_9         = $FFB9;

  XK_F1          = $FFBE;
  XK_F2          = $FFBF;
  XK_F3          = $FFC0;
  XK_F4          = $FFC1;
  XK_F5          = $FFC2;
  XK_F6          = $FFC3;
  XK_F7          = $FFC4;
  XK_F8          = $FFC5;
  XK_F9          = $FFC6;
  XK_F10         = $FFC7;
  XK_F11         = $FFC8;
  XK_F12         = $FFC9;

  XK_Shift_L     = $FFE1;
  XK_Shift_R     = $FFE2;
  XK_Control_L   = $FFE3;
  XK_Control_R   = $FFE4;
  XK_Caps_Lock   = $FFE5;
  XK_Shift_Lock  = $FFE6;
  XK_Meta_L      = $FFE7;
  XK_Meta_R      = $FFE8;
  XK_Alt_L       = $FFE9;
  XK_Alt_R       = $FFEA;
  XK_Super_L     = $FFEB;
  XK_Super_R     = $FFEC;
  XK_Hyper_L     = $FFED;
  XK_Hyper_R     = $FFEE;

  XK_ISO_Left_Tab = $FE20;

  // Modifier masks as delivered by X11 / xcb
  FtShiftMask   = 1;
  FtLockMask    = 2;
  FtControlMask = 4;
  FtMod1Mask    = 8;    // Alt
  FtMod2Mask    = 16;
  FtMod3Mask    = 32;
  FtMod4Mask    = 64;   // Super / Meta
  FtMod5Mask    = 128;

// Convert a keysym to the text it produces (may be empty for special keys).
function KeySymToText(AKeySym: LongWord): string;

// Convert a keysym plus modifier state to the byte sequence a terminal
// application expects. Returns '' when the key is a modifier-only press.
function KeySymToTerminalInput(AKeySym, AState: LongWord;
  AAppCursorKeys, AAppKeypad: Boolean): string;

// True for pure modifier keys (Shift, Ctrl, Alt, Caps, ...).
function IsModifierKeySym(AKeySym: LongWord): Boolean;

function IsCtrlPressed(AState: LongWord): Boolean;
function IsAltPressed(AState: LongWord): Boolean;
function IsShiftPressed(AState: LongWord): Boolean;

// Encode a Unicode code point as UTF-8.
function CodePointToUTF8(ACodePoint: LongWord): string;

implementation

uses
  SysUtils;

function IsCtrlPressed(AState: LongWord): Boolean;
begin
  Result := (AState and FtControlMask) <> 0;
end;

function IsAltPressed(AState: LongWord): Boolean;
begin
  Result := (AState and FtMod1Mask) <> 0;
end;

function IsShiftPressed(AState: LongWord): Boolean;
begin
  Result := (AState and FtShiftMask) <> 0;
end;

function IsModifierKeySym(AKeySym: LongWord): Boolean;
begin
  case AKeySym of
    XK_Shift_L, XK_Shift_R, XK_Control_L, XK_Control_R,
    XK_Caps_Lock, XK_Shift_Lock, XK_Meta_L, XK_Meta_R,
    XK_Alt_L, XK_Alt_R, XK_Super_L, XK_Super_R,
    XK_Hyper_L, XK_Hyper_R:
      Result := True;
    else
      Result := False;
  end;
end;

function CodePointToUTF8(ACodePoint: LongWord): string;
begin
  if ACodePoint < $80 then
  begin
    SetLength(Result, 1);
    Result[1] := Chr(ACodePoint);
  end
  else if ACodePoint < $800 then
  begin
    SetLength(Result, 2);
    Result[1] := Chr($C0 or (ACodePoint shr 6));
    Result[2] := Chr($80 or (ACodePoint and $3F));
  end
  else if ACodePoint < $10000 then
  begin
    SetLength(Result, 3);
    Result[1] := Chr($E0 or (ACodePoint shr 12));
    Result[2] := Chr($80 or ((ACodePoint shr 6) and $3F));
    Result[3] := Chr($80 or (ACodePoint and $3F));
  end
  else
  begin
    SetLength(Result, 4);
    Result[1] := Chr($F0 or (ACodePoint shr 18));
    Result[2] := Chr($80 or ((ACodePoint shr 12) and $3F));
    Result[3] := Chr($80 or ((ACodePoint shr 6) and $3F));
    Result[4] := Chr($80 or (ACodePoint and $3F));
  end;
end;

function KeySymToText(AKeySym: LongWord): string;
begin
  // Latin-1 printable range maps directly.
  if (AKeySym >= $20) and (AKeySym <= $7E) then
    Result := Chr(AKeySym)
  else if (AKeySym >= $A0) and (AKeySym <= $FF) then
    Result := CodePointToUTF8(AKeySym)
  // Unicode keysyms: 0x01000000 + code point.
  else if (AKeySym >= $01000100) and (AKeySym <= $0110FFFF) then
    Result := CodePointToUTF8(AKeySym and $00FFFFFF)
  else
  begin
    case AKeySym of
      XK_Return, XK_KP_Enter: Result := #13;
      XK_BackSpace: Result := #8;
      XK_Tab, XK_KP_Tab: Result := #9;
      XK_Escape: Result := #27;
      XK_KP_Space: Result := ' ';
      XK_KP_0..XK_KP_9: Result := Chr(Ord('0') + (AKeySym - XK_KP_0));
      XK_KP_Add: Result := '+';
      XK_KP_Subtract: Result := '-';
      XK_KP_Multiply: Result := '*';
      XK_KP_Divide: Result := '/';
      XK_KP_Decimal, XK_KP_Separator: Result := '.';
      XK_KP_Equal: Result := '=';
    else
      Result := '';
    end;
  end;
end;

function ModParam(AState: LongWord): Integer;
begin
  // xterm modifier parameter: 1 + Shift(1) + Alt(2) + Ctrl(4) + Super(8)
  Result := 1;
  if (AState and FtShiftMask) <> 0 then Inc(Result, 1);
  if (AState and FtMod1Mask) <> 0 then Inc(Result, 2);
  if (AState and FtControlMask) <> 0 then Inc(Result, 4);
  if (AState and FtMod4Mask) <> 0 then Inc(Result, 8);
end;

function CsiKey(const ALetter: Char; AMod: Integer): string;
begin
  if AMod <= 1 then
    Result := #27 + '[' + ALetter
  else
    Result := #27 + '[1;' + IntToStr(AMod) + ALetter;
end;

function CsiTilde(const ANum: Integer; AMod: Integer): string;
begin
  if AMod <= 1 then
    Result := #27 + '[' + IntToStr(ANum) + '~'
  else
    Result := #27 + '[' + IntToStr(ANum) + ';' + IntToStr(AMod) + '~';
end;

function KeySymToTerminalInput(AKeySym, AState: LongWord;
  AAppCursorKeys, AAppKeypad: Boolean): string;
var
  modp: Integer;
  txt: string;
  cp: LongWord;
begin
  Result := '';

  if IsModifierKeySym(AKeySym) then Exit;

  modp := ModParam(AState);

  // Cursor keys and editing keys.
  case AKeySym of
    XK_Up:
      begin
        if AAppCursorKeys then
        begin
          if modp <= 1 then Exit(#27 + 'OA')
          else Exit(#27 + '[1;' + IntToStr(modp) + 'A');
        end;
        Exit(CsiKey('A', modp));
      end;
    XK_Down: 
      begin
        if AAppCursorKeys then
        begin
          if modp <= 1 then Exit(#27 + 'OB')
          else Exit(#27 + '[1;' + IntToStr(modp) + 'B');
        end;
        Exit(CsiKey('B', modp));
      end;
    XK_Right:
      begin
        if AAppCursorKeys then
        begin
          if modp <= 1 then Exit(#27 + 'OC')
          else Exit(#27 + '[1;' + IntToStr(modp) + 'C');
        end;
        Exit(CsiKey('C', modp));
      end;
    XK_Left:
      begin
        if AAppCursorKeys then
        begin
          if modp <= 1 then Exit(#27 + 'OD')
          else Exit(#27 + '[1;' + IntToStr(modp) + 'D');
        end;
        Exit(CsiKey('D', modp));
      end;
    XK_Home:
      begin
        if AAppCursorKeys then
        begin
          if modp <= 1 then Exit(#27 + 'OH')
          else Exit(#27 + '[1;' + IntToStr(modp) + 'H');
        end;
        Exit(CsiKey('H', modp));
      end;
    XK_End:
      begin
        if AAppCursorKeys then
        begin
          if modp <= 1 then Exit(#27 + 'OF')
          else Exit(#27 + '[1;' + IntToStr(modp) + 'F');
        end;
        Exit(CsiKey('F', modp));
      end;
    XK_Insert: Exit(CsiTilde(2, modp));
    XK_Delete: Exit(CsiTilde(3, modp));
    XK_Page_Up: Exit(CsiTilde(5, modp));
    XK_Page_Down: Exit(CsiTilde(6, modp));
    XK_KP_Home: Exit(CsiKey('H', modp));
    XK_KP_End: Exit(CsiKey('F', modp));
    XK_KP_Insert: Exit(CsiTilde(2, modp));
    XK_KP_Delete: Exit(CsiTilde(3, modp));
    XK_KP_Page_Up: Exit(CsiTilde(5, modp));
    XK_KP_Page_Down: Exit(CsiTilde(6, modp));
    XK_KP_Up: Exit(CsiKey('A', modp));
    XK_KP_Down: Exit(CsiKey('B', modp));
    XK_KP_Right: Exit(CsiKey('C', modp));
    XK_KP_Left: Exit(CsiKey('D', modp));
    XK_ISO_Left_Tab: Exit(#27 + '[Z');
    XK_F1: if modp <= 1 then Exit(#27 + 'OP') else Exit(#27 + '[1;' + IntToStr(modp) + 'P');
    XK_F2: if modp <= 1 then Exit(#27 + 'OQ') else Exit(#27 + '[1;' + IntToStr(modp) + 'Q');
    XK_F3: if modp <= 1 then Exit(#27 + 'OR') else Exit(#27 + '[1;' + IntToStr(modp) + 'R');
    XK_F4: if modp <= 1 then Exit(#27 + 'OS') else Exit(#27 + '[1;' + IntToStr(modp) + 'S');
    XK_F5: Exit(CsiTilde(15, modp));
    XK_F6: Exit(CsiTilde(17, modp));
    XK_F7: Exit(CsiTilde(18, modp));
    XK_F8: Exit(CsiTilde(19, modp));
    XK_F9: Exit(CsiTilde(20, modp));
    XK_F10: Exit(CsiTilde(21, modp));
    XK_F11: Exit(CsiTilde(23, modp));
    XK_F12: Exit(CsiTilde(24, modp));
    XK_Return, XK_KP_Enter: Exit(#13);
    XK_Tab, XK_KP_Tab: Exit(#9);
    XK_BackSpace: Exit(#127);
    XK_Escape: Exit(#27);
  end;

  // Ctrl + printable key produces a C0 control character.
  if IsCtrlPressed(AState) then
  begin
    cp := AKeySym;
    if (cp >= Ord('a')) and (cp <= Ord('z')) then
      Exit(CodePointToUTF8(cp - Ord('a') + 1));
    if (cp >= Ord('A')) and (cp <= Ord('Z')) then
      Exit(CodePointToUTF8(cp - Ord('A') + 1));
    case cp of
      Ord('@'), Ord(' '), Ord('2'): Exit(#0);
      Ord('['): Exit(#27);
      Ord('\'): Exit(#28);
      Ord(']'): Exit(#29);
      Ord('^'): Exit(#30);
      Ord('_'): Exit(#31);
      Ord('?'): Exit(#127);
    end;
  end;

  txt := KeySymToText(AKeySym);
  if txt = '' then Exit('');

  // Alt acts as the meta/escape prefix.
  if IsAltPressed(AState) then
    Result := #27 + txt
  else
    Result := txt;
end;

end.
