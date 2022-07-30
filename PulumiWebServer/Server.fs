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

        // IMPORTANT NOTE: do not inline this script. It is licensed under the GPL, so we
        // must invoke it without "establishing intimate communication" with it.
        // https://www.gnu.org/licenses/gpl-faq.html#GPLPlugins
        args.Create <-
            "curl https://raw.githubusercontent.com/elitak/nixos-infect/90dbc4b073db966e3614b8f679a78e98e1d04e59/nixos-infect | NO_REBOOT=1 PROVIDER=digitalocean NIX_CHANNEL=nixos-21.11 bash 2>&1 | tee /tmp/infect.log && ls /etc/NIXOS_LUSTRATE"

        Command ("nix-infect", args)

    let contentAddressedCopy
        (PrivateKey privateKey)
        (address : Address)
        (name : string)
        (trigger : Output<'a>)
        (targetPath : string)
        (fileContents : string)
        : Command
        =
        let args = CommandArgs ()
        args.Connection <- Input.lift (connection privateKey address)

        args.Triggers <-
            trigger
            |> Output.map (unbox<obj> >> Seq.singleton)
            |> InputList.ofOutput

        if targetPath.Contains '\'' || targetPath.Contains '\n' then
            failwith $"Can't copy a file to a location with a quote mark in, got: {targetPath}"
        let delimiter = "EOF"
        if fileContents.Contains delimiter then
            failwith "String contained delimiter; please implement something better"
        let commandString =
            [
                $"cat <<{delimiter}"
                fileContents
                "EOF"
            ]
            |> String.concat "\n"
        args.Create <- commandString
        args.Delete <- $"rm '{targetPath}'"

        Command (name, args)

    let writeNginxConfig
        (trigger : Output<'a>)
        (nginxConfig : NginxConfig)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let nginx = Nginx.createNixConfig nginxConfig
        contentAddressedCopy privateKey address "write-nginx-config" trigger "/etc/nixos/nginx.nix" nginx

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

        contentAddressedCopy privateKey address "write-user-config" trigger "/etc/nixos/userconfig.nix" userConfig

    let writeGiteaConfig
        (trigger : Output<'a>)
        (subdomain : string)
        (DomainName domain)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let giteaConfig =
            Utils.getEmbeddedResource "gitea.nix"
            |> fun s -> s.Replace ("@@DOMAIN@@", domain)
            |> fun s -> s.Replace ("@@GITEA_SUBDOMAIN@@", subdomain)

        contentAddressedCopy privateKey address "write-gitea-config" trigger "/etc/nixos/gitea.nix" giteaConfig

    let writeNextCloudConfig
        (trigger : Output<'a>)
        (subdomains : Map<WellKnownSubdomain, string>)
        (DomainName domain)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let nextCloudConfig =
            Utils.getEmbeddedResource "nextcloud.nix"
            |> fun s -> s.Replace ("@@DOMAIN@@", domain)
            |> fun s -> s.Replace ("@@NEXTCLOUD_SUBDOMAIN@@", subdomains[WellKnownSubdomain.Nextcloud])

        contentAddressedCopy privateKey address "write-nextcloud-config" trigger "/etc/nixos/nextcloud.nix" nextCloudConfig

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

    let loadNextCloudConfig
        (onChange : Output<'a>)
        (PrivateKey privateKey)
        (address : Address)
        (config : NextCloudConfig)
        : Command list
        =
        let configureNix =
            let args = CommandArgs ()

            args.Triggers <-
                InputList.ofOutput<obj> (
                    onChange
                    |> Output.map (unbox<obj> >> Seq.singleton)
                )

            args.Connection <- Input.lift (connection privateKey address)

            args.Create <-
                """sed -i '4i\
        ./nextcloud.nix\
    ' /etc/nixos/configuration.nix"""

            args.Delete <- """sed -i '/nextcloud.nix/d' /etc/nixos/configuration.nix"""
            Command ("configure-nextcloud-nix", args)

        let configureNextCloud =
            let args = CommandArgs ()

            args.Triggers <-
                InputList.ofOutput<obj> (
                    onChange
                    |> Output.map (unbox<obj> >> Seq.singleton)
                )

            args.Connection <- Input.lift (connection privateKey address)

            let argsString =
                $"""OLD_UMASK=$(umask) && \
umask 077 && \
echo {config.ServerPassword} > /var/nextcloud-db-pass && \
chown nextcloud /var/nextcloud-db-pass && \
echo {config.AdminPassword} > /var/nextcloud-admin-pass && \
chown nextcloud /var/nextcloud-admin-pass && \
umask "$OLD_UMASK"
"""
            args.Create <- Input.lift argsString

            args.Delete <- """rm /var/nextcloud-db-pass && rm /var/nextcloud-admin-pass"""
            Command ("configure-nextcloud", args)

        [ configureNix ; configureNextCloud ]

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

    let reboot (stage : string) (onChange : OutputCrate list) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Input.lift (connection privateKey address)

        args.Triggers <-
            onChange
            |> OutputCrate.sequence
            |> Output.map List.toSeq
            |> InputList.ofOutput<obj>

        args.Create <- "shutdown -r now"
        Command ($"reboot-{stage}", args)
