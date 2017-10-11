module SubPath
    exposing
        ( SubPath
        , close
        , connect
        , continue
        , continueSmooth
        , element
        , empty
        , fromSegments
        , mapCoordinate
        , mapWithCursorState
        , parse
        , rotate
        , scale
        , subpath
        , toSegments
        , toString
        , translate
        , unwrap
        )

{-|


## Types

@docs SubPath


## Construction

@docs subpath, empty, parse


## Conversion

@docs element, toString, toSegments, fromSegments, parse, unwrap


## Composition

<img style="max-width: 100%;" src="https://rawgit.com/folkertdev/one-true-path-experiment/master/docs/subpath-composition.svg" />

@docs continue , connect, continueSmooth, close


## Mapping

@docs translate, rotate, scale
@docs mapCoordinate, mapWithCursorState

-}

import Deque exposing (Deque)
import List.Extra as List
import LowLevel.Command as Command exposing (CursorState, DrawTo(..), MoveTo(..))
import Matrix4 as Mat4
import Parser
import Path.LowLevel as LowLevel
import Path.LowLevel.Parser as PathParser
import Segment exposing (Segment)
import Svg
import Svg.Attributes
import Vector2 as Vec2 exposing (Vec2)
import Vector3 as Vec3 exposing (Vec3)


fromLowLevel : List LowLevel.SubPath -> List SubPath
fromLowLevel lowlevels =
    case lowlevels of
        [] ->
            []

        first :: _ ->
            -- first moveto is always interpreted absolute
            case first.moveto of
                LowLevel.MoveTo _ target ->
                    let
                        initialCursorState =
                            { start = target, cursor = target, previousControlPoint = Nothing }

                        folder { moveto, drawtos } ( state, accum ) =
                            let
                                ( stateAfterMoveTo, newMoveTo ) =
                                    Command.fromLowLevelMoveTo moveto state

                                ( stateAfterDrawtos, newDrawTos ) =
                                    Command.fromLowLevelDrawTos drawtos stateAfterMoveTo
                            in
                            ( stateAfterDrawtos, SubPath { moveto = newMoveTo, drawtos = Deque.fromList newDrawTos } :: accum )
                    in
                    List.foldl folder ( initialCursorState, [] ) lowlevels
                        |> Tuple.second
                        |> List.reverse


toLowLevel : SubPath -> Maybe LowLevel.SubPath
toLowLevel subpath =
    case subpath of
        Empty ->
            Nothing

        SubPath { moveto, drawtos } ->
            Just { moveto = Command.toLowLevelMoveTo moveto, drawtos = List.map Command.toLowLevelDrawTo (Deque.toList drawtos) }


{-| Type representing a subpath

A subpath is one moveto command followed by an arbitrary number of drawto commands.

-}
type SubPath
    = SubPath { moveto : MoveTo, drawtos : Deque DrawTo }
    | Empty


{-| Construct a subpath
-}
subpath : MoveTo -> List DrawTo -> SubPath
subpath moveto drawtos =
    SubPath { moveto = moveto, drawtos = Deque.fromList drawtos }


{-| An empty subpath
-}
empty : SubPath
empty =
    Empty


{-| deconstruct a subpath into its components
-}
unwrap : SubPath -> Maybe { moveto : MoveTo, drawtos : List DrawTo }
unwrap subpath =
    case subpath of
        Empty ->
            Nothing

        SubPath internal ->
            Just { internal | drawtos = Deque.toList internal.drawtos }


map : ({ moveto : MoveTo, drawtos : Deque DrawTo } -> SubPath) -> SubPath -> SubPath
map f subpath =
    case subpath of
        Empty ->
            Empty

        SubPath data ->
            f data


map2 :
    ({ moveto : MoveTo, drawtos : Deque DrawTo } -> { moveto : MoveTo, drawtos : Deque DrawTo } -> SubPath)
    -> SubPath
    -> SubPath
    -> SubPath
map2 f sub1 sub2 =
    case ( sub1, sub2 ) of
        ( Empty, Empty ) ->
            Empty

        ( Empty, subpath ) ->
            subpath

        ( subpath, Empty ) ->
            subpath

        ( SubPath a, SubPath b ) ->
            f a b


{-| Map over each drawto with the CursorState available.

The CursorState contains the subpath start position and the current cursor position at the
current DrawTo

-}
mapWithCursorState : (CursorState -> DrawTo -> b) -> SubPath -> List b
mapWithCursorState mapDrawTo subpath =
    case subpath of
        Empty ->
            []

        SubPath { moveto, drawtos } ->
            let
                (MoveTo start) =
                    moveto

                folder : DrawTo -> ( CursorState, List b ) -> ( CursorState, List b )
                folder drawto ( cursorState, accum ) =
                    let
                        new =
                            Command.updateCursorState drawto { start = cursorState.start, cursor = cursorState.cursor, previousControlPoint = Nothing }
                    in
                    ( new
                    , mapDrawTo cursorState drawto :: accum
                    )
            in
            Deque.foldl folder ( { start = start, cursor = start, previousControlPoint = Nothing }, [] ) drawtos
                |> Tuple.second
                |> List.reverse


{-| Start the second subpath where the first one ends
-}
continue : SubPath -> SubPath -> SubPath
continue =
    map2
        (\b a ->
            let
                (MoveTo firstPoint) =
                    b.moveto

                finalPoint =
                    finalCursorState a
                        |> .cursor

                distance =
                    Vec2.sub finalPoint firstPoint

                newRight =
                    b.drawtos
                        |> Deque.map (mapCoordinateDrawTo (Vec2.add distance))
            in
            SubPath
                { moveto = a.moveto
                , drawtos = Deque.append a.drawtos newRight
                }
        )


{-| Start the second subpath where the first one ends, and rotate it to continue smoothly
-}
continueSmooth : SubPath -> SubPath -> SubPath
continueSmooth b a =
    case
        ( toSegments a
            |> List.last
        , toSegments b
            |> List.head
        )
    of
        ( Just final, Just first ) ->
            let
                angle =
                    -- angle is negated because the svg coord system has +y facing down
                    Segment.angle final first
                        |> negate
            in
            a
                |> continue (rotate angle b)

        ( _, Nothing ) ->
            a

        ( Nothing, _ ) ->
            b


{-| Join two subpaths, connecting them with a straight line
-}
connect : SubPath -> SubPath -> SubPath
connect =
    map2
        (\b a ->
            let
                (MoveTo secondStart) =
                    b.moveto
            in
            SubPath
                { moveto = a.moveto
                , drawtos =
                    a.drawtos
                        |> Deque.pushBack (Command.lineTo [ secondStart ])
                        |> flip Deque.append b.drawtos
                }
        )


{-| Append a ClosePath at the end of the subpath (if none is present)
-}
close : SubPath -> SubPath
close subpath =
    case subpath of
        Empty ->
            Empty

        SubPath { moveto, drawtos } ->
            case Deque.popBack drawtos of
                ( Just ClosePath, preceding ) ->
                    -- subpath is already closed, return original
                    subpath

                _ ->
                    SubPath { moveto = moveto, drawtos = Deque.pushBack Command.closePath drawtos }


{-| Map over all the 2D coordinates in a subpath
-}
mapCoordinate : (Vec2 Float -> Vec2 Float) -> SubPath -> SubPath
mapCoordinate f =
    map
        (\{ moveto, drawtos } ->
            case moveto of
                MoveTo coordinate ->
                    SubPath
                        { moveto = MoveTo (f coordinate)
                        , drawtos = Deque.map (mapCoordinateDrawTo f) drawtos
                        }
        )


mapCoordinateDrawTo : (Vec2 Float -> Vec2 Float) -> DrawTo -> DrawTo
mapCoordinateDrawTo f drawto =
    case drawto of
        LineTo coordinates ->
            LineTo (List.map f coordinates)

        Horizontal coordinates ->
            coordinates
                |> List.map ((\x -> ( x, 0 )) >> f >> Tuple.first)
                |> Horizontal

        Vertical coordinates ->
            coordinates
                |> List.map ((\y -> ( 0, y )) >> f >> Tuple.second)
                |> Vertical

        CurveTo coordinates ->
            CurveTo (List.map (Vec3.map f) coordinates)

        QuadraticBezierCurveTo coordinates ->
            QuadraticBezierCurveTo (List.map (Vec2.map f) coordinates)

        EllipticalArc arguments ->
            EllipticalArc (List.map (\argument -> { argument | target = f argument.target }) arguments)

        ClosePath ->
            ClosePath


finalCursorState : { moveto : MoveTo, drawtos : Deque DrawTo } -> CursorState
finalCursorState { moveto, drawtos } =
    let
        (MoveTo start) =
            moveto

        initial =
            { start = start, cursor = start, previousControlPoint = Nothing }
    in
    case Deque.popBack drawtos of
        ( Just drawto, _ ) ->
            Command.updateCursorState drawto initial

        _ ->
            initial


{-| Convert a list of segments to a path

It is assumed that for every two adjacent segments in the list, the first segment's end point is the second segment's starting point

-}
fromSegments : List Segment -> SubPath
fromSegments segments =
    case segments of
        [] ->
            Empty

        segment :: rest ->
            subpath (Command.moveTo (Segment.firstPoint segment)) (List.map Segment.toDrawTo segments)


{-| -}
toSegments : SubPath -> List Segment
toSegments subpath =
    case subpath of
        Empty ->
            []

        SubPath { moveto, drawtos } ->
            case moveto of
                MoveTo coordinate ->
                    let
                        cursorState =
                            { start = coordinate, cursor = coordinate }

                        -- fake segment to get the fold going, not part of the final result
                        initial =
                            Segment.LineSegment coordinate coordinate

                        folder drawto ( previousSegment, accum ) =
                            let
                                newSegments =
                                    Segment.toSegment previousSegment drawto

                                finalNewSegment =
                                    Maybe.withDefault previousSegment (List.last newSegments)
                            in
                            ( finalNewSegment, accum ++ newSegments )
                    in
                    List.foldl folder ( initial, [] ) (Deque.toList drawtos)
                        |> Tuple.second


{-| Translate the subpath by a vector
-}
translate : Vec2 Float -> SubPath -> SubPath
translate vec subpath =
    mapCoordinate (Vec2.add vec) subpath


{-| Rotate a subpath around its starting point by an angle (in radians).
-}
rotate : Float -> SubPath -> SubPath
rotate angle subpath =
    case subpath of
        Empty ->
            Empty

        SubPath { moveto, drawtos } ->
            let
                (MoveTo firstPoint) =
                    moveto

                -- attempt to round to "nice" floats for fuzz tests
                cleanFloat v =
                    round (v * 1.0e12)
                        |> toFloat
                        |> (\v -> v * 1.0e-12)

                cleanVec2 ( x, y ) =
                    ( cleanFloat x, cleanFloat y )

                rotate angle point =
                    -- something simpler will lead to NaNs
                    point
                        |> flip Vec3.fromV2 0
                        |> Mat4.transform (Mat4.makeRotate angle ( 0, 0, 1 ))
                        |> (\( x, y, z ) -> ( x, y ))

                transform point =
                    point
                        |> flip Vec2.sub firstPoint
                        |> rotate angle
                        |> cleanVec2
                        |> Vec2.add firstPoint
            in
            SubPath
                { moveto = moveto
                , drawtos = Deque.map (mapCoordinateDrawTo transform) drawtos
                }


{-| Scale the subpath in the x and y direction

For more complex scaling operations, define a transformation matrix and use `mapCoordinate`.

-}
scale : Vec2 Float -> SubPath -> SubPath
scale vec subpath =
    case subpath of
        Empty ->
            Empty

        SubPath { moveto, drawtos } ->
            let
                (MoveTo firstPoint) =
                    moveto

                transform point =
                    point
                        |> flip Vec2.sub firstPoint
                        |> flip Vec3.fromV2 0
                        |> Mat4.transform (Mat4.makeScale (Vec3.fromV2 vec 0))
                        |> (\( x, y, z ) -> ( x, y ))
                        |> Vec2.add firstPoint
            in
            SubPath
                { moveto = moveto
                , drawtos = Deque.map (mapCoordinateDrawTo transform) drawtos
                }


{-| Convert a subpath into SVG path notation
-}
toString : SubPath -> String
toString subpath =
    toLowLevel subpath
        |> Maybe.map (LowLevel.toString << List.singleton)
        |> Maybe.withDefault ""


{-| Parse a single subpath

This parser will fail if there are multiple subpaths, use the parser in `Path` instead if multiple subpaths in your input are possible.

-}
parse : String -> Result Parser.Error (List SubPath)
parse =
    Result.map fromLowLevel << PathParser.parse


{-| Construct an svg path element from a `Path` with the given attributes
-}
element : SubPath -> List (Svg.Attribute msg) -> Svg.Svg msg
element path attributes =
    Svg.path (Svg.Attributes.d (toString path) :: attributes) []
