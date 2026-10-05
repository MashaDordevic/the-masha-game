module GameplayTest exposing (..)

import Dict
import Expect
import Game.Game exposing (Game, GameState, TurnTimer(..), createGameModel, emptyGameState)
import Game.Gameplay exposing (endOfExplaining, guessWord, isExplaining, isLocalPlayersTurn, isRoundEnd, nextRound, switchTimer)
import Game.Participants exposing (Participants)
import Game.Status
import Game.Teams exposing (Team, Teams, emptyTeams)
import Game.Words exposing (Word, Words)
import Html exposing (p)
import Player exposing (Player, PlayerStatus(..))
import Test exposing (..)


suit : Test
suit =
    describe "Gameplay" [ isRoundEndSuit, isLocalPlayersTurnSuit, isExplainingSuit, endOfExplainingSuit, switchTimerSuit, guessWordSuit ]


isRoundEndSuit : Test
isRoundEndSuit =
    describe "isRoundEnd"
        [ test "isRoundEnd beggining" <|
            \_ ->
                let
                    testState =
                        GameState (Words [] Maybe.Nothing []) emptyTeams 1 (Game.Game.NotTicking 5) Game.Game.PlayingRound 0 Nothing Nothing
                in
                isRoundEnd testState
                    |> Expect.equal True
        , test "isRoundEnd next not empty" <|
            \_ ->
                let
                    testState =
                        GameState (Words [] Maybe.Nothing [ Word "" "word" "p1" ]) emptyTeams 1 (Game.Game.NotTicking 5) Game.Game.PlayingRound 0 Nothing Nothing
                in
                isRoundEnd testState
                    |> Expect.equal False
        , test "isRoundEnd current not empty" <|
            \_ ->
                let
                    testState =
                        GameState (Words [] (Just (Word "" "word" "p1")) []) emptyTeams 1 (Game.Game.NotTicking 5) Game.Game.PlayingRound 0 Nothing Nothing
                in
                isRoundEnd testState
                    |> Expect.equal False
        , test "isRoundEnd yes" <|
            \_ ->
                let
                    testState =
                        GameState (Words [ Word "" "word" "p1" ] Maybe.Nothing []) emptyTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing
                in
                isRoundEnd testState
                    |> Expect.equal True
        ]


isLocalPlayersTurnSuit : Test
isLocalPlayersTurnSuit =
    describe "isLocalPlayersTurn"
        [ test "isLocalPlayersTurn onTurn" <|
            \_ ->
                let
                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] Maybe.Nothing []) testTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    testUser =
                        Player "1" "p1" Online False
                in
                isLocalPlayersTurn testGame testUser
                    |> Expect.equal True
        , test "isLocalPlayersTurn onTurn second" <|
            \_ ->
                let
                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] Maybe.Nothing []) testTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    testUser =
                        Player "2" "p2" Online False
                in
                isLocalPlayersTurn testGame testUser
                    |> Expect.equal True
        , test "isLocalPlayersTurn not onTurn" <|
            \_ ->
                let
                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] Maybe.Nothing []) testTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    testUser =
                        Player "2-1" "p21" Online False
                in
                isLocalPlayersTurn testGame testUser
                    |> Expect.equal False
        ]


isExplainingSuit : Test
isExplainingSuit =
    describe "isExplaining"
        [ test "isExplaining onTurn" <|
            \_ ->
                let
                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] Maybe.Nothing []) testTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    testUser =
                        Player "1" "p1" Online False
                in
                isExplaining testGame testUser
                    |> Expect.equal True
        , test "isExplaining onTurn second" <|
            \_ ->
                let
                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] Maybe.Nothing []) testTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    testUser =
                        Player "2" "p2" Online False
                in
                isExplaining testGame testUser
                    |> Expect.equal False
        , test "isExplaining not onTurn" <|
            \_ ->
                let
                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] Maybe.Nothing []) testTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    testUser =
                        Player "2-1" "p21" Online False
                in
                isExplaining testGame testUser
                    |> Expect.equal False
        ]


nextRoundSuit : Test
nextRoundSuit =
    describe "nextRound"
        [ test "nextRound create teams before first round and after adding words" <|
            \_ ->
                let
                    testPlayers =
                        Dict.fromList [ ( "1", Player "1" "p1" Online False ), ( "2", Player "2" "p2" Online False ), ( "2-1", Player "2-1" "p21" Online False ), ( "2-2", Player "2-2" "p22" Online False ) ]

                    testState =
                        GameState (Words [] Maybe.Nothing []) emptyTeams 0 (Game.Game.NotTicking 5) Game.Game.AddingWords 1 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants testPlayers Dict.empty) testState 60
                in
                Expect.all
                    [ .current >> Expect.notEqual Maybe.Nothing
                    , .next
                        >> List.length
                        >> Expect.equal 1
                    , .next
                        >> List.map (.players >> List.length)
                        >> Expect.equal [ 2 ]
                    ]
                    (nextRound testGame).state.teams
        , test "nextRound do nothing at the beginning" <|
            \_ ->
                let
                    wordsList =
                        [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]

                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] Maybe.Nothing wordsList) testTeams -1 (Game.Game.NotTicking 5) Game.Game.Lobby 0 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    expectedState =
                        { testState | round = 0 }

                    expectedGame =
                        { testGame | state = expectedState }
                in
                nextRound testGame
                    |> Expect.equal expectedGame
        , test "nextRound restarts guessed words after explaining round" <|
            \_ ->
                let
                    wordsList =
                        [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]

                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words wordsList Maybe.Nothing []) testTeams 1 (Game.Game.NotTicking 60) Game.Game.PlayingRound 2 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60
                in
                Expect.all
                    [ .teams
                        >> Expect.equal testTeams
                    , .words >> .guessed >> List.length >> Expect.equal 0
                    , .words
                        >> .current
                        >> Expect.equal Maybe.Nothing
                    , .words
                        >> .next
                        >> List.length
                        >> Expect.equal (List.length wordsList)
                    ]
                    (nextRound testGame).state
        ]


endOfExplainingSuit : Test
endOfExplainingSuit =
    describe "endOfExplaining"
        [ test "endOfExplaining standard " <|
            \_ ->
                let
                    wordsList =
                        [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]

                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    expectTeams =
                        Teams (Just (Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10)) [ Team [ Player "2" "p2" Online False, Player "1" "p1" Online False ] 0 ]

                    testState =
                        GameState (Words [] (Just (Word "d" "player2" "")) wordsList) testTeams 1 (Game.Game.NotTicking 60) Game.Game.PlayingRound 2 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60

                    wordsExpectation =
                        \words ->
                            Expect.all
                                [ .current
                                    >> Expect.equal Maybe.Nothing
                                , .guessed
                                    >> Expect.equal []
                                , .next
                                    >> List.length
                                    >> Expect.equal 4
                                ]
                                words
                in
                Expect.all
                    [ .state
                        >> .turnTimer
                        >> Expect.equal (Restarted 60)
                    , .state >> .words >> wordsExpectation
                    , .state
                        >> .teams
                        >> Expect.equal expectTeams
                    ]
                    (endOfExplaining testGame)
        ]


switchTimerSuit : Test
switchTimerSuit =
    describe "switchTimer"
        [ test "should pause if it's ticking" <|
            \_ ->
                let
                    testState =
                        { emptyGameState | turnTimer = Ticking }

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60
                in
                switchTimer testGame 34
                    |> .state
                    |> .turnTimer
                    |> Expect.equal (Game.Game.NotTicking 34)
        , test "should just continue if in the middle of explaining" <|
            \_ ->
                let
                    testState =
                        { emptyGameState | turnTimer = Game.Game.NotTicking 28, round = 1 }

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) Game.Game.emptyGameState 60
                in
                switchTimer testGame 34
                    |> .state
                    |> .turnTimer
                    |> Expect.equal Game.Game.Ticking
        , test "should start the timer in beginning of explaining" <|
            \_ ->
                let
                    testState =
                        { emptyGameState | turnTimer = Game.Game.Restarted 30, round = 1 }

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) Game.Game.emptyGameState 60
                in
                switchTimer testGame 34
                    |> .state
                    |> .turnTimer
                    |> Expect.equal Game.Game.Ticking
        , test "should set the current word at the beginning of explaining" <|
            \_ ->
                let
                    testState =
                        GameState (Words [] Maybe.Nothing [ Word "d" "player2" "" ]) Game.Teams.emptyTeams 1 (Game.Game.Restarted 30) Game.Game.PlayingRound 2 Nothing Nothing

                    testGame =
                        Game "" "" "ownerName" Game.Status.Open (Participants Dict.empty Dict.empty) testState 60
                in
                switchTimer testGame 34
                    |> .state
                    |> .words
                    |> .current
                    |> Expect.notEqual Maybe.Nothing
        ]


guessWordSuit : Test
guessWordSuit =
    describe "guessWord"
        [ test "guessWord standard" <|
            \_ ->
                let
                    wordsList =
                        [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]

                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    expectTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 3)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] (Just (Word "d" "player2" "")) wordsList) testTeams 1 Game.Game.Ticking Game.Game.PlayingRound 2 Nothing Nothing

                    wordsExpectation =
                        \words ->
                            Expect.all
                                [ .current
                                    >> Expect.notEqual Maybe.Nothing
                                , .guessed
                                    >> List.length
                                    >> Expect.equal 3
                                , .next
                                    >> Expect.equal []
                                ]
                                words
                in
                Expect.all
                    [ .turnTimer
                        >> Expect.equal Game.Game.Ticking
                    , .words >> wordsExpectation
                    , .teams
                        >> Expect.equal expectTeams
                    ]
                    (testState
                        |> guessWord 14
                        |> guessWord 14
                        |> guessWord 14
                    )
        , test "guessWord guess all" <|
            \_ ->
                let
                    wordsList =
                        [ Word "a" "player1" "", Word "b" "player2" "", Word "c" "player1" "" ]

                    testTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 0)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    expectTeams =
                        Teams (Just (Team [ Player "1" "p1" Online False, Player "2" "p2" Online False ] 4)) [ Team [ Player "2-1" "p21" Online False, Player "2-2" "p22" Online False ] 10 ]

                    testState =
                        GameState (Words [] (Just (Word "d" "player2" "")) wordsList) testTeams 1 Game.Game.Ticking Game.Game.PlayingRound 2 Nothing Nothing

                    wordsExpectation =
                        \words ->
                            Expect.all
                                [ .current
                                    >> Expect.equal Maybe.Nothing
                                , .guessed
                                    >> List.length
                                    >> Expect.equal 4
                                , .next
                                    >> Expect.equal []
                                ]
                                words
                in
                Expect.all
                    [ .turnTimer
                        >> Expect.equal (Game.Game.NotTicking 14)
                    , .words >> wordsExpectation
                    , .teams
                        >> Expect.equal expectTeams
                    ]
                    (testState
                        |> guessWord 14
                        |> guessWord 14
                        |> guessWord 14
                        |> guessWord 14
                    )
        ]
