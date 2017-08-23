# One True Path 

The aim is to create one package that makes working with SVG paths nice and convenient.  
Eventually, this package should replace (part of) the current separate implementations of SVG paths in existing packages.

*I'll refer to the package here as `OneTruePath`, but we might want to pick a more serious name later.*

## Core Concepts 

* **Path:** A list of subpaths
* **SubPath:** A move command followed by a list of draw commands
* **Command:** A lowlevel instruction (move the cursor, draw a straight line to a point)

### Composition

Lines can be composed in two "obvious" ways: concatenation and layering. 

concatenation happens on the subpath level, using the functions

* `connect:` draws a straight line connecting two subpaths (end to start)
* `continue:` make the start and end point of two subpaths coincide 
* `continueSmooth:` make the start and end point of two subpaths coincide, and rotate to make the transition smooth.

layering is done with a list. SVG draws paths from left to right, so the final subpath in a path will be on top.


### Using LowLevel 

The module has that name for a reason. Unless you are making your own primitives, there is probably a better way. 
If there isn't but you think there should be, please open an issue.

## What about styling

That's not part of this package, but I'm looking into it. The julia [Compose.jl](https://github.com/GiovineItalia/Compose.jl) library has some interesting ideas. 
