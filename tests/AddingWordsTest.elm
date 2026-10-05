module AddingWordsTest exposing (suite)

import Dict
import Expect
import Game.Game exposing (Game, createGameModel)
import Game.Words exposing (Word, Words)
import Html.Attributes as Attributes
import Player exposing (Player, PlayerStatus(..))
import Request
import State exposing (LocalUser(..), Msg(..))
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector exposing (attribute, class, tag, text)
import Views.AddingWords exposing (wordsInputView, wordsStatisticsView)


localPlayer : Player
localPlayer =
    Player "player-1" "MASHA" Online True


otherPlayer : Player
otherPlayer =
    Player "player-2" "ALICE" Online False


latePlayer : Player
latePlayer =
    Player "player-3" "ZOE" Online False


players : Dict.Dict String Player
players =
    Dict.fromList
        [ ( localPlayer.id, localPlayer )
        , ( otherPlayer.id, otherPlayer )
        , ( latePlayer.id, latePlayer )
        ]


words : Words
words =
    Words []
        Nothing
        [ { id = "word-1", word = "TABLE", player = localPlayer.name }
        , { id = "word-2", word = "MANGO", player = localPlayer.name }
        , { id = "word-3", word = "CHAIR", player = otherPlayer.name }
        ]


gameWithWords : List Word -> Game
gameWithWords existingWords =
    let
        initialGame =
            createGameModel localPlayer

        initialState =
            initialGame.state
    in
    { initialGame
        | state =
            { initialState
                | words = Words [] Nothing existingWords
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
        , test "asks for one word at a time" <|
            \_ ->
                gameWithWords []
                    |> (\game -> wordsInputView game localPlayer "" Request.idle)
                    |> Query.fromHtml
                    |> Expect.all
                        [ \rendered ->
                            rendered
                                |> Query.find [ tag "label" ]
                                |> Query.has [ text "Add words, one at a time. Then play when the group has enough." ]
                        , \rendered ->
                            rendered
                                |> Query.find [ tag "input" ]
                                |> Query.has [ attribute (Attributes.placeholder "e.g. mango") ]
                        , \rendered ->
                            rendered
                                |> Query.findAll [ tag "p", attribute (Attributes.id "word-hint") ]
                                |> Query.count (Expect.equal 0)
                        ]
        , test "lets the owner kick another player" <|
            \_ ->
                wordsStatisticsView words players True (LocalPlayer localPlayer)
                    |> Query.fromHtml
                    |> Query.find
                        [ tag "button"
                        , attribute (Attributes.attribute "aria-label" "Kick ALICE from the game")
                        ]
                    |> Event.simulate Event.click
                    |> Event.expect (KickPlayer otherPlayer.id)
        , test "never offers the owner a self-kick action" <|
            \_ ->
                wordsStatisticsView words players True (LocalPlayer localPlayer)
                    |> Query.fromHtml
                    |> Query.findAll
                        [ tag "button"
                        , attribute (Attributes.attribute "aria-label" "Kick MASHA from the game")
                        ]
                    |> Query.count (Expect.equal 0)
        , test "does not offer kick actions to non-owners" <|
            \_ ->
                wordsStatisticsView words players False (LocalPlayer otherPlayer)
                    |> Query.fromHtml
                    |> Query.findAll [ tag "button" ]
                    |> Query.count (Expect.equal 0)
        , test "retains word counts and includes late players with zero words" <|
            \_ ->
                let
                    rendered =
                        wordsStatisticsView words players True (LocalPlayer localPlayer)
                            |> Query.fromHtml

                    rows =
                        rendered
                            |> Query.findAll [ class "request" ]
                in
                Expect.all
                    [ \_ -> rows |> Query.index 0 |> Query.has [ text "ALICE", text "1" ]
                    , \_ -> rows |> Query.index 1 |> Query.has [ text "MASHA", text "2" ]
                    , \_ -> rows |> Query.index 2 |> Query.has [ text "ZOE", text "0" ]
                    ]
                    ()
        ]
