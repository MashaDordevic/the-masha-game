module Views.Playing.Playing exposing (..)

import Game.Game exposing (Game)
import Game.Gameplay
import Game.Timer
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (class)
import State exposing (Msg, PlayingGameModel)
import Time
import Views.Playing.CurrentWord exposing (currentWordView)
import Views.Playing.Info exposing (infoView)
import Views.Playing.Round exposing (roundView)
import Views.Playing.Teams exposing (teamsView)


playingNow : Game -> Html Msg
playingNow game =
    let
        teamOnTurn =
            game.state.teams.current

        score =
            teamOnTurn
                |> Maybe.map .score
                |> Maybe.withDefault 0

        explainingPlayer =
            Game.Gameplay.explainer game
                |> Maybe.map .name
                |> Maybe.withDefault "n/a"

        guessingPlayersNames =
            case teamOnTurn of
                Just currentTeam ->
                    Game.Gameplay.teamMembers game currentTeam
                        |> List.drop 1
                        |> List.map .name

                Nothing ->
                    [ "n/a" ]

        guessingPlayers =
            guessingPlayersNames
                |> List.map (\name -> span [] [ text name ])
                |> div [ class "guessing-players" ]
    in
    div [ class "info-container", class "section" ]
        [ div [ class "team-on-turn" ]
            [ div [ class "explaining-player" ]
                [ span [] [ text explainingPlayer ]
                , span [] [ text "☝️" ]
                ]
            , div [ class "score-container" ]
                [ span [] [ text (String.fromInt score) ]
                , span [] [ text "POINTS" ]
                ]
            , guessingPlayers
            , span [ class "star-eyed-emoji" ] [ text "🤩" ]
            ]
        ]


playingView : Float -> Time.Posix -> PlayingGameModel -> Html Msg
playingView serverTimeOffsetMs now model =
    let
        secondsLeft =
            Game.Timer.remainingSeconds serverTimeOffsetMs now model.game.state.turnTimer
    in
    div [ class "playing-container" ]
        [ div [ class "playing-now" ]
            [ roundView model.game.state.round
            , currentWordView model.game model.localUser secondsLeft
            , infoView model.game model.localUser secondsLeft
            , playingNow model.game
            ]
        , teamsView model.game
        ]
