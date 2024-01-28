namespace PulumiWebServer.Test

open System.IO

[<RequireQualifiedAccess>]
module Utils =

    type Dummy = class end

    let rec findFileAbove (fileName : string) (di : DirectoryInfo) =
        if isNull di then
            failwith "hit the root without finding anything"

        let candidate = Path.Combine (di.FullName, fileName) |> FileInfo

        if candidate.Exists then
            candidate
        else
            findFileAbove fileName di.Parent
