module Views.Playing.Teams exposing (..)

import Game.Game exposing (Game)
import Game.Gameplay
import Game.Teams exposing (Team, getScoreboard)
import Html exposing (Html, div, h2, h3, h4, span, text)
import Html.Attributes exposing (class)
import State exposing (Msg)


teamView : Game -> Int -> Team -> Html Msg
teamView game indexNumber team =
    let
        teamNumber =
            if indexNumber == 0 then
                "🎉"

            else
                "# " ++ String.fromInt (indexNumber + 1)
    in
    div [ class "team-container" ]
        [ h4 [] [ text teamNumber ]
        , span [] [ teamPlayers game team ]
        , h4 [ class "team-score" ] [ text (String.fromInt team.score) ]
        ]


teamPlayers : Game -> Team -> Html Msg
teamPlayers game team =
    Game.Gameplay.teamMembers game team
        |> List.map .name
        |> String.join " & "
        |> text


teamsView : Game -> Html Msg
teamsView game =
    div [ class "scoreboard-container" ]
        [ h3 [] [ text "Leader board" ]
        , getScoreboard game.state.teams
            |> List.indexedMap (teamView game)
            |> div [ class "scoreboard-teams-container" ]
        , div [ class "scoreboard-background" ] []
        ]
