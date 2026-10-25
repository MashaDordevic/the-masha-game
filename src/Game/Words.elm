module Game.Words exposing (..)

import Dict exposing (Dict)
import Game.Helpers exposing (optionalField, optionalMaybeField)
import Json.Decode exposing (Decoder, field, map3, string)
import Json.Encode


type alias Word =
    { word : String
    , playerId : String
    , id : String
    }


type alias Words =
    { guessed : List Word
    , current : Maybe Word
    , next : List Word
    }


wordDecoder : Decoder Word
wordDecoder =
    map3 Word
        (field "word" string)
        (field "playerId" string)
        (field "id" string)


wordEncoder : Word -> Json.Encode.Value
wordEncoder word =
    Json.Encode.object
        [ ( "word", Json.Encode.string word.word )
        , ( "playerId", Json.Encode.string word.playerId )
        , ( "id", Json.Encode.string word.id )
        ]


wordsDecoder : Decoder Words
wordsDecoder =
    let
        dictToValueList =
            Json.Decode.dict wordDecoder
                |> Json.Decode.map
                    (Dict.toList >> List.map Tuple.second)
    in
    map3 Words
        (optionalField "guessed" dictToValueList [])
        (optionalMaybeField "current" wordDecoder)
        (optionalField "next" dictToValueList [])


groupByPlayer : Word -> Dict String (List Word) -> Dict String (List Word)
groupByPlayer word wordsDict =
    Dict.update
        word.playerId
        (Maybe.map ((::) word) >> Maybe.withDefault [ word ] >> Just)
        wordsDict


wordsByPlayer : List Word -> Dict String (List Word)
wordsByPlayer =
    List.foldr groupByPlayer Dict.empty


wordToKey : Word -> Int -> String
wordToKey { word, playerId } index =
    let
        formattedIndex =
            ("000" ++ String.fromInt index)
                |> String.right 3
    in
    formattedIndex ++ "-" ++ word ++ "-" ++ playerId


wordWithKey : Int -> Word -> Word
wordWithKey index word =
    { word | id = wordToKey word index }


wordsEncoder : Words -> Json.Encode.Value
wordsEncoder words =
    Json.Encode.object
        [ ( "guessed", dictEncoder words.guessed )
        , ( "current", Maybe.map wordEncoder words.current |> Maybe.withDefault Json.Encode.null )
        , ( "next", dictEncoder words.next )
        ]


dictEncoder : List Word -> Json.Encode.Value
dictEncoder words =
    words
        |> List.map (\word -> ( word.id, wordEncoder word ))
        |> Json.Encode.object
