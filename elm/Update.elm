module Update exposing (..)

import Dict
import GitHub
import Html5.DragDrop as DragDrop
import Json.Decode
import Json.Encode
import Model exposing (..)
import WebSocket


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CloseError ->
            ( { model | error = Nothing }, Cmd.none )

        RepositoriesFetched (Ok repositories) ->
            ( { model | repositories = repositories }, Cmd.none )

        RepositoriesFetched (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

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
            ( { model | icelogFetching = True }, GitHub.searchIssues model.flags.githubToken model.icelogQuery IcelogFetched )

        IcelogSearchChanged query ->
            ( { model | icelogQuery = query }, Cmd.none )

        IssueFetched _ (Err msg) ->
            ( { model | error = Just (toString msg) }, Cmd.none )

        IcelogFetched (Ok issues) ->
            ( { model | icelog = issues, icelogFetching = False }, Cmd.none )

        IcelogFetched (Err msg) ->
            ( { model | error = Just (toString msg), icelogFetching = False }, Cmd.none )

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
                        |> Maybe.withDefault emptyDroppable

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

        colnums =
            toFloat (List.length columns)

        needrows : Int
        needrows =
            ceiling ((maxrow + 1) / colnums)
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


sendStateSync : Model -> Cmd msg
sendStateSync model =
    let
        state =
            Json.Encode.encode 2 <|
                encodeState model
    in
        WebSocket.send model.flags.websocketAddress state


fetchGitHubIssue : DroppableID -> String -> String -> String -> Int -> Cmd Msg
fetchGitHubIssue position token organization repo issueId =
    GitHub.fetchIssue token organization repo issueId (IssueFetched position)


refreshGithubIssue : DroppableID -> String -> String -> Cmd Msg
refreshGithubIssue position token cardUrl =
    GitHub.fetchIssueUrl token cardUrl (IssueRefreshed position)


fetchGitHubIssueUrl : DroppableID -> String -> String -> Cmd Msg
fetchGitHubIssueUrl position token cardUrl =
    GitHub.fetchIssueUrl token cardUrl (IssueFetched position)
