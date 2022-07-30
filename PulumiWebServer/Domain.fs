namespace PulumiWebServer

open System.IO

type ZoneId = ZoneId of string

type PublicKey = PublicKey of FileInfo
type PrivateKey = PrivateKey of FileInfo

type Username = Username of string

type SshFingerprint = SshFingerprint of string

type SshKey =
    {
        PublicKeyContents : string
        Fingerprint : SshFingerprint
    }

type EmailAddress =
    | EmailAddress of string

    override this.ToString () =
        match this with
        | EmailAddress s -> s

[<RequireQualifiedAccess>]
module SshKey =
    let fingerprint (key : SshKey) = key.Fingerprint


type DomainName =
    | DomainName of string

    override this.ToString () =
        match this with
        | DomainName s -> s

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

type WellKnownSubdomain =
    | Nextcloud
    | Gitea

    override this.ToString () =
        match this with
        | Nextcloud -> "nextcloud"
        | Gitea -> "gitea"

type WellKnownCnameTarget =
    | Root

    static member Reify (DomainName domain) (target : WellKnownCnameTarget) : string =
        match target with
        | WellKnownCnameTarget.Root -> domain

type WellKnownCname =
    | Www

    override this.ToString () =
        match this with
        | Www -> "www"
