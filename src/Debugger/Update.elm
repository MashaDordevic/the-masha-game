module Debugger.Update exposing (..)

import Dict
import Fixtures.Game exposing (emptyGame, getPlayerOnTurn, guessNextWords, lobbyGame, newlyStartedGame, restartWordsToFixture)
import Game.Game exposing (Game)
import Game.Teams exposing (advanceCurrentTeam)
import Maybe exposing (withDefault)
import Player exposing (Player)
import State exposing (GameModel(..), LocalUser(..), Model, Msg(..), PlayingGameModel)
import Game.Words exposing (restartWords)


upadateGame : PlayingGameModel -> Game -> GameModel
upadateGame gameModel game =
    let
        localUser =
            case gameModel.localUser of
                LocalPlayer p ->
                    p

                LocalWatcher w ->
                    w

        newLocalUser =
            Dict.values game.participants.players
                |> List.head
                |> withDefault localUser
                |> LocalPlayer
    in
    Playing { gameModel | game = game, localUser = newLocalUser }


getOwner : PlayingGameModel -> Maybe Player
getOwner gameModel =
    gameModel.game.participants.players
        |> Dict.toList
        |> List.map Tuple.second
        |> List.filter
            (\pl -> pl.isOwner)
        |> List.head


isOwner : PlayingGameModel -> Player -> Bool
isOwner gameModel player =
    let
        owner =
            getOwner gameModel
    in
    case owner of
        Just own ->
            own.id == player.id

        Nothing ->
            False


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case model.currentGame of
        Playing gameModel ->
            case msg of
                DebugRestart ->
                    ( { model | currentGame = upadateGame gameModel (emptyGame gameModel.game) }, Cmd.none )

                DebugLobby ->
                    ( { model | currentGame = upadateGame gameModel (lobbyGame gameModel.game) }, Cmd.none )

                DebugStarted ->
                    ( { model | currentGame = upadateGame gameModel (newlyStartedGame gameModel.game) }, Cmd.none )

                DebugRestartWords ->
                    ( { model | currentGame = upadateGame gameModel (restartWordsToFixture gameModel.game) }, Cmd.none )

                DebugSetNextPlayer ->
                    let
                        newTeams =
                            advanceCurrentTeam gameModel.game.state.teams

                        oldState =
                            gameModel.game.state

                        newState =
                            { oldState | teams = newTeams }

                        oldGame =
                            gameModel.game

                        newGame =
                            { oldGame | state = newState }
                    in
                    ( { model | currentGame = upadateGame gameModel newGame }, Cmd.none )

                DebugSetPlayerOnTurn ->
                    let
                        playerOnTurn =
                            getPlayerOnTurn gameModel.game
                    in
                    case playerOnTurn of
                        Just player ->
                            ( { model | currentGame = Playing { gameModel | localUser = LocalPlayer player } }, Cmd.none )

                        Maybe.Nothing ->
                            ( model, Cmd.none )

                DebugSetPlayerOwner ->
                    case getOwner gameModel of
                        Just player ->
                            ( { model | currentGame = Playing { gameModel | localUser = LocalPlayer player, isOwner = True } }, Cmd.none )

                        Maybe.Nothing ->
                            ( model, Cmd.none )

                DebugGuessNextWords ->
                    ( { model | currentGame = upadateGame gameModel (guessNextWords gameModel.game) }, Cmd.none )

                DebugSetRound newRound ->
                    let
                        oldState = gameModel.game.state
                        newWords = restartWords oldState.words
                        newState = { oldState | words = newWords, round = newRound }
                        oldGame = gameModel.game
                        newGame = { oldGame | state = newState }
                    in
                    ( { model | currentGame = upadateGame gameModel newGame }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )
