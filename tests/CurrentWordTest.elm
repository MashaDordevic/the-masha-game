module CurrentWordTest exposing (suite)

import Expect
import Game.Teams exposing (Team, Teams)
import Game.Words exposing (Word, Words)
import Player exposing (Role(..))
import State exposing (LocalUser(..))
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector exposing (tag, text)
import Views.Playing.CurrentWord exposing (currentWordView)
import GameFixture exposing (gameFor, player)


explainer =
    player "explainer" "EXPLAINER" PlayerRole


watcher =
    player "watcher" "WATCHER" WatcherRole


gameWithCurrentWord =
    let
        game =
            gameFor explainer

        state =
            game.state
    in
    { game
        | state =
            { state
                | words = Words [] (Just (Word "TABLE" explainer.id "word-1")) []
                , teams = Teams (Just (Team [ explainer.id ] 0)) []
            }
    }


suite : Test
suite =
    describe "current word controls"
        [ test "the explainer can submit a guess" <|
            \_ ->
                currentWordView gameWithCurrentWord (LocalPlayer explainer) 30
                    |> Query.fromHtml
                    |> Query.findAll [ tag "button" ]
                    |> Query.count (Expect.equal 1)
        , test "a watcher sees the word without interactive guess controls" <|
            \_ ->
                let
                    view =
                        currentWordView gameWithCurrentWord (LocalWatcher watcher) 30
                            |> Query.fromHtml
                in
                Expect.all
                    [ \_ -> view |> Query.has [ text "TABLE" ]
                    , \_ ->
                        view
                            |> Query.findAll [ tag "button" ]
                            |> Query.count (Expect.equal 0)
                    ]
                    ()
        ]
