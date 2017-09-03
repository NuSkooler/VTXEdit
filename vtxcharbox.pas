{

BSD 2-Clause License

Copyright (c) 2017, Daniel Mecklenburg Jr. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

}

unit VTXCharBox;

{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, Classes, SysUtils, FileUtil, Forms, Controls, Graphics,
  Dialogs, StdCtrls, Spin, ExtCtrls, VTXConst, VTXSupport, Math, FGL,
  BGRABitmap, BGRABitmapTypes;

type

  { TfChar }

  TfChar = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    pbBottomResizer: TPaintBox;
    pbChars: TPaintBox;
    pbClose: TPaintBox;
    pbTopResizer: TPaintBox;
    pbTitleBar: TPaintBox;
    pCharPal: TPanel;
    ScrollBox1: TScrollBox;
    seCharacter: TSpinEdit;
    tbCodePage: TEdit;
    tbUnicode: TEdit;
    procedure FormResize(Sender: TObject);
    procedure ScrollToChar;
    procedure FormCreate(Sender: TObject);
    procedure BuildPalette;
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure iCloseClick(Sender: TObject);
    procedure pbBottomResizerMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbCloseClick(Sender: TObject);
    procedure pbClosePaint(Sender: TObject);
    procedure pbTitleBarMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbTitleBarPaint(Sender: TObject);
    procedure pCharPalPaint(Sender: TObject);
    procedure pbCharsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure pbCharsPaint(Sender: TObject);
    procedure seCharacterChange(Sender: TObject);
    procedure pbTopResizerMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    { private declarations }
  public
    { public declarations }
    SelectedChar : integer;
    procedure WndProc(var Msg:TMessage); override;
  end;

var
  Unicode : boolean;
  UseCodePage : TEncoding;		// codepage to use.
  fChar: TfChar;
  NumChars : integer;

implementation

{$R *.lfm}

{ TfChar }

const
  PALCOLS = 16;
  CELL_WIDTH = 21;
  CELL_HEIGHT = 40;

var
  bmp : TBGRABitmap = nil;

procedure TfChar.BuildPalette;
var
  rows : integer;
  i : integer;
  x, y : integer;
  off : integer;
  cell : TBGRABitmap;
  rect : TRect;
begin
  // build palette
  seCharacter.Enabled := false;
  cell := TBGRABitmap.Create(8,16);
  if (UseCodePage = encUTF8) or (UseCodePage = encUTF16) then
  begin
    NumChars := math.floor(length(UVGA16) / 18) - 1;
    seCharacter.MinValue := $0020;
    seCharacter.MaxValue := $FFFF;
    Unicode := true;
  end
  else
  begin
    NumChars := 256;
    seCharacter.MinValue := $0000;
    seCharacter.MaxValue := $00FF;
    Unicode := false;
  end;
  seCharacter.Enabled := true;

  rows := (NumChars - 1) div PALCOLS + 1;
  if bmp <> nil then
    bmp.Free;
  bmp := TBGRABitmap.Create(PALCOLS * CELL_WIDTH + 4, rows * CELL_HEIGHT + 4);
  bmp.FillRect(0,0,bmp.Width,bmp.Height,clBlack);

  for i := 0 to NumChars - 1 do
  begin

    if Unicode then
    	off := (i + 1) * 18 + 2
    else
      off := CPages[UseCodePage].QuickGlyph[i];

    y := i div PALCOLS;
    x := i - (y * PALCOLS);

    x := x * CELL_WIDTH + 2;
    y := y * CELL_HEIGHT + 2;

    // draw simple glyph in cell (8x16)
    GetGlyphBmp(cell, CPages[UseCodePage].GlyphTable, off, 15, false);

    rect.Left := 2 + x;
    rect.Top := 2 + y;
    rect.Width := 16;
    rect.Height := 32;

    bmp.FillRect(2 + x - 1, 2 + y - 1, 4 + x + 17, 2 + y + 33, clDkGray);
    cell.Draw(bmp.Canvas, rect);
  end;
  cell.Free;
  pbChars.Invalidate;
end;

procedure TfChar.FormDestroy(Sender: TObject);
begin
  if bmp <> nil then
	  bmp.Free;
end;

procedure TfChar.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  off, i : integer;
begin
  // get index of selected char
	if Unicode then
    // convert unicode to offset
  	i := (GetGlyphOff(
    	SelectedChar,
      CPages[UseCodePage].GlyphTable,
      CPages[UseCodePage].GlyphTableSize) - 2) div 18 - 1
  else
    i := SelectedChar;

  case Key of
		VK_UP:		i -= 16;
    VK_DOWN:	i += 16;
    VK_LEFT:	i -= 1;
    VK_RIGHT:	i += 1;
  end;

	if i < 0 then
  	i := 0;
  if unicode then
  begin
	  if i >= (UVGA16_COUNT - 1) then
  		i := (UVGA16_COUNT - 2);
  end
  else
  begin
  	if i >= 256 then
    	i := 255;
  end;

  seCharacter.Enabled := false;
  if Unicode then
  begin
    off := (i + 1) * 18;
    i := (UVGA16[off] << 8) or UVGA16[off+1];
    SelectedChar := i;
    seCharacter.value := i;
    tbUnicode.Text := IntToStr(i);
  end
  else
  begin
    SelectedChar := i;
    seCharacter.value := i;
// CODEPAGE
//    tbUnicode.Text := IntToStr(CP437[i]);
    tbUnicode.Text := IntToStr(CPages[UseCodePage].EncodingLUT[i]);
  end;
  seCharacter.Enabled := true;
  pbChars.Invalidate;
	SendMessage(TForm(Owner).Handle, WM_VTXEDIT, WA_MAIN_UPDATE, 0);
end;

procedure TfChar.ScrollToChar;
begin
  // scroll to selected char if off screen.
//  if (ScrollBox1.VertScrollBar.Position + 36) < y then
//		ScrollBox1.VertScrollBar.Position := y;
//  if ScrollBox1.VertScrollBar.Position > (y) then
//		ScrollBox1.VertScrollBar.Position := y;
end;

procedure TfChar.FormResize(Sender: TObject);
begin
  movetools(self.handle, Left, Top);
end;

procedure TfChar.pCharPalPaint(Sender: TObject);
var
  p : TPanel;
  cnv : TCanvas;
  r : TRect;
begin
  p := TPanel(Sender);
  cnv := p.Canvas;
  r := p.ClientRect;
  p.Font.Color := ANSIColor[UIText];
  cnv.Brush.Color := ANSIColor[UIBackground];
  cnv.FillRect(r);
//  DrawBitmapTiled(textureStone.Bitmap, cnv, r);
  DrawRectangle3D(cnv, r, true);
end;

procedure TfChar.pbCharsMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  off, i : integer;
begin
  // click to select
  y := (y - 4) div CELL_HEIGHT;
  x := (x - 4) div CELL_WIDTH;
  seCharacter.Enabled := false;
  if between(x, 0, 15) and (y >= 0) then
  begin
    i := y * PALCOLS + x;
    if Unicode then
    begin
      off := (i + 1) * 18;
      i := (UVGA16[off] << 8) or UVGA16[off+1];
      SelectedChar := i;
      seCharacter.value := i;
      tbUnicode.Text := IntToStr(i);
    end
    else
    begin
      SelectedChar := i;
      seCharacter.value := i;
// CODEPAGE
//      tbUnicode.Text := IntToStr(CP437[i]);
      tbUnicode.Text := IntToStr(CPages[UseCodePage].EncodingLUT[i]);
    end;
  end;
  seCharacter.Enabled := true;
  pbChars.Invalidate;
	SendMessage(TForm(Owner).Handle, WM_VTXEDIT, WA_MAIN_UPDATE, 0);
end;

procedure TfChar.pbCharsPaint(Sender: TObject);
var
  pb : TPaintBox;
  cnv : TCanvas;
  i, x, y : integer;

begin
  pb := TPaintBox(Sender);
  cnv := pb.Canvas;
  pb.Width := bmp.Width;
  pb.Height := bmp.Height;
  bmp.Draw(cnv, 0, 0);

  // hilight the selected char
	if Unicode then
    // convert unicode to offset
  	i := (GetGlyphOff(
    	SelectedChar,
      CPages[UseCodePage].GlyphTable,
      CPages[UseCodePage].GlyphTableSize) - 2) div 18 - 1
  else
    i := SelectedChar;

  y := i div PALCOLS;
  x := i - (y * PALCOLS);
  x := x * CELL_WIDTH + 4;
  y := y * CELL_HEIGHT + 2;

  cnv.Brush.Style := bsClear;
  cnv.Pen.Color := clRed;
  cnv.Pen.Width := 1;
  cnv.Rectangle(x, y, x + 20, y + 36);
end;

procedure TfChar.seCharacterChange(Sender: TObject);
begin
	if TSpinEdit(sender).enabled then
  begin
    if Unicode then
    else
    begin
      SelectedChar := seCharacter.Value;
      if Unicode then
      	tbUnicode.Text := IntToStr(SelectedChar)
  		else
// CODEPAGE
//  			tbUnicode.Text := IntToStr(CP437[SelectedChar]);
				tbUnicode.Text := IntToStr(CPages[UseCodePage].EncodingLUT[SelectedChar]);
    end;
    pbChars.Invalidate;
  	SendMessage(TForm(Owner).Handle, WM_VTXEDIT, WA_MAIN_UPDATE, 0);
  end;
end;

procedure TfChar.WndProc(var Msg:TMessage);
var
  i, thisi : integer;
  twi : TWINDOWINFO;
  pwp : PWINDOWPOS;
  bx, by : integer;
begin
	if Msg.msg = WM_VTXEDIT then
  begin
    case Msg.wParam of
      WA_CHAR_CODEPAGE:
        begin
          // rebuild from codepage change.
          UseCodePage := TEncoding(Msg.lParam);
          tbCodePage.Text := CPages[UseCodePage].Name;
          BuildPalette;
        end;

      WA_CHAR_SETVALS:
        begin
          // select a character
          SelectedChar := Msg.lParam;
          seCharacter.Enabled := false;
          seCharacter.Value := SelectedChar;
					if Unicode then
            tbUnicode.Text := IntToStr(SelectedChar)
					else
// CODEPAGE
          	tbUnicode.Text := IntToStr(CPages[UseCodePage].EncodingLUT[SelectedChar]);
//            tbUnicode.Text := IntToStr(CP437[SelectedChar]);
          seCharacter.Enabled := true;
          pbChars.Invalidate;
        end;
    end;
  end
  else
    inherited WndProc(Msg);
end;

procedure TfChar.FormCreate(Sender: TObject);
begin
end;


// Caption Bar

procedure TfChar.iCloseClick(Sender: TObject);
begin
	Hide;
end;

procedure TfChar.pbCloseClick(Sender: TObject);
begin
  Hide;
end;

procedure TfChar.pbClosePaint(Sender: TObject);
var
  pb : TPaintBox;
  cnv : TCanvas;
  r : TRect;
begin
  pb := TPaintBox(Sender);
  cnv := pb.Canvas;
  r := pb.ClientRect;
	captionCloseUp.Draw(cnv, r);
end;

// resize grabber
procedure TfChar.pbTopResizerMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ReleaseCapture;
  SendMessage(Handle, WM_NCLBUTTONDOWN, HTTOP, 0);
end;

// resize grabber
procedure TfChar.pbBottomResizerMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ReleaseCapture;
  SendMessage(Handle, WM_NCLBUTTONDOWN, HTBOTTOM, 0);
end;

procedure TfChar.pbTitleBarPaint(Sender: TObject);
var
  pb : TPaintBox;
  cnv : TCanvas;
  r : TRect;
begin
  pb := TPaintBox(Sender);
  cnv := pb.Canvas;
  r := pb.ClientRect;

  cnv.Brush.Color := ANSIColor[UICaption];
  cnv.FillRect(r);
//  DrawBitmapTiled(textureStone.Bitmap, cnv, r);
  DrawRectangle3D(cnv, r, true);
  cnv.Brush.Style:=bsClear;
  cnv.Font.Color := ANSIColor[UICaptionText];
  cnv.Font.Size := -11;
  cnv.Font.Style := [ fsBold ];
  cnv.TextOut(3,1,'Character Palette');
end;


procedure TfChar.pbTitleBarMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ReleaseCapture;
  SendMessage(Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
end;

// end toobar move routines

end.
