namespace PulumiWebServer

open System
open Pulumi
open Pulumi.DigitalOcean
open System.IO

module Program =
    // Anything in this file is expected to be user-configured.
    let PRIVATE_KEY = Path.Combine (Environment.GetFolderPath Environment.SpecialFolder.UserProfile, ".ssh", "id_ed25519")

    let ACME_EMAIL =
        failwith "enter an ACME email address here"
        |> EmailAddress

    let DOMAIN =
        failwith "enter your domain here"
        |> DomainName

    let SUBDOMAIN = "staging"

    let REMOTE_USERNAME =
        failwith "enter your username here"
        |> Username

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
                        |> Output.map (Seq.map (fun s -> SshFingerprint s.Fingerprint) >> Array.ofSeq)
                    let! droplet = DigitalOcean.makeNixosServer (keys |> Array.map Input.lift) Region.LON1
                    let! ipv4 = droplet.Ipv4Address
                    let! ipv6 = droplet.Ipv6Address
                    let address =
                        {
                            IPv4 = Option.ofObj ipv4
                            IPv6 = Option.ofObj ipv6
                        }
                    let! zone = Cloudflare.getZone DOMAIN
                    let dns = Cloudflare.addDns SUBDOMAIN zone address
                    let! _ = Server.waitForReady privateKey address

                    let infectNix = Server.infectNix privateKey address
                    let! _ = infectNix.Stdout
                    let nginxConfig, tmpFile = Server.writeNginxConfig infectNix.Stdout SUBDOMAIN DOMAIN ACME_EMAIL privateKey address
                    toTidyUp.Add tmpFile
                    let userConfig, tmpFile2 = Server.writeUserConfig infectNix.Stdout keys REMOTE_USERNAME privateKey address
                    toTidyUp.Add tmpFile2
                    let! _ = nginxConfig.Urn
                    let configureNginx = Server.loadNginxConfig nginxConfig.Urn privateKey address
                    let! _ = configureNginx.Urn
                    let! _ = userConfig.Urn
                    let configureUsers = Server.loadUserConfig [OutputCrate.make userConfig.Urn ; OutputCrate.make configureNginx.Urn] privateKey address

                    let firstReboot = Server.reboot "post-infect" configureUsers.Stdout privateKey address
                    let! _ = firstReboot.Stdout
                    // The nixos rebuild has blatted the known public key.
                    Local.forgetKey address
                    let! _ = Server.waitForReady privateKey address
                    let deps =
                        [
                            Some (OutputCrate.make firstReboot.Stdout)
                            fst dns |> Option.map (fun record -> record.Urn |> OutputCrate.make)
                            snd dns |> Option.map (fun record -> record.Urn |> OutputCrate.make)
                        ]
                        |> List.choose id
                    let rebuild = Server.nixRebuild deps privateKey address
                    let! _ = rebuild.Stdout
                    return tmpFile, tmpFile2
                }
                |> ignore
            |> Deployment.RunAsync
            |> Async.AwaitTask
            |> Async.RunSynchronously

        for file in toTidyUp do printfn $"Now delete file {file.FullName}"

        output
