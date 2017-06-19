# CDSGrid
ClientDataSetGrid for Delphi

ClientDatasetGrid supports creating indices on the fly by clicking on the column of a grid. You can add columns by using Shift and Click, and switch any column to ascending or descending by clicking on it again. It demonstrates some of the features of the DataSnap ClientDataset, but it is a reasonably light component that descends from TDBGrid, so everything you do in TDBGrid should be supported as well. You can also save the column configuration.

Latest version notes:

- Support for VisualCLX
- Support for Delphi versions up to 2007
- rewrote the arrow drawing routine to be more configurable and included the index order information
- implemented SetIndexIndicators
- added TitleSort, ArrowShade, ArrowHighlight, ArrowColor
- added ConfigureColumns & persistence for the columns with ConfigFile property
- Adopted a suggestion from Ruud Bijvank for making sure the drawn arrow is not drawn over the title of the column.