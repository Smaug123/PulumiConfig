namespace PulumiWebServer

type NginxConfig =
    {
        Domain : DomainName
        WebSubdomain : string
        GiteaSubdomain : string
        AcmeEmail : EmailAddress
    }

    member this.Domains =
        [
            this.WebSubdomain
            this.GiteaSubdomain
        ]
        |> List.map (fun subdomain -> $"%s{subdomain}.{this.Domain}")
        |> fun subdomains ->
            // TODO(staging): remove the staging
            sprintf "staging.%O" this.Domain :: subdomains

[<RequireQualifiedAccess>]
module Nginx =

    let private trimStart (s : string) (target : string) =
        if target.StartsWith s then
            target.[s.Length ..]
        else
            target

    let createNixConfig (config : NginxConfig) : string =
        let configTemplate =
            Utils.getEmbeddedResource "nginx.nix"
            |> fun s ->
                s
                    // TODO(staging): remove the staging
                    .Replace("@@DOMAIN@@", "staging." + config.Domain.ToString ())
                    // TODO(staging): remove the staging
                    .Replace(
                        "@@WEBROOT_SUBDOMAIN@@",
                        config.WebSubdomain
                    )
                    .Replace("@@GITEA_SUBDOMAIN@@", config.GiteaSubdomain)
                    .Replace("@@ACME_EMAIL@@", config.AcmeEmail.ToString ())
                    .Replace ("staging.staging", "staging")

        let certConfig =
            config.Domains
            |> List.map (fun domain ->
                [
                    $"\"{domain}\" ="
                    "{"
                    "  server = \"https://acme-staging-v02.api.letsencrypt.org/directory\";"
                    "};"
                ]
                |> String.concat "\n"
            )
            |> String.concat "\n"

        configTemplate.Replace ("\"@@DOMAINS@@\"", sprintf "{%s}" certConfig)
