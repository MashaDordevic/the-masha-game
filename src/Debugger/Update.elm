module Debugger.Update exposing (..)

import Dict
import Fixtures.Game exposing (emptyGame, getPlayerOnTurn, guessNextWords, lobbyGame, newlyStartedGame, restartWordsToFixture, rotateCurrentTeam)
import Game.Game exposing (Game)
import Maybe exposing (withDefault)
import Player exposing (Player)
import State exposing (GameModel(..), LocalUser(..), Model, Msg(..), PlayingGameModel)


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
    Playing { gameModel | game = game, localUser = newLocalUser, isDebugFixture = True }


removePlayer : String -> Game -> Game
removePlayer playerId game =
    let
        participants =
            game.participants
    in
    { game
        | participants =
            { participants | players = Dict.remove playerId participants.players }
    }


getOwner : PlayingGameModel -> Maybe Player
getOwner gameModel =
    Dict.get gameModel.game.ownerId gameModel.game.participants.players


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
                    ( { model | currentGame = upadateGame gameModel (rotateCurrentTeam gameModel.game) }, Cmd.none )

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
                            ( { model | currentGame = Playing { gameModel | localUser = LocalPlayer player } }, Cmd.none )

                        Maybe.Nothing ->
                            ( model, Cmd.none )

                DebugGuessNextWords ->
                    ( { model | currentGame = upadateGame gameModel (guessNextWords gameModel.game) }, Cmd.none )

                DebugSetRound newRound ->
                    let
                        oldGame =
                            gameModel.game

                        oldState =
                            oldGame.state

                        newGame =
                            { oldGame | state = { oldState | round = newRound } }
                    in
                    ( { model | currentGame = upadateGame gameModel newGame }, Cmd.none )

                KickPlayer playerId ->
                    ( { model | currentGame = upadateGame gameModel (removePlayer playerId gameModel.game) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )
