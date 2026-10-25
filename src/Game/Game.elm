module Game.Game exposing (..)

import Game.Helpers exposing (optionalField, optionalMaybeField)
import Game.Participants exposing (Participants, participantsDecoder, participantsEncoder)
import Game.Status exposing (GameStatus, gameStatusDecoder, gameStatusEncoder)
import Game.Teams exposing (Teams, emptyTeams, teamsDecoder, teamsEncoder)
import Game.Words exposing (Words, wordsDecoder, wordsEncoder)
import Json.Decode exposing (Decoder, field, float, int, string)
import Json.Encode


type alias Game =
    { id : String
    , gameId : String
    , ownerId : String
    , status : GameStatus
    , participants : Participants
    , state : GameState
    , turnDurationMs : Int
    , schemaVersion : Int
    }


type TurnTimer
    = Ticking Float
    | NotTicking Int
    | Restarted Int


type GamePhase
    = Lobby
    | AddingWords
    | BetweenRounds
    | PlayingRound
    | GameFinished


type alias GameState =
    { words : Words
    , teams : Teams
    , round : Int
    , turnTimer : TurnTimer
    , phase : GamePhase
    , revision : Int
    , targetRound : Maybe Int
    , deadlineMs : Maybe Float
    , turnId : Int
    }


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Json.Decode.map2 (|>)


gameStateDecoder : Decoder GameState
gameStateDecoder =
    Json.Decode.succeed GameState
        |> andMap (optionalField "words" wordsDecoder (Game.Words.Words [] Maybe.Nothing []))
        |> andMap (optionalField "teams" teamsDecoder emptyTeams)
        |> andMap (field "round" int)
        |> andMap (field "turnTimer" turnTimerDecoder)
        |> andMap (field "phase" gamePhaseDecoder)
        |> andMap (field "revision" int)
        |> andMap (optionalMaybeField "targetRound" int)
        |> andMap (optionalMaybeField "deadlineMs" float)
        |> andMap (field "turnId" int)


gameStateEncoder : GameState -> Json.Encode.Value
gameStateEncoder gameState =
    Json.Encode.object
        [ ( "words", wordsEncoder gameState.words )
        , ( "teams", teamsEncoder gameState.teams )
        , ( "round", Json.Encode.int gameState.round )
        , ( "turnTimer", turnTimerEncoder gameState.turnTimer )
        , ( "phase", gamePhaseEncoder gameState.phase )
        , ( "revision", Json.Encode.int gameState.revision )
        , ( "targetRound", Maybe.map Json.Encode.int gameState.targetRound |> Maybe.withDefault Json.Encode.null )
        , ( "deadlineMs", Maybe.map Json.Encode.float gameState.deadlineMs |> Maybe.withDefault Json.Encode.null )
        , ( "turnId", Json.Encode.int gameState.turnId )
        ]


emptyGameState : GameState
emptyGameState =
    GameState (Game.Words.Words [] Maybe.Nothing []) emptyTeams -1 (Restarted 60000) Lobby 0 Nothing Nothing 0


gameDecoder : Decoder Game
gameDecoder =
    Json.Decode.map8 Game
        (field "id" Json.Decode.string)
        (field "gameId" Json.Decode.string)
        (field "ownerId" Json.Decode.string)
        (field "status" gameStatusDecoder)
        (field "participants" participantsDecoder)
        (field "state" gameStateDecoder)
        (field "turnDurationMs" int)
        (field "schemaVersion" schemaVersionDecoder)


schemaVersionDecoder : Decoder Int
schemaVersionDecoder =
    int
        |> Json.Decode.andThen
            (\version ->
                if version == 1 then
                    Json.Decode.succeed version

                else
                    Json.Decode.fail "unsupported game schema"
            )


turnTimerDecoder : Decoder TurnTimer
turnTimerDecoder =
    field "status" Json.Decode.string
        |> Json.Decode.andThen
            (\timerType ->
                case timerType of
                    "running" ->
                        field "deadlineMs" float |> Json.Decode.map Ticking

                    "paused" ->
                        field "remainingMs" int |> Json.Decode.map NotTicking

                    "reset" ->
                        field "remainingMs" int |> Json.Decode.map Restarted

                    _ ->
                        Json.Decode.fail "turn timer status unknown"
            )


gamePhaseDecoder : Decoder GamePhase
gamePhaseDecoder =
    string
        |> Json.Decode.andThen
            (\phase ->
                case phase of
                    "lobby" ->
                        Json.Decode.succeed Lobby

                    "addingWords" ->
                        Json.Decode.succeed AddingWords

                    "betweenRounds" ->
                        Json.Decode.succeed BetweenRounds

                    "playing" ->
                        Json.Decode.succeed PlayingRound

                    "finished" ->
                        Json.Decode.succeed GameFinished

                    _ ->
                        Json.Decode.fail "game phase unknown"
            )


gamePhaseEncoder : GamePhase -> Json.Encode.Value
gamePhaseEncoder phase =
    Json.Encode.string <|
        case phase of
            Lobby ->
                "lobby"

            AddingWords ->
                "addingWords"

            BetweenRounds ->
                "betweenRounds"

            PlayingRound ->
                "playing"

            GameFinished ->
                "finished"


turnTimerEncoder : TurnTimer -> Json.Encode.Value
turnTimerEncoder turnTimer =
    case turnTimer of
        Ticking deadlineMs ->
            Json.Encode.object [ ( "status", Json.Encode.string "running" ), ( "deadlineMs", Json.Encode.float deadlineMs ) ]

        NotTicking remainingMs ->
            Json.Encode.object [ ( "status", Json.Encode.string "paused" ), ( "remainingMs", Json.Encode.int remainingMs ) ]

        Restarted remainingMs ->
            Json.Encode.object [ ( "status", Json.Encode.string "reset" ), ( "remainingMs", Json.Encode.int remainingMs ) ]


gameEncoder : Game -> Json.Encode.Value
gameEncoder game =
    Json.Encode.object
        [ ( "id", Json.Encode.string game.id )
        , ( "gameId", Json.Encode.string game.gameId )
        , ( "ownerId", Json.Encode.string game.ownerId )
        , ( "status", gameStatusEncoder game.status )
        , ( "participants", participantsEncoder game.participants )
        , ( "state", gameStateEncoder game.state )
        , ( "turnDurationMs", Json.Encode.int game.turnDurationMs )
        , ( "schemaVersion", Json.Encode.int game.schemaVersion )
        ]
