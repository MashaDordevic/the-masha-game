module EncodingTest exposing (suite)

import Api
import Dict
import Expect
import Game.Game exposing (Game, GameState, TurnTimer(..), emptyGameState, gameDecoder, gameEncoder, gameStateDecoder, gameStateEncoder, turnTimerDecoder, turnTimerEncoder)
import Game.Participants exposing (Participants, emptyParticipants, participantsDecoder, participantsEncoder)
import Game.Status exposing (GameStatus(..), gameStatusDecoder, gameStatusEncoder)
import Game.Teams exposing (Team, Teams, emptyTeams, teamDecoder, teamEncoder, teamsDecoder, teamsEncoder)
import Game.Words exposing (Word, Words, wordDecoder, wordEncoder, wordsDecoder, wordsEncoder)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Player exposing (Player, PlayerStatus(..), playerDecoder, playerEncoder, playerSatatusEncoder, playerStatusDecoder)
import Test exposing (Test, describe, test)
import User exposing (User, decodeUser, userEncoder)


player : Player
player =
    Player "player-1" "Masha" Online True


otherPlayer : Player
otherPlayer =
    Player "player-2" "Pera" Offline False


word : Word
word =
    Word "elm" "player-1" "000-elm-player-1"


otherWord : Word
otherWord =
    Word "json" "player-2" "000-json-player-2"


team : Team
team =
    Team [ player, otherPlayer ] 3


words : Words
words =
    Words [ word ] (Just otherWord) [ otherWord ]


participants : Participants
participants =
    Participants
        (Dict.fromList [ ( player.id, player ) ])
        (Dict.fromList [ ( otherPlayer.id, otherPlayer ) ])


teams : Teams
teams =
    Teams (Just team) [ Team [ otherPlayer, player ] 1 ]


gameState : GameState
gameState =
    GameState words teams 2 (NotTicking 17)


game : Game
game =
    Game "database-id" "ABCD" "Masha" Running participants gameState 60


roundTrip : Decoder a -> (a -> Encode.Value) -> a -> Expect.Expectation
roundTrip decoder encoder value =
    encoder value
        |> Decode.decodeValue decoder
        |> Expect.equal (Ok value)


expectFailure : Decoder a -> Encode.Value -> Expect.Expectation
expectFailure decoder value =
    case Decode.decodeValue decoder value of
        Err _ ->
            Expect.pass

        Ok _ ->
            Expect.fail "Expected malformed JSON to be rejected"


decodeObject : Decoder a -> List ( String, Encode.Value ) -> Result Decode.Error a
decodeObject decoder fields =
    Encode.object fields
        |> Decode.decodeValue decoder


suite : Test
suite =
    describe "JSON encoding and decoding"
        [ describe "round trips"
            [ test "game statuses" <|
                \_ ->
                    [ Open, Running, Finished ]
                        |> List.map (gameStatusEncoder >> Decode.decodeValue gameStatusDecoder)
                        |> Expect.equal [ Ok Open, Ok Running, Ok Finished ]
            , test "player statuses" <|
                \_ ->
                    [ Online, Offline ]
                        |> List.map (playerSatatusEncoder >> Decode.decodeValue playerStatusDecoder)
                        |> Expect.equal [ Ok Online, Ok Offline ]
            , test "turn timer variants" <|
                \_ ->
                    [ Ticking, NotTicking 12, Restarted 60 ]
                        |> List.map (turnTimerEncoder >> Decode.decodeValue turnTimerDecoder)
                        |> Expect.equal [ Ok Ticking, Ok (NotTicking 12), Ok (Restarted 60) ]
            , test "users, including empty boundary strings" <|
                \_ ->
                    roundTrip decodeUser userEncoder (User "" "")
            , test "players" <|
                \_ ->
                    roundTrip playerDecoder playerEncoder player
            , test "words" <|
                \_ ->
                    roundTrip wordDecoder wordEncoder word
            , test "word collections preserve stable IDs and shuffled order" <|
                \_ ->
                    let
                        shuffledWords =
                            Words
                                [ Word "rock paper scissors" "player-2" "word-zeta" ]
                                (Just (Word "New York City" "player-1" "word-current"))
                                [ Word "ice cream" "player-1" "word-charlie"
                                , Word "Elm compiler" "player-2" "word-alpha"
                                ]
                    in
                    roundTrip wordsDecoder wordsEncoder shuffledWords
            , test "participants" <|
                \_ ->
                    roundTrip participantsDecoder participantsEncoder participants
            , test "teams and team state" <|
                \_ ->
                    Expect.all
                        [ \_ -> roundTrip teamDecoder teamEncoder team
                        , \_ -> roundTrip teamsDecoder teamsEncoder teams
                        ]
                        ()
            , test "game state and complete games" <|
                \_ ->
                    Expect.all
                        [ \_ -> roundTrip gameStateDecoder gameStateEncoder gameState
                        , \_ -> roundTrip gameDecoder gameEncoder game
                        ]
                        ()
            , test "API response decoders compose the model decoders" <|
                \_ ->
                    let
                        joinedResponse =
                            Encode.object
                                [ ( "status", Encode.string "joined" )
                                , ( "role", Encode.string "player" )
                                , ( "player", playerEncoder player )
                                , ( "game", gameEncoder game )
                                ]

                        addedResponse =
                            Encode.object
                                [ ( "game", gameEncoder game )
                                , ( "player", playerEncoder player )
                                ]
                    in
                    Expect.all
                        [ \_ ->
                            Decode.decodeValue Api.joinedGameResponseDecoder joinedResponse
                                |> Result.map
                                    (\result ->
                                        { status = result.status
                                        , role = result.role
                                        , player = result.player
                                        , game = result.game
                                        }
                                    )
                                |> Expect.equal
                                    (Ok
                                        { status = "joined"
                                        , role = "player"
                                        , player = player
                                        , game = game
                                        }
                                    )
                        , \_ ->
                            Decode.decodeValue Api.addedGameResponseDecoder addedResponse
                                |> Expect.equal (Ok ( game, player ))
                        ]
                        ()
            ]
        , describe "missing, null, and empty state"
            [ test "empty word collections decode to empty state" <|
                \_ ->
                    Decode.decodeString wordsDecoder "{}"
                        |> Expect.equal (Ok (Words [] Nothing []))
            , test "null word collection fields decode to empty state" <|
                \_ ->
                    Decode.decodeString wordsDecoder """{"guessed":null,"current":null,"next":null}"""
                        |> Expect.equal (Ok (Words [] Nothing []))
            , test "empty and null participant maps decode to empty state" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            Decode.decodeString participantsDecoder "{}"
                                |> Expect.equal (Ok emptyParticipants)
                        , \_ ->
                            Decode.decodeString participantsDecoder """{"players":null,"joinRequests":null}"""
                                |> Expect.equal (Ok emptyParticipants)
                        ]
                        ()
            , test "empty and null team collections decode to empty state" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            Decode.decodeString teamsDecoder "{}"
                                |> Expect.equal (Ok emptyTeams)
                        , \_ ->
                            Decode.decodeString teamsDecoder """{"current":null,"next":null}"""
                                |> Expect.equal (Ok emptyTeams)
                        ]
                        ()
            , test "missing and null team players decode to an empty list" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            Decode.decodeString teamDecoder """{"score":0}"""
                                |> Expect.equal (Ok (Team [] 0))
                        , \_ ->
                            Decode.decodeString teamDecoder """{"players":null,"score":0}"""
                                |> Expect.equal (Ok (Team [] 0))
                        ]
                        ()
            , test "missing and null game aggregates use migration defaults" <|
                \_ ->
                    let
                        expected =
                            Game "database-id" "ABCD" "Masha" Open emptyParticipants emptyGameState 60

                        requiredFields =
                            [ ( "id", Encode.string "database-id" )
                            , ( "gameId", Encode.string "ABCD" )
                            , ( "creator", Encode.string "Masha" )
                            , ( "status", Encode.string "open" )
                            , ( "defaultTimer", Encode.int 60 )
                            ]
                    in
                    Expect.all
                        [ \_ ->
                            decodeObject gameDecoder requiredFields
                                |> Expect.equal (Ok expected)
                        , \_ ->
                            decodeObject gameDecoder
                                (( "participants", Encode.null )
                                    :: ( "state", Encode.null )
                                    :: requiredFields
                                )
                                |> Expect.equal (Ok expected)
                        ]
                        ()
            ]
        , describe "malformed state is rejected"
            [ test "unknown discriminators" <|
                \_ ->
                    Expect.all
                        [ \_ -> expectFailure gameStatusDecoder (Encode.string "archived")
                        , \_ -> expectFailure playerStatusDecoder (Encode.string "away")
                        , \_ ->
                            expectFailure turnTimerDecoder
                                (Encode.object [ ( "status", Encode.string "stopped" ) ])
                        ]
                        ()
            , test "malformed word collection fields" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            expectFailure wordsDecoder
                                (Encode.object [ ( "guessed", Encode.list identity [] ) ])
                        , \_ ->
                            expectFailure wordsDecoder
                                (Encode.object [ ( "current", Encode.int 1 ) ])
                        , \_ ->
                            expectFailure wordsDecoder
                                (Encode.object [ ( "next", Encode.string "not-a-map" ) ])
                        ]
                        ()
            , test "malformed participant maps" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            expectFailure participantsDecoder
                                (Encode.object [ ( "players", Encode.list identity [] ) ])
                        , \_ ->
                            expectFailure participantsDecoder
                                (Encode.object [ ( "joinRequests", Encode.bool False ) ])
                        ]
                        ()
            , test "malformed team fields" <|
                \_ ->
                    Expect.all
                        [ \_ ->
                            expectFailure teamsDecoder
                                (Encode.object [ ( "current", Encode.string "not-a-team" ) ])
                        , \_ ->
                            expectFailure teamsDecoder
                                (Encode.object [ ( "next", Encode.object [] ) ])
                        , \_ ->
                            expectFailure teamDecoder
                                (Encode.object
                                    [ ( "players", Encode.object [] )
                                    , ( "score", Encode.int 0 )
                                    ]
                                )
                        ]
                        ()
            , test "malformed game aggregates" <|
                \_ ->
                    let
                        requiredFields =
                            [ ( "id", Encode.string "database-id" )
                            , ( "gameId", Encode.string "ABCD" )
                            , ( "creator", Encode.string "Masha" )
                            , ( "status", Encode.string "open" )
                            , ( "defaultTimer", Encode.int 60 )
                            ]
                    in
                    Expect.all
                        [ \_ ->
                            expectFailure gameDecoder
                                (Encode.object
                                    (( "participants", Encode.list identity [] )
                                        :: requiredFields
                                    )
                                )
                        , \_ ->
                            expectFailure gameDecoder
                                (Encode.object
                                    (( "state", Encode.string "not-a-state" )
                                        :: requiredFields
                                    )
                                )
                        , \_ ->
                            expectFailure gameStateDecoder
                                (Encode.object
                                    [ ( "round", Encode.int 1 )
                                    , ( "turnTimer", turnTimerEncoder Ticking )
                                    , ( "words", Encode.list identity [] )
                                    ]
                                )
                        ]
                        ()
            , test "required record fields remain required" <|
                \_ ->
                    Expect.all
                        [ \_ -> expectFailure playerDecoder (Encode.object [])
                        , \_ -> expectFailure wordDecoder (Encode.object [])
                        , \_ -> expectFailure decodeUser (Encode.object [])
                        , \_ ->
                            expectFailure Api.joinedGameResponseDecoder
                                (Encode.object [ ( "status", Encode.string "joined" ) ])
                        ]
                        ()
            ]
        ]
