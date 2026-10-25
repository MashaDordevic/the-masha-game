module Game.Teams exposing (..)

import Dict exposing (Dict)
import Game.Helpers exposing (optionalField, optionalMaybeField)
import Json.Decode exposing (Decoder, field)
import Json.Encode
import Player exposing (Player)


type alias Team =
    { playerIds : List String
    , score : Int
    }


type alias Teams =
    { current : Maybe Team
    , next : List Team
    }


emptyTeams : Teams
emptyTeams =
    Teams Maybe.Nothing []


members : Dict String Player -> Team -> List Player
members players team =
    team.playerIds
        |> List.filterMap (\playerId -> Dict.get playerId players)


getScoreboard : Teams -> List Team
getScoreboard teams =
    let
        queued =
            case teams.current of
                Just team ->
                    team :: teams.next

                Nothing ->
                    teams.next
    in
    List.sortBy (\team -> negate team.score) queued


teamsDecoder : Decoder Teams
teamsDecoder =
    Json.Decode.map2 Teams
        (optionalMaybeField "current" teamDecoder)
        (optionalField "next" (Json.Decode.list teamDecoder) [])


teamsEncoder : Teams -> Json.Encode.Value
teamsEncoder teams =
    Json.Encode.object
        [ ( "current", Maybe.map teamEncoder teams.current |> Maybe.withDefault Json.Encode.null )
        , ( "next", Json.Encode.list teamEncoder teams.next )
        ]


teamDecoder : Decoder Team
teamDecoder =
    Json.Decode.map2 Team
        (field "playerIds" (Json.Decode.list Json.Decode.string))
        (field "score" Json.Decode.int)


teamEncoder : Team -> Json.Encode.Value
teamEncoder team =
    Json.Encode.object
        [ ( "playerIds", Json.Encode.list Json.Encode.string team.playerIds )
        , ( "score", Json.Encode.int team.score )
        ]
