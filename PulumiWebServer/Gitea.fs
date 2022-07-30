namespace PulumiWebServer

[<RequireQualifiedAccess>]
type GiteaConfig =
    {
        ServerPassword : BashString
        AdminPassword : BashString
        AdminUsername : BashString
        AdminEmailAddress : BashString
    }
