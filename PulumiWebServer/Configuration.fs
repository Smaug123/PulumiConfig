namespace PulumiWebServer

open System
open System.Collections.Generic
open System.IO
open Newtonsoft.Json

[<NoComparison>]
type Configuration =
    {
        /// Name of this server, as it will be known to Pulumi.
        /// This isn't e.g. a hostname or anything; it's the key on which Pulumi deduplicates
        /// different runs of this plan.
        Name : string
        /// Private key with which to talk to the server
        PrivateKey : PrivateKey
        /// Public key corresponding to the PrivateKey (default has ".pub" appended)
        PublicKeyOverride : PublicKey option
        /// Umbrella domain name for all services
        Domain : DomainName
        /// All cnames to be created in DNS
        Cnames : Map<WellKnownCname, WellKnownCnameTarget>
        /// All subdomains which are not cnames;
        /// e.g. (WellKnownSubdomain.Www, "www") would indicate
        /// the `www.domain.name` address, in the counterfactual
        /// world where `Www` were implemented as a subdomain
        /// and not a cname
        Subdomains : Set<WellKnownSubdomain>
        /// Email address to use with ACME registration
        AcmeEmail : EmailAddress
        /// Username for the user account to be created on the server
        RemoteUsername : Username
    }

    member this.PublicKey =
        match this.PublicKeyOverride with
        | Some k -> k
        | None ->
            let (PrivateKey k) = this.PrivateKey
            Path.Combine (k.Directory.FullName, k.Name + ".pub") |> FileInfo |> PublicKey

[<NoComparison>]
[<RequireQualifiedAccess>]
type SerialisedConfig =
    {
        [<JsonProperty(Required = Required.Always)>]
        Name : string
        /// Path to private key
        [<JsonProperty(Required = Required.Always)>]
        PrivateKey : string
        /// Path to public key
        [<JsonProperty(Required = Required.DisallowNull)>]
        PublicKey : string
        [<JsonProperty(Required = Required.Always)>]
        Domain : string
        [<JsonProperty(Required = Required.Always)>]
        Cnames : Dictionary<string, string>
        [<JsonProperty(Required = Required.DisallowNull)>]
        Subdomains : string[]
        [<JsonProperty(Required = Required.Always)>]
        AcmeEmail : string
        [<JsonProperty(Required = Required.Always)>]
        RemoteUsername : string
    }

    static member Make (config : Configuration) =
        {
            SerialisedConfig.PrivateKey = let (PrivateKey p) = config.PrivateKey in p.FullName
            Name = config.Name
            PublicKey =
                match config.PublicKeyOverride with
                | None -> null
                | Some (PublicKey p) -> p.FullName
            Domain = config.Domain.ToString ()
            Cnames =
                config.Cnames
                |> Map.toSeq
                |> Seq.map (fun (cname, target) ->
                    KeyValuePair (cname.ToString (), WellKnownCnameTarget.Serialise target)
                )
                |> Dictionary
            Subdomains = config.Subdomains |> Seq.map (fun sub -> sub.ToString ()) |> Seq.toArray
            AcmeEmail = config.AcmeEmail.ToString ()
            RemoteUsername = config.RemoteUsername.ToString ()
        }

    static member Deserialise (config : SerialisedConfig) : Configuration =
        {
            Configuration.PrivateKey = FileInfo config.PrivateKey |> PrivateKey
            Name = config.Name
            PublicKeyOverride =
                match config.PublicKey with
                | null -> None
                | key -> FileInfo key |> PublicKey |> Some
            Domain = config.Domain |> DomainName
            Cnames =
                config.Cnames
                |> Seq.map (fun (KeyValue (cname, target)) ->
                    WellKnownCname.Parse cname, WellKnownCnameTarget.Deserialise target
                )
                |> Map.ofSeq
            Subdomains =
                match config.Subdomains with
                | null -> Set.empty
                | subdomains -> subdomains |> Seq.map WellKnownSubdomain.Parse |> Set.ofSeq
            AcmeEmail = config.AcmeEmail |> EmailAddress
            RemoteUsername = config.RemoteUsername |> Username
        }

[<RequireQualifiedAccess>]
module Configuration =

    let get (configFile : Stream) : Configuration =
        use reader = new StreamReader (configFile)

        JsonConvert.DeserializeObject<SerialisedConfig> (reader.ReadToEnd ())
        |> SerialisedConfig.Deserialise
