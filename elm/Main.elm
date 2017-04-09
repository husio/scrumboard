module Main exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html5.DragDrop as DragDrop
import Http
import Json.Decode exposing (field)
import Json.Encode
import Regex
import Array
import WebSocket
import Dict
import Json.Decode.Pipeline


columns : List String
columns =
    [ "Story", "To do", "In progress", "Done" ]


type alias ProgramFlags =
    { githubToken : String
    , websocketAddress : String
    }


type alias DraggableID =
    Int


type alias DroppableID =
    Int


type alias Model =
    { cards : List Card
    , dragDrop : DragDrop.Model DraggableID DroppableID
    , rows : Int
    , issueInput : IssuePathInput
    , error : Maybe String
    , flags : ProgramFlags
    , githubOrg : String
    }


type alias IssuePathInput =
    { value : String
    , valid : Bool
    }


type alias Card =
    { position : DroppableID
    , issue : Issue
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
    , assignees : List IssueUser
    }


type alias IssueUser =
    { id : Int
    , login : String
    , avatarUrl : String
    }


type alias IssueLabel =
    { name : String
    , color : String
    , url : String
    }


type Msg
    = DragDrop (DragDrop.Msg DraggableID DroppableID)
    | AddRow
    | DelRow
    | IssueInputChanged String
    | AddIssue
    | DelIssueCard Int
    | IssueFetched DroppableID (Result Http.Error Issue)
    | IssueRefreshed DroppableID (Result Http.Error Issue)
    | CloseError
    | WsMessage String


main : Program ProgramFlags Model Msg
main =
    programWithFlags
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : ProgramFlags -> ( Model, Cmd Msg )
init flags =
    let
        model =
            { cards = []
            , dragDrop = DragDrop.init
            , rows = 3
            , issueInput = issueInput ""
            , error = Nothing
            , flags =
                flags
                -- TODO allow to choose what organization (or user) is the issue comming from
            , githubOrg = "husio"
            }
    in
        ( model, Cmd.none )


issueInput : String -> IssuePathInput
issueInput value =
    let
        valid =
            case extractIssueInfo value of
                Nothing ->
                    False

                Just _ ->
                    True
    in
        IssuePathInput value valid


subscriptions : Model -> Sub Msg
subscriptions model =
    WebSocket.listen model.flags.websocketAddress WsMessage


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CloseError ->
            ( { model | error = Nothing }, Cmd.none )

        WsMessage content ->
            case Json.Decode.decodeString decodeState content of
                Err msg ->
                    ( { model | error = Just msg }, Cmd.none )

                Ok state ->
                    let
                        -- index existing cards by issue id
                        idx =
                            Dict.fromList <| List.map (\c -> ( c.issue.id, c )) model.cards

                        update : CardState -> ( Maybe Card, Cmd Msg )
                        update sccard =
                            case Dict.get sccard.issueId idx of
                                Nothing ->
                                    ( Nothing, refreshGithubIssue sccard.position model.flags.githubToken sccard.issueUrl )

                                Just card ->
                                    ( Just { card | position = sccard.position }, Cmd.none )

                        ( maybeCards, cmds ) =
                            List.unzip <| List.map update state.cards

                        noop a =
                            a

                        cards =
                            List.filterMap noop maybeCards
                    in
                        ( { model | rows = state.rows, cards = sortCards cards }, Cmd.batch cmds )

        AddIssue ->
            case extractIssueInfo model.issueInput.value of
                Nothing ->
                    ( model, Cmd.none )

                Just ( repo, issueId ) ->
                    -- add to first To Do
                    ( { model | issueInput = issueInput "" }, fetchGitHubIssue 1 model.flags.githubToken model.githubOrg repo issueId )

        IssueFetched position (Ok issue) ->
            let
                card =
                    Card position issue

                withoutFetched =
                    List.filter (\c -> c.issue.id /= issue.id) model.cards

                cards =
                    withoutFetched ++ [ card ]

                m =
                    { model | cards = sortCards cards }
            in
                ( m, sendStateSync m )

        IssueFetched _ (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        IssueRefreshed position (Ok issue) ->
            let
                card =
                    Card position issue

                withoutFetched =
                    List.filter (\c -> c.issue.id /= issue.id) model.cards

                cards =
                    withoutFetched ++ [ card ]

                m =
                    { model | cards = sortCards cards }
            in
                ( m, Cmd.none )

        IssueRefreshed _ (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        IssueInputChanged val ->
            ( { model | issueInput = issueInput val }, Cmd.none )

        AddRow ->
            let
                m =
                    { model | rows = model.rows + 1 }
            in
                ( m, sendStateSync m )

        DelRow ->
            let
                m =
                    { model
                        | rows =
                            if model.rows > 2 then
                                model.rows - 1
                            else
                                1
                    }
            in
                ( m, sendStateSync m )

        DragDrop dragMsg ->
            let
                ( dragModel, result ) =
                    DragDrop.update dragMsg model.dragDrop

                ( cards, sync ) =
                    case result of
                        Nothing ->
                            ( model.cards, False )

                        Just ( dragId, dropId ) ->
                            ( moveTo dropId dragId model.cards, True )

                m =
                    { model | dragDrop = dragModel, cards = sortCards cards }

                cmd =
                    if sync then
                        sendStateSync m
                    else
                        Cmd.none
            in
                ( m, cmd )

        DelIssueCard issueId ->
            let
                cards =
                    List.filter (\c -> c.issue.id /= issueId) model.cards

                m =
                    { model | cards = cards }
            in
                ( m, sendStateSync m )


sortCards : List Card -> List Card
sortCards cards =
    List.sortBy (\c -> c.issue.id) cards


moveTo : DroppableID -> DraggableID -> List Card -> List Card
moveTo position cardId cards =
    let
        updatePosition c =
            if c.issue.id == cardId then
                { c | position = position }
            else
                c
    in
        List.map updatePosition cards


view : Model -> Html Msg
view model =
    let
        clen =
            List.length columns

        row beginPos =
            viewRow ( clen * beginPos, clen * beginPos + clen - 1 ) model.cards

        rows =
            List.map row (List.range 0 (model.rows - 1))

        error =
            case model.error of
                Nothing ->
                    div [] []

                Just msg ->
                    div [ class "error" ]
                        [ span [ class "pull-right", onClick CloseError ] [ icon "times" ]
                        , text msg
                        ]
    in
        div []
            [ error
            , div []
                [ label [] [ text "Add issue " ]
                , input
                    [ onEnter AddIssue
                    , onInput IssueInputChanged
                    , value model.issueInput.value
                    , placeholder "<project>/<issue-id>"
                    , autofocus True
                    ]
                    []
                , button [ onClick AddIssue, disabled (not model.issueInput.valid) ] [ text "Add issue to the board" ]
                , div [ class "board" ] (viewHeaders columns :: rows)
                ]
            , button [ onClick AddRow ] [ text "add row" ]
            , button [ onClick DelRow ] [ text "remove row" ]
            ]


onEnter : Msg -> Attribute Msg
onEnter msg =
    let
        isEnter code =
            if code == 13 then
                Json.Decode.succeed msg
            else
                Json.Decode.fail ""
    in
        on "keydown" (Json.Decode.andThen isEnter keyCode)


isNothing : Maybe a -> Bool
isNothing maybe =
    case maybe of
        Just _ ->
            False

        Nothing ->
            True


viewHeaders : List String -> Html Msg
viewHeaders headers =
    let
        viewHeader title =
            strong [ class "board-header-col" ] [ text title ]

        rows =
            List.map viewHeader headers
    in
        div [ class "board-header" ] rows


viewRow : ( DroppableID, DroppableID ) -> List Card -> Html Msg
viewRow ( min, max ) cards =
    let
        droppableIds : List DroppableID
        droppableIds =
            List.range min max

        dropzones : List (Html Msg)
        dropzones =
            List.map (viewCell cards) droppableIds
    in
        div [ class "board-row" ] dropzones


viewCell : List Card -> DroppableID -> Html Msg
viewCell cards position =
    let
        contains =
            onlyContained position cards
    in
        div ([ class "board-cell" ] ++ DragDrop.droppable DragDrop position)
            (List.map viewCard contains)


onlyContained : DraggableID -> List Card -> List Card
onlyContained position cards =
    List.filter (\c -> c.position == position) cards


viewCard : Card -> Html Msg
viewCard card =
    let
        dragattr =
            DragDrop.draggable DragDrop card.issue.id

        color =
            case List.head card.issue.labels of
                Nothing ->
                    "#C2E4EF"

                Just label ->
                    "#" ++ label.color

        css =
            style [ ( "border-left", "6px solid " ++ color ) ]

        attrs =
            css :: class "card" :: dragattr

        stateClass =
            if card.issue.state == "closed" then
                "state-closed"
            else
                ""

        labels =
            List.map viewLabel card.issue.labels

        assignees =
            List.map viewAssignee card.issue.assignees
    in
        div attrs
            [ span
                [ onClick (DelIssueCard card.issue.id)
                , class "card-remove"
                , title "Remove from the board"
                ]
                [ icon "trash-o" ]
            , a
                [ title card.issue.body
                , class ("card-title " ++ stateClass)
                , href card.issue.htmlUrl
                , target "_blank"
                ]
                [ text card.issue.title ]
            , div [ class "card-meta" ]
                (labels
                    ++ [ div [ class "card-metainfo" ]
                            assignees
                       , div [ class "card-metainfo" ]
                            [ text <| issueLocation card.issue.url
                            , icon "code-fork"
                            ]
                       , div [ class "card-metainfo" ]
                            [ text (toString card.issue.comments)
                            , icon "comments-o"
                            ]
                       ]
                )
            ]


viewAssignee : IssueUser -> Html Msg
viewAssignee user =
    let
        url =
            user.avatarUrl ++ "&s=18"
    in
        img [ src url, class "avatar" ] []


viewLabel : IssueLabel -> Html Msg
viewLabel label =
    let
        attrs =
            [ style
                [ ( "color", "#" ++ label.color )
                , ( "border", "1px solid #" ++ label.color )
                ]
            ]
    in
        span (class "card-label" :: attrs) [ text label.name ]


issueLocation : String -> String
issueLocation url =
    let
        match =
            List.head <|
                Regex.find (Regex.AtMost 1) (Regex.regex "repos/[^/]+/([^/]+)/issues/(\\d+)$") url
    in
        case match of
            Nothing ->
                ""

            Just match ->
                String.join "/" <| List.map (Maybe.withDefault "") match.submatches


extractIssueInfo : String -> Maybe ( String, Int )
extractIssueInfo path =
    case issuePathInfo path of
        ( "", 0 ) ->
            Nothing

        ( repo, id ) ->
            Just ( repo, id )


issuePathInfo : String -> ( String, Int )
issuePathInfo path =
    let
        match =
            Regex.find (Regex.AtMost 1) (Regex.regex "^([^/]+)/(\\d+)$")

        str : Maybe String -> String
        str maybestr =
            Maybe.withDefault "" maybestr

        int : Maybe String -> Int
        int maybeint =
            Result.withDefault 0
                (String.toInt (Maybe.withDefault "" maybeint))
    in
        case List.head <| match path of
            Nothing ->
                ( "", 0 )

            Just match ->
                let
                    arr =
                        Array.fromList <|
                            List.map str (.submatches match)
                in
                    if Array.length arr /= 2 then
                        ( "", 0 )
                    else
                        ( str <| Array.get 0 arr, int <| Array.get 1 arr )


fetchGitHubIssue : DroppableID -> String -> String -> String -> Int -> Cmd Msg
fetchGitHubIssue position token organization repo issueId =
    let
        url =
            "https://api.github.com/repos/" ++ organization ++ "/" ++ repo ++ "/issues/" ++ (toString issueId) ++ "?access_token=" ++ token
    in
        Http.send (IssueFetched position) (Http.get url decodeIssue)


refreshGithubIssue : DroppableID -> String -> String -> Cmd Msg
refreshGithubIssue position token cardUrl =
    let
        url =
            cardUrl ++ "?access_token=" ++ token
    in
        Http.send (IssueRefreshed position) (Http.get url decodeIssue)


decodeIssue : Json.Decode.Decoder Issue
decodeIssue =
    Json.Decode.Pipeline.decode Issue
        |> Json.Decode.Pipeline.required "id" Json.Decode.int
        |> Json.Decode.Pipeline.required "html_url" Json.Decode.string
        |> Json.Decode.Pipeline.required "title" Json.Decode.string
        |> Json.Decode.Pipeline.required "state" Json.Decode.string
        |> Json.Decode.Pipeline.required "comments" Json.Decode.int
        |> Json.Decode.Pipeline.required "body" Json.Decode.string
        |> Json.Decode.Pipeline.required "labels" (Json.Decode.list decodeIssueLabel)
        |> Json.Decode.Pipeline.required "url" Json.Decode.string
        |> Json.Decode.Pipeline.required "assignees" (Json.Decode.list decodeIssueUser)


decodeIssueUser : Json.Decode.Decoder IssueUser
decodeIssueUser =
    Json.Decode.map3 IssueUser
        (field "id" Json.Decode.int)
        (field "login" Json.Decode.string)
        (field "avatar_url" Json.Decode.string)


decodeIssueLabel : Json.Decode.Decoder IssueLabel
decodeIssueLabel =
    Json.Decode.map3 IssueLabel
        (field "name" Json.Decode.string)
        (field "color" Json.Decode.string)
        (field "url" Json.Decode.string)


encodeState : Model -> Json.Encode.Value
encodeState model =
    Json.Encode.object
        [ ( "cards", Json.Encode.list (List.map encodeCard model.cards) )
        , ( "rows", Json.Encode.int model.rows )
        ]


encodeCard : Card -> Json.Encode.Value
encodeCard card =
    Json.Encode.object
        [ ( "position", Json.Encode.int card.position )
        , ( "issueUrl", Json.Encode.string card.issue.url )
        , ( "issueId", Json.Encode.int card.issue.id )
        ]


decodeState : Json.Decode.Decoder State
decodeState =
    Json.Decode.map2 State
        (field "rows" Json.Decode.int)
        (field "cards" (Json.Decode.list decodeCardState))


type alias State =
    { rows : Int
    , cards : List CardState
    }


decodeCardState : Json.Decode.Decoder CardState
decodeCardState =
    Json.Decode.map3 CardState
        (field "position" Json.Decode.int)
        (field "issueUrl" Json.Decode.string)
        (field "issueId" Json.Decode.int)


type alias CardState =
    { position : Int
    , issueUrl : String
    , issueId : Int
    }


sendStateSync : Model -> Cmd msg
sendStateSync model =
    let
        state =
            Json.Encode.encode 2 <|
                encodeState model
    in
        WebSocket.send model.flags.websocketAddress state


icon : String -> Html Msg
icon name =
    i [ class ("fa fa-" ++ name), attribute "aria-hidden" "true" ] []
