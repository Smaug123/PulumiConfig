namespace PulumiWebServer

open System.Diagnostics

[<RequireQualifiedAccess>]
module Htpasswd =

    /// Return the contents of an htpasswd file
    let generate (username : string) (password : string) : string =
        let args = ProcessStartInfo ()
        args.FileName <- "htpasswd"
        args.RedirectStandardOutput <- true
        args.RedirectStandardError <- true
        args.RedirectStandardInput <- true
        args.UseShellExecute <- false
        args.Arguments <- $"-n -i -B {username}"

        use p = new Process ()
        p.StartInfo <- args

        if not <| p.Start () then
            failwith "failed to start htpasswd"

        p.StandardInput.Write password
        p.StandardInput.Close ()

        p.WaitForExit ()

        if p.ExitCode = 0 then
            p.StandardOutput.ReadToEnd ()
        else

            printfn $"{p.StandardError.ReadToEnd ()}"
            failwith $"Bad exit code from htpasswd: {p.ExitCode}"
