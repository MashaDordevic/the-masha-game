module RequestTest exposing (suite)

import Expect
import Request
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Request lifecycle"
        [ test "starts an idle request" <|
            \_ ->
                Request.begin 1 Request.idle
                    |> Maybe.map Request.isLoading
                    |> Expect.equal (Just True)
        , test "rejects a duplicate request while loading" <|
            \_ ->
                Request.begin 2 (Request.loading 1)
                    |> Expect.equal Nothing
        , test "allows retry after a failure" <|
            \_ ->
                Request.loading 1
                    |> Request.fail 1 "failed"
                    |> Request.begin 2
                    |> Maybe.map Request.isLoading
                    |> Expect.equal (Just True)
        , test "retains the failure for the view" <|
            \_ ->
                Request.loading 1
                    |> Request.fail 1 "failed"
                    |> Request.error
                    |> Expect.equal (Just "failed")
        , test "ignores a stale failure" <|
            \_ ->
                Request.loading 2
                    |> Request.fail 1 "failed"
                    |> Expect.all
                        [ Request.isLoading >> Expect.equal True
                        , Request.error >> Expect.equal Nothing
                        ]
        , test "correlates active requests by id" <|
            \_ ->
                Request.loading 2
                    |> Expect.all
                        [ Request.isActive 2 >> Expect.equal True
                        , Request.isActive 1 >> Expect.equal False
                        ]
        , test "correlates a request with its resource" <|
            \_ ->
                Request.loading ( 3, "game-a" )
                    |> Expect.all
                        [ Request.isActive ( 3, "game-a" ) >> Expect.equal True
                        , Request.isActive ( 3, "game-b" ) >> Expect.equal False
                        ]
        ]
