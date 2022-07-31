namespace PulumiWebServer

open Pulumi
open Pulumi.Command.Remote

type RadicaleConfig =
    {
        /// The user who will log in to the CalDAV server
        User : string
        /// The password for the user when they log in to the CalDAV server
        Password : string
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

            args.Triggers <-
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
                |> InputList.ofOutput

            args.Connection <- Command.connection privateKey address

            Command.addToNixFileCommand args "radicale.nix"

            Command ("configure-radicale", args, Command.deleteBeforeReplace)

        let createUser = Server.createUser pk address (BashString.make "radicale")

        let writePassword =
            let password =
                Htpasswd.generate config.User config.Password
                |> BashString.make

            let args = CommandArgs ()
            args.Connection <- Command.connection privateKey address

            args.Triggers <-
                createUser.Stdout
                |> Output.map (box >> Seq.singleton)
                |> InputList.ofOutput

            Command.createSecretFile args "radicale" password "/var/radicale_users"

            Command ("configure-radicale-user", args, Command.deleteBeforeReplace)

        [ loadNix ; writePassword ]

    let private writeConfig
        (trigger : Output<'a>)
        (subdomains : Map<WellKnownSubdomain, string>)
        (DomainName domain)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let radicaleConfig =
            Utils.getEmbeddedResource "radicale.nix"
            |> fun s -> s.Replace ("@@DOMAIN@@", domain)
            |> fun s -> s.Replace ("@@RADICALE_SUBDOMAIN@@", subdomains[WellKnownSubdomain.Radicale])

        Command.contentAddressedCopy
            privateKey
            address
            "write-radicale-config"
            trigger
            "/etc/nixos/radicale.nix"
            radicaleConfig

    let configure
        (infectNixTrigger : Output<'a>)
        (subdomains : Map<WellKnownSubdomain, string>)
        (domain : DomainName)
        (privateKey : PrivateKey)
        (address : Address)
        (config : RadicaleConfig)
        : Module
        =
        let writeConfig = writeConfig infectNixTrigger subdomains domain privateKey address

        {
            WriteConfigFile = writeConfig
            EnableConfig = loadConfig writeConfig.Stdout privateKey address config
        }
