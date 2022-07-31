namespace Pulumi

open Pulumi

[<RequireQualifiedAccess>]
module Input =

    let lift<'a> (x : 'a) : 'a Input = Input.op_Implicit x
    let ofOutput<'a> (x : 'a Output) : 'a Input = Input.op_Implicit x
    let map<'a, 'b> (f : 'a -> 'b) (x : Input<'a>) : Input<'b> = x.Apply f |> ofOutput

[<RequireQualifiedAccess>]
module Output =

    let map<'a, 'b> (f : 'a -> 'b) (x : 'a Output) : 'b Output = x.Apply f

    let sequence<'a> (xs : 'a Output seq) : 'a list Output =
        let func (o : 'a list Output) (x : 'a Output) : 'a list Output =
            o.Apply<'a list> (fun o -> x.Apply<'a list> (fun x -> x :: o))

        xs
        |> Seq.fold func (Output.Create [])
        |> map List.rev

type OutputEvaluator<'ret> =
    abstract Eval<'a> : Output<'a> -> 'ret

type OutputCrate =
    abstract Apply<'ret> : OutputEvaluator<'ret> -> 'ret

[<RequireQualifiedAccess>]
module OutputCrate =
    let make<'a> (o : Output<'a>) =
        { new OutputCrate with
            member _.Apply e = e.Eval o
        }

    // Yuck but this is the type signature we need for consumption by Pulumi
    let sequence (xs : OutputCrate seq) : obj list Output =
        let func (o : obj list Output) (x : OutputCrate) : obj list Output =
            { new OutputEvaluator<_> with
                member _.Eval<'a> (x : 'a Output) =
                    o.Apply<obj list> (fun o -> x.Apply<obj list> (fun x -> unbox<obj> x :: o))
            }
            |> x.Apply

        xs
        |> Seq.fold func (Output.Create [])
        |> Output.map List.rev

[<RequireQualifiedAccess>]
module InputList =
    let ofOutput<'a> (x : 'a seq Output) : 'a InputList = InputList.op_Implicit x

    let lift<'a> (x : 'a seq) : 'a InputList =
        x |> Seq.toArray |> InputList.op_Implicit

[<RequireQualifiedAccess>]
module InputUnion =
    let liftLeft<'a, 'b> (x : 'a) : InputUnion<'a, 'b> = InputUnion.op_Implicit x

    let liftRight<'a, 'b> (x : 'b) : InputUnion<'a, 'b> = InputUnion.op_Implicit x

type OutputComputation() =
    member _.Bind (x : Output<'a>, f : 'a -> Output<'b>) : Output<'b> = x.Apply<'b> f
    member _.Return (x : 'a) : Output<'a> = Output.Create<'a> x
    member _.ReturnFrom (x : 'a Output) = x

[<AutoOpen>]
module ComputationExpressions =
    let output = OutputComputation ()
