namespace PulumiWebServer

open Pulumi
open Pulumi.Command.Local

[<RequireQualifiedAccess>]
module Local =
    let forgetKey (address : string) : Command =
        let args = CommandArgs ()
        args.Create <- Input.lift $"/usr/bin/ssh-keygen -R {address} || exit 0"

        Command ($"forget-key-{address}", args)
