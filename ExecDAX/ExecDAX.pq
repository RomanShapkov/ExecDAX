// This file contains your Data Connector logic
section ExecDAX;

redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";
token_uri = "https://login.windows.net/common/oauth2/token";
authorize_uri = "https://login.windows.net/common/oauth2/authorize";
logout_uri = "https://login.microsoftonline.com/logout.srf";
resourceUri = "https://analysis.windows.net/powerbi/api";


windowWidth = 720;
windowHeight = 1024;

[DataSource.Kind="ExecDAX", Publish="ExecDAX.Publish"]

shared ExecDAX.NavTableNested = () as table =>
    let
        objects = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            {
                {"PowerBIService", "PowerBIServiceFunc", CreateNavTable("ExecuteQueries"), "Table", "Table", "false"}
            }
        ),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

CreateNavTable = (tbname) as table => 
    let
        objects =[
             ExecuteQueries = #table(
                    {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
                    {
                        {"ExecuteQueries","ExecuteQueries", ExecDAX.ExecuteQueries, "function", "function", "true"}
                    }
                )

            ],
 
        Table = Record.Field(objects, tbname),
        NavTable = Table.ToNavigationTable(Table, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

ExecDAX.ExecuteQueries = Value.ReplaceType(ExecDAX.ExecuteQueriesImpl, ExecDAX.ExecuteQueriesType);

ExecDAX.ExecuteQueriesType = 
    type function (  
                     dataset_id as (type text meta [
                        Documentation.FieldCaption = "dataset_id",
                        Documentation.SampleValues = {"08809f32-0b14-4fd9-a6b8-5716f3f39630"}
                        ]),
                     dax as (type text meta [
                        Documentation.FieldCaption = "DAX", 
                        Documentation.SampleValues = {"EVALUATE ROW(""test"", 1)"""},
                        Formatting.IsMultiLine = true,
                        Formatting.IsCode = true
                     ]),
                     includenulls as (type logical meta [
                        Documentation.FieldCaption = "includenulls",
                        Formatting.IsMultiLine = true,
                        Formatting.IsCode = true
                        ])
                   )
        as function meta [
            Documentation.Name = "ExecuteQueries",
            Documentation.LongDescription = "Returns DAX result from dataset."
    ];

ExecDAX.ExecuteQueriesImpl = (dataset_id as text, dax as text, includenulls as logical) =>
    let
        url = "https://api.powerbi.com/v1.0/myorg/",
        endpoint = "datasets/" &dataset_id& "/executeQueries",
        token = Extension.CurrentCredential()[access_token],
        headers = [
            #"Content-Type" = "application/json", 
            #"Authorization" = "Bearer " &token
            ],
        content =  
            Json.FromValue(
                [ 
                    queries = { [query = dax] },
                    serializerSettings = [includeNulls = includenulls]
                ]
            ),
        responce = Json.Document(
                        Web.Contents( url, 
                            [RelativePath = endpoint,
                             Content = content, 
                             Headers  = headers, 
                             ManualCredentials = true]
                             )
                   ),
        lstrec = responce[results]{0}[tables]{0}[rows],
        table = toTable(lstrec)
    in
        table;

// Data Source Kind description
ExecDAX = [
TestConnection = (dataSourcePath) => {"ExecDAX.NavTableNested"},
    Authentication = [
       Aad =  [
            AuthorizationUri = authorize_uri,
            Resource = resourceUri
          ]            
    ],
    Label = Extension.LoadString("DataSourceLabel") 
];


// Data Source UI publishing description
ExecDAX.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = ExecDAX.Icons,
    SourceTypeImage = ExecDAX.Icons
];

ExecDAX.Icons = [
    Icon16 = { Extension.Contents("ExecDAX16.png"), Extension.Contents("ExecDAX20.png"), Extension.Contents("ExecDAX24.png"), Extension.Contents("ExecDAX32.png") },
    Icon32 = { Extension.Contents("ExecDAX32.png"), Extension.Contents("ExecDAX40.png"), Extension.Contents("ExecDAX48.png"), Extension.Contents("ExecDAX64.png") }
];

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;


toTable = (lstrec as list, optional index as number) as table =>
    let
        fieldnames = 
            let
                toprows = if index is null then lstrec else List.FirstN(lstrec, index),
                listfields = List.Transform(toprows, Record.FieldNames),
                namesdistinct = List.Union(listfields)
            in
                namesdistinct,
        tbl = Table.FromRecords(lstrec, fieldnames, MissingField.UseNull)
    in
        tbl;