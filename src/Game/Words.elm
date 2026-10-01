module Game.Words exposing (..)

import Dict exposing (Dict)
import Game.Helpers exposing (optionalNullableField)
import Json.Decode exposing (Decoder, field, map3, string)
import Json.Encode
import List
import Random
import Random.List exposing (shuffle)



type alias Word =
    { word : String
    , player : String
    , id : String
    }


type alias Words =
    { guessed : List Word
    , current : Maybe Word
    , next : List Word
    }


type alias AddWord =
    { gameId : String
    , word : Word
    }


type alias DeleteWord =
    { gameId : String
    , wordId : String
    }


wordDecoder : Decoder Word
wordDecoder =
    map3 Word
        (field "word" string)
        (field "player" string)
        (field "id" string)


wordEncoder : Word -> Json.Encode.Value
wordEncoder word =
    Json.Encode.object
        [ ( "word", Json.Encode.string word.word )
        , ( "player", Json.Encode.string word.player )
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
        (optionalNullableField "guessed" dictToValueList [])
        (optionalNullableField "current" (Json.Decode.map Just wordDecoder) Maybe.Nothing)
        (optionalNullableField "next" dictToValueList [])


groupByPlayer : Word -> Dict String (List Word) -> Dict String (List Word)
groupByPlayer word wordsDict =
    Dict.update
        word.player
        (Maybe.map ((::) word) >> Maybe.withDefault [ word ] >> Just)
        wordsDict


wordsByPlayer : List Word -> Dict String (List Word)
wordsByPlayer =
    List.foldr groupByPlayer Dict.empty


wordToKey : Word -> Int -> String
wordToKey { word, player } index =
    let
        formattedIndex =
            ("000"
                ++ String.fromInt index
            )
                |> String.right 3
    in
    formattedIndex ++ "-" ++ word ++ "-" ++ player


wordWithKey : Int -> Word -> Word
wordWithKey index word =
    { word | id = wordToKey word index }


wordsListEncoder : List Word -> Json.Encode.Value
wordsListEncoder list =
    list
        |> List.indexedMap wordWithKey
        |> List.map (\word -> ( word.id, wordEncoder word ))
        |> Json.Encode.object


wordsEncoder : Words -> Json.Encode.Value
wordsEncoder words =
    Json.Encode.object
        [ ( "guessed", wordsListEncoder words.guessed )
        , ( "current"
          , case words.current of
                Just word ->
                    wordEncoder word

                Nothing ->
                    Json.Encode.null
          )
        , ( "next", wordsListEncoder words.next )
        ]


restartWords : Words -> Words
restartWords words =
    let
        currentWord =
            case words.current of
                Just word ->
                    [ word ]

                Maybe.Nothing ->
                    []
        allWords =
            words.guessed ++ currentWord ++ words.next
        ( shuffledWords, _ ) =
            Random.step (shuffle allWords) (Random.initialSeed 0)
    in
    Words [] Maybe.Nothing shuffledWords


failCurrentWord : Words -> Words
failCurrentWord words =
    let
        newNextWords =
            case words.current of
                Just currentWord ->
                    currentWord :: words.next

                Maybe.Nothing ->
                    words.next

        ( shuffledNextWords, _ ) =
            Random.step (shuffle newNextWords) (Random.initialSeed 0)
    in
    Words words.guessed Maybe.Nothing shuffledNextWords


succeedCurrentWord : Words -> Words
succeedCurrentWord words =
    let
        guessedWords =
            case words.current of
                Just currentWord ->
                    currentWord :: words.guessed

                Nothing ->
                    words.guessed

        newCurrentWord =
            List.head words.next

        ( shuffledNextWords, _ ) =
            Random.step (shuffle (List.drop 1 words.next)) (Random.initialSeed 0)
    in
    Words guessedWords newCurrentWord shuffledNextWords
