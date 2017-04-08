module Main exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html5.DragDrop as DragDrop


type alias DraggableID =
    Int


type alias DroppableID =
    Int


type alias Model =
    { cards : List Card
    , dragDrop : DragDrop.Model DraggableID DroppableID
    , rows : Int
    }


type alias Card =
    { id : DraggableID
    , position : DroppableID
    , content : String
    }


type Msg
    = DragDrop (DragDrop.Msg DraggableID DroppableID)
    | AddRow
    | DelRow


columns : List String
columns =
    [ "Story", "To do", "In progress", "Done" ]


init : ( Model, Cmd Msg )
init =
    let
        model =
            { cards =
                [ Card 1 4 "Lorem ipsum dolor sit amet, diam doctus an vim, usu in tibique sensibus oportere, te vim dicant cetero fabulas. Eum te eirmod verear facilisi, nobis omittam sit no. Conceptam forensibus constituto in vel, duo ea soluta corrumpit."
                , Card 2 9 "No per virtute detraxit, simul commune expetenda et sea, eam pertinax comprehensam at. Lorem mollis verterem ea eos. No pri paulo efficiantur definitiones."
                , Card 3 0 "Ad pro aeque legere graeci. Purto elitr adipisci et est, duo fugit partiendo ei. Eam tritani nonumes scaevola cu, ea meliore neglegentur ius, et his ubique scaevola. Ea vis tantas vivendo incorrupte, eum te quem persius, splendide hendrerit ius ea."
                , Card 4 0 "Audire persecuti mel ex, dicat viderer inciderint mei et."
                , Card 5 1 "Cum modus scripserit eu. Sed autem iudico et."
                , Card 6 3 "Ea feugiat fierent nec. Id ferri epicuri pro, per ne ullum qualisque."
                ]
            , dragDrop = DragDrop.init
            , rows = 10
            }
    in
        ( model, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
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
                    { model
                        | dragDrop = dragModel
                        , cards = cards
                    }
            in
                ( m, Cmd.none )


moveTo : DroppableID -> DraggableID -> List Card -> List Card
moveTo position cardId cards =
    let
        updatePosition c =
            if c.id == cardId then
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
            , div [] (viewHeaders columns :: rows)
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
            DragDrop.draggable DragDrop card.id

        css =
            style
                [ "padding" => "2px 10px"
                , "border" => "1px solid #F1F1F1"
                , "border-radius" => "3px"
                , "border-left" => "4px solid #4174FF"
                , "background" => "#F7F7F7"
                , "margin" => "3px"
                ]

        attrs =
            css :: dragattr
    in
        div attrs
            [ a [ href "/" ] [ text card.content ]
            ]


main : Program Never Model Msg
main =
    program
        { init = init
        , update = update
        , view = view
        , subscriptions = always Sub.none
        }
