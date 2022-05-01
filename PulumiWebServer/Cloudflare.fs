namespace PulumiWebServer

open Nager.PublicSuffix
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

    let makeARecord (zone : string) (name : string) (ipAddress : Address) =
        let v6 =
            match ipAddress.IPv6 with
            | None -> None
            | Some ipv6Addr ->

                let args = RecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift name
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "AAAA"
                args.Value <- Input.lift ipv6Addr
                Record ($"{name}-ipv6", args) |> Some

        let v4 =
            match ipAddress.IPv4 with
            | None -> None
            | Some ipv4Addr ->

                let args = RecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift name
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "A"
                args.Value <- Input.lift ipv4Addr
                Record ($"{name}-ipv4", args) |> Some

        {
            ARecord.IPv4 = v4
            ARecord.IPv6 = v6
        }

    let addDns
        (domain : DomainName)
        (cnames : Map<WellKnownCname, WellKnownCnameTarget>)
        (subdomains : Set<WellKnownSubdomain>)
        (ZoneId zone)
        (ipAddress : Address)
        : Map<string, DnsRecord>
        =
        let globalSubdomain =
            let (DomainName domain) = domain
            let parser = DomainParser (WebTldRuleProvider ())
            let info = parser.Parse domain
            info.SubDomain |> Option.ofObj

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
                let args = RecordArgs ()
                args.ZoneId <- Input.lift zone
                args.Name <- Input.lift source
                args.Ttl <- Input.lift 60
                args.Type <- Input.lift "CNAME"
                args.Value <- Input.lift target

                source,
                {
                    Record = Record ($"{cname}{subdomainMarker}-cname", args)
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
