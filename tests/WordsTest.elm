module WordsTest exposing (suite)

import Dict
import Expect
import Game.Words exposing (Word, Words, wordsByPlayer)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "word read model"
        [ test "groups words by the player who added them" <|
            \_ ->
                wordsByPlayer
                    [ Word "desk" "1" "a"
                    , Word "orange" "2" "b"
                    , Word "keyboard" "1" "c"
                    ]
                    |> Dict.map (\_ words -> List.map .word words)
                    |> Expect.equal
                        (Dict.fromList
                            [ ( "1", [ "desk", "keyboard" ] )
                            , ( "2", [ "orange" ] )
                            ]
                        )
        , test "keeps guessed, current, and next as separate lists" <|
            \_ ->
                Words [ Word "old" "1" "old" ] (Just (Word "now" "1" "now")) []
                    |> .current
                    |> Maybe.map .word
                    |> Expect.equal (Just "now")
        ]
