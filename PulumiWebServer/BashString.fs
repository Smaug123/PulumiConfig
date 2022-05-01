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
                // This is actually of course not safe, but it's
                // close enough.
                if System.Object.ReferenceEquals (s, null) then
                    null
                else
                    s.Replace ("'", "'\"'\"'") |> sprintf "'%s'"
        }

    let unsafeOriginal (s : BashString) = s.Original
