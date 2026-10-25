module Fixtures.Game exposing (..)

import Dict
import Fixtures.State exposing (defaultTestState)
import Fixtures.Teams exposing (testPlayers4, testPlayers6)
import Game.Game exposing (Game)
import Game.Participants exposing (Participants)
import Game.Status
import Game.Words exposing (Words)
import Player exposing (Player)


emptyGame : Game -> Game
emptyGame game =
    { game | ownerId = "", participants = Participants Dict.empty, state = defaultTestState, turnDurationMs = 60000, schemaVersion = 1 }


lobbyGame : Game -> Game
lobbyGame game =
    { game | ownerId = "1", status = Game.Status.Open, participants = Participants testPlayers4, state = defaultTestState, turnDurationMs = 60000, schemaVersion = 1 }


newlyStartedGame : Game -> Game
newlyStartedGame game =
    { game | ownerId = "1", status = Game.Status.Running, participants = Participants testPlayers6, state = defaultTestState, turnDurationMs = 60000, schemaVersion = 1 }


restartWordsToFixture : Game -> Game
restartWordsToFixture game =
    let
        oldState =
            game.state

        newState =
            { oldState | words = Fixtures.State.words }
    in
    { game | state = newState }


getPlayerOnTurn : Game -> Maybe Player
getPlayerOnTurn game =
    game.state.teams.current
        |> Maybe.andThen (\team -> List.head team.playerIds)
        |> Maybe.andThen (\playerId -> Dict.get playerId game.participants.players)


guessNextWords : Game -> Game
guessNextWords game =
    let
        newWords =
            Words (game.state.words.next ++ game.state.words.guessed) game.state.words.current []

        oldState =
            game.state
    in
    { game | state = { oldState | words = newWords } }


rotateCurrentTeam : Game -> Game
rotateCurrentTeam game =
    let
        oldState =
            game.state

        teams =
            oldState.teams

        rotated =
            case teams.current of
                Just team ->
                    case team.playerIds of
                        first :: rest ->
                            { teams | current = Just { team | playerIds = rest ++ [ first ] } }

                        [] ->
                            teams

                Nothing ->
                    teams
    in
    { game | state = { oldState | teams = rotated } }
