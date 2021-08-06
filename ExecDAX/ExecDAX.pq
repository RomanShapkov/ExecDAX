// This file contains your Data Connector logic
section ExecDAX;

redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";
token_uri = "https://login.windows.net/common/oauth2/token";
authorize_uri = "https://login.windows.net/common/oauth2/authorize";
logout_uri = "https://login.microsoftonline.com/logout.srf";
resourceUri = "https://analysis.windows.net/powerbi/api";


access_token = Extension.CurrentCredential()[access_token];

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
                        {"ExecuteQueries","ExecuteQueries", ExecDAX.ExecuteQueries, "function", "function", "true"},
                        {"GetGroups", "GetGroups", ExecDAX.GetGroups, "function", "function", "true"}
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
        endpoint = "datasets/" &dataset_id& "/executeQueries",
        content = Json.FromValue(
                [ 
                    queries = { [query = dax] },
                    serializerSettings = [includeNulls = includenulls]
                ]
           ),
        responce = GetData(endpoint, null, content),
        table = toTable(responce)
    in
        table;


ExecDAX.GetGroups = () =>
    let
        endpoint = "groups",
        responce = GetData(endpoint)
    in
        responce;


GetData = (endpoint as text, optional params as record, optional content) =>
    let
        url = "https://api.powerbi.com/v1.0/myorg/",
        headers = [#"Content-Type" = "application/json", #"Authorization" = "Bearer " &access_token],
        options = 
            let 
                required = [RelativePath = endpoint, Headers = headers, ManualCredentials = true],
                addparams = add_rec(required, "Query", params),
                addcontent = add_rec(addparams, "Content", content)
            in 
                addcontent,
        source = Json.Document(Web.Contents(url, options))
    in
        source;

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


toTable = (responce as record, optional index as number) as table =>
    let
        lstrec = responce[results]{0}[tables]{0}[rows],
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


add_rec = (rec as record, recname as text, value as any) =>
    if value is null then rec else Record.AddField(rec, recname, value);