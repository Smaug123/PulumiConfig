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
        /// Email address to which Let's Encrypt is to send emails
        AcmeEmail : EmailAddress
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
        /// Linux user to create on the server
        RemoteUsername : Username
        GiteaConfig : GiteaConfig option
        RadicaleConfig : RadicaleConfig option
    }

    member this.NginxConfig =
        {
            Domain = this.Domain
            WebSubdomain = WellKnownCname.Www
            AcmeEmail = this.AcmeEmail
        }

    member this.PublicKey =
        match this.PublicKeyOverride with
        | Some k -> k
        | None ->
            let (PrivateKey k) = this.PrivateKey
            Path.Combine (k.Directory.FullName, k.Name + ".pub") |> FileInfo |> PublicKey

[<RequireQualifiedAccess>]
[<Struct>]
type SerialisedGiteaConfig =
    {
        [<JsonProperty(Required = Required.Always)>]
        ServerPassword : string
        [<JsonProperty(Required = Required.Always)>]
        AdminPassword : string
        [<JsonProperty(Required = Required.Always)>]
        AdminUsername : string
        [<JsonProperty(Required = Required.Always)>]
        AdminEmailAddress : string
    }

    static member Make (config : GiteaConfig) =
        {
            SerialisedGiteaConfig.ServerPassword = config.ServerPassword |> BashString.unsafeOriginal
            AdminPassword = config.AdminPassword |> BashString.unsafeOriginal
            AdminUsername = config.AdminUsername |> BashString.unsafeOriginal
            AdminEmailAddress = config.AdminEmailAddress |> BashString.unsafeOriginal
        }

    static member Deserialise (config : SerialisedGiteaConfig) : GiteaConfig =
        {
            GiteaConfig.ServerPassword = config.ServerPassword |> BashString.make
            AdminPassword = config.AdminPassword |> BashString.make
            AdminUsername = config.AdminUsername |> BashString.make
            AdminEmailAddress = config.AdminEmailAddress |> BashString.make
        }

[<RequireQualifiedAccess>]
[<Struct>]
type SerialisedRadicaleConfig =
    {
        [<JsonProperty(Required = Required.Always)>]
        User : string
        [<JsonProperty(Required = Required.Always)>]
        Password : string
        [<JsonProperty(Required = Required.DisallowNull)>]
        GitEmail : string
    }

    static member Make (config : RadicaleConfig) =
        {
            SerialisedRadicaleConfig.User = config.User
            Password = config.Password
            GitEmail = config.GitEmail |> Option.toObj
        }

    static member Deserialise (c : SerialisedRadicaleConfig) : RadicaleConfig =
        {
            RadicaleConfig.User = c.User
            Password = c.Password
            GitEmail = c.GitEmail |> Option.ofObj
        }

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
        AcmeEmail : string
        [<JsonProperty(Required = Required.Always)>]
        Domain : string
        [<JsonProperty(Required = Required.Always)>]
        Cnames : Dictionary<string, string>
        [<JsonProperty(Required = Required.DisallowNull)>]
        Subdomains : string[]
        [<JsonProperty(Required = Required.Always)>]
        RemoteUsername : string
        GiteaConfig : Nullable<SerialisedGiteaConfig>
        RadicaleConfig : Nullable<SerialisedRadicaleConfig>
    }

    static member Make (config : Configuration) =
        {
            SerialisedConfig.PrivateKey = let (PrivateKey p) = config.PrivateKey in p.FullName
            Name = config.Name
            PublicKey =
                match config.PublicKeyOverride with
                | None -> null
                | Some (PublicKey p) -> p.FullName
            AcmeEmail = config.AcmeEmail.ToString ()
            Domain = config.Domain.ToString ()
            Cnames =
                config.Cnames
                |> Map.toSeq
                |> Seq.map (fun (cname, target) ->
                    KeyValuePair (cname.ToString (), WellKnownCnameTarget.Serialise target)
                )
                |> Dictionary
            Subdomains = config.Subdomains |> Seq.map (fun sub -> sub.ToString ()) |> Seq.toArray
            RemoteUsername = config.RemoteUsername.ToString ()
            GiteaConfig = config.GiteaConfig |> Option.map SerialisedGiteaConfig.Make |> Option.toNullable
            RadicaleConfig =
                config.RadicaleConfig
                |> Option.map SerialisedRadicaleConfig.Make
                |> Option.toNullable
        }

    static member Deserialise (config : SerialisedConfig) : Configuration =
        {
            Configuration.PrivateKey = FileInfo config.PrivateKey |> PrivateKey
            Name = config.Name
            PublicKeyOverride =
                match config.PublicKey with
                | null -> None
                | key -> FileInfo key |> PublicKey |> Some
            AcmeEmail = config.AcmeEmail |> EmailAddress
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
            RemoteUsername = config.RemoteUsername |> Username
            GiteaConfig =
                config.GiteaConfig
                |> Option.ofNullable
                |> Option.map SerialisedGiteaConfig.Deserialise
            RadicaleConfig =
                config.RadicaleConfig
                |> Option.ofNullable
                |> Option.map SerialisedRadicaleConfig.Deserialise
        }

[<RequireQualifiedAccess>]
module Configuration =

    let get (configFile : Stream) : Configuration =
        use reader = new StreamReader (configFile)

        JsonConvert.DeserializeObject<SerialisedConfig> (reader.ReadToEnd ())
        |> SerialisedConfig.Deserialise
