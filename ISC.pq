// This file contains your Data Connector logic
[Version = "1.0.0"]
section ISC;

[DataSource.Kind = "ISC", Publish = "ISC.Publish"]
shared ISC.Contents = Value.ReplaceType(ISC.ISCNavTable, ISC.ISCNavTableType);

// For testing purpose
// [DataSource.Kind = "ISC"]
// shared ISC.IdentityNowTest = Value.ReplaceType(ISC.CallSearch, ISC.ISCNavTableType);
// For testing purpose
ISC.CallSearch = (url as text) as any =>
    let
        accessToken = ISC.GetAccessToken(url),
        indice = "roles",
        schema = GetSchemaForIndice(indice),
        // result = ISC.GetIndice(url, accessToken, "identities")
        // result = ISC.PagedSearch(url, accessToken, indice, schema)
        result = ISC.SearchImpl(url, accessToken, "identities", "0", schema)
        // response = Table.ChangeType(result, schema)
    in
        result;

GetSchemaForIndice = (indice as text) as type =>
    try Indices{[Indice = indice]}[Type] otherwise error "Couldn't find indice: '" & indice & "'";

ISC.ISCNavTable = (url as text) as table =>
    let
        // 1h should be enough?
        accessToken = ISC.GetAccessToken(url),
        withData = #table(
            {"Name", "Type", "Data"},
            {
                {
                    "Access Profiles",
                    Schema.AccessProfileType,
                    ISC.GetIndice(url, accessToken, "accessprofiles")
                },
                {
                    "Account Activities",
                    Schema.AccountActivityType,
                    ISC.GetIndice(url, accessToken, "accountactivities")
                },
                {"Entitlements", Schema.EntitlementType, ISC.GetIndice(url, accessToken, "entitlements")},
                {"Events", Schema.EventType, ISC.GetIndice(url, accessToken, "events")},
                {"Identities", Schema.IdentityType, ISC.GetIndice(url, accessToken, "identities")},
                {"Roles", Schema.RoleType, ISC.GetIndice(url, accessToken, "roles")},
                {
                    "Outliers",
                    Schema.OutlierType,
                    ISC.GetResource(url, accessToken, "/beta/outliers", Schema.OutlierType)
                },
                {"Potential Roles", Schema.OutlierType, ISC.GetPotentialRoles(url, accessToken)}
            }
        ),
        // Add Data as a calculated column
        //withData = Table.AddColumn(Indices, "Data", each ISC.GetIndice(url, accessToken, [Indice])),
        // Add ItemKind and ItemName as fixed text values
        withItemKind = Table.AddColumn(withData, "ItemKind", each "Table", type text),
        withItemName = Table.AddColumn(withItemKind, "ItemName", each "Table", type text),
        // Indicate that the node should not be expandable
        withIsLeaf = Table.AddColumn(withItemName, "IsLeaf", each true, type logical),
        // Generate the nav table
        navTable = Table.ToNavigationTable(withIsLeaf, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

ISC.ISCNavTableType = type function (
    aPIURL as (
        type text meta [
            Documentation.FieldCaption = "ISC API URL (https://{tenant}.api.identitynow.com)",
            Documentation.FieldDescription = "ISC API URL",
            Documentation.SampleValues = {"https://{tenant}.api.identitynow.com"}
        ]
    )
) as any;

Indices = #table(
    {"Name", "Indice", "Type"},
    {
        {"Access Profiles", "accessprofiles", Schema.AccessProfileType},
        {"Account Activities", "accountactivities", Schema.AccountActivityType},
        {"Entitlements", "entitlements", Schema.EntitlementType},
        {"Events", "events", Schema.EventType},
        {"Identities", "identities", Schema.IdentityType},
        {"Roles", "roles", Schema.RoleType}
    }
);

ISC.GetIndice = (url as text, accessToken as text, indice as text) as table =>
    let
        schema = GetSchemaForIndice(indice),
        result = ISC.PagedSearch(url, accessToken, indice, schema),
        appliedSchema = Table.ChangeType(result, schema)
    in
        appliedSchema;

// Read all pages of data.
// Table.GenerateByPage will keep asking for more pages until we return null.
ISC.PagedSearch = (url as text, accessToken as text, indice as text, schema as type) as table =>
    Table.GenerateByPage(
        (previous) =>
            let
                offset = if (previous = null) then "0" else Value.Metadata(previous)[NextOffset],
                count = if (previous = null) then "10000" else Value.Metadata(previous)[Count],
                page =
                    if (
                        Number.FromText(offset) < 10000
                        and Value.Compare(Number.FromText(offset), Number.FromText(count)) < 0
                    ) then
                        ISC.SearchImpl(url, accessToken, indice, offset, schema)
                    else
                        null
            in
                page
    );

ISC.SearchImpl = (url as text, accessToken as text, indice as text, offset as text, schema as type) =>
    let
        limit = "250",
        searchUrl = Uri.Combine(url, "/v3/search")
            & "?"
            & Uri.BuildQueryString([
                count = "true",
                offset = offset,
                limit = limit
            ]),
        _url = Diagnostics.LogValue("Search URL", searchUrl),
        response = Web.Contents(
            searchUrl,
            [
                Content = Json.FromValue(
                    [
                        indices = {indice},
                        query = [
                            query = "*"
                        ],
                        sort = {"created"},
                        includeNested = true
                    ]
                ),
                Headers = [
                    #"Content-Type" = "application/json",
                    #"Accept" = "application/json",
                    #"Authorization" = "Bearer " & accessToken
                ]
            ]
        ),
        count = Value.Metadata(response)[Headers][#"X-Total-Count"],
        nextOffset = Number.ToText(Value.Add(Number.FromText(limit), Number.FromText(offset))),
        json = Json.Document(response),
        // expand all columns from the record
        asTable = Table.FromList(json, Splitter.SplitByNothing(), {"Column1"}),
        fields = Record.FieldNames(Type.RecordFields(Type.TableRow(schema))),
        expanded = Table.ExpandRecordColumn(asTable, "Column1", fields)
        //expanded = Table.FromRecords(json)
    in
        expanded meta [
            Count = count,
            NextOffset = nextOffset
        ];

[DataSource.Kind = "ISC"]
shared ISC.GetAccessToken = (aPIURL as text) =>
    let
        tokenUrl = Uri.Combine(aPIURL, "/oauth/token"),
        credentials = Extension.CurrentCredential(),
        Response = Web.Contents(
            tokenUrl,
            [
                Content = Text.ToBinary(
                    Uri.BuildQueryString(
                        [
                            client_id = credentials[Username],
                            client_secret = credentials[Password],
                            grant_type = "client_credentials"
                        ]
                    )
                ),
                Headers = [#"Content-type" = "application/x-www-form-urlencoded", #"Accept" = "application/json"]
            ]
        ),
        Parts = Json.Document(Response),
        accessToken = Parts[access_token]
    in
        accessToken;

ISC.GetResource = (url as text, accessToken as text, path as text, schema as type) as table =>
    let
        resourceUrl = Uri.Combine(url, path),
        count = ISC.GetCount(resourceUrl, accessToken),
        result = ISC.PaginatedResource(resourceUrl, accessToken, count, schema),
        appliedSchema = Table.ChangeType(result, schema)
    in
        appliedSchema;

ISC.GetCount = (resourceUrl as text, accessToken as text) =>
    let
        limit = "0",
        targetUrl = resourceUrl & "?" & Uri.BuildQueryString([
            count = "true",
            offset = "0",
            limit = limit
        ]),
        response = Web.Contents(
            targetUrl, [
                Headers = [
                    #"Accept" = "application/json",
                    #"Authorization" = "Bearer " & accessToken
                ]
            ]
        ),
        count = Number.FromText(Value.Metadata(response)[Headers][#"X-Total-Count"])
    in
        count;

ISC.PaginatedResource = (url as text, accessToken as text, count as number, schema as type) as table =>
    Table.GenerateByPage(
        (previous) =>
            let
                offset = Number.FromText(
                    if (previous = null) then "0" else Number.ToText(Value.Metadata(previous)[NextOffset])
                ),
                page = if (offset > count) then null else ISC.GetPage(url, accessToken, offset, schema)
            in
                page
    );

ISC.GetPage = (resourceUrl as text, accessToken as text, offset as number, schema as type) =>
    let
        limit = 250,
        targetUrl = resourceUrl
            & "?"
            & Uri.BuildQueryString([
                count = "false",
                offset = Number.ToText(offset),
                limit = Number.ToText(limit)
            ]),
        response = Web.Contents(
            targetUrl, [
                Headers = [
                    #"Accept" = "application/json",
                    #"Authorization" = "Bearer " & accessToken
                ]
            ]
        ),
        json = Json.Document(response),
        nextOffset = offset + limit,
        // expand all columns from the record
        asTable = Table.FromList(json, Splitter.SplitByNothing(), {"Column1"}),
        fields = Record.FieldNames(Type.RecordFields(Type.TableRow(schema))),
        expanded = Table.ExpandRecordColumn(asTable, "Column1", fields)
    in
        expanded meta [
            NextOffset = nextOffset
        ];

ISC.GetPotentialRoles = (url as text, accessToken as text) as table =>
    let
        allRoleMiningSessionsUrl = Uri.Combine(url, "/beta/role-mining-sessions"),
        allRoleMiningSessionsCount = ISC.GetCount(allRoleMiningSessionsUrl, accessToken),
        allRoleMiningSessionsResult = ISC.PaginatedResource(
            allRoleMiningSessionsUrl, accessToken, allRoleMiningSessionsCount, Schema.RoleMiningSessionType
        ),
        allRoleMiningSessionsAppliedSchema = Table.ChangeType(
            allRoleMiningSessionsResult, Schema.RoleMiningSessionType
        ),
        withUrl = Table.AddColumn(
            allRoleMiningSessionsAppliedSchema,
            "Url",
            each Uri.Combine(url, "/beta/role-mining-sessions/" & [id] & "/potential-role-summaries")
        ),
        withSessionId = Table.RenameColumns(withUrl, {"id", "sessionId"}),
        roleMiningSessionsFields = Record.FieldNames(Type.RecordFields(Type.TableRow(Schema.RoleMiningSessionType))),
        withData = Table.AddColumn(
            withSessionId,
            "Data",
            each ISC.GetResource([Url], accessToken, "", Schema.PotentialRoleSummaryType)
        ),
        cleanedFromroleMiningSessionsColumns = Table.RemoveColumns(
            withData, roleMiningSessionsFields, MissingField.Ignore
        ),
        cleanedFromUrl = Table.RemoveColumns(cleanedFromroleMiningSessionsColumns, {"Url"}),
        potentialRoleSummaryFields = Record.FieldNames(
            Type.RecordFields(Type.TableRow(Schema.PotentialRoleSummaryType))
        ),
        expanded = Table.ExpandTableColumn(cleanedFromUrl, "Data", potentialRoleSummaryFields),
        withUrlDetails = Table.AddColumn(
            expanded, "UrlDetails", each
                Uri.Combine(url, "/beta/role-mining-potential-roles/" & [id] & "?details=true")
        ),
        withPotentialRoleDetails = Table.AddColumn(
            withUrlDetails, "PotentialRoleDetails", each ISC.GetSingleResource([UrlDetails], accessToken)
        ),
        withoutIdentityIds = Table.RemoveColumns(withPotentialRoleDetails, {"identityIds", "UrlDetails"}),
        expandedWithDetails = Table.ExpandRecordColumn(withoutIdentityIds, "PotentialRoleDetails", {"identityIds"}),
        appliedSchema = Table.ChangeType(expandedWithDetails, Schema.PotentialRoleSummaryType)
    in
        expandedWithDetails;

ISC.GetSingleResource = (url as text, accessToken as text) as any =>
    let
        source = Web.Contents(
            url, [
                Headers = [
                    #"Accept" = "application/json",
                    #"Authorization" = "Bearer " & accessToken
                ]
            ]
        ),
        json = Json.Document(source)
    in
        json;
// Example of REST call
ISC.GetIdentities = (url as text, accessToken as text) as any =>
    let
        identitiesUrl = Text.Trim(url, "/") & "/beta/identities",
        source = Web.Contents(
            identitiesUrl, [
                Headers = [
                    #"Accept" = "application/json",
                    #"Authorization" = "Bearer " & accessToken
                ]
            ]
        ),
        json = Json.Document(source)
    in
        json;

// Data Source Kind description
ISC = [
    //GetAccessToken is used for efficiency
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath), aPIURL = json[aPIURL]
        in
            {"ISC.GetAccessToken", aPIURL},
    Authentication = [
        UsernamePassword = []
    ]
];

// Data Source UI publishing description
ISC.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = {Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp")},
    LearnMoreUrl = "https://sailpoint.com/",
    SourceImage = ISC.Icons,
    SourceTypeImage = ISC.Icons
];

ISC.Icons = [
    Icon16 = {
        Extension.Contents("ISC16.png"),
        Extension.Contents("ISC20.png"),
        Extension.Contents("ISC24.png"),
        Extension.Contents("ISC32.png")
    },
    Icon32 = {
        Extension.Contents("ISC32.png"),
        Extension.Contents("ISC40.png"),
        Extension.Contents("ISC48.png"),
        Extension.Contents("ISC64.png")
    }
];

/************************************************
 ******************* Includes *******************
 ************************************************/
// TEMPORARY WORKAROUND until we're able to reference other M modules
Extension.LoadFunction = (fileName as text) =>
    let
        binary = Extension.Contents(fileName), asText = Text.FromBinary(binary)
    in
        try
            Expression.Evaluate(asText, #shared) catch (e) =>
                error
                    [
                        Reason = "Extension.LoadFunction Failure",
                        Message.Format = "Loading '#{0}' failed - '#{1}': '#{2}'",
                        Message.Parameters = {fileName, e[Reason], e[Message]},
                        Detail = [File = fileName, Error = e]
                    ];

// Diagnostics module contains multiple functions. We can take the ones we need.
Diagnostics = Extension.LoadFunction("Diagnostics.pqm");

Diagnostics.LogValue = Diagnostics[LogValue];
Diagnostics.LogFailure = Diagnostics[LogFailure];

Table.ChangeType = Extension.LoadFunction("Table.ChangeType.pqm");
Table.GenerateByPage = Extension.LoadFunction("Table.GenerateByPage.pqm");
Table.ToNavigationTable = Extension.LoadFunction("Table.ToNavigationTable.pqm");

Schema = Extension.LoadFunction("Schema.pqm");

Schema.AccessProfileType = Schema[AccessProfileType];
Schema.AccountActivityType = Schema[AccountActivityType];
Schema.EntitlementType = Schema[EntitlementType];
Schema.EventType = Schema[EventType];
Schema.IdentityType = Schema[IdentityType];
Schema.RoleType = Schema[RoleType];
Schema.OutlierType = Schema[OutlierType];
Schema.RoleMiningSessionType = Schema[RoleMiningSessionType];
Schema.PotentialRoleSummaryType = Schema[PotentialRoleSummaryType];

SchemaModule = Extension.LoadFunction("Schema.functions.pqm");

EnforceSchema.Strict = SchemaModule[EnforceSchema.Strict];
EnforceSchema.IgnoreExtraColumns = SchemaModule[EnforceSchema.IgnoreExtraColumns];
EnforceSchema.IgnoreMissingColumns = SchemaModule[EnforceSchema.IgnoreMissingColumns];
