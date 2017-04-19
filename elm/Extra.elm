module Extra exposing (..)

import Html exposing (..)
import Html.Events exposing (..)
import Json.Decode


onEnter : msg -> Attribute msg
onEnter msg =
    onKeyPressed 13 msg


onEsc : msg -> Attribute msg
onEsc msg =
    onKeyPressed 27 msg


onKeyPressed : Int -> msg -> Attribute msg
onKeyPressed key cmd =
    let
        isKey code =
            if code == key then
                Json.Decode.succeed cmd
            else
                Json.Decode.fail ""
    in
        on "keydown" (Json.Decode.andThen isKey keyCode)
