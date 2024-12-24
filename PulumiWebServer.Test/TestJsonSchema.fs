namespace PulumiWebServer.Test

open System.IO
open System.Reflection
open PulumiWebServer
open NJsonSchema.Validation
open NUnit.Framework
open FsUnitTyped
open NJsonSchema
open Newtonsoft.Json
open Newtonsoft.Json.Serialization

[<TestFixture>]
module TestSchema =

    [<Test>]
    let ``Example conforms to schema`` () =
        let executing = Assembly.GetExecutingAssembly().Location |> FileInfo

        let schemaFile =
            Utils.findFileAbove "PulumiWebServer/config.schema.json" executing.Directory

        let schema = JsonSchema.FromJsonAsync(File.ReadAllText schemaFile.FullName).Result

        let json = Utils.getEmbeddedResource typeof<Utils.Dummy>.Assembly "config.json"

        let validator = JsonSchemaValidator ()
        let errors = validator.Validate (json, schema)

        errors |> shouldBeEmpty

    [<Test>]
    let ``Example can be loaded`` () =
        let config = Utils.getEmbeddedResource typeof<Utils.Dummy>.Assembly "config.json"

        use stream = new MemoryStream ()

        do
            let writer = new StreamWriter (stream)
            writer.WriteLine config
            writer.Flush ()

        stream.Seek (0L, SeekOrigin.Begin) |> ignore
        Configuration.get stream |> ignore

    [<Test>]
    [<Explicit "Run this to regenerate the schema file">]
    let ``Update schema file`` () =
        let schemaFile =
            Assembly.GetExecutingAssembly().Location
            |> FileInfo
            |> fun fi -> fi.Directory
            |> Utils.findFileAbove "PulumiWebServer/config.schema.json"

        let settings =
            NJsonSchema.NewtonsoftJson.Generation.NewtonsoftJsonSchemaGeneratorSettings ()

        settings.SerializerSettings <-
            JsonSerializerSettings (ContractResolver = CamelCasePropertyNamesContractResolver ())

        let schema = JsonSchema.FromType (typeof<SerialisedConfig>, settings)

        File.WriteAllText (schemaFile.FullName, schema.ToJson ())
