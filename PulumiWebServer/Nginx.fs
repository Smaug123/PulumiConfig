namespace PulumiWebServer

type NginxConfig =
    {
        Domain : DomainName
        WebSubdomain : WellKnownCname
    }

    member this.Domains =
        [ this.WebSubdomain ]
        |> List.map (fun subdomain -> $"%O{subdomain}.{this.Domain}")
        |> fun subdomains -> this.Domain.ToString () :: subdomains
