namespace PulumiWebServer

open System
open Nager.PublicSuffix
open Newtonsoft.Json
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
            FileInfo("/Users/patrick/Documents/GitHub/Pulumi/PulumiWebServer/Nix/config.json")
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
                    |> DigitalOcean.makeNixosServer config.Name Region.LON1

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

                let readyCommand = Server.waitForReady 1 config.PrivateKey address
                let! _ = readyCommand.Stdout

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

                // Pull the configuration files down.
                let pullNetworking =
                    Command.pullFile
                        config.PrivateKey
                        address
                        infectNix.Stdout
                        "pull-networking"
                        (BashString.make "/etc/nixos/networking.nix")
                        (BashString.make "/tmp/networking.nix")
                    |> fun c -> c.Stdout

                let pullHardware =
                    Command.pullFile
                        config.PrivateKey
                        address
                        infectNix.Stdout
                        "pull-hardware"
                        (BashString.make "/etc/nixos/hardware-configuration.nix")
                        (BashString.make "/tmp/hardware-configuration.nix")
                    |> fun c -> c.Stdout

                let! _ = pullNetworking
                Log.Info "Networking configuration at /tmp/networking.nix"
                let! _ = pullHardware
                Log.Info "Hardware configuration at /tmp/hardware.nix"

                // TODO: do this properly via Command
                keys
                |> Array.map (fun k -> k.PublicKeyContents)
                |> Array.collect (fun s -> s.Split "\n")
                |> JsonConvert.SerializeObject
                |> fun s -> File.WriteAllText ("/tmp/ssh-keys.json", s)

                Log.Info "Stored SSH keys at /tmp/ssh-keys.json"

                // The nixos rebuild has blatted the known public key.
                let! _ = (Local.forgetKey (address.Get ())).Stdout
                let! _ = (Local.forgetKey (string<DomainName> config.Domain)).Stderr
                let readyCommand = Server.waitForReady 2 config.PrivateKey address

                // Reboot so that we're fully a NixOS system.
                let reboot =
                    Server.reboot "initial-reboot" readyCommand.Stdout config.PrivateKey address

                let! _ = reboot.Stdout

                return address
            }
            |> ignore
        |> Deployment.RunAsync
        |> Async.AwaitTask
        |> Async.RunSynchronously
