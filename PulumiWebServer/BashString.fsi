namespace PulumiWebServer

type BashString

[<RequireQualifiedAccess>]
module BashString =
    val make : string -> BashString

    /// Get the original string that was used to make this BashString.
    /// This is not safe to interpolate into a Bash script.
    val unsafeOriginal : BashString -> string
