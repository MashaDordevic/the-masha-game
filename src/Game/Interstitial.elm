module Game.Interstitial exposing (DueTransition(..), dueTransition)

import Game.Game exposing (Game, GamePhase(..))
import Game.Gameplay
import Time


type DueTransition
    = EnterBetweenRounds
    | AdvanceRound


dueTransition : Float -> Time.Posix -> Game -> Maybe DueTransition
dueTransition serverTimeOffsetMs now game =
    let
        serverNow =
            toFloat (Time.posixToMillis now) + serverTimeOffsetMs
    in
    case game.state.phase of
        PlayingRound ->
            if Game.Gameplay.isRoundEnd game.state then
                Just EnterBetweenRounds

            else
                Nothing

        BetweenRounds ->
            case game.state.deadlineMs of
                Just deadlineMs ->
                    if serverNow >= deadlineMs then
                        Just AdvanceRound

                    else
                        Nothing

                Nothing ->
                    Nothing

        _ ->
            Nothing
