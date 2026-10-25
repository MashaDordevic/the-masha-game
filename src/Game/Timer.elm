module Game.Timer exposing (inCountdown, label, remainingSeconds)

import Constants exposing (countdownMoment)
import Game.Game exposing (TurnTimer(..))
import Time


remainingSeconds : Float -> Time.Posix -> TurnTimer -> Int
remainingSeconds serverTimeOffsetMs now turnTimer =
    let
        remainingMs =
            case turnTimer of
                Ticking deadlineMs ->
                    deadlineMs - (toFloat (Time.posixToMillis now) + serverTimeOffsetMs)

                NotTicking pausedMs ->
                    toFloat pausedMs

                Restarted durationMs ->
                    toFloat durationMs
    in
    max 0 (ceiling (remainingMs / 1000))


label : TurnTimer -> String
label turnTimer =
    case turnTimer of
        Ticking _ ->
            "Pause"

        NotTicking _ ->
            "Continue"

        Restarted _ ->
            ""


inCountdown : Float -> Time.Posix -> TurnTimer -> Bool
inCountdown serverTimeOffsetMs now turnTimer =
    remainingSeconds serverTimeOffsetMs now turnTimer <= countdownMoment
