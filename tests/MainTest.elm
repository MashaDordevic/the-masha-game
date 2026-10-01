module MainTest exposing (suite)

import Expect
import Main
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
        ]
