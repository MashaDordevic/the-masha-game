module Request exposing (State, begin, error, fail, idle, isLoading, loading, succeed)


type State error
    = Idle
    | Loading
    | Failed error


idle : State error
idle =
    Idle


loading : State error
loading =
    Loading


begin : State error -> Maybe (State error)
begin state =
    case state of
        Loading ->
            Nothing

        _ ->
            Just Loading


succeed : State error -> State error
succeed _ =
    Idle


fail : error -> State error -> State error
fail requestError _ =
    Failed requestError


isLoading : State error -> Bool
isLoading state =
    case state of
        Loading ->
            True

        _ ->
            False


error : State error -> Maybe error
error state =
    case state of
        Failed requestError ->
            Just requestError

        _ ->
            Nothing
