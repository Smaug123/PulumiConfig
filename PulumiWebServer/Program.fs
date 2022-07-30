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

    let SUBDOMAINS = [ WellKnownSubdomain.Nextcloud, "nextcloud" ] |> Map.ofList

    let REMOTE_USERNAME = failwith "username" |> Username

    let nginxConfig =
        {
            Domain = DOMAIN
            WebSubdomain = WellKnownCname.Www
            AcmeEmail = ACME_EMAIL
        }

    let NEXTCLOUD_CONFIG =
        {
            ServerPassword = failwith "password for nextcloud user on machine" |> BashString.make
            AdminPassword = failwith "password for admin user within nextcloud" |> BashString.make
        }

    [<EntryPoint>]
    let main _argv =
        let toTidyUp = ResizeArray ()
        let privateKey = FileInfo PRIVATE_KEY |> PrivateKey
        let publicKey = FileInfo (PRIVATE_KEY + ".pub") |> PublicKey

        let output =
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
                        DigitalOcean.makeNixosServer
                            (keys
                             |> Array.map (SshKey.fingerprint >> Input.lift))
                            Region.LON1

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

                    let nginxConfigFile, tmpFile =
                        Server.writeNginxConfig infectNix.Stdout nginxConfig privateKey address

                    toTidyUp.Add tmpFile

                    let userConfigFile, tmpFile2 =
                        Server.writeUserConfig infectNix.Stdout keys REMOTE_USERNAME privateKey address

                    toTidyUp.Add tmpFile2

                    let nextCloudConfig, tmpFile3 =
                        Server.writeNextCloudConfig infectNix.Stdout SUBDOMAINS DOMAIN privateKey address
                    toTidyUp.Add tmpFile3

                    // Wait for the config files to be written
                    let! _ = nginxConfigFile.Urn
                    let! _ = userConfigFile.Urn
                    let! _ = nextCloudConfig.Urn

                    let configureNginx = Server.loadNginxConfig nginxConfigFile.Urn privateKey address

                    let configureUsers =
                        Server.loadUserConfig [ OutputCrate.make configureNginx.Urn ] privateKey address

                    let configureNextcloud =
                        Server.loadNextCloudConfig
                            configureUsers.Urn
                            privateKey
                            address
                            NEXTCLOUD_CONFIG

                    let firstReboot =
                        Server.reboot "post-infect" (configureNextcloud |> List.map (fun o -> OutputCrate.make o.Stdout)) privateKey address

                    let! _ = firstReboot.Stdout
                    // The nixos rebuild has blatted the known public key.
                    Local.forgetKey address
                    let! _ = Server.waitForReady privateKey address

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

                        OutputCrate.make firstReboot.Stdout :: dnsDeps

                    let rebuild = Server.nixRebuild deps privateKey address
                    let! _ = rebuild.Stdout
                    return tmpFile, tmpFile2
                }
                |> ignore
            |> Deployment.RunAsync
            |> Async.AwaitTask
            |> Async.RunSynchronously

        for file in toTidyUp do
            printfn $"Now delete file {file.FullName}"

        output
