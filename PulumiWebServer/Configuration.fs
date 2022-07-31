namespace PulumiWebServer

open System.IO

[<NoComparison>]
type Configuration =
    {
        /// Private key with which to talk to the server
        PrivateKey : PrivateKey
        /// Public key corresponding to the PrivateKey
        PublicKey : PublicKey
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
        Subdomains : Map<WellKnownSubdomain, string>
        /// Linux user to create on the server
        RemoteUsername : Username
        GiteaConfig : GiteaConfig option
        NextCloudConfig : NextCloudConfig option
        RadicaleConfig : RadicaleConfig option
    }

    member this.NginxConfig =
        {
            Domain = this.Domain
            WebSubdomain = WellKnownCname.Www
            AcmeEmail = this.AcmeEmail
        }

[<RequireQualifiedAccess>]
type SerialisedGiteaConfig =
    {
        ServerPassword : string
        AdminPassword : string
        AdminUsername : string
        AdminEmailAddress : string
    }

    static member Make (config : GiteaConfig) =
        {
            SerialisedGiteaConfig.ServerPassword = config.ServerPassword |> BashString.unsafeOriginal
            AdminPassword = config.AdminPassword |> BashString.unsafeOriginal
            AdminUsername = config.AdminUsername |> BashString.unsafeOriginal
            AdminEmailAddress =
                config.AdminEmailAddress
                |> BashString.unsafeOriginal
        }

    static member Deserialise (config : SerialisedGiteaConfig) : GiteaConfig =
        {
            GiteaConfig.ServerPassword = config.ServerPassword |> BashString.make
            AdminPassword = config.AdminPassword |> BashString.make
            AdminUsername = config.AdminUsername |> BashString.make
            AdminEmailAddress = config.AdminEmailAddress |> BashString.make
        }

[<RequireQualifiedAccess>]
type SerialisedNextCloudConfig =
    {
        ServerPassword : string
        AdminPassword : string
    }

    static member Make (config : NextCloudConfig) =
        {
            SerialisedNextCloudConfig.ServerPassword = config.ServerPassword |> BashString.unsafeOriginal
            AdminPassword = config.AdminPassword |> BashString.unsafeOriginal
        }

    static member Deserialise (c : SerialisedNextCloudConfig) : NextCloudConfig =
        {
            NextCloudConfig.ServerPassword = c.ServerPassword |> BashString.make
            AdminPassword = c.AdminPassword |> BashString.make
        }

[<RequireQualifiedAccess>]
type SerialisedRadicaleConfig =
    {
        User : string
        Password : string
    }

    static member Make (config : RadicaleConfig) =
        {
            SerialisedRadicaleConfig.User = config.User
            Password = config.Password
        }

    static member Deserialise (c : SerialisedRadicaleConfig) : RadicaleConfig =
        {
            RadicaleConfig.User = c.User
            Password = c.Password
        }

[<NoComparison>]
[<RequireQualifiedAccess>]
type SerialisedConfig =
    {
        /// Path to private key
        PrivateKey : string
        /// Path to public key
        PublicKey : string
        AcmeEmail : string
        Domain : string
        Cnames : Map<string, string>
        Subdomains : Map<string, string>
        RemoteUsername : string
        GiteaConfig : SerialisedGiteaConfig option
        NextCloudConfig : SerialisedNextCloudConfig option
        RadicaleConfig : SerialisedRadicaleConfig option
    }

    static member Make (config : Configuration) =
        {
            SerialisedConfig.PrivateKey = let (PrivateKey p) = config.PrivateKey in p.FullName
            PublicKey = let (PublicKey p) = config.PublicKey in p.FullName
            AcmeEmail = config.AcmeEmail.ToString ()
            Domain = config.Domain.ToString ()
            Cnames =
                config.Cnames
                |> Map.toSeq
                |> Seq.map (fun (cname, target) -> cname.ToString (), WellKnownCnameTarget.Serialise target)
                |> Map.ofSeq
            Subdomains =
                config.Subdomains
                |> Map.toSeq
                |> Seq.map (fun (sub, value) -> sub.ToString (), value)
                |> Map.ofSeq
            RemoteUsername = config.RemoteUsername.ToString ()
            GiteaConfig =
                config.GiteaConfig
                |> Option.map SerialisedGiteaConfig.Make
            NextCloudConfig =
                config.NextCloudConfig
                |> Option.map SerialisedNextCloudConfig.Make
            RadicaleConfig =
                config.RadicaleConfig
                |> Option.map SerialisedRadicaleConfig.Make
        }

    static member Deserialise (config : SerialisedConfig) : Configuration =
        {
            Configuration.PrivateKey = FileInfo config.PrivateKey |> PrivateKey
            PublicKey = FileInfo config.PublicKey |> PublicKey
            AcmeEmail = config.AcmeEmail |> EmailAddress
            Domain = config.Domain |> DomainName
            Cnames =
                config.Cnames
                |> Map.toSeq
                |> Seq.map (fun (cname, target) -> WellKnownCname.Parse cname, WellKnownCnameTarget.Deserialise target)
                |> Map.ofSeq
            Subdomains =
                config.Subdomains
                |> Map.toSeq
                |> Seq.map (fun (sub, value) -> WellKnownSubdomain.Parse sub, value)
                |> Map.ofSeq
            RemoteUsername = config.RemoteUsername |> Username
            GiteaConfig =
                config.GiteaConfig
                |> Option.map SerialisedGiteaConfig.Deserialise
            NextCloudConfig =
                config.NextCloudConfig
                |> Option.map SerialisedNextCloudConfig.Deserialise
            RadicaleConfig =
                config.RadicaleConfig
                |> Option.map SerialisedRadicaleConfig.Deserialise
        }
