module State exposing (..)

import Browser
import Browser.Navigation
import Game.Game exposing (Game)
import Http
import Json.Decode
import Player exposing (Player)
import Route exposing (Route)
import Time
import Url


type alias Flags =
    { environment : String
    }


type LocalUser
    = LocalPlayer Player
    | LocalWatcher Player


type alias PlayingGameModel =
    { localUser : LocalUser, game : Game, isOwner : Bool, wordInput : String, turnTimer : Int, isBetweenRounds : Bool }


type alias InitialGameModel =
    { pinInput : String
    , instructionSlideNumber : Int
    }


type GameModel
    = Initial InitialGameModel
    | CreatingGame { nameInput : String }
    | LoadingGameToJoin { nameInput : String }
    | JoiningGame { game : Game, nameInput : String }
    | Playing PlayingGameModel


type alias Errors =
    List String


type alias JoinedGameInfo =
    { status : String
    , player : Player
    , game : Game
    }


type alias Model =
    { currentGame : GameModel
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
    | GameNotFound
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
    | GameFound (Result Http.Error Game)
    | GameAdded (Result Http.Error ( Game, Player ))
    | JoinedGame (Result Http.Error JoinedGameInfo)
    | ReceivedUsernameFromLocalStorage String
    | NoOpResult (Result Http.Error String)
