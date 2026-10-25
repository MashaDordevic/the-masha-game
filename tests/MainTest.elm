module MainTest exposing (suite)

import Expect
import GameFixture
import Game.Game exposing (GamePhase(..), TurnTimer(..))
import Game.Interstitial exposing (DueTransition(..), dueTransition)
import Game.Timer exposing (remainingSeconds)
import Main
import Player
import Request
import State exposing (GameModel(..))
import Test exposing (Test, describe, test)
import Time


suite : Test
suite =
    describe "presentation reads"
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
        , test "derives paused time from the stored remaining milliseconds" <|
            \_ ->
                remainingSeconds 0 (Time.millisToPosix 0) (NotTicking 12500)
                    |> Expect.equal 13
        , test "derives running time from the deadline and server offset" <|
            \_ ->
                remainingSeconds 500 (Time.millisToPosix 10000) (Ticking 15500)
                    |> Expect.equal 5
        , test "requests the round advance only once the interstitial deadline has passed" <|
            \_ ->
                let
                    game =
                        GameFixture.gameFor (GameFixture.player "owner" "OWNER" Player.PlayerRole)

                    state =
                        game.state

                    betweenRoundsGame =
                        { game
                            | state =
                                { state
                                    | phase = BetweenRounds
                                    , deadlineMs = Just 10500
                                }
                        }
                in
                Expect.all
                    [ \_ ->
                        dueTransition 500 (Time.millisToPosix 10000) betweenRoundsGame
                            |> Expect.equal (Just AdvanceRound)
                    , \_ ->
                        dueTransition 499 (Time.millisToPosix 10000) betweenRoundsGame
                            |> Expect.equal Nothing
                    ]
                    ()
        ]
