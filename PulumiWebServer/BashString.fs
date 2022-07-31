namespace PulumiWebServer

type BashString =
    private
        {
            Original : string
            Safe : string
        }

    override this.ToString () = this.Safe

[<RequireQualifiedAccess>]
module BashString =
    let make (s : string) =
        {
            Original = s
            Safe =
                if System.Object.ReferenceEquals (s, null) then
                    null
                else
                    s.Replace ("'", "'\"'\"'") |> sprintf "'%s'"
        }

    let unsafeOriginal (s : BashString) = s.Original
