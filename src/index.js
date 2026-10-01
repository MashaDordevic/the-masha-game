import "./main.css";
import {Elm} from "./Main.elm";
import * as serviceWorker from "./serviceWorker";
import NoSleep from "nosleep.js";

var noSleep = new NoSleep();

function enableNoSleep() {
  noSleep.enable();
  document.removeEventListener("touchstart", enableNoSleep, false);
}

// Enable wake lock.
// (must be wrapped in a user input event handler e.g. a mouse or touch handler)
document.addEventListener("touchstart", enableNoSleep, false);

const LOCAL_STORAGE_KEY = "TheMashaGame.username";

// Your web app's Firebase configuration
const firebaseConfig = {
    apiKey: "AIzaSyA_Hv4Deh_usUCTACNLESTxpyM4QHWfv58",
    authDomain: "themashagame-990a8.firebaseapp.com",
    databaseURL:
      process.env.NODE_ENV === "development"
        ? "http://localhost:9000?ns=themashagame-990a8"
        : "https://themashagame-990a8.firebaseio.com",
    projectId: "themashagame-990a8",
    storageBucket: "themashagame-990a8.appspot.com",
    messagingSenderId: "616742583607",
    appId: "1:616742583607:web:cae493ca4fc3a05e98eeb2",
    measurementId: "G-5NL1EL32WM"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
const database = firebase.database();

const app = Elm.Main.init({
  node: document.getElementById("root"),
  flags: {
    environment: process.env.NODE_ENV,
  },
});

const GAMES_PATH = "games";

app.ports.subscribeToGame.subscribe(({ gameId, userId }) => {
  console.log("subscribing to game", gameId, "user: ", userId);
  database.ref(`${GAMES_PATH}/${gameId}`).on("child_changed", () => {
    database
      .ref(`${GAMES_PATH}/${gameId}`)
      .once("value")
      .then((data) => {
        const newGame = { ...data.val(), id: data.key };
        console.log("new game data", newGame);
        app.ports.gameChanged.send(newGame);
      });
  });

  if (!userId) {
    return;
  }
  // user online/offline status management
  managePlayerStatus({ gameId, userId });
});

app.ports.changeGame.subscribe((game) => {
  console.log("updating game to", game);
  database.ref(`${GAMES_PATH}/${game.id}`).set(game);
});

app.ports.copyInviteLink.subscribe((gameId) => {
  console.log("copy to clipboard", gameId);
  navigator.clipboard.writeText(`${window.location.origin}/join/${gameId}`);
});

app.ports.saveUsernameToLocalStorage.subscribe((username) => {
  localStorage.setItem(LOCAL_STORAGE_KEY, username);
});

app.ports.getUsernameFromLocalStorage.subscribe(() => {
  const username = localStorage.getItem(LOCAL_STORAGE_KEY) ?? "";
  app.ports.receivedUsernameFromLocalStorage.send(username);
});

const managePlayerStatus = ({ gameId, userId }) => {
  // Create a reference to this user's specific status node.
  // This is where we will store data about being online/offline.
  var userStatusDatabaseRef = database.ref(
    `${GAMES_PATH}/${gameId}/participants/players/${userId}/status`
  );

  // We'll create two constants which we will write to
  // the Realtime database when this device is offline
  // or online.
  var isOfflineForDatabase = "offline";
  //  = {
  //   state: "offline",
  //   last_changed: firebase.database.ServerValue.TIMESTAMP,
  // };

  var isOnlineForDatabase = "online";
  // {
  //   state: "online",
  //   last_changed: firebase.database.ServerValue.TIMESTAMP,
  // };

  // Create a reference to the special '.info/connected' path in
  // Realtime Database. This path returns `true` when connected
  // and `false` when disconnected.
  database.ref(".info/connected").on("value", function (snapshot) {
    // If we're not currently connected, don't do anything.
    if (snapshot.val() == false) {
      return;
    }

    // If we are currently connected, then use the 'onDisconnect()'
    // method to add a set which will only trigger once this
    // client has disconnected by closing the app,
    // losing internet, or any other means.
    userStatusDatabaseRef
      .onDisconnect()
      .set(isOfflineForDatabase)
      .then(function () {
        // The promise returned from .onDisconnect().set() will
        // resolve as soon as the server acknowledges the onDisconnect()
        // request, NOT once we've actually disconnected:
        // https://firebase.google.com/docs/reference/js/firebase.database.OnDisconnect

        // We can now safely set ourselves as 'online' knowing that the
        // server will mark us as offline once we lose connection.
        userStatusDatabaseRef.set(isOnlineForDatabase);
      });
  });
};

// If you want your app to work offline and load faster, you can change
// unregister() to register() below. Note this comes with some pitfalls.
// Learn more about service workers: https://bit.ly/CRA-PWA
serviceWorker.unregister();
