module TeamsTest exposing (..)

import Dict
import Expect
import Game.Teams exposing (Team, Teams, advanceCurrentTeam, createTeams, getScoreboard, increaseCurrentTeamsScore, shiftTeamPlayers, teamToString)
import Player exposing (Player, PlayerStatus(..))
import Test exposing (..)


sortWithTeamName : Team -> Team -> Basics.Order
sortWithTeamName a b =
    Basics.compare (teamToString a.players) (teamToString b.players)


sortTeams : Teams -> Teams
sortTeams teams =
    Teams teams.current (List.sortWith sortWithTeamName teams.next)


suit : Test
suit =
    describe "Teams"
        [ test "shiftTeamPlayers with two players" <|
            \_ ->
                shiftTeamPlayers (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)
                    |> Expect.equal (Team [ Player "2" "p2" Online False, Player "1" "p1" Online False ] 0)
        , test "shiftTeamPlayers with three players" <|
            \_ ->
                shiftTeamPlayers (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False, Player "3" "p3" Online False ] 0)
                    |> Expect.equal (Team [ Player "2" "p2" Online False, Player "3" "p3" Online False, Player "1" "p1" Online False ] 0)
        , test "advanceCurrentTeam" <|
            \_ ->
                advanceCurrentTeam (Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ])
                    |> Expect.equal (Teams (Just (Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10)) [ Team [ Player "2" "p2" Online False, Player "1" "p1" Online False ] 0 ])
        , test "advanceCurrentTeam empty" <|
            \_ ->
                advanceCurrentTeam (Teams Maybe.Nothing [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ])
                    |> Expect.equal (Teams (Just (Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10)) [])
        , test "advanceCurrentTeam one team" <|
            \_ ->
                advanceCurrentTeam (Teams (Just (Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10)) [])
                    |> Expect.equal (Teams (Just (Team [ Player "2-2" "p22" Online False, Player "2-1" "p21" Online False ] 10)) [])
        , test "increaseCurrentTeamsScore" <|
            \_ ->
                increaseCurrentTeamsScore (Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ])
                    |> Expect.equal (Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 1)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ])
        , test "createTeams" <|
            \_ ->
                let
                    teams =
                        createTeams (Dict.fromList [ ( "1", Player "1" "p1" Online False ), ( "2", Player "2" "p2" Online False ), ( "3", Player "3" "p3" Online False ), ( "4", Player "4" "p4" Online False ), ( "5", Player "5" "p5" Online False ), ( "6", Player "6" "p6" Online False ), ( "7", Player "7" "p7" Online False ), ( "8", Player "8" "p8" Online False ) ])
                in
                Expect.all
                    [ .current >> Expect.notEqual Maybe.Nothing
                    , .next
                        >> List.length
                        >> Expect.equal 3
                    , .next
                        >> List.map (.players >> List.length)
                        >> Expect.equal [ 2, 2, 2 ]
                    ]
                    teams
        , test "createTeams uneven" <|
            \_ ->
                let
                    teams =
                        createTeams (Dict.fromList [ ( "1", Player "1" "p1" Online False ), ( "2", Player "2" "p2" Online False ), ( "3", Player "3" "p3" Online False ), ( "4", Player "4" "p4" Online False ), ( "5", Player "5" "p5" Online False ), ( "6", Player "6" "p6" Online False ), ( "7", Player "7" "p7" Online False ), ( "8", Player "8" "p8" Online False ), ( "9", Player "9" "p9" Online False ) ])
                in
                Expect.all
                    [ .current >> Expect.notEqual Maybe.Nothing
                    , .next
                        >> List.length
                        >> Expect.equal 3
                    , .next
                        >> List.map (.players >> List.length)
                        >> Expect.equal [ 2, 2, 3 ]
                    ]
                    teams
        , test "getScoreboard" <|
            \_ ->
                let
                    teams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 15)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10, Team [ Player "3-1" "p31" Online False, Player "3-2" "p32" Online False ] 12 ]
                in
                getScoreboard teams
                    |> Expect.equal [ Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 15, Team [ Player "3-1" "p31" Online False, Player "3-2" "p32" Online False ] 12, Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]
        ]
