module NameInputTest exposing (suite)

import Html.Attributes exposing (for, id)
import Request
import State exposing (Msg(..))
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector exposing (attribute, tag, text)
import Views.NameInput exposing (gameLookupView, nameInputView)


suite : Test
suite =
    describe "Name input views"
        [ test "associates a programmatic label with the nickname input" <|
            \_ ->
                nameInputView "" "Joining…" Request.idle JoinGame
                    |> Query.fromHtml
                    |> Query.find [ tag "label", attribute (for "nickname") ]
                    |> Query.has [ text "Nickname" ]
        , test "shows an inline lookup error with recovery actions" <|
            \_ ->
                Request.loading 1
                    |> Request.fail 1 "Could not find that game."
                    |> gameLookupView
                    |> Query.fromHtml
                    |> Query.has
                        [ text "Could not find that game."
                        , text "Try again"
                        , text "Back"
                        ]
        , test "gives the nickname input the label target id" <|
            \_ ->
                nameInputView "" "Creating…" Request.idle AddGame
                    |> Query.fromHtml
                    |> Query.find [ tag "input" ]
                    |> Query.has [ attribute (id "nickname") ]
        ]
