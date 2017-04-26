module Extra exposing (..)

import Html exposing (..)
import Html.Events exposing (..)
import Json.Decode


keyEnter : number
keyEnter =
    13


keyEsc : number
keyEsc =
    27


onKeyDown : List ( Int, msg ) -> Attribute msg
onKeyDown mapping =
    let
        isKey : ( Int, msg ) -> Int -> Json.Decode.Decoder msg
        isKey ( key, cmd ) code =
            if code == key then
                Json.Decode.succeed cmd
            else
                Json.Decode.fail ""

        isMappedKey : Int -> Json.Decode.Decoder msg
        isMappedKey code =
            List.map isKey mapping
                |> List.map (\x -> x code)
                |> Json.Decode.oneOf
    in
        on "keydown" (Json.Decode.andThen isMappedKey keyCode)
