module Views.FinishedGame exposing (..)

import Array
import Game.Game exposing (Game)
import Game.Gameplay
import Game.Teams exposing (getScoreboard)
import Game.Words exposing (Word)
import Html exposing (Html, div, h2, h3, h4, span, text)
import Html.Attributes exposing (class)
import State exposing (Msg)
import Views.Playing.Teams exposing (teamsView)


finishedGameView : Game -> Html Msg
finishedGameView game =
    let
        winningTeam =
            getScoreboard game.state.teams
                |> List.head
                |> Maybe.map
                    (\team ->
                        Game.Gameplay.teamMembers game team
                            |> List.map .name
                            |> String.join " & "
                            |> text
                    )
                |> Maybe.withDefault (text "")

        confetti =
            List.range 0 200
                |> List.map (\index -> div [ class ("confetti-" ++ String.fromInt index) ] [])
                |> div [ class "confetti-animation-container" ]
    in
    div [ class "finished-game-container" ]
        [ confetti
        , h2 []
            [ text "And the winners are" ]
        , span [ class "winners" ] [ winningTeam ]
        , span [ class "medal" ] [ text "\u{1F947}" ]
        , teamsView game
        ]
