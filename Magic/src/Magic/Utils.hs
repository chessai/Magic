{-# LANGUAGE TypeOperators #-}

module Magic.Utils (mkCard, emptyObject, countCountersOfType, sortOn, textShow, deleteAtIndex, gor, gand, count) where

import Magic.Types

import Control.Monad.State (State, execState)
import Data.Boolean (Boolean(..), true)
import Data.Label
import Data.List (sortBy)
import Data.Maybe (catMaybes, fromMaybe)
import Data.Monoid (mempty)
import Data.Ord (comparing)
import qualified Data.Set as Set
import Data.Text (Text, pack)


-- | Creates a card by starting with an 'emptyObject', running the State
-- action over it and finally setting its colors based on the resulting
-- object's 'play' ability.
mkCard :: State Object () -> Card
mkCard f = Card (setColors . execState f . emptyObject 0)
  where
    setColors o = case get play o of
      Just ab -> set colors (Set.fromList (catMaybes (fromMaybe [] (manaCost ab)))) o
      Nothing -> o

emptyObject :: Timestamp -> PlayerRef -> Object
emptyObject t rOwner = Object
  { _name = Nothing
  , _colors = mempty
  , _types = mempty
  , _owner = rOwner
  , _controller = rOwner
  , _timestamp = t
  , _counters = mempty

  , _pt = Nothing
  , _allowAttacks = true
  , _allowBlocks = true
  , _loyalty = Nothing

  , _play = Nothing
  , _alternativePlays = []
  , _staticKeywordAbilities = []
  , _layeredEffects = []
  , _activatedAbilities = []
  , _triggeredAbilities = mempty
  , _replacementEffects = []

  , _temporaryEffects = []
  }


countCountersOfType :: CounterType -> Object -> Int
countCountersOfType ty o = length (filter (== ty) (get counters o))

sortOn :: Ord b => (a -> b) -> [a] -> [a]
sortOn = sortBy . comparing

textShow :: Show a => a -> Text
textShow = pack . show

deleteAtIndex :: Int -> [a] -> [a]
deleteAtIndex i xs = ys ++ zs
  where
    (ys, _:zs) = splitAt i xs

gor :: Boolean b => [b] -> b
gor = foldr (||*) false

gand :: Boolean b => [b] -> b
gand = foldr (&&*) true

count :: [a] -> (a -> Bool) -> Int
count xs ok = length (filter ok xs)
