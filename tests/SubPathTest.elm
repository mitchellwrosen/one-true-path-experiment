module SubPathTest exposing (..)

import Test exposing (..)
import Fuzz
import Expect
import Segment exposing (Segment(..))
import Curve
import SubPath
import Vector2 as Vec2
import LowLevel.Command exposing (moveTo, lineTo, quadraticCurveTo)


down =
    Curve.linear [ ( 0, 0 ), ( 0, 100 ) ]


right =
    Curve.linear [ ( 0, 0 ), ( 100, 0 ) ]


up =
    Curve.linear [ ( 0, 0 ), ( 0, -100 ) ]


left =
    Curve.linear [ ( 0, 0 ), ( -100, 0 ) ]


slope =
    Curve.linear [ ( 0, 0 ), ( 100, 100 ) |> Vec2.normalize |> Vec2.scale 100 ]


u =
    down
        |> SubPath.continue right
        |> SubPath.continue up


n =
    up
        |> SubPath.continue right
        |> SubPath.continue down


tests =
    describe "composition tests"
        [ test "unwrap << subpath does not change the order of drawtos" <|
            \_ ->
                let
                    drawtos =
                        [ lineTo [ ( 1, 2 ) ], quadraticCurveTo [ ( ( 1, 2 ), ( 3, 5 ) ) ] ]
                in
                    drawtos
                        |> SubPath.subpath (moveTo ( 0, 0 ))
                        |> SubPath.unwrap
                        |> Maybe.map .drawtos
                        |> Expect.equal (Just drawtos)
        , test "right smooth right produces a straight line" <|
            \_ ->
                right
                    |> SubPath.continueSmooth right
                    |> SubPath.toSegments
                    |> Expect.equal [ Segment.line ( 0, 0 ) ( 100, 0 ), Segment.line ( 100, 0 ) ( 200, 0 ) ]
        , test "right smooth down produces a straight line" <|
            \_ ->
                right
                    |> SubPath.continueSmooth down
                    |> SubPath.toSegments
                    |> Expect.equal [ Segment.line ( 0, 0 ) ( 100, 0 ), Segment.line ( 100, 0 ) ( 200, 0 ) ]
        , test "right smooth up produces a straight line" <|
            \_ ->
                right
                    |> SubPath.continueSmooth up
                    |> SubPath.toSegments
                    |> Expect.equal [ Segment.line ( 0, 0 ) ( 100, 0 ), Segment.line ( 100, 0 ) ( 200, 0 ) ]
        , test "right smooth left produces a straight line" <|
            \_ ->
                right
                    |> SubPath.continueSmooth left
                    |> SubPath.toSegments
                    |> Expect.equal [ Segment.line ( 0, 0 ) ( 100, 0 ), Segment.line ( 100, 0 ) ( 200, 0 ) ]
        , test "right smooth slope produces a straight line" <|
            \_ ->
                right
                    |> SubPath.continueSmooth slope
                    |> SubPath.toSegments
                    |> Expect.equal [ Segment.line ( 0, 0 ) ( 100, 0 ), Segment.line ( 100, 0 ) ( 200, 0 ) ]
        , test "toSegments returns segments in the correct order" <|
            \_ ->
                SubPath.subpath (moveTo ( 0, 0 )) [ lineTo [ ( 0, 100 ), ( 100, 100 ), ( 100, 0 ) ] ]
                    |> SubPath.toSegments
                    |> Expect.equal [ Segment.line ( 0, 0 ) ( 0, 100 ), Segment.line ( 0, 100 ) ( 100, 100 ), Segment.line ( 100, 100 ) ( 100, 0 ) ]
        , test "continue produces segments in the correct order" <|
            \_ ->
                (right |> SubPath.continue down)
                    |> SubPath.toSegments
                    |> Expect.equal [ Segment.line ( 0, 0 ) ( 100, 0 ), Segment.line ( 100, 0 ) ( 100, 100 ) ]
        , test "connect produces segments in the correct order" <|
            \_ ->
                Curve.linear [ ( 0, 0 ), ( 100, 0 ) ]
                    |> SubPath.connect (Curve.linear [ ( 200, 0 ), ( 300, 0 ) ])
                    |> SubPath.toSegments
                    |> Expect.equal
                        [ Segment.line ( 0, 0 ) ( 100, 0 )
                        , Segment.line ( 100, 0 ) ( 200, 0 )
                        , Segment.line ( 200, 0 ) ( 300, 0 )
                        ]
        ]


arcLengthParameterization =
    describe "arc length parameterization tests" <|
        let
            tolerance =
                0.0001

            straightLine =
                Curve.linear [ ( 0, 0 ), ( 20, 0 ), ( 40, 0 ), ( 100, 0 ) ]
        in
            [ fuzz (Fuzz.intRange 0 100) "point along fuzz" <|
                \t ->
                    let
                        curve =
                            Curve.linear [ ( 0, 0 ), ( 20, 0 ), ( 40, 0 ), ( 42, 0 ), ( 50, 0 ), ( 55, 0 ), ( 98, 0 ), ( 100, 0 ) ]
                                |> SubPath.arcLengthParameterized tolerance
                    in
                        curve
                            |> flip SubPath.pointAlong (toFloat t * SubPath.arcLength curve / 100)
                            |> Maybe.map (round << Tuple.first)
                            |> Expect.equal (Just t)
            , test "1. evenly spaced" <|
                \_ ->
                    Curve.linear [ ( 0, 0 ), ( 100, 0 ) ]
                        |> SubPath.arcLengthParameterized tolerance
                        |> SubPath.evenlySpacedPoints 1
                        |> Expect.equal [ ( 50, 0 ) ]
            , test "2. evenly spaced" <|
                \_ ->
                    Curve.linear [ ( 0, 0 ), ( 100, 0 ) ]
                        |> SubPath.arcLengthParameterized tolerance
                        |> SubPath.evenlySpacedPoints 2
                        |> Expect.equal [ ( 0, 0 ), ( 100, 0 ) ]
            , test "3. evenly spaced" <|
                \_ ->
                    Curve.linear [ ( 0, 0 ), ( 20, 0 ), ( 40, 0 ), ( 100, 0 ) ]
                        |> SubPath.arcLengthParameterized tolerance
                        |> SubPath.evenlySpacedPoints 5
                        |> Expect.equal [ ( 0, 0 ), ( 25, 0 ), ( 50, 0 ), ( 75, 0 ), ( 100, 0 ) ]
            , test "quadratic bezier at t=0 is the starting point" <|
                \_ ->
                    Curve.quadraticBezier ( 0, 100 ) [ ( ( 400, 400 ), ( 800, 100 ) ) ]
                        |> SubPath.arcLengthParameterized tolerance
                        |> flip SubPath.pointAlong 0
                        |> Expect.equal (Just ( 0, 100 ))
            ]
