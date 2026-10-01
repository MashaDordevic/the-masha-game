module Game.Game exposing (..)

import Constants exposing (defaultTimer)
import Dict
import Game.Helpers exposing (optionalNullableField)
import Game.Participants exposing (Participants, emptyParticipants, participantsDecoder, participantsEncoder)
import Game.Status exposing (GameStatus, gameStatusDecoder, gameStatusEncoder)
import Game.Teams exposing (Teams, emptyTeams, teamsDecoder, teamsEncoder)
import Game.Words exposing (Words, wordsDecoder, wordsEncoder)
import Json.Decode exposing (Decoder, field, int)
import Json.Encode
import Player exposing (Player)


type alias FindGame =
    { gameId : String
    }


type alias Game =
    { id : String
    , gameId : String
    , creator : String
    , status : GameStatus
    , participants : Participants
    , state : GameState
    , defaultTimer : Int
    }


type TurnTimer
    = Ticking
    | NotTicking Int
    | Restarted Int


type alias GameState =
    { words : Words
    , teams : Teams
    , round : Int
    , turnTimer : TurnTimer
    }


gameStateDecoder : Decoder GameState
gameStateDecoder =
    Json.Decode.map4 GameState
        (optionalNullableField "words" wordsDecoder (Words [] Maybe.Nothing []))
        (optionalNullableField "teams" teamsDecoder emptyTeams)
        (field "round" int)
        (field "turnTimer" turnTimerDecoder)


gameStateEncoder : GameState -> Json.Encode.Value
gameStateEncoder gameState =
    Json.Encode.object
        [ ( "words", wordsEncoder gameState.words )
        , ( "teams", teamsEncoder gameState.teams )
        , ( "round", Json.Encode.int gameState.round )
        , ( "turnTimer", turnTimerEncoder gameState.turnTimer )
        ]


emptyGameState : GameState
emptyGameState =
    GameState (Words [] Maybe.Nothing []) emptyTeams -1 (Restarted defaultTimer)


createGameModel : Player -> Game
createGameModel player =
    let
        -- will be overwritten once created and once player gets an ID
        participants =
            Participants Dict.empty Dict.empty
    in
    Game "" "" player.name Game.Status.Open participants emptyGameState defaultTimer


gameDecoder : Decoder Game
gameDecoder =
    Json.Decode.map7 Game
        (field "id" Json.Decode.string)
        (field "gameId" Json.Decode.string)
        (field "creator" Json.Decode.string)
        (field "status" gameStatusDecoder)
        (optionalNullableField "participants" participantsDecoder emptyParticipants)
        (optionalNullableField "state" gameStateDecoder emptyGameState)
        (field "defaultTimer" int)


turnTimerDecoder : Decoder TurnTimer
turnTimerDecoder =
    field "status" Json.Decode.string
        |> Json.Decode.andThen turnTimerTypeDecoder


turnTimerTypeDecoder : String -> Decoder TurnTimer
turnTimerTypeDecoder timerType =
    case timerType of
        "ticking" ->
            Json.Decode.succeed Ticking

        "paused" ->
            field "value" Json.Decode.int |> Json.Decode.map NotTicking

        "restarted" ->
            field "value" Json.Decode.int |> Json.Decode.map Restarted

        _ ->
            Json.Decode.fail "turn timer status unknown"



-- Json.Decode.oneOf
-- [ Json.Decode.bool |> Json.Decode.map (\_ -> Ticking), Json.Decode.int |> Json.Decode.map NotTicking ]


turnTimerEncoder : TurnTimer -> Json.Encode.Value
turnTimerEncoder turnTimer =
    case turnTimer of
        Ticking ->
            Json.Encode.object [ ( "status", Json.Encode.string "ticking" ) ]

        NotTicking timerValue ->
            Json.Encode.object [ ( "status", Json.Encode.string "paused" ), ( "value", Json.Encode.int timerValue ) ]

        Restarted timerValue ->
            Json.Encode.object [ ( "status", Json.Encode.string "restarted" ), ( "value", Json.Encode.int timerValue ) ]


gameEncoder : Game -> Json.Encode.Value
gameEncoder game =
    Json.Encode.object
        [ ( "id", Json.Encode.string game.id )
        , ( "gameId", Json.Encode.string game.gameId )
        , ( "creator", Json.Encode.string game.creator )
        , ( "status", gameStatusEncoder game.status )
        , ( "participants", participantsEncoder game.participants )
        , ( "state", gameStateEncoder game.state )
        , ( "defaultTimer", Json.Encode.int game.defaultTimer )
        ]
