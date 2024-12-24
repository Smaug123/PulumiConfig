namespace PulumiWebServer.Test

open System
open System.IO
open NUnit.Framework
open FsCheck
open FsCheck.FSharp
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
            let! s = ArbMap.defaults |> ArbMap.generate<string>
            return BashString.make s
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

    [<Test>]
    let ``Serialisation round-trip`` () =
        let arbMap =
            ArbMap.defaults
            |> ArbMap.mergeArb
                { new Arbitrary<FileInfo>() with
                    override x.Generator = fileInfoGenerator
                    override x.Shrinker t = Seq.empty
                }
            |> ArbMap.mergeArb
                { new Arbitrary<BashString>() with
                    override x.Generator = bashStringGenerator
                    override x.Shrinker t = Seq.empty
                }

        let property (c : Configuration) : bool =
            let serialised = SerialisedConfig.Make c
            let roundTripped = SerialisedConfig.Deserialise serialised
            c = roundTripped

        Check.One (Config.QuickThrowOnFailure, Prop.forAll (arbMap.ArbFor<_> ()) property)

    [<Test>]
    let ``Specific example`` () =
        let publicConfig =
            {
                Name = ""
                PrivateKey = PrivateKey (FileInfo "/tmp")
                PublicKeyOverride = None
                Domain = DomainName ""
                Cnames = Map.empty
                Subdomains = Set.empty
                AcmeEmail = EmailAddress "test@example.com"
                RemoteUsername = Username "non-root"
            }

        let serialised = SerialisedConfig.Make publicConfig
        let roundTripped = SerialisedConfig.Deserialise serialised
        publicConfig |> shouldEqual roundTripped
