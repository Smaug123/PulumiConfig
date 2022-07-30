namespace PulumiWebServer

/// A Bash-escaped string suitable for sprintf: $"echo {bashString}"
type BashString

[<RequireQualifiedAccess>]
module BashString =
    val make : string -> BashString

type NextCloudConfig =
    {
        ServerPassword : BashString
        AdminPassword : BashString
    }
