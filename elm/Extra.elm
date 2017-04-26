module Extra exposing (..)

import Html exposing (..)
import Html.Events exposing (..)
import Json.Decode


onEnter : msg -> Attribute msg
onEnter msg =
    onEvent "keydown" 13 msg


onEsc : msg -> Attribute msg
onEsc msg =
    onEvent "keypress" 27 msg


onEvent : String -> Int -> msg -> Attribute msg
onEvent event key cmd =
    let
        isKey code =
            if code == key then
                Json.Decode.succeed cmd
            else
                Json.Decode.fail ""
    in
        on event (Json.Decode.andThen isKey keyCode)
