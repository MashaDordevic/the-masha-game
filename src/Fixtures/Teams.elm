module Fixtures.Teams exposing (..)

import Dict
import Game.Teams exposing (Team, Teams)
import Player exposing (Player, PlayerStatus(..), Role(..))


testPlayers4 =
    Dict.fromList
        [ ( "1", Player "1" "p1" PlayerRole Online )
        , ( "2", Player "2" "p2" PlayerRole Online )
        , ( "2-1", Player "2-1" "p21" PlayerRole Online )
        , ( "2-2", Player "2-2" "p22" PlayerRole Online )
        ]


testPlayers6 =
    Dict.fromList
        [ ( "1", Player "1" "p1" PlayerRole Online )
        , ( "2", Player "2" "p2" PlayerRole Online )
        , ( "2-1", Player "2-1" "p21" PlayerRole Online )
        , ( "2-2", Player "2-2" "p22" PlayerRole Online )
        , ( "3-1", Player "3-1" "p31" PlayerRole Online )
        , ( "3-2", Player "3-2" "p32" PlayerRole Online )
        ]


defaultTestTeams =
    Teams (Just (Team [ "1", "2" ] 0)) [ Team [ "2-1", "2-2" ] 0, Team [ "3-1", "3-2" ] 0 ]
