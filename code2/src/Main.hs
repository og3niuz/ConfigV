{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Data.Aeson
import qualified Data.ByteString.Lazy  as B
import qualified Data.List             as L
import           Data.Maybe
import qualified Data.Text             as T
import qualified Data.Text.IO          as T
import           Data.Time.Clock.POSIX

import           Control.Applicative
import           Control.Monad
import           System.IO
import           System.Environment
import qualified GHC.IO.Encoding       as G

import           Debug.Trace

import           Benchmarks
import           Convert
import           LearningEngine
import           Checker

import qualified Settings
import Types.Rules
import Types.IR
import Types.JSON
import Types.Errors

rules = learnRules learnTarget

main = do
  G.setLocaleEncoding utf8
  G.setFileSystemEncoding utf8
  G.setForeignEncoding utf8  
  vFiles <- mapM T.readFile vFilePaths :: IO [T.Text]
  let vTargets = map (\(f,v) -> (f,v,MySQL)) (zip vFilePaths vFiles) :: [ConfigFile Language]
  unless Settings.uSE_CACHE $ B.writeFile "cachedRules.json" $ encode ((toLists $ learnRules learnTarget):: RuleSetLists)
  cached <- (fromLists. fromJust. decode) <$> B.readFile "cachedRules.json"

  --to check integrity of cache
  --when (rules /= (fromLists. fromJust $ decode c)) (fail  "error in json cache")

  fitness <- runVerify cached vTargets
  return ()


runVerify ::  RuleSet -> [ConfigFile Language] -> IO Int
runVerify rules vTargets  = do
  let errors =  map (verifyOn rules) vTargets
  fitnesses <- 
    if Settings.bENCHMARKS 
    then zipWithM reportBenchmarkPerformance benchmarks errors 
    else mapM reportUserPerformance $ L.sortOn (\(f,es) -> length es) (zip (map (\(x,y,z)->x) vTargets) errors) 
  printSummary errors fitnesses
  return $ sum fitnesses


printSummary :: [ErrorReport] -> [Int] -> IO ()
printSummary ers fitnesses = do
  putStrLn "------------"
  putStrLn $ "Found "++(show $sum fitnesses)++" errors in "++(show $ length $ filter (>0) fitnesses)++"/"++(show $ length fitnesses)++" files."
  let numOfClass x = (show x)++", "++(show $ length $ filter (\e-> errIdent e == x) (concat ers))
  putStrLn "------------"
  putStrLn "Table of results"
  putStrLn "Error Class, Number, Support Threshold, Confidence Threshold"
  putStrLn $ (numOfClass TYPE)++", - , - "
  putStrLn $ numOfClass INTREL++", "++(show (Settings.intRelSupport `percent` length fitnesses))++"%, "++(show ((Settings.intRelSupport -Settings.intRelConfidence) `percent` Settings.intRelSupport))++"%"
  putStrLn $ numOfClass FINEGRAINED++", "++(show (Settings.fineGrainSupport `percent` length fitnesses))++"%, "++(show ((Settings.fineGrainSupport -Settings.fineGrainConfidence) `percent` Settings.fineGrainSupport))++"%"
  putStrLn $ numOfClass MISSING++", "++(show (Settings.keywordCoorSupport `percent` length fitnesses))++"%, "++(show ((Settings.keywordCoorSupport -Settings.keywordCoorConfidence) `percent` Settings.keywordCoorSupport))++"%"
  putStrLn $ numOfClass ORDERING++", "++(show (Settings.orderSupport `percent` length fitnesses))++"%, "++(show ((Settings.orderSupport -Settings.orderConfidence) `percent` Settings.orderSupport))++"%"
  putStrLn $ "Total, "++(show $sum fitnesses)++", -, -"
  putStrLn "------------"
  putStrLn "Histogram of Errors"
  print fitnesses
  
percent :: Int -> Int -> Int
percent x y = floor $ 100 * (fromIntegral x / fromIntegral y)

-- print and how many errs
reportUserPerformance :: (FilePath,ErrorReport) -> IO Int
reportUserPerformance (f,es) = do
  print f
  print es
  return $ length es

 -- | compare the original benchark spec to the generated one
reportBenchmarkPerformance :: ErrorReport -> ErrorReport -> IO Int
reportBenchmarkPerformance spec foundErrs =
  let
    truePos = filter ((==) $ head spec) foundErrs
    passing = (length truePos) > 0
    falsePos = filter ((/=) $ head spec) foundErrs
    -- larger fitness is worse performance over benchmarks
    fitness =
      100 * fromEnum (not passing) --large penalty for not passing
      + length falsePos
  in do
    --startT <- getPOSIXTime --this is the right place to put it because of lazy eval
    putStrLn (getFileName $ head spec)
    putStrLn $ "    Passing: " ++ show passing
    putStrLn $ "    True Positives: "++ show (length truePos)
    putStrLn $ "    False Positives: "++ show (length falsePos)
    when Settings.vERBOSE $ putStrLn $ "Specification :   \n" ++ show spec
    when Settings.vERBOSE $ putStrLn $ "True Errors :    \n" ++ unlines (map show $ take 10 truePos)
    when Settings.vERBOSE $ putStrLn $ "False Positives : \n" ++ unlines (map show $ take 10 falsePos)
    putStrLn ""
    --endT <- liftM2 (-) getPOSIXTime (return startT)
    --print endT
    --hFlush stdout
    return fitness
