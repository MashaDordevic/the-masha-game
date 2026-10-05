module MainTest exposing (suite)

import Debugger.Update
import Dict
import Expect
import Fixtures.Game
import Game.Game exposing (GamePhase(..), createGameModel)
import Main
import Player exposing (Player, PlayerStatus(..))
import Request
import State exposing (GameModel(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "request navigation reducer"
        [ test "invalidates a pending create before internal navigation" <|
            \_ ->
                CreatingGame
                    { nameInput = "MASHA"
                    , clientRequestId = "client-request"
                    , request = Request.loading 4
                    }
                    |> Main.invalidatePendingNavigation
                    |> Expect.equal (Initial { pinInput = "", instructionSlideNumber = 1 })
        , test "invalidates a pending lookup before internal navigation" <|
            \_ ->
                LoadingGameToJoin
                    { gameCode = "ABCDE"
                    , request = Request.loading ( 5, "ABCDE" )
                    }
                    |> Main.invalidatePendingNavigation
                    |> Expect.equal (Initial { pinInput = "", instructionSlideNumber = 1 })
        , test "removes a fixture player locally" <|
            \_ ->
                Player "owner" "OWNER" Online True
                    |> createGameModel
                    |> Fixtures.Game.lobbyGame
                    |> Debugger.Update.removePlayer "2"
                    |> .participants
                    |> .players
                    |> Dict.member "2"
                    |> Expect.equal False
        , test "starts a local animation from a committed interstitial" <|
            \_ ->
                let
                    game =
                        Player "owner" "OWNER" Online True
                            |> createGameModel

                    state =
                        game.state

                    betweenRoundsGame =
                        { game
                            | state =
                                { state
                                    | phase = BetweenRounds
                                    , revision = 3
                                    , targetRound = Just 2
                                }
                        }
                in
                Main.betweenRoundsAnimation betweenRoundsGame
                    |> Expect.equal
                        (Just
                            { revision = 3
                            , targetRound = 2
                            }
                        )
        , test "does not invent an animation without a target round" <|
            \_ ->
                let
                    game =
                        Player "owner" "OWNER" Online True
                            |> createGameModel

                    state =
                        game.state
                in
                Main.betweenRoundsAnimation
                    { game
                        | state =
                            { state
                                | phase = BetweenRounds
                                , targetRound = Nothing
                            }
                    }
                    |> Expect.equal Nothing
        , test "keeps an active animation after shared gameplay advances" <|
            \_ ->
                let
                    game =
                        Player "owner" "OWNER" Online True
                            |> createGameModel

                    animation =
                        { revision = 3, targetRound = 2 }
                in
                Main.animationAfterGameChange Nothing (Just animation) game
                    |> Expect.equal (Just animation)
        , test "does not restart an animation the client already finished" <|
            \_ ->
                let
                    game =
                        Player "owner" "OWNER" Online True
                            |> createGameModel

                    state =
                        game.state

                    betweenRoundsGame =
                        { game
                            | state =
                                { state
                                    | phase = BetweenRounds
                                    , revision = 3
                                    , targetRound = Just 2
                                }
                        }
                in
                Main.animationAfterGameChange (Just 3) Nothing betweenRoundsGame
                    |> Expect.equal Nothing
        ]
