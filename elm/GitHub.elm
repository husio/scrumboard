module GitHub exposing (..)

import Json.Decode exposing (field)
import Json.Decode.Pipeline
import Http
import Regex


type alias Repository =
    { name : String
    , fullName : String
    , private : Bool
    , owner : User
    }


type alias Issue =
    { id : Int
    , htmlUrl : String
    , title : String
    , state : String
    , comments : Int
    , body : String
    , labels : List IssueLabel
    , url : String
    , assignees : List User
    }


type alias User =
    { id : Int
    , login : String
    , avatarUrl : String
    }


type alias IssueLabel =
    { name : String
    , color : String
    , url : String
    }


fetchUserRepos : String -> (Result Http.Error (List Repository) -> msg) -> Cmd msg
fetchUserRepos githubAccessKey msg =
    let
        url =
            "https://api.github.com/user/repos?access_token=" ++ githubAccessKey
    in
        Http.send msg (Http.get url (Json.Decode.list decodeRespository))


decodeRespository : Json.Decode.Decoder Repository
decodeRespository =
    Json.Decode.map4 Repository
        (field "name" Json.Decode.string)
        (field "full_name" Json.Decode.string)
        (field "private" Json.Decode.bool)
        (field "owner" decodeUser)


fetchIssue : String -> String -> String -> Int -> (Result Http.Error Issue -> msg) -> Cmd msg
fetchIssue accessToken organization repo issueId msg =
    let
        url =
            "https://api.github.com/repos/" ++ organization ++ "/" ++ repo ++ "/issues/" ++ (toString issueId) ++ "?access_token=" ++ accessToken
    in
        Http.send msg (Http.get url decodeIssue)


fetchIssueUrl : String -> String -> (Result Http.Error Issue -> msg) -> Cmd msg
fetchIssueUrl token cardUrl msg =
    let
        url =
            cardUrl ++ "?access_token=" ++ token
    in
        Http.send msg (Http.get url decodeIssue)


fetchIssues : String -> (Result Http.Error (List Issue) -> msg) -> Cmd msg
fetchIssues accessToken msg =
    let
        url =
            "https://api.github.com/user/issues?filter=all&state=all&sort=created&per_page=500&access_token=" ++ accessToken
    in
        Http.send msg (Http.get url (Json.Decode.list decodeIssue))


searchIssues : String -> String -> (Result Http.Error (List Issue) -> msg) -> Cmd msg
searchIssues accessToken query msg =
    let
        replaceWhitespace with =
            Regex.replace Regex.All (Regex.regex "\\S+") (\_ -> with)

        q =
            replaceWhitespace query "+"

        url =
            "https://api.github.com/search/issues?q=" ++ q ++ "&access_token=" ++ accessToken
    in
        Http.send msg (Http.get url decodeSearch)


decodeSearch : Json.Decode.Decoder (List Issue)
decodeSearch =
    Json.Decode.at [ "items" ] (Json.Decode.list decodeIssue)


decodeIssue : Json.Decode.Decoder Issue
decodeIssue =
    Json.Decode.Pipeline.decode Issue
        |> Json.Decode.Pipeline.required "id" Json.Decode.int
        |> Json.Decode.Pipeline.required "html_url" Json.Decode.string
        |> Json.Decode.Pipeline.required "title" Json.Decode.string
        |> Json.Decode.Pipeline.required "state" Json.Decode.string
        |> Json.Decode.Pipeline.required "comments" Json.Decode.int
        |> Json.Decode.Pipeline.optional "body" Json.Decode.string ""
        |> Json.Decode.Pipeline.required "labels" (Json.Decode.list decodeIssueLabel)
        |> Json.Decode.Pipeline.required "url" Json.Decode.string
        |> Json.Decode.Pipeline.required "assignees" (Json.Decode.list decodeUser)


decodeUser : Json.Decode.Decoder User
decodeUser =
    Json.Decode.map3 User
        (field "id" Json.Decode.int)
        (field "login" Json.Decode.string)
        (field "avatar_url" Json.Decode.string)


decodeIssueLabel : Json.Decode.Decoder IssueLabel
decodeIssueLabel =
    Json.Decode.map3 IssueLabel
        (field "name" Json.Decode.string)
        (field "color" Json.Decode.string)
        (field "url" Json.Decode.string)
