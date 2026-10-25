port module Main exposing (..)

import Api
import Browser
import Browser.Dom
import Browser.Navigation as Nav
import Debugger.Update
import Dict
import Game.Game exposing (..)
import Game.Gameplay
import Game.Interstitial
import Game.Words exposing (Word)
import Set
import Http
import Json.Decode
import Json.Encode
import Request
import Route
import State exposing (Flags, GameModel(..), LocalUser(..), Model, Msg(..))
import Task
import Time
import Url
import Views.View exposing (view)


devApiUrl : String
devApiUrl =
    "http://localhost:5001/themashagame-990a8/us-central1"



--- PORTS ----


port subscribeToGame : Json.Encode.Value -> Cmd msg


port gameChanged : (Json.Decode.Value -> msg) -> Sub msg


port copyInviteLink : Json.Encode.Value -> Cmd msg


port saveUsernameToLocalStorage : Json.Encode.Value -> Cmd msg


port getUsernameFromLocalStorage : () -> Cmd msg


port receivedUsernameFromLocalStorage : (String -> msg) -> Sub msg


port authTokenChanged : (String -> msg) -> Sub msg


port serverTimeOffsetChanged : (Float -> msg) -> Sub msg


port presenceChanged : (List String -> msg) -> Sub msg



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
      , serverTimeOffsetMs = 0
      , now = Time.millisToPosix 0
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


localPlayerId : LocalUser -> String
localPlayerId localUser =
    case localUser of
        LocalPlayer player ->
            player.id

        LocalWatcher player ->
            player.id


presentGame : State.PlayingGameModel -> Game -> Game
presentGame gameModel game =
    Game.Gameplay.withPresence (localPlayerId gameModel.localUser) gameModel.onlinePlayerIds game


newPlaying : Game -> LocalUser -> State.PlayingGameModel
newPlaying game localUser =
    let
        gameModel =
            { localUser = localUser
            , game = game
            , wordInput = ""
            , addWordRequest = Request.idle
            , onlinePlayerIds = Set.empty
            , isStartConfirmationOpen = False
            , isStartRequestPending = False
            , startRequestError = Nothing
            , isDebugFixture = False
            }
    in
    { gameModel | game = presentGame gameModel game }


dueTransitionCmd : Model -> Game -> Cmd Msg
dueTransitionCmd model game =
    case Game.Interstitial.dueTransition model.serverTimeOffsetMs model.now game of
        Just Game.Interstitial.EnterBetweenRounds ->
            Api.enterBetweenRounds model.apiUrl model.authToken game.id game.state.revision

        Just Game.Interstitial.AdvanceRound ->
            Api.advanceRound model.apiUrl model.authToken game.id game.state.revision

        Nothing ->
            Cmd.none


gameChangedUpdate : Json.Decode.Value -> Model -> State.PlayingGameModel -> ( Model, Cmd Msg )
gameChangedUpdate value model gameModel =
    case Json.Decode.decodeValue gameDecoder value of
        Ok decodedGame ->
            if gameModel.game.id /= decodedGame.id then
                ( model, Cmd.none )

            else
                let
                    remainsInWordEntry =
                        decodedGame.state.phase == AddingWords

                    nextGameModel =
                        { gameModel
                            | game = presentGame gameModel decodedGame
                            , isStartConfirmationOpen = gameModel.isStartConfirmationOpen && remainsInWordEntry
                            , isStartRequestPending = gameModel.isStartRequestPending && remainsInWordEntry
                            , isDebugFixture = False
                        }

                    transitionCmd =
                        case gameModel.localUser of
                            LocalWatcher _ ->
                                Cmd.none

                            LocalPlayer _ ->
                                dueTransitionCmd model nextGameModel.game

                    timerRefreshCmd =
                        case decodedGame.state.turnTimer of
                            Ticking _ ->
                                Task.perform TimerTick Time.now

                            _ ->
                                Cmd.none
                in
                ( { model | currentGame = Playing nextGameModel }
                , Cmd.batch [ timerRefreshCmd, transitionCmd ]
                )

        Err _ ->
            ( model, Cmd.none )


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
                                                Game.Words.wordWithKey 0 (Word submittedWord localPlayer.id "")
                                        in
                                        ( { model
                                            | currentGame = Playing { gameModel | addWordRequest = request }
                                            , nextRequestId = model.nextRequestId + 1
                                          }
                                        , Api.addWord model.apiUrl model.authToken model.nextRequestId game.id newWord.id newWord.word
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

                        TimerTick now ->
                            let
                                expiryCmd =
                                    case game.state.turnTimer of
                                        Ticking deadlineMs ->
                                            if toFloat (Time.posixToMillis now) + model.serverTimeOffsetMs >= deadlineMs then
                                                Api.expireTurn model.apiUrl model.authToken game.id game.state.revision game.state.turnId

                                            else
                                                Cmd.none

                                        _ ->
                                            Cmd.none
                            in
                            ( { model | now = now }, expiryCmd )

                        SwitchTimer ->
                            let
                                canSwitchTimer =
                                    Game.Gameplay.isExplaining game localPlayer

                                timerCmd =
                                    case game.state.turnTimer of
                                        Ticking _ ->
                                            Api.pauseTurn model.apiUrl model.authToken game.id game.state.revision game.state.turnId

                                        _ ->
                                            Api.startTurn model.apiUrl model.authToken game.id game.state.revision game.state.turnId
                            in
                            if canSwitchTimer then
                                ( model, timerCmd )

                            else
                                ( model, Cmd.none )

                        WordGuessed ->
                            if Game.Gameplay.isExplaining game localPlayer then
                                case game.state.turnTimer of
                                    Ticking _ ->
                                        ( model, Api.guessWord model.apiUrl model.authToken game.id game.state.revision game.state.turnId )

                                    _ ->
                                        ( model, Cmd.none )

                            else
                                ( model, Cmd.none )

                        GameChanged value ->
                            gameChangedUpdate value model gameModel

                        OpenStartConfirmation ->
                            if game.state.phase == AddingWords then
                                ( { model | currentGame = Playing { gameModel | isStartConfirmationOpen = True, startRequestError = Nothing } }, Cmd.none )

                            else
                                ( model, Cmd.none )

                        CancelStartConfirmation ->
                            if gameModel.isStartRequestPending then
                                ( model, Cmd.none )

                            else
                                ( { model | currentGame = Playing { gameModel | isStartConfirmationOpen = False, startRequestError = Nothing } }, Cmd.none )

                        ConfirmStartPlaying ->
                            if gameModel.isStartConfirmationOpen && not gameModel.isStartRequestPending && game.state.phase == AddingWords then
                                ( { model | currentGame = Playing { gameModel | isStartRequestPending = True, startRequestError = Nothing } }
                                , Api.startBetweenRounds model.apiUrl model.authToken game.id game.state.revision
                                )

                            else
                                ( model, Cmd.none )

                        StartBetweenRoundsCompleted result ->
                            case result of
                                Ok _ ->
                                    ( { model | currentGame = Playing { gameModel | isStartRequestPending = False } }, Cmd.none )

                                Err _ ->
                                    ( { model | currentGame = Playing { gameModel | isStartRequestPending = False, startRequestError = Just "Could not start the game. Try again." } }, Cmd.none )

                        TransitionTick now ->
                            let
                                timedModel =
                                    { model | now = now }
                            in
                            ( timedModel, dueTransitionCmd timedModel game )

                        PresenceChanged onlinePlayerIds ->
                            let
                                nextGameModel =
                                    { gameModel | onlinePlayerIds = Set.fromList onlinePlayerIds }
                            in
                            ( { model | currentGame = Playing { nextGameModel | game = presentGame nextGameModel gameModel.game } }, Cmd.none )

                        _ ->
                            if Game.Gameplay.isOwner game localPlayer then
                                case msg of
                                    CopyInviteLink ->
                                        ( model, copyInviteLink (Json.Encode.string game.gameId) )

                                    KickPlayer userId ->
                                        if gameModel.isDebugFixture then
                                            Debugger.Update.update msg model

                                        else
                                            ( model, Api.kickPlayer model.apiUrl model.authToken userId game.id )

                                    StartGame ->
                                        ( model, Api.startGame model.apiUrl model.authToken game.id game.state.revision )

                                    _ ->
                                        Debugger.Update.update msg model

                            else
                                Debugger.Update.update msg model

                LocalWatcher _ ->
                    case msg of
                        GameChanged value ->
                            gameChangedUpdate value model gameModel

                        PresenceChanged onlinePlayerIds ->
                            let
                                nextGameModel =
                                    { gameModel | onlinePlayerIds = Set.fromList onlinePlayerIds }
                            in
                            ( { model | currentGame = Playing { nextGameModel | game = presentGame nextGameModel gameModel.game } }, Cmd.none )

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

        ServerTimeOffsetChanged offsetMs ->
            ( { model | serverTimeOffsetMs = offsetMs }, Cmd.none )

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

                                    Err error ->
                                        let
                                            message =
                                                case error of
                                                    Http.BadStatus 409 ->
                                                        "This game uses an older running timer and cannot be recovered. Create a new game."

                                                    _ ->
                                                        "Could not find that game. Check the code and try again."
                                        in
                                        ( { model | currentGame = LoadingGameToJoin { gameModel | request = Request.fail ( requestId, gameCode ) message gameModel.request } }, Cmd.none )

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
                                        ( { model
                                            | currentGame = CreatingGame { gameModel | request = request }
                                            , nextRequestId = model.nextRequestId + 1
                                          }
                                        , Api.addGame model.apiUrl model.authToken model.nextRequestId gameModel.clientRequestId gameModel.nameInput
                                        )

                                    Nothing ->
                                        ( model, Cmd.none )

                        GameAdded requestId result ->
                            if not (Request.isActive requestId gameModel.request) then
                                ( model, Cmd.none )

                            else
                                case result of
                                    Ok ( game, player ) ->
                                        ( { model | currentGame = Playing (newPlaying game (LocalPlayer player)) }
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
                                                    localUserName =
                                                        case localUser of
                                                            LocalPlayer player ->
                                                                player.name

                                                            LocalWatcher watcher ->
                                                                watcher.name
                                                in
                                                ( { model | currentGame = Playing (newPlaying joinedGameInfo.game localUser) }
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
                        Game.Game.Ticking _ ->
                            Time.every 1000 TimerTick

                        _ ->
                            Sub.none

                Initial _ ->
                    Time.every 5000 TimerTick

                _ ->
                    Sub.none

        transitionSub =
            case model.currentGame of
                Playing gameModel ->
                    case gameModel.localUser of
                        LocalWatcher _ ->
                            Sub.none

                        LocalPlayer _ ->
                            if
                                (gameModel.game.state.phase == PlayingRound && Game.Gameplay.isRoundEnd gameModel.game.state)
                                    || gameModel.game.state.phase
                                    == BetweenRounds
                            then
                                Time.every 1000 TransitionTick

                            else
                                Sub.none

                _ ->
                    Sub.none
    in
    Sub.batch
        [ gameChanged GameChanged
        , authTokenChanged AuthTokenChanged
        , serverTimeOffsetChanged ServerTimeOffsetChanged
        , receivedUsernameFromLocalStorage ReceivedUsernameFromLocalStorage
        , presenceChanged PresenceChanged
        , timerSub
        , transitionSub
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
