module MainTest exposing (suite)

import Debugger.Update
import Dict
import Expect
import Fixtures.Game
import Game.Game exposing (createGameModel)
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
        ]
