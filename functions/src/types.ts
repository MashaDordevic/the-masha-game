type Word = {
  word: string;
  player: string;
  id: string;
};

type User = {
  id: string;
  name: string;
};

type Player = {
  id: string;
  name: string;
  isOwner: boolean;
  status: string;
};

type Game = {
  id: string;
  defaultTimer: number;
  participants: {
    players: { [key: string]: Player };
  };
  state: {
    round: number;
  };
};
