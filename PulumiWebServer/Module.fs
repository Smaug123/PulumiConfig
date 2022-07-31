namespace PulumiWebServer

open Pulumi.Command.Remote

type Module =
    {
        /// This is expected to be able to run in parallel with any
        /// other Module.
        WriteConfigFile : Command
        /// This is expected to be able to run in parallel with any
        /// other Module. TODO actually it's not?
        EnableConfig : Command list
    }
