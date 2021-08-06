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

        NavTable = (tb as table) => Table.ToNavigationTable(tb, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf"),

        lv1 = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            
            {
                {"ExecuteQueries", "ExecuteQueries", ExecDAX.ExecuteQueries, "function", "function", "true"},
                {"GetReportList", "GetReportList", ExecDAX.GetReportNameList, "function", "function", "true"}
            }   
        ),

        lv0 = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            
            {
                {"PowerBI Service", "PowerBIService", NavTable(lv1), "Folder", "Folder", false}
            }   
        )
    in
        NavTable(lv0);


ExecDAX.ExecuteQueries = Value.ReplaceType(ExecDAX.ExecuteQueriesImpl, ExecDAX.ExecuteQueriesType);

ExecDAX.ExecuteQueriesType = 
    type function (  
                     dataset_id as (type text meta [
                        Documentation.FieldCaption = "dataset_id",
                        Documentation.AllowedValues = ExecDAX.GetReportNameList(),
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
                        Documentation.AllowedValues = {false,true},
                        Documentation.SampleValues = {}
                        ])
                   )
        as function meta [
            Documentation.Name = "ExecuteQueries",
            Documentation.LongDescription = "Returns DAX result from dataset."
    ];

ExecDAX.ExecuteQueriesImpl = (report as text, dax as text, includenulls as logical) =>
    let
        dataset_id = parse_dataset_id(report),
        endpoint = "datasets/" &dataset_id& "/executeQueries",
        content = Json.FromValue(
                [ 
                    queries = { [query = dax] },
                    serializerSettings = [includeNulls = includenulls]
                ]
           ),
        responce = GetData(endpoint, null, content),
        lstrec = responce[results]{0}[tables]{0}[rows],
        table = toTable(lstrec)
    in
        table;


ExecDAX.GetGroups = () =>
    let
        endpoint = "groups",
        responce = GetData(endpoint),
        groups = responce[value]
    in
        groups;

ExecDAX.GetReportsInGroup = (groupId, optional groupname as text) =>
    let
        endpoint = "groups/" &groupId& "/reports",
        responce = GetData(endpoint),
        reports = responce[value],
        fn = (g,n,i) => "Workspace: "& g &" Report: "& n & " Dataset_id: "& i,
        repname = List.Transform( reports, each fn(groupname, _[name], _[datasetId]) )
    in
        repname;

parse_dataset_id = (str) => Text.AfterDelimiter(str, " Dataset_id: ");

ExecDAX.GetReportNameList = () =>
    let
        groups = ExecDAX.GetGroups(),
        replist = List.Transform(groups, each ExecDAX.GetReportsInGroup( _[id], _[name])),
        combine = List.Combine(replist)
    in 
        combine;

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


add_rec = (rec as record, recname as text, value as any) =>
    if value is null then rec else Record.AddField(rec, recname, value);