module Fixtures.Game exposing (..)

import Dict
import Fixtures.State exposing (defaultTestState)
import Fixtures.Teams exposing (testJoinRequests, testPlayers4, testPlayers6)
import Game.Game exposing (Game)
import Game.Participants exposing (Participants)
import Game.Status
import Game.Words exposing (Words)
import Player exposing (Player)


emptyGame : Game -> Game
emptyGame game =
    { game | participants = Participants Dict.empty Dict.empty, state = defaultTestState, defaultTimer = 60 }


lobbyGame : Game -> Game
lobbyGame game =
    { game | status = Game.Status.Open, participants = Participants testPlayers4 testJoinRequests, state = defaultTestState, defaultTimer = 60 }


newlyStartedGame : Game -> Game
newlyStartedGame game =
    { game | status = Game.Status.Running, participants = Participants testPlayers6 Dict.empty, state = defaultTestState, defaultTimer = 60 }


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
    let
        teamOnTurn =
            game.state.teams.current
    in
    case teamOnTurn of
        Just currentTeam ->
            currentTeam.players
                |> List.head

        Nothing ->
            Maybe.Nothing


guessNextWords : Game -> Game
guessNextWords game =
    let
        newGuessed =
            List.append game.state.words.next game.state.words.guessed

        newWords =
            Words newGuessed game.state.words.current []

        oldState =
            game.state

        newState =
            { oldState | words = newWords }
    in
    { game | state = newState }
