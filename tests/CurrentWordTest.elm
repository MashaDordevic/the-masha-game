module CurrentWordTest exposing (suite)

import Expect
import Game.Game exposing (createGameModel)
import Game.Teams exposing (Team, Teams)
import Game.Words exposing (Word, Words)
import Player exposing (Player, PlayerStatus(..))
import State exposing (LocalUser(..))
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector exposing (tag, text)
import Views.Playing.CurrentWord exposing (currentWordView)


explainer : Player
explainer =
    Player "explainer" "EXPLAINER" Online False


watcher : Player
watcher =
    Player "watcher" "WATCHER" Online False


gameWithCurrentWord =
    let
        game =
            createGameModel explainer

        state =
            game.state
    in
    { game
        | state =
            { state
                | words = Words [] (Just (Word "TABLE" "AUTHOR" "word-1")) []
                , teams = Teams (Just (Team [ explainer ] 0)) []
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
