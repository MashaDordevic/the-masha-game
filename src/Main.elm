port module Main exposing (..)

import Api
import Browser
import Browser.Dom
import Browser.Navigation as Nav
import Constants exposing (defaultTimer)
import Debugger.Update exposing (isOwner)
import Delay
import Dict
import Game.Game exposing (..)
import Game.Gameplay
import Game.Participants
import Game.Words exposing (Word)
import Json.Decode
import Json.Encode
import Player exposing (Player, PlayerStatus(..))
import Request
import Route
import State exposing (Flags, GameModel(..), LocalUser(..), Model, Msg(..))
import String exposing (join)
import Task
import Time
import Url
import User exposing (..)
import Views.View exposing (view)


devApiUrl : String
devApiUrl =
    "http://localhost:5001/themashagame-990a8/us-central1"



--- PORTS ----


port subscribeToGame : Json.Encode.Value -> Cmd msg


port gameChanged : (Json.Decode.Value -> msg) -> Sub msg


port changeGame : Json.Encode.Value -> Cmd msg


port copyInviteLink : Json.Encode.Value -> Cmd msg


port saveUsernameToLocalStorage : Json.Encode.Value -> Cmd msg


port getUsernameFromLocalStorage : () -> Cmd msg


port receivedUsernameFromLocalStorage : (String -> msg) -> Sub msg


port authTokenChanged : (String -> msg) -> Sub msg



---- MODEL ----


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url navKey =
    let
        route =
            Route.parseUrl url

        apiUrl =
            if flags.environment == "development" then
                devApiUrl

            else
                ""
    in
    ( { currentGame =
            case route of
                Route.Join gameCode ->
                    LoadingGameToJoin { gameCode = gameCode, request = Request.loading ( 0, gameCode ) }

                Route.Create ->
                    CreatingGame { nameInput = "", clientRequestId = flags.createRequestKey ++ "-0", request = Request.idle }

                _ ->
                    Initial { pinInput = "", instructionSlideNumber = 1 }
      , environment = flags.environment
      , authToken = flags.authToken
      , createRequestKey = flags.createRequestKey
      , nextRequestId =
            case route of
                Route.Join _ ->
                    1

                Route.Create ->
                    1

                _ ->
                    0
      , apiUrl = apiUrl
      , errors = []
      , isHelpDialogOpen = False
      , isDonateDialogOpen = False
      , url = url
      , route = route
      , navKey = navKey
      }
    , case route of
        Route.Join gameCode ->
            Api.findGame apiUrl 0 gameCode

        _ ->
            Cmd.none
    )


playingGameUpdate : Msg -> Model -> ( Model, Cmd Msg )
playingGameUpdate msg model =
    case model.currentGame of
        Playing gameModel ->
            case gameModel.localUser of
                LocalPlayer localPlayer ->
                    let
                        game =
                            gameModel.game
                    in
                    case msg of
                        UpdateWordInput input ->
                            ( { model | currentGame = Playing { gameModel | wordInput = input } }, Cmd.none )

                        AddWord ->
                            let
                                submittedWord =
                                    gameModel.wordInput
                                        |> String.trim
                                        |> String.toUpper
                            in
                            if String.isEmpty submittedWord then
                                ( model, Cmd.none )

                            else
                                case Request.begin ( model.nextRequestId, game.id ) gameModel.addWordRequest of
                                    Just request ->
                                        let
                                            newWord =
                                                Game.Words.wordWithKey 0 (Word submittedWord localPlayer.name "")
                                        in
                                        ( { model
                                            | currentGame = Playing { gameModel | addWordRequest = request }
                                            , nextRequestId = model.nextRequestId + 1
                                          }
                                        , Api.addWord model.apiUrl model.authToken model.nextRequestId game.id newWord
                                        )

                                    Nothing ->
                                        ( model, Cmd.none )

                        WordAdded requestId gameId result ->
                            if not (Request.isActive ( requestId, gameId ) gameModel.addWordRequest) then
                                ( model, Cmd.none )

                            else
                                case result of
                                    Ok _ ->
                                        ( { model | currentGame = Playing { gameModel | wordInput = "", addWordRequest = Request.idle } }
                                        , Task.attempt WordInputFocused (Browser.Dom.focus "word")
                                        )

                                    Err _ ->
                                        ( { model | currentGame = Playing { gameModel | addWordRequest = Request.fail ( requestId, gameId ) "Could not add the word. Try again." gameModel.addWordRequest } }, Cmd.none )

                        State.DeleteWord id ->
                            ( model, Api.deleteWord model.apiUrl model.authToken game.id id )

                        QuitGame ->
                            -- TODO: remove the player from the list of players or set to offline
                            ( { model | currentGame = Initial { pinInput = "", instructionSlideNumber = 1 }, errors = [] }, Cmd.none )

                        TimerTick _ ->
                            let
                                newTimerValue =
                                    gameModel.turnTimer - 1

                                cmd =
                                    if newTimerValue < 0 && gameModel.isOwner then
                                        let
                                            newGame =
                                                Game.Gameplay.endOfExplaining game
                                        in
                                        newGame
                                            |> Game.Game.gameEncoder
                                            |> changeGame

                                    else
                                        Cmd.none

                                normalisedTimer =
                                    if newTimerValue < 0 then
                                        0

                                    else
                                        newTimerValue
                            in
                            ( { model | currentGame = Playing { gameModel | turnTimer = normalisedTimer } }, cmd )

                        SwitchTimer ->
                            let
                                canSwitchTimer =
                                    Game.Gameplay.isLocalPlayersTurn game localPlayer

                                newGame =
                                    if canSwitchTimer then
                                        Game.Gameplay.switchTimer game gameModel.turnTimer

                                    else
                                        game
                            in
                            if canSwitchTimer then
                                ( model
                                , newGame
                                    |> Game.Game.gameEncoder
                                    |> changeGame
                                )

                            else
                                ( model, Cmd.none )

                        WordGuessed ->
                            let
                                newGameState =
                                    Game.Gameplay.guessWord gameModel.turnTimer game.state

                                newGame =
                                    { game | state = newGameState }
                            in
                            ( model
                            , newGame
                                |> Game.Game.gameEncoder
                                |> changeGame
                            )

                        GameChanged value ->
                            case Json.Decode.decodeValue gameDecoder value of
                                Ok decodedGame ->
                                    let
                                        newTimer =
                                            case decodedGame.state.turnTimer of
                                                Ticking ->
                                                    gameModel.turnTimer

                                                Game.Game.NotTicking timerValue ->
                                                    timerValue

                                                Game.Game.Restarted timerValue ->
                                                    timerValue

                                        isRoundEnd =
                                            Game.Gameplay.isRoundEnd decodedGame.state && decodedGame.state.round > 0

                                        isLocalPlayerOwner =
                                            Game.Gameplay.isPlayerOnwer decodedGame localPlayer
                                    in
                                    if game.id == decodedGame.id then
                                        ( { model | currentGame = Playing { gameModel | game = decodedGame, isOwner = isLocalPlayerOwner, turnTimer = newTimer, isBetweenRounds = isRoundEnd } }
                                        , if isRoundEnd then
                                            Delay.after 6500 NextRound

                                          else
                                            Cmd.none
                                        )

                                    else
                                        ( model, Cmd.none )

                                Err _ ->
                                    ( model, Cmd.none )

                        _ ->
                            if gameModel.isOwner then
                                case msg of
                                    CopyInviteLink ->
                                        ( model, copyInviteLink (Json.Encode.string game.gameId) )

                                    KickPlayer userId ->
                                        ( model, Api.kickPlayer model.apiUrl model.authToken userId game.id )

                                    StartGame ->
                                        let
                                            newGame =
                                                Game.Gameplay.startGame game
                                        in
                                        ( model
                                        , newGame
                                            |> Game.Game.gameEncoder
                                            |> changeGame
                                        )

                                    StartPlaying ->
                                        ( { model | currentGame = Playing { gameModel | isBetweenRounds = True } }
                                        , Delay.after 6500 NextRound
                                        )

                                    NextRound ->
                                        let
                                            newGame =
                                                Game.Gameplay.nextRound game
                                        in
                                        ( { model | currentGame = Playing { gameModel | isBetweenRounds = False } }
                                        , newGame
                                            |> Game.Game.gameEncoder
                                            |> changeGame
                                        )

                                    _ ->
                                        Debugger.Update.update msg model

                            else
                                Debugger.Update.update msg model

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )



---- UPDATE ----


invalidatePendingNavigation : GameModel -> GameModel
invalidatePendingNavigation currentGame =
    case currentGame of
        CreatingGame _ ->
            Initial { pinInput = "", instructionSlideNumber = 1 }

        LoadingGameToJoin _ ->
            Initial { pinInput = "", instructionSlideNumber = 1 }

        JoiningGame _ ->
            Initial { pinInput = "", instructionSlideNumber = 1 }

        _ ->
            currentGame


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AuthTokenChanged authToken ->
            ( { model | authToken = authToken }, Cmd.none )

        ToggleHelpDialog ->
            ( { model | isHelpDialogOpen = not model.isHelpDialogOpen }, Cmd.none )

        ToggleDonateDialog ->
            ( { model | isDonateDialogOpen = not model.isDonateDialogOpen }, Cmd.none )

        WordInputFocused _ ->
            ( model, Cmd.none )

        UrlChanged url ->
            let
                newRoute =
                    Route.parseUrl url
            in
            case newRoute of
                Route.Join gameCode ->
                    case model.currentGame of
                        LoadingGameToJoin gameModel ->
                            if gameModel.gameCode == gameCode then
                                ( { model | url = url, route = newRoute }, Cmd.none )

                            else
                                ( { model
                                    | currentGame = LoadingGameToJoin { gameCode = gameCode, request = Request.loading ( model.nextRequestId, gameCode ) }
                                    , url = url
                                    , route = newRoute
                                    , nextRequestId = model.nextRequestId + 1
                                  }
                                , Api.findGame model.apiUrl model.nextRequestId gameCode
                                )

                        JoiningGame gameModel ->
                            if gameModel.game.gameId == gameCode then
                                ( { model | url = url, route = newRoute }, Cmd.none )

                            else
                                ( { model
                                    | currentGame = LoadingGameToJoin { gameCode = gameCode, request = Request.loading ( model.nextRequestId, gameCode ) }
                                    , url = url
                                    , route = newRoute
                                    , nextRequestId = model.nextRequestId + 1
                                  }
                                , Api.findGame model.apiUrl model.nextRequestId gameCode
                                )

                        Playing gameModel ->
                            if gameModel.game.gameId == gameCode then
                                ( { model | url = url, route = newRoute }, Cmd.none )

                            else
                                ( { model
                                    | currentGame = LoadingGameToJoin { gameCode = gameCode, request = Request.loading ( model.nextRequestId, gameCode ) }
                                    , url = url
                                    , route = newRoute
                                    , nextRequestId = model.nextRequestId + 1
                                  }
                                , Api.findGame model.apiUrl model.nextRequestId gameCode
                                )

                        _ ->
                            ( { model
                                | currentGame = LoadingGameToJoin { gameCode = gameCode, request = Request.loading ( model.nextRequestId, gameCode ) }
                                , url = url
                                , route = newRoute
                                , nextRequestId = model.nextRequestId + 1
                              }
                            , Api.findGame model.apiUrl model.nextRequestId gameCode
                            )

                Route.Create ->
                    case model.currentGame of
                        CreatingGame _ ->
                            ( { model | url = url, route = newRoute }, Cmd.none )

                        _ ->
                            ( { model
                                | currentGame =
                                    CreatingGame
                                        { nameInput = ""
                                        , clientRequestId = model.createRequestKey ++ "-" ++ String.fromInt model.nextRequestId
                                        , request = Request.idle
                                        }
                                , url = url
                                , route = newRoute
                                , nextRequestId = model.nextRequestId + 1
                              }
                            , Cmd.none
                            )

                _ ->
                    ( { model
                        | currentGame = Initial { pinInput = "", instructionSlideNumber = 1 }
                        , errors = []
                        , url = url
                        , route = newRoute
                      }
                    , Cmd.none
                    )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( { model | currentGame = invalidatePendingNavigation model.currentGame }
                    , Nav.pushUrl model.navKey (Url.toString url)
                    )

                Browser.External href ->
                    ( model, Nav.load href )

        BackToStart ->
            ( { model | currentGame = Initial { pinInput = "", instructionSlideNumber = 1 }, errors = [] }
            , Nav.pushUrl model.navKey "/"
            )

        _ ->
            case model.currentGame of
                Initial gameModel ->
                    case msg of
                        EnterGame ->
                            ( model, Nav.pushUrl model.navKey (String.concat [ "/join/", gameModel.pinInput ]) )

                        SetCreatingGameMode ->
                            ( { model
                                | currentGame =
                                    CreatingGame
                                        { nameInput = ""
                                        , clientRequestId = model.createRequestKey ++ "-" ++ String.fromInt model.nextRequestId
                                        , request = Request.idle
                                        }
                                , nextRequestId = model.nextRequestId + 1
                              }
                            , Nav.pushUrl model.navKey "/create"
                            )

                        UpdatePinInput input ->
                            ( { model | currentGame = Initial { pinInput = input, instructionSlideNumber = 1 } }, Cmd.none )

                        TimerTick _ ->
                            ( { model | currentGame = Initial { pinInput = gameModel.pinInput, instructionSlideNumber = gameModel.instructionSlideNumber + 1 } }, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

                LoadingGameToJoin gameModel ->
                    case msg of
                        RetryGameLookup ->
                            case Request.begin ( model.nextRequestId, gameModel.gameCode ) gameModel.request of
                                Just request ->
                                    ( { model
                                        | currentGame = LoadingGameToJoin { gameModel | request = request }
                                        , nextRequestId = model.nextRequestId + 1
                                      }
                                    , Api.findGame model.apiUrl model.nextRequestId gameModel.gameCode
                                    )

                                Nothing ->
                                    ( model, Cmd.none )

                        GameFound requestId gameCode result ->
                            if not (Request.isActive ( requestId, gameCode ) gameModel.request) then
                                ( model, Cmd.none )

                            else
                                case result of
                                    Ok game ->
                                        ( { model | currentGame = JoiningGame { game = game, nameInput = "", request = Request.idle } }
                                        , Cmd.batch
                                            [ subscribeToGame
                                                (Json.Encode.object
                                                    [ ( "userId", Json.Encode.null )
                                                    , ( "gameId", Json.Encode.string game.id )
                                                    ]
                                                )
                                            , getUsernameFromLocalStorage ()
                                            ]
                                        )

                                    Err _ ->
                                        ( { model | currentGame = LoadingGameToJoin { gameModel | request = Request.fail ( requestId, gameCode ) "Could not find that game. Check the code and try again." gameModel.request } }, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

                CreatingGame gameModel ->
                    case msg of
                        UpdateNameInput input ->
                            ( { model | currentGame = CreatingGame { gameModel | nameInput = String.toUpper input } }, Cmd.none )

                        AddGame ->
                            if String.isEmpty (String.trim gameModel.nameInput) then
                                ( model, Cmd.none )

                            else
                                case Request.begin model.nextRequestId gameModel.request of
                                    Just request ->
                                        let
                                            -- will be overwritten because the user doesn't have an ID yet
                                            tempPlayer =
                                                Player "" gameModel.nameInput Online True

                                            newGame =
                                                Game.Game.createGameModel tempPlayer
                                        in
                                        ( { model
                                            | currentGame = CreatingGame { gameModel | request = request }
                                            , nextRequestId = model.nextRequestId + 1
                                          }
                                        , Api.addGame model.apiUrl model.authToken model.nextRequestId gameModel.clientRequestId gameModel.nameInput newGame
                                        )

                                    Nothing ->
                                        ( model, Cmd.none )

                        GameAdded requestId result ->
                            if not (Request.isActive requestId gameModel.request) then
                                ( model, Cmd.none )

                            else
                                case result of
                                    Ok ( game, player ) ->
                                        ( { model | currentGame = Playing { game = game, isOwner = True, localUser = LocalPlayer player, wordInput = "", addWordRequest = Request.idle, turnTimer = defaultTimer, isBetweenRounds = False } }
                                        , Cmd.batch
                                            [ subscribeToGame
                                                (Json.Encode.object
                                                    [ ( "userId", Json.Encode.string player.id )
                                                    , ( "gameId", Json.Encode.string game.id )
                                                    ]
                                                )
                                            , saveUsernameToLocalStorage (Json.Encode.string player.name)
                                            , Nav.pushUrl model.navKey (String.concat [ "/join/", game.gameId ])
                                            ]
                                        )

                                    Err _ ->
                                        ( { model | currentGame = CreatingGame { gameModel | request = Request.fail requestId "Could not create the game. Try again." gameModel.request } }, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

                JoiningGame gameModel ->
                    case msg of
                        UpdateNameInput input ->
                            ( { model | currentGame = JoiningGame { gameModel | nameInput = String.toUpper input } }, Cmd.none )

                        ReceivedUsernameFromLocalStorage username ->
                            ( { model | currentGame = JoiningGame { gameModel | nameInput = String.toUpper username } }, Cmd.none )

                        JoinedGame requestId gameId result ->
                            if not (Request.isActive ( requestId, gameId ) gameModel.request) then
                                ( model, Cmd.none )

                            else
                                case result of
                                    Ok joinedGameInfo ->
                                        let
                                            game =
                                                gameModel.game

                                            maybeLocalUser : Maybe LocalUser
                                            maybeLocalUser =
                                                case joinedGameInfo.role of
                                                    "player" ->
                                                        Just (LocalPlayer joinedGameInfo.player)

                                                    "watcher" ->
                                                        Just (LocalWatcher joinedGameInfo.player)

                                                    _ ->
                                                        Nothing
                                        in
                                        case maybeLocalUser of
                                            Just localUser ->
                                                let
                                                    isLocalPlayerOwner =
                                                        case localUser of
                                                            LocalPlayer player ->
                                                                Game.Gameplay.isPlayerOnwer game player

                                                            _ ->
                                                                False

                                                    localUserName =
                                                        case localUser of
                                                            LocalPlayer player ->
                                                                player.name

                                                            LocalWatcher watcher ->
                                                                watcher.name
                                                in
                                                ( { model | currentGame = Playing { localUser = localUser, isOwner = isLocalPlayerOwner, game = joinedGameInfo.game, wordInput = "", addWordRequest = Request.idle, turnTimer = defaultTimer, isBetweenRounds = False } }
                                                , Cmd.batch
                                                    [ subscribeToGame
                                                        (Json.Encode.object
                                                            [ ( "userId", Json.Encode.string joinedGameInfo.player.id )
                                                            , ( "gameId", Json.Encode.string game.id )
                                                            ]
                                                        )
                                                    , saveUsernameToLocalStorage (Json.Encode.string localUserName)
                                                    ]
                                                )

                                            Nothing ->
                                                ( { model | currentGame = JoiningGame { gameModel | request = Request.fail ( requestId, gameId ) joinedGameInfo.status gameModel.request } }, Cmd.none )

                                    Err _ ->
                                        ( { model | currentGame = JoiningGame { gameModel | request = Request.fail ( requestId, gameId ) "Could not join the game. Try again." gameModel.request } }, Cmd.none )

                        JoinGame ->
                            if String.isEmpty (String.trim gameModel.nameInput) then
                                ( model, Cmd.none )

                            else
                                case Request.begin ( model.nextRequestId, gameModel.game.gameId ) gameModel.request of
                                    Just request ->
                                        ( { model
                                            | currentGame = JoiningGame { gameModel | request = request }
                                            , nextRequestId = model.nextRequestId + 1
                                          }
                                        , Api.joinGame model.apiUrl model.authToken model.nextRequestId gameModel.game.gameId gameModel.nameInput
                                        )

                                    Nothing ->
                                        ( model, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

                Playing _ ->
                    playingGameUpdate msg model



---- SUBSCRIPTOINS ----


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        timerSub =
            case model.currentGame of
                Playing gameModel ->
                    case gameModel.game.state.turnTimer of
                        Game.Game.Ticking ->
                            Time.every 1000 TimerTick

                        _ ->
                            Sub.none

                Initial _ ->
                    Time.every 5000 TimerTick

                _ ->
                    Sub.none
    in
    Sub.batch
        [ gameChanged GameChanged
        , authTokenChanged AuthTokenChanged
        , receivedUsernameFromLocalStorage ReceivedUsernameFromLocalStorage
        , timerSub
        ]



---- VIEW ----
---- PROGRAM ----


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }
