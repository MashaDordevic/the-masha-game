module Views.Help exposing (helpView)

import Html exposing (Html, b, br, button, div, h2, h3, h4, p, span, text)
import Html.Attributes exposing (attribute, class, classList, type_)
import Html.Events exposing (onClick)
import State exposing (GameModel(..), Model, Msg(..))
import Views.Header exposing (headerView)


type HelpContext
    = Hide
    | Round Int


helpContent : HelpContext -> Html Msg
helpContent context =
    case context of
        Round 0 ->
            div []
                [ h2 [] [ text "Adding words" ]
                , span [] [ text "Now all players add words that are going to be described later." ]
                , span [] [ text "Not sure what to write? Think about what you'd like to see your friends charade" ]
                , h3 [] [ text "Tips for competitive players:" ]
                , span []
                    [ text "There are only two rules: "
                    , text "words have to be "
                    , b [] [ text "nouns" ]
                    , text " , and they "
                    , b [] [ text "can't" ]
                    , text " be "
                    , b [] [ text "proper nouns" ]
                    ]
                , span []
                    [ text "Here are some examples: "
                    ]
                , span [ class "examples" ]
                    [ span [ class "correct" ] [ text "car" ]
                    , span [] [ span [ class "incorrect" ] [ text "blue car" ], br [] [], text "(should be ONE generic term)" ]
                    , span [ class "correct" ] [ text "government" ]
                    , span [] [ span [ class "incorrect" ] [ text "Harry Potter" ], br [] [], text " (should NOT be a proper noun)" ]
                    , span [ class "correct" ] [ text "sunbed" ]
                    , span [] [ span [ class "incorrect" ] [ text "jump" ], br [] [], text " (should be a noun)" ]
                    ]
                , h4 [] [ text "How many words should we add?" ]
                , span [] [ text "It's up to you to agree on! It depends on the number of players and how long you would like to play. We recommend having 35-50 words in total." ]
                ]

        Round 1 ->
            div []
                [ h2 [] [ text "Describing" ]
                , span [] [ text "Once it's your turn to describe words you'll see the start button and words will show up." ]
                , span [] [ text "There's only one rule: you can't say ", b [] [ text "the root of the word" ], text "." ]
                , span [] [ text "For example: if a word is \"sunbed\"", text " avoid explaining it as \"a  ", b [] [ text "bed" ], text " you lay on while being on the ", b [] [ text "sun" ], text ", or while ", b [] [ text "sun" ], text "tanning\". All the ", b [] [ text "bold" ], text " words in the previous example are violations." ]
                , br [] []
                , span []
                    [ text "Some more examples would be:"
                    , span [ class "examples" ]
                        [ span [] [ text "\"row row row your... \"" ]
                        , span [] [ text "🤔 boat!" ]
                        , span [] [ text "\"a car has 4... \"" ]
                        , span [] [ text "🤔 wheels!... or wheel*" ]
                        , span [] [ text "\"sour fruit... \"" ]
                        , span [] [ text "lemon! ⛔️ lime?! ✅" ]
                        ]
                    ]
                ]

        Round 2 ->
            div []
                [ h2 [] [ text "Charades" ]
                , span [] [ text "We're playing standard charades with the same words that we had in the prevous round." ]
                , span [] [ text "There's only one rule: you can't make sounds (for example humming or \"bzzz\" sounds)" ]
                , span [] [ text "🙊" ]
                ]

        Round 3 ->
            div []
                [ h2 [] [ text "One word" ]
                , span [] [ text "In this round we're explaining words with only ", b [] [ text "one word" ], text "." ]
                , span [] [ text "We played two rounds with the same words already so we can explain words with only one word now! Here are some examples: " ]
                , span [ class "examples" ]
                    [ span [] [ text "\"rowing... \"" ]
                    , span [] [ text "🤔 boat!" ]
                    , span [] [ text "\"steering... \"" ]
                    , span [] [ text "🤔 wheel" ]
                    , span [] [ text "\"sour... \"" ]
                    , span [] [ text "lime" ]
                    ]
                ]

        _ ->
            text ""


helpView : Model -> Html Msg
helpView model =
    let
        context =
            case model.currentGame of
                Playing gameModel ->
                    Round gameModel.game.state.round

                _ ->
                    Hide

        shouldShow =
            case context of
                Hide ->
                    False

                Round round ->
                    round >= 0
    in
    div [ class "help-dialog-container" ]
        [ if model.isHelpDialogOpen then
            div [ class "help-dialog" ]
                [ headerView
                , div [ class "help-dialog-content" ]
                    [ helpContent context
                    , span [ class "bottom" ] [ text "If something went wrong try refreshing the page and re-joining the game by entering the same game code and using the same username." ]
                    , button [ class "close-button", onClick ToggleHelpDialog ] [ text "𝗫" ]
                    ]
                ]

          else
            button
                [ classList [ ( "help-dialog-button", True ), ( "secondary", True ), ( "hide", not shouldShow ) ]
                , type_ "button"
                , attribute "aria-label" "Open help"
                , onClick ToggleHelpDialog
                ]
                [ span [ attribute "aria-hidden" "true" ] [ text "?" ]
                ]
        ]
