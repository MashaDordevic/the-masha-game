module AddingWordsTest exposing (suite)

import Game.Game exposing (Game, createGameModel)
import Game.Words exposing (Word, Words)
import Player exposing (Player, PlayerStatus(..))
import Request
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector exposing (class, tag)
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
        [ test "keeps the entry form above the growing word list" <|
            \_ ->
                let
                    gameWithReorderedWords =
                        gameWithWords
                            [ { id = "word-2", word = "MANGO", player = localPlayer.name }
                            , { id = "word-1", word = "TABLE", player = localPlayer.name }
                            ]

                    children =
                        wordsInputView gameWithReorderedWords localPlayer "" Request.idle
                            |> Query.fromHtml
                            |> Query.children []
                in
                children
                    |> Query.index 0
                    |> Query.has [ tag "form" ]
        , test "renders the added words immediately after the entry form" <|
            \_ ->
                gameWithWords
                    [ { id = "word-1", word = "TABLE", player = localPlayer.name } ]
                    |> (\game -> wordsInputView game localPlayer "" Request.idle)
                    |> Query.fromHtml
                    |> Query.children [ tag "div" ]
                    |> Query.index 0
                    |> Query.has [ class "local-words" ]
        ]
