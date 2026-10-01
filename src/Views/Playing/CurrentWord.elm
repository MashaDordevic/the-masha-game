module Views.Playing.CurrentWord exposing (..)

import Constants exposing (countdownMoment)
import Game.Game exposing (Game)
import Game.Gameplay exposing (isExplaining)
import Game.Words exposing (Word)
import Html exposing (Html, button, div, h1, h3, text)
import Html.Attributes exposing (class, classList)
import Html.Events exposing (onClick)
import State exposing (LocalUser(..), Msg(..))


start : Html Msg
start =
    div [ class "current-word-container", class "section" ]
        [ h3 [ class "show-first" ] [ text "It’s your turn" ]
        , h3 [ class "show-second" ] [ text "You’ll see the word here" ]
        , button [ class "show-third", onClick SwitchTimer ] [ text "Start" ]
        ]


currentWord : Word -> Int -> Html Msg
currentWord word turnTimer =
    div [ class "section" ]
        [ div [ classList [ ( "current-word-border", True ), ( "countdown10", turnTimer <= countdownMoment ) ] ]
            [ div [ class "current-word-container", class "has-word" ]
                [ h1 [ class "current-word", onClick WordGuessed ] [ text word.word ]
                ]
            ]
        , button [ class "next-word", onClick WordGuessed ] [ text "Word guessed! Next word" ]
        ]


currentWordView : Game -> LocalUser -> Int -> Html Msg
currentWordView game localUser turnTimer =
    case localUser of
        LocalPlayer localPlayer ->
            if isExplaining game localPlayer then
                case game.state.words.current of
                    Just word ->
                        currentWord word turnTimer

                    Nothing ->
                        start

            else
                text ""

        LocalWatcher _ ->
            case game.state.words.current of
                Just word ->
                    currentWord word turnTimer

                Nothing ->
                    text ""
