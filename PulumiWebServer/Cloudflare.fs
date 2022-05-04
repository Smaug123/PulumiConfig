namespace PulumiWebServer

open Pulumi
open Pulumi.Cloudflare

[<RequireQualifiedAccess>]
type DnsRecord =
    {
        IPv4 : Record option
        IPv6 : Record option
    }

[<RequireQualifiedAccess>]
module Cloudflare =

    let getZone (DomainName domain) : Output<ZoneId> =
        let args = GetZoneInvokeArgs ()
        args.Name <- domain

        output {
            let! zone = GetZone.Invoke args
            return ZoneId zone.ZoneId
        }

    let addDns (subdomains : string list) (ZoneId zone) (ipAddress : Address) : Map<string, DnsRecord> =
        subdomains
        |> List.map (fun subdomain ->
            let ipv4 =
                match ipAddress.IPv4 with
                | None -> None
                | Some ipv4Addr ->

                let args = RecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift subdomain
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "A"
                args.Value <- Input.lift ipv4Addr
                Record ($"{subdomain}-ipv4", args) |> Some

            let ipv6 =
                match ipAddress.IPv6 with
                | None -> None
                | Some ipv6Addr ->

                let args = RecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift subdomain
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "AAAA"
                args.Value <- Input.lift ipv6Addr
                Record ($"{subdomain}-ipv6", args) |> Some

            subdomain,
            {
                DnsRecord.IPv4 = ipv4
                DnsRecord.IPv6 = ipv6
            }
        )
        |> Map.ofList
