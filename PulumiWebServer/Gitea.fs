namespace PulumiWebServer

open Pulumi
open Pulumi.Command.Remote

[<RequireQualifiedAccess>]
type GiteaConfig =
    {
        ServerPassword : BashString
        AdminPassword : BashString
        AdminUsername : BashString
        AdminEmailAddress : BashString
    }

[<RequireQualifiedAccess>]
module Gitea =

    let private writeConfig
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

        Command.contentAddressedCopy privateKey address "write-gitea-config" trigger "/etc/nixos/gitea.nix" giteaConfig

    let private loadConfig<'a>
        (onChange : Output<'a>)
        (PrivateKey privateKey)
        (address : Address)
        (config : GiteaConfig)
        : Command list
        =
        let loadNix =
            let args = CommandArgs ()

            args.Triggers <-
                onChange
                |> Output.map (unbox<obj> >> Seq.singleton)
                |> InputList.ofOutput

            args.Connection <- Command.connection privateKey address

            Command.addToNixFileCommand args "gitea.nix"

            Command ("configure-gitea", args, Command.deleteBeforeReplace)

        let writePassword =
            let args = CommandArgs ()
            args.Connection <- Command.connection privateKey address

            Command.createSecretFile args "gitea" config.ServerPassword "/var/gitea-db-pass"

            Command ("configure-gitea-password", args, Command.deleteBeforeReplace)

        let writeGiteaUserPassword =
            let args = CommandArgs ()
            args.Connection <- Command.connection privateKey address

            Command.createSecretFile args "gitea" config.AdminPassword "/var/gitea-admin-pass"

            Command ("write-gitea-password", args, Command.deleteBeforeReplace)

        [
            loadNix
            writePassword
            writeGiteaUserPassword
        ]

    let configure<'a>
        (infectNixTrigger : Output<'a>)
        (subdomains : Map<WellKnownSubdomain, string>)
        (domain : DomainName)
        (privateKey : PrivateKey)
        (address : Address)
        (config : GiteaConfig)
        : Module
        =
        let writeConfig =
            writeConfig infectNixTrigger subdomains domain privateKey address config

        {
            WriteConfigFile = writeConfig
            EnableConfig = loadConfig writeConfig.Stdout privateKey address config
        }
