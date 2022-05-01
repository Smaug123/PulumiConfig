namespace PulumiWebServer

open System
open Nager.PublicSuffix
open Pulumi
open Pulumi.DigitalOcean
open System.IO

module Program =

    let stripSubdomain (DomainName str) =
        let parser = DomainParser (WebTldRuleProvider ())
        let info = parser.Parse str
        $"{info.Domain}.{info.TLD}" |> DomainName

    let config =
        use file =
            FileInfo("/Users/patrick/Documents/GitHub/WebsiteConfig/config.json")
                .OpenRead ()

        Configuration.get file

    [<EntryPoint>]
    let main _argv =
        fun () ->
            output {
                let! existingKeys = DigitalOcean.storedSshKeys (Output.Create "")

                let keyContents =
                    let (PublicKey file) = config.PublicKey
                    File.ReadAllText file.FullName

                let key =
                    existingKeys
                    |> Seq.filter (fun key -> key.PublicKey = keyContents)
                    |> Seq.tryHead

                let key =
                    match key with
                    | None -> (DigitalOcean.saveSshKey config.PublicKey).Name
                    | Some key -> Output.Create key.Name

                let! keys =
                    DigitalOcean.storedSshKeys key
                    |> Output.map (
                        Seq.map (fun s ->
                            {
                                Fingerprint = SshFingerprint s.Fingerprint
                                PublicKeyContents = s.PublicKey
                            }
                        )
                        >> Seq.sort
                        >> Array.ofSeq
                    )

                let! droplet =
                    keys
                    |> Array.map (SshKey.fingerprint >> Input.lift)
                    |> DigitalOcean.makeNixosServer "server-staging" Region.LON1

                let! ipv4 = droplet.Ipv4Address
                let! ipv6 = droplet.Ipv6Address

                let address =
                    {
                        IPv4 = Option.ofObj ipv4
                        IPv6 = Option.ofObj ipv6
                    }

                let! zone = Cloudflare.getZone (stripSubdomain config.Domain)

                let dns =
                    Cloudflare.addDns config.Domain config.Cnames config.Subdomains zone address

                let! _ = Server.waitForReady config.PrivateKey address

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
                        |> List.map (fun record -> record.Urn)

                    dnsDeps |> Output.sequence |> Output.map (String.concat ",")

                let! _ = deps

                let infectNix = Server.infectNix config.PrivateKey address
                let! _ = infectNix.Stdout

                // The nixos rebuild has blatted the known public key.
                Local.forgetKey address
                let! _ = Server.waitForReady config.PrivateKey address

                let initialSetupModules =
                    [
                        yield Server.configureUser infectNix.Stdout config.RemoteUsername keys config.PrivateKey address
                        yield! Server.writeFlake infectNix.Stdout config.PrivateKey address
                    ]

                let! _ =
                    initialSetupModules
                    |> Seq.map (fun m -> m.WriteConfigFile.Stdout)
                    |> Output.sequence
                // Load the configuration
                let setup =
                    initialSetupModules
                    |> Seq.map (fun m ->
                        m.EnableConfig
                        |> Seq.map (fun c -> c.Stdout)
                        |> Output.sequence
                        |> Output.map (String.concat "\n---\n")
                    )
                    |> Output.sequence
                    |> Output.map (String.concat "\n===\n")

                let rebuild = Server.nixRebuild 0 setup config.PrivateKey address
                let! _ = rebuild.Stdout

                // If this is a new node, reboot
                let firstReboot = Server.reboot "post-infect" droplet.Urn config.PrivateKey address
                let! _ = firstReboot.Stdout

                let! _ = Server.waitForReady config.PrivateKey address

                let copyPreserve = Server.copyPreserve config.PrivateKey address
                let! _ = copyPreserve.Stdout

                let modules =
                    [
                        Nginx.configure copyPreserve.Stdout config.PrivateKey address config.NginxConfig
                        |> Some
                        config.GiteaConfig
                        |> Option.map (Gitea.configure copyPreserve.Stdout config.Domain config.PrivateKey address)
                        config.RadicaleConfig
                        |> Option.map (Radicale.configure copyPreserve.Stdout config.Domain config.PrivateKey address)
                    ]
                    |> List.choose id

                let configFiles =
                    modules |> Seq.map (fun m -> m.WriteConfigFile.Stdout) |> Output.sequence

                // Wait for the config files to be written
                let! _ = configFiles

                // Load the configuration
                let modules =
                    modules
                    |> Seq.map (fun m ->
                        m.EnableConfig
                        |> Seq.map (fun c -> c.Stdout)
                        |> Output.sequence
                        |> Output.map (String.concat "\n---\n")
                    )
                    |> Output.sequence
                    |> Output.map (String.concat "\n===\n")

                let rebuild = Server.nixRebuild 1 modules config.PrivateKey address
                let! _ = rebuild.Stdout

                return ()
            }
            |> ignore
        |> Deployment.RunAsync
        |> Async.AwaitTask
        |> Async.RunSynchronously
