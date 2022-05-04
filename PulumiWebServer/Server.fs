namespace PulumiWebServer

open System
open System.Diagnostics
open System.IO
open Pulumi
open Pulumi.Command.Remote

[<RequireQualifiedAccess>]
module Server =

    let connection (privateKey : FileInfo) (address : Address) =
        let inputArgs = Inputs.ConnectionArgs ()

        inputArgs.Host <-
            address.IPv4
            |> Option.defaultWith (fun () -> Option.get address.IPv6)
            |> Input.lift

        inputArgs.Port <- Input.lift 22
        inputArgs.User <- Input.lift "root"
        inputArgs.PrivateKey <- Input.lift (File.ReadAllText privateKey.FullName)
        inputArgs

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
        args.Connection <- Input.lift (connection privateKey address)

        args.Create <-
            "curl https://raw.githubusercontent.com/elitak/nixos-infect/90dbc4b073db966e3614b8f679a78e98e1d04e59/nixos-infect | NO_REBOOT=1 PROVIDER=digitalocean NIX_CHANNEL=nixos-21.11 bash 2>&1 | tee /tmp/infect.log"

        Command ("nix-infect", args)

    let writeNginxConfig
        (trigger : Output<'a>)
        (subdomain : string)
        (DomainName domain)
        (EmailAddress acmeEmail)
        (PrivateKey privateKey)
        (address : Address)
        : CopyFile * FileInfo
        =
        let nginx =
            Utils.getEmbeddedResource "nginx.nix"
            |> fun s ->
                s
                    .Replace("@@DOMAIN@@", $"{subdomain}.{domain}")
                    .Replace ("@@ACME_EMAIL", acmeEmail)

        let tmpPath = Path.GetTempFileName () |> FileInfo
        File.WriteAllText (tmpPath.FullName, nginx)
        let args = CopyFileArgs ()
        printfn "%s" tmpPath.FullName

        args.Triggers <-
            InputList.ofOutput<obj> (
                trigger
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.LocalPath <- Input.lift tmpPath.FullName
        args.RemotePath <- Input.lift "/etc/nixos/nginx.nix"
        args.Connection <- Input.lift (connection privateKey address)
        CopyFile ("write-nginx-config", args), tmpPath

    let writeUserConfig
        (trigger : Output<'a>)
        (keys : SshFingerprint seq)
        (Username username)
        (PrivateKey privateKey)
        (address : Address)
        : CopyFile * FileInfo
        =
        let userConfig =
            Utils.getEmbeddedResource "userconfig.nix"
            |> fun s ->
                s
                    .Replace(
                        "@@AUTHORIZED_KEYS@@",
                        keys
                        |> Seq.map (fun (SshFingerprint r) -> r)
                        |> String.concat "\" \""
                    )
                    .Replace ("@@USER@@", username)

        let tmpPath = Path.GetTempFileName () |> FileInfo
        File.WriteAllText (tmpPath.FullName, userConfig)
        let args = CopyFileArgs ()

        args.Triggers <-
            InputList.ofOutput<obj> (
                trigger
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.LocalPath <- Input.lift tmpPath.FullName
        args.RemotePath <- Input.lift "/etc/nixos/userconfig.nix"
        args.Connection <- Input.lift (connection privateKey address)
        CopyFile ("write-user-config", args), tmpPath

    let writeGiteaConfig
        (trigger : Output<'a>)
        (DomainName domain)
        (PrivateKey privateKey)
        (address : Address)
        : CopyFile * FileInfo
        =
        let userConfig =
            Utils.getEmbeddedResource "gitea.nix"
            |> fun s -> s.Replace("@@DOMAIN@@", domain)

        let tmpPath = Path.GetTempFileName () |> FileInfo
        File.WriteAllText (tmpPath.FullName, userConfig)
        let args = CopyFileArgs ()

        args.Triggers <-
            InputList.ofOutput<obj> (
                trigger
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.LocalPath <- Input.lift tmpPath.FullName
        args.RemotePath <- Input.lift "/etc/nixos/gitea.nix"
        args.Connection <- Input.lift (connection privateKey address)
        CopyFile ("write-gitea-config", args), tmpPath

    let loadUserConfig (onChange : OutputCrate list) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <-
            onChange
            |> OutputCrate.sequence
            |> Output.map List.toSeq
            |> InputList.ofOutput

        args.Connection <- Input.lift (connection privateKey address)

        args.Create <-
            """sed -i '4i\
    ./userconfig.nix\
' /etc/nixos/configuration.nix"""

        args.Delete <- """sed -i '/userconfig.nix/d' /etc/nixos/configuration.nix"""
        Command ("configure-users", args)

    let loadGiteaConfig<'a> (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <-
            onChange
            |> Output.map (unbox<obj> >> Seq.singleton)
            |> InputList.ofOutput

        args.Connection <- Input.lift (connection privateKey address)

        args.Create <-
            """sed -i '4i\
    ./gitea.nix\
' /etc/nixos/configuration.nix"""

        args.Delete <- """sed -i '/gitea.nix/d' /etc/nixos/configuration.nix"""
        Command ("configure-gitea", args)

    let loadNginxConfig (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <-
            InputList.ofOutput<obj> (
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.Connection <- Input.lift (connection privateKey address)

        args.Create <-
            """sed -i '4i\
    ./nginx.nix\
' /etc/nixos/configuration.nix"""

        args.Delete <- """sed -i '/nginx.nix/d' /etc/nixos/configuration.nix"""
        Command ("configure-nginx", args)

    let nixRebuild (onChange : OutputCrate list) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Input.lift (connection privateKey address)
        args.Create <- "/run/current-system/sw/bin/nixos-rebuild switch"

        args.Triggers <-
            onChange
            |> OutputCrate.sequence
            |> Output.map List.toSeq
            |> InputList.ofOutput<obj>

        Command ("nixos-rebuild", args)

    let reboot (stage : string) (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Input.lift (connection privateKey address)

        args.Triggers <-
            InputList.ofOutput<obj> (
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.Create <- "shutdown -r now"
        Command ($"reboot-{stage}", args)
