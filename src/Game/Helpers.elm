module Game.Helpers exposing (optionalNullableField)

import Json.Decode exposing (Decoder)


optionalNullableField : String -> Decoder a -> a -> Decoder a
optionalNullableField name decoder fallback =
    Json.Decode.keyValuePairs Json.Decode.value
        |> Json.Decode.andThen
            (\fields ->
                if List.any (Tuple.first >> (==) name) fields then
                    Json.Decode.field name (Json.Decode.nullable decoder)
                        |> Json.Decode.map (Maybe.withDefault fallback)

                else
                    Json.Decode.succeed fallback
            )
