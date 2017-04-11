module Main exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Events.Extra exposing (targetSelectedIndex)
import Html5.DragDrop as DragDrop
import Http
import Json.Decode exposing (field)
import Json.Encode
import Regex
import Array
import WebSocket
import Dict
import GitHub
import List.Extra


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
    { position : Int
    , order : Int
    }


type alias Model =
    { cards : List Card
    , dragDrop : DragDrop.Model DraggableID DroppableID
    , rows : Int
    , issueInput : IssuePathInput
    , error : Maybe String
    , flags : ProgramFlags
    , githubOrg : String
    , repositories : List GitHub.Repository
    }


type alias IssuePathInput =
    { value : String
    , valid : Bool
    }


type alias Card =
    { position : Int
    , order : Int
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
    | RepositoriesFetched (Result Http.Error (List GitHub.Repository))
    | GithubOwnerSelected String
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
            , flags = flags
            , githubOrg = ""
            , repositories = []
            }

        fetchReposCmd =
            GitHub.fetchUserRepos flags.githubToken RepositoriesFetched
    in
        ( model, fetchReposCmd )


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

        RepositoriesFetched (Ok repositories) ->
            ( { model | repositories = repositories }, Cmd.none )

        RepositoriesFetched (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        GithubOwnerSelected name ->
            ( { model | githubOrg = name }, Cmd.none )

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
                        update sc =
                            case Dict.get sc.issueId idx of
                                Nothing ->
                                    ( Nothing, refreshGithubIssue (DroppableID sc.position sc.order) model.flags.githubToken sc.issueUrl )

                                Just card ->
                                    ( Just { card | position = sc.position }, Cmd.none )

                        ( maybeCards, cmds ) =
                            List.unzip <| List.map update state.cards

                        noop a =
                            a

                        cards =
                            List.filterMap noop maybeCards
                    in
                        ( { model | rows = state.rows, cards = tidyCards cards }, Cmd.batch cmds )

        AddIssue ->
            case extractIssueInfo model.issueInput.value of
                Nothing ->
                    ( model, Cmd.none )

                Just ( repo, issueId ) ->
                    -- add to first To Do
                    ( { model | issueInput = issueInput "" }, fetchGitHubIssue defaultDropId model.flags.githubToken model.githubOrg repo issueId )

        IssueFetched position (Ok issue) ->
            let
                card =
                    Card position.position position.order issue

                withoutFetched =
                    List.filter (\c -> c.issue.id /= issue.id) model.cards

                cards =
                    withoutFetched ++ [ card ]

                m =
                    { model | cards = tidyCards cards }
            in
                ( m, sendStateSync m )

        IssueFetched _ (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        IssueRefreshed position (Ok issue) ->
            let
                card =
                    Card position.position position.order issue

                withoutFetched =
                    List.filter (\c -> c.issue.id /= issue.id) model.cards

                cards =
                    withoutFetched ++ [ card ]

                m =
                    { model | cards = tidyCards cards }
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
                    DragDrop.updateSticky dragMsg model.dragDrop

                ( _, sync ) =
                    case result of
                        Nothing ->
                            ( model.cards, False )

                        Just ( dragId, dropId ) ->
                            ( moveCardTo dropId dragId model.cards, True )

                dragId =
                    DragDrop.getDragId dragModel
                        |> Maybe.withDefault -1

                dropId =
                    DragDrop.getDropId dragModel
                        |> Maybe.withDefault defaultDropId

                cards =
                    moveCardTo dropId dragId model.cards

                m =
                    { model
                        | dragDrop = dragModel
                        , cards = tidyCards cards
                    }

                cmd =
                    case result of
                        Just _ ->
                            sendStateSync m

                        Nothing ->
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


tidyCards : List Card -> List Card
tidyCards cards =
    let
        sorted =
            sortCards cards

        orders =
            List.range 1 200

        reorder : Int -> Card -> Card
        reorder o c =
            { c | order = o * 2 }
    in
        List.map2 reorder orders sorted


sortCards : List Card -> List Card
sortCards cards =
    let
        cardOrder : Card -> Card -> Order
        cardOrder a b =
            if a.position > b.position then
                GT
            else if a.position < b.position then
                LT
            else if a.order > b.order then
                GT
            else
                LT
    in
        List.sortWith cardOrder cards


view : Model -> Html Msg
view model =
    let
        clen =
            List.length columns

        dragId : Maybe DraggableID
        dragId =
            DragDrop.getDragId model.dragDrop

        row beginPos =
            viewRow ( DroppableID (clen * beginPos) 0, DroppableID (clen * beginPos + clen - 1) 0 ) dragId model.cards

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
                [ label [] [ text "Add issue from " ]
                , viewGithubOwnerSelector model.repositories
                , input
                    [ onEnter AddIssue
                    , onInput IssueInputChanged
                    , value model.issueInput.value
                    , placeholder "<project>/<issue-id>"
                    , autofocus True
                    ]
                    []
                , button [ onClick AddIssue, disabled (not model.issueInput.valid || model.githubOrg == "") ] [ text "Add issue to the board" ]
                , div [ class "board" ] (viewHeaders columns :: rows)
                ]
            , button [ onClick AddRow ] [ text "add row" ]
            , button [ onClick DelRow ] [ text "remove row" ]
            ]


viewGithubOwnerSelector : List GitHub.Repository -> Html Msg
viewGithubOwnerSelector repositories =
    let
        names : List String
        names =
            List.map .owner repositories
                |> List.map .login
                |> List.Extra.unique

        nameByIndex : Maybe Int -> Msg
        nameByIndex maybeIdx =
            case maybeIdx of
                Nothing ->
                    GithubOwnerSelected ""

                Just idx ->
                    GithubOwnerSelected
                        (Array.fromList names
                            |> Array.get idx
                            |> Maybe.withDefault ""
                        )

        selectEvent =
            on "change"
                (Json.Decode.map nameByIndex targetSelectedIndex)

        viewOption : String -> Html Msg
        viewOption name =
            option [ value name ] [ text name ]

        options =
            List.map viewOption names
    in
        select [ selectEvent ] options


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


viewRow : ( DroppableID, DroppableID ) -> Maybe DraggableID -> List Card -> Html Msg
viewRow ( min, max ) dragId cards =
    let
        droppablePositions : List Int
        droppablePositions =
            List.range min.position max.position

        droppableIds : List DroppableID
        droppableIds =
            List.map2 DroppableID droppablePositions (List.range 0 30)

        dropzones : List (Html Msg)
        dropzones =
            List.map (viewCell dragId cards) droppableIds
    in
        div [ class "board-row" ] dropzones


viewCell : Maybe DraggableID -> List Card -> DroppableID -> Html Msg
viewCell dragId cards dropId =
    let
        contains =
            onlyContained dropId cards

        -- drop attribute should be present only if there are no cards, because
        -- otherwise we want to position relative to other cards.
        dropAttr =
            []

        attrs =
            [ class "board-cell" ] ++ dropAttr

        cardViews =
            List.map (viewCard dragId) contains

        beforeHelper =
            viewCardDrophelper (DroppableID dropId.position 0)

        afterHelper =
            viewCardDrophelper (DroppableID dropId.position 1000)
    in
        div attrs (beforeHelper :: cardViews ++ [ afterHelper ])


viewCardDrophelper : DroppableID -> Html Msg
viewCardDrophelper dropId =
    let
        dropAttrs =
            DragDrop.droppable DragDrop dropId

        attrs =
            class "drop-helper" :: dropAttrs
    in
        div attrs []


onlyContained : DroppableID -> List Card -> List Card
onlyContained dropId cards =
    List.filter (\c -> c.position == dropId.position) cards


viewCard : Maybe DraggableID -> Card -> Html Msg
viewCard dragId card =
    let
        color =
            case List.head card.issue.labels of
                Nothing ->
                    "#C2E4EF"

                Just label ->
                    "#" ++ label.color

        css =
            style [ ( "border-left", "6px solid " ++ color ) ]

        placeholderClass =
            if Maybe.withDefault 0 dragId == cardDragId card then
                class "card-placeholder"
            else
                class ""

        dragattr =
            DragDrop.draggable DragDrop <| cardDragId card

        dropAttrs =
            DragDrop.droppable DragDrop <| cardDropId card

        attrs =
            (placeholderClass :: css :: class "card" :: dragattr) ++ dropAttrs

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
                , class ("card-title state-" ++ card.issue.state)
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
    GitHub.fetchIssue token organization repo issueId (IssueFetched position)


refreshGithubIssue : DroppableID -> String -> String -> Cmd Msg
refreshGithubIssue position token cardUrl =
    let
        url =
            cardUrl ++ "?access_token=" ++ token
    in
        Http.send (IssueRefreshed position) (Http.get url GitHub.decodeIssue)


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
        , ( "order", Json.Encode.int card.order )
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
    Json.Decode.map4 CardState
        (field "position" Json.Decode.int)
        (field "order" Json.Decode.int)
        (field "issueUrl" Json.Decode.string)
        (field "issueId" Json.Decode.int)


type alias CardState =
    { position : Int
    , order : Int
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


cardDragId : Card -> DraggableID
cardDragId card =
    card.issue.id


cardDropId : Card -> DroppableID
cardDropId card =
    DroppableID card.position card.order


moveCardTo : DroppableID -> DraggableID -> List Card -> List Card
moveCardTo dropId cardId cards =
    let
        updatePosition : Card -> Card
        updatePosition c =
            if c.issue.id == cardId then
                { c | position = dropId.position, order = dropId.order }
            else
                c
    in
        List.map updatePosition cards


defaultDropId : DroppableID
defaultDropId =
    { position = 1, order = 0 }
