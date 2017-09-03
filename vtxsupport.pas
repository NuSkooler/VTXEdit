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

unit VTXSupport;

{$mode objfpc}{$H+}

interface

uses
  UnicodeHelper,
  Classes, Forms, SysUtils, ExtCtrls, VTXConst, BGRABitmap, BGRABitmapTypes, Windows, Graphics;

function GetGlyphOff(codepoint : integer; table : PByte; size : integer) : integer;
procedure GetGlyphBmp(var bmp : TBGRABitmap; base : pbyte; off : integer; attr : Uint32; blink : boolean);
function Between(val, lo, hi : integer) : boolean; inline;
function Between(val, lo, hi : char) : boolean; inline;
function HasBits(val, mask : UInt32) : boolean; inline;
function GetBits(val, mask : UInt32; shift : integer = 0) : UInt32; inline;
procedure SetBits(var val : UInt32; mask, bits : UInt32; shift : integer = 0); inline;
procedure SetBit(var val : UInt32; mask : UInt32; bit : boolean);
procedure SetBit(var val : longint; mask : longint; bit : boolean);
procedure Swap(var val1, val2 : integer); inline;
procedure Swap(var val1, val2 : UInt32); inline;
function Brighten(color : TColor; factor: real): TColor;
procedure DrawBitmapTiled(const bmp:TBitmap; cnv: TCanvas; dest:TRect);
function DrawTextCentered(cnv: TCanvas; const r: TRect; s: unicodeString): Integer;
function DrawTextRight(cnv: TCanvas; const r: TRect; s: unicodeString): Integer;
procedure DrawLine(cnv : TCanvas; clr : TBGRAPixel; x1, y1, x2, y2 : integer);
procedure DrawRectangle3D(cnv: TCanvas; x1, y1, x2, y2 : integer; raised:boolean);
procedure DrawRectangle3D(cnv: TCanvas; rect : TRect; raised:boolean);
procedure DrawRectangle(cnv: TCanvas; x1, y1, x2, y2 : integer; clr : TColor);
procedure DrawRectangle(cnv: TCanvas; rect : TRect; clr : TColor);
procedure DrawRectangleButton(cnv: TCanvas; x1, y1, x2, y2 : integer; down : boolean);
procedure DrawRectangleButton(cnv: TCanvas; rect : TRect; down : boolean);
procedure LineCalcInit(x0, y0, x1, y1 : integer);
function LineCalcNext(var xo, yo : integer) : boolean;
function QuadToStr(q : TQuad) : unicodestring;
function StrToQuad(str : unicodestring) : TQuad;
procedure SetFormQuad(f : TForm; q : TQuad);
function GetFormQuad(f : TForm) : TQuad;
function CharsToStr(src : array of char; len : integer) : unicodestring;
function isInteger(str : unicodestring) : boolean;

// downstates in tag of tpaintbox buttons
procedure SetDown(pb : TPaintBox; val : boolean); inline;
function GetDown(pb : TPaintBox) : boolean; inline;
function GetIgnore(pb : TPaintBox) : boolean; inline;

// tool moving
procedure movetools(h : hwnd; x, y : integer);

var
  Version : string;

  textureUp, textureDown,			// 24x24 button images (up / down)
  textureBlotch,								// overlay for color palette entry
	iconsNormal, iconsGrayed, iconsHilite, iconsDown,	// button icons
  captionCloseUp,
  captionCloseDown,
  captionAutoRollupUp,
  captionAutoRollupDown,
  textureRuler : TBGRABitmap;
  Ctrl3D : array [0..4] of TBGRAPixel;  // 0=dark/2=mid/4=light

  UIBackground : integer = 4;
  UIText : integer = 15;
  UICaption : integer = 5;
  UICaptionText : integer = 15;

  // various settings
  PageType : 								integer;	// from cbPageType  PAGETYPE_
  ColorScheme :							integer;	// from cbColorScheme COLORSCHEME_

  bmpPage : TBGRABitmap;	// copy of page.
  PageZoom : 								double;			// 1.0 = 100%
  XScale : 									double;			// horizontal stretch. 1.0 = 100%
  CellWidth, CellHeight : 	integer;		// pixels
  CellWidthZ, CellHeightZ : integer;		// adjusted by PageZoom

  KeyBinds : array of TKeyBinds;

implementation

{*****************************************************************************}

{ Support Functions }

// get offset of codepoint of glyph in UVGA16. return 0 if not found
// called like GetGlyphOff(9673, @UVGA16, sizeof(UVGA16));
function GetGlyphOff(codepoint : integer; table : PByte; size : integer) : integer;
var
  rec, min, max : integer;
  key, off : integer;
  recs : integer;
begin
  recs := size div 18;

  // do binary search for codepoint in UVGA16
  min := 0;
  max := recs;
	repeat
    if max < min then
    begin
      // not found! return 0 (the undef char)
      off := 0;
      break;
    end;

    rec := (max + min) >> 1;
    off := rec * 18;
		key := (table[off] << 8) or table[off + 1];

    if key = codepoint then
    	// got a match. exit with off
      break;

    if key < codepoint then
      min := rec + 1
    else if key > codepoint then
      max := rec - 1;

  until key = codepoint;
  result := off + 2;
end;

// return new rendered glyph - does not render blink or double height
procedure GetGlyphBmp(
  var bmp : TBGRABitmap;
	base : pbyte;					// base address of glyph table
  off : integer;				// offset into glyph table points to 8x16
  attr : Uint32;				// standard cell attributes
  blink : boolean 			// if on, conceal text.
  );
var
  x, y : integer;
  b : byte;
  ptr : pbyte;
  bptr : ^TBGRAPixel;
  fg, bg, sc : TBGRAPixel;
  italics, bold, shadow : boolean;
  underline, strike, dstrike : boolean;
  disp : integer;
  adj : integer;
  i, dl : integer;
  s : pbgrapixel;
  fi, bi : integer;
begin
  ptr := @base[off];

	italics := 		HasBits(attr, A_CELL_ITALICS);
  bold :=  			HasBits(attr, A_CELL_BOLD);
  shadow :=  		HasBits(attr, A_CELL_SHADOW);
  underline :=	HasBits(attr, A_CELL_UNDERLINE);
	strike :=			HasBits(attr, A_CELL_STRIKETHROUGH);
	dstrike :=  	HasBits(attr, A_CELL_DOUBLESTRIKE);
	disp := 			GetBits(attr, A_CELL_DISPLAY_MASK);

  // dont' swap bold bit if BBS or CTerm and colors between 8-15
  fi := GetBits(attr, A_CELL_FG_MASK);
  bi := GetBits(attr, A_CELL_BG_MASK, 8);
  if HasBits(attr, A_CELL_REVERSE) then
  begin
	  if ColorScheme = COLORSCHEME_BBS then
    begin
      i := fi and $08;
      fi := fi and $07;
      bi := bi or i;
	  end;
    fg := ANSIColor[bi];
    bg := ANSIColor[fi];
  end
  else
  begin
    fg := ANSIColor[fi];
    bg := ANSIColor[bi];
  end;

  if HasBits(attr, A_CELL_FAINT) then
		fg := Brighten(fg, -0.33);

  if shadow then
  	sc := Brighten(bg, -0.33);

  // draw background.
  bmp.FillRect(0,0,8,16,bg);
  if not blink and (disp <> A_CELL_DISPLAY_CONCEAL) then
  begin
		for y := 0 to 15 do
  	begin
     	bptr := bmp.ScanLine[y];
	    b := ptr^;
  	  inc(ptr);

      if underline and (y = 15) then 							b := $ff;
      if strike    and (y = 7) then 							b := $ff;
      if dstrike   and ((y = 3) or (y = 11)) then b := $ff;

	  	for x := 0 to 7 do
	    begin
  	    if (b and $80) > 0 then
    	  begin
      	  adj := 0;
      		if italics and (y < 8) then
        		inc(adj);

	        if x + adj < 8 then
  	      begin
            if shadow and (y > 0) and (x + adj < 7) then
  						bptr[adj - 7] := sc;

			      bptr[adj] := fg;
  	  	    if bold and (x + adj < 7) then
    	  	  	bptr[adj + 1] := fg;

          end;
  	    end;
				inc(bptr);
      	b := (b and $7F) << 1;
	    end;
  	end;
    // adjust for double height
    if disp = A_CELL_DISPLAY_TOP then
    begin
      // stretch top half down over entire cell
      for i := 7 downto 0 do
      begin
        s := bmp.ScanLine[i];
        dl := i << 1;
        Move(s[0], bmp.ScanLine[dl    ][0], 32);
        Move(s[0], bmp.ScanLine[dl + 1][0], 32);
      end;
    end
    else if disp = A_CELL_DISPLAY_BOTTOM then
    begin
      // stretch bottom half up over entire cell
      for i := 8 to 15 do
      begin
        s := bmp.ScanLine[i];
        dl := (i - 8) << 1;
        Move(s[0], bmp.ScanLine[dl    ][0], 32);
        Move(s[0], bmp.ScanLine[dl + 1][0], 32);
      end;
    end;
  end;
end;

// is val between lo and hi?
function Between(val, lo, hi : integer) : boolean; inline;
begin
  result := ((val >= lo) and (val <= hi));
end;

// is val between lo and hi?
function Between(val, lo, hi : char) : boolean; inline;
begin
  result := ((ord(val) >= ord(lo)) and (ord(val) <= ord(hi)));
end;

// any bits set?
function HasBits(val, mask : UInt32) : boolean; inline;
begin
	result := ((val and mask) <> 0);
end;

// return bits under bitmask
function GetBits(val, mask : UInt32; shift : integer = 0) : UInt32; inline;
begin
  result := ((val and mask) >> shift);
end;

// set bits for bitmask
procedure SetBits(var val : UInt32; mask, bits : UInt32; shift : integer = 0); inline;
begin
	val := ((val and not mask) or ((bits << shift) and mask));
end;

procedure SetBit(var val : UInt32; mask : UInt32; bit : boolean);
var
  bitval : UInt32;
begin
	bitval := mask;
  if not bit then
  	bitval := 0;
  val := ((val and not mask) or bitval);
end;

procedure SetBit(var val : longint; mask : longint; bit : boolean);
var
  bitval : longint;
begin
	bitval := mask;
  if not bit then
  	bitval := 0;
  val := ((val and not mask) or bitval);
end;

procedure Swap(var val1, val2 : integer); inline;
var
  tmp : integer;
begin
	tmp := val1; val1 := val2; val2 := tmp;
end;

procedure Swap(var val1, val2 : UInt32); inline;
var
  tmp : UInt32;
begin
	tmp := val1; val1 := val2; val2 := tmp;
end;

// brighten / darken color
function Brighten(color : TColor; factor: real): TColor;

	function Norm(val : byte) : double; inline;
  begin
		result := val / 255.0;
  end;

  function Unnorm(val : double) : byte; inline;
  begin
    result := round(val * 255.0);
  end;

var
  r, g, b : double;
begin
	r := Norm(Red(color));
  g := Norm(Green(color));
  b := Norm(Blue(color));
  if factor < 0 then
  begin
    factor := factor + 1.0;
    r := r * factor;
    g := g * factor;
    b := b * factor;
  end
  else
  begin
    r := (1.0 - r) * factor + r;
    g := (1.0 - g) * factor + g;
    b := (1.0 - b) * factor + b;
  end;
  result := RGB(Unnorm(r), Unnorm(g), Unnorm(b));
end;

procedure DrawBitmapTiled(const bmp:TBitmap; cnv: TCanvas; dest:TRect);
var
  X, Y: Integer;
  dX, dY: Integer;
begin
  dX := bmp.Width;
  dY := bmp.Height;
  Y := dest.Top;
  while Y < dest.Bottom do
    begin
      X := dest.Left;
      while X < dest.Right do
        begin
          cnv.Draw(X, Y, bmp);
          Inc(X, dX);
        end;
      Inc(Y, dY);
    end;
end;

function DrawTextCentered(cnv: TCanvas; const r: TRect; s: unicodeString): Integer;
var
  DrawRect: TRect;
  DrawFlags: Cardinal;
  DrawParams: TDrawTextParams;
begin
  DrawRect := r;
  DrawFlags := DT_END_ELLIPSIS or DT_NOPREFIX or DT_WORDBREAK or
    DT_EDITCONTROL or DT_CENTER;
  DrawText(cnv.Handle, PChar(S), -1, DrawRect, DrawFlags or DT_CALCRECT);
  DrawRect.Right := R.Right;
  if DrawRect.Bottom < R.Bottom then
    OffsetRect(DrawRect, 0, (R.Bottom - DrawRect.Bottom) div 2)
  else
    DrawRect.Bottom := R.Bottom;
  ZeroMemory(@DrawParams, SizeOf(DrawParams));
  DrawParams.cbSize := SizeOf(DrawParams);
  DrawTextEx(cnv.Handle, PChar(S), -1, DrawRect, DrawFlags, @DrawParams);
  Result := DrawParams.uiLengthDrawn;
end;

function DrawTextRight(cnv: TCanvas; const r: TRect; s: unicodeString): Integer;
var
  DrawRect: TRect;
  DrawFlags: Cardinal;
  DrawParams: TDrawTextParams;
begin
  DrawRect := r;
  DrawFlags := DT_END_ELLIPSIS or DT_NOPREFIX or DT_WORDBREAK or
    DT_EDITCONTROL or DT_RIGHT;
  DrawText(cnv.Handle, PChar(S), -1, DrawRect, DrawFlags or DT_CALCRECT);
  DrawRect.Right := R.Right;
  if DrawRect.Bottom < R.Bottom then
    OffsetRect(DrawRect, 0, (R.Bottom - DrawRect.Bottom) div 2)
  else
    DrawRect.Bottom := R.Bottom;
  ZeroMemory(@DrawParams, SizeOf(DrawParams));
  DrawParams.cbSize := SizeOf(DrawParams);
  DrawTextEx(cnv.Handle, PChar(S), -1, DrawRect, DrawFlags, @DrawParams);
  Result := DrawParams.uiLengthDrawn;
end;

procedure DrawLine(cnv : TCanvas; clr : TBGRAPixel; x1, y1, x2, y2 : integer);
var
  tmp : TBGRABitmap;
  r : TRect;
begin
  r.Left := 0;
  r.Right := 0;
  r.Width := cnv.Width;
  r.Height := cnv.Height;
	tmp := TBGRABitmap.Create(cnv.Width, cnv.Height);
  BitBlt(tmp.Canvas.Handle, 0, 0, cnv.Width, cnv.Height, cnv.Handle, 0, 0, SRCCOPY);
  tmp.DrawLine(x1,y1,x2,y2,clr,true);
  tmp.Draw(cnv, 0, 0, true);
  tmp.free;
end;

procedure DrawRectangle3D(cnv: TCanvas; rect : TRect; raised:boolean);
begin
	DrawRectangle3D(cnv, rect.Left, rect.Top, rect.Right - 1, rect.Bottom - 1, raised);
end;

procedure DrawRectangle3D(cnv: TCanvas; x1, y1, x2, y2 : integer; raised:boolean);
var i1, i2 : integer;
begin
  if raised then
  begin
    i1 := 3;
    i2 := 1;
  end
  else
  begin
    i1 := 1;
    i2 := 3;
  end;
  DrawLine(cnv, Ctrl3D[i1], x2 - 1, y1, x1, y1);
  DrawLine(cnv, Ctrl3D[i1], x1, y1, x1, y2 -1);
  DrawLine(cnv, Ctrl3D[i2], x1 + 1, y2, x2, y2);
  DrawLine(cnv, Ctrl3D[i2], x2, y2, x2, y1 + 1);
end;

procedure DrawRectangleButton(cnv: TCanvas; rect : TRect; down : boolean);
begin
	DrawRectangleButton(cnv, rect.Left, rect.Top, rect.Right - 1, rect.Bottom - 1, down);
end;

procedure DrawRectangleButton(cnv: TCanvas; x1, y1, x2, y2 : integer; down : boolean);
begin
  if down then
  begin
    cnv.Pen.Color := clBlack;
    cnv.Line(x2, y1, x1, y1);
    cnv.Line(x1, y1, x1, y2);
    cnv.Line(x1, y2, x2, y2);
    cnv.Line(x2, y2, x2, y1);

    inc(x1); inc(y1);
    dec(x2); dec(y2);

    DrawLine(cnv, Ctrl3D[1], x2, y1, x1, y1); //  _
    DrawLine(cnv, Ctrl3D[1], x1, y1, x1, y2);  // |
    DrawLine(cnv, Ctrl3D[0], x1, y2, x2, y2); //
    DrawLine(cnv, Ctrl3D[0], x2, y2, x2, y1); //     _|
  end
	else
  begin
    DrawLine(cnv, Ctrl3D[4], x2 - 1, y1, x1, y1);
    DrawLine(cnv, Ctrl3D[4], x1, y1, x1, y2 -1);
    DrawLine(cnv, Ctrl3D[0], x1 + 1, y2, x2, y2);
    DrawLine(cnv, Ctrl3D[0], x2, y2, x2, y1 + 1);

    inc(x1); inc(y1);
    dec(x2); dec(y2);

    DrawLine(cnv, Ctrl3D[4], x2 - 1, y1, x1, y1);
    DrawLine(cnv, Ctrl3D[4], x1, y1, x1, y2 -1);
    DrawLine(cnv, Ctrl3D[0], x1 + 1, y2, x2, y2);
    DrawLine(cnv, Ctrl3D[0], x2, y2, x2, y1 + 1);
  end;
end;

procedure DrawRectangle(cnv: TCanvas; rect : TRect; clr : TColor);
begin
	DrawRectangle(cnv, rect.Left, rect.Top, rect.Right - 1, rect.Bottom - 1, clr);
end;

procedure DrawRectangle(cnv: TCanvas; x1, y1, x2, y2 : integer; clr : TColor);
begin
  cnv.Pen.Color := clr;
  cnv.Line(x2, y1, x1, y1);
  cnv.Line(x1, y1, x1, y2);
  cnv.Line(x1, y2, x2, y2);
  cnv.Line(x2, y2, x2, y1);
end;

procedure SetDown(pb : TPaintBox; val : boolean); inline;
var v : longint;
begin
  v := pb.Tag;
  SetBit(v, PBB_DOWN, val);
	pb.Tag := v;
  pb.Invalidate;
end;

function GetDown(pb : TPaintBox) : boolean; inline;
begin
 	result := ((pb.Tag and PBB_DOWN) > 0);
end;

function GetIgnore(pb : TPaintBox) : boolean; inline;
begin
 	result := ((pb.Tag and PBB_IGNORE) > 0);
end;


// http://members.chello.at/~easyfilter/bresenham.html

// line plotting vars
var
	calcX0, calcY0, calcX1, calcY1 : integer;
	calcDX, calcDY, calcSX, calcSY : integer;
	calcErr : integer;

// initialize line plotting calculator
procedure LineCalcInit(x0, y0, x1, y1 : integer);
begin
	calcX0 := x0;						calcY0 := y0;
  calcX1 := x1;						calcY1 := y1;
  calcDX := abs(x1 - x0);	calcDY := abs(y1 - y0);
	if x0 < x1 then calcSX := 1 else calcSX := -1;
	if y0 < y1 then calcSY := 1 else calcSY := -1;
  if calcDX > calcDY then
  	calcErr := calcDX div 2
  else
	  calcErr := (-calcDY) div 2;
end;

// get next point
function LineCalcNext(var xo, yo : integer) : boolean;
var
  e2 : integer;
begin
  result := ((calcX0 = calcX1) and (calcY0 = calcY1));
	if not result then
  begin
		e2 := calcErr;
    if e2 > -calcDX then
    begin
      calcErr -= calcDY;
			calcX0 += calcSX;
    end;
    if e2 < calcDY then
    begin
      calcErr += calcDX;
      calcY0 += calcSY;
    end;
    result := ((calcX0 = calcX1) and (calcY0 = calcY1));
  end;
  xo := calcX0;
  yo := calcY0;
end;

function QuadToStr(q : TQuad) : unicodestring;
begin
  result := format('%d,%d %d,%d', [ q.v0, q.v1, q.v2, q.v3]);
end;

function isInteger(str : unicodestring) : boolean;
var
  i : integer;
begin
  for i := 1 to str.length do
  	if not between(str[i], '0', '9') then
    	exit(false);
  result := true;
end;

function StrToQuad(str : unicodestring) : TQuad;
var
  l : integer;
  vals : TUnicodeStringArray;
begin
  result.v0 := 64;
  result.v1 := 64;
  result.v2 := 64;
  result.v3 := 64;
	vals := str.Split([',',' ']);
  l := length(vals);
  if (l >= 1) and isInteger(vals[0]) then result.v0 := strtoint(vals[0]);
  if (l >= 2) and isInteger(vals[1]) then result.v1 := strtoint(vals[1]);
  if (l >= 3) and isInteger(vals[2]) then result.v2 := strtoint(vals[2]);
  if (l >= 4) and isInteger(vals[3]) then result.v3 := strtoint(vals[3]);
  setlength(vals,0);
end;

procedure SetFormQuad(f : TForm; q : TQuad);
begin
  if q.v0 < 0 then q.v0 := 0;
  if q.v1 < 0 then q.v1 := 0;
  if q.v0 > Screen.Width then q.v0 := 0;
  if q.v1 > Screen.Height then q.v1 := 0;

	f.Left := q.v0;
  f.Top := q.v1;
  if q.v2 > 0 then
  begin
	  f.Width := q.v2;
  	f.Height := q.v3;
  end;
end;

function GetFormQuad(f : TForm) : TQuad;
begin
  result.v0 := f.RestoredLeft;
  result.v1 := f.RestoredTop;
  result.v2 := f.RestoredWidth;
  result.v3 := f.RestoredHeight;
end;

function CharsToStr(src : array of char; len : integer) : unicodestring;
var
  i : integer;
begin
  result := '';
  len := length(src);
  for i := 0 to len - 1 do
	  result += src[i];
end;


// move this window + all snapped
procedure movetools(h : hwnd; x, y : integer);
begin
 	SetWindowPos(h, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE or SWP_NOACTIVATE);
end;

end.
