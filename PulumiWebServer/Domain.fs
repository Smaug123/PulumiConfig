namespace PulumiWebServer

open System.IO

type ZoneId = ZoneId of string

type PublicKey = PublicKey of FileInfo
type PrivateKey = PrivateKey of FileInfo

type Username = Username of string

type SshFingerprint = SshFingerprint of string

type EmailAddress = EmailAddress of string

type DomainName = DomainName of string

type Address =
    {
        IPv4 : string option
        IPv6 : string option
    }

    member this.Get () =
        // TODO: default to IPv6 for access
        match this.IPv4 with
        | Some v -> v
        | None ->

        match this.IPv6 with
        | Some v -> v
        | None -> failwith "could not get"

    override this.ToString () =
        let ipv4 =
            match this.IPv4 with
            | Some s -> s
            | None -> ""

        let ipv6 =
            match this.IPv6 with
            | Some s -> s
            | None -> ""

        [ ipv4 ; ipv6 ] |> String.concat " ; "
