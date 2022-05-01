namespace PulumiWebServer

open System.Diagnostics

[<RequireQualifiedAccess>]
module Local =
    let forgetKey (address : Address) : unit =
        let address = address.Get()
        let psi = ProcessStartInfo "/usr/bin/ssh-keygen"
        psi.Arguments <- $"-R {address}"
        psi.RedirectStandardError <- true
        psi.RedirectStandardOutput <- true
        psi.UseShellExecute <- false
        let proc = psi |> Process.Start
        proc.WaitForExit ()
        let error = proc.StandardOutput.ReadToEnd ()
        // We don't expect to have configured SSH yet, so this is fine.
        if proc.ExitCode <> 0 then
            failwith $"Unexpectedly failed to forget key: {address} ({proc.ExitCode}). {error}"
