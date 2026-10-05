module Views.AddingWords exposing (..)

import Dict exposing (Dict)
import Game.Game exposing (Game)
import Game.Words
import Html exposing (Html, button, div, form, h1, h3, input, label, p, span, text)
import Html.Attributes exposing (attribute, class, disabled, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Player exposing (Player)
import Request
import State exposing (LocalUser(..), Msg(..), PlayingGameModel)
import Views.PlayerKick exposing (kickPlayerButton)


wordsStatisticsView : Game.Words.Words -> Dict String Player -> Bool -> LocalUser -> Html Msg
wordsStatisticsView words players isOwner localUser =
    let
        wordCountByPlayer =
            Game.Words.wordsByPlayer words.next
                |> Dict.map (\_ wordsList -> List.length wordsList)

        allPlayers =
            players
                |> Dict.values
                |> List.map (\player -> ( player.name, 0 ))
                |> Dict.fromList

        playerByName =
            players
                |> Dict.values
                |> List.map (\player -> ( player.name, player ))
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
                            , div [ class "player-list-details" ]
                                [ span [] [ text (String.fromInt wordsCount) ]
                                , playerByName
                                    |> Dict.get playerName
                                    |> Maybe.map (kickPlayerButton isOwner localUser)
                                    |> Maybe.withDefault (text "")
                                ]
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
                                , button
                                    [ type_ "button"
                                    , onClick (DeleteWord id)
                                    , class "icon-button"
                                    , attribute "aria-label" ("Remove " ++ word)
                                    ]
                                    [ span [ attribute "aria-hidden" "true" ] [ text "𝗫" ] ]
                                ]
                        )
                    |> div [ class "word-list" ]
                ]


wordsInputView : Game -> Player -> String -> Request.State requestId String -> Html Msg
wordsInputView game localUser inputValue request =
    let
        isLoading =
            Request.isLoading request
    in
    div [ class "words-input-container" ]
        [ form [ class "word-entry-form", onSubmit AddWord ]
            [ label [ for "word" ] [ text "Add words, one at a time. Then play when the group has enough." ]
            , input
                [ type_ "text"
                , id "word"
                , attribute "name" "word"
                , attribute "autocomplete" "on"
                , attribute "autocapitalize" "characters"
                , attribute "spellcheck" "true"
                , placeholder "e.g. mango"
                , value inputValue
                , onInput UpdateWordInput
                , disabled isLoading
                ]
                []
            , button
                [ class "secondary"
                , type_ "submit"
                , disabled (isLoading || String.isEmpty (String.trim inputValue))
                , attribute "aria-busy" (if isLoading then "true" else "false")
                ]
                [ text (if isLoading then "Adding…" else "Add") ]
            ]
        , case Request.error request of
            Just requestError ->
                p [ class "error", attribute "role" "alert" ] [ text requestError ]

            Nothing ->
                text ""
        , localPlayersWords game.state.words localUser
        ]


addingWordsView : PlayingGameModel -> Html Msg
addingWordsView model =
    let
        wordsInput =
            case model.localUser of
                LocalPlayer localPlayer ->
                    wordsInputView model.game localPlayer model.wordInput model.addWordRequest

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
            , wordsStatisticsView model.game.state.words model.game.participants.players model.isOwner model.localUser
            , if model.isOwner then
                button [ onClick StartPlaying, disabled hasNoWords ] [ text "Let's play" ]

              else
                text ""
            ]
        ]
