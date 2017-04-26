module Model exposing (..)

import GitHub
import Html5.DragDrop as DragDrop
import Http
import Json.Decode exposing (field)
import Json.Encode


type Msg
    = DragDrop (DragDrop.Msg DraggableID DroppableID)
    | DelIssueCard Int
    | IssueFetched DroppableID (Result Http.Error GitHub.Issue)
    | IssueRefreshed DroppableID (Result Http.Error GitHub.Issue)
    | RepositoriesFetched (Result Http.Error (List GitHub.Repository))
    | QueryIcelog
    | IcelogSearchChanged String
    | IcelogFetched (Result Http.Error (List GitHub.Issue))
    | ShowIcelog Bool
    | CloseError
    | WsMessage String


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


emptyDroppable : DroppableID
emptyDroppable =
    { position = 1, order = 0 }


type alias Model =
    { cards : List Card
    , dragDrop : DragDrop.Model DraggableID DroppableID
    , rows : Int
    , icelog : List GitHub.Issue
    , icelogQuery : String
    , icelogFetching : Bool
    , showIcelog : Bool
    , error : Maybe String
    , flags : ProgramFlags
    , repositories : List GitHub.Repository
    }


type alias Card =
    { position : Int
    , order : Int
    , issue : GitHub.Issue
    }


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
