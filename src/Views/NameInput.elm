module Views.NameInput exposing (gameLookupView, nameInputView)

import Html exposing (Html, button, div, h1, input, label, p, text)
import Html.Attributes exposing (attribute, class, disabled, for, id, type_, value)
import Html.Events exposing (onClick, onInput)
import Request
import State exposing (Msg(..))


nameInputView : String -> String -> Request.State requestId String -> Msg -> Html Msg
nameInputView nameInput loadingLabel request onClickMsg =
    let
        isLoading =
            Request.isLoading request
    in
    div [ class "name-input-container" ]
        [ h1 [] [ text "ADD A NICKNAME" ]
        , label [ for "nickname" ] [ text "Nickname" ]
        , input [ id "nickname", value nameInput, onInput UpdateNameInput, disabled isLoading ] []
        , button
            [ onClick onClickMsg
            , disabled (isLoading || String.isEmpty (String.trim nameInput))
            , attribute "aria-busy" (if isLoading then "true" else "false")
            ]
            [ text (if isLoading then loadingLabel else "Enter") ]
        , case Request.error request of
            Just requestError ->
                p [ class "error", attribute "role" "alert" ] [ text requestError ]

            Nothing ->
                text ""
        ]


gameLookupView : Request.State requestId String -> Html Msg
gameLookupView request =
    div [ class "name-input-container" ]
        [ h1 [] [ text "FINDING GAME" ]
        , case Request.error request of
            Just requestError ->
                div []
                    [ p [ class "error", attribute "role" "alert" ] [ text requestError ]
                    , button [ onClick RetryGameLookup ] [ text "Try again" ]
                    , button [ class "secondary", onClick BackToStart ] [ text "Back" ]
                    ]

            Nothing ->
                p [ attribute "role" "status" ] [ text "Loading game…" ]
        ]
