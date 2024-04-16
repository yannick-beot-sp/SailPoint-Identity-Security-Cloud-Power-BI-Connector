// Use this file to write queries to test your data connector
let
    source = ISC.Contents("https://xxx.api.identitynow.com/"),
    data = source{[Name = "Account Activities"]}[Data],
    result = Table.RowCount(data)

in
    result
