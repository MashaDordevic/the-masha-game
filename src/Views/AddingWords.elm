module Views.AddingWords exposing (..)

import Dict exposing (Dict)
import Game.Game exposing (Game)
import Game.Words
import Html exposing (Html, button, div, h1, h3, input, span, text)
import Html.Attributes exposing (class, disabled, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Player exposing (Player)
import State exposing (LocalUser(..), Msg(..), PlayingGameModel)


wordsStatisticsView : Game.Words.Words -> Dict String Player -> Html Msg
wordsStatisticsView words players =
    let
        wordCountByPlayer =
            Game.Words.wordsByPlayer words.next
                |> Dict.map (\_ wordsList -> List.length wordsList)

        allPlayers =
            players
                |> Dict.values
                |> List.map (\player -> ( player.name, 0 ))
                |> Dict.fromList

        statsData =
            Dict.union wordCountByPlayer allPlayers

        stats =
            statsData
                |> Dict.toList
                |> List.map
                    (\( playerName, wordsCount ) ->
                        div [ class "request", class "space-between" ]
                            [ span [] [ text playerName ]
                            , span [] [ text (String.fromInt wordsCount) ]
                            ]
                    )
                |> div []
    in
    div []
        [ div [ class "join-requests-container", class "words-stats-container" ]
            [ h3 []
                [ text "Players" ]
            , stats
            ]
        ]


localPlayersWords : Game.Words.Words -> Player -> Html Msg
localPlayersWords words localUser =
    let
        localWords =
            words.next
                |> Game.Words.wordsByPlayer
                |> Dict.get localUser.name

        noWords =
            case localWords of
                Nothing ->
                    0

                Just wordsList ->
                    List.length wordsList
    in
    case localWords of
        Nothing ->
            text ""

        Just wordsList ->
            div [ class "local-words" ]
                [ h3 [] [ text ("Words added: " ++ String.fromInt noWords) ]
                , wordsList
                    |> List.map
                        (\{ id, word } ->
                            div [ class "space-between" ]
                                [ span [] [ text word ]
                                , button [ onClick (DeleteWord id), class "icon-button" ] [ span [] [ text "𝗫" ] ]
                                ]
                        )
                    |> div [ class "word-list" ]
                ]


wordsInputView : Game -> Player -> String -> Html Msg
wordsInputView game localUser inputValue =
    div [ class "words-input-container" ]
        [ input [ type_ "text", id "word", placeholder "e.g. table, mango, nudist", value inputValue, onInput UpdateWordInput ] []
        , button [ class "secondary", onClick AddWord ] [ text "Add" ]
        , localPlayersWords game.state.words localUser
        ]


addingWordsView : PlayingGameModel -> Html Msg
addingWordsView model =
    let
        wordsInput =
            case model.localUser of
                LocalPlayer localPlayer ->
                    wordsInputView model.game localPlayer model.wordInput

                LocalWatcher _ ->
                    text ""

        hasNoWords =
            List.isEmpty model.game.state.words.next
    in
    div [ class "adding-words-container" ]
        [ h1 []
            [ text "Let’s add some words" ]
        , div []
            [ wordsInput
            , wordsStatisticsView model.game.state.words model.game.participants.players
            , if model.isOwner then
                button [ onClick StartPlaying, disabled hasNoWords ] [ text "Let's play" ]

              else
                text ""
            ]
        ]
