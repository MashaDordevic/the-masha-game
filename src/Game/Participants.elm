module Game.Participants exposing (..)

import Dict exposing (Dict)
import Json.Decode exposing (Decoder, field)
import Json.Encode
import Player exposing (Player, playerDecoder, playerEncoder)


type alias Participants =
    { players : Dict String Player
    }


emptyParticipants : Participants
emptyParticipants =
    Participants Dict.empty


participantsDecoder : Decoder Participants
participantsDecoder =
    Json.Decode.map Participants
        (field "players" (Json.Decode.dict playerDecoder))


participantsEncoder : Participants -> Json.Encode.Value
participantsEncoder participants =
    Json.Encode.object
        [ ( "players", Json.Encode.dict identity playerEncoder participants.players )
        ]
