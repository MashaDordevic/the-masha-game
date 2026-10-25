import "./main.css";
import { Elm } from "./Main.elm";
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
const isLocalhost =
  window.location.hostname === "localhost" ||
  window.location.hostname === "127.0.0.1";

// Your web app's Firebase configuration
const firebaseConfig = {
  apiKey: "AIzaSyA_Hv4Deh_usUCTACNLESTxpyM4QHWfv58",
  authDomain: "themashagame-990a8.firebaseapp.com",
  databaseURL:
    isLocalhost
      ? "http://localhost:9000?ns=themashagame-990a8"
      : "https://themashagame-990a8.firebaseio.com",
  projectId: "themashagame-990a8",
  storageBucket: "themashagame-990a8.appspot.com",
  messagingSenderId: "616742583607",
  appId: "1:616742583607:web:cae493ca4fc3a05e98eeb2",
  measurementId: "G-5NL1EL32WM",
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
const database = firebase.database();
const auth = firebase.auth();

if (isLocalhost) {
  auth.useEmulator("http://localhost:9099");
}

const initializeElm = (authToken) => {
  let currentAuthToken = authToken;
  const app = Elm.Main.init({
    node: document.getElementById("root"),
    flags: {
      authToken,
      createRequestKey: crypto.randomUUID(),
      environment: process.env.NODE_ENV,
    },
  });

  firebase.auth().onIdTokenChanged(async (user) => {
    if (user) {
      currentAuthToken = await user.getIdToken();
      app.ports.authTokenChanged.send(currentAuthToken);
    }
  });

  database.ref(".info/serverTimeOffset").on("value", (snapshot) => {
    app.ports.serverTimeOffsetChanged.send(snapshot.val() ?? 0);
  });

  const GAMES_PATH = "games";
  const PRESENCE_PATH = "presence";
  const apiUrl =
    process.env.NODE_ENV === "development"
      ? "http://localhost:5001/themashagame-990a8/us-central1"
      : "";

  const connectionId = crypto.randomUUID();

  app.ports.subscribeToGame.subscribe(({ gameId, userId }) => {
    database.ref(`${GAMES_PATH}/${gameId}`).on("value", (data) => {
      if (!data.exists()) {
        return;
      }
      app.ports.gameChanged.send({ ...data.val(), id: data.key });
    });

    database.ref(`${PRESENCE_PATH}/${gameId}`).on("value", (snapshot) => {
      const presence = snapshot.val() ?? {};
      const onlinePlayerIds = Object.entries(presence)
        .filter(([, leases]) => leases && Object.keys(leases).length > 0)
        .map(([playerId]) => playerId);
      app.ports.presenceChanged.send(onlinePlayerIds);
    });

    if (!userId) {
      return;
    }
    managePresence({ gameId, userId, connectionId });
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

  const managePresence = ({ gameId, userId, connectionId }) => {
    const leaseRef = database.ref(
      `${PRESENCE_PATH}/${gameId}/${userId}/${connectionId}`
    );

    database.ref(".info/connected").on("value", (snapshot) => {
      if (snapshot.val() !== true) {
        return;
      }

      leaseRef.onDisconnect().remove().then(() => leaseRef.set(true));
    });
  };
};

auth
  .signInAnonymously()
  .then(({ user }) => user.getIdToken())
  .then(initializeElm)
  .catch((error) => {
    console.error("Unable to authenticate player", error);
  });

// If you want your app to work offline and load faster, you can change
// unregister() to register() below. Note this comes with some pitfalls.
// Learn more about service workers: https://bit.ly/CRA-PWA
serviceWorker.unregister();
