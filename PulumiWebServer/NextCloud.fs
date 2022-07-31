namespace PulumiWebServer

open Pulumi
open Pulumi.Command.Remote

type NextCloudConfig =
    {
        ServerPassword : BashString
        AdminPassword : BashString
    }

[<RequireQualifiedAccess>]
module NextCloud =

    let private writeConfig
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

        Command.contentAddressedCopy
            privateKey
            address
            "write-nextcloud-config"
            trigger
            "/etc/nixos/nextcloud.nix"
            nextCloudConfig

    let private loadConfig
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

            args.Connection <- Command.connection privateKey address

            Command.addToNixFileCommand args "nextcloud.nix"

            Command ("configure-nextcloud-nix", args, Command.deleteBeforeReplace)

        let createServerPass =
            let args = CommandArgs ()

            args.Connection <- Command.connection privateKey address

            Command.createSecretFile args "nextcloud" config.ServerPassword "/var/nextcloud-db-pass"
            Command ("configure-nextcloud", args, Command.deleteBeforeReplace)

        let createUserPass =
            let args = CommandArgs ()
            args.Connection <- Command.connection privateKey address
            Command.createSecretFile args "nextcloud" config.AdminPassword "/var/nextcloud-admin-pass"
            Command ("configure-nextcloud-user", args, Command.deleteBeforeReplace)

        [
            configureNix
            createServerPass
            createUserPass
        ]

    let configure<'a>
        (infectNixTrigger : Output<'a>)
        (subdomains : Map<_, _>)
        (domain : DomainName)
        (privateKey : PrivateKey)
        (address : Address)
        (config : NextCloudConfig)
        =
        let writeConfig = writeConfig infectNixTrigger subdomains domain privateKey address

        {
            WriteConfigFile = writeConfig
            EnableConfig = loadConfig writeConfig.Stdout privateKey address config
        }
