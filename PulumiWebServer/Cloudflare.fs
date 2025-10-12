namespace PulumiWebServer

open Nager.PublicSuffix
open Pulumi
open Pulumi.Cloudflare
open Pulumi.Cloudflare.Inputs

[<RequireQualifiedAccess>]
type ARecord =
    {
        IPv4 : DnsRecord option
        IPv6 : DnsRecord option
    }

type Cname =
    {
        Source : string
        Target : string
        Record : DnsRecord
    }

type DnsRecord =
    | Cname of Cname
    | ARecord of ARecord

[<RequireQualifiedAccess>]
module Cloudflare =

    let getZone (DomainName domain) : Output<ZoneId> =
        let args = GetZoneInvokeArgs ()
        args.Filter <- GetZoneFilterInputArgs (Name = domain, Match = "any")

        output {
            let! zone = GetZone.Invoke args
            return ZoneId zone.ZoneId
        }

    let makeARecord (zone : string) (name : string) (ipAddress : Address) =
        let v6 =
            match ipAddress.IPv6 with
            | None -> None
            | Some ipv6Addr ->

                let args = DnsRecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift name
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "AAAA"
                args.Content <- Input.lift ipv6Addr
                DnsRecord ($"{name}-ipv6", args) |> Some

        let v4 =
            match ipAddress.IPv4 with
            | None -> None
            | Some ipv4Addr ->

                let args = DnsRecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift name
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "A"
                args.Content <- Input.lift ipv4Addr
                DnsRecord ($"{name}-ipv4", args) |> Some

        {
            ARecord.IPv4 = v4
            ARecord.IPv6 = v6
        }

    let addDns
        (parser : IDomainParser)
        (domain : DomainName)
        (cnames : Map<WellKnownCname, WellKnownCnameTarget>)
        (subdomains : Set<WellKnownSubdomain>)
        (ZoneId zone)
        (ipAddress : Address)
        : Map<string, DnsRecord>
        =
        let globalSubdomain =
            let (DomainName domain) = domain
            let info = parser.Parse domain
            info.Subdomain |> Option.ofObj

        let subdomainMarker =
            match globalSubdomain with
            | None -> ""
            | Some s -> $".{s}"

        let cnames =
            cnames
            |> Map.toSeq
            |> Seq.map (fun (cname, target) ->
                let source = $"{cname.ToString ()}{subdomainMarker}"
                let target = WellKnownCnameTarget.Reify domain target
                let args = DnsRecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift source
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "CNAME"
                args.Content <- Input.lift target

                source,
                {
                    Record = DnsRecord ($"{cname}{subdomainMarker}-cname", args)
                    Source = source
                    Target = target
                }
                |> DnsRecord.Cname
            )
            |> Seq.toList

        let subdomains =
            subdomains
            |> Seq.map (fun subdomainType ->
                let subdomain = subdomainType.ToString ()
                subdomain, DnsRecord.ARecord (makeARecord zone $"{subdomain}{subdomainMarker}" ipAddress)
            )
            |> Seq.toList

        (domain.ToString (), DnsRecord.ARecord (makeARecord zone (domain.ToString ()) ipAddress))
        :: cnames
        @ subdomains
        |> Map.ofList
