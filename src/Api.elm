module Api exposing (..)

import Game.Game exposing (Game, gameDecoder)
import Game.Words exposing (Word, wordEncoder)
import Http
import Json.Decode
import Json.Encode
import Player exposing (Player, playerDecoder)
import State exposing (..)


deleteWord : String -> String -> String -> String -> Cmd Msg
deleteWord apiUrl authToken gameId wordId =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/deleteWord"
        , body =
            Http.jsonBody <|
                Json.Encode.object
                    [ ( "gameId", Json.Encode.string gameId )
                    , ( "wordId", Json.Encode.string wordId )
                    ]
        , expect = Http.expectString NoOpResult
        , timeout = Nothing
        , tracker = Nothing
        }


addWord : String -> String -> String -> Word -> Cmd Msg
addWord apiUrl authToken gameId word =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/addWord"
        , body =
            Http.jsonBody <|
                Json.Encode.object
                    [ ( "gameId", Json.Encode.string gameId )
                    , ( "word", wordEncoder word )
                    ]
        , expect = Http.expectString WordAdded
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
            Http.jsonBody <|
                Json.Encode.object
                    [ ( "userId", Json.Encode.string userId )
                    , ( "gameId", Json.Encode.string gameId )
                    ]
        , expect = Http.expectString NoOpResult
        , timeout = Nothing
        , tracker = Nothing
        }


joinGame : String -> String -> String -> String -> Cmd Msg
joinGame apiUrl authToken gameId username =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/joinGame"
        , body =
            Http.jsonBody <|
                Json.Encode.object
                    [ ( "gameId", Json.Encode.string gameId )
                    , ( "username", Json.Encode.string username )
                    ]
        , expect = Http.expectJson JoinedGame joinedGameResponseDecoder
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


findGame : String -> String -> Cmd Msg
findGame apiUrl gameCode =
    Http.get
        { url = apiUrl ++ "/findGame?gameId=" ++ gameCode
        , expect = Http.expectJson GameFound gameDecoder
        }


addedGameResponseDecoder : Json.Decode.Decoder ( Game, Player )
addedGameResponseDecoder =
    Json.Decode.map2 Tuple.pair
        (Json.Decode.field "game" gameDecoder)
        (Json.Decode.field "player" playerDecoder)


createAddGameRequestBody : String -> Game -> Http.Body
createAddGameRequestBody username game =
    Http.jsonBody <|
        Json.Encode.object
            [ ( "game", Game.Game.gameEncoder game )
            , ( "username", Json.Encode.string username )
            ]


addGame : String -> String -> String -> Game -> Cmd Msg
addGame apiUrl authToken username game =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ authToken) ]
        , url = apiUrl ++ "/addGame"
        , body = createAddGameRequestBody username game
        , expect = Http.expectJson GameAdded addedGameResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
