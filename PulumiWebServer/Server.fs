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
            """if ! ls /run/current-system 1>/dev/null; then
    curl https://raw.githubusercontent.com/elitak/nixos-infect/318fc516d1d87410fd06178331a9b2939b9f2fef/nixos-infect > /tmp/infect.sh || exit 1
    while ! NO_REBOOT=1 PROVIDER=digitalocean NIX_CHANNEL=nixos-22.05 bash /tmp/infect.sh 2>&1 1>/tmp/infect.log; do
      sleep 5;
    done
fi && mkdir -p /preserve/nixos && cp /etc/nixos/* /preserve/nixos && touch /preserve/ready.txt && date"""

        Command ("nix-infect", args)

    let writeFlake (trigger : Output<'a>) (privateKey : PrivateKey) (address : Address) =
        let flakeFile = Utils.getEmbeddedResource typeof<PrivateKey>.Assembly "flake.nix"
        let flakeLock = Utils.getEmbeddedResource typeof<PrivateKey>.Assembly "flake.lock"

        [
            {
                WriteConfigFile =
                    Command.contentAddressedCopy
                        privateKey
                        address
                        "write-flake"
                        trigger
                        "/preserve/nixos/flake.nix"
                        flakeFile
                EnableConfig = []
            }
            {
                WriteConfigFile =
                    Command.contentAddressedCopy
                        privateKey
                        address
                        "write-flake-lock"
                        trigger
                        "/preserve/nixos/flake.lock"
                        flakeLock
                EnableConfig = []
            }
        ]

    let private writeUserConfig
        (trigger : Output<'a>)
        (keys : SshKey seq)
        (Username username)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let keys =
            keys
            |> Seq.collect (fun k -> k.PublicKeyContents.Split '\n')
            |> Seq.filter (not << String.IsNullOrEmpty)

        let userConfig =
            Utils.getEmbeddedResource typeof<PrivateKey>.Assembly "userconfig.nix"
            |> fun s ->
                s
                    .Replace("@@AUTHORIZED_KEYS@@", keys |> String.concat "\" \"")
                    .Replace ("@@USER@@", username)

        Command.contentAddressedCopy
            privateKey
            address
            "write-user-config"
            trigger
            "/preserve/nixos/userconfig.nix"
            userConfig

    let private loadUserConfig (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <- onChange |> Output.map (unbox<obj> >> Seq.singleton) |> InputList.ofOutput

        args.Connection <- Command.connection privateKey address

        Command.addToNixFileCommand args "userconfig.nix"

        Command ("configure-users", args, Command.deleteBeforeReplace)

    let configureUser<'a>
        (infectNixTrigger : Output<'a>)
        (remoteUser : Username)
        (keys : SshKey seq)
        (privateKey : PrivateKey)
        (address : Address)
        : Module
        =
        let writeConfig =
            writeUserConfig infectNixTrigger keys remoteUser privateKey address

        {
            WriteConfigFile = writeConfig
            EnableConfig = loadUserConfig writeConfig.Stdout privateKey address |> List.singleton
        }

    let nixRebuild (counter : int) (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address
        // The rebuild fails with exit code 1, indicating that we need to restart. This is fine.
        args.Create <-
            // TODO /nix/var/nix/profiles/system/sw/bin/nixos-rebuild might do it
            "$(find /nix/store -type f -name nixos-rebuild | head -1) switch --flake /preserve/nixos#nixos-server || exit 0"

        args.Triggers <- onChange |> Output.map (unbox<obj> >> Seq.singleton) |> InputList.ofOutput

        Command ($"nixos-rebuild-{counter}", args)

    let reboot (stage : string) (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address

        args.Triggers <- InputList.ofOutput<obj> (onChange |> Output.map (unbox<obj> >> Seq.singleton))

        args.Create <-
            "while ! ls /preserve/ready.txt ; do sleep 10; done && rm -f /preserve/ready.txt && shutdown -r now"

        Command ($"reboot-{stage}", args)

    let copyPreserve (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address

        args.Create <- "mkdir /preserve && cp -ar /old-root/preserve/nixos /preserve/nixos"

        Command ("copy-preserve", args)
