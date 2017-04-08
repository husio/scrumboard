module Main exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html5.DragDrop as DragDrop
import Http
import Json.Decode exposing (field)
import Regex
import Array
import WebSocket


type alias DraggableID =
    Int


type alias DroppableID =
    Int


type alias Model =
    { cards : List Card
    , dragDrop : DragDrop.Model DraggableID DroppableID
    , rows : Int
    , issueInput : IssuePathInput
    }


type alias IssuePathInput =
    { value : String
    , valid : Bool
    }


type alias Card =
    { position : DroppableID
    , issue : Issue
    }


type Msg
    = DragDrop (DragDrop.Msg DraggableID DroppableID)
    | AddRow
    | DelRow
    | IssueInputChanged String
    | FetchIssue
    | IssueFetched (Result Http.Error Issue)
    | WsMessage String


columns : List String
columns =
    [ "Story", "To do", "In progress", "Done" ]


githubToken : String
githubToken =
    "bb89cff5cfcf89509ce8f36ae4b7966bbef6191e"


init : ( Model, Cmd Msg )
init =
    let
        model =
            { cards = []
            , dragDrop = DragDrop.init
            , rows = 10
            , issueInput = issueInput ""
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


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        WsMessage _ ->
            ( model, Cmd.none )

        FetchIssue ->
            case extractIssueInfo model.issueInput.value of
                Nothing ->
                    ( model, Cmd.none )

                Just ( repo, issueId ) ->
                    ( { model | issueInput = issueInput "" }, fetchIssue githubToken repo issueId )

        IssueFetched (Ok issue) ->
            let
                issueToCard issue =
                    Card 0 issue

                cards =
                    model.cards ++ [ issueToCard issue ]
            in
                ( { model | cards = cards }, Cmd.none )

        IssueFetched (Err _) ->
            ( model, Cmd.none )

        IssueInputChanged val ->
            ( { model | issueInput = issueInput val }, Cmd.none )

        AddRow ->
            ( { model | rows = model.rows + 1 }, Cmd.none )

        DelRow ->
            ( { model | rows = model.rows - 1 }, Cmd.none )

        DragDrop dragMsg ->
            let
                ( dragModel, result ) =
                    DragDrop.update dragMsg model.dragDrop

                cards =
                    case result of
                        Nothing ->
                            model.cards

                        Just ( dragId, dropId ) ->
                            moveTo dropId dragId model.cards

                m =
                    { model | dragDrop = dragModel, cards = cards }
            in
                ( m, Cmd.none )


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
    in
        div []
            [ button [ onClick AddRow ] [ text "add row" ]
            , button [ onClick DelRow ] [ text "remove row" ]
            , div []
                [ label [] [ text "Add issue " ]
                , input [ onInput IssueInputChanged, value model.issueInput.value, placeholder "<project>/<issue-id>" ] []
                , button [ onClick FetchIssue, disabled (not model.issueInput.valid) ] [ text "Add issue to the board" ]
                , div [] (viewHeaders columns :: rows)
                ]
            ]


isNothing : Maybe a -> Bool
isNothing maybe =
    case maybe of
        Just _ ->
            False

        Nothing ->
            True


(=>) : a -> a -> ( a, a )
(=>) =
    (,)


viewHeaders : List String -> Html Msg
viewHeaders headers =
    let
        viewHeader title =
            strong
                [ style
                    [ "padding" => "0 10px"
                    , "flex" => "1"
                    ]
                ]
                [ text title ]

        rows =
            List.map viewHeader headers
    in
        div
            [ style
                [ "display" => "flex"
                , "text-align" => "center"
                ]
            ]
            rows


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
        div
            [ style
                [ "min-height" => "80px"
                , "display" => "flex"
                , "border-top" => "1px solid #EAEAEA"
                , "margin" => "10px"
                , "padding" => "8px"
                ]
            ]
            dropzones


viewCell : List Card -> DroppableID -> Html Msg
viewCell cards position =
    let
        divStyle =
            style
                [ "padding" => "0 10px"
                , "flex" => "1"
                ]

        contains =
            onlyContained position cards
    in
        div ([ divStyle ] ++ DragDrop.droppable DragDrop position)
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
                    "#F1F1F1"

                Just label ->
                    "#" ++ label.color

        css =
            style
                [ "padding" => "2px 10px"
                , "border" => "1px solid #F1F1F1"
                , "border-radius" => "3px"
                , "border-left" => ("4px solid " ++ color)
                , "background" => "#F7F7F7"
                , "min-height" => "40px"
                , "margin" => "3px"
                ]

        attrs =
            css :: dragattr
    in
        div attrs
            [ a [ href card.issue.url ] [ text card.issue.title ]
            , text (toString card.issue.comments)
            ]


main : Program Never Model Msg
main =
    program
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type alias Issue =
    { id : Int
    , url : String
    , title : String
    , state : String
    , comments : Int
    , body : String
    , labels : List IssueLabel
    }


type alias IssueLabel =
    { name : String
    , color : String
    , url : String
    }


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


fetchIssue : String -> String -> Int -> Cmd Msg
fetchIssue token repo issueId =
    let
        url =
            "https://api.github.com/repos/opinary/" ++ repo ++ "/issues/" ++ (toString issueId) ++ "?access_token=" ++ token
    in
        Http.send IssueFetched (Http.get url decodeIssue)


decodeIssue : Json.Decode.Decoder Issue
decodeIssue =
    Json.Decode.map7 Issue
        (field "id" Json.Decode.int)
        (field "html_url" Json.Decode.string)
        (field "title" Json.Decode.string)
        (field "state" Json.Decode.string)
        (field "comments" Json.Decode.int)
        (field "body" Json.Decode.string)
        (field "labels" (Json.Decode.list decodeIssueLabel))


decodeIssueLabel : Json.Decode.Decoder IssueLabel
decodeIssueLabel =
    Json.Decode.map3 IssueLabel
        (field "name" Json.Decode.string)
        (field "color" Json.Decode.string)
        (field "url" Json.Decode.string)


subscriptions : Model -> Sub Msg
subscriptions model =
    WebSocket.listen "ws://echo.websocket.org" WsMessage
