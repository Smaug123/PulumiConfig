namespace PulumiWebServer

open Pulumi
open Pulumi.Cloudflare

[<RequireQualifiedAccess>]
type ARecord =
    {
        IPv4 : Record option
        IPv6 : Record option
    }

type Cname =
    {
        Source : string
        Target : string
        Record : Record
    }

type DnsRecord =
    | Cname of Cname
    | ARecord of ARecord

[<RequireQualifiedAccess>]
module Cloudflare =

    let getZone (DomainName domain) : Output<ZoneId> =
        let args = GetZoneInvokeArgs ()
        args.Name <- domain

        output {
            let! zone = GetZone.Invoke args
            return ZoneId zone.ZoneId
        }

    let addDns
        (DomainName domain)
        (subdomains : string list)
        (ZoneId zone)
        (ipAddress : Address)
        : Map<string, DnsRecord>
        =
        let v6 =
            match ipAddress.IPv6 with
            | None -> None
            | Some ipv6Addr ->

            let args = RecordArgs ()
            args.ZoneId <- Input.lift zone
            args.Name <- Input.lift domain
            args.Ttl <- Input.lift 60
            args.Type <- Input.lift "AAAA"
            args.Value <- Input.lift ipv6Addr
            Record ($"{domain}-ipv6", args) |> Some

        let v4 =
            match ipAddress.IPv4 with
            | None -> None
            | Some ipv4Addr ->

            let args = RecordArgs ()
            args.ZoneId <- Input.lift zone
            args.Name <- Input.lift domain
            args.Ttl <- Input.lift 60
            args.Type <- Input.lift "A"
            args.Value <- Input.lift ipv4Addr
            Record ($"{domain}-ipv4", args) |> Some

        let aRecord =
            {
                ARecord.IPv4 = v4
                ARecord.IPv6 = v6
            }

        let subs =
            subdomains
            |> List.map (fun subdomain ->
                let args = RecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift subdomain
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "CNAME"
                args.Value <- Input.lift domain

                subdomain,
                {
                    Record = Record ($"{subdomain}-cname", args)
                    Source = subdomain
                    Target = domain
                }
                |> DnsRecord.Cname
            )

        (domain, DnsRecord.ARecord aRecord) :: subs
        |> Map.ofList
