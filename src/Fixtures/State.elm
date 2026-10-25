module Fixtures.State exposing (..)

import Fixtures.Teams exposing (defaultTestTeams)
import Game.Game exposing (GameState)
import Game.Words exposing (Word, Words)


emptyTestState : Game.Game.GameState
emptyTestState =
    GameState (Words [] Maybe.Nothing []) defaultTestTeams -1 (Game.Game.Restarted 60000) Game.Game.Lobby 0 Nothing Nothing 0


wordsList : List Word
wordsList =
    [ Word "desk" "1" ""
    , Word "keyboard" "1" ""
    , Word "computer" "1" ""
    , Word "orange" "2" ""
    , Word "mango" "2" ""
    , Word "apple" "2" ""
    , Word "glass" "2-1" ""
    , Word "cup" "2-1" ""
    , Word "plate" "2-1" ""
    ]


words : Words
words =
    Words [] Maybe.Nothing wordsList


defaultTestState : Game.Game.GameState
defaultTestState =
    GameState words defaultTestTeams 1 (Game.Game.Restarted 60000) Game.Game.PlayingRound 2 Nothing Nothing 1
