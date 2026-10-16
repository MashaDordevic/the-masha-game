module Views.Playing.Info exposing (..)

import Constants exposing (countdownMoment)
import Game.Game exposing (Game, TurnTimer)
import Game.Gameplay exposing (isLocalPlayersTurn)
import Html exposing (Html, button, div, h1, span, text)
import Html.Attributes exposing (class, classList)
import Html.Events exposing (onClick)
import State exposing (LocalUser(..), Msg(..))


wordsLeft : Game -> Bool -> Html Msg
wordsLeft game isExplaining =
    let
        wordsLeftCount =
            case game.state.words.current of
                Just _ ->
                    1 + List.length game.state.words.next

                Nothing ->
                    List.length game.state.words.next
    in
    div [ classList [ ( "info-container", True ), ( "small", isExplaining ) ] ]
        [ h1 [] [ text (String.fromInt wordsLeftCount) ]
        , span []
            [ text "words left"
            ]
        ]


timeLeft : Int -> Html Msg
timeLeft localTimer =
    div [ class "info-container" ]
        [ h1 [ classList [ ( "info-timer", Basics.True ), ( "countdown10", localTimer <= countdownMoment ) ] ] [ text (String.fromInt localTimer) ]
        , span []
            [ text "seconds"
            ]
        ]


previousWord : Game -> Html Msg
previousWord game =
    let
        prevWord =
            List.head game.state.words.guessed
    in
    case prevWord of
        Just word ->
            div [ class "info-container", class "previous-word" ]
                [ h1 [] [ text word.word ]
                , span [] [ text "previous" ]
                ]

        Nothing ->
            text ""


getTimerString : TurnTimer -> String
getTimerString turnTimer =
    case turnTimer of
        Game.Game.Ticking _ ->
            "Pause"

        Game.Game.NotTicking _ ->
            "Continue"

        Game.Game.Restarted _ ->
            ""


timerButton : Game -> Bool -> Html Msg
timerButton game isExplaining =
    let
        timerString =
            getTimerString game.state.turnTimer

        shouldShowButton =
            case game.state.turnTimer of
                Game.Game.Restarted _ ->
                    Basics.False

                _ ->
                    True
    in
    if isExplaining then
        div [ class "timer-button-container" ]
            [ if shouldShowButton then
                button [ class "timer-button", onClick SwitchTimer ]
                    [ span [ class "material-icons" ] [ text "access_time" ]
                    , span [] [ text timerString ]
                    ]

              else
                text ""
            ]

    else
        text ""


infoView : Game -> LocalUser -> Int -> Html Msg
infoView game localUser localTimer =
    let
        isExplaining =
            case localUser of
                LocalPlayer localPlayer ->
                    Game.Gameplay.isExplaining game localPlayer

                LocalWatcher _ ->
                    False

        shouldSeePreviousWord =
            case localUser of
                LocalPlayer localPlayer ->
                    not (isLocalPlayersTurn game localPlayer)

                LocalWatcher _ ->
                    True
    in
    div
        [ classList [ ( "turn-stats", True ), ( "section", True ), ( "on-turn", isExplaining ) ] ]
        [ wordsLeft game isExplaining
        , timeLeft localTimer
        , if shouldSeePreviousWord then
            previousWord game

          else
            text ""
        , timerButton game isExplaining
        ]
