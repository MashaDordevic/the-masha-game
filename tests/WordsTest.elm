module WordsTest exposing (..)

import Dict
import Expect
import Game.Words exposing (Word, Words, failCurrentWord, restartWords, succeedCurrentWord, wordWithKey, wordsByPlayer)
import Player exposing (PlayerStatus(..))
import Test exposing (..)


sortWords : Words -> Words
sortWords words =
    Words (List.sortBy .word words.guessed) words.current (List.sortBy .word words.next)


suite : Test
suite =
    describe "Words"
        [ test "wordWithKey" <|
            \_ ->
                wordWithKey 0 (Word "word" "playerName" "")
                    |> Expect.equal
                        { id = "000-word-playerName"
                        , word = "word"
                        , player = "playerName"
                        }
        , test "wordsByPlayer" <|
            \_ ->
                wordsByPlayer [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]
                    |> Expect.equal
                        (Dict.fromList
                            [ ( "player1"
                              , [ { id = ""
                                  , word = "a"
                                  , player = "player1"
                                  }
                                , { id = ""
                                  , word = "c"
                                  , player = "player1"
                                  }
                                ]
                              )
                            , ( "player2"
                              , [ { id = ""
                                  , word = "b"
                                  , player = "player2"
                                  }
                                ]
                              )
                            ]
                        )
        , test "restartWords" <|
            \_ ->
                let
                    wordsList =
                        [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]
                in
                restartWords (Words wordsList Maybe.Nothing [])
                    |> sortWords
                    |> Expect.equal (Words [] Maybe.Nothing wordsList |> sortWords)
        , test "restartWords includes the current and remaining words" <|
            \_ ->
                let
                    guessedWord =
                        Word "a" "player1" ""

                    currentWord =
                        Word "b" "player2" ""

                    remainingWord =
                        Word "c" "player1" ""
                in
                restartWords (Words [ guessedWord ] (Just currentWord) [ remainingWord ])
                    |> sortWords
                    |> Expect.equal
                        (Words [] Maybe.Nothing [ guessedWord, currentWord, remainingWord ]
                            |> sortWords
                        )
        , test "failCurrentWord" <|
            \_ ->
                failCurrentWord (Words [] (Just (Word "a" "player1" "")) [ Word "b" "player2" "", Word "c" "player1" "" ])
                    |> sortWords
                    |> Expect.equal
                        (Words [] Maybe.Nothing [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]
                            |> sortWords
                        )
        , test "succeedCurrentWord" <|
            \_ ->
                succeedCurrentWord (Words [ Word "b" "player2" "", Word "c" "player2" "" ] (Just (Word "d" "player1" "")) [ Word "a" "player1" "" ])
                    |> Expect.equal
                        (Words [ Word "d" "player1" "", Word "b" "player2" "", Word "c" "player2" "" ] (Just (Word "a" "player1" "")) [])
        ]
