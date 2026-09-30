module Debugger.Debugger exposing (..)

import Html exposing (Html, button, div, p, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import State exposing (GameModel(..), LocalUser(..), Model, Msg(..))


debugger : Model -> Html Msg
debugger model =
    let
        urlQueryParam = model.url.query
        isUrlDebuggerEnabled =
            case urlQueryParam of
                Just query ->
                    String.contains "debug=true" query
                Nothing ->
                    False
        isDebuggerEnabled =
            model.environment == "development" || isUrlDebuggerEnabled


        localUserName = case model.currentGame of
                Playing gameModel ->
                   case gameModel.localUser of
                                   LocalPlayer p ->
                                       p.name
                                   LocalWatcher w ->
                                       w.name
                _ ->
                    "unknown"

    in
    if isDebuggerEnabled then
        div [ class "debugger" ]
            [ p [] [ text ("DEBUGGER: " ++ localUserName) ]
            , button [ onClick DebugRestart ] [ text "Restart" ]
            , button [ onClick DebugLobby ] [ text "Lobby" ]
            , button [ onClick DebugStarted ] [ text "Newly started" ]
            , button [ onClick DebugRestartWords ] [ text "Restart words" ]
            , button [ onClick DebugSetNextPlayer ] [ text "Set next player" ]
            , button [ onClick DebugSetPlayerOnTurn ] [ text "Set player on turn" ]
            , button [ onClick DebugSetPlayerOwner ] [ text "Set player owner" ]
            , button [ onClick DebugGuessNextWords ] [ text "Guess next words" ]
            , button [ onClick (DebugSetRound 1) ] [ text "Set round 1" ]
            , button [ onClick (DebugSetRound 2) ] [ text "Set round 2" ]
            ]
    else
        text ""
