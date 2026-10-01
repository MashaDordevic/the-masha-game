module State exposing (..)

import Browser
import Browser.Navigation
import Game.Game exposing (Game)
import Http
import Json.Decode
import Player exposing (Player)
import Request
import Route exposing (Route)
import Time
import Url


type alias Flags =
    { authToken : String
    , environment : String
    , createRequestKey : String
    }


type LocalUser
    = LocalPlayer Player
    | LocalWatcher Player


type alias PlayingGameModel =
    { localUser : LocalUser
    , game : Game
    , isOwner : Bool
    , wordInput : String
    , addWordRequest : Request.State ( RequestId, String ) String
    , turnTimer : Int
    , isBetweenRounds : Bool
    }


type alias InitialGameModel =
    { pinInput : String
    , instructionSlideNumber : Int
    }


type alias RequestId =
    Int


type GameModel
    = Initial InitialGameModel
    | CreatingGame { nameInput : String, clientRequestId : String, request : Request.State RequestId String }
    | LoadingGameToJoin { gameCode : String, request : Request.State ( RequestId, String ) String }
    | JoiningGame { game : Game, nameInput : String, request : Request.State ( RequestId, String ) String }
    | Playing PlayingGameModel


type alias Errors =
    List String


type alias JoinedGameInfo =
    { status : String
    , role : String
    , player : Player
    , game : Game
    }


type alias Model =
    { currentGame : GameModel
    , authToken : String
    , createRequestKey : String
    , nextRequestId : RequestId
    , environment : String
    , apiUrl : String
    , errors : Errors
    , isHelpDialogOpen : Bool
    , isDonateDialogOpen : Bool
    , url : Url.Url
    , route : Route
    , navKey : Browser.Navigation.Key
    }


type Msg
    = UrlChanged Url.Url
    | LinkClicked Browser.UrlRequest
    | SetCreatingGameMode
    | UpdateNameInput String
    | RetryGameLookup
    | BackToStart
    | AddGame
    | JoinGame
    | EnterGame
    | GameChanged Json.Decode.Value
    | KickPlayer String
    | StartGame
    | CopyInviteLink
    | UpdateWordInput String
    | UpdatePinInput String
    | AddWord
    | NextRound
    | StartPlaying
    | DeleteWord String
    | QuitGame
    | TimerTick Time.Posix
    | SwitchTimer
    | WordGuessed
    | ToggleHelpDialog
    | ToggleDonateDialog
    | DebugRestart
    | DebugLobby
    | DebugStarted
    | DebugRestartWords
    | DebugSetPlayerOnTurn
    | DebugSetPlayerOwner
    | DebugSetNextPlayer
    | DebugGuessNextWords
    | DebugSetRound Int
    | GameFound RequestId String (Result Http.Error Game)
    | GameAdded RequestId (Result Http.Error ( Game, Player ))
    | JoinedGame RequestId String (Result Http.Error JoinedGameInfo)
    | WordAdded RequestId String (Result Http.Error String)
    | AuthTokenChanged String
    | ReceivedUsernameFromLocalStorage String
    | NoOpResult (Result Http.Error String)
