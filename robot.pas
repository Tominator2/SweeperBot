{
 To Do:
 ------
 - Implement a simple rule system so that each rule only has to be
   specified once for each of the four possible orientations.
    - Note that some rules are wall aware.
    - see some initial rule definitions in the 'const' section below and
      the start of 2 rule checking procedures:
      TryGenericRules() & TryWallRules()

 - Could read the font for number of mines.

 - Instead of random clicking could look for best odds.

}

unit robot;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, StdCtrls, Math;

type
  TForm1 = class(TForm)
    SweepButton: TButton;
    Memo1: TMemo;
    ImageTiles: TImage;
    ImageSmileys: TImage;
    procedure SweepButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
    procedure LeftClick(Pt: TPoint) ;
    procedure RightClick(Pt: TPoint);
    procedure MiddleClick(Pt: TPoint);
    procedure MouseButtonClick(Pt: TPoint;
                                  ButtonDown, ButtonUp: Integer);
    procedure TakeScreenshot(Win: HWND; Bmp:TBitmap);
    function  TileToNumber(i: Integer): Integer;
    function  GetFirstTilePos(img: TBitmap): TPoint;
    function  PixelsMatch(a, b: RGBTriple): Bool;
    function  GridRefToPixels(GridX,GridY: Integer): Tpoint;
    function  GridRefToScreen(GridX,GridY: Integer): Tpoint;
    function  RecogniseTile(img: TBitmap; GridX, GridY: Integer): Integer;
    procedure RescanBoard(Win: HWND; img: TBitmap);
    function  CountAdjacent(GridX, GridY, TileType: Integer): Integer;
    function  CheckPosition(GridX, GridY, TileType: Integer): Integer;
    procedure SetFlags(GridX,GridY: Integer);
    function  RecogniseSmiley(img: TBitmap): Integer;
    function  GetSmileyPos(img: TBitmap): TPoint;
    procedure TryGenericRules();
    procedure TryWallRules();
  public
    { Public declarations }
  end;

var
  Form1: TForm1;
  TileWidth, TileHeight: Integer;
  CheckWidth, CheckHeight: Integer; // how many pixels need to match
  NoOfTiles: Integer;               // no of tiles in image strip
  Tiles:   array[0..15] of TBitmap; // bitmaps of the game tiles
  Smileys: array[0..4] of TBitmap;  // bitmaps of the smiley tiles
  FirstTileOffset: TPoint;          // top left corner of first tile
  SmileyOffset:    TPoint;          // top left corner of the smiley
  SmileyWidth, SmileyHeight: Integer;
  GameDimensions: TPoint;           // no. of game tiles wide and hide
  Grid: array of array of Integer;
  Clicked: array of array of Bool;
  WinMine: hWnd;                    // Window Handle for Minesweeper
  BoardChanged: Bool;               // Flag indicates changes to board
  InPlay: Bool;                     // Is a game in progress?

const
  // Define some rules where...
  //   - R|M|L correspond to a covered (but un-flagged) tile that should
  //     be given the respecive mouse-click if the rule macthes
  //   - ? corresponds to a blank (empty) or numbered square
  //   - C corresponds to a covered square
  GenericRules: Array[0..0,0..2,0..2] of Char =
    ((('?','?','?'),
      ('1','2','1'),
      ('C','L','C')));

  // N.B. The following rules assume the wall is on the left in the original
  //      orientation.
  WallRules:    Array[0..1,0..2,0..2] of Char =
    ((
      ('?','?','?'),
      ('1','1','1'),
      ('C','C','L') // clear it
      ),
      (('?','?','?'),
      ('1','2','?'),
      ('C','C','R') // flag it
      ));

type
  PRGBTripleArray = ^TRGBTripleArray;
  TRGBTripleArray = array[0..4095] of TRGBTriple;

implementation

{$R *.dfm}


//
// Left mouse button click (clears square)
//
procedure TForm1.LeftClick(Pt: TPoint) ;
begin
  MouseButtonClick(Pt, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP);
end;


//
// Right mouse button click (consecutive clicks toggle:
// flag -> ? -> blank -> flag)
//
procedure TForm1.RightClick(Pt: TPoint) ;
begin
  MouseButtonClick(Pt, MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP);
end;


//
// Middle mouse button click (clears surrounding squares if all the mines in
// adjacent squares are flagged correctly)
//
procedure TForm1.MiddleClick(Pt: TPoint) ;
begin
  MouseButtonClick(Pt, MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP);
end;


//
// ButtonUp and ButtonDown are the Windows mouse_event API parameters for the
// desired button
//
procedure TForm1.MouseButtonClick(Pt: TPoint;
                                  ButtonDown, ButtonUp: Integer);
begin
    Application.ProcessMessages;
    BringWindowToTop(WinMine);

    // convert pixels to screen dimensions in Mickeys
    Pt.x := Round(Pt.x * (65535 / Screen.Width)) ;
    Pt.y := Round(Pt.y * (65535 / Screen.Height)) ;

    {Simulate the mouse move}
    Mouse_Event(MOUSEEVENTF_ABSOLUTE or
                MOUSEEVENTF_MOVE,
                Pt.x, Pt.y, 0, 0);
    {Simulate this mouse button down}
    Mouse_Event(MOUSEEVENTF_ABSOLUTE or
                ButtonDown,
                Pt.x, Pt.y, 0, 0);
    sleep(100); // slight delay so click is visible on UI
    {Simulate this mouse button up}
    Mouse_Event(MOUSEEVENTF_ABSOLUTE or
                ButtonUp,
                Pt.x, Pt.y, 0, 0);
    sleep(100);  // Give UI time to respond?  
end;


//
//  Start sweeping when the "Sweep" button is clicked.
//
procedure TForm1.SweepButtonClick(Sender: TObject);
var
  //WinMine: hWnd;
  WindowPos: TRect;        // top left corner of the Minsweeper window
  Screenshot: TBitmap;
  //Filename: String;
  GridPosition: TPoint;
  i, j: Integer;
  noFlags, noCovered: Integer;
  Smiley: Integer;
begin

  // Find the Minesweeper window by Title text and Classname
  WinMine := FindWindow('Minesweeper','Minesweeper');

  // Check that Minsweeper is running!
  if WinMine = 0 then
    begin
      MessageDlg('Start Minesweeper and then click ''Sweep'' again.',
                 mtWarning, [mbOK], 0);
      Exit;
    end;

  // Restore the window if minimised
  ShowWindow(WinMine,SW_RESTORE);

  //Get the window position
  Windows.GetWindowRect(WinMine, WindowPos);
  Memo1.Lines.Append('Minsweeper window is at (' + IntToStr(WindowPos.Left)
                     + ',' + IntToStr(WindowPos.Top) +')');

  // grab a screenshot
  Screenshot := TBitmap.Create;
  Screenshot.PixelFormat := pf24bit;
  TakeScreenshot(WinMine, Screenshot);

  // Write the screenshot to a file
  {
  FileName := 'Screenshot_' +
              FormatDateTime('mm-dd-yyyy-hhnnss', Now());
  Screenshot.SaveToFile(Format('C:\Temp\%s.bmp', [FileName]));
  }

  // Find the location of the smiley
  Memo1.Lines.Append('Locating the smiley...');
  SmileyOffset := GetSmileyPos(Screenshot);
  Memo1.Lines.Append('...found smiley ' + IntToStr(RecogniseSmiley(Screenshot))
                     + ' at (' + IntToStr(SmileyOffset.X)
                     + ',' + IntToStr(SmileyOffset.Y) +')');

  Smiley := RecogniseSmiley(Screenshot);
  if (Smiley = 1) or (Smiley = 2) then      // won!
  begin
      // could send 'F2' to start a new game instead of
      // asking
      MessageDlg('Start a new game then click ''Sweep'' again.', mtWarning,
                 [mbOK], 0);
      Exit;
  end;

  // Find the location of the first tile
  Memo1.Lines.Append('Locating first tile...');
  FirstTileOffset := GetFirstTilePos(Screenshot);
  Memo1.Lines.Append('...found first tile at (' + IntToStr(FirstTileOffset.X)
                     + ',' + IntToStr(FirstTileOffset.Y) +')');

  // If there is no blank tile at position 0,0 then this causes
  // problems.  This behaviour could be changed later so that rather than
  // starting with a blank board the robot could be used to help out with an
  // existing game.
  if (FirstTileOffset.X < 0) or (FirstTileOffset.Y < 0) then
    begin
      MessageDlg('Start a new game of Minesweeper and then click ''Sweep'' again.',
                 mtWarning, [mbOK], 0);
      Exit;
    end;

  SweepButton.Enabled := False;
  SweepButton.Caption := 'Sweeping';

  // Find out how many tiles wide and high
  //
  // I originally though about using image matching for this but
  // realised that this approach would be simpler and faster!
  GameDimensions.X := Trunc((Screenshot.Width  - FirstTileOffset.X)/TileWidth);
  GameDimensions.Y := Trunc((Screenshot.Height - FirstTileOffset.Y)/TileHeight);
  Memo1.Lines.Append('Game grid is ' + IntToStr(GameDimensions.X)
                     + 'x' + IntToStr(GameDimensions.Y));

  // Initialise the board
  SetLength(Grid, GameDimensions.X, GameDimensions.Y);
  SetLength(Clicked, GameDimensions.X, GameDimensions.Y);

  InPlay := False;

  for j := 0 to GameDimensions.Y - 1 do
  begin
    for i := 0 to GameDimensions.X - 1 do
    begin
      Grid[i][j] := RecogniseTile(Screenshot, i, j);
      if Grid[i][j] <> 0 then
        InPlay := True;
      Clicked[i][j] := False;
    end;
  end;

  // Click a random tile to start (not along the edges)
  if not InPlay then
  begin
    GridPosition := Point(RandomRange(1,GameDimensions.X - 2),
                        RandomRange(1,GameDimensions.Y - 2));
    Memo1.Lines.Append('First click at ' + IntToStr(GridPosition.X)
                     + ',' + IntToStr(GridPosition.Y));
    LeftClick(GridRefToScreen(GridPosition.X, GridPosition.Y));
    Clicked[GridPosition.X][GridPosition.Y] := True;
  end;

  // First click is never a mine so no need to check for a win at this stage

  BoardChanged := True;

  // start solving!
  while BoardChanged do
  begin

    RescanBoard(WinMine, Screenshot);
    BoardChanged := False;  // reset board changes flag

    //Memo1.Lines.Append('Rescanned board and change flag reset...'); // debug

    // scan for numeric squares
    //
    // should do 2 passes...
    // 1) a first pass to set flags, then
    // 2) a second pass to middle click
    for j := 0 to GameDimensions.Y - 1 do
    begin
      for i := 0 to GameDimensions.X - 1 do
      begin
        if (Grid[i][j] >= 7) and (Grid[i][j] <= 14) and not
          Clicked[i][j] then // is it an unclicked number tile?
        begin
          noFlags := CountAdjacent(i, j, 1);
          // this ignores '?' squares for now
          noCovered := noFlags + CountAdjacent(i, j, 0);
          { // debugging
          Memo1.Lines.Append('(' + IntToStr(i) + ',' +
                             IntToStr(j) + ') = ' +
                             IntToStr(TileToNumber(Grid[i][j])) + ', F:' + IntToStr(noFlags)
                             + ', []:' + IntToStr(noCovered));
          }

          // The no. of covered adjacent spaces is equal to the number
          // so they should all be set to flags.
          if noCovered = TileToNumber(Grid[i][j]) then
          begin
            SetFlags(i,j);
            BoardChanged := True;
          end
          else if noFlags = TileToNumber(Grid[i][j]) then
          begin
            Memo1.Lines.Append('Middle click at ' + IntToStr(i)
                     + ',' + IntToStr(j));
            MiddleClick(GridRefToScreen(i,j));
            Clicked[i][j] := True;
            BoardChanged := True; // although some middle clicks won't chage things
          end; // if
        end; // if
      end; // for
    end; // for

  // Try any rules here...
  Memo1.Lines.Append('Checking rules...');
  TryGenericRules();
  TryWallRules();

  // check for win/lose
  Smiley := RecogniseSmiley(Screenshot);
  if Smiley = 1 then      // won!
  begin
    Memo1.Lines.Append('Hooray!');
    Break;
  end
  else if Smiley = 2 then // lost
  begin
    Memo1.Lines.Append('Sorry!');
    Memo1.Lines.Append('');
    Break;
  end;

  //if BoardChanged then
  //  Memo1.Lines.Append('...board flagged as changed');  // debug

  end; // while

  SweepButton.Enabled := True;
  SweepButton.Caption := 'Sweep';

end;


//
// Capture a screenshot of the board
//
// Code adapted from:
// http://stackoverflow.com/questions/661250/how-to-take-a-screenshot-of-the-active-window-in-delphi
//
Procedure TForm1.TakeScreenshot(Win: HWND; Bmp: TBitmap);
const
  FullWindow = False; // Set to false if you only want the client area.
var
  //Win: HWND;
  DC: HDC;
  //Bmp: TBitmap;
  //FileName: string;
  WinRect: TRect;
  Width, Height: Integer;
begin
  //Form1.Hide;
  try
    //Win := GetForegroundWindow;

    BringWindowToTop(Win);
    Application.ProcessMessages;
    Sleep(100);

    if FullWindow then
      begin
        GetWindowRect(Win, WinRect);
        DC := GetWindowDC(Win);
      end
    else
      begin
        //Windows.GetClientRect(Win, WinRect);
        Windows.GetWindowRect(Win, WinRect);
        DC := GetWindowDC(Win);
      end;
    try
      Width := WinRect.Right - WinRect.Left;
      Height := WinRect.Bottom - WinRect.Top;

      //Bmp := TBitmap.Create;
      try
        Bmp.Height := Height;
        Bmp.Width := Width;
        BitBlt(Bmp.Canvas.Handle, 0, 0, Width, Height, DC, 0, 0, SRCCOPY);
       finally
        //Bmp.Free;
      end;
    finally
      ReleaseDC(Win, DC);
    end;
  finally
    //Form1.Show;
  end;
end;


//
//   Initialise the application
//
procedure TForm1.FormCreate(Sender: TObject);
var
  i: Integer;
  FromRect, ToRect: Trect;
begin

  // Actually no need to cut these up - could simply use scanlines and offsets
  // from the original bitmap arrays!
  //
  // cut each of the tiles from the vertical strip
  // and populate an array with them
  TileWidth  := 16;
  TileHeight := 16;
  NoOfTiles  := 16; // in the intial tile image strip

  ToRect := Rect(0,0,16,16);

  for i := 0 to NoOfTiles - 1 do
  begin
    Tiles[i] := TBitmap.create;
    Tiles[i].PixelFormat := pf24bit;
    Tiles[i].Height := TileHeight;
    Tiles[i].Width  := TileWidth;

    FromRect := Rect(0,                        // left
                     (i * TileHeight) ,        // top
                     TileWidth,                // right
                     (TileHeight + (i * 16))); //bottom

    Tiles[i].Canvas.CopyRect(ToRect, ImageTiles.Canvas, FromRect);

    // Dump tiles to image files for checking
    //Tiles[i].SaveToFile('C:\Temp\t' + IntToStr(i) + '.bmp');
  end;

  // cut each of the tiles from the vertical strip
  // and populate an array with them
  SmileyWidth  := 24;
  SmileyHeight := 24;
  NoOfTiles  := 5; // in the intial tile image strip

  ToRect := Rect(0,0,24,24);

  for i := 0 to NoOfTiles - 1 do
  begin
    Smileys[i] := TBitmap.create;
    Smileys[i].PixelFormat := pf24bit; // must match the screenshot image!
    Smileys[i].Height := SmileyHeight;
    Smileys[i].Width  := SmileyWidth;

    FromRect := Rect(0,                 // left
                     (i*24) ,           // top
                     24,                // right
                     (24 + (i * 24)));  //bottom

    Smileys[i].Canvas.CopyRect(ToRect, ImageSmileys.Canvas, FromRect);

    // Dump smileys to image files for checking
    //Smileys[i].SaveToFile('C:\Temp\s' + IntToStr(i) + '.bmp');
  end;

  // How much of a tile do we need to scan to recognise it reliably?
  CheckWidth  := Trunc(TileWidth/2);
  CheckHeight := Trunc(TileHeight/2);

  FirstTileOffset := Point(-1,-1);
  SmileyOffset := Point(-1,-1);
  GameDimensions  := Point(0,0);

  Randomize;

  Memo1.Lines.Append('Run Minesweeper and click');
  Memo1.Lines.Append('on ''Sweep'' to start...');

end;


//
// Find the location of the smiley button
//
function TForm1.GetSmileyPos(img: TBitmap): TPoint;
var
  top, left, row, col: Integer;
  searchBounds: TRect;
  SmileLine, ImgLine: PRGBTripleArray;
  found: Bool;
  CommonSmileHeight: Integer;
begin
  // Smile[1] is an unclicked smiley image - 1..4 have the same top 7 rows.
  // This will search for the top left corner of a smiley image which is
  // common to all un-clicked smileys
  CommonSmileHeight := 7;

  result := Point(-1,-1);
  Assert(img.PixelFormat = Smileys[1].PixelFormat);

  // define a search area to look in for the top left pixel of the
  // first tile
  searchBounds := Rect(Point(Trunc(img.Width/2) - SmileyWidth, 60),
                       Point(Trunc(img.Width/2) + SmileyWidth, 90));

  // search for the tile!
  for top := searchBounds.Top to searchBounds.Bottom do
  begin

    for left := searchBounds.Left to searchBounds.Right do
    begin

      found := True; // reset flag

      // only need to compare the top of a smiley to recognise it
      for row := 0 to CommonSmileHeight do
      begin
        // get scanline from the smiley we are searching for
        SmileLine := Smileys[1].Scanline[row];

        // get scanlines from the image to be searched
        ImgLine := img.ScanLine[top + row];

        for col := 0 to Trunc(SmileyWidth/2) do
        begin
          // search for first image match by comparing pixels
          //Memo1.Lines.Append(IntToStr(left) + ',' + IntToStr(top) + ':' +
          //                   IntToStr(col) + ',' + IntToStr(row));

          if not PixelsMatch(SmileLine[col],ImgLine[left + col]) then
            begin
              found := False;
              break; // break loop
            end;

        end; // end for

        // scanning along this row failed so stop and start next pixel over
        if not found then
          break;

      end; // end for

      if found then
        begin
          result := Point(left,top);  // match found!
          exit;
        end;
    end;
  end;

end;


//
// Return the numerical value of the tile at this index
//
function TForm1.TileToNumber(i: Integer): Integer;
begin
  if (i < 8) or (i > 15) then
    result := -1
  else
    result := 15 - i;
end;


//
// Search for any of the tiles to locate the first position in the
// grid
//
function TForm1.GetFirstTilePos(img: TBitmap): TPoint;
var
  top, left, row, col: Integer;
  searchBounds: TRect;
  TileLine, ImgLine: PRGBTripleArray;
  found: Bool;
  i: Integer;
begin
  // Tiles[0] is the image for an unclicked tile

  result := Point(-1,-1);
  Assert(img.PixelFormat = Tiles[0].PixelFormat);

  // define a search area to look in for the top left pixel of the
  // first tile
  searchBounds := Rect(Point(10,95),Point(40,120));

  // search for the tile!
  for top := searchBounds.Top to searchBounds.Bottom do
  begin

    for left := searchBounds.Left to searchBounds.Right do
    begin

      // currently we try all possible tiles for a match although
      // really only 0..3 and uncovered are useful/possible because
      // we check for win/loss already via the smiley
      for i := 0 to 15 do  // check all possible tiles
      begin

        found := True; // reset flag

        // only need to compare part of a tile to recognise it
        for row := 0 to CheckHeight do
        begin
          // get scanline from the tile we are searching for
          TileLine := Tiles[i].Scanline[row];

          // get scanlines from the image to be searched
          ImgLine := img.ScanLine[top + row];

          for col := 0 to CheckWidth do
          begin
            // search for first image match by comparing pixels
            //Memo1.Lines.Append(IntToStr(left) + ',' + IntToStr(top) + ':'
            //                   + IntToStr(col) + ',' + IntToStr(row));

            if not PixelsMatch(TileLine[col],ImgLine[left + col]) then
            begin
              found := False;
              break; // break loop
            end;

          end; // end for col

          // scanning along this row failed so stop and start next pixel over
          if not found then
            break;

        end; // end for row

        if found then
          begin
            result := Point(left,top);  // match found!
            exit;
          end;

      end; // end for i
    end; // end left
  end; // end top

end;


//
// Returns true if the two pixels have the same RGB colour values
//
function TForm1.PixelsMatch(a, b: RGBTriple): Bool;
begin
  if (a.rgbtRed = b.rgbtRed) and (a.rgbtGreen = b.rgbtGreen) and
     (a.rgbtBlue = b.rgbtBlue) then
    result := True
  else
    result := False;
end;


//
// Returns the top left corner of the tile at these grid co-ords
//
function TForm1.GridRefToPixels(GridX,GridY: Integer): Tpoint;
begin
  // include CheckWidth and CheckHeight so we click in the approx.
  // center fo the tile
  result.X := FirstTileOffset.X + (GridX * TileWidth);
  result.Y := FirstTileOffset.Y + (GridY * TileHeight);
end;


//
// Returns the screen co-ords of the center of the tile at these
// grid co-ords
//
function TForm1.GridRefToScreen(GridX,GridY: Integer): Tpoint;
var
  WindowPos: TRect;
begin
  // include CheckWidth and CheckHeight so we click in the approx.
  // center fo the tile
  Windows.GetWindowRect(WinMine, WindowPos);
  result.X := WindowPos.Left + FirstTileOffset.X + (GridX * TileWidth)  + CheckWidth;
  result.Y := WindowPos.Top  + FirstTileOffset.Y + (GridY * TileHeight) + CheckHeight;
end;


//
//
//
function TForm1.RecogniseTile(img: TBitmap; GridX, GridY: Integer): Integer;
var
  row, col: Integer;
  i: Integer;
  found: bool;
  offset: TPoint;
  TileLine, ImgLine: PRGBTripleArray;
begin

  offset := GridRefToPixels(GridX, GridY);

  result := -1;

  // do we need to check for all of these or just  0, 1, 7..15?
  for i := 0 to 15 do
  begin

    //Memo1.Lines.Append('Checking tile ' + IntToStr(i) + '@' +
    //  IntToStr(offset.X) + ',' + IntToStr(offset.Y));

    found := True; // reset flag

    // only need to compare part of a tile to recognise it
    for row := 0 to CheckHeight do
    begin
        // get scanline from the tile we are searching for
        TileLine := Tiles[i].Scanline[row];

        // get scanlines from the image to be searched
        ImgLine := img.ScanLine[offset.Y + row];

        for col := 0 to CheckWidth do
        begin
          // search for first image match by comparing pixels
          //Memo1.Lines.Append('    ' +
          //                   IntToStr(col) + ',' + IntToStr(row));

          if not PixelsMatch(TileLine[col],ImgLine[offset.X + col]) then
            begin
              found := False;
              break; // break loop
            end;

        end; // end for

        // scanning along this row failed so stop and start next pixel over
        if not found then
          break;

      end; // end for

      if found then
        begin
          result := i;  // match found!
          exit;
        end;
  end;

end;


//
//  Check to see if this tile matches any of the smiley tiles
//
function TForm1.RecogniseSmiley(img: TBitmap): Integer;
var
  row, col: Integer;
  i: Integer;
  found: bool;
  SmileLine, ImgLine: PRGBTripleArray;
begin

  result := -1;

  for i := 0 to 4 do
  begin

    //Memo1.Lines.Append('Checking tile ' + IntToStr(i) + '@' +
    //  IntToStr(SmileyOffset.X) + ',' + IntToStr(offset.Y));

    found := True; // reset flag

    // only need to compare part of a smiley to recognise it
    for row := 0 to Trunc(SmileyHeight/2) do
    begin
        // get scanline from the smiley we are searching for
        SmileLine := Smileys[i].Scanline[row];

        // get scanlines from the image to be searched
        ImgLine := img.ScanLine[SmileyOffset.Y + row];

        for col := 0 to Trunc(SmileyWidth/2) do
        begin
          // search for first image match by comparing pixels
          //Memo1.Lines.Append('    ' +
          //                   IntToStr(col) + ',' + IntToStr(row));

          if not PixelsMatch(SmileLine[col],ImgLine[SmileyOffset.X + col]) then
            begin
              found := False;
              break; // break loop
            end;

        end; // end for

        // scanning along this row failed so stop and start next pixel over
        if not found then
          break;

      end; // end for

      if found then
        begin
          result := i;  // match found!
          exit;
        end;
  end;

end;


//
// Re-scan the board but ignore already exposed empty or numeric tiles
//
procedure TForm1.RescanBoard(Win: HWND; img: TBitmap);
var
  i,j: Integer;
begin
  TakeScreenshot(Win, img);

    for j := 0 to GameDimensions.Y - 1 do
    begin
      for i := 0 to GameDimensions.X - 1 do
      begin
        if (Grid[i][j] < 7) then // only re-scan non-numeric tiles
          Grid[i][j] := RecogniseTile(img, i, j);
      end;
    end;

end;


//
// Returns the count of how many tiles of the specified type are adjacent to
// this grid reference
//
function TForm1.CountAdjacent(GridX, GridY, TileType: Integer): Integer;
var
 x,y: Integer;
 count: Integer;
begin

  count := 0;

  for y := GridY - 1 to GridY + 1 do
  begin
    for x := GridX - 1 to GridX + 1 do
    begin
        if not ((x = GridX) and (y = GridY)) then
          count := count + CheckPosition(x, y, TileType);
    end;
  end;

  result := count;

end;


//
// Returns true if the tile at this grid reference is of the specified type
//
function TForm1.CheckPosition(GridX, GridY, TileType: Integer): Integer;
begin
  if (GridX >= 0) and (GridY >= 0) and
     (GridX < GameDimensions.X) and (GridY < GameDimensions.Y) then
    begin
      if Grid[GridX][GridY] = TileType then
        result := 1
      else
        result := 0;
    end
  else
    result := 0;
end;


//
//  Set any flags in the 8 squares surrounding this location
//
procedure TForm1.SetFlags(GridX,GridY: Integer);
var
  x,y: Integer;
begin
  for y := GridY - 1 to GridY + 1 do
  begin
    for x := GridX - 1 to GridX + 1 do
    begin
      if (x >= 0) and (y >= 0) and
     (x < GameDimensions.X) and (y < GameDimensions.Y) then
      begin
        if (Grid[x][y] = 0) and (not Clicked[x][y]) then
        begin
          Memo1.Lines.Append('Set flag at ' + IntToStr(x)
                     + ',' + IntToStr(y));
          RightClick(GridRefToScreen(x,y));
          Clicked[x][y] := True;
        end;  // if
      end; // if
    end; // for x
  end; // for y
end;


//
// Try to find a match for a rule where...
//   - R|M|L correspond to a covered (but un-flagged) tile that should
//     be given the respecive mouse-click if the rule macthes
//   - ? corresponds to a blank or numbered square
//   - C corresponds to a covered square
//
procedure TForm1.TryGenericRules();
var
  rot, rule, x, y: Integer;
  matched: Bool;
  NumTile:   Set of 0..15;
  ClickTile: Set of 'C'..'R';
begin

  NumTile := [7..15]; // "numbered" tiles 8..0
  ClickTile := ['C','L','M','R'];

  // for each rule...
  for rule := 0 to 0 do
  begin

    // rotations & flips
    // Note that the matrix will be rotated and flipped again
    // so we can leave it in any state
    for rot := 0 to 3 do
    begin

      for y := 0 to GameDimensions.Y do
      begin

        for x:= 0 to GameDimensions.X do
        begin

          // look for a pattern match
          matched := True;

          // if found - apply the rule
          // look for an 'L', 'M' or 'R' and apply the click
          // to the corresponding square
          if matched then
          begin
            Memo1.Lines.Append('Match for rule ' + IntToStr(rule) +
              ' with rotation ' + IntToStr(rot) + ' at ' + IntTostr(x) +
              ',' + IntTostr(y));

            Exit;
          end; // if

        end; // for x
      end; // for y

      // rotate it and try again

    end; // for rot
  end; // for rule

end;


//
//  Try to find a match for rules that apply along walls
//
procedure TForm1.TryWallRules();
var
  x, y: Integer;
begin

end;


end.
