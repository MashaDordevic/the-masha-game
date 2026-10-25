module Views.View exposing (view)

import Browser
import Debugger.Debugger exposing (debugger)
import Game.Gameplay
import Html exposing (div, text)
import Html.Attributes exposing (..)
import State exposing (..)
import Views.AddingWords exposing (addingWordsView)
import Views.BetweenRounds exposing (betweenRoundsView)
import Views.Donate exposing (donateView)
import Views.FinishedGame exposing (finishedGameView)
import Views.Header exposing (headerView)
import Views.Help exposing (helpView)
import Views.Lobby exposing (lobbyView)
import Views.NameInput exposing (gameLookupView, nameInputView)
import Views.Playing.Playing exposing (playingView)
import Views.Start exposing (startView)


view : Model -> Browser.Document Msg
view model =
    { title = "The Masha Game"
    , body =
        [ let
            currView =
                case model.currentGame of
                    Playing gameModel ->
                        case Game.Gameplay.screen gameModel.game of
                            Game.Gameplay.LobbyScreen ->
                                lobbyView gameModel

                            Game.Gameplay.AddingWordsScreen ->
                                addingWordsView gameModel

                            Game.Gameplay.BetweenRoundsScreen targetRound ->
                                betweenRoundsView targetRound

                            Game.Gameplay.PlayingScreen ->
                                playingView model.serverTimeOffsetMs model.now gameModel

                            Game.Gameplay.FinishedScreen ->
                                finishedGameView gameModel.game

                    CreatingGame gameModel ->
                        nameInputView gameModel.nameInput "Creating…" gameModel.request AddGame

                    LoadingGameToJoin gameModel ->
                        gameLookupView gameModel.request

                    JoiningGame gameModel ->
                        nameInputView gameModel.nameInput "Joining…" gameModel.request JoinGame

                    Initial gameModel ->
                        startView gameModel model.errors

            showHeader =
                case model.currentGame of
                    Initial _ ->
                        Basics.False

                    _ ->
                        Basics.True
          in
          div [ class "page-wrapper" ]
            [ div [ class "page-container" ]
                [ if showHeader then
                    headerView

                  else
                    text ""
                , currView
                ]
            , donateView model
            , helpView model
            , debugger model
            ]
        ]
    }
