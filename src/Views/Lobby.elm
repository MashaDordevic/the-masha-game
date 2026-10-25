module Views.Lobby exposing (..)

import Dict exposing (Dict)
import Game.Gameplay
import Html exposing (Html, button, div, h1, h3, span, text)
import Html.Attributes exposing (class, classList, disabled)
import Html.Events exposing (onClick)
import Player exposing (Player)
import State exposing (LocalUser(..), Msg(..), PlayingGameModel)
import Views.PlayerKick exposing (canKickPlayer, kickPlayerButton)


playersList : Dict String Player -> Bool -> LocalUser -> Html Msg
playersList users isOwner localUser =
    users
        |> Dict.toList
        |> List.map
            (\( _, user ) ->
                let
                    canBeKicked =
                        canKickPlayer isOwner localUser user
                in
                div
                    [ classList
                        [ ( "space-between", canBeKicked )
                        , ( "request", True )
                        ]
                    ]
                    [ span [] [ text user.name ]
                    , kickPlayerButton isOwner localUser user
                    ]
            )
        |> div [ class "participants" ]


lobbyView : PlayingGameModel -> Html Msg
lobbyView model =
    let
        cantStartGame =
            Dict.size model.game.participants.players <= 1

        isOwner =
            case model.localUser of
                LocalPlayer player ->
                    Game.Gameplay.isOwner model.game player

                LocalWatcher player ->
                    Game.Gameplay.isOwner model.game player

        titleCopy =
            if isOwner then
                "Waiting for players to join"

            else
                "Waiting for game to start"
    in
    div [ class "lobby-container" ]
        [ div [ class "invite-to-game" ]
            [ h1 []
                [ text titleCopy ]
            , button [ onClick CopyInviteLink, class "secondary" ] [ text "Copy invite link 🔗" ]
            , div [ class "join-requests-container" ]
                [ h3 []
                    [ text "Players" ]
                , playersList
                    model.game.participants.players
                    isOwner
                    model.localUser
                ]
            ]
        , if isOwner then
            button [ onClick StartGame, class "start-game", disabled cantStartGame ] [ text "start game" ]

          else
            text ""
        ]
