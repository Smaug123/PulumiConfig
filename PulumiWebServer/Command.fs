namespace PulumiWebServer

open System.IO
open Pulumi
open Pulumi.Command.Remote

[<RequireQualifiedAccess>]
module Command =

    let connection (privateKey : FileInfo) (address : Address) =
        let inputArgs = Inputs.ConnectionArgs ()

        inputArgs.Host <- address.Get () |> Input.lift

        inputArgs.Port <- Input.lift 22
        inputArgs.User <- Input.lift "root"

        inputArgs.PrivateKey <- File.ReadAllText privateKey.FullName |> Output.CreateSecret |> Input.ofOutput

        inputArgs |> Output.CreateSecret |> Input.ofOutput

    let pullFile
        (PrivateKey privateKey)
        (address : Address)
        (trigger : Output<'a>)
        (commandName : string)
        (remotePath : BashString)
        (destPath : BashString)
        : Pulumi.Command.Local.Command
        =
        let args = Pulumi.Command.Local.CommandArgs ()

        args.Triggers <- trigger |> Output.map (unbox<obj> >> Seq.singleton) |> InputList.ofOutput

        let argsString =
            $"scp -i {privateKey.FullName} root@{address.Get ()}:{remotePath} {destPath}"

        args.Create <- Input.ofOutput (Output.CreateSecret argsString)

        Pulumi.Command.Local.Command (commandName, args)
