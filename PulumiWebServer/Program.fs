namespace PulumiWebServer

open System
open Pulumi
open Pulumi.DigitalOcean
open System.IO

module Program =
    // Anything in this file is expected to be user-configured.
    let PRIVATE_KEY =
        Path.Combine (Environment.GetFolderPath Environment.SpecialFolder.UserProfile, ".ssh", "id_ed25519")

    let ACME_EMAIL = failwith "email address" |> EmailAddress

    let DOMAIN = failwith "domain" |> DomainName

    let CNAMES =
        [
            WellKnownCname.Www, WellKnownCnameTarget.Root
        ]
        |> Map.ofList

    let SUBDOMAINS =
        [
            WellKnownSubdomain.Nextcloud, "nextcloud"
            WellKnownSubdomain.Gitea, "gitea"
            WellKnownSubdomain.Radicale, "calendar"
        ]
        |> Map.ofList

    let REMOTE_USERNAME = failwith "username" |> Username

    let nginxConfig =
        {
            Domain = DOMAIN
            WebSubdomain = WellKnownCname.Www
            AcmeEmail = ACME_EMAIL
        }

    let GITEA_CONFIG =
        {
            GiteaConfig.ServerPassword =
                failwith "password for the gitea Linux user"
                |> BashString.make
            GiteaConfig.AdminPassword =
                failwith "password for the admin user within gitea"
                |> BashString.make
            GiteaConfig.AdminUsername =
                failwith "username for the admin user within gitea"
                |> BashString.make
            GiteaConfig.AdminEmailAddress =
                failwith "email address for the admin user within gitea"
                |> BashString.make
        }

    let NEXTCLOUD_CONFIG =
        {
            ServerPassword =
                failwith "password for nextcloud user on machine"
                |> BashString.make
            AdminPassword =
                failwith "password for admin user within nextcloud"
                |> BashString.make
        }

    let RADICALE_CONFIG =
        {
            User = failwith "Username to log in to Radicale"
            Password = failwith "Password to log in to Radicale"
        }

    [<EntryPoint>]
    let main _argv =
        let privateKey = FileInfo PRIVATE_KEY |> PrivateKey
        let publicKey = FileInfo (PRIVATE_KEY + ".pub") |> PublicKey

        fun () ->
            output {
                let key = DigitalOcean.saveSshKey publicKey

                let! keys =
                    DigitalOcean.storedSshKeys key.Urn
                    |> Output.map (
                        Seq.map (fun s ->
                            {
                                Fingerprint = SshFingerprint s.Fingerprint
                                PublicKeyContents = s.PublicKey
                            }
                        )
                        >> Array.ofSeq
                    )

                let! droplet =
                    keys
                    |> Array.map (SshKey.fingerprint >> Input.lift)
                    |> DigitalOcean.makeNixosServer Region.LON1

                let! ipv4 = droplet.Ipv4Address
                let! ipv6 = droplet.Ipv6Address

                let address =
                    {
                        IPv4 = Option.ofObj ipv4
                        IPv6 = Option.ofObj ipv6
                    }

                let! zone = Cloudflare.getZone DOMAIN
                let dns = Cloudflare.addDns DOMAIN CNAMES SUBDOMAINS zone address
                let! _ = Server.waitForReady privateKey address

                let infectNix = Server.infectNix privateKey address
                let! _ = infectNix.Stdout

                let initialSetupModules =
                    [
                        Server.configureUser infectNix.Stdout REMOTE_USERNAME keys privateKey address
                    ]

                let! _ =
                    initialSetupModules
                    |> Seq.map (fun m -> m.WriteConfigFile.Stdout)
                    |> Output.sequence
                // Load the configuration
                let! _ =
                    initialSetupModules
                    |> Seq.map (fun m ->
                        m.EnableConfig
                        |> Seq.map (fun c -> c.Stdout)
                        |> Output.sequence
                    )
                    |> Output.sequence

                // If this is a new node, reboot
                let firstReboot = Server.reboot "post-infect" droplet.Urn privateKey address
                let! _ = firstReboot.Stdout

                // The nixos rebuild has blatted the known public key.
                Local.forgetKey address
                let! _ = Server.waitForReady privateKey address

                let modules =
                    [
                        Nginx.configure infectNix.Stdout privateKey address nginxConfig
                        Gitea.configure infectNix.Stdout DOMAIN SUBDOMAINS privateKey address GITEA_CONFIG
                        NextCloud.configure infectNix.Stdout SUBDOMAINS DOMAIN privateKey address NEXTCLOUD_CONFIG
                        Radicale.configure infectNix.Stdout SUBDOMAINS DOMAIN privateKey address RADICALE_CONFIG
                    ]

                let configFiles =
                    modules
                    |> Seq.map (fun m -> m.WriteConfigFile.Stdout)
                    |> Output.sequence

                // Wait for the config files to be written
                let! _ = configFiles

                // Load the configuration
                let _ =
                    modules
                    |> Seq.map (fun m ->
                        m.EnableConfig
                        |> Seq.map (fun c -> c.Stdout)
                        |> Output.sequence
                    )
                    |> Output.sequence

                let deps =
                    let dnsDeps =
                        dns
                        |> Map.toList
                        |> List.collect (fun (_, record) ->
                            match record with
                            | DnsRecord.ARecord record -> [ record.IPv4 ; record.IPv6 ]
                            | DnsRecord.Cname _ -> []
                        )
                        |> List.choose id
                        |> List.map (fun record -> record.Urn |> OutputCrate.make)

                    OutputCrate.make (configFiles |> Output.map List.toArray)
                    :: OutputCrate.make firstReboot.Stdout :: dnsDeps

                let rebuild = Server.nixRebuild deps privateKey address
                let! _ = rebuild.Stdout
                return ()
            }
            |> ignore
        |> Deployment.RunAsync
        |> Async.AwaitTask
        |> Async.RunSynchronously
