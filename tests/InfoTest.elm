module InfoTest exposing (suite)

import Test exposing (Test, test)
import Test.Html.Query as Query
import Test.Html.Selector exposing (text)
import Views.Playing.Info exposing (timeLeft)


suite : Test
suite =
    test "renders the deadline-derived countdown in seconds" <|
        \_ ->
            timeLeft 13
                |> Query.fromHtml
                |> Query.has [ text "13", text "seconds" ]
