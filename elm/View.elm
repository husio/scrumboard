module View exposing (..)

import Extra
import GitHub
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html5.DragDrop as DragDrop
import Html5.DragDrop as DragDrop
import Model exposing (..)
import Regex


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
            if model.showIcelog && isNothing dragId then
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
        boardIssues =
            List.map (\c -> c.issue.id) model.cards

        -- remove those issues that are already present on the board - no need to show them on in the icelog
        filterOutDisplayed : List GitHub.Issue -> List GitHub.Issue
        filterOutDisplayed icelog =
            List.filter (\i -> not (List.member i.id boardIssues)) icelog

        icelogIssues =
            filterOutDisplayed model.icelog
                |> List.map viewIcelogIssue

        ifFetching : String -> String -> String
        ifFetching yes no =
            if model.icelogFetching then
                yes
            else
                no
    in
        div [ class "icelog-sidebar" ]
            [ div [ class "icelog-toolbar" ]
                [ input
                    [ Extra.onKeyDown
                        [ ( Extra.keyEnter, QueryIcelog )
                        , ( Extra.keyEsc, (ShowIcelog False) )
                        ]
                    , class "icelog-query"
                    , onInput IcelogSearchChanged
                    , placeholder "Search GitHub issues"
                    , value (ifFetching "feching issues..." model.icelogQuery)
                    , autofocus True
                    , disabled model.icelogFetching
                    ]
                    []
                , button
                    [ onClick QueryIcelog
                    , class "icelog-query-btn"
                    , disabled model.icelogFetching
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

        cardRemove =
            if card.askDelete then
                span [ class "card-remove" ]
                    [ span
                        [ class "card-remove-yes"
                        , onClick (DelIssueCardConfirm card.issue.id)
                        , title "Confirm and remove from the board"
                        ]
                        [ icon "trash-o" ]
                    , span
                        [ class "card-remove-no"
                        , onClick (DelIssueCardCancel card.issue.id)
                        , title "Cancel removing from the board"
                        ]
                        [ icon "ban" ]
                    ]
            else
                span
                    [ onClick (DelIssueCard card.issue.id)
                    , class "card-remove"
                    , title "Remove from the board"
                    ]
                    [ icon "trash-o" ]
    in
        div attrs
            [ cardRemove
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


icon : String -> Html Msg
icon name =
    i [ class ("fa fa-" ++ name), attribute "aria-hidden" "true" ] []


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


cardDragId : Card -> DraggableID
cardDragId card =
    issueDragId card.issue


issueDragId : GitHub.Issue -> DraggableID
issueDragId issue =
    { id = issue.id, url = issue.url }


cardDropId : Card -> DroppableID
cardDropId card =
    DroppableID card.position card.order
