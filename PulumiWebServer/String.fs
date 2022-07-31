namespace PulumiWebServer

[<RequireQualifiedAccess>]
module String =

    let private trimStart (s : string) (target : string) =
        if target.StartsWith s then
            target[s.Length ..]
        else
            target
