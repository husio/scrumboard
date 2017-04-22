module Main exposing (..)

import GitHub
import Html exposing (programWithFlags)
import Html5.DragDrop as DragDrop
import Model exposing (..)
import Update
import View
import WebSocket


main : Program ProgramFlags Model Msg
main =
    programWithFlags
        { init = init
        , update = Update.update
        , view = View.view
        , subscriptions = subscriptions
        }


init : ProgramFlags -> ( Model, Cmd Msg )
init flags =
    let
        model =
            { cards = []
            , dragDrop = DragDrop.init
            , rows = 3
            , icelog = []
            , icelogQuery = ""
            , showIcelog = False
            , error = Nothing
            , flags = flags
            , githubOrg = ""
            , repositories = []
            }

        fetchReposCmd =
            GitHub.fetchUserRepos flags.githubToken RepositoriesFetched

        fetchIcelog =
            GitHub.fetchIssues flags.githubToken IcelogFetched
    in
        ( model, Cmd.batch [ fetchReposCmd, fetchIcelog ] )


subscriptions : Model -> Sub Msg
subscriptions model =
    WebSocket.listen model.flags.websocketAddress WsMessage
