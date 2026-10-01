module AddingWordsTest exposing (suite)

import Expect
import Game.Game exposing (Game, createGameModel)
import Game.Words exposing (Word, Words)
import Player exposing (Player, PlayerStatus(..))
import Request
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector exposing (class, tag, text)
import Views.AddingWords exposing (wordsInputView)


localPlayer : Player
localPlayer =
    Player "player-1" "MASHA" Online True


gameWithWords : List Word -> Game
gameWithWords words =
    let
        initialGame =
            createGameModel localPlayer

        initialState =
            initialGame.state
    in
    { initialGame
        | state =
            { initialState
                | words = Words [] Nothing words
            }
    }


suite : Test
suite =
    describe "Adding words view"
        [ test "renders the form and reordered words as complete ordered children" <|
            \_ ->
                let
                    rendered =
                        gameWithWords
                            [ { id = "word-2", word = "MANGO", player = localPlayer.name }
                            , { id = "word-1", word = "TABLE", player = localPlayer.name }
                            ]
                            |> (\game -> wordsInputView game localPlayer "" Request.idle)
                            |> Query.fromHtml

                    children =
                        rendered
                            |> Query.children []

                    wordRows =
                        rendered
                            |> Query.find [ class "word-list" ]
                            |> Query.children []
                in
                Expect.all
                    [ \_ -> children |> Query.count (Expect.equal 3)
                    , \_ -> children |> Query.index 0 |> Query.has [ tag "form", class "word-entry-form" ]
                    , \_ -> children |> Query.index 1 |> Query.has [ text "" ]
                    , \_ -> children |> Query.index 2 |> Query.has [ tag "div", class "local-words" ]
                    , \_ -> wordRows |> Query.count (Expect.equal 2)
                    , \_ -> wordRows |> Query.index 0 |> Query.has [ text "MANGO" ]
                    , \_ -> wordRows |> Query.index 1 |> Query.has [ text "TABLE" ]
                    ]
                    ()
        ]
