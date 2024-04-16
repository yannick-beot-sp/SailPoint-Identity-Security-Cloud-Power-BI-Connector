// Use this file to write queries to test your data connector
let
    source = ISC.Contents("https://xxx.api.identitynow.com/"),
    result = source{[Name = "Potential Roles"]}[Data]
in
    result
