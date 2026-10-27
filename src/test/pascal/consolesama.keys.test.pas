// consolesama.keys.test.pas — unit tests for keyboard translation
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Keys.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  ConsoleSama.Keys;

type
  TKeysTranslationTest = class(TTestCase)
  published
    procedure TestPrintableKeys();
    procedure TestControlKeys();
    procedure TestArrowKeys();
    procedure TestApplicationCursorKeys();
    procedure TestSpecialKeys();
    procedure TestEditingKeys();
    procedure TestModifierCombinations();
    procedure TestCapsLock();
    procedure TestUtf8Encoding();
  end;

implementation

procedure TKeysTranslationTest.TestPrintableKeys();
begin
  AssertEquals('Printable letter a', 'a', KeySymToTerminalInput(Ord('a'), 0, False, False));
  AssertEquals('Printable letter Z', 'Z', KeySymToTerminalInput(Ord('Z'), 0, False, False));
  AssertEquals('Printable digit 7', '7', KeySymToTerminalInput(Ord('7'), 0, False, False));
  AssertEquals('Space', ' ', KeySymToTerminalInput(Ord(' '), 0, False, False));
end;

procedure TKeysTranslationTest.TestControlKeys();
begin
  // Ctrl+C -> ETX (#3)
  AssertEquals('Ctrl+C', #3, KeySymToTerminalInput(Ord('c'), FtControlMask, False, False));
  AssertEquals('Ctrl+C uppercase', #3, KeySymToTerminalInput(Ord('C'), FtControlMask, False, False));

  // Ctrl+A -> SOH (#1)
  AssertEquals('Ctrl+A', #1, KeySymToTerminalInput(Ord('a'), FtControlMask, False, False));

  // Ctrl+D -> EOT (#4)
  AssertEquals('Ctrl+D', #4, KeySymToTerminalInput(Ord('d'), FtControlMask, False, False));

  // Ctrl+Z -> SUB (#26)
  AssertEquals('Ctrl+Z', #26, KeySymToTerminalInput(Ord('z'), FtControlMask, False, False));

  // Ctrl+[ -> ESC (#27)
  AssertEquals('Ctrl+[', #27, KeySymToTerminalInput(Ord('['), FtControlMask, False, False));
end;

procedure TKeysTranslationTest.TestArrowKeys();
begin
  AssertEquals('Up arrow normal', #27'[A', KeySymToTerminalInput(XK_Up, 0, False, False));
  AssertEquals('Down arrow normal', #27'[B', KeySymToTerminalInput(XK_Down, 0, False, False));
  AssertEquals('Right arrow normal', #27'[C', KeySymToTerminalInput(XK_Right, 0, False, False));
  AssertEquals('Left arrow normal', #27'[D', KeySymToTerminalInput(XK_Left, 0, False, False));
end;

procedure TKeysTranslationTest.TestApplicationCursorKeys();
begin
  AssertEquals('Up arrow app mode', #27'OA', KeySymToTerminalInput(XK_Up, 0, True, False));
  AssertEquals('Down arrow app mode', #27'OB', KeySymToTerminalInput(XK_Down, 0, True, False));
  AssertEquals('Right arrow app mode', #27'OC', KeySymToTerminalInput(XK_Right, 0, True, False));
  AssertEquals('Left arrow app mode', #27'OD', KeySymToTerminalInput(XK_Left, 0, True, False));
end;

procedure TKeysTranslationTest.TestSpecialKeys();
begin
  AssertEquals('Return', #13, KeySymToTerminalInput(XK_Return, 0, False, False));
  AssertEquals('BackSpace', #127, KeySymToTerminalInput(XK_BackSpace, 0, False, False));
  AssertEquals('Tab', #9, KeySymToTerminalInput(XK_Tab, 0, False, False));
  AssertEquals('Escape', #27, KeySymToTerminalInput(XK_Escape, 0, False, False));
end;

procedure TKeysTranslationTest.TestEditingKeys();
begin
  AssertEquals('Home', #27'[H', KeySymToTerminalInput(XK_Home, 0, False, False));
  AssertEquals('End', #27'[F', KeySymToTerminalInput(XK_End, 0, False, False));
  AssertEquals('Insert', #27'[2~', KeySymToTerminalInput(XK_Insert, 0, False, False));
  AssertEquals('Delete', #27'[3~', KeySymToTerminalInput(XK_Delete, 0, False, False));
  AssertEquals('PageUp', #27'[5~', KeySymToTerminalInput(XK_Page_Up, 0, False, False));
  AssertEquals('PageDown', #27'[6~', KeySymToTerminalInput(XK_Page_Down, 0, False, False));
end;

procedure TKeysTranslationTest.TestModifierCombinations();
begin
  // Shift+Up: mod param = 1 + Shift(1) = 2 -> \e[1;2A
  AssertEquals('Shift+Up', #27'[1;2A', KeySymToTerminalInput(XK_Up, FtShiftMask, False, False));

  // Alt+Down: mod param = 1 + Alt(2) = 3 -> \e[1;3B
  AssertEquals('Alt+Down', #27'[1;3B', KeySymToTerminalInput(XK_Down, FtMod1Mask, False, False));

  // Ctrl+Right: mod param = 1 + Ctrl(4) = 5 -> \e[1;5C
  AssertEquals('Ctrl+Right', #27'[1;5C', KeySymToTerminalInput(XK_Right, FtControlMask, False, False));

  // Ctrl+Shift+Left: mod param = 1 + 1 + 4 = 6 -> \e[1;6D
  AssertEquals('Ctrl+Shift+Left', #27'[1;6D', KeySymToTerminalInput(XK_Left, FtShiftMask or FtControlMask, False, False));
end;

procedure TKeysTranslationTest.TestCapsLock();
begin
  // CapsLock uppercases unshifted letters...
  AssertEquals('Caps+ a', 'A', KeySymToTerminalInput(Ord('a'), FtLockMask, False, False));
  // ...and lowercases Shift+letter (Caps inverts Shift).
  AssertEquals('Caps+Shift+ a', 'a',
    KeySymToTerminalInput(Ord('A'), FtLockMask or FtShiftMask, False, False));
  // Non-letter keys are unaffected by CapsLock.
  AssertEquals('Caps+7', '7', KeySymToTerminalInput(Ord('7'), FtLockMask, False, False));
  // Ctrl combinations still produce control characters.
  AssertEquals('Caps+Ctrl+c', #3,
    KeySymToTerminalInput(Ord('c'), FtLockMask or FtControlMask, False, False));
  // Latin-1 letters are case-folded too.
  AssertEquals('Caps+é', #$C3#$89, KeySymToTerminalInput($E9, FtLockMask, False, False));
end;

procedure TKeysTranslationTest.TestUtf8Encoding();
begin
  // ASCII 'A' ($41)
  AssertEquals('ASCII UTF-8', 'A', CodePointToUTF8($41));
  // Latin 'é' ($E9)
  AssertEquals('Latin UTF-8', #$C3#$A9, CodePointToUTF8($E9));
  // CJK '中' ($4E2D)
  AssertEquals('CJK UTF-8', #$E4#$B8#$AD, CodePointToUTF8($4E2D));
  // Emoji '🚀' ($1F680)
  AssertEquals('Emoji UTF-8', #$F0#$9F#$9A#$80, CodePointToUTF8($1F680));
end;

initialization
  RegisterTest(TKeysTranslationTest);

end.
