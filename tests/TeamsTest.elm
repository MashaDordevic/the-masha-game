module TeamsTest exposing (suite)

import Dict
import Expect
import Game.Teams exposing (Team, Teams, getScoreboard, members)
import Player exposing (PlayerStatus(..), Role(..))
import Test exposing (Test, describe, test)
import GameFixture exposing (player)


suite : Test
suite =
    describe "team read model"
        [ test "resolves member ids to players" <|
            \_ ->
                members
                    (Dict.fromList
                        [ ( "1", player "1" "Ada" PlayerRole )
                        , ( "2", player "2" "Bea" PlayerRole )
                        ]
                    )
                    (Team [ "2", "1" ] 3)
                    |> List.map .name
                    |> Expect.equal [ "Bea", "Ada" ]
        , test "orders the scoreboard by score" <|
            \_ ->
                getScoreboard
                    (Teams (Just (Team [ "1" ] 1)) [ Team [ "2" ] 4 ])
                    |> List.map .score
                    |> Expect.equal [ 4, 1 ]
        ]
