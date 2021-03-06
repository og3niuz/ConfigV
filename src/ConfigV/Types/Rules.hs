{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass#-}
{-# LANGUAGE MultiParamTypeClasses #-} 
{-# LANGUAGE AllowAmbiguousTypes #-} 
{-# LANGUAGE MultiWayIf #-} 
{-# LANGUAGE RecordWildCards #-} 

module ConfigV.Types.Rules 
  ( module ConfigV.Types.Rules
  , module ConfigV.Types.SMTRules 
  ) where

import ConfigV.Types.Common
import ConfigV.Types.IR
import ConfigV.Types.Errors
import ConfigV.Types.Countable
import ConfigV.Types.SMTRules
import ConfigV.Types.Locatable

import Prelude hiding (Ordering)
import           Data.Aeson
import           GHC.Generics     (Generic)

import Control.Monad.Reader
import ConfigV.Settings.Config

--TODO Strict or Lazy maps?
import qualified Data.Map.Strict as M

import Control.DeepSeq

-- | every instance of Learnable is a template of rules we can learn
--   instance provided in the Learners dir
class (Eq a, Show a, Ord a, Countable b) => Learnable a b where
  -- | build a set of rules from a single IR
  --   these rules will have TotalTimes=1
  --   this used to be learn
  buildRelations :: IRConfigFile -> Reader ConfigVConfiguration (RuleDataMap a b)
  -- | once you have all the evidence from indiviual files, merge into one rule using support and confidence
  --   sometimes this can be 'id' if the countable data is isolated (See typeErr)
  merge :: Countable b => [RuleDataMap a b] -> Reader ConfigVConfiguration (RuleDataMap a b)
  -- | given a rule on keywords a, 
  --   check if the first (learned) rule is violated by the second rule from the target verification file
  check :: a -> b -> b -> Maybe b
  -- | How to convert a rule to an error message
  toError :: IRConfigFile -> FilePath -> (a, b) -> Error

-- | A rule is the structure for tracking and merging evidence relations
--   We need to track how much evidence we have for the rule, against the rule, and how often we have seen the rule
type RuleDataMap a b = M.Map a b

emptyRuleMap :: RuleDataMap a b
emptyRuleMap = M.empty

data RuleSet = RuleSet
  { order     :: RuleDataMap Ordering AntiRule
  , intRel    :: RuleDataMap IntRel Formula
  , fineInt   :: RuleDataMap FineGrained Formula
  , smtRules  :: RuleDataMap SMTFormula AntiRule
  , typeErr   :: RuleDataMap TypeErr QType
  } deriving (Eq, Show, Generic, NFData)--, Typeable)

emptyRuleSet  = RuleSet
  { order     = M.empty
  , intRel    = M.empty
  , fineInt   = M.empty
  , smtRules  = M.empty
  , typeErr   = M.empty}

------------
-- The specific types of relations we want to learn
-- go below here
-----------

data Ordering = Ordering (Keyword,Keyword)
  deriving (Eq, Show,Ord,Generic,ToJSON,FromJSON,NFData)
instance Locatable Ordering where
  keys (Ordering  (k1,k2)) = [k1,k2]

data IntRel = IntRel Keyword Keyword
  deriving (Show,Ord,Generic,ToJSON,FromJSON,NFData)
instance Eq IntRel where
  (==) (IntRel k1 k2) (IntRel k1' k2') = 
     (k1==k1' && k2==k2') || 
     (k1==k2' && k2==k1')
{-instance Ord IntRel where
  compare (IntRel k1 k2) (IntRel k1' k2') = if
    | compare (T.append k1 k2) (T.append k2' k1') == EQ -> EQ
    | otherwise -> compare (T.append k1 k2) (T.append k1' k2')-}

instance Locatable IntRel where
  keys (IntRel k1 k2) = [k1,k2]

data FineGrained = FineGrained Keyword Keyword Keyword
  deriving (Eq,Show,Ord,Generic,ToJSON,FromJSON,NFData)

instance Locatable FineGrained where
  keys (FineGrained k1 k2 k3) = [k1,k2,k3]

data TypeErr = TypeErr (Keyword)
  deriving (Eq, Show,Ord,Generic,ToJSON,FromJSON,NFData)
instance Locatable TypeErr where
  keys (TypeErr (k1)) = [k1]



