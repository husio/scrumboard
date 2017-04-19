module Main exposing (..)

import Array
import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Events.Extra exposing (targetSelectedIndex)
import Html5.DragDrop as DragDrop
import Http
import Json.Decode exposing (field)
import Json.Encode
import List.Extra
import Regex
import WebSocket
import GitHub
import Extra


columns : List String
columns =
    [ "Story", "To do", "In progress", "Done" ]


type alias ProgramFlags =
    { githubToken : String
    , websocketAddress : String
    }


type alias DraggableID =
    { id : Int
    , url : String
    }


emptyDraggable : DraggableID
emptyDraggable =
    { id = 0, url = "http:///issue-without-url" }


type alias DroppableID =
    { position : Int
    , order : Int
    }


type alias Model =
    { cards : List Card
    , dragDrop : DragDrop.Model DraggableID DroppableID
    , rows : Int
    , icelog : List GitHub.Issue
    , icelogQuery : String
    , showIcelog : Bool
    , error : Maybe String
    , flags : ProgramFlags
    , githubOrg : String
    , repositories : List GitHub.Repository
    }


type alias Card =
    { position : Int
    , order : Int
    , issue : GitHub.Issue
    }


type Msg
    = DragDrop (DragDrop.Msg DraggableID DroppableID)
    | DelIssueCard Int
    | IssueFetched DroppableID (Result Http.Error GitHub.Issue)
    | IssueRefreshed DroppableID (Result Http.Error GitHub.Issue)
    | RepositoriesFetched (Result Http.Error (List GitHub.Repository))
    | GithubOwnerSelected String
    | QueryIcelog
    | IcelogSearchChanged String
    | IcelogFetched (Result Http.Error (List GitHub.Issue))
    | ShowIcelog Bool
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
            , icelog = []
            , icelogQuery = ""
            , showIcelog = True
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

                        m =
                            adjustRowNumber { model | rows = state.rows, cards = tidyCards cards }
                    in
                        ( m, Cmd.batch cmds )

        IssueFetched position (Ok issue) ->
            let
                card =
                    Card position.position position.order issue

                withoutFetched =
                    List.filter (\c -> c.issue.id /= issue.id) model.cards

                cards =
                    withoutFetched ++ [ card ]

                m =
                    adjustRowNumber { model | cards = tidyCards cards }
            in
                ( m, sendStateSync m )

        QueryIcelog ->
            ( model, GitHub.searchIssues model.flags.githubToken model.icelogQuery IcelogFetched )

        IcelogSearchChanged query ->
            ( { model | icelogQuery = query }, Cmd.none )

        IssueFetched _ (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        IcelogFetched (Ok issues) ->
            ( { model | icelog = issues }, Cmd.none )

        IcelogFetched (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        ShowIcelog show ->
            ( { model | showIcelog = show }, Cmd.none )

        IssueRefreshed position (Ok issue) ->
            let
                card =
                    Card position.position position.order issue

                withoutFetched =
                    List.filter (\c -> c.issue.id /= issue.id) model.cards

                cards =
                    withoutFetched ++ [ card ]

                m =
                    adjustRowNumber { model | cards = tidyCards cards }
            in
                ( m, Cmd.none )

        IssueRefreshed _ (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        DragDrop dragMsg ->
            let
                ( dragModel, result ) =
                    DragDrop.updateSticky dragMsg model.dragDrop

                dragId =
                    DragDrop.getDragId dragModel
                        |> Maybe.withDefault emptyDraggable

                dropId =
                    DragDrop.getDropId dragModel
                        |> Maybe.withDefault defaultDropId

                ( cards, cardCmd ) =
                    if hasCard dragId model.cards then
                        moveCardTo dropId dragId model.cards
                    else if dragId == emptyDraggable then
                        -- ignore if reciving empty draggable that does not
                        -- represent real github issue card
                        ( model.cards, Cmd.none )
                    else
                        addCardTo model.flags.githubToken dropId dragId model.cards

                m =
                    adjustRowNumber
                        { model
                            | dragDrop = dragModel
                            , cards = tidyCards cards
                        }

                syncCmd =
                    case result of
                        Just _ ->
                            sendStateSync m

                        Nothing ->
                            Cmd.none
            in
                ( m, Cmd.batch [ syncCmd, cardCmd ] )

        DelIssueCard issueId ->
            let
                cards =
                    List.filter (\c -> c.issue.id /= issueId) model.cards

                m =
                    adjustRowNumber { model | cards = cards }
            in
                ( m, sendStateSync m )


adjustRowNumber : Model -> Model
adjustRowNumber model =
    -- make sure there is always only one empty row at the very bottom, but do
    -- not remove middle rows
    let
        maxrow : Float
        maxrow =
            List.map .position model.cards
                |> List.maximum
                |> Maybe.withDefault 0
                |> toFloat

        colnum : Float
        colnum =
            List.length columns
                |> toFloat

        needrows : Int
        needrows =
            ceiling (maxrow / colnum)
    in
        { model | rows = needrows + 1 }


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

        icelog =
            if model.showIcelog then
                viewIcelog model
            else
                text ""
    in
        div []
            [ error
            , div []
                [ span
                    [ class "toggle-icelog-btn"
                    , onClick (ShowIcelog (not model.showIcelog))
                    , title "Toggle icelog"
                    ]
                    [ icon "list" ]
                , icelog
                , div [ class "board" ] (viewHeaders columns :: rows)
                ]
            , div
                [ class "footer" ]
                [ a [ href "https://github.com/husio/scrumboard", target "_blank" ] [ icon "github", text " source code" ] ]
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


isNothing : Maybe a -> Bool
isNothing maybe =
    case maybe of
        Just _ ->
            False

        Nothing ->
            True


viewIcelog : Model -> Html Msg
viewIcelog model =
    let
        icelogIssues =
            List.map viewIcelogIssue model.icelog
    in
        div [ class "icelog" ]
            [ div [ class "icelog-toolbar" ]
                [ input
                    [ Extra.onEnter QueryIcelog
                    , Extra.onEsc (ShowIcelog False)
                    , class "icelog-query"
                    , onInput IcelogSearchChanged
                    , placeholder "Search GitHub issues"
                    , value model.icelogQuery
                    , autofocus True
                    ]
                    []
                , button
                    [ onClick QueryIcelog
                    , class "icelog-query-btn"
                    ]
                    [ icon "search" ]
                , p [ class "icelog-toolbar-help" ]
                    [ text "You can use "
                    , a [ target "_blank", href "https://help.github.com/articles/searching-issues/" ] [ text "advanced search" ]
                    , text " formatting."
                    ]
                , span
                    [ class "toggle-icelog-btn"
                    , onClick (ShowIcelog False)
                    , title "Hide icelog"
                    ]
                    [ icon "list" ]
                ]
            , div [ class "icelog-issues" ] icelogIssues
            ]


viewIcelogIssue : GitHub.Issue -> Html Msg
viewIcelogIssue issue =
    let
        assignees =
            List.map viewAssignee issue.assignees

        labels =
            List.map viewLabel issue.labels

        dragattr =
            DragDrop.draggable DragDrop <| issueDragId issue

        attrs =
            cardBorder issue :: class "card" :: dragattr
    in
        div attrs
            [ a
                [ title issue.body
                , class ("card-title state-" ++ issue.state)
                , href issue.htmlUrl
                , target "_blank"
                ]
                [ text issue.title ]
            , div [ class "card-meta" ]
                (labels
                    ++ [ div [ class "card-metainfo" ]
                            assignees
                       , div [ class "card-metainfo" ]
                            [ text <| issueLocation issue.url
                            , icon "code-fork"
                            ]
                       , div [ class "card-metainfo" ]
                            [ text (toString issue.comments)
                            , icon "comments-o"
                            ]
                       ]
                )
            ]


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
        placeholderClass =
            if Maybe.withDefault emptyDraggable dragId == cardDragId card then
                class "card-placeholder"
            else
                class ""

        dragattr =
            DragDrop.draggable DragDrop <| cardDragId card

        dropAttrs =
            DragDrop.droppable DragDrop <| cardDropId card

        attrs =
            (placeholderClass :: cardBorder card.issue :: class "card" :: dragattr) ++ dropAttrs

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


cardBorder : GitHub.Issue -> Attribute Msg
cardBorder issue =
    let
        color =
            case List.head issue.labels of
                Nothing ->
                    "#C2E4EF"

                Just label ->
                    "#" ++ label.color
    in
        style [ ( "border-left", "6px solid " ++ color ) ]


viewAssignee : GitHub.User -> Html Msg
viewAssignee user =
    let
        url =
            user.avatarUrl ++ "&s=18"
    in
        img [ src url, class "avatar" ] []


viewLabel : GitHub.IssueLabel -> Html Msg
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
    GitHub.fetchIssueUrl token cardUrl (IssueRefreshed position)


fetchGitHubIssueUrl : DroppableID -> String -> String -> Cmd Msg
fetchGitHubIssueUrl position token cardUrl =
    GitHub.fetchIssueUrl token cardUrl (IssueFetched position)


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
    issueDragId card.issue


issueDragId : GitHub.Issue -> DraggableID
issueDragId issue =
    { id = issue.id, url = issue.url }


cardDropId : Card -> DroppableID
cardDropId card =
    DroppableID card.position card.order


hasCard : DraggableID -> List Card -> Bool
hasCard drag cards =
    List.any (\c -> c.issue.id == drag.id) cards


moveCardTo : DroppableID -> DraggableID -> List Card -> ( List Card, Cmd Msg )
moveCardTo dropId drag cards =
    let
        updatePosition : Card -> Card
        updatePosition c =
            if c.issue.id == drag.id then
                { c | position = dropId.position, order = dropId.order }
            else
                c
    in
        ( List.map updatePosition cards, Cmd.none )


addCardTo : String -> DroppableID -> DraggableID -> List Card -> ( List Card, Cmd Msg )
addCardTo githubToken dropId drop cards =
    let
        cmd =
            fetchGitHubIssueUrl dropId githubToken drop.url
    in
        ( cards, cmd )


defaultDropId : DroppableID
defaultDropId =
    { position = 1, order = 0 }
