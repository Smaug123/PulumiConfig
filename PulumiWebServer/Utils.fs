namespace PulumiWebServer

open System.IO

module Utils =
    type private Dummy =
        class
        end

    let getEmbeddedResource (name : string) : string =
        let assy = typeof<Dummy>.Assembly

        use s =
            assy.GetManifestResourceNames ()
            |> Seq.filter (fun s -> s.EndsWith name)
            |> Seq.exactlyOne
            |> assy.GetManifestResourceStream
            |> fun s -> new StreamReader (s)

        s.ReadToEnd ()
