module Fixtures.State exposing (..)

import Fixtures.Teams exposing (defaultTestTeams)
import Game.Game exposing (GameState)
import Game.Words exposing (Word, Words)


emptyTestState : Game.Game.GameState
emptyTestState =
    GameState (Words [] Maybe.Nothing []) defaultTestTeams -1 (Game.Game.Restarted 60000) Game.Game.Lobby 0 Nothing Nothing 0


wordsList : List Word
wordsList =
    [ Word "desk" "p1" ""
    , Word "keyboard" "p1" ""
    , Word "computer" "p1" ""
    , Word "orange" "p2" ""
    , Word "mango" "p2" ""
    , Word "apple" "p2" ""
    , Word "glass" "p21" ""
    , Word "cup" "p21" ""
    , Word "plate" "p21" ""
    ]


words : Words
words =
    Words [] Maybe.Nothing wordsList


defaultTestState : Game.Game.GameState
defaultTestState =
    GameState words defaultTestTeams 1 (Game.Game.Restarted 60000) Game.Game.PlayingRound 2 Nothing Nothing 1
