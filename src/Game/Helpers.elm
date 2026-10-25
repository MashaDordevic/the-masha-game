module Game.Helpers exposing (optionalField, optionalMaybeField)

import Json.Decode exposing (Decoder)


optionalField : String -> Decoder a -> a -> Decoder a
optionalField name decoder fallback =
    Json.Decode.keyValuePairs Json.Decode.value
        |> Json.Decode.andThen
            (\fields ->
                if List.any (Tuple.first >> (==) name) fields then
                    Json.Decode.field name decoder

                else
                    Json.Decode.succeed fallback
            )


optionalMaybeField : String -> Decoder a -> Decoder (Maybe a)
optionalMaybeField name decoder =
    Json.Decode.oneOf
        [ Json.Decode.field name (Json.Decode.nullable decoder)
        , Json.Decode.succeed Nothing
        ]
