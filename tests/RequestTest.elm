module RequestTest exposing (suite)

import Expect
import Request
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Request lifecycle"
        [ test "starts an idle request" <|
            \_ ->
                Request.begin Request.idle
                    |> Maybe.map Request.isLoading
                    |> Expect.equal (Just True)
        , test "rejects a duplicate request while loading" <|
            \_ ->
                Request.begin Request.loading
                    |> Expect.equal Nothing
        , test "allows retry after a failure" <|
            \_ ->
                Request.idle
                    |> Request.fail "failed"
                    |> Request.begin
                    |> Maybe.map Request.isLoading
                    |> Expect.equal (Just True)
        , test "retains the failure for the view" <|
            \_ ->
                Request.idle
                    |> Request.fail "failed"
                    |> Request.error
                    |> Expect.equal (Just "failed")
        , test "clears request state after success" <|
            \_ ->
                Request.loading
                    |> Request.succeed
                    |> Request.isLoading
                    |> Expect.equal False
        ]
