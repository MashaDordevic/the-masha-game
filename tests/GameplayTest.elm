module GameplayTest exposing (suite)

import Dict
import Expect
import Game.Game exposing (GamePhase(..))
import Game.Gameplay exposing (Screen(..), explainer, isExplaining, isOwner, isRoundEnd, screen, withPresence)
import Game.Participants exposing (Participants)
import Game.Teams exposing (Team, Teams)
import Game.Words exposing (Words)
import Player exposing (PlayerStatus(..), Role(..))
import Set
import Test exposing (Test, describe, test)
import GameFixture exposing (gameFor, player)


owner =
    player "owner" "OWNER" PlayerRole


partner =
    player "partner" "PARTNER" PlayerRole


playingGame =
    let
        game =
            gameFor owner

        state =
            game.state
    in
    { game
        | participants = Participants (Dict.fromList [ ( owner.id, owner ), ( partner.id, partner ) ])
        , state =
            { state
                | phase = PlayingRound
                , round = 1
                , teams = Teams (Just (Team [ owner.id, partner.id ] 0)) []
                , words = Words [] Nothing []
            }
    }


statusOf id game =
    game.participants.players
        |> Dict.get id
        |> Maybe.map .status


suite : Test
suite =
    describe "gameplay read projection"
        [ test "the first current team member is the explainer" <|
            \_ ->
                explainer playingGame
                    |> Maybe.map .id
                    |> Expect.equal (Just owner.id)
        , test "only that player is explaining" <|
            \_ ->
                Expect.all
                    [ \_ -> isExplaining playingGame owner |> Expect.equal True
                    , \_ -> isExplaining playingGame partner |> Expect.equal False
                    ]
                    ()
        , test "a round ends when no current or upcoming word remains" <|
            \_ ->
                isRoundEnd playingGame.state |> Expect.equal True
        , test "ownership comes from the game's owner id" <|
            \_ ->
                isOwner playingGame owner |> Expect.equal True
        , test "the screen follows the phase" <|
            \_ ->
                screen playingGame |> Expect.equal PlayingScreen
        , test "presence marks the local player and connected players online" <|
            \_ ->
                let
                    presented =
                        withPresence owner.id (Set.singleton partner.id) playingGame
                in
                Expect.all
                    [ \_ -> statusOf owner.id presented |> Expect.equal (Just Online)
                    , \_ -> statusOf partner.id presented |> Expect.equal (Just Online)
                    ]
                    ()
        ]
