namespace PulumiWebServer

type BashString =
    private
    | BashString of string

    override this.ToString () =
        match this with
        | BashString s -> s

[<RequireQualifiedAccess>]
module BashString =
    let make (s : string) =
        s.Replace ("'", "\"'\"")
        |> sprintf "'%s'"
        |> BashString

type NextCloudConfig =
    {
        ServerPassword : BashString
        AdminPassword : BashString
    }
