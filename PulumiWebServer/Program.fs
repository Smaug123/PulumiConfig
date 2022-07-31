namespace PulumiWebServer

open Pulumi
open Pulumi.DigitalOcean
open System.IO

module Program =

    let config : Configuration =
        {
            PrivateKey =
                FileInfo (failwith "path to private key")
                |> PrivateKey
            PublicKey =
                FileInfo (failwith "path to public key for that private key")
                |> PublicKey
            AcmeEmail = failwith "email address for ACME emails from Let's Encrypt"
            Domain = failwith "domain"
            RemoteUsername = failwith "username on remote machine" |> Username
            GiteaConfig =
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
                |> Some
            NextCloudConfig =
                {
                    ServerPassword =
                        failwith "password for nextcloud user on machine"
                        |> BashString.make
                    AdminPassword =
                        failwith "password for admin user within nextcloud"
                        |> BashString.make
                }
                |> Some
            RadicaleConfig =
                {
                    User = failwith "Username to log in to Radicale"
                    Password = failwith "Password to log in to Radicale"
                }
                |> Some
            Cnames =
                [
                    WellKnownCname.Www, WellKnownCnameTarget.Root
                ]
                |> Map.ofList
            Subdomains =
                [
                    WellKnownSubdomain.Nextcloud, "nextcloud"
                    WellKnownSubdomain.Gitea, "gitea"
                    WellKnownSubdomain.Radicale, "calendar"
                ]
                |> Map.ofList
        }

    [<EntryPoint>]
    let main _argv =
        fun () ->
            output {
                let key = DigitalOcean.saveSshKey config.PublicKey

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

                let! zone = Cloudflare.getZone config.Domain

                let dns =
                    Cloudflare.addDns config.Domain config.Cnames config.Subdomains zone address

                let! _ = Server.waitForReady config.PrivateKey address

                let infectNix = Server.infectNix config.PrivateKey address
                let! _ = infectNix.Stdout

                let initialSetupModules =
                    [
                        Server.configureUser infectNix.Stdout config.RemoteUsername keys config.PrivateKey address
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
                let firstReboot = Server.reboot "post-infect" droplet.Urn config.PrivateKey address
                let! _ = firstReboot.Stdout

                // The nixos rebuild has blatted the known public key.
                Local.forgetKey address
                let! _ = Server.waitForReady config.PrivateKey address

                let modules =
                    [
                        Nginx.configure infectNix.Stdout config.PrivateKey address config.NginxConfig
                        |> Some
                        config.GiteaConfig
                        |> Option.map (
                            Gitea.configure infectNix.Stdout config.Subdomains config.Domain config.PrivateKey address
                        )
                        config.NextCloudConfig
                        |> Option.map (
                            NextCloud.configure
                                infectNix.Stdout
                                config.Subdomains
                                config.Domain
                                config.PrivateKey
                                address
                        )
                        config.RadicaleConfig
                        |> Option.map (
                            Radicale.configure
                                infectNix.Stdout
                                config.Subdomains
                                config.Domain
                                config.PrivateKey
                                address
                        )
                    ]
                    |> List.choose id

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

                let rebuild = Server.nixRebuild deps config.PrivateKey address
                let! _ = rebuild.Stdout
                return ()
            }
            |> ignore
        |> Deployment.RunAsync
        |> Async.AwaitTask
        |> Async.RunSynchronously
