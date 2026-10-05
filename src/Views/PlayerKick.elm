module Views.PlayerKick exposing (canKickPlayer, kickPlayerButton)

import Html exposing (Html, button, span, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Player exposing (Player)
import State exposing (LocalUser(..), Msg(..))


canKickPlayer : Bool -> LocalUser -> Player -> Bool
canKickPlayer isOwner localUser player =
    let
        localUserId =
            case localUser of
                LocalPlayer localPlayer ->
                    localPlayer.id

                LocalWatcher localWatcher ->
                    localWatcher.id
    in
    isOwner && localUserId /= player.id


kickPlayerButton : Bool -> LocalUser -> Player -> Html Msg
kickPlayerButton isOwner localUser player =
    if canKickPlayer isOwner localUser player then
        button
            [ class "icon-button"
            , type_ "button"
            , onClick (KickPlayer player.id)
            , attribute "aria-label" ("Kick " ++ player.name ++ " from the game")
            ]
            [ span [ attribute "aria-hidden" "true" ] [ text "🚫" ] ]

    else
        text ""
