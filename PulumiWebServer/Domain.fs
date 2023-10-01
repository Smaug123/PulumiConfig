namespace PulumiWebServer

open System.IO

type ZoneId = | ZoneId of string

[<NoComparison ; CustomEquality>]
type PublicKey =
    | PublicKey of FileInfo

    override this.Equals (other : obj) =
        match this, other with
        | PublicKey this, (:? PublicKey as PublicKey other) -> this.FullName = other.FullName
        | _, _ -> false

    override this.GetHashCode () =
        match this with
        | PublicKey p -> p.FullName.GetHashCode ()

[<NoComparison ; CustomEquality>]
type PrivateKey =
    | PrivateKey of FileInfo

    override this.Equals (other : obj) =
        match this, other with
        | PrivateKey this, (:? PrivateKey as PrivateKey other) -> this.FullName = other.FullName
        | _, _ -> false

    override this.GetHashCode () =
        match this with
        | PrivateKey p -> p.FullName.GetHashCode ()

type Username =
    | Username of string

    override this.ToString () =
        match this with
        | Username s -> s

type SshFingerprint = | SshFingerprint of string

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
    | Radicale
    | Rss
    | Woodpecker
    | WoodpeckerAgent
    | Grafana

    override this.ToString () =
        match this with
        | Nextcloud -> "nextcloud"
        | Gitea -> "gitea"
        | Radicale -> "calendar"
        | Rss -> "rss"
        | Grafana -> "grafana"
        | Woodpecker -> "woodpecker"
        | WoodpeckerAgent -> "woodpecker-agent"

    static member Parse (s : string) =
        match s with
        | "nextcloud" -> WellKnownSubdomain.Nextcloud
        | "gitea" -> WellKnownSubdomain.Gitea
        | "calendar" -> WellKnownSubdomain.Radicale
        | "rss" -> WellKnownSubdomain.Rss
        | "woodpecker" -> WellKnownSubdomain.Woodpecker
        | "woodpecker-agent" -> WellKnownSubdomain.WoodpeckerAgent
        | "grafana" -> WellKnownSubdomain.Grafana
        | _ -> failwith $"Failed to deserialise: {s}"


type WellKnownCnameTarget =
    | Root

    static member Reify (DomainName domain) (target : WellKnownCnameTarget) : string =
        match target with
        | WellKnownCnameTarget.Root -> domain

    static member Serialise (t : WellKnownCnameTarget) : string =
        match t with
        | WellKnownCnameTarget.Root -> "root"

    static member Deserialise (t : string) : WellKnownCnameTarget =
        match t with
        | "root" -> WellKnownCnameTarget.Root
        | _ -> failwith $"Failed to deserialise: {t}"

type WellKnownCname =
    | Www

    override this.ToString () =
        match this with
        | Www -> "www"

    static member Parse (s : string) =
        match s with
        | "www" -> WellKnownCname.Www
        | _ -> failwith $"Failed to deserialise: {s}"
