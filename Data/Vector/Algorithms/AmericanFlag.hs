{-# LANGUAGE FlexibleContexts, ScopedTypeVariables #-}

-- ---------------------------------------------------------------------------
-- |
-- Module      : Data.Vector.Algorithms.AmericanFlag
-- Copyright   : (c) 2011 Dan Doel
-- Maintainer  : Dan Doel <dan.doel@gmail.com>
-- Stability   : Experimental
-- Portability : Non-portable ()
--
-- This module implements American flag sort: an in-place, unstable, bucket
-- sort. Also in contrast to radix sort, the values are inspected in a big
-- endian order, and buckets are sorted via recursive splitting. This,
-- however, makes it sensible for sorting strings in lexicographic order
-- (provided indexing is fast).

module Data.Vector.Algorithms.AmericanFlag ( sort
                                           , sortBy
                                           ) where

import Prelude hiding (read, length)

import Control.Monad
import Control.Monad.Primitive

import Data.Word
import Data.Int
import Data.Bits

import Data.Vector.Generic.Mutable
import qualified Data.Vector.Primitive.Mutable as PV

import qualified Data.Vector.Unboxed.Mutable as U

import Data.Vector.Algorithms.Common

import qualified Data.Vector.Algorithms.Insertion as I

class Lexicographic e where
  terminate :: e -> Int -> Bool
  size      :: e -> Int
  index     :: Int -> e -> Int

instance Lexicographic Word8 where
  terminate _ n = n > 0
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index _ n = fromIntegral n
  {-# INLINE index #-}

instance Lexicographic Word16 where
  terminate _ n = n > 1
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = fromIntegral $ (n `shiftR`  8) .&. 255
  index 1 n = fromIntegral $ n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

instance Lexicographic Word32 where
  terminate _ n = n > 3
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = fromIntegral $ (n `shiftR` 24) .&. 255
  index 1 n = fromIntegral $ (n `shiftR` 16) .&. 255
  index 2 n = fromIntegral $ (n `shiftR`  8) .&. 255
  index 3 n = fromIntegral $ n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

instance Lexicographic Word64 where
  terminate _ n = n > 7
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = fromIntegral $ (n `shiftR` 56) .&. 255
  index 1 n = fromIntegral $ (n `shiftR` 48) .&. 255
  index 2 n = fromIntegral $ (n `shiftR` 40) .&. 255
  index 3 n = fromIntegral $ (n `shiftR` 32) .&. 255
  index 4 n = fromIntegral $ (n `shiftR` 24) .&. 255
  index 5 n = fromIntegral $ (n `shiftR` 16) .&. 255
  index 6 n = fromIntegral $ (n `shiftR`  8) .&. 255
  index 7 n = fromIntegral $ n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

instance Lexicographic Word where
  terminate _ n = n > 7
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = fromIntegral $ (n `shiftR` 56) .&. 255
  index 1 n = fromIntegral $ (n `shiftR` 48) .&. 255
  index 2 n = fromIntegral $ (n `shiftR` 40) .&. 255
  index 3 n = fromIntegral $ (n `shiftR` 32) .&. 255
  index 4 n = fromIntegral $ (n `shiftR` 24) .&. 255
  index 5 n = fromIntegral $ (n `shiftR` 16) .&. 255
  index 6 n = fromIntegral $ (n `shiftR`  8) .&. 255
  index 7 n = fromIntegral $ n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

instance Lexicographic Int8 where
  terminate _ n = n > 0
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index _ n = 255 .&. fromIntegral n `xor` 128

instance Lexicographic Int16 where
  terminate _ n = n > 1
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = fromIntegral $ ((n `xor` minBound) `shiftR` 8) .&. 255
  index 1 n = fromIntegral $ n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

instance Lexicographic Int32 where
  terminate _ n = n > 3
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = fromIntegral $ ((n `xor` minBound) `shiftR` 24) .&. 255
  index 1 n = fromIntegral $ (n `shiftR` 16) .&. 255
  index 2 n = fromIntegral $ (n `shiftR`  8) .&. 255
  index 3 n = fromIntegral $ n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

instance Lexicographic Int64 where
  terminate _ n = n > 7
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = fromIntegral $ ((n `xor` minBound) `shiftR` 56) .&. 255
  index 1 n = fromIntegral $ (n `shiftR` 48) .&. 255
  index 2 n = fromIntegral $ (n `shiftR` 40) .&. 255
  index 3 n = fromIntegral $ (n `shiftR` 32) .&. 255
  index 4 n = fromIntegral $ (n `shiftR` 24) .&. 255
  index 5 n = fromIntegral $ (n `shiftR` 16) .&. 255
  index 6 n = fromIntegral $ (n `shiftR`  8) .&. 255
  index 7 n = fromIntegral $ n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

instance Lexicographic Int where
  terminate _ n = n > 7
  {-# INLINE terminate #-}
  size _ = 256
  {-# INLINE size #-}
  index 0 n = ((n `xor` minBound) `shiftR` 56) .&. 255
  index 1 n = (n `shiftR` 48) .&. 255
  index 2 n = (n `shiftR` 40) .&. 255
  index 3 n = (n `shiftR` 32) .&. 255
  index 4 n = (n `shiftR` 24) .&. 255
  index 5 n = (n `shiftR` 16) .&. 255
  index 6 n = (n `shiftR`  8) .&. 255
  index 7 n = n .&. 255
  index _ _ = 0
  {-# INLINE index #-}

sort :: forall e m v. (PrimMonad m, MVector v e, Lexicographic e, Ord e)
     => v (PrimState m) e -> m ()
sort v = sortBy compare terminate (size e) index v
 where e :: e
       e = undefined
{-# INLINE sort #-}

sortBy :: (PrimMonad m, MVector v e)
       => Comparison e
       -> (e -> Int -> Bool) -- a stopping predicate
       -> Int                -- size of auxiliary arrays
       -> (Int -> e -> Int)  -- big-endian radix
       -> v (PrimState m) e  -- the array to be sorted
       -> m ()
sortBy cmp stop buckets radix v = do count <- new buckets
                                     pile <- new buckets
                                     countLoop (radix 0) v count
                                     flagLoop cmp stop radix count pile v
{-# INLINE sortBy #-}

flagLoop :: (PrimMonad m, MVector v e)
         => Comparison e
         -> (e -> Int -> Bool)           -- number of passes
         -> (Int -> e -> Int)            -- radix function
         -> PV.MVector (PrimState m) Int -- auxiliary count array
         -> PV.MVector (PrimState m) Int -- auxiliary pile array
         -> v (PrimState m) e            -- source array
         -> m ()
flagLoop cmp stop radix count pile v = go 0 v
 where

 go pass v = do e <- read v 0
                unless (stop e $ pass - 1) $ go' pass v

 go' pass v
   | len < threshold = I.sortByBounds cmp v 0 len
   | otherwise       = do accumulate count pile
                          permute (radix pass) count pile v
                          recurse 0
  where
  len = length v
  ppass = pass + 1

  recurse i
    | i < len   = do j <- countStripe (radix ppass) (radix pass) count v i
                     go ppass (slice i (j - i) v)
                     recurse j
    | otherwise = return ()
{-# INLINE flagLoop #-}

accumulate :: (PrimMonad m)
           => PV.MVector (PrimState m) Int
           -> PV.MVector (PrimState m) Int
           -> m ()
accumulate count pile = loop 0 0
 where
 len = length count

 loop i acc
   | i < len = do ci <- read count i
                  let acc' = acc + ci
                  write pile i acc
                  write count i acc'
                  loop (i+1) acc'
   | otherwise    = return ()
{-# INLINE accumulate #-}

permute :: (PrimMonad m, MVector v e)
        => (e -> Int)                       -- radix function
        -> PV.MVector (PrimState m) Int     -- count array
        -> PV.MVector (PrimState m) Int     -- pile array
        -> v (PrimState m) e                -- source array
        -> m ()
permute rdx count pile v = go 0
 where
 len = length v

 go i
   | i < len   = do e <- read v i
                    let r = rdx e
                    p <- read pile r
                    m <- if r > 0
                            then read count (r-1)
                            else return 0
                    case () of
                      -- if the current element is already in the right pile,
                      -- go to the end of the pile
                      _ | m <= i && i < p  -> go p
                      -- if the current element happens to be in the right
                      -- pile, bump the pile counter and go to the next element
                        | i == p           -> write pile r (p+1) >> go (i+1)
                      -- otherwise follow the chain
                        | otherwise        -> follow i e p >> go (i+1)
   | otherwise = return ()
 
 follow i e j = do en <- read v j
                   let r = rdx en
                   p <- inc pile r
                   if p == j
                      -- if the target happens to be in the right pile, don't move it.
                      then follow i e (j+1)
                      else write v j e >> if i == p
                                             then write v i en
                                             else follow i en p
{-# INLINE permute #-}

countStripe :: (PrimMonad m, MVector v e)
            => (e -> Int)                   -- radix function
            -> (e -> Int)                   -- stripe function
            -> PV.MVector (PrimState m) Int -- count array
            -> v (PrimState m) e            -- source array
            -> Int                          -- starting position
            -> m Int                        -- end of stripe: [lo,hi)
countStripe rdx str count v lo = do set count 0
                                    e <- read v lo
                                    go (str e) e (lo+1)
 where
 len = length v

 go s e i = inc count (rdx e) >>
            if i < len
               then do en <- read v i
                       if str en == s
                          then go s en (i+1)
                          else return i
                else return len
{-# INLINE countStripe #-}

threshold :: Int
threshold = 25

