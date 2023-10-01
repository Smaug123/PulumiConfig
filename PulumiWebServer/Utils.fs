namespace PulumiWebServer

open System.IO
open System.Reflection

[<RequireQualifiedAccess>]
module Utils =
    let getEmbeddedResource (assembly : Assembly) (name : string) : string =
        let names = assembly.GetManifestResourceNames ()
        let names = names |> Seq.filter (fun s -> s.EndsWith name)

        use s =
            names
            |> Seq.exactlyOne
            |> assembly.GetManifestResourceStream
            |> fun s -> new StreamReader (s)

        s.ReadToEnd ()
