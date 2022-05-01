namespace PulumiWebServer

open Pulumi
open Pulumi.Command.Remote

type NginxConfig =
    {
        Domain : DomainName
        WebSubdomain : WellKnownCname
        AcmeEmail : EmailAddress
    }

    member this.Domains =
        [ this.WebSubdomain ]
        |> List.map (fun subdomain -> $"%O{subdomain}.{this.Domain}")
        |> fun subdomains -> this.Domain.ToString () :: subdomains

[<RequireQualifiedAccess>]
module Nginx =

    let private createNixConfig (config : NginxConfig) : string =
        let configTemplate =
            Utils.getEmbeddedResource typeof<NginxConfig>.Assembly "nginx.nix"
            |> fun s ->
                s
                    .Replace("@@DOMAIN@@", config.Domain.ToString ())
                    .Replace("@@WEBROOT_SUBDOMAIN@@", config.WebSubdomain.ToString ())
                    .Replace ("@@ACME_EMAIL@@", config.AcmeEmail.ToString ())

        let certConfig =
            config.Domains
            |> List.map (fun domain ->
                [
                    $"\"{domain}\" ="
                    "{"
                    "  server = \"https://acme-v02.api.letsencrypt.org/directory\";"
                    "};"
                ]
                |> String.concat "\n"
            )
            |> String.concat "\n"

        configTemplate.Replace ("\"@@DOMAINS@@\"", sprintf "{%s}" certConfig)

    let private loadConfig (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()

        args.Triggers <- InputList.ofOutput<obj> (onChange |> Output.map (unbox<obj> >> Seq.singleton))

        args.Connection <- Command.connection privateKey address

        Command.addToNixFileCommand args "nginx.nix"

        Command ("configure-nginx", args, Command.deleteBeforeReplace)

    let private writeConfig
        (trigger : Output<'a>)
        (nginxConfig : NginxConfig)
        (privateKey : PrivateKey)
        (address : Address)
        : Command
        =
        let nginx = createNixConfig nginxConfig
        Command.contentAddressedCopy privateKey address "write-nginx-config" trigger "/preserve/nixos/nginx.nix" nginx

    let configure<'a>
        (infectNixTrigger : Output<'a>)
        (privateKey : PrivateKey)
        (address : Address)
        (config : NginxConfig)
        : Module
        =
        let writeConfig = writeConfig infectNixTrigger config privateKey address

        {
            WriteConfigFile = writeConfig
            EnableConfig = loadConfig writeConfig.Stdout privateKey address |> List.singleton
        }
