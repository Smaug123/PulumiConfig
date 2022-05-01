namespace PulumiWebServer

open System.IO
open System.Reflection

[<RequireQualifiedAccess>]
module Utils =
    let getEmbeddedResource (assembly : Assembly) (name : string) : string =
        use s =
            assembly.GetManifestResourceNames ()
            |> Seq.filter (fun s -> s.EndsWith name)
            |> Seq.exactlyOne
            |> assembly.GetManifestResourceStream
            |> fun s -> new StreamReader (s)

        s.ReadToEnd ()
