namespace PulumiWebServer

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

    let private trimStart (s : string) (target : string) =
        if target.StartsWith s then
            target[s.Length ..]
        else
            target

    let createNixConfig (config : NginxConfig) : string =
        let configTemplate =
            Utils.getEmbeddedResource "nginx.nix"
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
