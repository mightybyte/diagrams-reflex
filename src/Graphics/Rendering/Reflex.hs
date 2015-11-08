{-# LANGUAGE CPP               #-}
{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE ViewPatterns      #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.Reflex
-- Copyright   :  (c) 2015 diagrams-reflex team (see LICENSE)
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  diagrams-discuss@googlegroups.com
--
-- Lower level tools for creating SVGs.
--
-----------------------------------------------------------------------------

module Graphics.Rendering.Reflex
    ( RenderM
    , Element(..)
    , Attrs
    -- , AttributeValue
    -- , svgHeader
    , renderPath
    -- , renderClip
    -- , renderText
    -- , renderDImage
    -- , renderDImageEmb
    , renderStyles
    , renderMiterLimit
    -- , renderFillTextureDefs
    -- , renderFillTexture
    -- , renderLineTextureDefs
    -- , renderLineTexture
    -- , dataUri
    , getNumAttr
    ) where

-- from base
import           Data.List                   (intercalate)
#if __GLASGOW_HASKELL__ < 710
import           Data.Foldable               (foldMap)
#endif

import           Data.Monoid

-- from mtl
import Control.Monad.Reader

-- from diagrams-lib
import           Diagrams.Prelude            hiding (Attribute, Render, with,
                                              (<>))
import           Diagrams.TwoD.Path          (getFillRule)
import           Diagrams.TwoD.Text

-- from containers
import Data.Map (Map, singleton)

-- from base64-bytestring, bytestring
-- import qualified Data.ByteString.Base64.Lazy as BS64
-- import qualified Data.ByteString.Lazy.Char8  as BS8

data Element = Element
               String -- ^ SVG element name
               (Map String String) -- ^ Attributes
               [Element] -- ^ Children

type RenderM = Reader (Style V2 Double) [Element]

instance Monoid RenderM where
  mempty = return []
  mappend r1 r2 = mappend <$> r1 <*> r2

type AttributeValue = String

type Attrs = Map String String

getNumAttr :: AttributeClass (a Double) => (a Double -> t) -> Style v Double -> Maybe t
getNumAttr f = (f <$>) . getAttr

renderPath :: Path V2 Double -> RenderM
renderPath trs = if makePath == ""
                 then return []
                 else return $ [ Element "path" (singleton "d" makePath) [] ]
  where
    makePath = foldMap renderTrail (op Path trs)

renderTrail :: Located (Trail V2 Double) -> AttributeValue
renderTrail (viewLoc -> (P (V2 x y), t)) =
  concat [ "M " , show x, ",",  show y, " " ]
  <> withTrail renderLine renderLoop t
  where
    renderLine = foldMap renderSeg . lineSegments
    renderLoop lp =
      case loopSegments lp of
        -- let z handle the last segment if it is linear
        (segs, Linear _) -> foldMap renderSeg segs

        -- otherwise we have to emit it explicitly
        _ -> foldMap renderSeg (lineSegments . cutLoop $ lp)
      <> "Z"

renderSeg :: Segment Closed V2 Double -> AttributeValue
renderSeg (Linear (OffsetClosed (V2 x 0))) = concat [ "h ", show x, " "]
renderSeg (Linear (OffsetClosed (V2 0 y))) = concat [ "v ", show y, " " ]
renderSeg (Linear (OffsetClosed (V2 x y))) = concat [ "l ", show x, ",", show y, " "]
renderSeg (Cubic  (V2 x0 y0) (V2 x1 y1) (OffsetClosed (V2 x2 y2))) =
  concat [ " c ", show x0, ",", show y0, " ", show x1, ",", show y1
         , " ", show x2, " ", show y2]

renderStyles :: Int -> Int -> Style v Double -> Attrs
renderStyles _fillId _lineId s = foldMap ($ s) $
  -- [ renderLineTexture lineId
  -- , renderFillTexture fillId
  [ renderLineWidth
  , renderLineCap
  , renderLineJoin
  , renderFillRule
  , renderDashing
  , renderOpacity
  , renderFontSize
  , renderFontSlant
  , renderFontWeight
  , renderFontFamily
  -- , renderSvgId
  -- , renderSvgClass
  , renderMiterLimit ]

renderMiterLimit :: Style v Double -> Attrs
renderMiterLimit s = renderAttr "stroke-miterlimit" miterLimit
 where miterLimit = getLineMiterLimit <$> getAttr s

renderOpacity :: Style v Double -> Attrs
renderOpacity s = renderAttr "opacity" o
 where o = getOpacity <$> getAttr s

renderFillRule :: Style v Double -> Attrs
renderFillRule s = renderTextAttr "fill-rule" fr
  where fr = (fillRuleToText . getFillRule) <$> getAttr s
        fillRuleToText :: FillRule -> AttributeValue
        fillRuleToText Winding = "nonzero"
        fillRuleToText EvenOdd = "evenodd"

renderLineWidth :: Style v Double -> Attrs
renderLineWidth s = renderAttr "stroke-width" lWidth
  where lWidth = getNumAttr getLineWidth s

renderLineCap :: Style v Double -> Attrs
renderLineCap s = renderTextAttr "stroke-linecap" lCap
  where lCap = (lineCapToText . getLineCap) <$> getAttr s
        lineCapToText :: LineCap -> AttributeValue
        lineCapToText LineCapButt   = "butt"
        lineCapToText LineCapRound  = "round"
        lineCapToText LineCapSquare = "square"

renderLineJoin :: Style v Double -> Attrs
renderLineJoin s = renderTextAttr "stroke-linejoin" lj
  where lj = (lineJoinToText . getLineJoin) <$> getAttr s
        lineJoinToText :: LineJoin -> AttributeValue
        lineJoinToText LineJoinMiter = "miter"
        lineJoinToText LineJoinRound = "round"
        lineJoinToText LineJoinBevel = "bevel"

renderDashing :: Style v Double -> Attrs
renderDashing s = renderTextAttr "stroke-dasharray" arr <>
                  renderAttr "stroke-dashoffset" dOffset
 where
  getDasharray  (Dashing a _) = a
  getDashoffset (Dashing _ o) = o
  dashArrayToStr              = intercalate "," . map show
  -- Ignore dashing if dashing array is empty
  checkEmpty (Just (Dashing [] _)) = Nothing
  checkEmpty other                 = other
  dashing'                    = checkEmpty $ getNumAttr getDashing s
  arr                         = (dashArrayToStr . getDasharray) <$> dashing'
  dOffset                     = getDashoffset <$> dashing'

renderFontSize :: Style v Double -> Attrs
renderFontSize s = renderTextAttr "font-size" fs
 where
  fs = getNumAttr ((++ "px") . show . getFontSize) s

renderFontSlant :: Style v Double -> Attrs
renderFontSlant s = renderTextAttr "font-style" fs
 where
  fs = (fontSlantAttr . getFontSlant) <$> getAttr s
  fontSlantAttr :: FontSlant -> AttributeValue
  fontSlantAttr FontSlantItalic  = "italic"
  fontSlantAttr FontSlantOblique = "oblique"
  fontSlantAttr FontSlantNormal  = "normal"

renderFontWeight :: Style v Double -> Attrs
renderFontWeight s = renderTextAttr "font-weight" fw
 where
  fw = (fontWeightAttr . getFontWeight) <$> getAttr s
  fontWeightAttr :: FontWeight -> AttributeValue
  fontWeightAttr FontWeightNormal = "normal"
  fontWeightAttr FontWeightBold   = "bold"

renderFontFamily :: Style v Double -> Attrs
renderFontFamily s = renderTextAttr  "font-family" ff
 where
  ff = (getFont) <$> getAttr s

-- | Render a style attribute if available, empty otherwise.
renderAttr :: Show s => String -> Maybe s -> Attrs
renderAttr attrName valM = maybe mempty (\v -> singleton attrName $ show v) valM

renderTextAttr :: String -> Maybe AttributeValue -> Attrs
renderTextAttr attrName valM = maybe mempty (\v -> singleton attrName v) valM