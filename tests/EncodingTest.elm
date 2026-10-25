module EncodingTest exposing (suite)

import Dict
import Expect
import Game.Game exposing (GamePhase(..), TurnTimer(..), gameDecoder, gameEncoder)
import Game.Teams exposing (Team, Teams)
import Game.Words exposing (Word, Words)
import Json.Decode as Decode
import Json.Encode as Encode
import Player exposing (Role(..))
import Test exposing (Test, describe, test)
import GameFixture exposing (gameFor, player)


canonicalGame =
    let
        owner =
            player "owner" "OWNER" PlayerRole

        game =
            gameFor owner

        state =
            game.state
    in
    { game
        | state =
            { state
                | round = 1
                , phase = PlayingRound
                , revision = 4
                , turnId = 2
                , turnTimer = Ticking 15000
                , words = Words [] (Just (Word "OTTER" owner.id "word-1")) []
                , teams = Teams (Just (Team [ owner.id ] 3)) []
            }
    }


suite : Test
suite =
    describe "canonical game codec"
        [ test "round-trips schema version 1" <|
            \_ ->
                let
                    stored =
                        let
                            game =
                                canonicalGame

                            participants =
                                game.participants
                        in
                        { game
                            | participants =
                                { participants
                                    | players =
                                        Dict.map (\_ storedPlayer -> { storedPlayer | status = Player.Offline }) participants.players
                                }
                        }
                in
                stored
                    |> gameEncoder
                    |> Encode.encode 0
                    |> Decode.decodeString gameDecoder
                    |> Expect.equal (Ok stored)
        , test "rejects a game without the canonical schema version" <|
            \_ ->
                """{"id":"game","gameId":"ABCDE","creator":"OWNER","status":"open","defaultTimer":60,"participants":{"players":{}},"state":{"round":-1}}"""
                    |> Decode.decodeString gameDecoder
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]
