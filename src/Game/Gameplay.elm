module Game.Gameplay exposing (..)

import Dict exposing (Dict)
import Game.Game exposing (Game, GamePhase(..), GameState)
import Game.Teams
import Player exposing (Player, PlayerStatus(..))
import Set exposing (Set)


isRoundEnd : GameState -> Bool
isRoundEnd gameState =
    case gameState.words.current of
        Just _ ->
            False

        Nothing ->
            List.isEmpty gameState.words.next


isLocalPlayersTurn : Game -> Player -> Bool
isLocalPlayersTurn game player =
    game.state.teams.current
        |> Maybe.map (\team -> List.member player.id team.playerIds)
        |> Maybe.withDefault False


isOwner : Game -> Player -> Bool
isOwner game player =
    game.ownerId == player.id


isExplaining : Game -> Player -> Bool
isExplaining game player =
    game.state.teams.current
        |> Maybe.andThen (\team -> List.head team.playerIds)
        |> Maybe.map ((==) player.id)
        |> Maybe.withDefault False


explainer : Game -> Maybe Player
explainer game =
    game.state.teams.current
        |> Maybe.andThen (\team -> List.head team.playerIds)
        |> Maybe.andThen (\playerId -> Dict.get playerId game.participants.players)


teamMembers : Game -> Game.Teams.Team -> List Player
teamMembers game team =
    Game.Teams.members game.participants.players team


withPresence : String -> Set String -> Game -> Game
withPresence localPlayerId onlineIds game =
    let
        participants =
            game.participants

        players =
            Dict.map
                (\_ player ->
                    { player
                        | status =
                            if player.id == localPlayerId || Set.member player.id onlineIds then
                                Online

                            else
                                Offline
                    }
                )
                participants.players
    in
    { game | participants = { participants | players = players } }


type Screen
    = LobbyScreen
    | AddingWordsScreen
    | BetweenRoundsScreen Int
    | PlayingScreen
    | FinishedScreen


screen : Game -> Screen
screen game =
    case game.state.phase of
        Lobby ->
            LobbyScreen

        AddingWords ->
            AddingWordsScreen

        BetweenRounds ->
            BetweenRoundsScreen (Maybe.withDefault (game.state.round + 1) game.state.targetRound)

        PlayingRound ->
            PlayingScreen

        GameFinished ->
            FinishedScreen
