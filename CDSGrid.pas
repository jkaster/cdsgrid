unit CDSGrid;
{
  Copyright (c) 1999 - 2017 John F. Kaster
  Written by John F. Kaster and Anders Ohlsson

  Anders Ohlsson
    - created the TClientDataSetGrid component
    - wrote the arrow drawing for the columns

  John Kaster
    - implemented SortGrid
    - overrode the default TitleClick() procedure
    - overrode the default MouseDown() procedure to intercept the
      ShiftState setting when the mouse is clicked
    - rewrote the arrow drawing routine to be more configurable and
      included the index order information
    - implemented SetIndexIndicators
    - added TitleSort, ArrowShade, ArrowHighlight, ArrowColor
    - added ConfigureColumns & persistence for the columns with ConfigFile
      property
    - Adopted a suggestion from Ruud Bijvank for making sure the drawn arrow
      is not drawn over the title of the column.

  Usage:
  - Click on the column to change the listing order to that column only.
  - Click on an indexed column to reverse the listing order of that column
    only.
  - Shift-Click on a non-indexed column to ADD it to the listing order.
  - Shift-Click on an indexed column to cycle its listing order through
    descending, and off.

  Description:

  This component is a descendant of TDBGrid, and can be used with any TDataset
  descendant.  If the dataset used in the grid is a TClientDataSet or
  descendant, the "sorting" feature of the grid can be enabled to work
  automatically with any dataset.

  History:
    Sep 21 2000
    - fixed bug with dgIndicator being off causing the arrow to be drawn
      in the wrong column
    - changed the column click logic when multiple columns are in use to
      toggle a column as ascending, descending, off, ascending, descending,
      off. This only is used with Shift-Clicking.

}
{ TODO : Publish ShowArrows, Change TitleSort to "EnableTitleSort?" }
interface

{$if declared(QCDSGrid)}
{$define CLX}
{$ifend}

uses
{$ifdef CLX}
  SysUtils, Classes, Types, QControls, QGraphics,
  QGrids, DB, QDBGrids, fGridCols;
{$else}
  SysUtils, Classes, Types, Controls, Graphics,
  Grids, DB, DBGrids, fGridCols, Messages;
{$endif}

const
  atNone = 0; // No arrow to be drawn

type
  TArrowType = integer;

  TClientDataSetGrid = class(TDBGrid)
  private
    { Private declarations }
    FArrow : TList; // array of TArrowType;
    FArrowHighlight: TColor;
    FArrowShade: TColor;
    FTitleSort: boolean;
    FConfigFile: string;
    FLastShiftState : TShiftState;
    procedure SetArrow(Index : Integer; Value : TArrowType);
    function GetArrow(Index : Integer) : TArrowType;
    procedure SetConfigFile(const Value: string);
    procedure SetTitleSort(const Value: boolean);
  protected
    { Protected declarations }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure DrawCell(ACol, ARow: Longint; ARect: TRect; AState: TGridDrawState); override;
    procedure TitleClick(Column : TColumn); override;
    procedure WndProc(var Msg: TMessage); override;
  public
    { Public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Arrow[Index : Integer] : TArrowType read GetArrow write SetArrow;
    procedure GetAvailableColumns(ColumnList : TStrings; const VisibleOnly : boolean = True);
    procedure GetActiveColumns(ColumnList : TStrings);
    procedure SaveSettings(FileName : string = '');
    procedure LoadSettings(FileName : string = '');
    procedure SetIndexIndicators(AIndexName : string);
    procedure ClearIndexIndicators;
    function FindFieldColumn(Value : TField) : integer;
    procedure ConfigureColumns; virtual;
    function ColOffset: integer;
  published
    { Published declarations }
    property ConfigFile : string read FConfigFile write SetConfigFile;
    property ArrowShade : TColor read FArrowShade write FArrowShade
      default clBtnShadow;
    property ArrowHighlight : TColor read FArrowHighlight write FArrowHighlight
      default clWhite;
    property TitleSort : boolean read FTitleSort write SetTitleSort default True;
  end;

procedure SortGrid(Column : TColumn; const Shifted : boolean;
  const IndexName : string = 'SortGrid');
procedure ListFieldNames(List : TStrings; const FieldNames : string);
procedure ListIntersect(OldList, NewList : TStrings);
function SemiText(const List : TStrings) : string;
function FindFieldColumn(const Grid: TDBGrid; const Field: TField): integer;

implementation

uses DBClient, typinfo;

type
  TCDSAccess = class(TCustomClientDataset);

function FindFieldColumn(const Grid: TDBGrid; const Field: TField): integer;
var
  i : integer;
begin
  for i := 0 to Grid.Columns.Count - 1 do
    if Grid.Columns[ i ].Field = Field then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
end; { FindFieldColumn() }

function GetIndexDefs(cds: TDataSet): TIndexDefs;
begin
  Result := nil;
  //! Result := IProviderSupport(cds).PSGetIndexDefs([]);

  { TODO : Remove this when the above line always works }
  if not Assigned(Result) and (cds is TCustomClientDataset) then
    Result := TCDSAccess(cds).IndexDefs;
end;

function GetIndexDef(cds : TDataSet; const sName : string) : TIndexDef;
var
  Indices : TIndexDefs;
  Index : integer;
begin
  Result := nil;

  Indices := GetIndexDefs(cds);
  if Assigned(Indices) then
  begin
    Index := Indices.IndexOf(sName);
    if Index <> -1 then
      Result := Indices[Index]
    else
      Result := nil;
  end;
end; { GetIndexDef() }

procedure ListFieldNames(List : TStrings; const FieldNames : string);
var
  Pos: Integer;
begin
  Pos := 1;
  while Pos <= Length(FieldNames) do
    List.Add(ExtractFieldName(FieldNames, Pos));
end; { ListFieldNames() }

procedure ListIntersect(OldList, NewList : TStrings);
var
  Pos: Integer;
begin
  Pos := OldList.Count - 1;
  while Pos > -1 do
  begin
    if NewList.IndexOf(OldList[Pos]) = -1 then
      OldList.Delete(Pos);
    Dec(Pos);
  end; { while }
end; { ListIntersect() }

function SemiText(const List : TStrings) : string;
var
  i, j : integer;
begin
  j := List.Count - 1;
  if j >= 0 then
  begin
    Result := List[0];
    for i := 1 to j do
      Result := Result + ';' + List[i];
  end
  else
    Result := '';

end; { SemiText() }

function GetCDSAndIndexInfo(DataSource : TDataSource;
  var IdxDef : TIndexDef;
  var AllFields, DescFields : string;
  AIndexName : string = '') : TCustomClientDataSet;
begin
  Result := nil;
  IdxDef := nil;
  AllFields := '';
  DescFields := '';
  if Assigned(DataSource) and Assigned(DataSource.DataSet)
    and (DataSource.DataSet is TCustomClientDataSet) then
  begin
    Result := TCustomClientDataset(DataSource.DataSet);
    if AIndexName = '' then
      //! Why do I still need this?
      AIndexName := TCDSAccess(Result).IndexName;

    if AIndexName <> '' then
      IdxDef := GetIndexDef(Result, AIndexName);

    if Assigned(IdxDef) then
    begin
//      IdxDef := GetIndexDef(Result, AIndexName);
      AllFields := IdxDef.Fields;
      DescFields := IdxDef.DescFields;
      if (DescFields = '') and (ixDescending in IdxDef.Options) then
        DescFields := AllFields;
    end
    else
    begin
      //! I shouldn't need this
      AllFields := TCDSAccess(Result).IndexFieldNames;
      DescFields := '';
    end;
  end;
end;

procedure SortGrid(Column : TColumn; const Shifted : boolean;
  const IndexName : string = 'SortGrid');
var
  cds : TCustomClientDataset;

  procedure UpdateIndexDefs;
  begin
    { TODO : Use the commented out line, or TCustomClientDataset when public }
    //! IProviderSupport(cds).PSGetIndexDefs.Update;
    TCDSAccess(cds).IndexDefs.Update;
  end;

  procedure SetIndexField(const FieldNames : string; Shifty : boolean;
    ColIndex : integer);
  var
    ccDB : TClientDataSetGrid;
    i, j,
    AscField : integer;
    DescList,
    FieldList,
    NewList : TStringList;
    IndexDef : TIndexDef;
    FieldName,
    AllFields,
    DescFields,
    SaveAll,
    SaveDesc : string;
    SaveOpts,
    IdxOpts   : TIndexOptions;
  begin
    FieldList := nil;
    NewList := nil;
    DescList := TStringList.Create;
    if Column.Grid is TClientDataSetGrid then
      ccDB := TClientDataSetGrid(Column.Grid)
    else
      ccDB := nil;
    try
      FieldList := TStringList.Create;
      NewList := TStringList.Create;
      ListFieldNames(NewList, FieldNames);
      cds := GetCDSAndIndexInfo(Column.Grid.DataSource, IndexDef, AllFields,
        DescFields, IndexName);
      IdxOpts := [];
      ListFieldNames(FieldList, AllFields);
      ListFieldNames(DescList, DescFields);
      if Shifty then { Additive index }
      begin
        if Assigned(IndexDef) then
          IdxOpts  := IndexDef.Options;
      end
      else { Only retain fields currently in index }
      begin
        ListIntersect(FieldList, NewList);
        ListIntersect(DescList, NewList);
      end;

      if Assigned(IndexDef) then
      begin
        SaveAll := IndexDef.Fields;
        SaveDesc := IndexDef.DescFields;
        SaveOpts := IndexDef.Options;
        if IsPublishedProp(cds, 'IndexName') then
          SetStrProp(cds, 'IndexName', '');
        cds.DeleteIndex(IndexName);
        UpdateIndexDefs;
      end { Index exists }
      else
      begin
        SaveAll := '';
        SaveDesc := '';
        SaveOpts := [];
      end;

      Include(IdxOpts, ixCaseInsensitive);
      for j := NewList.Count - 1 downto 0 do
      begin

        FieldName := NewList[j];

        AscField := FieldList.IndexOf(FieldName);
        if AscField <> -1 then
        begin
          i := DescList.IndexOf(FieldName);
          if i <> -1 then
          begin
            DescList.Delete(i);
            if Shifty then
              FieldList.Delete(AscField);
          end
          else
            DescList.Add(FieldName);
        end { Field already exists in index }
        else
          FieldList.Add(FieldName);

      end; { Processing each new field }

      DescFields := SemiText(DescList);
      AllFields := SemiText(FieldList);
      try
        cds.AddIndex(IndexName, AllFields, IdxOpts, DescFields);
        UpdateIndexDefs;
        if Assigned(ccDB) then
          ccDB.SetIndexIndicators(IndexName);
        TCDSAccess(cds).IndexName := IndexName;
      except
        on E: Exception do
        begin
          if Assigned(ccDB) then
          begin
            if SaveAll <> '' then
            begin
              cds.AddIndex(IndexName, SaveAll, SaveOpts, SaveDesc);
              UpdateIndexDefs;
              ccDB.SetIndexIndicators(IndexName);
            end
            else
              ccDB.ClearIndexIndicators;
          end;
          Raise E;
        end;
      end;
    finally
      FreeAndNil(NewList);
      FreeAndNil(DescList);
      FreeAndNil(FieldList);
    end; { finally }
  end; { AddFieldName() }

begin

  if Assigned(Column) and Assigned(Column.Field)
    and Assigned(Column.Field.DataSet)
    and (Column.Field.Dataset is TCustomClientDataset) then
  begin
    case Column.Field.FieldKind of
    fkData, fkInternalCalc : SetIndexField(Column.FieldName, Shifted,
      Column.Index);
    fkLookup : SetIndexField(Column.Field.KeyFields, Shifted, Column.Index);
    // fkCalculated, fkAggregate : // can't do anything with these
    end;
  end; { Can do something with it }
end; { SortGrid() }

{ TClientDataSetGrid }

constructor TClientDataSetGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  //SetLength(FArrow, 0);
  FArrow := TList.Create;
  FTitleSort := True;
  FArrowShade := clBtnShadow;
  FArrowHighlight := clWhite;
  FLastShiftState := [];
end;

destructor TClientDataSetGrid.Destroy;
begin
  //SetLength(FArrow,0);
  if Assigned(FArrow) then FreeAndNil(FArrow);
  if FConfigFile <> '' then
    SaveSettings(FConfigFile);
  inherited Destroy;
end;

procedure TClientDataSetGrid.SetArrow(Index : Integer; Value : TArrowType);
begin
  FArrow[Index] := Pointer(Value);
end;

function TClientDataSetGrid.GetArrow(Index : Integer) : TArrowType;
begin
  Result := Integer(FArrow[Index]);
end;

procedure TClientDataSetGrid.DrawCell(ACol, ARow: Longint; ARect: TRect;
  AState: TGridDrawState);
const
  SFontName = 'Small Fonts'; { TODO : Is this available for Kylix? }
  FontSize = 5;
  TriWidth = 12;
  TriHeight = 16;
  TriOffset = 4;
  TextHOffset = 2;
  TextVOffset = 2;

var
  OldPenColor : TColor;
  AFont : TFont;
  Col : TColumn;
  TextPoint,
  LeftPoint,
  MidPoint,
  RightPoint : TPoint;

  procedure Triangulate(Direction : integer);
  begin
    LeftPoint.x := ARect.Right - TriWidth - TriOffset;
    RightPoint.x := ARect.Right - TriOffset;
    MidPoint.x := ARect.Right - (TriWidth div 2) - TriOffset;
    TextPoint.x := MidPoint.x - TextHOffset;
    if Direction < 1 then // Draw arrow pointing down
    begin
      LeftPoint.y := ARect.Top + TriOffset;
      MidPoint.y := ARect.Bottom - TriOffset;
      TextPoint.y := LeftPoint.y; // + TextVOffset;
    end
    else
    begin
      LeftPoint.y := ARect.Bottom - TriOffset;
      MidPoint.y := ARect.Top + TriOffset;
      TextPoint.y := MidPoint.y + TextVOffset;
    end;
    RightPoint.y := LeftPoint.y;
  end;

begin
  inherited;
  if (not FTitleSort) then Exit;
  if (gdFixed in AState) and ((FArrow.Count > 0)
    and (Arrow[ACol] <> atNone)) then
    with Canvas do
    begin
      OldPenColor := Pen.Color;
      Triangulate(Arrow[ACol]);
      if ACol - ColOffset < 0 then
        exit;
      Col := Columns[ACol - ColOffset];
      { Resize column if necessary }
      if (ARect.Right - ARect.Left)
        < (Canvas.TextWidth(Col.Title.Caption) + TriWidth + TriOffset) then
        ColWidths[ACol] := (Canvas.TextWidth(Col.Title.Caption)
          + TriWidth + TriOffset);

      AFont := TFont.Create;
      try
        AFont.Assign(Canvas.Font);
        Canvas.Font.Name := SFontName;
        Canvas.Font.Size := FontSize;
        Canvas.TextOut(TextPoint.x, TextPoint.y, IntToStr(Abs(Arrow[ACol])));
        Canvas.Font.Assign(AFont);
      finally
        AFont.Free;
      end;
      Canvas.MoveTo(LeftPoint.x,LeftPoint.y);
      Canvas.Pen.Color := FArrowShade;
      Canvas.LineTo(MidPoint.x,MidPoint.y);
      Canvas.Pen.Color := FArrowHighlight;
      Canvas.LineTo(RightPoint.x,RightPoint.y);
      Canvas.LineTo(LeftPoint.x,LeftPoint.y);
      Canvas.Pen.Color := OldPenColor;
    end;
end;

procedure TClientDataSetGrid.TitleClick(Column: TColumn);
begin
  // Have to use OnTitleClick instead of FOnTitleClick because
  // FOnTitleClick is private and not visible to this component
  if FTitleSort then SortGrid(Column, ssShift in FLastShiftState);
  if Assigned(OnTitleClick) then OnTitleClick(Column);
end;

procedure TClientDataSetGrid.SaveSettings(FileName : string);
begin
  if FileName = '' then
    FileName := FConfigFile;
  if (FileName <> '') and Assigned(Columns) then
    Columns.SaveToFile(FileName)
  else
    DeleteFile(FileName);
end;

procedure TClientDataSetGrid.LoadSettings(FileName : string);
begin
  if FileName = '' then
    FileName := FConfigFile;
  if FileExists(FileName) then
    Columns.LoadFromFile(FileName)
  else
    Columns.RestoreDefaults;
end;

procedure TClientDataSetGrid.SetConfigFile(const Value: string);
begin
  FConfigFile := Value;
  if FileExists(Value) then
    LoadSettings(Value);
end;

procedure TClientDataSetGrid.GetActiveColumns(ColumnList: TStrings);
var
  i : integer;
begin
  ColumnList.Clear;
  for i := 0 to Columns.Count - 1 do
  begin
    ColumnList.Add(Columns[i].Field.DisplayName);
    ColumnList.Objects[i] := Columns[i];
  end; { for each column }
end;

procedure TClientDataSetGrid.GetAvailableColumns(ColumnList: TStrings;
  const VisibleOnly: boolean);
var
  i : integer;
begin
  ColumnList.Clear;
  if Assigned(DataSource) and Assigned(DataSource.DataSet) then
    with DataSource.DataSet do
      for i := 0 to Fields.Count - 1 do
        if (not VisibleOnly) or (Fields[i].Visible) then
        begin
          ColumnList.Add(Columns[i].Field.DisplayName);
          ColumnList.Objects[i] := Fields[i];
        end;
end;

function TClientDataSetGrid.FindFieldColumn(Value: TField): integer;
begin
  Result := CDSGrid.FindFieldColumn(Self, Value);
end;

procedure TClientDataSetGrid.ConfigureColumns;
begin
  GridColumnToggler(Self);
end;

procedure TClientDataSetGrid.MouseDown(Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  FLastShiftState := Shift;
end;

procedure TClientDataSetGrid.SetIndexIndicators(AIndexName: string);
var
  i,
  ColOff,
  ColIndex : integer;
  CDS : TCustomClientDataset;
  IdxDef : TIndexDef;
  AllFields,
  FieldName,
  DescFields : string;
  FieldList : TStrings;
begin
  ClearIndexIndicators;
  CDS := GetCDSAndIndexInfo(DataSource, IdxDef, AllFields, DescFields,
    AIndexName);
  if Assigned(CDS) then
  begin
    FieldList := TStringList.Create;
    try
      ListFieldNames(FieldList, AllFields);
      ColOff := ColOffset;

      for i := 0 to FieldList.Count - 1 do
      begin
        FieldName := FieldList[i];
        ColIndex := FindFieldColumn(CDS.FieldByName(FieldName));
        if (Pos(FieldName, DescFields) > 0) then
          Arrow[ColIndex + ColOff] := - (i + 1)
        else
          Arrow[ColIndex + ColOff] := i + 1;
      end; { for }

    finally
      FieldList.Free;
    end;
  end;
end;

procedure TClientDataSetGrid.SetTitleSort(const Value: boolean);
begin
  if FTitleSort <> Value then
  begin
    FTitleSort := Value;
    if not (csLoading in ComponentState) then
    begin
      if (FTitleSort) then
        SetIndexIndicators('')
      else
        ClearIndexIndicators;
    end;
    Invalidate;
  end;
end;

procedure TClientDataSetGrid.ClearIndexIndicators;
var
  ColOff,
  ColIndex : integer;
begin
  ColOff := ColOffset;
  if FArrow.Count <> Columns.Count + ColOff then
    FArrow.Count := Columns.Count + ColOff;
  for ColIndex := 0 to Columns.Count + ColOff - 1 do
    Arrow[ColIndex] := atNone; // Clear all arrows
end;

function TClientDataSetGrid.ColOffset: integer;
begin
  if dgIndicator in Options then
    Result := 1
  else
    Result := 0;
end;

procedure TClientDataSetGrid.WndProc(var Msg: TMessage);
begin
  case (Msg.Msg) of
    WM_MOUSEWHEEL:
      Msg.Result := 0;
    else
      inherited;
  end;
end;

initialization
{$ifdef CLX}
  GroupDescendentsWith(TClientDataSetGrid, QControls.TControl);
{$else}
  GroupDescendentsWith(TClientDataSetGrid, Controls.TControl);
{$endif}

end.
