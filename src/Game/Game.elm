module Game.Game exposing (..)

import Constants exposing (defaultTimer)
import Dict
import Game.Helpers exposing (optionalNullableField)
import Game.Participants exposing (Participants, emptyParticipants, participantsDecoder, participantsEncoder)
import Game.Status exposing (GameStatus, gameStatusDecoder, gameStatusEncoder)
import Game.Teams exposing (Teams, emptyTeams, teamsDecoder, teamsEncoder)
import Game.Words exposing (Words, wordsDecoder, wordsEncoder)
import Json.Decode exposing (Decoder, field, float, int, string)
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


gameStateDecoder : Decoder GameState
gameStateDecoder =
    field "round" int
        |> Json.Decode.andThen
            (\round ->
                Json.Decode.map8
                    (\words teams turnTimer phase revision targetRound deadlineMs turnId ->
                        GameState words teams round turnTimer phase revision targetRound deadlineMs turnId
                    )
                    (optionalNullableField "words" wordsDecoder (Words [] Maybe.Nothing []))
                    (optionalNullableField "teams" teamsDecoder emptyTeams)
                    (field "turnTimer" turnTimerDecoder)
                    (optionalNullableField "phase" gamePhaseDecoder (phaseForRound round))
                    (optionalNullableField "revision" int 0)
                    (optionalNullableField "targetRound" (Json.Decode.map Just int) Nothing)
                    (optionalNullableField "deadlineMs" (Json.Decode.map Just float) Nothing)
                    (optionalNullableField "turnId" int 0)
            )


phaseForRound : Int -> GamePhase
phaseForRound round =
    if round < 0 then
        Lobby

    else if round == 0 then
        AddingWords

    else if round >= 4 then
        GameFinished

    else
        PlayingRound


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
    GameState (Words [] Maybe.Nothing []) emptyTeams -1 (Restarted (defaultTimer * 1000)) Lobby 0 Nothing Nothing 0


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
        "running" ->
            field "deadlineMs" float |> Json.Decode.map Ticking

        "paused" ->
            Json.Decode.oneOf
                [ field "remainingMs" int |> Json.Decode.map NotTicking
                , field "value" int |> Json.Decode.map ((*) 1000 >> NotTicking)
                ]

        "reset" ->
            field "remainingMs" int |> Json.Decode.map Restarted

        "restarted" ->
            field "value" int |> Json.Decode.map ((*) 1000 >> Restarted)

        "ticking" ->
            Json.Decode.fail "legacy running timer has no recoverable deadline"

        _ ->
            Json.Decode.fail "turn timer status unknown"


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



-- Json.Decode.oneOf
-- [ Json.Decode.bool |> Json.Decode.map (\_ -> Ticking), Json.Decode.int |> Json.Decode.map NotTicking ]


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
        , ( "creator", Json.Encode.string game.creator )
        , ( "status", gameStatusEncoder game.status )
        , ( "participants", participantsEncoder game.participants )
        , ( "state", gameStateEncoder game.state )
        , ( "defaultTimer", Json.Encode.int game.defaultTimer )
        ]
