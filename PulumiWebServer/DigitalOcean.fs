namespace PulumiWebServer

open Pulumi
open System.IO
open Pulumi.DigitalOcean
open Pulumi.DigitalOcean.Outputs

[<RequireQualifiedAccess>]
module DigitalOcean =
    let saveSshKey (PublicKey publicKey) : SshKey =
        let args = SshKeyArgs ()
        args.PublicKey <- File.ReadAllText publicKey.FullName |> Input.lift
        SshKey ("default", args)

    let makeNixosServer (region : Region) (sshKeys : Input<SshFingerprint> []) : Output<Droplet> =
        output {
            let args =
                DropletArgs (Name = Input.lift "nixos-server", Size = InputUnion.liftRight DropletSlug.DropletS1VCPU1GB)

            args.Tags.Add (Input.lift "nixos")
            args.Image <- "ubuntu-22-04-x64" |> Input.lift
            args.Monitoring <- Input.lift false
            args.Backups <- Input.lift false
            args.Ipv6 <- true
            args.Region <- InputUnion.liftRight region
            args.DropletAgent <- Input.lift false
            args.GracefulShutdown <- Input.lift false

            // TODO: for some reason this keeps replacing the keys on second run :(
            args.SshKeys.Add (
                sshKeys
                |> Array.map (Input.map (fun (SshFingerprint s) -> s))
            )

            return Droplet ("nixos-server", args)
        }

    let storedSshKeys (dep : 'a Output) : Output<GetSshKeysSshKeyResult list> =
        let args = GetSshKeysInvokeArgs ()

        output {
            let! _ = dep
            let! keys = GetSshKeys.Invoke args

            return
                keys.SshKeys
                |> Seq.toList
                |> List.sortBy (fun s -> s.Fingerprint)
        }
