namespace PulumiWebServer

open System.IO
open Pulumi
open Pulumi.Command.Remote

[<RequireQualifiedAccess>]
module Command =

    let deleteBeforeReplace =
        CustomResourceOptions (DeleteBeforeReplace = System.Nullable true)

    let createSecretFile (args : CommandArgs) (username : string) (toWrite : BashString) (filePath : string) : unit =
        if filePath.Contains "'" then
            failwith $"filepath contained quote: {filePath}"

        if username.Contains "'" then
            failwith $"username contained quote: {username}"

        let argsString =
            $"""OLD_UMASK=$(umask) && \
umask 077 && \
mkdir -p "$(dirname {filePath})" && \
echo {toWrite} > '{filePath}' && \
chown '{username}' '{filePath}' && \
umask "$OLD_UMASK"
"""

        args.Create <- Input.ofOutput (Output.CreateSecret argsString)
        args.Delete <- $"rm -f '{filePath}'"

    let connection (privateKey : FileInfo) (address : Address) =
        let inputArgs = Inputs.ConnectionArgs ()

        inputArgs.Host <-
            address.IPv4
            |> Option.defaultWith (fun () -> Option.get address.IPv6)
            |> Input.lift

        inputArgs.Port <- Input.lift 22
        inputArgs.User <- Input.lift "root"

        inputArgs.PrivateKey <- File.ReadAllText privateKey.FullName |> Output.CreateSecret |> Input.ofOutput

        inputArgs |> Output.CreateSecret |> Input.ofOutput

    let contentAddressedCopy
        (PrivateKey privateKey)
        (address : Address)
        (name : string)
        (trigger : Output<'a>)
        (targetPath : string)
        (fileContents : string)
        : Command
        =
        let args = CommandArgs ()
        args.Connection <- connection privateKey address

        args.Triggers <- trigger |> Output.map (unbox<obj> >> Seq.singleton) |> InputList.ofOutput

        // TODO - do this by passing into stdin instead
        if targetPath.Contains '\'' || targetPath.Contains '\n' then
            failwith $"Can't copy a file to a location with a quote mark in, got: {targetPath}"

        let delimiter = "EOF"

        if fileContents.Contains delimiter then
            failwith "String contained delimiter; please implement something better"

        let commandString =
            [
                $"mkdir -p \"$(dirname {targetPath})\" && \\"
                "{"
                $"cat <<'{delimiter}'"
                fileContents
                delimiter
                sprintf "} | tee '%s'" targetPath
            ]
            |> String.concat "\n"
            |> Output.CreateSecret

        args.Create <- commandString
        args.Delete <- $"rm -f '{targetPath}'"

        Command (name, args, deleteBeforeReplace)

    let addToNixFileCommand (args : CommandArgs) (filename : string) : unit =
        args.Create <-
            $"""while ! ls /preserve/nixos/configuration.nix; do sleep 5; done
sed -i '4i\
    ./{filename}' /preserve/nixos/configuration.nix"""

        args.Delete <- $"""sed -i -n '/{filename}/!p' /preserve/nixos/configuration.nix || exit 0"""
