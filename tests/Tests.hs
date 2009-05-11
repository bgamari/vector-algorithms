{-# LANGUAGE ImpredicativeTypes, Rank2Types, TypeOperators #-}

module Main (main) where

import Properties

import Util

import Test.QuickCheck

import Control.Monad
import Control.Monad.ST

import Data.Int
import Data.Word

import Data.Array.Vector

import Data.Array.Vector.Algorithms.Combinators

import qualified Data.Array.Vector.Algorithms.Insertion as INS
import qualified Data.Array.Vector.Algorithms.Intro     as INT
import qualified Data.Array.Vector.Algorithms.Merge     as M
import qualified Data.Array.Vector.Algorithms.Radix     as R
import qualified Data.Array.Vector.Algorithms.TriHeap   as TH
import qualified Data.Array.Vector.Algorithms.Optimal   as O

type Algo e = forall s. MUArr e s -> ST s ()
type SizeAlgo e = forall s. MUArr e s -> Int -> ST s ()

args = stdArgs
       { maxSuccess = 300
       , maxDiscard = 200
       }

check_Int_sort = forM_ algos $ \(name,algo) ->
  quickCheckWith args (label name . prop_fullsort algo)
 where
 algos :: [(String, Algo Int)]
 algos = [ ("introsort", INT.sort)
         , ("insertion sort", INS.sort)
         , ("merge sort", M.sort)
         , ("tri-heapsort", TH.sort)
         ]

check_Int_partialsort = forM_ algos $ \(name,algo) ->
  quickCheckWith args (label name . prop_partialsort algo)
 where
 algos :: [(String, SizeAlgo Int)]
 algos = [ ("intro-partialsort", INT.partialSort)
         , ("tri-heap partialsort", TH.partialSort)
         ]

check_Int_select = forM_ algos $ \(name,algo) ->
  quickCheckWith args (label name . prop_select algo)
 where
 algos :: [(String, SizeAlgo Int)]
 algos = [ ("intro-select", INT.select)
         , ("tri-heap select", TH.select)
         ]

check_radix_sorts = do
  qc (label "Word8"       . prop_fullsort (R.sort :: Algo Word8))
  qc (label "Word16"      . prop_fullsort (R.sort :: Algo Word16))
  qc (label "Word32"      . prop_fullsort (R.sort :: Algo Word32))
  qc (label "Word64"      . prop_fullsort (R.sort :: Algo Word64))
  qc (label "Word"        . prop_fullsort (R.sort :: Algo Word))
  qc (label "Int8"        . prop_fullsort (R.sort :: Algo Int8))
  qc (label "Int16"       . prop_fullsort (R.sort :: Algo Int16))
  qc (label "Int32"       . prop_fullsort (R.sort :: Algo Int32))
  qc (label "Int64"       . prop_fullsort (R.sort :: Algo Int64))
  qc (label "Int"         . prop_fullsort (R.sort :: Algo Int))
  qc (label "Int :*: Int" . prop_fullsort (R.sort :: Algo (Int :*: Int)))
 where
 qc algo = quickCheckWith args algo

check_schwartzian = do
  quickCheckWith args (prop_schwartzian i2w INS.sortBy)
 where
 i2w :: Int -> Word
 i2w = fromIntegral

check_stable = do quickCheckWith args (label "merge sort" . prop_stable M.sortBy)
                  quickCheckWith args (label "radix sort" . prop_stable_radix R.sortBy)

check_optimal = do qc . label "size 2" $ prop_optimal 2 O.sort2ByOffset
                   qc . label "size 3" $ prop_optimal 3 O.sort3ByOffset
                   qc . label "size 4" $ prop_optimal 4 O.sort4ByOffset
 where
 qc = quickCheck

main = do putStrLn "Int tests:"
          check_Int_sort
          check_Int_partialsort
          check_Int_select
          putStrLn "Radix sort tests:"
          check_radix_sorts
          putStrLn "Schwartzian transform (Int -> Word):"
          check_schwartzian
          putStrLn "Stability:"
          check_stable
          putStrLn "Optimals:"
          check_optimal
