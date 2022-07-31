namespace PulumiWebServer

open System
open System.Diagnostics
open Pulumi
open Pulumi.Command.Remote

[<RequireQualifiedAccess>]
module Server =

    let createUser (PrivateKey privateKey) (address : Address) (name : BashString) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address

        args.Create <- $"useradd --no-create-home --no-user-group {name} 2>/dev/null 1>/dev/null || echo {name}"

        Command ($"create-user-{name}", args)

    let rec waitForReady (PrivateKey privateKey as pk) (address : Address) : Output<unit> =
        output {
            let psi = ProcessStartInfo "/usr/bin/ssh"

            psi.Arguments <-
                $"root@{address.Get ()} -o ConnectTimeout=5 -o IdentityFile={privateKey.FullName} -o StrictHostKeyChecking=off echo hello"

            psi.RedirectStandardError <- true
            psi.RedirectStandardOutput <- true
            psi.UseShellExecute <- false
            let proc = psi |> Process.Start
            proc.WaitForExit ()
            let output = proc.StandardOutput.ReadToEnd ()
            let error = proc.StandardOutput.ReadToEnd ()
            // We don't expect to have configured SSH yet, so this is fine.
            if proc.ExitCode = 0 && output.StartsWith "hello" then
                // For some reason /usr/bin/ssh can get in at this point even though Pulumi cannot :(
                // error: ssh: handshake failed: ssh: unable to authenticate, attempted methods [none publickey], no supported methods remain

                System.Threading.Thread.Sleep (TimeSpan.FromSeconds 10.0)
                return ()
            else
                printfn $"Sleeping due to: {proc.ExitCode} {error}"
                System.Threading.Thread.Sleep (TimeSpan.FromSeconds 5.0)
                return! waitForReady pk address
        }

    let infectNix (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address

        // IMPORTANT NOTE: do not inline this script. It is licensed under the GPL, so we
        // must invoke it without "establishing intimate communication" with it.
        // https://www.gnu.org/licenses/gpl-faq.html#GPLPlugins
        args.Create <-
            "curl https://raw.githubusercontent.com/elitak/nixos-infect/90dbc4b073db966e3614b8f679a78e98e1d04e59/nixos-infect | NO_REBOOT=1 PROVIDER=digitalocean NIX_CHANNEL=nixos-21.11 bash 2>&1 | tee /tmp/infect.log && ls /etc/NIXOS_LUSTRATE"

        Command ("nix-infect", args)

    let writeUserConfig
        (trigger : Output<'a>)
        (keys : SshKey seq)
        (Username username)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let userConfig =
            Utils.getEmbeddedResource "userconfig.nix"
            |> fun s ->
                s
                    .Replace(
                        "@@AUTHORIZED_KEYS@@",
                        keys
                        |> Seq.map (fun key -> key.PublicKeyContents)
                        |> String.concat "\" \""
                    )
                    .Replace ("@@USER@@", username)

        Command.contentAddressedCopy
            privateKey
            address
            "write-user-config"
            trigger
            "/etc/nixos/userconfig.nix"
            userConfig

    let loadUserConfig (onChange : OutputCrate list) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <-
            onChange
            |> OutputCrate.sequence
            |> Output.map List.toSeq
            |> InputList.ofOutput

        args.Connection <- Command.connection privateKey address

        Command.addToNixFileCommand args "userconfig.nix"

        Command ("configure-users", args, Command.deleteBeforeReplace)

    let nixRebuild (onChange : OutputCrate list) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address
        args.Create <- "/run/current-system/sw/bin/nixos-rebuild switch"

        args.Triggers <-
            onChange
            |> OutputCrate.sequence
            |> Output.map List.toSeq
            |> InputList.ofOutput<obj>

        Command ("nixos-rebuild", args)

    let reboot (stage : string) (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address

        args.Triggers <-
            InputList.ofOutput<obj> (
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.Create <- "shutdown -r now"
        Command ($"reboot-{stage}", args)
