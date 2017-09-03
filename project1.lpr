program project1;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, VTXEdit, VTXConst, VTXColorBox, VTXAttrBox, VTXCharBox, VTXPreviewBox,
  VTXSupport, Graphics, VTXEncDetect, UnicodeHelper, VTXFonts
  { you can add units after this };

{$R *.res}

begin
  Application.Title:='VTXEdit';
  RequireDerivedFormResource:=True;
  Application.Initialize;
  Application.CreateForm(TfMain, fMain);
  Application.CreateForm(TfFonts, fFonts);
  Application.Run;
end.

