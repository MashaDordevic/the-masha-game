module Player exposing (..)

import Json.Decode exposing (Decoder, field)
import Json.Encode


type alias Player =
    { id : String
    , name : String
    , role : Role
    , status : PlayerStatus
    }


type Role
    = PlayerRole
    | WatcherRole


type PlayerStatus
    = Online
    | Offline


isOnline : Player -> Bool
isOnline player =
    case player.status of
        Online ->
            True

        Offline ->
            False


playerDecoder : Decoder Player
playerDecoder =
    Json.Decode.map4 Player
        (field "id" Json.Decode.string)
        (field "name" Json.Decode.string)
        (field "role" roleDecoder)
        (Json.Decode.succeed Offline)


roleDecoder : Decoder Role
roleDecoder =
    Json.Decode.string
        |> Json.Decode.andThen
            (\role ->
                case role of
                    "player" ->
                        Json.Decode.succeed PlayerRole

                    "watcher" ->
                        Json.Decode.succeed WatcherRole

                    _ ->
                        Json.Decode.fail "player role unknown"
            )


roleEncoder : Role -> Json.Encode.Value
roleEncoder role =
    Json.Encode.string <|
        case role of
            PlayerRole ->
                "player"

            WatcherRole ->
                "watcher"


playerEncoder : Player -> Json.Encode.Value
playerEncoder player =
    Json.Encode.object
        [ ( "id", Json.Encode.string player.id )
        , ( "name", Json.Encode.string player.name )
        , ( "role", roleEncoder player.role )
        ]
