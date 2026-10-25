module Api exposing (..)

import Game.Game exposing (Game, gameDecoder)
import Http
import Json.Decode
import Json.Encode
import Player exposing (Player, playerDecoder)
import State exposing (..)


protocolVersion : Int
protocolVersion =
    1


commandBody : List ( String, Json.Encode.Value ) -> Http.Body
commandBody fields =
    Http.jsonBody <|
        Json.Encode.object (( "protocolVersion", Json.Encode.int protocolVersion ) :: fields)


roundTransitionRequest : String -> String -> String -> String -> Int -> (Result Http.Error String -> Msg) -> Cmd Msg
roundTransitionRequest apiUrl authToken gameId endpoint expectedRevision toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/" ++ endpoint
        , body =
            commandBody
                [ ( "gameId", Json.Encode.string gameId )
                , ( "expectedRevision", Json.Encode.int expectedRevision )
                ]
        , expect = Http.expectString toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


enterBetweenRounds : String -> String -> String -> Int -> Cmd Msg
enterBetweenRounds apiUrl authToken gameId expectedRevision =
    roundTransitionRequest apiUrl authToken gameId "enterBetweenRounds" expectedRevision NoOpResult


advanceRound : String -> String -> String -> Int -> Cmd Msg
advanceRound apiUrl authToken gameId expectedRevision =
    roundTransitionRequest apiUrl authToken gameId "advanceRound" expectedRevision NoOpResult


startBetweenRounds : String -> String -> String -> Int -> Cmd Msg
startBetweenRounds apiUrl authToken gameId expectedRevision =
    roundTransitionRequest apiUrl authToken gameId "enterBetweenRounds" expectedRevision StartBetweenRoundsCompleted


startGame : String -> String -> String -> Int -> Cmd Msg
startGame apiUrl authToken gameId expectedRevision =
    roundTransitionRequest apiUrl authToken gameId "startGame" expectedRevision NoOpResult


turnCommandRequest : String -> String -> String -> String -> Int -> Int -> Cmd Msg
turnCommandRequest apiUrl authToken gameId endpoint expectedRevision expectedTurnId =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/" ++ endpoint
        , body =
            commandBody
                [ ( "gameId", Json.Encode.string gameId )
                , ( "expectedRevision", Json.Encode.int expectedRevision )
                , ( "expectedTurnId", Json.Encode.int expectedTurnId )
                ]
        , expect = Http.expectString NoOpResult
        , timeout = Nothing
        , tracker = Nothing
        }


startTurn : String -> String -> String -> Int -> Int -> Cmd Msg
startTurn apiUrl authToken gameId expectedRevision expectedTurnId =
    turnCommandRequest apiUrl authToken gameId "startTurn" expectedRevision expectedTurnId


pauseTurn : String -> String -> String -> Int -> Int -> Cmd Msg
pauseTurn apiUrl authToken gameId expectedRevision expectedTurnId =
    turnCommandRequest apiUrl authToken gameId "pauseTurn" expectedRevision expectedTurnId


guessWord : String -> String -> String -> Int -> Int -> Cmd Msg
guessWord apiUrl authToken gameId expectedRevision expectedTurnId =
    turnCommandRequest apiUrl authToken gameId "guessWord" expectedRevision expectedTurnId


expireTurn : String -> String -> String -> Int -> Int -> Cmd Msg
expireTurn apiUrl authToken gameId expectedRevision expectedTurnId =
    turnCommandRequest apiUrl authToken gameId "expireTurn" expectedRevision expectedTurnId


deleteWord : String -> String -> String -> String -> Cmd Msg
deleteWord apiUrl authToken gameId wordId =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/deleteWord"
        , body =
            commandBody
                [ ( "gameId", Json.Encode.string gameId )
                , ( "wordId", Json.Encode.string wordId )
                ]
        , expect = Http.expectString NoOpResult
        , timeout = Nothing
        , tracker = Nothing
        }


addWord : String -> String -> RequestId -> String -> String -> String -> Cmd Msg
addWord apiUrl authToken requestId gameId wordId text =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/addWord"
        , body =
            commandBody
                [ ( "gameId", Json.Encode.string gameId )
                , ( "wordId", Json.Encode.string wordId )
                , ( "text", Json.Encode.string text )
                ]
        , expect = Http.expectString (WordAdded requestId gameId)
        , timeout = Nothing
        , tracker = Nothing
        }


kickPlayer : String -> String -> String -> String -> Cmd Msg
kickPlayer apiUrl authToken userId gameId =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/kickPlayer"
        , body =
            commandBody
                [ ( "userId", Json.Encode.string userId )
                , ( "gameId", Json.Encode.string gameId )
                ]
        , expect = Http.expectString NoOpResult
        , timeout = Nothing
        , tracker = Nothing
        }


joinGame : String -> String -> RequestId -> String -> String -> Cmd Msg
joinGame apiUrl authToken requestId gameId username =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/joinGame"
        , body =
            commandBody
                [ ( "gameId", Json.Encode.string gameId )
                , ( "displayName", Json.Encode.string username )
                ]
        , expect = Http.expectJson (JoinedGame requestId gameId) joinedGameResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


joinedGameResponseDecoder : Json.Decode.Decoder JoinedGameInfo
joinedGameResponseDecoder =
    Json.Decode.map4 JoinedGameInfo
        (Json.Decode.field "status" Json.Decode.string)
        (Json.Decode.field "role" Json.Decode.string)
        (Json.Decode.field "player" playerDecoder)
        (Json.Decode.field "game" Game.Game.gameDecoder)


findGame : String -> RequestId -> String -> Cmd Msg
findGame apiUrl requestId gameCode =
    Http.get
        { url = apiUrl ++ "/findGame?gameId=" ++ gameCode ++ "&protocolVersion=" ++ String.fromInt protocolVersion
        , expect = Http.expectJson (GameFound requestId gameCode) gameDecoder
        }


addedGameResponseDecoder : Json.Decode.Decoder ( Game, Player )
addedGameResponseDecoder =
    Json.Decode.map2 Tuple.pair
        (Json.Decode.field "game" gameDecoder)
        (Json.Decode.field "player" playerDecoder)


addGame : String -> String -> RequestId -> String -> String -> Cmd Msg
addGame apiUrl authToken requestId clientRequestId username =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/addGame"
        , body =
            commandBody
                [ ( "displayName", Json.Encode.string username )
                , ( "clientRequestId", Json.Encode.string clientRequestId )
                ]
        , expect = Http.expectJson (GameAdded requestId) addedGameResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
