namespace PulumiWebServer

open System.IO
open System.Reflection
open Pulumi
open Pulumi.Command.Remote

[<RequireQualifiedAccess>]
module Server =

    let waitForReady (id : int) (PrivateKey privateKey) (address : Address) : Pulumi.Command.Local.Command =
        let args = Pulumi.Command.Local.CommandArgs ()
        args.Create <- Input.lift $"/bin/sh waitforready.sh {address.Get ()} {privateKey.FullName}"
        args.Dir <- Input.lift (FileInfo(Assembly.GetExecutingAssembly().Location).Directory.FullName)
        Pulumi.Command.Local.Command ($"wait-for-ready-{id}", args)

    let infectNix (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address

        // IMPORTANT NOTE: do not inline this script. It is licensed under the GPL, so we
        // must invoke it without "establishing intimate communication" with it.
        // https://www.gnu.org/licenses/gpl-faq.html#GPLPlugins
        args.Create <-
            """if ! ls /run/current-system 1>/dev/null; then
    curl https://raw.githubusercontent.com/elitak/nixos-infect/318fc516d1d87410fd06178331a9b2939b9f2fef/nixos-infect > /tmp/infect.sh || exit 1
    while ! NO_REBOOT=1 PROVIDER=digitalocean NIX_CHANNEL=nixos-22.05 bash /tmp/infect.sh 2>&1 1>/tmp/infect.log; do
      sleep 5;
    done
fi && mkdir -p /preserve/nixos && cp /etc/nixos/* /preserve/nixos && touch /preserve/ready.txt && date"""

        Command ("nix-infect", args)

    let reboot (stage : string) (onChange : Output<'a>) (PrivateKey privateKey) (address : Address) =
        let args = CommandArgs ()
        args.Connection <- Command.connection privateKey address

        args.Triggers <- InputList.ofOutput<obj> (onChange |> Output.map (unbox<obj> >> Seq.singleton))

        args.Create <-
            "while ! ls /preserve/ready.txt ; do sleep 10; done && rm -f /preserve/ready.txt && shutdown -r now"

        Command ($"reboot-{stage}", args)
