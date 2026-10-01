module Views.NameInput exposing (nameInputView)

import Html exposing (Html, button, div, h1, input, p, text)
import Html.Attributes exposing (attribute, class, disabled, type_, value)
import Html.Events exposing (onClick, onInput)
import Request
import State exposing (Msg(..))


nameInputView : String -> String -> Request.State String -> Msg -> Html Msg
nameInputView nameInput loadingLabel request onClickMsg =
    let
        isLoading =
            Request.isLoading request
    in
    div [ class "name-input-container" ]
        [ h1 [] [ text "ADD A NICKNAME" ]
        , input [ value nameInput, onInput UpdateNameInput, disabled isLoading ] []
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
