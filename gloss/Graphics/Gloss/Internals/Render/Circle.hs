{-# LANGUAGE BangPatterns, MagicHash, PatternGuards #-}
{-# OPTIONS_HADDOCK hide #-}

-- | Fast(ish) rendering of circles.
module Graphics.Gloss.Internals.Render.Circle
        ( renderCircle
        , renderArc)
where
import 	Graphics.Gloss.Internals.Render.Common
import  Graphics.Gloss.Geometry.Angle
import	qualified Graphics.Rendering.OpenGL.GL		as GL
import	GHC.Exts


-- | Decide how many line segments to use to render the circle
{-# INLINE circleSteps #-}
circleSteps :: Float -> Int
circleSteps sDiam
        | sDiam < 1     = 1
        | sDiam < 2     = 4
        | sDiam < 10    = 8
        | sDiam < 20    = 16
        | sDiam < 30    = 32
        | otherwise     = 40


-- Circle ---------------------------------------------------------------------
-- | Render a circle with the given thickness
renderCircle :: Float -> Float -> Float -> Float -> Float -> IO ()
renderCircle posX posY scaleFactor radius_ thickness
 	| radius        <- abs radius_
        , radScreen	<- scaleFactor * radius
	, steps		<- circleSteps (2 * radScreen)
	= if thickness == 0 
		then renderCircleLine  posX posY steps radius
		else renderCircleStrip posX posY steps radius thickness


-- | Render a circle as a line.
renderCircleLine :: Float -> Float -> Int -> Float -> IO ()
renderCircleLine (F# posX) (F# posY) steps (F# rad)
 = let  n               = fromIntegral steps
        !(F# tStep)     = (2 * pi) / n
        !(F# tStop)     = (2 * pi)

   in   GL.renderPrimitive GL.LineLoop
         $ renderCircleLine_step posX posY tStep tStop rad 0.0#
{-# INLINE renderCircleLine #-}


-- | Render a circle with a given thickness as a triangle strip
renderCircleStrip :: Float -> Float -> Int -> Float -> Float -> IO ()
renderCircleStrip (F# posX) (F# posY) steps r width
 = let  n               = fromIntegral steps
        !(F# tStep)     = (2 * pi) / n
        !(F# tStop)     = (2 * pi) + (F# tStep) / 2
        !(F# r1)        = r - width / 2
        !(F# r2)        = r + width / 2

   in   GL.renderPrimitive GL.TriangleStrip
         $ renderCircleStrip_step posX posY tStep tStop r1 0.0# r2 
                (tStep `divideFloat#` 2.0#)
{-# INLINE renderCircleStrip #-}


-- Arc ------------------------------------------------------------------------
-- | Render an arc with the given thickness.
renderArc :: Float -> Float -> Float -> Float -> Float -> Float -> Float -> IO ()
renderArc posX posY scaleFactor radius_ a1 a2 thickness
 	| radius        <- abs radius_
        , radScreen	<- scaleFactor * radius
	, steps		<- circleSteps (2 * radScreen)
	= if thickness == 0 
		then renderArcLine posX posY steps radius a1 a2
		else renderArcStrip posX posY steps radius a1 a2 thickness
  

-- | Render an arc as a line.
renderArcLine :: Float -> Float -> Int -> Float -> Float -> Float -> IO ()
renderArcLine (F# posX) (F# posY) steps (F# rad) a1 a2
 = let 	n		= fromIntegral steps
	!(F# tStep)	= (2 * pi) / n
        !(F# tStart)    = degToRad a1
	!(F# tStop)	= degToRad a2 + if a1 >= a2 then 2 * pi else 0

        -- force the line to end at the desired angle
        endVertex       = addPointOnCircle posX posY rad tStop

   in	GL.renderPrimitive GL.LineStrip
   	 $ do   renderCircleLine_step posX posY tStep tStop rad tStart
                endVertex
{-# INLINE renderArcLine #-}


-- | Render an arc with a given thickness as a triangle strip
renderArcStrip :: Float -> Float -> Int -> Float -> Float -> Float -> Float -> IO ()
renderArcStrip (F# posX) (F# posY) steps r a1 a2 width
 = let	n		= fromIntegral steps
 	!(F# tStep)	= (2 * pi) / n
        -- TODO: could extend tStart/tStop to account for non-zero width
        !(F# tStart)    = degToRad a1
	!(F# tStop)	= degToRad a2 + if a1 >= a2 then 2 * pi else 0
	!(F# r1)	= r - width / 2
	!(F# r2)	= r + width / 2
        
        !dt             = tStep `divideFloat#` 2.0#
        
   in	GL.renderPrimitive GL.TriangleStrip
   	 $ do    -- start vector
                 addPointOnCircle posX posY r2 tStart

                 renderCircleStrip_step posX posY tStep tStop r1 tStart r2
                    (tStart `plusFloat#` dt)

                 -- end vectors
                 addPointOnCircle posX posY r1 tStop
                 addPointOnCircle posX posY r2 tStop
{-# INLINE renderArcStrip #-}


-- Step functions -------------------------------------------------------------
renderCircleLine_step
        :: Float# -> Float#
        -> Float# -> Float#
        -> Float# -> Float# 
        -> IO ()

renderCircleLine_step posX posY tStep tStop rad tt
        | tt `geFloat#` tStop
        = return ()
        
        | otherwise
        = do    addPointOnCircle posX posY rad tt
                renderCircleLine_step posX posY tStep tStop rad 
                        (tt `plusFloat#` tStep)
{-# INLINE renderCircleLine_step #-}


renderCircleStrip_step 
	:: Float# -> Float# 
	-> Float# -> Float# 
	-> Float# -> Float#
        -> Float# -> Float# -> IO ()

renderCircleStrip_step posX posY tStep tStop r1 t1 r2 t2
	| t1 `geFloat#` tStop
	= return ()
	
	| otherwise
	= do	addPointOnCircle posX posY r1 t1
                addPointOnCircle posX posY r2 t2
		renderCircleStrip_step posX posY tStep tStop r1 
			(t1 `plusFloat#` tStep) r2 (t2 `plusFloat#` tStep)
{-# INLINE renderCircleStrip_step #-}


addPoint :: Float# -> Float# -> IO ()
addPoint x y =
  GL.vertex $ GL.Vertex2 (gf (F# x)) (gf (F# y))
{-# INLINE addPoint #-}


addPointOnCircle :: Float# -> Float# -> Float# -> Float# -> IO ()
addPointOnCircle posX posY rad tt =
  addPoint
    (posX `plusFloat#` (rad `timesFloat#` (cosFloat# tt)))
    (posY `plusFloat#` (rad `timesFloat#` (sinFloat# tt)))
{-# INLINE addPointOnCircle #-}



{- Unused sector drawing code.
   Sectors are currently drawn as compound Pictures,
   but we might want this if we end up implementing the ThickSector 
   version as well.

-- | Render a sector as a line.
renderSectorLine :: Float -> Float -> Int -> Float -> Float -> Float -> IO ()
renderSectorLine pX@(F# posX) pY@(F# posY) steps (F# rad) a1 a2
 = let  n               = fromIntegral steps
        !(F# tStep)     = (2 * pi) / n
        !(F# tStart)    = degToRad a1
        !(F# tStop)     = degToRad a2 + if a1 >= a2 then 2 * pi else 0

        -- need to set up the edges of the start/end triangles
        startVertex     = GL.vertex $ GL.Vertex2 (gf pX) (gf pY)
        endVertex       = addPointOnCircle posX posY rad tStop

   in   GL.renderPrimitive GL.LineLoop
         $ do   startVertex
                renderCircleLine_step posX posY tStep tStop rad tStart
                endVertex

-- | Render a sector.
renderSector :: Float -> Float -> Float -> Float -> Float -> Float -> IO ()
renderSector posX posY scaleFactor radius a1 a2
        | radScreen     <- scaleFactor * radius
        , steps         <- circleSteps (2 * radScreen)
        = renderSectorLine posX posY steps radius a1 a2
-}

