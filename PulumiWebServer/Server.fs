namespace PulumiWebServer

open System
open System.Diagnostics
open System.IO
open Pulumi
open Pulumi.Command.Remote

[<RequireQualifiedAccess>]
module Server =

    let createSecretFile (args : CommandArgs) (username : string) (toWrite : BashString) (filePath : string) : unit =
        if filePath.Contains "'" then
            failwith $"filepath contained quote: {filePath}"
        if username.Contains "'" then
            failwith $"username contained quote: {username}"
        let argsString =
            $"""OLD_UMASK=$(umask) && \
umask 077 && \
echo {toWrite} > '{filePath}' && \
chown '{username}' '{filePath}' && \
umask "$OLD_UMASK"
"""
        args.Create <- Input.ofOutput (Output.CreateSecret argsString)
        args.Delete <- $"rm -f '{filePath}'"

    let connection (privateKey : FileInfo) (address : Address) =
        let inputArgs = Inputs.ConnectionArgs ()

        inputArgs.Host <-
            address.IPv4
            |> Option.defaultWith (fun () -> Option.get address.IPv6)
            |> Input.lift

        inputArgs.Port <- Input.lift 22
        inputArgs.User <- Input.lift "root"

        inputArgs.PrivateKey <-
            File.ReadAllText privateKey.FullName
            |> Output.CreateSecret
            |> Input.ofOutput

        inputArgs |> Output.CreateSecret |> Input.ofOutput

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
        args.Connection <- connection privateKey address

        // IMPORTANT NOTE: do not inline this script. It is licensed under the GPL, so we
        // must invoke it without "establishing intimate communication" with it.
        // https://www.gnu.org/licenses/gpl-faq.html#GPLPlugins
        args.Create <-
            "curl https://raw.githubusercontent.com/elitak/nixos-infect/90dbc4b073db966e3614b8f679a78e98e1d04e59/nixos-infect | NO_REBOOT=1 PROVIDER=digitalocean NIX_CHANNEL=nixos-21.11 bash 2>&1 | tee /tmp/infect.log && ls /etc/NIXOS_LUSTRATE"

        Command ("nix-infect", args)

    let deleteBeforeReplace =
        CustomResourceOptions (DeleteBeforeReplace = Nullable true)

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
        args.Connection <- connection privateKey address

        args.Triggers <-
            trigger
            |> Output.map (unbox<obj> >> Seq.singleton)
            |> InputList.ofOutput

        // TODO - do this by passing into stdin instead
        if targetPath.Contains '\''
           || targetPath.Contains '\n' then
            failwith $"Can't copy a file to a location with a quote mark in, got: {targetPath}"

        let delimiter = "EOF"

        if fileContents.Contains delimiter then
            failwith "String contained delimiter; please implement something better"

        let commandString =
            [
                "{"
                $"cat <<'{delimiter}'"
                fileContents
                delimiter
                sprintf "} | tee '%s'" targetPath
            ]
            |> String.concat "\n"
            |> Output.CreateSecret

        args.Create <- commandString
        args.Delete <- $"rm -f '{targetPath}'"

        Command (name, args, deleteBeforeReplace)

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
        (subdomains : Map<WellKnownSubdomain, string>)
        (DomainName domain)
        (privateKey : PrivateKey)
        (address : Address)
        (config : GiteaConfig)
        : Command
        =
        let giteaConfig =
            Utils.getEmbeddedResource "gitea.nix"
            |> fun s -> s.Replace ("@@DOMAIN@@", domain)
            |> fun s -> s.Replace ("@@GITEA_SUBDOMAIN@@", subdomains[WellKnownSubdomain.Gitea])
            |> fun s -> s.Replace ("@@GITEA_ADMIN_USERNAME@@", config.AdminUsername.ToString ())
            |> fun s -> s.Replace ("@@GITEA_ADMIN_EMAIL@@", config.AdminEmailAddress.ToString ())

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

        contentAddressedCopy
            privateKey
            address
            "write-nextcloud-config"
            trigger
            "/etc/nixos/nextcloud.nix"
            nextCloudConfig

    let addToNixFileCommand (args : CommandArgs) (filename : string) : unit =
        args.Create <- $"""sed -i '4i\
    ./{filename}' /etc/nixos/configuration.nix"""
        args.Delete <- $"""sed -i -n '/{filename}/!p' /etc/nixos/configuration.nix"""

    let loadUserConfig (onChange : OutputCrate list) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <-
            onChange
            |> OutputCrate.sequence
            |> Output.map List.toSeq
            |> InputList.ofOutput

        args.Connection <- connection privateKey address

        addToNixFileCommand args "userconfig.nix"

        Command ("configure-users", args, deleteBeforeReplace)

    let loadGiteaConfig<'a>
        (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) (config : GiteaConfig)
        : Command list
        =
        let loadNix =
            let args = CommandArgs ()

            args.Triggers <-
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
                |> InputList.ofOutput

            args.Connection <- connection privateKey address

            addToNixFileCommand args "gitea.nix"

            Command ("configure-gitea", args, deleteBeforeReplace)

        let writePassword =
            let args = CommandArgs ()
            args.Connection <- connection privateKey address

            createSecretFile args "gitea" config.ServerPassword "/var/gitea-db-pass"

            Command ("configure-gitea-password", args, deleteBeforeReplace)

        let writeGiteaUserPassword =
            let args = CommandArgs ()
            args.Connection <- connection privateKey address

            createSecretFile args "gitea" config.AdminPassword "/var/gitea-admin-pass"

            Command ("write-gitea-password", args, deleteBeforeReplace)

        [ loadNix ; writePassword ; writeGiteaUserPassword ]

    let loadNginxConfig (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <-
            InputList.ofOutput<obj> (
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.Connection <- connection privateKey address

        addToNixFileCommand args "nginx.nix"

        Command ("configure-nginx", args, deleteBeforeReplace)

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

            args.Connection <- connection privateKey address

            addToNixFileCommand args "nextcloud.nix"

            Command ("configure-nextcloud-nix", args, deleteBeforeReplace)

        let createServerPass =
            let args = CommandArgs ()

            args.Connection <- connection privateKey address

            createSecretFile args "nextcloud" config.ServerPassword "/var/nextcloud-db-pass"
            Command ("configure-nextcloud", args, deleteBeforeReplace)

        let createUserPass =
            let args = CommandArgs ()
            args.Connection <- connection privateKey address
            createSecretFile args "nextcloud" config.AdminPassword "/var/nextcloud-admin-pass"
            Command ("configure-nextcloud-user", args, deleteBeforeReplace)

        [ configureNix ; createServerPass ; createUserPass ]

    let nixRebuild (onChange : OutputCrate list) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- connection privateKey address
        args.Create <- "/run/current-system/sw/bin/nixos-rebuild switch"

        args.Triggers <-
            onChange
            |> OutputCrate.sequence
            |> Output.map List.toSeq
            |> InputList.ofOutput<obj>

        Command ("nixos-rebuild", args)

    let reboot (stage : string) (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- connection privateKey address

        args.Triggers <-
            InputList.ofOutput<obj> (
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
            )

        args.Create <- "shutdown -r now"
        Command ($"reboot-{stage}", args)
