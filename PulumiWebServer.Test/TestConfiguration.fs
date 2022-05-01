namespace PulumiWebServer.Test

open System
open System.IO
open NUnit.Framework
open FsCheck
open FsUnitTyped
open PulumiWebServer

[<TestFixture>]
module TestConfiguration =

    let fileInfoGenerator =
        gen {
            let! fileName = Gen.choose (65, 90) |> Gen.map char |> Gen.arrayOf
            return FileInfo (Path.Combine ("/tmp", String fileName))
        }

    let bashStringGenerator =
        gen {
            let! s = Arb.generate<string>
            return BashString.make s
        }

    let radicaleConfigGen =
        gen {
            let! password = Arb.generate<string>
            let! username = Arb.generate<string>
            let! optionValue = Arb.generate<bool>

            if optionValue then
                let! (NonNull s) = Arb.generate<NonNull<string>>

                return
                    {
                        RadicaleConfig.User = username
                        RadicaleConfig.Password = password
                        RadicaleConfig.GitEmail = Some s
                    }
            else
                return
                    {
                        RadicaleConfig.User = username
                        RadicaleConfig.Password = password
                        RadicaleConfig.GitEmail = None
                    }
        }

    type MyGenerators =
        static member FileInfo () =
            { new Arbitrary<FileInfo>() with
                override x.Generator = fileInfoGenerator
                override x.Shrinker t = Seq.empty
            }

        static member BashString () =
            { new Arbitrary<BashString>() with
                override x.Generator = bashStringGenerator
                override x.Shrinker t = Seq.empty
            }

        static member RadicaleConfig () =
            { new Arbitrary<RadicaleConfig>() with
                override x.Generator = radicaleConfigGen
                override x.Shrinker t = Seq.empty
            }

    [<Test>]
    let ``Serialisation round-trip`` () =
        Arb.register<MyGenerators> () |> ignore

        let property (c : Configuration) : bool =
            let serialised = SerialisedConfig.Make c
            let roundTripped = SerialisedConfig.Deserialise serialised
            c = roundTripped

        property |> Check.QuickThrowOnFailure

    [<Test>]
    let ``Specific example`` () =
        let config =
            {
                Name = ""
                PrivateKey = PrivateKey (FileInfo "/tmp")
                PublicKeyOverride = None
                AcmeEmail = EmailAddress ""
                Domain = DomainName ""
                Cnames = Map.empty
                Subdomains = Set.empty
                RemoteUsername = Username ""
                GiteaConfig = None
                RadicaleConfig =
                    Some
                        {
                            User = ""
                            Password = ""
                            GitEmail = None
                        }
            }

        let serialised = SerialisedConfig.Make config
        let roundTripped = SerialisedConfig.Deserialise serialised
        config |> shouldEqual roundTripped
