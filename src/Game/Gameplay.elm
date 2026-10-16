module Game.Gameplay exposing (..)

import Dict
import Game.Game exposing (Game, GameState)
import Game.Status
import Game.Teams
import Game.Words
import Player exposing (Player)


isRoundEnd : GameState -> Bool
isRoundEnd gameState =
    case gameState.words.current of
        Just _ ->
            Basics.False

        Nothing ->
            List.isEmpty gameState.words.next


isLocalPlayersTurn : Game -> Player -> Bool
isLocalPlayersTurn game player =
    let
        teamOnTurn =
            game.state.teams.current

        isLocPlayersTurn =
            case teamOnTurn of
                Just currentTeam ->
                    List.member player currentTeam.players

                Nothing ->
                    False
    in
    isLocPlayersTurn


isPlayerOnwer : Game -> Player -> Bool
isPlayerOnwer game player =
    let
        owner =
            game.participants.players
                |> Dict.toList
                |> List.map Tuple.second
                |> List.filter
                    (\pl -> pl.isOwner)
                |> List.head
    in
    case owner of
        Just o ->
            o.id == player.id

        Nothing ->
            False


isExplaining : Game -> Player -> Basics.Bool
isExplaining game player =
    let
        teamOnTurn =
            game.state.teams.current
    in
    case teamOnTurn of
        Just currentTeam ->
            case List.head currentTeam.players of
                Just explainingUser ->
                    explainingUser.id == player.id

                Nothing ->
                    False

        Nothing ->
            False


nextRound : Game -> Game
nextRound game =
    let
        newRound =
            game.state.round + 1

        oldState =
            game.state

        newState =
            case newRound of
                0 ->
                    game.state

                1 ->
                    let
                        newTeams =
                            Game.Teams.createTeams game.participants.players

                        -- shuffle words
                        newWords =
                            Game.Words.failCurrentWord game.state.words
                    in
                    { oldState | teams = newTeams, words = newWords }

                _ ->
                    let
                        newWords =
                            Game.Words.restartWords game.state.words
                    in
                    { oldState | words = newWords }

        newStatus =
            if newRound == 4 then
                Game.Status.Finished

            else
                game.status
    in
    { game | state = { newState | round = newRound }, status = newStatus }
