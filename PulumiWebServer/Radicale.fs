namespace PulumiWebServer

open Pulumi
open Pulumi.Command.Remote

type RadicaleConfig =
    {
        /// The user who will log in to the CalDAV server
        User : string
        /// The password for the user when they log in to the CalDAV server
        Password : string
        /// The email address for the Git user, if we are going to set up Git versioning.
        GitEmail : string option
    }

[<RequireQualifiedAccess>]
module Radicale =

    let private loadConfig<'a>
        (onChange : Output<'a>)
        (PrivateKey privateKey as pk)
        (address : Address)
        (config : RadicaleConfig)
        : Command list
        =
        let loadNix =
            let args = CommandArgs ()

            args.Triggers <- onChange |> Output.map (unbox<obj> >> Seq.singleton) |> InputList.ofOutput

            args.Connection <- Command.connection privateKey address

            Command.addToNixFileCommand args "radicale.nix"

            Command ("configure-radicale", args, Command.deleteBeforeReplace)

        let createUser = Server.createUser pk address (BashString.make "radicale")

        let writePassword =
            let password = Htpasswd.generate config.User config.Password |> BashString.make

            let args = CommandArgs ()
            args.Connection <- Command.connection privateKey address

            args.Triggers <- createUser.Stdout |> Output.map (box >> Seq.singleton) |> InputList.ofOutput

            Command.createSecretFile args "root" password "/preserve/keys/radicale-users"

            Command ("configure-radicale-user", args, Command.deleteBeforeReplace)

        let writeGit =
            match config.GitEmail with
            | None -> []
            | Some gitEmail ->
                let writeGitConfig =
                    $"""[user]
  email = "%s{gitEmail}"
  name = "radicale"
"""
                    |> Command.contentAddressedCopy
                        pk
                        address
                        "radicale-gitconfig"
                        onChange
                        "/preserve/radicale/data/.git/config"

                let writeGitIgnore =
                    """.Radicale.cache
.Radicale.lock
.Radicale.tmp-*"""
                    |> Command.contentAddressedCopy
                        pk
                        address
                        "radicale-gitignore"
                        onChange
                        "/preserve/radicale/data/.gitignore"

                [ writeGitConfig ; writeGitIgnore ]

        [ yield loadNix ; yield writePassword ; yield! writeGit ]

    let private writeConfig
        (enableGit : bool)
        (trigger : Output<'a>)
        (DomainName domain)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let radicaleConfig =
            Utils.getEmbeddedResource typeof<PrivateKey>.Assembly "radicale.nix"
            |> fun s -> s.Replace ("@@DOMAIN@@", domain)
            |> fun s -> s.Replace ("@@RADICALE_SUBDOMAIN@@", WellKnownSubdomain.Radicale.ToString ())
            |> fun s ->
                if not enableGit then
                    s.Replace ("enableGit = true", "enableGit = false")
                else
                    s

        Command.contentAddressedCopy
            privateKey
            address
            "write-radicale-config"
            trigger
            "/preserve/nixos/radicale.nix"
            radicaleConfig

    let configure
        (infectNixTrigger : Output<'a>)
        (domain : DomainName)
        (privateKey : PrivateKey)
        (address : Address)
        (config : RadicaleConfig)
        : Module
        =
        let writeConfig =
            writeConfig config.GitEmail.IsSome infectNixTrigger domain privateKey address

        {
            WriteConfigFile = writeConfig
            EnableConfig = loadConfig writeConfig.Stdout privateKey address config
        }
