namespace PulumiWebServer

open System
open Pulumi
open Pulumi.DigitalOcean
open System.IO

module Program =
    // Anything in this file is expected to be user-configured.
    let PRIVATE_KEY =
        Path.Combine (Environment.GetFolderPath Environment.SpecialFolder.UserProfile, ".ssh", "id_ed25519")

    let ACME_EMAIL =
        "patrick+acme@patrickstevens.co.uk"
        |> EmailAddress

    let DOMAIN = "patrickstevens.co.uk" |> DomainName

    let SUBDOMAINS =
        [
            "staging"
            "www.staging"
            "gitea.staging"
        ]

    let REMOTE_USERNAME = "patrick" |> Username

    let nginxConfig =
        {
            Domain = DOMAIN
            WebSubdomain = "www.staging"
            GiteaSubdomain = "gitea.staging"
            AcmeEmail = ACME_EMAIL
        }

    [<EntryPoint>]
    let main argv =
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
                            Seq.map (fun s -> SshFingerprint s.Fingerprint)
                            >> Array.ofSeq
                        )

                    let! droplet = DigitalOcean.makeNixosServer (keys |> Array.map Input.lift) Region.LON1
                    let! ipv4 = droplet.Ipv4Address
                    let! ipv6 = droplet.Ipv6Address

                    let address =
                        {
                            IPv4 = Option.ofObj ipv4
                            IPv6 = Option.ofObj ipv6
                        }

                    let! zone = Cloudflare.getZone DOMAIN
                    let dns = Cloudflare.addDns SUBDOMAINS zone address
                    let! _ = Server.waitForReady privateKey address

                    let infectNix = Server.infectNix privateKey address
                    let! _ = infectNix.Stdout

                    let nginxConfigFile, tmpFile =
                        Server.writeNginxConfig infectNix.Stdout nginxConfig privateKey address

                    toTidyUp.Add tmpFile

                    let userConfigFile, tmpFile2 =
                        Server.writeUserConfig infectNix.Stdout keys REMOTE_USERNAME privateKey address

                    toTidyUp.Add tmpFile2

                    let giteaConfigFile, tmpFile3 =
                        Server.writeGiteaConfig
                            infectNix.Stdout
                            nginxConfig.GiteaSubdomain
                            nginxConfig.Domain
                            privateKey
                            address

                    toTidyUp.Add tmpFile3

                    // Wait for the config files to be written
                    let! _ = nginxConfigFile.Urn
                    let! _ = giteaConfigFile.Urn
                    let! _ = userConfigFile.Urn

                    let configureNginx = Server.loadNginxConfig nginxConfigFile.Urn privateKey address
                    let configureGitea = Server.loadGiteaConfig configureNginx.Urn privateKey address

                    let configureUsers =
                        Server.loadUserConfig [ OutputCrate.make configureGitea.Urn ] privateKey address

                    let firstReboot =
                        Server.reboot "post-infect" configureUsers.Stdout privateKey address

                    let! _ = firstReboot.Stdout
                    // The nixos rebuild has blatted the known public key.
                    Local.forgetKey address
                    let! _ = Server.waitForReady privateKey address

                    let deps =
                        let dnsDeps =
                            dns
                            |> Map.toList
                            |> List.collect (fun (_, record) -> [ record.IPv4 ; record.IPv6 ])
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
