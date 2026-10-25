module GameFixture exposing (gameFor, player)

import Dict
import Game.Game exposing (Game, emptyGameState)
import Game.Participants exposing (Participants)
import Game.Status exposing (GameStatus(..))
import Player exposing (Player, PlayerStatus(..), Role(..))


player : String -> String -> Role -> Player
player id name role =
    Player id name role Online


gameFor : Player -> Game
gameFor owner =
    { id = "game"
    , gameId = "ABCDE"
    , ownerId = owner.id
    , status = Open
    , participants = Participants (Dict.singleton owner.id owner)
    , state = emptyGameState
    , turnDurationMs = 60000
    , schemaVersion = 1
    }
