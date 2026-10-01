module Request exposing (State, begin, error, fail, idle, isActive, isLoading, loading)


type State requestId error
    = Idle
    | Loading requestId
    | Failed error


idle : State requestId error
idle =
    Idle


loading : requestId -> State requestId error
loading requestId =
    Loading requestId


begin : requestId -> State requestId error -> Maybe (State requestId error)
begin requestId state =
    case state of
        Loading _ ->
            Nothing

        _ ->
            Just (Loading requestId)


isActive : requestId -> State requestId error -> Bool
isActive requestId state =
    case state of
        Loading activeRequestId ->
            activeRequestId == requestId

        _ ->
            False


fail : requestId -> error -> State requestId error -> State requestId error
fail requestId requestError state =
    if isActive requestId state then
        Failed requestError

    else
        state


isLoading : State requestId error -> Bool
isLoading state =
    case state of
        Loading _ ->
            True

        _ ->
            False


error : State requestId error -> Maybe error
error state =
    case state of
        Failed requestError ->
            Just requestError

        _ ->
            Nothing
