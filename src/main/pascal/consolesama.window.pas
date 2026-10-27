// consolesama.window.pas — application window
// Copyright (c) 2026 Dio Affriza — SPDX-License-Identifier: MPL-2.0

unit ConsoleSama.Window;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix,
  ftpas, ftpas.types, ftpas.api, ftpas.app, ftpas.widget, ftpas.controls, ftpas.layouts, ftpas.menus,
  ftpas.ftml, ftpas.font,
  ConsoleSama.Terminal, ConsoleSama.Vt, ConsoleSama.Pty, ConsoleSama.Keys;

type
  // One notebook page plus the terminal living inside it.
  TConsoleTab = class
  public
    Page: TFtWidget;
    View: TConsoleTerminalView;
    ScrollBar: TFtScrollBar;
    Title: string;
    CustomTitle: Boolean;
  end;

  TConsoleSamaWindow = class(TFtFTMLForm)
  private
    FNotebook: TFtNotebook;
    FStatusBar: TFtWidget;
    FStatusText: TFtLabel;
    FStatusRight: TFtLabel;
    FTabs: TList;
    FActiveIndex: Integer;
    FTabCounter: Integer;
    FLastPump: QWord;
    FLastStatus: QWord;
    FClosing: Boolean;
    FDebugMode: Boolean;

    procedure SetupUI();
    procedure DumpLayout(const ATag: string);
    procedure HookMenu(const AId: string; AHandler: TNotifyEvent);
    function  AddTerminalTab(): TConsoleTab;
    procedure CloseTab(AIndex: Integer);
    procedure LayoutTabs();
    procedure UpdateStatus();
    procedure UpdateTitle();
    procedure FocusActive();
    procedure HandleTabChange(Sender: TFtNotebook; ANewIndex, AOldIndex: Integer);
    function  HandleShortcut(Sender: TObject; AKeySym, AState: LongWord): Boolean;
    procedure HandleTerminalTitle(Sender: TObject; const ATitle: string);
    procedure HandleTerminalExit(Sender: TObject);
    procedure PumpTabs();

    procedure MenuNewTab(Sender: TObject);
    procedure MenuNewWindow(Sender: TObject);
    procedure MenuCloseTab(Sender: TObject);
    procedure MenuQuit(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuPaste(Sender: TObject);
    procedure MenuSelectAll(Sender: TObject);
    procedure MenuZoomIn(Sender: TObject);
    procedure MenuZoomOut(Sender: TObject);
    procedure MenuZoomReset(Sender: TObject);
    procedure MenuToggleDarkMode(Sender: TObject);
    procedure MenuScrollUp(Sender: TObject);
    procedure MenuScrollDown(Sender: TObject);
    procedure MenuScrollEnd(Sender: TObject);
    procedure MenuAbout(Sender: TObject);
  protected
    procedure DoResize(ANewWidth, ANewHeight: Integer); override;
  public
    constructor Create(ADebugMode: Boolean = False); reintroduce;
    destructor Destroy(); override;

    procedure PumpTicks();
    function  ActiveTab(): TConsoleTab;
    function  ActiveTerminal(): TConsoleTerminalView;
    property Notebook: TFtNotebook read FNotebook;
    property DebugMode: Boolean read FDebugMode;
  end;

// Spawn another consolesama process (used by File ▸ New Window).
procedure SpawnNewConsolesama();

implementation

uses
  Math, ftpas.dialogs;

var
  GCurrentWindow: TConsoleSamaWindow = nil;
  GDebugMode: Boolean = False;

// ----------------------------- Tick plumbing -----------------------------

procedure TickDispatcher(AUserData: Pointer); cdecl;
begin
  if AUserData <> nil then
    TConsoleSamaWindow(AUserData).PumpTicks();
end;

procedure SpawnNewConsolesama();
var
  pid: TPid;
  exe: string;
  argv: array[0..2] of PChar;
begin
  exe := ParamStr(0);
  if exe = '' then Exit;
  pid := fpFork();
  if pid = 0 then
  begin
    argv[0] := PChar(exe);
    if GDebugMode then
    begin
      argv[1] := '--debug';
      argv[2] := nil;
    end
    else
      argv[1] := nil;
    fpExecv(PChar(exe), @argv[0]);
    Halt(127);
  end;
end;

// ------------------------------- Window ----------------------------------

constructor TConsoleSamaWindow.Create(ADebugMode: Boolean);
begin
  inherited Create(980, 660, 'consolesama', 'TConsoleSamaWindow');
  FDebugMode := ADebugMode;
  FTabs := TList.Create();
  FActiveIndex := -1;
  FTabCounter := 0;
  FLastPump := 0;
  FLastStatus := 0;
  FClosing := False;
  GDebugMode := ADebugMode;
  GCurrentWindow := Self;

  SetupUI();
  DoResize(Width, Height);

  // First terminal tab.
  AddTerminalTab();

  if Assigned(ft_set_tick_callback) then
    ft_set_tick_callback(@TickDispatcher, Pointer(Self));
end;

destructor TConsoleSamaWindow.Destroy();
var
  i: Integer;
begin
  if Assigned(ft_set_tick_callback) then
    ft_set_tick_callback(nil, nil);
  if GCurrentWindow = Self then
    GCurrentWindow := nil;
  if FTabs <> nil then
  begin
    for i := 0 to FTabs.Count - 1 do
      TConsoleTab(FTabs[i]).Free();
    FreeAndNil(FTabs);
  end;
  inherited Destroy();
end;

procedure TConsoleSamaWindow.SetupUI();
var
  w: TFtWidget;
begin
  w := FindWidget('tabHost');
  if w is TFtNotebook then
    FNotebook := TFtNotebook(w);
  w := FindWidget('statusBar');
  if w <> nil then
    FStatusBar := w;
  w := FindWidget('statusText');
  if w is TFtLabel then
    FStatusText := TFtLabel(w);
  w := FindWidget('statusRight');
  if w is TFtLabel then
    FStatusRight := TFtLabel(w);

  // The status bar is a developer aid: hidden unless --debug was passed.
  if (FStatusBar <> nil) and (not FDebugMode) then
    FStatusBar.Hide();

  if FNotebook = nil then
  begin
    WriteLn(StdErr, '[consolesama] FTML design has no Notebook with id tabHost.');
    Halt(2);
  end;

  FNotebook.OnTabChange := @HandleTabChange;

  HookMenu('newTabItem', @MenuNewTab);
  HookMenu('newWindowItem', @MenuNewWindow);
  HookMenu('closeTabItem', @MenuCloseTab);
  HookMenu('quitItem', @MenuQuit);
  HookMenu('copyItem', @MenuCopy);
  HookMenu('pasteItem', @MenuPaste);
  HookMenu('selectAllItem', @MenuSelectAll);
  HookMenu('zoomInItem', @MenuZoomIn);
  HookMenu('zoomOutItem', @MenuZoomOut);
  HookMenu('zoomResetItem', @MenuZoomReset);
  HookMenu('darkModeItem', @MenuToggleDarkMode);
  HookMenu('scrollUpItem', @MenuScrollUp);
  HookMenu('scrollDownItem', @MenuScrollDown);
  HookMenu('scrollEndItem', @MenuScrollEnd);
  HookMenu('aboutItem', @MenuAbout);

  if GetEnvironmentVariable('CS_DEBUG') = '1' then
    DumpLayout('after SetupUI');
end;

procedure TConsoleSamaWindow.DumpLayout(const ATag: string);
var
  ids: array[0..3] of string = ('menuBar', 'tabHost', 'statusBar', 'statusText');
  i: Integer;
  w: TFtWidget;
begin
  WriteLn(StdErr, '--- layout ', ATag, ' window=', Width, 'x', Height);
  for i := Low(ids) to High(ids) do
  begin
    w := FindWidget(ids[i]);
    if w = nil then
      WriteLn(StdErr, '  ', ids[i], ': <none>')
    else
      WriteLn(StdErr, '  ', ids[i], ': ', w.ClassName, ' x=', w.X, ' y=', w.Y,
        ' w=', w.Width, ' h=', w.Height, ' vis=', w.Visible);
  end;
  if FNotebook <> nil then
    WriteLn(StdErr, '  notebook pages=', FNotebook.PageCount,
      ' tabHeight=', FNotebook.TabHeight);
end;

procedure TConsoleSamaWindow.HookMenu(const AId: string; AHandler: TNotifyEvent);
var
  mi: TFtMenuItem;
begin
  mi := FindMenuItem(AId);
  if mi <> nil then
    mi.OnClick := TFtMenuClickEvent(AHandler);
end;

function TConsoleSamaWindow.ActiveTab(): TConsoleTab;
begin
  if (FActiveIndex >= 0) and (FActiveIndex < FTabs.Count) then
    Result := TConsoleTab(FTabs[FActiveIndex])
  else
    Result := nil;
end;

function TConsoleSamaWindow.ActiveTerminal(): TConsoleTerminalView;
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then
    Result := tab.View
  else
    Result := nil;
end;

function TConsoleSamaWindow.AddTerminalTab(): TConsoleTab;
const
  ScrollBarWidth = 14;
var
  page: TFtTabPage;
  pageWidget: TFtWidget;
  view: TConsoleTerminalView;
  sb: TFtScrollBar;
  tab: TConsoleTab;
  availW, availH, termW, pageX, pageY: Integer;
begin
  Inc(FTabCounter);

  page := FNotebook.AddTab(Format('Terminal %d', [FTabCounter]), True);
  pageWidget := TFtWidget.Wrap(page.Handle, FNotebook, False);

  availW := FNotebook.Width;
  availH := FNotebook.Height - Round(FNotebook.TabHeight) - 2;
  if availW < 100 then availW := 980;
  if availH < 100 then availH := 580;

  pageX := FNotebook.X;
  pageY := FNotebook.Y + Round(FNotebook.TabHeight);
  termW := availW - ScrollBarWidth;
  if termW < 50 then termW := availW;

  pageWidget.SetBounds(pageX, pageY, availW, availH);

  view := TConsoleTerminalView.Create(pageWidget, pageX, pageY, termW, availH);
  view.OnShortcut := @HandleShortcut;
  view.OnTitle := @HandleTerminalTitle;
  view.OnExit := @HandleTerminalExit;

  sb := TFtScrollBar.Create(pageWidget, pageX + termW, pageY, ScrollBarWidth, availH, ftsboVertical);
  sb.CornerRadius := 4.0;
  view.ScrollBar := sb;

  tab := TConsoleTab.Create();
  tab.Page := pageWidget;
  tab.View := view;
  tab.ScrollBar := sb;
  tab.Title := Format('Terminal %d', [FTabCounter]);
  tab.CustomTitle := False;
  FTabs.Add(tab);

  FActiveIndex := FTabs.Count - 1;
  FNotebook.ActiveIndex := FActiveIndex;

  view.StartShell('', '');
  LayoutTabs();
  view.SetFocus();
  UpdateStatus();
  Result := tab;
end;

procedure TConsoleSamaWindow.CloseTab(AIndex: Integer);
var
  tab: TConsoleTab;
begin
  if (AIndex < 0) or (AIndex >= FTabs.Count) then Exit;
  tab := TConsoleTab(FTabs[AIndex]);

  if tab.ScrollBar <> nil then
  begin
    tab.ScrollBar.Visible := False;
    FreeAndNil(tab.ScrollBar);
  end;
  if tab.View <> nil then
  begin
    tab.View.Visible := False;
    FreeAndNil(tab.View);
  end;
  if tab.Page <> nil then
  begin
    FreeAndNil(tab.Page);
  end;

  FTabs.Delete(AIndex);
  tab.Free();

  if FNotebook <> nil then
    FNotebook.RemoveTab(AIndex);

  if FTabs.Count = 0 then
  begin
    Close();
    Exit;
  end;

  if AIndex >= FTabs.Count then
    FActiveIndex := FTabs.Count - 1
  else
    FActiveIndex := AIndex;
  FNotebook.ActiveIndex := FActiveIndex;
  FocusActive();
  UpdateStatus();
end;

procedure TConsoleSamaWindow.LayoutTabs();
const
  ScrollBarWidth = 14;
var
  i, availW, availH, termW, pageX, pageY: Integer;
  tab: TConsoleTab;
begin
  if FNotebook = nil then Exit;

  // Without the debug status bar the notebook claims the space down to the
  // window's bottom edge.
  if not FDebugMode then
    FNotebook.SetBounds(FNotebook.X, FNotebook.Y, FNotebook.Width,
      Height - FNotebook.Y);

  availW := FNotebook.Width;
  availH := FNotebook.Height - Round(FNotebook.TabHeight) - 2;
  if availW < 100 then availW := 980;
  if availH < 100 then availH := 580;

  pageX := FNotebook.X;
  pageY := FNotebook.Y + Round(FNotebook.TabHeight);
  termW := availW - ScrollBarWidth;
  if termW < 50 then termW := availW;

  for i := 0 to FTabs.Count - 1 do
  begin
    tab := TConsoleTab(FTabs[i]);
    if tab.Page <> nil then
      tab.Page.SetBounds(pageX, pageY, availW, availH);

    if tab.View <> nil then
    begin
      tab.View.SetBounds(pageX, pageY, termW, availH);
      tab.View.Invalidate();
    end;

    if tab.ScrollBar <> nil then
    begin
      tab.ScrollBar.SetBounds(pageX + termW, pageY, ScrollBarWidth, availH);
      if tab.View <> nil then
        tab.View.UpdateScrollBar();
      tab.ScrollBar.Invalidate();
    end;
  end;
end;

procedure TConsoleSamaWindow.DoResize(ANewWidth, ANewHeight: Integer);
begin
  inherited DoResize(ANewWidth, ANewHeight);
  LayoutTabs();
end;

procedure TConsoleSamaWindow.FocusActive();
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if (tab <> nil) and (tab.View <> nil) then
    tab.View.SetFocus();
end;

procedure TConsoleSamaWindow.HandleTabChange(Sender: TFtNotebook;
  ANewIndex, AOldIndex: Integer);
begin
  if (ANewIndex >= 0) and (ANewIndex < FTabs.Count) then
  begin
    FActiveIndex := ANewIndex;
    LayoutTabs();
    FocusActive();
    UpdateStatus();
  end;
end;

procedure TConsoleSamaWindow.PumpTabs();
var
  i: Integer;
  tab: TConsoleTab;
begin
  for i := 0 to FTabs.Count - 1 do
  begin
    tab := TConsoleTab(FTabs[i]);
    if tab.View <> nil then
      tab.View.Pump();
  end;
end;

procedure TConsoleSamaWindow.PumpTicks();
var
  nowTick: QWord;
begin
  nowTick := GetTickCount64();
  if nowTick - FLastPump < 8 then
  begin
    Sleep(8 - Byte(nowTick - FLastPump));
    Exit;
  end;
  FLastPump := nowTick;

  PumpTabs();
  LayoutTabs();

  if nowTick - FLastStatus > 500 then
  begin
    FLastStatus := nowTick;
    UpdateStatus();
  end;
end;

procedure TConsoleSamaWindow.UpdateStatus();
var
  tab: TConsoleTab;
  right: string;
begin
  tab := ActiveTab();
  if FStatusText <> nil then
  begin
    if tab = nil then
      FStatusText.Text := 'Console'
    else
      FStatusText.Text := Format('%s — %dx%d', [tab.Title, tab.View.TermCols, tab.View.TermRows]);
  end;
  if FStatusRight <> nil then
  begin
    if (tab <> nil) and (tab.View.PTY <> nil) then
      right := Format('pid %d', [tab.View.PTY.ChildPid])
    else
      right := '';
    FStatusRight.Text := right;
  end;
end;

procedure TConsoleSamaWindow.UpdateTitle();
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if (tab <> nil) and tab.CustomTitle then
    Title := tab.Title + ' — Samarinda Console'
  else
    Title := 'Samarinda Console';
end;

procedure TConsoleSamaWindow.HandleTerminalTitle(Sender: TObject; const ATitle: string);
var
  i: Integer;
  tab: TConsoleTab;
begin
  for i := 0 to FTabs.Count - 1 do
  begin
    tab := TConsoleTab(FTabs[i]);
    if tab.View = Sender then
    begin
      if ATitle <> '' then
      begin
        tab.Title := ATitle;
        tab.CustomTitle := True;
      end
      else
      begin
        tab.Title := Format('Terminal %d', [i + 1]);
        tab.CustomTitle := False;
      end;
      FNotebook.GetPage(i).Title := tab.Title;
      if i = FActiveIndex then
      begin
        UpdateTitle();
        UpdateStatus();
      end;
      Break;
    end;
  end;
end;

procedure TConsoleSamaWindow.HandleTerminalExit(Sender: TObject);
var
  i: Integer;
  tab: TConsoleTab;
begin
  if FClosing then Exit;
  for i := 0 to FTabs.Count - 1 do
  begin
    tab := TConsoleTab(FTabs[i]);
    if tab.View = Sender then
    begin
      CloseTab(i);
      Break;
    end;
  end;
end;

function TConsoleSamaWindow.HandleShortcut(Sender: TObject; AKeySym,
  AState: LongWord): Boolean;
var
  ctrl, shift: Boolean;
  ch: Char;
  tab: TConsoleTab;
begin
  Result := False;
  ctrl := IsCtrlPressed(AState);
  shift := IsShiftPressed(AState);
  if not ctrl then Exit;

  ch := #0;
  if (AKeySym >= 32) and (AKeySym <= 126) then
    ch := UpCase(Char(AKeySym));

  if shift then
  begin
    case ch of
      'T':
        begin
          AddTerminalTab();
          Result := True;
        end;
      'W':
        begin
          CloseTab(FActiveIndex);
          Result := True;
        end;
      'N':
        begin
          SpawnNewConsolesama();
          Result := True;
        end;
      'C':
        begin
          tab := ActiveTab();
          if tab <> nil then tab.View.CopySelection();
          Result := True;
        end;
      'V':
        begin
          tab := ActiveTab();
          if tab <> nil then tab.View.PasteFromClipboard();
          Result := True;
        end;
      'A':
        begin
          tab := ActiveTab();
          if tab <> nil then tab.View.SelectAll();
          Result := True;
        end;
      'D':
        begin
          MenuToggleDarkMode(Self);
          Result := True;
        end;
    end;
    Exit;
  end;

  if (AKeySym = Ord('+')) or (AKeySym = Ord('=')) or (AKeySym = XK_KP_Add) then
  begin
    tab := ActiveTab();
    if tab <> nil then tab.View.Zoom(1);
    Result := True;
  end
  else if (AKeySym = Ord('-')) or (AKeySym = Ord('_')) or (AKeySym = XK_KP_Subtract) then
  begin
    tab := ActiveTab();
    if tab <> nil then tab.View.Zoom(-1);
    Result := True;
  end
  else if (AKeySym = Ord('0')) or (AKeySym = XK_KP_0) then
  begin
    tab := ActiveTab();
    if tab <> nil then tab.View.ResetZoom();
    Result := True;
  end
  else if ch = 'Q' then
  begin
    Close();
    Result := True;
  end;
end;

// --------------------------------- Menus ---------------------------------

procedure TConsoleSamaWindow.MenuNewTab(Sender: TObject);
begin
  AddTerminalTab();
end;

procedure TConsoleSamaWindow.MenuNewWindow(Sender: TObject);
begin
  SpawnNewConsolesama();
end;

procedure TConsoleSamaWindow.MenuCloseTab(Sender: TObject);
begin
  CloseTab(FActiveIndex);
end;

procedure TConsoleSamaWindow.MenuQuit(Sender: TObject);
begin
  Close();
end;

procedure TConsoleSamaWindow.MenuCopy(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.CopySelection();
end;

procedure TConsoleSamaWindow.MenuPaste(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.PasteFromClipboard();
end;

procedure TConsoleSamaWindow.MenuSelectAll(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.SelectAll();
end;

procedure TConsoleSamaWindow.MenuZoomIn(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.Zoom(1);
end;

procedure TConsoleSamaWindow.MenuZoomOut(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.Zoom(-1);
end;

procedure TConsoleSamaWindow.MenuZoomReset(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.ResetZoom();
end;

procedure TConsoleSamaWindow.MenuToggleDarkMode(Sender: TObject);
var
  i: Integer;
  tab: TConsoleTab;
begin
  FtApp().DarkMode := not FtApp().DarkMode;
  if FTabs <> nil then
  begin
    for i := 0 to FTabs.Count - 1 do
    begin
      tab := TConsoleTab(FTabs[i]);
      if tab.View <> nil then
        tab.View.RefreshThemeColors();
      if tab.ScrollBar <> nil then
        tab.ScrollBar.Invalidate();
    end;
  end;
  Invalidate();
end;

procedure TConsoleSamaWindow.MenuScrollUp(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.ScrollPage(1);
end;

procedure TConsoleSamaWindow.MenuScrollDown(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.ScrollPage(-1);
end;

procedure TConsoleSamaWindow.MenuScrollEnd(Sender: TObject);
var
  tab: TConsoleTab;
begin
  tab := ActiveTab();
  if tab <> nil then tab.View.ScrollToEnd();
end;

procedure TConsoleSamaWindow.MenuAbout(Sender: TObject);
begin
  TFtMessageDialog.ShowInfo('About Samarinda Console',
    'A terminal built with ftpas',
    'Samarinda Console is a terminal console built on the Floria Toolkit ' +
    'Pascal binding (ftpas), with its window chrome modelled in FTML and ' +
    'embedded into the executable.');
end;

end.
